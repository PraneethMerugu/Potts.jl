using Test
import LocalMath
const LMR = LocalMath

struct ReduceStageNode end
struct DecimalFold end
@inline (::DecimalFold)(left::Int32, right::Int32) = left * Int32(10) + right
struct ItemContribution end
@inline (::ItemContribution)(item::Int32, reads, parameters) =
    (value = LMR.Contribution(item),)
struct FloatContribution end
@inline (::FloatContribution)(item::Int32, reads, parameters) =
    (value = LMR.Contribution(Float32(item)),)
struct TwoLaneContribution end
@inline (::TwoLaneContribution)(item::Int32, reads, parameters) = (
    value = (LMR.Contribution(item),
        LMR.Contribution(item + Int32(10))),)
struct MixedConflictEvaluator end
@inline (::MixedConflictEvaluator)(item::Int32, reads, parameters) = (
    unique = LMR.UniqueValue(item),
    reduction = LMR.Contribution(item),
)

function _reduce_test_stage(source, output, relation, law, evaluator;
        role = :value, control = LMR.Control())
    publication = LMR.Publication((LMR.FieldPublication(
        output, relation, LMR.PublicationValue(role)),), law)
    return LMR.Stage(source, NamedTuple(), (publication,),
        LMR.Evaluator(evaluator), control,
        LMR.SourceOrigin(:reduce_stage_test, 1))
end

function _prepare_test_candidate(bound, index = 1; parameters = ())
    backend = LMR.KernelAbstractions.get_backend(
        first(bound.binding.fields).storage)
    index == 1 || throw(ArgumentError("the public Stage lifecycle plans all stages"))
    return LMR.prepare(LMR.plan(bound; backend))
end

function _run_test_candidate!(prepared)
    event = LMR.execute!(prepared)
    try
        wait(event)
    catch error
        error isa LMR.LocalMathValidationError || rethrow()
    end
    return only(prepared.runtime.launches).stage
end

@testset "canonical Reduce is the exact item-major lane-minor left fold" begin
    source = LMR.Space(ReduceStageNode, 3)
    destination = LMR.Space(ReduceStageNode, 2)
    output = LMR.Field(destination, Int32)
    relation = LMR.FixedRelation(source => destination; degree = 2)
    law = LMR.Reduce(Int32, DecimalFold(); maximum = 2,
        seed = LMR.IdentitySeed(Int32(0)),
        order = LMR.CanonicalLeftFold())
    stage = _reduce_test_stage(
        source, output, relation, law, TwoLaneContribution())
    storage = fill(Int32(-1), 2)
    endpoints = reshape(Int32[1, 2, 1, 2, 1, 2], 2, 3)
    bound = LMR._bind_law(LMR.LocalLaw(stage), LMR._StructuralBinding(
        (LMR._field_storage_binding(output, storage),),
        (LMR._relation_storage_binding(relation, (
            endpoints, counts = fill(Int32(2), 3))),)))
    prepared = _run_test_candidate!(_prepare_test_candidate(bound))

    # Destination 1 receives (1, 2, 3); destination 2 receives (11, 12, 13).
    @test storage == Int32[123, 1233]
    @test only(Array(prepared.execution.status)) ==
        LMR._CANDIDATE_STATUS_SUCCESS
end

@testset "canonical Reduce seed and empty-destination semantics" begin
    source = LMR.Space(ReduceStageNode, 2)
    destination = LMR.Space(ReduceStageNode, 3)
    output = LMR.Field(destination, Int32)
    relation = LMR.FixedRelation(source => destination; degree = 1)
    endpoints = reshape(Int32[1, 2], 1, 2)
    relation_binding = LMR._relation_storage_binding(relation, (
        endpoints, counts = fill(Int32(1), 2)))

    identity_law = LMR.Reduce(Int32, +;
        seed = LMR.IdentitySeed(Int32(0)),
        order = LMR.CanonicalLeftFold())
    identity_stage = _reduce_test_stage(
        source, output, relation, identity_law, ItemContribution())
    identity_storage = fill(Int32(99), 3)
    identity_bound = LMR._bind_law(
        LMR.LocalLaw(identity_stage), LMR._StructuralBinding(
            (LMR._field_storage_binding(output, identity_storage),),
            (relation_binding,)))
    _run_test_candidate!(_prepare_test_candidate(identity_bound))
    @test identity_storage == Int32[1, 2, 0]

    existing_law = LMR.Reduce(Int32, +;
        seed = LMR.ExistingSeed(),
        order = LMR.CanonicalLeftFold())
    existing_stage = _reduce_test_stage(
        source, output, relation, existing_law, ItemContribution())
    existing_storage = Int32[10, 20, 30]
    existing_bound = LMR._bind_law(
        LMR.LocalLaw(existing_stage), LMR._StructuralBinding(
            (LMR._field_storage_binding(output, existing_storage),),
            (relation_binding,)))
    _run_test_candidate!(_prepare_test_candidate(existing_bound))
    @test existing_storage == Int32[11, 22, 30]
