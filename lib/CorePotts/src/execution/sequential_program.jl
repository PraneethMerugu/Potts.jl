# Proposal acceptance and the sequential/checkerboard program barriers.

mutable struct SequentialTransactionWorkspace{O, K, G, TS, R, D, L}
    ownership::O
    cell_kinds::K
    cell_generations::G
    trackers::TS
    relationships::R
    descriptor_state::D
    lifecycle_compaction::L
end

@inline function _sequential_workspace_with_lifecycle_compaction(
        workspace::SequentialTransactionWorkspace, lifecycle_compaction
    )
    return SequentialTransactionWorkspace(
        workspace.ownership,
        workspace.cell_kinds,
        workspace.cell_generations,
        workspace.trackers,
        workspace.relationships,
        workspace.descriptor_state,
        lifecycle_compaction,
    )
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
    candidate_snapshot::Any
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

"""Return the lifecycle receipt staged by a program-step transaction."""
@inline program_step_lifecycle_receipt(transaction::ProgramStepTransaction) =
    (_require_staged_program_step(transaction); transaction.lifecycle_receipt)

"""Return an independently owned snapshot of a staged program-step candidate."""
function program_step_snapshot(transaction::ProgramStepTransaction)
    _require_staged_program_step(transaction)
    transaction.candidate_snapshot === nothing ||
        return transaction.candidate_snapshot
    runtime = transaction.runtime
    return _materialize_program_state_snapshot(
        runtime, transaction.workspace, runtime.mcs + 1
    )
end

"""Validate and stage replacement parameters without publishing them."""
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
    return _validate_auxiliary_state_candidate(
        runtime.program.descriptor_plan.state_layout,
        runtime.descriptor_state,
        candidate,
    )
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
    if _is_checkerboard_execution_workspace(workspace)
        snapshot = transaction.candidate_snapshot
        snapshot === nothing && error(
            "checkerboard transaction has no materialized candidate snapshot"
        )
        _validate_program_descriptor_state(runtime, candidate)
        copyto_auxiliary_state!(snapshot.descriptor_state, candidate)
        return transaction
    end
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
        nothing,
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

