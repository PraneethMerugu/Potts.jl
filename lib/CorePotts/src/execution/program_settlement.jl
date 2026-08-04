# Sole host-wait and device-to-host publication boundary for queued programs.

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

struct ProgramSettlementRequest
    reason::ProgramSettlementReason
    full_snapshot::Bool
end

ProgramSettlementRequest(
    reason::ProgramSettlementReason; full_snapshot::Bool = false
) = ProgramSettlementRequest(reason, full_snapshot)

struct ProgramSettlementReceipt{S, F}
    submitted_mcs::Int
    drained_mcs::Int
    committed_mcs::Int
    materialized_mcs::Int
    counters::NamedTuple
    status::LifecycleStatusPayload
    failure::F
    snapshot::S
end

"""Immutable public detail for one expected device-reported scientific stop."""
struct ProgramFailureReport
    code::LifecycleStatusCode
    mcs::Int
    stage::LifecycleExecutionStage
    source::Int32
    action_identity::UInt64
    secondary_source::Int32
    anchor::Int32
    detail::LifecycleStatusDetailCode
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
    replacement = T.(parameters)
    all(isfinite, replacement) ||
        throw(ArgumentError("runtime parameters must be finite"))
    copyto!(runtime.parameters, replacement)
    workspace = runtime.engine_workspace
    if workspace isa CheckerboardWorkspace
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
    copyto_auxiliary_state!(runtime.descriptor_state, descriptor_state)
    workspace = runtime.engine_workspace
    if workspace isa CheckerboardWorkspace
        primary = workspace.state.descriptor_state
        primary === runtime.descriptor_state ||
            copyto_auxiliary_state!(primary, descriptor_state)
        secondary = workspace.alternate_state.descriptor_state
        secondary === primary || secondary === runtime.descriptor_state ||
            copyto_auxiliary_state!(secondary, descriptor_state)
    end
    return runtime
end

ProgramFailureReport(status::LifecycleStatusPayload) = ProgramFailureReport(
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

@inline function lifecycle_status_is_expected(status::LifecycleStatusPayload)
    status.code in (
        LifecycleStatusInadmissible,
        LifecycleStatusConflict,
        LifecycleStatusCellCapacity,
        LifecycleStatusRelationshipCapacity,
        LifecycleStatusGenerationOverflow,
    ) && return true
    status.code === LifecycleStatusEvaluator || return false
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

"""
    settle_program!(workspace, request)

Drain all work submitted to a checkerboard program's ordered backend queue, inspect its sticky
status and cumulative counters, and optionally materialize the last coherent scientific bank.
This is the only production operation permitted to synchronize or transfer checkerboard program
state to the host.
"""
function settle_program!(
        workspace::CheckerboardWorkspace,
        request::ProgramSettlementRequest,
    )
    execution = workspace.execution
    submitted = execution.submitted_mcs
    previous_drained = execution.drained_mcs
    backend = KernelAbstractions.get_backend(workspace.state.ownership)
    try
        KernelAbstractions.synchronize(backend)
    catch error
        throw(LifecycleBackendFailure(
            error, previous_drained + 1, submitted
        ))
    end
    execution.drained_mcs = submitted
    execution.settlement_count += 1

    status_values = Adapt.adapt(
        Array, workspace.state.lifecycle_workspace.status
    )
    counter_values = Adapt.adapt(
        Array, workspace.state.lifecycle_control.counters
    )
    statistic_values = Adapt.adapt(
        Array, workspace.state.lifecycle_control.statistics
    )
    status = only(status_values)
    committed = Int(counter_values[_LIFECYCLE_CONTROL_COMMITTED_MCS])
    active_bank = Int(counter_values[_LIFECYCLE_CONTROL_ACTIVE_BANK])
    execution.committed_mcs = committed

    failure = _translate_lifecycle_status(status)
    if failure !== nothing && !lifecycle_status_is_expected(status)
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

    snapshot = if request.full_snapshot
        state = _settlement_active_state(workspace, active_bank)
        value = _materialize_program_bank(state, committed)
        execution.materialized_mcs = committed
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
        snapshot,
    )
end
