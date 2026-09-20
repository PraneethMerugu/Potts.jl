using Test
using Potts
using SciMLBase
using Symbolics
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "cell_processes.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "model_cell_transactions.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "lifecycle_public.jl"))

@testset "authored cell processes and retirement execute on CPU and Metal" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    for backend in (Potts.CPUBackend(), Potts.MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            _cell_process_contract(CheckerboardSweepCPM(), backend)
            _model_cell_transaction_contract(CheckerboardSweepCPM(), backend)
            _structured_retirement_contract(CheckerboardSweepCPM(), backend)
        end
    end
end

@testset "mitotic-delay Uniform draw preserves CPU/Metal lifecycle parity" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    fixture = lifecycle_public_fixture(; mitotic_draw = true)
    problem = PottsProblem(
        mtkcompile(fixture.source), fixture.initial, (0, 3); seed = 0x51f3
    )
    cpu = solve(
        problem, CheckerboardSweepCPM();
        backend = Potts.CPUBackend(), scalar_type = Float32,
        save_everystep = true,
    )
    device = solve(
        problem, CheckerboardSweepCPM();
        backend = Potts.MetalBackend(), scalar_type = Float32,
        save_everystep = true,
    )
    @test cpu.retcode == device.retcode == SciMLBase.ReturnCode.Success
    @test cpu.t == device.t == collect(0:3)
    @test count(!iszero, cpu(3).cell_kinds) == 4
    for index in eachindex(cpu.u)
        @test Array(device.u[index].ownership) == cpu.u[index].ownership
        @test Array(device.u[index].cell_kinds) == cpu.u[index].cell_kinds
    end
    @test device.stats == cpu.stats
end
