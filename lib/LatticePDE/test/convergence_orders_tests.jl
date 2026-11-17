# TS2-1: Empirical convergence orders (temporal and spatial via `observed_orders`) and
# multigrid mesh-independence across refined grids (h -> h/2 -> h/4).

@testsetup module LP_convergence_orders
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
    System, t_nounits as t, D_nounits as D
using Symbolics: Num
using DomainSets: Interval
using SciMLBase: SciMLBase, solve
using LatticeFields: LatticeFields, Problems as LFP
using OrdinaryDiffEqTsit5: Tsit5
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("../../../test/shared/convergence_helpers.jl")
include("shared/export_all.jl")
end

@testitem "TS2-1: temporal convergence orders (EE, BE, CN, BDF2, IMEX)" setup = [LP_convergence_orders] tags = [:latticepde, :convergence] begin
    @testset "TS2-1: temporal convergence orders" begin
        @variables u(..) v(..)
        ue, ve = u(t, x, y), v(t, x, y)
        # Manufactured solution u(t, x, y) = exp(t) * sin(pi * x) * sin(pi * y) on [0, 1]^2
        # u_t - 0.05 * Δu = (1 + 0.1 * pi^2) * exp(t) * sin(pi * x) * sin(pi * y)
        Dcoef = 0.005
        src = (1.0 + 2.0 * Dcoef * pi^2) * exp(t) * sin(pi * x) * sin(pi * y)
        sys = PDESystem(
            [D(ue) ~ Dcoef * Δ(ue) + src],
            [
                u(0, x, y) ~ sin(pi * x) * sin(pi * y),
                u(t, 0, y) ~ 0.0, u(t, 1, y) ~ 0.0, u(t, x, 0) ~ 0.0, u(t, x, 1) ~ 0.0,
            ],
            [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
            [t, x, y], [ue], Num[]; name = :mms_time
        )
        prob = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64))
        # Reference semi-discrete ODE solution (eliminates spatial error)
        ref = solve(prob, Tsit5(); abstol = 1.0e-12, reltol = 1.0e-12).u[end]

        dts = [0.04, 0.02, 0.01]
        for (label, alg, target_order, tol) in (
                ("ExplicitEuler", ExplicitEuler(; substeps = 1), 1.0, 0.15),
                ("BackwardEuler", BackwardEuler(; linsolve = BTIGHT), 1.0, 0.15),
                ("CrankNicolson", CrankNicolson(; linsolve = BTIGHT), 2.0, 0.15),
                ("BDF2", BDF2(; linsolve = BTIGHT), 2.0, 0.15),
            )
            @testset "$label" begin
                errs = [maximum(abs, solve(prob, alg; dt).u[end] .- ref) for dt in dts]
                orders = observed_orders(dts, errs)
                @test all(o -> abs(o - target_order) < tol, orders)
                @test abs(observed_order(dts, errs) - target_order) < tol
            end
        end

        @testset "IMEX FieldGroups (ExplicitEuler + BackwardEuler)" begin
            imex_sys = PDESystem(
                [D(ue) ~ Dcoef * Δ(ue) - 0.5 * ve + src, D(ve) ~ 0.2 * Δ(ve) - ve + 0.5 * ue],
                [
                    u(0, x, y) ~ sin(pi * x) * sin(pi * y), v(0, x, y) ~ x * (1 - x) * y * (1 - y),
                    u(t, 0, y) ~ 0.0, u(t, 1, y) ~ 0.0, u(t, x, 0) ~ 0.0, u(t, x, 1) ~ 0.0,
                    v(t, 0, y) ~ 0.0, v(t, 1, y) ~ 0.0, v(t, x, 0) ~ 0.0, v(t, x, 1) ~ 0.0,
                ],
                [t ∈ Interval(0.0, 0.2), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)],
                [t, x, y], [ue, ve], Num[]; name = :imex_time
            )
            iprob = discretize(imex_sys, LatticeDiscretization(Grid((12, 12)); T = Float64))
            iref = solve(iprob, Tsit5(); abstol = 1.0e-12, reltol = 1.0e-12).u[end]
            idts = [0.02, 0.01, 0.005]
            errs = [
                maximum(
                    abs, solve(
                        iprob, FieldGroups(
                            ue => ExplicitEuler(; substeps = 1),
                            ve => BackwardEuler(; linsolve = BTIGHT)
                        )
                        ; dt
                    ).u[end] .- iref
                ) for dt in idts
            ]
            orders = observed_orders(idts, errs)
            @test all(o -> abs(o - 1.0) < 0.15, orders)
            @test abs(observed_order(idts, errs) - 1.0) < 0.15
        end
    end
