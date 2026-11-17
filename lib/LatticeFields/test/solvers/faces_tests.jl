# F3-05 (F3 design §3.4): the solver group's face conditions and inputs, against hand
# matrices assembled here from the ghost rule (independent of the solver's fields):
#   - Robin faces `α u + β ∂u/∂n = g` (diagonal `w α/(α/2 + β)`, right side `w g/(α/2 + β)`),
#     the sign rule (a negative diagonal stays out of the operator, as a defect correction),
#     and the refusal of `α/2 + β = 0` naming the face;
#   - face-Dirichlet and Robin faces with field face coefficients (LF62 lifted: the boundary
#     face takes the field's value at the boundary site);
#   - the mask value as an input field;
#   - input binding (`inputs = …`): the caller's arrays, aliased, no copy;
#   - every refusal names the user's field (`name`), not a string key.
# Base (1079c4ff): `robin`, `name`, `axes` and `inputs` are unknown keywords (MethodError);
# a field face with a Dirichlet value is refused ("a face-Dirichlet axis must be
# non-periodic with a constant face coefficient"); the messages are IRErrors without the
# field; a Dirichlet value on a size-1 axis enters the diagonal but not the right side
# (max error 0.71 against the hand matrix below); the mask value field already solved (5e-13:
# F3-05 adds its test).

@testsetup module LF_solvers_faces
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields.Solvers: deflatable
include("../host_runner.jl")
include("../solvers_cases.jl")
using LinearAlgebra: norm
using LatticeFields.Solvers: robin_parts, tangent!, set_coefficients!, sentinel

"""
The eliminated system `A x = b` over the active sites of `op` with inputs `inp`, in Float64,
from the ghost rule: `(A, b, cells)`.
"""
function hand_system(op::CellOperator{N}, inp) where {N}
    d = op.dims
    n = prod(d)
    get(x, i) = x isa Real ? Float64(x) : Float64(inp[x][i])
    m = op.mask === nothing ? zeros(UInt8, n) : inp[op.mask]
    act = m .== 0
    f = haskey(inp, "in.f") ? Float64.(inp["in.f"]) : zeros(n)
    cells = findall(act)
    idx = zeros(Int, n)
    idx[cells] .= 1:length(cells)
    A, b = zeros(length(cells), length(cells)), zeros(length(cells))
    CI, LI = CartesianIndices(d), LinearIndices(d)
    for (q, i) in enumerate(cells)
        b[q] += f[i]
        A[q, q] += get(op.shift, i)
        c = Tuple(CI[i])
        for a in 1:N, (k, σ) in enumerate((-1, 1))

            v = c[a] + σ
            if 1 <= v <= d[a] || op.periodic[a]
                d[a] == 1 && continue
                j = LI[CartesianIndex(ntuple(e -> e == a ? mod1(v, d[a]) : c[e], N))]
                w = σ > 0 ? get(op.face[a], i) : get(op.face[a], j)
                A[q, q] += w
                act[j] ? (A[q, idx[j]] -= w) : (b[q] += w * get(op.value, j))
            else                                         # a box face: the ghost rule
                w = get(op.face[a], i)
                g, r = op.dirichlet[a][k], op.robin[a][k]
                if g !== nothing
                    A[q, q] += 2w
                    b[q] += 2w * g
                elseif r !== nothing                    # ghost (g − (α/2 − β)u)/(α/2 + β)
                    α, β, gr = r
                    A[q, q] += w * α / (α / 2 + β)
                    b[q] += w * gr / (α / 2 + β)
                end
            end
        end
    end
    return A, b, cells
end

"""
A tight Float64 solve of `op` with inputs `inp` (copied in), and the hand solution.
"""
function solve_vs_hand(op, inp; linsolve = DevicePCG(; maxiters = 64, reltol = 1.0e-12), T = Float64)
    sv = FieldSolver(HostExec(), op; T, linsolve)
    for (k, v) in inp
        copyto!(field(sv, k), v)
    end
    steady!(sv; maxiter = 64)
    A, b, cells = hand_system(op, inp)
    x = A \ b
    u = solver_solution(sv)[cells]
    return maximum(abs, u .- x) / maximum(abs, x), sv
