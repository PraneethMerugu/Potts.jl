using Test
import KernelAbstractions
import LocalMath
import StaticArrays

const LMA = LocalMath

struct StorageAuthoringNode end
struct StorageAuthoringRecord
    value::Int32
    weight::Float32
end
struct StorageAuthoringCollectEvaluator end
@inline function (::StorageAuthoringCollectEvaluator)(item::Int32, reads, parameters)
    return (records = LMA.CollectedValue(
        StorageAuthoringRecord(item, Float32(item))),)
end

function _storage_authoring_identity(law)
    publication = only(only(law.stages).publications)
    return only(publication.components).relation
end

@testset "explicit scientific storage allocation" begin
    backend = KernelAbstractions.CPU()
    cells = LMA.Space(StorageAuthoringNode, (2, 2))
    input = LMA.Field(cells, Float32)
    output = LMA.Field(cells, Float32)
    law = LMA.@localmath i ∈ cells begin
        output[i] = 2f0 * input[i]
    end
    output_identity = _storage_authoring_identity(law)
    source = reshape(Float32[1, 2, 3, 4], 2, 2)
    bound = LMA.bind(law,
        input => LMA.Allocate(source),
        output => LMA.Allocate(undef); backend)
    input_storage = LMA.storage(bound, input)
    output_storage = LMA.storage(bound, output)
    @test input_storage == source
    @test input_storage !== source
    @test size(output_storage) == (2, 2)
    @test LMA.storage(bound, output_identity) === nothing
    @test_throws LMA.LocalMathValidationError LMA.bind(law,
        input => source, output => zeros(Float32, 2, 2),
        output_identity => nothing)
    @test !occursin("Allocate", string(typeof(bound)))
    source[1] = 99f0
    @test input_storage[1] == 1f0

    prepared = LMA.prepare(law,
        input => source, output => LMA.Allocate(undef); backend)
    @test LMA.storage(prepared.plan, input) === source
    @test LMA.storage(prepared, output) !== output_storage
    @test !occursin("Allocate", string(typeof(prepared)))
    wait(LMA.execute!(prepared))
    @test LMA.storage(prepared, output) == 2f0 .* source

    caller_output = zeros(Float32, 2, 2)
    caller_bound = LMA.bind(law, input => source, output => caller_output)
    @test LMA.storage(caller_bound, output) === caller_output
    @test_throws LMA.LocalMathValidationError LMA.storage(
        caller_bound, LMA.Field(cells, Float32))
    conflicting = LMA.Field(cells, Int32;
        id = LMA.semantic_identity(output))
    @test_throws LMA.LocalMathValidationError LMA.storage(
        caller_bound, conflicting)

    vector_cells = LMA.Space(StorageAuthoringNode, 2)
    tuple_input = LMA.Field(vector_cells, NTuple{2,Float32})
    tuple_output = LMA.Field(vector_cells, NTuple{2,Float32})
    tuple_law = LMA.@localmath i ∈ vector_cells begin
        tuple_output[i] = tuple_input[i]
    end
    tuple_bound = LMA.bind(tuple_law,
        tuple_input => LMA.Allocate((1f0, 2f0)),
        tuple_output => LMA.Allocate(undef); backend)
    tuple_prepared = LMA.prepare(LMA.plan(tuple_bound; backend))
    wait(LMA.execute!(tuple_prepared))
    @test LMA.storage(tuple_bound, tuple_output) ==
        fill((1f0, 2f0), 2)

    StaticVector = StaticArrays.SVector{2,Float32}
    static_input = LMA.Field(vector_cells, StaticVector)
    static_output = LMA.Field(vector_cells, StaticVector)
    static_law = LMA.@localmath i ∈ vector_cells begin
        static_output[i] = static_input[i]
    end
    static_source = StaticVector[StaticVector(1f0, 2f0),
        StaticVector(3f0, 4f0)]
    static_bound = LMA.bind(static_law,
        static_input => LMA.Allocate(static_source),
        static_output => LMA.Allocate(undef); backend)
    @test LMA.storage(static_bound, static_input) == static_source
    @test LMA.storage(static_bound, static_input) !== static_source
    @test size(LMA.storage(static_bound, static_output)) == (2,)
end

