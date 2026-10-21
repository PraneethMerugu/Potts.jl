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
    @test cut.state == ["gc"] && cut.external == ["go"] && "go" in cut.inputs
    # the group's bound sees its own rows: o is a source of c's step (the whole system's rows
    # are coupled: no bound)
    @test isnan(whole.stability(LFP.with_tables([0.3, 0.2], Pair{String, Vector{Float64}}[]))) &&
          cut.stability(LFP.with_tables([0.3, 0.2], Pair{String, Vector{Float64}}[])) ≈ 512
    @test occursin("not a dependent variable", gerr(() -> LatticePDE.lower_group(gsys(), disc; fields = [x])))
end
