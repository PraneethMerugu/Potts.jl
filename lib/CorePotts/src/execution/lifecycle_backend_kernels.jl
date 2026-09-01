# Portable fixed-capacity lifecycle transaction kernels and local device algorithms.

@kernel function _reset_lifecycle_backend_kernel!(
        plan, workspace, control, next_mcs
    )
    index = @index(Global, Linear)
    success = ProgramStatus()
    open = _lifecycle_backend_open(workspace)
    open && index <= length(control.candidate_status) &&
        (@inbounds control.candidate_status[index] = success)
    open && index <= length(control.state_rule_failure_rank) &&
        (@inbounds control.state_rule_failure_rank[index] = typemax(Int32))
    open && index == 1 && begin
        @inbounds workspace.request_count[1] = Int32(0)
        @inbounds workspace.selection.ready[1] = false
        @inbounds control.counters[_LIFECYCLE_CONTROL_DUE] = Int32(0)
        @inbounds control.counters[_LIFECYCLE_CONTROL_RETIRED] = Int32(0)
        due = false
        for descriptor in plan.descriptors
            due |= _lifecycle_due(descriptor, Int(next_mcs))
        end
        @inbounds control.counters[_LIFECYCLE_CONTROL_DUE] = Int32(due)
    end
    open && index <= length(workspace.active) && @inbounds begin
        workspace.active[index] = false
        workspace.filtered[index] = false
        workspace.filtered_detail[index] = LifecycleDetailNone
        workspace.planned_site_count[index] = Int32(0)
    end
    open && index <= length(workspace.partition_owner) && @inbounds begin
        workspace.partition_owner[index] = Int32(0)
    end
    open && index <= length(workspace.partition_labels) && @inbounds begin
        workspace.partition_labels[index] = UInt8(0)
        workspace.partition_scratch[index] = UInt8(0)
        workspace.planned_site_request[index] = Int32(0)
        workspace.site_seen[index] = false
        workspace.site_queue[index] = Int32(0)
    end
end


@kernel function _plan_lifecycle_effect_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        count = Int(_lifecycle_canonical_request_count(workspace))
        for position in 1:count
            request = Int(_lifecycle_canonical_request_slot(
                workspace, position
            ))
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _ProgramStatusSlot(
                    control.candidate_status, Int32(request)
                ),
            )
            reason = _plan_lifecycle_request_effect!(
                BackendLifecycleExecution(),
                state,
                plan,
                request_workspace,
                request,
                plan_class,
            )
            _record_lifecycle_planning_reason!(
                workspace,
                request_workspace,
                request,
                descriptor,
                reason,
            )
        end
    end
end

@inline function _record_lifecycle_planning_reason!(
        workspace, request_workspace, request, descriptor, reason
    )
    reason === :status_failure && return nothing
    reason === :ok && return nothing
    if descriptor.on_inadmissible === FilterLifecycleInadmissible
        @inbounds begin
            workspace.active[request] = false
            workspace.filtered[request] = true
            workspace.filtered_detail[request] =
                _lifecycle_detail_code(reason)
        end
    else
        _set_lifecycle_status!(
            request_workspace,
            ProgramStatusInadmissible;
            source = descriptor.source_handle,
            anchor = @inbounds(workspace.anchor[request]),
            detail = _lifecycle_detail_code(reason),
        )
    end
    return nothing
end

@inline function _lifecycle_request_generation_current(
        state, workspace, request
    )
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    return anchor <= 0 || (
        1 <= anchor <= length(state.cell_kinds) &&
        @inbounds(state.cell_generations[anchor]) == generation &&
        @inbounds(state.cell_kinds[anchor]) != 0
    )
end

@kernel function _plan_lifecycle_division_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        count = Int(_lifecycle_canonical_request_count(workspace))
        for position in 1:count
            request = Int(_lifecycle_canonical_request_slot(
                workspace, position
            ))
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _ProgramStatusSlot(
                    control.candidate_status, Int32(request)
                ),
            )
            reason = if _lifecycle_request_generation_current(
                    state, workspace, request
                )
                _plan_division!(
                    BackendLifecycleExecution(),
                    state,
                    plan,
                    request_workspace,
                    request,
                    descriptor,
                    plan_class.partition,
                    plan_class.side,
                )
            else
                _set_lifecycle_status!(
                    request_workspace,
                    ProgramStatusStaleGeneration;
                    anchor = @inbounds(workspace.anchor[request]),
                )
                :status_failure
            end
            _record_lifecycle_planning_reason!(
                workspace,
                request_workspace,
                request,
                descriptor,
                reason,
            )
        end
    end
end

@kernel function _validate_lifecycle_division_relationships_backend_kernel!(
        state, workspace, control
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        count = Int(_lifecycle_canonical_request_count(workspace))
        for position in 1:count
            request = Int(_lifecycle_canonical_request_slot(
                workspace, position
            ))
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            descriptor.effect === DivideCellLifecycleEffect || continue
            @inbounds(control.candidate_status[request].code) ===
                ProgramStatusSuccess || continue
            anchor = @inbounds workspace.anchor[request]
            _lifecycle_relationships_admissible(
                state, plan, descriptor, anchor
            ) && continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _ProgramStatusSlot(
                    control.candidate_status, Int32(request)
                ),
            )
            _record_lifecycle_planning_reason!(
                workspace,
                request_workspace,
                request,
                descriptor,
                :relationship_policy_rejected,
            )
        end
    end
