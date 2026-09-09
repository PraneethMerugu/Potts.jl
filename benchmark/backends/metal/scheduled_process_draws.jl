using Test, Potts
import Metal
include(joinpath(@__DIR__, "../../../test/fixtures/scheduled_process_draws.jl"))

Metal.functional() || error("scheduled process draws require actual Metal hardware")
Metal.allowscalar(false)
@testset "scheduled process draws and checkpoint on actual Metal" begin
    cpu = _scheduled_draw_contract(CheckerboardSweepCPM(), CPUBackend())
    device = _scheduled_draw_contract(CheckerboardSweepCPM(), Potts.MetalBackend())
    for (host, gpu) in zip(cpu, device)
        @test host.model == gpu.model
        @test host.sites == gpu.sites
        @test getindex.(host.cells, 1) == getindex.(gpu.cells, 1)
        @test getindex.(host.cells, 2) ≈ getindex.(gpu.cells, 2) rtol = 2.0f-5 atol = 2.0f-6
    end
end
