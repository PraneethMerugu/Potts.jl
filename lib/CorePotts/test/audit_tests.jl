# Regression tests for docs/design/AUDIT.md findings (IDs A-xx).

@testsetup module CP_audit
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
# imports an earlier file made in the old single Main
using CorePotts: Proposal
include("shared/gg_model.jl")

# The host executor (LatticeFields.Exec, v3 §9.1): a site phase of more than `HOST_GRAIN`
# sites runs in threaded chunks when Julia has threads. The checkerboard runs its phases inline
# (`threads = false`): a threaded lockless phase is not reproducible (D-271). The trajectory
# must not depend on the chunks: a 4-thread process (chunks) reproduces this process's
# single-threaded run (plain loops), and a different seed does not (negative control).
const HOST_EXEC_RUN = raw"""
using CorePotts, StaticArrays
using CorePotts: Exec
kindidx(st, c) = c == 0 ? 1 : Int(@inbounds st.cell.kind[c]) + 1
function gg_dH(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
end
jac!(st, p, ctx, key, mcs, i) = (@inbounds st.site.v[i] = st.site.u[i] + 1; nothing)
function host_exec_run(seed)
    L = 192                                   # a site phase of 36864 sites > HOST_GRAIN
    σ = zeros(Int32, L, L); kinds = Int32[]; id = 0
    for x in 1:8:(L - 6), y in 1:8:(L - 6)
        id += 1; push!(kinds, isodd(id) ? 1 : 2); σ[x:(x + 6), y:(y + 6)] .= id
    end
    p = (; J = SMatrix{3, 3}(0.0, 16, 16, 16, 2, 11, 16, 11, 14), λ = 1.0, V0 = 49.0, T = 10.0)
    u = zeros(L, L)
    f = CPMFunction(gg_dH; temperature = (st, p, prop, ctx) -> p.T,
        phases = Phases(after_mcs = (SitePhase(jac!), CopyPhase((:site, :u) => (:site, :v)))))
    st = initial_state(σ, kinds; site = (; u, v = copy(u)))
    sol = solve(PottsProblem(f, st, Lattice((L, L)), (0, 6), p; seed), CheckerboardCPM(; proposal = Moore(1), threads = false);
        save_start = false)
    return hash((sol.u[end].σ, sol.u[end].cell.volume, sol.u[end].site.u))
end
"""
include("shared/export_all.jl")
end

@testitem "A-10 mismatched history rings are an error" setup = [CP_audit] tags = [:corepotts, :audit] begin
@testset "A-10 mismatched history rings are an error" begin
    lat = Lattice((12, 12))
    σ, kinds = blocks((12, 12), 4)
    st = with_capacity(initial_state(σ, kinds), 50)
    st = CPMState(st.σ, st.cell, st.site, st.model, (; vh = history_buffer(zeros(Int32, 50), 3)))
    f = CPMFunction(gg_delta_H; temperature = gg_temperature,
        phases = Phases(; end_mcs = (HistoryPush(:vh => (:cell, :volume)),)))
    sol = solve(PottsProblem(f, st, lat, (0, 3), gg_params()), SequentialCPM())
    @test sol.u[end].history.vh[1:length(kinds), mod1(3, 3)] == sol.u[end].cell.volume[1:length(kinds)]
    # a mismatched ring is an error, not an out-of-bounds write
    bad = initial_state(σ, kinds; history = (; vh = history_buffer(zeros(Int32, 2), 3)))
    @test_throws DimensionMismatch solve(PottsProblem(f, bad, lat, (0, 1), gg_params()), SequentialCPM())
end
end

@testitem "A-11 asymmetric contact relations are rejected" setup = [CP_audit] tags = [:corepotts, :audit] begin
@testset "A-11 asymmetric contact relations are rejected" begin
    lat = Lattice((12, 12))
    σ, kinds = blocks((12, 12), 4)
    st = initial_state(σ, kinds)
    prob = PottsProblem(GG, st, lat, (0, 1), gg_params(); contact = Stencil([(1, 0), (0, 1)]))
        @test_throws ["ArgumentError", "contact relation", "not symmetric"] solve(prob, SequentialCPM())
    ok = PottsProblem(GG, st, lat, (0, 1), gg_params(); contact = Stencil([(1, 0), (-1, 0)]))
    @test solve(ok, SequentialCPM()).retcode == ReturnCode.Success