end

relerr(a, b) = maximum(abs, a .- b) / maximum(abs, b)
msg(f) = try
    f(); ""
catch e
    e isa ArgumentError || rethrow()
    sprint(showerror, e)
end

const NM = (; name = "c", axes = ("x", "y"))
include("../shared/export_all.jl")
end

@testitem "Robin faces against the ghost-rule hand matrix (16²)" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "Robin faces against the ghost-rule hand matrix (16²)" begin
    rng = Xoshiro(5)
    f = rand(rng, 256)
    # α, β of the same sign: the diagonal enters the operator (d = 0.4/0.45, 2/2, 1/(0.25 + 0.6))
    rob = (((0.4, 0.25, 0.3), (2.0, 1.0, -0.1)), ((1.0, 0.6, 0.2), nothing))
    op = CellOperator((16, 16); shift = 0.05, robin = rob, NM...)
    @test !Solvers.has_defect(op) && Solvers.anchored(op) && !Solvers.deflatable(op)
        for linsolve in (DevicePCG(; maxiters = 64, reltol = 1.0e-12), Multigrid(; maxiters = 64, reltol = 1.0e-12))
        e, _ = solve_vs_hand(op, Dict("in.f" => f); linsolve)
        @test e <= 1e-10
    end
    # a pure flux face (α = 0): no diagonal, the flux g/β on the right side
    op = CellOperator((16, 16); shift = 0.3, robin = (((0.0, 1.0, 0.5), nothing), (nothing, nothing)), NM...)
    @test robin_parts(0.0, 1.0, 0.5) == (0.0, 0.0, 0.5)
    @test solve_vs_hand(op, Dict("in.f" => f))[1] <= 1e-10
    # Dirichlet is the Robin face (1, 0, g): the same operator and the same solution
    opd = CellOperator((16, 16); shift = 0.05, dirichlet = ((0.2, nothing), (nothing, nothing)))
    opr = CellOperator((16, 16); shift = 0.05, robin = (((1.0, 0.0, 0.2), nothing), (nothing, nothing)))
        sd, sr = (FieldSolver(HostExec(), o; T = Float64, linsolve = DevicePCG(; maxiters = 64, reltol = 1.0e-12)) for o in (opd, opr))
    for s in (sd, sr)
        copyto!(field(s, "in.f"), f)
        steady!(s)
    end
    @test relerr(solver_solution(sr), solver_solution(sd)) <= 1e-12
end
end

@testitem "the sign rule: a negative Robin diagonal is a defect correction" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "the sign rule: a negative Robin diagonal is a defect correction" begin
    rng = Xoshiro(6)
    f = rand(rng, 256)
    # α = 0.1, β = −1 (opposite signs, |β| > α/2): d = 0.1/(−0.95) < 0
    rob = (((0.1, -1.0, 0.4), nothing), (nothing, nothing))
    op = CellOperator((16, 16); shift = 0.1, dirichlet = ((nothing, 1.0), (nothing, nothing)), robin = rob, NM...)
    dp, dn, q = robin_parts(0.1, -1.0, 0.4)
    @test dp == 0 && dn ≈ 0.1 / -0.95 && q ≈ 0.4 / -0.95
    @test Solvers.has_defect(op)
    e, sv = solve_vs_hand(op, Dict("in.f" => f))
    @test e <= 1e-8                                       # the full operator's solution
    # the operator itself holds only d⁺ = 0: one plain solve (no defect pass) is not the solution
        s1 = FieldSolver(HostExec(), op; T = Float64, linsolve = DevicePCG(; maxiters = 64, reltol = 1.0e-12))
    copyto!(field(s1, "in.f"), f)
    rebuild!(s1)
    lift!(s1)
    solve!(s1; host = true)
    A, b, cells = hand_system(op, Dict("in.f" => f))
    @test relerr(solver_solution(s1)[cells], A \ b) > 1e-3
    # following lift! + solve! by hand is the same defect correction (device mode)
    for _ in 1:40
        lift!(s1)
        solve!(s1)
    end
    @test relerr(solver_solution(s1)[cells], A \ b) <= 1e-8
