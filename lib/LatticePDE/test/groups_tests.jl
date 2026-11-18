# F2-06: the shared group layer (LatticeFields.Problems, group.jl). An owned problem steps
# through `GroupRuntime`s (`advance!`, one per field group); `FieldGroups` assigns algorithms
# to fields; an algorithm declares its buffers (`nbuffers`) and keeps a cache (`alg_cache`)
# that `reset!` and its return code (`step_retcode!`) reach.
# F2-07: `lower_group` (the rate form and the group cut), the update pass (`fuse_update`) and
# its byte-identity gate, a clip in B, `dt` required, Cartesian indexing on the host.

@testsetup module LP_groups
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/export_all.jl")
end

@testitem "F2-06: B steps through the group layer" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F2-06: B steps through the group layer" begin
        p = gown(gsys())
        a4, a3 = ExplicitEuler(; substeps = 4), ExplicitEuler(; substeps = 3)
        ig = init(p, a4; dt = 0.01)
        rt = only(ig.runtimes)
        @test rt isa LFP.GroupRuntime && rt.n == ig.substeps == 4 && rt.ends_in === :parity
        @test p.group isa LFP.FieldGroup && p.group.spec.state == p.state && p.group.spec.kind === :rate
        # `advance!` returns the step's code; a healthy run in progress is `Default` (SciML)
        @test LFP.advance!(rt, (0.0, 0)) == ReturnCode.Success && rt.status == ReturnCode.Success
        step!(ig)
        @test ig.retcode == ReturnCode.Default && SciMLBase.check_error(ig) == ReturnCode.Success
        # one algorithm for every field is one group: the same launches, the same states
        s1, s2 = solve(p, a4; dt = 0.01), solve(p, FieldGroups(gce => a4, goe => a4); dt = 0.01)
        @test s2.u == s1.u && substep_counts(s2) == substep_counts(s1)
        s3 = solve(p, FieldGroups(goe => a4; default = a4); dt = 0.01)
        @test s3.u == s1.u
        # step! allocates nothing, one group and two
        @test gwarm(init(p, a4; dt = 0.01, save_everystep = false)) == 0
        @test gwarm(init(p, FieldGroups(gce => a4, goe => a3); dt = 0.01, save_everystep = false)) == 0
    end
end

@testitem "F2-06: FieldGroups: two groups in state order, each ending in slot 1" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F2-06: FieldGroups: two groups in state order, each ending in slot 1" begin
        # c does not read o (ga = 0): the c group steps alone; the o group runs after it and reads
        # the new c from its array (base: no groups in B)
        p = remake(gown(gsys()); p = [ga => 0.0])
        a4, a3 = ExplicitEuler(; substeps = 4), ExplicitEuler(; substeps = 3)
        ig = init(p, FieldGroups(gce => a4, goe => a3); dt = 0.01)
        @test length(ig.runtimes) == 2 && [r.n for r in ig.runtimes] == [4, 3] &&
            all(r -> r.ends_in === :slot1, ig.runtimes)
        # each group's count comes from the bound of its own rows: with c reading o (ga = 0.3) the
        # whole system's rows are coupled, the c group's are not (o is read from its array)
        ic = init(gown(gsys()), FieldGroups(gce => ExplicitEuler(); default = ExplicitEuler(; substeps = 3)); dt = 0.01)
        @test [r.n for r in ic.runtimes] == [3, 3]                    # c: ⌈0.01 · 512 / 1.8⌉ = 3, automatic
        @test occursin("no automatic substeps", gerr(() -> init(gown(gsys()), ExplicitEuler(); dt = 0.01)))   # control
        o0 = copy(ig[goe])
        step!(ig)
        c1, o1 = ig[gce], ig[goe]
        h = 0.01 / 3
        ref = o0
        for _ in 1:3
            ref = ref .+ h .* (-0.2 .* ref .+ 0.1 .* c1)
        end
        @test o1 ≈ ref rtol = 1.0e-12                                   # three substeps with c at its new value
        one = init(p, a4; dt = 0.01)
        step!(one)
        @test c1 ≈ one[gce] rtol = 1.0e-14                              # the c group: four substeps
        @test all(==(1), ig.store.cur[[r.swaps[1] for r in ig.runtimes]])   # odd count: back in slot 1
        @test !(o1 ≈ one[goe])                                        # control: one group steps o in 4, Jacobi
        # refusals: a map with a rate, a field with no algorithm, a name that is no field
        @test occursin("never mixed", gerr(() -> init(p, FieldGroups(gce => a4, goe => ExplicitMap()); dt = 0.01)))
        @test occursin("`go`", gerr(() -> init(p, FieldGroups(gce => a4); dt = 0.01)))
        @test occursin("not a state field", gerr(() -> init(p, FieldGroups(:zz => a4; default = a4); dt = 0.01)))
        @test occursin("one algorithm per field", gerr(() -> FieldGroups(gce => FieldGroups(goe => a4))))
        @test occursin("not a field algorithm", gerr(() -> FieldGroups(gce => 1.0)))
    end
