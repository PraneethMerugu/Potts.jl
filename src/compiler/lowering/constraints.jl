# Prelaunch parameter-domain constraints and descriptor-plan assembly.

function _parameter_only_expression(expression)
    expression isa Union{
        CorePotts.LiteralExpression,
        CorePotts.ParameterExpression,
    } && return true
    expression isa CorePotts.OperationExpression || return false
    return all(_parameter_only_expression, expression.arguments)
end

function _parameter_constraint(
        expression::CorePotts.AbstractStaticExpression,
        predicate::UInt8,
        node::NormalizedTermNode,
    )
    _parameter_only_expression(expression) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :runtime_dependent_partial_operation,
            node.source,
            String(node.operation),
            node.source.path,
            "a parameter-only validated domain or a total device operation",
            "runtime state/context dependent domain",
            (),
            UnknownSource(),
        ),),
    ))
    return CorePotts.ParameterDomainConstraint(
        CorePotts.StaticEvaluator(expression),
        predicate,
        node.record,
    )
end

function _draw_family_code(
        graph::NormalizedTermGraph,
        node::NormalizedTermNode,
    )
    family_node = graph.nodes[first(node.operands)]
    family_node.payload_kind === :literal &&
        family_node.payload isa Integer || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :nonliteral_draw_family,
            node.source,
            String(node.operation),
            node.source.path,
            "a statically known scalar distribution family",
            repr(family_node.payload),
            (),
            UnknownSource(),
        ),),
    ))
    return Int(family_node.payload)
end

function _draw_domain_constraints(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
    ) where {T <: AbstractFloat}
    length(node.operands) == 4 || error(
        "validated draw operation has invalid normalized arity"
    )
    family = _draw_family_code(ir.graph, node)
    cache = Dict{Int32, CorePotts.AbstractStaticExpression}()
    first_parameter = _lower_static_node(
        ir.graph,
        ir,
        node.operands[2],
        manifest,
        T,
        state_handles,
        cache,
    )
    second_parameter = _lower_static_node(
        ir.graph,
        ir,
        node.operands[3],
        manifest,
        T,
        state_handles,
        cache,
    )
    zero_expression = CorePotts.LiteralExpression(zero(T))
    one_expression = CorePotts.LiteralExpression(one(T))
    if family == 1
        lower = CorePotts.OperationExpression(
            CorePotts.operation_callable(Val(:greater_equal), v"1.0.0"),
            first_parameter,
            zero_expression,
        )
        upper = CorePotts.OperationExpression(
            CorePotts.operation_callable(Val(:less_equal), v"1.0.0"),
            first_parameter,
            one_expression,
        )
        return (
            _parameter_constraint(lower, 0x03, node),
            _parameter_constraint(upper, 0x03, node),
        )
    elseif family == 2
        ordered = CorePotts.OperationExpression(
            CorePotts.operation_callable(Val(:less), v"1.0.0"),
            first_parameter,
            second_parameter,
        )
        return (_parameter_constraint(ordered, 0x03, node),)
    elseif family == 3
        positive = CorePotts.OperationExpression(
            CorePotts.operation_callable(Val(:greater), v"1.0.0"),
            second_parameter,
            zero_expression,
        )
        return (_parameter_constraint(positive, 0x03, node),)
    elseif family == 4
        throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :nonscalar_distribution_in_proposal_term,
                node.source,
                String(node.operation),
                node.source.path,
                "a scalar Bernoulli, Uniform, or Normal distribution",
                "UnitVector",
                (),
                UnknownSource(),
            ),),
        ))
    end
    throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :unknown_draw_family,
            node.source,
            String(node.operation),
            node.source.path,
            "a registered scalar distribution family",
            string(family),
            (),
            UnknownSource(),
        ),),
    ))
end

function _domain_constraints(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
    ) where {T <: AbstractFloat}
    constraints = Any[]
    for node in ir.graph.nodes
        node.transfer === nothing && continue
        node.transfer.totality in (
            :domain_checked, :requires_prelaunch_validation
        ) || continue
        if node.operation === :draw
            append!(
                constraints,
                _draw_domain_constraints(
                    ir, node, manifest, T, state_handles
                ),
            )
            continue
        end
        node.operation in (:logarithm, :square_root) || throw(
            PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :unsupported_totality_rule,
                    node.source,
                    String(node.operation),
                    node.source.path,
                    "a specified prelaunch domain predicate",
                    String(node.operation),
                    (),
                    UnknownSource(),
                ),),
            ),
        )
        length(node.operands) == 1 || error(
            "validated unary operation has invalid normalized arity"
        )
        cache = Dict{Int32, CorePotts.AbstractStaticExpression}()
        operand = _lower_static_node(
            ir.graph,
            ir,
            only(node.operands),
            manifest,
            T,
            state_handles,
            cache,
        )
        predicate = node.operation === :logarithm ? UInt8(0x01) : UInt8(0x02)
        push!(
            constraints,
            _parameter_constraint(operand, predicate, node),
        )
    end
    keys = DataType[]
    values = Vector{Vector{Any}}()
    for constraint in constraints
        key = typeof(constraint)
        index = findfirst(==(key), keys)
        if index === nothing
            push!(keys, key)
            push!(values, Any[constraint])
        else
            push!(values[index], constraint)
        end
    end
    groups = ()
    for (key, entries) in zip(keys, values)
        typed = key[entry for entry in entries]
        groups = (groups..., CorePotts.ConstraintGroup(typed))
    end
    return groups
end

function _lower_descriptor_plan(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
    ) where {T <: AbstractFloat}
    state_layout, state_handles = _state_layout(ir, T)
    workspace_layout, workspace_handles = _workspace_layout(ir, T)
    descriptors = Any[]
    for candidate in ir.candidates
        candidate.category in (
            :hamiltonian, :drive, :constraint, :modifier,
        ) || continue
        _descriptor_candidate_enabled(
            ir.source.records[candidate.record]
        ) || continue
        push!(
            descriptors,
            _proposal_descriptor(
                ir,
                candidate,
                manifest,
                T,
                state_handles,
                workspace_layout,
                workspace_handles,
            ),
        )
    end
    descriptor_sources = Int32[
        descriptor.source_handle
        for descriptor in descriptors
    ]
    allunique(descriptor_sources) || throw(ArgumentError(
        "V1 requires exactly one proposal descriptor occurrence per source statement"
    ))
    groups = _descriptor_groups(descriptors)
    constraints = _domain_constraints(ir, manifest, T, state_handles)
    domain_resources = _hamiltonian_domain_resources(ir)
    fingerprint = _sha256_hex(
        "potts-descriptor-execution-plan-v2",
        ir.structural_key,
        Tuple((
            group.split,
            length(group.launch.instances),
            group.launch.state_handles,
            group.launch.workspace_handles,
        ) for group in groups),
        Tuple((
            schema.identity.path,
            schema.identity.name,
            schema.version,
            schema.domain,
            schema.element_type,
            schema.shape,
            schema.capacity,
        ) for schema in state_layout.schemas),
        Tuple((
            schema.identity.path,
            schema.identity.name,
            schema.version,
            schema.element_type,
            schema.shape,
            schema.capacity,
        ) for schema in workspace_layout.schemas),
        domain_resources.contact_offsets,
        domain_resources.contact_starts,
        domain_resources.contact_counts,
        domain_resources.relationship_slots,
    )
    return CorePotts.DescriptorExecutionPlan(
        groups,
        state_layout,
        workspace_layout,
        constraints,
        [record.identity for record in ir.source.records],
        Int32(length(descriptors)),
        fingerprint,
        domain_resources,
    )
end
