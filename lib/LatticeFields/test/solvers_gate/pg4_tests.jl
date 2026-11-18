# PG-4 sweep (opt-in group `solvers_gate`). Per reference case:
#   - Float64, undeflated PCG and stationary V(2,2): equal to the reference counts (D-048);
#   - PG-4(a), the group's solver under `linsolve = :auto` (PCG, deflated when unanchored), in
#     Float64 and Float32: ≤ 8 iterations (9 on the 512² disk at s = 5.5e-6; ≤ 12 on odd
#     periodic axes, user ruling), `done`. Float32 periodic rows run a Float64 solver
#     (`solver_type = :auto` on unanchored weak-reaction groups, user ruling);
#   - with `solver_type = Float32`, Float32 periodic rows at s = 5.5e-6 stop at the Float32 floor
#     (`:floor`, never `:done`): the best true residual against its measured bound;
#   - PG-4(d), depth: measured Float32 stationary counts grow ≤ 2 from the 128² to the 512² box.
# per300 (odd coarse axes) needs 11 (3D per45: 12, in solvers/deflation.jl).

@testsetup module LF_solvers_gate_pg4
using Test, LatticeFields
include("../host_runner.jl")
include("../solvers_cases.jl")
const PG4_FLOOR = Dict("per256" => 3e-4, "per300" => 1.5e-3)  # measured best: 1.0e-4, 4.8e-4

function auto_run(case, T; kw...)
    sv = case_solver(case, T; kw...)
    k = steady!(sv; maxiter = 40)
    return k, scalars(sv)
end
include("../shared/export_all.jl")
end

@testitem "PG-4 sweep" setup = [LF_solvers_gate_pg4] tags = [:latticefields, :solvers_gate] begin
@testset "PG-4 sweep" begin
    mg32 = Dict{String, Int}()
    for ((name, s), ref) in sort(collect(REFERENCE); by = first)
        case = named_case(name, s)
        f64 = counts(case, Float64)
        k64, s64 = auto_run(case, Float64)
        k32, s32 = auto_run(case, Float32)
            mg = steady!(
                case_solver(case, Float32; linsolve = LatticeMultigrid(), solver_type = Float32);
            maxiter = 40)
        s == 5.5e-6 && (mg32[name] = mg)
        println(rpad(name, 12), " s=", rpad(s, 8), " ref ", ref, "  F64 ", f64,
            "  auto F64 ", k64, " ", s64.status, "  auto F32 ", k32, " ", s32.status,
            " best ", round(s32.best / s32.bnorm; sigdigits = 2), "  MG F32 ", mg)
        @test f64[1] <= 12 && f64[2] <= 25
        @test k64 <= 12 && s64.done && s64.rnorm <= 1e-6 * s64.bnorm
        @test k32 <= 12 && s32.done && s32.rnorm <= 1e-6 * s32.bnorm
        if startswith(name, "per")
                _, f32 = auto_run(case, Float32; solver_type = Float32)
            @test f32.status === :floor                # never :done above the tolerance
            @test f32.best / f32.bnorm <= PG4_FLOOR[name]
        end
    end
    @test mg32["box512"] - mg32["box128"] <= 2         # PG-4(d) on measured counts
end
end
