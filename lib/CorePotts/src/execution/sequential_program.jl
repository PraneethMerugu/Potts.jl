# Proposal acceptance and the sequential/checkerboard program barriers.

mutable struct SequentialTransactionWorkspace{O, K, G, TS, R, D}
    ownership::O
    cell_kinds::K
    cell_generations::G
    trackers::TS
    relationships::R
    descriptor_state::D
end

@enum ProgramStepTransactionState::UInt8 begin
    ProgramStepStaged = 0x01
    ProgramStepCommitted = 0x02
    ProgramStepAborted = 0x03
end

"""Opaque unpublished sequential-MCS candidate owned by CorePotts."""
mutable struct ProgramStepTransaction{T <: AbstractFloat, R, W, C, L}
    runtime::R
    workspace::W
    counters_before::C
    counters_candidate::C
    lifecycle_receipt::L
    pending_parameters::Union{Nothing, Vector{T}}
    state::ProgramStepTransactionState
end

function ProgramStepTransaction(
        runtime::ProgramRuntime{T}, workspace, counters_before,
        counters_candidate, receipt
    ) where {T}
    return ProgramStepTransaction{
        T, typeof(runtime), typeof(workspace), typeof(counters_before),
        typeof(receipt),
    }(
        runtime,
        workspace,
        counters_before,
        counters_candidate,
        receipt,
        nothing,
        ProgramStepStaged,
    )
end

@inline function _require_staged_program_step(
        transaction::ProgramStepTransaction
    )
    transaction.state === ProgramStepStaged || throw(ArgumentError(
        "program-step transaction is no longer staged"
    ))
    transaction.runtime.settled && throw(ArgumentError(
        "a staged program-step transaction cannot own a settled runtime"
    ))
    return transaction
end

@inline program_step_lifecycle_receipt(transaction::ProgramStepTransaction) =
    (_require_staged_program_step(transaction); transaction.lifecycle_receipt)

function program_step_snapshot(transaction::ProgramStepTransaction)
    _require_staged_program_step(transaction)
    runtime = transaction.runtime
    return _materialize_program_state_snapshot(
        runtime, transaction.workspace, runtime.mcs + 1
    )
end

function stage_program_parameters!(
        transaction::ProgramStepTransaction{T},
        parameters::AbstractVector{<:Real},
    ) where {T}
    _require_staged_program_step(transaction)
    transaction.pending_parameters === nothing || throw(ArgumentError(
        "program parameters are already staged for this transaction"
    ))
    transaction.pending_parameters = _validated_program_parameters(
        transaction.runtime.program, parameters
    )
    return transaction
end

@inline function _descriptor_state_banks_are_independent(
        candidate::AuxiliaryState,
        staged::AuxiliaryState,
        published::AuxiliaryState,
    )
    for source_bank in candidate.banks
        source = source_bank.values
        for destination_bank in staged.banks
            Base.mightalias(source, destination_bank.values) && return false
        end
        for destination_bank in published.banks
            Base.mightalias(source, destination_bank.values) && return false
        end
    end
    return true
end

function _validate_program_descriptor_state(
        runtime::ProgramRuntime,
        candidate::AuxiliaryState,
    )
    expected = runtime.descriptor_state
    typeof(candidate.banks) === typeof(expected.banks) || throw(ArgumentError(
        "descriptor state has an incompatible physical layout or element type"
    ))
    for (candidate_bank, expected_bank) in zip(
            candidate.banks, expected.banks
        )
        axes(candidate_bank.values) == axes(expected_bank.values) || throw(
            ArgumentError("descriptor state has an incompatible bank shape")
        )
    end
    for entry in runtime.program.descriptor_plan.state_layout.entries
        validate_state_block(
            entry.schema, state_block(candidate, entry.handle)
        )
    end
    return candidate
end

"""
Stage an independently owned auxiliary-state candidate for coordinated commit.

The supplied state is validated completely before it is copied into the
transaction's unpublished bank. The last published bank is never mutated;
`abort_program_step!` therefore restores it without copying.
"""
function stage_program_descriptor_state!(
        transaction::ProgramStepTransaction,
        candidate::AuxiliaryState,
    )
    _require_staged_program_step(transaction)
    runtime = transaction.runtime
    workspace = transaction.workspace
    runtime.engine_workspace === workspace || throw(ArgumentError(
        "program-step transaction lost its runtime workspace ownership"
    ))
    _descriptor_state_banks_are_independent(
        candidate,
        runtime.descriptor_state,
        workspace.descriptor_state,
    ) || throw(ArgumentError(
        "staged descriptor state must own independent storage"
    ))
    _validate_program_descriptor_state(runtime, candidate)
    copyto_auxiliary_state!(workspace.descriptor_state, candidate)
    return transaction
