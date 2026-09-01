using Test
import KernelAbstractions
import LocalMath
const LMCE = LocalMath

struct CollectExecutionNode end
struct CollectExecutionEvaluator end
@inline (::CollectExecutionEvaluator)(item::Int32, reads, parameters) = (
    records = (
        LMCE.CollectedValue(item),
        LMCE.CollectedValue(item + Int32(10), isodd(item)),
    ),
)

struct CollectExecutionGroupKey end
@inline (::CollectExecutionGroupKey)(value::Int32) = Int32(1)
struct CollectExecutionReverseKey end
@inline (::CollectExecutionReverseKey)(value::Int32) = -value
struct CollectExecutionMultiEvaluator end
@inline (::CollectExecutionMultiEvaluator)(item::Int32, reads, parameters) = (
    first = LMCE.CollectedValue(item),
    second = LMCE.CollectedValue(Int32(100) + item),
)
struct CollectParameterizedEvaluator end
@inline (::CollectParameterizedEvaluator)(item::Int32, reads, parameters) = (
    records = LMCE.CollectedValue(item * getfield(parameters, 1)),
)

function _collect_execution_storage(capacity; groups = nothing, positions = nothing)
    LMCE.CompactedStorage(
        LMCE._CONSTRUCTION_TOKEN, fill(Int32(-99), capacity), Int32[-77],
        groups, fill(Int32(-66), capacity), fill(Int32(-55), capacity), positions,
    )
end

function _collect_execution_multi_stage(source, first, second, first_law, second_law)
    first_publication = LMCE.Publication((LMCE.CollectionPublication(
        first, LMCE.PublicationValue(:first)),), first_law)
    second_publication = LMCE.Publication((LMCE.CollectionPublication(
        second, LMCE.PublicationValue(:second)),), second_law)
    LMCE.Stage(source, NamedTuple(), (first_publication, second_publication),
        LMCE.Evaluator(CollectExecutionMultiEvaluator()), LMCE.Control(),
        LMCE.SourceOrigin(:collect_stage_execution_test, 2))
end

function _collect_workspace_for_test(backend, spec)
    authority = LMCE._WorkspaceAuthority(spec.leaves, spec.template)
    tree = LMCE._materialize_workspace(
        authority.template, authority, LMCE._WorkspaceAllocator(backend))
    return LMCE._collect_stage_workspace_from_tree(tree, spec)
end

function _prepare_collect_execution(stage, collection, storage; backend,
        lease_capacity::Int = 1)
    bound = LMCE._bind_law(LMCE.LocalLaw(stage),
        LMCE._StructuralBinding((), (), (
            LMCE._collection_storage_binding(collection, storage),
        )))
    admission = _test_stage_admission(bound; backend)
    raw_spec = LMCE._collect_stage_workspace_spec(admission.stage;
        path = (:stage, 1), name_prefix = :collect_execution)
    authority = LMCE._prepared_workspace_authority(
        LMCE._WorkspaceAuthority(raw_spec.leaves, raw_spec.template), lease_capacity)
    spec = (; raw_spec..., leaves = authority.leaves)
    workspace = _collect_workspace_for_test(backend, spec)
    return LMCE._prepare_collect_stage(admission, workspace)
end

function _collect_execution_stage(source, collection, law)
    publication = LMCE.Publication((LMCE.CollectionPublication(
        collection, LMCE.PublicationValue(:records)),), law)
    LMCE.Stage(source, NamedTuple(), (publication,),
        LMCE.Evaluator(CollectExecutionEvaluator()), LMCE.Control(),
        LMCE.SourceOrigin(:collect_stage_execution_test, 1))
end

