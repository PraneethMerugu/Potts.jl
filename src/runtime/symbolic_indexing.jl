_scheduled_parameter_entries(system::PottsSystem) =
    _scheduled_data(system).parameters.entries
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
    return _parameter_selection(_scheduled_data(system).parameters, symbol)
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
) = is_scheduled(system) ? SymbolicIndexingInterface.parameter_index(system, symbol) !== nothing :
    invoke(SymbolicIndexingInterface.is_parameter, Tuple{ModelingToolkitBase.AbstractSystem, Symbol}, system, symbol)

# ModelingToolkitBase's public indexing interface unwraps symbolic wrappers
# before redispatching here; the scheduled manifest owns their identities.
SymbolicIndexingInterface.is_parameter(
    system::PottsSystem, symbol::SymbolicUtils.BasicSymbolic
) = is_scheduled(system) ? SymbolicIndexingInterface.parameter_index(system, symbol) !== nothing :
    invoke(SymbolicIndexingInterface.is_parameter, Tuple{ModelingToolkitBase.AbstractSystem, typeof(symbol)}, system, symbol)

SymbolicIndexingInterface.is_parameter(
    system::PottsSystem, symbol::SymbolicUtils.BasicSymbolic{SymbolicUtils.SymReal}
) = invoke(SymbolicIndexingInterface.is_parameter, Tuple{PottsSystem, SymbolicUtils.BasicSymbolic}, system, symbol)

SymbolicIndexingInterface.is_parameter(
    system::PottsSystem, symbol::Int
) = is_scheduled(system) &&
    1 <= symbol <= length(_scheduled_parameter_entries(system))

function SymbolicIndexingInterface.parameter_symbols(system::PottsSystem)
    is_scheduled(system) || return invoke(
        SymbolicIndexingInterface.parameter_symbols, Tuple{ModelingToolkitBase.AbstractSystem}, system
    )
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
    return _parameter_values(integrator.plan.parameter_manifest, integrator.runtime.parameters)
end
function SymbolicIndexingInterface.parameter_values(solution::PottsSolution)
    isempty(solution.parameter_history) && return solution.prob.p.values
    return last(solution.parameter_history).second
end
SymbolicIndexingInterface.parameter_values(solution::PottsSolution, index) =
    SymbolicIndexingInterface.parameter_values(solution)[index]

SymbolicIndexingInterface.parameter_values(solution::PottsSolution, index::ParameterComponentIndex) =
    SymbolicIndexingInterface.parameter_values(solution)[index.parameter][index.component]

function SymbolicIndexingInterface.parameter_values(
        provider::Union{PottsProblem, PottsIntegrator}, index::ParameterComponentIndex,
    )
    values = SymbolicIndexingInterface.parameter_values(provider)
    return values[index.parameter][index.component]
end

SymbolicIndexingInterface.parameter_values(integrator::PottsIntegrator, index::Integer) =
    SymbolicIndexingInterface.parameter_values(integrator)[index]

struct PottsSymbolicSetter{I <: Tuple, N}
    targets::I
    names::N
    single::Bool
    publish::Bool
end

function (::PottsSymbolicSetter)(::Union{PottsSystem, PottsProblem, PottsSolution}, replacements)
    throw(ArgumentError("symbolic mutation requires a PottsIntegrator; use remake to update an immutable problem"))
end

function _require_symbolic_mutation_boundary!(integrator::PottsIntegrator)
    _request_integrator_settlement!(integrator, CorePotts.BackendSPI.IndexMutationSettlement)
    if CorePotts.program_failed(integrator.runtime) || integrator.failure_report !== nothing
        throw(ArgumentError("symbolic mutation cannot repair a terminal-failed integrator"))
    end
    return nothing
end

