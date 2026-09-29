using Potts, Test

@testset "Potts re-exports CorePotts" begin
    @test isdefined(Potts, :CPMProblem)
end

include("parity/graner.jl")
include("parity/legacy_models.jl")
