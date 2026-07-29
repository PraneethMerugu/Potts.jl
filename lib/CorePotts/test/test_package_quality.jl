using Aqua

@testset "CorePotts package-quality gates" begin
    Aqua.test_all(CorePotts)
    @test isempty(Test.detect_ambiguities(CorePotts; recursive = true))

    versions = @inferred scientific_contract_versions()
    sequential = @inferred algorithm_guarantees(SequentialCPM())
    checkerboard = @inferred algorithm_guarantees(CheckerboardSweepCPM())
    @test versions.sequential_algorithm == v"1.0.0"
    @test sequential.proposal_process.recipient === :uniform_with_replacement
    @test checkerboard.transaction_semantics.snapshot === :common_per_color
end
