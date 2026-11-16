# Plans and device control: preconditioner symmetry (§4.5), Krylov symmetry of the eliminated
# operator (T-3), the budget skip with its pass-through, the sentinel, `inner = :auto`,
# launch counts (PG-5) and Float32/allocation hygiene of every launch.

@testsetup module LF_solvers_plans
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields.IR: runtime
include("../host_runner.jl")
include("../solvers_cases.jl")
using LatticeFields.Solvers: precond_plan, solve_plan, resolve_inner, sentinel,
                             nlaunches, PlanBuilder, SolvePlan, fin!, gen!, INIT
using LatticeFields.Compile: LOWERING

active(sv) = field(sv, lkey(0, "active")) .!= 0

"""
z = M r: one preconditioner V-cycle from zero.
"""
function apply_M(sv, r)
    copyto!(field(sv, lkey(0, "b")), r)
    Solvers.run!(sv, precond_plan(sv))
    return copy(field(sv, lkey(0, "x")))
end

function symmetry_defect(sv)
    rebuild!(sv)
    rng, act, worst = Xoshiro(11), active(sv), 0.0
    for _ in 1:3
        x, y = randn(rng, length(act)) .* act, randn(rng, length(act)) .* act
        Mx, My = apply_M(sv, x), apply_M(sv, y)
        worst = max(worst, abs(Mx' * y - x' * My) / abs(Mx' * y))
    end
    return worst
end
include("../shared/export_all.jl")
end

@testitem "the preconditioner is a fixed linear SPD operator" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "the preconditioner is a fixed linear SPD operator" begin
    for case in (named_case("sphere42", 0.022), named_case("box300x192", 5.5e-6))
        @test symmetry_defect(case_solver(case, Float64)) < 1e-12
    end
    v21 = Multigrid(cycle = V(2, 1))       # negative control (DevicePCG refuses it)
    @test symmetry_defect(case_solver(named_case("sphere42", 0.022), Float64; inner = v21)) >
          1e-3
end
end

@testitem "Krylov operator is symmetric in eliminated form (T-3, s = 1e-8)" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "Krylov operator is symmetric in eliminated form (T-3, s = 1e-8)" begin
    n = 16
    m = UInt8.(rand(Xoshiro(2), n, n, n) .< 0.3)
    op = CellOperator((n, n, n); shift = 1e-8, mask = "in.mask", value = 0.0)
    sv = case_solver((op, ("in.mask" => vec(m),)), Float64)
    rebuild!(sv)
    function A(x)                                      # A x = −r(b = 0) through pcg.true
        fill!(field(sv, "pcg.b"), 0)
        copyto!(field(sv, "pcg.x"), x)
        pl = PlanBuilder(sv)
        fin!(pl, INIT)
        gen!(pl, "pcg.true")
        Solvers.run!(sv, SolvePlan(pl))
        return -copy(field(sv, lkey(0, "b")))
    end
    act = active(sv)
    absA = abs.(level_matrix(sv, 0))
    rng = Xoshiro(4)
    for _ in 1:10
        x, y = randn(rng, n^3) .* act, randn(rng, n^3) .* act
        scale = eps() * (abs.(y[act])' * absA * abs.(x[act]))
        @test abs(A(x)' * y - x' * A(y)) / scale < 1
    end
    # negative control: the row-only identity form couples active rows to masked columns
    R = zeros(n^3, n^3)
    R[act, act] = level_matrix(sv, 0)
    for i in findall(.!act)
        R[i, i] = 1
    end
    LI = LinearIndices((n, n, n))
    for c in CartesianIndices((n, n, n)), a in 1:3

        i, c2 = LI[c], Tuple(c)
        c2[a] < n || continue
        j = LI[CartesianIndex(ntuple(k -> k == a ? c2[a] + 1 : c2[k], 3))]
        act[i] && !act[j] && (R[i, j] = -1)
    end
    x, y = randn(rng, n^3), randn(rng, n^3)
    @test abs((R * x)' * y - x' * (R * y)) / (eps() * (abs.(y)' * abs.(R) * abs.(x))) > 1e6
end
end

@testitem "budget skip keeps the pass-through (odd flips per cycle)" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "budget skip keeps the pass-through (odd flips per cycle)" begin
    case = named_case("disk128", 0.022)
    v21 = Multigrid(cycle = V(2, 1))
    sv = case_solver(case, Float32; inner = v21)
    k = steady!(sv)
    want = copy(field(sv, lkey(0, "x")))
    for (stages, same) in ((LOWERING, true), (
        merge(LOWERING, (; passthrough = c -> Any[])), false))
        sv = case_solver(case, Float32; inner = v21, stages)
        rebuild!(sv)
        lift!(sv)
        solve!(sv; budget = k + 1)                     # device mode: one gated cycle
        @test scalars(sv).iter == k
        @test (field(sv, lkey(0, "x")) == want) == same
    end
end
end

@testitem "sentinel and inner = :auto" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "sentinel and inner = :auto" begin
    disk, per = named_case("disk512", 1.9e-3), periodic_case(128, 128; s = 1.0)
    @test resolve_inner(disk[1], :auto) isa DevicePCG
    @test resolve_inner(disk[1], Multigrid()).budget == 12
    @test resolve_inner(per[1], :auto).budget == 8
    sv = case_solver(disk, Float32; inner = Multigrid())   # stationary budget 12 needs 17
    rebuild!(sv)
    lift!(sv)
    solve!(sv)
    @test (@test_logs (:warn, r"use DevicePCG") sentinel(sv))
    sv = case_solver(per, Float32)
    rebuild!(sv)
    lift!(sv)
    solve!(sv)
    @test !sentinel(sv) && scalars(sv).done
end
end

@testitem "sentinel uses the plan's budget; DevicePCG validation" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "sentinel uses the plan's budget; DevicePCG validation" begin
    case = named_case("disk128", 5.5e-6)
    sv = case_solver(case, Float64; inner = DevicePCG(budget = 4))
    @test steady!(sv) > 4                    # past the algorithm budget, converged
    @test scalars(sv).done && !scalars(sv).warn && !sentinel(sv)
    sv = case_solver(case, Float64; inner = DevicePCG(budget = 30))
    rebuild!(sv)
    lift!(sv)
    @test solve!(sv; host = true, budget = 3) == 3   # plan budget below the algorithm's
    sc = scalars(sv)
    @test !sc.done && sc.warn
    @test sc.rnorm ≈ maximum(abs, true_residual(sv)) rtol = 1e-6   # final true residual
    @test (@test_logs (:warn, r"tolerance") sentinel(sv))
        @test_throws ["ArgumentError", "DevicePCG", "symmetric preconditioner cycle"] resolve_inner(
            case[1],
        DevicePCG(precond = Multigrid(cycle = V(2, 1))))
        @test_throws ["ArgumentError", "DevicePCG", "one preconditioner cycle per iteration", "cycles = 2"] resolve_inner(
            case[1],
        DevicePCG(precond = Multigrid(cycles = 2)))
end
end

@testitem "launches per cycle and iteration (PG-5 ≤ 25)" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "launches per cycle and iteration (PG-5 ≤ 25)" begin
    per = periodic_case(256, 256; s = 0.022)
    sv = case_solver(per, Float32; inner = Multigrid())
    @test nlaunches(solve_plan(sv, 2), 2) == 13        # 2 levels × 5 + bottom + norm + finish
    sv = case_solver(per, Float32)                     # deflated PCG: no extra launches
    @test sv.deflate &&
          nlaunches(solve_plan(sv, 2), 2) ==
          nlaunches(solve_plan(case_solver(per, Float32; deflate = false), 2), 2)
    sv = case_solver(named_case("sphere42", 0.022), Float32)
    # (segment 1: the setup; 2: the first V-cycle, its own segment since F3-07, so a solve done
    # at its setup stops before it on the host; 3: the first iteration)
    @test nlaunches(solve_plan(sv, 2), 2) == 12        # V 11 + finish
    @test nlaunches(solve_plan(sv, 2), 3) == 15        # V 11 + K1, α, K2 (true residual), finish
end
end

@testitem "Float32 launches: no Float64 in any device code (Metal)" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "Float32 launches: no Float64 in any device code (Metal)" begin
    # Every launch body, hand-written (finish!, bottom!, gershgorin!, build_site!) or
    # generated, with every callee: no Float64 value in the typed code, and none in the
    # arguments. Deflated and undeflated PCG, stationary multigrid, 2D and 3D.
    for (c, kw) in (("disk128", (;)), ("disk128", (; inner = Multigrid())),
        ("per128", (; solver_T = Float32)), (
        "per128", (; deflate = false, solver_T = Float32)),
        ("sphere42", (;)))
        sv = case_solver(named_case(c, 0.022), Float32; kw...)
        @test sv.T == Float32
        @test all(b -> !has_f64(b[1].body), values(sv.bodies))
        steady!(sv)
        bad = String[]
        for sp in (Solvers.rebuild_plan(sv), Solvers.lift_plan(sv), solve_plan(sv, 1),
                precond_plan(sv)), seg in [sp.segments; sp.epilogue], l in seg
            f64_type(Tuple{typeof(l.S), typeof(l.P), typeof(l.G)}) &&
                push!(bad, "args of " * l.key)
            append!(bad, f64_sites(launch_sig(l)))
        end
        @test isempty(bad) || (foreach(println, unique(bad)); false)
    end
    # negative control: a Float32-vs-Int32 compare (the round-2 `_sentinel!` defect)
    probe(scal, G) = scal[1] >= G.budget
    @test !isempty(f64_sites(Tuple{
        typeof(probe), Vector{Float32}, typeof((; budget = Int32(8)))}))
    @test f64_type(typeof((; a = (1.0f0, 2.0))))
end
end

@testitem "Float32 launches: warm launches allocate nothing" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "Float32 launches: warm launches allocate nothing" begin
    sv = case_solver(named_case("disk128", 0.022), Float32)
    steady!(sv)
    for seg in solve_plan(sv, 1).segments, l in seg

        Solvers.launch!(HostExec(), l)
        @test (@allocated Solvers.launch!(HostExec(), l)) == 0
    end
    # the per-window rebuild and lift run every window: they allocate nothing either
    for c in ("disk128", "sphere42")
        sv = case_solver(named_case(c, 0.022), Float32)
        steady!(sv)
        for sp in (Solvers.rebuild_plan(sv), Solvers.lift_plan(sv)), seg in sp.segments,
            l in seg
            Solvers.launch!(HostExec(), l)
            @test (@allocated Solvers.launch!(HostExec(), l)) == 0
        end
    end
end
end

@testitem "the time slot is reserved: no solver kernel reads G.rt[TIME_SLOT]" setup = [LF_solvers_plans] tags = [:latticefields, :solvers] begin
@testset "the time slot is reserved: no solver kernel reads G.rt[TIME_SLOT]" begin
    TS = LatticeFields.Compile.TIME_SLOT
    for (c, kw) in (("disk128", (;)), ("disk128", (; inner = Multigrid())), ("per128", (;)))
        sv = case_solver(named_case(c, 0.022), Float32; kw...)
        @test all(k -> all(n -> !(n.op == IR.RUNTIME && n.imm == TS), k.nodes),
            sv.prog.kernels)
        @test all(b -> !b[1].timed, values(sv.bodies))
        @test !(TS in Solvers.SOLVER_RT)
    end
    # negative control: a kernel that reads the time slot is refused
    pb = ProgramBuilder(Grid((8,)))
    u = field!(pb, "u")
    kb = kernel(pb)
    store(kb, u, load(kb, u) + IR.runtime(kb, TS))
    add!(pb, kb, "timed")
    @test_throws r"reads the time slot" Solvers.check_no_time(program(pb))
end
end
