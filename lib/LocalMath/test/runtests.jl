using Aqua
using ExplicitImports
using Test
import LocalMath

@testset "LocalMath package quality" begin
    Aqua.test_all(LocalMath; ambiguities = false)
    # These qualified non-public accesses implement the reviewed central
    # admission, compiler-identity, storage-alias, and backend-validation
    # boundaries. Keep the allowlist exact so new private reliance still fails.
    qualified_internal_boundary = (
        Symbol("@adapt_structure"),
        Symbol("@atomic"),
        Symbol("@nospecializeinfer"),
        :Argument,
        :CodeInfo,
        :CodeInstance,
        :Compiler,
        :Const,
        :LLVMPtr,
        :MethodInstance,
        :PkgId,
        :SSAValue,
        :SlotNumber,
        :Typeof,
        :apply_type,
        :checked_mul,
        :code_typed_by_type,
        :datatype_alignment,
        :device,
        :functional,
        :get_world_counter,
        :ifelse,
        :inferencebarrier,
        :invoke_in_world,
        :loaded_modules,
        :mightalias,
        :return_type,
        :throw_boundserror,
        :throw_inexacterror,
        :typename,
        :typesof,
        :uncompressed_ast,
        :unwrap_unionall,
    )
    ExplicitImports.test_explicit_imports(
        LocalMath;
        all_qualified_accesses_are_public =
            (; ignore = qualified_internal_boundary),
    )
    @test isempty(Test.detect_ambiguities(
        LocalMath, Base; recursive = true
    ))
end

include("support.jl")
const LOCALMATH_INCLUDED_TESTS = (
    "test_public_api.jl",
    "test_spatial_model.jl",
    "test_stage_model.jl",
    "test_stage_parameter_layout.jl",
    "test_stage_planning.jl",
    "test_stage_preparation.jl",
    "test_direct_pointwise_stage.jl",
    "test_unique_stage.jl",
    "test_stage_program_lifecycle.jl",
    "test_execution_receipts.jl",
    "test_reduce_stage.jl",
    "test_resolve_stage.jl",
    "test_runtime_routed_stage.jl",
    "test_candidate_grouping.jl",
    "test_collect_stage_model.jl",
    "test_collect_stage_execution.jl",
    "test_ordered_fold_stage_model.jl",
    "test_ordered_fold_stage_execution.jl",
    "test_stage_failure_barrier.jl",
    "test_stage_collection_binding.jl",
    "test_collection_stage_access.jl",
    "test_relation_device_views.jl",
    "test_structural_binding.jl",
    "test_bound_law.jl",
    "test_relation_preparation.jl",
    "test_composed_relation.jl",
    "test_relation_receipts.jl",
    "test_inspection_phases.jl",
    "test_inspection_diagnostics.jl",
    "test_descriptor_presentation.jl",
    "test_storage_authoring.jl",
    "test_prepare_authoring.jl",
    "test_localmath_authoring.jl",
)

@testset "LocalMath test runner inventory" begin
    discovered = sort(filter(name ->
        startswith(name, "test_") && endswith(name, ".jl"), readdir(@__DIR__)))
    @test sort(collect(LOCALMATH_INCLUDED_TESTS)) == discovered
end

foreach(include, LOCALMATH_INCLUDED_TESTS)
