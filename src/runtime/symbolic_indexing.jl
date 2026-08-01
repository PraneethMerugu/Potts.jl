function _symbolic_state_manifest(executable::PottsExecutable)
    return executable.reports.states
end

SymbolicIndexingInterface.symbolic_container(executable::PottsExecutable) =
    executable
SymbolicIndexingInterface.symbolic_container(problem::PottsProblem) =
    problem.executable
SymbolicIndexingInterface.symbolic_container(integrator::PottsIntegrator) =
    integrator.prob.executable
SymbolicIndexingInterface.symbolic_container(solution::PottsSolution) =
    solution.prob.executable

function SymbolicIndexingInterface.is_parameter(
        executable::PottsExecutable, symbol
    )
    return _parameter_index(executable.parameter_manifest, symbol) !== nothing
end

function SymbolicIndexingInterface.parameter_index(
        executable::PottsExecutable, symbol
    )
    return _parameter_index(executable.parameter_manifest, symbol)
end

SymbolicIndexingInterface.parameter_symbols(executable::PottsExecutable) =
    Symbol[entry.name for entry in executable.parameter_manifest]

function SymbolicIndexingInterface.is_variable(
        executable::PottsExecutable, symbol
    )
    key = _try_symbolic_name(symbol)
    key === nothing && return false
    return any(entry -> entry.key === key,
               _symbolic_state_manifest(executable)) ||
           any(entry -> entry.name === key, executable.observations)
end

function SymbolicIndexingInterface.variable_index(
        executable::PottsExecutable, symbol
    )
    key = _try_symbolic_name(symbol)
    key === nothing && return nothing
    states = _symbolic_state_manifest(executable)
    state_index = findfirst(entry -> entry.key === key, states)
    state_index === nothing || return state_index
    observation_index = findfirst(
        entry -> entry.name === key, executable.observations
    )
    observation_index === nothing && return nothing
    return length(states) + observation_index
end

SymbolicIndexingInterface.variable_symbols(executable::PottsExecutable) =
    Symbol[
        (entry.key for entry in _symbolic_state_manifest(executable))...,
        (entry.name for entry in executable.observations)...,
    ]
SymbolicIndexingInterface.all_variable_symbols(executable::PottsExecutable) =
    SymbolicIndexingInterface.variable_symbols(executable)
SymbolicIndexingInterface.all_symbols(executable::PottsExecutable) =
    Any[
        SymbolicIndexingInterface.variable_symbols(executable)...,
        SymbolicIndexingInterface.parameter_symbols(executable)...,
    ]
SymbolicIndexingInterface.constant_structure(::PottsExecutable) = true
SymbolicIndexingInterface.is_time_dependent(::PottsExecutable) = true
SymbolicIndexingInterface.is_markovian(::PottsExecutable) = true

SymbolicIndexingInterface.parameter_values(problem::PottsProblem) =
    _parameter_buffer(problem.parameters)
SymbolicIndexingInterface.parameter_values(integrator::PottsIntegrator) =
    integrator.runtime.parameters
SymbolicIndexingInterface.parameter_values(solution::PottsSolution) =
    isempty(solution.parameter_history) ?
    _parameter_buffer(solution.prob.parameters) :
    _parameter_buffer(
        last(solution.parameter_history).second,
        eltype(solution.prob.executable.core_program.parameter_defaults),
    )

struct PottsParameterSetter{I <: Tuple}
    indices::I
end

function _parameter_setter_indices(executable::PottsExecutable, symbols)
    requested = if symbols isa Tuple || symbols isa AbstractArray
        Tuple(symbols)
    else
        (symbols,)
    end
    indices = Int[]
    for symbol in requested
        index = SymbolicIndexingInterface.parameter_index(executable, symbol)
        index === nothing && throw(ArgumentError(
            "unknown runtime parameter $(repr(symbol))"
        ))
        index in indices && throw(ArgumentError(
            "a parameter transaction cannot contain duplicate identities"
        ))
        push!(indices, index)
    end
    return Tuple(indices)
end

function SymbolicIndexingInterface.setp(
        integrator::PottsIntegrator, symbols
    )
    return PottsParameterSetter(
        _parameter_setter_indices(integrator.prob.executable, symbols)
    )
end