end

@testitem "TS2-1: spatial convergence orders (DivKGrad, Upwind1, Robin, Hex)" setup = [LP_convergence_orders] tags = [:latticepde, :convergence] begin
    @testset "TS2-1: spatial convergence orders" begin
        @variables u(..)
        ue = u(t, x, y)
        fdom = [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]

        @testset "DivKGrad(:harmonic and :arithmetic) variable coefficient O(h^2)" begin
            # Exact steady u(x, y) = sin(pi * x) * sin(pi * y), K(x, y) = 1 + 0.5 * x
            # -div(K grad u) + u = K * 2*pi^2 * sin(pi*x)*sin(pi*y) - 0.5*pi*cos(pi*x)*sin(pi*y) + u
            Kexpr = 1.0 + 0.5 * x
            exact_fn(xx, yy) = sin(pi * xx) * sin(pi * yy)
            rhs_src = Kexpr * 2 * pi^2 * sin(pi * x) * sin(pi * y) - 0.5 * pi * cos(pi * x) * sin(pi * y) + exact_fn(x, y)
            for mean_kind in (:harmonic, :arithmetic)
                sys = PDESystem(
                    [0 ~ DivKGrad(mean_kind)(Kexpr, u(x, y)) - u(x, y) + rhs_src],
                    [u(0, y) ~ 0.0, u(1, y) ~ 0.0, u(x, 0) ~ 0.0, u(x, 1) ~ 0.0],
                    fdom, [x, y], [u(x, y)], Num[]; name = Symbol(:dkg_, mean_kind)
                )
                ns = [16, 32, 64]
                hs = 1.0 ./ ns
                errs = map(ns) do N
                    lp = discretize(sys, LatticeDiscretization(Grid((N, N)); T = Float64))
                    sol = solve(lp, LatticePCG(); reltol = 1.0e-12, abstol = 0.0)
                    h = 1.0 / N
                    xs = ((1:N) .- 0.5) .* h
                    ex = [exact_fn(xx, yy) for xx in xs, yy in xs]
                    maximum(abs, reshape(sol.u, N, N) .- ex)
                end
                orders = observed_orders(hs, errs)
                @test all(o -> abs(o - 2.0) < 0.15, orders)
                @test abs(observed_order(hs, errs) - 2.0) < 0.15
            end
        end

        @testset "Advect(Upwind1()) spatial order O(h)" begin
            # Steady periodic advection-reaction: 0 = -∂_x u - u + (2π cos(2πx) + sin(2πx))
            sys = PDESystem(
                [0 ~ -Advect(Upwind1())([1.0, 0.0], u(x, y)) - u(x, y) + 2 * pi * cos(2 * pi * x) + sin(2 * pi * x)],
                [u(0, y) ~ u(1, y), u(x, 0) ~ u(x, 1)],
                fdom, [x, y], [u(x, y)], Num[]; name = :upwind_order
            )
            ns = [16, 32, 64, 128]
            hs = 1.0 ./ ns
            errs = map(ns) do N
                lp = discretize(sys, LatticeDiscretization(Grid((N, 8)); T = Float64))
                uvec = LFP.lattice_matrix(lp.A) \ lp.b
                h = 1.0 / N
                xs = ((1:N) .- 0.5) .* h
                ex = [sin(2 * pi * xx) for xx in xs, _ in 1:8]
                maximum(abs, reshape(uvec, N, 8) .- ex)
            end
            orders = observed_orders(hs, errs)
            @test all(o -> abs(o - 1.0) < 0.15, orders)
            @test abs(observed_order(hs, errs) - 1.0) < 0.15
        end

        @testset "Robin face spatial order O(h^2)" begin
            # Exact steady u(x, y) = x^2 + 1 on [0, 1]^2:
            # Δu = 2, -u_x(0, y) + 1.5 * u(0, y) = 1.5, u(1, y) = 2, u_y = 0 at y = 0, 1
            sys = PDESystem(
                [0 ~ Δ(u(x, y)) - u(x, y) + (x^2 + 1 - 2)],
                [
                    1.5 * u(0, y) - Differential(x)(u(0, y)) ~ 1.5, u(1, y) ~ 2.0,
                    Differential(y)(u(x, 0)) ~ 0.0, Differential(y)(u(x, 1)) ~ 0.0,
                ],
                fdom, [x, y], [u(x, y)], Num[]; name = :robin_order
            )
            ns = [16, 32, 64]
            hs = 1.0 ./ ns
            errs = map(ns) do N
                lp = discretize(sys, LatticeDiscretization(Grid((N, N)); T = Float64))
                sol = solve(lp, LatticePCG(); reltol = 1.0e-12, abstol = 0.0)
                h = 1.0 / N
                xs = ((1:N) .- 0.5) .* h
                ex = [xx^2 + 1.0 for xx in xs, _ in xs]
                maximum(abs, reshape(sol.u, N, N) .- ex)
            end
            orders = observed_orders(hs, errs)
            @test all(o -> abs(o - 2.0) < 0.15, orders)
            @test abs(observed_order(hs, errs) - 2.0) < 0.15
        end

        @testset "Hexagonal Laplacian spatial order O(h^2)" begin
            # Periodic 1D Helmholtz on axial Hex grid: Δ_hex u = (4/3) ∂_x^2 u for u(x, y) = sin(2πx)
            sys = PDESystem(
                [0 ~ 0.75 * Δ(u(x, y)) - u(x, y) + (4 * pi^2 + 1) * sin(2 * pi * x)],
                [u(0, y) ~ u(1, y), u(x, 0) ~ u(x, 1)],
                fdom, [x, y], [u(x, y)], Num[]; name = :hex_order
            )
            ns = [16, 32, 64]
            hs = 1.0 ./ ns
            errs = map(ns) do N
                lp = discretize(sys, LatticeDiscretization(Grid((N, N); geometry = HEX); T = Float64))
                sol = solve(lp, LatticePCG(); reltol = 1.0e-12, abstol = 0.0)
                h = 1.0 / N
                xs = ((1:N) .- 0.5) .* h
                ex = [sin(2 * pi * xx) for xx in xs, _ in 1:N]
                maximum(abs, reshape(sol.u, N, N) .- ex)
            end
            orders = observed_orders(hs, errs)
            @test all(o -> abs(o - 2.0) < 0.2, orders)
            @test abs(observed_order(hs, errs) - 2.0) < 0.2
        end
    end
