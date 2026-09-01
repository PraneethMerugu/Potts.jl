function _remove_all_incident!(state, anchor)
    while @inbounds(state.degree[anchor]) > 0
        edge = Int(@inbounds state.incident_edges[1, anchor])
        apply_validated_relationship_request!(
            state, RemoveRelationshipRequest(edge)
        )
    end
    return state
end

function _apply_relationship_rule!(
        state, runtime, workspace, descriptor, rule, anchor
    )
    if rule.action === RemoveIncidentLifecycleRelationship
        return _remove_all_incident!(state, anchor)
    elseif rule.action in (
            PreserveCompatibleLifecycleRelationship,
            RemoveIncompatibleLifecycleRelationship,
        )
        destination_kind = descriptor.destination_kind
        position = 1
        while position <= @inbounds(state.degree[anchor])
            edge = Int(@inbounds state.incident_edges[position, anchor])
            other = @inbounds state.endpoint_a[edge] == anchor ?
                state.endpoint_b[edge] : state.endpoint_a[edge]
            other_kind = @inbounds workspace.staged_cell_kinds[other]
            compatible = _relationship_kinds_match(
                destination_kind, other_kind, rule
            )
            if !compatible && rule.action === RemoveIncompatibleLifecycleRelationship
                apply_validated_relationship_request!(
                    state, RemoveRelationshipRequest(edge)
                )
            else
                position += 1
            end
        end
    end
    return state
end

function _apply_relationship_rule_action!(
        state, runtime, workspace, descriptor, rule, anchor,
        action_value::Val,
    )
    action = _lifecycle_relationship_action_value(action_value)
    rule.action === action || return state
    if action === RemoveIncidentLifecycleRelationship
        return _remove_all_incident!(state, anchor)
    end
    destination_kind = descriptor.destination_kind
    position = 1
    while position <= @inbounds(state.degree[anchor])
        edge = Int(@inbounds state.incident_edges[position, anchor])
        other = @inbounds state.endpoint_a[edge] == anchor ?
            state.endpoint_b[edge] : state.endpoint_a[edge]
        other_kind = @inbounds workspace.staged_cell_kinds[other]
        compatible = _relationship_kinds_match(
            destination_kind, other_kind, rule
        )
        if !compatible
            apply_validated_relationship_request!(
                state, RemoveRelationshipRequest(edge)
            )
        else
            position += 1
        end
    end
    return state
end

function _apply_lifecycle_relationship_rules!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        descriptor,
        anchor,
    )
    for offset in 0:(Int(descriptor.relationship_rule_count) - 1)
        rule = @inbounds plan.relationship_rules[
            Int(descriptor.relationship_rule_offset) + offset
        ]
        succeeded = if mode isa HostLifecycleExecution
            try
                _call_relationship_slot(
                    _apply_relationship_rule!,
                    workspace.staged_relationships,
                    rule.relationship_slot,
                    (runtime, workspace, descriptor, rule, Int(anchor)),
                )
                true
            catch
                false
            end
        else
            _call_relationship_slot(
                _apply_relationship_rule!,
                workspace.staged_relationships,
                rule.relationship_slot,
                (runtime, workspace, descriptor, rule, Int(anchor)),
            )
            true
        end
        if !succeeded
            return _set_lifecycle_status!(
                workspace,
                ProgramStatusInvariant;
                source = descriptor.source_handle,
                anchor,
                detail = LifecycleDetailRelationshipCommitInvalid,
            )
        end
    end
    return true
end

function _apply_lifecycle_relationship_rules!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        descriptor,
        anchor,
        action::Val,
    )
    for offset in 0:(Int(descriptor.relationship_rule_count) - 1)
        rule = @inbounds plan.relationship_rules[
            Int(descriptor.relationship_rule_offset) + offset
        ]
        _call_relationship_slot(
            _apply_relationship_rule_action!,
            workspace.staged_relationships,
            rule.relationship_slot,
            (runtime, workspace, descriptor, rule, Int(anchor), action),
        )
    end
    return true
end

function _allocated_generation(runtime, slot)
    generation = @inbounds runtime.cell_generations[slot]
    return iszero(generation) ? UInt32(1) : generation + UInt32(1)
end

function _stage_lifecycle_effect_base!(
        mode, runtime, plan, workspace, request, descriptor,
        ::_CreateLifecyclePlan,
    )
    allocation = _lifecycle_request_allocation(workspace, request)
    generation = _allocated_generation(runtime, allocation)
    @inbounds begin
        workspace.staged_cell_kinds[allocation] = descriptor.destination_kind
        workspace.staged_cell_generations[allocation] = generation
    end
    for position in 1:Int(workspace.planned_site_count[request])
        linear = Int(@inbounds workspace.planned_sites[position, request])
        @inbounds workspace.planned_site_request[linear] = Int32(request)
        _stage_owner_change!(
            mode, runtime, plan, workspace, linear, allocation
        ) || return false
    end
    return true
end

function _stage_lifecycle_effect_base!(
        mode, runtime, plan, workspace, request, descriptor,
        ::_RemoveLifecyclePlan,
    )
    anchor = @inbounds workspace.anchor[request]
    for record in _lifecycle_site_records(workspace, anchor)
        linear = Int(record.site)
        _stage_owner_change!(
            mode,
            runtime,
            plan,
            workspace,
            linear,
            -Int32(descriptor.replacement_medium),
        ) || return false
    end
    return true
end

