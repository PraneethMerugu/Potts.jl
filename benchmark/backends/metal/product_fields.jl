using Test
using Potts
using SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "product_fields.jl"))

@testset "authored scalar, vector, and nested product fields execute on CPU and Metal" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    for backend in (Potts.CPUBackend(), Potts.MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            _product_field_execution_contract(CheckerboardSweepCPM(), backend)
        end
    end
end
