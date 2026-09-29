using Test
using Metal
using LocalMath
using StaticArrays
using Statistics

struct LocalMathMetalNode end

@testset "LocalMath syntax uses the sole Metal KA path" begin
    backend = Metal.MetalBackend()
    cells = LocalMath.Space(LocalMathMetalNode, 4)
    input = LocalMath.Field(cells, Float32)
    output = LocalMath.Field(cells, Float32)
    pointwise = LocalMath.@localmath (i ∈ cells;
            parameters = (scale::Float32,)) begin
        output[i] = input[i] * scale
    end
    prepared = LocalMath.prepare(pointwise,
        input => LocalMath.Allocate(Float32[1, 2, 3, 4]),
        output => LocalMath.Allocate(undef);
        backend)
    input_storage = LocalMath.storage(prepared, input)
    output_storage = LocalMath.storage(prepared, output)
    wait(LocalMath.execute!(prepared; parameters = (; scale = 2f0)))
    @test Array(output_storage) == Float32[2, 4, 6, 8]

    StaticVector = SVector{2,Float32}
    static_input = LocalMath.Field(cells, StaticVector)
    static_output = LocalMath.Field(cells, StaticVector)
    static_law = LocalMath.@localmath i ∈ cells begin
        static_output[i] = static_input[i]
    end
    static_source_parent = StaticVector[
        StaticVector(Float32(i), Float32(i + 1)) for i in 1:8]
    static_source_view = @view static_source_parent[1:2:7]
    static_source = collect(static_source_view)
    # This case qualifies cold structured allocation only; SVector field
    # execution is intentionally outside the reviewed Metal storage operations.
    static_bound = LocalMath.bind(static_law,
        static_input => LocalMath.Allocate(static_source_view),
        static_output => LocalMath.Allocate(undef);
        backend)
    static_source_parent[1] = StaticVector(-1.0f0, -2.0f0)
    @test Array(LocalMath.storage(static_bound, static_input)) == static_source
    @test LocalMath.storage(static_bound, static_input) !== static_source_view
    @test size(LocalMath.storage(static_bound, static_output)) == (4,)
    device_source = Metal.MtlArray(static_source)
    device_bound = LocalMath.bind(static_law,
        static_input => LocalMath.Allocate(device_source),
        static_output => LocalMath.Allocate(undef);
        backend)
    @test Array(LocalMath.storage(device_bound, static_input)) == static_source
    @test LocalMath.storage(device_bound, static_input) !== device_source

    source = LocalMath.Space(LocalMathMetalNode, 3)
    destination = LocalMath.Space(LocalMathMetalNode, 2)
    assembled = LocalMath.Field(destination, Int32)
    scatter = LocalMath.FixedRelation(source => destination; degree = 1)
    reduction = LocalMath.@localmath item ∈ source begin
        assembled[scatter(item)] += item
    end
    relation_declaration = LocalMath.Allocate((
            endpoints = reshape(Int32[1, 2, 1], 1, 3),
            counts = ones(Int32, 3),
        ))
    reduction_prepared = LocalMath.prepare(reduction,
        assembled => LocalMath.Allocate(Int32(0)),
        scatter => relation_declaration;
        backend)
    assembled_storage = LocalMath.storage(reduction_prepared, assembled)
    @test isempty(only(LocalMath.inspect(reduction_prepared).stages).
        planning.relationship_receipts)
    wait(LocalMath.execute!(reduction_prepared))
    @test Array(assembled_storage) == Int32[4, 2]

    mixed_device_bound = LocalMath.bind(reduction,
        assembled => zeros(Int32, 2),
        scatter => (; endpoints=Metal.MtlArray(
            reshape(Int32[1, 2, 1], 1, 3)));
        backend)
    @test_throws LocalMath.LocalMathValidationError LocalMath.plan(
        mixed_device_bound; backend)
    invalid_fixed_relation = try
        LocalMath.prepare(reduction,
            assembled => LocalMath.Allocate(Int32(0)),
            scatter => LocalMath.Allocate((;
                endpoints=reshape(Int32[1, 3, 1], 1, 3)));
            backend)
        nothing
    catch error
        error
    end
    @test invalid_fixed_relation isa LocalMath.LocalMathValidationError
    @test invalid_fixed_relation.stage == :bind
    @test invalid_fixed_relation.contract == :fixed_relation_content
    @test invalid_fixed_relation.expected == (count = 0:1, endpoint = 1:2)
    @test invalid_fixed_relation.actual == :invalid_device_content

    resolved = LocalMath.Field(destination, Int32)
    resolution = LocalMath.@localmath item ∈ source begin
        resolved[scatter(item)] = resolve_to(;
            score = Int32(4) - item, payload = item,
            lower = Int32(1), upper = Int32(3))
    end
    resolution_prepared = LocalMath.prepare(resolution,
        resolved => LocalMath.Allocate(Int32(-1)),
        scatter => relation_declaration;
        backend)
    resolved_storage = LocalMath.storage(resolution_prepared, resolved)
    wait(LocalMath.execute!(resolution_prepared))
    @test Array(resolved_storage) == Int32[3, 2]

    keys = LocalMath.Field(source, Int32)
    indirect_values = LocalMath.Field(destination, Int32)
    indirect_output = LocalMath.Field(source, Int32)
    indirect = LocalMath.IndexRelation(keys => destination)
    indexed_gather = LocalMath.@localmath item ∈ source begin
        gathered = indirect_values[indirect(item)]
        indirect_output[item] = gathered[1]
    end
    indexed_prepared = LocalMath.prepare(indexed_gather,
        keys => LocalMath.Allocate(Int32[2, 1, 2]),
        indirect_values => LocalMath.Allocate(Int32[11, 17]),
        indirect_output => LocalMath.Allocate(undef);
        backend)
    wait(LocalMath.execute!(indexed_prepared))
    @test Array(LocalMath.storage(indexed_prepared, indirect_output)) ==
        Int32[17, 11, 17]

    optional = LocalMath.IndexRelation(keys => destination; optional = true)
    optional_gather = LocalMath.@localmath item ∈ source begin
        lane = samples(indirect_values[optional(item)])[1]
        indirect_output[item] = something(lane.value, Int32(-1))
    end
    optional_prepared = LocalMath.prepare(optional_gather,
        keys => LocalMath.Allocate(Int32[2, 0, 1]),
        indirect_values => LocalMath.Allocate(Int32[11, 17]),
        indirect_output => LocalMath.Allocate(undef);
        backend)
    wait(LocalMath.execute!(optional_prepared))
    @test Array(LocalMath.storage(optional_prepared, indirect_output)) ==
        Int32[17, -1, 11]

    fold_sources = LocalMath.Space(2)
    fold_values_space = LocalMath.Space(4)
    fold_values = LocalMath.Field(fold_values_space, Float32)
    fold_output = LocalMath.Field(fold_sources, Float32)
    neighborhoods = LocalMath.FixedRelation(
        fold_sources => fold_values_space; degree = 2)
    fold_law = LocalMath.@localmath item ∈ fold_sources begin
        fold_output[item] = LocalMath.fold(
            samples(fold_values[neighborhoods(item)]);
            combine = +, init = 0.0f0, domain = >(0.0f0))
    end
    fold_prepared = LocalMath.prepare(fold_law,
        fold_values => LocalMath.Allocate(Float32[1, 2, 3, 4]),
        fold_output => LocalMath.Allocate(Float32(0)),
        neighborhoods => LocalMath.Allocate(
            reshape(Int32[1, 2, 3, 4], 2, 2));
        backend)
    wait(LocalMath.execute!(fold_prepared))
    @test Array(LocalMath.storage(fold_prepared, fold_output)) ==
        Float32[3, 7]

    rejected_fold = LocalMath.prepare(fold_law,
        fold_values => LocalMath.Allocate(Float32[1, -2, 3, 4]),
        fold_output => LocalMath.Allocate(Float32(-1)),
        neighborhoods => LocalMath.Allocate(
            reshape(Int32[1, 2, 3, 4], 2, 2));
        backend)
    @test_throws LocalMath.LocalMathValidationError wait(
        LocalMath.execute!(rejected_fold))
    @test Array(LocalMath.storage(rejected_fold, fold_output)) ==
        Float32[-1, -1]

    sum_output = LocalMath.Field(fold_sources, Float32)
    minimum_output = LocalMath.Field(fold_sources, Float32)
    maximum_output = LocalMath.Field(fold_sources, Float32)
    mean_output = LocalMath.Field(fold_sources, Float32)
    geometric_output = LocalMath.Field(fold_sources, Float32)
    sum_law = LocalMath.@localmath item ∈ fold_sources begin
        values = fold_values[neighborhoods(item)]
        sum_output[item] = sum(values)
    end
    minimum_law = LocalMath.@localmath item ∈ fold_sources begin
        values = fold_values[neighborhoods(item)]
        minimum_output[item] = minimum(values)
    end
    maximum_law = LocalMath.@localmath item ∈ fold_sources begin
        values = fold_values[neighborhoods(item)]
        maximum_output[item] = maximum(values)
    end
    mean_law = LocalMath.@localmath item ∈ fold_sources begin
        values = fold_values[neighborhoods(item)]
        mean_output[item] = Statistics.mean(values)
    end
    geometric_law = LocalMath.@localmath item ∈ fold_sources begin
        values = fold_values[neighborhoods(item)]
        geometric_output[item] = LocalMath.geometric_mean(values)
    end
    reductions = LocalMath.sequence(
        sum_law, minimum_law, maximum_law, mean_law, geometric_law)
    reductions_prepared = LocalMath.prepare(reductions,
        fold_values => LocalMath.Allocate(Float32[1, 4, 4, 16]),
        sum_output => LocalMath.Allocate(undef),
        minimum_output => LocalMath.Allocate(undef),
        maximum_output => LocalMath.Allocate(undef),
        mean_output => LocalMath.Allocate(undef),
        geometric_output => LocalMath.Allocate(undef),
        neighborhoods => LocalMath.Allocate(
            reshape(Int32[1, 2, 3, 4], 2, 2));
        backend)
    wait(LocalMath.execute!(reductions_prepared))
    @test Array(LocalMath.storage(reductions_prepared, sum_output)) ==
        Float32[5, 20]
    @test Array(LocalMath.storage(reductions_prepared, minimum_output)) ==
        Float32[1, 4]
    @test Array(LocalMath.storage(reductions_prepared, maximum_output)) ==
        Float32[4, 16]
    @test Array(LocalMath.storage(reductions_prepared, mean_output)) ==
        Float32[2.5, 10]
    @test Array(LocalMath.storage(reductions_prepared, geometric_output)) ==
        Float32[2, 8]

    rejected_geometric = LocalMath.prepare(geometric_law,
        fold_values => LocalMath.Allocate(Float32[1, 0, 4, 16]),
        geometric_output => LocalMath.Allocate(Float32(-1)),
        neighborhoods => LocalMath.Allocate(
            reshape(Int32[1, 2, 3, 4], 2, 2));
        backend)
    @test_throws LocalMath.LocalMathValidationError wait(
        LocalMath.execute!(rejected_geometric))
    @test Array(LocalMath.storage(rejected_geometric, geometric_output)) ==
        Float32[-1, -1]

    fresh = LocalMath.CompactedStorage(
        backend, Int32, 3;
        group_count = 2, source_items = 6, source_position = true)
    @test Array(fresh.count) == Int32[0]
    @test Array(fresh.segment_starts) == Int32[1, 1, 1]
    @test Array(fresh.source_item) == zeros(Int32, 3)
    @test Array(fresh.source_lane) == zeros(Int32, 3)
    @test Array(fresh.source_position) == zeros(Int32, 6)
    empty_fresh = LocalMath.CompactedStorage(
        backend, Int32, 0;
        group_count = 0, source_items = 0, source_position = true)
    @test Array(empty_fresh.count) == Int32[0]
    @test Array(empty_fresh.segment_starts) == Int32[1]
    @test isempty(empty_fresh.records)
    @test isempty(empty_fresh.source_item)
    @test isempty(empty_fresh.source_lane)
    @test isempty(empty_fresh.source_position)

    records = LocalMath.Collection(Int32, 3)
    collected = LocalMath.@localmath item ∈ source begin
        records[item] = bounded_collect(Int32(item); maximum = 1,
            group = Int32(mod1(item, 2)), groups = 2)
    end
    collected_prepared = LocalMath.prepare(collected,
        records => LocalMath.Allocate(); backend)
    compacted = LocalMath.storage(collected_prepared, records)
    @test Array(compacted.segment_starts) == ones(Int32, 3)
    wait(LocalMath.execute!(collected_prepared))
    @test Array(compacted.records) == Int32[1, 3, 2]
    @test Array(compacted.segment_starts) == Int32[1, 3, 4]
end
