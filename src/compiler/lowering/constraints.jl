# Prelaunch parameter-domain constraints and descriptor-plan assembly.

function _parameter_only_expression(expression)
    expression isa Union{
        CorePotts.CompilerSPI.LiteralExpression,
        CorePotts.CompilerSPI.ParameterExpression,
    } && return true
    expression isa CorePotts.CompilerSPI.OperationExpression || return false
    return all(_parameter_only_expression, expression.arguments)
end

function _parameter_constraint(
        expression::CorePotts.CompilerSPI.AbstractStaticExpression,
        predicate::UInt8,
        node::NormalizedTermNode,
        record::QualifiedStatement,
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
    return CorePotts.CompilerSPI.ParameterDomainConstraint(
        _static_evaluator(
            expression,
            CorePotts.CompilerSPI.AbstractProbeEvaluationContext,
            record,
        ),
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
        family_node.payload isa LiteralPayload &&
        family_node.payload.value isa Integer || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :nonliteral_draw_family,
            node.source,
            String(node.operation),
            node.source.path,
            "a statically known scalar distribution family",
            repr(_normalized_payload_key(family_node.payload)),
            (),
            UnknownSource(),
        ),),
    ))
    return Int(family_node.payload.value)
end

function _draw_domain_constraints(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
    ) where {T <: AbstractFloat}
    length(node.operands) == 4 || error(
        "validated draw operation has invalid normalized arity"
    )
    family = _draw_family_code(ir.graph, node)
    record = ir.source.records[node.record]
    cache = Dict{Int32, CorePotts.CompilerSPI.AbstractStaticExpression}()
    first_parameter = _lower_static_node(
        ir.graph,
        ir,
        node.operands[2],
        manifest,
        T,
        state_handles,
        draw_handles,
        cache,
    )
    second_parameter = _lower_static_node(
        ir.graph,
        ir,
        node.operands[3],
        manifest,
        T,
        state_handles,
        draw_handles,
        cache,
    )
    zero_expression = CorePotts.CompilerSPI.LiteralExpression(zero(T))
    one_expression = CorePotts.CompilerSPI.LiteralExpression(one(T))
    if family == 1
        lower = _compiler_synthesized_operation_expression(
            ir.graph,
            (>=),
            (first_parameter, zero_expression),
            record,
        )
        upper = _compiler_synthesized_operation_expression(
            ir.graph,
            (<=),
            (first_parameter, one_expression),
            record,
        )
        return (
            _parameter_constraint(lower, 0x03, node, record),
            _parameter_constraint(upper, 0x03, node, record),
        )
    elseif family == 2
        ordered = _compiler_synthesized_operation_expression(
            ir.graph,
            (<),
            (first_parameter, second_parameter),
            record,
        )
        return (_parameter_constraint(ordered, 0x03, node, record),)
    elseif family == 3
        positive = _compiler_synthesized_operation_expression(
            ir.graph,
            (>),
            (second_parameter, zero_expression),
            record,
        )
        return (_parameter_constraint(positive, 0x03, node, record),)
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
        draw_handles,
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
                    ir, node, manifest, T, state_handles, draw_handles
                ),
            )
            continue
        end
        # Unit/totality analysis admits `power` only after proving a literal
        # integer exponent. The compiled floating-point evaluator is total for
        # that closed case, so no runtime parameter predicate remains.
        node.operation === :power && continue
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
        cache = Dict{Int32, CorePotts.CompilerSPI.AbstractStaticExpression}()
        operand = _lower_static_node(
            ir.graph,
            ir,
            only(node.operands),
            manifest,
            T,
            state_handles,
            draw_handles,
            cache,
        )
        predicate = node.operation === :logarithm ? UInt8(0x01) : UInt8(0x02)
        push!(
            constraints,
            _parameter_constraint(
                operand,
                predicate,
                node,
                ir.source.records[node.record],
            ),
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
        groups = (groups..., CorePotts.CompilerSPI.ConstraintGroup(typed))
    end
    return groups
end

function _lower_descriptor_plan(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
        relationship_endpoint_policies,
    ) where {T <: AbstractFloat}
    state_layout, state_handles = _state_layout(ir, T)
    workspace_layout, workspace_handles = _workspace_layout(ir, T)
    draw_handles = _draw_operation_handles(ir)
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
                draw_handles,
            ),
        )
    end
    descriptor_sources = Int32[
        descriptor.source_handle
        for descriptor in descriptors
    ]
    allunique(descriptor_sources) || throw(ArgumentError(
        "proposal lowering requires exactly one descriptor occurrence per source statement"
    ))
    groups = _descriptor_groups(descriptors)
    constraints = _domain_constraints(
        ir, manifest, T, state_handles, draw_handles
    )
    domain_resources = _hamiltonian_domain_resources(
        ir, relationship_endpoint_policies
    )
    fingerprint = _sha256_hex(
        "potts-descriptor-execution-plan-v2",
        ir.structural_key,
        Tuple((
            group.split,
            length(group.instances),
            group.state_handles,
            group.workspace_handles,
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
    plan = CorePotts.CompilerSPI.DescriptorExecutionPlan(
        groups,
        state_layout,
        workspace_layout,
        constraints,
        [record.identity for record in ir.source.records],
        Int32(length(descriptors)),
        fingerprint,
        domain_resources,
    )
    return (; plan, state_handles, draw_handles)
end
