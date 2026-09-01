using Test
using Metal
using LocalMath
import KernelAbstractions

const LMSP = LocalMath

Metal.functional() || error("Metal is not functional")
Metal.allowscalar(false)

struct StageProgramStageProgramNode end
struct StageProgramParameterizedContribution end
@inline (::StageProgramParameterizedContribution)(item::Int32, reads, parameters) =
    (value = LMSP.Contribution(item * getfield(parameters, 1)),)

struct StageProgramParameterizedCollect end
@inline (::StageProgramParameterizedCollect)(item::Int32, reads, parameters) =
    (record = LMSP.CollectedValue(item * getfield(parameters, 1)),)

struct StageProgramParameterizedFold end
@inline (::StageProgramParameterizedFold)(item::Int32, reads, parameters) =
    (event = LMSP.FoldValue(item * getfield(parameters, 1)),)
struct StageProgramFoldValue end
@inline (::StageProgramFoldValue)(item::Int32, reads, parameters) =
    (event = LMSP.FoldValue(item),)

struct StageProgramLastWrite end
@inline (::StageProgramLastWrite)(state, value, item, reads) = LMSP.FoldStep((
    accumulator = LMSP.BoundedWrites(
        (Int32(1),), (value,), Int32(1)),
))

struct StageProgramUniqueValue end
@inline (::StageProgramUniqueValue)(item::Int32, reads, parameters) =
    (value = LMSP.UniqueValue(item),)
struct StageProgramSuccessorValue end
@inline (::StageProgramSuccessorValue)(item::Int32, reads, parameters) =
    (value = LMSP.UniqueValue(Int32(100) + item),)
struct StageProgramResolveValue end
@inline function (::StageProgramResolveValue)(item::Int32, reads, parameters)
    local_item = item <= Int32(3) ? item : item - Int32(3)
    rank = local_item == Int32(3) ? Int32(0) : local_item
    return (value = LMSP.ResolutionValue(rank, item),)
end
struct StageProgramPointwiseSeed end
@inline (::StageProgramPointwiseSeed)(item::Int32, reads, parameters) =
    (value = LMSP.UniqueValue(item),)
struct StageProgramPointwiseStep end
@inline (::StageProgramPointwiseStep)(item::Int32, reads, parameters) =
    (value = LMSP.UniqueValue(
        something(@inbounds(reads[1][1].value)) + Int32(1)),)
struct StageProgramTypedOperation{Identity} end
@inline (::StageProgramTypedOperation{:source_site})(item::Int32) =
    item + Int32(10)
struct StageProgramMultiPointwise{O}
    operation::O
end
@inline function (evaluator::StageProgramMultiPointwise)(
        item::Int32, reads, parameters)
    value = evaluator.operation(item)
    return (
        key = LMSP.UniqueValue(item == Int32(2) ? Int32(0) : item),
        integer = LMSP.UniqueValue(value),
        floating = LMSP.UniqueValue(Float32(value) + 0.5f0),
    )
end
struct StageProgramOptionalGather end
@inline function (::StageProgramOptionalGather)(item::Int32, reads, parameters)
    sample = reads[1][1]
    return (value = LMSP.UniqueValue(
        something(sample.value, Int32(-1))),)
end
struct StageProgramDoubleCollect end
@inline (::StageProgramDoubleCollect)(item::Int32, reads, parameters) =
    (record = (LMSP.CollectedValue(item), LMSP.CollectedValue(item + Int32(10))),)
struct StageProgramConstantOrder end
@inline (::StageProgramConstantOrder)(value::Int32) = Int32(0)
struct StageProgramInvalidWrite end
@inline (::StageProgramInvalidWrite)(state, value, item, reads) = LMSP.FoldStep((
    accumulator = LMSP.BoundedWrites((Int32(2),), (value,), Int32(1)),
))

KernelAbstractions.@kernel function stage_program_packed_relation_producer!(
        active, endpoints, offsets, counts, generation, status,
        validated_generation, next_generation::UInt64, next_status::Int32,
    )
    if KernelAbstractions.@index(Global, Linear) == 1
        for item in eachindex(active)
            @inbounds begin
                active[item] = true
                endpoints[item] = Int32(length(active) - item + 1)
            end
        end
        @inbounds begin
            offsets[1] = Int32(1)
            counts[1] = Int32(length(active))
            # Publication of validation metadata is deliberately last.  The
            # immediately submitted consumer must observe this whole prefix
            # through the common KA provider tail without a host wait.
            generation[1] = next_generation
            status[1] = next_status
            validated_generation[1] = next_generation
        end
    end
end

function stage_program_validation_error(event)
    try
        wait(event)
        return nothing
    catch error
        error isa LMSP.LocalMathValidationError || rethrow()
        return error
    end
end