@testset "prepared Collect Stage publishes only after validation" begin
    backend = KernelAbstractions.CPU()
    source = LMCE.Space(CollectExecutionNode, 3)
    collection = LMCE.Collection(Int32, 5)
    storage = _collect_execution_storage(5; positions = fill(Int32(-44), 6))
    stage = _collect_execution_stage(source, collection,
        LMCE.Collect(Int32; maximum = 2,
            projection = LMCE._PersistentSourcePosition()))
    prepared = _prepare_collect_execution(stage, collection, storage; backend)
    program_validation = LMCE._ProgramValidationTarget(
        zeros(UInt32, LMCE._VALIDATION_STATUS_FIELDS, 1), Int32(1))
    LMCE._execute_collect_stage!(prepared, (), Int32(1), (),
        LMCE._NoStageRelationGuard(), program_validation)
    KernelAbstractions.synchronize(backend)
    @test storage.count == Int32[5]
    @test storage.records == Int32[1, 11, 2, 3, 13]
    @test storage.source_item == Int32[1, 1, 2, 3, 3]
    @test storage.source_lane == Int32[1, 2, 1, 1, 2]
    @test storage.source_position == Int32[1, 2, 3, 0, 4, 5]
    @test only(Array(prepared.execution.gate))
    @test only(Array(prepared.execution.status)) == LMCE._COLLECT_STATUS_SUCCESS

    overflow_collection = LMCE.Collection(Int32, 4)
    overflow_stage = _collect_execution_stage(source, overflow_collection,
        LMCE.Collect(Int32; maximum = 2,
            projection = LMCE._PersistentSourcePosition()))
    overflow = _collect_execution_storage(4; positions = fill(Int32(-44), 6))
    overflowing = _prepare_collect_execution(
        overflow_stage, overflow_collection, overflow; backend)
    overflow_validation = LMCE._ProgramValidationTarget(
        zeros(UInt32, LMCE._VALIDATION_STATUS_FIELDS, 1), Int32(1))
    LMCE._execute_collect_stage!(overflowing, (), Int32(1), (),
        LMCE._NoStageRelationGuard(), overflow_validation)
    KernelAbstractions.synchronize(backend)
    @test overflow.count == Int32[-77]
    @test overflow.records == fill(Int32(-99), 4)
    @test overflow.source_item == fill(Int32(-66), 4)
    @test overflow.source_lane == fill(Int32(-55), 4)
    @test overflow.source_position == fill(Int32(-44), 6)
    @test !only(Array(overflowing.execution.gate))
    @test Array(overflowing.validation)[:, 1] == UInt32[
        LMCE._COMPACTED_CAPACITY, 1, 5, 4, 0, 0]

    leased_storage = _collect_execution_storage(5; positions = fill(Int32(-44), 6))
    leased = _prepare_collect_execution(stage, collection, leased_storage;
        backend, lease_capacity = 2)
    leased_validation = LMCE._ProgramValidationTarget(
        zeros(UInt32, LMCE._VALIDATION_STATUS_FIELDS, 2), Int32(1))
    LMCE._execute_collect_stage!(leased, (), Int32(2), (),
        LMCE._NoStageRelationGuard(), leased_validation)
    KernelAbstractions.synchronize(backend)
    @test leased_storage.count == Int32[5]
    @test leased.validation[LMCE._VALIDATION_FAILURE_CLASS, 2] == 0
    records_before = copy(leased_storage.records)
    count_before = copy(leased_storage.count)
    predecessor = zeros(UInt32, LMCE._VALIDATION_STATUS_FIELDS, 2)
    predecessor[LMCE._VALIDATION_FAILURE_CLASS, 2] = UInt32(1)
    LMCE._execute_collect_stage!(leased, (), Int32(2), (predecessor,),
        LMCE._NoStageRelationGuard(), leased_validation)
    KernelAbstractions.synchronize(backend)
    @test leased_storage.records == records_before
    @test leased_storage.count == count_before
    @test !only(Array(leased.execution.gate))
end

