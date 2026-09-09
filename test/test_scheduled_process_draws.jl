include("fixtures/scheduled_process_draws.jl")

@testset "authored scheduled draws retain identity and continuation" begin
    reference = nothing
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        values = _scheduled_draw_contract(algorithm, CPUBackend())
        changed = _scheduled_draw_contract(algorithm, CPUBackend(); reordered = true, unrelated = true)
        @test changed == values
        reference === nothing || @test reference == values
        reference = values
    end
end
