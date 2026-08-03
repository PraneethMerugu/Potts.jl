# Canonical deduplication, conflict resolution, and capacity preflight.

@inline function _lifecycle_request_key(plan, workspace, request)
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    return (
        descriptor.source_identity,
        descriptor.action_identity,
        @inbounds(workspace.anchor[request]),
        @inbounds(workspace.generation[request]),
    )
end

@inline function _lifecycle_requests_equivalent(plan, workspace, left, right)
    return _lifecycle_request_key(plan, workspace, left) ==
           _lifecycle_request_key(plan, workspace, right)
end

function _lifecycle_relationship_footprints_conflict(
        runtime, plan, workspace, left, right
    )
    left_descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[left])]
    right_descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[right])]
    left_descriptor.relationship_rule_count > 0 || return false
    right_descriptor.relationship_rule_count > 0 || return false
    left_anchor = @inbounds workspace.anchor[left]
    right_anchor = @inbounds workspace.anchor[right]
    left_anchor > 0 && right_anchor > 0 || return false
    for left_offset in 0:(Int(left_descriptor.relationship_rule_count) - 1)
        left_rule = @inbounds plan.relationship_rules[
            Int(left_descriptor.relationship_rule_offset) + left_offset
        ]
        left_state = runtime.relationships[Int(left_rule.relationship_slot)]
        for right_offset in 0:(Int(right_descriptor.relationship_rule_count) - 1)
            right_rule = @inbounds plan.relationship_rules[
                Int(right_descriptor.relationship_rule_offset) + right_offset
            ]
            left_rule.relationship_slot == right_rule.relationship_slot || continue
            left_degree = Int(@inbounds left_state.degree[left_anchor])
            right_degree = Int(@inbounds left_state.degree[right_anchor])
            for left_position in 1:left_degree, right_position in 1:right_degree
                @inbounds left_state.incident_edges[left_position, left_anchor] ==
                    left_state.incident_edges[right_position, right_anchor] &&
                    return true
            end
        end
    end
    return false
end

function _lifecycle_requests_conflict(runtime, plan, workspace, left, right)
    left_anchor = @inbounds workspace.anchor[left]
    right_anchor = @inbounds workspace.anchor[right]
    left_anchor > 0 && left_anchor == right_anchor && return true
    left_count = Int(@inbounds workspace.planned_site_count[left])
    right_count = Int(@inbounds workspace.planned_site_count[right])
    for left_position in 1:left_count, right_position in 1:right_count
        @inbounds workspace.planned_sites[left_position, left] ==
                  workspace.planned_sites[right_position, right] && return true
    end
    return _lifecycle_relationship_footprints_conflict(
        runtime, plan, workspace, left, right
    )
end

function _deduplicate_lifecycle_requests!(plan, workspace)
    for right in 1:Int(workspace.request_count)
        @inbounds workspace.active[right] || continue
        for left in 1:(right - 1)
            @inbounds workspace.active[left] || continue
            _lifecycle_requests_equivalent(plan, workspace, left, right) || continue
            @inbounds workspace.active[right] = false
            break
        end
    end
    return workspace
end