end

function stage_program_descriptor_state!(
        transaction::ProgramStepTransaction,
        candidate,
    )
    _require_staged_program_step(transaction)
    throw(ArgumentError(
        "staged descriptor state must be a CorePotts AuxiliaryState"
    ))
end

"""Independently owned view of parameters that would become visible at commit."""
@inline function program_step_parameter_view(
        transaction::ProgramStepTransaction
    )
    _require_staged_program_step(transaction)
    pending = transaction.pending_parameters
    pending === nothing && throw(ArgumentError(
        "no unpublished program parameters are staged for this transaction"
    ))
    return copy(pending)
end

function allocate_sequential_transaction_workspace(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
    )
    return SequentialTransactionWorkspace(
        copy(ownership),
        copy(cell_kinds),
        copy(cell_generations),
        copy_tracker_state(trackers),
        copy(relationships),
        copy_auxiliary_state(program.descriptor_plan.state_layout, descriptor_state),
    )
end

@inline function _proposal_acceptance_draw(
        runtime::ProgramRuntime{T},
        attempt_identity::Int,
        subround::Int,
        ::Val{:addressed},
        scripted::T,
    ) where {T}
    return _program_uniform(
        T,
        runtime,
        AcceptanceStream,
        3,
        attempt_identity;
        subround,
    )
end

@inline _proposal_acceptance_draw(
    runtime::ProgramRuntime{T},
    attempt_identity::Int,
    subround::Int,
    ::Val{:scripted},
    scripted::T,
) where {T} = scripted

function _attempt_selected!(
        runtime::ProgramRuntime{T, N},
        source::CartesianIndex{N},
        target::CartesianIndex{N},
        attempt_identity::Int,
        subround::Int,
        draw_mode::Val,
        scripted_draw::T,
    ) where {T, N}
    program = runtime.program
    old_owner = @inbounds runtime.ownership[target]
    new_owner = @inbounds runtime.ownership[source]
    old_owner == new_owner && (runtime.null_attempts += 1; return false)
    if !_extinction_copy_admitted(runtime, old_owner, new_owner)
        runtime.constraint_rejections += 1
        runtime.rejected += 1
        return false
    end

    context = _ProposalEvaluationContext(
        runtime,
        source,
        target,
        old_owner,
        new_owner,
        attempt_identity,
        subround,
    )
    evaluate_proposal_contributions!(
        runtime.proposal_contributions,
        program.descriptor_plan,
        context,
    )
    evaluation = fold_proposal_contributions(
        program.descriptor_plan, runtime.proposal_contributions
    )
    temperature = compiled_scalar_value(program.temperature, runtime.parameters)
    result = _proposal_acceptance_result(evaluation, temperature)
    if result.code === ProposalAcceptanceConstraintRejected
        runtime.constraint_rejections += 1
        runtime.rejected += 1
        return false
    end
    if result.code !== ProposalAcceptanceReady
        runtime.failure_status = _acceptance_failure_status(
            result, runtime.mcs + 1, attempt_identity
        )
        return false
    end
    log_ratio = result.log_ratio
    accepted = log_ratio >= zero(T)
    if !accepted && isfinite(log_ratio)
        draw = _proposal_acceptance_draw(
            runtime,
            attempt_identity,
            subround,
            draw_mode,
            scripted_draw,
        )
        accepted = log(draw) < log_ratio
    end
    if accepted
        _emit_accepted_copy_stage!(runtime, context)
        _commit_copy!(
            runtime,
            target,
            old_owner,
            new_owner,
            context,
        )
        runtime.accepted += 1
        return true
    end
    runtime.energy_rejections += 1
    runtime.rejected += 1
    return false
end

function _attempt!(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        attempt_identity::Int,
        subround::Int,
    ) where {T, N}
    program = runtime.program
    direction = _program_bounded(
        runtime,
        ProposalDirectionStream,
        2,
        attempt_identity,
        size(program.proposal_offsets, 2);
        subround,
    )
    source = _neighbor_index(program, target, program.proposal_offsets, direction)
    source === nothing && (runtime.null_attempts += 1; return false)
    return _attempt_selected!(
        runtime,
        source,
        target,
        attempt_identity,
        subround,
        Val(:addressed),
        zero(T),
    )
