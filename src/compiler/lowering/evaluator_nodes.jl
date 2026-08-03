# Recursive lowering from analyzed term nodes to concrete CorePotts expressions.

function _lower_static_node(
        graph::NormalizedTermGraph,
        ir::AnalyzedTermIR,
        node_index::Int32,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles::Dict{QualifiedStatementID, CorePotts.StateHandle},
        draw_handles::Dict{Tuple{Tuple, Symbol}, UInt16},
        cache::Dict{Int32, CorePotts.AbstractStaticExpression},
        state_binding = nothing,
    ) where {T <: AbstractFloat}
    haskey(cache, node_index) && return cache[node_index]
    node = graph.nodes[node_index]
    expression = if node.payload_kind === :literal
        _static_literal(node.payload.value, manifest, T)
    elseif node.payload_kind === :parameter
        _static_parameter(node.payload.value, manifest, T)
    elseif node.payload_kind in (:state, :variable)
        handle = _state_handle_for_leaf(ir, node, state_handles)
        handle === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_state_handle,
                node.source,
                repr(_normalized_payload_key(node.payload)),
                node.source.path,
                "one qualified state resource",
                "no matching state block",
                (),
                UnknownSource(),
            ),),
        ))
        state_expression = CorePotts.StateExpression(handle)
        if state_binding === nothing
            state_expression
        else
            operation = state_binding isa CorePotts.ProposalTargetStageSite ?
                _potts_proposal_bound_state_value :
                state_binding isa CorePotts.IterationStageSite ?
                _potts_iteration_bound_state_value :
                state_binding isa Symbol && startswith(
                    String(state_binding), "lifecycle_"
                ) ?
                _potts_lifecycle_bound_state_value :
                throw(ArgumentError("unsupported compiled state binding"))
            _compiler_synthesized_operation_expression(
                graph,
                operation,
                (state_expression,),
                ir.source.records[node.record],
                semantic_role = state_binding isa Symbol ? state_binding :
                    _record_operation_role(ir.source.records[node.record]),
                semantic_phase = state_binding isa Symbol ? :Lifecycle :
                    _record_operation_phase(ir.source.records[node.record]),
            )
        end
    elseif node.payload_kind === :proposal_context
        # Context operations consume these compiler tokens. They are never
        # looked up by name in the executable.
        CorePotts.LiteralExpression(Int32(0))
    elseif node.payload_kind === :spatial_relation
        handle = _compiled_resource_leaf(
            ir,
            node,
            :SpatialRelation,
        )
        handle === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_spatial_relation_handle,
                node.source,
                repr(_normalized_payload_key(node.payload)),
                node.source.path,
                "a declared finite SpatialRelation",
                "no matching spatial relation",
                (),
                UnknownSource(),
            ),),
        ))
        CorePotts.LiteralExpression(handle)
    elseif node.payload_kind === :relationship_set
        handle = _compiled_resource_leaf(
            ir,
            node,
            :RelationshipState,
        )
        handle === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_relationship_handle,
                node.source,
                repr(_normalized_payload_key(node.payload)),
                node.source.path,
                "a declared RelationshipState",
                "no matching relationship resource",
                (),
                UnknownSource(),
            ),),
        ))
        CorePotts.LiteralExpression(handle)
    elseif node.payload_kind === :relationship_payload
        CorePotts.LiteralExpression(
            _relationship_payload_slot(ir, node)
        )
    elseif node.payload_kind in (
            :site_anchor, :cell_anchor, :contact_anchor,
            :relationship_context,
        )
        _energy_anchor_expression(node.payload_kind, node)
    elseif node.payload_kind === :kind
        kind = _compiled_kind_leaf(ir, node)
        kind === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_kind_handle,
                node.source,
                repr(_normalized_payload_key(node.payload)),
                node.source.path,
                "a declared value-level kind index",
                "no matching cell or medium kind",
                (),
                UnknownSource(),
            ),),
        ))
        CorePotts.LiteralExpression(kind)
    elseif node.payload_kind === :draw
        draw_handle = _draw_handle_for_leaf(draw_handles, node)
        draw_handle === nothing ? throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_symbolic_leaf,
                node.source,
                repr(_normalized_payload_key(node.payload)),
                node.source.path,
                "a parameter, context token, state handle, or RNG handle",
                "unresolved symbolic leaf",
                (),
                UnknownSource(),
            ),),
        )) : CorePotts.LiteralExpression(draw_handle)
    else
        operation = _static_operation_callable(node)
        tracker_keys = _operation_tracker_keys(ir, node, T)
        qualified_keys = filter(
            key -> key isa CorePotts.QualifiedTrackerKey,
            tracker_keys,
        )
        if !isempty(qualified_keys)
            length(qualified_keys) == 1 || throw(ArgumentError(
                "V1 operations admit at most one qualified tracker binding"
            ))
            key = only(qualified_keys)
            operation = CorePotts.QualifiedTrackerOperation(
                operation,
                key.quantity,
                key.source_handle,
            )
        end
        arguments = Tuple(
            _lower_static_node(
                graph,
                ir,
                operand,
                manifest,
                T,
                state_handles,
                draw_handles,
                cache,
                state_binding,
            )
            for operand in node.operands
        )
        if operation isa CorePotts.ContextOperation
            CorePotts.ContextExpression(operation)
        else
            _bounded_static_operation(operation, arguments)
        end
    end
    cache[node_index] = expression
    return expression
end
