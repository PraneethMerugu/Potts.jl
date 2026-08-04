# Transaction-local state, relationship, tracker, and ownership commit logic.

@inline function _commit_lifecycle_tracker_updates!(
        ::HostLifecycleExecution,
        workspace,
        runtime,
        source,
        site,
        old_owner,
        new_owner,
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
        return false
    end
    return true
end

@inline function _commit_lifecycle_tracker_updates!(
        ::BackendLifecycleExecution,
        workspace,
        runtime,
        source,
        site,
        old_owner,
        new_owner,
    )
    commit_tracker_updates!(
        workspace.staged_trackers,
        runtime.program.tracker_plan,
        source,
        site,
        old_owner,
        new_owner,
    )
    return true
end

@inline function _stage_owner_change!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        linear,
        new_owner,
    )
    old_owner = @inbounds workspace.staged_ownership[linear]
    old_owner == new_owner && return true
    site = CartesianIndices(runtime.program.shape)[linear]
    source = tracker_source_view(
        runtime.program, workspace.staged_ownership
    )
    if !_commit_lifecycle_tracker_updates!(
            mode,
            workspace,
            runtime,
            source,
            site,
            old_owner,
            new_owner,
        )
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
        ::HostLifecycleExecution,
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

@inline function _coerce_lifecycle_state_value(
        ::BackendLifecycleExecution,
        workspace,
        descriptor,
        anchor,
        values,
        value,
    )
    converted = convert(eltype(values), value)
    if converted isa AbstractFloat && !isfinite(converted)
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
        mode::AbstractLifecycleExecutionMode,
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
    destination_generation = if destination <= 0
        UInt32(0)
    elseif descriptor.effect in (
            CreateCellLifecycleEffect, DivideCellLifecycleEffect,
        )
        _allocated_generation(runtime, destination)
    else
        @inbounds runtime.cell_generations[destination]
    end
    anchor = source > 0 ? source : destination
    generation = source > 0 ? source_generation : destination_generation
    planned = _LifecycleRequestView(
        runtime,
        workspace,
        descriptor,
        Int32(request),
    )
    context = _LifecycleStateContext(
        runtime,
        planned,
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
        mode, plan, evaluator, context, descriptor, workspace
    )
end

@inline function _lifecycle_distribution_draw(
        runtime,
        workspace,
        descriptor,
        family::UInt8,
        first_parameter::T,
        second_parameter::T,
        operation::UInt16,
        destination::Int32,
        generation::UInt32,
        daughter::Bool,
    ) where {T <: AbstractFloat}
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

@inline function _lifecycle_fraction_valid(
        ::HostLifecycleExecution, value
    )
    return try
        isfinite(value) && zero(value) <= value <= one(value)
    catch
        false
    end
end


@inline _lifecycle_fraction_valid(::BackendLifecycleExecution, value) =
    isfinite(value) && zero(value) <= value <= one(value)