"""Execute one MCS into an unpublished transaction candidate."""
function stage_program_mcs!(runtime::ProgramRuntime)
    _require_program_execution_capability(
        runtime.capability_report;
        operation = :staged_mcs,
    )
    if runtime.program.engine isa CheckerboardProgramEngine
        return _stage_checkerboard_program_mcs!(runtime)
    end
    runtime.program.engine isa SequentialProgramEngine || throw(ArgumentError(
        "staged coupled execution requires a sequential or checkerboard program"
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

function _stage_checkerboard_program_mcs!(runtime::ProgramRuntime)
    supports_queued_program_execution(runtime) || throw(ArgumentError(
        "staged checkerboard coupling requires the device-total queued MCS path"
    ))
    runtime.settled || throw(ArgumentError(
        "cannot stage an MCS while another program transaction is pending"
    ))
    before = _program_counter_snapshot(runtime)
    enqueue_program_mcs!(runtime)
    receipt = settle_program!(
        runtime.engine_workspace,
        ProgramSettlementRequest(PublicStepSettlement; full_snapshot = true),
    )
    if receipt.failure !== nothing
        _publish_program_receipt!(runtime, receipt)
        return nothing
    end
    candidate = (
        receipt.counters.accepted,
        receipt.counters.rejected,
        receipt.counters.null_attempts,
        receipt.counters.constraint_rejections,
        receipt.counters.energy_rejections,
        receipt.counters.retired_cells,
    )
    transaction = ProgramStepTransaction(
        runtime,
        runtime.engine_workspace,
        before,
        candidate,
        receipt.lifecycle_receipt,
    )
    transaction.candidate_snapshot = receipt.snapshot
    return transaction
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
    if _is_checkerboard_execution_workspace(transaction.workspace)
        workspace = _checkerboard_core(transaction.workspace)
        snapshot = transaction.candidate_snapshot
        _validate_program_descriptor_state(runtime, snapshot.descriptor_state)
        _, destination, _ = _checkerboard_transaction_banks(
            workspace, runtime.mcs
        )
        copyto_auxiliary_state!(
            destination.descriptor_state, snapshot.descriptor_state
        )
        pending === nothing || copyto!(destination.parameters, pending)
        KernelAbstractions.synchronize(
            KernelAbstractions.get_backend(destination.ownership)
        )
        workspace.execution.synchronization_count += 1
    else
        _validate_program_descriptor_state(
            runtime, transaction.workspace.descriptor_state
        )
    end
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
    if _is_checkerboard_execution_workspace(transaction.workspace)
        _publish_program_snapshot!(runtime, transaction.candidate_snapshot)
        _restore_program_counters!(runtime, transaction.counters_candidate)
        runtime.last_lifecycle_receipt = transaction.lifecycle_receipt
        runtime.failure_status = ProgramStatus()
        runtime.settled = true
        transaction.state = ProgramStepCommitted
        return runtime
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

"""Prevalidate and atomically publish a staged program-step transaction."""
function commit_program_step!(transaction::ProgramStepTransaction)
    prevalidate_program_step_transaction(transaction)
    return publish_program_step_transaction!(transaction)
end

"""Discard a staged program-step transaction without changing its runtime."""
function abort_program_step!(transaction::ProgramStepTransaction)
    _require_staged_program_step(transaction)
    runtime = transaction.runtime
    if _is_checkerboard_execution_workspace(transaction.workspace)
        _rollback_checkerboard_program_step!(transaction)
    end
    # The host runtime already points at its published bank; discarding the token
    # leaves that state and its counters unchanged.
    runtime.failure_status = ProgramStatus()
    runtime.settled = true
    transaction.state = ProgramStepAborted
    return runtime
end

@kernel function _rollback_checkerboard_program_step_kernel!(
        control, status, bank::Int32, committed::Int32,
        accepted::UInt64, rejected::UInt64, null_attempts::UInt64,
        constraint_rejections::UInt64, energy_rejections::UInt64,
        retired::UInt64,
    )
    if @index(Global, Linear) == 1
        @inbounds begin
            control.counters[_LIFECYCLE_CONTROL_ACTIVE_BANK] = bank
            control.counters[_LIFECYCLE_CONTROL_COMMITTED_MCS] = committed
            control.statistics[_PROGRAM_STAT_ACCEPTED] = accepted
            control.statistics[_PROGRAM_STAT_REJECTED] = rejected
            control.statistics[_PROGRAM_STAT_NULL] = null_attempts
            control.statistics[_PROGRAM_STAT_CONSTRAINT] = constraint_rejections
            control.statistics[_PROGRAM_STAT_ENERGY] = energy_rejections
            control.statistics[_PROGRAM_STAT_RETIRED] = retired
            status[1] = ProgramStatus()
        end
    end
end

function _rollback_checkerboard_program_step!(transaction)
    runtime = transaction.runtime
    workspace = _checkerboard_core(transaction.workspace)
    source, _, destination_bank = _checkerboard_transaction_banks(
        workspace, runtime.mcs
    )
    # `_checkerboard_transaction_banks` returns the destination bank as its
    # third result; the source bank is the opposite bank.
    published_bank = destination_bank == 1 ? Int32(2) : Int32(1)
    backend = KernelAbstractions.get_backend(source.ownership)
    counters = transaction.counters_before
    _rollback_checkerboard_program_step_kernel!(backend, 1)(
        source.lifecycle_control,
        source.program_status,
        published_bank,
        Int32(runtime.mcs),
        counters...;
        ndrange = 1,
    )
    KernelAbstractions.synchronize(backend)
    workspace.execution.synchronization_count += 1
    execution = workspace.execution
    execution.submitted_mcs = runtime.mcs
    execution.drained_mcs = runtime.mcs
    execution.committed_mcs = runtime.mcs
    execution.materialized_mcs = runtime.mcs
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

"""Return whether the runtime uses the prepared queued checkerboard path."""
@inline function supports_queued_program_execution(runtime::ProgramRuntime)
    return runtime.engine_workspace isa _CheckerboardExecutionWorkspace
end

function _checkerboard_execution_identity(
        workspace::CheckerboardWorkspace,
        color_laws,
        mechanics,
        queue_mcs_capacity::Integer,
    )
    mechanical_preparations = (
        color_laws.prepared...,
        mechanics.clear_report...,
        (entry.prepared[1]
            for entry in mechanics.stage_boundaries.before)...,
        (entry.prepared[2]
            for entry in mechanics.stage_boundaries.before)...,
        (entry.prepared[1]
            for entry in mechanics.stage_boundaries.after)...,
        (entry.prepared[2]
            for entry in mechanics.stage_boundaries.after)...,
        (mechanics.lifecycle_reductions === nothing ? () : (
            mechanics.lifecycle_reductions[1].site_index,
            mechanics.lifecycle_reductions[1].request_index,
            mechanics.lifecycle_reductions[1].selection,
            mechanics.lifecycle_reductions[2].site_index,
            mechanics.lifecycle_reductions[2].request_index,
            mechanics.lifecycle_reductions[2].selection,
        ))...,
    )
    compilers = map(mechanical_preparations) do prepared
        LocalMath.lowering_identity(prepared.plan)
    end
    all(==(isempty(compilers) ? nothing : first(compilers)), compilers) || throw(ArgumentError(
        "checkerboard proposal stages disagree on provider compiler"
    ))
    compiler_identity = isempty(compilers) ?
        :corepotts_kernelabstractions_v1 : first(compilers)
    mechanisms = workspace.capability_report.key.mechanisms
    submissions_per_mcs = _checked_checkerboard_capacity_mul(
        Int(workspace.state.program.attempts_per_site),
        Int(workspace.state.program.checkerboard_plan.color_count),
        :submissions_per_mcs,
    )
    before_lifecycle_submissions = sum(
        entry.repetitions for entry in mechanics.stage_boundaries.before;
        init = 0)
    after_lifecycle_submissions = sum(
        entry.repetitions for entry in mechanics.stage_boundaries.after;
        init = 0)
    return CheckerboardExecutionIdentity(
        _CHECKERBOARD_EXECUTION_SCHEMA,
        _CHECKERBOARD_MECHANISM_IDENTITY,
        :corepotts_checkerboard_transaction_v1,
        mechanisms.descriptor_fingerprint,
        _capability_key_fingerprint(workspace.capability_report.key),
        workspace.state.program.topology_epoch,
        (
            contract_version = mechanisms.rng_contract_version,
            lowering = mechanisms.rng_lowering_identity,
        ),
        (
            clear_report = LocalMath.lowering_identity(
                mechanics.clear_report[1].plan),
            color_mechanics = LocalMath.lowering_identity(
                first(color_laws.prepared).plan),
            before_lifecycle = map(mechanics.stage_boundaries.before) do entry
                LocalMath.lowering_identity(entry.prepared[1].plan)
            end,
            after_lifecycle = map(mechanics.stage_boundaries.after) do entry
                LocalMath.lowering_identity(entry.prepared[1].plan)
            end,
            lifecycle_status = mechanics.lifecycle_reductions === nothing ?
                :not_applicable : :corepotts_lifecycle_status_ka_v1,
            lifecycle_planning_status =
                mechanics.lifecycle_reductions === nothing ?
                :not_applicable : :corepotts_lifecycle_status_ka_v1,
            lifecycle_site_index = mechanics.lifecycle_reductions === nothing ?
                :not_applicable : LocalMath.lowering_identity(
                    mechanics.lifecycle_reductions[1].site_index.plan
                ),
            lifecycle_request_index = mechanics.lifecycle_reductions === nothing ?
                :not_applicable : LocalMath.lowering_identity(
                    mechanics.lifecycle_reductions[1].request_index.plan
                ),
            lifecycle_emission = mechanics.lifecycle_reductions === nothing ?
                :not_applicable : :corepotts_lifecycle_emission_ka_v1,
            lifecycle_selection = mechanics.lifecycle_reductions === nothing ?
                :not_applicable : LocalMath.lowering_identity(
                    mechanics.lifecycle_reductions[1].selection.plan
                ),
        ),
        :KernelAbstractions,
        compiler_identity,
        (
            mcs_capacity = Int(queue_mcs_capacity),
            color_submissions_per_mcs = submissions_per_mcs,
            clear_report_submissions_per_mcs = 1,
            before_lifecycle_submissions_per_mcs =
                before_lifecycle_submissions,
            after_lifecycle_submissions_per_mcs =
                after_lifecycle_submissions,
            lifecycle_status_submissions_per_mcs = 1,
            lifecycle_planning_status_submissions_per_mcs = 3,
            lifecycle_site_index_submissions_per_mcs = 1,
            lifecycle_request_index_submissions_per_mcs = 1,
            lifecycle_emission_submissions_per_mcs = 1,
            lifecycle_selection_submissions_per_mcs = 1,
            receipt_scope = :backend_queue,
            receipt_cumulative = true,
            receipt_selective = false,
            completion = :grouped_cumulative_receipts,
        ),
        _CHECKERBOARD_CHECKPOINT_SCHEMA,
    )
end

function _build_checkerboard_capability_report(
        direct::ProgramCapabilityReport,
        identity::CheckerboardExecutionIdentity,
    )
    capability_authorizes_execution(direct) ||
        throw(ProgramCapabilityError(:checkerboard_localmath, direct))
    identity.capability_fingerprint ==
        _capability_key_fingerprint(direct.key) || throw(ArgumentError(
        "checkerboard execution identity does not name the admitted capability key"
    ))
    return direct
end

function _prepare_checkerboard_execution(
        runtime::ProgramRuntime;
        queue_mcs_capacity::Integer = 12,
    )
    runtime.settled || throw(ArgumentError(
        "checkerboard execution preparation requires a settled runtime"
    ))
    _require_program_execution_capability(
        runtime.capability_report;
        operation = :checkerboard_localmath,
    )
    workspace = runtime.engine_workspace
    workspace isa CheckerboardWorkspace || throw(ArgumentError(
        "checkerboard execution preparation requires authoritative Core storage"
    ))
    queue_mcs_capacity > 0 || throw(ArgumentError(
        "checkerboard queue capacity must be positive"
    ))
    submissions_per_mcs = _checked_checkerboard_capacity_mul(
        Int(runtime.program.attempts_per_site),
        Int(runtime.program.checkerboard_plan.color_count),
        :compiled_color_submissions_per_mcs)
    color_lease_capacity = _checked_checkerboard_capacity_mul(
        Int(queue_mcs_capacity), submissions_per_mcs,
        :compiled_color_lease_capacity)
    color_laws = _prepare_checkerboard_color_laws(
        workspace,
        runtime.program.checkerboard_plan,
        runtime.program.proposal_offsets,
        runtime.program.descriptor_plan,
        runtime.program.stage_plan,
        runtime.program.ownership_change_handles,
        runtime.program.relationships,
        runtime.program.kind_count,
        color_lease_capacity,
    )
    mechanics = _prepare_localmath_checkerboard_mechanics(
        workspace;
        queue_mcs_capacity,
        canonical_plan = runtime.program.checkerboard_plan,
        canonical_proposal_offsets = runtime.program.proposal_offsets,
        canonical_stage_plan = runtime.program.stage_plan,
    )
    identity = _checkerboard_execution_identity(
        workspace,
        color_laws,
        mechanics,
        queue_mcs_capacity,
    )
    capability_report = _build_checkerboard_capability_report(
        runtime.capability_report, identity
    )
    execution = _CheckerboardExecutionWorkspace(
        workspace,
        color_laws,
        mechanics.clear_report,
        mechanics.stage_boundaries,
        mechanics.lifecycle_reductions,
        mechanics.gates,
        _empty_checkerboard_receipts(),
        identity,
        capability_report,
    )
    return _rebuild_program_runtime(runtime, capability_report, execution)
end

function _checkerboard_execution_identity_block(
        identity::CheckerboardExecutionIdentity
    )
    return (
        schema = identity.schema,
        mechanism_identity = identity.mechanism_identity,
        scientific_abi = identity.scientific_abi,
        descriptor_fingerprint = identity.descriptor_fingerprint,
        capability_fingerprint = identity.capability_fingerprint,
        topology_epoch = identity.topology_epoch,
        rng_identity = identity.rng_identity,
        lowerings = identity.lowerings,
        provider = identity.provider,
        provider_compiler = identity.provider_compiler,
        queue_policy = identity.queue_policy,
        checkpoint_schema = identity.checkpoint_schema,
    )
end

function _checkpoint_execution_block(
        runtime::ProgramRuntime{T, N, P, C, R, TS, D, SB, EW, LW}
    ) where {
        T, N, P, C, R, TS, D, SB,
        EW <: _CheckerboardExecutionWorkspace, LW,
    }
    execution = runtime.engine_workspace
    return (
        schema = _CHECKERBOARD_CHECKPOINT_SCHEMA,
        mechanism_identity = execution.identity.mechanism_identity,
        identity = _checkerboard_execution_identity_block(execution.identity),
    )
end

function _restore_checkerboard_checkpoint(
        program::CompiledPottsProgram,
        checkpoint::ProgramCheckpoint,
    )
    expected = _CHECKERBOARD_MECHANISM_IDENTITY
    _validate_program_checkpoint(program, checkpoint, expected)
    block = checkpoint.extensions.CorePotts.execution_lowering
    block.schema == _CHECKERBOARD_CHECKPOINT_SCHEMA || throw(ArgumentError(
        "checkerboard checkpoint has an unsupported execution schema"
    ))
    runtime = _restore_validated_program_checkpoint(program, checkpoint)
    runtime.engine_workspace isa CheckerboardWorkspace || return runtime
    queue_mcs_capacity = Int(block.identity.queue_policy.mcs_capacity)
    restored = _prepare_checkerboard_execution(
        runtime; queue_mcs_capacity
    )
    _checkpoint_execution_block(restored) == block || throw(ArgumentError(
        "checkerboard checkpoint execution identity does not match this environment"
    ))
    return restored
end

function _inspect_checkerboard_execution(
        execution::_CheckerboardExecutionWorkspace
    )
    return (
        identity = _checkerboard_execution_identity_block(execution.identity),
        color_mechanics = map(
            LocalMath.inspect, execution.color_laws.prepared),
        clear_report = map(LocalMath.inspect, execution.clear_report),
        stage_boundaries = (
            before = map(execution.stage_boundaries.before) do entry
                map(LocalMath.inspect, entry.prepared)
            end,
            after = map(execution.stage_boundaries.after) do entry
                map(LocalMath.inspect, entry.prepared)
            end,
        ),
        lifecycle_reductions = execution.lifecycle_reductions === nothing ?
            nothing : map(execution.lifecycle_reductions) do reductions
                (
                    direct = (owner = :CorePotts,
                        executor = :KernelAbstractions,
                        lowering = :corepotts_lifecycle_status_ka_v1),
                    planning = (owner = :CorePotts,
                        executor = :KernelAbstractions,
                        lowering = :corepotts_lifecycle_status_ka_v1),
                    site_index = LocalMath.inspect(reductions.site_index),
                    request_index = LocalMath.inspect(
                        reductions.request_index
                    ),
                    emission = (
                        owner = :CorePotts,
                        executor = :KernelAbstractions,
                        lowering = :corepotts_lifecycle_emission_ka_v1,
                    ),
                    selection = LocalMath.inspect(reductions.selection),
                )
            end,
        completion_receipts = (
            mechanics = execution.receipts.mechanics,
            lifecycle = execution.receipts.lifecycle,
        ),
        order = (
            :state_initialization_and_report_reset,
            :color_mechanics,
            :before_lifecycle,
            :core_lifecycle_transaction,
            :after_lifecycle,
            :bank_authorization_and_publication,
        ),
    )
end

"""Queue one checkerboard MCS without publishing host-visible logical state."""
function enqueue_program_mcs!(runtime::ProgramRuntime)
    _require_program_execution_capability(
        runtime.capability_report;
        operation = :queued_mcs,
    )
    supports_queued_program_execution(runtime) || throw(ArgumentError(
        "this program does not support queued whole-MCS execution"
    ))
    program_failed(runtime) && throw(ArgumentError(
        "cannot enqueue a program runtime after a terminal scientific failure"
    ))
    workspace = runtime.engine_workspace
    execution = _checkerboard_execution_position(workspace)
    current_mcs = execution.submitted_mcs
    _preflight_checkerboard_mcs!(workspace, current_mcs)
    # From this point onward an ordered CorePotts prefix may have reached the
    # backend even if a later LocalMath admission check rejects. Keep the
    # runtime unsettled until the portable settlement boundary drains it.
    runtime.settled = false
    _enqueue_checkerboard_mcs_after_preflight!(workspace, current_mcs)
    return runtime
end

"""Queue checkerboard execution through the requested absolute MCS."""
function enqueue_program_through!(
        runtime::ProgramRuntime, target_mcs::Integer
    )
    _require_program_execution_capability(
        runtime.capability_report;
        operation = :queued_mcs_through,
    )
    supports_queued_program_execution(runtime) || throw(ArgumentError(
        "this program does not support queued whole-MCS execution"
    ))
    workspace = runtime.engine_workspace
    execution = _checkerboard_execution_position(workspace)
    target = Int(target_mcs)
    target >= execution.submitted_mcs || throw(ArgumentError(
        "queued execution target precedes the submitted MCS"
    ))
    while execution.submitted_mcs < target
        enqueue_program_mcs!(runtime)
    end
    return runtime
end

"""Drain queued work and publish it according to a settlement request."""
function settle_program!(
        runtime::ProgramRuntime, request::ProgramSettlementRequest
    )
    _require_program_execution_capability(
        runtime.capability_report;
        operation = :settle_program,
    )
    supports_queued_program_execution(runtime) || throw(ArgumentError(
        "this program does not support queued whole-MCS settlement"
    ))
    receipt = settle_program!(runtime.engine_workspace, request)
    request.full_snapshot && _publish_program_receipt!(runtime, receipt)
    return receipt
end

function _advance_checkerboard_transaction!(runtime::ProgramRuntime)
    workspace = runtime.engine_workspace
    workspace isa _CheckerboardExecutionWorkspace || error(
        "checkerboard runtime has no portable execution workspace"
    )
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

"""Advance one complete transactional MCS and publish only after successful settlement."""
function advance_mcs!(runtime::ProgramRuntime)
    _require_program_execution_capability(
        runtime.capability_report;
        operation = :advance_mcs,
    )
    runtime.settled ||
        throw(ArgumentError("cannot advance an unsettled program runtime"))
    program_failed(runtime) && throw(ArgumentError(
        "cannot advance a program runtime after a terminal scientific failure"
    ))
    if runtime.program.engine isa CheckerboardProgramEngine
        return _advance_checkerboard_transaction!(runtime)
    end
    if runtime.program.engine isa SequentialProgramEngine
        return _advance_sequential_transaction!(runtime)
    end
    error("unsupported program engine $(typeof(runtime.program.engine))")
end

"""Return the durable symbolic identity of a compiled program backend."""
@inline program_backend_name(::CPUProgramBackend) = :CPUBackend
@inline program_backend_name(::AdaptedProgramBackend{Name}) where {Name} = Name

"""Inspect the program's engine, backend, numerical policy, tracker plan, and RNG contract."""
function program_execution_report(program::CompiledPottsProgram)
    _validate_compiled_program_integrity(program)
    return (
        engine = nameof(typeof(program.engine)),
        backend = program_backend_name(program.backend),
        scalar_type = eltype(program.parameter_defaults),
        shape = program.shape,
        attempts_per_site = program.attempts_per_site,
        trackers = tracker_plan_report(program.tracker_plan),
        rng = :Philox4x32x10V2,
        numerical_policy = (
            math = :accurate,
            reductions = :deterministic,
            bounds = :checked,
        ),
    )
end
