using ParallelTestRunner
using Test
import LocalMath

const LOCALMATH_INCLUDED_TESTS = (
    "test_public_api.jl",
    "test_spatial_model.jl",
    "test_stage_model.jl",
    "test_stage_parameter_layout.jl",
    "test_stage_planning.jl",
    "test_stage_preparation.jl",
    "test_direct_pointwise_stage.jl",
    "test_empty_pointwise_domains.jl",
    "test_trigonometric_stages.jl",
    "test_product_values.jl",
    "test_unique_stage.jl",
    "test_stage_program_lifecycle.jl",
    "test_execution_receipts.jl",
    "test_launch_contract.jl",
    "test_reduce_stage.jl",
    "test_reduction_control.jl",
    "test_resolve_stage.jl",
    "test_runtime_routed_stage.jl",
    "test_candidate_grouping.jl",
    "test_collect_stage_model.jl",
    "test_collect_stage_execution.jl",
    "test_collect_canonical_order.jl",
    "test_keyed_reduce_stage.jl",
    "test_ordered_fold_stage_model.jl",
    "test_ordered_fold_stage_execution.jl",
    "test_ordered_fold_step_validation.jl",
    "test_ordered_fold_control.jl",
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
    "test_bounded_reductions.jl",
    "test_semantic_oracles.jl",
)

const LOCALMATH_TEST_SUITE = Dict{String, Expr}(
    "package_quality" => quote
        using Aqua
        using ExplicitImports

        @testset "LocalMath package quality" begin
            Aqua.test_all(LocalMath; ambiguities = false)
            # These qualified non-public accesses implement the reviewed
            # central admission, compiler-identity, storage-alias, and
            # backend-validation boundaries. Keep the allowlist exact so new
            # private reliance still fails.
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
                :copyto!,
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
            @test isempty(
                Test.detect_ambiguities(
                    LocalMath, Base; recursive = true
                )
            )
        end
    end,
    "test_runner_inventory" => quote
        @testset "LocalMath test runner inventory" begin
            discovered = sort(
                filter(
                    name -> startswith(name, "test_") && endswith(name, ".jl"),
                    readdir(@__DIR__),
                )
            )
            @test sort(collect($LOCALMATH_INCLUDED_TESTS)) == discovered
        end
    end,
)

for test_file in LOCALMATH_INCLUDED_TESTS
    test_name = first(splitext(test_file))
    LOCALMATH_TEST_SUITE[test_name] = quote
        include($(joinpath(@__DIR__, "support.jl")))
        LocalMathTestTelemetry.include_fixture(
            @__MODULE__, $(joinpath(@__DIR__, test_file)), $test_name;
            kind = "parallel_fixture",
        )
    end
end

const LOCALMATH_TEST_INITIALIZATION = quote
    using Test
    import KernelAbstractions
    import LocalMath
    include($(joinpath(@__DIR__, "telemetry_support.jl")))
end

ParallelTestRunner.runtests(
    LocalMath,
    ARGS;
    testsuite = LOCALMATH_TEST_SUITE,
    init_code = LOCALMATH_TEST_INITIALIZATION,
    serial = ["package_quality", "test_runner_inventory"],
)
