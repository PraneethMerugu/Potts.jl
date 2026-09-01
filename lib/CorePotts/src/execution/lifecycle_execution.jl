# Engine-status orchestration and the single host exception boundary.

_execute_lifecycle_status!(
    runtime, ::NoLifecycleExecutionPlan, ::NoLifecycleWorkspace
) = true

@inline function _lifecycle_transaction_identity(
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
        completed_mcs::Integer,
    )
    completed_mcs > 0 || throw(ArgumentError(
        "a published lifecycle transaction requires a positive completed MCS"
    ))
    identity = _rng_mix64(xor(
        _trajectory_seed(seed, replica, repeat),
        UInt64(completed_mcs) * UInt64(0x94d049bb133111eb),
    ))
    return iszero(identity) ? typemax(UInt64) : identity
end

@inline function _receipt_cell_identity(kinds, generations, slot::Integer)
    0 < slot <= length(kinds) || throw(LifecycleInvariantFailure(
        Int32(0), Int32(slot), :invalid_lifecycle_receipt_slot
    ))
    return CellIdentity(slot, generations[slot], kinds[slot])
end

function _materialize_lifecycle_receipt(
        ::NoLifecycleExecutionPlan,
        ::NoLifecycleWorkspace,
        before_kinds,
        before_generations,
        after_kinds,
        after_generations,
        completed_mcs::Integer,
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
    )
    return LifecycleReceipt(
        completed_mcs,
        _lifecycle_transaction_identity(
            seed, replica, repeat, completed_mcs
        ),
    )
end

function _materialize_lifecycle_receipt(
        plan::LifecycleExecutionPlan,
        workspace::LifecycleWorkspace,
        before_kinds,
        before_generations,
        after_kinds,
        after_generations,
        completed_mcs::Integer,
        seed::UInt64,
        replica::UInt32,
        repeat::UInt32,
    )
    events = LifecycleEvent[]
    selected_count = _lifecycle_selected_count(workspace)
    sizehint!(events, selected_count)
    for position in 1:selected_count
        request = Int(_lifecycle_selected_request(workspace, position))
        descriptor = @inbounds plan.descriptors[
            Int(workspace.descriptor[request])
        ]
        anchor = Int(@inbounds workspace.anchor[request])
        request_identity = QualifiedLifecycleRequestIdentity(
            descriptor.source_identity,
            descriptor.action_identity,
            anchor,
            @inbounds(workspace.generation[request]),
        )
        effect = descriptor.effect
        event = if effect === CreateCellLifecycleEffect
            allocation = Int(_lifecycle_request_allocation(workspace, request))
            CreateLifecycleEvent(
                request_identity,
                _receipt_cell_identity(
                    after_kinds, after_generations, allocation
                ),
            )
        elseif effect === RemoveCellLifecycleEffect
            RemoveCellLifecycleEvent(
                request_identity,
                _receipt_cell_identity(
                    before_kinds, before_generations, anchor
                ),
            )
        elseif effect === RetireCellLifecycleEffect
            RetireLifecycleEvent(
                request_identity,
                _receipt_cell_identity(
                    before_kinds, before_generations, anchor
                ),
                descriptor.source_identity,
                descriptor.action_identity,
            )
        elseif effect === TransitionCellLifecycleEffect
            TransitionLifecycleEvent(
                request_identity,
                _receipt_cell_identity(
                    before_kinds, before_generations, anchor
                ),
                _receipt_cell_identity(
                    after_kinds, after_generations, anchor
                ),
            )
        elseif effect === DivideCellLifecycleEffect
            allocation = Int(_lifecycle_request_allocation(workspace, request))
            DivideLifecycleEvent(
                request_identity,
                _receipt_cell_identity(
                    before_kinds, before_generations, anchor
                ),
                _receipt_cell_identity(
                    after_kinds, after_generations, anchor
                ),
                _receipt_cell_identity(
                    after_kinds, after_generations, allocation
                ),
            )
        else
            throw(LifecycleInvariantFailure(
                descriptor.source_handle,
                Int32(anchor),
                :unknown_lifecycle_receipt_effect,
            ))
        end
        push!(events, event)
    end
    return LifecycleReceipt(
        completed_mcs,
        _lifecycle_transaction_identity(
            seed, replica, repeat, completed_mcs
        ),
        events,
    )
