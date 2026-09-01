using Test
import KernelAbstractions
import LocalMath
const LMLM = LocalMath

struct LocalMathAuthoringNode end
struct LocalMathAuthoringGate end
struct LocalMathFoldTransition end
@inline function (::LocalMathFoldTransition)(state, value, item, reads)
    return LMLM.FoldStep((accumulator = LMLM.BoundedWrites(
        (Int32(1),), (value,), Int32(1)),))
end

@testset "transparent LocalMath scalar definitions are ordinary Julia" begin
    LMLM.@localmath function localmath_geometric_mean(
            x::T, y::T,
        )::T where {T<:AbstractFloat}
        sqrt(x * y)
    end

    @test localmath_geometric_mean(4.0f0, 9.0f0) == 6.0f0
    @test @inferred(localmath_geometric_mean(4.0, 9.0)) == 6.0
    method = which(localmath_geometric_mean, (Float32, Float32))
    @test method.module === @__MODULE__
    @test !isdefined(LMLM, :localmath_geometric_mean)
end

@testset "IndexRelation authored gather and strictness" begin
    source = LMLM.Space(3)
    destination = LMLM.Space(4)
    keys = LMLM.Field(source, Int32)
    values = LMLM.Field(destination, Int32)
    output = LMLM.Field(source, Int32)
    indexed = LMLM.IndexRelation(keys => destination)
    law = LMLM.@localmath i ∈ source begin
        gathered = values[indexed(i)]
        output[i] = gathered[1]
    end
    prepared = LMLM.prepare(law,
        keys => Int32[4, 2, 1], values => Int32[10, 20, 30, 40],
        output => zeros(Int32, 3);
        backend = LMLM.KernelAbstractions.CPU())
    wait(LMLM.execute!(prepared))
    @test LMLM.storage(prepared, output) == Int32[40, 20, 10]
    @test only(filter(r -> r.identity == LMLM.semantic_identity(indexed),
        LMLM.inspect(prepared).relations)).footprint.kind == :bounded_indirect

    failing = LMLM.prepare(law,
        keys => Int32[4, 0, 1], values => Int32[10, 20, 30, 40],
        output => fill(Int32(-1), 3);
        backend = LMLM.KernelAbstractions.CPU())
    @test_throws LMLM.LocalMathValidationError wait(LMLM.execute!(failing))
    @test LMLM.storage(failing, output) == fill(Int32(-1), 3)

    optional = LMLM.IndexRelation(keys => destination; optional = true)
    optional_law = LMLM.@localmath i ∈ source begin
        lane = samples(values[optional(i)])[1]
        output[i] = something(lane.value, Int32(-2))
    end
    optional_prepared = LMLM.prepare(optional_law,
        keys => Int32[4, 0, 1], values => Int32[10, 20, 30, 40],
        output => zeros(Int32, 3);
        backend = LMLM.KernelAbstractions.CPU())
    wait(LMLM.execute!(optional_prepared))
    @test LMLM.storage(optional_prepared, output) == Int32[40, -2, 10]
end

