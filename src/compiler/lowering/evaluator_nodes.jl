# Recursive lowering from analyzed term nodes to concrete CorePotts expressions.

function _operand_order_is_observable(graph, node_index::Int32)
    node = graph.nodes[Int(node_index)]
    node.payload isa DrawBindingPayload && return true
    transfer = node.transfer
    transfer === nothing || (
        transfer.purity === :pure && transfer.totality === :total
    ) || return true
    return any(
        operand -> _operand_order_is_observable(graph, operand),
        node.operands,
    )
end

function _scalar_product_is_commutatively_canonicalizable(
        graph,
        ir,
        node::NormalizedTermNode,
    )
    transfer = node.transfer
    return transfer !== nothing &&
        transfer.identity === :multiply &&
        transfer.owner === :Potts &&
        transfer.serialization_identity == "potts-operation:multiply:v1" &&
        length(node.operands) == 2 &&
        all(operand -> ir.facts.shape[Int(operand)] == (), node.operands) &&
        all(
            operand -> !_operand_order_is_observable(graph, operand),
            node.operands,
        )
end

function _operational_expression_shape_key(graph, ir, node_index::Int32)
    node = graph.nodes[Int(node_index)]
    operand_keys = String[
        _operational_expression_shape_key(graph, ir, operand)
        for operand in node.operands
    ]
    _scalar_product_is_commutatively_canonicalizable(graph, ir, node) &&
        sort!(operand_keys)
    # Runtime expression topology depends on semantic roles and shapes, not on
    # declaration spelling. Values and qualified identities stay in payloads.
    payload_role = if node.payload isa StateBindingPayload
        owner = _state_record_for_leaf(ir.source, node)
        owner === nothing ? (:state, :unresolved) :
            (:state, _state_sample_record(ir.source, owner).kind)
    elseif node.payload isa VariableBindingPayload
        (:variable,)
    elseif node.payload isa ParameterBindingPayload
        (:parameter,)
    elseif node.payload isa LiteralPayload
        (:literal, ir.facts.result_type[Int(node_index)])
    else
        (node.payload_kind,)
    end
    return _sha256_hex(
        "potts-operational-expression-shape-v1",
        node.operation,
        node.schema_version,
        payload_role,
        ir.facts.shape[Int(node_index)],
        ir.facts.result_type[Int(node_index)],
        Tuple(operand_keys),
    )
end

function _operational_operand_order(graph, ir, node::NormalizedTermNode)
    _scalar_product_is_commutatively_canonicalizable(graph, ir, node) ||
        return node.operands
    return sort(
        node.operands;
        by = operand -> _operational_expression_shape_key(graph, ir, operand),
    )
end

function _bound_state_expression(graph, ir, node, handle, owner, state_binding)
    expression = CorePotts.CompilerSPI.StateExpression(handle)
    sample = owner === nothing ? nothing : _state_sample_record(ir.source, owner)
    operation = if sample !== nothing && sample.kind === :ModelState
        _potts_model_bound_state_value
    elseif state_binding === nothing
        return expression
    elseif state_binding isa CorePotts.CompilerSPI.ProposalTargetStageSite
        _potts_proposal_bound_state_value
    elseif state_binding isa CorePotts.CompilerSPI.IterationStageSite
        _potts_iteration_bound_state_value
    elseif state_binding isa CorePotts.CompilerSPI.ModelStageSite
        _potts_model_bound_state_value
    elseif state_binding isa CorePotts.CompilerSPI.BoundCellStateValueOperation
        _potts_cell_bound_state_value
    elseif state_binding isa Symbol && startswith(String(state_binding), "lifecycle_")
        _potts_lifecycle_bound_state_value
    else
        throw(ArgumentError("unsupported compiled state binding"))
    end
    record = ir.source.records[node.record]
    return _compiler_synthesized_operation_expression(graph, operation, (expression,), record;
        semantic_role = state_binding isa Symbol ? state_binding : _record_operation_role(record),
        semantic_phase = state_binding isa Symbol ? :Lifecycle : _record_operation_phase(record))
end

