using Test
using Potts
using SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "discrete_field_rhs.jl"))

@testset "explicit local field rates and stochastic continuation on Metal" begin
    Metal.functional() || error("explicit field-rate tests require functional Metal")
    Metal.allowscalar(false)
    test_discrete_field_clipping_and_rollback(Potts.CheckerboardSweepCPM(), Potts.CPUBackend())
    test_discrete_field_clipping_and_rollback(Potts.CheckerboardSweepCPM(), Potts.MetalBackend())
    for stochastic in (false, true)
        reference = test_discrete_field_rhs(Potts.CheckerboardSweepCPM(), Potts.CPUBackend(); stochastic)
        @test test_discrete_field_rhs(Potts.CheckerboardSweepCPM(), Potts.MetalBackend(); stochastic) == reference
    end
end