function stage_program_unique_stage(source, output, relation, evaluator, line)
    publication = LMSP.Publication((LMSP.FieldPublication(
        output, relation, LMSP.PublicationValue(:value)),),
        LMSP.Unique(Int32))
    LMSP.Stage(source, NamedTuple(), (publication,),
        LMSP.Evaluator(evaluator), LMSP.Control(),
        LMSP.SourceOrigin(:stage_program_metal_negative, line))
end

function stage_program_parameter(name::Symbol)
    LMSP.Parameter(name, Int32;
        bounds = LMSP._ClosedParameterBounds(Int32(1), Int32(8)))
end

function stage_program_stage_program_reduce(backend)
    n, destinations = 513, 19
    source = LMSP.Space(StageProgramStageProgramNode, n)
    target = LMSP.Space(StageProgramStageProgramNode, destinations)
    output = LMSP.Field(target, Int32)
    relation = LMSP.PackedRelation(source => target;
        degree_bound = 1, capacity = n)
    factor = stage_program_parameter(:factor)
    law = LMSP.Reduce(Int32, +;
        seed = LMSP.IdentitySeed(Int32(0)))
    publication = LMSP.Publication((LMSP.FieldPublication(
        output, relation, LMSP.PublicationValue(:value)),), law)
    stage = LMSP.Stage(source, NamedTuple(), (publication,),
        LMSP.Evaluator(StageProgramParameterizedContribution(), (factor,)),
        LMSP.Control(), LMSP.SourceOrigin(:stage_program_metal_stage_program, 1))
    work = LMSP.LocalLaw(stage; parameters = LMSP.ParameterSchema(factor))

    host_endpoints = reshape(Int32[mod1(item, destinations) for item in 1:n], 1, n)
    storage = Metal.MtlArray(fill(Int32(-1), destinations))
    generation = Metal.MtlArray(UInt64[7])
    validated_generation = Metal.MtlArray(UInt64[7])
    relation_status = Metal.MtlArray(Int32[0])
    binding = LMSP._StructuralBinding(
        (LMSP._field_storage_binding(output, storage),),
        (LMSP._relation_storage_binding(relation, (
            active = Metal.MtlArray(fill(true, n)),
            endpoints = Metal.MtlArray(host_endpoints),
            offsets = Metal.MtlArray(Int32[1]),
            counts = Metal.MtlArray(Int32[n]),
        ); generation = LMSP._RelationContentGenerationRef(generation, 1),
           status = LMSP._RelationStatusRef(
               relation_status, validated_generation, 1)),))
    bound = LMSP._bind_law(work, binding)
    prepared = LMSP.prepare(LMSP.plan(bound; backend))
    wait(LMSP.execute!(prepared; parameters = (factor = Int32(3),)))

    expected = Int32[sum(Int32(item * 3) for item in 1:n
        if mod1(item, destinations) == destination)
        for destination in 1:destinations]
    return Array(storage), expected, prepared, generation,
        validated_generation, relation_status
end

function stage_program_stage_program_collect(backend)
    n = 513
    source = LMSP.Space(StageProgramStageProgramNode, n)
    collection = LMSP.Collection(Int32, n)
    factor = stage_program_parameter(:factor)
    law = LMSP.Collect(Int32)
    publication = LMSP.Publication((LMSP.CollectionPublication(
        collection, LMSP.PublicationValue(:record)),), law)
    stage = LMSP.Stage(source, NamedTuple(), (publication,),
        LMSP.Evaluator(StageProgramParameterizedCollect(), (factor,)),
        LMSP.Control(), LMSP.SourceOrigin(:stage_program_metal_stage_program, 2))
    work = LMSP.LocalLaw(stage; parameters = LMSP.ParameterSchema(factor))
    storage = LMSP.CompactedStorage(LMSP._CONSTRUCTION_TOKEN,
        Metal.MtlArray(fill(Int32(-1), n)), Metal.MtlArray(Int32[0]), nothing,
        Metal.MtlArray(fill(Int32(0), n)), Metal.MtlArray(fill(Int32(0), n)),
        nothing)
    bound = LMSP._bind_law(work, LMSP._StructuralBinding((), (), (
        LMSP._collection_storage_binding(collection, storage),)))
    prepared = LMSP.prepare(LMSP.plan(bound; backend))
    wait(LMSP.execute!(prepared; parameters = (factor = Int32(2),)))
    return Array(storage.records), Array(storage.count), prepared
end