end

function _advance_sequential!(runtime::ProgramRuntime)
    site_count = length(runtime.ownership)
    attempts = site_count * Int(runtime.program.attempts_per_site)
    indices = CartesianIndices(runtime.ownership)
    for attempt in 1:attempts
        target_linear = _program_bounded(
            runtime, ProposalRecipientStream, 1, attempt, site_count
        )
        _attempt!(runtime, indices[target_linear], attempt, 0)
        program_failed(runtime) && return nothing
    end
    return nothing
end

function _after_mcs!(runtime::ProgramRuntime{T, N}) where {T, N}
    _execute_after_mcs_stage!(
        runtime, runtime.program.stage_plan.before_lifecycle
    )
    execute_lifecycle!(runtime)
    _execute_after_mcs_stage!(
        runtime, runtime.program.stage_plan.after_lifecycle
    )
    return nothing
end

function _prepare_sequential_transaction!(runtime, workspace)
    copyto!(workspace.ownership, runtime.ownership)
    copyto!(workspace.cell_kinds, runtime.cell_kinds)
    copyto!(workspace.cell_generations, runtime.cell_generations)
    copyto_tracker_state!(workspace.trackers, runtime.trackers)
    copyto!(workspace.relationships, runtime.relationships)
    copyto_auxiliary_state!(workspace.descriptor_state, runtime.descriptor_state)
    runtime.ownership, workspace.ownership = workspace.ownership, runtime.ownership
    runtime.cell_kinds, workspace.cell_kinds =
        workspace.cell_kinds, runtime.cell_kinds
    runtime.cell_generations, workspace.cell_generations =
        workspace.cell_generations, runtime.cell_generations
    runtime.trackers, workspace.trackers = workspace.trackers, runtime.trackers
    runtime.relationships, workspace.relationships =
        workspace.relationships, runtime.relationships
    runtime.descriptor_state, workspace.descriptor_state =
        workspace.descriptor_state, runtime.descriptor_state
    if runtime.lifecycle_workspace isa LifecycleWorkspace
        runtime.lifecycle_workspace = _lifecycle_workspace_with_staged_state(
            runtime.lifecycle_workspace, runtime
        )
    end
    return runtime
end

function _restore_sequential_transaction!(runtime, workspace)
    runtime.ownership, workspace.ownership = workspace.ownership, runtime.ownership
    runtime.cell_kinds, workspace.cell_kinds =
        workspace.cell_kinds, runtime.cell_kinds
    runtime.cell_generations, workspace.cell_generations =
        workspace.cell_generations, runtime.cell_generations
    runtime.trackers, workspace.trackers = workspace.trackers, runtime.trackers
    runtime.relationships, workspace.relationships =
        workspace.relationships, runtime.relationships
    runtime.descriptor_state, workspace.descriptor_state =
        workspace.descriptor_state, runtime.descriptor_state
    if runtime.lifecycle_workspace isa LifecycleWorkspace
        runtime.lifecycle_workspace = _lifecycle_workspace_with_staged_state(
            runtime.lifecycle_workspace, runtime
        )
    end
    return runtime
end

@inline function _program_counter_snapshot(runtime)
    return (
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
    )
end

@inline function _restore_program_counters!(runtime, values)
    runtime.accepted = values[1]
    runtime.rejected = values[2]
    runtime.null_attempts = values[3]
    runtime.constraint_rejections = values[4]
    runtime.energy_rejections = values[5]
    runtime.retired_cells = values[6]
    return runtime
end