function _commit_symbolic_update!(
        integrator::PottsIntegrator;
        parameters = nothing,
        descriptor_state = nothing,
        descriptor_before = nothing,
    )
    parameters === nothing && descriptor_state === nothing && return nothing
    previous_parameters = parameters === nothing ? nothing : copy(integrator.runtime.parameters)
    previous_pending = integrator.pending_parameters
    previous_u = integrator.u
    history_length = length(integrator.parameter_history)

    # Core owns full acceptance and storage validation. No callback or other
    # scientific observer runs between these settled-boundary publications.
    parameters === nothing || CorePotts.update_program_parameters!(integrator.runtime, parameters)
    if descriptor_state !== nothing
        try
            CorePotts.CompilerSPI.update_program_descriptor_state!(integrator.runtime, descriptor_state)
        catch error
            if parameters !== nothing && !CorePotts.program_failed(integrator.runtime)
                try
                    CorePotts.update_program_parameters!(integrator.runtime, previous_parameters)
                catch restore_error
                    throw(CompositeException(Any[error, restore_error]))
                end
            end
            rethrow()
        end
    end
    try
        if parameters !== nothing
            saved_parameters = _saved_parameters(integrator.plan.parameter_manifest, parameters)
            push!(integrator.parameter_history, integrator.t => saved_parameters)
            integrator.pending_parameters = nothing
        end
        integrator.u = _current_saved_state(integrator)
    catch error
        # Ordinary host refresh failure restores the complete logical update.
        # Backend copy/execution or terminal-runtime failures are not a general
        # rollback guarantee; preserve both errors if restoration itself fails.
        CorePotts.program_failed(integrator.runtime) && rethrow()
        try
            parameters === nothing || CorePotts.update_program_parameters!(integrator.runtime, previous_parameters)
            descriptor_state === nothing || CorePotts.CompilerSPI.update_program_descriptor_state!(integrator.runtime, descriptor_before)
        catch restore_error
            throw(CompositeException(Any[error, restore_error]))
        end
        resize!(integrator.parameter_history, history_length)
        integrator.pending_parameters = previous_pending
        integrator.u = previous_u
        rethrow()
    end
    return nothing
end

function SymbolicIndexingInterface.set_parameter!(
        ::PottsProblem, value, index
    )
    throw(
        ArgumentError(
            "PottsProblem parameters are immutable; use remake(problem; p=...)"
        )
    )
end

function SymbolicIndexingInterface.set_parameter!(
        integrator::PottsIntegrator, value, index
    )
    _require_symbolic_mutation_boundary!(integrator)
    index isa Union{Integer, ParameterComponentIndex} && !(index isa Bool) || throw(ArgumentError("a parameter index must identify a logical parameter or component"))
    selected = _parameter_selection(integrator.plan.parameter_manifest, index)
    staged = integrator.pending_parameters === nothing ?
        copy(integrator.runtime.parameters) : copy(integrator.pending_parameters)
    _write_parameter_value!(staged, integrator.plan.parameter_manifest, selected, value)
    integrator.pending_parameters = staged
    return nothing
end

function SymbolicIndexingInterface.finalize_parameters_hook!(
        integrator::PottsIntegrator, symbols
    )
    _require_symbolic_mutation_boundary!(integrator)
    staged = integrator.pending_parameters
    staged === nothing && return nothing
    return _commit_symbolic_update!(integrator; parameters = staged)
end

function _symbolic_setter_selection(symbols)
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

function _parameter_setter_index(system, symbol)
    symbol isa Bool && throw(ArgumentError("a parameter index cannot be Bool"))
    return _parameter_selection(_scheduled_data(system).parameters, symbol)
end

function _symbolic_setter(provider, symbols; parameters_only, publish)
    system = SymbolicIndexingInterface.symbolic_container(provider)
    is_scheduled(system) || throw(ArgumentError("symbolic setters require a scheduled Potts system"))
    requested, names, single = _symbolic_setter_selection(symbols)
    targets = map(requested) do symbol
        if !parameters_only
            index = _state_setter_index(system, symbol)
            index === nothing || return :state => index
        end
        index = _parameter_setter_index(system, symbol)
        index === nothing && throw(
            ArgumentError(
                "symbolic mutation requires canonical stored states or parameters; unsupported target $(repr(symbol))"
            )
        )
        return :parameter => index
    end
    length(unique(targets)) == length(targets) ||
        throw(ArgumentError("a symbolic transaction cannot contain duplicate identities"))
    selected_slots = Set{Int}()
    for target in targets
        first(target) === :parameter || continue
        slots = _parameter_slots(_scheduled_data(system).parameters, last(target))
        any(in(selected_slots), slots) && throw(ArgumentError("a symbolic transaction cannot contain overlapping parameter selections"))
        union!(selected_slots, slots)
    end
    return PottsSymbolicSetter(targets, names, single, publish)
