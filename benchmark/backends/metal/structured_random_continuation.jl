using Test
using Potts
import Metal
include(joinpath(@__DIR__, "../../../test/fixtures/structured_random_continuation.jl"))

Metal.functional() || error("structured random continuation requires actual Metal hardware")
Metal.allowscalar(false)

@testset "structured scheduled randomness and checkpoint continuation on actual Metal" begin
    cpu = _structured_random_continuation_contract(CheckerboardSweepCPM(), CPUBackend())
    device = _structured_random_continuation_contract(
        CheckerboardSweepCPM(), Potts.MetalBackend(),
    )
    @test device == cpu
end