function _apply_lifecycle_state_rule_action!(
        rule,
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        descriptor,
        request::Int,
        source::Int32,
        destination::Int32,
        action_plan::Val,
    )
    action = _lifecycle_state_action_value(action_plan)
    rule.action === action || return true
    values = state_block(
        workspace.staged_descriptor_state, rule.handle
    ).values
    source_generation = source > 0 ?
        @inbounds(runtime.cell_generations[source]) : UInt32(0)
    destination_generation = destination > 0 ?
        @inbounds(workspace.staged_cell_generations[destination]) : UInt32(0)
    if action === InitializeLifecycleState
        value_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, DestinationLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, destination, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[destination] = value_a
    elseif action === RetireToLifecycleState
        value_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, SourceLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, source, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[source] = value_a
    elseif action === PreserveLifecycleState
        nothing
    elseif action in (ResetLifecycleState, TransformLifecycleState)
        value_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, SourceLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, source, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[source] = value_a
    elseif action === CopyDaughtersLifecycleState
        @inbounds values[destination] = values[source]
    elseif action === PreserveParentResetDaughterLifecycleState
        value_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, destination, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[destination] = value_a
    elseif action === ResetBothLifecycleState
        value_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_b isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, source, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, destination, values, value_b
        )
        value_b isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = value_a
            values[destination] = value_b
        end
    elseif action === SplitConservativelyLifecycleState
        value_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        fraction_valid = _lifecycle_fraction_valid(mode, value_a)
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
            mode, workspace, descriptor, source, values, parent
        )
        parent isa LifecycleEvaluationFailed && return false
        daughter = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, destination, values, daughter
        )
        daughter isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = parent
            values[destination] = daughter
        end
    elseif action === TransformDaughtersLifecycleState
        value_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_b isa LifecycleEvaluationFailed && return false
        value_a = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, source, values, value_a
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, destination, values, value_b
        )
        value_b isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = value_a
            values[destination] = value_b
        end
    elseif action === RedrawDaughtersLifecycleState
        first_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        first_a isa LifecycleEvaluationFailed && return false
        second_a = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, ParentLifecycleStateRole,
        )
        second_a isa LifecycleEvaluationFailed && return false
        first_b = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_c, request,
            source, destination, DaughterLifecycleStateRole,
        )
        first_b isa LifecycleEvaluationFailed && return false
        second_b = _state_rule_value(
            mode, runtime, plan, workspace, descriptor, rule, rule.evaluator_d, request,
            source, destination, DaughterLifecycleStateRole,
        )
        second_b isa LifecycleEvaluationFailed && return false
        T = eltype(runtime.parameters)
        parent_value = _lifecycle_distribution_draw(
            runtime,
            workspace,
            descriptor,
            rule.parent_distribution,
            T(first_a),
            T(second_a),
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
            T(first_b),
            T(second_b),
            rule.daughter_draw,
            destination,
            destination_generation,
            true,
        )
        daughter_value isa LifecycleEvaluationFailed && return false
        parent_value = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, source, values, parent_value
        )
        parent_value isa LifecycleEvaluationFailed && return false
        daughter_value = _coerce_lifecycle_state_value(
            mode, workspace, descriptor, destination, values, daughter_value
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

function _apply_lifecycle_state_rule!(
        rule,
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        descriptor,
        request::Int,
        source::Int32,
        destination::Int32,
    )
    action = rule.action
    action === InitializeLifecycleState && return _apply_lifecycle_state_rule_action!(
        rule, mode, runtime, plan, workspace, descriptor, request, source,
        destination, Val(InitializeLifecycleState),
    )
    action === RetireToLifecycleState && return _apply_lifecycle_state_rule_action!(
        rule, mode, runtime, plan, workspace, descriptor, request, source,
        destination, Val(RetireToLifecycleState),
    )
    action === PreserveLifecycleState && return _apply_lifecycle_state_rule_action!(
        rule, mode, runtime, plan, workspace, descriptor, request, source,
        destination, Val(PreserveLifecycleState),
    )
    action === ResetLifecycleState && return _apply_lifecycle_state_rule_action!(
        rule, mode, runtime, plan, workspace, descriptor, request, source,
        destination, Val(ResetLifecycleState),
    )
    action === TransformLifecycleState && return _apply_lifecycle_state_rule_action!(
        rule, mode, runtime, plan, workspace, descriptor, request, source,
        destination, Val(TransformLifecycleState),
    )
    action === CopyDaughtersLifecycleState && return _apply_lifecycle_state_rule_action!(
        rule, mode, runtime, plan, workspace, descriptor, request, source,
        destination, Val(CopyDaughtersLifecycleState),
    )
    action === PreserveParentResetDaughterLifecycleState &&
        return _apply_lifecycle_state_rule_action!(
            rule, mode, runtime, plan, workspace, descriptor, request, source,
            destination, Val(PreserveParentResetDaughterLifecycleState),
        )
    action === ResetBothLifecycleState && return _apply_lifecycle_state_rule_action!(
        rule, mode, runtime, plan, workspace, descriptor, request, source,
        destination, Val(ResetBothLifecycleState),
    )
    action === SplitConservativelyLifecycleState &&
        return _apply_lifecycle_state_rule_action!(
            rule, mode, runtime, plan, workspace, descriptor, request, source,
            destination, Val(SplitConservativelyLifecycleState),
        )
    action === TransformDaughtersLifecycleState &&
        return _apply_lifecycle_state_rule_action!(
            rule, mode, runtime, plan, workspace, descriptor, request, source,
            destination, Val(TransformDaughtersLifecycleState),
        )
    action === RedrawDaughtersLifecycleState &&
        return _apply_lifecycle_state_rule_action!(
            rule, mode, runtime, plan, workspace, descriptor, request, source,
            destination, Val(RedrawDaughtersLifecycleState),
        )
    return _set_lifecycle_status!(
        workspace,
        LifecycleStatusInvariant;
        source = descriptor.source_handle,
        anchor = source,
        detail = LifecycleDetailUnsupportedStatePolicy,
    )
end

function _apply_lifecycle_state_rules!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        descriptor,
        request,
        source,
        destination,
    )
    for offset in 0:(Int(descriptor.state_rule_count) - 1)
        index = Int(descriptor.state_rule_offset) + offset
        succeeded = call_lifecycle_state_rule(
            _apply_lifecycle_state_rule!,
            plan.state_rules,
            index,
            mode,
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

function _apply_lifecycle_state_rules!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        descriptor,
        request,
        source,
        destination,
        action::Val,
    )
    for offset in 0:(Int(descriptor.state_rule_count) - 1)
        index = Int(descriptor.state_rule_offset) + offset
        succeeded = call_lifecycle_state_rule(
            _apply_lifecycle_state_rule_action!,
            plan.state_rules,
            index,
            mode,
            runtime,
            plan,
            workspace,
            descriptor,
            request,
            source,
            destination,
            action,
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
                LifecycleStatusInvariant;
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
    allocation = @inbounds workspace.allocation[request]
    generation = _allocated_generation(runtime, allocation)
    @inbounds begin
        workspace.staged_cell_kinds[allocation] = descriptor.destination_kind
        workspace.staged_cell_generations[allocation] = generation
    end
    for position in 1:Int(workspace.planned_site_count[request])
        linear = Int(@inbounds workspace.planned_sites[position, request])
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
    for position in _cell_site_range(workspace, anchor)
        linear = Int(@inbounds workspace.cell_sites[position])
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
    allocation = @inbounds workspace.allocation[request]
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
            LifecycleStatusInvariant;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailDivisionPlanMissing,
        )
    end
    for position in _cell_site_range(workspace, anchor)
        @inbounds workspace.partition_labels[position] == 2 || continue
        linear = Int(@inbounds workspace.cell_sites[position])
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
) = (Int32(0), @inbounds(workspace.allocation[request]))
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
    @inbounds(workspace.allocation[request]),
)