end
end

@testitem "a degenerate Robin face is refused naming the face, at build and at every write" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "a degenerate Robin face is refused naming the face, at build and at every write" begin
    deg = (((1.0, -0.5, 0.0), nothing), (nothing, nothing))           # α/2 + β = 0
    e = msg(() -> CellOperator((16, 16); robin = deg, NM...))
    @test occursin("field `c`: the Robin condition `α u + β ∂u/∂n = g` on the low face of axis `x` has α/2 + β = 0", e)
    @test occursin("leaves the ghost value undefined: change α or β", e)
    op = CellOperator((16, 16); shift = 0.1, robin = (((1.0, 0.5, 0.0), nothing), (nothing, nothing)), NM...)
    sv = FieldSolver(HostExec(), op; T = Float64)
    bad = CellOperator{2}(op.dims, op.periodic, op.face, op.shift, op.mask, op.value, op.dirichlet,
        deg, op.name, op.axes, op.robin_full, op.diag)   # bypasses the constructor
    @test occursin("has α/2 + β = 0", msg(() -> set_coefficients!(sv, bad)))
    @test occursin("has α = β = 0, which is no condition",
        msg(() -> CellOperator((16, 16); robin = (((0.0, 0.0, 1.0), nothing), (nothing, nothing)), NM...)))
    @test occursin("must have finite α, β and g",
        msg(() -> CellOperator((16, 16); robin = (((1.0, NaN, 1.0), nothing), (nothing, nothing)), NM...)))
    @test occursin("axis `y` is periodic: it has no high face for a Robin condition",
        msg(() -> CellOperator((16, 16); periodic = (false, true), robin = ((nothing, nothing), (nothing, (1.0, 1.0, 0.0))), NM...)))
    @test occursin("the high face of axis `x` has both a Dirichlet value and a Robin condition",
        msg(() -> CellOperator((16, 16); dirichlet = ((nothing, 1.0), (nothing, nothing)),
            robin = ((nothing, (1.0, 1.0, 0.0)), (nothing, nothing)), NM...)))
end
end

@testitem "field face coefficients with face-Dirichlet and Robin faces (LF62)" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "field face coefficients with face-Dirichlet and Robin faces (LF62)" begin
    rng = Xoshiro(7)
    inp = Dict("in.f" => rand(rng, 256), "in.wx" => 0.5 .+ rand(rng, 256), "in.wy" => 0.5 .+ rand(rng, 256))
    op = CellOperator((16, 16); shift = 0.02, face = ("in.wx", "in.wy"),
        dirichlet = ((0.2, 1.0), (nothing, nothing)), robin = ((nothing, nothing), ((1.0, 0.5, 0.3), nothing)), NM...)
        for T in (Float64,), linsolve in (DevicePCG(; maxiters = 64, reltol = 1.0e-12), Multigrid(; maxiters = 64, reltol = 1.0e-12))
        @test solve_vs_hand(op, inp; linsolve, T)[1] <= 1e-10
    end
    # a field shift and a mask on top
    inp["in.s"] = 0.01 .+ 0.1rand(rng, 256)
    inp["in.mask"] = UInt8.(rand(rng, 256) .< 0.15)
    op = CellOperator((16, 16); shift = "in.s", face = ("in.wx", "in.wy"), mask = "in.mask", value = 0.7,
        dirichlet = ((0.2, 1.0), (nothing, nothing)), NM...)
    @test solve_vs_hand(op, inp)[1] <= 1e-10
    # a Dirichlet value on a size-1 axis enters the diagonal and the right side (base: diagonal only)
    op = CellOperator((16, 1); shift = 0.05, dirichlet = ((0.0, 1.0), (0.5, 0.5)))
    @test solve_vs_hand(op, Dict("in.f" => rand(rng, 16)))[1] <= 1e-10