function stage_program_stage_program_collect_projection(backend)
    n = 32
    source = LMSP.Space(StageProgramStageProgramNode, n)
    collection = LMSP.Collection(Int32, n)
    factor = stage_program_parameter(:factor)
    law = LMSP.Collect(Int32;
        projection = LMSP._PersistentSourcePosition())
    publication = LMSP.Publication((LMSP.CollectionPublication(
        collection, LMSP.PublicationValue(:record)),), law)
    stage = LMSP.Stage(source, NamedTuple(), (publication,),
        LMSP.Evaluator(StageProgramParameterizedCollect(), (factor,)),
        LMSP.Control(), LMSP.SourceOrigin(:stage_program_metal_stage_program, 3))
    work = LMSP.LocalLaw(stage; parameters = LMSP.ParameterSchema(factor))
    storage = LMSP.CompactedStorage(LMSP._CONSTRUCTION_TOKEN,
        Metal.MtlArray(fill(Int32(-1), n)), Metal.MtlArray(Int32[0]), nothing,
        Metal.MtlArray(fill(Int32(0), n)), Metal.MtlArray(fill(Int32(0), n)),
        Metal.MtlArray(fill(Int32(-1), n)))
    bound = LMSP._bind_law(work, LMSP._StructuralBinding((), (), (
        LMSP._collection_storage_binding(collection, storage),)))
    prepared = LMSP.prepare(LMSP.plan(bound; backend))
    wait(LMSP.execute!(prepared; parameters = (factor = Int32(2),)))
    return Array(storage.records), Array(storage.count),
        Array(storage.source_position)
end

function stage_program_stage_program_ordered_fold(backend)
    n = 513
    source = LMSP.Space(StageProgramStageProgramNode, n)
    state_space = LMSP.Space(StageProgramStageProgramNode, 1)
    initial = LMSP.Field(state_space, Int32)
    accumulator = LMSP.Field(state_space, Int32)
    factor = stage_program_parameter(:factor)
    state = LMSP.InitializedState(; accumulator = LMSP.FoldComponent(
        accumulator; from = initial))
    law = LMSP.OrderedFold(Int32, state, StageProgramLastWrite();
        order = LMSP._SourceOrder())
    publication = LMSP.Publication((LMSP.FoldPublication(
        LMSP.PublicationValue(:event)),), law)
    stage = LMSP.Stage(source, NamedTuple(), (publication,),
        LMSP.Evaluator(StageProgramParameterizedFold(), (factor,)),
        LMSP.Control(), LMSP.SourceOrigin(:stage_program_metal_stage_program, 3))
    work = LMSP.LocalLaw(stage; parameters = LMSP.ParameterSchema(factor))
    initial_storage = Metal.MtlArray(Int32[7])
    accumulator_storage = Metal.MtlArray(Int32[-1])
    bound = LMSP._bind_law(work, LMSP._StructuralBinding((
        LMSP._field_storage_binding(initial, initial_storage),
        LMSP._field_storage_binding(accumulator, accumulator_storage),
    ), ()))
    prepared = LMSP.prepare(LMSP.plan(bound; backend))
    wait(LMSP.execute!(prepared; parameters = (factor = Int32(4),)))
    return Array(accumulator_storage), prepared
end

