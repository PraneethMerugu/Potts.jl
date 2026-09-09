using Test, Potts, SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "vector_parameters.jl"))

@testset "whole and indexed vector parameters with device storage" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    for backend in (CPUBackend(), Potts.MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            _fixed_vector_parameters_contract((CheckerboardSweepCPM(),), backend)
            _vector_parameter_units_and_imports_contract((CheckerboardSweepCPM(),), backend)
        end
    end
end