function stage_program_mcs!(runtime::ProgramRuntime)
    _require_program_execution_capability(
        runtime.capability_report; operation = :staged_mcs
    )
    runtime.program.engine isa SequentialProgramEngine || throw(ArgumentError(
        "staged coupled execution currently requires the sequential CPU reference profile"
    ))
    runtime.settled || throw(ArgumentError(
        "cannot stage an MCS while another program transaction is pending"
    ))
    program_failed(runtime) && throw(ArgumentError(
        "cannot stage a program runtime after a terminal scientific failure"
    ))
    workspace = runtime.engine_workspace
    workspace isa SequentialTransactionWorkspace || error(
        "sequential runtime has no transaction workspace"
    )
    counters = _program_counter_snapshot(runtime)
    _prepare_sequential_transaction!(runtime, workspace)
    runtime.failure_status = ProgramStatus()
    runtime.settled = false
    try
        _advance_sequential!(runtime)
        program_failed(runtime) || _after_mcs!(runtime)
        if program_failed(runtime)
            status = runtime.failure_status
            _restore_sequential_transaction!(runtime, workspace)
            _restore_program_counters!(runtime, counters)
            runtime.failure_status = status
            runtime.settled = true
            return nothing
        end
        receipt = _materialize_lifecycle_receipt(
            runtime.program.lifecycle_plan,
            runtime.lifecycle_workspace,
            workspace.cell_kinds,
            workspace.cell_generations,
            runtime.cell_kinds,
            runtime.cell_generations,
            runtime.mcs + 1,
            runtime.seed,
            runtime.replica,
            runtime.repeat,
        )
        candidate_counters = _program_counter_snapshot(runtime)
        transaction = ProgramStepTransaction(
            runtime, workspace, counters, candidate_counters, receipt
        )
        # Staging owns the inactive transaction bank.  Restore the runtime's
        # published bank before exposing the token so no caller can observe
        # unpublished scientific state through `ProgramRuntime` fields.
        _restore_sequential_transaction!(runtime, workspace)
        _restore_program_counters!(runtime, counters)
        return transaction
    catch error
        status = runtime.lifecycle_workspace isa LifecycleWorkspace ?
            lifecycle_workspace_status(runtime.lifecycle_workspace) :
            ProgramStatus()
        _restore_sequential_transaction!(runtime, workspace)
        _restore_program_counters!(runtime, counters)
        if error isa AbstractLifecycleFailure &&
                status.code !== ProgramStatusSuccess
            if program_status_is_expected(status)
                runtime.failure_status = status
                runtime.settled = true
                return nothing
            end
        end
        runtime.lifecycle_workspace isa LifecycleWorkspace &&
            _reset_lifecycle_workspace!(runtime.lifecycle_workspace)
        runtime.failure_status = ProgramStatus()
        runtime.settled = true
        rethrow()
    end
end

"""Validate a program token completely before any coordinated publication."""
function prevalidate_program_step_transaction(
        transaction::ProgramStepTransaction
    )
    _require_staged_program_step(transaction)
    runtime = transaction.runtime
    runtime.engine_workspace === transaction.workspace || throw(ArgumentError(
        "program-step transaction lost its runtime workspace ownership"
    ))
    pending = transaction.pending_parameters
    if pending !== nothing
        _validated_program_parameters(runtime.program, pending)
    end
    _validate_program_descriptor_state(
        runtime, transaction.workspace.descriptor_state
    )
    return transaction
end

"""
Publish a prevalidated program token using assignment-only operations.

This is the no-throw half of coordinated commit and must only be called after
`prevalidate_program_step_transaction` succeeds for every participating token.
"""
function publish_program_step_transaction!(
        transaction::ProgramStepTransaction
    )
    runtime = transaction.runtime
    if transaction.pending_parameters !== nothing
        copyto!(runtime.parameters, transaction.pending_parameters)
    end
    # The candidate has remained isolated in the transaction workspace since
    # staging.  Publication is the single pointer-swap that makes it active.
    _restore_sequential_transaction!(runtime, transaction.workspace)
    _restore_program_counters!(runtime, transaction.counters_candidate)
    runtime.last_lifecycle_receipt = transaction.lifecycle_receipt
    runtime.mcs += 1
    runtime.failure_status = ProgramStatus()
    runtime.settled = true
    transaction.state = ProgramStepCommitted
    return runtime
end

function commit_program_step!(transaction::ProgramStepTransaction)
    prevalidate_program_step_transaction(transaction)
    return publish_program_step_transaction!(transaction)
end

function abort_program_step!(transaction::ProgramStepTransaction)
    _require_staged_program_step(transaction)
    runtime = transaction.runtime
    # The runtime already points at its published bank; discarding the token
    # leaves that state and its counters unchanged.
    runtime.failure_status = ProgramStatus()
    runtime.settled = true
    transaction.state = ProgramStepAborted
    return runtime
end