@inline function _apply_lifecycle_effect_state!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    )
    source, destination = _lifecycle_state_endpoints(
        workspace, request, plan_class
    )
    return _apply_lifecycle_state_rules!(
        mode,
        runtime,
        plan,
        workspace,
        descriptor,
        request,
        source,
        destination,
    )
end

@inline function _apply_lifecycle_effect_state!(
        mode, runtime, plan, workspace, request, descriptor, plan_class,
        action::Val,
    )
    source, destination = _lifecycle_state_endpoints(
        workspace, request, plan_class
    )
    return _apply_lifecycle_state_rules!(
        mode,
        runtime,
        plan,
        workspace,
        descriptor,
        request,
        source,
        destination,
        action,
    )
end

@inline _finalize_lifecycle_effect!(
    workspace, request, descriptor, ::_CreateLifecyclePlan
) = 0
@inline _finalize_lifecycle_effect!(
    workspace, request, descriptor, ::_TransitionLifecyclePlan
) = 0
@inline _finalize_lifecycle_effect!(
    workspace, request, descriptor, ::_DivideLifecyclePlan
) = 0
@inline function _finalize_lifecycle_effect!(
        workspace, request, descriptor, ::_RemoveLifecyclePlan
    )
    @inbounds workspace.staged_cell_kinds[workspace.anchor[request]] = 0
    return 1
end
@inline function _finalize_lifecycle_effect!(
        workspace, request, descriptor, ::_RetireLifecyclePlan
    )
    @inbounds workspace.staged_cell_kinds[workspace.anchor[request]] = 0
    return 1
end

function _apply_lifecycle_request_effect!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    )
    _apply_lifecycle_pre_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    ) || return -1
    _stage_lifecycle_effect_base!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    ) || return -1
    _apply_lifecycle_post_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    ) || return -1
    _apply_lifecycle_effect_state!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    ) || return -1
    return _finalize_lifecycle_effect!(
        workspace, request, descriptor, plan_class
    )
end

@inline function _lifecycle_request_plan_class(descriptor)
    descriptor.effect === CreateCellLifecycleEffect &&
        return _CreateLifecyclePlan()
    descriptor.effect === RemoveCellLifecycleEffect &&
        return _RemoveLifecyclePlan()
    descriptor.effect === RetireCellLifecycleEffect &&
        return _RetireLifecyclePlan()
    descriptor.effect === TransitionCellLifecycleEffect &&
        return _TransitionLifecyclePlan()
    descriptor.effect === DivideCellLifecycleEffect &&
        return _DivideLifecyclePlan()
    return nothing
end

function _apply_lifecycle_request!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        request,
    )
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    plan_class = _lifecycle_request_plan_class(descriptor)
    plan_class === nothing && return -1
    return _apply_lifecycle_request_effect!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    )
end

@inline function _stage_lifecycle_request_structure!(
        mode, runtime, plan, workspace, request
    )
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    plan_class = _lifecycle_request_plan_class(descriptor)
    plan_class === nothing && return false
    return _stage_lifecycle_effect_base!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    )
end

@inline function _stage_lifecycle_request_relationships!(
        mode, runtime, plan, workspace, request
    )
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    plan_class = _lifecycle_request_plan_class(descriptor)
    plan_class === nothing && return false
    _apply_lifecycle_pre_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    ) || return false
    return _apply_lifecycle_post_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    )
end

@inline function _stage_lifecycle_request_relationships!(
        mode, runtime, plan, workspace, request, action::Val
    )
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    plan_class = _lifecycle_request_plan_class(descriptor)
    plan_class === nothing && return false
    _apply_lifecycle_pre_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class, action
    ) || return false
    return _apply_lifecycle_post_relationships!(
        mode, runtime, plan, workspace, request, descriptor, plan_class, action
    )
end

@inline function _stage_lifecycle_request_state!(
        mode, runtime, plan, workspace, request
    )
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    plan_class = _lifecycle_request_plan_class(descriptor)
    plan_class === nothing && return false
    return _apply_lifecycle_effect_state!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    )
end

@inline function _finalize_lifecycle_request!(plan, workspace, request)
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    plan_class = _lifecycle_request_plan_class(descriptor)
    plan_class === nothing && return -1
    return _finalize_lifecycle_effect!(
        workspace, request, descriptor, plan_class
    )
end

_apply_lifecycle_request!(runtime, plan, workspace, request) =
    _apply_lifecycle_request!(
        HostLifecycleExecution(), runtime, plan, workspace, request
    )
