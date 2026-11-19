# The lattice solvers as LinearSolve.jl algorithms: `LatticePCG`, `LatticeGMRES` and
# `LatticeMultigrid` pass LinearSolve's interface check; `solve(LinearProblem(A, b), alg)` on
# a lattice field's operator (`BoundOperator`) gives the bits of the field solver driven
# directly (`rebuild!`, `lift!`, `solve!`), at a first solve and after a new right-hand side;
# `BoundOperator` supports `mul!`/`*` and `FusedVCycle` supports `ldiv!`, so `KrylovJL_CG(;
# precs = LatticeMultigrid())` works on `BoundOperator`; non-fused `precs` (including `nothing`)
# fall back to the generic CG path; `LatticeMultigrid` on a non-field matrix is refused, naming
# the route.

@testsetup module LF_solvers_linearsolve
using Test, LatticeFields
include("../host_runner.jl")
include("../solvers_cases.jl")
using KernelAbstractions: Backend
using LatticeFields: Schedule
using LatticeFields.Solvers: BoundOperator, LatticeGMRES, iterations
using LinearSolve: LinearSolve, KrylovJL_CG, KLUFactorization, UMFPACKFactorization, LinearProblem, init, reinit!, solve
using SciMLBase: ReturnCode
using LinearAlgebra: I, SymTridiagonal, mul!
using SparseArrays: sparse
# (the test executor's scalars are host memory: the solve reads its status for free;
# `MockDevExec` delegates execution to `HostExec` with `host_scalars === false` for the device path)
Solvers.host_scalars(::HostExec, scal) = scal isa Array
struct MockDevExec end
Solvers.alloc(::MockDevExec, ::Type{T}, n) where {T} = zeros(T, n)
Schedule.supports(::MockDevExec, ::Type{Float64}) = true
Solvers.to_host(::MockDevExec, A) = copy(A)
Solvers.launch!(::MockDevExec, l::Solvers.Launch) = Solvers.launch!(HostExec(), l)
Solvers.host_scalars(::MockDevExec, scal) = false
struct MockGPUBackend <: Backend end
struct _NoBackendVec <: AbstractVector{Float64}
    n::Int
end
Base.size(v::_NoBackendVec) = (v.n,)
Base.getindex(v::_NoBackendVec, ::Int) = 0.0

# a masked disk with a random right-hand side (`homog_disk`: zero boundary data, linear `A * x = b`)
function disk(T, n = 48; s = 0.02)
    op, ins = ball_case((n, n); s)
    b = T.(rand(Xoshiro(3), n * n))
    return op, ins, b
end
function homog_disk(T, n = 48; s = 0.02)
    op, ins = ball_case((n, n); s)
    op0 = CellOperator(op.dims; periodic = op.periodic, shift = op.shift, mask = op.mask, value = 0.0)
    b = T.(rand(Xoshiro(3), n * n))
    mask = ins[1][2]
    b[mask .!= 0] .= zero(T)
    return op0, ins, b
end
# the field solver driven directly: its solution after `rebuild!`, `lift!` and `solve!`
function direct(op, ins, b, T, linsolve; maxiters = nothing)
    sv = FieldSolver(HostExec(), op; T, linsolve, inputs = ("in.f" => b, ins...))
    rebuild!(sv)
    lift!(sv)
    maxiters === nothing ? solve!(sv) : solve!(sv; maxiters)
    return sv
end
function err_msg(f)
    try
        f()
        return ""
    catch err
        return err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
end
include("../shared/export_all.jl")
end