@testset "allocation initialization is exact" begin
    backend = KernelAbstractions.CPU()
    cells = LMA.Space(StorageAuthoringNode, 3)
    field = LMA.Field(cells, Float32)
    output = LMA.Field(cells, Float32)
    partial = LMA.@localmath (i ∈ cells;
            parameters = (active::Bool,), when = active) begin
        output[i] = field[i]
    end
    @test_throws LMA.LocalMathValidationError LMA.bind(partial,
        field => LMA.Allocate(undef), output => LMA.Allocate(0f0); backend)
    @test_throws LMA.LocalMathValidationError LMA.bind(partial,
        field => LMA.Allocate(Float32[1, 2]),
        output => LMA.Allocate(0f0); backend)
    @test_throws LMA.LocalMathValidationError LMA.bind(partial,
        field => LMA.Allocate(Int32[1, 2, 3]),
        output => LMA.Allocate(0f0); backend)
    @test_throws LMA.LocalMathValidationError LMA.bind(partial,
        field => LMA.Allocate("unsupported"),
        output => LMA.Allocate(0f0); backend)
    @test_throws LMA.LocalMathValidationError LMA.bind(partial,
        field => LMA.Allocate(0f0), output => zeros(Float32, 3))

    middle = LMA.Field(cells, Float32)
    final = LMA.Field(cells, Float32)
    staged = LMA.@localmath begin
        @stage initialize(i ∈ cells) begin
            middle[i] = field[i] + 1f0
        end
        @stage consume(i ∈ cells) begin
            final[i] = 2f0 * middle[i]
        end
    end
    staged_bound = LMA.bind(staged,
        field => LMA.Allocate(Float32[1, 2, 3]),
        middle => LMA.Allocate(undef),
        final => LMA.Allocate(undef); backend)
    staged_prepared = LMA.prepare(LMA.plan(staged_bound; backend))
    wait(LMA.execute!(staged_prepared))
    @test LMA.storage(staged_bound, final) == Float32[4, 6, 8]

    temporary_bound = LMA.bind(staged,
        field => LMA.Allocate(Float32[1, 2, 3]),
        middle => LMA.Temporary(),
        final => LMA.Allocate(undef); backend)
    middle_bound_binding = only(filter(temporary_bound.binding.fields) do value
        value.field == middle
    end)
    @test middle_bound_binding.storage isa LMA._TemporaryStorageRequest
    @test_throws LMA.LocalMathValidationError LMA.storage(
        temporary_bound, middle)
    temporary_plan = LMA.plan(temporary_bound; backend)
    middle_plan_binding = only(filter(
            temporary_plan.bound.binding.binding.fields) do value
        value.field == middle
    end)
    @test middle_plan_binding.storage isa AbstractArray
    fill!(middle_plan_binding.storage, -99f0)
    temporary_prepared = LMA.prepare(temporary_plan)
    temporary_facts = LMA.inspect(temporary_prepared)
    middle_fact = only(filter(temporary_facts.realized.bindings.fields) do fact
        fact.identity == LMA.semantic_identity(middle)
    end)
    @test middle_fact.ownership === :temporary
    segment = only(temporary_facts.planning.physical_segments)
    @test LMA.semantic_identity(middle) in segment.forwarded_values
    @test LMA.semantic_identity(middle) ∉ segment.retained_materializations
    wait(LMA.execute!(temporary_prepared))
    @test all(==(-99f0), middle_plan_binding.storage)
    @test LMA.storage(temporary_prepared, final) == Float32[4, 6, 8]
    @test_throws LMA.LocalMathValidationError LMA.bind(staged,
        field => Float32[1, 2, 3], middle => LMA.Temporary(),
        final => zeros(Float32, 3))

    partial_temporary = LMA.@localmath (i ∈ cells;
            parameters = (active::Bool,), when = active) begin
        middle[i] = field[i]
    end
    @test_throws LMA.LocalMathValidationError LMA.bind(partial_temporary,
        field => Float32[1, 2, 3], middle => LMA.Temporary(); backend)
end

struct NestedStorageRecord
    endpoints::NTuple{2,Int32}
    direction::NTuple{3,Float32}
    weight::Float32
end

@testset "allocated StructArray Fields preserve component storage" begin
    backend = KernelAbstractions.CPU()
    cells = LMA.Space(StorageAuthoringNode, 2)
    records = LMA.Field(cells, NestedStorageRecord)
    output = LMA.Field(cells, Float32)
    law = LMA.@localmath i ∈ cells begin
        record = records[i]
        output[i] = record.weight + record.direction[1] +
            Float32(record.endpoints[1])
    end
    source = LMA.StructArrays.StructArray(NestedStorageRecord[
        NestedStorageRecord((1, 2), (1f0, 0f0, 0f0), 3f0),
        NestedStorageRecord((2, 3), (0f0, 1f0, 0f0), 4f0),
    ])
    direct_bound = LMA.bind(law,
        records => source, output => zeros(Float32, 2))
    @test LMA.storage(direct_bound, records) === source
    prepared = LMA.prepare(law,
        records => LMA.Allocate(source), output => LMA.Allocate(undef);
        backend)
    copied = LMA.storage(prepared, records)
    @test copied isa LMA.StructArrays.StructArray{NestedStorageRecord}
    @test copied !== source
    @test size(copied) == size(source)
    @test eltype(copied) === NestedStorageRecord
    @test all(zip(
            values(LMA.StructArrays.components(copied)),
            values(LMA.StructArrays.components(source)),
        )) do (copied_component, source_component)
        copied_component !== source_component
    end
    LMA.StructArrays.components(source).weight[1] = 100f0
    @test LMA.storage(direct_bound, records)[1].weight == 100f0
    @test copied[1].weight == 3f0
    wait(LMA.execute!(prepared))
    @test LMA.storage(prepared, output) == Float32[5, 6]
