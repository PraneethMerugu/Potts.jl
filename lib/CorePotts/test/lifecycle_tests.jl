# Lifecycle: division, removal, transition, id reuse, capacity (ROADMAP M2.8).

@testsetup module CP_lifecycle
using Test, CorePotts, StaticArrays, Statistics, Random
using Base.CoreLogging: ConsoleLogger, Warn, with_logger
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
include("shared/geometry.jl")
include("shared/lifecycle.jl")
include("shared/export_all.jl")
end

@testitem "lifecycle" setup = [CP_lifecycle] tags = [:corepotts, :lifecycle] begin
@testset "lifecycle" begin
    @testset "division planes (2D, across the periodic seam)" begin
        lat = Lattice((40, 40))
        σ = zeros(Int32, 40, 40); σ[1:20, 1:6] .= 1
        σ = circshift(σ, (-5, -2))                          # straddles both seams
        for (normal, sizes) in ((along_minor_axis, (10 * 6, 10 * 6)), (along_major_axis, (20 * 3, 20 * 3)))
            sol = run_lifecycle(σ, [1], lat, Lifecycle(divide_at(0); normal))
            u = sol.u[end]
            @test sort(u.cell.volume[1:2]) == collect(sizes)
            @test u.cell.generation[2] == 1 && u.cell.kind[2] == 1
            @test sol.stats.lifecycle.divisions == 1
            for c in 1:2                                    # each half is a clean box
                μ, C = brute_geometry(u.ownership, lat, c)
                @test all(isapprox.(centroid(u.cell, lat, c), μ; atol = 1e-9))
            end
        end
        sol = run_lifecycle(σ, [1], lat, Lifecycle(divide_at(0); normal = random_plane))
        @test sum(sol.u[end].cell.volume) == 120 && all(>(0), sol.u[end].cell.volume[1:2])
    end

    @testset "division plane (3D box)" begin
        lat = Lattice((20, 20, 20))
        σ = zeros(Int32, 20, 20, 20); σ[3:14, 5:10, 5:10] .= 1
        u = run_lifecycle(σ, [1], lat, Lifecycle(divide_at(0))).u[end]
        @test u.cell.volume[1:2] == [216, 216]
        halves = (Set(CartesianIndices((3:8, 5:10, 5:10))), Set(CartesianIndices((9:14, 5:10, 5:10))))
        @test Set(Set(findall(==(c), u.ownership)) for c in 1:2) == Set(halves)
    end

    @testset "removal and transition" begin
        σ, kinds = blocks((30, 30), 5)
        lat = Lattice((30, 30))
        remove2(st, p, ctx, key, mcs, c) = mcs == 2 && st.cell.kind[c] == 2 ? EVENT_REMOVE : EVENT_NONE
        u = run_lifecycle(σ, kinds, lat, Lifecycle(remove2); tspan = (0, 4)).u[end]
        @test all(u.cell.volume[i] == 0 for i in eachindex(kinds) if kinds[i] == 2)
        @test all(u.ownership[i] == 0 || kinds[u.ownership[i]] == 1 for i in eachindex(u.ownership))
        flip(st, p, ctx, key, mcs, c) = mcs == 1 ? EVENT_TRANSITION : EVENT_NONE
        u = run_lifecycle(σ, kinds, lat, Lifecycle(flip; kind = (st, p, ctx, key, mcs, c) -> Int32(3 - st.cell.kind[c])); tspan = (0, 2)).u[end]
        @test u.cell.kind[1:length(kinds)] == 3 .- kinds
    end

    @testset "id reuse, generations, capacity deferral, daughter state" begin
        lat = Lattice((30, 30))
        σ = zeros(Int32, 30, 30); σ[3:8, 3:8] .= 1; σ[15:24, 15:20] .= 2
        # remove cell 1 at MCS 0, divide cell 2 at MCS 1 → daughter reuses id 1, generation 2
        ev(st, p, ctx, key, mcs, c) = (mcs == 0 && c == 1) ? EVENT_REMOVE :
                                      (mcs == 1 && c == 2) ? EVENT_DIVIDE : EVENT_NONE
        halve!(st, p, ctx, key, mcs, parent, daughter) =
            (st.cell.target[parent] /= 2; st.cell.target[daughter] = st.cell.target[parent]; nothing)
        sol = run_lifecycle(σ, [1, 2], lat, Lifecycle(ev; divide! = halve!); capacity = 2,
            tspan = (0, 2), cell = (; target = [36.0, 60.0], tag = [7.0, 9.0]))
        u = sol.u[end]
        @test u.cell.volume == [30, 30]
        @test u.cell.generation == [2, 1]
        @test u.cell.kind == [2, 2]
        @test u.cell.target == [30.0, 30.0]          # rule applied after the default Copy
        @test u.cell.tag == [9.0, 9.0]               # copied from the parent
        # no free id: the division is deferred and counted
        sol = run_lifecycle(σ, [1, 2], lat, Lifecycle(divide_at(0)); capacity = 2)
        @test sol.stats.lifecycle.deferred == 2 && sol.stats.lifecycle.divisions == 0
        @test sol.u[end].ownership == σ
    end

    @testset "growth and division keep every tracker exact ($(nameof(typeof(alg))))" for alg in (
            SequentialCPM(), CheckerboardCPM())
        lat = Lattice((48, 48))
        σ = zeros(Int32, 48, 48); σ[20:27, 20:27] .= 1
        grow!(st, p, ctx, key, mcs, c) = (@inbounds st.cell.target[c] += 1.0; nothing)
        big(st, p, ctx, key, mcs, c) = st.cell.volume[c] >= 80 ? EVENT_DIVIDE : EVENT_NONE
        reset!(st, p, ctx, key, mcs, parent, daughter) =
            (st.cell.target[parent] = 40.0; st.cell.target[daughter] = 40.0; nothing)
        function dH(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - @inbounds(st.cell.target[c]))^2
            return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
        end
        commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx, prop))
        st = lc_state(σ, [1], lat; capacity = 64, cell = (; target = [64.0]))
        f = CPMFunction(dH; commit!, temperature = gg_temperature,
            phases = Phases(before_mcs = (CellPhase(grow!),)),
            lifecycle = Lifecycle(big; divide! = reset!))
        sol = solve(PottsProblem(f, st, lat, (0, 120), gg_params()), alg)
        u = sol.u[end]
        live = findall(>(0), u.cell.volume)
        @test length(live) >= 4
        @test sol.stats.lifecycle.divisions >= 3
        @test u.cell.volume == [count(==(c), u.ownership) for c in 1:64]
        for c in live
            μ, C = brute_geometry(u.ownership, lat, c)
            @test all(isapprox.(centroid(u.cell, lat, c), μ; atol = 1e-9))
        end
    end
