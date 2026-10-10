# SciML integration: ensembles vary the replica stream; DiscreteCallbacks run at MCS
# boundaries.
using SciMLBase: ContinuousCallback

@testset "SciML ensembles and callbacks" begin
    σ, kinds = blocks((40, 40), 5)
    prob = PottsProblem(GG, initial_state(σ, kinds), Lattice((40, 40)), (0, 10), gg_params(); seed = 3)
    alg = SequentialCPM(; proposal = Moore(1))

    @testset "ensembles: trajectory i is replica i" begin
        ens = solve(EnsembleProblem(prob), alg, EnsembleSerial(); trajectories = 3)
        @test length(ens.u) == 3
        @test ens.u[1].u[end].σ != ens.u[2].u[end].σ
        @test ens.u[2].u[end].σ == solve(remake(prob; replica = 2), alg).u[end].σ
        thr = solve(EnsembleProblem(prob), alg, EnsembleThreads(); trajectories = 3)
        @test all(i -> thr.u[i].u[end].σ == ens.u[i].u[end].σ, 1:3)        # reproducible, any scheduler
        # a prob_func that changes parameters still gets distinct replicas
        pf(q, ctx) = remake(q; p = merge(q.p, (; T = 5.0)))
        e2 = solve(EnsembleProblem(prob; prob_func = pf), alg, EnsembleSerial(); trajectories = 2)
        @test e2.u[1].u[end].σ != e2.u[2].u[end].σ && e2.u[1].prob.p.T == 5.0
        # … unless it chooses the seed or replica itself
        pinned(q, ctx) = remake(q; replica = 7)
        e3 = solve(EnsembleProblem(prob; prob_func = pinned), alg, EnsembleSerial(); trajectories = 2)
        @test e3.u[1].u[end].σ == e3.u[2].u[end].σ
    end

    @testset "DiscreteCallback at MCS boundaries" begin
        seen = Int[]
        log = DiscreteCallback((u, t, integ) -> iseven(t), integ -> push!(seen, integ.t))
        stop = DiscreteCallback((u, t, integ) -> t == 4, integ -> terminate!(integ))
        sol = solve(prob, alg; callback = CallbackSet(log, stop))
        @test seen == [2, 4]
        @test sol.t[end] == 4 && sol.retcode == ReturnCode.Terminated
        # affect! may change the live state and parameters; saved states see it
        heat = DiscreteCallback((u, t, integ) -> t == 3, integ -> (integ.p = merge(integ.p, (; T = 1e6))))
        s2 = solve(prob, alg; callback = heat, saveat = [3, 10])
        @test s2.t == [0, 3, 10]
        integ = init(prob, alg; callback = heat)
        foreach(_ -> step!(integ), 1:3)
        @test integ.p.T == 1e6
        @test_throws ArgumentError init(prob, alg; callback = ContinuousCallback((u, t, i) -> t - 1, i -> nothing))
        # initialize/finalize hooks run once
        calls = Int[]
        cb = DiscreteCallback((u, t, i) -> false, i -> nothing;
            initialize = (c, u, t, i) -> push!(calls, 1), finalize = (c, u, t, i) -> push!(calls, 2))
        solve(prob, alg; callback = cb)
        @test calls == [1, 2]
    end
end

