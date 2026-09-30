using Potts, Test

@testset "Potts re-exports CorePotts" begin
    @test isdefined(Potts, :CPMProblem)
end

include(joinpath(@__DIR__, "..", "benchmark", "models.jl"))
include("ports/models.jl")
include("ports/symbolic_models.jl")
include("symbolic.jl")
include("oracle.jl")
include("audit.jl")
include("units.jl")
include("adaptive.jl")
get(ENV, "POTTS_GPU", "") == "metal" && include("gpu.jl")
get(ENV, "POTTS_QA", "true") == "true" && include("qa.jl")
