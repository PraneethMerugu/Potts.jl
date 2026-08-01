# Relationship and lifecycle process lowering.

function _relationship_process_stage_descriptor(
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
    length(arguments.effects) == 1 &&
        only(arguments.effects) isa Union{Remove, Retune} ||
        throw(ArgumentError(
            "a relationship stage requires exactly one Remove or Retune effect"
        ))
    effect = only(arguments.effects)
    relationship = _resource_record(
        ir.source, record, :RelationshipState, effect.relationship
    )
    relationship === nothing && throw(ArgumentError(
        "relationship request does not resolve to a declared store"
    ))
    store_slot = _relationship_endpoint_policy(
        relationship_endpoint_policies, relationship.identity
    ).slot
    arguments.domain isa Edges && _same_domain_resource(
        arguments.domain.relationship, effect.relationship
    ) || throw(ArgumentError(
        "relationship request must iterate the affected relationship store"
    ))
    condition = _stage_evaluator(
        ir,
        record_index,
        :expression,
        false,
        manifest,
        T,
        state_handles,
        draw_handles,
        nothing,
    )
    maximum_degree = Int(_numeric_value(get(
        _record_options(relationship), :maximum_degree, 0
    )))
    reads = _record_state_handles(ir, record, state_handles)
    compiled_effect = if effect isa Remove
        CorePotts.RelationshipRemoveEffect(store_slot)
    else
        declared_payload = get(
            _record_options(relationship), :payload, NamedTuple()
        )
        effect.payload isa NamedTuple &&
            keys(effect.payload) == keys(declared_payload) || throw(
                ArgumentError(
                    "relationship-retune payload must exactly match its declared schema"
                )
            )
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
                nothing,
            )
            for name in keys(declared_payload)
        )
        CorePotts.RelationshipRetuneEffect(store_slot, payload)
    end
    return CorePotts.CompiledStageDescriptor(
        condition,
        _static_evaluator(
            CorePotts.LiteralExpression(zero(T)),
            CorePotts.AbstractRelationshipStageEvaluationContext,
            record,
        ),
        compiled_effect,
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            reads,
            (),
            CorePotts.IncidentRelationshipFootprint(maximum_degree),
        ),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end
