# The precompile workload runs on the current API without warnings.

@testitem "the precompile workload runs" tags = [:corepotts] begin
    using CorePotts, Test
    @testset "the precompile workload runs" begin
        @test (
            @test_logs(
                min_level = Base.CoreLogging.Warn, CorePotts._precompile_workload()
            )
        ) === nothing
    end
end
