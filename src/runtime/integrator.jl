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
    declared = Set{Symbol}((:ownership, :cell_kinds, :volumes, :activity, :field))
    union!(declared, Symbol(statement_id(value)) for value in executable.observations)
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

function _runtime_observations(runtime, requested)
    values = Dict{Symbol, Any}()
    for name in requested
        name in (:ownership, :cell_kinds, :volumes, :activity, :field) && continue
        # Derived observation lowering is intentionally closed. Built-in observations
        # are added as concrete kernels by the compiler; none are currently implicit.
        values[name] = missing
    end
    return NamedTuple{Tuple(keys(values))}(Tuple(values[key] for key in keys(values)))
end

function _current_saved_state(integrator::PottsIntegrator)
    snapshot = CorePotts.program_snapshot(integrator.runtime)
    observations = _runtime_observations(
        integrator.runtime, integrator.policy.observables
    )
    return _saved_state(snapshot, observations)
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
    core_initial = _core_initial_state(problem.executable, problem.initial)
    runtime = CorePotts.initialize_program(
        problem.executable.core_program,
        core_initial,
        problem.parameters.values,
        problem.seed,
        problem.replica;
        initial_mcs = problem.tspan[1],
    )
    initial_snapshot = CorePotts.program_snapshot(runtime)
    initial_state = _saved_state(initial_snapshot, NamedTuple())
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
    return PottsStats(
        integrator.iterations,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
    )
end

function _set_runtime_parameters!(integrator::PottsIntegrator, values)
    integrator.runtime.settled ||
        throw(ArgumentError("parameter updates require a settled MCS boundary"))
    parameters = _normalize_parameters(integrator.prob.executable, values)
    CorePotts.update_program_parameters!(
        integrator.runtime, parameters.values
    )
    push!(integrator.parameter_history, integrator.t => parameters)
    return parameters
end
