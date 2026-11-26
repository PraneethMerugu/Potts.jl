# CheckerboardCPM, the lockless block scheme: the
# layout, the stays, the copy counts, the serial pass and the lockless trackers. On the CPU
# the work items run one after another, so ΔH and every tracker are exact there; the device
# tests (gpu.jl) check the trackers after concurrent runs. The closeness to SequentialCPM is
# measured by `benchmark/kinetics.jl` and `benchmark/kinetics/`, not here; these tests pin
# correctness.

@testsetup module CP_checkerboard_passes
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates,
    linear_index, shift
# imports an earlier file made in the old single Main
using CorePotts: global_gains
using CorePotts: global_keeps
include("shared/gg_model.jl")
# PottsDevices: the device of the GPU group (test/shared/devices.jl)
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "devices.jl"))
include("shared/export_all.jl")
end

@testitem "checkerboard" setup = [CP_checkerboard_passes] tags = [
    :corepotts, :checkerboard_passes,
] begin
    @testset "checkerboard" begin
        lat = Lattice((30, 30))
        σ, kinds = blocks((30, 30), 5)
        tracked = CPMFunction(
            gg_delta_H; temperature = gg_temperature,
            track = CorePotts.TrackEnergyChange{Float64}()
        )
        prob = PottsProblem(tracked, initial_state(σ, kinds), lat, (0, 20), gg_params())
        H(u) = total_H(u, lat, prob.contact, gg_params())
        recount(u) = [count(==(c), u.ownership) for c in eachindex(kinds)]

        @testset "exact ΔH on the CPU" begin
            for kw in (
                        (;), (; region = 3), (; region = 4),
                        (; region = 5, switches = 5), (; region = 3, switches = 3),
                        (; region = 3, switches = 4), (; region = 1, parts = 3),
                        (; region = 2, parts = 3, switches = 2), (; parts = 2),
                    ),
                    seed in 1:2

                sol = solve(
                    remake(prob; seed),
                    CheckerboardCPM(; proposal = Moore(1), kw...)
                )
                u0, u = sol.u[1], sol.u[end]
                @test sol.stats.accepted_energy_change ≈ H(u) - H(u0) atol = 1.0e-6
                @test abs(H(u) - H(u0)) > 100
                @test u.cell.volume == recount(u)
            end
            a = solve(remake(prob; seed = 4), CheckerboardCPM(; region = 3)).u[end]
            b = solve(remake(prob; seed = 4), CheckerboardCPM(; region = 3)).u[end]
            # the CPU is deterministic
            @test a.ownership == b.ownership
        end

        @testset "defaults: about 64 phases per MCS" begin
            @test CorePotts.default_parts.((1, 2, 3)) == (64, 8, 4)
            l = init(prob, CheckerboardCPM()).cache.layout
            # Moore(1) contact: block 1 suffices
            @test l.k == 8 && l.base == (1, 1)
            l3 = init(
                PottsProblem(
                    GG, initial_state(blocks((12, 12, 12), 4)...),
                    Lattice((12, 12, 12)), (0, 1), gg_params()
                ),
                CheckerboardCPM()
            ).cache.layout
            @test l3.k == 4
        end

        @testset "layout covers every site once" begin
            # each site is (block, phase, u) for exactly one triple, and a draw picks u
            # uniformly
            for (dims, b, k) in (
                    ((30, 30), 3, 2), ((31, 17), 2, 2), ((12, 8, 6), 2, 2),
                    ((100, 100, 23), 3, 2), ((5, 9), 3, 2),
                    ((30, 30), 1, 4), ((31, 17), 1, 3), ((100, 100, 36), 1, 4),
                    ((13, 11, 7), 2, 3), ((500, 300), 1, 8), ((3, 2), 1, 8),
                )
                N = length(dims)
                l = CorePotts.BlockLayout(dims, b, k)
                hits = zeros(Int, dims)
                for blk in 1:CorePotts.nblocks(l), ph in 1:(k^N)
                    lo, side = CorePotts.block_region(l, blk, ph)
                    n = prod(side)
                    for u in 0:(n - 1)
                        hits[
                            CorePotts.block_site(
                                lo, side,
                                UInt32(u * cld(2^32, n))
                            )...,
                        ] += 1
                    end
                end
                @test all(==(1), hits)
            end
            l = CorePotts.BlockLayout((30, 30), 3)
            c = zeros(Int, 30, 30)
            for blk in 1:25, i in 1:900
                lo, side = CorePotts.block_region(l, blk, 1)
                c[
                    CorePotts.block_site(
                        lo, side, draw(
                            RNGKey(1), 1, blk, CorePotts.STREAM_BLOCK, i
                        )[3]
                    )...,
                ] += 1
            end
            f = filter(>(0), vec(c))
            # 100 per site of phase 1
            @test length(f) == 225 && maximum(abs.(f .- 100)) < 50
            # a stay makes n / s attempts: exactly n with one switch, n / s on average
            # otherwise
            rs = [draw(RNGKey(2), 1, i, CorePotts.STREAM_BLOCK, 0)[1] for i in 1:20_000]
            @test all(r -> CorePotts._stay_attempts(4, 1, r) == 4, rs)
            @test all(r -> CorePotts._stay_attempts(9, 4, r) in (2, 3), rs)
            @test abs(sum(r -> CorePotts._stay_attempts(9, 4, r), rs) / 20_000 - 9 / 4) <
                0.02
            # block numbers and coordinates are inverse (first axis fastest)
            for dims in ((30, 30), (31, 17, 9)), k in (2, 3)
                l = CorePotts.BlockLayout(dims, 1, k)
                @test all(
                    blk -> CorePotts.block_index(l, CorePotts.block_coords(l, blk)) == blk,
                    1:CorePotts.nblocks(l)
                )
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
            # SequentialCPM's option only
            @test_throws MethodError CheckerboardCPM(; skip_interior = true)
            @test repr(CheckerboardCPM()) == "CheckerboardCPM()"
            @test repr(CheckerboardCPM(; parts = 4, threads = false)) ==
                "CheckerboardCPM(; parts = 4, threads = false)"
        end

        @testset "invalid settings" begin
            # below the footprint
            @test_throws ArgumentError init(prob, CheckerboardCPM(; region = 0))
            @test_throws ArgumentError init(prob, CheckerboardCPM(; parts = 1))
            @test_throws ArgumentError init(
                prob,
                CheckerboardCPM(; region = 3, switches = 0)
            )
            # 2^16 phases per MCS
            @test_throws ArgumentError init(
                prob,
                CheckerboardCPM(; parts = 2, switches = 2^14)
            )
        end

        # a `Global` veto: the gaining side local, the losing side searched in a window of 2
        # or exactly
        function post_w(st, p, prop, ctx, stage)
            if CorePotts.global_gains(st.ownership, ctx, prop, Val(false))
                return CorePotts.global_keeps(
                    st.ownership, ctx, prop, Val(false), Val(2), Val(25), stage
                )
            else
                return Int32(2)
            end
        end
        function post_x(st, p, prop, ctx, stage)
            if CorePotts.global_gains(st.ownership, ctx, prop, Val(false))
                return CorePotts.global_keeps(
                    st.ownership, ctx, prop, Val(false), Val(nothing), Val(0), stage
                )
            else
                return Int32(2)
            end
        end
        vetoes = (
            (
                "window 2",
                CorePotts.ConnectivityHooks(;
                    post = post_w, uses_global = true,
                    window = 2
                ),
            ),
            (
                "exact",
                CorePotts.ConnectivityHooks(;
                    post = post_x, uses_global = true,
                    exact_veto = true
                ),
            ),
        )

        @testset "Global veto ($label)" for (label, hooks) in vetoes
            fc = CPMFunction(
                gg_delta_H; temperature = gg_temperature,
                track = CorePotts.TrackEnergyChange{Float64}(),
                connectivity = hooks
            )
            cprob = PottsProblem(
                fc, initial_state(σ, kinds), lat, (0, 15), gg_params(); seed = 4
            )
            integ = init(cprob, CheckerboardCPM(; proposal = Moore(1)); save_start = false)
            l = integ.cache.layout
            r, w = CorePotts.reach(fc.footprint, integ.ctx.proposal)
            # the window is inside the spacing
            @test (l.k - 1) * l.box[1] >= max(r, hooks.window) + w
            @test CorePotts._serial_pass(integ.cache.serial, fc) == hooks.exact_veto
            pieces0 = first(CorePotts.recompute_pieces(σ, lat, Val(false), length(kinds)))
            u0 = current_state(integ)
            for _ in 1:15
                step!(integ)
            end
            u = current_state(integ)
            @test integ.stats.accepted_energy_change ≈ H(u) - H(u0) atol = 1.0e-6
            @test abs(H(u) - H(u0)) > 100
            @test all(
                first(
                    CorePotts.recompute_pieces(
                        u.ownership, lat, Val(false),
                        length(kinds)
                    )
                ) .<=
                    pieces0
            )   # no cell splits
            @test u.cell.volume == recount(u)
            @test integ.stats.committed > 0
        end

        @testset "lockless moments re-center once per MCS" begin
            function commit!(st, p, prop, ctx)
                commit_volume!(st, p, prop, ctx)
                return commit_moments!(st.cell, ctx, prop)
            end
            fm = CPMFunction(gg_delta_H; temperature = gg_temperature, commit!)
            mprob = PottsProblem(
                fm, initial_state(σ, kinds; cell = init_moments(σ, lat, length(kinds))),
                lat, (0, 10),
                gg_params(); seed = 3
            )
            integ = init(mprob, CheckerboardCPM(); save_start = false)
            @test CorePotts._lockless(integ.ctx)
            for _ in 1:10
                step!(integ)
                u = current_state(integ)
                ref = init_moments(Array(u.ownership), lat, length(kinds))
                for c in eachindex(kinds)
                    @test all(
                        isapprox.(
                            centroid(u.cell, lat, c), centroid(
                                merge(
                                    ref, (;
                                        volume = u.cell.volume,
                                    )
                                ), lat, c
                            );
                            atol = 1.0e-9
                        )
                    )
                end
            end
            # the sequential form is unchanged: a context without `lockless` re-centers per
            # copy
            @test !CorePotts._lockless(init(mprob, SequentialCPM()).ctx)
        end

        @testset "threaded CPU phases" begin
            # `threads = true`: each phase one KA launch (any thread count, any phase size);
            # trackers stay exact, a Global veto without window goes through the host serial
            # pass
            # 900 sites: inline
            @test init(prob, CheckerboardCPM()).cache.inline
            @test init(prob, CheckerboardCPM(; threads = false)).cache.inline
            @test_throws ArgumentError init(prob, CheckerboardCPM(; threads = :many))
            integ = init(
                prob, CheckerboardCPM(; proposal = Moore(1), threads = true);
                save_start = false
            )
            nb = integ.cache.layout.nblocks
            @test !integ.cache.inline &&
                integ.cache.groupsize == (nb[1], cld(nb[2], Threads.nthreads()))
            u0 = current_state(integ)
            for _ in 1:15
                step!(integ)
            end
            u = current_state(integ)
            @test u.cell.volume == recount(u)
            @test integ.stats.committed == integ.stats.accepted > 0
            Threads.nthreads() == 1 &&
                # one task: in order
                @test integ.stats.accepted_energy_change ≈ H(u) - H(u0) atol = 1.0e-6
            fc = CPMFunction(
                gg_delta_H; temperature = gg_temperature,
                connectivity = vetoes[2][2]
            )
            ci = init(
                PottsProblem(
                    fc, initial_state(σ, kinds), lat, (0, 15), gg_params(); seed = 4
                ),
                CheckerboardCPM(; proposal = Moore(1), threads = true); save_start = false
            )
            pieces0 = first(CorePotts.recompute_pieces(σ, lat, Val(false), length(kinds)))
            for _ in 1:15
                step!(ci)
            end
            uc = current_state(ci)
            @test all(
                first(
                    CorePotts.recompute_pieces(
                        uc.ownership, lat, Val(false),
                        length(kinds)
                    )
                ) .<=
                    pieces0
            )
            @test uc.cell.volume == recount(uc) && all(iszero, ci.cache.serial.count)
            # `:auto` in a threaded ensemble runs inline (its trajectories hold the
            # threads); in a serial ensemble or a plain run the size rule decides (here:
            # threaded, `inline_max_blocks = 0`)
            threaded = CheckerboardCPM(; inline_max_blocks = 0)
            seen = Channel{Bool}(Inf)
            cb = DiscreteCallback(
                (u, t, i) -> t == 1, i -> put!(seen, i.cache.inline);
                save_positions = (false, false)
            )
            function inline_in(e)
                solve(
                    EnsembleProblem(remake(prob; tspan = (0, 2))), threaded, e;
                    trajectories = 3,
                    callback = cb
                )
                return [take!(seen) for _ in 1:3]
            end
            @test all(inline_in(EnsembleThreads()))
            @test inline_in(EnsembleSerial()) == fill(Threads.nthreads() == 1, 3)
            @test init(prob, threaded).cache.inline == (Threads.nthreads() == 1)
        end

        @testset "on-copy cell writes" begin
            # a counter that reads its own value adds the change on the checkerboard; a
            # plain value is stored
            a = Int32[5, 0]
            lock = (; lockless = true)
            CorePotts.oncopy_cell!(a, 1, a[1] + 1, a[1], lock)
            # computed from a stale 5: adds 2
            CorePotts.oncopy_cell!(a, 1, 7, 5, lock)
            @test a[1] == 8
            # elsewhere: stored
            CorePotts.oncopy_cell!(a, 1, 3, a[1], (;))
            @test a[1] == 3
            # the medium: nothing
            CorePotts.oncopy_cell!(a, 0, 9, 0, lock)
            @test a == Int32[3, 0]
            b = [false, false]
            # not numeric: stored
            CorePotts.oncopy_cell!(b, 2, true, false, lock)
            @test b == [false, true]
        end
    end
