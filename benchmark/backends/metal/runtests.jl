using Test
using Metal
using LocalMath
using Potts
import KernelAbstractions

const METAL_SEMANTIC_WITNESSES = (
    "discrete_field_rhs.jl",
    "extension_load_order.jl",
    "problem_construction.jl",
    "authored_randomness.jl",
    "scheduled_process_draws.jl",
    "cell_polarity_dynamics.jl",
    "fixed_vector_operations.jl",
    "history_structured_samples.jl",
    "product_fields.jl",
    "cell_processes.jl",
    "logical_state_mutation.jl",
    "mixed_symbolic_mutation.jl",
    "vector_parameters.jl",
    "corepotts_relationship_energy.jl",
    "corepotts_relationship_stages.jl",
    "native_component_execution.jl",
)
const METAL_PERFORMANCE_PROGRAMS = ("native_component_performance.jl",)

@testset "real-Metal runner inventory" begin
    discovered = Set(
        filter(
            name -> endswith(name, ".jl") && name != "runtests.jl",
            readdir(@__DIR__)
        )
    )
    @test discovered == union(
        Set(METAL_SEMANTIC_WITNESSES),
        Set(METAL_PERFORMANCE_PROGRAMS)
    )
end

isempty(ARGS) || error("the complete Metal profile does not accept selectors")
Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

for witness in METAL_SEMANTIC_WITNESSES
    include(witness)
end
