using Test
import LocalMath
const LMSB = LocalMath

struct StageBarrierNode end
struct StageBarrierCandidateEvaluator end
@inline (::StageBarrierCandidateEvaluator)(item::Int32, reads, parameters) =
    (candidate = LMSB.UniqueValue(item),)
struct StageBarrierCollectEvaluator end
@inline (::StageBarrierCollectEvaluator)(item::Int32, reads, parameters) =
    (record = LMSB.CollectedValue(item),)
struct StageBarrierFoldEvaluator end
@inline (::StageBarrierFoldEvaluator)(item::Int32, reads, parameters) =
    (event = LMSB.FoldValue(item),)
struct StageBarrierInvalidTransition end
@inline (::StageBarrierInvalidTransition)(state, value, item, reads) =
    LMSB.FoldStep((state = LMSB.BoundedWrites(
        (Int32(2),), (value,), Int32(1)),))
struct StageBarrierSuccessor end
@inline (::StageBarrierSuccessor)(item::Int32, reads, parameters) =
    (successor = LMSB.UniqueValue(item + Int32(100)),)

function _stage_barrier_successor(source, output, identity, line)
    publication = LMSB.Publication((LMSB.FieldPublication(
        output, identity, LMSB.PublicationValue(:successor)),),
        LMSB.Unique(Int32))
    return LMSB.Stage(source, NamedTuple(), (publication,),
        LMSB.Evaluator(StageBarrierSuccessor()), LMSB.Control(),
        LMSB.SourceOrigin(:stage_failure_barrier, line))
end

function _stage_barrier_prepare(law, binding, backend)
    bound = LMSB._bind_law(law, binding)
    return LMSB.prepare(LMSB.plan(bound; backend))
end

@testset "Candidate failure suppresses later direct publication" begin
    source = LMSB.Space(StageBarrierNode, 2)
    destination_space = LMSB.Space(StageBarrierNode, 1)
    conflicted = LMSB.Field(destination_space, Int32)
    successor = LMSB.Field(source, Int32)
    collision = LMSB.FixedRelation(source => destination_space; degree = 1)
    identity = LMSB.IdentityRelation(source)
    conflict = LMSB.Publication((LMSB.FieldPublication(
        conflicted, collision, LMSB.PublicationValue(:candidate)),),
        LMSB.Unique(Int32))
    failing = LMSB.Stage(source, NamedTuple(), (conflict,),
        LMSB.Evaluator(StageBarrierCandidateEvaluator()), LMSB.Control(),
        LMSB.SourceOrigin(:stage_failure_barrier, 1))
    law = LMSB.sequence(LMSB.LocalLaw(failing), LMSB.LocalLaw(
        _stage_barrier_successor(source, successor, identity, 2)))
    conflicted_storage = Int32[-7]
    successor_storage = fill(Int32(-9), 2)
    binding = LMSB._StructuralBinding((
        LMSB._field_storage_binding(conflicted, conflicted_storage),
        LMSB._field_storage_binding(successor, successor_storage),
    ), (
        LMSB._relation_storage_binding(collision, (
            endpoints = reshape(Int32[1, 1], 1, 2),
            counts = Int32[1, 1],
        )),
        LMSB._relation_storage_binding(identity),
    ))
    backend = LMSB.KernelAbstractions.get_backend(successor_storage)
    prepared = _stage_barrier_prepare(law, binding, backend)
    @test prepared.runtime.launches[2].stage isa
        LMSB._DirectPointwiseSegmentPreparation
    @test_throws LMSB.LocalMathValidationError wait(LMSB.execute!(prepared))
    @test conflicted_storage == Int32[-7]
    @test successor_storage == fill(Int32(-9), 2)
end

@testset "Collect failure suppresses later direct publication" begin
    source = LMSB.Space(StageBarrierNode, 2)
    collection = LMSB.Collection(Int32, 1)
    successor = LMSB.Field(source, Int32)
    identity = LMSB.IdentityRelation(source)
    collect = LMSB.Publication((LMSB.CollectionPublication(
        collection, LMSB.PublicationValue(:record)),),
        LMSB.Collect(Int32; maximum = 1))
    failing = LMSB.Stage(source, NamedTuple(), (collect,),
        LMSB.Evaluator(StageBarrierCollectEvaluator()), LMSB.Control(),
        LMSB.SourceOrigin(:stage_failure_barrier, 3))
    law = LMSB.sequence(LMSB.LocalLaw(failing), LMSB.LocalLaw(
        _stage_barrier_successor(source, successor, identity, 4)))
    storage = LMSB.CompactedStorage(LMSB._CONSTRUCTION_TOKEN,
        Int32[-7], Int32[-1], nothing, Int32[-1], Int32[-1], nothing)
    successor_storage = fill(Int32(-9), 2)
    binding = LMSB._StructuralBinding((
        LMSB._field_storage_binding(successor, successor_storage),
    ), (LMSB._relation_storage_binding(identity),), (
        LMSB._collection_storage_binding(collection, storage),
    ))
    backend = LMSB.KernelAbstractions.get_backend(successor_storage)
    prepared = _stage_barrier_prepare(law, binding, backend)
    @test_throws LMSB.LocalMathValidationError wait(LMSB.execute!(prepared))
    @test storage.count == Int32[-1]
    @test storage.records == Int32[-7]
    @test successor_storage == fill(Int32(-9), 2)
end

@testset "OrderedFold failure suppresses later direct publication" begin
    source = LMSB.Space(StageBarrierNode, 2)
    state_space = LMSB.Space(StageBarrierNode, 1)
    initial = LMSB.Field(state_space, Int32)
    state = LMSB.Field(state_space, Int32)
    successor = LMSB.Field(source, Int32)
    identity = LMSB.IdentityRelation(source)
    initialized = LMSB.InitializedState(;
        state = LMSB.FoldComponent(state; from = initial))
    fold = LMSB.OrderedFold(Int32, initialized,
        StageBarrierInvalidTransition(); order = LMSB._SourceOrder())
    publication = LMSB.Publication((LMSB.FoldPublication(
        LMSB.PublicationValue(:event)),), fold)
    failing = LMSB.Stage(source, NamedTuple(), (publication,),
        LMSB.Evaluator(StageBarrierFoldEvaluator()), LMSB.Control(),
        LMSB.SourceOrigin(:stage_failure_barrier, 5))
    law = LMSB.sequence(LMSB.LocalLaw(failing), LMSB.LocalLaw(
        _stage_barrier_successor(source, successor, identity, 6)))
    initial_storage = Int32[4]
    state_storage = Int32[8]
    successor_storage = fill(Int32(-9), 2)
    binding = LMSB._StructuralBinding((
        LMSB._field_storage_binding(initial, initial_storage),
        LMSB._field_storage_binding(state, state_storage),
        LMSB._field_storage_binding(successor, successor_storage),
    ), (LMSB._relation_storage_binding(identity),))
    backend = LMSB.KernelAbstractions.get_backend(successor_storage)
    prepared = _stage_barrier_prepare(law, binding, backend)
    @test_throws LMSB.LocalMathValidationError wait(LMSB.execute!(prepared))
    @test state_storage == Int32[8]
    @test successor_storage == fill(Int32(-9), 2)
end