end

@testset "relation and Collection allocation" begin
    backend = KernelAbstractions.CPU()
    source = LMA.Space(StorageAuthoringNode, 3)
    destination = LMA.Space(StorageAuthoringNode, 2)
    accumulated = LMA.Field(destination, Int32)
    scatter = LMA.FixedRelation(source => destination; degree = 1)
    reduction = LMA.@localmath item ∈ source begin
        accumulated[scatter(item)] += item
    end
    host_relation = (
        endpoints = reshape(Int32[1, 2, 1], 1, 3),
        counts = ones(Int32, 3),
    )
    bound = LMA.bind(reduction,
        accumulated => LMA.Allocate(Int32(0)),
        scatter => LMA.Allocate(host_relation); backend)
    copied_relation = LMA.storage(bound, scatter)
    @test copied_relation.endpoints == host_relation.endpoints
    @test copied_relation.endpoints !== host_relation.endpoints
    prepared = LMA.prepare(LMA.plan(bound; backend))
    wait(LMA.execute!(prepared))
    @test LMA.storage(bound, accumulated) == Int32[4, 2]

    immutable_output = zeros(Int32, 2)
    immutable_bound = LMA.bind(reduction,
        accumulated => immutable_output, scatter => host_relation.endpoints)
    immutable_prepared = LMA.prepare(LMA.plan(immutable_bound; backend))
    wait(LMA.execute!(immutable_prepared))
    @test immutable_output == Int32[4, 2]

    endpoint_bound = LMA.bind(reduction,
        accumulated => LMA.Allocate(Int32(0)),
        scatter => LMA.Allocate(host_relation.endpoints); backend)
    @test LMA.storage(endpoint_bound, scatter).endpoints ==
        host_relation.endpoints

    duplicate_bound = LMA.bind(reduction,
        accumulated => zeros(Int32, 2), accumulated => zeros(Int32, 2),
        scatter => host_relation.endpoints)
    @test_throws LMA.LocalMathValidationError LMA.plan(
        duplicate_bound; backend)
    foreign = LMA.Field(destination, Int32)
    foreign_bound = LMA.bind(reduction,
        accumulated => zeros(Int32, 2),
        foreign => zeros(Int32, 2),
        scatter => host_relation.endpoints)
    @test_throws LMA.LocalMathValidationError LMA.plan(
        foreign_bound; backend)
    computed = LMA.IdentityRelation(source)
    @test_throws LMA.LocalMathValidationError LMA.bind(reduction,
        accumulated => zeros(Int32, 2),
        scatter => host_relation.endpoints,
        computed => nothing)

    records = LMA.Collection(Int32, 3)
    collection_law = LMA.@localmath item ∈ source begin
        records[item] = bounded_collect(Int32(item); maximum = 1,
            group = Int32(mod1(item, 2)), groups = 2)
    end
    collection_bound = LMA.bind(
        collection_law, records => LMA.Allocate(); backend)
    collection_storage = LMA.storage(collection_bound, records)
    @test size(collection_storage.records) == (3,)
    @test size(collection_storage.count) == (1,)
    @test size(collection_storage.segment_starts) == (3,)
    @test collection_storage.segment_starts == ones(Int32, 3)
    @test collection_storage.source_position === nothing
    prepared_collection = LMA.prepare(
        LMA.plan(collection_bound; backend))
    wait(LMA.execute!(prepared_collection))
    @test collection_storage.records == Int32[1, 3, 2]
end