end
end

@testitem "A-12 lifecycle rebuild! hook refreshes model trackers" setup = [CP_audit] tags = [:corepotts, :audit] begin
@testset "A-12 lifecycle rebuild! hook refreshes model trackers" begin
    lat = Lattice((30, 30))
    σ = zeros(Int32, 30, 30); σ[8:22, 10:20] .= 1
    v = Float64[x[1] for x in CartesianIndices(σ)]
    st = initial_state(σ, [1]; cell = merge((; vsum = recompute_site_sum(σ, v, 1)), init_moments(σ, lat, 1)))
    st = with_capacity(st, 4)
    rebuild!(st, p, ctx, backend) = copyto!(st.cell.vsum, recompute_site_sum(Array(st.σ), v, length(st.cell.kind)))
    lc = Lifecycle((st, p, ctx, key, mcs, c) -> (mcs == 0 && c == 1) ? EVENT_DIVIDE : EVENT_NONE; rebuild!)
    commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx, prop);
        commit_site_sum!(st.cell.vsum, prop, @inbounds v[prop.target]))
    f = CPMFunction(gg_delta_H; commit!, temperature = (a...) -> 0.0, lifecycle = lc)
    u = solve(PottsProblem(f, st, lat, (0, 1), gg_params()), SequentialCPM()).u[end]
    @test u.cell.volume[2] > 0
    @test u.cell.vsum ≈ recompute_site_sum(u.σ, v, 4)
end
end

@testitem "A-19 solution display and integer indexing; A-14 scalar saveat" setup = [CP_audit] tags = [:corepotts, :audit] begin
@testset "A-19 solution display and integer indexing; A-14 scalar saveat" begin
    lat = Lattice((12, 12))
    σ, kinds = blocks((12, 12), 4)
    prob = PottsProblem(GG, initial_state(σ, kinds), lat, (0, 10), gg_params())
    sol = solve(prob, SequentialCPM(); saveat = 2)
    @test sol.t == [0, 2, 4, 6, 8, 10]
    @test sol[end] === sol.u[end]
    @test sol[1].σ == σ
    @test occursin("6 saved states", sprint(show, MIME"text/plain"(), sol))
    @test occursin("PottsSolution", sprint(show, sol))
end
end

@testitem "A-01 hex connectivity uses the 6-ring" setup = [CP_audit] tags = [:corepotts, :audit] begin
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
        @test locally_connected(σ, ctx, prop) == (!isempty(members) && length(comp) == length(members))
    end
    # the adjacent pair (1,0),(0,1) is one arc of the hex ring
    σ = zeros(Int32, 12, 12); σ[6, 6] = 1; σ[7, 6] = 1; σ[6, 7] = 1
    prop = Proposal(linear_index(L, x), linear_index(L, (5, 6)), x, 1, Int32(1), Int32(0))
    @test ring_arcs(σ, ctx, prop) == 1
end
end

@testitem "A-03 hex minimum image" setup = [CP_audit] tags = [:corepotts, :audit] begin
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
end

@testitem "A-05 hex domains and weights see Cartesian positions" setup = [CP_audit] tags = [:corepotts, :audit] begin
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
end

@testitem "A-65 footprint reach includes the proposal radius and source reads" setup = [CP_audit] tags = [:corepotts, :audit] begin
@testset "A-65 footprint reach includes the proposal radius and source reads" begin
    L = Lattice((24, 24))
    @test CorePotts.reach(Footprint(), relation(Moore(2), L)) == (2, 0)
    @test CorePotts.reach(Footprint(; source_read = 2, source_write = 0), relation(Moore(2), L)) == (4, 2)
    σ, kinds = blocks((24, 24), 4)
    prob = PottsProblem(GG, initial_state(σ, kinds), L, (0, 3), gg_params())
    u = solve(prob, CheckerboardCPM(; proposal = Moore(2))).u[end]
    @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
