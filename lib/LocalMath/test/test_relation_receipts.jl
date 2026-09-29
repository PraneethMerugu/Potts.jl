using Test
import LocalMath
const LWRR = LocalMath

struct RelationReceiptNode end
struct RelationReceiptEvaluator end
@inline (::RelationReceiptEvaluator)(item::Int32, reads, parameters) =
    (value = LWRR.UniqueValue(Int32(item)),)
struct RelationReceiptSuccessor end
@inline (::RelationReceiptSuccessor)(item::Int32, reads, parameters) =
    (next = LWRR.UniqueValue(Int32(100) + item),)

@testset "Stage descriptor closure is the sole receipt dependency authority" begin
    nodes = LWRR.Space(RelationReceiptNode, 2)
    input = LWRR.Field(nodes, Int32)
    output = LWRR.Field(nodes, Int32)
    mask = LWRR.Field(nodes, Bool)
    packed = LWRR.PackedRelation(
        nodes => nodes; degree_bound = 1, capacity = 2)
    masked_access = LWRR.MaskedRelation(packed, mask)
    subset = LWRR.MaskedRelation(LWRR.IdentityRelation(nodes), mask)
    stage = LWRR.Stage(nodes,
        (input = LWRR.Access(input, masked_access),),
        (LWRR.Publication((LWRR.FieldPublication(output, packed,
            LWRR.PublicationValue(:value)),), LWRR.Unique(Int32)),),
        LWRR.Evaluator(RelationReceiptEvaluator()),
        LWRR.Control(; subset = LWRR._SubsetSelection(subset)),
        LWRR.SourceOrigin(:relation_receipts, 1))
    generation = LWRR._RelationContentGenerationRef(UInt64[3], 1)
    status = LWRR._RelationStatusRef(Int32[0], UInt64[3], 1)
    packed_storage = (active = Bool[true, true],
        endpoints = reshape(Int32[1, 2], 1, 2),
        offsets = Int32[1], counts = Int32[2])
    binding = LWRR._StructuralBinding((
        LWRR._field_storage_binding(input, Int32[1, 2]),
        LWRR._field_storage_binding(output, zeros(Int32, 2)),
        LWRR._field_storage_binding(mask, Bool[true, false]),
    ), (
        LWRR._relation_storage_binding(packed, packed_storage;
            generation, status),
        LWRR._relation_storage_binding(masked_access),
        LWRR._relation_storage_binding(subset),
        LWRR._relation_storage_binding(subset.representation.base),
    ))
    bound = LWRR._bind_law(LWRR.LocalLaw(stage), binding)
    validated_bound = LWRR._validate_bound_law(bound)
    dependencies = LWRR._stage_dynamic_relation_dependencies(
        validated_bound.binding, stage)
    @test length(dependencies) == 1
    @test only(dependencies).generation === generation
    @test only(dependencies).status === status
end

