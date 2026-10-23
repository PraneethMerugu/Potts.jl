# F2-06: the shared group layer (LatticeFields.Problems, group.jl). An owned problem steps
# through `GroupRuntime`s (`advance!`, one per field group); `FieldGroups` assigns algorithms
# to fields; an algorithm declares its buffers (`nbuffers`) and keeps a cache (`alg_cache`)
# that `reset!` and its return code (`step_retcode!`) reach.
# F2-07: `lower_group` (the rate form and the group cut), the update pass (`fuse_update`) and
# its byte-identity gate, a clip in B, `dt` required, Cartesian indexing on the host.
using LatticeFields: Problems as LFP
using SciMLBase: SciMLBase, remake, reinit!, ReturnCode
using SymbolicIndexingInterface: setp
using LatticeFields.Compile: fingerprint_text, fuse_update

# a stub algorithm: Euler with three substeps, three buffers and a counting cache that fails at
# step `fail_at` (0: never)
struct GStub <: LFP.FieldAlgorithm
    dt::Float64
    fail_at::Int
end
mutable struct GStubCache
    steps::Int
    resets::Int
    fail_at::Int
end
LFP.nbuffers(::GStub) = 3
LFP.update_key(::GStub) = :euler
LFP.update_rule(::GStub) = LFP.update_rule(ExplicitEuler())
LFP.alg_cache(a::GStub, group, store) = GStubCache(0, 0, a.fail_at)
LFP.reset_cache!(c::GStubCache) = (c.resets += 1; nothing)
LFP.step_retcode!(c::GStubCache, rt) = (c.steps += 1; c.steps == c.fail_at ? ReturnCode.ConvergenceFailure : ReturnCode.Success)
LFP.substeps(::LFP.FieldProblem, ::GStub, p = nothing; tables = nothing, inputs = nothing) = 3

@parameters ga = 0.3 gb = 0.2
@variables gc(..) go(..)
gce, goe = gc(t, x, y), go(t, x, y)
# c diffuses and reads o; o decays and reads c
gsys(; T = 0.1) = PDESystem([D(gce) ~ Δ(gce) + ga * goe, D(goe) ~ -gb * goe + 0.1 * gce],
    [gc(0, x, y) ~ x * y, go(0, x, y) ~ 1.0 + x, gc(t, 0, y) ~ gc(t, 1, y), gc(t, x, 0) ~ gc(t, x, 1),
     go(t, 0, y) ~ go(t, 1, y), go(t, x, 0) ~ go(t, x, 1)],
    [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [gce, goe], [ga, gb]; name = :g)
gown(sys; n = 8) = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64, problem = :owned))
gwarm(ig) = (step!(ig); step!(ig); @allocated step!(ig))      # (a function barrier)
gerr(f) = try
    f(); ""
catch e
    e isa ArgumentError || rethrow()
    sprint(showerror, e)
end

@testset "F2-06: B steps through the group layer" begin
    p = gown(gsys())
    a4, a3 = ExplicitEuler(; dt = 0.01, substeps = 4), ExplicitEuler(; dt = 0.01, substeps = 3)
    ig = init(p, a4)
    rt = only(ig.runtimes)
    @test rt isa LFP.GroupRuntime && rt.n == ig.substeps == 4 && rt.ends_in === :parity
    @test p.group isa LFP.FieldGroup && p.group.spec.state == p.state && p.group.spec.kind === :rate
    # `advance!` returns the step's code, and `integ.retcode` reads it
    @test LFP.advance!(rt, (0.0, 0)) == ReturnCode.Success && rt.status == ReturnCode.Success
    step!(ig)
    @test ig.retcode == ReturnCode.Success
    # one algorithm for every field is one group: the same launches, the same states
    s1, s2 = solve(p, a4), solve(p, FieldGroups(gce => a4, goe => a4))
    @test s2.u == s1.u && s2.substeps == s1.substeps
    s3 = solve(p, FieldGroups(goe => a4; default = a4))
    @test s3.u == s1.u
    # step! allocates nothing, one group and two
    @test gwarm(init(p, a4)) == 0
    @test gwarm(init(p, FieldGroups(gce => a4, goe => a3))) == 0
