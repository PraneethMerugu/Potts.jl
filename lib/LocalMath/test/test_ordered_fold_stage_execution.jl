using Test
import LocalMath
const LWFSE = LocalMath

struct OrderedFoldExecutionNode end
struct OrderedFoldExecutionEvaluator end
@inline (::OrderedFoldExecutionEvaluator)(item::Int32, reads, parameters) =
    (event = LWFSE.FoldValue(item),)
struct OrderedFoldParameterizedEvaluator end
@inline (::OrderedFoldParameterizedEvaluator)(item::Int32, reads, parameters) =
    (event = LWFSE.FoldValue(item * getfield(parameters, 1)),)
struct ReverseFoldOrder end
@inline (::ReverseFoldOrder)(value::Int32) = Int32(6) - value
struct SameFoldOrder end
@inline (::SameFoldOrder)(value::Int32) = Int32(0)
struct FoldIdentity end
@inline (::FoldIdentity)(value::Int32) = value
struct SameFoldIdentity end
@inline (::SameFoldIdentity)(value::Int32) = Int32(0)
struct FoldWriteTransition end
@inline (::FoldWriteTransition)(state, value, item, reads) = LWFSE.FoldStep(
    (accumulator = LWFSE.BoundedWrites((Int32(1),), (value,), Int32(1)),),
)
struct FoldInvalidTransition end
@inline (::FoldInvalidTransition)(state, value, item, reads) = LWFSE.FoldStep(
    (accumulator = LWFSE.BoundedWrites((Int32(3),), (value,), Int32(1)),),
)
struct FoldHaltTransition end
@inline (::FoldHaltTransition)(state, value, item, reads) = LWFSE.FoldStep(
    (accumulator = LWFSE.BoundedWrites((Int32(1),), (value,), Int32(1)),),
    halt = true,
)

function _ordered_fold_execution_stage(transition, order)
    source = LWFSE.Space(OrderedFoldExecutionNode, 5)
    state_space = LWFSE.Space(OrderedFoldExecutionNode, 2)
    initial, accumulator = LWFSE.Field(state_space, Int32), LWFSE.Field(state_space, Int32)
    state = LWFSE.InitializedState(; accumulator = LWFSE.FoldComponent(accumulator; from = initial))
    law = LWFSE.OrderedFold(Int32, state, transition; order)
    publication = LWFSE.Publication((LWFSE.FoldPublication(
        LWFSE.PublicationValue(:event)),), law)
    stage = LWFSE.Stage(source, NamedTuple(), (publication,),
        LWFSE.Evaluator(OrderedFoldExecutionEvaluator()), LWFSE.Control(),
        LWFSE.SourceOrigin(:ordered_fold_execution, 1))
    return source, initial, accumulator, stage
end

struct OrderedFoldBoundedEvaluator{F}
    fold::F
end
@inline function (evaluator::OrderedFoldBoundedEvaluator)(
        item::Int32, reads, parameters,
    )
    return (event = LWFSE.FoldValue(Int32(evaluator.fold(reads[1]))),)
end

struct OrderedFoldBoundedTransition{F}
    fold::F
end
@inline function (transition::OrderedFoldBoundedTransition)(
        state, value, item, reads,
    )
    folded = Int32(transition.fold(reads[1]))
    return LWFSE.FoldStep((accumulator = LWFSE.BoundedWrites(
        (Int32(1),), (value + folded,), Int32(1)),))
end