@testset "PackedRelation generation declarations require device content validation" begin
    nodes = LWRR.Space(RelationReceiptNode, 2)
    output = LWRR.Field(nodes, Int32)
    packed = LWRR.PackedRelation(
        nodes => nodes; degree_bound = 1, capacity = 2)
    stage = LWRR.Stage(nodes, NamedTuple(),
        (LWRR.Publication((LWRR.FieldPublication(output, packed,
            LWRR.PublicationValue(:value)),), LWRR.Unique(Int32;
                coverage = LWRR.PartialCoverage(),
                onempty = LWRR.FillEmpty(Int32(0)))),),
        LWRR.Evaluator(RelationReceiptEvaluator()), LWRR.Control(),
        LWRR.SourceOrigin(:packed_content_validation, 1))
    backend = LWRR.KernelAbstractions.CPU()

    function execute(storage)
        destination = fill(Int32(-9), 2)
        generation = UInt64[11]
        status = Int32[0]
        validated = UInt64[11] # Deliberately self-certified by the caller.
        binding = LWRR._StructuralBinding(
            (LWRR._field_storage_binding(output, destination),),
            (LWRR._relation_storage_binding(packed, storage;
                generation = LWRR._RelationContentGenerationRef(generation, 1),
                status = LWRR._RelationStatusRef(status, validated, 1)),))
        prepared = LWRR.prepare(LWRR.plan(LWRR._bind_law(
            LWRR.LocalLaw(stage), binding); backend))
        failure = try
            wait(LWRR.execute!(prepared))
            nothing
        catch error
            error
        end
        return (; destination, generation, status, validated, failure)
    end

    valid = execute((active = Bool[true, true],
        endpoints = reshape(Int32[1, 2], 1, 2),
        offsets = Int32[1], counts = Int32[2]))
    @test valid.failure === nothing
    @test valid.destination == Int32[1, 2]
    @test valid.validated == valid.generation == UInt64[11]

    inactive = execute((active = Bool[true, false],
        endpoints = reshape(Int32[1, typemax(Int32)], 1, 2),
        offsets = Int32[1], counts = Int32[2]))
    @test inactive.failure === nothing
    @test inactive.destination == Int32[1, 0]

    invalid_cases = (
        (active = Bool[true, true], endpoints = reshape(Int32[1, 2], 1, 2),
            offsets = Int32[1], counts = Int32[3]),
        (active = Bool[true, true], endpoints = reshape(Int32[1, 2], 1, 2),
            offsets = Int32[0], counts = Int32[2]),
        (active = Bool[true, true], endpoints = reshape(Int32[1, 2], 1, 2),
            offsets = Int32[2], counts = Int32[2]),
        (active = Bool[true, true], endpoints = reshape(Int32[1, 3], 1, 2),
            offsets = Int32[1], counts = Int32[2]),
    )
    for storage in invalid_cases
        result = execute(storage)
        @test result.failure isa LWRR.LocalMathValidationError
        @test result.failure.contract === :runtime_stage_validation
        @test result.destination == fill(Int32(-9), 2)
        @test result.status == Int32[1]
        @test result.validated == UInt64[0]
    end
end

@testset "Stage lifecycle receipts gate publication and successors" begin
    nodes = LWRR.Space(RelationReceiptNode, 2)
    first = LWRR.Field(nodes, Int32)
    second = LWRR.Field(nodes, Int32)
    packed = LWRR.PackedRelation(
        nodes => nodes; degree_bound = 1, capacity = 2)
    identity = LWRR.IdentityRelation(nodes)
    first_stage = LWRR.Stage(nodes, NamedTuple(),
        (LWRR.Publication((LWRR.FieldPublication(first, packed,
            LWRR.PublicationValue(:value)),), LWRR.Unique(Int32)),),
        LWRR.Evaluator(RelationReceiptEvaluator()), LWRR.Control(),
        LWRR.SourceOrigin(:relation_receipts, 2))
    second_stage = LWRR.Stage(nodes, NamedTuple(),
        (LWRR.Publication((LWRR.FieldPublication(second, identity,
            LWRR.PublicationValue(:next)),), LWRR.Unique(Int32)),),
        LWRR.Evaluator(RelationReceiptSuccessor()), LWRR.Control(),
        LWRR.SourceOrigin(:relation_receipts, 3))
    work = LWRR.sequence(LWRR.LocalLaw(first_stage),
        LWRR.LocalLaw(second_stage))
    first_storage = fill(Int32(-1), 2)
    second_storage = fill(Int32(-2), 2)
    generations = UInt64[7]
    validated_generations = UInt64[7]
    statuses = Int32[4]
    binding = LWRR._StructuralBinding((
        LWRR._field_storage_binding(first, first_storage),
        LWRR._field_storage_binding(second, second_storage),
    ), (
        LWRR._relation_storage_binding(packed,
            (active = Bool[true, true],
             endpoints = reshape(Int32[1, 2], 1, 2),
             offsets = Int32[1], counts = Int32[2]);
            generation = LWRR._RelationContentGenerationRef(generations, 1),
            status = LWRR._RelationStatusRef(
                statuses, validated_generations, 1)),
        LWRR._relation_storage_binding(identity),
    ))
    bound = LWRR._bind_law(work, binding)
    backend = LWRR.KernelAbstractions.get_backend(first_storage)

    self_certified = LWRR.prepare(LWRR.plan(bound; backend))
    wait(LWRR.execute!(self_certified))
    phases = LWRR.inspect(
        self_certified).stages[1].planning.phases
    @test only(filter(phase -> phase.kind === :relationship_validation,
        phases)).count == 2
    @test only(filter(phase -> phase.kind === :relationship_receipt,
        phases)).count == 1
    @test statuses == Int32[0]
    @test validated_generations == generations == UInt64[7]
    @test first_storage == Int32[1, 2]
    @test second_storage == Int32[101, 102]
    @test only(self_certified.runtime.launches[1].guard.receipts) == UInt64(7)

    statuses[1] = Int32(0)
    generations[1] = UInt64(8)
    validated_generations[1] = UInt64(8)
    valid = LWRR.prepare(LWRR.plan(bound; backend))
    wait(LWRR.execute!(valid))
    @test first_storage == Int32[1, 2]
    @test second_storage == Int32[101, 102]
    @test only(valid.runtime.launches[1].guard.receipts) == UInt64(8)