end

@testitem "F2-06: an algorithm's buffers, cache, reset! and return code" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F2-06: an algorithm's buffers, cache, reset! and return code" begin
        p = gown(gsys())
        ig = init(p, GStub(0); dt = 0.01)
        @test length(ig.store.flat) == 3                              # nbuffers = 3: a third buffer
        c = only(ig.runtimes).cache
        @test c isa GStubCache && c.resets == 0
        ig[gce] = fill(1.0, 8, 8)                                     # a state write
        @test c.resets == 1
        reinit!(ig)
        @test c.resets == 2 && ig.iter == 0 && ig[gce] ≈ init(p, GStub(0); dt = 0.01)[gce]
        setp(ig, ga)(ig, 0.5)                                         # a rebind
        @test c.resets == 3
        # a remade problem's integrator starts with a fresh cache
        c2 = only(init(remake(p; p = [gb => 0.1]), GStub(0); dt = 0.01).runtimes).cache
        @test c2 !== c && c2.resets == 0 && c2.steps == 0
        # the stub steps as ExplicitEuler with its count: the third buffer changes nothing
        @test solve(p, GStub(0); dt = 0.01).u[end] == solve(p, ExplicitEuler(; substeps = 3); dt = 0.01).u[end]
        # its failure code stops solve! at that step
        ig = init(p, GStub(3); dt = 0.01)
        sol = solve!(ig)
        @test sol.retcode == ReturnCode.ConvergenceFailure && ig.iter == 3
        @test solve(p, GStub(0); dt = 0.01).retcode == ReturnCode.Success  # control: no failure, the full span
    end
end

@testitem "F2-06: the step-start clamp: a mask that switches on is read by that step's substeps" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F2-06: the step-start clamp: a mask that switches on is read by that step's substeps" begin
        @variables gw(..) gwk(..)::Int32 [input = true]
        we, wk = gw(t, x, y), gwk(t, x, y)
        sys = PDESystem(
            [D(we) ~ laplacian(we)], [gw(0, x, y) ~ 0.0, we ~ masked((t > 0.0015) & (wk == 0), 1.0)],
            [t ∈ Interval(0.0, 0.003), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [we, wk], Num[]; name = :w
        )
        K = ones(Int32, 4, 4)
        K[1, 1] = 0
        p = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64); inputs = [wk => K])
        s = solve(p, ExplicitEuler(; substeps = 1); dt = 0.001, saveat = 0.001)
        @test s[:gw, 3][1, 1] == 0.0 && s[:gw, 3][2, 1] == 0.0       # t = 0.002: the mask was off at each step's start
        # step 3 starts at t = 0.002 > 0.0015: the site is clamped at its start and the substep reads
        # the 1.0 (without the step-start clamp the neighbour stays 0.0 until step 4)
        @test s[:gw, 4][1, 1] == 1.0 && s[:gw, 4][2, 1] > 0.01
    end
end

@testitem "F2-06: the warning set stays bounded over 500 remakes" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F2-06: the warning set stays bounded over 500 remakes" begin
        # the coupled rows of c and o are not bounded: an explicit count warns once per (program,
        # term, cause), never once per value (base: 500 keys, about 120 KB, record (a))
        p = gown(gsys())
        alg = ExplicitEuler(; substeps = 2)
        init(p, alg; dt = 0.01)
        @test any(startswith(LFP._warn_key(p, "")), LFP._SEEN_WARNED)  # this program's key is there
        n0 = length(LFP._SEEN_WARNED)
        for k in 1:500
            init(remake(p; p = [gb => 0.2 + k * 1.0e-4]), alg; dt = 0.01)
        end
        @test length(LFP._SEEN_WARNED) == n0
    end
