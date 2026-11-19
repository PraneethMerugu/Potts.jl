# Constant-mode deflation on unanchored groups (provisional D-C7b) and the stop statuses: the
# mean coefficient, the zero-mean solve, the warm start, s = 0, the Float32 floor and the
# Float64 solver of unanchored weak-reaction groups (`solver_type`), a slow solve that is not a
# floor, and
# divergence (stationary only).

@testsetup module LF_solvers_deflation
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields.Solvers: set_coefficients!
include("../host_runner.jl")
include("../solvers_cases.jl")
using LatticeFields.Solvers: resolve_inner, sentinel, solution_key, deflatable, solve_plan,
                             floor_regime

"""
3D periodic 45³ (odd axes), s = 5.5e-6, a half-filled source.
"""
function per45_case()
    f3 = zeros(45, 45, 45)
    f3[1:22, :, :] .= 1
    op = CellOperator((45, 45, 45); periodic = (true, true, true), shift = 5.5e-6)
    return (op, ("in.f" => vec(f3),))
end

"""
Unanchored, not fully periodic: no-flux x, periodic y, s = 1e-5 (Float32 floor 1.1e-4).
"""
function neumann_x_case()
    f = zeros(128, 96)
    f[1:40, 1:30] .= 1
    return (CellOperator((128, 96); periodic = (false, true), shift = 1e-5),
        ("in.f" => vec(f),))
end
"""
Pure Neumann (no-flux on every face), s = 0, a compatible (zero-sum) right-hand side.
"""
function neumann_case()
    f = zeros(128, 96)
    f[1:40, 1:30] .= 1
    f[90:end, 60:end] .= -sum(f) / length(f[90:end, 60:end])
    return (CellOperator((128, 96); shift = 0.0), ("in.f" => vec(f),))
end

"""
A test executor without `Schedule.supports` methods (the conservative default).
"""
struct MinExec end
Solvers.alloc(::MinExec, ::Type{T}, n) where {T} = zeros(T, n)
Solvers.to_host(::MinExec, A) = copy(A)
Solvers.launch!(::MinExec, l::Solvers.Launch) = Solvers.launch!(HostExec(), l)

"""
Periodic 128², log-normal face coefficients (σ = 2), s = 1e-4: a slow, still-converging
solve (C7b review round 2).
"""
function jumpy_case(σ = 2.0)
    rng, n = MersenneTwister(3), 128
    fx, fy = exp.(randn(rng, n, n) .* σ), exp.(randn(rng, n, n) .* σ)
    f = zeros(n, n)
    f[1:(n ÷ 2), :] .= 1
    op = CellOperator((n, n); periodic = (true, true), shift = 1e-4, face = (
        "in.fx", "in.fy"))
    return (op, ("in.f" => vec(f), "in.fx" => vec(fx), "in.fy" => vec(fy)))
end
include("../shared/export_all.jl")
end

@testitem "linsolve = :auto: PCG with deflation on unanchored groups" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
    @testset "linsolve = :auto: PCG with deflation on unanchored groups" begin
    per, disk = periodic_case(64, 64; s = 1e-3), named_case("disk128", 0.022)
        @test resolve_inner(per[1], :auto) isa Solvers.FusedPCG && deflatable(per[1])
    @test !deflatable(disk[1]) && !deflatable(named_case("box128", 5.5e-6)[1])
    sv = case_solver(per, Float32)
    @test sv.deflate && solution_key(sv) == "pcg.u"
    @test !case_solver(disk, Float32).deflate
end
end

@testitem "deflated solve: mean coefficient and solution (Float64)" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
@testset "deflated solve: mean coefficient and solution (Float64)" begin
    case = named_case("per256", 5.5e-6)
    sv, ref = case_solver(case, Float64), case_solver(case, Float64; deflate = false)
    k = steady!(sv)
    @test scalars(sv).done && k <= 12 && scalars(sv).rnorm <= 1e-6 * scalars(sv).bnorm   # D-C7b: PCG <= 12
    @test scalars(sv).mean ≈ 0.5 / 5.5e-6 rtol = 1e-12 # mean(b)/s
    steady!(ref)
    u, uref = field(sv, "pcg.u"), field(ref, "pcg.x")
    @test maximum(abs, u .- uref) / maximum(abs, uref) < 1e-6
    @test abs(sum(field(sv, "pcg.x"))) / length(u) < 1e-9 * maximum(abs, u)   # zero-mean part
    # PG-4(a) on odd periodic axes is ≤ 12 (user ruling, D-C7b). per300 (75 → 37): measured
    # 11 deflated (12 undeflated); 3D per45 (45 → 22): measured 12.
    sv = case_solver(named_case("per300", 5.5e-6), Float64)
    @test steady!(sv) <= 12 && scalars(sv).done
    sv = case_solver(per45_case(), Float64)
    @test steady!(sv) <= 12 && scalars(sv).done