end
end

@testitem "rule-carrying events: the firing rule reaches the state rule; members take the root's" setup = [CP_lifecycle] tags = [:corepotts, :lifecycle] begin
@testset "rule-carrying events: the firing rule reaches the state rule; members take the root's" begin
    lat = Lattice((40, 40))
    # a lone cell 1 (rule 2) and a cluster {3 root, 4 member} (rule 5); cell 2 divides plain
    σ = zeros(Int32, 40, 40); σ[3:10, 3:10] .= 1; σ[3:10, 20:27] .= 2
    σ[20:35, 15:22] .= 3; σ[25:30, 17:20] .= 4
    cell = merge(init_moments(σ, lat, 4), init_clusters(σ, Int32[1, 2, 3, 3], lat))
    st = with_capacity(initial_state(σ, Int32[1, 1, 1, 1]; cell = merge(cell, (; x = zeros(4)))), 10)
    tr(st, p, ctx, key, mcs, c) = mcs != 0 ? EVENT_NONE : c == 1 ? CorePotts.ruled_event(EVENT_DIVIDE, 2) :
                                  c == 2 ? CorePotts.ruled_event(EVENT_DIVIDE, 1) :
                                  c == 3 ? CorePotts.ruled_event(EVENT_DIVIDE_CLUSTER, 5) :
                                  c == 4 ? CorePotts.ruled_event(EVENT_DIVIDE, 7) : EVENT_NONE     # ignored: its cluster divides
    seen = Dict{Int32, Int32}()
    rule!(st, p, ctx, key, mcs, parent, daughter, rule) = (seen[parent] = rule; st.cell.x[daughter] = rule; nothing)
    frozen(st, p, prop, ctx) = false
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen,
        lifecycle = Lifecycle(tr; divide! = rule!, rules = true))
    sol = solve(PottsProblem(f, st, lat, (0, 1), gg_params()), SequentialCPM())
    @test sol.stats.lifecycle.divisions == 4
    @test seen == Dict(Int32(1) => 2, Int32(2) => 1, Int32(3) => 5, Int32(4) => 5)
    u = sol.u[end]
    @test sort(u.cell.x[5:8]) == [1.0, 2.0, 5.0, 5.0]
    # the plain path: a 7-argument state rule, events without a rule
    plain(st, p, ctx, key, mcs, c) = mcs == 0 && c == 1 ? EVENT_DIVIDE : EVENT_NONE
    n = Ref(0)
    f7 = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen,
        lifecycle = Lifecycle(plain; divide! = (st, p, ctx, key, mcs, parent, daughter) -> (n[] += 1; nothing)))
    @test solve(PottsProblem(f7, st, lat, (0, 1), gg_params()), SequentialCPM()).stats.lifecycle.divisions == 1 && n[] == 1
