using Test
import LocalMath
const LMK = LocalMath

struct RuntimeRoutedStageNode end
struct RoutedUniqueEvaluator end
@inline (::RoutedUniqueEvaluator)(item::Int32, reads, parameters) =
    (value = LMK.RoutedUniqueValue(
        Int32(4) - item, item * Int32(10)),)
struct RoutedReduceEvaluator end
@inline (::RoutedReduceEvaluator)(item::Int32, reads, parameters) =
    (value = LMK.RoutedContribution(
        item == 3 ? Int32(2) : Int32(1), item),)
struct RoutedResolveEvaluator end
@inline (::RoutedResolveEvaluator)(item::Int32, reads, parameters) =
    (value = LMK.RoutedResolutionValue(
        item == 1 ? Int32(2) : Int32(1),
        Int32(4) - item, item),)
struct ZeroRoutedUniqueEvaluator end
@inline (::ZeroRoutedUniqueEvaluator)(item::Int32, reads, parameters) =
    (value = LMK.ConditionalRoutedUniqueValue(
        Int32(0), item, true),)
struct InvalidRoutedUniqueEvaluator end
@inline (::InvalidRoutedUniqueEvaluator)(item::Int32, reads, parameters) =
    (value = LMK.RoutedUniqueValue(Int32(4), item),)

function _runtime_routed_stage(source, output, relation, law, evaluator)
    component = LMK.FieldPublication(
        output, relation, LMK.PublicationValue(:value))
    return LMK.Stage(source, NamedTuple(),
        (LMK.Publication((component,), law),),
        LMK.Evaluator(evaluator), LMK.Control(),
        LMK.SourceOrigin(:runtime_routed_stage_test, 1))
end

function _prepare_runtime_routed(stage, output, relation, storage)
    bound = LMK._bind_law(LMK.LocalLaw(stage), LMK._StructuralBinding(
        (LMK._field_storage_binding(output, storage),),
        (LMK._relation_storage_binding(relation),)))
    backend = LMK.KernelAbstractions.get_backend(storage)
    return LMK.prepare(LMK.plan(bound; backend))
end

function _run_runtime_routed!(stage, output, relation, storage)
    prepared = _prepare_runtime_routed(stage, output, relation, storage)
    event = LMK.execute!(prepared)
    wait(event)
    return only(prepared.runtime.launches).stage
end

@testset "RuntimeRelation routes the existing Stage laws" begin
    source = LMK.Space(RuntimeRoutedStageNode, 3)
    destination = LMK.Space(RuntimeRoutedStageNode, 3)
    relation = LMK.RuntimeRelation(source => destination;
        degree_bound = 1, key_type = Int32)

    unique_output = LMK.Field(destination, Int32)
    unique_storage = fill(Int32(-1), 3)
    unique = _runtime_routed_stage(source, unique_output, relation,
        LMK.Unique(Int32), RoutedUniqueEvaluator())
    unique_prepared = _run_runtime_routed!(
        unique, unique_output, relation, unique_storage)
    @test unique_storage == Int32[30, 20, 10]
    @test only(Array(unique_prepared.execution.status)) ==
        LMK._CANDIDATE_STATUS_SUCCESS

    reduce_output = LMK.Field(destination, Int32)
    reduce_storage = fill(Int32(-1), 3)
    reduce = _runtime_routed_stage(source, reduce_output, relation,
        LMK.Reduce(Int32, +;
            seed = LMK.IdentitySeed(Int32(0))),
        RoutedReduceEvaluator())
    reduce_prepared = _run_runtime_routed!(
        reduce, reduce_output, relation, reduce_storage)
    @test reduce_storage == Int32[3, 3, 0]
    @test only(Array(reduce_prepared.execution.status)) ==
        LMK._CANDIDATE_STATUS_SUCCESS

    resolve_output = LMK.Field(destination, Int32)
    resolve_storage = fill(Int32(-1), 3)
    resolve = _runtime_routed_stage(source, resolve_output, relation,
        LMK.Resolve(Int32, Int32;
            lower = Int32(0), upper = Int32(9)),
        RoutedResolveEvaluator())
    resolve_prepared = _run_runtime_routed!(
        resolve, resolve_output, relation, resolve_storage)
    @test resolve_storage == Int32[3, 1, -1]
    @test only(Array(resolve_prepared.execution.status)) ==
        LMK._CANDIDATE_STATUS_SUCCESS
end

@testset "RuntimeRelation key zero is absent and invalid nonzero keys fail" begin
    source = LMK.Space(RuntimeRoutedStageNode, 1)
    destination = LMK.Space(RuntimeRoutedStageNode, 2)
    relation = LMK.RuntimeRelation(source => destination;
        degree_bound = 1, key_type = Int32)
    output = LMK.Field(destination, Int32)
    partial = LMK.Unique(Int32;
        coverage = LMK.PartialCoverage(),
        onempty = LMK.PreserveEmpty())

    zero_storage = Int32[31, 32]
    zero_stage = _runtime_routed_stage(source, output, relation, partial,
        ZeroRoutedUniqueEvaluator())
    zero_prepared = _run_runtime_routed!(
        zero_stage, output, relation, zero_storage)
    @test zero_storage == Int32[31, 32]
    @test only(Array(zero_prepared.execution.status)) ==
        LMK._CANDIDATE_STATUS_SUCCESS

    invalid_storage = Int32[41, 42]
    invalid_stage = _runtime_routed_stage(source, output, relation, partial,
        InvalidRoutedUniqueEvaluator())
    invalid_prepared = _prepare_runtime_routed(
        invalid_stage, output, relation, invalid_storage)
    invalid_event = LMK.execute!(invalid_prepared)
    error = try
        wait(invalid_event)
        nothing
    catch caught
        caught
    end
    @test error isa LMK.LocalMathValidationError
    @test error.contract == :runtime_stage_validation
    @test error.actual.failure_class == :invalid_route_key
    @test error.actual.context_index == 1
    @test error.actual.source_item == 1
    @test error.actual.canonical_position == 1
    @test error.actual.witness == 4
    @test invalid_storage == Int32[41, 42]
end
