using Test
import LocalMath
const LMU = LocalMath

struct UniqueStageNode end
struct UniqueConstantEvaluator{T}; value::T; end
@inline (evaluator::UniqueConstantEvaluator)(item::Int32, reads, parameters) =
    (value = LMU.UniqueValue(evaluator.value),)
struct UniqueDualEvaluator end
@inline (::UniqueDualEvaluator)(item::Int32, reads, parameters) = (
    left = LMU.UniqueValue(Int32(1)),
    right = LMU.UniqueValue(Int32(2)),
)
struct UniqueTwoLaneEvaluator end
@inline (::UniqueTwoLaneEvaluator)(item::Int32, reads, parameters) = (
    value = (
        LMU.UniqueValue(Int32(item * 10 + 1)),
        LMU.UniqueValue(Int32(item * 10 + 2)),
    ),
)

function _unique_test_stage(source, output, relation, law, evaluator;
        accesses = NamedTuple(), control = LMU.Control())
    publication = LMU.Publication((LMU.FieldPublication(
        output, relation, LMU.PublicationValue(:value),
    ),), law)
    LMU.Stage(source, accesses, (publication,),
        LMU.Evaluator(evaluator), control,
        LMU.SourceOrigin(:unique_stage_test, 1))
end

function _prepare_test_unique(bound)
    backend = LMU._array_backend(first(bound.binding.fields).storage)
    return LMU.prepare(LMU.plan(bound; backend))
end

function _run_test_unique!(prepared; stage = 1)
    event = LMU.execute!(prepared)
    try
        wait(event)
    catch error
        error isa LMU.LocalMathValidationError || rethrow()
    end
    for launch in prepared.runtime.launches
        physical = launch.stage
        if physical isa LMU._DirectPointwiseSegmentPreparation
            stage in physical.logical_indices && return physical
        elseif stage == 1
            return physical
        end
    end
    throw(ArgumentError("no prepared launch contains logical stage $stage"))
end

@testset "closed Unique gate preserves destinations" begin
    source = LMU.Space(UniqueStageNode, 2)
    output = LMU.Field(source, Int32)
    identity = LMU.IdentityRelation(source)
    law = LMU.Unique(Int32;
        coverage = LMU.PartialCoverage(),
        onempty = LMU.FillEmpty(Int32(-9)))

    enabled = LMU.Parameter(:enabled, Bool)
    parameter_stage = _unique_test_stage(source, output, identity, law,
        UniqueConstantEvaluator(Int32(4));
        control = LMU.Control(; gate = LMU._ParameterGate(enabled)))
    parameter_storage = Int32[31, 32]
    parameter_bound = LMU._bind_law(LMU.LocalLaw(parameter_stage),
        LMU._StructuralBinding(
            (LMU._field_storage_binding(output, parameter_storage),),
            (LMU._relation_storage_binding(identity),)))
    backend = LMU.KernelAbstractions.get_backend(parameter_storage)
    parameter_prepared = _prepare_test_unique(parameter_bound)
    wait(LMU.execute!(parameter_prepared; parameters = (; enabled = false)))
    @test parameter_storage == Int32[31, 32]

    stale_relation = LMU.PackedRelation(
        source => source; degree_bound = 1, capacity = 2)
    stale_stage = _unique_test_stage(source, output, stale_relation, law,
        UniqueConstantEvaluator(Int32(8));
        control = LMU.Control(; gate = LMU._ParameterGate(enabled)))
    stale_storage = Int32[35, 36]
    stale_bound = LMU._bind_law(LMU.LocalLaw(stale_stage),
        LMU._StructuralBinding(
            (LMU._field_storage_binding(output, stale_storage),),
            (LMU._relation_storage_binding(stale_relation, (
                active = Bool[true, true],
                endpoints = reshape(Int32[1, 3], 1, 2),
                offsets = Int32[1], counts = Int32[2],
            );
                generation = LMU._RelationContentGenerationRef(UInt64[1], 1),
                status = LMU._RelationStatusRef(Int32[9], UInt64[0], 1)),)))
    stale_prepared = _prepare_test_unique(stale_bound)
    stale_event = LMU.execute!(stale_prepared; parameters = (; enabled = true))
    @test_throws LMU.LocalMathValidationError wait(stale_event)
    @test stale_storage == Int32[35, 36]

    gate_space = LMU.Space(UniqueStageNode, 1)
    gate = LMU.Field(gate_space, Bool)
    prefix = LMU.Field(gate_space, Int32)
    gate_identity = LMU.IdentityRelation(gate_space)
    gate_stage = _unique_test_stage(
        gate_space, gate, gate_identity, LMU.Unique(Bool),
        UniqueConstantEvaluator(false))
    prefix_stage = _unique_test_stage(
        gate_space, prefix, gate_identity, LMU.Unique(Int32),
        UniqueConstantEvaluator(Int32(999)))
    field_stage = _unique_test_stage(source, output, identity, law,
        UniqueConstantEvaluator(Int32(5));
        control = LMU.Control(;
            prefix = LMU._FieldPrefix(prefix),
            gate = LMU._FieldGate(gate)))
    field_storage = Int32[41, 42]
    field_work = LMU.sequence(
        LMU.LocalLaw(prefix_stage), LMU.LocalLaw(gate_stage),
        LMU.LocalLaw(field_stage))
    field_bound = LMU._bind_law(field_work,
        LMU._StructuralBinding((
            LMU._field_storage_binding(output, field_storage),
            LMU._field_storage_binding(gate, Bool[false]),
            LMU._field_storage_binding(prefix, Int32[999]),
        ), (
            LMU._relation_storage_binding(gate_identity),
            LMU._relation_storage_binding(identity),
        )))
    field_prepared = _run_test_unique!(_prepare_test_unique(field_bound); stage = 3)
    @test field_storage == Int32[41, 42]
    @test field_prepared isa LMU._DirectPointwiseSegmentPreparation
