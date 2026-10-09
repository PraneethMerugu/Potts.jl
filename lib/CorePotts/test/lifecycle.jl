# Lifecycle: division, removal, transition, id reuse, capacity (ROADMAP M2.8).

frozen_dynamics(st, p, prop, ctx) = false
lc_state(σ, kinds, lat; capacity = length(kinds), cell = (;)) = with_capacity(
    initial_state(σ, kinds; cell = merge(init_moments(σ, lat, length(kinds)), cell)), capacity)

function run_lifecycle(σ, kinds, lat, lifecycle; capacity = length(kinds) + 4, tspan = (0, 1),
        cell = (;), constraint = frozen_dynamics, p = gg_params(), alg = SequentialCPM(),
        phases = Phases(), backend = CPU())
    st = lc_state(σ, kinds, lat; capacity, cell)
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint, lifecycle, phases)
    return solve(PottsProblem(f, st, lat, tspan, p), alg; backend)
end

divide_at(t) = (st, p, ctx, key, mcs, c) -> mcs == t ? EVENT_DIVIDE : EVENT_NONE

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
                μ, C = brute_geometry(u.σ, lat, c)
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
        @test Set(Set(findall(==(c), u.σ)) for c in 1:2) == Set(halves)
    end

    @testset "removal and transition" begin
        σ, kinds = blocks((30, 30), 5)
        lat = Lattice((30, 30))
        remove2(st, p, ctx, key, mcs, c) = mcs == 2 && st.cell.kind[c] == 2 ? EVENT_REMOVE : EVENT_NONE
        u = run_lifecycle(σ, kinds, lat, Lifecycle(remove2); tspan = (0, 4)).u[end]
        @test all(u.cell.volume[i] == 0 for i in eachindex(kinds) if kinds[i] == 2)
        @test all(u.σ[i] == 0 || kinds[u.σ[i]] == 1 for i in eachindex(u.σ))
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
        @test sol.u[end].σ == σ
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
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
        end
        commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
        st = lc_state(σ, [1], lat; capacity = 64, cell = (; target = [64.0]))
        f = CPMFunction(dH; commit!, temperature = gg_temperature,
            phases = Phases(before_mcs = (CellPhase(grow!),)),
            lifecycle = Lifecycle(big; divide! = reset!))
        sol = solve(PottsProblem(f, st, lat, (0, 120), gg_params()), alg)
        u = sol.u[end]
        live = findall(>(0), u.cell.volume)
        @test length(live) >= 4
        @test sol.stats.lifecycle.divisions >= 3
        @test u.cell.volume == [count(==(c), u.σ) for c in 1:64]
        for c in live
            μ, C = brute_geometry(u.σ, lat, c)
            @test all(isapprox.(centroid(u.cell, lat, c), μ; atol = 1e-9))
        end
    end
end

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

# P6.0d (D-081): a frozen mask that derives from the state (as Potts' `[frozen]` kinds) is
# recomputed after every MCS with a lifecycle event, by `refresh_frozen!` and by `reinit!`.
# `FrozenKind(k)`: the standard rule (built on the device), the sites of cells of kind `k`
# are frozen. `HostFrozen(k)`: the same rule given as a custom `remake_frozen` (the host
# fallback). `nothing`: a static mask.
struct FrozenKind
    k::Int32
end
CorePotts.frozen_kinds(s::FrozenKind) = (s.k,)              # `frozen_varies` follows
struct HostFrozen
    k::Int32
end
CorePotts.frozen_varies(::HostFrozen) = true                # required with a custom rule
struct OnlyRemake end                                       # … which this one forgets
fk_mask(u, k) = (kinds = Array(u.cell.kind); map(c -> c != 0 && kinds[c] == k, Array(u.σ)))
CorePotts.remake_frozen(s::HostFrozen, prob, u) = fk_mask(u, s.k)
CorePotts.remake_frozen(::OnlyRemake, prob, u) = fk_mask(u, 2)