@testset "prepared Collect Stage canonically groups multiport output" begin
    backend = KernelAbstractions.CPU()
    source = LMCE.Space(CollectExecutionNode, 3)
    first = LMCE.Collection(Int32, 3)
    second = LMCE.Collection(Int32, 3)
    first_law = LMCE.Collect(Int32;
        groups = LMCE.group_by(CollectExecutionGroupKey(); count = 1),
        order = LMCE.canonical_by(CollectExecutionReverseKey(),
            CollectExecutionReverseKey()))
    second_law = LMCE.Collect(Int32)
    stage = _collect_execution_multi_stage(
        source, first, second, first_law, second_law)
    first_storage = LMCE.CompactedStorage(
        LMCE._CONSTRUCTION_TOKEN, fill(Int32(0), 3), Int32[0],
        fill(Int32(0), 2), fill(Int32(0), 3), fill(Int32(0), 3), nothing)
    second_storage = _collect_execution_storage(3)
    bound = LMCE._bind_law(LMCE.LocalLaw(stage),
        LMCE._StructuralBinding((), (), (
            LMCE._collection_storage_binding(first, first_storage),
            LMCE._collection_storage_binding(second, second_storage),
        )))
    admission = _test_stage_admission(bound; backend)
    spec = LMCE._collect_stage_workspace_spec(admission.stage;
        path = (:stage, 2), name_prefix = :collect_multi)
    prepared = LMCE._prepare_collect_stage(
        admission, _collect_workspace_for_test(backend, spec))
    first_order = getfield(prepared.execution.plans, 1).order
    @test first_order isa LMCE._PreparedCanonicalBy
    @test LMCE._prepared_order_types(first_order) == (Int32, Int32)
    program_validation = LMCE._ProgramValidationTarget(
        zeros(UInt32, LMCE._VALIDATION_STATUS_FIELDS, 1), Int32(1))
    LMCE._execute_collect_stage!(prepared, (), Int32(1), (),
        LMCE._NoStageRelationGuard(), program_validation)
    KernelAbstractions.synchronize(backend)
    @test first_storage.count == Int32[3]
    @test first_storage.records == Int32[3, 2, 1]
    @test first_storage.segment_starts == Int32[1, 4]
    @test second_storage.records == Int32[101, 102, 103]
    @test only(Array(prepared.execution.gate))
end

@testset "Collect uses the sole public Stage lifecycle" begin
    backend = KernelAbstractions.CPU()
    source = LMCE.Space(CollectExecutionNode, 3)
    collection = LMCE.Collection(Int32, 5)
    storage = _collect_execution_storage(5; positions = fill(Int32(-44), 6))
    stage = _collect_execution_stage(source, collection,
        LMCE.Collect(Int32; maximum = 2,
            projection = LMCE._PersistentSourcePosition()))
    bound = LMCE._bind_law(LMCE.LocalLaw(stage),
        LMCE._StructuralBinding((), (), (
            LMCE._collection_storage_binding(collection, storage),
        )))
    prepared = LMCE.prepare(LMCE.plan(bound; backend))
    wait(LMCE.execute!(prepared))
    @test storage.records == Int32[1, 11, 2, 3, 13]
    @test storage.source_position == Int32[1, 2, 3, 0, 4, 5]
    facts = LMCE.inspect(prepared)
    @test facts.stages[1].planning.executor === :collect
    @test facts.planning.stage_phases ==
        LMCE.inspect(prepared.plan).planning.stage_phases
    @test facts.planning.base_provider_launch_count ==
        facts.planning.stage_local_launch_count + 1
    @test :collect_publish in
        map(phase -> phase.kind, facts.stages[1].planning.phases)
end

@testset "Collect consumes per-submission positional parameters" begin
    backend = KernelAbstractions.CPU()
    source = LMCE.Space(CollectExecutionNode, 3)
    collection = LMCE.Collection(Int32, 3)
    factor = LMCE.Parameter(:factor, Int32)
    law = LMCE.Collect(Int32)
    publication = LMCE.Publication((LMCE.CollectionPublication(
        collection, LMCE.PublicationValue(:records)),), law)
    stage = LMCE.Stage(source, NamedTuple(), (publication,),
        LMCE.Evaluator(CollectParameterizedEvaluator(), (factor,)),
        LMCE.Control(), LMCE.SourceOrigin(:collect_parameters, 1))
    storage = _collect_execution_storage(3)
    work = LMCE.LocalLaw(stage; parameters = LMCE.ParameterSchema(factor))
    bound = LMCE._bind_law(work, LMCE._StructuralBinding((), (), (
        LMCE._collection_storage_binding(collection, storage),
    )))
    prepared = LMCE.prepare(LMCE.plan(bound; backend))
    wait(LMCE.execute!(prepared; parameters = (factor = Int32(7),)))
    @test storage.records == Int32[7, 14, 21]
    @test prepared.runtime.launches[1].stage.execution.stage.parameter_slots ==
        (LMCE._ParameterSlot{1}(),)
end