end


@testset "Unique has exact static relation lanes" begin
    source = LMU.Space(UniqueStageNode, 2)
    destination = LMU.Space(UniqueStageNode, 4)
    output = LMU.Field(destination, Int32)
    relation = LMU.FixedRelation(source => destination; degree = 2)
    stage = _unique_test_stage(source, output, relation,
        LMU.Unique(Int32; maximum = 2), UniqueTwoLaneEvaluator())
    storage = fill(Int32(-1), 4)
    bound = LMU._bind_law(LMU.LocalLaw(stage), LMU._StructuralBinding(
        (LMU._field_storage_binding(output, storage),),
        (LMU._relation_storage_binding(relation, (
            endpoints = reshape(Int32[1, 2, 3, 4], 2, 2),
            counts = Int32[2, 2],
        )),),
    ))
    backend = LMU.KernelAbstractions.get_backend(storage)
    prepared = _run_test_unique!(_prepare_test_unique(bound))
    @test storage == Int32[11, 12, 21, 22]
    @test only(Array(prepared.execution.status)) ==
        LMU._UNIQUE_STATUS_SUCCESS
end

@testset "Unique candidate storage admits reviewed wide records" begin
    source = LMU.Space(UniqueStageNode, 2)
    destination = LMU.Space(UniqueStageNode, 2)
    record = (Int32(1), Int32(2), Int32(3), 4.0, 5.0, UInt32(6), true)
    output = LMU.Field(destination, typeof(record))
    relation = LMU.FixedRelation(source => destination; degree = 1)
    stage = _unique_test_stage(source, output, relation,
        LMU.Unique(typeof(record)), UniqueConstantEvaluator(record))
    storage = LMU.StructArrays.StructArray(fill(record, 2))
    bound = LMU._bind_law(LMU.LocalLaw(stage), LMU._StructuralBinding(
        (LMU._field_storage_binding(output, storage),),
        (LMU._relation_storage_binding(relation, (
            endpoints = reshape(Int32[1, 2], 1, 2),
            counts = Int32[1, 1],
        )),),
    ))
    _run_test_unique!(_prepare_test_unique(bound))
    @test collect(storage) == fill(record, 2)