@testitem "the lattice solvers pass LinearSolve's interface check" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    for alg in (
            LatticePCG(), LatticeGMRES(), LatticeMultigrid(),
            LatticePCG(; precs = LatticeMultigrid(; cycle = (3, 3)), maxiters = 4),
        )
        @test isempty(LinearSolve.algorithm_interface_issues(alg))
        @test !LinearSolve.needs_concrete_A(alg)
    end
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
        # the same values given on the algorithm, and an unset `maxiters` uses the fused default (8)
        @test solve(LinearProblem(A, b), LatticePCG(; maxiters = 8, reltol = 1.0e-6)).u == x
        @test solve(LinearProblem(A, b), LatticePCG(; reltol = 1.0e-6)).u == x
        # a non-default cycle
        alg = LatticePCG(; precs = LatticeMultigrid(; cycle = (3, 3)), maxiters = 5)
        sv3 = direct(op, ins, b, T, alg)
        @test solve(LinearProblem(A, b), alg; reltol = 1.0e-6).u == field(sv3, solution_key(sv3))
        # stationary multigrid (including LinearSolve reltol/maxiters overrides)
        mg = LatticeMultigrid(; cycles = 3)
        svm = direct(op, ins, b, T, mg)
        solm = solve(LinearProblem(A, b), mg)
        @test solm.u == field(svm, solution_key(svm)) && solm.retcode == ReturnCode.Success
        svm2 = direct(op, ins, b, T, LatticeMultigrid(; maxiters = 4, reltol = 1.0e-5))
        solm2 = solve(LinearProblem(A, b), LatticeMultigrid(); maxiters = 4, reltol = 1.0e-5)
        @test solm2.u == field(svm2, solution_key(svm2))
        # a cache: a new right-hand side warm-starts from the last solution
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

@testitem "BoundOperator mul!, KrylovJL_CG with LatticeMultigrid, and the device retcode" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    for T in (Float32, Float64)
        op, ins, b = homog_disk(T)
        A = BoundOperator(HostExec(), op; T, inputs = ins)
        sp = solve(LinearProblem(A, b), LatticePCG(); maxiters = 32, reltol = T == Float32 ? 1.0e-5 : 1.0e-10)
        y = similar(b)
        mul!(y, A, sp.u)
        @test y == A * sp.u
        @test isapprox(y, b; rtol = T == Float32 ? 1.0e-4 : 1.0e-8)
        sk = solve(LinearProblem(A, b), KrylovJL_CG(; precs = LatticeMultigrid()); reltol = T == Float32 ? 1.0e-5 : 1.0e-10, abstol = zero(T), maxiters = 64)
        @test sk.retcode == ReturnCode.Success
        @test isapprox(sk.u, sp.u; rtol = T == Float32 ? 1.0e-4 : 1.0e-8)
    end
    # fused device path (`host_scalars === false`): returns `ReturnCode.Default` with `iters = 0` and the host solution's bits
    op, ins, b = disk(Float64)
    Ah = BoundOperator(HostExec(), op; T = Float64, inputs = ins)
    Ad = BoundOperator(MockDevExec(), op; T = Float64, inputs = ins)
    sh = solve(LinearProblem(Ah, b), LatticePCG(); maxiters = 8, reltol = 1.0e-6)
    sd = solve(LinearProblem(Ad, b), LatticePCG(); maxiters = 8, reltol = 1.0e-6)
    @test sd.u == sh.u && sd.retcode == ReturnCode.Default && sd.iters == 0
    sdm = solve(LinearProblem(Ad, b), LatticeMultigrid(; cycles = 3))
    @test sdm.retcode == ReturnCode.Default && sdm.iters == 0
end