function _operation_reference_factor(ir, node, manifest)
    units = ir.facts.units
    result_unit = units[Int(node.identity)]
    _is_polymorphic_zero_unit(result_unit) && return 1.0
    rule = node.transfer.unit_rule
    arithmetic = rule === :arithmetic && node.operation in (:multiply, :divide, :power)
    (arithmetic || rule === :square_root) || return 1.0
    raw_scales = map(index -> _expression_reference_scale(units[index], manifest), node.operands)
    raw_result_scale = _expression_reference_scale(result_unit, manifest)
    all(==(1), raw_scales) && raw_result_scale == 1 && return 1.0
    # Julia 1.12 scopes this precision to the task without changing the caller's
    # default. Wide intermediates avoid overflow before the final scalar cast.
    return setprecision(BigFloat, 256) do
        operand_scales = map(BigFloat, raw_scales)
        result_scale = BigFloat(raw_result_scale)
        scale = if rule === :square_root
            sqrt(only(operand_scales))
        elseif node.operation === :multiply
            prod(operand_scales)
        elseif node.operation === :divide
            operand_scales[1] / operand_scales[2]
        else
            exponent = _literal_integer_exponent(node, ir.graph)
            exponent === nothing && error("validated power has no literal integer exponent")
            first(operand_scales)^exponent
        end
        return scale / result_scale
    end
end

function _scaled_operation_expression(expression, ir, node, manifest, ::Type{T}, state_binding) where {T <: AbstractFloat}
    factor = _operation_reference_factor(ir, node, manifest)
    factor == 1 && return expression
    converted = T(factor)
    isfinite(converted) && converted > zero(T) || throw(
        PottsValidationError(
            :descriptor_lowering, (
                PottsDiagnostic(
                    :expression_reference_scale, node.source, String(node.operation), node.source.path,
                    "a finite positive reference conversion representable by $T", string(factor), (),
                    ir.source.records[Int(node.record)].source,
                ),
            ),
        )
    )
    record = ir.source.records[Int(node.record)]
    return _compiler_synthesized_operation_expression(
        ir.graph, *,
        (CorePotts.CompilerSPI.LiteralExpression(converted), expression), record;
        semantic_role = state_binding isa Symbol ? state_binding : _record_operation_role(record),
        semantic_phase = state_binding isa Symbol ? :Lifecycle : _record_operation_phase(record)
    )
end

