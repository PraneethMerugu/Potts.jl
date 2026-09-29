@testset "generous allocation regression ceilings" begin
    measurements = allocation_measurements()
    @test measurements.cell_type <= 8 * 2^20
    @test measurements.identity <= 20 * 2^20
    @test measurements.boundaries <= 4 * 2^20
    @test measurements.conformance <= 1 * 2^20
end
