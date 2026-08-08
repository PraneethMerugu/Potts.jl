_scheduled_parameter_entries(system::PottsSystem) =
    _scheduled_data(system).parameters.runtime
_scheduled_state_entries(system::PottsSystem) = _scheduled_data(system).states
_scheduled_observation_entries(system::PottsSystem) =
    _scheduled_data(system).observations

function _symbolic_identity_name(value)
    value isa Symbol && return value
    return _try_symbolic_name(value)
end

function _entry_matches(entry, symbol, fields)
    any(field -> haskey(entry, field) && isequal(getproperty(entry, field), symbol), fields) &&
        return true
    requested = _symbolic_identity_name(symbol)
    requested === nothing && return false
    return any(fields) do field
        haskey(entry, field) || return false
        candidate = getproperty(entry, field)
        candidate_name = _symbolic_identity_name(candidate)
        candidate_name === requested
    end
end

SymbolicIndexingInterface.symbolic_container(system::PottsSystem) = system
SymbolicIndexingInterface.symbolic_container(problem::PottsProblem) = problem.system
SymbolicIndexingInterface.symbolic_container(integrator::PottsIntegrator) =
    integrator.prob.system
SymbolicIndexingInterface.symbolic_container(solution::PottsSolution) =
    solution.prob.system

function SymbolicIndexingInterface.parameter_index(system::PottsSystem, symbol)
    is_scheduled(system) || return nothing
    return findfirst(
        entry -> _entry_matches(entry, symbol, (:symbolic, :name)),
        _scheduled_parameter_entries(system),
    )
end

SymbolicIndexingInterface.parameter_index(
    system::PottsSystem, symbol::Symbol
) = invoke(
    SymbolicIndexingInterface.parameter_index,
    Tuple{PottsSystem, Any},
    system,
    symbol,
)

SymbolicIndexingInterface.is_parameter(
    system::PottsSystem, symbol::Symbol
) = SymbolicIndexingInterface.parameter_index(system, symbol) !== nothing

SymbolicIndexingInterface.is_parameter(
    system::PottsSystem, symbol::Int
) = is_scheduled(system) &&
    1 <= symbol <= length(_scheduled_parameter_entries(system))

function SymbolicIndexingInterface.parameter_symbols(system::PottsSystem)
    is_scheduled(system) || return Any[]
    return Any[entry.symbolic for entry in _scheduled_parameter_entries(system)]
end

function SymbolicIndexingInterface.is_variable(system::PottsSystem, symbol)
    return SymbolicIndexingInterface.variable_index(system, symbol) !== nothing
end

SymbolicIndexingInterface.is_variable(
    system::PottsSystem, symbol::Symbol
) = SymbolicIndexingInterface.variable_index(system, symbol) !== nothing

function SymbolicIndexingInterface.variable_index(system::PottsSystem, symbol)
    is_scheduled(system) || return nothing
    return findfirst(
        entry -> _entry_matches(entry, symbol, (:variable, :key, :name)),
        _scheduled_state_entries(system),
    )
end

SymbolicIndexingInterface.variable_index(
    system::PottsSystem, symbol::Symbol
) = invoke(
    SymbolicIndexingInterface.variable_index,
    Tuple{PottsSystem, Any},
    system,
    symbol,
)

function SymbolicIndexingInterface.variable_symbols(system::PottsSystem)
    is_scheduled(system) || return Any[]
    return Any[entry.variable for entry in _scheduled_state_entries(system)]
end

function SymbolicIndexingInterface.is_observed(system::PottsSystem, symbol)
    is_scheduled(system) || return false
    return any(
        entry -> _entry_matches(entry, symbol, (:name, :expression)),
        _scheduled_observation_entries(system),
    )
end

function _observation_index(system::PottsSystem, symbol)
    return findfirst(
        entry -> _entry_matches(entry, symbol, (:name, :expression)),
        _scheduled_observation_entries(system),
    )
end

function SymbolicIndexingInterface.observed(system::PottsSystem, symbol)
    index = _observation_index(system, symbol)
    index === nothing && throw(ArgumentError(
        "unknown scheduled observation $(repr(symbol))"
    ))
    state_count = length(_scheduled_state_entries(system))
    return (u, _, _) -> u[state_count + index]
end

function SymbolicIndexingInterface.all_variable_symbols(system::PottsSystem)
    is_scheduled(system) || return Any[]
    return Any[
        SymbolicIndexingInterface.variable_symbols(system)...,
        (entry.name for entry in _scheduled_observation_entries(system))...,
    ]
