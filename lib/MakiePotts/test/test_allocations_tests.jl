@testsetup module MP_test_allocations
using Test
using Aqua
using CairoMakie
using MakiePotts
using Random
import Makie
import CorePotts
include("shared/makiepotts.jl")
include("shared/export_all.jl")
end

@testitem "generous allocation regression ceilings" setup = [MP_test_allocations] tags = [
    :makiepotts, :allocations,
] begin
    @testset "generous allocation regression ceilings" begin
        measurements = allocation_measurements()
        @test measurements.cell_type <= 8 * 2^20
        @test measurements.identity <= 20 * 2^20
        @test measurements.boundaries <= 4 * 2^20
        @test measurements.conformance <= 1 * 2^20
    end
end
