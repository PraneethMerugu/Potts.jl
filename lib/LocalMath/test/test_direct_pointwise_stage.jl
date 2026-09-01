using Test
import LocalMath
const LMDP = LocalMath

struct DirectPointwiseNode end

struct TypedContextOperation{Identity} end
@inline (::TypedContextOperation{:source_site})(value::Int32) = value + Int32(10)

struct SymbolParameterizedEvaluator{O}
    operation::O
end

@inline function (evaluator::SymbolParameterizedEvaluator)(
        item::Int32, reads, parameters)
    value = evaluator.operation(item)
    return (
        integer = LMDP.UniqueValue(value),
        floating = LMDP.UniqueValue(Float32(value) + 0.5f0),
    )
end

struct RuntimeSymbolEvaluator
    identity::Symbol
end
@inline (::RuntimeSymbolEvaluator)(item::Int32, reads, parameters) =
    (value = LMDP.UniqueValue(item),)

struct ConditionalPointwiseEvaluator end
@inline function (::ConditionalPointwiseEvaluator)(item::Int32, reads, parameters)
    participates = isodd(item)
    return (
        preserved = LMDP.ConditionalUniqueValue(item, participates),
        filled = LMDP.ConditionalUniqueValue(Float32(item), participates),
    )
end

struct PrefixValueEvaluator end
@inline (::PrefixValueEvaluator)(item::Int32, reads, parameters) =
    (prefix = LMDP.UniqueValue(getfield(parameters, 1)),)

struct ControlFieldEvaluator end
@inline function (::ControlFieldEvaluator)(item::Int32, reads, parameters)
    return (
        active = LMDP.UniqueValue(item != Int32(2)),
        owned = LMDP.UniqueValue(item != Int32(3)),
    )
end

struct ControlledValueEvaluator end
@inline (::ControlledValueEvaluator)(item::Int32, reads, parameters) =
    (value = LMDP.UniqueValue(item),)

struct OptionalIndexEvaluator end
@inline function (::OptionalIndexEvaluator)(item::Int32, reads, parameters)
    sample = reads[1][1]
    value = something(sample.value, Int32(-1))
    return (value = LMDP.UniqueValue(value),)
end

struct RequiredReadEvaluator end
@inline function (::RequiredReadEvaluator)(item::Int32, reads, parameters)
    return (value = LMDP.UniqueValue(something(reads[1][1].value)),)
end

struct PointwiseChainSeed end
@inline (::PointwiseChainSeed)(item::Int32, reads, parameters) =
    (value = LMDP.UniqueValue(item),)
struct PointwiseChainStep end
@inline (::PointwiseChainStep)(item::Int32, reads, parameters) =
    (value = LMDP.UniqueValue(
        something(@inbounds(reads[1][1].value)) + Int32(1)),)

function _direct_pointwise_publication(field, relation, port, law)
    return LMDP.Publication((LMDP.FieldPublication(
        field, relation, LMDP.PublicationValue(port)),), law)
end

function _direct_pointwise_bound(law, fields::Tuple, relations::Tuple)
    return LMDP._bind_law(law, LMDP._StructuralBinding(
        map(pair -> LMDP._field_storage_binding(first(pair), last(pair)), fields),
        map(LMDP._relation_storage_binding, relations),
    ))
end


@testset "bounded physical pointwise segmentation and forwarding" begin
    for stage_count in (1, 2, 4, 5)
        source = LMDP.Space(8)
        identity = LMDP.IdentityRelation(source)
        fields = ntuple(_ -> LMDP.Field(source, Int32), stage_count)
        storages = ntuple(_ -> fill(Int32(-1), 8), stage_count)
        stages = ntuple(stage_count) do index
            accesses = index == 1 ? NamedTuple() : (
                prior = LMDP.Access(fields[index - 1], identity;
                    required = true),)
            evaluator = index == 1 ? PointwiseChainSeed() :
                PointwiseChainStep()
            LMDP.Stage(source, accesses,
                (_direct_pointwise_publication(fields[index], identity,
                    :value, LMDP.Unique(Int32)),),
                LMDP.Evaluator(evaluator), LMDP.Control(),
                LMDP.SourceOrigin(:pointwise_chain, index))
        end
        law = LMDP.sequence(map(LMDP.LocalLaw, stages)...)
        bound = _direct_pointwise_bound(law,
            map(=>, fields, storages), (identity,))
        backend = LMDP.KernelAbstractions.get_backend(first(storages))
        plan = LMDP.plan(bound; backend)
        expected_segments = cld(stage_count, 4)
        @test length(plan.lowering.launches) == expected_segments
        @test all(launch -> launch isa LMDP._PointwiseSegmentEntry,
            plan.lowering.launches)
        facts = LMDP.inspect(plan)
        @test facts.planning.stage_local_launch_count == expected_segments
        @test facts.planning.base_provider_launch_count == expected_segments + 1
        @test sum(length(segment.forwarded_values)
            for segment in facts.planning.physical_segments) ==
            stage_count - expected_segments
        prepared = LMDP.prepare(plan)
        @test length(prepared.runtime.launches) == expected_segments
        wait(LMDP.execute!(prepared))
        for index in 1:stage_count
            @test storages[index] == Int32.(1:8) .+ Int32(index - 1)
        end
    end
