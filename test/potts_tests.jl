@testitem "Potts re-exports CorePotts" tags = [:potts] begin
    using Potts
    @testset "Potts re-exports CorePotts" begin
        @test isdefined(Potts, :PottsProblem)
        @test Potts.PottsProblem === Potts.CorePotts.PottsProblem
    end
end
