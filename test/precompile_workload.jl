# F4-14 (F4 design §5, AF-08): Potts' precompile workload runs on front end B (a plain
# PDESystem coupled with `couple` and with `@fields`; the coupled model's first MCS with
# ExplicitEuler and with BackwardEuler, and its `field_report`) without a warning.
using Potts, Test

@testset "F4-14: the precompile workload runs" begin
    @test (@test_logs min_level = Base.CoreLogging.Warn Potts._precompile_workload()) === nothing
end
