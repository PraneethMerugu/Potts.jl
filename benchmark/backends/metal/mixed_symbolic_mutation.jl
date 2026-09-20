using Test, Potts, SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "mixed_symbolic_mutation.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "symbolic_mutation_observation_failure.jl"))

@testset "mixed symbolic publication and host refresh rollback with device storage" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    for backend in (CPUBackend(), Potts.MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            _mixed_symbolic_mutation_contract((CheckerboardSweepCPM(),), backend)
            # The injected failure is an ordinary host observation error after
            # publication, not a device-copy or execution failure.
            _symbolic_mutation_refresh_failure_contract((CheckerboardSweepCPM(),), backend)
        end
    end
end
