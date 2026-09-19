using Aqua
using Test
import CorePotts

include("test_program_v1.jl")

@testset "CorePotts package quality" begin
    Aqua.test_all(CorePotts; ambiguities = false)
end