end

@testset "F2-06: FieldGroups: two groups in state order, each ending in slot 1" begin
    # c does not read o (ga = 0): the c group steps alone; the o group runs after it and reads
    # the new c from its array (base: no groups in B)
    p = remake(gown(gsys()); p = [ga => 0.0])
    a4, a3 = ExplicitEuler(; dt = 0.01, substeps = 4), ExplicitEuler(; dt = 0.01, substeps = 3)
    ig = init(p, FieldGroups(gce => a4, goe => a3))
    @test length(ig.runtimes) == 2 && [r.n for r in ig.runtimes] == [4, 3] &&
          all(r -> r.ends_in === :slot1, ig.runtimes)
    # each group's count comes from the bound of its own rows: with c reading o (ga = 0.3) the
    # whole system's rows are coupled, the c group's are not (o is read from its array)
    ic = init(gown(gsys()), FieldGroups(gce => ExplicitEuler(; dt = 0.01); default = ExplicitEuler(; dt = 0.01, substeps = 3)))
    @test [r.n for r in ic.runtimes] == [3, 3]                    # c: ⌈0.01 · 512 / 1.8⌉ = 3, automatic
    @test occursin("no automatic substeps", gerr(() -> init(gown(gsys()), ExplicitEuler(; dt = 0.01))))   # control
    o0 = copy(ig[goe])
    step!(ig)
    c1, o1 = ig[gce], ig[goe]
    h = 0.01 / 3
    ref = o0
    for _ in 1:3
        ref = ref .+ h .* (-0.2 .* ref .+ 0.1 .* c1)
    end
    @test o1 ≈ ref rtol = 1e-12                                   # three substeps with c at its new value
    one = init(p, a4)
    step!(one)
    @test c1 ≈ one[gce] rtol = 1e-14                              # the c group: four substeps
    @test all(==(1), ig.store.cur[[r.swaps[1] for r in ig.runtimes]])   # odd count: back in slot 1
    @test !(o1 ≈ one[goe])                                        # control: one group steps o in 4, Jacobi
    # refusals: two windows, a map with a rate, a field with no algorithm, a name that is no field
    @test occursin("same window", gerr(() -> init(p, FieldGroups(gce => a4, goe => ExplicitEuler(; dt = 0.02)))))
    @test occursin("never mixed", gerr(() -> init(p, FieldGroups(gce => a4, goe => ExplicitMap()))))
    @test occursin("`go`", gerr(() -> init(p, FieldGroups(gce => a4))))
    @test occursin("not a state field", gerr(() -> init(p, FieldGroups(:zz => a4; default = a4))))
    @test occursin("one algorithm per field", gerr(() -> FieldGroups(gce => FieldGroups(goe => a4))))
    @test occursin("not a field algorithm", gerr(() -> FieldGroups(gce => 1.0)))
end

@testset "F2-06: an algorithm's buffers, cache, reset! and return code" begin
    p = gown(gsys())
    ig = init(p, GStub(0.01, 0))
    @test length(ig.store.flat) == 3                              # nbuffers = 3: a third buffer
    c = only(ig.runtimes).cache
    @test c isa GStubCache && c.resets == 0
    ig[gce] = fill(1.0, 8, 8)                                     # a state write
    @test c.resets == 1
    reinit!(ig)
    @test c.resets == 2 && ig.iter == 0 && ig[gce] ≈ init(p, GStub(0.01, 0))[gce]
    setp(ig, ga)(ig, 0.5)                                         # a rebind
    @test c.resets == 3
    # a remade problem's integrator starts with a fresh cache
    c2 = only(init(remake(p; p = [gb => 0.1]), GStub(0.01, 0)).runtimes).cache
    @test c2 !== c && c2.resets == 0 && c2.steps == 0
    # the stub steps as ExplicitEuler with its count: the third buffer changes nothing
    @test solve(p, GStub(0.01, 0)).u[end] == solve(p, ExplicitEuler(; dt = 0.01, substeps = 3)).u[end]
    # its failure code stops solve! at that step
    ig = init(p, GStub(0.01, 3))
    sol = solve!(ig)
    @test sol.retcode == ReturnCode.ConvergenceFailure && ig.iter == 3
    @test solve(p, GStub(0.01, 0)).retcode == ReturnCode.Success  # control: no failure, the full span