@testset "bounded fold policies use the Stage transaction barrier" begin
    sources = LMLM.Space(2)
    values_space = LMLM.Space(4)
    values = LMLM.Field(values_space, Float32)
    output = LMLM.Field(sources, Float32)
    neighborhoods = LMLM.FixedRelation(sources => values_space; degree = 2)
    positive_sum = LMLM.bounded_fold(identity, +, 0.0f0,
        (sum, count) -> sum;
        domain = LMLM.Where(>(0.0f0)),
        oninvalid = LMLM.RejectInvalid(),
        onempty = LMLM.RejectEmpty(),
        order = LMLM.CanonicalLeftFold())
    law = LMLM.@localmath i ∈ sources begin
        local_values = samples(values[neighborhoods(i)])
        output[i] = positive_sum(local_values)
    end
    endpoints = reshape(Int32[1, 2, 3, 4], 2, 2)
    prepared = LMLM.prepare(law,
        values => Float32[1, 2, 3, 4], output => zeros(Float32, 2),
        neighborhoods => endpoints;
        backend = KernelAbstractions.CPU())
    wait(LMLM.execute!(prepared))
    @test LMLM.storage(prepared, output) == Float32[3, 7]

    rejected = LMLM.prepare(law,
        values => Float32[1, -2, 3, 4], output => fill(-1.0f0, 2),
        neighborhoods => endpoints;
        backend = KernelAbstractions.CPU())
    @test_throws LMLM.LocalMathValidationError wait(LMLM.execute!(rejected))
    @test LMLM.storage(rejected, output) == fill(-1.0f0, 2)

    forgiving = LMLM.bounded_fold(identity, +, 0.0f0,
        (sum, count) -> sum;
        domain = LMLM.Where(>(0.0f0)),
        oninvalid = LMLM.SkipInvalid(),
        onempty = LMLM.FillEmpty(42.0f0),
        order = LMLM.RelaxedAssociative())
    forgiving_law = LMLM.@localmath i ∈ sources begin
        output[i] = forgiving(samples(values[neighborhoods(i)]))
    end
    forgiving_prepared = LMLM.prepare(forgiving_law,
        values => Float32[-1, -2, 3, 4], output => zeros(Float32, 2),
        neighborhoods => endpoints;
        backend = KernelAbstractions.CPU())
    wait(LMLM.execute!(forgiving_prepared))
    @test LMLM.storage(forgiving_prepared, output) == Float32[42, 7]
end

function _localmath_prepared(work, fields, relations;
        collections = (), parameters = (;))
    stored_relations = Tuple(pair for pair in relations
        if LMLM._relation_requires_storage(first(pair).representation))
    bound = LMLM.bind(work, fields..., stored_relations..., collections...)
    prepared = LMLM.prepare(LMLM.plan(bound;
        backend = KernelAbstractions.CPU()))
    wait(LMLM.execute!(prepared; parameters = parameters))
    return prepared
end

