include("../setup.jl")

const AUTHORITATIVE_G5H_FAST_TESTS = (
    "test_public_api_v2.jl",
    "test_system_contract.jl",
    "test_completion_and_diagnostics.jl",
    "test_units_and_parameters.jl",
    "test_mtkcompile.jl",
    "test_initial_problem_remake.jl",
    "test_runtime_solution_sii.jl",
    "test_source_traversal_authority.jl",
    "test_native_authoring.jl",
    "test_native_component_pools.jl",
    "test_sciml_lifecycle_v2.jl",
    "test_lifecycle_public_v2.jl",
    "test_relationship_host_transactions_v2.jl",
    "test_external_compiler_spi_v2.jl",
    "test_scientific_operation_spi.jl",
    "test_scientific_witnesses_v2.jl",
    "test_fresh_process_v2.jl",
    "test_core_spi_boundary.jl",
)

test_root = normpath(joinpath(@__DIR__, ".."))
include(joinpath(test_root, "test_runner_authority.jl"))
verify_authoritative_runner(test_root, AUTHORITATIVE_G5H_FAST_TESTS)

@testset "G5H authoritative fast surface" begin
    for file in AUTHORITATIVE_G5H_FAST_TESTS
        include(joinpath(test_root, file))
    end
end
