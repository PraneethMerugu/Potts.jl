using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics

include("../test/fixtures/G2SpecializationFixtures.jl")
using .G2SpecializationFixtures

@testset "G2 full specialization-growth qualification" begin
    one = G2SpecializationFixtures.compile_direct_model(1)
    many = G2SpecializationFixtures.compile_direct_model(32)
    stress = G2SpecializationFixtures.compile_direct_model(1024)
    parameter_only = G2SpecializationFixtures.compile_direct_model(
        32;
        weight_default = 7.0,
    )

    @test typeof(one) === typeof(many) ===
          typeof(stress) === typeof(parameter_only)
    reports = (
        one.reports.descriptors,
        many.reports.descriptors,
        stress.reports.descriptors,
        parameter_only.reports.descriptors,
    )
    @test getfield.(reports, :groups) == (1, 1, 1, 1)
    @test getfield.(reports, :occurrences) == (1, 32, 1024, 32)
    @test many.reports.descriptors.group_splits ==
          stress.reports.descriptors.group_splits ==
          parameter_only.reports.descriptors.group_splits
    @test many.reports.descriptors.kernel_families ==
          stress.reports.descriptors.kernel_families ==
          parameter_only.reports.descriptors.kernel_families
end
