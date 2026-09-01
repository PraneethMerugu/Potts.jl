# Sole host-wait and device-to-host publication boundary for queued programs.

"""Reason a caller requires queued work to cross a host publication boundary."""
@enum ProgramSettlementReason::UInt8 begin
    FinalizationSettlement = 0x01
    PublicStepSettlement = 0x02
    SaveSettlement = 0x03
    HostCallbackSettlement = 0x04
    CheckpointSettlement = 0x05
    IndexReadSettlement = 0x06
    IndexMutationSettlement = 0x07
    ComponentExchangeSettlement = 0x08
    ProgressSettlement = 0x09
    StatisticsSettlement = 0x0a
    ObservationSettlement = 0x0b
end
"""Settlement requested before runtime finalization."""
FinalizationSettlement
"""Settlement requested by the public one-step API."""
PublicStepSettlement
"""Settlement requested before saving logical state."""
SaveSettlement
"""Settlement requested before invoking a host callback."""
HostCallbackSettlement
"""Settlement requested before constructing an exact checkpoint."""
CheckpointSettlement
"""Settlement requested before indexed state observation."""
IndexReadSettlement
"""Settlement requested before indexed state mutation."""
IndexMutationSettlement
"""Settlement requested before component-state exchange."""
ComponentExchangeSettlement
"""Settlement requested to report execution progress."""
ProgressSettlement
"""Settlement requested to publish execution statistics."""
StatisticsSettlement
"""Settlement requested to materialize a scientific observation."""
ObservationSettlement

"""Requested publication reason and whether a complete snapshot is required."""
struct ProgramSettlementRequest
    reason::ProgramSettlementReason
    full_snapshot::Bool
end

ProgramSettlementRequest(
    reason::ProgramSettlementReason; full_snapshot::Bool = false
) = ProgramSettlementRequest(reason, full_snapshot)

"""Result of draining queued work and optionally materializing a logical snapshot."""
struct ProgramSettlementReceipt{S, F, L}
    submitted_mcs::Int
    drained_mcs::Int
    committed_mcs::Int
    materialized_mcs::Int
    counters::NamedTuple
    status::ProgramStatus
    failure::F
    lifecycle_receipt::L
    snapshot::S
end

"""Immutable public detail for one expected device-reported scientific stop."""
struct ProgramFailureReport
    code::ProgramStatusCode
    mcs::Int
    stage::ProgramExecutionStage
    source::Int32
    action_identity::UInt64
    secondary_source::Int32
    anchor::Int32
    detail::ProgramStatusDetailCode
    required::Int32
    available::Int32
    maximum::Int32
end

"""
    update_program_parameters!(runtime, parameters)

Publish one validated host parameter transaction at an already settled scientific boundary. The
host mirror and every execution bank are updated together here so runtime adapters and indexing
hooks do not acquire independent device-publication paths.
"""
function update_program_parameters!(
        runtime::ProgramRuntime{T}, parameters::AbstractVector{<:Real}
    ) where {T}
    runtime.settled ||
        throw(ArgumentError("parameter updates require a settled MCS boundary"))
    length(parameters) == length(runtime.parameters) ||
        throw(ArgumentError("runtime parameter buffer has the wrong length"))
    replacement = _validated_program_parameters(runtime.program, parameters)
    copyto!(runtime.parameters, replacement)
    execution_workspace = runtime.engine_workspace
    if _is_checkerboard_execution_workspace(execution_workspace)
        workspace = _checkerboard_core(execution_workspace)
        primary = workspace.state.parameters
        primary === runtime.parameters || copyto!(primary, replacement)
        secondary = workspace.alternate_state.parameters
        secondary === primary || secondary === runtime.parameters ||
            copyto!(secondary, replacement)
    end
    return runtime
end

"""Publish one validated auxiliary-state transaction to the host mirror and both banks."""
function update_program_descriptor_state!(
        runtime::ProgramRuntime, descriptor_state::AuxiliaryState
    )
    runtime.settled || throw(ArgumentError(
        "state updates require a settled MCS boundary"
    ))
    execution_workspace = runtime.engine_workspace
    destinations = AuxiliaryState[runtime.descriptor_state]
    if _is_checkerboard_execution_workspace(execution_workspace)
        workspace = _checkerboard_core(execution_workspace)
        primary = workspace.state.descriptor_state
        primary === runtime.descriptor_state || push!(destinations, primary)
        secondary = workspace.alternate_state.descriptor_state
        secondary === primary || secondary === runtime.descriptor_state ||
            push!(destinations, secondary)
    end
    _validate_auxiliary_state_candidate(
        runtime.program.descriptor_plan.state_layout,
        runtime.descriptor_state,
        descriptor_state,
    )
    for destination in destinations
        _require_auxiliary_copy_compatible(destination, descriptor_state)
    end
    for destination in destinations
        copyto_auxiliary_state!(destination, descriptor_state)
    end
    return runtime
end

