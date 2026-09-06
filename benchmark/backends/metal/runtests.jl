using Test
using Metal
using LocalMath
using Potts
import KernelAbstractions

const METAL_SEMANTIC_WITNESSES = (
    "extension_load_order.jl",
    "corepotts_relationship_energy.jl",
    "corepotts_relationship_stages.jl",
    "native_component_execution.jl",
)
const METAL_PERFORMANCE_PROGRAMS = ("native_component_performance.jl",)

@testset "real-Metal runner inventory" begin
    discovered = Set(filter(name -> endswith(name, ".jl") && name != "runtests.jl",
        readdir(@__DIR__)))
    @test discovered == union(Set(METAL_SEMANTIC_WITNESSES),
        Set(METAL_PERFORMANCE_PROGRAMS))
end

isempty(ARGS) || error("the complete Metal profile does not accept selectors")
Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

for witness in METAL_SEMANTIC_WITNESSES
    include(witness)
end
