using Test
using Potts
using SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "scoped_quantities.jl"))

@testset "scoped quantities and anchors execute on CPU and Metal" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    for backend in (CPUBackend(), MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            _scoped_population_contract(CheckerboardSweepCPM(), backend)
            _scoped_import_contract(CheckerboardSweepCPM(), backend)
            for domain in (:cell, :site)
                _scoped_anchor_contract(CheckerboardSweepCPM(), backend, domain)
            end
        end
    end
end
