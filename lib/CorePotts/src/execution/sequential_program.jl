# Proposal acceptance and the sequential/checkerboard program barriers.

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

function _advance_checkerboard!(runtime::ProgramRuntime{T, N}) where {T, N}
    colors = 1 << N
    attempt_identity = 0
    for color in 0:(colors - 1)
        for target in CartesianIndices(runtime.ownership)
            encoded = 0
            coordinates = Tuple(target)
            for dimension in 1:N
                encoded |= ((coordinates[dimension] - 1) & 1) << (dimension - 1)
            end
            encoded == color || continue
            for _ in 1:Int(runtime.program.attempts_per_site)
                attempt_identity += 1
                _attempt!(runtime, target, attempt_identity, color)
            end
        end
    end
    return nothing
end

function _clear_retired_cell_state!(
        layout::StateLayout,
        state::AuxiliaryState,
        cell::Integer,
    )
    for entry in layout.entries
        entry.schema.domain === :cell || continue
        values = state_block(state, entry.handle).values
        1 <= cell <= length(values) || error(
            "compiled cell-state block is incompatible with the cell table"
        )
        @inbounds values[cell] = zero(eltype(values))
    end
    return state
end

function _retire_extinct_cells!(runtime::ProgramRuntime)
    for cell in eachindex(runtime.cell_kinds)
        @inbounds runtime.cell_kinds[cell] == 0 && continue
        @inbounds runtime.volumes[cell] == 0 || continue
        @inbounds runtime.cell_kinds[cell] = 0
        runtime.retired_cells += 1
        _clear_retired_cell_state!(
            runtime.program.descriptor_plan.state_layout,
            runtime.descriptor_state,
            cell,
        )
    end
    return nothing
end

function _after_mcs!(runtime::ProgramRuntime{T, N}) where {T, N}
    _retire_extinct_cells!(runtime)
    _execute_after_mcs_stage!(runtime)
    return nothing
end

function advance_mcs!(runtime::ProgramRuntime)
    runtime.settled ||
        throw(ArgumentError("cannot advance an unsettled program runtime"))
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
    return runtime
end

program_execution_report(program::CompiledPottsProgram) = (
    engine = nameof(typeof(program.engine)),
    backend = nameof(typeof(program.backend)),
    scalar_type = eltype(program.parameter_defaults),
    shape = program.shape,
    attempts_per_site = program.attempts_per_site,
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
)