end
end

@testitem "solver_type = :auto: Float64 solver for unanchored weak-reaction groups" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
    @testset "solver_type = :auto: Float64 solver for unanchored weak-reaction groups" begin
    # Float32 state; the solver runs in Float64 and reaches 1e-6 at weak reaction; the
    # caller-facing arrays stay Float32 (converted at the boundary)
    for case in (named_case("per256", 5.5e-6), named_case("per300", 5.5e-6),
        per45_case(), neumann_x_case(), neumann_case())
        sv = case_solver(case, Float32)
        k = steady!(sv)
        sc = scalars(sv)
        @test sv.T == Float64 && sv.state == Float32 && floor_regime(sv.op)
        @test sc.status === :done && k <= 12 && sc.rnorm <= 1e-6 * sc.bnorm
        x = solver_solution(sv)
        @test maximum(abs, true_residual(sv, x)) <= 1e-6 * sc.bnorm
        u = field(sv, solution_key(sv))
        @test eltype(u) == Float32 && eltype(field(sv, "in.f")) == Float32
        @test maximum(abs, u .- x) <= eps(Float32) * maximum(abs, x)   # rounding only
        @test !sentinel(sv)
    end
    # negative control: the Neumann-x group with a Float32 solver floors (measured 1.1e-4)
        sv = case_solver(neumann_x_case(), Float32; solver_type = Float32)
    steady!(sv)
    @test sv.T == Float32 && scalars(sv).status === :floor
    # strong reaction (s ≥ FLOOR_SHIFT) and anchored groups stay in the state type
    sv = case_solver(named_case("per256", 1.0), Float32)
    @test sv.T == Float32 && steady!(sv) <= 12 && scalars(sv).done
    @test case_solver(named_case("disk128", 0.022), Float32).T == Float32
    @test case_solver(named_case("box128", 5.5e-6), Float32).T == Float32
    # explicit types: Float32 keeps (the floor testset below); Float64 forces, the solution
    # stays in the state type (`out.u`)
        @test case_solver(named_case("per128", 0.022), Float32; solver_type = Float32).T == Float32
        sv = case_solver(named_case("disk128", 0.022), Float32; solver_type = Float64)
    steady!(sv)
    @test sv.T == Float64 && solution_key(sv) == "out.u" && scalars(sv).done
    @test field(sv, "out.u") == Float32.(solver_solution(sv))
end
end

@testitem "solver_type: backends and number types" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
    @testset "solver_type: backends and number types" begin
    op, inputs = named_case("per256", 5.5e-6)
    # a backend without Float64 (Metal): documented Float32 fallback under :auto
    sv = FieldSolver(HostExec(false), op)
    foreach(((k, v),) -> copyto!(field(sv, k), v), inputs)
    steady!(sv)
    @test sv.T == Float32 && scalars(sv).status === :floor
    @test (@test_logs (:warn, r"Float32 floor of an unanchored group") sentinel(sv))
    # explicit Float64 there is refused, naming the type
    @test_throws ArgumentError FieldSolver(
        HostExec(false), op;
        solver_type = Float64
    )
    @test_throws ArgumentError FieldSolver(HostExec(false), op;
        T = Float64)
    # types the solver does not lower: a clear error, not a MethodError
    @test_throws ArgumentError FieldSolver(
        HostExec(), op;
        solver_type = BigFloat
    )
    @test_throws ArgumentError FieldSolver(HostExec(), op;
        T = Float16)
    @test_throws ArgumentError FieldSolver(
        HostExec(), op; solver_type = :fast
    )
    # an executor without `supports` methods: the conservative default (Float32 only),
    # asked only when the choice depends on it
    disk = named_case("disk128", 0.022)
    sv = FieldSolver(MinExec(), disk[1])
    foreach(((k, v),) -> copyto!(field(sv, k), v), disk[2])
    @test steady!(sv) <= 12 && scalars(sv).done && sv.T == Float32
    @test FieldSolver(MinExec(), op).T == Float32           # :auto falls back
    @test_throws ArgumentError FieldSolver(MinExec(), op; solver_type = Float64)
end
end

@testitem "s = 0: the zero-mean solution of a compatible right-hand side" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
@testset "s = 0: the zero-mean solution of a compatible right-hand side" begin
    n = 128
    f = zeros(n, n)
    f[1:(n ÷ 2), :] .= 1
    f[(n ÷ 2 + 1):end, :] .= -1
    op = CellOperator((n, n); periodic = (true, true), shift = 0.0)
    sv = case_solver((op, ("in.f" => vec(f),)), Float64)
    steady!(sv)
    @test scalars(sv).done && scalars(sv).mean == 0
    u = field(sv, "pcg.u")
    @test abs(sum(u)) / length(u) < 1e-9 * maximum(abs, u)
    @test maximum(abs, true_residual(sv)) <= 1e-6 * maximum(abs, f)
