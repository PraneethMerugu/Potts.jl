@testset "optional extension loading" begin
    @test Base.get_extension(
        Potts, :PottsModelingToolkitExt
    ) !== nothing
    @test Base.get_extension(
        Potts, :PottsUnitfulExt
    ) !== nothing
end