end

@testset "F2-06: the step-start clamp: a mask that switches on is read by that step's substeps" begin
    @variables gw(..) gwk(..)::Int32 [input = true]
    we, wk = gw(t, x, y), gwk(t, x, y)
    sys = PDESystem([D(we) ~ Δ(we)], [gw(0, x, y) ~ 0.0, we ~ masked((t > 0.0015) & (wk == 0), 1.0)],
        [t ∈ Interval(0.0, 0.003), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [we, wk], Num[]; name = :w)
    K = ones(Int32, 4, 4)
    K[1, 1] = 0
    p = discretize(sys, LatticeDiscretization(Grid((4, 4)); T = Float64, problem = :owned); inputs = [wk => K])
    s = solve(p, ExplicitEuler(; dt = 0.001, substeps = 1); saveat = 0.001)
    @test s[:gw][3][1, 1] == 0.0 && s[:gw][3][2, 1] == 0.0       # t = 0.002: the mask was off at each step's start
    # step 3 starts at t = 0.002 > 0.0015: the site is clamped at its start and the substep reads
    # the 1.0 (without the step-start clamp the neighbour stays 0.0 until step 4)
    @test s[:gw][4][1, 1] == 1.0 && s[:gw][4][2, 1] > 0.01
end

@testset "F2-06: the warning set stays bounded over 500 remakes" begin
    # the coupled rows of c and o are not bounded: an explicit count warns once per (program,
    # term, cause), never once per value (base: 500 keys, about 120 KB, record (a))
    p = gown(gsys())
    alg = ExplicitEuler(; dt = 0.01, substeps = 2)
    init(p, alg)
    @test any(startswith(LFP._warn_key(p, "")), LFP._SEEN_WARNED)  # this program's key is there
    n0 = length(LFP._SEEN_WARNED)
    for k in 1:500
        init(remake(p; p = [gb => 0.2 + k * 1e-4]), alg)
    end
    @test length(LFP._SEEN_WARNED) == n0
end

# Hand FTCS on a 2D box (test/fields.jl:10–33, ported): `n` substeps of `dt/n`; periodic or
# zero-flux faces; `rate(c, i, j)` the reaction; the update clipped below at `lower`
function g_ftcs(c0, D, h, dt, n; periodic, rate = (c, i, j) -> 0.0, lower = nothing)
    c = copy(c0)
    nx, ny = size(c)
    for _ in 1:n
        new = similar(c)
        for j in 1:ny, i in 1:nx
            lap = 0.0
            for (di, dj, hd) in ((1, 0, h[1]), (-1, 0, h[1]), (0, 1, h[2]), (0, -1, h[2]))
                a, b = i + di, j + dj
                if periodic
                    a, b = mod1(a, nx), mod1(b, ny)
                elseif !(1 <= a <= nx && 1 <= b <= ny)
                    continue                                       # zero flux: the ghost is the site
                end
                lap += (c[a, b] - c[i, j]) / hd^2
            end
            v = c[i, j] + dt / n * (D * lap + rate(c, i, j))
            new[i, j] = lower === nothing ? v : max(v, lower)
        end
        c = new
    end
    return c
end

@testset "F2-07: the update pass equals the symbolic fusion (byte-identity gate)" begin
    @variables gm(..) gd(..)::Bool [input = true] gk(..)::Int32 [input = true]
    gme, gde, gke = gm(t, x, y), gd(t, x, y), gk(t, x, y)
    @parameters gr = -0.5 Dg[1:2] = [0.3, 1.0]
    dom = [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    systems = [
        gsys(),                                                       # coupled, periodic
        PDESystem([D(gme) ~ at(Dg, gke) * Δ(gme) - 0.1gme], [gm(0, x, y) ~ x, gme ~ masked(gke == 2, 1.0)],
            dom, [t, x, y], [gme, gke], [Dg]; name = :m),             # a masked condition, a site multiplier
        PDESystem([D(gme) ~ Δ(gme)], [gm(0, x, y) ~ x * y, gm(t, 0, y) + gr * Differential(x)(gm(t, 0, y)) ~ 1.0],
            dom, [t, x, y], [gme], [gr]; name = :r),                  # a Robin face
    ]
    discs = [LatticeDiscretization(Grid((8, 8)); T = Float64), LatticeDiscretization(Grid((8, 8)); T = Float64),
        LatticeDiscretization(Grid((8, 8)); T = Float64)]
    # an irregular domain (`select(inside, …)` around the update)
    push!(systems, PDESystem([D(gme) ~ Δ(gme) - gme], [gm(0, x, y) ~ x], dom, [t, x, y], [gme, gde], Num[]; name = :d))
    push!(discs, LatticeDiscretization(Grid((8, 8)); T = Float64, domain = gd))
    for (sys, disc) in zip(systems, discs), lower in (nothing, 0.0), T in (Float64, Float32)
        rate = symbolic_discretize(sys, disc).program
        sym = symbolic_discretize(sys, disc; update = (kb, c, r) -> (v = LatticePDE.euler_update(kb, c, r);
                                                                        lower === nothing ? v : max(v, lower))).program
        pass = fuse_update(rate, LFP.update_rule(ExplicitEuler(; lower)))
        @test fingerprint_text(pass; T) == fingerprint_text(sym; T)
        @test fingerprint_text(rate; T) != fingerprint_text(sym; T)      # control: the rate form is not the step
    end
    # the gate inside `discretize` (`LATTICEPDE_CHECK_FUSION=1`: the suites run with it)
    withenv("LATTICEPDE_CHECK_FUSION" => "1") do
        @test gown(gsys()) isa FieldProblem
    end
end

@testset "F2-07: a clip in B; a second algorithm fuses once, with no LatticePDE call" begin
    @variables gq(..)
    gqe = gq(t, x, y)
    n = 8
    sys = PDESystem([D(gqe) ~ Δ(gqe) - 3.0], [gq(0, x, y) ~ x * y, gq(t, 0, y) ~ gq(t, 1, y), gq(t, x, 0) ~ gq(t, x, 1)],
        [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [gqe], Num[]; name = :q)
    p = gown(sys; n)
    @test p.options.index === :cartesian                          # the host indexes by coordinates
    alg = ExplicitEuler(; dt = 0.05, substeps = 4, lower = 0.0)
    s = solve(p, alg)
    k = init(p, alg).substeps                                     # 4 is a minimum: the bound raises it
    @test k == 15                                                 # ⌈0.05 · 512 / 1.8⌉
    c = s[:gq][1]
    for _ in 1:4
        c = g_ftcs(c, 1.0, (1 / n, 1 / n), 0.05, k; periodic = true, rate = (c, i, j) -> -3.0, lower = 0.0)
    end
    @test isapprox(s[:gq][end], c; rtol = 1e-12) && minimum(c) == 0.0   # clipped (base: `lower` refused in B)
    @test minimum(solve(p, ExplicitEuler(; dt = 0.05, substeps = 4))[:gq][end]) < 0   # control: no clip
    # the clip's program is fused once, in the group (the update pass, no symbolic step)
    @test haskey(p.group.programs, (:euler, 0.0)) && length(p.group.programs) == 2
    init(p, ExplicitEuler(; dt = 0.1, substeps = 2, lower = 0.0))   # another window and count: the same update
    @test length(p.group.programs) == 2
    q = remake(p; u0 = p.u0)
    @test q.group === p.group                                     # a remake shares the group
    pc = gown(sys; n)
    cold = @allocated init(pc, ExplicitEuler(; dt = 0.05, substeps = 4, lower = 1.0))   # fused, planned, emitted
    warm = @allocated init(pc, ExplicitEuler(; dt = 0.05, substeps = 4, lower = 1.0))
    @test warm < cold / 4 && length(pc.group.programs) == 2        # warm: nothing fused, planned or emitted
end

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

# F3-02 (F2 design §2.2): the group's slots are specs, not names. A parameter slot holds its
# default and role (a computed default: `:computed` with its expression), a table its values, an
# input its element type, declared bounds, default and whether a front end fills it at every
# step (`filled`: front end A's CPM reads; none in B). `string` of each is its key, so the
# names in order are unchanged.
@parameters gk = 2ga
@variables gin(..) [input = true, bounds = (0.0, 2.0)] gki(..)::Int32 [input = true]
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
    isys = PDESystem([D(gce) ~ Δ(gce) + ga * gie + gb * gke], [gc(0, x, y) ~ 0.0, gc(t, 0, y) ~ gc(t, 1, y), gc(t, x, 0) ~ gc(t, x, 1)],
        [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [gce, gie, gke], [ga, gb]; name = :gi)
    ispec = LatticePDE.lower_group(isys, disc)
    @test length(ispec.inputs) == 2 && !any(i -> i.filled, ispec.inputs)
    bi = only(i for i in ispec.inputs if i.eltype === Real)
    ki = only(i for i in ispec.inputs if i.eltype === Int32)
    @test bi.bounds == (0.0, 2.0) && ki.bounds == (-Inf, Inf) && string(bi) == bi.key
    fspec = LatticePDE.lower_group(isys, disc; filled = [ki.key])
    @test [i.filled for i in fspec.inputs] == [i.key == ki.key for i in fspec.inputs]
    # a computed default: its role and expression; a table keeps its values
    csys = PDESystem([D(gce) ~ Δ(gce) - gk * gce + Dk[2] * gce], [gc(0, x, y) ~ 0.0, gc(t, 0, y) ~ gc(t, 1, y), gc(t, x, 0) ~ gc(t, x, 1)],
        [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [gce], [ga, gk, Dk]; name = :gk)
    cspec = LatticePDE.lower_group(csys, disc)
    k2 = only(q for q in cspec.params if q.name == "gk")
    @test k2.role === :computed && occursin("ga", k2.derivation)
    tb = only(cspec.tables)
    @test tb isa LFP.TableSpec && string(tb) == "Dk" && tb.values == [1.0, 2.0, 3.0]
end

# F3-02 review r1 S6: an aux field read at neighbor sites by a rate (`K ~ k c`, `D(c) ~ Δ(K)`)
# has no value beyond a closed face: refused in the equation's words with the route (`k Δ(c)`),
# which builds and gives the same run on a periodic box. A face condition on an aux field is
# refused naming it. Base (8f658abd): "IRError: field `K` has no boundary rule on axis 1 side -";
# a face on `K`: "face conditions apply to rate fields (a map's offset …)" (reviewer probe u3_b §5b).
@variables gsc(..) gsK(..)
@testset "F3-02: an aux field read at neighbor sites (closed box: refused with the route)" begin
    ce, Ke = gsc(t, x, y), gsK(t, x, y)
    dom = [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    mk(rate, bcs) = PDESystem([D(ce) ~ rate, Ke ~ 0.5 * ce], [gsc(0, x, y) ~ x * y, bcs...], dom, [t, x, y], [ce, Ke],
        Num[]; name = :gs)
    nf = [Differential(x)(gsc(t, 0, y)) ~ 0.0, Differential(x)(gsc(t, 1, y)) ~ 0.0,
          Differential(y)(gsc(t, x, 0)) ~ 0.0, Differential(y)(gsc(t, x, 1)) ~ 0.0]
    e = gerr(() -> gown(mk(Δ(Ke), nf); n = 4))
    @test occursin("the rate of `gsc` reads the aux field `gsK` at a neighbor site across a closed face of axis 1 (`Δ(gsK)`)", e)
    @test occursin("`Δ(K)` is `k * Δ(c)`", e) && !occursin("IRError", e) && !occursin("LatticePDE.", e)
    # a face condition on the aux field names it
    e = gerr(() -> gown(mk(0.5 * Δ(ce), [nf; Differential(x)(gsK(t, 0, y)) ~ 0.0]); n = 4))
    @test occursin("`gsK` is an aux field", e) && occursin("takes no face condition", e)
    # an aux field as a `DivKGrad` coefficient needs no value beyond the face: it builds (control)
    @test gown(mk(DivKGrad(:harmonic)(Ke, ce), nf); n = 4) isa LFP.FieldProblem
    # the route builds and runs
    s = solve(gown(mk(0.5 * Δ(ce), nf); n = 4), ExplicitEuler(; dt = 0.01, substeps = 1))
    @test s.retcode == ReturnCode.Success
    @test s[Ke][end] ≈ 0.5 .* s[ce][end] rtol = 1e-14
    # periodic: no face, so `Δ(K)` runs (with an explicit count) and equals the route
    per = [gsc(t, 0, y) ~ gsc(t, 1, y), gsc(t, x, 0) ~ gsc(t, x, 1)]
    a = solve(gown(mk(Δ(Ke), per); n = 4), ExplicitEuler(; dt = 0.01, substeps = 1))
    b = solve(gown(mk(0.5 * Δ(ce), per); n = 4), ExplicitEuler(; dt = 0.01, substeps = 1))
    @test a.retcode == ReturnCode.Success
    @test a[ce][end] ≈ b[ce][end] rtol = 1e-12
end

# F3-02 (F3 design §3.11): an aux field that carries one state into another's rate (`K ~ c`,
# `D(a) ~ -k K`, `D(c) ~ k a`) is a one-buffer field read new inside the group's Jacobi step:
# its kernel runs first. One group equals the hand-stepped Jacobi step; two groups the split
# (a's group, holding c, then c's group reading the new a). Base (eb2efb60): `discretize`
# refused it ("the fields K, a, c define each other within one step (a read cycle …)").
@parameters gkl = 1.0
@variables gla(..) glc(..) glK(..)
@testset "F3-02: an aux-carried loop runs (Jacobi in a group, the split across groups)" begin
    ae, cl, Kl = gla(t, x, y), glc(t, x, y), glK(t, x, y)
    per = [gla(t, 0, y) ~ gla(t, 1, y), gla(t, x, 0) ~ gla(t, x, 1), glc(t, 0, y) ~ glc(t, 1, y), glc(t, x, 0) ~ glc(t, x, 1)]
    sys = PDESystem([D(ae) ~ -gkl * Kl, D(cl) ~ gkl * ae, Kl ~ cl], [gla(0, x, y) ~ 1.0, glc(0, x, y) ~ 0.0, per...],
        [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ae, cl, Kl], [gkl]; name = :gl)
    p = gown(sys; n = 4)
    h = 0.01
    s = solve(p, ExplicitEuler(; dt = h, substeps = 1))
    a, c = 1.0, 0.0
    for _ in 1:10
        a, c = a - h * c, c + h * a                    # K = c at the substep's start
    end
    @test s.retcode == ReturnCode.Success
    @test all(≈(a; rtol = 1e-14), s[ae][end]) && all(≈(c; rtol = 1e-14), s[cl][end]) && s[Kl][end] == s[cl][end]
    s2 = solve(p, FieldGroups(ae => ExplicitEuler(; dt = h, substeps = 1), cl => ExplicitEuler(; dt = h, substeps = 2)))
    a, c = 1.0, 0.0
    for _ in 1:10
        a = a - h * c
        for _ in 1:2
            c = c + h / 2 * a                           # c's group reads the new a
        end
    end
    @test all(≈(a; rtol = 1e-14), s2[ae][end]) && all(≈(c; rtol = 1e-14), s2[cl][end])
    # (aux fields that define each other stay refused, naming them: silent.jl LF48)
end

# F3-04 (F3 design §3.3, §3.4): the status word and its readers. A stub with a solve (`WStub`)
# steps as Euler and writes into its cache's word what an implicit solver would: a solve per
# window, a linear budget hit per window when `need > budget`, and code `code` from window `at`
# (sticky, with the window and a cause bit). B reads the word on the host after every step,
# and at the saves and the end. Base (f8510fe8): no reader; the run ended `Success`.
struct WStub <: LFP.FieldAlgorithm
    dt::Float64
    code::UInt32
    at::Int
    need::Int
    budget::Int
end
WStub(dt; code = 0, at = 0, need = 0, budget = 8) = WStub(dt, UInt32(code), at, need, budget)
mutable struct WStubCache{W}
    word::W
    steps::Int
    a::WStub
end
LFP.nbuffers(::WStub) = 2
LFP.update_key(::WStub) = :euler
LFP.update_rule(::WStub) = LFP.update_rule(ExplicitEuler())
LFP.alg_cache(a::WStub, group, store) = WStubCache(fill!(similar(store.flat[1], UInt32, 8), 0), 0, a)
LFP.status_word(c::WStubCache) = c.word
LFP.reset_cache!(::WStubCache) = nothing                  # (no history; a write keeps the word)
LFP.substeps(::LFP.FieldProblem, ::WStub, p = nothing; tables = nothing, inputs = nothing) = 1
wbump!(w, i, x) = (v = view(w, i:i); v .+= UInt32(x); nothing)
wset!(w, i, x) = (v = view(w, i:i); v .= UInt32(x); nothing)
function LFP.step_retcode!(c::WStubCache, rt)
    c.steps += 1
    wbump!(c.word, LFP.STATUS_SOLVES, 1)
    c.a.need > c.a.budget && wbump!(c.word, LFP.STATUS_BUDGET, 1)
    if c.a.code > 0 && c.steps == c.a.at
        wset!(c.word, LFP.STATUS_CODE, c.a.code)
        # the window, as a solver writes it: the runtime's window count (review r1 S3)
        c.a.code >= 2 && (wset!(c.word, LFP.STATUS_WINDOW, rt.totals.windows); wset!(c.word, LFP.STATUS_CAUSE, 1))
    end
    return ReturnCode.Success
end

@testset "F3-04: B reads the status word (host: after every step)" begin
    p = gown(gsys())                                      # 10 windows of 0.01
    ig = init(p, WStub(0.01; code = 2, at = 3); saveat = 0.05)
    s = @test_logs (:warn, r"fields `gc`, `go`: the solve failed in window 3 \(t = 0\.02\) \(the linear solve diverged\).*ConvergenceFailure.*substeps = n") solve!(ig)
    @test s.retcode == ReturnCode.ConvergenceFailure && ig.iter == 3          # after window 3
    @test s.stats.solves == 3
    # a rounding floor survives to the end
    s = solve(p, WStub(0.01; code = 1, at = 3); saveat = 0.05)
    @test s.retcode == ReturnCode.StalledSuccess && s.t[end] ≈ 0.1
    # a linear budget count warns once with the route, stays `Success`; the route removes it
    s = @test_logs (:warn, r"the linear solve reached its budget 1 time so far.*Success.*`inner = DevicePCG\(; budget = n\)`") solve(p,
        WStub(0.01; need = 10, budget = 8))
    @test s.retcode == ReturnCode.Success && s.stats.budget == 10 && s.stats.solves == 10
    s = @test_logs solve(p, WStub(0.01; need = 10, budget = 16))
    @test s.retcode == ReturnCode.Success && s.stats.budget == 0
    # explicit groups read nothing: no counters, and a warm step allocates nothing
    @test solve(p, ExplicitEuler(; dt = 0.01, substeps = 2)).stats == (; solves = 0, budget = 0, floor = 0, newton_budget = 0)
    @test gwarm(init(p, ExplicitEuler(; dt = 0.01, substeps = 2))) == 0
end

# F3-04 review r1: M2 `reinit!` starts a clean run (the word, the totals and `rt.status`
# cleared); S5 a write (`reset!`) keeps the failure; S4 a failure saves the state it stopped at;
# S3 the window's number and start time. The stub fails at its 3rd step only (its own count, not
# cleared), so the run after `reinit!` succeeds. Base (8f658abd): `reinit!` kept the totals and
# the failing window (the new run warned nothing and ended `ConvergenceFailure` at its first
# read); a write set `rt.status = Success`; the saves ended at 0.0.
@testset "F3-04: reinit! starts a clean run; a write keeps the failure; the stop is saved" begin
    p = gown(gsys())
    ig = init(p, WStub(0.01; code = 2, at = 3); saveat = 0.05)
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
