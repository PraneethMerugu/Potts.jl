include("fixtures/cell_polarity_dynamics.jl")

@testset "cell polarity consumes held turns once per selected identity" begin
    reference = nothing
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        result = _polarity_dynamics_contract(algorithm, CPUBackend())
        changed = _polarity_dynamics_contract(algorithm, CPUBackend(); reordered = true, unrelated = true)
        @test changed == result
        reference === nothing || @test result == reference
        reference = result
    end
    _polarity_dynamics_contract(SequentialCPM(), CPUBackend(); scalar_type = Float64)
end
