using Test
import KernelAbstractions
import LocalMath
const LMCA = LocalMath

struct CollectionAccessItem end
struct CollectionAccessRecord
    group::Int32
    value::Int32
end
struct CollectionAccessGroup end
@inline (::CollectionAccessGroup)(record::CollectionAccessRecord) = record.group

struct CollectionAccessProducer end
@inline (::CollectionAccessProducer)(item::Int32, reads, parameters) = (
    records = LMCA.CollectedValue(CollectionAccessRecord(item, item * Int32(10)),
        item != Int32(3)),
)

struct CollectionAccessConsumer end
@inline function (::CollectionAccessConsumer)(item::Int32, reads, parameters)
    records = getfield(reads, 1)
    total = Int32(0)
    for record in records
        total += record.value
    end
    position = getfield(reads, 2)
    return (total = LMCA.UniqueValue(total),
        position = LMCA.UniqueValue(position))
end

struct CollectionCountConsumer end
@inline (::CollectionCountConsumer)(item::Int32, reads, parameters) =
    (live = LMCA.UniqueValue(item),)
struct CollectionCapabilityBypass end
@inline function (::CollectionCapabilityBypass)(item::Int32, reads, parameters)
    records = getfield(getfield(reads, 1), :records)
    return (total = LMCA.UniqueValue(Int32(length(records))),
        position = LMCA.UniqueValue(Int32(0)))
end
struct CollectionOverflowGroup end
@inline (::CollectionOverflowGroup)(value::Int32) = Int32(1)
struct CollectionOverflowProducer end
@inline (::CollectionOverflowProducer)(item::Int32, reads, parameters) =
    (records = LMCA.CollectedValue(item),)
struct CollectionOverflowConsumer end
@inline (::CollectionOverflowConsumer)(item::Int32, reads, parameters) =
    (live = LMCA.UniqueValue(Int32(length(getfield(reads, 1)))),)

function _collection_access_storage(capacity::Int, groups::Int, positions::Int)
    return LMCA.CompactedStorage(LMCA._CONSTRUCTION_TOKEN,
        LMCA._allocate_compacted_records(
            KernelAbstractions.CPU(), CollectionAccessRecord, capacity),
        Int32[-1], fill(Int32(-1), groups + 1), fill(Int32(-1), capacity),
        fill(Int32(-1), capacity), fill(Int32(-1), positions))
end

@testset "bounded Collection occupancy fails before consumer publication" begin
    producer_source = LMCA.Space(CollectionAccessItem, 3)
    consumer_source = LMCA.Space(CollectionAccessItem, 1)
    collection = LMCA.Collection(Int32, 3)
    output = LMCA.Field(consumer_source, Int32)
    identity = LMCA.IdentityRelation(consumer_source)
    collect = LMCA.Publication((LMCA.CollectionPublication(collection,
        LMCA.PublicationValue(:records)),), LMCA.Collect(Int32;
            groups = LMCA._GroupBy(CollectionOverflowGroup(), Int32(1))))
    producer = LMCA.Stage(producer_source, NamedTuple(), (collect,),
        LMCA.Evaluator(CollectionOverflowProducer()), LMCA.Control(),
        LMCA.SourceOrigin(:collection_access, 5))
    publication = LMCA.Publication((LMCA.FieldPublication(output,
        identity, LMCA.PublicationValue(:live)),), LMCA.Unique(Int32))
    consumer = LMCA.Stage(consumer_source,
        (records = LMCA.CollectionAccess(collection, LMCA.BoundedGroup(2)),),
        (publication,), LMCA.Evaluator(CollectionOverflowConsumer()),
        LMCA.Control(), LMCA.SourceOrigin(:collection_access, 6))
    storage = LMCA.CompactedStorage(LMCA._CONSTRUCTION_TOKEN,
        zeros(Int32, 3), zeros(Int32, 1), zeros(Int32, 2), zeros(Int32, 3),
        zeros(Int32, 3), nothing)
    output_storage = Int32[-7]
    work = LMCA.sequence(LMCA.LocalLaw(producer), LMCA.LocalLaw(consumer))
    bound = LMCA.bind(work, output => output_storage, collection => storage)
    prepared = LMCA.prepare(LMCA.plan(bound; backend = KernelAbstractions.CPU()))
    error = try
        wait(LMCA.execute!(prepared))
        nothing
    catch caught
        caught
    end
    @test error isa LMCA.LocalMathValidationError
    @test output_storage == Int32[-7]
end