ProgramFailureReport(status::ProgramStatus) = ProgramFailureReport(
    status.code,
    Int(status.mcs),
    status.stage,
    status.source,
    status.action_identity,
    status.secondary_source,
    status.anchor,
    status.detail,
    status.required,
    status.available,
    status.maximum,
)

@inline function program_status_is_expected(status::ProgramStatus)
    status.code in (
        ProgramStatusInadmissible,
        ProgramStatusConflict,
        ProgramStatusCellCapacity,
        ProgramStatusRelationshipCapacity,
        ProgramStatusGenerationOverflow,
        ProgramStatusAcceptance,
    ) && return true
    status.code === ProgramStatusEvaluator || return false
    return status.detail in (
        LifecycleDetailNonfiniteResult,
        LifecycleDetailSplitFractionOutOfBounds,
        LifecycleDetailStateValueInvalid,
    )
end

function _settlement_counters(values)
    return (
        accepted = UInt64(values[_PROGRAM_STAT_ACCEPTED]),
        rejected = UInt64(values[_PROGRAM_STAT_REJECTED]),
        null_attempts = UInt64(values[_PROGRAM_STAT_NULL]),
        constraint_rejections = UInt64(values[_PROGRAM_STAT_CONSTRAINT]),
        energy_rejections = UInt64(values[_PROGRAM_STAT_ENERGY]),
        retired_cells = UInt64(values[_PROGRAM_STAT_RETIRED]),
    )
end

function _materialize_program_bank(state, committed_mcs::Int)
    ownership = Adapt.adapt(Array, state.ownership)
    cell_kinds = Adapt.adapt(Array, state.cell_kinds)
    cell_generations = Adapt.adapt(Array, state.cell_generations)
    trackers = Adapt.adapt(Array, state.trackers)
    relationships = Adapt.adapt(Array, state.relationships)
    descriptor_state = Adapt.adapt(Array, state.descriptor_state)
    return ProgramSnapshot{
        eltype(state.parameters),
        ndims(ownership),
        typeof(relationships),
        typeof(descriptor_state),
        typeof(trackers),
    }(
        committed_mcs,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
    )
end

function _settlement_active_state(workspace, active_bank::Int)
    active_bank == 1 && return workspace.state
    active_bank == 2 && return workspace.alternate_state
    throw(LifecycleInvariantFailure(
        Int32(0), Int32(active_bank), :invalid_active_state_bank
    ))
end

function _settlement_inactive_state(workspace, active_bank::Int)
    active_bank == 1 && return workspace.alternate_state
    active_bank == 2 && return workspace.state
    throw(LifecycleInvariantFailure(
        Int32(0), Int32(active_bank), :invalid_active_state_bank
    ))
end

function _settlement_lifecycle_receipt(
        backend,
        active_state,
        before_state,
        committed::Int,
        previous_drained::Int,
        failure,
    )
    failure === nothing || return nothing
    committed > previous_drained || return nothing
    plan = active_state.program.lifecycle_plan
    workspace = active_state.lifecycle_workspace
    before_kinds = before_state.cell_kinds
    before_generations = before_state.cell_generations
    after_kinds = active_state.cell_kinds
    after_generations = active_state.cell_generations
    if !(backend isa KernelAbstractions.CPU) &&
            !(plan isa NoLifecycleExecutionPlan)
        # Receipt publication is part of settlement.  A device lifecycle plan
        # therefore crosses to owned host storage here, never from a kernel or
        # from an indexing/observation helper.  The no-lifecycle case needs no
        # transfer and still publishes an empty transaction receipt.
        plan = Adapt.adapt(Array, plan)
        workspace = Adapt.adapt(Array, workspace)
        before_kinds = Adapt.adapt(Array, before_kinds)
        before_generations = Adapt.adapt(Array, before_generations)
        after_kinds = Adapt.adapt(Array, after_kinds)
        after_generations = Adapt.adapt(Array, after_generations)
    end
    return _materialize_lifecycle_receipt(
        plan,
        workspace,
        before_kinds,
        before_generations,
        after_kinds,
        after_generations,
        committed,
        active_state.seed,
        active_state.replica,
        active_state.repeat,
    )
end

