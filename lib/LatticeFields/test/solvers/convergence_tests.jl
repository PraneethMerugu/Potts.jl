# Convergence against the reference counts (Float64: equal; Float32: PG-4 holds), the rule-M
# negative control (PG-4(c)), the analytic Helmholtz oracle (T-4) and init = :steady.

@testsetup module LF_solvers_convergence
using Test, LatticeFields
include("../host_runner.jl")
include("../solvers_cases.jl")
include("../shared/export_all.jl")
end

@testitem "iteration counts equal the reference (F64), PG-4 in F32" setup = [LF_solvers_convergence] tags = [:latticefields, :solvers] begin
@testset "iteration counts equal the reference (F64), PG-4 in F32" begin
    for (name, ss) in (("disk128", (5.5e-6, 1.9e-3, 0.022, 0.063)),
        ("sphere42", (5.5e-6, 1.9e-3, 0.022, 0.063)), ("box300x192", (5.5e-6, 1.9e-3)))
        for s in ss
            ref = REFERENCE[(name, s)]
            case = named_case(name, s)
            @test counts(case, Float64) == ref
            pcg, mg = counts(case, Float32)
            @test pcg == ref[1] && pcg <= 8
            @test mg <= ref[2] + 1
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
    sv = case_solver(disk, Float64; inner = Multigrid(), rule = half)
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
    sv = case_solver(box_case(nx, ny; s), Float64; inner = Multigrid(cycles = 2))
    steady!(sv)                                        # negative control: two cycles
    u = reshape(field(sv, lkey(0, "x")), nx, ny)
    @test maximum(abs, u .- exact) / maximum(exact) > 1e-4
end
end

@testitem "init = :steady from zero" setup = [LF_solvers_convergence] tags = [:latticefields, :solvers] begin
@testset "init = :steady from zero" begin
    @test steady!(case_solver(named_case("box300x192", 5.5e-6), Float32)) == 7
    @test steady!(case_solver(named_case("sphere42", 0.022), Float32)) == 6
end
end
