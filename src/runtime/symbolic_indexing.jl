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
    Any[entry.variable for entry in executable.parameter_manifest]

function SymbolicIndexingInterface.is_variable(
        executable::PottsExecutable, symbol
    )
    return any(entry -> isequal(entry.variable, symbol),
        _symbolic_state_manifest(executable))
end

function SymbolicIndexingInterface.variable_index(
        executable::PottsExecutable, symbol
    )
    return findfirst(entry -> isequal(entry.variable, symbol),
        _symbolic_state_manifest(executable))
end

SymbolicIndexingInterface.variable_symbols(executable::PottsExecutable) =
    Any[entry.variable for entry in _symbolic_state_manifest(executable)]
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
    problem.parameters.values
SymbolicIndexingInterface.parameter_values(integrator::PottsIntegrator) =
    integrator.runtime.parameters
SymbolicIndexingInterface.parameter_values(solution::PottsSolution) =
    solution.prob.parameters.values

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
    converted = if entry.unit === nothing
        _is_quantity(value) &&
            throw(ArgumentError("parameter `$(entry.name)` is dimensionless"))
        T(_numeric_value(value))
    else
        _is_quantity(value) || throw(ArgumentError(
            "parameter `$(entry.name)` requires units compatible with $(entry.unit)"
        ))
        T(_numeric_value(value, entry.unit))
    end
    isfinite(converted) ||
        throw(ArgumentError("parameter `$(entry.name)` must be finite"))
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

function _state_value(saved::PottsSavedState, name::Symbol)
    return saved[name]
end

function _state_values_for(executable::PottsExecutable, saved::PottsSavedState)
    return Tuple(_state_value(saved, entry.name)
        for entry in _symbolic_state_manifest(executable))
end

SymbolicIndexingInterface.state_values(integrator::PottsIntegrator) =
    _state_values_for(integrator.prob.executable, integrator.u)
SymbolicIndexingInterface.state_values(solution::PottsSolution) =
    [_state_values_for(solution.prob.executable, saved) for saved in solution.u]
SymbolicIndexingInterface.current_time(integrator::PottsIntegrator) =
    integrator.t
SymbolicIndexingInterface.current_time(solution::PottsSolution) =
    solution.t
SymbolicIndexingInterface.is_timeseries(::PottsSolution) =
    SymbolicIndexingInterface.Timeseries()