# 30×30 periodic, cell 1 (kind 1) and cell 2 (kind 2), both 6×6 and growing toward V0 = 40
function fk_problem(trigger = nothing; kind = nothing, sys = FrozenKind(2), T = Float64,
        tspan = (0, 30), seed = 1)
    lat = Lattice((30, 30))
    σ = zeros(Int32, 30, 30); σ[5:10, 5:10] .= 1; σ[18:23, 18:23] .= 2
    st = lc_state(σ, Int32[1, 2], lat)
    lc = trigger === nothing ? nothing :
         Lifecycle(trigger; normal = AlongMinorAxis{T}(), (kind === nothing ? (;) : (; kind))...)
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, lifecycle = lc, sys)
    return PottsProblem(f, st, lat, tspan, gg_params(T); seed, frozen = fk_mask(st, 2))
end
fk_sites(u, c) = Array(u.σ) .== c
# saved states i-1 → i in which cell c's site set changed
fk_moved(sol, c, is) = count(i -> fk_sites(sol.u[i], c) != fk_sites(sol.u[i - 1], c), is)
fk_flip(S) = (st, p, ctx, key, mcs, c) -> mcs == S ? EVENT_TRANSITION : EVENT_NONE
fk_swap(st, p, ctx, key, mcs, c) = Int32(3 - st.cell.kind[c])
# a disk domain with no frozen kind (a static mask) and a division at MCS 2
function fk_domain_problem(; T = Float64)
    lat = Lattice((30, 30); boundary = Closed(), domain = x -> (x[1] - 15.5)^2 + (x[2] - 15.5)^2 <= 13^2)
    σ = zeros(Int32, 30, 30); σ[10:19, 12:19] .= 1
    st = lc_state(σ, Int32[1], lat; capacity = 3)
    lc = Lifecycle((st, p, ctx, key, mcs, c) -> mcs == 2 && c == 1 ? EVENT_DIVIDE : EVENT_NONE;
        normal = AlongMinorAxis{T}())
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, lifecycle = lc)
    return PottsProblem(f, st, lat, (0, 8), gg_params(T))