"""
    settle_program!(workspace, request)

Drain all work submitted to a checkerboard program's ordered backend queue, inspect its sticky
status and cumulative counters, and optionally materialize the last coherent scientific bank.
This is the only production operation permitted to synchronize or transfer checkerboard program
state to the host.
"""
function _settle_program_after_wait!(
        workspace::CheckerboardWorkspace,
        request::ProgramSettlementRequest,
        did_synchronize::Bool,
    )
    execution = workspace.execution
    submitted = execution.submitted_mcs
    previous_drained = execution.drained_mcs
    backend = KernelAbstractions.get_backend(workspace.state.ownership)
    did_synchronize && (execution.synchronization_count += 1)
    execution.drained_mcs = submitted
    execution.settlement_count += 1

    status_values = Adapt.adapt(Array, workspace.state.program_status)
    counter_values = Adapt.adapt(
        Array, workspace.state.lifecycle_control.counters
    )
    statistic_values = Adapt.adapt(
        Array, workspace.state.lifecycle_control.statistics
    )
    execution.control_transfer_count += 1
    status = only(status_values)
    committed = Int(counter_values[_LIFECYCLE_CONTROL_COMMITTED_MCS])
    active_bank = Int(counter_values[_LIFECYCLE_CONTROL_ACTIVE_BANK])
    execution.committed_mcs = committed

    failure = _translate_program_status(status)
    if failure !== nothing && !program_status_is_expected(status)
        throw(failure)
    end
    if failure === nothing && committed != submitted
        throw(LifecycleInvariantFailure(
            Int32(0), Int32(committed), :committed_submission_mismatch
        ))
    end
    if failure !== nothing
        0 < status.mcs <= submitted || throw(LifecycleInvariantFailure(
            status.source, status.anchor, :invalid_failure_mcs
        ))
        committed < status.mcs || throw(LifecycleInvariantFailure(
            status.source, status.anchor, :failure_after_publication
        ))
    end

    active_state = _settlement_active_state(workspace, active_bank)
    before_state = _settlement_inactive_state(workspace, active_bank)
    lifecycle_receipt = _settlement_lifecycle_receipt(
        backend,
        active_state,
        before_state,
        committed,
        previous_drained,
        failure,
    )
    if !(backend isa KernelAbstractions.CPU) &&
            !(active_state.program.lifecycle_plan isa NoLifecycleExecutionPlan) &&
            lifecycle_receipt !== nothing
        execution.lifecycle_transfer_count += 1
    end
    snapshot = if request.full_snapshot
        value = _materialize_program_bank(active_state, committed)
        execution.materialized_mcs = committed
        execution.snapshot_transfer_count += 1
        value
    else
        nothing
    end
    return ProgramSettlementReceipt(
        submitted,
        execution.drained_mcs,
        committed,
        execution.materialized_mcs,
        _settlement_counters(statistic_values),
        status,
        failure,
        lifecycle_receipt,
        snapshot,
    )
end

function _checkerboard_settlement_events(
        execution::_CheckerboardExecutionWorkspace
    )
    identity = execution.identity
    identity.scientific_abi ===
        :corepotts_checkerboard_transaction_v1 || throw(ArgumentError(
        "checkerboard settlement received an unknown scientific ABI"
    ))
    identity.queue_policy.completion ===
        :grouped_cumulative_receipts || throw(ArgumentError(
        "checkerboard settlement received an unsupported completion policy"
    ))
    identity.queue_policy.receipt_cumulative === true &&
        identity.queue_policy.receipt_selective === false ||
        throw(ArgumentError(
            "checkerboard settlement requires cumulative provider-tail receipts"
        ))
    lifecycle = execution.receipts.lifecycle
    banks = (
        execution.receipts.mechanics,
        lifecycle.direct, lifecycle.planning,
        lifecycle.site_index, lifecycle.request_index,
        lifecycle.emission, lifecycle.selection,
    )
    return Tuple(receipt for family in banks for bank in family for receipt in bank)
end

function _clear_checkerboard_settlement_events!(execution)
    lifecycle = execution.receipts.lifecycle
    banks = (
        execution.receipts.mechanics,
        lifecycle.direct, lifecycle.planning,
        lifecycle.site_index, lifecycle.request_index,
        lifecycle.emission, lifecycle.selection,
    )
    for family in banks, bank in family
        empty!(bank)
    end
    return nothing
end

function _wait_checkerboard_execution!(
        execution::_CheckerboardExecutionWorkspace,
        backend,
    )
    submitted = _checkerboard_settlement_events(execution)
    did_synchronize = execution.core.execution.submitted_mcs !=
        execution.core.execution.drained_mcs ||
        any(LocalMath.ispending, submitted)
    isempty(submitted) || LocalMath.waitall(submitted)
    KernelAbstractions.synchronize(backend)
    _clear_checkerboard_settlement_events!(execution)
    return did_synchronize
end

function _synchronize_checkerboard_execution!(
        execution::_CheckerboardExecutionWorkspace,
        backend,
    )
    submitted = _checkerboard_settlement_events(execution)
    isempty(submitted) || LocalMath.waitall(submitted)
    KernelAbstractions.synchronize(backend)
    _clear_checkerboard_settlement_events!(execution)
    return nothing
end

function settle_program!(
        execution_graph::_CheckerboardExecutionWorkspace,
        request::ProgramSettlementRequest,
    )
    workspace = execution_graph.core
    capability = execution_graph.capability_report
    _require_program_execution_capability(
        capability;
        operation = :backend_settle_program,
    )
    execution = workspace.execution
    submitted = execution.submitted_mcs
    previous_drained = execution.drained_mcs
    backend = KernelAbstractions.get_backend(workspace.state.ownership)
    did_synchronize = try
        _wait_checkerboard_execution!(execution_graph, backend)
    catch error
        throw(LifecycleBackendFailure(
            error, previous_drained + 1, submitted
        ))
    end
    return _settle_program_after_wait!(
        workspace, request, did_synchronize
    )
end