end

@testset "static relation borrowing and dynamic relation validation" begin
    source = LMU.Space(UniqueStageNode, 2)
    destination = LMU.Space(UniqueStageNode, 2)
    output = LMU.Field(destination, Int32)
    relation = LMU.FixedRelation(source => destination; degree = 1)
    stage = _unique_test_stage(source, output, relation,
        LMU.Unique(Int32), UniqueConstantEvaluator(Int32(7)))

    static_endpoints = reshape(Int32[1, 2], 1, 2)
    static_output = fill(Int32(-1), 2)
    static_bound = LMU._bind_law(LMU.LocalLaw(stage),
        LMU._StructuralBinding((
            LMU._field_storage_binding(output, static_output),), (
            LMU._relation_storage_binding(relation, (
                endpoints = static_endpoints, counts = Int32[1, 1])),)))
    static_prepared = _prepare_test_unique(static_bound)
    static_event = LMU.execute!(static_prepared)
    @test wait(static_event) === static_event
    @test static_output == fill(Int32(7), 2)

    dynamic_endpoints = reshape(Int32[1, 2], 1, 2)
    generations = UInt64[1]
    statuses = Int32[0]
    validated_generations = UInt64[0]
    dynamic_output = fill(Int32(-1), 2)
    dynamic_bound = LMU._bind_law(LMU.LocalLaw(stage),
        LMU._StructuralBinding((
            LMU._field_storage_binding(output, dynamic_output),), (
            LMU._relation_storage_binding(relation, (
                endpoints = dynamic_endpoints, counts = Int32[1, 1]);
                generation = LMU._RelationContentGenerationRef(
                    generations, 1),
                status = LMU._RelationStatusRef(
                    statuses, validated_generations, 1)),)))
    dynamic_prepared = _prepare_test_unique(dynamic_bound)
    dynamic_endpoints[1, 1] = Int32(3)
    generations[1] += UInt64(1)
    event = LMU.execute!(dynamic_prepared)
    @test_throws LMU.LocalMathValidationError wait(event)
    @test statuses[1] != 0
    @test validated_generations[1] == 0
    @test dynamic_output == fill(Int32(-1), 2)
end

