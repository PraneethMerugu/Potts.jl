@testset "optional extension loading" begin
    @test Base.get_extension(
        PottsToolkit, :PottsToolkitModelingToolkitExt
    ) !== nothing
    @test Base.get_extension(
        PottsToolkit, :PottsToolkitProcessBigraphsExt
    ) !== nothing
    @test Base.get_extension(
        PottsToolkit, :PottsToolkitUnitfulExt
    ) !== nothing
end
