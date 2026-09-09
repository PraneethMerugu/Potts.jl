using Test
using Potts
using SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "cell_processes.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "model_cell_transactions.jl"))

@testset "authored cell processes and retirement execute on CPU and Metal" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    for backend in (Potts.CPUBackend(), Potts.MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            _cell_process_contract(CheckerboardSweepCPM(), backend)
            _model_cell_transaction_contract(CheckerboardSweepCPM(), backend)
            _structured_retirement_contract(CheckerboardSweepCPM(), backend)
        end
    end
end