end

@testitem "checkerboard: the tuning keywords" setup = [CP_checkerboard_passes] tags = [
    :corepotts, :checkerboard_passes,
] begin
    @testset "checkerboard: the tuning keywords" begin
        lat = Lattice((30, 30))
        σ, kinds = blocks((30, 30), 5)
        prob = PottsProblem(GG, initial_state(σ, kinds), lat, (0, 2), gg_params())
        alg = CheckerboardCPM()
        @test alg.inline_max_blocks > 0 && alg.fused_lifecycle_max_sites > 0 &&
            alg.fused_lifecycle_max_cells > 0
        # printed as the keyword call that rebuilds it, defaults left out
        @test repr(alg) == "CheckerboardCPM()"
        tuned = CheckerboardCPM(; inline_max_blocks = 7, fused_lifecycle_max_cells = 3)
        @test eval(Meta.parse(repr(tuned))) == tuned
        # a negative limit is refused when the algorithm is built, naming the keyword
        for k in (
                :inline_max_blocks, :fused_lifecycle_max_sites,
                :fused_lifecycle_max_cells,
            )
            @test_throws ArgumentError CheckerboardCPM(; (k => -1,)...)
        end
        # a phase with at most `inline_max_blocks` work items runs inline; 0 sends every
        # phase to the threads (one thread runs everything inline)
        @test init(prob, CheckerboardCPM(; inline_max_blocks = 10^6)).cache.inline
        @test init(prob, CheckerboardCPM(; inline_max_blocks = 0)).cache.inline ==
            (Threads.nthreads() == 1)
        for kw in (
                (; inline_max_blocks = -1), (; fused_lifecycle_max_sites = -1),
                (; fused_lifecycle_max_cells = -1),
            )
            @test_throws ArgumentError init(prob, CheckerboardCPM(; kw...))
        end
    end