function _advance_sequential_transaction!(runtime::ProgramRuntime)
    transaction = stage_program_mcs!(runtime)
    transaction === nothing && return runtime
    return commit_program_step!(transaction)
end

function _publish_program_snapshot!(runtime::ProgramRuntime, snapshot)
    copyto!(runtime.ownership, snapshot.ownership)
    copyto!(runtime.cell_kinds, snapshot.cell_kinds)
    copyto!(runtime.cell_generations, snapshot.cell_generations)
    copyto_tracker_state!(runtime.trackers, snapshot.trackers)
    copyto!(runtime.relationships, snapshot.relationships)
    copyto_auxiliary_state!(runtime.descriptor_state, snapshot.descriptor_state)
    runtime.mcs = snapshot.mcs
    return runtime
end

function _publish_program_receipt!(runtime::ProgramRuntime, receipt)
    receipt.snapshot === nothing && throw(LifecycleInvariantFailure(
        Int32(0), Int32(receipt.committed_mcs), :missing_program_snapshot
    ))
    _publish_program_snapshot!(runtime, receipt.snapshot)
    runtime.accepted = receipt.counters.accepted
    runtime.rejected = receipt.counters.rejected
    runtime.null_attempts = receipt.counters.null_attempts
    runtime.constraint_rejections = receipt.counters.constraint_rejections
    runtime.energy_rejections = receipt.counters.energy_rejections
    runtime.retired_cells = receipt.counters.retired_cells
    runtime.failure_status = receipt.status
    receipt.lifecycle_receipt === nothing ||
        (runtime.last_lifecycle_receipt = receipt.lifecycle_receipt)
    runtime.settled = true
    return runtime
end

@inline function supports_queued_program_execution(runtime::ProgramRuntime)
    runtime.engine_workspace isa CheckerboardWorkspace || return false
    return isempty(runtime.program.stage_plan.after_mcs)
end

function enqueue_program_mcs!(runtime::ProgramRuntime)
    _require_program_execution_capability(
        runtime.capability_report; operation = :queued_mcs
    )
    supports_queued_program_execution(runtime) || throw(ArgumentError(
        "this program does not support queued whole-MCS execution"
    ))
    program_failed(runtime) && throw(ArgumentError(
        "cannot enqueue a program runtime after a terminal scientific failure"
    ))
    workspace = runtime.engine_workspace
    enqueue_checkerboard_mcs!(workspace, workspace.execution.submitted_mcs)
    runtime.settled = false
    return runtime
end

function enqueue_program_through!(
        runtime::ProgramRuntime, target_mcs::Integer
    )
    _require_program_execution_capability(
        runtime.capability_report; operation = :queued_mcs_through
    )
    supports_queued_program_execution(runtime) || throw(ArgumentError(
        "this program does not support queued whole-MCS execution"
    ))
    workspace = runtime.engine_workspace
    target = Int(target_mcs)
    target >= workspace.execution.submitted_mcs || throw(ArgumentError(
        "queued execution target precedes the submitted MCS"
    ))
    while workspace.execution.submitted_mcs < target
        enqueue_program_mcs!(runtime)
    end
    return runtime
end

function settle_program!(
        runtime::ProgramRuntime, request::ProgramSettlementRequest
    )
    _require_program_execution_capability(
        runtime.capability_report; operation = :settle_program
    )
    supports_queued_program_execution(runtime) || throw(ArgumentError(
        "this program does not support queued whole-MCS settlement"
    ))
    receipt = settle_program!(runtime.engine_workspace, request)
    request.full_snapshot && _publish_program_receipt!(runtime, receipt)
    return receipt
end

mutable struct _CheckerboardTransactionRuntime{
        P, O, K, G, TS, R, D, S, L, A,
    }
    program::P
    ownership::O
    cell_kinds::K
    cell_generations::G
    trackers::TS
    relationships::R
    descriptor_state::D
    stage_buffers::S
    lifecycle_workspace::L
    parameters::A
    mcs::Int
    retired_cells::UInt64
end

function _checkerboard_transaction_runtime(runtime, state, mcs)
    return _CheckerboardTransactionRuntime(
        runtime.program,
        state.ownership,
        state.cell_kinds,
        state.cell_generations,
        state.trackers,
        state.relationships,
        state.descriptor_state,
        state.stage_buffers,
        state.lifecycle_workspace,
        state.parameters,
        Int(mcs),
        runtime.retired_cells,
    )