end
end

@testitem "warm re-solve keeps the zero-mean part (Float32)" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
@testset "warm re-solve keeps the zero-mean part (Float32)" begin
        sv = case_solver(named_case("per300", 1.0), Float32; solver_type = Float32)
    @test steady!(sv) <= 12 && scalars(sv).done
    @test solve!(sv; host = true) == 0 && scalars(sv).done     # converged warm start
    @test abs(sum(field(sv, "pcg.x"))) / length(field(sv, "pcg.x")) < 1e-3
end
end

@testitem "Float32 floor: status :floor, never :done (solver_type = Float32)" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
    @testset "Float32 floor: status :floor, never :done (solver_type = Float32)" begin
    case = named_case("per256", 5.5e-6)                # ‖x̃‖∞ ≈ 1e3: floor ≈ ε‖A‖‖x̃‖/‖b‖
        sv = case_solver(case, Float32; solver_type = Float32)
    steady!(sv)
    sc = scalars(sv)
    @test sc.status === :floor && !sc.done && sc.warn
    @test sc.best / sc.bnorm < 3e-4                    # measured 1.0e-4
    @test sc.best <= Solvers.FLOOR_ULPS * eps(Float32) * sc.scale   # measured 0.11 ε·scale
    @test (@test_logs (:warn, r"stagnated") sentinel(sv))
        ref = case_solver(case, Float32; deflate = false, solver_type = Float32)   # no deflation
    steady!(ref)
    @test scalars(ref).status === :floor
    @test maximum(abs, true_residual(ref)) / scalars(ref).bnorm > 1e-2   # offset in F32
end
end

@testitem "a slow solve far above rounding level is not :floor" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
@testset "a slow solve far above rounding level is not :floor" begin
    # The max-norm residual stalls for more than three checks (the stall test alone stopped
    # this at k = 10, ‖r‖/‖b‖ = 37), but the best residual is ~1e7 ε·scale: it runs on.
    sv = case_solver(jumpy_case(), Float64)
    k = steady!(sv; maxiter = 60)
    sc = scalars(sv)
    @test k == 60 && sc.status === :budget && sc.warn
    @test sc.best / sc.bnorm < 1e-2                    # measured 3.6e-3 (was 37 at :floor)
    @test sc.best > 1e3 * Solvers.FLOOR_ULPS * eps(Float64) * sc.scale
    @test (@test_logs (:warn, r"ended") sentinel(sv))
end
end

@testitem "divergence is reported as :diverged, transient growth is not" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
@testset "divergence is reported as :diverged, transient growth is not" begin
    # stationary V(1,1) on the 512² disk diverges (‖r‖/‖b‖ 0.46 → 0.93 by cycle 10)
    sv = case_solver(named_case("disk512", 5.5e-6), Float64;
            linsolve = LatticeMultigrid(cycle = VCycle(1, 1))
        )
    k = steady!(sv; maxiter = 30)
    sc = scalars(sv)
    @test sc.status === :diverged && !sc.done && sc.warn && k < 30
    @test sc.rnorm > 2 * sc.best
    @test (@test_logs (:warn, r"diverged") sentinel(sv))
    # negative control: V(2,2) on the jumpy field grows 27 → 41 over ten cycles, then falls;
    # the growth counter reaches 3 (rn stays below 2·best), the solve runs to its budget
        sv = case_solver(jumpy_case(), Float64; linsolve = LatticeMultigrid())
    rebuild!(sv)
    lift!(sv)
    scal = sv.tables[Solvers.tid(sv, "solve.scal")]
    grew = 0.0
    for seg in solve_plan(sv, 30).segments
        foreach(l -> Solvers.launch!(sv.exec, l), seg)
        grew = max(grew, scal[Solvers.GROW])
    end
    @test grew >= Solvers.GROW_CHECKS && scalars(sv).status === :budget
end
end

@testitem "a slow PCG solve that wanders is not :diverged (stationary only)" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
@testset "a slow PCG solve that wanders is not :diverged (stationary only)" begin
    # σ = 4: the max-norm residual wanders between 150 and 310 for tens of iterations (round
    # 2 stopped it as :diverged at 45) and reaches 2.5 at 300; PCG cannot diverge in the
    # A-norm. The growth test fires on this history (checked here) but is stationary-only.
    sv = case_solver(jumpy_case(4.0), Float64)
    rebuild!(sv)
    lift!(sv)
    scal = sv.tables[Solvers.tid(sv, "solve.scal")]
    sp = solve_plan(sv, 60)
    fired = false
    for seg in sp.segments
        foreach(l -> Solvers.launch!(sv.exec, l), seg)
        fired |= scal[Solvers.GROW] >= Solvers.GROW_CHECKS &&
                 scal[Solvers.RNORM] > Solvers.GROW_FACTOR * scal[Solvers.BEST]
    end
    sc = scalars(sv)
    @test fired                                        # the old rule would have stopped it
    @test sc.status === :budget && sc.iter == 60
