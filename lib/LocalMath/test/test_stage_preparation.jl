using Test
import LocalMath
const LMPRE = LocalMath

struct PreparedStageNode end
struct PreparedStageEvaluator
    fields::Float32
end
struct PreparedStageBypassEvaluator end
struct PreparedStageHelperBypassEvaluator end
struct PreparedStageRecord{T}
    enabled::Bool
    value::T
end
struct PreparedStageUnsupportedRecord
    enabled::Bool
    value::Int64
end
struct PreparedStageNoInlineIncrement end
Base.@noinline (::PreparedStageNoInlineIncrement)(value::Int32) =
    value + Int32(1)
struct PreparedStageNoInlineCapture
    values::Vector{Int32}
end
Base.@noinline (capture::PreparedStageNoInlineCapture)(value::Int32) =
    capture.values[1] + value
struct PreparedStageNoInlineWrapper{F}
    operation::F
end
@inline (wrapper::PreparedStageNoInlineWrapper)(value::Int32) =
    wrapper.operation(value)
struct PreparedStageNoInlineChain{F}
    operation::F
end
Base.@noinline (chain::PreparedStageNoInlineChain)(value::Int32) =
    chain.operation(value)
@enum PreparedStageStatus::UInt8 PreparedStageReady = 0x00
struct PreparedStageStatusRecord
    status::PreparedStageStatus
    source::Int32
end

@inline function (evaluator::PreparedStageEvaluator)(item::Int32, reads, parameters)
    return (value = LMPRE.UniqueValue(
        getfield(parameters, 1) * getproperty(evaluator, :fields)),)
end
@inline prepared_stage_steal(read) = getfield(read, (:fields,)[1])
@inline function (::PreparedStageHelperBypassEvaluator)(item::Int32, reads, parameters)
    fields = prepared_stage_steal(reads[1])
    return (value = LMPRE.UniqueValue(@inbounds(fields[1][item])),)
end
@inline function (::PreparedStageBypassEvaluator)(item::Int32, reads, parameters)
    fields = reads[1].fields
    return (value = LMPRE.UniqueValue(@inbounds(fields[1][item])),)
end

@testset "Stage storage admits only reviewed scalar and record leaves" begin
    backend = LMPRE.KernelAbstractions.CPU()
    @test isnothing(LMPRE._require_stage_storage_operation(
        backend,
        fill(PreparedStageRecord(false, 0.0), 2, 2),
        :load,
        :record_read,
    ))
    @test isnothing(LMPRE._require_stage_storage_operation(
        backend, fill(PreparedStageReady, 2), :load, :enum_leaf,
    ))
    @test isnothing(LMPRE._require_stage_storage_operation(
        backend,
        fill(PreparedStageStatusRecord(PreparedStageReady, Int32(1)), 2),
        :store,
        :enum_record,
    ))
    @test_throws LMPRE.LocalMathValidationError begin
        LMPRE._require_stage_storage_operation(
            backend, zeros(Int64, 2), :load, :unsupported_scalar
        )
    end
    @test_throws LMPRE.LocalMathValidationError begin
        LMPRE._require_stage_storage_operation(
            backend,
            fill(PreparedStageUnsupportedRecord(false, Int64(0)), 2),
            :load,
            :unsupported_record_leaf,
        )
    end
end

@testset "closed callable analysis follows concrete noinline boundaries" begin
    safe = LMPRE._closed_callable_effect_analysis(
        PreparedStageNoInlineWrapper(PreparedStageNoInlineIncrement()),
        Tuple{Int32}, method_signature -> length(method_signature) == 2
    )
    @test safe.qualified
    @test safe.return_type === Int32

    # Scientific expression compilers naturally produce deeply nested,
    # concrete callable trees. The cold effect screen follows those exact
    # method instances while its cycle guard and total IR budget remain the
    # safety authorities.
    deep = PreparedStageNoInlineIncrement()
    for _ in 1:16
        deep = PreparedStageNoInlineChain(deep)
    end
    deep_analysis = LMPRE._closed_callable_effect_analysis(
        deep, Tuple{Int32}, method_signature -> length(method_signature) == 2
    )
    @test deep_analysis.qualified
    @test deep_analysis.return_type === Int32

    unsafe = LMPRE._closed_callable_effect_analysis(
        PreparedStageNoInlineWrapper(
            PreparedStageNoInlineCapture(Int32[1])
        ),
        Tuple{Int32}, method_signature -> length(method_signature) == 2
    )
    @test !unsafe.qualified
end