end

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
        @test all(i -> sol.u[i].σ == sol.u[5].σ, 5:9)            # nothing moves from t = 4 on
        # at construction a fully frozen lattice is still an error
        @test_throws "every site is frozen" init(PottsProblem(GG, st, lat, (0, 1), gg_params(); frozen = trues(10, 10)), alg)
    end

    @testset "a domain without frozen kinds never refreshes ($(nameof(typeof(alg))))" for alg in (SequentialCPM(), CheckerboardCPM())
        prob = fk_domain_problem()
        sol = solve(prob, alg)
        @test sol.stats.lifecycle.divisions == 1
        @test sol.stats.refreshes == 0
        @test sol.stats.attempts == 8 * count(prob.lattice.mask)
        @test all(Array(sol.u[end].σ)[.!prob.lattice.mask] .== 0)
        @test frozen_sites(prob, sol.u[end]) == .!prob.lattice.mask
    end

    @testset "a callback that writes kind: refresh_frozen!, u_modified!, set_state!" begin
        writes = (
            refresh = integ -> (integ.state.cell.kind[1] = 2; refresh_frozen!(integ)),
            u_modified = integ -> (integ.state.cell.kind[1] = 2; SciMLBase.u_modified!(integ, true)),
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
        # a custom rule without `frozen_varies` is static: init warns (once per session)
        @test_logs (:warn, r"frozen_varies") init(fk_problem(; sys = OnlyRemake()), SequentialCPM())
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
        @test_throws ArgumentError PottsProblem(prob.f, st, lat, (0, 1), gg_params(); frozen = falses(30, 30))
        integ = init(prob, alg)
        for _ in 1:15
            step!(integ)
        end
        integ.u                                                   # a host read point (D-089)
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
        @test sol.u[end].σ == u2.σ                                 # nothing mobile moves into a cell
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

# P6.0v2b (D-128): a custom rule declares the leaves it reads (`frozen_reads`). On the CPU
# the declared path is the live state (no copy), so only the validation and the masks are
# exercised here; the byte behaviour is covered on Metal by the acceptance file
# `p6_0v2b_frozen_refresh_bytes.jl`. A bad declaration fails at `init`, before any step.
struct DeclaredFrozen
    k::Int32
    reads::Any
end
CorePotts.frozen_varies(::DeclaredFrozen) = true
CorePotts.frozen_reads(s::DeclaredFrozen) = s.reads
CorePotts.remake_frozen(s::DeclaredFrozen, prob, u) = fk_mask(u, s.k)
struct KindsBadReads end                                    # the standard rule, a bad declaration
CorePotts.frozen_kinds(::KindsBadReads) = (Int32(2),)
CorePotts.frozen_reads(::KindsBadReads) = (:nonexistent,)

@testset "a custom rule's declared reads (frozen_reads)" begin
    @test CorePotts.frozen_reads(HostFrozen(2)) === nothing && CorePotts.frozen_reads(FrozenKind(2)) === nothing
    S = 10
    for alg in (SequentialCPM(), CheckerboardCPM())
        dec = solve(fk_problem(fk_flip(S); kind = fk_swap, sys = DeclaredFrozen(2, (:σ, :kind))), alg; saveat = 1)
        ref = solve(fk_problem(fk_flip(S); kind = fk_swap, sys = HostFrozen(2)), alg; saveat = 1)
        @test dec.stats.refreshes == ref.stats.refreshes == 1
        @test [u.σ for u in dec.u] == [u.σ for u in ref.u]       # same masks, same run
        @test fk_moved(dec, 1, (S + 3):31) == 0                   # frozen after the transition
        # checkpoint resume and reinit! refresh by the declared rule
        prob = fk_problem(fk_flip(S); kind = fk_swap, sys = DeclaredFrozen(2, (:σ, :kind)), tspan = (0, 20))
        integ = init(prob, alg)
        for _ in 1:15
            step!(integ)
        end
        ck = checkpoint(integ)
        @test init(prob, alg; checkpoint = ck).ctx.mobility.frozen == fk_mask(ck.state, 2) != fk_mask(prob.u0, 2)
        reinit!(integ, prob.u0)
        @test integ.ctx.mobility.frozen == fk_mask(prob.u0, 2)
        # a name that is not `:σ` or a cell column, or not a tuple of Symbols: rejected at init
        for bad in ((:σ, :knd), (:σ, :q), [:σ], (:σ, "kind"), (:σ, :kind, :kind), (:σ, :σ))
            @test_throws ArgumentError init(fk_problem(; sys = DeclaredFrozen(2, bad)), alg)
        end
        @test_throws r"`kind` more than once" init(fk_problem(; sys = DeclaredFrozen(2, (:σ, :kind, :kind))), alg)
        # negative control: the standard rule ignores the hook (not even checked)
        integ = init(fk_problem(; sys = KindsBadReads()), alg)
        @test refresh_frozen!(integ).ctx.mobility.frozen == fk_mask(prob.u0, 2)
    end
end

# P6.4b1 review: BoundarySiteCPM's skip constant log(1 - n/N) is keyed on both n = |B| and
# the mobile count N. Removing a frozen cell embedded in medium frees its sites (N grows by
# 36) and leaves |B| unchanged; the constant must follow N.
@testset "BoundarySiteCPM: the skip constant follows a mask change that keeps |B| (P6.4b1)" begin
    integ = init(fk_problem(), SequentialCPM(; skip_interior = true); save_start = false)
    step!(integ)
    B = integ.cache
    n0, N0 = length(CorePotts._boundary_sites(integ)), integ.nmobile
    CorePotts._skip_lq!(B, n0, N0)                           # cached for (n0, N0)
    integ.state.σ[integ.state.σ .== 2] .= 0                  # the frozen cell 2 is removed
    u_modified!(integ, true)
    @test integ.nmobile == N0 + 36
    n = length(CorePotts._boundary_sites(integ))
    @test n == n0                                            # |B| unchanged
    @test CorePotts._skip_lq!(B, n, integ.nmobile) == log1p(-n / integ.nmobile)
    @test CorePotts._skip_lq!(B, n, integ.nmobile) != log1p(-n / N0)   # not the stale constant
    step!(integ)
    @test integ.stats.attempts == N0 + integ.nmobile
end
