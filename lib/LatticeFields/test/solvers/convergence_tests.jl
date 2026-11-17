# Mesh-independent MG convergence / contraction-factor bounds across refined grids (h, h/2, h/4),
# the rule-M negative control (PG-4(c)), the analytic Helmholtz oracle (T-4), and init = :steady
# residual-reduction checks.

@testsetup module LF_solvers_convergence
using Test, LatticeFields
include("../host_runner.jl")
include("../solvers_cases.jl")
include("../../../../test/shared/convergence_helpers.jl")
include("../shared/export_all.jl")
end

@testitem "mesh-independent MG contraction across refined grids and PCG/MG convergence" setup = [LF_solvers_convergence] tags = [:latticefields, :solvers] begin
@testset "mesh-independent MG contraction across refined grids and PCG/MG convergence" begin
    # Refined grids (h, h/2, h/4) with shift scaled by h^2 so the physical Helmholtz length
    # 1 / sqrt(s_phys) is constant across refinements: V(2,2) contraction stays bounded and
    # mesh-independent within 0.05.
    for (kind, ns, s0) in (("box", (64, 128, 256), 5.5e-6), ("disk", (64, 128, 256), 5.5e-6))
        rhos = [cycle_factor(named_case("$(kind)$(n)", s0 * (128 / n)^2)) for n in ns]
        @test all(<(0.35), rhos)
        @test maximum(rhos) - minimum(rhos) <= 0.05
    end

    # PCG and stationary V(2,2) convergence across geometries, shifts, and precisions:
    # D-C7b bounds PCG <= 12; stationary V(2,2) with rho < 0.35 reaches 1e-6 within 15-20 cycles.
    for (name, ss) in (("disk128", (5.5e-6, 1.9e-3, 0.022, 0.063)),
        ("sphere42", (5.5e-6, 1.9e-3, 0.022, 0.063)), ("box300x192", (5.5e-6, 1.9e-3)))
        for s in ss
            case = named_case(name, s)
            for T in (Float64, Float32)
                    sv_pcg = case_solver(case, T; linsolve = DevicePCG(), deflate = false)
                k_pcg = steady!(sv_pcg; maxiter = 40)
                sc_pcg = scalars(sv_pcg)
                @test sc_pcg.done && sc_pcg.status === :done && k_pcg <= 12
                @test sc_pcg.rnorm <= 1e-6 * sc_pcg.bnorm

                    sv_mg = case_solver(case, T; linsolve = Multigrid())
                k_mg = steady!(sv_mg; maxiter = 40)
                sc_mg = scalars(sv_mg)
                @test sc_mg.done && sc_mg.status === :done && k_mg <= 20
                @test sc_mg.rnorm <= 1e-6 * sc_mg.bnorm
            end
        end
    end
end
end

@testitem "rule M against ½Σ with the Any fold (PG-4(c)), factors" setup = [LF_solvers_convergence] tags = [:latticefields, :solvers] begin
@testset "rule M against ½Σ with the Any fold (PG-4(c)), factors" begin
    half = RuleWeights(inside = 0.5, plane = 0.5, inherited = 0.5)
    sph = named_case("sphere42", 5.5e-6)
    @test cycle_factor(sph) < 0.25                     # reference 0.196 (2-norm)
    @test cycle_factor(sph; rule = half) > 1           # diverges (reference 1.31)
    disk = named_case("disk128", 1.9e-3)
    @test cycle_factor(disk) < 0.3
        sv = case_solver(disk, Float64; linsolve = Multigrid(), rule = half)
    steady!(sv; maxiter = 20)
    @test !scalars(sv).done                            # stalls (floor) or runs out
end
end

@testitem "analytic oracle: 1D Helmholtz between Dirichlet faces (T-4)" setup = [LF_solvers_convergence] tags = [:latticefields, :solvers] begin
@testset "analytic oracle: 1D Helmholtz between Dirichlet faces (T-4)" begin
    nx, ny, s = 300, 192, 5.5e-6
    ℓ = 1 / sqrt(s)                                    # cells
    x = ((1:nx) .- 0.5)
    exact = sinh.(x ./ ℓ) ./ sinh(nx / ℓ)
    for T in (Float64, Float32)
        sv = case_solver(box_case(nx, ny; s), T)
        steady!(sv)
        u = reshape(field(sv, "pcg.x"), nx, ny)
        @test maximum(abs, u .- exact) / maximum(exact) < 1e-4
    end
        sv = case_solver(box_case(nx, ny; s), Float64; linsolve = Multigrid(cycles = 2))
    steady!(sv)                                        # negative control: two cycles
    u = reshape(field(sv, lkey(0, "x")), nx, ny)
    @test maximum(abs, u .- exact) / maximum(exact) > 1e-4
end
end

@testitem "init = :steady from zero" setup = [LF_solvers_convergence] tags = [:latticefields, :solvers] begin
@testset "init = :steady from zero" begin
    for (name, s) in (("box300x192", 5.5e-6), ("sphere42", 0.022))
        sv = case_solver(named_case(name, s), Float32)
        k = steady!(sv)
        sc = scalars(sv)
        @test sc.done && sc.status === :done && 1 <= k <= 12
        @test sc.rnorm <= 1e-6 * sc.bnorm
        @test maximum(abs, true_residual(sv)) <= 1e-5 * sc.bnorm
        @test solve!(sv; host = true) == 0 && scalars(sv).done
    end
end
end

@testitem "1D Helmholtz discrete solver spatial refinement order (O(h^2))" setup = [LF_solvers_convergence] tags = [:latticefields, :solvers] begin
    @testset "1D Helmholtz discrete solver spatial refinement order" begin
        # Physical domain [0, 1] with u(0) = 0, u(1) = 1 and Helmholtz parameter s_phys = 4.0:
        # discrete shift is s_phys * h^2. Cell-centered FD gives O(h^2) convergence to exact sinh.
        s_phys = 4.0
        lam = sqrt(s_phys)
        ns = [32, 64, 128]
        hs = 1.0 ./ ns
        errs = map(ns) do nx
            h = 1.0 / nx
            ny = 16
            sv = case_solver(box_case(nx, ny; s = s_phys * h^2), Float64)
            steady!(sv)
            u = reshape(field(sv, "pcg.x"), nx, ny)
            x = ((1:nx) .- 0.5) .* h
            exact = sinh.(lam .* x) ./ sinh(lam)
            maximum(abs, u .- exact)
        end
        orders = observed_orders(hs, errs)
        @test all(o -> abs(o - 2.0) < 0.1, orders)
        @test abs(observed_order(hs, errs) - 2.0) < 0.1
    end
end