end

@testset "relation receipts qualify success by generation and lease" begin
    generations = UInt64[5]
    validated_generations = UInt64[5]
    statuses = Int32[0]
    dependency = LWRR._StageRelationDependency(
        LWRR._RelationContentGenerationRef(generations, 1),
        LWRR._RelationStatusRef(statuses, validated_generations, 1),
        LWRR._NoRelationContentValidator(),
    )
    receipts = zeros(UInt64, 1, 2)
    validation = zeros(UInt32, LWRR._VALIDATION_STATUS_FIELDS, 2)
    program_validation = zeros(UInt32, LWRR._VALIDATION_STATUS_FIELDS, 2)
    program_target = LWRR._ProgramValidationTarget(program_validation, Int32(1))
    guard = LWRR._StageRelationGuard((dependency,), receipts)
    backend = LWRR.KernelAbstractions.get_backend(receipts)

    LWRR._launch_stage_relation_receipt!(
        backend, guard, validation, program_target, Int32(1))
    LWRR.KernelAbstractions.synchronize(backend)
    @test receipts[:, 1] == UInt64[5]
    @test LWRR._stage_relation_guard_succeeded(guard, Int32(1))

    # A prior zero status is not a reusable success receipt after content moves.
    generations[1] = UInt64(6)
    @test !LWRR._stage_relation_guard_succeeded(guard, Int32(1))
    @test LWRR._candidate_prefix_succeeded((guard,), Int32(1)) == false

    LWRR._launch_stage_relation_receipt!(
        backend, guard, validation, program_target, Int32(2))
    LWRR.KernelAbstractions.synchronize(backend)
    @test receipts[:, 2] == UInt64[6]
    @test !LWRR._stage_relation_guard_succeeded(guard, Int32(2))
    validated_generations[1] = UInt64(6)
    LWRR._launch_stage_relation_receipt!(
        backend, guard, validation, program_target, Int32(2))
    LWRR.KernelAbstractions.synchronize(backend)
    @test LWRR._stage_relation_guard_succeeded(guard, Int32(2))
    @test !LWRR._stage_relation_guard_succeeded(guard, Int32(1))

    statuses[1] = Int32(9)
    LWRR._launch_stage_relation_receipt!(
        backend, guard, validation, program_target, Int32(1))
    LWRR.KernelAbstractions.synchronize(backend)
    @test receipts[:, 1] == UInt64[6]
    @test !LWRR._stage_relation_guard_succeeded(guard, Int32(1))
    @test validation[LWRR._VALIDATION_FAILURE_CLASS, 1] ==
        UInt32(LWRR._CANDIDATE_STATUS_RELATION)

    # The same typed prefix combines content freshness with prior Stage status.
    statuses[1] = Int32(0)
    predecessor = zeros(UInt32, LWRR._VALIDATION_STATUS_FIELDS, 2)
    predecessor[LWRR._VALIDATION_FAILURE_CLASS, 2] = UInt32(1)
    @test !LWRR._candidate_prefix_succeeded(
        (guard, predecessor), Int32(2))
end

@testset "status-only relation dependencies use the same guard" begin
    statuses = Int32[0]
    dependency = LWRR._StageRelationDependency(
        nothing, LWRR._RelationStatusRef(statuses, nothing, 1),
        LWRR._NoRelationContentValidator())
    receipts = fill(typemax(UInt64), 1, 1)
    validation = zeros(UInt32, LWRR._VALIDATION_STATUS_FIELDS, 1)
    program_validation = zeros(UInt32, LWRR._VALIDATION_STATUS_FIELDS, 1)
    program_target = LWRR._ProgramValidationTarget(program_validation, Int32(1))
    guard = LWRR._StageRelationGuard((dependency,), receipts)
    backend = LWRR.KernelAbstractions.get_backend(receipts)
    LWRR._launch_stage_relation_receipt!(
        backend, guard, validation, program_target, Int32(1))
    LWRR.KernelAbstractions.synchronize(backend)
    @test receipts[1, 1] == UInt64(0)
    @test LWRR._stage_relation_guard_succeeded(guard, Int32(1))
    statuses[1] = Int32(1)
    @test !LWRR._stage_relation_guard_succeeded(guard, Int32(1))
