# Portable fixed-capacity lifecycle transaction kernels and local device algorithms.

@kernel function _reset_lifecycle_backend_kernel!(
        plan, workspace, control, next_mcs
    )
    index = @index(Global, Linear)
    success = LifecycleStatusPayload()
    open = _lifecycle_backend_open(workspace)
    open && index <= length(control.candidate_status) &&
        (@inbounds control.candidate_status[index] = success)
    open && index <= length(control.state_rule_failure_rank) &&
        (@inbounds control.state_rule_failure_rank[index] = typemax(Int32))
    open && index == 1 && begin
        @inbounds workspace.request_count[1] = Int32(0)
        @inbounds control.counters[_LIFECYCLE_CONTROL_DUE] = Int32(0)
        @inbounds control.counters[_LIFECYCLE_CONTROL_SELECTED] = Int32(0)
        @inbounds control.counters[_LIFECYCLE_CONTROL_RETIRED] = Int32(0)
        due = false
        for descriptor in plan.descriptors
            due |= _lifecycle_due(descriptor, Int(next_mcs))
        end
        @inbounds control.counters[_LIFECYCLE_CONTROL_DUE] = Int32(due)
    end
    open && index <= length(control.site_keys) &&
        (@inbounds control.site_keys[index] = typemax(UInt64))
    open && index <= length(control.request_scan) &&
        (@inbounds control.request_scan[index] = Int32(0))
    open && index <= length(workspace.active) && @inbounds begin
        workspace.active[index] = false
        workspace.selected[index] = false
        workspace.filtered[index] = false
        workspace.filtered_detail[index] = LifecycleDetailNone
        workspace.planned_site_count[index] = Int32(0)
        workspace.allocation[index] = Int32(0)
        workspace.canonical_order[index] = Int32(0)
        workspace.conflict_seen[index] = false
    end
    open && index <= length(workspace.cell_site_starts) && @inbounds begin
        workspace.cell_site_starts[index] = Int32(0)
        workspace.cell_site_counts[index] = Int32(0)
        workspace.cell_site_cursor[index] = Int32(0)
        workspace.free_slots[index] = Int32(0)
        workspace.representative_site[index] = Int32(0)
        workspace.partition_owner[index] = Int32(0)
    end
    open && index <= length(workspace.site_position) && @inbounds begin
        workspace.partition_labels[index] = UInt8(0)
        workspace.partition_scratch[index] = UInt8(0)
        workspace.cell_sites[index] = Int32(0)
        workspace.site_position[index] = Int32(0)
        workspace.planned_site_request[index] = Int32(0)
        workspace.site_seen[index] = false
        workspace.site_queue[index] = Int32(0)
    end
end

@kernel function _mark_lifecycle_requests_kernel!(workspace, control)
    request = @index(Global, Linear)
    if request <= length(control.request_scan) &&
            _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        @inbounds control.request_scan[request] =
            Int32(workspace.active[request])
    end
end

@kernel function _compact_lifecycle_requests_kernel!(workspace, control)
    request = @index(Global, Linear)
    if request <= length(control.request_scan) &&
            _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        position = @inbounds control.request_scan[request]
        if @inbounds(workspace.active[request])
            @inbounds workspace.canonical_order[position] = Int32(request)
        end
        if request == length(control.request_scan)
            @inbounds workspace.request_count[1] = position
        end
    end
end