end
end

@testitem "the frozen mask follows lifecycle events, callbacks and reinit! (P6.0d)" setup = [CP_lifecycle] tags = [:corepotts, :lifecycle] begin
@testset "the frozen mask follows lifecycle events, callbacks and reinit! (P6.0d)" begin
    S = 10
    before, after = 2:(S + 2), (S + 3):31       # saved u at t = 1 … S+1 and t = S+2 … 30
    @testset "transition into and out of the frozen kind ($(nameof(typeof(alg))), $(nameof(typeof(sys))))" for alg in (SequentialCPM(), CheckerboardCPM()),
                                                                                                             sys in (FrozenKind(2), HostFrozen(2))
        sol = solve(fk_problem(fk_flip(S); kind = fk_swap, sys), alg; saveat = 1)
        @test sol.retcode == ReturnCode.Success && sol.stats.lifecycle.transitions == 2
        @test sol.stats.refreshes == 1                           # the one event MCS
        @test Array(sol.u[end].cell.kind)[1:2] == [2, 1]
        @test fk_moved(sol, 1, before) >= length(before) ÷ 2
        @test fk_moved(sol, 2, before) == 0
        @test fk_moved(sol, 1, after) == 0                       # frozen from the next sweep on
        @test fk_moved(sol, 2, after) >= length(after) ÷ 2       # released
        @test frozen_sites(sol.prob, sol.u[end]) == fk_mask(sol.u[end], 2)
        # negative control: a static mask (no state-derived rule) does not follow
        ctl = solve(fk_problem(fk_flip(S); kind = fk_swap, sys = nothing), alg; saveat = 1)
        @test ctl.stats.refreshes == 0
        @test fk_moved(ctl, 1, after) >= length(after) ÷ 2
        @test fk_moved(ctl, 2, after) == 0
        @test frozen_sites(ctl.prob, ctl.u[end]) == ctl.prob.frozen
    end

    @testset "removal of a frozen cell: its sites become mobile; attempts follow ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        rm2(st, p, ctx, key, mcs, c) = mcs == S && c == 2 ? EVENT_REMOVE : EVENT_NONE
        sol = solve(fk_problem(rm2), alg)
        @test sol.stats.lifecycle.removals == 1
        # sweeps 0 … S use the old count, S+1 … 29 the whole lattice
        @test sol.stats.attempts == (S + 1) * (900 - 36) + (30 - S - 1) * 900
        quiet = solve(fk_problem((st, p, ctx, key, mcs, c) -> EVENT_NONE), alg)
        @test quiet.stats.attempts == 30 * (900 - 36)            # control: no event, no change
        @test quiet.stats.refreshes == 0
    end

    @testset "every site frozen mid-run: no attempts, no error ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        lat = Lattice((10, 10))
        σ = zeros(Int32, 10, 10); σ[:, 1:5] .= 1; σ[:, 6:10] .= 2
        st = lc_state(σ, Int32[1, 2], lat)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, sys = FrozenKind(2),
            lifecycle = Lifecycle((st, p, ctx, key, mcs, c) -> mcs == 3 && c == 1 ? EVENT_TRANSITION : EVENT_NONE;
                kind = (st, p, ctx, key, mcs, c) -> Int32(2)))
        sol = solve(PottsProblem(f, st, lat, (0, 8), gg_params(); frozen = fk_mask(st, 2)), alg; saveat = 1)
        @test sol.retcode == ReturnCode.Success
        @test sol.stats.attempts == 4 * 50                       # sweeps 0 … 3, then none
        @test all(i -> sol.u[i].ownership == sol.u[5].ownership, 5:9)            # nothing moves from t = 4 on
        # at construction a fully frozen lattice is still an error
        @test_throws "every site is frozen" init(PottsProblem(GG, st, lat, (0, 1), gg_params(); frozen = trues(10, 10)), alg)
    end

    @testset "a domain without frozen kinds never refreshes ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        prob = fk_domain_problem()
        sol = solve(prob, alg)
        @test sol.stats.lifecycle.divisions == 1
        @test sol.stats.refreshes == 0
        @test sol.stats.attempts == 8 * count(prob.lattice.mask)
        @test all(Array(sol.u[end].ownership)[.!prob.lattice.mask] .== 0)
        @test frozen_sites(prob, sol.u[end]) == .!prob.lattice.mask
    end

        @testset "a callback that writes kind: refresh_frozen!, derivative_discontinuity!, set_state!" begin
        writes = (
            refresh = integ -> (integ.state.cell.kind[1] = 2; refresh_frozen!(integ)),
                discontinuity = integ -> (integ.state.cell.kind[1] = 2; SciMLBase.derivative_discontinuity!(integ, true)),
            set_state = integ -> CorePotts.SymbolicIndexingInterface.set_state!(integ, Int32[2, 2], StateIndex(:cell, :kind)),
            stale = integ -> (integ.state.cell.kind[1] = 2))
        for (name, w) in pairs(writes)
            sol = solve(fk_problem(), SequentialCPM(); saveat = 1,
                callback = DiscreteCallback((u, t, integ) -> t == S, integ -> (w(integ); nothing)))
            @test fk_moved(sol, 1, 2:(S + 1)) >= S ÷ 2
            if name === :stale        # without a refresh the mask is stale and the cell keeps moving
                @test fk_moved(sol, 1, (S + 2):31) >= (30 - S) ÷ 2
                @test sol.stats.refreshes == 0
            else                      # frozen from sweep S on
                @test fk_moved(sol, 1, (S + 2):31) == 0
                @test sol.stats.refreshes == 1
                @test sol.stats.attempts == S * (900 - 36) + (30 - S) * (900 - 36 - Int(sol.u[end].cell.volume[1]))
            end
        end
        # a custom rule without `frozen_varies` is static: init warns once per logger,
        # independent of prior test execution order or session warn cache (TS1-9)
        @test_logs (:warn, r"frozen_varies") init(fk_problem(; sys = OnlyRemake()), SequentialCPM())
        io = IOBuffer()
        with_logger(ConsoleLogger(io, Warn)) do
            init(fk_problem(; sys = OnlyRemake()), SequentialCPM())
            init(fk_problem(; sys = OnlyRemake()), SequentialCPM())
        end
        msg = String(take!(io))
        @test occursin("frozen_varies", msg) && count("is overridden", msg) == 1
        # refresh_frozen! on a problem without a mask is a no-op
        integ = init(PottsProblem(GG, initial_state(blocks((20, 20), 5)...), Lattice((20, 20)), (0, 2), gg_params()), SequentialCPM())
        @test refresh_frozen!(integ) === integ && integ.ctx.mobility isa AllMobile && integ.stats.refreshes == 0
    end

    @testset "frozen kinds build the mask: construction, remake, checkpoint resume ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        mobile_ok(integ) = (fz = Array(integ.ctx.mobility.frozen);
            fz == frozen_sites(integ.prob, integ.state) && integ.nmobile == count(!, fz))
        prob = fk_problem(fk_flip(S); kind = fk_swap, tspan = (0, 20))
        # no `frozen` given: the rule builds it; a different mask is rejected
        lat, st = prob.lattice, prob.u0
        @test PottsProblem(prob.f, st, lat, (0, 1), gg_params()).frozen == fk_mask(st, 2)
            @test_throws ["ArgumentError", "frozen kinds", "cannot be combined"] PottsProblem(prob.f, st, lat, (0, 1), gg_params(); frozen = falses(30, 30))
        integ = init(prob, alg)
        for _ in 1:15
            step!(integ)
        end
            current_state(integ)                                                   # a host read point (D-089)
        @test integ.stats.lifecycle.transitions == 2 && mobile_ok(integ)
        ck = checkpoint(integ)                                    # after the transition
        integ2 = init(prob, alg; checkpoint = ck)
        @test mobile_ok(integ2)
        @test integ2.ctx.mobility.frozen == fk_mask(ck.state, 2) != fk_mask(prob.u0, 2)
        solve!(integ2)
        @test mobile_ok(integ2)
        # remake with a new state: the mask of that state
        r = remake(prob; u0 = ck.state)
        @test r.frozen == fk_mask(ck.state, 2)
        @test mobile_ok(init(r, alg))
        # negative control: a static mask keeps the problem's t0 mask on resume
        sprob = fk_problem(fk_flip(S); kind = fk_swap, sys = nothing, tspan = (0, 20))
        @test remake(sprob; u0 = ck.state).frozen == sprob.frozen
    end

    @testset "reinit! accepts a state with a different frozen-site count ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        prob = fk_problem(; tspan = (0, 10))
        integ = init(prob, alg)
        solve!(integ)
        u2 = deepcopy(prob.u0); u2.cell.kind[1] = 2                # both cells frozen
        reinit!(integ, u2)
        sol = solve!(integ)
        @test sol.u[end].ownership == u2.ownership                                 # nothing mobile moves into a cell
        @test sol.stats.attempts == 10 * (900 - 72)
        reinit!(integ, prob.u0)                                    # and back
        sol = solve!(integ)
        @test fk_sites(sol.u[end], 1) != fk_sites(prob.u0, 1)
        @test sol.stats.attempts == 10 * (900 - 36)
        # a static mask is not recomputed by reinit!
        integ = init(fk_problem(; sys = nothing, tspan = (0, 2)), alg)
        reinit!(integ, u2)
        @test integ.ctx.mobility.frozen == fk_mask(prob.u0, 2)
    end