function stage_program_relation_queue_packet(backend)
    n = 4
    source = LMSP.Space(StageProgramStageProgramNode, n)
    first, successor = LMSP.Field(source, Int32), LMSP.Field(source, Int32)
    packed = LMSP.PackedRelation(source => source; degree_bound = 1, capacity = n)
    identity = LMSP.IdentityRelation(source)
    work = LMSP.sequence(
        LMSP.LocalLaw(stage_program_unique_stage(
            source, first, packed, StageProgramUniqueValue(), 10)),
        LMSP.LocalLaw(stage_program_unique_stage(
            source, successor, identity, StageProgramSuccessorValue(), 11)),
    )
    function make_prepared(current::UInt64, validated::UInt64,
            relation_code::Int32; invalid_endpoint::Bool = false)
        first_storage = Metal.MtlArray(fill(Int32(-11), n))
        successor_storage = Metal.MtlArray(fill(Int32(-22), n))
        active = Metal.MtlArray(fill(true, n))
        endpoint_values = Int32.(1:n)
        invalid_endpoint && (endpoint_values[end] = Int32(n + 1))
        endpoints = Metal.MtlArray(reshape(endpoint_values, 1, n))
        offsets, counts = Metal.MtlArray(Int32[1]), Metal.MtlArray(Int32[n])
        generation = Metal.MtlArray(UInt64[current])
        status = Metal.MtlArray(Int32[relation_code])
        validated_generation = Metal.MtlArray(UInt64[validated])
        binding = LMSP._StructuralBinding((
            LMSP._field_storage_binding(first, first_storage),
            LMSP._field_storage_binding(successor, successor_storage),
        ), (
            LMSP._relation_storage_binding(packed,
                (; active, endpoints, offsets, counts);
                generation = LMSP._RelationContentGenerationRef(generation, 1),
                status = LMSP._RelationStatusRef(status, validated_generation, 1)),
            LMSP._relation_storage_binding(identity),
        ))
        prepared = LMSP.prepare(LMSP.plan(
            LMSP._bind_law(work, binding); backend))
        return (; prepared, first_storage, successor_storage, active, endpoints,
            offsets, counts, generation, status, validated_generation)
    end

    stale = make_prepared(UInt64(2), UInt64(1), Int32(0);
        invalid_endpoint = true)
    stale_error = stage_program_validation_error(LMSP.execute!(stale.prepared))
    stale_outputs = (Array(stale.first_storage), Array(stale.successor_storage))

    # Caller-written status cannot self-certify or veto content when the
    # package owns an exact validator. Valid bytes are requalified on device.
    nonzero = make_prepared(UInt64(3), UInt64(3), Int32(9))
    status_error = stage_program_validation_error(LMSP.execute!(nonzero.prepared))
    status_outputs = (Array(nonzero.first_storage), Array(nonzero.successor_storage))

    success = make_prepared(UInt64(3), UInt64(3), Int32(9))
    # No synchronization between this producer and execute!: this is the actual
    # same-provider-tail construction/validation/consumption witness.
    stage_program_packed_relation_producer!(backend)(success.active, success.endpoints,
        success.offsets, success.counts, success.generation, success.status,
        success.validated_generation, UInt64(4), Int32(0); ndrange = 1)
    wait(LMSP.execute!(success.prepared))
    # A second successful submission reuses the released lease on the same
    # preparation and proves that the generation-qualified receipt is renewed.
    stage_program_packed_relation_producer!(backend)(success.active, success.endpoints,
        success.offsets, success.counts, success.generation, success.status,
        success.validated_generation, UInt64(5), Int32(0); ndrange = 1)
    wait(LMSP.execute!(success.prepared))
    return (; stale_error, stale_outputs, status_error, status_outputs,
        success_outputs = (Array(success.first_storage), Array(success.successor_storage)),
        generation = Array(success.generation), status = Array(success.status),
        validated_generation = Array(success.validated_generation),
        submissions = LMSP.submission_capacity(success.prepared).submitted)
end

function stage_program_candidate_conflict(backend)
    source = LMSP.Space(StageProgramStageProgramNode, 2)
    target = LMSP.Space(StageProgramStageProgramNode, 1)
    output = LMSP.Field(target, Int32)
    collision = LMSP.FixedRelation(source => target; degree = 1)
    stage = stage_program_unique_stage(source, output, collision, StageProgramUniqueValue(), 20)
    storage = Metal.MtlArray(Int32[77])
    binding = LMSP._StructuralBinding(
        (LMSP._field_storage_binding(output, storage),),
        (LMSP._relation_storage_binding(collision, (
            endpoints = Metal.MtlArray(reshape(Int32[1, 1], 1, 2)),
            counts = Metal.MtlArray(Int32[1, 1]),
        );
            generation = LMSP._RelationContentGenerationRef(
                Metal.MtlArray(UInt64[1]), 1),
            status = LMSP._RelationStatusRef(
                Metal.MtlArray(Int32[0]), Metal.MtlArray(UInt64[0]), 1)),))
    prepared = LMSP.prepare(LMSP.plan(
        LMSP._bind_law(LMSP.LocalLaw(stage), binding); backend))
    error = stage_program_validation_error(LMSP.execute!(prepared))
    return error, Array(storage)
end

function stage_program_atomic_resolve(backend)
    source = LMSP.Space(StageProgramStageProgramNode, 6)
    target = LMSP.Space(StageProgramStageProgramNode, 2)
    output = LMSP.Field(target, Int32)
    relation = LMSP.FixedRelation(source => target; degree = 1)
    law = LMSP.Resolve(Int32, Int32;
        direction = LMSP.ArgMin(), lower = Int32(0), upper = Int32(2),
        onempty = LMSP.FillEmpty(Int32(-9)))
    publication = LMSP.Publication((LMSP.FieldPublication(
        output, relation, LMSP.PublicationValue(:value)),), law)
    stage = LMSP.Stage(source, NamedTuple(), (publication,),
        LMSP.Evaluator(StageProgramResolveValue()), LMSP.Control(),
        LMSP.SourceOrigin(@__FILE__, @__LINE__;
            label = :metal_atomic_resolve))
    storage = Metal.MtlArray(fill(Int32(70), 2))
    binding = LMSP._StructuralBinding(
        (LMSP._field_storage_binding(output, storage),),
        (LMSP._relation_storage_binding(relation, (
            endpoints = Metal.MtlArray(reshape(
                Int32[1, 1, 1, 2, 2, 2], 1, 6)),
            counts = Metal.MtlArray(fill(Int32(1), 6)),
        )),))
    prepared = LMSP.prepare(LMSP.plan(
        LMSP._bind_law(LMSP.LocalLaw(stage), binding); backend))
    wait(LMSP.execute!(prepared))
    return Array(storage), LMSP.inspect(prepared)
