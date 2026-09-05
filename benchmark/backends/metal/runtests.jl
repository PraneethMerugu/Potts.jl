using Test

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

if isempty(ARGS)
    project = dirname(Base.active_project())
    for witness in METAL_SEMANTIC_WITNESSES
        run(`$(Base.julia_cmd()) --project=$(project) --startup-file=no $(@__FILE__) $(witness)`)
    end
else
    length(ARGS) == 1 || error("expected at most one Metal witness argument")
    witness = only(ARGS)
    witness in METAL_SEMANTIC_WITNESSES ||
        error("unknown Metal semantic witness: $(repr(witness))")

    using Metal
    using LocalMath
    using Potts
    import KernelAbstractions

    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    include(witness)
end