end

@testset "pointwise mask and subset use preceding typed control fields" begin
    source = LMDP.Space(DirectPointwiseNode, 4)
    active = LMDP.Field(source, Bool)
    owned = LMDP.Field(source, Bool)
    output = LMDP.Field(source, Int32)
    identity = LMDP.IdentityRelation(source)
    subset = LMDP.MaskedRelation(identity, owned)
    producer = LMDP.Stage(source, NamedTuple(), (
        _direct_pointwise_publication(active, identity, :active,
            LMDP.Unique(Bool)),
        _direct_pointwise_publication(owned, identity, :owned,
            LMDP.Unique(Bool)),
    ), LMDP.Evaluator(ControlFieldEvaluator()), LMDP.Control(),
        LMDP.SourceOrigin(:direct_pointwise_control, 1))
    controlled = LMDP.Stage(source, NamedTuple(), (
        _direct_pointwise_publication(output, identity, :value,
            LMDP.Unique(Int32; coverage = LMDP.PartialCoverage(),
                onempty = LMDP.FillEmpty(Int32(-4)))),
    ), LMDP.Evaluator(ControlledValueEvaluator()),
        LMDP.Control(; mask = active, subset),
        LMDP.SourceOrigin(:direct_pointwise_control, 2))
    law = LMDP.sequence(
        LMDP.LocalLaw(producer), LMDP.LocalLaw(controlled))
    active_storage = fill(false, 4)
    owned_storage = fill(false, 4)
    output_storage = fill(Int32(90), 4)
    bound = _direct_pointwise_bound(law, (
        active => active_storage,
        owned => owned_storage,
        output => output_storage,
    ), (identity, subset))
    backend = LMDP.KernelAbstractions.get_backend(output_storage)
    plan = LMDP.plan(bound; backend)
    entries = LMDP._logical_lowering_entries(plan.lowering)
    @test all(entry -> entry.executor.layout isa
        LMDP._DirectIdentityUniqueLayout, entries)
    @test only(plan.lowering.launches) isa LMDP._PointwiseSegmentEntry
    wait(LMDP.execute!(LMDP.prepare(plan)))
    @test active_storage == Bool[true, false, true, true]
    @test owned_storage == Bool[true, true, false, true]
    @test output_storage == Int32[1, -4, -4, 4]
end

@testset "typed callable identities and multi-port pointwise publication" begin
    source = LMDP.Space(DirectPointwiseNode, 4)
    integer = LMDP.Field(source, Int32)
    floating = LMDP.Field(source, Float32)
    identity = LMDP.IdentityRelation(source)
    evaluator = SymbolParameterizedEvaluator(TypedContextOperation{:source_site}())
    @test LMDP._device_evaluator_capture(evaluator)
    @test_throws LMDP.LocalMathValidationError begin
        LMDP.Evaluator(RuntimeSymbolEvaluator(:source_site))
    end

    stage = LMDP.Stage(source, NamedTuple(), (
        _direct_pointwise_publication(
            integer, identity, :integer, LMDP.Unique(Int32)),
        _direct_pointwise_publication(
            floating, identity, :floating, LMDP.Unique(Float32)),
    ), LMDP.Evaluator(evaluator), LMDP.Control(),
        LMDP.SourceOrigin(:direct_pointwise, 1))
    integer_storage = fill(Int32(-1), 4)
    floating_storage = fill(-1.0f0, 4)
    bound = _direct_pointwise_bound(LMDP.LocalLaw(stage), (
        integer => integer_storage,
        floating => floating_storage,
    ), (identity,))
    backend = LMDP.KernelAbstractions.get_backend(integer_storage)
    plan = LMDP.plan(bound; backend)
    @test LMDP._logical_lowering_entries(plan.lowering)[1].executor.layout isa
        LMDP._DirectIdentityUniqueLayout
    @test LMDP.inspect(plan).stages[1].planning.phases ==
        ((kind = :direct_identity_unique, count = 1),)
    prepared = LMDP.prepare(plan)
    direct = prepared.runtime.launches[1].stage
    @test direct isa LMDP._DirectPointwiseSegmentPreparation
    @test direct.destinations === ((integer_storage, floating_storage),)
    wait(LMDP.execute!(prepared))
    @test integer_storage == Int32[11, 12, 13, 14]
    @test floating_storage == Float32[11.5, 12.5, 13.5, 14.5]