@testitem "the generic path, cache refreshes with precs = nothing, and the refusals" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    # any other operator: CG on `−A` (negative definite here), `precs` LinearSolve's contract
    n = 40
    A = -SymTridiagonal(fill(2.5, n), fill(-1.0, n - 1))
    b = collect(range(-1.0, 1.0; length = n))
    sol = solve(LinearProblem(A, b), LatticePCG(; precs = (A, p) -> (I, I)); reltol = 1.0e-12, maxiters = 200)
    @test sol.retcode == ReturnCode.Success && isapprox(sol.u, A \ b; rtol = 1.0e-9)
    @test solve(LinearProblem(A, b), LatticePCG(; precs = (A, p) -> (I, I), maxiters = 2); reltol = 1.0e-12).retcode == ReturnCode.MaxIters
    # `LatticeGMRES` on a plain matrix with `precs = nothing`, plus `cache.A = ...` and `reinit!` refresh
    A2 = -SymTridiagonal(fill(3.5, n), fill(-1.0, n - 1))
    sg = solve(LinearProblem(A, b), LatticeGMRES(; precs = nothing); reltol = 1.0e-12, abstol = 0.0, maxiters = 100)
    @test sg.retcode == ReturnCode.Success && isapprox(sg.u, A \ b; rtol = 1.0e-9)
    for alg in (LatticePCG(; precs = nothing), LatticeGMRES(; precs = nothing))
        c = init(LinearProblem(A, b), alg; reltol = 1.0e-12, abstol = 0.0, maxiters = 100)
        @test isapprox(LinearSolve.solve!(c).u, A \ b; rtol = 1.0e-9)
        c.A = A2
        @test isapprox(LinearSolve.solve!(c).u, A2 \ b; rtol = 1.0e-9)
        reinit!(c; A = A)
        @test isapprox(LinearSolve.solve!(c).u, A \ b; rtol = 1.0e-9)
    end
    # generic CG path on a `BoundOperator`: `precs = (A, p) -> (I, I)` and `precs = nothing` (negative control: more iters than preconditioned)
    op, ins, bb = homog_disk(Float64, 32)
    Bop = BoundOperator(HostExec(), op; T = Float64, inputs = ins)
    sf = solve(LinearProblem(Bop, bb), LatticePCG(); reltol = 1.0e-8, maxiters = 64)
    su = solve(LinearProblem(Bop, bb), LatticePCG(; precs = nothing); reltol = 1.0e-8, abstol = 0.0, maxiters = 200)
    si = solve(LinearProblem(Bop, bb), LatticePCG(; precs = (M, p) -> (I, I)); reltol = 1.0e-8, abstol = 0.0, maxiters = 200)
    @test su.retcode == ReturnCode.Success && si.retcode == ReturnCode.Success
    @test isapprox(su.u, sf.u; rtol = 1.0e-6) && isapprox(si.u, sf.u; rtol = 1.0e-6)
    @test su.iters > sf.iters
    # refusals (typed ArgumentError plus message token)
    @test_throws ArgumentError solve(LinearProblem(A, b), LatticeMultigrid())
    @test occursin("lattice field", err_msg(() -> solve(LinearProblem(A, b), LatticeMultigrid())))
    @test_throws ArgumentError solve(LinearProblem(A, b), LatticeGMRES())
    @test occursin("precs = LatticeMultigrid()", err_msg(() -> solve(LinearProblem(A, b), LatticeGMRES())))
    @test_throws ArgumentError solve(LinearProblem(Bop, bb), LatticePCG(); maxiters = 2000)
    @test occursin("maxiters", err_msg(() -> solve(LinearProblem(Bop, bb), LatticePCG(); maxiters = 2000)))
    @test_throws ArgumentError LatticePCG(; maxiters = 0)
    @test occursin("maxiters", err_msg(() -> LatticePCG(; maxiters = 0)))
    @test_throws ArgumentError LatticeGMRES(; gmres_restart = 1)
    @test occursin("gmres_restart", err_msg(() -> LatticeGMRES(; gmres_restart = 1)))
    @test_throws ArgumentError LatticeMultigrid(; cycles = 0)
    @test occursin("cycles", err_msg(() -> LatticeMultigrid(; cycles = 0)))
end

