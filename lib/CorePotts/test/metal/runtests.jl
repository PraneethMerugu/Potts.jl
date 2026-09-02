using CorePotts
using LocalMath
using Metal
using Test

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

const COREPOTTS_METAL_WITNESSES = (
    "corepotts_feasibility.jl",
    "corepotts_stage_boundaries.jl",
)

@testset "CorePotts Metal runner inventory" begin
    discovered = Set(filter(
        name -> endswith(name, ".jl") && name != "runtests.jl",
        readdir(@__DIR__),
    ))
    @test discovered == Set(COREPOTTS_METAL_WITNESSES)
end

foreach(include, COREPOTTS_METAL_WITNESSES)
include(joinpath(@__DIR__, "..", "backend_conformance", "localmath_execution.jl"))