@testset "recursive relation and exact Collection schemas" begin
    backend = KernelAbstractions.CPU()
    source = LMA.Space(StorageAuthoringNode, 3)
    input = LMA.Field(source, Int32)
    output = LMA.Field(source, Int32)
    packed = LMA.PackedRelation(
        source => source; degree_bound = 1, capacity = 3)
    law = LMA.@localmath item ∈ source begin
        gathered = input[packed(item)]
        output[item] = gathered[1]
    end
    host_endpoints = reshape(Int32[1, 2, 3], 1, 3)
    bound = LMA.bind(law,
        input => Int32[4, 5, 6],
        output => LMA.Allocate(undef),
        packed => LMA.MutableRelationStorage((
                active = LMA.Allocate(Bool[true, true, true]),
                endpoints = LMA.Allocate(host_endpoints),
                offsets = LMA.Allocate(Int32[1]),
                counts = LMA.Allocate(Int32[3]),
            ); generation = LMA.Allocate(UInt64[1])); backend)
    packed_storage = LMA.storage(bound, packed)
    @test packed_storage.endpoints == host_endpoints
    @test packed_storage.endpoints !== host_endpoints
    packed_binding = only(binding for binding in bound.binding.relations
        if binding.relation == packed)
    @test packed_binding.status !== nothing
    @test packed_binding.status.validated_generations !== nothing
    prepared = LMA.prepare(LMA.plan(bound; backend))
    wait(LMA.execute!(prepared))
    @test LMA.storage(bound, output) == Int32[4, 5, 6]

    fixed = LMA.FixedRelation(source => source; degree = 2)
    inverse = LMA.InverseRelation(fixed; degree_bound = 2)
    inverse_output = LMA.Field(source, Int32)
    inverse_law = LMA.@localmath item ∈ source begin
        gathered = input[inverse(item)]
        inverse_output[item] = gathered[1]
    end
    inverse_host = (
        degrees = Int32[2, 2, 2],
        incidents = Int32[1 1 2; 3 2 3],
    )
    inverse_bound = LMA.bind(inverse_law,
        input => Int32[7, 8, 9],
        inverse_output => LMA.Allocate(undef),
        inverse => LMA.Allocate(inverse_host); backend)
    @test LMA.storage(inverse_bound, inverse).incidents ==
        inverse_host.incidents
    inverse_prepared = LMA.prepare(LMA.plan(inverse_bound; backend))
    wait(LMA.execute!(inverse_prepared))
    @test LMA.storage(inverse_bound, inverse_output) == Int32[7, 7, 8]

    collection = LMA.Collection(StorageAuthoringRecord, 3)
    projected = LMA.Publication((LMA.CollectionPublication(
        collection, LMA.PublicationValue(:records)),),
        LMA.Collect(StorageAuthoringRecord; maximum = 2,
            projection = LMA.persistent_source_position()))
    projected_stage = LMA.Stage(source, NamedTuple(), (projected,),
        LMA.Evaluator(StorageAuthoringCollectEvaluator()), LMA.Control(),
        LMA.SourceOrigin(:storage_authoring, 1))
    projected_law = LMA.LocalLaw(projected_stage)
    projected_bound = LMA.bind(
        projected_law, collection => LMA.Allocate(); backend)
    projected_storage = LMA.storage(projected_bound, collection)
    @test projected_storage.records isa LMA.StructArrays.StructArray
    @test length(projected_storage.records) == 3
    @test length(projected_storage.source_position) == 6

    empty_source = LMA.Space(StorageAuthoringNode, 0)
    empty_collection = LMA.Collection(Int32, 0)
    empty_publication = LMA.Publication((LMA.CollectionPublication(
        empty_collection, LMA.PublicationValue(:records)),),
        LMA.Collect(Int32; maximum = 1))
    empty_stage = LMA.Stage(empty_source, NamedTuple(), (empty_publication,),
        LMA.Evaluator(StorageAuthoringCollectEvaluator()), LMA.Control(),
        LMA.SourceOrigin(:storage_authoring, 2))
    empty_bound = LMA.bind(
        LMA.LocalLaw(empty_stage), empty_collection => LMA.Allocate(); backend)
    @test isempty(LMA.storage(empty_bound, empty_collection).records)

    ordinary = LMA.Publication((LMA.CollectionPublication(
        collection, LMA.PublicationValue(:records)),),
        LMA.Collect(StorageAuthoringRecord; maximum = 2))
    ordinary_stage = LMA.Stage(source, NamedTuple(), (ordinary,),
        LMA.Evaluator(StorageAuthoringCollectEvaluator()), LMA.Control(),
        LMA.SourceOrigin(:storage_authoring, 3))
    inconsistent = LMA.sequence(
        LMA.LocalLaw(ordinary_stage), projected_law)
    @test_throws LMA.LocalMathValidationError LMA.bind(
        inconsistent, collection => LMA.Allocate(); backend)
    consistent = LMA.sequence(projected_law, projected_law)
    consistent_bound = LMA.bind(
        consistent, collection => LMA.Allocate(); backend)
    @test length(LMA.storage(consistent_bound, collection).source_position) == 6
end