end

@testitem "TS2-1: multigrid mesh-independence under grid refinement (h -> h/2 -> h/4)" setup = [LP_convergence_orders] tags = [:latticepde, :convergence] begin
    @testset "TS2-1: multigrid mesh-independence under grid refinement" begin
        @variables w(..)
        fdom = [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        exact_fn(xx, yy) = sin(pi * xx) * sin(pi * yy)
        rhs = (0.3 * 2 * pi^2 + 2.0) * sin(pi * x) * sin(pi * y)
        sys = PDESystem(
            [0 ~ 0.3 * Δ(w(x, y)) - 2.0 * w(x, y) + rhs],
            [w(0, y) ~ 0.0, w(1, y) ~ 0.0, w(x, 0) ~ 0.0, w(x, 1) ~ 0.0],
            fdom, [x, y], [w(x, y)], Num[]; name = :mg_mesh_indep
        )

        ns = [32, 64, 128]
        hs = 1.0 ./ ns
        errs = Float64[]
        iters = Int[]
        for N in ns
            lp = discretize(sys, LatticeDiscretization(Grid((N, N)); T = Float64))
            sol = solve(lp, LatticePCG(); reltol = 1.0e-12, abstol = 0.0)
            @test SciMLBase.successful_retcode(sol)
            push!(iters, sol.iters)
            h = 1.0 / N
            xs = ((1:N) .- 0.5) .* h
            ex = [exact_fn(xx, yy) for xx in xs, yy in xs]
            push!(errs, maximum(abs, reshape(sol.u, N, N) .- ex))
        end
        # Iteration counts stay bounded and mesh-independent (no O(N) blowup)
        @test all(<=(25), iters)
        @test maximum(iters) - minimum(iters) <= 6
        # Spatial error converges at O(h^2)
        orders = observed_orders(hs, errs)
        @test all(o -> abs(o - 2.0) < 0.1, orders)
        @test abs(observed_order(hs, errs) - 2.0) < 0.1
    end
end