@testset "LocalMath bounded Collect" begin
    source = LMLM.Space(LocalMathAuthoringNode, 3)
    records = LMLM.Collection(Int32, 3)
    work = LMLM.@localmath item ∈ source begin
        records[item] = bounded_collect(Int32(item); maximum = 1)
    end
    storage = LMLM.CompactedStorage(LMLM._CONSTRUCTION_TOKEN,
        fill(Int32(-1), 3), Int32[0], nothing,
        fill(Int32(0), 3), fill(Int32(0), 3), nothing)
    _localmath_prepared(work, (), ();
        collections = (records => storage,))
    @test storage.records == Int32[1, 2, 3]
    @test storage.count == Int32[3]

    grouped_records = LMLM.Collection(Int32, 3)
    grouped_work = LMLM.@localmath item ∈ source begin
        grouped_records[item] = bounded_collect(Int32(item);
            maximum = 1, group = Int32(mod1(item, 2)), groups = 2)
    end
    grouped_storage = LMLM.CompactedStorage(LMLM._CONSTRUCTION_TOKEN,
        fill(Int32(-1), 3), Int32[0], fill(Int32(0), 3),
        fill(Int32(0), 3), fill(Int32(0), 3), nothing)
    _localmath_prepared(grouped_work, (), ();
        collections = (grouped_records => grouped_storage,))
    @test grouped_storage.records == Int32[1, 3, 2]
    @test grouped_storage.segment_starts == Int32[1, 3, 4]

    tuple_records = LMLM.Collection(Tuple{Int32,Int32}, 6)
    tuple_work = LMLM.@localmath item ∈ source begin
        tuple_records[item] = bounded_collect(
            (Int32(item), Int32(10) * item); maximum=1)
    end
    tuple_evaluator = only(tuple_work.stages).evaluator.evaluator
    @test tuple_evaluator isa LMLM._AuthoringTypedEvaluator
    @test isbitstype(typeof(tuple_evaluator))
    @test fieldnames(typeof(tuple_evaluator)) == (:evaluator,)
    @test fieldcount(typeof(tuple_evaluator)) == 1
    @test !(getfield(tuple_evaluator, :evaluator) isa
        LMLM._AuthoringRecordType)
    tuple_marker = LMLM._AuthoringRecordType{Tuple{Int32,Int32}}()
    @test @inferred(LMLM._authoring_collect(
        (Int32(1), Int32(2)), true, tuple_marker)) isa
        LMLM.CollectedValue{Tuple{Int32,Int32}}
    @test @inferred(LMLM._authoring_collect(
        ((Int32(1), Int32(2)), (Int32(3), Int32(4))),
        (true, false), tuple_marker)) isa NTuple{2,LMLM.CollectedValue{
            Tuple{Int32,Int32}}}
    tuple_prepared = LMLM.prepare(tuple_work,
        tuple_records => LMLM.Allocate(); backend=KernelAbstractions.CPU())
    wait(LMLM.execute!(tuple_prepared))
    tuple_storage = LMLM.storage(tuple_prepared, tuple_records)
    @test tuple_storage.records[1:3] ==
        Tuple{Int32,Int32}[(1, 10), (2, 20), (3, 30)]

    emitted_tuples = LMLM.Collection(Tuple{Int32,Int32}, 6)
    emitted_work = LMLM.@localmath item ∈ source begin
        emitted_tuples[item] = bounded_collect((
                (Int32(item), Int32(1)),
                (Int32(item), Int32(2)),
            ); maximum=2, when=(true, isodd(item)))
    end
    emitted_prepared = LMLM.prepare(emitted_work,
        emitted_tuples => LMLM.Allocate(); backend=KernelAbstractions.CPU())
    wait(LMLM.execute!(emitted_prepared))
    emitted_storage = LMLM.storage(emitted_prepared, emitted_tuples)
    @test only(emitted_storage.count) == Int32(5)
    @test emitted_storage.source_lane[1:5] == Int32[1, 2, 1, 1, 2]

    consumed = LMLM.Field(source, Int32)
    positions = LMLM.Field(source, Int32)
    pipeline = LMLM.@localmath begin
        @stage produce(item ∈ source) begin
            grouped_records[item] = bounded_collect(Int32(10) * item;
                maximum=1, group=Int32(item), groups=3,
                projection=:source_position)
        end
        @stage consume(item ∈ source; prefix=count(grouped_records)) begin
            group = bounded(grouped_records[item]; maximum=1)
            consumed[item] = group[1]
            positions[item] = source_position(grouped_records, item; lane=1)
        end
    end
    @test pipeline.stages[2].publications[1].law.coverage isa
        LMLM.PartialCoverage
    @test pipeline.stages[2].publications[1].law.onempty isa
        LMLM.PreserveEmpty
    pipeline_storage = LMLM.CompactedStorage(LMLM._CONSTRUCTION_TOKEN,
        fill(Int32(-1), 3), Int32[0], fill(Int32(0), 4),
        fill(Int32(0), 3), fill(Int32(0), 3), fill(Int32(0), 3))
    identities = Tuple(unique(component.relation
        for stage in pipeline.stages for publication in stage.publications
        for component in publication.components
        if component isa LMLM.FieldPublication))
    _localmath_prepared(pipeline, (
        consumed => fill(Int32(-1), 3),
        positions => fill(Int32(-1), 3),
    ), Tuple(relation => nothing for relation in identities);
        collections=(grouped_records => pipeline_storage,))
    @test pipeline_storage.records == Int32[10, 20, 30]

    emitted_records = LMLM.Collection(Int32, 6)
    lane_one = LMLM.Field(source, Int32)
    lane_two = LMLM.Field(source, Int32)
    multi_lane_pipeline = LMLM.@localmath begin
        @stage produce(item ∈ source) begin
            emitted_records[item] = bounded_collect((
                Int32(10) * item, Int32(20) * item,
            ); maximum=2, when=(true, isodd(item)),
                projection=:source_position)
        end
        @stage consume(item ∈ source) begin
            lane_one[item] = source_position(emitted_records, item; lane=1)
            lane_two[item] = source_position(emitted_records, item; lane=2)
        end
    end
    multi_lane_prepared = LMLM.@prepare (
            multi_lane_pipeline; backend=KernelAbstractions.CPU()) begin
        emitted_records = allocate()
        lane_one = allocate(Int32(-1))
        lane_two = allocate(Int32(-1))
    end
    wait(LMLM.execute!(multi_lane_prepared))
    @test LMLM.storage(multi_lane_prepared, lane_one) == Int32[1, 3, 4]
    @test LMLM.storage(multi_lane_prepared, lane_two) == Int32[2, 0, 5]

    invalid_lane = LMLM.Field(source, Int32)
    invalid_lane_pipeline = LMLM.@localmath begin
        @stage produce(item ∈ source) begin
            emitted_records[item] = bounded_collect((item, item);
                maximum=2, when=(true, true), projection=:source_position)
        end
        @stage consume(item ∈ source) begin
            invalid_lane[item] = source_position(emitted_records, item; lane=3)
        end
    end
    lane_error = try
        LMLM.@prepare (invalid_lane_pipeline;
                backend=KernelAbstractions.CPU()) begin
            emitted_records = allocate()
            invalid_lane = allocate(Int32(-1))
        end
        nothing
    catch caught
        caught
    end
    @test lane_error isa LMLM.LocalMathValidationError
    @test lane_error.contract == :collection_source_position_lane
    @test lane_error.expected == 1:2
    @test lane_error.actual == 3