end
end

@testitem "the mask value as an input field" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "the mask value as an input field" begin
    rng = Xoshiro(8)
    for dims in ((16, 16), (8, 8, 8))
        n = prod(dims)
        inp = Dict("in.f" => 0.1rand(rng, n), "in.mask" => UInt8.(rand(rng, n) .< 0.2), "in.v" => rand(rng, n))
        op = CellOperator(dims; shift = 0.05, mask = "in.mask", value = "in.v")
        e, sv = solve_vs_hand(op, inp)
        @test e <= 1e-10
        # control: one value for every masked site is another solution
        inp1 = filter(p -> p.first != "in.v", inp)
        e1, _ = solve_vs_hand(CellOperator(dims; shift = 0.05, mask = "in.mask", value = 0.5), inp1)
        @test e1 <= 1e-10
        A1, b1, cells = hand_system(CellOperator(dims; shift = 0.05, mask = "in.mask", value = 0.5), inp1)
        @test relerr(solver_solution(sv)[cells], A1 \ b1) > 1e-2
    end
end
end

@testitem "inputs bind the caller's arrays (aliased, no copy)" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "inputs bind the caller's arrays (aliased, no copy)" begin
    rng = Xoshiro(9)
    n = 256
    f, m, v = rand(rng, n), UInt8.(rand(rng, n) .< 0.2), rand(rng, n)
    op = CellOperator((16, 16); shift = 0.05, mask = "in.mask", value = "in.v", NM...)
        linsolve = DevicePCG(; maxiters = 64, reltol = 1.0e-12)
    sv = FieldSolver(HostExec(), op; T = Float64, linsolve, inputs = ("in.f" => f, "in.mask" => m, "in.v" => v))
    @test field(sv, "in.f") === f && field(sv, "in.mask") === m && field(sv, "in.v") === v
    steady!(sv)
    @test solve_vs_hand(op, Dict("in.f" => f, "in.mask" => m, "in.v" => v))[1] <= 1e-10
    # writing the caller's arrays changes the next solve
    f .*= 2
    v .= 1 .- v
    m .= UInt8.(rand(rng, n) .< 0.3)
    steady!(sv)
    A, b, cells = hand_system(op, Dict("in.f" => f, "in.mask" => m, "in.v" => v))
    @test relerr(solver_solution(sv)[cells], A \ b) <= 1e-10
    # an array of the lattice's shape: its memory is read (a write into it reaches the solve)
    F = reshape(copy(f), 16, 16)
    s2 = FieldSolver(HostExec(), CellOperator((16, 16); shift = 0.05); T = Float64, linsolve, inputs = Dict("in.f" => F))
    steady!(s2)
    F .*= 3
    steady!(s2)
    A, b, cells = hand_system(CellOperator((16, 16); shift = 0.05), Dict("in.f" => vec(F)))
    @test relerr(solver_solution(s2)[cells], A \ b) <= 1e-10
    # refusals in the user's words
    @test occursin("field `c`: `inputs`: `in.g` is not an input of this solver; its inputs are `in.f`, `in.mask`, `in.v`",
        msg(() -> FieldSolver(HostExec(), op; T = Float64, inputs = ["in.g" => f])))
    @test occursin("`inputs`: `in.f` holds Float32 values; this solver's state type is `Float64` (`T = Float64`): pass an array of Float64, or build the solver with `T = Float32`",
        msg(() -> FieldSolver(HostExec(), op; T = Float64, inputs = ["in.f" => Float32.(f)])))
    @test occursin("`inputs`: `in.mask` holds Float64 values; this solver's mask is `UInt8`",
        msg(() -> FieldSolver(HostExec(), op; T = Float64, inputs = ("in.mask" => f,))))
    # a vector of pairs converts its arrays to one element type: the message says so
    @test occursin("pass the pairs as a tuple or a `Dict`",
        msg(() -> FieldSolver(HostExec(), op; T = Float64, inputs = ["in.f" => f, "in.mask" => m])))
    @test occursin("field `c`: `in.g` is not a field of this solver; its inputs are `in.f`, `in.mask`, `in.v`",
        msg(() -> field(sv, "in.g")))
    @test occursin("this solver needs one value per site: a vector of 256 or an array of size (16, 16)",
        msg(() -> FieldSolver(HostExec(), op; T = Float64, inputs = ["in.f" => rand(10)])))
    # following the routes works
    @test FieldSolver(HostExec(), op; T = Float32, inputs = ["in.f" => Float32.(f)]) isa FieldSolver
