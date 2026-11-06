# CheckerboardCPM, the lockless block scheme (P6.0bl, research/checkerboard-kinetics.md): the
# layout, the stays, the copy counts, the serial pass and the lockless trackers. On the CPU the
# work items run one after another, so ΔH and every tracker are exact there; the device tests
# (gpu.jl) check the trackers after concurrent runs. The closeness to SequentialCPM is measured
# by `benchmark/kinetics.jl` and `benchmark/kinetics/`, not here; these tests pin correctness.

@testset "checkerboard (P6.0bl)" begin
    lat = Lattice((30, 30))
    σ, kinds = blocks((30, 30), 5)
    tracked = CPMFunction(gg_delta_H; temperature = gg_temperature, track = CorePotts.TrackDeltaH{Float64}())
    prob = PottsProblem(tracked, initial_state(σ, kinds), lat, (0, 20), gg_params())
    H(u) = total_H(u, lat, prob.contact, gg_params())
    recount(u) = [count(==(c), u.σ) for c in eachindex(kinds)]

    @testset "exact ΔH on the CPU" begin
        for kw in ((;), (; region = 3), (; region = 4), (; region = 5, switches = 5), (; region = 3, switches = 3),
                (; region = 3, switches = 4), (; region = 1, parts = 3), (; region = 2, parts = 3, switches = 2), (; parts = 2)),
            seed in 1:2
            sol = solve(remake(prob; seed), CheckerboardCPM(; proposal = Moore(1), kw...))
            u0, u = sol.u[1], sol.u[end]
            @test sol.stats.accepted_ΔH ≈ H(u) - H(u0) atol = 1e-6
            @test abs(H(u) - H(u0)) > 100
            @test u.cell.volume == recount(u)
        end
        a = solve(remake(prob; seed = 4), CheckerboardCPM(; region = 3)).u[end]
        b = solve(remake(prob; seed = 4), CheckerboardCPM(; region = 3)).u[end]
        @test a.σ == b.σ                                   # the CPU is deterministic
    end

    @testset "defaults: about 64 phases per MCS" begin
        @test CorePotts.default_parts.((1, 2, 3)) == (64, 8, 4)
        l = init(prob, CheckerboardCPM()).cache.layout
        @test l.k == 8 && l.base == (1, 1)                 # Moore(1) contact: block 1 suffices
        l3 = init(PottsProblem(GG, initial_state(blocks((12, 12, 12), 4)...), Lattice((12, 12, 12)), (0, 1), gg_params()),
            CheckerboardCPM()).cache.layout
        @test l3.k == 4
    end

    @testset "layout covers every site once" begin
        # each site is (block, phase, u) for exactly one triple, and a draw picks u uniformly
        for (dims, b, k) in (((30, 30), 3, 2), ((31, 17), 2, 2), ((12, 8, 6), 2, 2), ((100, 100, 23), 3, 2), ((5, 9), 3, 2),
            ((30, 30), 1, 4), ((31, 17), 1, 3), ((100, 100, 36), 1, 4), ((13, 11, 7), 2, 3), ((500, 300), 1, 8), ((3, 2), 1, 8))
            N = length(dims)
            l = CorePotts.BlockLayout(dims, b, k)
            hits = zeros(Int, dims)
            for blk in 1:CorePotts.nblocks(l), ph in 1:(k^N)
                lo, side = CorePotts.block_region(l, blk, ph)
                n = prod(side)
                for u in 0:(n - 1)
                    hits[CorePotts.block_site(lo, side, UInt32(u * cld(2^32, n)))...] += 1
                end
            end
            @test all(==(1), hits)
        end
        l = CorePotts.BlockLayout((30, 30), 3)
        c = zeros(Int, 30, 30)
        for blk in 1:25, i in 1:900
            lo, side = CorePotts.block_region(l, blk, 1)
            c[CorePotts.block_site(lo, side, draw(RNGKey(1), 1, blk, CorePotts.STREAM_BLOCK, i)[3])...] += 1
        end
        f = filter(>(0), vec(c))
        @test length(f) == 225 && maximum(abs.(f .- 100)) < 50     # 100 per site of phase 1
        # a stay makes n / s attempts: exactly n with one switch, n / s on average otherwise
        rs = [draw(RNGKey(2), 1, i, CorePotts.STREAM_BLOCK, 0)[1] for i in 1:20_000]
        @test all(r -> CorePotts._stay_attempts(4, 1, r) == 4, rs)
        @test all(r -> CorePotts._stay_attempts(9, 4, r) in (2, 3), rs)
        @test abs(sum(r -> CorePotts._stay_attempts(9, 4, r), rs) / 20_000 - 9 / 4) < 0.02
        # block numbers and coordinates are inverse (first axis fastest)
        for dims in ((30, 30), (31, 17, 9)), k in (2, 3)
            l = CorePotts.BlockLayout(dims, 1, k)
            @test all(blk -> CorePotts.block_index(l, CorePotts.block_coords(l, blk)) == blk, 1:CorePotts.nblocks(l))
        end
    end

    @testset "counts" begin
        s = solve(remake(prob; seed = 5), CheckerboardCPM()).stats
        @test s.committed == s.accepted > 0
        # one counter per block, folded into the stats and zeroed at the read points
        integ = init(remake(prob; seed = 5), CheckerboardCPM(); save_start = false)
        step!(integ)
        current_state(integ)                                     # a read point
        a1 = integ.stats.accepted
        @test a1 > 0 && all(iszero, integ.cache.cnt)
        step!(integ)
        current_state(integ)
        @test integ.stats.accepted > a1
    end

    @testset "keywords and printing" begin
        @test_throws MethodError CheckerboardCPM(; skip_interior = true)   # SequentialCPM's option only
        @test repr(CheckerboardCPM()) == "CheckerboardCPM()"
        @test repr(CheckerboardCPM(; parts = 4, threads = false)) == "CheckerboardCPM(; parts = 4, threads = false)"
    end

    @testset "invalid settings" begin
        @test_throws ArgumentError init(prob, CheckerboardCPM(; region = 0))       # below the footprint
        @test_throws ArgumentError init(prob, CheckerboardCPM(; parts = 1))
        @test_throws ArgumentError init(prob, CheckerboardCPM(; region = 3, switches = 0))
        @test_throws ArgumentError init(prob, CheckerboardCPM(; parts = 2, switches = 2^14))   # 2^16 phases per MCS
    end

    # a `Global` veto: the gaining side local, the losing side searched in a window of 2 or exactly
    post_w(st, p, prop, ctx, stage) = CorePotts.global_gains(st.σ, ctx, prop, Val(false)) ?
        CorePotts.global_keeps(st.σ, ctx, prop, Val(false), Val(2), Val(25), stage) : Int32(2)
    post_x(st, p, prop, ctx, stage) = CorePotts.global_gains(st.σ, ctx, prop, Val(false)) ?
        CorePotts.global_keeps(st.σ, ctx, prop, Val(false), Val(nothing), Val(0), stage) : Int32(2)
    vetoes = (("window 2", CorePotts.ConnectivityHooks(; post = post_w, uses_global = true, window = 2)),
        ("exact", CorePotts.ConnectivityHooks(; post = post_x, uses_global = true, exact_veto = true)))

    @testset "Global veto ($label)" for (label, hooks) in vetoes
        fc = CPMFunction(gg_delta_H; temperature = gg_temperature, track = CorePotts.TrackDeltaH{Float64}(),
            connectivity = hooks)
        cprob = PottsProblem(fc, initial_state(σ, kinds), lat, (0, 15), gg_params(); seed = 4)
        integ = init(cprob, CheckerboardCPM(; proposal = Moore(1)); save_start = false)
        l = integ.cache.layout
        r, w = CorePotts.reach(fc.footprint, integ.ctx.proposal)
        @test (l.k - 1) * l.box[1] >= max(r, hooks.window) + w      # the window is inside the spacing
        @test CorePotts._serial_pass(integ.cache.serial, fc) == hooks.exact_veto
        pieces0 = first(CorePotts.recompute_pieces(σ, lat, Val(false), length(kinds)))
        u0 = current_state(integ)
        for _ in 1:15
            step!(integ)
        end
        u = current_state(integ)
        @test integ.stats.accepted_ΔH ≈ H(u) - H(u0) atol = 1e-6
        @test abs(H(u) - H(u0)) > 100
        @test all(first(CorePotts.recompute_pieces(u.σ, lat, Val(false), length(kinds))) .<= pieces0)   # no cell splits
        @test u.cell.volume == recount(u)
        @test integ.stats.committed > 0
    end

    @testset "lockless moments re-center once per MCS" begin
        commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx, prop))
        fm = CPMFunction(gg_delta_H; temperature = gg_temperature, commit!)
        mprob = PottsProblem(fm, initial_state(σ, kinds; cell = init_moments(σ, lat, length(kinds))), lat, (0, 10),
            gg_params(); seed = 3)
        integ = init(mprob, CheckerboardCPM(); save_start = false)
        @test CorePotts._lockless(integ.ctx)
        for _ in 1:10
            step!(integ)
            u = current_state(integ)
            ref = init_moments(Array(u.σ), lat, length(kinds))
            for c in eachindex(kinds)
                @test all(isapprox.(centroid(u.cell, lat, c), centroid(merge(ref, (; volume = u.cell.volume)), lat, c);
                    atol = 1e-9))
            end
        end
        # the sequential form is unchanged: a context without `lockless` re-centers per copy
        @test !CorePotts._lockless(init(mprob, SequentialCPM()).ctx)
    end

    @testset "threaded CPU phases" begin
        # `threads = true`: each phase one KA launch (any thread count, any phase size); trackers
        # stay exact, a Global veto without window goes through the host serial pass
        @test init(prob, CheckerboardCPM()).cache.inline              # 900 sites: inline
        @test init(prob, CheckerboardCPM(; threads = false)).cache.inline
        @test_throws ArgumentError init(prob, CheckerboardCPM(; threads = :many))
        integ = init(prob, CheckerboardCPM(; proposal = Moore(1), threads = true); save_start = false)
        nb = integ.cache.layout.nblocks
        @test !integ.cache.inline && integ.cache.groupsize == (nb[1], cld(nb[2], Threads.nthreads()))
        u0 = current_state(integ)
        for _ in 1:15
            step!(integ)
        end
        u = current_state(integ)
        @test u.cell.volume == recount(u)
        @test integ.stats.committed == integ.stats.accepted > 0
        Threads.nthreads() == 1 && @test integ.stats.accepted_ΔH ≈ H(u) - H(u0) atol = 1e-6   # one task: in order
        fc = CPMFunction(gg_delta_H; temperature = gg_temperature, connectivity = vetoes[2][2])
        ci = init(PottsProblem(fc, initial_state(σ, kinds), lat, (0, 15), gg_params(); seed = 4),
            CheckerboardCPM(; proposal = Moore(1), threads = true); save_start = false)
        pieces0 = first(CorePotts.recompute_pieces(σ, lat, Val(false), length(kinds)))
        for _ in 1:15
            step!(ci)
        end
        uc = current_state(ci)
        @test all(first(CorePotts.recompute_pieces(uc.σ, lat, Val(false), length(kinds))) .<= pieces0)
        @test uc.cell.volume == recount(uc) && all(iszero, ci.cache.serial.count)
        # `:auto` in a threaded ensemble runs inline (its trajectories hold the threads); in a
        # serial ensemble or a plain run the size rule decides (here: threaded, grain 0)
        grain = CorePotts.BLOCK_GRAIN[]
        CorePotts.BLOCK_GRAIN[] = 0
        try
            seen = Channel{Bool}(Inf)
            cb = DiscreteCallback((u, t, i) -> t == 1, i -> put!(seen, i.cache.inline); save_positions = (false, false))
            inline_in(e) = (solve(EnsembleProblem(remake(prob; tspan = (0, 2))), CheckerboardCPM(), e; trajectories = 3,
                callback = cb); [take!(seen) for _ in 1:3])
            @test all(inline_in(EnsembleThreads()))
            @test inline_in(EnsembleSerial()) == fill(Threads.nthreads() == 1, 3)
            @test init(prob, CheckerboardCPM()).cache.inline == (Threads.nthreads() == 1)
        finally
            CorePotts.BLOCK_GRAIN[] = grain
        end
    end

    @testset "on-copy cell writes" begin
        # a counter that reads its own value adds the change on the checkerboard; a plain value is stored
        a = Int32[5, 0]
        lock = (; lockless = true)
        CorePotts.oncopy_cell!(a, 1, a[1] + 1, a[1], lock)
        CorePotts.oncopy_cell!(a, 1, 7, 5, lock)                     # computed from a stale 5: adds 2
        @test a[1] == 8
        CorePotts.oncopy_cell!(a, 1, 3, a[1], (;))                    # elsewhere: stored
        @test a[1] == 3
        CorePotts.oncopy_cell!(a, 0, 9, 0, lock)                      # the medium: nothing
        @test a == Int32[3, 0]
        b = [false, false]
        CorePotts.oncopy_cell!(b, 2, true, false, lock)               # not numeric: stored
        @test b == [false, true]
    end
end
