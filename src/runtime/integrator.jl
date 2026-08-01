struct PottsSavePolicy{T <: Tuple, O <: Tuple}
    saveat::T
    save_start::Bool
    save_end::Bool
    save_everystep::Bool
    observables::O
    maxiters::Int
    progress::Bool
    progress_steps::Int
    verbose::Bool
end

mutable struct PottsIntegrator{P, R, S}
    prob::P
    runtime::R
    t::Int
    u::S
    policy::PottsSavePolicy
    saved_times::Vector{Int}
    saved_states::Vector{S}
    parameter_history::Vector{Pair{Int, Any}}
    iterations::Int
    terminated::Bool
    retcode::SciMLBase.ReturnCode.T
end

function _normalize_saveat(saveat, tspan)
    saveat === nothing && return ()
    saveat isa Integer && begin
        saveat > 0 || throw(ArgumentError("saveat cadence must be positive"))
        return Tuple((tspan[1] + saveat):saveat:tspan[2])
    end
    all(value -> value isa Integer, saveat) ||
        throw(ArgumentError("saveat contains a noninteger MCS"))
    values = Tuple(Int(value) for value in saveat)
    all(value -> tspan[1] <= value <= tspan[2], values) ||
        throw(ArgumentError("saveat lies outside the problem time span"))
    length(unique(values)) == length(values) ||
        throw(ArgumentError("saveat boundaries must be unique"))
    return Tuple(sort(collect(values)))
end

function _normalize_observables(executable, observables)
    requested = Tuple(_state_name(value) for value in observables)
    declared = Set{Symbol}(
        (
            :ownership, :cell_kinds, :cell_generations, :volumes,
        )
    )
    union!(declared, entry.name for entry in executable.reports.states)
    union!(declared, entry.name for entry in executable.reports.relationship_states)
    union!(declared, value.name for value in executable.observations)
    unknown = setdiff(Set(requested), declared)
    isempty(unknown) ||
        throw(ArgumentError("unknown executable observation$(length(unknown) == 1 ? "" : "s"): " *
                            join(string.(sort!(collect(unknown))), ", ")))
    return requested
end

function _save_policy(
        problem::PottsProblem;
        saveat = (),
        save_start::Bool = true,
        save_end::Bool = true,
        save_everystep::Bool = false,
        observables = (),
        maxiters::Integer = problem.tspan[2] - problem.tspan[1],
        progress::Bool = false,
        progress_steps::Integer = 1,
        verbose::Bool = true,
        kwargs...,
    )
    isempty(kwargs) || throw(ArgumentError(
        "unsupported Potts solve control$(length(kwargs) == 1 ? "" : "s"): " *
        join(string.(keys(kwargs)), ", ")
    ))
    maxiters >= 0 || throw(ArgumentError("maxiters must be nonnegative"))
    progress_steps > 0 || throw(ArgumentError("progress_steps must be positive"))
    return PottsSavePolicy(
        _normalize_saveat(saveat, problem.tspan),
        save_start,
        save_end,
        save_everystep,
        _normalize_observables(problem.executable, observables),
        Int(maxiters),
        progress,
        Int(progress_steps),
        verbose,
    )
end

function _named_runtime_observations(runtime, executable, requested_names)
    requested = Set(requested_names)
    pairs = Pair{Symbol, Any}[]
    for entry in executable.observations
        entry.name in requested || continue
        value = _evaluate_observation(entry.evaluator, runtime)
        push!(pairs, entry.name => value)
    end
    names = Tuple(first(pair) for pair in pairs)
    return NamedTuple{names}(Tuple(last(pair) for pair in pairs))
end

function _current_saved_state(integrator::PottsIntegrator)
    snapshot = CorePotts.program_snapshot(integrator.runtime)
    observations = _named_runtime_observations(
        integrator.runtime,
        integrator.prob.executable,
        integrator.policy.observables,
    )
    return _saved_state(
        integrator.prob.executable,
        snapshot,
        observations,
        (entry.name for entry in integrator.prob.executable.observations),
    )
end

function _save_current!(integrator::PottsIntegrator)
    if !isempty(integrator.saved_times) &&
            last(integrator.saved_times) == integrator.t
        return integrator
    end
    state = _current_saved_state(integrator)
    push!(integrator.saved_times, integrator.t)
    push!(integrator.saved_states, state)
    integrator.u = state
    return integrator
end

function _save_due(integrator::PottsIntegrator)
    policy = integrator.policy
    integrator.t in policy.saveat && return true
    policy.save_everystep && return true
    policy.save_end && integrator.t == integrator.prob.tspan[2] && return true
    return false
end

function init(problem::PottsProblem; checkpoint = nothing, kwargs...)
    policy = _save_policy(problem; kwargs...)
    checkpoint === nothing ||
        return _init_from_checkpoint(problem, checkpoint, policy)
    core_initial = _core_initial_state(
        problem.executable, problem.initial, problem.seed, problem.replica
    )
    runtime = CorePotts.initialize_program(
        problem.executable.core_program,
        core_initial,
        _parameter_buffer(problem.parameters),
        problem.seed,
        problem.replica;
        repeat = problem.ensemble_repeat,
        initial_mcs = problem.tspan[1],
    )
    initial_snapshot = CorePotts.program_snapshot(runtime)
    initial_state = _saved_state(
        problem.executable,
        initial_snapshot,
        _named_runtime_observations(
            runtime, problem.executable, policy.observables
        ),
        (entry.name for entry in problem.executable.observations),
    )
    integrator = PottsIntegrator(
        problem,
        runtime,
        problem.tspan[1],
        initial_state,
        policy,
        Int[],
        typeof(initial_state)[],
        Pair{Int, Any}[problem.tspan[1] => problem.parameters],
        0,
        false,
        SciMLBase.ReturnCode.Default,
    )
    policy.save_start && _save_current!(integrator)
    return integrator
