using Test, Potts
@testset "Potts re-exports CorePotts" begin
    @test isdefined(Potts, :CorePotts)
end