end

@testset "inverse relation content validates through KernelAbstractions" begin
    generations = UInt64[1]
    statuses = Int32[0]
    validated_generations = UInt64[0]
    generation = LWRR._RelationContentGenerationRef(generations, 1)
    status = LWRR._RelationStatusRef(statuses, validated_generations, 1)
    backend = LWRR.KernelAbstractions.get_backend(statuses)

    incidents = reshape(Int32[1, 3], 1, 2)
    lane = LWRR._InverseLaneContentValidator(
        Int32[1, 1], incidents, Int32(2), Int32(2), Int32(1))
    lane_dependency = LWRR._StageRelationDependency(
        generation, status, lane)
    LWRR._launch_relation_content_validation!(backend, lane_dependency)
    LWRR.KernelAbstractions.synchronize(backend)
    @test statuses[1] != 0
    @test validated_generations[1] == 0

    incidents[1, 2] = Int32(2)
    generations[1] = UInt64(2)
    LWRR._launch_relation_content_validation!(backend, lane_dependency)
    LWRR.KernelAbstractions.synchronize(backend)
    @test statuses[1] == 0
    @test validated_generations[1] == UInt64(2)

    grouped = LWRR._GroupedInverseContentValidator(
        Int32[1, 3, 2], Int32[1, 2],
        Int32(2), Int32(2), Int32(2))
    grouped_dependency = LWRR._StageRelationDependency(
        generation, status, grouped)
    generations[1] = UInt64(3)
    LWRR._launch_relation_content_validation!(backend, grouped_dependency)
    LWRR.KernelAbstractions.synchronize(backend)
    @test statuses[1] != 0
    @test validated_generations[1] == 0
end

@testset "ghost mappings validate through KernelAbstractions" begin
    mapping = Int32[1, 0, 0, 0, 0, 3]
    generations = UInt64[4]
    statuses = Int32[0]
    validated_generations = UInt64[0]
    dependency = LWRR._StageRelationDependency(
        LWRR._RelationContentGenerationRef(generations, 1),
        LWRR._RelationStatusRef(statuses, validated_generations, 1),
        LWRR._GhostRelationContentValidator(
            mapping, Int32(length(mapping)), Int32(2)))
    backend = LWRR.KernelAbstractions.get_backend(mapping)

    LWRR._launch_relation_content_validation!(backend, dependency)
    LWRR.KernelAbstractions.synchronize(backend)
    @test statuses[1] != 0
    @test validated_generations[1] == 0

    mapping[end] = Int32(2)
    generations[1] = UInt64(5)
    LWRR._launch_relation_content_validation!(backend, dependency)
    LWRR.KernelAbstractions.synchronize(backend)
    @test statuses[1] == 0
    @test validated_generations[1] == UInt64(5)

    mapping[1] = Int32(-1)
    generations[1] = UInt64(6)
    LWRR._launch_relation_content_validation!(backend, dependency)
    LWRR.KernelAbstractions.synchronize(backend)
    @test statuses[1] != 0
    @test validated_generations[1] == 0
end

@testset "relation failures preserve relation rather than publication provenance" begin
    relation_identity = LWRR.UUIDs.uuid4()
    context = LWRR._StageEntryContext(
        LWRR.SourceOrigin(:relation_receipts, 40), (),
        (relation_identity,), :candidate)
    words = zeros(UInt32, LWRR._VALIDATION_STATUS_FIELDS, 1)
    words[LWRR._VALIDATION_FAILURE_CLASS, 1] =
        UInt32(LWRR._CANDIDATE_STATUS_RELATION)
    words[LWRR._VALIDATION_CONTEXT_INDEX, 1] = UInt32(1)
    words[LWRR._VALIDATION_STAGE_INDEX, 1] = reinterpret(UInt32, Int32(3))
    status = LWRR._ValidatedPublicationStatus(
        words, words, context, :unrelated_publication, 3)

    error = LWRR._validated_publication_error(status, 1)
    @test error isa LWRR.LocalMathValidationError
    @test error.port === nothing
    @test error.actual.relation == relation_identity
    @test error.actual.relation_dependency == 1
    @test error.actual.stage == 3
    @test error.origin == context.origin
end