end
end

@testitem "solver_type = :auto: the floor regime is s relative to the faces" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
    @testset "solver_type = :auto: the floor regime is s relative to the faces" begin
    n = 256
    f = zeros(n, n)
    f[1:(n ÷ 2), :] .= 1
    per(w, s) = (CellOperator((n, n); periodic = (true, true), shift = s, face = (w, w)),
        ("in.f" => vec(f),))
    # face = 100, s = 1: s/face = 0.01, floors in Float32 (measured 4.8e-6), Float64 :done
        sv = case_solver(per(100.0, 1.0), Float32; solver_type = Float32)
    steady!(sv)
    @test scalars(sv).status === :floor
    sv = case_solver(per(100.0, 1.0), Float32)
    @test sv.T == Float64 && steady!(sv) <= 8 && scalars(sv).done
    # face = 0.01, s = 0.1: s/face = 10, Float32 converges (no Float64 needed)
    sv = case_solver(per(0.01, 0.1), Float32)
    @test sv.T == Float32 && steady!(sv) <= 8 && scalars(sv).done
    # a field-valued face counts as weak, whatever the shift
    @test floor_regime(CellOperator((8, 8); periodic = (true, true), shift = 10.0,
        face = ("in.fx", 1.0)))
    @test !floor_regime(CellOperator((8, 8); periodic = (true, true), shift = 10.0))
end
end

@testitem "coefficients are validated; set_coefficients! warns once about solver_type" setup = [LF_solvers_deflation] tags = [:latticefields, :solvers] begin
    @testset "coefficients are validated; set_coefficients! warns once about solver_type" begin
    # refusals in the user's words (F3-05): an ArgumentError naming the field and the axis
    E(f) = try
        f(); ""
    catch e
        e isa ArgumentError || rethrow()
        sprint(showerror, e)
    end
    nm = (; name = "c", axes = ("x", "y"))
    e = E(() -> CellOperator((8, 8); shift = -1.0, nm...))
    @test occursin("field `c`: the shift", e) && occursin("must be ≥ 0; got -1.0", e) &&
          occursin("step the field with an explicit method (`ExplicitEuler`)", e)
    @test occursin("field `c`: the shift", E(() -> CellOperator((8, 8); shift = Inf, nm...)))
    @test occursin("field `c`: the face coefficient of axis `x` must be > 0; got 0.0",
        E(() -> CellOperator((8, 8); face = (0.0, 1.0), nm...)))
    @test occursin("the face coefficient of axis `y` must be > 0; got -2.0",
        E(() -> CellOperator((8, 8); face = (1.0, -2.0), nm...)))
    @test occursin("the face coefficient of axis `x` must be finite", E(() -> CellOperator((8, 8); face = (Inf, 1.0), nm...)))
    @test occursin("the face coefficient of axis `y` must be finite", E(() -> CellOperator((8, 8); face = (1.0, NaN), nm...)))
    @test occursin("field `c`: the mask value must be finite", E(() -> CellOperator((8, 8); mask = "m", value = Inf, nm...)))
    @test occursin("the Dirichlet value on the high face of axis `x` must be finite",
        E(() -> CellOperator((8, 8); dirichlet = ((0.0, Inf), (nothing, nothing)), nm...)))
    @test occursin("the solver group: the shift", E(() -> CellOperator((8, 8); shift = -1.0)))   # no name given
    op, inputs = named_case("per256", 1.0)               # :auto resolves to Float32
    sv = case_solver((op, inputs), Float32)
    @test sv.T == Float32
    bad = CellOperator{2}(op.dims, op.periodic, op.face, -1.0, op.mask, op.value,
        op.dirichlet, op.robin, op.name, op.axes, op.robin_full, op.diag)    # bypasses the constructor
    @test_throws ArgumentError Solvers.set_coefficients!(sv, bad)
    weak = CellOperator(op.dims; periodic = op.periodic, shift = 1e-3)
        @test_logs (:warn, r"solver_type = :auto would now resolve to Float64") Solvers.set_coefficients!(
        sv, weak)
    @test sv.T == Float32 && sv.op.shift == 1e-3         # not re-resolved, not refused
    @test_logs Solvers.set_coefficients!(sv, weak)       # once per solver
        sv = case_solver((op, inputs), Float32; solver_type = Float32)   # explicit: no warning
    @test_logs Solvers.set_coefficients!(sv, weak)
end
end
