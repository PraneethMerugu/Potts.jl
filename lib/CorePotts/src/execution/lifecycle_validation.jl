# Staged-state validation and atomic publication.

@inline _validate_tracker_storage_shapes!(::Tuple{}, ::Tuple{}, cell_count) = nothing

@inline function _validate_tracker_storage_shapes!(
        descriptors::Tuple{D, Vararg}, values::Tuple{V, Vararg}, cell_count
    ) where {D, V}
    _validate_tracker_state(
        tracker_storage(first(descriptors)), first(values), cell_count
    )
    _validate_tracker_storage_shapes!(
        Base.tail(descriptors), Base.tail(values), cell_count
    )
    return nothing
end

function _validate_staged_lifecycle!(
        ::HostLifecycleExecution, runtime, plan, workspace
    )
    tracker_plan = runtime.program.tracker_plan
    length(tracker_plan.descriptors) == length(workspace.staged_trackers.values) ||
        return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            detail = LifecycleDetailTrackerPlanStateMisalignment,
        )
    volumes = try
        _validate_tracker_storage_shapes!(
            tracker_plan.descriptors,
            workspace.staged_trackers.values,
            length(workspace.staged_cell_kinds),
        )
        tracker_values(
            runtime.program.tracker_plan,
            workspace.staged_trackers,
            Val(:cell_volume),
        )
    catch
        return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            detail = LifecycleDetailTrackerStorageInvalid,
        )
    end
    for cell in eachindex(workspace.staged_cell_kinds)
        active = @inbounds workspace.staged_cell_kinds[cell] != 0
        occupied = @inbounds volumes[cell] != 0
        active == occupied || return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            anchor = cell,
            detail = LifecycleDetailActiveOccupancyMismatch,
        )
        if active && @inbounds plan.forbid_extinction[
                workspace.staged_cell_kinds[cell]
            ] && !occupied
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                anchor = cell,
                detail = LifecycleDetailForbiddenExtinction,
            )
        end
    end
    for slot in eachindex(workspace.staged_relationships)
        try
            validate_relationship_integrity(
                workspace.staged_relationships[slot],
                runtime.program.relationships[slot],
                workspace.staged_cell_kinds,
                workspace.staged_cell_generations,
            )
        catch
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                source = slot,
                detail = LifecycleDetailRelationshipIntegrityInvalid,
            )
        end
    end
    # Lifecycle state storage cannot change representation or shape here.
    # Every writable scalar crosses `_coerce_lifecycle_state_value`; copy and
    # clear policies preserve an already validated representation. Rewalking
    # the type-erased schema layout would duplicate that authority and allocate
    # on the otherwise bounded warm path.
    return true
end

@inline function _relationship_payload_is_finite(state, edge)
    for values in state.payload
        isfinite(@inbounds(values[edge])) || return false
    end
    return true
end

@inline function _relationship_payload_is_zero(state, edge)
    for values in state.payload
        iszero(@inbounds(values[edge])) || return false
    end
    return true
end

@inline function _validate_relationship_integrity_backend(
        state, schema, endpoint_status, endpoint_generations
    )
    capacity = Int(schema.capacity)
    length(state.active) == capacity || return false
    length(state.payload) == length(schema.payload_defaults) || return false
    for values in state.payload
        length(values) == capacity || return false
    end
    length(endpoint_status) == length(endpoint_generations) || return false
    length(endpoint_status) == length(state.degree) || return false
    length(endpoint_status) == size(state.incident_edges, 2) || return false
    size(state.incident_edges, 1) == Int(schema.maximum_degree) || return false

    for edge in 1:capacity
        if @inbounds state.active[edge]
            a = @inbounds state.endpoint_a[edge]
            b = @inbounds state.endpoint_b[edge]
            1 <= a < b <= length(endpoint_status) || return false
            @inbounds(!iszero(endpoint_status[a]) &&
                      !iszero(endpoint_status[b])) || return false
            @inbounds(state.generation_a[edge] == endpoint_generations[a] &&
                      state.generation_b[edge] == endpoint_generations[b]) ||
                return false
            _relationship_payload_is_finite(state, edge) || return false
            for prior in 1:(edge - 1)
                @inbounds state.active[prior] || continue
                @inbounds(
                    state.endpoint_a[prior] == a &&
                    state.endpoint_b[prior] == b
                ) && return false
            end
        else
            @inbounds(
                iszero(state.endpoint_a[edge]) &&
                iszero(state.endpoint_b[edge]) &&
                iszero(state.generation_a[edge]) &&
                iszero(state.generation_b[edge])
            ) || return false
            _relationship_payload_is_zero(state, edge) || return false
        end
    end

    for endpoint in eachindex(state.degree)
        degree = Int(@inbounds state.degree[endpoint])
        0 <= degree <= Int(schema.maximum_degree) || return false
        expected = 0
        for edge in 1:capacity
            expected += Int(@inbounds(
                state.active[edge] &&
                (state.endpoint_a[edge] == endpoint ||
                 state.endpoint_b[edge] == endpoint)
            ))
        end
        expected == degree || return false
        previous = Int32(0)
        for position in 1:Int(schema.maximum_degree)
            edge = @inbounds state.incident_edges[position, endpoint]
            if position <= degree
                edge > previous || return false
                1 <= edge <= capacity || return false
                @inbounds state.active[edge] || return false
                @inbounds(
                    state.endpoint_a[edge] == endpoint ||
                    state.endpoint_b[edge] == endpoint
                ) || return false
                previous = edge
            else
                iszero(edge) || return false
            end
        end
    end
    return true