function (setter::PottsParameterSetter)(
        integrator::PottsIntegrator, values
    )
    integrator.runtime.settled ||
        throw(ArgumentError("parameter updates require a settled MCS boundary"))
    replacements = length(setter.indices) == 1 &&
                   !(values isa Tuple || values isa AbstractArray) ?
                   (values,) : Tuple(values)
    length(replacements) == length(setter.indices) || throw(ArgumentError(
        "parameter transaction value count does not match its symbolic identities"
    ))
    T = eltype(integrator.runtime.parameters)
    staged = copy(integrator.runtime.parameters)
    for (index, value) in zip(setter.indices, replacements)
        entry = integrator.prob.executable.parameter_manifest[index]
        staged[index] = _convert_parameter_value(entry, value, T)
    end
    # One publication after every value has validated preserves atomicity.
    CorePotts.update_program_parameters!(integrator.runtime, staged)
    names = Tuple(
        entry.name for entry in integrator.prob.executable.parameter_manifest
    )
    parameters = PottsParameters(
        staged, NamedTuple{names}(Tuple(staged))
    )
    push!(integrator.parameter_history, integrator.t => parameters)
    return nothing
end

function SymbolicIndexingInterface.set_parameter!(
        ::PottsProblem, value, index
    )
    throw(ArgumentError(
        "PottsProblem parameters are immutable; use remake(problem; p=...)"
    ))
end

function SymbolicIndexingInterface.set_parameter!(
        integrator::PottsIntegrator, value, index
    )
    integrator.runtime.settled ||
        throw(ArgumentError("parameter updates require a settled MCS boundary"))
    1 <= index <= length(integrator.prob.executable.parameter_manifest) ||
        throw(BoundsError(integrator.runtime.parameters, index))
    entry = integrator.prob.executable.parameter_manifest[index]
    T = eltype(integrator.runtime.parameters)
    converted = _convert_parameter_value(entry, value, T)
    integrator.runtime.parameters[index] = converted
    return nothing
end

function SymbolicIndexingInterface.finalize_parameters_hook!(
        integrator::PottsIntegrator, symbols
    )
    CorePotts.update_program_parameters!(
        integrator.runtime, integrator.runtime.parameters
    )
    names = Tuple(entry.name for entry in integrator.prob.executable.parameter_manifest)
    parameters = PottsParameters(
        copy(integrator.runtime.parameters),
        NamedTuple{names}(Tuple(integrator.runtime.parameters)),
    )
    push!(integrator.parameter_history, integrator.t => parameters)
    return nothing
end

function _state_value(saved::PottsSavedState, entry)
    entry.role === :activity && return saved.activity
    entry.role === :field && return saved.field
    entry.role === :history && return saved.history
    return saved[entry.name]
end

function _state_values_for(executable::PottsExecutable, saved::PottsSavedState)
    return (
        (_state_value(saved, entry)
         for entry in _symbolic_state_manifest(executable))...,
        (saved[entry.name] for entry in executable.observations)...,
    )
end

function _problem_saved_state(problem::PottsProblem)
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
    available = CorePotts.program_observations(runtime)
    names = Tuple(entry.name for entry in problem.executable.observations)
    observations = NamedTuple{names}(Tuple(available))
    return _saved_state(
        CorePotts.program_snapshot(runtime), observations, names
    )
end

SymbolicIndexingInterface.state_values(problem::PottsProblem) =
    _state_values_for(problem.executable, _problem_saved_state(problem))
SymbolicIndexingInterface.state_values(integrator::PottsIntegrator) =
    _state_values_for(integrator.prob.executable, integrator.u)
SymbolicIndexingInterface.state_values(solution::PottsSolution) =
    [_state_values_for(solution.prob.executable, saved) for saved in solution.u]
SymbolicIndexingInterface.current_time(integrator::PottsIntegrator) =
    integrator.t
SymbolicIndexingInterface.current_time(problem::PottsProblem) =
    problem.tspan[1]
SymbolicIndexingInterface.current_time(solution::PottsSolution) =
    solution.t
SymbolicIndexingInterface.is_timeseries(::PottsSolution) =
    SymbolicIndexingInterface.Timeseries()

function SymbolicIndexingInterface.remake_buffer(
        executable::PottsExecutable,
        old::PottsParameters,
        indices,
        values,
    )
    staged = collect(old.values)
    T = eltype(executable.core_program.parameter_defaults)
    for (identity, value) in zip(indices, values)
        index = identity isa Integer ?
                Int(identity) :
                SymbolicIndexingInterface.parameter_index(executable, identity)
        index === nothing && throw(ArgumentError(
            "unknown runtime parameter $(repr(identity))"
        ))
        1 <= index <= length(executable.parameter_manifest) ||
            throw(BoundsError(staged, index))
        entry = executable.parameter_manifest[index]
        staged[index] = _convert_parameter_value(entry, value, T)
    end
    names = Tuple(entry.name for entry in executable.parameter_manifest)
    return PottsParameters(staged, NamedTuple{names}(Tuple(staged)))
end
