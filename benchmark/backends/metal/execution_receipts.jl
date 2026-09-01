using Test
using Metal
using LocalMath

const LMER = LocalMath

struct LMEReceiptNode end
struct LMEReceiptEvaluator{T}
    value::T
end
@inline (evaluator::LMEReceiptEvaluator)(item::Int32, reads, parameters) =
    (value = LMER.UniqueValue(evaluator.value + item),)

function execution_receipt_receipt_preparation(array_type, backend, value::Int32;
        dependency_arity::Int = 0, lease_capacity::Int = 1)
    space = LMER.Space(LMEReceiptNode, 2)
    output = LMER.Field(space, Int32)
    relation = LMER.IdentityRelation(space)
    publication = LMER.Publication((LMER.FieldPublication(
        output, relation, LMER.PublicationValue(:value)),),
        LMER.Unique(Int32))
    stage = LMER.Stage(space, NamedTuple(), (publication,),
        LMER.Evaluator(LMEReceiptEvaluator(value)), LMER.Control(),
        LMER.SourceOrigin(:execution_receipt_metal_receipt, 1))
    storage = array_type(fill(Int32(-1), 2))
    bound = LMER._bind_law(LMER.LocalLaw(stage),
        LMER._StructuralBinding(
            (LMER._field_storage_binding(output, storage),),
            (LMER._relation_storage_binding(relation),)))
    prepared = LMER.prepare(LMER.plan(bound; backend);
        dependency_arity, lease_capacity)
    return prepared, storage
end

function execution_receipt_conflict_preparation(backend)
    source = LMER.Space(LMEReceiptNode, 2)
    destination = LMER.Space(LMEReceiptNode, 1)
    output = LMER.Field(destination, Int32)
    relation = LMER.FixedRelation(source => destination; degree = 1)
    publication = LMER.Publication((LMER.FieldPublication(
        output, relation, LMER.PublicationValue(:value)),),
        LMER.Unique(Int32))
    stage = LMER.Stage(source, NamedTuple(), (publication,),
        LMER.Evaluator(LMEReceiptEvaluator(Int32(7))), LMER.Control(),
        LMER.SourceOrigin(:execution_receipt_metal_conflict, 1))
    storage = Metal.MtlArray(Int32[91])
    generation = Metal.MtlArray(UInt64[1])
    validated_generation = Metal.MtlArray(UInt64[1])
    relation_status = Metal.MtlArray(Int32[0])
    bound = LMER._bind_law(LMER.LocalLaw(stage),
        LMER._StructuralBinding(
            (LMER._field_storage_binding(output, storage),),
            (LMER._relation_storage_binding(relation, (
                endpoints = Metal.MtlArray(reshape(Int32[1, 1], 1, 2)),
                counts = Metal.MtlArray(Int32[1, 1]));
                generation = LMER._RelationContentGenerationRef(
                    generation, 1),
                status = LMER._RelationStatusRef(
                    relation_status, validated_generation, 1)),)))
    return LMER.prepare(LMER.plan(bound; backend)), storage
end

@testset "real-Metal execution receipts" begin
    backend = Metal.MetalBackend()
    roots = map(Int32[10, 20]) do value
        execution_receipt_receipt_preparation(Metal.MtlArray, backend, value)
    end
    unary = execution_receipt_receipt_preparation(Metal.MtlArray, backend, Int32(30);
        dependency_arity = 1)
    binary = execution_receipt_receipt_preparation(Metal.MtlArray, backend, Int32(40);
        dependency_arity = 2)
    quaternary = execution_receipt_receipt_preparation(Metal.MtlArray, backend, Int32(50);
        dependency_arity = 4)

    event_a = LMER.execute!(roots[1][1])
    event_b = LMER.execute!(roots[2][1])
    event_1 = LMER.execute!(unary[1]; dependencies = (event_a,))
    event_2 = LMER.execute!(binary[1]; dependencies = (event_a, event_1))
    event_4 = LMER.execute!(quaternary[1];
        dependencies = (event_a, event_b, event_1, event_2))
    wait(event_4)

    @test Array(quaternary[2]) == Int32[51, 52]
    @test LMER.ispending(event_a)
    synchronizations = LMER.inspect(
        quaternary[1]).realized.state.provider_scope_completions
    LMER.waitall(event_a, event_b, event_1, event_2)
    @test LMER.inspect(
        quaternary[1]).realized.state.provider_scope_completions ==
        synchronizations

    cpu_root, _ = execution_receipt_receipt_preparation(identity,
        LMER.KernelAbstractions.CPU(), Int32(60))
    unresolved_cpu = LMER.execute!(cpu_root)
    cross_scope, _ = execution_receipt_receipt_preparation(Metal.MtlArray, backend,
        Int32(70); dependency_arity = 1)
    @test_throws LMER.LocalMathValidationError LMER.execute!(cross_scope;
        dependencies = (unresolved_cpu,))
    wait(unresolved_cpu)
    admitted = LMER.execute!(cross_scope; dependencies = (unresolved_cpu,))
    wait(admitted)

    grouped_cpu, grouped_cpu_storage = execution_receipt_receipt_preparation(identity,
        LMER.KernelAbstractions.CPU(), Int32(75))
    grouped_metal, grouped_metal_storage = execution_receipt_receipt_preparation(
        Metal.MtlArray, backend, Int32(76))
    grouped_cpu_event = LMER.execute!(grouped_cpu)
    grouped_metal_event = LMER.execute!(grouped_metal)
    LMER.waitall(grouped_metal_event, grouped_cpu_event)
    @test grouped_cpu_storage == Int32[76, 77]
    @test Array(grouped_metal_storage) == Int32[77, 78]

    failing, failing_storage = execution_receipt_conflict_preparation(backend)
    dependent, dependent_storage = execution_receipt_receipt_preparation(
        Metal.MtlArray, backend, Int32(80); dependency_arity = 1)
    failed = LMER.execute!(failing)
    child = LMER.execute!(dependent; dependencies = (failed,))
    child_error = try
        wait(child)
        nothing
    catch error
        error
    end
    @test child_error isa LMER.LocalMathValidationError
    @test child_error.contract === :execution_dependency
    @test Array(failing_storage) == Int32[91]
    @test Array(dependent_storage) == fill(Int32(-1), 2)

    warm, warm_storage = execution_receipt_receipt_preparation(Metal.MtlArray, backend,
        Int32(90); lease_capacity = 1)
    wait(LMER.execute!(warm))
    warm_result = @timed wait(LMER.execute!(warm))
    @test warm_result.compile_time == 0.0
    @test warm_result.recompile_time == 0.0
    @test Array(warm_storage) == Int32[91, 92]
end
