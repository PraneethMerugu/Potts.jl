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
    "corepotts_relationship_energy.jl",
    "native_component_execution.jl",
)
const METAL_PERFORMANCE_PROGRAMS = ("native_component_performance.jl",)

@testset "real-Metal runner inventory" begin
    discovered = Set(filter(name -> endswith(name, ".jl") && name != "runtests.jl",
        readdir(@__DIR__)))
    @test discovered == union(Set(METAL_SEMANTIC_WITNESSES),
        Set(METAL_PERFORMANCE_PROGRAMS))
end

# With no argument, the authoritative device packet runs every semantic
# witness. CI may name one witness so each large GPU compiler workload receives
# a fresh Julia process without changing the covered set.
selected_witnesses = if isempty(ARGS)
    METAL_SEMANTIC_WITNESSES
else
    length(ARGS) == 1 || error("expected at most one Metal witness argument")
    witness = only(ARGS)
    witness in METAL_SEMANTIC_WITNESSES ||
        error("unknown Metal semantic witness: $(repr(witness))")
    (witness,)
end

for witness in selected_witnesses
    include(witness)
end
