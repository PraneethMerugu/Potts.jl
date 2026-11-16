# Top-level definitions for GPU device test suites (`gpu_tests.jl`, `gpu_fields_tests.jl`, `gpu_acceptance_tests.jl`).

@testsetup module GpuSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using PottsModels: PottsModels, OpenVTGrowingMonolayer, openvt_monolayer_state
using OrdinaryDiffEqTsit5: Tsit5
using Potts.ModelingToolkitBase: ShiftIndex, Clock
using StableRNGs: StableRNG
using Statistics: mean, var

# test-only models that the included acceptance files use by name (D-254)

isdefined(@__MODULE__, :SingleDivisionFixture) ||
    include(joinpath(@__DIR__, "..", "lib", "PottsModels", "test", "fixtures.jl"))
isdefined(@__MODULE__, :stat_accept) || include(joinpath(@__DIR__, "shared", "stats_helpers.jl"))


# ROCm: the hook-based IR checks (negative controls, compile-only launches; D-157)
# (PottsDevices.device_name() == "rocm" && include("device_ir.jl"): now its own item file)


# P6.0b: two relationships, each with its own store, law and shared read claims, on the device
@potts_model MetalSprings begin
    @kinds medium blob
    @parameters begin
        k₁ = 2.0
        k₂ = 2.0
        J[kind, kind] = [0 16; 16 2]
    end
    @variables begin
        rest(bond) = 12.0
        len(tether) = 18.0
    end
    @relationship bond(cell, cell) capacity = 1
    @relationship tether(cell, cell) capacity = 2
    @lattice Lattice((64, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 36)^2
        contacts => J[kind, kind′]
        edges(bond) => k₁ * (distance - rest)^2
        edges(tether) => k₂ * (distance - len)^2
    end
    @sweep Metropolis(; temperature = 10.0)
end


# P6.0ag: every fixed-step ODE system expanded in place. The acceptance file's device testsets
# (each rate shape compiles on the device and equals the CPU Float32 run; a gather ODE runs)
# P6.0ao: `÷`/`div` in generated code stays in Float32 on the device (Base's Float32 `div`
# goes through Float64): a parameter, a variable, a literal and the Int32 `volume`, in an
# energy and in updates, against `div` on the host.
@potts_model MetalIntDiv begin
    @kinds medium A
    @parameters begin
        n = 7.5
    end
    @variables begin
        h(cell) = 0.0
        q(cell) = 0.0
        r(cell) = 0.0
        s(cell) = 9.5
    end
    @lattice Lattice((16, 16); neighborhood = VonNeumann(1))
    @energy cells(A) => (volume - n ÷ 2 - div(volume, 3))^2
    @after_mcs begin
        h ~ volume ÷ 2
        q ~ div(volume + 0.5, n)
        r ~ s ÷ 1.5
    end
    @sweep Metropolis(; temperature = 10.0)
end


# P6.0v: exact host-transfer counts of the current device paths (an ordinary test; P6.0v1/v2
# update its formulas)
# (include("transfer_counts.jl"): now its own item file)

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