end

@testset "LocalMath explicit runtime routing" begin
    source = LMLM.Space(LocalMathAuthoringNode, 3)
    destination = LMLM.Space(LocalMathAuthoringNode, 3)
    output = LMLM.Field(destination, Int32)
    route = LMLM.RuntimeRelation(source => destination;
        degree_bound = 1, key_type = Int32)
    work = LMLM.@localmath item ∈ source begin
        publish(output, Int32(10) * item;
            route = route, key = Int32(4) - item, law = :unique)
    end
    storage = fill(Int32(-1), 3)
    _localmath_prepared(work, (output => storage,), (route => nothing,))
    @test storage == Int32[30, 20, 10]
end

@testset "LocalMath pointwise authoring" begin
    @test Base.isexported(LMLM, Symbol("@localmath"))
    cells = LMLM.Space(LocalMathAuthoringNode, 4)
    input = LMLM.Field(cells, Float32)
    output = LMLM.Field(cells, Float32)
    work = LMLM.@localmath (i ∈ cells;
            parameters = (scale::Float32,)) begin
        output[i] = input[i] * scale
    end

    @test work isa LMLM.LocalLaw
    @test isbitstype(typeof(only(work.stages).evaluator.evaluator))
    @test length(work.stages) == 1
    report = LMLM.inspect(work)
    @test only(report.stages).reads[1].mode == :required
    @test only(report.stages).reads[1].role ==
        :input_via_identity_required
    @test only(only(report.stages).publications).ports == (:output_unique,)
    repeated = LMLM.@localmath (i ∈ cells;
            parameters = (scale::Float32,)) begin
        output[i] = input[i] * scale
    end
    @test keys(only(repeated.stages).accesses) ==
        keys(only(work.stages).accesses)
    @test LMLM.inspect(repeated).stages[1].publications[1].ports ==
        report.stages[1].publications[1].ports
    @test only(report.stages).publications[1].details.law.kind == :unique
    @test only(report.stages).publications[1].origin.line > 0
    @test_throws LMLM.LocalMathValidationError macroexpand(@__MODULE__, :(
        LMLM.@localmath only(work.stages)))

    construction_calls = Ref(0)
    source_once() = (construction_calls[] += 1; cells)
    outer_i = :untouched
    single_evaluation = LMLM.@localmath i ∈ source_once() begin
        output[i] = input[i]
    end
    @test single_evaluation isa LMLM.LocalLaw
    @test construction_calls[] == 1
    @test outer_i === :untouched

    input_storage = Float32[1, 2, 3, 4]
    output_storage = zeros(Float32, 4)
    identity = only(values(only(work.stages).accesses)).relation
    _localmath_prepared(work, (
        input => input_storage,
        output => output_storage,
    ), (identity => nothing,);
        parameters = (; scale = 2.5f0))
    @test output_storage == Float32[2.5, 5, 7.5, 10]
