# P6.0m2 (ROADMAP Phase 6, step 0): breaking batch part 1 (D-075 Q2, Q9). Frozen
# (AUTONOMY §7.3).
#
# Semantics pinned here:
#  1. The problem type is `CorePotts.PottsProblem` (renamed from `CPMProblem`), with its
#     supertype unchanged (`SciMLBase.AbstractSciMLProblem`, not a DE problem). No alias:
#     `CPMProblem` is not defined in CorePotts or Potts.
#  2. `Potts.PottsProblem` and `CorePotts.PottsProblem` are one function and one type: a
#     symbolic model's problem `isa CorePotts.PottsProblem`.
#  3. `SciMLBase.isdiscrete(alg)` is `true` for every Potts algorithm.
#  4. Solving is unchanged: the renamed problem solves under both algorithms.
using Potts: CorePotts

const p60m2_SciMLBase = CorePotts.SciMLBase

@potts_model P60m2Model begin
    @kinds medium A
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9)^2
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.0m2: PottsProblem (D-075 Q2)" begin
    @test isdefined(CorePotts, :PottsProblem)
    @test !isdefined(CorePotts, :CPMProblem)
    @test !isdefined(Potts, :CPMProblem)
    @test Potts.PottsProblem === CorePotts.PottsProblem
    @test CorePotts.PottsProblem <: p60m2_SciMLBase.AbstractSciMLProblem
    @test !(CorePotts.PottsProblem <: p60m2_SciMLBase.AbstractDEProblem)

    σ = zeros(Int32, 12, 12); σ[4:6, 4:6] .= 1
    prob = PottsProblem(P60m2Model(), [CorePotts.ownership => σ, kind => [:A]], (0, 5))
    @test prob isa CorePotts.PottsProblem
    for alg in (SequentialCPM(), CheckerboardCPM())
        @test p60m2_SciMLBase.isdiscrete(alg)
        sol = solve(prob, alg)
        @test sol.t[end] == 5
        @test count(!iszero, Array(sol.u[end].σ)) > 0
    end
end
