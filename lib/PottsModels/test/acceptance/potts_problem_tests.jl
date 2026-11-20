# breaking batch part 1 (D-075 Q2, Q9).
#
# Semantics pinned here:
#  1. The problem type is `CorePotts.PottsProblem` (renamed from `CPMProblem`), with its
#     supertype unchanged (`SciMLBase.AbstractSciMLProblem`, not a DE problem). No alias:
#     `CPMProblem` is not defined in CorePotts or Potts.
#  2. `Potts.PottsProblem` and `CorePotts.PottsProblem` are one function and one type: a
#     symbolic model's problem `isa CorePotts.PottsProblem`.
#  3. `SciMLBase.isdiscrete(alg)` is `true` for every Potts algorithm.
#  4. Solving is unchanged: the renamed problem solves under both algorithms.

@testsetup module PottsProblemSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
const problem_SciMLBase = CorePotts.SciMLBase
@potts_model Model begin
    @kinds medium A
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9)^2
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "potts problem: PottsProblem" setup = [PottsProblemSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "potts problem: PottsProblem" begin
        @test isdefined(CorePotts, :PottsProblem)
        @test !isdefined(CorePotts, :CPMProblem)
        @test !isdefined(Potts, :CPMProblem)
        @test Potts.PottsProblem === CorePotts.PottsProblem
        @test CorePotts.PottsProblem <: problem_SciMLBase.AbstractSciMLProblem
        @test !(CorePotts.PottsProblem <: problem_SciMLBase.AbstractDEProblem)

        σ = zeros(Int32, 12, 12)
        σ[4:6, 4:6] .= 1
        prob = PottsProblem(
            Model(; name = :m), [CorePotts.ownership => σ, kind => [:A]], (
                0, 5,
            )
        )
        @test prob isa CorePotts.PottsProblem
        for alg in (SequentialCPM(), CheckerboardCPM())
            @test problem_SciMLBase.isdiscrete(alg)
            sol = solve(prob, alg)
            @test sol.t[end] == 5
            @test count(!iszero, Array(sol.u[end].ownership)) > 0
        end
    end
end