end

@testset "LocalMath bounded gather, Reduce, and Resolve" begin
    source = LMLM.Space(LocalMathAuthoringNode, 3)
    destination = LMLM.Space(LocalMathAuthoringNode, 2)
    values_field = LMLM.Field(destination, Int32)
    gathered = LMLM.Field(source, Int32)
    reduction = LMLM.Field(destination, Int32)
    relation = LMLM.FixedRelation(source => destination; degree = 1)

    reduce_work = LMLM.@localmath i ∈ source begin
        reduction[relation(i)] += Int32(i)
    end
    reduction_storage = zeros(Int32, 2)
    _localmath_prepared(reduce_work, (reduction => reduction_storage,),
        (relation => (
        endpoints = reshape(Int32[1, 2, 1], 1, 3),
        counts = ones(Int32, 3)),))
    @test reduction_storage == Int32[4, 2]

    conditional_work = LMLM.@localmath i ∈ source begin
        reduction[relation(i)] = reduce_to(Int32(i);
            op = +, onempty = :preserve, when = isodd(i))
    end
    conditional_storage = zeros(Int32, 2)
    _localmath_prepared(conditional_work, (reduction => conditional_storage,),
        (relation => (
        endpoints = reshape(Int32[1, 2, 1], 1, 3),
        counts = ones(Int32, 3)),))
    @test conditional_storage == Int32[4, 0]

    resolve_work = LMLM.@localmath i ∈ source begin
        values_field[relation(i)] = resolve_to(;
            score = Int32(4 - i), payload = i,
            lower = Int32(1), upper = Int32(3))
    end
    resolved_storage = fill(Int32(9), 2)
    _localmath_prepared(resolve_work, (values_field => resolved_storage,),
        (relation => (
        endpoints = reshape(Int32[1, 1, 1], 1, 3),
        counts = ones(Int32, 3)),))
    @test resolved_storage == Int32[3, 9]

    tie_field = LMLM.Field(source, UInt32)
    secondary_tie = LMLM.Field(source, Int32)
    tied_work = LMLM.@localmath i ∈ source begin
        values_field[relation(i)] = resolve_to(;
            score = Int32(1), tie = (tie_field[i], secondary_tie[i]), payload = i,
            lower = Int32(0), upper = Int32(2), onempty = Int32(-1))
    end
    tied_identity = first(values(only(tied_work.stages).accesses)).relation
    tied_storage = fill(Int32(9), 2)
    _localmath_prepared(tied_work, (
        tie_field => UInt32[30, 10, 20],
        secondary_tie => Int32[1, 2, 0],
        values_field => tied_storage,
    ), (
        tied_identity => nothing,
        relation => (
            endpoints = reshape(Int32[1, 1, 1], 1, 3),
            counts = ones(Int32, 3)),
    ))
    @test tied_storage == Int32[2, -1]

    max_work = LMLM.@localmath i ∈ source begin
        values_field[relation(i)] = resolve_to(;
            score=Int32(i), payload=i, lower=Int32(0), upper=Int32(4),
            sense=:max)
    end
    max_storage = fill(Int32(-1), 2)
    _localmath_prepared(max_work, (values_field => max_storage,),
        (relation => (endpoints=reshape(Int32[1, 1, 1], 1, 3),
            counts=ones(Int32, 3)),))
    @test max_storage[1] == 3

    @test_throws LMLM.LocalMathValidationError LMLM.@localmath i ∈ source begin
        reduction[relation(i)] = reduce_to(Int32(i);
            op=+, seed=Int32(0), order=:nonsense)
    end
    @test_throws LMLM.LocalMathValidationError LMLM.@localmath i ∈ source begin
        values_field[relation(i)] = resolve_to(;
            score=Int32(i), payload=i, lower=Int32(0), upper=Int32(4),
            sense=:nonsense)
    end

    # `samples` retains the exact optional topology protocol.
    sample_output = LMLM.Field(source, Int32)
    sample_work = LMLM.@localmath i ∈ source begin
        lane = samples(gathered[i])[1]
        sample_output[i] = something(lane.value)
    end
    @test only(LMLM.inspect(sample_work).stages).reads[1].mode == :samples

    required_work = LMLM.@localmath i ∈ source begin
        neighborhood = values_field[relation(i)]
        gathered[i] = neighborhood[1]
    end
    required_identity = only(required_work.stages).publications[1].components[1].relation
    required_output = fill(Int32(-7), 3)
    failure_task = @async try
        _localmath_prepared(required_work, (
            values_field => Int32[10, 20],
            gathered => required_output,
        ), (
            relation => (
                endpoints = reshape(Int32[1, 2, 1], 1, 3),
                counts = Int32[1, 0, 1]),
            required_identity => nothing,
        ))
        nothing
    catch error
        error
    end
    @test fetch(failure_task) isa Exception
    @test required_output == fill(Int32(-7), 3)