end
end

@testitem "A-16 division on a 1D lattice" setup = [CP_audit] tags = [:corepotts, :audit] begin
@testset "A-16 division on a 1D lattice" begin
    lat = Lattice((40,))
    σ = zeros(Int32, 40); σ[5:20] .= 1
    st = with_capacity(initial_state(σ, [1]; cell = init_moments(σ, lat, 1)), 4)
    st = CPMState(st.σ, merge(st.cell, init_moments(σ, lat, 4)), st.site, st.model, st.history)
    lc = Lifecycle((st, p, ctx, key, mcs, c) -> (mcs == 0 && c == 1) ? EVENT_DIVIDE : EVENT_NONE)
    f = CPMFunction(gg_delta_H; temperature = (a...) -> 0.0, lifecycle = lc)
    u = solve(PottsProblem(f, st, lat, (0, 1), gg_params()), SequentialCPM(; proposal = VonNeumann(1))).u[end]
    @test count(>(0), u.cell.volume) == 2
end
end

@testitem "A-17 a member's transition survives its cluster's division" setup = [CP_audit] tags = [:corepotts, :audit] begin
@testset "A-17 a member's transition survives its cluster's division" begin
    lat = Lattice((40, 40))
    σ = zeros(Int32, 40, 40); σ[11:30, 15:22] .= 1; σ[18:23, 17:20] .= 2
    cell = merge(init_moments(σ, lat, 2), init_clusters(σ, Int32[1, 1], lat))
    st = with_capacity(initial_state(σ, Int32[1, 2]; cell), 6)
    tr(st, p, ctx, key, mcs, c) = mcs != 0 ? EVENT_NONE : c == 1 ? EVENT_DIVIDE_CLUSTER : c == 2 ? EVENT_TRANSITION : EVENT_NONE
    frozen(st, p, prop, ctx) = false
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen,
        lifecycle = Lifecycle(tr; kind = (st, p, ctx, key, mcs, c) -> Int32(1)))
    sol = solve(PottsProblem(f, st, lat, (0, 1), gg_params()), SequentialCPM())
    u = sol.u[end]
    @test sol.stats.lifecycle.divisions == 2 && sol.stats.lifecycle.transitions == 1
    @test u.cell.kind[1:4] == Int32[1, 1, 1, 1]          # member 2 and its daughter took kind 1
end
end

@testitem "host executor: threaded chunks give the single-threaded trajectory" setup = [CP_audit] tags = [:corepotts, :audit] begin
@testset "host executor: threaded chunks give the single-threaded trajectory" begin
    mod = Module()
    Base.include_string(mod, HOST_EXEC_RUN)
    @test CorePotts.Exec.HOST_GRAIN < 192^2
    here = Base.invokelatest(mod.host_exec_run, 1)
    @test here != Base.invokelatest(mod.host_exec_run, 2)               # control: the seed matters
    code = HOST_EXEC_RUN * "\nprint(Threads.nthreads(), \" \", host_exec_run(1))"
    out = read(`$(Base.julia_cmd()) --startup-file=no -t 4 --project=$(Base.active_project()) -e $code`, String)
    nt, h = split(strip(out))
    @test parse(Int, nt) == 4
    @test parse(UInt, h) == here
    # and a warm CPU checkerboard step allocates nothing (in place of the KA-workgroup check)
    L = Lattice((48, 48))
    σ, kinds = blocks((48, 48), 6)
    prob = PottsProblem(GG, initial_state(σ, kinds), L, (0, 20), gg_params())
    # a small checkerboard phase runs inline on the CPU: a warm step allocates nothing
    a = init(prob, CheckerboardCPM(; proposal = Moore(1)))
    @test a.cache.inline
    @test minimum(_ -> (step!(a); @allocated step!(a)), 1:3) == 0
end
end