end

@testitem "checkerboard: launch arguments follow the integrator" setup = [
    CP_checkerboard_passes,
] tags = [:corepotts, :checkerboard_passes] begin
    @testset "checkerboard: launch arguments follow the integrator" begin
        lat = Lattice((30, 30))
        σ, kinds = blocks((30, 30), 5)
        u0 = initial_state(σ, kinds)
        prob = PottsProblem(GG, u0, lat, (0, 6), gg_params(); seed = 2)
        alg = CheckerboardCPM(; threads = false)            # reproducible
        run(integ, n) = (foreach(_ -> step!(integ), 1:n); copy(integ.state.ownership))
        # the converted arguments are the integrator's own state and context
        integ = init(prob, alg)
        @test integ.cache.args.st === integ.state && integ.cache.args.ctx === integ.ctx
        # a copy steps its own arrays, as the original does
        c = deepcopy(integ)
        @test c.cache.args.st === c.state && c.cache.args.st !== integ.state
        @test run(c, 3) == run(init(prob, alg), 3)
        # a parameter write replaces `p`: the next sweep uses the new value
        cold = merge(gg_params(), (; T = 0.5))
        ref = run(init(remake(prob; p = cold), alg), 3)
        integ.p = cold
        @test run(integ, 3) == ref
        @test ref != run(init(prob, alg), 3)
        # `reinit!` with another state continues as a fresh run from it
        integ = init(prob, alg)
        other = init(remake(prob; seed = 9), alg)
        run(other, 2)
        u2 = current_state(other)
        ref = run(init(remake(prob; u0 = u2), alg), 3)
        reinit!(integ, u2)
        @test run(integ, 3) == ref
        # a state write (`set_state!`) is seen by the next sweep
        flip = [k == 1 ? 2 : 1 for k in kinds]
        ref = run(init(remake(prob; u0 = initial_state(σ, flip)), alg), 3)
        integ = init(prob, alg)
        kind = integ.state.cell.kind
        CorePotts.SymbolicIndexingInterface.set_state!(
            integ, convert(Vector{eltype(kind)}, flip), StateIndex(:cell, :kind)
        )
        @test run(integ, 3) == ref
        @test ref != run(init(prob, alg), 3)                # the flip changes the run
        # a run restored from a checkpoint continues as the original does
        integ = init(prob, alg)
        run(integ, 2)
        rest = init(prob, alg; checkpoint = checkpoint(integ))
        @test run(rest, 3) == run(integ, 3)
    end
