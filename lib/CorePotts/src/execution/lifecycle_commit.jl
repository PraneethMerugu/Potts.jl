# Transaction-local state, relationship, tracker, and ownership commit logic.

@inline function _stage_owner_change!(runtime, plan, workspace, linear, new_owner)
    old_owner = @inbounds workspace.staged_ownership[linear]
    old_owner == new_owner && return true
    site = CartesianIndices(runtime.program.shape)[linear]
    source = tracker_source_view(
        runtime.program, workspace.staged_ownership
    )
    try
        commit_tracker_updates!(
            workspace.staged_trackers,
            runtime.program.tracker_plan,
            source,
            site,
            old_owner,
            new_owner,
        )
    catch
        return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            anchor = old_owner > 0 ? old_owner : new_owner,
            detail = LifecycleDetailTrackerCommitInvalid,
        )
    end
    @inbounds workspace.staged_ownership[linear] = new_owner
    for rule in plan.ownership_rules
        rule.action === ClearLifecycleOwnershipState || continue
        values = state_block(workspace.staged_descriptor_state, rule.handle).values
        @inbounds values[linear] = zero(eltype(values))
    end
    return true
end

@inline function _coerce_lifecycle_state_value(
        workspace, descriptor, anchor, values, value
    )
    converted = try
        convert(eltype(values), value)
    catch
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailStateValueInvalid,
        )
        return LifecycleEvaluationFailed()
    end
    finite = try
        isfinite(converted)
    catch
        true
    end
    finite || begin
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailStateValueInvalid,
        )
        return LifecycleEvaluationFailed()
    end
    return converted
end

@inline function _state_rule_value(
        runtime,
        plan,
        workspace,
        descriptor,
        rule,
        evaluator,
        request,
        source,
        destination,
        role,
    )
    source_generation = source > 0 ?
        @inbounds(runtime.cell_generations[source]) : UInt32(0)
    destination_generation = destination > 0 ?
        @inbounds(workspace.staged_cell_generations[destination]) : UInt32(0)
    anchor = source > 0 ? source : destination
    generation = source > 0 ? source_generation : destination_generation
    context = _LifecycleStateContext(
        runtime,
        descriptor.source_identity,
        descriptor.action_identity,
        descriptor.state_workspace_maximum,
        Int32(0),
        Int32(request),
        anchor,
        generation,
        source,
        source_generation,
        destination,
        destination_generation,
        role,
        rule.source_identity,
        rule.handle,
        _lifecycle_context_site(runtime, workspace, anchor),
        Int32(0),
        UInt16(descriptor.source_handle),
    )
    return _evaluate_lifecycle_checked(
        plan, evaluator, context, descriptor, workspace
    )
end

function _lifecycle_distribution_draw(
        runtime,
        workspace,
        descriptor,
        family,
        first_parameter,
        second_parameter,
        operation,
        destination,
        generation,
        daughter,
    )
    T = eltype(runtime.parameters)
    first_uniform = _lifecycle_uniform(
        T,
        runtime,
        LifecycleStateStream,
        operation,
        destination,
        generation,
        0;
        destination = true,
        draw = 0,
    )
    family == 1 && return first_uniform < T(first_parameter)
    family == 2 && return muladd(
        first_uniform, T(second_parameter) - T(first_parameter), T(first_parameter)
    )
    if family != 3
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor = destination,
            detail = LifecycleDetailUnknownDistribution,
        )
        return LifecycleEvaluationFailed()
    end
    iszero(second_parameter) && return T(first_parameter)
    second_uniform = _lifecycle_uniform(
        T,
        runtime,
        LifecycleStateStream,
        operation,
        destination,
        generation,
        0;
        destination = true,
        draw = 1,
    )
    normal = sqrt(-T(2) * log(first_uniform)) * cos(T(2pi) * second_uniform)
    return muladd(T(second_parameter), normal, T(first_parameter))
end