@testset "descriptor-free prepared Stage ABI" begin
    nodes = LMPRE.Space(PreparedStageNode, 4)
    input = LMPRE.Field(nodes, Float32)
    output = LMPRE.Field(nodes, Float32)
    relation = LMPRE.IdentityRelation(nodes)
    scale = LMPRE.Parameter(:scale, Float32)
    stage = LMPRE.Stage(
        nodes,
        (input = LMPRE.Access(input, relation),),
        (LMPRE.Publication((LMPRE.FieldPublication(
            output, relation, LMPRE.PublicationValue(:value),
        ),), LMPRE.Unique(Float32)),),
        LMPRE.Evaluator(PreparedStageEvaluator(1.0f0), (scale,)),
        LMPRE.Control(), LMPRE.SourceOrigin(:stage_preparation, 1),
    )
    spare = LMPRE.Parameter(:spare, Int32)
    work = LMPRE.LocalLaw(
        stage; parameters = LMPRE.ParameterSchema(scale, spare),
    )
    bound = LMPRE._bind_law(work, LMPRE._StructuralBinding(
        (
            LMPRE._field_storage_binding(input, Float32[1, 2, 3, 4]),
            LMPRE._field_storage_binding(output, zeros(Float32, 4)),
        ),
        (LMPRE._relation_storage_binding(relation),),
    ))
    backend = LMPRE.KernelAbstractions.get_backend(bound.binding.fields[1].storage)
    admission = _test_stage_admission(bound; backend)
    prepared = admission.stage
    draft = LMPRE._StageDraft(prepared.fields, prepared.accesses,
        prepared.parameter_slots, prepared.control, prepared.publications,
        prepared.source_count)
    @test_throws ArgumentError LMPRE._AdmittedStage(
        LMPRE._AdmittedStageSeal(), PreparedStageEvaluator(1.0f0), draft,
    )

    bypass_stage = LMPRE.Stage(
        nodes, stage.accesses, stage.publications,
        LMPRE.Evaluator(PreparedStageBypassEvaluator(), (scale,)),
        stage.control, LMPRE.SourceOrigin(:stage_preparation, 2),
    )
    bypass_bound = LMPRE._bind_law(
        LMPRE.LocalLaw(bypass_stage), bound.binding)
    bypass_error = try
        _test_stage_admission(bypass_bound; backend)
        nothing
    catch error
        error
    end
    @test bypass_error isa LMPRE.LocalMathValidationError
    @test bypass_error.contract == :stage_evaluator_effects
    helper_bypass_stage = LMPRE.Stage(
        nodes, stage.accesses, stage.publications,
        LMPRE.Evaluator(PreparedStageHelperBypassEvaluator(), (scale,)),
        stage.control, LMPRE.SourceOrigin(:stage_preparation, 3),
    )
    helper_bypass_bound = LMPRE._bind_law(
        LMPRE.LocalLaw(helper_bypass_stage), bound.binding)
    helper_bypass_error = try
        _test_stage_admission(helper_bypass_bound; backend)
        nothing
    catch error
        error
    end
    @test helper_bypass_error isa LMPRE.LocalMathValidationError
    @test helper_bypass_error.contract == :stage_evaluator_effects

    @test prepared.evaluator isa LMPRE._PortProjector{PreparedStageEvaluator}
    @test prepared.fields == (Float32[1, 2, 3, 4], zeros(Float32, 4))
    @test prepared.source_count == Int32(4)
    @test fieldtype(typeof(prepared.accesses[1].relation.view), :field_slot) ===
        LMPRE._PreparedFieldSlot{1}
    @test fieldtype(typeof(prepared.publications[1].components[1].relation.view), :field_slot) ===
        LMPRE._PreparedFieldSlot{2}
    @test !(prepared.accesses[1].relation.view isa LMPRE.Relation)
    @test !(prepared.publications[1].components[1].relation.view isa LMPRE.Relation)

    read = LMPRE._StageRead(
        prepared.fields, prepared.accesses[1].relation, Int32(2),
        LMPRE._NoEvaluationValidation(),
    )
    @test length(read) == 1
    @test read[1].value == 2.0f0
    @test read[1].present
    @test !read[1].exterior

    @test prepared.evaluator isa LMPRE._PortProjector{PreparedStageEvaluator}
    @test admission.result_type === NamedTuple{(:value,),Tuple{LMPRE.UniqueValue{Float32}}}
    @test admission.signature == Tuple{
        Int32,
        Tuple{LMPRE._StageRead{
            typeof(prepared.fields),typeof(prepared.accesses[1].relation),
            LMPRE._NoEvaluationValidation}},
        Tuple{Float32},
    }
    @test !hasproperty(prepared, :backend)
    @test !hasproperty(prepared, :signature)
    @test LMPRE._stage_evaluator_parameters(
        (1.0f0, Int32(7)), prepared.parameter_slots,
    ) == (1.0f0,)
    lifecycle = LMPRE.prepare(LMPRE.plan(bound; backend))
    @test lifecycle.submission_schema isa LMPRE._StageParameterLayout
    direct = lifecycle.runtime.launches[1].stage
    @test direct isa LMPRE._DirectPointwiseSegmentPreparation
    @test length(direct.stages) == 1
    @test typeof(direct.stages[1].evaluator) === typeof(prepared.evaluator)
    @test direct.stages[1].fields == prepared.fields
    @test direct.stages[1].accesses == prepared.accesses
    @test direct.stages[1].parameter_slots == prepared.parameter_slots
    @test !hasfield(typeof(LMPRE._stage_evaluation(prepared)),
        :parameter_slots)
    @test direct.destinations === ((prepared.fields[2],),)
    @test direct.empty_policies == ((LMPRE.UnreachableEmpty(),),)
    inspection = LMPRE.inspect(lifecycle)
    @test !hasproperty(inspection.realized, :parameter_values_stored)
    @test map(fact -> fact.name, inspection.realized.parameter_layout) ==
        (:scale, :spare)
    @test inspection.stages[1].planning.executor === :candidate
    wait(LMPRE.execute!(lifecycle; parameters = (spare = Int32(7), scale = 2.0f0)))
    @test output === bound.binding.fields[2].field
    @test bound.binding.fields[2].storage == fill(2.0f0, 4)

    queued = LMPRE.prepare(LMPRE.plan(bound; backend); lease_capacity = 2)
    first_event = LMPRE.execute!(queued; parameters = (scale = 3.0f0, spare = Int32(1)))
    second_event = LMPRE.execute!(queued; parameters = (spare = Int32(2), scale = 4.0f0))
    wait(second_event)
    @test first_event.serial == UInt64(1)
    @test bound.binding.fields[2].storage == fill(4.0f0, 4)

    rejected = LMPRE.prepare(LMPRE.plan(bound; backend))
    @test_throws LMPRE.LocalMathValidationError LMPRE.execute!(
        rejected; parameters = (scale = 2.0, spare = Int32(1)))
    @test rejected.submitted == UInt64(0)
    @test_throws LMPRE.LocalMathValidationError LMPRE.execute!(
        rejected; parameters = (scale = 2.0f0, wrong = Int32(1)))
    @test rejected.submitted == UInt64(0)

    count = LMPRE.Parameter(:count, Int32;
        bounds = LMPRE._ClosedParameterBounds(Int32(0), Int32(4)))
    enabled = LMPRE.Parameter(:enabled, Bool)
    controlled_output = LMPRE.Field(nodes, Float32)
    controlled_publication = LMPRE.Publication((LMPRE.FieldPublication(
        controlled_output, relation, LMPRE.PublicationValue(:value)),),
        LMPRE.Unique(Float32; coverage = LMPRE.PartialCoverage(),
            onempty = LMPRE.PreserveEmpty()))
    controlled_stage = LMPRE.Stage(nodes, NamedTuple(),
        (controlled_publication,),
        LMPRE.Evaluator(PreparedStageEvaluator(1.0f0), (scale,)),
        LMPRE.Control(LMPRE._ParameterPrefix(count), LMPRE._NoMask(),
            LMPRE._NoSubset(), LMPRE._ParameterGate(enabled)),
        LMPRE.SourceOrigin(:stage_parameter_control, 1))
    controlled_work = LMPRE.LocalLaw(controlled_stage; parameters =
        LMPRE.ParameterSchema(scale, count, enabled))
    controlled_storage = fill(9.0f0, 4)
    controlled_bound = LMPRE._bind_law(controlled_work,
        LMPRE._StructuralBinding((LMPRE._field_storage_binding(
            controlled_output, controlled_storage),),
            (LMPRE._relation_storage_binding(relation),)))
    controlled = LMPRE.prepare(LMPRE.plan(controlled_bound; backend))
    wait(LMPRE.execute!(controlled;
        parameters = (scale = 5.0f0, enabled = false, count = Int32(2))))
    @test controlled_storage == fill(9.0f0, 4)
    wait(LMPRE.execute!(controlled;
        parameters = (enabled = true, count = Int32(2), scale = 5.0f0)))
    @test controlled_storage == Float32[5, 5, 9, 9]
end