end

function SymbolicIndexingInterface.all_symbols(system::PottsSystem)
    return Any[
        SymbolicIndexingInterface.all_variable_symbols(system)...,
        SymbolicIndexingInterface.parameter_symbols(system)...,
        SymbolicIndexingInterface.independent_variable_symbols(system)...,
    ]
end

SymbolicIndexingInterface.constant_structure(::PottsSystem) = true
SymbolicIndexingInterface.is_time_dependent(::PottsSystem) = true
SymbolicIndexingInterface.is_markovian(::PottsSystem) = true
function SymbolicIndexingInterface.get_all_timeseries_indexes(
        system::PottsSystem, symbol
    )
    if SymbolicIndexingInterface.is_variable(system, symbol) ||
            SymbolicIndexingInterface.is_observed(system, symbol) ||
            SymbolicIndexingInterface.is_independent_variable(system, symbol)
        return Set([SymbolicIndexingInterface.ContinuousTimeseries()])
    end
    return Set()
end
SymbolicIndexingInterface.independent_variable_symbols(::PottsSystem) = Any[:mcs]
SymbolicIndexingInterface.is_independent_variable(::PottsSystem, value) =
    value === :mcs
SymbolicIndexingInterface.is_independent_variable(
    ::PottsSystem, value::Symbol
) = value === :mcs

function SymbolicIndexingInterface.default_values(system::PottsSystem)
    is_scheduled(system) || return Dict{Any, Any}()
    result = Dict{Any, Any}()
    for entry in _scheduled_parameter_entries(system)
        entry.required || (result[entry.symbolic] = _defensive_copy(entry.default))
    end
    for entry in _scheduled_state_entries(system)
        result[entry.variable] = _defensive_copy(entry.initial)
    end
    return result
end

SymbolicIndexingInterface.parameter_values(problem::PottsProblem) =
    problem.p.values
function SymbolicIndexingInterface.parameter_values(integrator::PottsIntegrator)
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.IndexReadSettlement
    )
    return integrator.runtime.parameters
end
function SymbolicIndexingInterface.parameter_values(solution::PottsSolution)
    isempty(solution.parameter_history) && return solution.prob.p.values
    return last(solution.parameter_history).second
end
SymbolicIndexingInterface.parameter_values(solution::PottsSolution, index) =
    SymbolicIndexingInterface.parameter_values(solution)[index]

struct PottsParameterSetter{I <: Tuple}
    indices::I
end

function _parameter_setter_indices(system::PottsSystem, symbols)
    requested = symbols isa Tuple || symbols isa AbstractArray ?
                Tuple(symbols) : (symbols,)
    indices = Int[]
    for symbol in requested
        index = SymbolicIndexingInterface.parameter_index(system, symbol)
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
        _parameter_setter_indices(integrator.prob.system, symbols)
    )
end

function (setter::PottsParameterSetter)(integrator::PottsIntegrator, values)
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.IndexMutationSettlement
    )
    replacements = length(setter.indices) == 1 &&
                   !(values isa Tuple || values isa AbstractArray) ?
                   (values,) : Tuple(values)
    length(replacements) == length(setter.indices) || throw(ArgumentError(
        "parameter transaction value count does not match its symbolic identities"
    ))
    T = eltype(integrator.runtime.parameters)
    staged = copy(integrator.runtime.parameters)
    for (index, value) in zip(setter.indices, replacements)
        staged[index] = _convert_parameter_value(
            integrator.plan.parameter_manifest[index], value, T
        )
    end
    CorePotts.update_program_parameters!(integrator.runtime, staged)
    names = Tuple(entry.name for entry in integrator.plan.parameter_manifest)
    parameters = PottsParameters(staged, NamedTuple{names}(Tuple(staged)))
    push!(integrator.parameter_history, integrator.t => parameters)
    integrator.pending_parameters = nothing
    integrator.u = _current_saved_state(integrator)
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
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.IndexMutationSettlement
    )
    1 <= index <= length(integrator.plan.parameter_manifest) ||
        throw(BoundsError(integrator.runtime.parameters, index))
    staged = integrator.pending_parameters === nothing ?
             copy(integrator.runtime.parameters) : integrator.pending_parameters
    staged[index] = _convert_parameter_value(
        integrator.plan.parameter_manifest[index],
        value,
        eltype(integrator.runtime.parameters),
    )
    integrator.pending_parameters = staged
    return nothing
