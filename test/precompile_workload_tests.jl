# Potts' precompile workload runs on the standalone field path (a plain
# PDESystem coupled with `couple` and with `@fields`; the coupled model's first MCS with
# ExplicitEuler and with BackwardEuler, and its `field_report`) without a warning.

@testsetup module PrecompileWorkloadSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts, Test
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "F4-14: the precompile workload runs" setup = [PrecompileWorkloadSetup] tags = [:potts, :precompile_workload] begin
    @testset "F4-14: the precompile workload runs" begin
        @test (@test_logs min_level = Base.CoreLogging.Warn Potts._precompile_workload()) === nothing
    end
end
