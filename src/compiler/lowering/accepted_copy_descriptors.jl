# Accepted-copy assignment and bounded relationship-creation lowering.

function _stage_descriptor(
        ir::AnalyzedTermIR,
        record_index::Integer,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        stage::CorePotts.AbstractCompiledStage,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    arguments = first(record.normalized_payload)
    effects = arguments.effects
    length(effects) == 1 || throw(ArgumentError(
        "V1 staged assignment descriptors require exactly one effect"
    ))
    effect = only(effects)
    effect isa Assign || throw(ArgumentError(
        "V1 staged assignment descriptors require Assign"
    ))
    binding = stage isa CorePotts.AcceptedCopyStage ?
              CorePotts.ProposalTargetStageSite() :
              CorePotts.IterationStageSite()
    condition = _stage_evaluator(
        ir,
        record_index,
        :expression,
        true,
        manifest,
        T,
        state_handles,
        draw_handles,
        binding,
    )
    value = _stage_evaluator(
        ir,
        record_index,
        :effect_1_value,
        effect.value,
        manifest,
        T,
        state_handles,
        draw_handles,
        binding,
    )
    target = _stage_state_handle(ir, record, effect.target, state_handles)
    reads = _record_state_handles(ir, record, state_handles)
    target in reads || (reads = (reads..., target))
    footprint = stage isa CorePotts.AcceptedCopyStage ?
                CorePotts.ProposalContextFootprint() :
                CorePotts.FiniteSpatialFootprint(())
    return CorePotts.CompiledStageDescriptor(
        condition,
        value,
        CorePotts.SiteAssignmentEffect(target),
        stage,
        CorePotts.ResourceAccess(reads, (target,), footprint),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end
function _relationship_create_stage_descriptor(
        ir::AnalyzedTermIR,
        record_index::Integer,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        relationship_endpoint_policies,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    arguments = first(record.normalized_payload)
    length(arguments.effects) == 1 && only(arguments.effects) isa Create ||
        throw(ArgumentError(
            "a relationship-create stage requires exactly one Create effect"
        ))
    effect = only(arguments.effects)
    relationship = _resource_record(
        ir.source, record, :RelationshipState, effect.relationship
    )
    relationship === nothing && throw(ArgumentError(
        "relationship-create effect does not resolve to a declared store"
    ))
    endpoint_policy = _relationship_endpoint_policy(
        relationship_endpoint_policies, relationship.identity
    )
    store_slot = endpoint_policy.slot

    condition = _stage_evaluator(
        ir,
        record_index,
        :expression,
        true,
        manifest,
        T,
        state_handles,
        draw_handles,
        CorePotts.ProposalTargetStageSite(),
    )
    endpoint_a = _stage_evaluator(
        ir,
        record_index,
        :effect_1_endpoint_a,
        effect.endpoint_a,
        manifest,
        T,
        state_handles,
        draw_handles,
        CorePotts.ProposalTargetStageSite(),
    )
    endpoint_b = _stage_evaluator(
        ir,
        record_index,
        :effect_1_endpoint_b,
        effect.endpoint_b,
        manifest,
        T,
        state_handles,
        draw_handles,
        CorePotts.ProposalTargetStageSite(),
    )

    relationship_options = _record_options(relationship)
    declared_payload = get(
        relationship_options, :payload, NamedTuple()
    )
    declared_payload isa NamedTuple && effect.payload isa NamedTuple ||
        throw(ArgumentError(
            "relationship payload declarations and requests must be named tuples"
        ))
    keys(effect.payload) == keys(declared_payload) || throw(ArgumentError(
        "relationship-create payload must exactly match its declared schema"
    ))
    payload = Tuple(
        _stage_evaluator(
            ir,
            record_index,
            Symbol(:effect_1_payload_, name),
            getproperty(effect.payload, name),
            manifest,
            T,
            state_handles,
            draw_handles,
            CorePotts.ProposalTargetStageSite(),
        )
        for name in keys(declared_payload)
    )

    kind_condition = _compiler_operation_expression(
        _potts_relationship_endpoint_kinds,
        (
            endpoint_a.expression,
            endpoint_b.expression,
            CorePotts.LiteralExpression(endpoint_policy.kind_a),
            CorePotts.LiteralExpression(endpoint_policy.kind_b),
        ),
        record,
    )
    compiled_condition = _static_evaluator(
        _compiler_operation_expression(
            (&),
            (
            condition.expression,
            kind_condition,
            ),
            record,
        ),
        CorePotts.AbstractProposalEvaluationContext,
        record,
    )
    priority = _numeric_value(effect.priority)
    priority isa Real && isinteger(priority) || throw(ArgumentError(
        "relationship request priority must be structurally resolved"
    ))
    reads = _record_state_handles(ir, record, state_handles)
    return CorePotts.CompiledStageDescriptor(
        compiled_condition,
        _static_evaluator(
            CorePotts.LiteralExpression(zero(T)),
            CorePotts.AbstractProposalEvaluationContext,
            record,
        ),
        CorePotts.RelationshipCreateEffect(
            store_slot,
            endpoint_a,
            endpoint_b,
            payload,
            Int(priority),
        ),
        CorePotts.AcceptedCopyStage(),
        CorePotts.ResourceAccess(
            reads,
            (),
            CorePotts.ProposalContextFootprint(),
        ),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end