end

function stage_program_collect_overflow(backend)
    source = LMSP.Space(StageProgramStageProgramNode, 2)
    collection = LMSP.Collection(Int32, 3)
    law = LMSP.Collect(Int32; maximum = 2)
    publication = LMSP.Publication((LMSP.CollectionPublication(
        collection, LMSP.PublicationValue(:record)),), law)
    stage = LMSP.Stage(source, NamedTuple(), (publication,),
        LMSP.Evaluator(StageProgramDoubleCollect()), LMSP.Control(),
        LMSP.SourceOrigin(:stage_program_metal_negative, 30))
    storage = LMSP.CompactedStorage(LMSP._CONSTRUCTION_TOKEN,
        Metal.MtlArray(fill(Int32(-31), 3)), Metal.MtlArray(Int32[-32]), nothing,
        Metal.MtlArray(fill(Int32(-33), 3)), Metal.MtlArray(fill(Int32(-34), 3)),
        nothing)
    binding = LMSP._StructuralBinding((), (), (
        LMSP._collection_storage_binding(collection, storage),))
    prepared = LMSP.prepare(LMSP.plan(
        LMSP._bind_law(LMSP.LocalLaw(stage), binding); backend))
    error = stage_program_validation_error(LMSP.execute!(prepared))
    return error, (Array(storage.records), Array(storage.count),
        Array(storage.source_item), Array(storage.source_lane))
end

function stage_program_fold_failure(backend, array, transition, order; line)
    source = LMSP.Space(StageProgramStageProgramNode, 4)
    state_space = LMSP.Space(StageProgramStageProgramNode, 1)
    initial, accumulator = LMSP.Field(state_space, Int32), LMSP.Field(state_space, Int32)
    state = LMSP.InitializedState(; accumulator = LMSP.FoldComponent(
        accumulator; from = initial))
    law = LMSP.OrderedFold(Int32, state, transition; order)
    publication = LMSP.Publication((LMSP.FoldPublication(
        LMSP.PublicationValue(:event)),), law)
    stage = LMSP.Stage(source, NamedTuple(), (publication,),
        LMSP.Evaluator(StageProgramFoldValue()), LMSP.Control(),
        LMSP.SourceOrigin(:stage_program_metal_negative, line))
    initial_storage, accumulator_storage = array(Int32[7]), array(Int32[91])
    binding = LMSP._StructuralBinding((
        LMSP._field_storage_binding(initial, initial_storage),
        LMSP._field_storage_binding(accumulator, accumulator_storage),
    ), ())
    prepared = LMSP.prepare(LMSP.plan(
        LMSP._bind_law(LMSP.LocalLaw(stage), binding); backend))
    error = stage_program_validation_error(LMSP.execute!(prepared))
    return error, Array(accumulator_storage)
end

function inspection_law()
    source = LMSP.Space(StageProgramStageProgramNode, 4)
    output = LMSP.Field(source, Int32)
    relation = LMSP.IdentityRelation(source)
    stage = stage_program_unique_stage(source, output, relation, StageProgramUniqueValue(), 60)
    return (law = LMSP.LocalLaw(stage), output, relation)
end

function stage_program_direct_pointwise(backend)
    source = LMSP.Space(StageProgramStageProgramNode, 3)
    values = LMSP.Field(source, Int32)
    keys = LMSP.Field(source, Int32)
    integer = LMSP.Field(source, Int32)
    floating = LMSP.Field(source, Float32)
    gathered = LMSP.Field(source, Int32)
    identity = LMSP.IdentityRelation(source)
    indexed = LMSP.IndexRelation(keys => source; optional = true)
    publication(field, relation, port, law) = LMSP.Publication((
        LMSP.FieldPublication(field, relation, LMSP.PublicationValue(port)),),
        law)
    geometry = LMSP.Stage(source, NamedTuple(), (
        publication(keys, identity, :key, LMSP.Unique(Int32)),
        publication(integer, identity, :integer, LMSP.Unique(Int32)),
        publication(floating, identity, :floating, LMSP.Unique(Float32)),
    ), LMSP.Evaluator(StageProgramMultiPointwise(
        StageProgramTypedOperation{:source_site}())), LMSP.Control(),
        LMSP.SourceOrigin(:stage_program_direct_pointwise, 1))
    gather = LMSP.Stage(source,
        (values = LMSP.Access(values, indexed; required = false),),
        (publication(gathered, identity, :value, LMSP.Unique(Int32)),),
        LMSP.Evaluator(StageProgramOptionalGather()), LMSP.Control(),
        LMSP.SourceOrigin(:stage_program_direct_pointwise, 2))
    law = LMSP.sequence(LMSP.LocalLaw(geometry), LMSP.LocalLaw(gather))
    storage = (
        values = Metal.MtlArray(Int32[5, 6, 7]),
        keys = Metal.MtlArray(zeros(Int32, 3)),
        integer = Metal.MtlArray(zeros(Int32, 3)),
        floating = Metal.MtlArray(zeros(Float32, 3)),
        gathered = Metal.MtlArray(zeros(Int32, 3)),
    )
    prepared = LMSP.prepare(law,
        values => storage.values,
        keys => storage.keys,
        integer => storage.integer,
        floating => storage.floating,
        gathered => storage.gathered;
        backend)
    wait(LMSP.execute!(prepared))
    return (
        keys = Array(storage.keys),
        integer = Array(storage.integer),
        floating = Array(storage.floating),
        gathered = Array(storage.gathered),
        phases = map(stage -> stage.planning.phases,
            LMSP.inspect(prepared).stages),
    )
