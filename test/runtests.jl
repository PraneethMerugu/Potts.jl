using ParallelTestRunner
import Potts

const POTTS_TESTS = (
    "test_public_api.jl", "test_system_contract.jl",
    "test_statements_and_traversal.jl", "test_completion_and_diagnostics.jl",
    "test_units_and_parameters.jl", "test_mtkcompile.jl",
    "test_initial_problem_remake.jl", "test_runtime_solution_sii.jl",
    "test_source_traversal_authority.jl", "test_native_authoring.jl",
    "test_native_component_pools.jl", "test_sciml_lifecycle.jl",
    "test_lifecycle_public.jl", "test_relationship_host_transactions.jl",
    "test_external_compiler_spi.jl", "test_scientific_operation_spi.jl",
    "test_scientific_witnesses.jl", "test_product_programs.jl",
    "test_fresh_process.jl", "test_core_spi_boundary.jl",
    "test_package_quality.jl",
)

const POTTS_TEST_SUITE = Dict(
    splitext(file)[1] => :(include($(joinpath(@__DIR__, file))))
    for file in POTTS_TESTS
)
POTTS_TEST_SUITE["inventory"] = quote
    discovered = Set(filter(
        name -> startswith(name, "test_") && endswith(name, ".jl"),
        readdir(@__DIR__),
    ))
    @test discovered == Set($(POTTS_TESTS))
end

const POTTS_TEST_INIT = quote
    include($(joinpath(@__DIR__, "setup.jl")))
    using Aqua
    using ExplicitImports
end

ParallelTestRunner.runtests(
    Potts,
    ARGS;
    testsuite=POTTS_TEST_SUITE,
    init_code=POTTS_TEST_INIT,
    serial=["inventory", "test_package_quality"],
    serial_position=:after,
)
