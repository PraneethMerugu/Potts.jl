# Coefficients as runtime parameters (P5 C7b-2): a value change reuses the compiled bodies;
# tangent solves (P5 §3.4): derivatives of the solution with respect to a coefficient from
# one primal solve and one tangent solve with homogeneous boundary values, against finite
# differences, with the negative control that keeps the primal boundary values.

@testsetup module LF_solvers_coefficients
using Test, LatticeFields
include("../host_runner.jl")
include("../solvers_cases.jl")
include("../shared/solvers_coefficients.jl")
include("../shared/export_all.jl")
end

@testitem "coefficients are parameters: a value change does not recompile" setup = [LF_solvers_coefficients] tags = [:latticefields, :solvers] begin
using .LF_solvers_coefficients: fd
@testset "coefficients are parameters: a value change does not recompile" begin
    op, inputs = box_case(64, 32; s = 0.01)
    sv, _ = primal_solve((op, inputs))
    fns = Dict(k => v[2] for (k, v) in sv.bodies)
    @test all(v -> !occursin("0.01", string(v[1].body)), values(sv.bodies))  # no baked value
    op2 = with(op; shift = 0.02, dirichlet = ((0.0, 2.0), (nothing, nothing)))
    set_coefficients!(sv, op2)
    steady!(sv)
    @test all(k -> sv.bodies[k][2] === fns[k], keys(fns))                     # same bodies
    ref, uref = primal_solve((op2, inputs))
    @test Solvers.solver_solution(sv) == uref                                  # bitwise
    @test coef_values(sv.op) == coef_values(op2)
    # a structural change is refused
    @test_throws ArgumentError set_coefficients!(
        sv,
        with(op; dirichlet = ((0.0, nothing), (nothing, nothing))))
end
end

@testitem "tangent solves match finite differences (homogeneous boundary values)" setup = [LF_solvers_coefficients] tags = [:latticefields, :solvers] begin
using .LF_solvers_coefficients: fd
@testset "tangent solves match finite differences (homogeneous boundary values)" begin
    box = box_case(64, 32; s = 0.01)
    sv, u = primal_solve(box)
    du = tangent!(sv, u, :shift)
    ref = fd(box, :shift, 1e-5)
    @test relmax(du, ref) <= 1e-5                       # P5 probe B2: 4e-7
    # u is linear in the Dirichlet value: the tangent is exact
    dg = tangent!(sv, u, (:dirichlet, 1, 2))
    @test relmax(dg, fd(box, (:dirichlet, 1, 2), 0.1)) <= 1e-8
    # the face coefficients (the Dirichlet axis and the periodic axis); masked islands make
    # the solution depend on y (without them ∂u/∂face₂ = 0)
    isl = box_case(64, 32; s = 0.01, islands = 0.1)
    si, ui = primal_solve(isl)
    for a in 1:2
        ref = fd(isl, (:face, a), 1e-5)
        @test maximum(abs, ref) > 1e-3
        @test relmax(tangent!(si, ui, (:face, a)), ref) <= 1e-5
    end
    # the mask value (linear: exact)
    disk = named_case("disk128", 0.022)
    sd, ud = primal_solve(disk)
    @test relmax(tangent!(sd, ud, :value), fd(disk, :value, 0.1)) <= 1e-8
    # warm starts stay correct: after tangent! the working state is the primal one, so a
    # warm re-solve is converged at once and returns u (not u̇)
    k = tangent!(sd, ud, :shift)
    @test solve!(sd; host = true) == 0 && scalars(sd).done
    @test Solvers.solver_solution(sd) == ud
    @test field(sd, solution_key(sd)) == ud
    # a warm re-solve that is not converged (b changed after tangent!) matches a solver that
    # never ran a tangent: same iterations, same bits
    fresh, _ = primal_solve(disk)
    for s in (sd, fresh)
        fill!(field(s, "in.f"), 0.05)
        lift!(s)
    end
    k1, k2 = solve!(sd; host = true), solve!(fresh; host = true)
    @test k1 == k2 > 0
    @test field(sd, solution_key(sd)) == field(fresh, solution_key(fresh))
    # the primal inputs and coefficients are restored: a fresh solve reproduces u
    steady!(sv)
    @test Solvers.solver_solution(sv) == u
    # negative control: keeping the primal boundary values is wrong (P5: 5%)
    bad = tangent!(sv, u, :shift; homogeneous = false)
    @test relmax(bad, ref) >= 1e-2
    # a periodic, deflated group: ∂u/∂s = −A⁻¹u
    per = named_case("per128", 0.022)
    sp, up = primal_solve(per)
    @test sp.deflate
    @test relmax(tangent!(sp, up, :shift), fd(per, :shift, 1e-6)) <= 1e-5
    @test_throws ArgumentError tangent!(sp, up, :value => 1)
end
end