end

function inspection_inspection_report(law, array, backend)
    storage = array(fill(Int32(-1), 4))
    binding = LMSP._StructuralBinding(
        (LMSP._field_storage_binding(law.output, storage),),
        (LMSP._relation_storage_binding(law.relation),),
    )
    plan = LMSP.plan(LMSP._bind_law(law.law, binding); backend)
    prepared = LMSP.prepare(plan)
    return LMSP.inspect(plan), LMSP.inspect(prepared)
end

function inspection_stage_structure(stage)
    planning = stage.planning
    return (
        index = stage.index,
        source = stage.source,
        origin = stage.origin,
        reads = stage.reads,
        control = stage.control,
        publications = stage.publications,
        planning = (
            executor = planning.executor,
            layout = planning.layout,
            evaluator_result_type = planning.evaluator_result_type,
            relationship_receipts = planning.relationship_receipts,
            relation_uses = planning.relation_uses,
            workspace_paths = planning.workspace_paths,
            phases = planning.phases,
        ),
    )
end

function inspection_plan_structure(report)
    planning = report.planning
    return (
        lifecycle = report.lifecycle,
        parameters = report.parameters,
        relations = report.relations,
        stages = map(inspection_stage_structure, report.stages),
        planning = (
            compiler = planning.compiler,
            workspace = planning.workspace,
            workspace_bytes = planning.workspace_bytes,
            program_phases = planning.program_phases,
            stage_phases = planning.stage_phases,
            stage_local_launch_count = planning.stage_local_launch_count,
            program_reset_count = planning.program_reset_count,
            base_provider_launch_count = planning.base_provider_launch_count,
        ),
        equivalence = report.equivalence,
    )
end

inspection_leaf_structure(leaf) = (name = leaf.name, logical = leaf.logical)
function inspection_binding_structure(bindings)
    fields = map(bindings.fields) do field
        (identity = field.identity, ownership = field.ownership,
            leaves = map(inspection_leaf_structure, field.leaves))
    end
    relations = map(bindings.relations) do relation
        (identity = relation.identity, ownership = relation.ownership,
            dynamic_generation = relation.dynamic_generation,
            dynamic_status = relation.dynamic_status,
            leaves = map(inspection_leaf_structure, relation.leaves))
    end
    collections = map(bindings.collections) do collection
        (identity = collection.identity,
            leaves = map(inspection_leaf_structure, collection.leaves))
    end
    return (; fields, relations, collections)
end

function inspection_realized_structure(realized)
    callbacks = map(realized.callback_methods) do callback
        (purpose = callback.purpose, return_type = callback.return_type,
            admission = callback.admission, method = callback.method)
    end
    return (
        callback_methods = callbacks,
        bindings = inspection_binding_structure(realized.bindings),
        parameter_layout = realized.parameter_layout,
        dependency_arity = realized.dependency_arity,
        lease_capacity = realized.lease_capacity,
        workspace_ownership = realized.workspace_ownership,
        state = realized.state,
    )
end

