# Proposal acceptance and the sequential/checkerboard program barriers.

mutable struct SequentialTransactionWorkspace{O, K, G, TS, R, D}
    ownership::O
    cell_kinds::K
    cell_generations::G
    trackers::TS
    relationships::R
    descriptor_state::D
end
struct NoSequentialTransactionWorkspace end

function allocate_sequential_transaction_workspace(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
    )
    program.lifecycle_plan isa NoLifecycleExecutionPlan &&
        return NoSequentialTransactionWorkspace()
    return SequentialTransactionWorkspace(
        copy(ownership),
        copy(cell_kinds),
        copy(cell_generations),
        copy_tracker_state(trackers),
        copy(relationships),
        copy_auxiliary_state(program.descriptor_plan.state_layout, descriptor_state),
    )
end

@inline function proposal_log_acceptance_ratio(
        evaluation::ProposalEvaluation{T},
        temperature::Real,
    ) where {T <: AbstractFloat}
    converted_temperature = T(temperature)
    isfinite(converted_temperature) && converted_temperature >= zero(T) ||
        throw(ArgumentError(
            "acceptance temperature must be finite and nonnegative"
        ))
    all(isfinite, (
        evaluation.delta_h,
        evaluation.drive_energy,
        evaluation.drive_log_bias,
        evaluation.kinetic_modifier,
    )) || throw(ArgumentError(
        "proposal acceptance inputs must be finite"
    ))
    evaluation.constraints_allowed || return -T(Inf)
    if iszero(converted_temperature)
        iszero(evaluation.drive_log_bias) &&
            iszero(evaluation.kinetic_modifier) || throw(ArgumentError(
                "nonconservative drives and proposal modifiers require positive temperature"
            ))
        effective_energy = evaluation.delta_h + evaluation.drive_energy
        return effective_energy <= zero(T) ? zero(T) : -T(Inf)
    end
    return -(evaluation.delta_h + evaluation.drive_energy) /
           converted_temperature +
           evaluation.drive_log_bias + evaluation.kinetic_modifier
end

"""Exact conventional acceptance probability for a structured proposal evaluation."""
@inline function proposal_acceptance_probability(
        evaluation::ProposalEvaluation{T}, temperature::Real
    ) where {T <: AbstractFloat}
    log_ratio = proposal_log_acceptance_ratio(evaluation, temperature)
    return log_ratio >= zero(T) ? one(T) :
           isfinite(log_ratio) ? exp(log_ratio) : zero(T)
end

"""Apply the V1 strict-threshold decision to one pre-addressed uniform draw."""
@inline function proposal_acceptance_decision(
        evaluation::ProposalEvaluation{T},
        temperature::Real,
        draw::Real,
    ) where {T <: AbstractFloat}
    converted_draw = T(draw)
    zero(T) < converted_draw < one(T) || throw(ArgumentError(
        "acceptance draws must lie strictly inside (0, 1)"
    ))
    log_ratio = proposal_log_acceptance_ratio(evaluation, temperature)
    return log_ratio >= zero(T) ||
           (isfinite(log_ratio) && log(converted_draw) < log_ratio)
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
    if !evaluation.constraints_allowed
        runtime.constraint_rejections += 1
        runtime.rejected += 1
        return false
    end
    temperature = compiled_scalar_value(program.temperature, runtime.parameters)
    log_ratio = proposal_log_acceptance_ratio(evaluation, temperature)
    accepted = log_ratio >= zero(T)
    if !accepted && isfinite(log_ratio)
        draw = _proposal_acceptance_draw(
            runtime,
            attempt_identity,
            subround,
            draw_mode,
            scripted_draw,
        )
        accepted = proposal_acceptance_decision(
            evaluation, temperature, draw
        )
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

function _advance_sequential_transaction!(runtime::ProgramRuntime)
    workspace = runtime.engine_workspace
    workspace isa SequentialTransactionWorkspace || error(
        "sequential runtime has no transaction workspace"
    )
    counters = _program_counter_snapshot(runtime)
    _prepare_sequential_transaction!(runtime, workspace)
    runtime.settled = false
    try
        _advance_sequential!(runtime)
        _after_mcs!(runtime)
    catch error
        _restore_sequential_transaction!(runtime, workspace)
        _restore_program_counters!(runtime, counters)
        status = runtime.lifecycle_workspace isa LifecycleWorkspace ?
            lifecycle_workspace_status(runtime.lifecycle_workspace) :
            LifecycleStatusPayload()
        if error isa AbstractLifecycleFailure &&
                status.code !== LifecycleStatusSuccess
            if lifecycle_status_is_expected(status)
                runtime.failure_status = status
                runtime.settled = true
                return runtime
            end
        end
        rethrow()
    end
    runtime.mcs += 1
    runtime.failure_status = LifecycleStatusPayload()
    runtime.settled = true
    return runtime
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
    runtime.settled = true
    return runtime
end

@inline function supports_queued_program_execution(runtime::ProgramRuntime)
    runtime.engine_workspace isa CheckerboardWorkspace || return false
    runtime.program.lifecycle_plan isa LifecycleExecutionPlan || return false
    return isempty(runtime.program.stage_plan.after_mcs)
end

function enqueue_program_mcs!(runtime::ProgramRuntime)
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
    succeeded = true
    try
        _execute_after_mcs_stage!(
            transaction, runtime.program.stage_plan.before_lifecycle
        )
        execute_lifecycle!(transaction)
        _execute_after_mcs_stage!(
            transaction, runtime.program.stage_plan.after_lifecycle
        )
    catch error
        status = lifecycle_workspace_status(
            transaction.lifecycle_workspace
        )
        if error isa AbstractLifecycleFailure &&
                status.code !== LifecycleStatusSuccess &&
                lifecycle_status_is_expected(status)
            succeeded = false
        else
            rethrow()
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
    runtime.settled ||
        throw(ArgumentError("cannot advance an unsettled program runtime"))
    program_failed(runtime) && throw(ArgumentError(
        "cannot advance a program runtime after a terminal scientific failure"
    ))
    if runtime.program.engine isa CheckerboardProgramEngine &&
            runtime.program.lifecycle_plan isa LifecycleExecutionPlan
        return _advance_checkerboard_transaction!(runtime)
    end
    runtime.program.engine isa SequentialProgramEngine &&
            runtime.program.lifecycle_plan isa LifecycleExecutionPlan &&
        return _advance_sequential_transaction!(runtime)
    runtime.settled = false
    if runtime.program.engine isa SequentialProgramEngine
        _advance_sequential!(runtime)
    elseif runtime.program.engine isa CheckerboardProgramEngine
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

program_execution_report(program::CompiledPottsProgram) = (
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

program_capability_report(program::CompiledPottsProgram) = (
    sequential = program.engine isa SequentialProgramEngine,
    checkerboard = program.engine isa CheckerboardProgramEngine,
    cpu = program.backend isa CPUProgramBackend,
    gpu = program.backend isa AdaptedProgramBackend,
    state_domains = Tuple(unique(
        entry.schema.domain
        for entry in program.descriptor_plan.state_layout.entries
    )),
    stage_effects = Tuple(unique(
        nameof(typeof(descriptor.effect))
        for groups in (
            program.stage_plan.accepted_copy,
            program.stage_plan.after_mcs,
        )
        for group in groups
        for descriptor in group.instances
    )),
    relationships = !isempty(program.relationships),
    trackers = tracker_plan_report(program.tracker_plan),
    checkerboard_plan = checkerboard_plan_report(program.checkerboard_plan),
)