end

function step!(integrator::PottsIntegrator)
    integrator.terminated &&
        throw(ArgumentError("cannot step a terminated PottsIntegrator"))
    integrator.t < integrator.prob.tspan[2] ||
        throw(ArgumentError("cannot advance beyond the PottsProblem horizon"))
    integrator.iterations < integrator.policy.maxiters || begin
        integrator.retcode = SciMLBase.ReturnCode.MaxIters
        return integrator
    end
    CorePotts.advance_mcs!(integrator.runtime)
    integrator.t = integrator.runtime.mcs
    integrator.iterations += 1
    integrator.u = _current_saved_state(integrator)
    _save_due(integrator) && _save_current!(integrator)
    return integrator
end

function terminate!(integrator::PottsIntegrator)
    integrator.terminated = true
    integrator.retcode = SciMLBase.ReturnCode.Terminated
    return integrator
end

function _integrator_stats(integrator::PottsIntegrator)
    runtime = integrator.runtime
    candidate_attempts = runtime.accepted + runtime.null_attempts +
                         runtime.constraint_rejections +
                         runtime.energy_rejections
    return PottsStats(
        integrator.iterations,
        candidate_attempts,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
    )
end

runtime_statistics(integrator::PottsIntegrator) =
    _integrator_stats(integrator)

function _set_runtime_parameters!(integrator::PottsIntegrator, values)
    integrator.runtime.settled ||
        throw(ArgumentError("parameter updates require a settled MCS boundary"))
    parameters = _normalize_parameters(integrator.prob.executable, values)
    CorePotts.update_program_parameters!(
        integrator.runtime, _parameter_buffer(parameters)
    )
    push!(integrator.parameter_history, integrator.t => parameters)
    return parameters
end

function _external_input_pairs(values)
    values isa NamedTuple && return Pair[
        key => getproperty(values, key) for key in keys(values)
    ]
    values isa AbstractDict && return collect(pairs(values))
    values isa Tuple && all(value -> value isa Pair, values) &&
        return Pair[values...]
    values isa AbstractVector{<:Pair} && return collect(values)
    values isa Pair && return Pair[values]
    isempty(values) && return Pair[]
    throw(ArgumentError("external inputs must be pairs, a dictionary, or a named tuple"))
end

"""
    stage_external_inputs!(integrator, values)

Validate and atomically publish one frozen set of compiled external inputs at a
settled MCS boundary. This qualified hook exists for runtime adapters.
"""
function stage_external_inputs!(integrator::PottsIntegrator, values)
    integrator.runtime.settled ||
        throw(ArgumentError("external inputs require a settled MCS boundary"))
    manifest = inspect(integrator.prob.executable, ExternalIO())
    supplied = _external_input_pairs(values)
    isempty(supplied) && return integrator
    resolved = Pair{Any, Any}[]
    seen = Set{Symbol}()
    for (key, value) in supplied
        key_name = _state_name(key)
        index = findfirst(manifest) do entry
            entry.direction === :input &&
                (entry.identity === key_name || entry.endpoint === key_name)
        end
        index === nothing &&
            throw(ArgumentError("unknown compiled external input `$key_name`"))
        entry = manifest[index]
        entry.endpoint in seen &&
            throw(ArgumentError("duplicate compiled external input `$key_name`"))
        push!(seen, entry.endpoint)
        push!(resolved, entry => value)
    end

    T = eltype(integrator.runtime.parameters)
    parameters = copy(integrator.runtime.parameters)
    state_layout = integrator.prob.executable.core_program.descriptor_plan.state_layout
    descriptor_state = CorePotts.copy_auxiliary_state(
        state_layout, integrator.runtime.descriptor_state
    )
    parameter_changed = false
    state_changed = false
    for (entry, value) in resolved
        if entry.parameter_index !== nothing
            parameter = integrator.prob.executable.parameter_manifest[
                entry.parameter_index
            ]
            parameters[entry.parameter_index] =
                _convert_parameter_value(parameter, value, T)
            parameter_changed = true
        else
            state = integrator.prob.executable.reports.states[entry.state_index]
            converted = _normalize_initial_state_entry(
                state,
                Dict(state.name => value),
                integrator.prob.executable.core_program.shape,
                length(integrator.runtime.cell_kinds),
                T,
            )
            target = CorePotts.state_block(
                descriptor_state, state.handle
            ).values
            if state.storage === :history
                axis = ndims(target)
                length(converted) == size(target, axis) || error(
                    "normalized external history depth is incompatible"
                )
                for index in eachindex(converted)
                    copyto!(selectdim(target, axis, index), converted[index])
                end
            elseif converted isa AbstractArray
                size(converted) == size(target) || error(
                    "normalized external state shape is incompatible"
                )
                copyto!(target, converted)
            else
                fill!(target, converted)
            end
            state_changed = true
        end
    end

    parameter_changed &&
        CorePotts.update_program_parameters!(integrator.runtime, parameters)
    state_changed && (integrator.runtime.descriptor_state = descriptor_state)
    if parameter_changed
        names = Tuple(
            entry.name
            for entry in integrator.prob.executable.parameter_manifest
        )
        normalized = PottsParameters(
            copy(parameters), NamedTuple{names}(Tuple(parameters))
        )
        push!(integrator.parameter_history, integrator.t => normalized)
    end
    integrator.u = _current_saved_state(integrator)
    return integrator
end
