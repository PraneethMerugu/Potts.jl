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
