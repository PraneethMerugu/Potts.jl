# The lattice solvers as LinearSolve.jl algorithms: `LatticePCG`, `LatticeGMRES` and `Multigrid`
# pass LinearSolve's interface check; `solve(LinearProblem(A, b), alg)` on a lattice field's
# operator (`BoundOperator`) gives the bits of the field solver driven directly (`rebuild!`,
# `lift!`, `solve!`), at a first solve and after a new right-hand side; the generic path (any
# other operator) is CG on `−A`; a `precs` the fused path cannot apply and a `Multigrid` on a
# matrix are refused, naming the route.

@testsetup module LF_solvers_linearsolve
using Test, LatticeFields
include("../host_runner.jl")
include("../solvers_cases.jl")
using LatticeFields.Solvers: BoundOperator, LatticeGMRES, iterations
using LinearSolve: LinearSolve, LinearProblem, init, solve
using SciMLBase: ReturnCode
using LinearAlgebra: I, SymTridiagonal
# (the test executor's scalars are host memory: the solve reads its status for free)
Solvers.host_scalars(::HostExec, scal) = scal isa Array

# a masked disk with a random right-hand side
function disk(T, n = 48; s = 0.02)
    op, ins = ball_case((n, n); s)
    b = T.(rand(Xoshiro(3), n * n))
    return op, ins, b
end
# the field solver driven directly: its solution after `rebuild!`, `lift!` and `solve!`
function direct(op, ins, b, T, linsolve; maxiters = nothing)
    sv = FieldSolver(HostExec(), op; T, linsolve, inputs = ("in.f" => b, ins...))
    rebuild!(sv)
    lift!(sv)
    maxiters === nothing ? solve!(sv) : solve!(sv; maxiters)
    return sv
end
include("../shared/export_all.jl")
end

@testitem "the lattice solvers pass LinearSolve's interface check" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    for alg in (LatticePCG(), LatticeGMRES(), Multigrid(), LatticePCG(; precs = LatticeMultigrid(; cycle = (3, 3)), maxiters = 4))
        @test isempty(LinearSolve.algorithm_interface_issues(alg))
    end
    @test !LinearSolve.needs_concrete_A(LatticePCG()) && !LinearSolve.needs_concrete_A(Multigrid())
end

@testitem "solve(LinearProblem) on a field's operator gives the direct solve's bits" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    for T in (Float32, Float64)
        op, ins, b = disk(T)
        # PCG: the budget and the tolerance are LinearSolve's keywords
        sv = direct(op, ins, b, T, LatticePCG(; maxiters = 8, reltol = 1.0e-6))
        x = copy(field(sv, solution_key(sv)))
        A = BoundOperator(HostExec(), op; T, inputs = ins)
        sol = solve(LinearProblem(A, b), LatticePCG(); maxiters = 8, reltol = 1.0e-6)
        @test sol.u == x
        @test sol.iters == iterations(sv) && sol.retcode == (scalars(sv).done ? ReturnCode.Success : ReturnCode.MaxIters)
        # the same values given on the algorithm, and a non-default cycle
        @test solve(LinearProblem(A, b), LatticePCG(; maxiters = 8, reltol = 1.0e-6)).u == x
        # (an unset `reltol` is the solve's: LinearSolve's default is √eps)
        alg = LatticePCG(; precs = LatticeMultigrid(; cycle = (3, 3)), maxiters = 5)
        sv3 = direct(op, ins, b, T, alg)
        @test solve(LinearProblem(A, b), alg; reltol = 1.0e-6).u == field(sv3, solution_key(sv3))
        # stationary multigrid
        mg = Multigrid(; cycles = 3)
        svm = direct(op, ins, b, T, mg)
        solm = solve(LinearProblem(A, b), mg)
        @test solm.u == field(svm, solution_key(svm)) && solm.retcode == ReturnCode.Success
        # a cache: a new right-hand side warm-starts from the last solution, as the direct
        # solver does after a write into its `"in.f"`
        c = init(LinearProblem(A, copy(b)), LatticePCG(; maxiters = 8, reltol = 1.0e-6))
        LinearSolve.solve!(c)
        b2 = T.(rand(Xoshiro(5), length(b)))
        c.b = b2
        u2 = copy(LinearSolve.solve!(c).u)
        copyto!(b, b2)
        lift!(sv)
        solve!(sv)
        @test u2 == field(sv, solution_key(sv))
    end
end

@testitem "the generic path and the refusals" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    # any other operator: CG on `−A` (negative definite here), `precs` LinearSolve's contract
    n = 40
    A = -SymTridiagonal(fill(2.5, n), fill(-1.0, n - 1))
    b = collect(range(-1.0, 1.0; length = n))
    sol = solve(LinearProblem(A, b), LatticePCG(; precs = (A, p) -> (I, I)); reltol = 1.0e-12, maxiters = 200)
    @test sol.retcode == ReturnCode.Success && isapprox(sol.u, A \ b; rtol = 1.0e-9)
    @test solve(LinearProblem(A, b), LatticePCG(; precs = (A, p) -> (I, I), maxiters = 2); reltol = 1.0e-12).retcode == ReturnCode.MaxIters
    # a field's operator takes `precs = LatticeMultigrid(…)` (fused); a stationary
    # `Multigrid` solves a field's operator only
    op, ins, bb = disk(Float64, 16)
    Bop = BoundOperator(HostExec(), op; T = Float64, inputs = ins)
    @test_throws ["ArgumentError", "precs = LatticeMultigrid"] solve(LinearProblem(Bop, bb), LatticePCG(; precs = (A, p) -> (I, I)); maxiters = 4)
    @test_throws ["ArgumentError", "`Multigrid` solves a lattice field's operator"] solve(LinearProblem(A, b), Multigrid())
    # the keywords are checked, naming the keyword
    @test_throws ["ArgumentError", "`LatticePCG(; maxiters = 0)`"] LatticePCG(; maxiters = 0)
    @test_throws ["ArgumentError", "`LatticeGMRES(; gmres_restart = 1)`"] LatticeGMRES(; gmres_restart = 1)
    @test_throws ["ArgumentError", "`LatticeMultigrid(; cycles = 0)`"] LatticeMultigrid(; cycles = 0)
end