@testitem "BoundOperator CSC assembly, KLUFactorization / UMFPACKFactorization, and device backend refusal" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    op, ins, b = homog_disk(Float64, 32)
    A = BoundOperator(HostExec(), op; T = Float64, inputs = ins)
    M = sparse(A)
    x = rand(Xoshiro(7), length(b))
    @test M * x ≈ A * x rtol = 1.0e-12
    # Hex operator CSC matches mul! as well
    op_hex = CellOperator((12, 10); periodic = (false, true), shift = 0.05, face = (0.3, 0.2, 0.15), dirichlet = ((0.0, 0.0), (nothing, nothing)), hex = true)
    A_hex = BoundOperator(HostExec(), op_hex; T = Float64)
    @test sparse(A_hex) * rand(Xoshiro(11), 120) ≈ A_hex * rand(Xoshiro(11), 120) rtol = 1.0e-12
    # KLU and UMFPACK match LatticePCG on BoundOperator
    sp = solve(LinearProblem(A, b), LatticePCG(); maxiters = 48, reltol = 1.0e-12)
    for fact in (KLUFactorization(), UMFPACKFactorization())
        sf = solve(LinearProblem(A, b), fact)
        @test sf.u ≈ sp.u rtol = 1.0e-10
    end
    # Device backend refuses concrete-A factorizations with matrix-free route
    @test_throws ArgumentError Solvers.field_cache(MockGPUBackend(), op, KLUFactorization(); T = Float64, inputs = ("in.f" => b, ins...))
    msg = err_msg(() -> Solvers.field_cache(MockGPUBackend(), op, KLUFactorization(); T = Float64, inputs = ("in.f" => b, ins...)))
    @test occursin("LatticePCG", msg)
    Ag = BoundOperator(MockGPUBackend(), op; T = Float64, inputs = ins)
    @test_throws ArgumentError convert(AbstractMatrix, Ag)
    @test occursin("LatticePCG", err_msg(() -> convert(AbstractMatrix, Ag)))

    # Float32 state with KLUFactorization assembles a Float64 CSC under :auto and refuses explicit solver_type = Float32
    op32, ins32, b32 = homog_disk(Float32, 24)
    c32, _ = Solvers.bound_field_cache(HostExec(), op32, KLUFactorization(); T = Float32, solver_type = :auto, inputs = ("in.f" => b32, ins32...))
    @test eltype(c32.A) == Float64 && eltype(c32.b) == Float64 && eltype(c32.u) == Float64
    sol32 = LinearSolve.solve!(c32)
    @test sol32.retcode == ReturnCode.Success
    sp32 = solve(LinearProblem(BoundOperator(HostExec(), op32; T = Float32, solver_type = Float64, inputs = ins32), b32), LatticePCG(); maxiters = 48, reltol = 1.0e-7)
    @test Float32.(sol32.u) ≈ sp32.u rtol = 1.0e-5
    @test_throws ArgumentError Solvers.field_cache(HostExec(), op32, KLUFactorization(); T = Float32, solver_type = Float32, inputs = ("in.f" => b32, ins32...))
    @test occursin("Float64", err_msg(() -> Solvers.field_cache(HostExec(), op32, KLUFactorization(); T = Float32, solver_type = Float32, inputs = ("in.f" => b32, ins32...))))
end

@testitem "FusedVCycle reuses held FieldSolver across precs refreshes" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    using LinearAlgebra: ldiv!
    op, ins, b = homog_disk(Float64, 24)
    mg = LatticeMultigrid()
    A1 = BoundOperator(HostExec(), op; T = Float64, inputs = ins)
    P1, _ = mg(A1, nothing)
    y = similar(b)
    ldiv!(y, P1, b)
    sv1 = only(values(mg.engines))[]
    @test sv1 isa FieldSolver
    # Refresh with updated coefficients on the same operator structure and inputs: same FieldSolver reused
    op2 = CellOperator(op.dims; periodic = op.periodic, shift = 0.05, mask = op.mask, value = 0.0)
    A2 = BoundOperator(HostExec(), op2; T = Float64, inputs = ins)
    P2, _ = mg(A2, nothing)
    ldiv!(y, P2, b)
    sv2 = only(values(mg.engines))[]
    @test sv2 === sv1 && sv2.op.shift == 0.05
end

@testitem "_is_cpu_vec handles SubArray and custom arrays without KA fallback error" setup = [LF_solvers_linearsolve] tags = [:latticefields, :solvers] begin
    using LatticeFields.Solvers: _is_cpu_vec, _check_precs_device
    @test _is_cpu_vec(view(zeros(4), 1:2))
    v = _NoBackendVec(2)
    @test !_is_cpu_vec(v)
    @test_throws ArgumentError _check_precs_device(zeros(2, 2), v)
    @test occursin("preconditioner", err_msg(() -> _check_precs_device(zeros(2, 2), v)))
end