@kernel function _sort_lifecycle_backend_kernel!(state, workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        _sort_lifecycle_requests!(
            BackendLifecycleExecution(),
            state,
            state.program.lifecycle_plan,
            workspace,
        )
    end
end


@kernel function _plan_lifecycle_effect_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        count = Int(lifecycle_request_count(workspace))
        for position in 1:count
            request = Int(@inbounds workspace.canonical_order[position])
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _LifecycleStatusSlot(
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
            LifecycleStatusInadmissible;
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
        count = Int(lifecycle_request_count(workspace))
        for position in 1:count
            request = Int(@inbounds workspace.canonical_order[position])
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _LifecycleStatusSlot(
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
                    LifecycleStatusStaleGeneration;
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
        count = Int(lifecycle_request_count(workspace))
        for position in 1:count
            request = Int(@inbounds workspace.canonical_order[position])
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            descriptor.effect === DivideCellLifecycleEffect || continue
            @inbounds(control.candidate_status[request].code) ===
                LifecycleStatusSuccess || continue
            anchor = @inbounds workspace.anchor[request]
            _lifecycle_relationships_admissible(
                state, plan, descriptor, anchor
            ) && continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _LifecycleStatusSlot(
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
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        for position in 1:selected
            request = Int(@inbounds workspace.canonical_order[position])
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _LifecycleStatusSlot(
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
                    LifecycleStatusInvariant;
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
    if request <= length(workspace.selected) && slot <= capacity &&
            _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control) &&
            @inbounds(workspace.selected[request])
        descriptor = @inbounds plan.descriptors[
            Int(workspace.descriptor[request])
        ]
        descriptor.effect === DivideCellLifecycleEffect &&
            @inbounds(workspace.policy_workspace[slot, request] =
                zero(eltype(workspace.policy_workspace)))
    end
end

@kernel function _reduce_lifecycle_planning_status_kernel!(workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        count = Int(lifecycle_request_count(workspace))
        for position in 1:count
            request = Int(@inbounds workspace.canonical_order[position])
            status = @inbounds control.candidate_status[request]
            if status.code !== LifecycleStatusSuccess
                @inbounds workspace.status[1] = status
                break
            end
        end
    end
end

@kernel function _select_lifecycle_backend_kernel!(state, workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        selected = if _resolve_lifecycle_conflicts!(
                state, plan, workspace
            )
            _preflight_lifecycle_capacity!(state, plan, workspace)
        else
            -1
        end
        @inbounds control.counters[_LIFECYCLE_CONTROL_SELECTED] =
            Int32(max(selected, 0))
    end
end

@kernel function _stage_lifecycle_structure_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        failed = false
        for position in 1:selected
            if !failed
                request = Int(@inbounds workspace.canonical_order[position])
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
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        failed = false
        for position in 1:selected
            if !failed
                request = Int(@inbounds workspace.canonical_order[position])
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
    if request <= length(workspace.selected) &&
            _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control) &&
            @inbounds(workspace.selected[request])
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
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        retired = Int32(0)
        for position in 1:selected
            request = Int(@inbounds workspace.canonical_order[position])
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
            @inbounds(control.counters[_LIFECYCLE_CONTROL_SELECTED]) > 0
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

@kernel function _lifecycle_scan_step_kernel!(
        destination, source, workspace, control, offset::Int32
    )
    index = @index(Global, Linear)
    if index <= length(source) && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        value = @inbounds source[index]
        index > offset && (value += @inbounds source[index - offset])
        @inbounds destination[index] = value
    end
end

@kernel function _lifecycle_sort_step_kernel!(
        keys, workspace, control, span::Int32, stride::Int32
    )
    index = @index(Global, Linear)
    if index <= length(keys) && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        zero_based = index - 1
        partner = xor(zero_based, Int(stride)) + 1
        if partner > index && partner <= length(keys)
            left = @inbounds keys[index]
            right = @inbounds keys[partner]
            ascending = (zero_based & Int(span)) == 0
            if (ascending && left > right) || (!ascending && left < right)
                @inbounds begin
                    keys[index] = right
                    keys[partner] = left
                end
            end
        end
    end
end

function _enqueue_lifecycle_scan!(workspace, control, backend, launch)
    source = control.request_scan
    scratch = control.request_scan_scratch
    length(source) == length(scratch) || throw(ArgumentError(
        "lifecycle scan buffers must have equal lengths"
    ))
    offset = 1
    while offset < length(source)
        scan_step = launch(_lifecycle_scan_step_kernel!)
        scan_step(
            scratch,
            source,
            workspace,
            control,
            Int32(offset);
            ndrange = length(source),
        )
        source, scratch = scratch, source
        offset <<= 1
    end
    if source !== control.request_scan
        _enqueue_lifecycle_gated_array_copy!(
            control.request_scan,
            source,
            backend,
            workspace,
            control,
            Val(:due),
        )
    end
    return nothing
end

function _enqueue_lifecycle_sort!(keys, workspace, control, launch)
    length(keys) <= 1 && return nothing
    ispow2(length(keys)) || throw(ArgumentError(
        "lifecycle site-key capacity must be a power of two"
    ))
    span = 2
    while span <= length(keys)
        stride = span >>> 1
        while stride > 0
            sort_step = launch(_lifecycle_sort_step_kernel!)
            sort_step(
                keys,
                workspace,
                control,
                Int32(span),
                Int32(stride);
                ndrange = length(keys),
            )
            stride >>>= 1
        end
        span <<= 1
    end
    return nothing
end

@kernel function _lifecycle_site_key_kernel!(
        keys, ownership, workspace, control, capacity
    )
    site = @index(Global, Linear)
    if site <= length(keys) && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        key = if site <= length(ownership)
            owner = @inbounds ownership[site]
            if owner > capacity
                @inbounds control.candidate_status[site] =
                    _lifecycle_backend_status(
                        LifecycleStatusInvariant;
                        anchor = owner,
                        detail = LifecycleDetailOwnershipExceedsCellCapacity,
                        maximum = capacity,
                    )
            end
            if 0 < owner <= capacity
                (UInt64(UInt32(owner)) << 32) | UInt64(UInt32(site))
            else
                typemax(UInt64)
            end
        else
            typemax(UInt64)
        end
        @inbounds keys[site] = key
    end
end

@kernel function _reduce_lifecycle_status_kernel!(workspace, control, count)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace)
        result = LifecycleStatusPayload()
        found = false
        for candidate in 1:Int(count)
            status = @inbounds control.candidate_status[candidate]
            if !found && status.code !== LifecycleStatusSuccess
                result = status
                found = true
            end
        end
        found && @inbounds(workspace.status[1] = result)
    end
end

@inline function _lifecycle_owner_lower_bound(keys, owner::UInt32)
    target = UInt64(owner) << 32
    lower = 1
    upper = length(keys) + 1
    while lower < upper
        middle = lower + ((upper - lower) >>> 1)
        value = @inbounds keys[middle]
        if value < target
            lower = middle + 1
        else
            upper = middle
        end
    end
    return lower
end

@kernel function _index_lifecycle_sites_kernel!(workspace, control, capacity)
    cell = @index(Global, Linear)
    if cell <= capacity && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        first_position = _lifecycle_owner_lower_bound(
            control.site_keys, UInt32(cell)
        )
        next_position = cell == capacity ?
            _lifecycle_owner_lower_bound(control.site_keys, UInt32(cell) + UInt32(1)) :
            _lifecycle_owner_lower_bound(control.site_keys, UInt32(cell + 1))
        count = next_position - first_position
        @inbounds begin
            workspace.cell_site_starts[cell] = Int32(first_position)
            workspace.cell_site_counts[cell] = Int32(count)
            workspace.cell_site_cursor[cell] = Int32(next_position)
            workspace.representative_site[cell] = count > 0 ?
                Int32(control.site_keys[first_position] & UInt64(typemax(UInt32))) :
                Int32(0)
        end
        for position in first_position:(next_position - 1)
            site = Int(control.site_keys[position] & UInt64(typemax(UInt32)))
            @inbounds begin
                workspace.cell_sites[position] = Int32(site)
                workspace.site_position[site] = Int32(position)
            end
        end
    end
end

@inline function _lifecycle_descriptor_for_request(offsets, request::Int32)
    lower = 1
    upper = length(offsets)
    while lower < upper
        middle = lower + ((upper - lower + 1) >>> 1)
        if @inbounds(offsets[middle]) <= request
            lower = middle
        else
            upper = middle - 1
        end
    end
    return lower
end

@inline function _evaluate_lifecycle_backend(
        plan, evaluator::Int32, context, descriptor, control, slot
    )
    value = evaluate_lifecycle(plan.evaluators, evaluator, context)
    if value isa AbstractFloat && !isfinite(value)
        @inbounds control.candidate_status[slot] = _lifecycle_backend_status(
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor = context.anchor,
            detail = LifecycleDetailNonfiniteResult,
        )
        return LifecycleEvaluationFailed()
    end
    return value
end

@inline function _emit_lifecycle_backend_one!(
        request,
        state, workspace, control, next_mcs
    )
    request <= length(workspace.active) || return
    _lifecycle_backend_open(workspace) || return
    descriptor_index = _lifecycle_descriptor_for_request(
        control.request_offsets, Int32(request)
    )
    descriptor = @inbounds state.program.lifecycle_plan.descriptors[
        descriptor_index
    ]
    _lifecycle_due(descriptor, Int(next_mcs)) || return
    first_request = @inbounds control.request_offsets[descriptor_index]
    lane = Int32(request) - first_request + Int32(1)
    anchor = descriptor.domain === ModelLifecycleDomain ? Int32(0) : lane
    descriptor.domain === ModelLifecycleDomain && lane != 1 && return
    if anchor > 0
        kind = @inbounds state.cell_kinds[anchor]
        kind == descriptor.domain_kind || return
    end
    generation = anchor > 0 ? @inbounds(state.cell_generations[anchor]) : UInt32(0)
    if anchor > 0 && iszero(generation)
        @inbounds control.candidate_status[request] = _lifecycle_backend_status(
            LifecycleStatusStaleGeneration; anchor
        )
        return
    end
    context = _LifecycleTriggerContext(
        state,
        descriptor.source_identity,
        descriptor.action_identity,
        descriptor.trigger_workspace_maximum,
        Int32(0),
        Int32(request),
        anchor,
        generation,
        _lifecycle_context_site(state, workspace, anchor),
        Int32(0),
        UInt16(descriptor.source_handle),
    )
    enabled = _evaluate_lifecycle_backend(
        state.program.lifecycle_plan,
        descriptor.trigger_evaluator,
        context,
        descriptor,
        control,
        request,
    )
    enabled isa LifecycleEvaluationFailed && return
    if !(enabled isa Bool)
        @inbounds control.candidate_status[request] = _lifecycle_backend_status(
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailTriggerNotBoolean,
        )
        return
    end
    enabled || return
    @inbounds begin
        workspace.descriptor[request] = Int32(descriptor_index)
        workspace.anchor[request] = anchor
        workspace.generation[request] = generation
        workspace.occurrence[request] = Int32(0)
        workspace.active[request] = true
    end
end

@kernel function _emit_lifecycle_backend_kernel!(
        state, workspace, control, next_mcs
    )
    request = @index(Global, Linear)
    if request <= length(workspace.active) && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        _emit_lifecycle_backend_one!(
            request, state, workspace, control, next_mcs
        )
    end
end