end

@testset "LocalMath Cartesian bounds and grouped offsets" begin
    line = LMLM.Space(5)
    line_input = LMLM.Field(line, Int32)
    line_output = LMLM.Field(line, Int32)
    line_law = LMLM.@localmath i ∈ periodic(line) begin
        line_output[i] = line_input[i - 1] + line_input[i + 1]
    end
    line_values = Int32[1, 2, 3, 4, 5]
    line_result = fill(Int32(-1), 5)
    _localmath_prepared(line_law,
        (line_input => line_values, line_output => line_result), ())
    @test line_result == circshift(line_values, 1) .+
        circshift(line_values, -1)

    grid = LMLM.Space((4, 4))
    input = LMLM.Field(grid, Int32)
    output = LMLM.Field(grid, Int32)
    input_storage = reshape(Int32.(1:16), 4, 4)

    pointwise = LMLM.@localmath (i, j) ∈ grid begin
        output[i, j] = input[i, j]
    end
    pointwise_output = fill(Int32(-1), 4, 4)
    _localmath_prepared(pointwise,
        (input => input_storage, output => pointwise_output), ())
    @test pointwise_output == input_storage

    periodic_law = LMLM.@localmath (i, j) ∈ periodic(grid) begin
        output[i, j] = input[i - 1, j] + input[i + 1, j]
    end
    periodic_output = fill(Int32(-1), 4, 4)
    _localmath_prepared(periodic_law,
        (input => input_storage, output => periodic_output), ())
    @test periodic_output == circshift(input_storage, (1, 0)) .+
        circshift(input_storage, (-1, 0))
    @test length(only(periodic_law.stages).accesses) == 1
    periodic_footprints = map(
        relation -> relation.footprint, LMLM.inspect(periodic_law).relations)
    read_footprint = only(filter(footprint ->
        hasproperty(footprint, :offsets) && length(footprint.offsets) == 2,
        periodic_footprints))
    @test read_footprint.strength === :exact
    @test read_footprint.offsets == ((-1, 0), (1, 0))
    @test read_footprint.halos.read ==
        (lower=(1, 0), upper=(1, 0))
    @test read_footprint.halos.reverse_publication ==
        (lower=(1, 0), upper=(1, 0))

    interior_law = LMLM.@localmath (i, j) ∈ interior(grid, 1) begin
        output[i, j] = input[i, j]
    end
    interior_output = fill(Int32(-1), 4, 4)
    _localmath_prepared(interior_law,
        (input => input_storage, output => interior_output), ())
    @test interior_output[2:3, 2:3] == input_storage[2:3, 2:3]
    @test all(interior_output[[1, 4], :] .== -1)
    @test all(interior_output[:, [1, 4]] .== -1)
    @test only(interior_law.stages).publications[1].law.coverage isa
        LMLM.PartialCoverage
    interior_read_law = LMLM.@localmath (i, j) ∈ interior(grid, 1) begin
        output[i, j] = input[i - 1, j] + input[i + 1, j]
    end
    interior_footprints = map(
        relation -> relation.footprint, LMLM.inspect(interior_read_law).relations)
    interior_read_footprint = only(filter(footprint ->
        hasproperty(footprint, :offsets) && length(footprint.offsets) == 2,
        interior_footprints))
    @test interior_read_footprint.offsets == ((-1, 0), (1, 0))
    @test interior_read_footprint.halos.read ==
        (lower=(1, 0), upper=(1, 0))
    interior_read_relation = only(filter(relation ->
        relation.representation.family === :affine &&
            length(relation.representation.offsets) == 2,
        LMLM.inspect(interior_read_law).relations))
    @test interior_read_relation.representation.origin == (1, 1)

    volume = LMLM.Space((4, 4, 4))
    volume_input = LMLM.Field(volume, Int32)
    volume_output = LMLM.Field(volume, Int32)
    @test_throws LMLM.LocalMathValidationError macroexpand(@__MODULE__, :(
        LMLM.@localmath i ∈ interior(line, 1) begin
            line_output[i] = line_input[i - 2]
        end))
    @test_throws LMLM.LocalMathValidationError macroexpand(@__MODULE__, :(
        LMLM.@localmath (i, j) ∈ interior(grid, 1) begin
            output[i, j] = input[i, j + 2]
        end))
    @test_throws LMLM.LocalMathValidationError macroexpand(@__MODULE__, :(
        LMLM.@localmath (i, j, k) ∈ interior(volume, 1) begin
            volume_output[i, j, k] = volume_input[i, j, k - 2]
        end))

    cartesian_tie = LMLM.Field(grid, UInt32)
    cartesian_resolve = LMLM.@localmath (i, j) ∈ periodic(grid) begin
        output[i, j] = resolve_to(;
            score=input[i, j], tie=cartesian_tie[i, j], payload=input[i, j],
            lower=Int32(0), upper=Int32(16))
    end
    @test only(cartesian_resolve.stages).publications[1].law isa LMLM.Resolve

    sampled = LMLM.@localmath (i, j) ∈ periodic(grid) begin
        neighbor = samples(input[i - 1, j])
        output[i, j] = neighbor.value
    end
    @test length(only(sampled.stages).accesses) == 1
