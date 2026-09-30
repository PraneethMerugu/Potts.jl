# Regression tests for docs/design/AUDIT.md findings (IDs A-xx).

@testset "A-10 mismatched history rings are an error" begin
    lat = Lattice((12, 12))
    σ, kinds = blocks((12, 12), 4)
    st = with_capacity(initial_state(σ, kinds), 50)
    st = CPMState(st.σ, st.cell, st.site, st.model, (; vh = history_buffer(zeros(Int32, 50), 3)))
    f = CPMFunction(gg_delta_H; temperature = gg_temperature,
        phases = Phases(; end_mcs = (HistoryPush(:vh => (:cell, :volume)),)))
    sol = solve(CPMProblem(f, st, lat, (0, 3), gg_params()), SequentialCPM())
    @test sol.u[end].history.vh[1:length(kinds), mod1(3, 3)] == sol.u[end].cell.volume[1:length(kinds)]
    # a mismatched ring is an error, not an out-of-bounds write
    bad = initial_state(σ, kinds; history = (; vh = history_buffer(zeros(Int32, 2), 3)))
    @test_throws DimensionMismatch solve(CPMProblem(f, bad, lat, (0, 1), gg_params()), SequentialCPM())
end

@testset "A-11 asymmetric contact relations are rejected" begin
    lat = Lattice((12, 12))
    σ, kinds = blocks((12, 12), 4)
    st = initial_state(σ, kinds)
    prob = CPMProblem(GG, st, lat, (0, 1), gg_params(); contact = Stencil([(1, 0), (0, 1)]))
    @test_throws ArgumentError solve(prob, SequentialCPM())
    ok = CPMProblem(GG, st, lat, (0, 1), gg_params(); contact = Stencil([(1, 0), (-1, 0)]))
    @test solve(ok, SequentialCPM()).retcode == ReturnCode.Success
end

@testset "A-12 lifecycle rebuild! hook refreshes model trackers" begin
    lat = Lattice((30, 30))
    σ = zeros(Int32, 30, 30); σ[8:22, 10:20] .= 1
    v = Float64[x[1] for x in CartesianIndices(σ)]
    st = initial_state(σ, [1]; cell = merge((; vsum = recompute_site_sum(σ, v, 1)), init_moments(σ, lat, 1)))
    st = with_capacity(st, 4)
    rebuild!(st, p, ctx, backend) = copyto!(st.cell.vsum, recompute_site_sum(Array(st.σ), v, length(st.cell.kind)))
    lc = Lifecycle((st, p, ctx, key, mcs, c) -> (mcs == 0 && c == 1) ? EVENT_DIVIDE : EVENT_NONE; rebuild!)
    commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop);
        commit_site_sum!(st.cell.vsum, prop, @inbounds v[prop.target]))
    f = CPMFunction(gg_delta_H; commit!, temperature = (a...) -> 0.0, lifecycle = lc)
    u = solve(CPMProblem(f, st, lat, (0, 1), gg_params()), SequentialCPM()).u[end]
    @test u.cell.volume[2] > 0
    @test u.cell.vsum ≈ recompute_site_sum(u.σ, v, 4)
end

@testset "A-19 solution display and integer indexing; A-14 scalar saveat" begin
    lat = Lattice((12, 12))
    σ, kinds = blocks((12, 12), 4)
    prob = CPMProblem(GG, initial_state(σ, kinds), lat, (0, 10), gg_params())
    sol = solve(prob, SequentialCPM(); saveat = 2)
    @test sol.t == [0, 2, 4, 6, 8, 10]
    @test sol[end] === sol.u[end]
    @test sol[1].σ == σ
    @test occursin("6 saved states", sprint(show, MIME"text/plain"(), sol))
    @test occursin("PottsSolution", sprint(show, sol))
end

@testset "A-01 hex connectivity uses the 6-ring" begin
    L = Lattice((12, 12); geometry = Hexagonal())
    ctx = (; lattice = L)
    ring = ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1))
    hexadj(a, b) = (d = (b[1] - a[1], b[2] - a[2]); d in ring)
    rng = Xoshiro(3)
    x = (6, 6)
    for _ in 1:500
        σ = zeros(Int32, 12, 12)
        σ[6, 6] = 1
        members = [o for o in ring if rand(rng, Bool)]
        foreach(o -> σ[6 + o[1], 6 + o[2]] = 1, members)
        foreach(o -> σ[6 + o[1], 6 + o[2]] = 2, [o for o in ring if !(o in members) && rand(rng, Bool)])
        prop = Proposal(linear_index(L, x), linear_index(L, (5, 6)), x, 1, Int32(1), Int32(2))
        # brute force: the members are one component under hex adjacency
        comp = isempty(members) ? Set() : Set([first(members)])
        while true
            grown = union(comp, Set(m for m in members if any(c -> hexadj(c, m), comp)))
            grown == comp && break
            comp = grown
        end
        @test locally_connected(σ, ctx, prop) == (length(comp) == length(members))
    end
    # the Merks rule allows the adjacent pair (1,0),(0,1) on hex
    σ = zeros(Int32, 12, 12); σ[6, 6] = 1; σ[7, 6] = 1; σ[6, 7] = 1
    prop = Proposal(linear_index(L, x), linear_index(L, (5, 6)), x, 1, Int32(1), Int32(0))
    @test merks_connectivity(σ, ctx, prop)
