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

    @testset "phases on Metal" begin
        σp, kp = blocks((32, 32), 4)
        latp = Lattice((32, 32))
        u0 = Float32[sin(2π * i / 32) + cos(2π * j / 16) for i in 1:32, j in 1:32]
        st = initial_state(σp, kp; site = (; u = copy(u0), u_next = zero(u0)),
            history = (; u = history_buffer(u0, 2)))
        ph = Phases(after_mcs = (SitePhase(jacobi!), CopyPhase((:site, :u) => (:site, :u_next)),
            HistoryPush(:u => (:site, :u))))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        pp = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 16.0f0, T = 10.0f0, D = 0.05f0)
        prob = CPMProblem(f, st, latp, (0, 5), pp)
        g = solve(prob, CheckerboardCPM(); backend).u[end]
        c = solve(prob, CheckerboardCPM()).u[end]
        @test g.site.u ≈ c.site.u rtol = 1e-5
        @test g.history.u ≈ c.history.u rtol = 1e-5
    end

    @testset "fields on Metal" begin
        σf, kf = blocks((64, 32), 6)
        latf = Lattice((64, 32))
        c0 = Float32[exp(-((i - 20)^2 + (j - 10)^2) / 30) for i in 1:64, j in 1:32]
        pf = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 36.0f0, T = 10.0f0,
            D = 0.1f0)
        prob = field_problem(σf, kf, latf, c0, diffuse, pf; dt = 1.0f0, spacing = (1.0f0, 0.8f0),
            tspan = (0, 20))
        g = solve(prob, CheckerboardCPM(); backend).u[end].site.c
        c = solve(prob, CheckerboardCPM()).u[end].site.c
        @test g ≈ c rtol = 1e-4
        @test sum(g) ≈ sum(c0) rtol = 1e-4
    end

    @testset "frozen sites and cell reductions on Metal" begin
        σz, kz = blocks((32, 32), 5; gap = 0)
        latz = Lattice((32, 32))
        frozen = falses(32, 32); frozen[:, 1:2] .= true
        v = Float32[i + j for i in 1:32, j in 1:32]
        n = length(kz)
        st = initial_state(σz, kz; site = (; v), cell = (; vsum = zeros(Float32, n), vmax = zeros(Float32, n)))
        ph = Phases(after_mcs = (
            CellReduce((:cell, :vsum), (st, p, ctx, key, mcs, i) -> st.site.v[i]),
            CellReduce((:cell, :vmax), (st, p, ctx, key, mcs, i) -> st.site.v[i]; op = max)))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        pz = (; J = SMatrix{3, 3, Float32}(gg_params().J), λ = 1.0f0, V0 = 25.0f0, T = 20.0f0)
        u = solve(CPMProblem(f, st, latz, (0, 10), pz; frozen), CheckerboardCPM(); backend).u[end]
        @test u.σ[frozen] == σz[frozen]
        for c in 1:n
            owned = findall(==(c), u.σ)
            isempty(owned) && continue
            @test u.cell.vsum[c] ≈ sum(v[owned]) rtol = 1e-5
            @test u.cell.vmax[c] == maximum(v[owned])
        end
    end
end