end
end

@testitem "a custom rule's declared reads (frozen_reads)" setup = [CP_lifecycle] tags = [:corepotts, :lifecycle] begin
@testset "a custom rule's declared reads (frozen_reads)" begin
    @test CorePotts.frozen_reads(HostFrozen(2)) === nothing && CorePotts.frozen_reads(FrozenKind(2)) === nothing
    S = 10
    for alg in (SequentialCPM(), CheckerboardCPM())
        dec = solve(fk_problem(fk_flip(S); kind = fk_swap, sys = DeclaredFrozen(2, (:ownership, :kind))), alg; saveat = 1)
        ref = solve(fk_problem(fk_flip(S); kind = fk_swap, sys = HostFrozen(2)), alg; saveat = 1)
        @test dec.stats.refreshes == ref.stats.refreshes == 1
        @test [u.ownership for u in dec.u] == [u.ownership for u in ref.u]       # same masks, same run
        @test fk_moved(dec, 1, (S + 3):31) == 0                   # frozen after the transition
        # checkpoint resume and reinit! refresh by the declared rule
        prob = fk_problem(fk_flip(S); kind = fk_swap, sys = DeclaredFrozen(2, (:ownership, :kind)), tspan = (0, 20))
        integ = init(prob, alg)
        for _ in 1:15
            step!(integ)
        end
        ck = checkpoint(integ)
        @test init(prob, alg; checkpoint = ck).ctx.mobility.frozen == fk_mask(ck.state, 2) != fk_mask(prob.u0, 2)
        reinit!(integ, prob.u0)
        @test integ.ctx.mobility.frozen == fk_mask(prob.u0, 2)
        # a name that is not `:ownership` or a cell column, or not a tuple of Symbols: rejected at init
        for bad in ((:ownership, :knd), (:ownership, :q), [:ownership], (:ownership, "kind"), (:ownership, :kind, :kind), (:ownership, :ownership))
            @test_throws ArgumentError init(fk_problem(; sys = DeclaredFrozen(2, bad)), alg)
        end
        @test_throws r"`kind` more than once" init(fk_problem(; sys = DeclaredFrozen(2, (:ownership, :kind, :kind))), alg)
        # negative control: the standard rule ignores the hook (not even checked)
        integ = init(fk_problem(; sys = KindsBadReads()), alg)
        @test refresh_frozen!(integ).ctx.mobility.frozen == fk_mask(prob.u0, 2)
    end
