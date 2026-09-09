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

struct PottsStateSetter{I <: Tuple, N}
    indices::I
    names::N
    single::Bool
end

function _state_setter_selection(symbols)
    if symbols isa NamedTuple
        return Tuple(values(symbols)), keys(symbols), false
    elseif symbols isa Tuple || (
            symbols isa AbstractArray &&
                SymbolicIndexingInterface.symbolic_type(symbols) isa SymbolicIndexingInterface.NotSymbolic
        )
        return Tuple(symbols), nothing, false
    end
    return (symbols,), nothing, true
end

function _state_setter_index(system, symbol)
    entries = _scheduled_state_entries(system)
    if symbol isa Integer
        symbol isa Bool && throw(ArgumentError("a state index cannot be Bool"))
        1 <= symbol <= length(entries) || throw(BoundsError(entries, symbol))
        return Int(symbol)
    end
    index = SymbolicIndexingInterface.variable_index(system, symbol)
    index === nothing && return nothing
    # A field/index expression must not inherit write permission merely
    # because its display name resolves to the containing state.
    symbol isa Symbol || isequal(symbol, entries[index].variable) ||
        throw(ArgumentError("state mutation requires a whole canonical state, not a projected expression"))
    return index
end

function SymbolicIndexingInterface.setu(
        provider::Union{PottsSystem, PottsProblem, PottsIntegrator}, symbols
    )
    system = SymbolicIndexingInterface.symbolic_container(provider)
    is_scheduled(system) || throw(ArgumentError("state setters require a scheduled Potts system"))
    requested, names, single = _state_setter_selection(symbols)
    indices = map(symbol -> _state_setter_index(system, symbol), requested)
    if !isempty(requested) && all(isnothing, indices) &&
            all(symbol -> SymbolicIndexingInterface.is_parameter(system, symbol), requested)
        return invoke(SymbolicIndexingInterface.setu, Tuple{Any, Any}, provider, symbols)
    end
    all(index -> index !== nothing, indices) || throw(
        ArgumentError(
            "state transactions accept only canonical stored states; observations, ownership, derived expressions, and mixed state/parameter targets are unsupported"
        )
    )
    length(unique(indices)) == length(indices) ||
        throw(ArgumentError("a state transaction cannot contain duplicate identities"))
    return PottsStateSetter(indices, names, single)
end

function _state_setter_replacements(setter::PottsStateSetter, replacements)
    setter.single && return setter.indices, (replacements,)
    if setter.names !== nothing
        replacements isa NamedTuple || throw(ArgumentError("named state targets require named replacement values"))
        positions = map(keys(replacements)) do name
            index = findfirst(isequal(name), setter.names)
            index === nothing && throw(ArgumentError("unknown state replacement label `$name`"))
            index
        end
        return map(index -> setter.indices[index], positions), Tuple(values(replacements))
    end
    replacements isa Union{Tuple, AbstractArray} ||
        throw(ArgumentError("multiple state targets require a tuple or array of replacement values"))
    selected_values = Tuple(replacements)
    length(selected_values) == length(setter.indices) || throw(
        ArgumentError(
            "state transaction value count does not match its symbolic identities"
        )
    )
    return setter.indices, selected_values
end

function (setter::PottsStateSetter)(integrator::PottsIntegrator, replacements)
    _request_integrator_settlement!(integrator, CorePotts.BackendSPI.IndexMutationSettlement)
    if CorePotts.program_failed(integrator.runtime) || integrator.failure_report !== nothing
        throw(ArgumentError("state mutation cannot repair a terminal-failed integrator"))
    end
    indices, values = _state_setter_replacements(setter, replacements)
    isempty(indices) && return nothing
    SPI = CorePotts.CompilerSPI
    program = integrator.plan.core_program
    layout = program.descriptor_plan.state_layout
    before = CorePotts.BackendSPI.program_snapshot_descriptor_state(CorePotts.program_snapshot(integrator.runtime))
    candidate = SPI.copy_auxiliary_state(before)
    for (index, value) in zip(indices, values)
        entry = integrator.plan.state_manifest[index]
        layout_entry = only(item for item in layout.entries if item.handle == entry.handle)
        source = entry.storage === :history ? SPI.history_source(program.stage_plan, layout, entry.handle) : layout_entry
        capacity = source.schema.domain === :cell ? only(source.schema.shape) : 0
        # Runtime slot identities may contain holes. Unlike fresh initial
        # values, mutation always supplies the complete canonical slot buffer.
        normalized = _normalize_initial_state_entry(
            entry, Dict(entry.name => value), program.shape, capacity, capacity,
            integrator.scalar_type, entry.storage === :history ? source : nothing,
        )
        copyto!(SPI.state_block(candidate, entry.handle).values, _descriptor_state_value(layout_entry, normalized))
    end
    previous_u = integrator.u
    SPI.update_program_descriptor_state!(integrator.runtime, candidate)
    try
        integrator.u = _current_saved_state(integrator)
    catch
        # Ordinary host observation errors restore through the same state
        # publisher. Backend copy/execution failures are not a rollback claim.
        CorePotts.program_failed(integrator.runtime) && rethrow()
        SPI.update_program_descriptor_state!(integrator.runtime, before)
        integrator.u = previous_u
        rethrow()
    end
    return nothing
end

function SymbolicIndexingInterface.set_state!(integrator::PottsIntegrator, value, index::Integer)
    setter = SymbolicIndexingInterface.setu(integrator, index)
    return setter(integrator, value)
end

function SymbolicIndexingInterface.set_state!(::Union{PottsProblem, PottsSolution}, value, index)
    throw(ArgumentError("saved and problem state is immutable; mutate a PottsIntegrator or remake the problem"))
end

function _state_values_for(
        plan::_PottsExecutionPlan,
        saved::PottsSavedState;
        require_observations::Bool = true,
    )
    states = Tuple(saved[entry.name] for entry in plan.state_manifest)
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
SymbolicIndexingInterface.state_values(problem::PottsProblem, ::Colon) =
    SymbolicIndexingInterface.state_values(problem)

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
SymbolicIndexingInterface.state_values(
    integrator::PottsIntegrator, ::Colon
) = SymbolicIndexingInterface.state_values(integrator)

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
SymbolicIndexingInterface.state_values(solution::PottsSolution, ::Colon) =
    SymbolicIndexingInterface.state_values(solution)
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
SymbolicIndexingInterface.current_time(solution::PottsSolution, ::Colon) =
    SymbolicIndexingInterface.current_time(solution)
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