function _ordered_fold_bounded_law(; transition_fold = nothing,
        empty_input::Bool = false)
    source = LWFSE.Space(OrderedFoldExecutionNode, 2)
    values_space = LWFSE.Space(OrderedFoldExecutionNode, 4)
    state_space = LWFSE.Space(OrderedFoldExecutionNode, 2)
    values = LWFSE.Field(values_space, Int32)
    keys = LWFSE.Field(source, Int32)
    initial = LWFSE.Field(state_space, Int32)
    accumulator = LWFSE.Field(state_space, Int32)
    neighbors = empty_input ?
        LWFSE.IndexRelation(keys => values_space; optional = true) :
        LWFSE.FixedRelation(source => values_space; degree = 2)
    positive_sum = LWFSE.bounded_fold(identity, +, Int32(0),
        (sum, count) -> sum;
        domain = LWFSE.Where(>(Int32(0))),
        oninvalid = LWFSE.RejectInvalid(),
        onempty = LWFSE.RejectEmpty(),
        order = LWFSE.CanonicalLeftFold())
    evaluator = transition_fold === nothing ?
        OrderedFoldBoundedEvaluator(positive_sum) :
        OrderedFoldExecutionEvaluator()
    transition = transition_fold === nothing ? FoldWriteTransition() :
        OrderedFoldBoundedTransition(positive_sum)
    state = LWFSE.InitializedState(;
        accumulator = LWFSE.FoldComponent(accumulator; from = initial))
    publication = LWFSE.Publication((LWFSE.FoldPublication(
        LWFSE.PublicationValue(:event)),),
        LWFSE.OrderedFold(Int32, state, transition;
            order = LWFSE._SourceOrder()))
    stage = LWFSE.Stage(source,
        (values = LWFSE.Access(values, neighbors),),
        (publication,), LWFSE.Evaluator(evaluator), LWFSE.Control(),
        LWFSE.SourceOrigin(:ordered_fold_bounded_validation, 1))
    law = LWFSE.LocalLaw(stage)
    endpoints = reshape(Int32[1, 2, 3, 4], 2, 2)
    return (; law, values, keys, initial, accumulator, neighbors, endpoints)
end
struct FoldLateInvalidTransition end
@inline function (::FoldLateInvalidTransition)(state, value, item, reads)
    destination = item == Int32(1) ? Int32(1) : Int32(3)
    return LWFSE.FoldStep((accumulator = LWFSE.BoundedWrites(
        (destination,), (value,), Int32(1)),))
end

function _run_ordered_fold_stage!(transition, order; predecessor = ())
    source, initial, accumulator, stage = _ordered_fold_execution_stage(transition, order)
    initial_storage, accumulator_storage = Int32[7, 8], Int32[66, 77]
    bound = LWFSE._bind_law(LWFSE.LocalLaw(stage), LWFSE._StructuralBinding((
        LWFSE._field_storage_binding(initial, initial_storage),
        LWFSE._field_storage_binding(accumulator, accumulator_storage),
    ), ()))
    backend = LWFSE.KernelAbstractions.get_backend(initial_storage)
    admission = _test_stage_admission(bound; backend)
    spec = LWFSE._ordered_fold_stage_workspace_spec(admission.stage;
        path = (:ordered_fold_execution,), name_prefix = :ordered_fold_execution)
    authority = LWFSE._WorkspaceAuthority(spec.leaves, spec.template)
    tree = LWFSE._materialize_workspace(authority.template, authority,
        LWFSE._WorkspaceAllocator(backend))
    prepared = LWFSE._prepare_ordered_fold_stage(admission,
        LWFSE._ordered_fold_stage_workspace_from_tree(tree, spec))
    program_validation = LWFSE._ProgramValidationTarget(
        zeros(UInt32, LWFSE._VALIDATION_STATUS_FIELDS, 1), Int32(1))
    LWFSE._execute_ordered_fold_stage!(prepared, (), Int32(1), predecessor,
        LWFSE._NoStageRelationGuard(), program_validation)
    LWFSE.KernelAbstractions.synchronize(backend)
    return accumulator_storage, prepared
end