end

function SymbolicIndexingInterface.finalize_parameters_hook!(
        integrator::PottsIntegrator, symbols
    )
    staged = integrator.pending_parameters
    staged === nothing && return nothing
    CorePotts.update_program_parameters!(integrator.runtime, staged)
    names = Tuple(entry.name for entry in integrator.plan.parameter_manifest)
    parameters = PottsParameters(staged, NamedTuple{names}(Tuple(staged)))
    push!(integrator.parameter_history, integrator.t => parameters)
    integrator.pending_parameters = nothing
    integrator.u = _current_saved_state(integrator)
    return nothing
end

function _state_values_for(
        plan::_PottsExecutionPlan,
        saved::PottsSavedState;
        require_observations::Bool = true,
    )
    states = Tuple(saved[entry.name] for entry in plan.reports.states)
    observations = Tuple(
        require_observations ? saved[entry.name] :
        get(saved.observations, entry.name, missing)
        for entry in plan.observations
    )
    return (states..., observations...)
end

function _problem_state_values(problem::PottsProblem)
    supplied = Dict{Symbol, Any}()
    for (key, value) in _problem_initial_state(problem).values
        supplied[_state_name(key)] = value
    end
    states = Tuple(
        _defensive_copy(get(
            supplied,
            entry.name,
            get(supplied, entry.key, entry.initial),
        ))
        for entry in _scheduled_state_entries(problem.system)
    )
    observations = ntuple(
        _ -> missing,
        length(_scheduled_observation_entries(problem.system)),
    )
    return (states..., observations...)
end

SymbolicIndexingInterface.state_values(problem::PottsProblem) =
    _problem_state_values(problem)
SymbolicIndexingInterface.state_values(problem::PottsProblem, index) =
    _problem_state_values(problem)[index]

function SymbolicIndexingInterface.state_values(integrator::PottsIntegrator)
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.IndexReadSettlement
    )
    all_names = Tuple(entry.name for entry in integrator.plan.observations)
    current = _saved_state(
        integrator.plan,
        CorePotts.program_snapshot(integrator.runtime),
        _named_runtime_observations(
            integrator.runtime, integrator.plan, all_names
        ),
        all_names,
    )
    return _state_values_for(integrator.plan, current)
end
SymbolicIndexingInterface.state_values(
    integrator::PottsIntegrator, index
) = SymbolicIndexingInterface.state_values(integrator)[index]

function _scheduled_saved_values(system::PottsSystem, saved::PottsSavedState)
    states = Tuple(
        saved[entry.name] for entry in _scheduled_state_entries(system)
    )
    observations = Tuple(
        saved[entry.name] for entry in _scheduled_observation_entries(system)
    )
    return (states..., observations...)
end

SymbolicIndexingInterface.state_values(solution::PottsSolution) =
    [_scheduled_saved_values(solution.prob.system, saved) for saved in solution.u]
function SymbolicIndexingInterface.state_values(
        solution::PottsSolution, index
    )
    saved = solution.u[index]
    # Saved-state ordering is the scheduled ordering and does not require
    # rematerializing runtime state.
    return _scheduled_saved_values(solution.prob.system, saved)
end

SymbolicIndexingInterface.current_time(integrator::PottsIntegrator) = begin
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.IndexReadSettlement
    )
    integrator.t
end
SymbolicIndexingInterface.current_time(problem::PottsProblem) = problem.tspan[1]
SymbolicIndexingInterface.current_time(solution::PottsSolution) = solution.t
SymbolicIndexingInterface.current_time(solution::PottsSolution, index) =
    solution.t[index]
SymbolicIndexingInterface.is_timeseries(::PottsSolution) =
    SymbolicIndexingInterface.Timeseries()

function SymbolicIndexingInterface.remake_buffer(
        system::PottsSystem,
        old::PottsParameters,
        indices,
        values,
    )
    replacements = Dict{Symbol, Any}(
        name => getproperty(old.named, name) for name in keys(old.named)
    )
    for (identity, value) in zip(indices, values)
        index = identity isa Integer ? Int(identity) :
                SymbolicIndexingInterface.parameter_index(system, identity)
        index === nothing && throw(ArgumentError(
            "unknown runtime parameter $(repr(identity))"
        ))
        entries = _scheduled_parameter_entries(system)
        1 <= index <= length(entries) || throw(BoundsError(entries, index))
        replacements[entries[index].name] = value
    end
    return _normalize_problem_parameters(system, replacements)
end
