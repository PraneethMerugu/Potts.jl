# Accepted-copy assignment and bounded relationship-creation lowering.

function _stage_descriptor(
        ir::AnalyzedTermIR,
        record_index::Integer,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        state_layout::CorePotts.CompilerSPI.StateLayout,
        stage::CorePotts.CompilerSPI.AbstractCompiledStage,
        slot::Integer,
        effect_index::Integer = 1,
        ; history_descriptors, tracker_handles = nothing,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    arguments = first(record.normalized_payload)
    effect = arguments.effects[effect_index]
    effect isa Assign || throw(
        ArgumentError(
            "staged assignment descriptors require Assign"
        )
    )
    target_record = _stage_state_record(ir, record, effect.target)
    target_record === nothing && throw(
        ArgumentError(
            "staged assignment target does not resolve to declared state"
        )
    )
    target_arguments = _record_arguments(target_record)
    target_variable = get(target_arguments, :variable, nothing)
    target_shape = target_variable isa Symbolics.Arr ? Tuple(size(target_variable)) : ()
    value_root = _stage_root(ir, record_index, Symbol(:effect_, effect_index, :_value))
    value_shape = value_root === nothing ? () : ir.facts.shape[value_root]
    value_shape == target_shape || throw(
        PottsValidationError(
            :descriptor_lowering,
            (
                PottsDiagnostic(
                    :assignment_value_shape, record.identity, repr(effect.value),
                    record.identity.path, "logical value shape $target_shape",
                    "logical value shape $value_shape", (), record.source,
                ),
            ),
        )
    )
    target_root = _stage_root(ir, record_index, Symbol(:effect_, effect_index, :_target))
    target_unit = target_root === nothing ? :unknown : ir.facts.units[target_root]
    value_unit = if value_root !== nothing
        ir.facts.units[value_root]
    elseif _compiler_leaf_kind(effect.value, ir.source) === :literal &&
            effect.value isa Union{Number, Symbol}
        _literal_unit(effect.value)
    else
        :unknown
    end
    (
        !_is_unknown_unit(target_unit) && !_is_unknown_unit(value_unit) &&
            _unit_compatible(target_unit, value_unit)
    ) || throw(
        PottsValidationError(
            :descriptor_lowering,
            (
                PottsDiagnostic(
                    :assignment_value_units, record.identity, repr(effect.value),
                    record.identity.path, "units compatible with target $target_unit",
                    "assignment value units $value_unit", (), record.source,
                ),
            ),
        )
    )
    is_model_assignment =
        stage isa CorePotts.CompilerSPI.AfterMCSStage &&
        target_record.kind === :ModelState
    is_cell_assignment =
        stage isa CorePotts.CompilerSPI.AfterMCSStage &&
        target_record.kind === :CellState
    binding = stage isa CorePotts.CompilerSPI.AcceptedCopyStage ?
        CorePotts.CompilerSPI.ProposalTargetStageSite() :
        is_model_assignment ? CorePotts.CompilerSPI.ModelStageSite() :
        is_cell_assignment ? CorePotts.CompilerSPI.BoundCellStateValueOperation() :
        CorePotts.CompilerSPI.IterationStageSite()
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
        ; state_layout, history_descriptors, tracker_handles,
    )
    value = _stage_evaluator(
        ir,
        record_index,
        Symbol(:effect_, effect_index, :_value),
        effect.value,
        manifest,
        T,
        state_handles,
        draw_handles,
        binding,
        ; state_layout, history_descriptors, tracker_handles,
    )
    target = _stage_state_handle(ir, record, effect.target, state_handles)
    reads = _record_state_handles(ir, record, state_handles; expressions = (condition.expression, value.expression))
    target in reads || (reads = (reads..., target))
    if is_model_assignment || is_cell_assignment
        entries = Tuple(
            CorePotts.CompilerSPI.state_read_source(history_descriptors, state_layout, handle)
                for handle in reads
        )
        domains = is_model_assignment ? (:model,) : (:cell, :model)
        all(entry -> entry.schema.domain in domains, entries) || throw(
            ArgumentError(
                is_model_assignment ?
                    "a synchronous ModelState assignment may read only ModelState values and parameters" :
                    "a synchronous CellState assignment requires CellState or ModelState reads and parameters"
            )
        )
        all(entry -> entry.schema.domain !== :model || prod(entry.schema.shape; init = 1) == 1, entries) || throw(
            ArgumentError(
                "a synchronous assignment requires one logical value per model state"
            )
        )
    end
    cell_kind = if is_cell_assignment
        scope = _quantity_scope(ir.source.records, target_record)
        domain = scope === nothing ? arguments.domain : scope.binding.domain
        domain isa Cells || throw(ArgumentError("cell assignment requires cells(kind) or a scoped target"))
        kind = _compiled_kind_index(ir, scope === nothing ? record : target_record, domain.kind)
        kind === nothing && throw(ArgumentError("cell assignment kind does not resolve"))
        kind
    else
        nothing
    end
    return CorePotts.CompilerSPI.CompiledStageDescriptor(
        condition,
        value,
        is_model_assignment ?
            CorePotts.CompilerSPI.ModelAssignmentEffect(target) :
            is_cell_assignment ?
            CorePotts.CompilerSPI.CellAssignmentEffect(target, cell_kind) :
            CorePotts.CompilerSPI.SiteAssignmentEffect(target),
        stage,
        CorePotts.CompilerSPI.ResourceAccess(
            reads,
            (target,),
            _record_read_footprint(ir, record_index),
            is_model_assignment ? CorePotts.CompilerSPI.ModelFootprint() :
                is_cell_assignment ? CorePotts.CompilerSPI.OwnerFootprint() :
                _site_write_footprint(ir, stage),
            CorePotts.CompilerSPI.ExclusiveWriteAccess(),
        ),
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
        effect_index::Integer = 1,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    arguments = first(record.normalized_payload)
    effect = arguments.effects[effect_index]
    effect isa Create ||
        throw(
        ArgumentError(
            "a relationship-create descriptor requires a Create effect"
        )
    )
    relationship = _resource_record(
        ir.source, record, :RelationshipState, effect.relationship
    )
    relationship === nothing && throw(
        ArgumentError(
            "relationship-create effect does not resolve to a declared store"
        )
    )
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
        CorePotts.CompilerSPI.ProposalTargetStageSite(),
    )
    endpoint_a = _stage_evaluator(
        ir,
        record_index,
        Symbol(:effect_, effect_index, :_endpoint_a),
        effect.endpoint_a,
        manifest,
        T,
        state_handles,
        draw_handles,
        CorePotts.CompilerSPI.ProposalTargetStageSite(),
    )
    endpoint_b = _stage_evaluator(
        ir,
        record_index,
        Symbol(:effect_, effect_index, :_endpoint_b),
        effect.endpoint_b,
        manifest,
        T,
        state_handles,
        draw_handles,
        CorePotts.CompilerSPI.ProposalTargetStageSite(),
    )

    relationship_options = _record_options(relationship)
    declared_payload = get(
        relationship_options, :payload, NamedTuple()
    )
    declared_payload isa NamedTuple && effect.payload isa NamedTuple ||
        throw(
        ArgumentError(
            "relationship payload declarations and requests must be named tuples"
        )
    )
    keys(effect.payload) == keys(declared_payload) || throw(
        ArgumentError(
            "relationship-create payload must exactly match its declared schema"
        )
    )
    payload = Tuple(
        _stage_evaluator(
                ir,
                record_index,
                Symbol(:effect_, effect_index, :_payload_, name),
                getproperty(effect.payload, name),
                manifest,
                T,
                state_handles,
                draw_handles,
                CorePotts.CompilerSPI.ProposalTargetStageSite(),
            )
            for name in keys(declared_payload)
    )

    kind_condition = _compiler_synthesized_operation_expression(
        ir.graph,
        _potts_relationship_endpoint_kinds,
        (
            endpoint_a.expression,
            endpoint_b.expression,
            CorePotts.CompilerSPI.LiteralExpression(endpoint_policy.kind_a),
            CorePotts.CompilerSPI.LiteralExpression(endpoint_policy.kind_b),
        ),
        record,
    )
    compiled_condition = _static_evaluator(
        _compiler_synthesized_operation_expression(
            ir.graph,
            (&),
            (
                condition.expression,
                kind_condition,
            ),
            record,
        ),
        CorePotts.CompilerSPI.AbstractProposalEvaluationContext,
        record,
    )
    priority = _numeric_value(effect.priority)
    priority isa Real && isinteger(priority) || throw(
        ArgumentError(
            "relationship request priority must be structurally resolved"
        )
    )
    reads = _record_state_handles(ir, record, state_handles)
    return CorePotts.CompilerSPI.CompiledStageDescriptor(
        compiled_condition,
        _static_evaluator(
            CorePotts.CompilerSPI.LiteralExpression(zero(T)),
            CorePotts.CompilerSPI.AbstractProposalEvaluationContext,
            record,
        ),
        CorePotts.CompilerSPI.RelationshipCreateEffect(
            store_slot,
            endpoint_a,
            endpoint_b,
            payload,
            Int(priority),
        ),
        CorePotts.CompilerSPI.AcceptedCopyStage(),
        CorePotts.CompilerSPI.ResourceAccess(
            reads,
            (store_slot,),
            _record_read_footprint(ir, record_index),
            CorePotts.CompilerSPI.EmptyFootprint(),
            CorePotts.CompilerSPI.DeferredRequestWriteAccess(),
        ),
        _stage_support(ir, record_index),
        record_index,
        slot,
    )
end
