# Exec static gates: type stability of the host executor, launches and plan walk.
using JET: @test_opt

@testset "Exec JET" begin
    a = zeros(Float32, 64)
    @test_opt target_modules = (LatticeFields.Exec,) Exec.host_launch!(AddK{1}(), 64, (a,))
    @test_opt target_modules = (LatticeFields.Exec,) Exec.launch!(KA.CPU(), AddK{1}(), 64, (a,))
    ls, _, _ = host_plan(40)
    plan = Exec.Plan(ls)
    @test_opt target_modules = (LatticeFields.Exec,) plan()
end