function _lower_static_node(
        graph::NormalizedTermGraph,
        ir::AnalyzedTermIR,
        node_index::Int32,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles::Dict{QualifiedStatementID, CorePotts.CompilerSPI.StateHandle},
        draw_handles::Dict{Tuple{Tuple, Symbol}, CorePotts.CompilerSPI.RNGOperationKey},
        cache::Dict{Int32, CorePotts.CompilerSPI.AbstractStaticExpression},
        state_binding = nothing,
        workspace_slices = nothing,
        ; state_layout = nothing, history_descriptors = (), tracker_handles = nothing,
    ) where {T <: AbstractFloat}
    haskey(cache, node_index) && return cache[node_index]
    node = graph.nodes[node_index]
    expression = if node.payload_kind === :literal
        _static_literal(node.payload.value, manifest, T)
    elseif node.payload_kind === :parameter
        _static_parameter(node.payload.value, manifest, T; graph, record = ir.source.records[node.record])
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
        owner = _state_record_for_leaf(ir.source, node)
        _bound_state_expression(graph, ir, node, handle, owner, state_binding)
    elseif node.payload_kind === :proposal_context
        # Context operations consume these compiler tokens. They are never
        # looked up by name in the executable.
        CorePotts.CompilerSPI.LiteralExpression(Int32(0))
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
        CorePotts.CompilerSPI.LiteralExpression(handle)
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
        CorePotts.CompilerSPI.LiteralExpression(handle)
    elseif node.payload_kind === :relationship_payload
        CorePotts.CompilerSPI.LiteralExpression(
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
        CorePotts.CompilerSPI.LiteralExpression(kind)
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
        )) : CorePotts.CompilerSPI.LiteralExpression(draw_handle)
    elseif _is_site_aggregate(node)
        tracker_handles === nothing && throw(ArgumentError("aggregate reads require the canonical tracker lowering handles"))
        cell = _lower_static_node(graph, ir, node.operands[3], manifest, T, state_handles, draw_handles,
            cache, state_binding, workspace_slices; state_layout, history_descriptors, tracker_handles)
        if _is_unit_count(graph, node)
            _compiler_synthesized_operation_expression(graph, cell_volume, (cell,), ir.source.records[node.record])
        else
            key = tracker_handles[Int(node.identity)]
            key isa CorePotts.CompilerSPI.QualifiedTrackerKey ||
                throw(ArgumentError("aggregate read has no analyzed tracker handle"))
            operation = CorePotts.CompilerSPI.QualifiedTrackerOperation(node.callable, key.quantity, key.source_handle)
            CorePotts.CompilerSPI.OperationExpression(operation, (cell,))
        end
    elseif _is_history_sample_projection(node)
        owner, amount = _history_sample_operand(ir.source, graph, node)
        state_layout === nothing && throw(ArgumentError("history sample lowering requires the canonical state layout"))
        handle = CorePotts.CompilerSPI.history_sample_handle(history_descriptors, state_layout, state_handles[owner.identity], amount)
        _bound_state_expression(graph, ir, node, handle, owner, state_binding)
    else
        operation = _static_operation_callable(node)
        if workspace_slices !== nothing && haskey(workspace_slices, node_index)
            slice = workspace_slices[node_index]
            operation = CorePotts.CompilerSPI.LifecycleWorkspaceOperation(
                operation, slice.offset, slice.maximum
            )
        end
        tracker_source = _tracker_projection_operand(node, graph)
        if tracker_source !== nothing
            descriptors = _operation_tracker_descriptors(
                ir, tracker_source, T)
            all(descriptor ->
                CorePotts.CompilerSPI.tracker_contract(descriptor).storage isa
                    CorePotts.CompilerSPI.DenseOwnerScalarStorage,
                descriptors) || throw(PottsValidationError(
                    :descriptor_lowering,
                    (PottsDiagnostic(
                        :unsupported_tracker_projection_storage,
                        node.source,
                        repr(tracker_source.transfer.identity),
                        node.source.path,
                        "one direct dense-scalar tracker quantity",
                        "structured tracker storage",
                        (),
                        ir.source.records[Int(node.record)].source,
                    ),),
                ))
        end
        tracker_keys = _operation_tracker_keys(ir, node, T)
        qualified_keys = filter(
            key -> key isa CorePotts.CompilerSPI.QualifiedTrackerKey,
            tracker_keys,
        )
        if tracker_source === nothing && !isempty(qualified_keys)
            length(qualified_keys) == 1 || throw(ArgumentError(
                "executable operations admit at most one qualified tracker binding"
            ))
            key = only(qualified_keys)
            operation = CorePotts.CompilerSPI.QualifiedTrackerOperation(
                operation,
                key.quantity,
                key.source_handle,
            )
        end
        ordered_operands = _operational_operand_order(graph, ir, node)
        arguments = if tracker_source === nothing
            Tuple(map(enumerate(ordered_operands)) do indexed
                index, operand = indexed
                if node.transfer.identity === :bounded_fold && index == 1
                    operand_node = graph.nodes[operand]
                    if operand_node.payload_kind === :literal
                        fold = operand_node.payload.value
                        if fold isa LocalMath.BoundedFold ||
                                fold isa _GatherReduction
                            return CorePotts.CompilerSPI.LiteralExpression(
                                _materialize_checked_gather_fold(
                                    ir, node, graph, fold, T))
                        end
                    end
                end
                return _lower_static_node(
                    graph,
                    ir,
                    operand,
                    manifest,
                    T,
                    state_handles,
                    draw_handles,
                    cache,
                    state_binding,
                    workspace_slices,
                    ; state_layout, history_descriptors, tracker_handles,
                )
            end)
        else
            length(tracker_keys) == 1 || throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :ambiguous_tracker_projection,
                    node.source,
                    repr(tracker_source.transfer.identity),
                    node.source.path,
                    "one canonical tracker quantity",
                    "$(length(tracker_keys)) tracker quantities",
                    (),
                    ir.source.records[Int(node.record)].source,
                ),),
            ))
            Tuple(map(enumerate(ordered_operands)) do indexed
                index, operand = indexed
                index == 2 && return CorePotts.CompilerSPI.LiteralExpression(
                    only(tracker_keys))
                if node.transfer.identity === :bounded_fold && index == 1
                    operand_node = graph.nodes[operand]
                    if operand_node.payload_kind === :literal
                        fold = operand_node.payload.value
                        if fold isa LocalMath.BoundedFold ||
                                fold isa _GatherReduction
                            return CorePotts.CompilerSPI.LiteralExpression(
                                _materialize_checked_gather_fold(
                                    ir, node, graph, fold, T))
                        end
                    end
                end
                return _lower_static_node(
                    graph,
                    ir,
                    operand,
                    manifest,
                    T,
                    state_handles,
                    draw_handles,
                    cache,
                    state_binding,
                    workspace_slices,
                    ; state_layout, history_descriptors, tracker_handles,
                )
            end)
        end
        if operation isa CorePotts.CompilerSPI.ContextOperation
            CorePotts.CompilerSPI.ContextExpression(operation)
        else
            _scaled_operation_expression(_bounded_static_operation(operation, arguments), ir, node, manifest, T, state_binding)
        end
    end
    cache[node_index] = expression
    return expression
end
