# F4-14 (F4 design §5, AF-08): the precompile workload runs on the current API (owned
# ExplicitEuler and BackwardEuler in Float64 and Float32, one ODE right-side call, the
# solution read by name, `field_report`) without a warning.
@testset "F4-14: the precompile workload runs" begin
    @test (@test_logs min_level = Base.CoreLogging.Warn LatticePDE._precompile_workload()) === nothing
end
