using Aqua

@testset "PottsToolkit package-quality gates" begin
    Aqua.test_all(PottsToolkit)
    @test isempty(Test.detect_ambiguities(PottsToolkit; recursive = true))

    sequential = @inferred SequentialCPM()
    checkerboard = @inferred CheckerboardSweepCPM()
    @test @inferred(CorePotts.component_identity(sequential)) ==
        CorePotts.ComponentIdentity(:sequential_cpm, v"1.0.0", :algorithm)
    @test @inferred(CorePotts.component_identity(checkerboard)) ==
        CorePotts.ComponentIdentity(:checkerboard_sweep_cpm, v"1.0.0", :algorithm)
end