end
end

@testitem "solver messages name the user's field" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "solver messages name the user's field" begin
    op = CellOperator((16, 16); shift = 0.1, mask = "in.mask", NM...)
    for (e, want) in (
                (
                    msg(() -> FieldSolver(HostExec(), op; linsolve = DevicePCG(; precond = Multigrid(; cycle = VCycle(2, 1))))),
            "`DevicePCG` needs a symmetric preconditioner cycle `(ν, ν)`; got `(2, 1)`: use `DevicePCG(; precond = Multigrid(; cycle = (2, 2)))`"),
        (msg(() -> FieldSolver(HostExec(), op; linsolve = DevicePCG(; precond = Multigrid(; cycles = 2)))),
            "applies one preconditioner cycle per iteration"),
                (msg(() -> FieldSolver(HostExec(), op; linsolve = :pcg)), "`linsolve` takes `:auto`, a `DevicePCG(…)` or a `Multigrid(…)`; got :pcg"),
        (msg(() -> FieldSolver(HostExec(), op; deflate = true)), "`deflate = true` needs `DevicePCG` on a group with no mask"),
        (msg(() -> FieldSolver(HostExec(), op; solver_type = BigFloat)), "BigFloat (solver_type) is not lowered"),
        (msg(() -> FieldSolver(HostExec(false), op; solver_type = Float64)), "Float64 (solver_type) is not supported"),
        (msg(() -> FieldSolver(HostExec(), CellOperator((1, 1); NM...))), "the lattice (1, 1) has one site"),
        (msg(() -> set_coefficients!(FieldSolver(HostExec(), op), CellOperator((16, 16); shift = 0.1, NM...))),
            "set_coefficients! takes new values for the same structure; the mask differs"),
        (msg(() -> tangent!(FieldSolver(HostExec(), op), zeros(256), :mass)), "tangent!: unknown coefficient :mass"),
        (msg(() -> tangent!(FieldSolver(HostExec(), op), zeros(256), (:robin, 1, 1, :g))), "tangent!: the low face of axis `x` has no Robin condition"))
        @test (startswith(e, "ArgumentError: field `c`: ") && occursin(want, e)) || (println("MSG: ", e); false)
        @test !occursin("in.mask", e)                    # the role, not the key
    end
    # the routes the messages give work when followed
        for kw in (
                (; linsolve = DevicePCG(; precond = Multigrid(; cycle = VCycle(2, 2)))), (; linsolve = Multigrid(; cycle = VCycle(2, 1))),
            (; linsolve = Multigrid(; cycles = 2)), (; deflate = :auto), (; solver_type = Float32))
        @test FieldSolver(HostExec(false), op; kw...) isa FieldSolver
    end
    # the sentinel names the field
        sv = FieldSolver(HostExec(), CellOperator((64, 64); shift = 1.0e-3, mask = "in.mask", value = 1.0, NM...); T = Float32, linsolve = Multigrid(; maxiters = 1))
    copyto!(field(sv, "in.mask"), UInt8.((1:4096) .% 7 .== 0))
    rebuild!(sv)
    lift!(sv)
    solve!(sv)
    @test (@test_logs (:warn, r"^field `c`: the field solve ended") sentinel(sv))
end
end