end

function _advance_checkerboard_host_stage_transaction!(runtime::ProgramRuntime)
    workspace = runtime.engine_workspace
    current_mcs = workspace.execution.submitted_mcs
    source, destination, destination_bank = _checkerboard_transaction_banks(
        workspace, current_mcs
    )
    destination = _checkerboard_state_at_mcs(destination, current_mcs)
    backend = KernelAbstractions.get_backend(destination.ownership)
    backend isa KernelAbstractions.CPU || throw(ArgumentError(
        "host after-MCS transaction execution requires the CPU backend"
    ))
    _enqueue_program_state_copy!(destination, source)
    execute_checkerboard_mcs!(workspace, current_mcs, destination)
    transaction = _checkerboard_transaction_runtime(
        runtime, destination, current_mcs
    )
    succeeded = _program_backend_open(destination)
    if succeeded
        try
            _execute_after_mcs_stage!(
                transaction, runtime.program.stage_plan.before_lifecycle
            )
            execute_lifecycle!(transaction)
            _execute_after_mcs_stage!(
                transaction, runtime.program.stage_plan.after_lifecycle
            )
        catch error
            status = @inbounds destination.program_status[1]
            if error isa AbstractLifecycleFailure &&
                    status.code !== ProgramStatusSuccess &&
                    program_status_is_expected(status)
                succeeded = false
            else
                rethrow()
            end
        end
    end
    if succeeded
        @inbounds destination.lifecycle_control.statistics[
            _PROGRAM_STAT_RETIRED
        ] = transaction.retired_cells
    end
    _enqueue_program_bank_publication!(
        destination,
        workspace.report,
        destination_bank,
        current_mcs + 1,
    )
    workspace.execution.submitted_mcs = current_mcs + 1
    runtime.settled = false
    receipt = settle_program!(
        workspace,
        ProgramSettlementRequest(PublicStepSettlement; full_snapshot = true),
    )
    _publish_program_receipt!(runtime, receipt)
    return runtime
end

function _advance_checkerboard_transaction!(runtime::ProgramRuntime)
    workspace = runtime.engine_workspace
    workspace isa CheckerboardWorkspace || error(
        "checkerboard runtime has no portable execution workspace"
    )
    isempty(runtime.program.stage_plan.after_mcs) ||
        return _advance_checkerboard_host_stage_transaction!(runtime)
    enqueue_program_mcs!(runtime)
    receipt = settle_program!(
        runtime,
        ProgramSettlementRequest(PublicStepSettlement; full_snapshot = true),
    )
    receipt.snapshot === nothing && throw(LifecycleInvariantFailure(
        Int32(0), Int32(receipt.committed_mcs), :missing_program_snapshot
    ))
    return runtime
end

function advance_mcs!(runtime::ProgramRuntime)
    _require_program_execution_capability(
        runtime.capability_report; operation = :advance_mcs
    )
    runtime.settled ||
        throw(ArgumentError("cannot advance an unsettled program runtime"))
    program_failed(runtime) && throw(ArgumentError(
        "cannot advance a program runtime after a terminal scientific failure"
    ))
    if runtime.program.engine isa CheckerboardProgramEngine
        return _advance_checkerboard_transaction!(runtime)
    end
    runtime.program.engine isa SequentialProgramEngine &&
        return _advance_sequential_transaction!(runtime)
    runtime.settled = false
    if runtime.program.engine isa CheckerboardProgramEngine
        _advance_checkerboard!(runtime)
    else
        error("unreachable program engine")
    end
    _after_mcs!(runtime)
    runtime.mcs += 1
    runtime.settled = true
    return runtime
end

@inline program_backend_name(::CPUProgramBackend) = :CPUBackend
@inline program_backend_name(::AdaptedProgramBackend{Name}) where {Name} = Name

function program_execution_report(program::CompiledPottsProgram)
    _validate_compiled_program_integrity(program)
    return (
        engine = nameof(typeof(program.engine)),
        backend = program_backend_name(program.backend),
        scalar_type = eltype(program.parameter_defaults),
        shape = program.shape,
        attempts_per_site = program.attempts_per_site,
        trackers = tracker_plan_report(program.tracker_plan),
        rng = :Philox4x32x10V1,
        numerical_policy = (
            math = :accurate,
            reductions = :deterministic,
            bounds = :checked,
        ),
    )
end
