using Test
using .TransitionEmpirical

@testset "transition-kernelE preregistered transition-row statistics" begin
    plan = TransitionSamplingPlan()
    @test plan.replicas == 262_144
    @test total_variation_radius(64, plan) ≈ 0.010142757248393525
    @test absolute_probability_radius(64, plan) ≈ 0.005245697756318495

    oracle = [0.25, 0.50, 0.25, 0.0]
    passing_counts = [65_536, 131_072, 65_536, 0]
    result = evaluate_empirical_row(oracle, passing_counts, 2; plan)
    @test result.passed
    @test result.total_variation == 0
    @test isempty(result.impossible_destinations)
    @test isempty(result.failed_criteria)

    impossible_counts = [65_535, 131_072, 65_536, 1]
    impossible = evaluate_empirical_row(oracle, impossible_counts, 2; plan)
    @test !impossible.passed
    @test impossible.impossible_destinations == [4]
    @test "observed destination outside oracle support" in impossible.failed_criteria

    biased_counts = [55_000, 141_608, 65_536, 0]
    biased = evaluate_empirical_row(oracle, biased_counts, 2; plan)
    @test !biased.passed
    @test any(message -> occursin("total-variation", message),
        biased.failed_criteria)
    @test any(message -> occursin("absolute-probability", message),
        biased.failed_criteria)

    @test_throws ArgumentError evaluate_empirical_row(
        oracle, [1, 2, 3, 4], 2; plan)
    @test_throws ArgumentError evaluate_empirical_row(
        fill(1 / 65, 65), vcat(fill(4033, 64), 4032), 1; plan)
end

@testset "transition-kernelE fixed autocorrelation and ESS estimators" begin
    alternating = repeat([0.0, 1.0], 128)
    @test integrated_autocorrelation_time(alternating; maximum_lag = 20) == 1.0
    @test effective_sample_size(alternating; maximum_lag = 20) == 256
    constant_values = fill(3.0, 32)
    @test integrated_autocorrelation_time(constant_values; maximum_lag = 10) == 1.0
    @test effective_sample_size(constant_values; maximum_lag = 10) == 32
end
