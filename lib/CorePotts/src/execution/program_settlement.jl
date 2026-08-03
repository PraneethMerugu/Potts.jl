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

@inline function _settlement_failure_is_expected(failure)
    return failure isa Union{
        LifecycleInadmissibilityFailure,
        LifecycleConflictFailure,
        CellCapacityFailure,
        RelationshipCapacityFailure,
        GenerationOverflowFailure,
        LifecycleEvaluatorFailure,
    }
end

function _settlement_counters(values)
    return (
        accepted = Int(values[_PROGRAM_STAT_ACCEPTED]),
        rejected = Int(values[_PROGRAM_STAT_REJECTED]),
        null_attempts = Int(values[_PROGRAM_STAT_NULL]),
        constraint_rejections = Int(values[_PROGRAM_STAT_CONSTRAINT]),
        energy_rejections = Int(values[_PROGRAM_STAT_ENERGY]),
        retired_cells = Int(values[_PROGRAM_STAT_RETIRED]),
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
    if failure !== nothing && !_settlement_failure_is_expected(failure)
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