end

function _execute_lifecycle_status!(
        runtime,
        plan::LifecycleExecutionPlan,
        workspace::LifecycleWorkspace,
    )
    _reset_lifecycle_workspace!(workspace)
    any(descriptor -> _lifecycle_due(descriptor, runtime.mcs + 1),
        plan.descriptors) || return true
    _validate_lifecycle_ownership!(runtime, workspace) || return (
        _stamp_host_lifecycle_failure!(
            runtime, plan, workspace, ProgramStageIndex
        )
    )
    _run_host_lifecycle_site_index!(runtime, workspace)
    _run_host_lifecycle_emission!(runtime, workspace) || return false
    _run_host_lifecycle_request_index!(runtime, workspace)
    _filter_lifecycle_requests!(runtime, plan, workspace) || return (
        _stamp_host_lifecycle_failure!(
            runtime, plan, workspace, ProgramStagePlanning
        )
    )
    _run_host_lifecycle_selection!(runtime, workspace) || return false
    selected_count = _lifecycle_selected_count(workspace)
    iszero(selected_count) && return true
    retired = _stage_lifecycle_transactions!(
        runtime, plan, workspace, selected_count
    )
    retired < 0 && return false
    _publish_lifecycle_transactions!(runtime, workspace, retired)
    return true
end

function _stamp_host_lifecycle_failure!(runtime, plan, workspace, stage)
    status = lifecycle_workspace_status(workspace)
    status.code === ProgramStatusSuccess && return false
    status.mcs != 0 && return false
    descriptor = _lifecycle_failure_descriptor(plan, workspace, status)
    source = descriptor === nothing ? status.source : descriptor.source_handle
    action_identity = descriptor === nothing ? status.action_identity :
                      descriptor.action_identity
    @inbounds workspace.status[1] = ProgramStatus(
        status.code,
        Int32(runtime.mcs + 1),
        stage,
        source,
        action_identity,
        status.secondary_source,
        status.anchor,
        status.detail,
        status.required,
        status.available,
        status.maximum,
    )
    return false
end

function _translate_program_status(status::ProgramStatus)
    code = status.code
    code === ProgramStatusSuccess && return nothing
    reason = _program_status_detail_symbol(status.detail)
    code === ProgramStatusInadmissible && return LifecycleInadmissibilityFailure(
        status.source, status.anchor, reason
    )
    code === ProgramStatusConflict && return LifecycleConflictFailure(
        status.source, status.secondary_source, status.anchor
    )
    code === ProgramStatusCellCapacity && return CellCapacityFailure(
        status.maximum, status.required, status.available
    )
    code === ProgramStatusRelationshipCapacity &&
        return RelationshipCapacityFailure(status.source)
    code === ProgramStatusStaleGeneration &&
        return StaleGenerationFailure(status.anchor)
    code === ProgramStatusGenerationOverflow &&
        return GenerationOverflowFailure(status.anchor)
    code === ProgramStatusEvaluator && return LifecycleEvaluatorFailure(
        status.source, status.anchor, reason
    )
    code === ProgramStatusFootprint && return LifecycleFootprintFailure(
        status.source, status.anchor, reason
    )
    code === ProgramStatusInvariant && return LifecycleInvariantFailure(
        status.source, status.anchor, reason
    )
    code === ProgramStatusAcceptance && return ProposalAcceptanceFailure(
        status.anchor, reason
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
            workspace, ProgramStatusBackend
        )
        false
    end
    backend_error === nothing || throw(LifecycleBackendFailure(backend_error))
    succeeded && return runtime
    failure = _translate_program_status(
        lifecycle_workspace_status(runtime.lifecycle_workspace)
    )
    failure === nothing && return runtime
    throw(failure)
end