@testset "buffered Unique conflict and empty semantics" begin
    source = LMU.Space(UniqueStageNode, 2)
    destination = LMU.Space(UniqueStageNode, 1)
    input = LMU.Field(source, Int32)
    output = LMU.Field(destination, Int32)
    identity = LMU.IdentityRelation(source)
    collision = LMU.FixedRelation(source => destination; degree = 1)
    stage = _unique_test_stage(
        source, output, collision, LMU.Unique(Int32),
        UniqueConstantEvaluator(Int32(7));
        accesses = (input = LMU.Access(input, identity),),
    )
    work = LMU.LocalLaw(stage)
    output_storage = Int32[91]
    bound = LMU._bind_law(work, LMU._StructuralBinding(
        (
            LMU._field_storage_binding(input, Int32[1, 2]),
            LMU._field_storage_binding(output, output_storage),
        ),
        (
            LMU._relation_storage_binding(identity),
            LMU._relation_storage_binding(collision, (
                endpoints = reshape(Int32[1, 1], 1, 2),
                counts = Int32[1, 1],
            )),
        ),
    ))
    backend = LMU.KernelAbstractions.get_backend(output_storage)
    plan = LMU.plan(bound; backend)
    phases = only(LMU.inspect(plan).planning.stage_phases)
    @test LMU._phase_count(phases) == 4
    @test map(phase -> phase.kind, phases) == (
        :candidate_reset,
        :candidate_evaluate,
        :candidate_validate,
        :candidate_finalize_publish,
    )
    @test all(phase -> !startswith(String(phase.kind),
        "destination_grouping_"), phases)
    prepared = _run_test_unique!(LMU.prepare(plan))
    @test output_storage == Int32[91]
    @test only(Array(prepared.execution.status)) ==
        LMU._UNIQUE_STATUS_CONFLICT
    @test Array(prepared.validation)[:, 1] == UInt32[
        LMU._UNIQUE_STATUS_CONFLICT, 1, 1, 2, 1, 0]

    masked_output = LMU.Field(source, Int32)
    mask = LMU.Field(source, Bool)
    partial = LMU.Unique(Int32;
        coverage = LMU.PartialCoverage(),
        onempty = LMU.FillEmpty(Int32(-4)))
    masked_stage = _unique_test_stage(
        source, masked_output, identity, partial,
        UniqueConstantEvaluator(Int32(5));
        control = LMU.Control(; mask = LMU._MaskSelection(mask)),
    )
    masked_work = LMU.LocalLaw(masked_stage)
    masked_storage = Int32[71, 72]
    masked_bound = LMU._bind_law(masked_work, LMU._StructuralBinding(
        (
            LMU._field_storage_binding(masked_output, masked_storage),
            LMU._field_storage_binding(mask, Bool[true, false]),
        ),
        (LMU._relation_storage_binding(identity),),
    ))
    masked_prepared = _run_test_unique!(_prepare_test_unique(masked_bound))
    @test masked_storage == Int32[5, -4]
    @test masked_prepared isa LMU._DirectPointwiseSegmentPreparation

    total_stage = _unique_test_stage(source, masked_output, identity,
        LMU.Unique(Int32;
            coverage = LMU.TotalCoverage(),
            onempty = LMU.UnreachableEmpty()),
        UniqueConstantEvaluator(Int32(6));
        control = LMU.Control(; mask = LMU._MaskSelection(mask)))
    total_storage = Int32[81, 82]
    total_bound = LMU._bind_law(LMU.LocalLaw(total_stage),
        LMU._StructuralBinding((
            LMU._field_storage_binding(masked_output, total_storage),
            LMU._field_storage_binding(mask, Bool[true, false]),
        ), (LMU._relation_storage_binding(identity),)))
    total_prepared = _run_test_unique!(_prepare_test_unique(total_bound))
    @test total_storage == Int32[81, 82]
    @test Array(total_prepared.validation)[:, 1] == UInt32[
        LMU._UNIQUE_STATUS_COVERAGE, 1, 2, 0, 0, 0]
end


@testset "Unique has one explicit destination authority" begin
    source = LMU.Space(UniqueStageNode, 2)
    output = LMU.Field(source, Int32)
    other = LMU.Field(source, Int32)
    relation = LMU.IdentityRelation(source)
    law = LMU.Unique(Int32)
    component(field, role) = LMU.FieldPublication(
        field, relation, LMU.PublicationValue(role))
    left = LMU.Publication((component(output, :left),), law)
    repeated = LMU.Publication((component(output, :right),), law)
    duplicate = try
        LMU.Stage(source, NamedTuple(), (left, repeated),
            LMU.Evaluator(UniqueDualEvaluator()), LMU.Control(),
            LMU.SourceOrigin(:unique_stage_test, 2))
        nothing
    catch error
        error
    end
    @test duplicate isa LMU.LocalMathValidationError
    @test duplicate.contract == :stage_publication_field_uniqueness

    right = LMU.Publication((component(other, :right),), law)
    stage = LMU.Stage(source, NamedTuple(), (left, right),
        LMU.Evaluator(UniqueDualEvaluator()), LMU.Control(),
        LMU.SourceOrigin(:unique_stage_test, 3))
    shared = zeros(Int32, 2)
    aliased = try
        bound = LMU._bind_law(LMU.LocalLaw(stage), LMU._StructuralBinding(
            (
                LMU._field_storage_binding(output, shared),
                LMU._field_storage_binding(other, shared),
            ),
            (LMU._relation_storage_binding(relation),),
        ))
        LMU.plan(bound; backend = LMU.KernelAbstractions.CPU())
        nothing
    catch error
        error
    end
    @test aliased isa LMU.LocalMathValidationError
    @test aliased.contract == :field_storage_alias
end
