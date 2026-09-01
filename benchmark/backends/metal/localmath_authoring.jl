using Test
using Metal
using LocalMath
using StaticArrays

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
    static_source = StaticVector[
        StaticVector(Float32(i), Float32(i + 1)) for i in 1:4]
    # This case qualifies cold structured allocation only; SVector field
    # execution is intentionally outside the reviewed Metal storage operations.
    static_bound = LocalMath.bind(static_law,
        static_input => LocalMath.Allocate(static_source),
        static_output => LocalMath.Allocate(undef);
        backend)
    @test Array(LocalMath.storage(static_bound, static_input)) == static_source
    @test size(LocalMath.storage(static_bound, static_output)) == (4,)

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
    @test_throws LocalMath.LocalMathValidationError LocalMath.prepare(reduction,
        assembled => LocalMath.Allocate(Int32(0)),
        scatter => LocalMath.Allocate((;
            endpoints=reshape(Int32[1, 3, 1], 1, 3)));
        backend)

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
    positive_sum = LocalMath.bounded_fold(
        identity, +, 0.0f0, (sum, count) -> sum;
        domain = LocalMath.Where(>(0.0f0)),
        oninvalid = LocalMath.RejectInvalid(),
        onempty = LocalMath.RejectEmpty(),
        order = LocalMath.CanonicalLeftFold(),
    )
    fold_law = LocalMath.@localmath item ∈ fold_sources begin
        fold_output[item] = positive_sum(
            samples(fold_values[neighborhoods(item)]))
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
