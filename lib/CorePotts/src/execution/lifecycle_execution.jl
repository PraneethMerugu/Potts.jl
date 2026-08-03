# Engine-status orchestration and the single host exception boundary.

_execute_lifecycle_status!(
    runtime, ::NoLifecycleExecutionPlan, ::NoLifecycleWorkspace
) = true

function _execute_lifecycle_status!(
        runtime,
        plan::LifecycleExecutionPlan,
        workspace::LifecycleWorkspace,
    )
    _reset_lifecycle_workspace!(workspace)
    _index_lifecycle_representative_sites!(runtime, workspace) || return false
    _emit_lifecycle_requests!(runtime, plan, workspace) || return false
    _filter_lifecycle_requests!(runtime, plan, workspace) || return false
    _resolve_lifecycle_conflicts!(runtime, plan, workspace) || return false
    selected_count = _preflight_lifecycle_capacity!(runtime, plan, workspace)
    selected_count < 0 && return false
    iszero(selected_count) && return true
    retired = _stage_lifecycle_transactions!(
        runtime, plan, workspace, selected_count
    )
    retired < 0 && return false
    _publish_lifecycle_transactions!(runtime, workspace, retired)
    return true
end

function _translate_lifecycle_status(status::LifecycleStatusPayload)
    code = status.code
    code === LifecycleStatusSuccess && return nothing
    reason = _lifecycle_detail_symbol(status.detail)
    code === LifecycleStatusInadmissible && return LifecycleInadmissibilityFailure(
        status.source, status.anchor, reason
    )
    code === LifecycleStatusConflict && return LifecycleConflictFailure(
        status.source, status.secondary_source, status.anchor
    )
    code === LifecycleStatusCellCapacity && return CellCapacityFailure(
        status.maximum, status.required, status.available
    )
    code === LifecycleStatusRelationshipCapacity &&
        return RelationshipCapacityFailure(status.source)
    code === LifecycleStatusStaleGeneration &&
        return StaleGenerationFailure(status.anchor)
    code === LifecycleStatusGenerationOverflow &&
        return GenerationOverflowFailure(status.anchor)
    code === LifecycleStatusEvaluator && return LifecycleEvaluatorFailure(
        status.source, status.anchor, reason
    )
    code === LifecycleStatusFootprint && return LifecycleFootprintFailure(
        status.source, status.anchor, reason
    )
    code === LifecycleStatusInvariant && return LifecycleInvariantFailure(
        status.source, status.anchor, reason
    )
    return LifecycleBackendFailure(nothing)
end

function execute_lifecycle!(runtime)
    backend_error = nothing
    succeeded = try
        _execute_lifecycle_status!(
            runtime, runtime.program.lifecycle_plan, runtime.lifecycle_workspace
        )
    catch error
        backend_error = error
        workspace = runtime.lifecycle_workspace
        workspace isa LifecycleWorkspace && _set_lifecycle_status!(
            workspace, LifecycleStatusBackend
        )
        false
    end
    backend_error === nothing || throw(LifecycleBackendFailure(backend_error))
    succeeded && return runtime
    failure = _translate_lifecycle_status(runtime.lifecycle_workspace.status)
    failure === nothing && return runtime
    throw(failure)
end
