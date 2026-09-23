using Test
using Potts
using SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "scoped_quantities.jl"))

@testset "scoped quantities and anchors execute on CPU and Metal" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    for backend in (Potts.CPUBackend(), Potts.MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            _scoped_population_contract(Potts.CheckerboardSweepCPM(), backend)
            _scoped_import_contract(Potts.CheckerboardSweepCPM(), backend)
            for domain in (:cell, :site)
                _scoped_anchor_contract(Potts.CheckerboardSweepCPM(), backend, domain)
            end
        end
    end
end