function _apply_lifecycle_state_rule!(
        rule,
        runtime,
        plan,
        workspace,
        descriptor,
        request::Int,
        source::Int32,
        destination::Int32,
    )
    values = state_block(
        workspace.staged_descriptor_state, rule.handle
    ).values
    source_generation = source > 0 ?
        @inbounds(runtime.cell_generations[source]) : UInt32(0)
    destination_generation = destination > 0 ?
        @inbounds(workspace.staged_cell_generations[destination]) : UInt32(0)
    if rule.action === InitializeLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, DestinationLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            workspace, descriptor, destination, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[destination] = value_a
    elseif rule.action === RetireToLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, SourceLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            workspace, descriptor, source, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[source] = value_a
    elseif rule.action === PreserveLifecycleState
        nothing
    elseif rule.action in (ResetLifecycleState, TransformLifecycleState)
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, SourceLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            workspace, descriptor, source, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[source] = value_a
    elseif rule.action === CopyDaughtersLifecycleState
        @inbounds values[destination] = values[source]
    elseif rule.action === PreserveParentResetDaughterLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            workspace, descriptor, destination, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[destination] = value_a
    elseif rule.action === ResetBothLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_b isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            workspace, descriptor, source, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _coerce_lifecycle_state_value(
            workspace, descriptor, destination, values, value_b
        )
        value_b isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = value_a
            values[destination] = value_b
        end
    elseif rule.action === SplitConservativelyLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        fraction_valid = try
            isfinite(value_a) && zero(value_a) <= value_a <= one(value_a)
        catch
            false
        end
        if !fraction_valid
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusEvaluator;
                source = descriptor.source_handle,
                anchor = source,
                detail = LifecycleDetailSplitFractionOutOfBounds,
            )
        end
        old = @inbounds values[source]
        fraction = value_a
        parent = old * fraction
        daughter = old - parent
        if eltype(values) <: Integer
            parent = rule.rounding === FloorLifecycleRounding ? floor(parent) :
                rule.rounding === CeilLifecycleRounding ? ceil(parent) :
                rule.rounding === NearestLifecycleRounding ? round(parent) : parent
            daughter = old - parent
        end
        parent = _coerce_lifecycle_state_value(
            workspace, descriptor, source, values, parent
        )
        parent isa LifecycleEvaluationFailed && return false
        daughter = _coerce_lifecycle_state_value(
            workspace, descriptor, destination, values, daughter
        )
        daughter isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = parent
            values[destination] = daughter
        end
    elseif rule.action === TransformDaughtersLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_b isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            workspace, descriptor, source, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _coerce_lifecycle_state_value(
            workspace, descriptor, destination, values, value_b
        )
        value_b isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = value_a
            values[destination] = value_b
        end
    elseif rule.action === RedrawDaughtersLifecycleState
        first_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        first_a isa LifecycleEvaluationFailed && return false
        second_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, ParentLifecycleStateRole,
        )
        second_a isa LifecycleEvaluationFailed && return false
        first_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_c, request,
            source, destination, DaughterLifecycleStateRole,
        )
        first_b isa LifecycleEvaluationFailed && return false
        second_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_d, request,
            source, destination, DaughterLifecycleStateRole,
        )
        second_b isa LifecycleEvaluationFailed && return false
        parent_value = _lifecycle_distribution_draw(
            runtime,
            workspace,
            descriptor,
            rule.parent_distribution,
            first_a,
            second_a,
            rule.parent_draw,
            source,
            source_generation,
            false,
        )
        parent_value isa LifecycleEvaluationFailed && return false
        daughter_value = _lifecycle_distribution_draw(
            runtime,
            workspace,
            descriptor,
            rule.daughter_distribution,
            first_b,
            second_b,
            rule.daughter_draw,
            destination,
            destination_generation,
            true,
        )
        daughter_value isa LifecycleEvaluationFailed && return false
        parent_value = _coerce_lifecycle_state_value(
            workspace, descriptor, source, values, parent_value
        )
        parent_value isa LifecycleEvaluationFailed && return false
        daughter_value = _coerce_lifecycle_state_value(
            workspace, descriptor, destination, values, daughter_value
        )
        daughter_value isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = parent_value
            values[destination] = daughter_value
        end
    else
        return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            source = descriptor.source_handle,
            anchor = source,
            detail = LifecycleDetailUnsupportedStatePolicy,
        )
    end
    return true