end

@testset "pointwise controls preserve Unique empty semantics" begin
    source = LMDP.Space(DirectPointwiseNode, 4)
    preserved = LMDP.Field(source, Int32)
    filled = LMDP.Field(source, Float32)
    singleton = LMDP.Space(DirectPointwiseNode, 1)
    prefix = LMDP.Field(singleton, Int32)
    identity = LMDP.IdentityRelation(source)
    prefix_identity = LMDP.IdentityRelation(singleton)
    count = LMDP.Parameter(:count, Int32)
    prefix_stage = LMDP.Stage(singleton, NamedTuple(), (
        _direct_pointwise_publication(prefix, prefix_identity, :prefix,
            LMDP.Unique(Int32)),
    ), LMDP.Evaluator(PrefixValueEvaluator(), (count,)), LMDP.Control(),
        LMDP.SourceOrigin(:direct_pointwise, 2))
    controlled_stage = LMDP.Stage(source, NamedTuple(), (
        _direct_pointwise_publication(preserved, identity, :preserved,
            LMDP.Unique(Int32; coverage = LMDP.PartialCoverage(),
                onempty = LMDP.PreserveEmpty())),
        _direct_pointwise_publication(filled, identity, :filled,
            LMDP.Unique(Float32; coverage = LMDP.PartialCoverage(),
                onempty = LMDP.FillEmpty(-4.0f0))),
    ), LMDP.Evaluator(ConditionalPointwiseEvaluator()),
        LMDP.Control(; prefix),
        LMDP.SourceOrigin(:direct_pointwise, 3))
    preserved_storage = fill(Int32(90), 4)
    filled_storage = fill(90.0f0, 4)
    prefix_storage = Int32[3]
    law = LMDP.sequence(
        LMDP.LocalLaw(prefix_stage;
            parameters = LMDP.ParameterSchema(count)),
        LMDP.LocalLaw(controlled_stage),
    )
    bound = _direct_pointwise_bound(law, (
        preserved => preserved_storage,
        filled => filled_storage,
        prefix => prefix_storage,
    ), (identity, prefix_identity))
    backend = LMDP.KernelAbstractions.get_backend(preserved_storage)
    plan = LMDP.plan(bound; backend)
    @test LMDP._logical_lowering_entries(plan.lowering)[2].executor.layout isa
        LMDP._DirectIdentityUniqueLayout
    prepared = LMDP.prepare(plan)
    wait(LMDP.execute!(prepared; parameters = (count = Int32(3),)))
    @test preserved_storage == Int32[1, 90, 3, 90]
    @test filled_storage == Float32[1, -4, 3, -4]

    preserved_storage .= Int32(80)
    filled_storage .= 80.0f0
    receipt = LMDP.execute!(prepared; parameters = (count = Int32(5),))
    @test_throws LMDP.LocalMathValidationError wait(receipt)
    @test preserved_storage == fill(Int32(80), 4)
    @test filled_storage == fill(80.0f0, 4)
end

