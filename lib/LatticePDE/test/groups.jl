# F2-06: the shared group layer (LatticeFields.Problems, group.jl). An owned problem steps
# through `GroupRuntime`s (`advance!`, one per field group); `FieldGroups` assigns algorithms
# to fields; an algorithm declares its buffers (`nbuffers`) and keeps a cache (`alg_cache`)
# that `reset!` and its return code (`step_retcode!`) reach.
using LatticeFields: Problems as LFP
using SciMLBase: SciMLBase, remake, reinit!, ReturnCode
using SymbolicIndexingInterface: setp

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
