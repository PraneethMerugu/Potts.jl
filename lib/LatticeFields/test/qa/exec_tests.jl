# Exec static gates: type stability of the host executor, launches and plan walk.

@testsetup module LF_qa_exec
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields.Schedule: plan
include("../exec_helpers.jl")
using JET: @test_opt
include("../shared/export_all.jl")
end

@testitem "Exec JET" setup = [LF_qa_exec] tags = [:latticefields, :qa] begin
@testset "Exec JET" begin
    a = zeros(Float32, 64)
    @test_opt target_modules = (LatticeFields.Exec,) Exec.host_launch!(AddK{1}(), 64, (a,))
    @test_opt target_modules = (LatticeFields.Exec,) Exec.launch!(KA.CPU(), AddK{1}(), 64, (a,))
    ls, _, _ = host_plan(40)
    plan = Exec.Plan(ls)
    @test_opt target_modules = (LatticeFields.Exec,) plan()
end
end