@testset "OrderedFold prepared Stage CPU execution" begin
    @test !isdefined(LWFSE, :_OrderedFoldStageRun)
    @test !isdefined(LWFSE, :_OrderedFoldStageExecution)
    @test !hasfield(LWFSE._OrderedFoldRecurrenceStage, :evaluator)
    @test !hasfield(LWFSE._StageEvaluation, :publications)
    canonical = LWFSE._CanonicalBy(ReverseFoldOrder(), FoldIdentity())
    output, prepared = _run_ordered_fold_stage!(FoldWriteTransition(), canonical)
    @test output == Int32[1, 8]
    @test prepared.workspace.status == Int32[0]

    duplicate = LWFSE._CanonicalBy(SameFoldOrder(), SameFoldIdentity())
    output, prepared = _run_ordered_fold_stage!(FoldWriteTransition(), duplicate)
    @test output == Int32[66, 77]
    @test prepared.workspace.status == Int32[LWFSE._ORDERED_FOLD_DUPLICATE_ORDER]
    predecessor = zeros(UInt32, LWFSE._VALIDATION_STATUS_FIELDS, 1)
    predecessor[LWFSE._VALIDATION_FAILURE_CLASS, 1] = UInt32(1)
    LWFSE._execute_ordered_fold_stage!(prepared, (), Int32(1), (predecessor,),
        LWFSE._NoStageRelationGuard(), LWFSE._ProgramValidationTarget(
            zeros(UInt32, LWFSE._VALIDATION_STATUS_FIELDS, 1), Int32(1)))
    LWFSE.KernelAbstractions.synchronize(prepared.backend)
    @test prepared.validation[LWFSE._VALIDATION_FAILURE_CLASS, 1] == UInt32(0)

    output, prepared = _run_ordered_fold_stage!(FoldInvalidTransition(), LWFSE._SourceOrder())
    @test output == Int32[66, 77]
    @test prepared.workspace.status == Int32[LWFSE._ORDERED_FOLD_DESTINATION]

    output, prepared = _run_ordered_fold_stage!(
        FoldLateInvalidTransition(), LWFSE._SourceOrder())
    @test output == Int32[66, 77]
    @test prepared.workspace.status == Int32[LWFSE._ORDERED_FOLD_DESTINATION]

    output, prepared = _run_ordered_fold_stage!(FoldHaltTransition(), canonical)
    @test output == Int32[5, 8]
    @test prepared.workspace.status == Int32[0]

    device = zeros(UInt32, LWFSE._VALIDATION_STATUS_FIELDS, 1)
    device[1, 1] = UInt32(1)
    output, prepared = _run_ordered_fold_stage!(FoldWriteTransition(), canonical;
        predecessor = (device,))
    @test output == Int32[66, 77]
    @test prepared.workspace.status == Int32[0]
end

@testset "OrderedFold uses the sole public Stage lifecycle" begin
    source, initial, accumulator, stage = _ordered_fold_execution_stage(
        FoldWriteTransition(), LWFSE._CanonicalBy(ReverseFoldOrder(), FoldIdentity()))
    initial_storage, accumulator_storage = Int32[7, 8], Int32[66, 77]
    bound = LWFSE._bind_law(LWFSE.LocalLaw(stage), LWFSE._StructuralBinding((
        LWFSE._field_storage_binding(initial, initial_storage),
        LWFSE._field_storage_binding(accumulator, accumulator_storage),
    ), ()))
    backend = LWFSE.KernelAbstractions.get_backend(initial_storage)
    prepared = LWFSE.prepare(LWFSE.plan(bound; backend))
    wait(LWFSE.execute!(prepared))
    @test accumulator_storage == Int32[1, 8]
    facts = LWFSE.inspect(prepared)
    @test facts.stages[1].planning.executor === :ordered_fold
    @test facts.planning.stage_phases ==
        LWFSE.inspect(prepared.plan).planning.stage_phases
    @test :ordered_fold_apply in
        map(phase -> phase.kind, facts.stages[1].planning.phases)
end

