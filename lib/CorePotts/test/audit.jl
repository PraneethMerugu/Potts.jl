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
