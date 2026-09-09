using ParallelTestRunner
import Potts

const POTTS_TESTS = (
    "test_public_api.jl", "test_system_contract.jl",
    "test_component_replacement.jl",
    "test_compound_effects.jl",
    "test_structured_state_authoring.jl",
    "test_state_initial_value_types.jl",
    "test_product_state_authoring.jl",
    "test_product_field_authoring.jl",
    "test_product_field_substitution.jl",
    "test_product_proposal_reads.jl",
    "test_state_initial_selection.jl",
    "test_component_initial_units.jl",
    "test_product_state_defaults.jl",
    "test_model_state_proposal_reads.jl",
    "test_model_state_energy.jl",
    "test_model_site_transactions.jl",
    "test_structured_assignments.jl",
    "test_dimensional_state_values.jl",
    "test_state_reference_inference.jl",
    "test_fixed_vector_operations.jl",
    "test_statements_and_traversal.jl", "test_completion_and_diagnostics.jl",
    "test_units_and_parameters.jl", "test_mtkcompile.jl",
    "test_initial_problem_remake.jl", "test_runtime_solution_sii.jl",
    "test_addressed_randomness.jl",
    "test_source_traversal_authority.jl", "test_native_authoring.jl",
    "test_native_component_pools.jl", "test_sciml_problem_and_indexing.jl",
    "test_sciml_callbacks_and_replay.jl",
    "test_sciml_ensemble_and_failures.jl",
    "test_lifecycle_public_contracts.jl",
    "test_lifecycle_public_arbitration.jl",
    "test_lifecycle_public_trajectories.jl",
    "test_lifecycle_public_policies.jl",
    "test_relationship_host_transactions.jl",
    "test_external_compiler_spi.jl", "test_scientific_operation_spi.jl",
    "test_external_operation_energy.jl",
    "test_gather_reductions.jl",
    "test_scientific_reference_witnesses.jl",
    "test_scientific_relationship_witnesses.jl",
    "test_scientific_activity_field_witnesses.jl",
    "test_product_programs.jl",
    "test_platform_smoke.jl",
    "test_fresh_process.jl", "test_core_spi_boundary.jl",
    "test_package_quality.jl",
)

# Each helper is owned either by the worker-wide setup or by one test unit.
# Keeping that inventory explicit prevents detached fixture artifacts without
# turning helpers into a second test suite.
const POTTS_TEST_FIXTURES = (
    "ExternalCompilerSPIFixture.jl",
    "ExternalSurfaceOperationFixture.jl",
    "LifecycleOperationFixtures.jl",
    "lifecycle_public.jl",
    "sciml_lifecycle.jl",
    "vector_rotation.jl",
    "product_fields.jl",
)

const POTTS_TEST_SUITE = Dict(
    splitext(file)[1] => :(include($(joinpath(@__DIR__, file))))
        for file in POTTS_TESTS
)
POTTS_TEST_SUITE["inventory"] = quote
    discovered = Set(
        filter(
            name -> startswith(name, "test_") && endswith(name, ".jl"),
            readdir(@__DIR__),
        )
    )
    @test discovered == Set($(POTTS_TESTS))

    fixture_directory = joinpath(@__DIR__, "fixtures")
    discovered_fixtures = Set(
        filter(
            name -> endswith(name, ".jl"),
            readdir(fixture_directory),
        )
    )
    @test discovered_fixtures == Set($(POTTS_TEST_FIXTURES))
end

const POTTS_TEST_INIT = quote
    include($(joinpath(@__DIR__, "setup.jl")))
    include($(joinpath(@__DIR__, "fixtures", "lifecycle_public.jl")))
    include($(joinpath(@__DIR__, "fixtures", "sciml_lifecycle.jl")))
end

ParallelTestRunner.runtests(
    Potts,
    ARGS;
    testsuite = POTTS_TEST_SUITE,
    init_code = POTTS_TEST_INIT,
    serial = ["inventory", "test_package_quality"],
    serial_position = :after,
)
