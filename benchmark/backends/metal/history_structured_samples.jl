using Test
using Potts
using SciMLBase
import Metal

include(joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "history_structured_samples.jl"))

@testset "structured history feedback and continuation on Metal" begin
    Metal.functional() || error("structured history requires functional Metal")
    Metal.allowscalar(false)
    test_structured_history_samples((CheckerboardSweepCPM(),); backend = Potts.MetalBackend())
end
