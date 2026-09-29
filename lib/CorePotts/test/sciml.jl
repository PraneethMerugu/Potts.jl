# SciML integration: ensembles vary the replica stream; DiscreteCallbacks run at MCS
# boundaries.
using SciMLBase: ContinuousCallback

@testset "SciML ensembles and callbacks" begin
    σ, kinds = blocks((40, 40), 5)
    prob = CPMProblem(GG, initial_state(σ, kinds), Lattice((40, 40)), (0, 10), gg_params(); seed = 3)
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