end

@testset "LocalMath finite stage composition and syntax rejection" begin
    cells = LMLM.Space(LocalMathAuthoringNode, 2)
    first_field = LMLM.Field(cells, Int32)
    second_field = LMLM.Field(cells, Int32)
    third_field = LMLM.Field(cells, Int32)
    work = LMLM.@localmath begin
        @stage first(i ∈ cells) begin
            second_field[i] = first_field[i] + Int32(1)
        end
        @stage second(i ∈ cells) begin
            third_field[i] = second_field[i] * Int32(2)
        end
    end
    @test length(work.stages) == 2
    @test map(stage -> stage.origin.label, work.stages) == (:first, :second)

    active_space = LMLM.Space(LocalMathAuthoringGate, 1)
    active = LMLM.Field(active_space, Bool)
    gated = LMLM.@localmath begin
        @stage gated_stage(i ∈ cells; when = active) begin
            second_field[i] = first_field[i]
        end
    end
    @test only(gated.stages).control.gate isa LMLM._FieldGate

    active = LMLM.Field(cells, Bool)
    owned = LMLM.Field(cells, Bool)
    identity = LMLM.IdentityRelation(cells)
    owned_subset = LMLM.MaskedRelation(identity, owned)
    controlled = LMLM.@localmath begin
        @stage selected(i ∈ cells; mask=active, subset=owned_subset) begin
            second_field[i] = first_field[i]
        end
    end
    controlled_output = fill(Int32(-1), 2)
    controlled_prepared = LMLM.prepare(controlled,
        first_field => Int32[10, 20],
        second_field => controlled_output,
        active => Bool[true, true],
        owned => Bool[false, true]; backend=KernelAbstractions.CPU())
    wait(LMLM.execute!(controlled_prepared))
    @test controlled_output == Int32[-1, 20]

    @test_throws LMLM.LocalMathValidationError macroexpand(@__MODULE__, :(
        LMLM.@localmath i ∈ cells begin
            while true
            end
            second_field[i] = first_field[i]
        end))
    @test_throws LMLM.LocalMathValidationError macroexpand(@__MODULE__, :(
        LMLM.@localmath i ∈ cells begin
            total = Int32(0)
            for lane in 1:i
                total += Int32(lane)
            end
            second_field[i] = total
        end))
    @test_throws LMLM.LocalMathValidationError macroexpand(@__MODULE__, :(
        LMLM.@localmath i ∈ cells begin
            second_field[i] = resolve_to(;
                score=first_field[i], tie=Int32(i), payload=first_field[i],
                lower=Int32(0), upper=Int32(10))
        end))

    reduction_order = :unsupported
    @test_throws LMLM.LocalMathValidationError LMLM.@localmath i ∈ cells begin
        second_field[i] = reduce_to((first_field[i],);
            op=+, seed=Int32(0), order=reduction_order)
    end