@testset "OrderedFold public failure preserves exact scientific receipt" begin
    source, initial, accumulator, stage = _ordered_fold_execution_stage(
        FoldInvalidTransition(), LWFSE._SourceOrder())
    initial_storage, accumulator_storage = Int32[7, 8], Int32[66, 77]
    bound = LWFSE._bind_law(LWFSE.LocalLaw(stage),
        LWFSE._StructuralBinding((
            LWFSE._field_storage_binding(initial, initial_storage),
            LWFSE._field_storage_binding(accumulator, accumulator_storage),
        ), ()))
    backend = LWFSE.KernelAbstractions.get_backend(initial_storage)
    prepared = LWFSE.prepare(LWFSE.plan(bound; backend))
    failure = try
        wait(LWFSE.execute!(prepared))
        nothing
    catch error
        error
    end
    @test failure isa LWFSE.LocalMathValidationError
    @test failure.contract === :runtime_ordered_fold_validation
    @test failure.actual.failure_class === :invalid_destination
    @test failure.actual.component === :accumulator
    @test failure.actual.source_item == Int32(1)
    @test failure.actual.canonical_position == Int32(1)
    @test failure.actual.witness == Int32(3)
    @test accumulator_storage == Int32[66, 77]
end

@testset "OrderedFold bounded validation is transactional" begin
    for transition_fold in (nothing, true), failure in (:invalid, :empty)
        witness = _ordered_fold_bounded_law(; transition_fold,
            empty_input = failure === :empty)
        destination = Int32[66, 77]
        values = failure === :invalid ? Int32[1, -2, 3, 4] :
            Int32[1, 2, 3, 4]
        bindings = failure === :invalid ?
            (witness.values => values,
                witness.initial => Int32[7, 8],
                witness.accumulator => destination,
                witness.neighbors => witness.endpoints) :
            (witness.values => values,
                witness.keys => zeros(Int32, 2),
                witness.initial => Int32[7, 8],
                witness.accumulator => destination)
        prepared = LWFSE.prepare(witness.law, bindings...;
            backend = LWFSE.KernelAbstractions.CPU())
        error = try
            wait(LWFSE.execute!(prepared))
            nothing
        catch exception
            exception
        end
        @test error isa LWFSE.LocalMathValidationError
        @test destination == Int32[66, 77]
        expected = failure === :invalid ?
            LWFSE._ORDERED_FOLD_INVALID_VALUE :
            LWFSE._ORDERED_FOLD_EMPTY_INPUT
        @test prepared.runtime.launches[1].stage.workspace.status ==
            Int32[expected]
    end
end

@testset "OrderedFold consumes per-submission positional parameters" begin
    source = LWFSE.Space(OrderedFoldExecutionNode, 5)
    state_space = LWFSE.Space(OrderedFoldExecutionNode, 2)
    initial = LWFSE.Field(state_space, Int32)
    accumulator = LWFSE.Field(state_space, Int32)
    factor = LWFSE.Parameter(:factor, Int32)
    state = LWFSE.InitializedState(; accumulator = LWFSE.FoldComponent(
        accumulator; from = initial))
    law = LWFSE.OrderedFold(Int32, state, FoldWriteTransition();
        order = LWFSE._SourceOrder())
    publication = LWFSE.Publication((LWFSE.FoldPublication(
        LWFSE.PublicationValue(:event)),), law)
    stage = LWFSE.Stage(source, NamedTuple(), (publication,),
        LWFSE.Evaluator(OrderedFoldParameterizedEvaluator(), (factor,)),
        LWFSE.Control(), LWFSE.SourceOrigin(:ordered_fold_parameters, 1))
    initial_storage, accumulator_storage = Int32[7, 8], Int32[0, 0]
    work = LWFSE.LocalLaw(stage; parameters = LWFSE.ParameterSchema(factor))
    bound = LWFSE._bind_law(work, LWFSE._StructuralBinding((
        LWFSE._field_storage_binding(initial, initial_storage),
        LWFSE._field_storage_binding(accumulator, accumulator_storage),
    ), ()))
    backend = LWFSE.KernelAbstractions.get_backend(initial_storage)
    prepared = LWFSE.prepare(LWFSE.plan(bound; backend))
    wait(LWFSE.execute!(prepared; parameters = (factor = Int32(3),)))
    @test accumulator_storage == Int32[15, 8]
    @test prepared.runtime.launches[1].stage.stage.parameter_slots ==
        (LWFSE._ParameterSlot{1}(),)
end
