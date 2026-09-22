include("fixtures/structured_random_continuation.jl")

@testset "structured scheduled randomness retains identity and checkpoint continuation" begin
    reference = nothing
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        values = _structured_random_continuation_contract(algorithm, CPUBackend())
        before = _structured_random_continuation_contract(
            algorithm, CPUBackend(); unrelated = :before,
        )
        after = _structured_random_continuation_contract(
            algorithm, CPUBackend(); unrelated = :after,
        )
        @test before == values
        @test after == values
        reference === nothing || @test values == reference
        reference = values
    end
end
