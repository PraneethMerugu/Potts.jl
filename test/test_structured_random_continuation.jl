include("fixtures/structured_random_continuation.jl")

@testset "structured scheduled randomness retains identity and checkpoint continuation" begin
    reference = nothing
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        values = _structured_random_continuation_contract(algorithm, CPUBackend())
        with_unrelated = _structured_random_continuation_contract(
            algorithm, CPUBackend(); unrelated = true,
        )
        @test with_unrelated == values
        reference === nothing || @test values == reference
        reference = values
    end
end