end

function SymbolicIndexingInterface.setu(
        provider::Union{PottsSystem, PottsProblem, PottsIntegrator}, symbols
    )
    return _symbolic_setter(provider, symbols; parameters_only = false, publish = true)
end

function SymbolicIndexingInterface.setp(
        provider::Union{PottsSystem, PottsProblem, PottsIntegrator}, symbols;
        run_hook::Bool = true,
    )
    return _symbolic_setter(provider, symbols; parameters_only = true, publish = run_hook)
end

function _symbolic_setter_replacements(setter::PottsSymbolicSetter, replacements, manifest)
    if setter.single
        target = only(setter.targets)
        scalar_parameter = first(target) === :parameter && (
            last(target) isa ParameterComponentIndex || isempty(manifest[last(target)].shape)
        )
        if scalar_parameter && replacements isa Union{Tuple, AbstractArray}
            length(replacements) == 1 || throw(ArgumentError("one parameter target requires one replacement value"))
            return setter.targets, Tuple(replacements)
        end
        return setter.targets, (replacements,)
    end
    if setter.names !== nothing
        replacements isa NamedTuple || throw(ArgumentError("named symbolic targets require named replacement values"))
        positions = map(keys(replacements)) do name
            index = findfirst(isequal(name), setter.names)
            index === nothing && throw(ArgumentError("unknown symbolic replacement label `$name`"))
            index
        end
        return map(index -> setter.targets[index], positions), Tuple(values(replacements))
    end
    if length(setter.targets) == 1 && first(only(setter.targets)) === :parameter &&
            !(replacements isa Union{Tuple, AbstractArray})
        return setter.targets, (replacements,)
    end
    replacements isa Union{Tuple, AbstractArray} ||
        throw(ArgumentError("multiple symbolic targets require a tuple or array of replacement values"))
    selected_values = Tuple(replacements)
    length(selected_values) == length(setter.targets) || throw(
        ArgumentError(
            "symbolic transaction value count does not match its identities"
        )
    )
    return setter.targets, selected_values
end

function (setter::PottsSymbolicSetter)(integrator::PottsIntegrator, replacements)
    _require_symbolic_mutation_boundary!(integrator)
    targets, values = _symbolic_setter_replacements(setter, replacements, integrator.plan.parameter_manifest)
    isempty(targets) && return nothing
    SPI = CorePotts.CompilerSPI
    program = integrator.plan.core_program
    layout = program.descriptor_plan.state_layout
    has_state = any(target -> first(target) === :state, targets)
    has_parameters = any(target -> first(target) === :parameter, targets)
    before = has_state ? CorePotts.BackendSPI.program_snapshot_descriptor_state(CorePotts.program_snapshot(integrator.runtime)) : nothing
    candidate = has_state ? SPI.copy_auxiliary_state(before) : nothing
    # A complete parameter transaction starts from published values. Explicit
    # run_hook=false staging instead accumulates the existing pending batch.
    parameter_base = setter.publish || integrator.pending_parameters === nothing ?
        integrator.runtime.parameters : integrator.pending_parameters
    parameters = has_parameters ? copy(parameter_base) : nothing
    for (target, value) in zip(targets, values)
        index = last(target)
        if first(target) === :parameter
            _write_parameter_value!(parameters, integrator.plan.parameter_manifest, index, value)
            continue
        end
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
    if !setter.publish
        integrator.pending_parameters = parameters
        return nothing
    end
    return _commit_symbolic_update!(
        integrator; parameters, descriptor_state = candidate, descriptor_before = before,
    )
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
    length(indices) == length(values) || throw(ArgumentError("parameter replacement identities and values must have equal length"))
    return _normalize_parameter_values(
        _scheduled_data(system).parameters, [identity => value for (identity, value) in zip(indices, values)]; base = old,
    )
end