end
end

# P6.4b1 review: the skip constant log(1 - n/N) of `SequentialCPM(; skip_interior = true)`
# is keyed on both n = |B| and the mobile count N. Removing a frozen cell embedded in medium frees its sites (N grows by
# 36) and leaves |B| unchanged; the constant must follow N.
@testitem "skip_interior: the skip constant follows a mask change that keeps |B| (P6.4b1)" setup = [CP_lifecycle] tags = [:corepotts, :lifecycle] begin
@testset "skip_interior: the skip constant follows a mask change that keeps |B| (P6.4b1)" begin
    integ = init(fk_problem(), SequentialCPM(; skip_interior = true); save_start = false)
    step!(integ)
    B = integ.cache
    n0, N0 = length(CorePotts._boundary_sites(integ)), integ.nmobile
    CorePotts._skip_lq!(B, n0, N0)                           # cached for (n0, N0)
    integ.state.ownership[integ.state.ownership .== 2] .= 0                  # the frozen cell 2 is removed
        SciMLBase.derivative_discontinuity!(integ, true)
    @test integ.nmobile == N0 + 36
    n = length(CorePotts._boundary_sites(integ))
    @test n == n0                                            # |B| unchanged
    @test CorePotts._skip_lq!(B, n, integ.nmobile) == log1p(-n / integ.nmobile)
    @test CorePotts._skip_lq!(B, n, integ.nmobile) != log1p(-n / N0)   # not the stale constant
    step!(integ)
    @test integ.stats.attempts == N0 + integ.nmobile
