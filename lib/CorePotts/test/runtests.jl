using Aqua
using ExplicitImports
using Test
import CorePotts
import LocalMath

const _COREPOTTS_COMPILED_PROGRAM_TESTS = (
    "test_compiled_program_support.jl",
    "test_compiled_program_execution.jl",
    "test_compiled_program_checkerboard_oracles.jl",
    "test_compiled_program_state.jl",
    "test_compiled_program_parallel_trackers.jl",
    "test_compiled_program_relationships_checkpoint.jl",
    "test_compiled_program_extensibility_storage.jl",
)
const _COREPOTTS_DIRECT_TESTS = (
    "test_api_boundary.jl",
    "test_rng_contract.jl",
    "test_scientific_reference.jl",
    "test_compiled_program.jl",
    "test_surface_tracker_contract.jl",
    "test_scientific_geometry_contract.jl",
    "test_relationship_access_contract.jl",
    "test_descriptor_state_spi.jl",
    "test_acceptance.jl",
    "test_capabilities.jl",
    "test_lifecycle_selection_oracle.jl",
    "test_lifecycle_receipts.jl",
    "test_localmath_compiler_boundary.jl",
)
const _COREPOTTS_TEST_HELPER_EXCLUSIONS = ()
const _COREPOTTS_DEVICE_CONFORMANCE_WITNESSES = (
    "checkerboard_execution.jl",
    "descriptor_boundary.jl",
    "lifecycle_execution.jl",
    "lifecycle_policy_execution.jl",
    "localmath_execution.jl",
    "relationship_execution.jl",
    "surface_execution.jl",
)

@testset "ordinary test runner owns every CorePotts test file" begin
    discovered = Set(filter(
        name -> startswith(name, "test_") && endswith(name, ".jl"),
        readdir(@__DIR__),
    ))
    included = Set((
        _COREPOTTS_DIRECT_TESTS...,
        _COREPOTTS_COMPILED_PROGRAM_TESTS...,
    ))
    exclusions = Set(_COREPOTTS_TEST_HELPER_EXCLUSIONS)
    @test isempty(intersect(included, exclusions))
    @test union(included, exclusions) == discovered
end

@testset "CorePotts owns every device conformance witness" begin
    witness_directory = joinpath(@__DIR__, "backend_conformance")
    discovered = Set(filter(
        name -> endswith(name, ".jl"), readdir(witness_directory)
    ))
    @test discovered == Set(_COREPOTTS_DEVICE_CONFORMANCE_WITNESSES)
end

for test_file in _COREPOTTS_DIRECT_TESTS
    include(test_file)
end

@testset "CorePotts package quality" begin
    Aqua.test_all(CorePotts; ambiguities = false)
    # Exact non-public dependencies support device adaptation, atomic
    # arbitration, world-age checks, and storage alias checks. LocalMath
    # consumers use only its declared public compiler surface.
    qualified_internal_boundary = (
        Symbol("@adapt_structure"),
        Symbol("@atomic"),
        :dataids,
        :device,
        :GIT_VERSION_INFO,
        :JLOptions,
        :foreachindex,
        :get_world_counter,
        :invoke_in_world,
        :libllvm_version,
        :mightalias,
        :setindex,
    )
    ExplicitImports.test_explicit_imports(
        CorePotts;
        all_qualified_accesses_are_public =
            (; ignore = qualified_internal_boundary),
    )
    ambiguities = Test.detect_ambiguities(CorePotts, Base; recursive = true)
    owned = filter(ambiguities) do pair
        any(method -> method.module === CorePotts, pair)
    end
    @test isempty(owned)
end
