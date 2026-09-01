# Kernel-safe proposal acceptance shared by every execution profile.

@enum ProposalAcceptanceCode::UInt8 begin
    ProposalAcceptanceReady = 0x00
    ProposalAcceptanceConstraintRejected = 0x01
    ProposalAcceptanceNonfinite = 0x02
    ProposalAcceptanceZeroTemperatureDrive = 0x03
end

struct ProposalAcceptanceResult{T <: AbstractFloat}
    log_ratio::T
    code::ProposalAcceptanceCode
end

@inline function _proposal_acceptance_result(
        evaluation::ProposalEvaluation{T}, temperature::T
    ) where {T <: AbstractFloat}
    return _proposal_acceptance_result(
        evaluation.delta_h,
        evaluation.drive_energy,
        evaluation.drive_log_bias,
        evaluation.kinetic_modifier,
        evaluation.constraints_allowed,
        temperature,
    )
end

@inline function _proposal_acceptance_result(
        delta_h::T,
        drive_energy::T,
        drive_log_bias::T,
        kinetic_modifier::T,
        constraints_allowed::Bool,
        temperature::T,
    ) where {T <: AbstractFloat}
    log_ratio, code = _proposal_acceptance_values(
        delta_h, drive_energy, drive_log_bias, kinetic_modifier,
        constraints_allowed, temperature)
    return ProposalAcceptanceResult(log_ratio, code)
end

@inline function _proposal_acceptance_values(
        delta_h::T,
        drive_energy::T,
        drive_log_bias::T,
        kinetic_modifier::T,
        constraints_allowed::Bool,
        temperature::T,
    ) where {T <: AbstractFloat}
    constraints_allowed || return (
        -T(Inf), ProposalAcceptanceConstraintRejected)
    finite = isfinite(delta_h) &&
             isfinite(drive_energy) &&
             isfinite(drive_log_bias) &&
             isfinite(kinetic_modifier)
    finite || return (-T(Inf), ProposalAcceptanceNonfinite)
    if iszero(temperature)
        if !iszero(drive_log_bias) || !iszero(kinetic_modifier)
            return (-T(Inf), ProposalAcceptanceZeroTemperatureDrive)
        end
        effective_energy = delta_h + drive_energy
        isfinite(effective_energy) || return (
            -T(Inf), ProposalAcceptanceNonfinite)
        return (
            effective_energy <= zero(T) ? zero(T) : -T(Inf),
            ProposalAcceptanceReady,
        )
    end
    log_ratio = -(delta_h + drive_energy) / temperature +
                drive_log_bias + kinetic_modifier
    isfinite(log_ratio) || return (-T(Inf), ProposalAcceptanceNonfinite)
    return (log_ratio, ProposalAcceptanceReady)
end

@inline function _validate_acceptance_temperature(
        ::Type{T}, temperature::Real
    ) where {T <: AbstractFloat}
    converted = T(temperature)
    isfinite(converted) && converted >= zero(T) || throw(ArgumentError(
        "acceptance temperature must be finite and nonnegative"
    ))
    return converted
end

@inline function _throw_invalid_acceptance(result::ProposalAcceptanceResult)
    result.code === ProposalAcceptanceNonfinite && throw(ArgumentError(
        "proposal acceptance inputs and resulting log ratio must be finite"
    ))
    result.code === ProposalAcceptanceZeroTemperatureDrive && throw(ArgumentError(
        "nonconservative drives and proposal modifiers require positive temperature"
    ))
    return result
end

@inline function proposal_log_acceptance_ratio(
        evaluation::ProposalEvaluation{T}, temperature::Real
    ) where {T <: AbstractFloat}
    converted_temperature = _validate_acceptance_temperature(T, temperature)
    result = _proposal_acceptance_result(evaluation, converted_temperature)
    _throw_invalid_acceptance(result)
    return result.log_ratio
end

"""Exact conventional acceptance probability for a structured proposal evaluation."""
@inline function proposal_acceptance_probability(
        evaluation::ProposalEvaluation{T}, temperature::Real
    ) where {T <: AbstractFloat}
    log_ratio = proposal_log_acceptance_ratio(evaluation, temperature)
    return log_ratio >= zero(T) ? one(T) :
           isfinite(log_ratio) ? exp(log_ratio) : zero(T)
end

"""Apply the strict-threshold decision to one pre-addressed uniform draw."""
@inline function proposal_acceptance_decision(
        evaluation::ProposalEvaluation{T}, temperature::Real, draw::Real
    ) where {T <: AbstractFloat}
    converted_draw = T(draw)
    zero(T) < converted_draw < one(T) || throw(ArgumentError(
        "acceptance draws must lie strictly inside (0, 1)"
    ))
    log_ratio = proposal_log_acceptance_ratio(evaluation, temperature)
    return log_ratio >= zero(T) ||
           (isfinite(log_ratio) && log(converted_draw) < log_ratio)
end

@inline function _acceptance_plan_has_nonconservative_terms(plan)
    for group in plan.groups
        for descriptor in group.launch.instances
            role = getfield(descriptor, :role)
            (role isa ProposalDriveRole || role isa ProposalModifierRole) &&
                return true
        end
    end
    return false
end

"""Validate all host-known proposal parameters before runtime allocation or publication."""
function _validated_program_parameters(program, parameters)
    T = eltype(program.parameter_defaults)
    length(parameters) == length(program.parameter_defaults) || throw(
        ArgumentError("runtime parameter buffer has the wrong length")
    )
    converted = T.(parameters)
    all(isfinite, converted) || throw(ArgumentError(
        "runtime parameters must be finite"
    ))
    validate_parameters(program.descriptor_plan, converted)
    temperature = compiled_scalar_value(program.temperature, converted)
    _validate_acceptance_temperature(T, temperature)
    if iszero(temperature) &&
            _acceptance_plan_has_nonconservative_terms(program.descriptor_plan)
        throw(ArgumentError(
            "zero-temperature programs cannot contain proposal log-bias or " *
            "kinetic-modifier descriptors"
        ))
    end
    return converted
end

@inline function _acceptance_failure_status(
        code::ProposalAcceptanceCode,
        next_mcs::Integer,
        proposal_identity::Integer,
    )
    detail = code === ProposalAcceptanceNonfinite ?
             LifecycleDetailAcceptanceNonfinite :
             LifecycleDetailAcceptanceZeroTemperatureDrive
    return ProgramStatus(
        ProgramStatusAcceptance,
        Int32(next_mcs),
        ProgramStageAcceptance,
        Int32(0),
        UInt64(0),
        Int32(0),
        Int32(proposal_identity),
        detail,
        Int32(0),
        Int32(0),
        Int32(0),
    )
end

@inline _acceptance_failure_status(
    result::ProposalAcceptanceResult,
    next_mcs::Integer,
    proposal_identity::Integer,
) = _acceptance_failure_status(result.code, next_mcs, proposal_identity)
