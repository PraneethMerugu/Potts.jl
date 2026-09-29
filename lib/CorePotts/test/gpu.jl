# GPU group (opt-in: COREPOTTS_GPU=metal). Trackers stay exact on the device; statistics
# agree with the CPU (D-029: statistical, not bitwise, CPU/GPU agreement).
using Metal

@testset "Metal" begin
    backend = MetalBackend()
    σ, kinds = blocks((64, 64), 6)
    σ = circshift(σ, (3, 3))
    lat = Lattice((64, 64))
    sspec = Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))
    cell = merge(init_moments(σ, lat, length(kinds)),
        (; surface = recompute_surface(σ, lat, relation(sspec, lat), length(kinds); T = Float32)))
    commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx);
        commit_surface!(st.cell.surface, prop, surface_change(st.σ, ctx, prop; T = Float32));
        commit_moments!(st.cell, ctx.lattice, prop))
    function delta_H(st, p, prop, ctx)
        J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
        E(v, c) = p.λ * (v - p.V0)^2
        S(s, c) = p.λs * (s - p.S0)^2
        return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
               surface_delta(st.cell.surface, prop, surface_change(st.σ, ctx, prop; T = Float32), S)
    end
    f = CPMFunction(delta_H; commit!, temperature = gg_temperature)
    p = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0,
        λs = 0.2f0, S0 = 22.0f0)
    prob = CPMProblem(f, initial_state(σ, kinds; cell), lat, (0, 50), p;
        relations = (; surface = sspec))
    sol = solve(prob, CheckerboardCPM(); backend)
    @test sol.retcode == ReturnCode.Success
    u = sol.u[end]
    @test u.σ != σ
    @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kinds)]
    @test u.cell.surface ≈ recompute_surface(u.σ, lat, relation(sspec, lat), length(kinds); T = Float64) rtol = 1e-4
    ref = init_moments(u.σ, lat, length(kinds))
    for c in eachindex(kinds)
        @test all(isapprox.(centroid(u.cell, lat, c), centroid(merge(ref, (; volume = u.cell.volume)), lat, c); atol = 1e-9))
    end

    # statistical parity of an observable, CPU vs Metal checkerboard
    function energy_proxy(u)          # mean |volume − V0|, a fast-relaxing observable
        sum(abs.(u.cell.volume .- 36)) / length(u.cell.volume)
    end
    xs = [energy_proxy(solve(remake(prob; seed), CheckerboardCPM(); save_start = false).u[end]) for seed in 1:12]
    ys = [energy_proxy(solve(remake(prob; seed), CheckerboardCPM(); backend, save_start = false).u[end]) for seed in 101:112]
    t = (mean(xs) - mean(ys)) / sqrt(var(xs) / 12 + var(ys) / 12)
    @info "CPU vs Metal" cpu = mean(xs) metal = mean(ys) t
    @test abs(t) < 4
end
