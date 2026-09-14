using Test
using Metal
using LocalMath
using Potts
import KernelAbstractions

const METAL_SEMANTIC_SHARDS = (
    authoring_and_state = (
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
    ),
    quantities_and_components = (
        "scoped_quantities.jl",
        "site_aggregates.jl",
        "site_minimum.jl",
        "corepotts_relationship_energy.jl",
        "corepotts_relationship_stages.jl",
        "native_component_execution.jl",
    ),
)
const METAL_PERFORMANCE_PROGRAMS = ("native_component_performance.jl",)

@testset "real-Metal runner inventory" begin
    discovered = Set(
        filter(
            name -> endswith(name, ".jl") && name != "runtests.jl",
            readdir(@__DIR__)
        )
    )
    semantic_witnesses = Tuple(
        witness
        for shard in values(METAL_SEMANTIC_SHARDS)
        for witness in shard
    )
    @test length(semantic_witnesses) == length(Set(semantic_witnesses))
    @test discovered == union(
        Set(semantic_witnesses),
        Set(METAL_PERFORMANCE_PROGRAMS)
    )
end

length(ARGS) <= 1 || error(
    "select at most one Metal semantic shard: " * join(string.(keys(METAL_SEMANTIC_SHARDS)), ", ")
)
witnesses = if isempty(ARGS)
    Tuple(
        witness
        for shard in values(METAL_SEMANTIC_SHARDS)
        for witness in shard
    )
else
    shard = Symbol(only(ARGS))
    haskey(METAL_SEMANTIC_SHARDS, shard) || error(
        "unknown Metal semantic shard $(repr(only(ARGS)))"
    )
    getproperty(METAL_SEMANTIC_SHARDS, shard)
end
Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

for witness in witnesses
    include(witness)
end