# P6.15m m3: a CallbackSet of two differently typed DiscreteCallbacks with `saveat` segfaulted
# on the host CheckerboardCPM path (GC heap corruption, found in a later `_save!`). The
# integrator looped `for cb in integ.callbacks`, which carries a `Union` of the callback types
# (closures and a BitVector next to bits fields), and Julia 1.12's optimized code for that
# loop corrupted the heap; it depends on the heap layout, so the crash itself reproduces only
# in a full model run (the OpenVT chain test in PottsModels). Here: the callback paths hold
# no such `Union`, and every hook of every callback still runs, in order.
@testset "CallbackSet of differently typed callbacks with saveat" begin
    σ, kinds = blocks((30, 30), 5)
    prob = PottsProblem(GG, initial_state(σ, kinds), Lattice((30, 30)), (0, 12), gg_params(); seed = 5)
    is_cb_union(T) = T isa Union && all(x -> x <: DiscreteCallback, Base.uniontypes(T))
    cb_unions(f, types) = count(is_cb_union ∘ CorePotts.Core.Compiler.widenconst,
        only(code_typed(f, types; optimize = true)).first.ssavaluetypes)
    @testset "$(nameof(typeof(alg)))" for alg in (CheckerboardCPM(; proposal = Moore(1)), SequentialCPM(; proposal = Moore(1)))
        calls = Tuple{Symbol, Int}[]
        snap = Ref(0)
        mark = DiscreteCallback((u, t, integ) -> t == 4, integ -> (snap[] = integ.stats.mcs; nothing);
            save_positions = (false, false), initialize = (c, u, t, i) -> push!(calls, (:init, 1)),
            finalize = (c, u, t, i) -> push!(calls, (:final, 1)))
        heat = DiscreteCallback((u, t, integ) -> t == 4, integ -> (integ.ps[:T] = 2 * integ.ps[:T]; nothing);
            initialize = (c, u, t, i) -> push!(calls, (:init, 2)), finalize = (c, u, t, i) -> push!(calls, (:final, 2)))
        integ = init(prob, alg; saveat = 0:12, callback = CallbackSet(mark, heat))
        T = typeof(integ)
        @test typeof(integ.callbacks) === Tuple{typeof(mark), typeof(heat)}       # two distinct types
        @test cb_unions(CorePotts._apply_callbacks!, (T,)) == 0
        @test cb_unions(CorePotts.CommonSolve.step!, (T,)) == 0
        @test cb_unions(CorePotts.CommonSolve.solve!, (T,)) == 0
        sol = solve!(integ)
        @test sol.t == 0:12 && length(sol.u) == 13
        @test snap[] == 4 && sol.prob.p.T == gg_params().T && integ.p.T == 2 * gg_params().T
        @test calls == [(:init, 1), (:init, 2), (:final, 1), (:final, 2)]
        # stress: many solves with saves, then a full collection (the crash surfaced in GC)
        for s in 1:20
            r = solve(remake(prob; seed = s), alg; saveat = 0:12, callback = CallbackSet(mark, heat))
            @test length(r.u) == 13
        end
        GC.gc(true)
        @test true
    end
    # negative control: a plain `for` loop over the same tuple does carry the Union
    loop(cbs) = (for cb in cbs
        cb.condition(nothing, 0, nothing)
    end; nothing)
    m = DiscreteCallback((u, t, i) -> t == 1, i -> nothing; save_positions = (false, false))
    h = DiscreteCallback((u, t, i) -> t == 2, i -> nothing)
    @test cb_unions(loop, (Tuple{typeof(m), typeof(h)},)) > 0
end

# D-116: a problem without a model whose parameter object is a NamedTuple has its fields as
# parameter names; `remake_buffer` (and `setp_oop`, which calls it) returns a new NamedTuple.
@testset "remake_buffer on a NamedTuple parameter object" begin
    SII = CorePotts.SymbolicIndexingInterface
    σ, kinds = blocks((20, 20), 5)
    gp = PottsProblem(GG, initial_state(σ, kinds), Lattice((20, 20)), (0, 2), gg_params(); seed = 3)
    gi = init(gp, SequentialCPM())
    # without a CorePotts method, SII's untyped fallback and its deprecated `Dict` method call
    # each other forever: check the method instead of risking the test process
    # (`setp_oop` calls it on the root container, with tuples)
    m = which(SII.remake_buffer, Tuple{typeof(gp), typeof(gp.p), Vector{Symbol}, Vector{Float64}})
    mo = which(SII.remake_buffer, Tuple{typeof(SII.symbolic_container(gi)), typeof(gp.p), Tuple{Any}, Tuple{Int}})
    @test m.module === CorePotts && mo.module === CorePotts
    if m.module === CorePotts && mo.module === CorePotts
        r = SII.remake_buffer(gp, gp.p, [:T, :λ], [3.0, 2])
        @test typeof(r) === typeof(gp.p) && r == merge(gp.p, (; T = 3.0, λ = 2.0))
        @test gp.p == gg_params()                                         # the original untouched
        @test SII.remake_buffer(gi, gi.p, [:V0], [7]).V0 === 7.0
        @test SII.setp_oop(gi, :T)(gi, 4) == merge(gp.p, (; T = 4.0))
        @test gi.p == gg_params()
        # negative controls: an unknown field; keys and values of different lengths
        @test_throws ArgumentError SII.remake_buffer(gp, gp.p, [:T, :zz], [1.0, 2.0])
        @test_throws DimensionMismatch SII.remake_buffer(gp, gp.p, [:T], [1.0, 2.0])
    end
end
