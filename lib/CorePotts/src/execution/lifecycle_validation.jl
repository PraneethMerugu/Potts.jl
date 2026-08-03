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

function _validate_staged_lifecycle!(runtime, plan, workspace)
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
    retired = 0
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        result = _apply_lifecycle_request!(runtime, plan, workspace, request)
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