end

@testset "A-03 hex minimum image" begin
    L = Lattice((20, 14); geometry = Hexagonal())
    rng = Xoshiro(5)
    for _ in 1:200
        δ = (20 * rand(rng) - 10, 14 * rand(rng) - 7)
        brute = minimum(hypot(embed(L, (δ[1] + 20i, δ[2] + 14j))...) for i in -2:2, j in -2:2)
        @test CorePotts._periodic_norm(Float64, L, δ) ≈ brute
    end
    @test CorePotts._periodic_norm(Float64, Lattice((20, 20); geometry = Hexagonal()), (8.0, 8.0)) ≈ sqrt(112)
end

@testset "A-05 hex domains and weights see Cartesian positions" begin
    L = Lattice((21, 21); geometry = Hexagonal(), boundary = Closed(),
        domain = x -> hypot(x[1] - 16.5, x[2] - 11 * sqrt(3) / 2) <= 6)
    c = embed(L, (11.0, 11.0))
    inside = [hypot((embed(L, Float64.(Tuple(i))) .- c)...) for i in CartesianIndices((21, 21)) if L.mask[i]]
    @test maximum(inside) <= 6 + 1e-9
    r = relation(Weighted(Hex(1), o -> 1 / sqrt(sum(abs2, o))), L)
    @test all(≈(1), r.weights)
    ri = relation(Weighted(Hex(1), OnIndices(o -> 1 / sqrt(sum(abs2, o)))), L)
    @test count(≈(1 / sqrt(2)), ri.weights) == 2
end

@testset "A-65 footprint reach includes the proposal radius and source reads" begin
    L = Lattice((24, 24))
    @test CorePotts.reach(Footprint(), relation(Moore(2), L)) == (2, 0)
    @test CorePotts.reach(Footprint(; source_read = 2, source_write = 0), relation(Moore(2), L)) == (4, 2)
    σ, kinds = blocks((24, 24), 4)
    prob = CPMProblem(GG, initial_state(σ, kinds), L, (0, 3), gg_params())
    u = solve(prob, CheckerboardCPM(; proposal = Moore(2))).u[end]
    @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
end

@testset "A-16 division on a 1D lattice" begin
    lat = Lattice((40,))
    σ = zeros(Int32, 40); σ[5:20] .= 1
    st = with_capacity(initial_state(σ, [1]; cell = init_moments(σ, lat, 1)), 4)
    st = CPMState(st.σ, merge(st.cell, init_moments(σ, lat, 4)), st.site, st.model, st.history)
    lc = Lifecycle((st, p, ctx, key, mcs, c) -> (mcs == 0 && c == 1) ? EVENT_DIVIDE : EVENT_NONE)
    f = CPMFunction(gg_delta_H; temperature = (a...) -> 0.0, lifecycle = lc)
    u = solve(CPMProblem(f, st, lat, (0, 1), gg_params()), SequentialCPM(; proposal = VonNeumann(1))).u[end]
    @test count(>(0), u.cell.volume) == 2
end

@testset "A-17 a member's transition survives its cluster's division" begin
    lat = Lattice((40, 40))
    σ = zeros(Int32, 40, 40); σ[11:30, 15:22] .= 1; σ[18:23, 17:20] .= 2
    cell = merge(init_moments(σ, lat, 2), init_clusters(σ, Int32[1, 1], lat))
    st = with_capacity(initial_state(σ, Int32[1, 2]; cell), 6)
    tr(st, p, ctx, key, mcs, c) = mcs != 0 ? EVENT_NONE : c == 1 ? EVENT_DIVIDE : c == 2 ? EVENT_TRANSITION : EVENT_NONE
    frozen(st, p, prop, ctx) = false
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen,
        lifecycle = Lifecycle(tr; clusters = true, kind = (st, p, ctx, key, mcs, c) -> Int32(1)))
    sol = solve(CPMProblem(f, st, lat, (0, 1), gg_params()), SequentialCPM())
    u = sol.u[end]
    @test sol.stats.lifecycle.divisions == 2 && sol.stats.lifecycle.transitions == 1
    @test u.cell.kind[1:4] == Int32[1, 1, 1, 1]          # member 2 and its daughter took kind 1
end

@testset "CPU launches: inline loops and multi-workgroup kernels agree" begin
    # single-threaded runs take the inline path everywhere; force the KA path explicitly
    out = zeros(Int, 100)
    body(i, a, k) = (@inbounds a[i] = k * i; nothing)
    CorePotts._each_kernel!(CorePotts.CPU())(body, (out, 3); ndrange = 100, workgroupsize = 16)
    @test out == 3 .* (1:100)
    L = Lattice((48, 48))
    σ, kinds = blocks((48, 48), 6)
    prob = CPMProblem(GG, initial_state(σ, kinds), L, (0, 20), gg_params())
    alg = CheckerboardCPM(; proposal = Moore(1))
    a, b = init(prob, alg), init(prob, alg)
    b.cache.groupsize .= 64                     # several workgroups per color
    for _ in 1:10
        step!(a); step!(b)
    end
    @test a.state.σ == b.state.σ && a.state.cell.volume == b.state.cell.volume
    @test minimum(_ -> (step!(a); @allocated step!(a)), 1:3) == 0
end
