# Fields: finite-difference primitives and explicit-rate steps (ROADMAP M2.4).

diffuse(st, p, ctx, key, mcs, i, c) = p.D * laplacian(c, ctx, i)
never(st, p, prop, ctx) = false                     # freeze ownership where needed

function field_problem(σ, kinds, lat, c0, rate, p; dt = 1.0, substeps = 1, spacing = nothing,
        constraint = CorePotts.always, tspan = (0, 10))
    st = initial_state(σ, kinds; site = (; c = copy(c0), c_next = zero(c0)))
    ph = Phases(after_mcs = (FieldStep((:site, :c) => (:site, :c_next), rate; dt, substeps),))
    f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint, phases = ph)
    return PottsProblem(f, st, lat, tspan, p; spacing)
end

@testset "fields" begin
    σ, kinds = blocks((64, 32), 6)
    p = merge(gg_params(), (; D = 0.1))

    @testset "Fourier mode decays by the exact discrete factor (h = $h)" for h in (
            (1.0, 1.0), (1.0, 0.5))
        lat = Lattice((64, 32))
        kx, ky = 3, 2
        c0 = [cos(2π * kx * (i - 1) / 64) * cos(2π * ky * (j - 1) / 32) for i in 1:64, j in 1:32]
        dt, m = 0.4, 10
        λ = (2cos(2π * kx / 64) - 2) / h[1]^2 + (2cos(2π * ky / 32) - 2) / h[2]^2
        prob = field_problem(σ, kinds, lat, c0, diffuse, merge(p, (; D = 0.2)); dt,
            spacing = h, tspan = (0, m))
        c = solve(prob, SequentialCPM()).u[end].site.c
        @test c ≈ (1 + dt * 0.2 * λ)^m .* c0 rtol = 1e-10
    end

    @testset "mass is conserved (periodic and zero-flux)" for bnd in (Periodic(), Closed())
        lat = Lattice((64, 32); boundary = bnd)
        c0 = [exp(-((i - 20)^2 + (j - 10)^2) / 30) for i in 1:64, j in 1:32]
        prob = field_problem(σ, kinds, lat, c0, diffuse, p; tspan = (0, 50))
        c = solve(prob, CheckerboardCPM()).u[end].site.c
        @test sum(c) ≈ sum(c0) rtol = 1e-12
        @test maximum(c) < maximum(c0)
    end

    @testset "substeps split the MCS" begin
        lat = Lattice((64, 32))
        c0 = [exp(-((i - 20)^2 + (j - 10)^2) / 30) for i in 1:64, j in 1:32]
        a = solve(field_problem(σ, kinds, lat, c0, diffuse, p; dt = 1.0, substeps = 4,
            tspan = (0, 3)), SequentialCPM()).u[end].site.c
        b = solve(field_problem(σ, kinds, lat, c0, diffuse, p; dt = 0.25, substeps = 1,
            tspan = (0, 12)), SequentialCPM(); ).u[end].site.c
        @test a ≈ b rtol = 1e-12
        @test stable_substeps(1.0, 1.0, (1.0, 1.0)) == 5          # 8/1.8 = 4.4
        @test stable_substeps(0.1, 1.0, (1.0, 0.5)) == 2          # 0.1·20/1.8 = 1.1
        @test stable_substeps(0.45, 1.0, (1.0, 1.0)) == 2         # 3.6/1.8 = 2 exactly
        @test stable_substeps(0.45, 1.0, (1.0, 1.0), 0.2) == 3    # the reaction rate counts
        @test stable_substeps(0.0, 1.0, (1.0,), 1.0) == 1
        for (D, dt, h, k) in ((0.5, 1.0, (1.0, 1.0), 0.2), (0.125, 2.0, (0.5, 0.5, 1.0), 1.6), (2.5, 0.5, (1.0,), 0.0))
            n = stable_substeps(D, dt, h, k)
            Λ = D * sum(x -> 4 / x^2, h) + k
            @test dt / n * Λ ≤ 1.8 * (1 + 1e-12) && n ≤ max(1, ceil(Int, dt * Λ))
        end
    end

    @testset "secretion–decay steady state" begin
        lat = Lattice((64, 32))
        secrete(st, p, ctx, key, mcs, i, c) =
            p.D * laplacian(c, ctx, i) + p.s * (owner_kind(st, i) == 1) - p.k * c[i]
        pk = merge(p, (; s = 0.2, k = 0.05))
        prob = field_problem(σ, kinds, lat, zeros(64, 32), secrete, pk; tspan = (0, 400),
            constraint = never)
        u = solve(prob, CheckerboardCPM()).u[end]
        N1 = count(i -> u.σ[i] != 0 && u.cell.kind[u.σ[i]] == 1, eachindex(u.σ))
        @test sum(u.site.c) ≈ 0.2 * N1 / 0.05 rtol = 1e-6       # d/dt Σc = s·N₁ − k·Σc
        g = gradient(u.site.c, (; lattice = lat), linear_index(lat, (10, 10)))
        @test all(isfinite, g)
    end

    @testset "gradient of a linear ramp" begin
        lat = Lattice((20, 20); boundary = Closed())
        c = [2.0i + 3.0j for i in 1:20, j in 1:20]
        ctx = (; lattice = lat, spacing = (0.5, 1.0))
        @test all(gradient(c, ctx, linear_index(lat, (7, 9))) .≈ (4.0, 3.0))
        @test laplacian(c, ctx, linear_index(lat, (7, 9))) ≈ 0 atol = 1e-12
        @test gradient(c, ctx, linear_index(lat, (1, 9)))[1] ≈ 2.0   # one-sided at the wall
    end
end