function _resolve_lifecycle_conflicts!(runtime, plan, workspace)
    _deduplicate_lifecycle_requests!(plan, workspace)
    count = Int(workspace.request_count)
    if plan.conflict_policy === RejectLifecycleConflicts
        first_conflict = 0
        second_conflict = 0
        for right in 1:count
            @inbounds workspace.active[right] || continue
            for left in 1:(right - 1)
                @inbounds workspace.active[left] || continue
                _lifecycle_requests_conflict(
                    runtime, plan, workspace, left, right
                ) || continue
                left_key = _lifecycle_request_key(plan, workspace, left)
                right_key = _lifecycle_request_key(plan, workspace, right)
                candidate_first, candidate_second = left_key <= right_key ?
                    (left, right) : (right, left)
                if iszero(first_conflict) ||
                        (_lifecycle_request_key(
                            plan, workspace, candidate_first
                        ), _lifecycle_request_key(
                            plan, workspace, candidate_second
                        )) <
                        (_lifecycle_request_key(
                            plan, workspace, first_conflict
                        ), _lifecycle_request_key(
                            plan, workspace, second_conflict
                        ))
                    first_conflict = candidate_first
                    second_conflict = candidate_second
                end
            end
        end
        if !iszero(first_conflict)
            first_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[first_conflict])
            ]
            second_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[second_conflict])
            ]
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusConflict;
                source = first_descriptor.source_handle,
                secondary_source = second_descriptor.source_handle,
                anchor = @inbounds(workspace.anchor[second_conflict]),
            )
        end
        for request in 1:count
            @inbounds workspace.active[request] || continue
            @inbounds workspace.selected[request] = true
        end
        return true
    end
    fill!(workspace.conflict_seen, false)
    for seed in 1:count
        @inbounds workspace.active[seed] || continue
        @inbounds workspace.conflict_seen[seed] && continue
        head = 1
        tail = 1
        workspace.canonical_order[1] = Int32(seed)
        workspace.conflict_seen[seed] = true
        while head <= tail
            current = Int(@inbounds workspace.canonical_order[head])
            head += 1
            for candidate in 1:count
                @inbounds workspace.active[candidate] || continue
                @inbounds workspace.conflict_seen[candidate] && continue
                _lifecycle_requests_conflict(
                    runtime, plan, workspace, current, candidate
                ) || continue
                tail += 1
                @inbounds begin
                    workspace.canonical_order[tail] = Int32(candidate)
                    workspace.conflict_seen[candidate] = true
                end
            end
        end
        best = 0
        tied = 0
        best_priority = typemin(Int32)
        for position in 1:tail
            candidate = Int(@inbounds workspace.canonical_order[position])
            priority = @inbounds plan.descriptors[
                Int(workspace.descriptor[candidate])
            ].priority
            if priority > best_priority
                best = candidate
                tied = 0
                best_priority = priority
            elseif priority == best_priority
                if _lifecycle_request_key(plan, workspace, candidate) <
                        _lifecycle_request_key(plan, workspace, best)
                    tied = best
                    best = candidate
                elseif iszero(tied) || _lifecycle_request_key(
                        plan, workspace, candidate
                    ) < _lifecycle_request_key(plan, workspace, tied)
                    tied = candidate
                end
            end
        end
        if !iszero(tied)
            best_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[best])
            ]
            tied_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[tied])
            ]
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusConflict;
                source = best_descriptor.source_handle,
                secondary_source = tied_descriptor.source_handle,
                anchor = @inbounds(workspace.anchor[tied]),
            )
        end
        @inbounds workspace.selected[best] = true
    end
    return true
end

function _sort_selected_requests!(plan, workspace)
    selected_count = 0
    for request in 1:Int(workspace.request_count)
        @inbounds workspace.selected[request] || continue
        selected_count += 1
        workspace.canonical_order[selected_count] = Int32(request)
    end
    for index in 2:selected_count
        request = @inbounds workspace.canonical_order[index]
        key = _lifecycle_request_key(plan, workspace, Int(request))
        position = index
        while position > 1 && _lifecycle_request_key(
                plan,
                workspace,
                Int(@inbounds workspace.canonical_order[position - 1]),
            ) > key
            @inbounds workspace.canonical_order[position] =
                workspace.canonical_order[position - 1]
            position -= 1
        end
        @inbounds workspace.canonical_order[position] = request
    end
    return selected_count
end

function _preflight_lifecycle_capacity!(runtime, plan, workspace)
    selected_count = _sort_selected_requests!(plan, workspace)
    requested = 0
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        effect = plan.descriptors[Int(workspace.descriptor[request])].effect
        effect in (CreateCellLifecycleEffect, DivideCellLifecycleEffect) &&
            (requested += 1)
    end
    free_count = 0
    high_water = 0
    for cell in eachindex(runtime.cell_kinds)
        generation = @inbounds runtime.cell_generations[cell]
        !iszero(generation) && (high_water = cell)
        if @inbounds runtime.cell_kinds[cell] == 0 && !iszero(generation)
            free_count += 1
            workspace.free_slots[free_count] = Int32(cell)
        end
    end
    for cell in (high_water + 1):length(runtime.cell_kinds)
        @inbounds iszero(runtime.cell_generations[cell]) || continue
        free_count += 1
        workspace.free_slots[free_count] = Int32(cell)
    end
    if requested > free_count
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusCellCapacity;
            required = requested,
            available = free_count,
            maximum = plan.cell_capacity,
        )
        return -1
    end
    allocation_position = 0
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        effect = plan.descriptors[Int(workspace.descriptor[request])].effect
        effect in (CreateCellLifecycleEffect, DivideCellLifecycleEffect) || continue
        allocation_position += 1
        slot = @inbounds workspace.free_slots[allocation_position]
        generation = @inbounds runtime.cell_generations[slot]
        if generation == typemax(UInt32)
            _set_lifecycle_status!(
                workspace, LifecycleStatusGenerationOverflow; anchor = slot
            )
            return -1
        end
        @inbounds workspace.allocation[request] = slot
    end
    return selected_count
end