@testset "optional indexed samples qualify without weakening strict keys" begin
    source = LMDP.Space(DirectPointwiseNode, 3)
    codomain = LMDP.Space(DirectPointwiseNode, 3)
    keys = LMDP.Field(source, Int32)
    values = LMDP.Field(codomain, Int32)
    output = LMDP.Field(source, Int32)
    identity = LMDP.IdentityRelation(source)

    function indexed_law(relation)
        access = LMDP.Access(values, relation; required = false)
        publication = _direct_pointwise_publication(
            output, identity, :value, LMDP.Unique(Int32))
        return LMDP.LocalLaw(LMDP.Stage(source, (values = access,),
            (publication,), LMDP.Evaluator(OptionalIndexEvaluator()),
            LMDP.Control(), LMDP.SourceOrigin(:direct_pointwise, 4)))
    end

    optional = LMDP.IndexRelation(keys => codomain; optional = true)
    optional_storage = fill(Int32(0), 3)
    optional_bound = _direct_pointwise_bound(indexed_law(optional), (
        keys => Int32[2, 0, 3],
        values => Int32[10, 20, 30],
        output => optional_storage,
    ), (identity, optional))
    backend = LMDP.KernelAbstractions.get_backend(optional_storage)
    optional_plan = LMDP.plan(optional_bound; backend)
    @test LMDP._logical_lowering_entries(
        optional_plan.lowering)[1].executor.layout isa
        LMDP._DirectIdentityUniqueLayout
    wait(LMDP.execute!(LMDP.prepare(optional_plan)))
    @test optional_storage == Int32[20, -1, 30]

    strict = LMDP.IndexRelation(keys => codomain; optional = false)
    strict_bound = _direct_pointwise_bound(indexed_law(strict), (
        keys => Int32[2, 1, 3],
        values => Int32[10, 20, 30],
        output => fill(Int32(0), 3),
    ), (identity, strict))
    strict_plan = LMDP.plan(strict_bound; backend)
    @test LMDP._logical_lowering_entries(
        strict_plan.lowering)[1].executor.layout isa
        LMDP._GroupedCandidateLayout
end

@testset "pointwise lowering rejects off-item destination reads" begin
    source = LMDP.Space(DirectPointwiseNode, 3)
    output = LMDP.Field(source, Int32)
    identity = LMDP.IdentityRelation(source)
    shifted = LMDP.AffineRelation(source => source; offsets = ((1,),))
    stage = LMDP.Stage(source,
        (output = LMDP.Access(output, shifted; required = false),),
        (_direct_pointwise_publication(
            output, identity, :value, LMDP.Unique(Int32)),),
        LMDP.Evaluator(OptionalIndexEvaluator()), LMDP.Control(),
        LMDP.SourceOrigin(:direct_pointwise_alias, 1))
    storage = Int32[1, 2, 3]
    bound = _direct_pointwise_bound(LMDP.LocalLaw(stage),
        (output => storage,), (identity, shifted))
    backend = LMDP.KernelAbstractions.get_backend(storage)
    plan = LMDP.plan(bound; backend)
    @test LMDP._logical_lowering_entries(plan.lowering)[1].executor.layout isa
        LMDP._GroupedCandidateLayout
end

@testset "total affine reads retain the one-pass pointwise path" begin
    source = LMDP.Space(DirectPointwiseNode, 3)
    codomain = LMDP.Space(DirectPointwiseNode, 5)
    input = LMDP.Field(codomain, Int32)
    output = LMDP.Field(source, Int32)
    identity = LMDP.IdentityRelation(source)
    interior = LMDP.AffineRelation(
        source => codomain; offsets = ((1,),))
    stage = LMDP.Stage(source,
        (input = LMDP.Access(input, interior; required = true),),
        (_direct_pointwise_publication(
            output, identity, :value, LMDP.Unique(Int32)),),
        LMDP.Evaluator(RequiredReadEvaluator()), LMDP.Control(),
        LMDP.SourceOrigin(:direct_pointwise_affine, 1))
    output_storage = zeros(Int32, 3)
    bound = _direct_pointwise_bound(LMDP.LocalLaw(stage), (
        input => Int32[10, 20, 30, 40, 50],
        output => output_storage,
    ), (identity, interior))
    backend = LMDP.KernelAbstractions.get_backend(output_storage)
    plan = LMDP.plan(bound; backend)
    @test LMDP._logical_lowering_entries(plan.lowering)[1].executor.layout isa
        LMDP._DirectIdentityUniqueLayout
    wait(LMDP.execute!(LMDP.prepare(plan)))
    @test output_storage == Int32[20, 30, 40]
end