@testset "stage-program execution real Metal" begin
    backend = Metal.MetalBackend()
    selected = get(ENV, "StageProgram_STAGE_PROGRAM_CASE", "all")

    selected in ("all", "pointwise") &&
    @testset "typed multi-port direct pointwise" begin
        result = stage_program_direct_pointwise(backend)
        @test result.keys == Int32[1, 0, 3]
        @test result.integer == Int32[11, 12, 13]
        @test result.floating == Float32[11.5, 12.5, 13.5]
        @test result.gathered == Int32[5, -1, 7]
        @test result.phases == ntuple(
            _ -> ((kind = :direct_identity_unique, count = 1),), 2)
    end

    selected in ("all", "collect") && @testset "parameterized Collect" begin
        records, count, prepared = stage_program_stage_program_collect(backend)
        @test count == Int32[513]
        @test records == Int32.(2 .* (1:513))
        @test LocalMath.inspect(prepared).stages[1].planning.executor === :collect
    end

    selected in ("all", "projection") &&
    @testset "candidate-owned Collect projection" begin
        projected, projected_count, positions =
            stage_program_stage_program_collect_projection(backend)
        @test projected_count == Int32[32]
        @test projected == Int32.(2 .* (1:32))
        @test positions == Int32.(1:32)
    end

    selected in ("all", "fusion") &&
    @testset "bounded pointwise segments execute on Metal" begin
        for stage_count in (1, 2, 4, 5)
            source = LocalMath.Space(8)
            identity = LocalMath.IdentityRelation(source)
            fields = ntuple(_ -> LocalMath.Field(source, Int32), stage_count)
            storages = ntuple(_ -> Metal.MtlArray(fill(Int32(-1), 8)),
                stage_count)
            stages = ntuple(stage_count) do index
                reads = index == 1 ? NamedTuple() : (
                    prior = LocalMath.Access(
                        fields[index - 1], identity; required = true),)
                evaluator = index == 1 ? StageProgramPointwiseSeed() :
                    StageProgramPointwiseStep()
                LocalMath.Stage(
                    source,
                    reads,
                    (LocalMath.Publication((LocalMath.FieldPublication(
                        fields[index], identity,
                        LocalMath.PublicationValue(:value)),),
                        LocalMath.Unique(Int32)),),
                    LocalMath.Evaluator(evaluator),
                    LocalMath.Control(),
                    LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                        label = Symbol(:metal_pointwise_, index)),
                )
            end
            law = LocalMath.sequence(map(LocalMath.LocalLaw, stages)...)
            prepared = LocalMath.prepare(law,
                map(=>, fields, storages)...; backend)
            facts = LocalMath.inspect(prepared)
            @test facts.planning.stage_local_launch_count == cld(stage_count, 4)
            @test length(facts.planning.physical_segments) == cld(stage_count, 4)
            wait(LocalMath.execute!(prepared))
            for index in 1:stage_count
                @test Array(storages[index]) ==
                    Int32.(1:8) .+ Int32(index - 1)
            end
        end


        source = LocalMath.Space(8)
        identity = LocalMath.IdentityRelation(source)
        temporary = LocalMath.Field(source, Int32)
        output = LocalMath.Field(source, Int32)
        seed = LocalMath.Stage(source, NamedTuple(),
            (LocalMath.Publication((LocalMath.FieldPublication(
                temporary, identity, LocalMath.PublicationValue(:value)),),
                LocalMath.Unique(Int32)),),
            LocalMath.Evaluator(StageProgramPointwiseSeed()),
            LocalMath.Control(),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :metal_temporary_seed))
        consume = LocalMath.Stage(source,
            (prior = LocalMath.Access(temporary, identity; required = true),),
            (LocalMath.Publication((LocalMath.FieldPublication(
                output, identity, LocalMath.PublicationValue(:value)),),
                LocalMath.Unique(Int32)),),
            LocalMath.Evaluator(StageProgramPointwiseStep()),
            LocalMath.Control(),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__;
                label = :metal_temporary_consume))
        storage = Metal.MtlArray(fill(Int32(-1), 8))
        prepared = LocalMath.prepare(
            LocalMath.sequence(LocalMath.LocalLaw(seed),
                LocalMath.LocalLaw(consume)),
            temporary => LocalMath.Temporary(), output => storage; backend)
        facts = LocalMath.inspect(prepared)
        segment = only(facts.planning.physical_segments)
        @test LocalMath.semantic_identity(temporary) in segment.forwarded_values
        @test LocalMath.semantic_identity(temporary) ∉
            segment.retained_materializations
        wait(LocalMath.execute!(prepared))
        @test Array(storage) == Int32.(2:9)
    end


    selected in ("all", "resolve") &&
    @testset "exact canonical Resolve executes on Metal" begin
        values, facts = stage_program_atomic_resolve(backend)
        @test values == Int32[3, 6]
        @test map(phase -> phase.kind,
            only(facts.planning.stage_phases)) == (
            :candidate_reset,
            :candidate_evaluate,
            :resolve_atomic_winner,
            :candidate_validate,
            :candidate_finalize_publish,
        )
    end

    selected in ("all", "fold") && @testset "parameterized OrderedFold" begin
        accumulator, prepared = stage_program_stage_program_ordered_fold(backend)
        @test accumulator == Int32[4 * 513]
        @test LocalMath.inspect(prepared).stages[1].planning.executor === :ordered_fold
    end

    # Keep the dynamic-relation Candidate last: a post-launch compiler failure
    # correctly poisons the shared provider scope and must not obscure the
    # independent Collect and OrderedFold evidence above.
    selected in ("all", "candidate") && @testset "parameterized Candidate plus relation receipt" begin
        actual, expected, prepared, generation, validated_generation,
            relation_status =
            stage_program_stage_program_reduce(backend)
        @test actual == expected
        @test Array(generation) == UInt64[7]
        @test Array(validated_generation) == UInt64[7]
        @test Array(relation_status) == Int32[0]
        @test LocalMath.inspect(prepared).stages[1].planning.executor === :candidate
    end

    selected in ("all", "inspection") &&
    @testset "CPU and Metal inspection structure" begin
        cpu_plan, cpu_prepared, metal_plan, metal_prepared = fetch(@async begin
            law = inspection_law()
            cpu = inspection_inspection_report(
                law, identity, KernelAbstractions.CPU())
            metal = inspection_inspection_report(law, Metal.MtlArray, backend)
            (cpu..., metal...)
        end)
        @test keys(cpu_plan) == keys(metal_plan)
        @test keys(cpu_prepared) == keys(metal_prepared)
        @test inspection_plan_structure(cpu_plan) == inspection_plan_structure(metal_plan)
        @test inspection_plan_structure(cpu_prepared) ==
            inspection_plan_structure(metal_prepared)
        @test inspection_realized_structure(cpu_prepared.realized) ==
            inspection_realized_structure(metal_prepared.realized)
        @test cpu_prepared.realized.provider == metal_prepared.realized.provider
        @test cpu_prepared.realized.bindings.fields[1].leaves[1].storage_type !=
            metal_prepared.realized.bindings.fields[1].leaves[1].storage_type
    end

    selected in ("all", "negative") && @testset "negative and provider-tail parity packet" begin
        relation = stage_program_relation_queue_packet(backend)
        @test relation.stale_error isa LMSP.LocalMathValidationError
        @test relation.stale_error.contract === :runtime_stage_validation
        @test relation.stale_outputs == (fill(Int32(-11), 4), fill(Int32(-22), 4))
        @test relation.status_error === nothing
        @test relation.status_outputs ==
            (Int32[1, 2, 3, 4], Int32[101, 102, 103, 104])
        @test relation.success_outputs == (Int32[4, 3, 2, 1], Int32[101, 102, 103, 104])
        @test relation.generation == UInt64[5]
        @test relation.validated_generation == UInt64[5]
        @test relation.status == Int32[0]
        @test relation.submissions == UInt64(2)

        conflict_error, conflict_output = stage_program_candidate_conflict(backend)
        @test conflict_error isa LMSP.LocalMathValidationError
        @test conflict_error.contract === :runtime_stage_validation
        @test conflict_error.actual.failure_code == LMSP._CANDIDATE_STATUS_CONFLICT
        @test conflict_output == Int32[77]

        overflow_error, overflow_storage = stage_program_collect_overflow(backend)
        @test overflow_error isa LMSP.LocalMathValidationError
        @test overflow_error.contract === :runtime_stage_validation
        @test overflow_storage == (fill(Int32(-31), 3), Int32[-32],
            fill(Int32(-33), 3), fill(Int32(-34), 3))

        duplicate_order = LMSP._CanonicalBy(
            StageProgramConstantOrder(), StageProgramConstantOrder())
        duplicate_error, duplicate_output = stage_program_fold_failure(
            backend, Metal.MtlArray, StageProgramLastWrite(), duplicate_order; line = 40)
        @test duplicate_error isa LMSP.LocalMathValidationError
        @test duplicate_error.contract === :runtime_ordered_fold_validation
        @test duplicate_error.actual.failure_class === :duplicate_order_identity
        @test duplicate_output == Int32[91]

        cpu_error, cpu_output = stage_program_fold_failure(
            KernelAbstractions.CPU(), Array, StageProgramInvalidWrite(),
            LMSP._SourceOrder(); line = 41)
        gpu_error, gpu_output = stage_program_fold_failure(
            backend, Metal.MtlArray, StageProgramInvalidWrite(),
            LMSP._SourceOrder(); line = 41)
        @test cpu_output == gpu_output == Int32[91]
        @test gpu_error isa LMSP.LocalMathValidationError
        @test gpu_error.contract === cpu_error.contract ===
            :runtime_ordered_fold_validation
        diagnostic_signature(error) = begin
            actual = error.actual
            return (
                stage = actual.stage,
                failure_code = actual.failure_code,
                failure_class = actual.failure_class,
                component = actual.component,
                source_item = actual.source_item,
                canonical_position = actual.canonical_position,
                witness = actual.witness,
                context_index = actual.context_index,
                origin = (source = error.origin.source,
                    line = error.origin.line, label = error.origin.label),
            )
        end
        @test diagnostic_signature(gpu_error) == diagnostic_signature(cpu_error)
    end
end