end
end

# `transitioning` is kernel-safe (no throw, it runs in the trigger); a transition bit on an
# event other than a division is refused on the host, by both planners (review of P6.5b, S5)
@testitem "transitioning: checked on the host, by both planners" setup = [CP_lifecycle] tags = [:corepotts, :lifecycle] begin
@testset "transitioning: checked on the host, by both planners" begin
    @test CorePotts.transitioning(EVENT_DIVIDE) == EVENT_DIVIDE | Int32(0x10)
    @test CorePotts.transitioning(EVENT_REMOVE) isa Int32                  # no throw in a kernel
    σ, kinds = blocks((30, 30), 5)
    lat = Lattice((30, 30))
    bad(st, p, ctx, key, mcs, c) = mcs == 1 && c == 1 ? CorePotts.transitioning(EVENT_REMOVE) : EVENT_NONE
    good(st, p, ctx, key, mcs, c) = mcs == 1 && c == 1 ? CorePotts.transitioning(EVENT_DIVIDE) : EVENT_NONE
    kind = (st, p, ctx, key, mcs, c) -> Int32(3 - st.cell.kind[c])
    prev = CorePotts._FORCE_DEVICE_LIFECYCLE[]         # this file also runs under the forced planner
    for force in (false, true)
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = force
        try
            err = try
                run_lifecycle(σ, kinds, lat, Lifecycle(bad; kind); tspan = (0, 2), alg = CheckerboardCPM())
                nothing
            catch e
                e
            end
            @test err isa ArgumentError && occursin("other than EVENT_DIVIDE", sprint(showerror, err))
            u = run_lifecycle(σ, kinds, lat, Lifecycle(good; kind); tspan = (0, 2), alg = CheckerboardCPM()).u[end]
            @test count(>(0), u.cell.volume) == length(kinds) + 1 && u.cell.kind[1] == 3 - kinds[1]
        finally
            CorePotts._FORCE_DEVICE_LIFECYCLE[] = prev
        end
    end
end
end
