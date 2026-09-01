const LMM = LocalMath

struct SMIdentityEvaluator end
(::SMIdentityEvaluator)(value) = value
struct SMAdd end
(::SMAdd)(left, right) = left + right

struct SMScaleEvaluator{T}
    scale::T
end
(evaluator::SMScaleEvaluator)(value) = evaluator.scale * value

struct SMHostileParameterEvaluator{P} end
(::SMHostileParameterEvaluator)(value) = value
struct SMArrayCaptureEvaluator{A}
    values::A
end
(::SMArrayCaptureEvaluator)(value) = value
mutable struct SMMutableCaptureEvaluator
    value::Int32
end
(::SMMutableCaptureEvaluator)(value) = value

struct SMScientificRecord{T}
    first::T
    second::T
end
struct SMTaggedRecord{Tag}
    value::Float32
end
struct SMPointerRecord
    value::Ptr{Cvoid}
end

struct SMForeignBounds <: LMM._ParameterBounds end

@testset "typed stage model foundation" begin
    struct SMNode end
    nodes = LMM.Space(SMNode, 4)
    singleton = LMM.Space(SMNode, 1)
    values_field = LMM.Field(nodes, Float32)
    record_field = LMM.Field(nodes, SMScientificRecord{Float32})
    @test eltype(record_field) === SMScientificRecord{Float32}
    @test_throws LMM.LocalMathValidationError LMM.Field(
        nodes, SMTaggedRecord{:host_metadata}
    )
    @test_throws LMM.LocalMathValidationError LMM.Field(
        nodes, SMPointerRecord
    )
    mask_field = LMM.Field(nodes, Bool)
    count_field = LMM.Field(singleton, Int32)
    gate_field = LMM.Field(singleton, Bool)
    identity = LMM.IdentityRelation(nodes)

    access = LMM.Access(values_field, identity)
    @test access.version isa LMM._StageEntryVersion
    @test access.field === values_field
    @test access.relation === identity

    count = LMM.Parameter(
        :count, Int32;
        bounds = (Int32(0), Int32(4)),
    )
    enabled = LMM.Parameter(:enabled, Bool)
    evaluator = LMM.Evaluator(SMIdentityEvaluator(), (count, enabled))
    @test evaluator.parameters == (count, enabled)
    @test LMM.Evaluator(SMScaleEvaluator(2.0f0)).evaluator.scale == 2.0f0
    @test_throws LMM.LocalMathValidationError LMM.Evaluator(identity)
    @test_throws LMM.LocalMathValidationError LMM.Parameter(
        :symbol, Symbol
    )
    @test_throws LMM.LocalMathValidationError LMM.Parameter(
        :uuid, LMM.UUIDs.UUID
    )
    @test_throws LMM.LocalMathValidationError LMM.Parameter(
        :pointer, Ptr{Cvoid}
    )
    @test_throws LMM.LocalMathValidationError LMM.Evaluator(
        SMScaleEvaluator(values_field)
    )
    @test_throws LMM.LocalMathValidationError LMM.Evaluator(
        SMArrayCaptureEvaluator(Float32[1, 2]))
    @test_throws LMM.LocalMathValidationError LMM.Evaluator(
        SMMutableCaptureEvaluator(Int32(1)))

    unique = LMM.Unique(Float32)
    publication = LMM.Publication(
        values_field, identity, unique; value = :value)
    component = publication.components[1]
    control = LMM.Control(
        prefix = count, mask = mask_field, subset = identity, gate = enabled)
    stage = LMM.Stage(nodes, (value = access,), (publication,),
        SMIdentityEvaluator(); parameters = (count, enabled), control,
        origin = LMM.SourceOrigin(:stage_model_test, 1))
    @test stage.source === nodes
    @test stage.publications == (publication,)
    @test stage.control === control

    # A program schema may declare scalar controls for a later stage; every
    # current Stage reference must agree exactly, but schema-only declarations
    # are not treated as an error.
    future_control = LMM.Parameter(:future_control, Bool)
    program = LMM.LocalLaw(
        stage;
        parameters = LMM.ParameterSchema(count, enabled, future_control),
    )
    @test program.stages == (stage,)
    @test program.parameters.declarations == (count, enabled, future_control)
    @test_throws LMM.LocalMathValidationError LMM.LocalLaw(
        stage; parameters = LMM.ParameterSchema(enabled, count)
    )
    sequenced = LMM.sequence(program, LMM.LocalLaw(stage))
    @test sequenced.stages == (stage, stage)
    @test sequenced.parameters.declarations == (count, enabled, future_control)

    plan = LMM.Plan(program, :cpu, :lowered)
    @test plan.bound === program
    @test propertynames(plan) == (:bound, :backend)
    @test propertynames(plan, true) == (:bound, :backend, :lowering)
    @test_throws MethodError LMM.Plan(
        LMM._CONSTRUCTION_TOKEN, program, :topology, :cpu, :lowered,
        (kind = :obsolete_shape,), :freshness,
    )

    valid_result = NamedTuple{(:value,),Tuple{LMM.UniqueValue{Float32}}}
    @test LMM._validate_evaluator_result_type((publication,), valid_result) === nothing
    @test_throws LMM.LocalMathValidationError LMM._validate_evaluator_result_type(
        (publication,), Float32
    )
    @test_throws LMM.LocalMathValidationError LMM._validate_evaluator_result_type(
        (publication,), NamedTuple{(:wrong,),Tuple{LMM.UniqueValue{Float32}}}
    )
    @test_throws LMM.LocalMathValidationError LMM._validate_evaluator_result_type(
        (publication,), NamedTuple{(:value,),Tuple{LMM.UniqueValue{Int32}}}
    )
    @test_throws LMM.LocalMathValidationError LMM._validate_evaluator_result_type(
        (publication,),
        NamedTuple{(:value,),Tuple{LMM.ConditionalUniqueValue{Float32}}},
    )

    field_control = LMM.Control(
        LMM._FieldPrefix(count_field), LMM._NoMask(), LMM._NoSubset(),
        LMM._FieldGate(gate_field),
    )
    # Field-derived controls are dependencies on preceding stages and use their
    # singleton Spaces, not the current iteration Space.
    @test field_control.prefix.field === count_field
    @test field_control.gate.field === gate_field
    field_control_stage = LMM.Stage(
        nodes, (value = access,), (publication,), evaluator, field_control,
        LMM.SourceOrigin(:stage_model_test, 2),
    )
    @test field_control_stage.control === field_control

    control_only = LMM.Parameter(:control_only, Bool)
    control_only_stage = LMM.Stage(
        nodes, (value = access,), (publication,),
        LMM.Evaluator(SMIdentityEvaluator()),
        LMM.Control(; gate = LMM._ParameterGate(control_only)),
        LMM.SourceOrigin(:stage_model_test, 3),
    )
    @test isempty(control_only_stage.evaluator.parameters)
    @test control_only_stage.control.gate.parameter === control_only

    partial = LMM.Unique(
        Float32; maximum = 2, coverage = LMM.PartialCoverage(),
        onempty = LMM.PreserveEmpty(),
    )
    @test typeof(partial).parameters[2] == 2
    @test_throws LMM.LocalMathValidationError LMM.Unique(
        Float32; coverage = LMM.PartialCoverage(),
        onempty = LMM.UnreachableEmpty(),
    )
    @test_throws LMM.LocalMathValidationError LMM.Unique(
        Float32; maximum = 33,
    )
    @test LMM.FillEmpty(1.0f0).value == 1.0f0
    @test_throws LMM.LocalMathValidationError LMM.FillEmpty(:metadata)

    reduce = LMM.Reduce(
        Float32, SMAdd(); seed = LMM.IdentitySeed(0.0f0),
        order = LMM.CanonicalLeftFold(),
    )
    reduce_publication = LMM.Publication((component,), reduce)
    @test reduce_publication.law === reduce
    @test LMM._validate_evaluator_result_type(
        (reduce_publication,),
        NamedTuple{(:value,),Tuple{LMM.Contribution{Float32}}},
    ) === nothing
    @test_throws LMM.LocalMathValidationError LMM._validate_evaluator_result_type(
        (reduce_publication,),
        NamedTuple{(:value,),Tuple{LMM.UniqueValue{Float32}}},
    )
    @test_throws LMM.LocalMathValidationError LMM.Reduce(
        Float32, SMAdd(); seed = LMM.IdentitySeed(Int32(0)),
    )
    @test_throws LMM.LocalMathValidationError LMM.Reduce(
        Float32, :add; seed = LMM.IdentitySeed(0.0f0),
    )
    relaxed_add = LMM.Reduce(
        Float32, +; seed = LMM.IdentitySeed(0.0f0),
        order = LMM.RelaxedAtomic(),
    )
    @test relaxed_add.operation === +

    resolve = LMM.Resolve(
        Int32, Float32; direction = LMM.ArgMin(),
        lower = typemin(Int32), upper = typemax(Int32),
        onempty = LMM.FillEmpty(-1.0f0),
    )
    resolve_publication = LMM.Publication((component,), resolve)
    @test LMM._validate_evaluator_result_type(
        (resolve_publication,),
        NamedTuple{(:value,),Tuple{
            LMM.ResolutionValue{
                Int32,LMM._CanonicalOrdinal,Float32
            }
        }},
    ) === nothing
    @test_throws LMM.LocalMathValidationError LMM.Resolve(
        Int32, Float32; lower = Int32(2), upper = Int32(1),
    )
    @test_throws LMM.LocalMathValidationError LMM.Resolve(
        ComplexF32, Float32; lower = ComplexF32(0), upper = ComplexF32(1),
    )
    @test_throws LMM.LocalMathValidationError LMM.Resolve(
        Int32, Float32; lower = typemin(Int32), upper = typemax(Int32),
        onempty = LMM.FillEmpty(Int32(-1)),
    )
    explicit_tie = LMM.Resolve(
        Int32, Float32; tie = LMM.TieMin{UInt32}(),
        lower = typemin(Int32), upper = typemax(Int32),
    )
    explicit_tie_publication = LMM.Publication((component,), explicit_tie)
    @test LMM._validate_evaluator_result_type(
        (explicit_tie_publication,), NamedTuple{(:value,),Tuple{
            LMM.ResolutionValue{Int32,UInt32,Float32}
        }},
    ) === nothing

    wrong_space = LMM.Space(SMNode, 4)
    wrong_relation = LMM.IdentityRelation(wrong_space)
    @test_throws LMM.LocalMathValidationError LMM.Access(
        values_field, wrong_relation
    )
    @test LMM.Access(values_field, identity).mode isa LMM._RequiredAccess
    @test LMM.Access(values_field, identity;
        required = false).mode isa LMM._SampleAccess
    @test_throws LMM.LocalMathValidationError LMM.FieldPublication(
        values_field, wrong_relation, LMM.PublicationValue(:value)
    )
    @test_throws LMM.LocalMathValidationError LMM._ParameterGate(count)
    @test_throws LMM.LocalMathValidationError LMM._MaskSelection(values_field)

    # Ghost storage is semantic access data, never inferred from a binding.
    ghost_space = LMM.Space(SMNode, 2)
    ghost_field = LMM.Field(ghost_space, Float32)
    affine = LMM.AffineRelation(nodes => nodes; offsets = ((-1,),))
    ghost_relation = LMM.BoundaryRelation(
        affine, LMM.GhostBoundary((1,), (1,), ghost_space),
    )
    @test LMM.Access(values_field, ghost_relation; ghost = ghost_field).ghost === ghost_field
    @test_throws LMM.LocalMathValidationError LMM.Access(values_field, ghost_relation)
    @test_throws LMM.LocalMathValidationError LMM.Access(
        values_field, identity; ghost = ghost_field,
    )
    @test_throws LMM.LocalMathValidationError LMM._relation_ghost_space(
        LMM._ProductRelation((ghost_relation,), 1),
    )
    @test_throws LMM.LocalMathValidationError LMM._relation_ghost_space(
        LMM._SelectedRelation(identity, ghost_relation, 1),
    )

    duplicate = LMM.Parameter(:count, Int32)
    @test_throws LMM.LocalMathValidationError LMM.Evaluator(
        SMIdentityEvaluator(), (count, duplicate)
    )

    # Symbol parameters are compile-time callable identity. Other metadata
    # cannot hide in an otherwise empty/isbits callable.
    symbol_identity = SMHostileParameterEvaluator{:label}()
    @test LMM.Evaluator(symbol_identity).evaluator === symbol_identity
    for hostile in (
            SMHostileParameterEvaluator{LMM.UUIDs.uuid4()}(),
            SMHostileParameterEvaluator{Val{1}}(),
            SMHostileParameterEvaluator{Ptr{Cvoid}}(),
            SMHostileParameterEvaluator{Base.RefValue{Int32}}(),
            SMHostileParameterEvaluator{
                NamedTuple{(:label,),Tuple{Int32}}
            }(),
            SMHostileParameterEvaluator{typeof(values_field)}(),
        )
        @test_throws LMM.LocalMathValidationError LMM.Evaluator(hostile)
    end
    captured = try
        LMM.Evaluator(SMArrayCaptureEvaluator(Float32[1]))
        nothing
    catch caught
        caught
    end
    @test captured isa LMM.LocalMathValidationError
    @test captured.actual.reason == :array_capture
    @test captured.actual.path == (:evaluator, :values)
    @test_throws MethodError LMM.PublicationValue{1}()
    @test_throws MethodError LMM.Parameter{
        Int32,SMForeignBounds
    }(:foreign, SMForeignBounds())
    @test_throws LMM.LocalMathValidationError LMM.Parameter(
        LMM._STAGE_MODEL_SEAL, Int32, :foreign, SMForeignBounds()
    )

    empty_nodes = LMM.Space(SMNode, 0)
    @test length(empty_nodes) == 0
    empty_field = LMM.Field(empty_nodes, Float32)
    empty_identity = LMM.IdentityRelation(empty_nodes)
    empty_publication = LMM.Publication((LMM.FieldPublication(
        empty_field, empty_identity, LMM.PublicationValue(:empty_value)
    ),), LMM.Unique(Float32))
    empty_stage = LMM.Stage(
        empty_nodes, NamedTuple(), (empty_publication,),
        LMM.Evaluator(SMIdentityEvaluator()), LMM.Control(),
        LMM.SourceOrigin(:zero_source_stage, 1),
    )
    @test length(empty_stage.source) == 0
    @test empty_stage.publications == (empty_publication,)
end