end

@kernel function _replan_selected_lifecycle_division_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        selected = _lifecycle_selected_count(workspace)
        for position in 1:selected
            request = Int(_lifecycle_selected_request(workspace, position))
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _ProgramStatusSlot(
                    control.candidate_status, Int32(request)
                ),
            )
            reason = _plan_division!(
                BackendLifecycleExecution(),
                state,
                plan,
                request_workspace,
                request,
                descriptor,
                plan_class.partition,
                plan_class.side,
            )
            reason === :ok || reason === :status_failure ||
                _set_lifecycle_status!(
                    request_workspace,
                    ProgramStatusInvariant;
                    source = descriptor.source_handle,
                    anchor = @inbounds(workspace.anchor[request]),
                    detail = _lifecycle_detail_code(reason),
                )
        end
    end
end

@kernel function _clear_selected_division_workspace_backend_kernel!(
        plan, workspace, control
    )
    index = @index(Global, Linear)
    capacity = size(workspace.policy_workspace, 1)
    request = capacity == 0 ? 0 : div(index - 1, capacity) + 1
    slot = capacity == 0 ? 0 : rem(index - 1, capacity) + 1
    if request <= length(workspace.active) && slot <= capacity &&
            _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control) &&
            _lifecycle_request_selected(workspace, request)
        descriptor = @inbounds plan.descriptors[
            Int(workspace.descriptor[request])
        ]
        descriptor.effect === DivideCellLifecycleEffect &&
            @inbounds(workspace.policy_workspace[slot, request] =
                zero(eltype(workspace.policy_workspace)))
    end
end

@kernel function _stage_lifecycle_structure_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        selected = _lifecycle_selected_count(workspace)
        failed = false
        for position in 1:selected
            if !failed
                request = Int(_lifecycle_selected_request(workspace, position))
                descriptor = @inbounds state.program.lifecycle_plan.descriptors[
                    Int(workspace.descriptor[request])
                ]
                _lifecycle_plan_matches(descriptor, plan_class) || continue
                failed = !_stage_lifecycle_effect_base!(
                    BackendLifecycleExecution(),
                    state,
                    state.program.lifecycle_plan,
                    workspace,
                    request,
                    descriptor,
                    plan_class,
                )
            end
        end
    end
end

@kernel function _stage_lifecycle_relationships_backend_kernel!(
        state, workspace, control, action
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        selected = _lifecycle_selected_count(workspace)
        failed = false
        for position in 1:selected
            if !failed
                request = Int(_lifecycle_selected_request(workspace, position))
                failed = !_stage_lifecycle_request_relationships!(
                    BackendLifecycleExecution(),
                    state,
                    state.program.lifecycle_plan,
                    workspace,
                    request,
                    action,
                )
            end
        end
    end
end

@kernel function _stage_lifecycle_state_backend_kernel!(
        runtime, descriptors, plan, workspace, control, plan_class, action
    )
    request = @index(Global, Linear)
    if request <= length(workspace.active) &&
            _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control) &&
            _lifecycle_request_selected(workspace, request)
        descriptor = @inbounds descriptors[
            Int(workspace.descriptor[request])
        ]
        if _lifecycle_plan_matches(descriptor, plan_class)
            _apply_lifecycle_effect_state!(
                BackendLifecycleExecution(),
                runtime,
                plan,
                workspace,
                request,
                descriptor,
                plan_class,
                action,
                control.candidate_status,
                control.state_rule_failure_rank,
            )
        end
    end
end

@kernel function _finalize_lifecycle_effect_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        selected = _lifecycle_selected_count(workspace)
        retired = Int32(0)
        for position in 1:selected
            request = Int(_lifecycle_selected_request(workspace, position))
            descriptor = @inbounds state.program.lifecycle_plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            retired += Int32(_finalize_lifecycle_effect!(
                workspace, request, descriptor, plan_class
            ))
        end
        @inbounds control.counters[_LIFECYCLE_CONTROL_RETIRED] += retired
    end
end

@kernel function _validate_lifecycle_backend_kernel!(state, workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control) &&
            _lifecycle_selected_count(workspace) > 0
        _validate_staged_lifecycle!(
            BackendLifecycleExecution(),
            state,
            state.program.lifecycle_plan,
            workspace,
        )
    end
end

@kernel function _finalize_lifecycle_backend_kernel!(workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        @inbounds control.statistics[_PROGRAM_STAT_RETIRED] += UInt64(
            control.counters[_LIFECYCLE_CONTROL_RETIRED]
        )
    end
end

@kernel function _clear_lifecycle_policy_workspace_kernel!(workspace, control)
    index = @index(Global, Linear)
    if index <= length(workspace.policy_workspace) &&
            _lifecycle_backend_open(workspace)
        @inbounds workspace.policy_workspace[index] =
            zero(eltype(workspace.policy_workspace))
    end
end

@kernel function _validate_lifecycle_ownership_kernel!(
        ownership, workspace, control, capacity
    )
    site = @index(Global, Linear)
    if site <= length(ownership) && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        owner = @inbounds ownership[site]
        if owner > capacity
            @inbounds control.candidate_status[site] =
                _lifecycle_backend_status(
                    ProgramStatusInvariant;
                    anchor = owner,
                    detail = LifecycleDetailOwnershipExceedsCellCapacity,
                    maximum = capacity,
                )
        end
    end
end