@testitem "tangents of Robin coefficients match finite differences" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "tangents of Robin coefficients match finite differences" begin
    rng = Xoshiro(10)
    f = rand(rng, 256)
    function prim(α, β, g; s = 0.1)
        op = CellOperator((16, 16); shift = s, dirichlet = ((nothing, 1.0), (nothing, nothing)),
            robin = (((α, β, g), nothing), (nothing, nothing)), NM...)
            sv = FieldSolver(HostExec(), op; T = Float64, linsolve = DevicePCG(; maxiters = 64, reltol = 1.0e-13))
        copyto!(field(sv, "in.f"), f)
        steady!(sv)
        return sv, solver_solution(sv)
    end
    for (α, β, g) in ((0.4, 0.25, 0.3), (0.1, -1.0, 0.4))      # positive part; negative part (defect)
        sv, u = prim(α, β, g)
        for (which, h) in ((:alpha, 1e-6), (:beta, 1e-6), (:g, 1e-3))
            pert(δ) = which === :alpha ? prim(α + δ, β, g)[2] : which === :beta ? prim(α, β + δ, g)[2] :
                      prim(α, β, g + δ)[2]
            ref = (pert(h) .- pert(-h)) ./ 2h
            @test relerr(tangent!(sv, u, (:robin, 1, 1, which)), ref) <= 1e-5
        end
        @test solver_solution(sv) ≈ u                   # restored (a warm re-solve continues from u)
    end
end
end

# F3-05 review r1 S1, N1: the inner solvers check their keywords when built, naming the keyword
# and its range, and print by keyword without the module path. Base (9db10886,
# ~/lpwork/f3b2r1-nc-lf.log: 17 of the
# testset's checks fail there): `DevicePCG(; maxiters = 0)`, `DevicePCG(; reltol = -1.0)`,
# `DevicePCG(; reltol = NaN)` and `Multigrid(; cycle = VCycle(0, 2))` construct; VCycle(0, 2) is refused
# only by `FieldSolver`; `repr(DevicePCG())` is "DevicePCG(Multigrid(LatticeFields.Solvers.V(2,
# 2), nothing, 1.0e-6, nothing, 1.0e-6), 8, 1.0e-6)".
@testitem "the inner solvers check their keywords when built" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "the inner solvers check their keywords when built" begin
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
    for (f, want) in (
                (() -> DevicePCG(; maxiters = 0), "`DevicePCG(; maxiters = 0)`: `maxiters` is the most CG iterations per solve, an integer ≥ 1"),
                (() -> DevicePCG(; maxiters = 2.5), "`DevicePCG(; maxiters = 2.5)`: `maxiters`"),
                (() -> DevicePCG(; reltol = -1.0), "`DevicePCG(; reltol = -1.0)`: `reltol` is the relative residual a solve stops at, finite and > 0"),
                (() -> DevicePCG(; reltol = 0.0), "`DevicePCG(; reltol = 0.0)`: `reltol`"),
                (() -> DevicePCG(; reltol = NaN), "`DevicePCG(; reltol = NaN)`: `reltol`"),
                (() -> DevicePCG(; reltol = Inf), "`DevicePCG(; reltol = Inf)`: `reltol`"),
                (() -> Multigrid(; cycle = VCycle(0, 2)), "`VCycle(0, 2)`: a V-cycle (the `cycle` of a `Multigrid`) needs ν₁, ν₂ ≥ 1"),
                (() -> VCycle(2, -1), "`VCycle(2, -1)`: a V-cycle"),
        (() -> Multigrid(; cycles = 0), "`Multigrid(; cycles = 0)`: `cycles` is the exact number of cycles, an integer ≥ 1"),
                (() -> Multigrid(; maxiters = 0), "`Multigrid(; maxiters = 0)`: `maxiters` is the most cycles per solve, an integer ≥ 1"),
                (() -> Multigrid(; reltol = -1.0e-6), "`Multigrid(; reltol = -1.0e-6)`: `reltol`"),
                (() -> Multigrid(; reltol = NaN), "`Multigrid(; reltol = NaN)`: `reltol`"),
        (() -> Multigrid(; warn_tol = 0.0), "`Multigrid(; warn_tol = 0.0)`: `warn_tol`"))
        m = e(f)
        @test startswith(m, want) || (println("MSG: ", m); false)
    end
    # the valid values the messages name build
        @test DevicePCG(; maxiters = 1, reltol = 1.0e-12).maxiters == 1 && Multigrid(; cycle = VCycle(1, 1), cycles = 1, maxiters = 1).cycles == 1
    # the display round-trips
        for s in (
                DevicePCG(), Multigrid(), VCycle(2, 3), DevicePCG(; precond = Multigrid(; cycle = VCycle(3, 3)), maxiters = 12),
                Multigrid(; cycles = 3, reltol = 1.0e-8), Multigrid(; warn_tol = 0.5),
            )
        @test eval(Meta.parse(repr(s))) == s
    end
    # a default stays out of the display: an argument printed with no call is the empty call
    @test !occursin("budget", repr(DevicePCG())) && !occursin("cycles", repr(Multigrid()))
