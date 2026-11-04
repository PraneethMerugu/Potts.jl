# CheckerboardCPM's kinetic options (P6.0bl, research/checkerboard-kinetics.md §6): retries,
# colors drawn with replacement, the stride, and the copy counts. The closeness to
# SequentialCPM is measured by `benchmark/kinetics.jl`, not here; these tests pin correctness.

@testset "checkerboard passes (P6.0bl)" begin
    lat = Lattice((30, 30))
    σ, kinds = blocks((30, 30), 5)
    tracked = CPMFunction(gg_delta_H; temperature = gg_temperature, track = CorePotts.TrackDeltaH{Float64}())
    prob = PottsProblem(tracked, initial_state(σ, kinds), lat, (0, 20), gg_params())
    H(u) = total_H(u, lat, prob.contact, gg_params())
    recount(u) = [count(==(c), u.σ) for c in eachindex(kinds)]

    @testset "exact ΔH and trackers: $(kw)" for kw in ((; retries = 1), (; retries = 3),
        (; colors = :replacement), (; retries = 2, colors = :replacement), (; stride = 3, retries = 1))
        for seed in 1:3
            sol = solve(remake(prob; seed), CheckerboardCPM(; proposal = Moore(1), kw...))
            u0, u = sol.u[1], sol.u[end]
            # every committed copy's ΔH was exact for the state it was committed to: a retry
            # re-evaluates against the winners' update, so no stale ΔH reaches a commit
            @test sol.stats.accepted_ΔH == H(u) - H(u0)
            @test abs(H(u) - H(u0)) > 100                                       # non-vacuous
            @test u.cell.volume == recount(u)
        end
    end

    @testset "counts add up" begin
        # an independent tally of the commits through the model's commit hook (host loops:
        # a 30² lattice runs each color as one workgroup)
        ncommit = Ref(0)
        counting = CPMFunction(gg_delta_H; temperature = gg_temperature,
            commit! = (st, p, prop, ctx) -> (ncommit[] += 1; commit_volume!(st, p, prop, ctx)))
        cprob = PottsProblem(counting, initial_state(σ, kinds), lat, (0, 20), gg_params(); seed = 7)
        for r in (0, 2)
            ncommit[] = 0
            sol = solve(cprob, CheckerboardCPM(; proposal = Moore(1), retries = r, counts = true))
            s = sol.stats
            @test s.committed == ncommit[] > 0
            @test s.dropped >= 0
            # without retries an accepted copy either commits or is dropped (with retries a
            # rejected proposal can be left undecided too)
            r == 0 && @test s.accepted == s.committed + s.dropped
        end
        # not counted: -1, as before
        s = solve(cprob, CheckerboardCPM(; proposal = Moore(1))).stats
        @test (s.accepted, s.committed, s.dropped) == (-1, -1, -1)
        # merged ensemble totals keep the counts
        a = solve(remake(cprob; seed = 1), CheckerboardCPM(; counts = true)).stats
        b = solve(remake(cprob; seed = 2), CheckerboardCPM(; counts = true)).stats
        @test merge(a, b).committed == a.committed + b.committed
    end

    @testset "retries recover dropped copies" begin
        st(r) = solve(remake(prob; seed = 3), CheckerboardCPM(; proposal = Moore(1), retries = r, counts = true)).stats
        # every real proposal claims under retries, so a pass leaves more undecided than the
        # stock drops; more passes decide them
        s0, s2, s8 = st(0), st(2), st(8)
        @test s8.committed > 2 * s0.committed
        @test s8.dropped < s2.dropped / 3
        @test s8.launches == 9 * s0.launches                       # 1 + R passes per color
    end

    @testset "deterministic" begin
        for alg in (CheckerboardCPM(; retries = 2, colors = :replacement), CheckerboardCPM(; stride = 4, retries = 1))
            a = solve(remake(prob; seed = 9), alg).u[end]
            b = solve(remake(prob; seed = 9), alg).u[end]
            @test a.σ == b.σ
        end
    end

    @testset "colors drawn with replacement" begin
        # per MCS, each of C colors is visited Binomial(C, 1/C) times
        order = zeros(Int, 4)
        nm = 20_000
        visits = zeros(Int, 5)                                     # 0, 1, 2, 3, 4 visits
        for m in 1:nm
            CorePotts._color_order!(order, RNGKey(5), m, true)
            visits[count(==(1), order) + 1] += 1
        end
        p = [binomial(4, k) * 0.25^k * 0.75^(4 - k) for k in 0:4]
        expected = nm .* p
        chi2 = sum((visits[1:4] .- expected[1:4]) .^ 2 ./ expected[1:4]) +
               (visits[5] - expected[5])^2 / expected[5]
        @test chi2 < 18.5                                          # χ²(4) at p = 0.001
        # the permutation stays a permutation, and is the default's draw
        o1, o2 = zeros(Int, 9), zeros(Int, 9)
        CorePotts._color_order!(o1, RNGKey(5), 3, false)
        CorePotts._color_order!(o2, RNGKey(5), 3)
        @test sort(o1) == 1:9 && o1 == o2
        # a second visit of a color in one MCS draws afresh: its directions agree with the first
        # visit's at chance (1/8 for Moore(1)), not always (the negative control: one key)
        L = CorePotts._lid
        same(l0, l1) = mean(1:4000) do t
            bounded(draw(RNGKey(5), 3, t, CorePotts.STREAM_PROPOSAL, l0)[1], 8) ==
            bounded(draw(RNGKey(5), 3, t, CorePotts.STREAM_PROPOSAL, l1)[1], 8)
        end
        @test abs(same(L(0, 0), L(1, 0)) - 1 / 8) < 0.03
        @test same(L(1, 0), L(1, 0)) == 1
        # a retry keeps the direction (the same copy) and redraws acceptance and priority
        d0, d1 = draw(RNGKey(5), 3, 17, CorePotts.STREAM_PROPOSAL, L(0, 0)), draw(RNGKey(5), 3, 17, CorePotts.STREAM_PROPOSAL, L(0, 1))
        @test d0[2] != d1[2] && d0[3] != d1[3]
        # one MCS still proposes about N copies: as many sub-steps as colors
        integ = init(prob, CheckerboardCPM(; colors = :replacement); save_start = false)
        step!(integ)
        @test sum(integ.cache.visits) == length(integ.cache.colors)
    end

    @testset "stride" begin
        lat36 = Lattice((36, 36))
        σ36, k36 = blocks((36, 36), 5)
        p36 = PottsProblem(GG, initial_state(σ36, k36), lat36, (0, 5), gg_params())
        @test length(init(p36, CheckerboardCPM()).cache.colors) == 4
        @test length(init(p36, CheckerboardCPM(; stride = 3)).cache.colors) == 9
        @test length(init(p36, CheckerboardCPM(; stride = 6)).cache.colors) == 36
        # below the footprint's stride: refused (Moore(1) contact and proposal need 2)
        @test_throws ArgumentError init(p36, CheckerboardCPM(; stride = 1))
    end

    @testset "validation" begin
        @test_throws ArgumentError init(prob, CheckerboardCPM(; retries = 256))
        @test_throws ArgumentError init(prob, CheckerboardCPM(; retries = -1))
        @test_throws ArgumentError init(prob, CheckerboardCPM(; colors = :shuffled))
    end

    @testset "shared cells: exact accounting" begin
        # Copies of one pass have disjoint footprints, so their contact terms add; their volume
        # terms do not: k copies to one cell, net change D = Σδ, change H by Σ ΔH_i + λ(D² − k),
        # each ΔH_i taken against the volume before the pass. A commit hook tallies (pass, cell, δ)
        # (host loops: a 30² color is one workgroup, so the hooks run one at a time) and a
        # constraint hook marks a new pass (proposes run before the pass's commits).
        pass, proposing = Ref(0), Ref(false)
        tally = Dict{Tuple{Int, Int32}, Vector{Int}}()
        mark(st, p, prop, ctx) = (proposing[] || (pass[] += 1; proposing[] = true); true)
        function hook!(st, p, prop, ctx)
            proposing[] = false
            prop.old != 0 && push!(get!(tally, (pass[], prop.old), Int[]), -1)
            prop.new != 0 && push!(get!(tally, (pass[], prop.new), Int[]), 1)
            return commit_volume!(st, p, prop, ctx)
        end
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = mark, commit! = hook!,
            track = CorePotts.TrackDeltaH{Float64}())
        sprob = PottsProblem(f, initial_state(σ, kinds), lat, (0, 20), gg_params())
        λ = gg_params().λ
        for (seed, kw) in ((1, (;)), (2, (; colors = :replacement)), (3, (; stride = 3)))
            empty!(tally); pass[] = 0; proposing[] = false
            sol = solve(remake(sprob; seed), CheckerboardCPM(; proposal = Moore(1), cells = :shared, kw...))
            u0, u = sol.u[1], sol.u[end]
            cross = sum(λ * (sum(d)^2 - length(d)) for d in values(tally))
            @test sol.stats.accepted_ΔH + cross ≈ H(u) - H(u0) atol = 1e-6
            @test cross != 0                                   # copies to one cell did share a pass
            @test u.cell.volume == recount(u)
        end
        # negative control: the exclusive checkerboard never commits two copies to one cell in a
        # pass, so its correction is zero
        empty!(tally); pass[] = 0; proposing[] = false
        solve(remake(sprob; seed = 1), CheckerboardCPM(; proposal = Moore(1)))
        @test all(d -> length(d) == 1, values(tally))
    end

    @testset "shared cells: counts, determinism, refusals" begin
        s = solve(remake(prob; seed = 5), CheckerboardCPM(; cells = :shared, counts = true)).stats
        @test s.committed == s.accepted > 0 && s.dropped == 0        # nothing dropped
        a = solve(remake(prob; seed = 9), CheckerboardCPM(; cells = :shared, colors = :replacement)).u[end]
        b = solve(remake(prob; seed = 9), CheckerboardCPM(; cells = :shared, colors = :replacement)).u[end]
        @test a.σ == b.σ && a.cell.volume == b.cell.volume
        @test_throws ArgumentError init(prob, CheckerboardCPM(; cells = :shared, retries = 1))
        @test_throws ArgumentError init(prob, CheckerboardCPM(; cells = :locked))
        cl = CPMFunction(gg_delta_H; temperature = gg_temperature, claims = (st, p, prop, ctx) -> (Int32(1),))
        @test_throws ArgumentError init(PottsProblem(cl, initial_state(σ, kinds), lat, (0, 2), gg_params()),
            CheckerboardCPM(; cells = :shared))
    end

    @testset "retries with a Global veto" begin
        # the connectivity path (`propose_conn_body!`) with retries: cells stay in one piece
        # and the tracked ΔH stays exact
        post(st, p, prop, ctx, stage) = CorePotts.global_gains(st.σ, ctx, prop, Val(false)) ?
            CorePotts.global_keeps(st.σ, ctx, prop, Val(false), Val(2), Val(25), stage) : Int32(2)
        fc = CPMFunction(gg_delta_H; temperature = gg_temperature, track = CorePotts.TrackDeltaH{Float64}(),
            connectivity = CorePotts.ConnectivityHooks(; post, uses_global = true))
        cprob = PottsProblem(fc, initial_state(σ, kinds), lat, (0, 15), gg_params(); seed = 4)
        integ = init(cprob, CheckerboardCPM(; proposal = Moore(1), retries = 2, counts = true); save_start = false)
        pieces0 = first(CorePotts.recompute_pieces(σ, lat, Val(false), length(kinds)))
        u0 = current_state(integ)
        for _ in 1:15
            step!(integ)
        end
        u = current_state(integ)
        @test integ.stats.accepted_ΔH == H(u) - H(u0) && abs(H(u) - H(u0)) > 100
        @test all(first(CorePotts.recompute_pieces(u.σ, lat, Val(false), length(kinds))) .<= pieces0)
        @test u.cell.volume == recount(u)
        @test integ.stats.committed > 0
    end
end