end

@testitem "checkerboard: a reconversion moves the sweep to other arrays" setup = [
    CP_checkerboard_passes,
] tags = [:corepotts, :checkerboard_passes] begin
    @testset "checkerboard: a reconversion moves the sweep to other arrays" begin
        lat = Lattice((30, 30))
        σ, kinds = blocks((30, 30), 5)
        prob = PottsProblem(GG, initial_state(σ, kinds), lat, (0, 6), gg_params(); seed = 2)
        alg = CheckerboardCPM(; threads = false)            # reproducible
        # a state with arrays of its own (on the CPU a conversion keeps the arrays, so only
        # the identity check makes the sweep write these)
        function other_state()
            o = init(remake(prob; seed = 9), alg)
            foreach(_ -> step!(o), 1:2)
            return deepcopy(o.state)
        end
        sweep!(integ) = CorePotts.checkerboard_mcs!(integ.cache, integ.p, integ.t)
        integ = init(prob, alg)
        st = other_state()
        old, new = copy(integ.state.ownership), copy(st.ownership)
        CorePotts.sync_launch!(
            integ.cache, merge(CorePotts._sweep_objects(integ), (; st))
        )
        @test integ.cache.args.st === st && integ.cache.launch.st === st
        sweep!(integ)
        @test st.ownership != new                           # the sweep wrote the new arrays
        @test integ.state.ownership == old                  # and left the old ones
        # negative control: with no reconversion the sweep writes the stale arrays
        integ = init(prob, alg)
        st = other_state()
        old, new = copy(integ.state.ownership), copy(st.ownership)
        sweep!(integ)
        @test st.ownership == new && integ.state.ownership != old
    end
end

@testitem "checkerboard: a step from another task" setup = [
    CP_checkerboard_passes,
] tags = [:corepotts, :checkerboard_passes, :device] begin
    @testset "checkerboard: a step from another task" begin
        backend = PottsDevices.on_device() ? PottsDevices.device_backend() :
            CorePotts.KernelAbstractions.CPU()
        σ, kinds = blocks((48, 48), 6)
        # no volume term: the energy change reads no value another work item of the phase
        # writes, so the lockless device run is reproducible
        p = merge(gg_params(Float32), (; λ = 0.0f0))
        prob = PottsProblem(GG, initial_state(σ, kinds), Lattice((48, 48)), (0, 6), p)
        alg = CheckerboardCPM()
        run!(integ) = (foreach(_ -> step!(integ), 1:6); Array(integ.state.ownership))
        ref = run!(init(prob, alg; backend))
        # `init` in one task, the steps in another
        integ = fetch(Threads.@spawn init(prob, alg; backend))
        task = integ.cache.task
        @test task !== current_task()
        @test run!(integ) == ref && ref != σ
        @test integ.cache.task === current_task()           # converted again in this task
    end
end
