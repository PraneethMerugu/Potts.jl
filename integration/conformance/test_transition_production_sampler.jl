using Test
using KernelAbstractions
using .TransitionFixtures
using .ProductionTransitionSampler

@testset "transition-kernel production transition sampler" begin
    manifest = load_transition_manifest()
    fixtures = [build_transition_fixture(row; manifest)
        for row in empirical_fixture_rows(manifest)]
    unsupported = filter(value -> !value.production_supported, fixtures)
    @test !isempty(unsupported)
    @test_throws ArgumentError sample_production_row(first(unsupported), :sequential;
        replicas = 1, backend = KernelAbstractions.CPU())
    fixture = first(filter(value -> value.production_supported, fixtures))

    for algorithm in (:sequential, :checkerboard)
        oracle = oracle_probability_row(fixture, algorithm)
        @test sum(oracle) ≈ 1
        @test count(>(0), oracle) <=
              manifest["empirical_sampling"]["maximum_oracle_support"]

        first_sample = sample_production_row(fixture, algorithm; replicas = 64,
            backend = KernelAbstractions.CPU())
        replay = sample_production_row(fixture, algorithm; replicas = 64,
            backend = KernelAbstractions.CPU())
        @test sum(first_sample.counts) == 64
        @test first_sample.counts == replay.counts
        @test first_sample.first_seed == 0x1300000000000000
        @test first_sample.last_seed == 0x130000000000003f
        @test first_sample.observation_synchronizations == 64
        @test all(index -> iszero(first_sample.counts[index]) || oracle[index] > 0,
            eachindex(oracle))
    end
end