end
end

# F3-06 review nits (batch 2): a cycle prints as the pair `(ν₁, ν₂)`, so the display runs where
# only `DevicePCG` and `Multigrid` are bound (`V` is public, not exported); a `V` of non-integers,
# a `cycle` that is not a cycle, a `precond` that is not a `Multigrid` and a `Bool` count each get
# a message naming the keyword and a working value. Base (437a84ef, ~/lpwork/f3b3-nc-nits.log):
# `repr` prints `cycle = VCycle(3, 3)` (an `UndefVarError` where `V` is not bound); `V(2.0, 2)` and
# `Multigrid(; cycle = (2, 2))` are MethodErrors; `precond = :mg` builds; `budget = true` builds.
@testitem "inner solver keywords: cycles, preconditioners and Bool counts" setup = [LF_solvers_faces] tags = [:latticefields, :solvers] begin
@testset "inner solver keywords: cycles, preconditioners and Bool counts" begin
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
    m = Module()
        Core.eval(m, :(using LatticeFields.Solvers: DevicePCG, Multigrid))    # no `VCycle` in scope
        s = DevicePCG(; precond = Multigrid(; cycle = VCycle(3, 3)), maxiters = 12)
    @test Core.eval(m, Meta.parse(repr(s))) == s
        @test Multigrid(; cycle = (3, 1)) == Multigrid(; cycle = VCycle(3, 1))
    for (f, want) in (
                (() -> VCycle(2.0, 2), "`VCycle(2.0, 2)`: a V-cycle's smoothing steps ν₁, ν₂ (pre and post) are integers ≥ 1; for example `VCycle(2, 2)`"),
                (() -> VCycle(true, 2), "`VCycle(true, 2)`: a V-cycle (the `cycle` of a `Multigrid`) needs ν₁, ν₂ ≥ 1"),
                (() -> Multigrid(; cycle = :w), "`Multigrid(; cycle = :w)`: `cycle` is the V-cycle's smoothing steps, `(ν₁, ν₂)` or `VCycle(ν₁, ν₂)`"),
                (() -> Multigrid(; cycle = (2, 0)), "`VCycle(2, 0)`: a V-cycle"),
        (() -> DevicePCG(; precond = :mg), "`DevicePCG(; precond = :mg)`: `precond` is the preconditioner's cycle, a `Multigrid(…)`"),
                (() -> DevicePCG(; maxiters = true), "`DevicePCG(; maxiters = true)`: `maxiters` is the most CG iterations per solve, an integer ≥ 1"),
        (() -> Multigrid(; cycles = true), "`Multigrid(; cycles = true)`: `cycles`"),
                (() -> Multigrid(; maxiters = false), "`Multigrid(; maxiters = false)`: `maxiters`"),
            )
        @test startswith(e(f), want) || (println("MSG: ", e(f)); false)
    end
    # the values the messages name build
        @test DevicePCG(; precond = Multigrid(; cycle = (3, 3))).precond.cycle == VCycle(3, 3)
end
end
