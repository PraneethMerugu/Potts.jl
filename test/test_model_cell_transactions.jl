include("fixtures/model_cell_transactions.jl")

@testset "model and vector cell updates share entry values across checkpoints" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        _model_cell_transaction_contract(algorithm, CPUBackend())
    end
end