end

@testset "relaxed atomic Reduce remains privately buffered" begin
    n = 513
    destination_count = 17
    source = LMR.Space(ReduceStageNode, n)
    destination = LMR.Space(ReduceStageNode, destination_count)
    output = LMR.Field(destination, Int32)
    relation = LMR.FixedRelation(source => destination; degree = 1)
    endpoints = reshape(Int32[mod1(37 * item, destination_count)
        for item in 1:n], 1, n)
    law = LMR.Reduce(Int32, +;
        seed = LMR.IdentitySeed(Int32(0)),
        order = LMR.RelaxedAtomic())
    stage = _reduce_test_stage(
        source, output, relation, law, ItemContribution())
    storage = fill(Int32(-1), destination_count)
    bound = LMR._bind_law(LMR.LocalLaw(stage), LMR._StructuralBinding(
        (LMR._field_storage_binding(output, storage),),
        (LMR._relation_storage_binding(relation, (
            endpoints, counts = fill(Int32(1), n))),)))
    prepared = _run_test_candidate!(_prepare_test_candidate(bound))
    expected = Int32[sum(Int32(item) for item in 1:n
        if endpoints[item] == destination_index)
        for destination_index in 1:destination_count]
    @test storage == expected
    @test only(Array(prepared.execution.status)) ==
        LMR._CANDIDATE_STATUS_SUCCESS
end

@testset "one stage status guards heterogeneous candidate publications" begin
    source = LMR.Space(ReduceStageNode, 2)
    one = LMR.Space(ReduceStageNode, 1)
    unique_output = LMR.Field(one, Int32)
    reduce_output = LMR.Field(source, Int32)
    collision = LMR.FixedRelation(source => one; degree = 1)
    identity = LMR.IdentityRelation(source)
    unique_publication = LMR.Publication((LMR.FieldPublication(
        unique_output, collision, LMR.PublicationValue(:unique)),),
        LMR.Unique(Int32))
    reduce_publication = LMR.Publication((LMR.FieldPublication(
        reduce_output, identity, LMR.PublicationValue(:reduction)),),
        LMR.Reduce(Int32, +;
            seed = LMR.IdentitySeed(Int32(0)),
            order = LMR.CanonicalLeftFold()))
    stage = LMR.Stage(source, NamedTuple(),
        (unique_publication, reduce_publication),
        LMR.Evaluator(MixedConflictEvaluator()), LMR.Control(),
        LMR.SourceOrigin(:reduce_stage_test, 2))
    unique_storage = Int32[71]
    reduce_storage = Int32[81, 82]
    bound = LMR._bind_law(LMR.LocalLaw(stage), LMR._StructuralBinding(
        (
            LMR._field_storage_binding(unique_output, unique_storage),
            LMR._field_storage_binding(reduce_output, reduce_storage),
        ),
        (
            LMR._relation_storage_binding(collision, (
                endpoints = reshape(Int32[1, 1], 1, 2),
                counts = fill(Int32(1), 2))),
            LMR._relation_storage_binding(identity),
        )))
    prepared = _run_test_candidate!(_prepare_test_candidate(bound))
    @test unique_storage == Int32[71]
    @test reduce_storage == Int32[81, 82]
    @test only(Array(prepared.execution.status)) ==
        LMR._CANDIDATE_STATUS_CONFLICT
end

@testset "a closed heterogeneous candidate stage is an exact no-op" begin
    source = LMR.Space(ReduceStageNode, 2)
    unique_output = LMR.Field(source, Int32)
    reduce_output = LMR.Field(source, Int32)
    identity = LMR.IdentityRelation(source)
    unique_publication = LMR.Publication((LMR.FieldPublication(
        unique_output, identity, LMR.PublicationValue(:unique)),),
        LMR.Unique(Int32))
    reduce_publication = LMR.Publication((LMR.FieldPublication(
        reduce_output, identity, LMR.PublicationValue(:reduction)),),
        LMR.Reduce(Int32, +;
            seed = LMR.IdentitySeed(Int32(0)),
            order = LMR.RelaxedAtomic()))
    enabled = LMR.Parameter(:enabled, Bool)
    stage = LMR.Stage(source, NamedTuple(),
        (unique_publication, reduce_publication),
        LMR.Evaluator(MixedConflictEvaluator()),
        LMR.Control(; gate = LMR._ParameterGate(enabled)),
        LMR.SourceOrigin(:reduce_stage_test, 3))
    unique_storage = Int32[41, 42]
    reduce_storage = Int32[51, 52]
    bound = LMR._bind_law(LMR.LocalLaw(stage), LMR._StructuralBinding(
        (
            LMR._field_storage_binding(unique_output, unique_storage),
            LMR._field_storage_binding(reduce_output, reduce_storage),
        ), (LMR._relation_storage_binding(identity),)))
    prepared = _prepare_test_candidate(bound)
    wait(LMR.execute!(prepared; parameters = (; enabled = false)))
    @test unique_storage == Int32[41, 42]
    @test reduce_storage == Int32[51, 52]