end

function _validate_staged_lifecycle!(
        ::BackendLifecycleExecution, runtime, plan, workspace
    )
    tracker_plan = runtime.program.tracker_plan
    length(tracker_plan.descriptors) == length(workspace.staged_trackers.values) ||
        return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            detail = LifecycleDetailTrackerPlanStateMisalignment,
        )
    volumes = tracker_values(
        tracker_plan, workspace.staged_trackers, Val(:cell_volume)
    )
    for cell in eachindex(workspace.staged_cell_kinds)
        active = @inbounds workspace.staged_cell_kinds[cell] != 0
        occupied = @inbounds volumes[cell] != 0
        active == occupied || return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            anchor = cell,
            detail = LifecycleDetailActiveOccupancyMismatch,
        )
        if active && @inbounds plan.forbid_extinction[
                workspace.staged_cell_kinds[cell]
            ] && !occupied
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                anchor = cell,
                detail = LifecycleDetailForbiddenExtinction,
            )
        end
    end
    for slot in eachindex(workspace.staged_relationships)
        _validate_relationship_integrity_backend(
            workspace.staged_relationships[slot],
            runtime.program.relationships[slot],
            workspace.staged_cell_kinds,
            workspace.staged_cell_generations,
        ) || return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            source = slot,
            detail = LifecycleDetailRelationshipIntegrityInvalid,
        )
    end
    return true
end

_validate_staged_lifecycle!(runtime, plan, workspace) =
    _validate_staged_lifecycle!(
        HostLifecycleExecution(), runtime, plan, workspace
    )

function _stage_lifecycle_transactions!(
        runtime, plan, workspace, selected_count
    )
    copyto!(workspace.staged_ownership, runtime.ownership)
    copyto!(workspace.staged_cell_kinds, runtime.cell_kinds)
    copyto!(workspace.staged_cell_generations, runtime.cell_generations)
    copyto_tracker_state!(workspace.staged_trackers, runtime.trackers)
    copyto!(workspace.staged_relationships, runtime.relationships)
    copyto_auxiliary_state!(
        workspace.staged_descriptor_state, runtime.descriptor_state
    )
    # The inactive bank is the concrete planned-after state. Finish structural
    # and derived consequences before state policies observe that view; no
    # scientific value is published until every phase validates.
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        _stage_lifecycle_request_structure!(
            HostLifecycleExecution(), runtime, plan, workspace, request
        ) || return -1
    end
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        _stage_lifecycle_request_relationships!(
            HostLifecycleExecution(), runtime, plan, workspace, request
        ) || return -1
    end
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        _stage_lifecycle_request_state!(
            HostLifecycleExecution(), runtime, plan, workspace, request
        ) || return -1
    end
    retired = 0
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        result = _finalize_lifecycle_request!(plan, workspace, request)
        result < 0 && return -1
        retired += result
    end
    _validate_staged_lifecycle!(runtime, plan, workspace) || return -1
    return retired
end

function _publish_lifecycle_transactions!(runtime, workspace, retired)
    copyto!(runtime.ownership, workspace.staged_ownership)
    copyto!(runtime.cell_kinds, workspace.staged_cell_kinds)
    copyto!(runtime.cell_generations, workspace.staged_cell_generations)
    copyto_tracker_state!(runtime.trackers, workspace.staged_trackers)
    copyto!(runtime.relationships, workspace.staged_relationships)
    copyto_auxiliary_state!(
        runtime.descriptor_state, workspace.staged_descriptor_state
    )
    runtime.retired_cells += retired
    return runtime
end