@inline _stage_lifecycle_effect_base!(
    mode, runtime, plan, workspace, request, descriptor,
    ::_RetireLifecyclePlan,
) = true

@inline function _stage_lifecycle_effect_base!(
        mode, runtime, plan, workspace, request, descriptor,
        ::_TransitionLifecyclePlan,
    )
    anchor = @inbounds workspace.anchor[request]
    @inbounds workspace.staged_cell_kinds[anchor] = descriptor.destination_kind
    return true
end

function _stage_lifecycle_effect_base!(
        mode, runtime, plan, workspace, request, descriptor,
        ::_DivideLifecyclePlan,
    )
    anchor = @inbounds workspace.anchor[request]
    allocation = _lifecycle_request_allocation(workspace, request)
    generation = _allocated_generation(runtime, allocation)
    parent_kind = descriptor.parent_kind == 0 ?
        @inbounds(runtime.cell_kinds[anchor]) : descriptor.parent_kind
    daughter_kind = descriptor.daughter_kind == 0 ?
        @inbounds(runtime.cell_kinds[anchor]) : descriptor.daughter_kind
    @inbounds begin
        workspace.staged_cell_kinds[anchor] = parent_kind
        workspace.staged_cell_kinds[allocation] = daughter_kind
        workspace.staged_cell_generations[allocation] = generation
    end
    if @inbounds(workspace.partition_owner[anchor]) != request
        return _set_lifecycle_status!(
            workspace,
            ProgramStatusInvariant;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailDivisionPlanMissing,
        )
    end
    for record in _lifecycle_site_records(workspace, anchor)
        position = Int(_lifecycle_site_position(workspace, record.site))
        @inbounds workspace.partition_labels[position] == 2 || continue
        linear = Int(record.site)
        _stage_owner_change!(
            mode, runtime, plan, workspace, linear, allocation
        ) || return false
    end
    return true
end

@inline _apply_lifecycle_effect_relationships!(
    mode, runtime, plan, workspace, request, descriptor,
    ::_CreateLifecyclePlan,
) = true

@inline function _apply_lifecycle_effect_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    )
    return _apply_lifecycle_relationship_rules!(
        mode,
        runtime,
        plan,
        workspace,
        descriptor,
        @inbounds(workspace.anchor[request]),
    )
end

@inline function _apply_lifecycle_effect_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class,
        action::Val,
    )
    plan_class isa _CreateLifecyclePlan && return true
    return _apply_lifecycle_relationship_rules!(
        mode,
        runtime,
        plan,
        workspace,
        descriptor,
        @inbounds(workspace.anchor[request]),
        action,
    )
end

@inline _apply_lifecycle_pre_relationships!(
    mode, runtime, plan, workspace, request, descriptor, plan_class
) = true
@inline _apply_lifecycle_pre_relationships!(
    mode, runtime, plan, workspace, request, descriptor,
    plan_class::_RemoveLifecyclePlan,
) = _apply_lifecycle_effect_relationships!(
    mode, runtime, plan, workspace, request, descriptor, plan_class
)
@inline _apply_lifecycle_pre_relationships!(
    mode, runtime, plan, workspace, request, descriptor,
    plan_class::_RetireLifecyclePlan,
) = _apply_lifecycle_effect_relationships!(
    mode, runtime, plan, workspace, request, descriptor, plan_class
)
@inline _apply_lifecycle_post_relationships!(
    mode, runtime, plan, workspace, request, descriptor, plan_class
) = true
@inline _apply_lifecycle_post_relationships!(
    mode, runtime, plan, workspace, request, descriptor,
    plan_class::_TransitionLifecyclePlan,
) = _apply_lifecycle_effect_relationships!(
    mode, runtime, plan, workspace, request, descriptor, plan_class
)

@inline _apply_lifecycle_pre_relationships!(
    mode, runtime, plan, workspace, request, descriptor, plan_class,
    action::Val,
) = plan_class isa Union{_RemoveLifecyclePlan, _RetireLifecyclePlan} ?
    _apply_lifecycle_effect_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class, action
    ) : true

@inline _apply_lifecycle_post_relationships!(
    mode, runtime, plan, workspace, request, descriptor, plan_class,
    action::Val,
) = plan_class isa Union{_TransitionLifecyclePlan, _DivideLifecyclePlan} ?
    _apply_lifecycle_effect_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class, action
    ) : true
@inline _apply_lifecycle_post_relationships!(
    mode, runtime, plan, workspace, request, descriptor,
    plan_class::_DivideLifecyclePlan,
) = _apply_lifecycle_effect_relationships!(
    mode, runtime, plan, workspace, request, descriptor, plan_class
)

@inline _lifecycle_state_endpoints(
    workspace, request, ::_CreateLifecyclePlan
) = (Int32(0), _lifecycle_request_allocation(workspace, request))
@inline _lifecycle_state_endpoints(
    workspace, request, ::_RemoveLifecyclePlan
) = (@inbounds(workspace.anchor[request]), Int32(0))
@inline _lifecycle_state_endpoints(
    workspace, request, ::_RetireLifecyclePlan
) = (@inbounds(workspace.anchor[request]), Int32(0))
@inline _lifecycle_state_endpoints(
    workspace, request, ::_TransitionLifecyclePlan
) = (@inbounds(workspace.anchor[request]), Int32(0))
@inline _lifecycle_state_endpoints(
    workspace, request, ::_DivideLifecyclePlan
) = (
    @inbounds(workspace.anchor[request]),
    _lifecycle_request_allocation(workspace, request),
)