end

@testset "relaxed atomic passes ignore heterogeneous non-atomic ports" begin
    source = LMR.Space(ReduceStageNode, 3)
    unique_output = LMR.Field(source, Int32)
    reduce_output = LMR.Field(source, Int32)
    identity = LMR.IdentityRelation(source)
    unique_publication = LMR.Publication((LMR.FieldPublication(
        unique_output, identity, LMR.PublicationValue(:unique)),),
        LMR.Unique(Int32))
    reduce_publication = LMR.Publication((LMR.FieldPublication(
        reduce_output, identity, LMR.PublicationValue(:reduction)),),
        LMR.Reduce(Int32, +;
            seed = LMR.IdentitySeed(Int32(0)),
            order = LMR.RelaxedAtomic()))
    stage = LMR.Stage(source, NamedTuple(),
        (unique_publication, reduce_publication),
        LMR.Evaluator(MixedConflictEvaluator()), LMR.Control(),
        LMR.SourceOrigin(:reduce_stage_test, 4))
    unique_storage = fill(Int32(-1), 3)
    reduce_storage = fill(Int32(-1), 3)
    bound = LMR._bind_law(LMR.LocalLaw(stage), LMR._StructuralBinding(
        (
            LMR._field_storage_binding(unique_output, unique_storage),
            LMR._field_storage_binding(reduce_output, reduce_storage),
        ), (LMR._relation_storage_binding(identity),)))
    _run_test_candidate!(_prepare_test_candidate(bound))
    @test unique_storage == Int32[1, 2, 3]
    @test reduce_storage == Int32[1, 2, 3]
end

@testset "candidate workspace authority rejects law specialization mismatch" begin
    source = LMR.Space(ReduceStageNode, 2)
    output = LMR.Field(source, Int32)
    identity = LMR.IdentityRelation(source)
    canonical_stage = _reduce_test_stage(source, output, identity,
        LMR.Reduce(Int32, +;
            seed = LMR.IdentitySeed(Int32(0)),
            order = LMR.CanonicalLeftFold()), ItemContribution())
    relaxed_stage = _reduce_test_stage(source, output, identity,
        LMR.Reduce(Int32, +;
            seed = LMR.IdentitySeed(Int32(0)),
            order = LMR.RelaxedAtomic()), ItemContribution())
    storage = zeros(Int32, 2)
    binding = LMR._StructuralBinding(
        (LMR._field_storage_binding(output, storage),),
        (LMR._relation_storage_binding(identity),))
    canonical_bound = LMR._bind_law(
        LMR.LocalLaw(canonical_stage), binding)
    relaxed_bound = LMR._bind_law(LMR.LocalLaw(relaxed_stage), binding)
    backend = LMR.KernelAbstractions.get_backend(storage)
    canonical_admission = _test_stage_admission(canonical_bound; backend)
    spec = LMR._candidate_stage_workspace_spec(canonical_admission.stage;
        path = (:stage, 1), name_prefix = :mismatched_candidate)
    authority = LMR._WorkspaceAuthority(spec.leaves, spec.template)
    tree = LMR._materialize_workspace(authority.template, authority,
        LMR._WorkspaceAllocator(backend))
    canonical_workspace = LMR._candidate_stage_workspace_from_tree(
        tree, spec, canonical_admission.stage)
    relaxed_admission = _test_stage_admission(relaxed_bound; backend)
    mismatch = try
        LMR._prepare_candidate_stage(
            relaxed_admission, canonical_workspace)
        nothing
    catch error
        error
    end
    @test mismatch isa LMR.LocalMathValidationError
    @test mismatch.contract == :candidate_workspace_specialization

    float_output = LMR.Field(source, Float32)
    float_stage = _reduce_test_stage(source, float_output, identity,
        LMR.Reduce(Float32, +;
            seed = LMR.IdentitySeed(0.0f0),
            order = LMR.CanonicalLeftFold()), FloatContribution())
    float_bound = LMR._bind_law(LMR.LocalLaw(float_stage),
        LMR._StructuralBinding(
            (LMR._field_storage_binding(
                float_output, zeros(Float32, 2)),),
            (LMR._relation_storage_binding(identity),)))
    float_admission = _test_stage_admission(float_bound; backend)
    type_mismatch = try
        LMR._prepare_candidate_stage(
            float_admission, canonical_workspace)
        nothing
    catch error
        error
    end
    @test type_mismatch isa LMR.LocalMathValidationError
    @test type_mismatch.contract == :candidate_workspace_specialization
end
