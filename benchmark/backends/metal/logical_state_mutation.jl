using Test
using Potts
using SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "logical_state_mutation.jl"))

@testset "logical state mutation uses ordinary CPU and Metal publication" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    for backend in (CPUBackend(), Potts.MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            _logical_state_mutation_contract((CheckerboardSweepCPM(),), backend)
        end
    end
end