end

@testset "LocalMath authored ordered state" begin
    events = LMLM.Space(LocalMathAuthoringNode, 3)
    state_space = LMLM.Space(LocalMathAuthoringNode, 1)
    key = LMLM.Field(events, Int32)
    identity = LMLM.Field(events, UInt32)
    initial = LMLM.Field(state_space, Int32)
    accumulator = LMLM.Field(state_space, Int32)
    work = LMLM.@localmath event ∈ events begin
        event_value = key[event]
        @ordered (by=(key[event], identity[event]),
                  state=(accumulator => initial,)) begin
            accumulator[Int32(1)] = event_value
        end
    end
    initial_storage = Int32[0]
    accumulator_storage = Int32[-1]
    _localmath_prepared(work, (
        key => Int32[30, 10, 20],
        identity => UInt32[1, 2, 3],
        initial => initial_storage,
        accumulator => accumulator_storage,
    ), ())
    @test accumulator_storage == Int32[30]
    @test only(LMLM.inspect(work).stages).publications[1].details.law.kind ==
        :ordered_fold

    source_ordered = LMLM.@localmath event ∈ events begin
        @ordered (by=:source, state=(accumulator => accumulator,)) begin
            accumulator[Int32(1)] = Int32(event)
        end
    end
    accumulator_storage .= 9
    _localmath_prepared(source_ordered,
        (accumulator => accumulator_storage,), ())
    @test accumulator_storage == Int32[3]

    halted = LMLM.@localmath event ∈ events begin
        @ordered (by=(key[event], identity[event]),
                  state=(accumulator => initial,)) begin
            accumulator[Int32(1)] = Int32(event)
            halt_when(event == Int32(3))
        end
    end
    accumulator_storage .= -1
    _localmath_prepared(halted, (
        key => Int32[30, 10, 20],
        identity => UInt32[1, 2, 3],
        initial => initial_storage,
        accumulator => accumulator_storage,
    ), ())
    @test accumulator_storage == Int32[3]
end
