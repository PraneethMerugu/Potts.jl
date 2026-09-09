using Test, Potts
import Metal
include(joinpath(@__DIR__, "../../../test/fixtures/cell_polarity_dynamics.jl"))

@testset "held-turn cell polarity dynamics on actual Metal" begin
    Metal.functional() || error("polarity dynamics requires functional Metal")
    Metal.allowscalar(false)
    host = _polarity_dynamics_contract(CheckerboardSweepCPM(), CPUBackend())
    device = _polarity_dynamics_contract(CheckerboardSweepCPM(), MetalBackend())
    for (cpu, gpu) in zip(host, device)
        @test cpu.turn == gpu.turn
        @test all(isapprox.(cpu.polarity, gpu.polarity; rtol = 3.0f-6, atol = 3.0f-6))
    end
end
