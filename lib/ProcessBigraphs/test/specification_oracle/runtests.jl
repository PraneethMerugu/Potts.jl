using Test
using TOML
using SHA

include(joinpath(@__DIR__, "Oracle.jl"))
using .SpecificationOracle

const FIXTURE = joinpath(@__DIR__, "fixtures.toml")

@testset "specification independent oracle units" begin
    results = SpecificationOracle.oracle_results(FIXTURE)
    @test length(results) == 22
    @test Set(keys(results)) ==
        Set(SpecificationOracle.FEATURE_IDS)
    @test results["imminent-event-scheduler"] ==
        "fast|fast+slow|fast|fast+slow"
    @test results["serial-semantic-executor"] ==
        "state=24;events=4"
    @test results["same-time-common-snapshot"] ==
        "fast:0|fast:1|slow:1|fast:12|fast:13|slow:13"
    @test results["semantic-lineage-rng"] ==
        "6627e8d5,e169c58d,bc57ac4c,9b00dbd8"
end
@testset "specification oracle mutation sensitivity" begin
    reference = SpecificationOracle.oracle_results(FIXTURE)
    for mutant in (:scheduler, :update, :rng, :failure, :checkpoint)
        candidate = SpecificationOracle.mutated_results(
            FIXTURE, mutant)
        @test candidate != reference
        @test count(id -> candidate[id] != reference[id],
            keys(reference)) == 1
    end
end