@testset "typed Collection Stage access stays on the Stage execution path" begin
    source = LMCA.Space(CollectionAccessItem, 3)
    collection = LMCA.Collection(CollectionAccessRecord, 3)
    identity = LMCA.IdentityRelation(source)
    total = LMCA.Field(source, Int32)
    position = LMCA.Field(source, Int32)
    live = LMCA.Field(source, Int32)

    collect = LMCA.Publication((LMCA.CollectionPublication(collection,
        LMCA.PublicationValue(:records)),),
        LMCA.Collect(CollectionAccessRecord;
            groups = LMCA._GroupBy(CollectionAccessGroup(), Int32(3)),
            projection = LMCA._PersistentSourcePosition()))
    producer = LMCA.Stage(source, NamedTuple(), (collect,),
        LMCA.Evaluator(CollectionAccessProducer()), LMCA.Control(),
        LMCA.SourceOrigin(:collection_access, 1))

    total_pub = LMCA.Publication((LMCA.FieldPublication(total, identity,
        LMCA.PublicationValue(:total)),), LMCA.Unique(Int32))
    position_pub = LMCA.Publication((LMCA.FieldPublication(position,
        identity, LMCA.PublicationValue(:position)),),
        LMCA.Unique(Int32))
    consumer = LMCA.Stage(source, (
            group = LMCA.CollectionAccess(collection, LMCA.BoundedGroup(1)),
            position = LMCA.SourcePositionAccess(collection),
        ), (total_pub, position_pub),
        LMCA.Evaluator(CollectionAccessConsumer()), LMCA.Control(),
        LMCA.SourceOrigin(:collection_access, 2))

    live_pub = LMCA.Publication((LMCA.FieldPublication(live, identity,
        LMCA.PublicationValue(:live)),),
        LMCA.Unique(Int32; coverage = LMCA.PartialCoverage(),
            onempty = LMCA.PreserveEmpty()))
    count_consumer = LMCA.Stage(source, NamedTuple(), (live_pub,),
        LMCA.Evaluator(CollectionCountConsumer()),
        LMCA.Control(prefix = LMCA.CollectionCount(collection)),
        LMCA.SourceOrigin(:collection_access, 3))

    storage = _collection_access_storage(3, 3, 3)
    work = LMCA.sequence(LMCA.LocalLaw(producer),
        LMCA.LocalLaw(consumer), LMCA.LocalLaw(count_consumer))
    bound = LMCA.bind(work,
        total => fill(Int32(-1), 3),
        position => fill(Int32(-1), 3), live => fill(Int32(-1), 3),
        collection => storage)
    backend = KernelAbstractions.CPU()
    prepared = LMCA.prepare(LMCA.plan(bound; backend))
    signature = LMCA._logical_lowering_entries(
        prepared.plan.lowering)[2].admission.signature
    bypass = LMCA._closed_callable_effect_analysis(
        CollectionCapabilityBypass(), signature,
        method_signature -> length(method_signature) == 4;
        source_policy = LMCA._stage_evaluator_source_safe,
        typed_policy = LMCA._stage_access_typed_safe)
    @test !bypass.qualified
    wait(LMCA.execute!(prepared))

    @test storage.count == Int32[2]
    @test storage.records[1:2] ==
        [CollectionAccessRecord(1, 10), CollectionAccessRecord(2, 20)]
    @test bound.binding.fields[1].storage == Int32[10, 20, 0]
    @test bound.binding.fields[2].storage == Int32[1, 2, 0]
    @test bound.binding.fields[3].storage == Int32[1, 2, -1]
    @test LMCA.lowering_identity(prepared.plan) ==
        :stage_local_erased_kernelabstractions_v1
end

@testset "Collection consumers require an exact preceding Collect" begin
    source = LMCA.Space(CollectionAccessItem, 1)
    collection = LMCA.Collection(Int32, 1)
    output = LMCA.Field(source, Int32)
    identity = LMCA.IdentityRelation(source)
    publication = LMCA.Publication((LMCA.FieldPublication(output,
        identity, LMCA.PublicationValue(:live)),), LMCA.Unique(Int32))
    stage = LMCA.Stage(source,
        (records = LMCA.CollectionAccess(collection, LMCA.BoundedGroup(1)),),
        (publication,), LMCA.Evaluator(CollectionCountConsumer()),
        LMCA.Control(), LMCA.SourceOrigin(:collection_access, 4))
    storage = LMCA.CompactedStorage(LMCA._CONSTRUCTION_TOKEN,
        zeros(Int32, 1), zeros(Int32, 1), zeros(Int32, 2), zeros(Int32, 1),
        zeros(Int32, 1), nothing)
    bound = LMCA.bind(LMCA.LocalLaw(stage),
        output => zeros(Int32, 1), collection => storage)
    error = try
        LMCA.plan(bound; backend = KernelAbstractions.CPU())
        nothing
    catch caught
        caught
    end
    @test error isa LMCA.LocalMathValidationError
    @test error.contract == :collection_producer
end