end

function _apply_lifecycle_state_rules!(
        runtime, plan, workspace, descriptor, request, source, destination
    )
    for offset in 0:(Int(descriptor.state_rule_count) - 1)
        index = Int(descriptor.state_rule_offset) + offset
        succeeded = call_lifecycle_state_rule(
            _apply_lifecycle_state_rule!,
            plan.state_rules,
            index,
            runtime,
            plan,
            workspace,
            descriptor,
            request,
            source,
            destination,
        )
        succeeded || return false
    end
    return true
end

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

function _apply_lifecycle_relationship_rules!(
        runtime, plan, workspace, descriptor, anchor
    )
    for offset in 0:(Int(descriptor.relationship_rule_count) - 1)
        rule = @inbounds plan.relationship_rules[
            Int(descriptor.relationship_rule_offset) + offset
        ]
        try
            _call_relationship_slot(
                _apply_relationship_rule!,
                workspace.staged_relationships,
                rule.relationship_slot,
                (runtime, workspace, descriptor, rule, Int(anchor)),
            )
        catch
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                source = descriptor.source_handle,
                anchor,
                detail = LifecycleDetailRelationshipCommitInvalid,
            )
        end
    end
    return true
end

function _allocated_generation(runtime, slot)
    generation = @inbounds runtime.cell_generations[slot]
    return iszero(generation) ? UInt32(1) : generation + UInt32(1)
end

function _apply_lifecycle_request!(runtime, plan, workspace, request)
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    anchor = @inbounds workspace.anchor[request]
    allocation = @inbounds workspace.allocation[request]
    if descriptor.effect === CreateCellLifecycleEffect
        generation = _allocated_generation(runtime, allocation)
        @inbounds begin
            workspace.staged_cell_kinds[allocation] = descriptor.destination_kind
            workspace.staged_cell_generations[allocation] = generation
        end
        for position in 1:Int(workspace.planned_site_count[request])
            linear = Int(@inbounds workspace.planned_sites[position, request])
            _stage_owner_change!(runtime, plan, workspace, linear, allocation) ||
                return -1
        end
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, Int32(0), allocation
        ) || return -1
    elseif descriptor.effect === RemoveCellLifecycleEffect
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        ) || return -1
        for position in _cell_site_range(workspace, anchor)
            linear = Int(@inbounds workspace.cell_sites[position])
            _stage_owner_change!(
                runtime,
                plan,
                workspace,
                linear,
                -Int32(descriptor.replacement_medium),
            ) || return -1
        end
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, anchor, Int32(0)
        ) || return -1
        @inbounds workspace.staged_cell_kinds[anchor] = 0
    elseif descriptor.effect === RetireCellLifecycleEffect
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        ) || return -1
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, anchor, Int32(0)
        ) || return -1
        @inbounds workspace.staged_cell_kinds[anchor] = 0
    elseif descriptor.effect === TransitionCellLifecycleEffect
        @inbounds workspace.staged_cell_kinds[anchor] = descriptor.destination_kind
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        ) || return -1
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, anchor, Int32(0)
        ) || return -1
    elseif descriptor.effect === DivideCellLifecycleEffect
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
            _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                source = descriptor.source_handle,
                anchor,
                detail = LifecycleDetailDivisionPlanMissing,
            )
            return -1
        end
        for position in _cell_site_range(workspace, anchor)
            @inbounds workspace.partition_labels[position] == 2 || continue
            linear = Int(@inbounds workspace.cell_sites[position])
            _stage_owner_change!(runtime, plan, workspace, linear, allocation) ||
                return -1
        end
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        ) || return -1
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, anchor, allocation
        ) || return -1
    end
    return descriptor.effect in (
        RemoveCellLifecycleEffect, RetireCellLifecycleEffect
    ) ? 1 : 0
end
