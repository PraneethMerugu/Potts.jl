using Potts, Test

@testset "Potts re-exports CorePotts" begin
    @test isdefined(Potts, :CPMProblem)
end

include(joinpath(@__DIR__, "..", "benchmark", "models.jl"))
include("parity/models.jl")
include("parity/symbolic_models.jl")
include("parity/graner.jl")
include("parity/legacy_models.jl")
include("symbolic.jl")
