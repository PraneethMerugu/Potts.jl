using Metal
using LocalMath
using Potts
using Test
import KernelAbstractions

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

const METAL_SEMANTIC_WITNESSES = (
    "extension_load_order.jl",
    "corepotts_relationship_stages.jl",
    "corepotts_stabilization.jl",
    "corepotts_relationship_energy.jl",
    "localmath_execution_parity.jl",
    "proposal_execution_parity.jl",
    "queued_lifecycle_runtime.jl",
    "lifecycle_transaction_conformance.jl",
    "native_component_execution.jl",
)
const METAL_PERFORMANCE_PROGRAMS = ("native_component_performance.jl",)

@testset "real-Metal runner inventory" begin
    discovered = Set(filter(name -> endswith(name, ".jl") && name != "runtests.jl",
        readdir(@__DIR__)))
    @test discovered == union(Set(METAL_SEMANTIC_WITNESSES),
        Set(METAL_PERFORMANCE_PROGRAMS))
end

# The authoritative device packet runs every semantic witness. Performance
# programs are intentionally separate and never implied by this runner.
for witness in METAL_SEMANTIC_WITNESSES
    include(witness)
end