end

@testitem "F2-07: the update pass equals the symbolic fusion (byte-identity gate)" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F2-07: the update pass equals the symbolic fusion (byte-identity gate)" begin
        @variables gm(..) gd(..)::Bool [input = true] gk(..)::Int32 [input = true]
        gme, gde, gke = gm(t, x, y), gd(t, x, y), gk(t, x, y)
        @parameters gr = -0.5 Dg[1:2] = [0.3, 1.0]
        dom = [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        systems = [
            gsys(),                                                       # coupled, periodic
            PDESystem(
                [D(gme) ~ value_at(Dg, gke) * laplacian(gme) - 0.1gme], [gm(0, x, y) ~ x, gme ~ masked(gke == 2, 1.0)],
                dom, [t, x, y], [gme, gke], [Dg]; name = :m
            ),             # a masked condition, a site multiplier
            PDESystem(
                [D(gme) ~ laplacian(gme)], [gm(0, x, y) ~ x * y, gm(t, 0, y) + gr * Differential(x)(gm(t, 0, y)) ~ 1.0],
                dom, [t, x, y], [gme], [gr]; name = :r
            ),                  # a Robin face
        ]
        discs = [
            LatticeDiscretization(Grid((8, 8)); T = Float64), LatticeDiscretization(Grid((8, 8)); T = Float64),
            LatticeDiscretization(Grid((8, 8)); T = Float64),
        ]
        # an irregular domain (`select(inside, …)` around the update)
        push!(systems, PDESystem([D(gme) ~ laplacian(gme) - gme], [gm(0, x, y) ~ x], dom, [t, x, y], [gme, gde], Num[]; name = :d))
        push!(discs, LatticeDiscretization(Grid((8, 8)); T = Float64, domain = gd))
        for (sys, disc) in zip(systems, discs), lower in (nothing, 0.0), T in (Float64, Float32)
            rate = symbolic_discretize(sys, disc).program
            sym = symbolic_discretize(
                sys, disc; update = (kb, c, r) -> (
                    v = LatticePDE.euler_update(kb, c, r);
                    lower === nothing ? v : max(v, lower)
                )
            ).program
            pass = fuse_update(rate, LFP.update_rule(ExplicitEuler(; lower_bound = lower)))
            @test fingerprint_text(pass; T) == fingerprint_text(sym; T)
            @test fingerprint_text(rate; T) != fingerprint_text(sym; T)      # control: the rate form is not the step
        end
        # the gate inside `discretize` (`LATTICEPDE_CHECK_FUSION=1`: the suites run with it)
        withenv("LATTICEPDE_CHECK_FUSION" => "1") do
            @test gown(gsys()) isa LFP.FieldProblem
        end
    end
end

@testitem "F2-07: a clip in B; a second algorithm fuses once, with no LatticePDE call" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F2-07: a clip in B; a second algorithm fuses once, with no LatticePDE call" begin
        @variables gq(..)
        gqe = gq(t, x, y)
        n = 8
        sys = PDESystem(
            [D(gqe) ~ laplacian(gqe) - 3.0], [gq(0, x, y) ~ x * y, gq(t, 0, y) ~ gq(t, 1, y), gq(t, x, 0) ~ gq(t, x, 1)],
            [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [gqe], Num[]; name = :q
        )
        p = gown(sys; n)
        @test p.options.index === :cartesian                          # the host indexes by coordinates
        alg = ExplicitEuler(; substeps = 4, lower_bound = 0.0)
        s = solve(p, alg; dt = 0.05)
        k = init(p, alg; dt = 0.05).substeps                                     # 4 is a minimum: the bound raises it
        @test k == 15                                                 # ⌈0.05 · 512 / 1.8⌉
        c = s[:gq, 1]
        for _ in 1:4
            c = g_ftcs(c, 1.0, (1 / n, 1 / n), 0.05, k; periodic = true, rate = (c, i, j) -> -3.0, lower = 0.0)
        end
        @test isapprox(s[:gq, end], c; rtol = 1.0e-12) && minimum(c) == 0.0   # clipped (base: `lower` refused in B)
        @test minimum(solve(p, ExplicitEuler(; substeps = 4); dt = 0.05)[:gq, end]) < 0   # control: no clip
        # the clip's program is fused once, in the group (the update pass, no symbolic step)
        @test haskey(p.group.programs, (:euler, 0.0)) && length(p.group.programs) == 2
        init(p, ExplicitEuler(; substeps = 2, lower_bound = 0.0); dt = 0.1)   # another window and count: the same update
        @test length(p.group.programs) == 2
        q = remake(p; u0 = p.u0)
        @test q.group === p.group                                     # a remake shares the group
        pc = gown(sys; n)
        cold = @allocated init(pc, ExplicitEuler(; substeps = 4, lower_bound = 1.0); dt = 0.05)   # fused, planned, emitted
        warm = @allocated init(pc, ExplicitEuler(; substeps = 4, lower_bound = 1.0); dt = 0.05)
        @test warm < cold / 4 && length(pc.group.programs) == 2        # warm: nothing fused, planned or emitted
    end
end

@testitem "F2-07: dt is required; lower_group cuts a group" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F2-07: dt is required; lower_group cuts a group" begin
        p = gown(gsys())
        for f in (() -> init(p, ExplicitEuler()), () -> solve(p), () -> solve(p; saveat = 0.05))
            e = gerr(f)
            @test occursin("needs `dt`", e) && occursin("saveat", e) && occursin("clock", e)       # F2-08c: the clock exists
        end
        disc = LatticeDiscretization(Grid((8, 8)); T = Float64)
        whole = LatticePDE.lower_group(gsys(), disc)
        @test whole.state == ["gc", "go"] && isempty(whole.external) && whole.kind === :rate
        cut = LatticePDE.lower_group(gsys(), disc; fields = [gce])
        @test cut.state == ["gc"] && cut.external == ["go"] && "go" in string.(cut.inputs)
        # the group's bound sees its own rows: o is a source of c's step (the whole system's rows
        # are coupled: no bound)
        @test isnan(whole.stability(LFP.with_tables([0.3, 0.2], Pair{String, Vector{Float64}}[]))) &&
            cut.stability(LFP.with_tables([0.3, 0.2], Pair{String, Vector{Float64}}[])) ≈ 512
        @test occursin("not a dependent variable", gerr(() -> LatticePDE.lower_group(gsys(), disc; fields = [x])))
    end
end

@testitem "F3-22 review r1: lower_group's cut keeps the faces of a field an operator reads" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F3-22 review r1: lower_group's cut keeps the faces of a field an operator reads" begin
        ce, oe = gc(t, x, y), go(t, x, y)
        sys = PDESystem(
            [D(ce) ~ 0.1 * laplacian(ce) + 0.5 * laplacian(oe) - ce, D(oe) ~ 0.2 * laplacian(oe) - oe],
            [gc(0, x, y) ~ 0.0, go(0, x, y) ~ x, go(t, 0, y) ~ 2.0, oe ~ masked(x < 0.3, 1.0)],
            [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ce, oe], Num[]; name = :gcut
        )
        disc = LatticeDiscretization(Grid((8, 8)); T = Float64)
        whole = LatticePDE.lower_group(sys, disc).rate
        cut = LatticePDE.lower_group(sys, disc; fields = [ce]).rate
        rules(p, k) = sort!(
            [
                (r.axis, r.side, r.alpha, r.beta, r.g) for r in p.rules if r isa GFaceRule &&
                    p.fields[r.field].key == k
            ]; by = r -> (r[1], r[2])
        )
        @test length(rules(cut, "go")) == 4 && rules(cut, "go") == rules(whole, "go")
        @test any(r -> r[1] == 1 && r[2] == -1 && r[5].value == 2.0, rules(cut, "go"))    # the Dirichlet face came along
        @test !any(k -> startswith(k.key, "mask:go"), cut.kernels)                       # its mask stays with its group
        # a field read pointwise only (`0.5 o`) keeps no face (the program as before)
        pt = PDESystem([D(ce) ~ 0.1 * laplacian(ce) + 0.5 * oe - ce, D(oe) ~ 0.2 * laplacian(oe) - oe], sys.bcs, sys.domain, [t, x, y], [ce, oe], Num[]; name = :gpt)
        @test isempty(rules(LatticePDE.lower_group(pt, disc; fields = [ce]).rate, "go"))
    end
end

@testitem "F3-02: ParamSlot, TableSpec and InputSpec in the GroupSpec" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F3-02: ParamSlot, TableSpec and InputSpec in the GroupSpec" begin
        disc = LatticeDiscretization(Grid((8, 8)); T = Float64)
        whole = LatticePDE.lower_group(gsys(), disc)
        @test string.(whole.params) == ["ga", "gb"] && all(q -> q isa LFP.ParamSlot && q.role === :base, whole.params)
        @test [q.default for q in whole.params] == [0.3, 0.2] && [q.text for q in whole.params] == ["ga", "gb"]
        @test all(q -> q.default === nothing, LatticePDE.lower_group(gsys(), disc; values = false).params)
        cut = LatticePDE.lower_group(gsys(), disc; fields = [gce])
        go_in = only(i for i in cut.inputs if i.key == "go")
        @test go_in isa LFP.InputSpec && !go_in.filled && go_in.eltype === Real   # another group's field: not filled
        # inputs: element type, declared bounds; none filled in B, the keys a front end names filled
        gie, gke = gin(t, x, y), gki(t, x, y)
        isys = PDESystem(
            [D(gce) ~ laplacian(gce) + ga * gie + gb * gke], [gc(0, x, y) ~ 0.0, gc(t, 0, y) ~ gc(t, 1, y), gc(t, x, 0) ~ gc(t, x, 1)],
            [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [gce, gie, gke], [ga, gb]; name = :gi
        )
        ispec = LatticePDE.lower_group(isys, disc)
        @test length(ispec.inputs) == 2 && !any(i -> i.filled, ispec.inputs)
        bi = only(i for i in ispec.inputs if i.eltype === Real)
        ki = only(i for i in ispec.inputs if i.eltype === Int32)
        @test bi.bounds == (0.0, 2.0) && ki.bounds == (-Inf, Inf) && string(bi) == bi.key
        fspec = LatticePDE.lower_group(isys, disc; filled = [ki.key])
        @test [i.filled for i in fspec.inputs] == [i.key == ki.key for i in fspec.inputs]
        # a computed default: its role and expression; a table keeps its values
        csys = PDESystem(
            [D(gce) ~ laplacian(gce) - gk * gce + Dk[2] * gce], [gc(0, x, y) ~ 0.0, gc(t, 0, y) ~ gc(t, 1, y), gc(t, x, 0) ~ gc(t, x, 1)],
            [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [gce], [ga, gk, Dk]; name = :gk
        )
        cspec = LatticePDE.lower_group(csys, disc)
        k2 = only(q for q in cspec.params if q.name == "gk")
        @test k2.role === :computed && occursin("ga", k2.derivation)
        tb = only(cspec.tables)
        @test tb isa LFP.TableSpec && tb.values == [1.0, 2.0, 3.0]
    end
end

@testitem "F3-02: an aux field read at neighbor sites (closed box: refused with the route)" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F3-02: an aux field read at neighbor sites (closed box: refused with the route)" begin
        ce, Ke = gsc(t, x, y), gsK(t, x, y)
        dom = [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        mk(rate, bcs) = PDESystem(
            [D(ce) ~ rate, Ke ~ 0.5 * ce], [gsc(0, x, y) ~ x * y, bcs...], dom, [t, x, y], [ce, Ke],
            Num[]; name = :gs
        )
        nf = [
            Differential(x)(gsc(t, 0, y)) ~ 0.0, Differential(x)(gsc(t, 1, y)) ~ 0.0,
            Differential(y)(gsc(t, x, 0)) ~ 0.0, Differential(y)(gsc(t, x, 1)) ~ 0.0,
        ]
        e = gerr(() -> gown(mk(laplacian(Ke), nf); n = 4))
        @test occursin("the rate of `gsc` reads the aux field `gsK` at a neighbor site across a closed face of axis 1 (`laplacian(gsK)`)", e)
        @test occursin("`laplacian(K)` is `k * laplacian(c)`", e) && !occursin("IRError", e) && !occursin("LatticePDE.", e)
        # a face condition on the aux field names it
        e = gerr(() -> gown(mk(0.5 * laplacian(ce), [nf; Differential(x)(gsK(t, 0, y)) ~ 0.0]); n = 4))
        @test occursin("`gsK` is an aux field", e) && occursin("takes no face condition", e)
        # an aux field as a `DivKGrad` coefficient needs no value beyond the face: it builds (control)
        @test gown(mk(DivKGrad(:harmonic)(Ke, ce), nf); n = 4) isa LFP.FieldProblem
        # the route builds and runs
        s = solve(gown(mk(0.5 * laplacian(ce), nf); n = 4), ExplicitEuler(; substeps = 1); dt = 0.01)
        @test s.retcode == ReturnCode.Success
        @test s[Ke, end] ≈ 0.5 .* s[ce, end] rtol = 1.0e-14
        # periodic: no face, so `laplacian(K)` runs (with an explicit count) and equals the route
        per = [gsc(t, 0, y) ~ gsc(t, 1, y), gsc(t, x, 0) ~ gsc(t, x, 1)]
        a = solve(gown(mk(laplacian(Ke), per); n = 4), ExplicitEuler(; substeps = 1); dt = 0.01)
        b = solve(gown(mk(0.5 * laplacian(ce), per); n = 4), ExplicitEuler(; substeps = 1); dt = 0.01)
        @test a.retcode == ReturnCode.Success
        @test a[ce, end] ≈ b[ce, end] rtol = 1.0e-12
    end
end

@testitem "F3-02: an aux-carried loop runs (Jacobi in a group, the split across groups)" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F3-02: an aux-carried loop runs (Jacobi in a group, the split across groups)" begin
        ae, cl, Kl = gla(t, x, y), glc(t, x, y), glK(t, x, y)
        per = [gla(t, 0, y) ~ gla(t, 1, y), gla(t, x, 0) ~ gla(t, x, 1), glc(t, 0, y) ~ glc(t, 1, y), glc(t, x, 0) ~ glc(t, x, 1)]
        sys = PDESystem(
            [D(ae) ~ -gkl * Kl, D(cl) ~ gkl * ae, Kl ~ cl], [gla(0, x, y) ~ 1.0, glc(0, x, y) ~ 0.0, per...],
            [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ae, cl, Kl], [gkl]; name = :gl
        )
        p = gown(sys; n = 4)
        h = 0.01
        s = solve(p, ExplicitEuler(; substeps = 1); dt = h)
        a, c = 1.0, 0.0
        for _ in 1:10
            a, c = a - h * c, c + h * a                    # K = c at the substep's start
        end
        @test s.retcode == ReturnCode.Success
        @test all(≈(a; rtol = 1.0e-14), s[ae, end]) && all(≈(c; rtol = 1.0e-14), s[cl, end]) && s[Kl, end] == s[cl, end]
        s2 = solve(p, FieldGroups(ae => ExplicitEuler(; substeps = 1), cl => ExplicitEuler(; substeps = 2)); dt = h)
        a, c = 1.0, 0.0
        for _ in 1:10
            a = a - h * c
            for _ in 1:2
                c = c + h / 2 * a                           # c's group reads the new a
            end
        end
        @test all(≈(a; rtol = 1.0e-14), s2[ae, end]) && all(≈(c; rtol = 1.0e-14), s2[cl, end])
        # (aux fields that define each other stay refused, naming them: silent.jl LF48)
    end
end

@testitem "F3-04: B reads the status word (host: after every step)" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F3-04: B reads the status word (host: after every step)" begin
        p = gown(gsys())                                      # 10 windows of 0.01
        ig = init(p, WStub(; code = 2, at = 3); dt = 0.01, saveat = 0.05)
        s = @test_logs (:warn, r"fields `gc`, `go`: the solve failed in window 3 \(t = 0\.02\) \(the linear solve diverged\).*ConvergenceFailure.*substeps = n") solve!(ig)
        @test s.retcode == ReturnCode.ConvergenceFailure && ig.iter == 3          # after window 3
        @test s.stats.solves == 3
        # a rounding floor survives to the end
        s = solve(p, WStub(; code = 1, at = 3); dt = 0.01, saveat = 0.05)
        @test s.retcode == ReturnCode.StalledSuccess && s.t[end] ≈ 0.1
        # a linear budget count warns once with the route, stays `Success`; the route removes it
        s = @test_logs (:warn, r"the linear solve reached its budget 1 time so far.*Success.*`linsolve = LatticePCG\(; maxiters = n\)`") solve(
            p,
            WStub(; need = 10, budget = 8);
            dt = 0.01
        )
        @test s.retcode == ReturnCode.Success && s.stats.budget == 10 && s.stats.solves == 10
        s = @test_logs solve(p, WStub(; need = 10, budget = 16); dt = 0.01)
        @test s.retcode == ReturnCode.Success && s.stats.budget == 0
        # explicit groups read nothing: no counters, and a warm step allocates nothing
        @test LFP.field_stats(solve(p, ExplicitEuler(; substeps = 2); dt = 0.01)) == (; solves = 0, budget = 0, floor = 0, newton_budget = 0)
        @test gwarm(init(p, ExplicitEuler(; substeps = 2); dt = 0.01, save_everystep = false)) == 0
    end
end

# F3-04 review r1: M2 `reinit!` starts a clean run (the word, the totals and `rt.status`
# cleared); S5 a write (`reset!`) keeps the failure; S4 a failure saves the state it stopped at;
# S3 the window's number and start time. The stub fails at its 3rd step only (its own count, not
# cleared), so the run after `reinit!` succeeds. Base (8f658abd): `reinit!` kept the totals and
# the failing window (the new run warned nothing and ended `ConvergenceFailure` at its first
# read); a write set `rt.status = Success`; the saves ended at 0.0.
@testitem "F3-04: reinit! starts a clean run; a write keeps the failure; the stop is saved" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F3-04: reinit! starts a clean run; a write keeps the failure; the stop is saved" begin
        p = gown(gsys())
        ig = init(p, WStub(; code = 2, at = 3); dt = 0.01, saveat = 0.05)
        s = @test_logs (:warn, r"window 3 \(t = 0\.02\)") solve!(ig)
        @test s.retcode == ReturnCode.ConvergenceFailure && s.t ≈ [0.0, 0.03] && s.u[end] == Array(ig.store.flat[LFP._parity(ig)])
        rt = only(ig.runtimes)
        ig.ps[ga] = 1.5                                               # a write: `reset!`
        @test rt.status == ReturnCode.ConvergenceFailure && LFP.check_status!(rt) == ReturnCode.ConvergenceFailure
        reinit!(ig)
        @test rt.status == ReturnCode.Success && all(iszero, LFP.status_word(rt.cache)) && rt.totals.windows == 0 &&
            rt.totals.window == 0 && rt.totals.solves == 0
        s = @test_logs solve!(ig)
        @test s.retcode == ReturnCode.Success && s.t ≈ [0.0, 0.05, 0.1] && s.stats.solves == 10
    end
end

@testitem "F3 r2: init's barriers: one group skips the coupling check; step! and solve! stay inferred" setup = [LP_groups] tags = [:latticepde, :groups] begin
    @testset "F3 r2: init's barriers: one group skips the coupling check; step! and solve! stay inferred" begin
        p = gown(gsys())
        a4 = ExplicitEuler(; substeps = 4)
        # one group returns before any work: `nothing` is no parameter vector, and it is not read
        @test LFP._check_coupling(p, [(a4, collect(String, p.state))], nothing; dt = 0.01) === nothing
        # control: two groups in a loop reach the check (`κ_c = 0.01 · 500 = 5 > 1`: refused)
        pl = remake(p; p = [ga => 500.0])
        two = [(ExplicitEuler(), [String(pl.state[1])]), (ExplicitEuler(), [String(pl.state[2])])]
        @test_throws ["ArgumentError", "FieldGroups", "dt · Σ max|coefficient|"] LFP._check_coupling(pl, two, pl.p; dt = 0.01)
        # `init` binds the groups behind a barrier (its return type is not inferred); the
        # integrator it returns steps and runs with inferred types, explicit and implicit (the
        # solution, SciML's `ODESolution`, is built behind a barrier: F4-04)
        for alg in (a4, BackwardEuler(; newton = 30, linsolve = LatticePCG(; reltol = 1.0e-12, maxiters = 64)))
            ig = init(p, alg; dt = 0.01)
            @inferred step!(ig)
            @test (@inferred LFP.finish!(ig)) === ig && solve!(ig).retcode == ReturnCode.Success
        end
    end
end
