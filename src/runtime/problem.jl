"""
    PottsProblem(system, u0, tspan; p=(), seed, replica=1, repeat=1, policies=(;))

Bind immutable initial data, runtime parameters, and stochastic identity to a
structurally scheduled `PottsSystem`. Construction performs host validation but
does not lower a CorePotts program or allocate runtime state. Algorithm,
backend, and scalar type are selected later by `init` or `solve`.
"""
struct PottsProblem{S, U, P, R} <: SciMLBase.AbstractSciMLProblem
    system::S
    u0::U
    p::P
    tspan::Tuple{Int, Int}
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    policies::R
end

# `u0` is a public SciML problem property, but the stored value is the frozen
# initialization recipe used by every later `init` and ensemble context.  A
# public read therefore returns an independently owned logical copy.  Package
# internals use this narrow accessor when they only need to read the frozen
# value without allocating another copy.
_problem_initial_state(problem::PottsProblem) = getfield(problem, :u0)

function Base.getproperty(problem::PottsProblem, name::Symbol)
    name === :u0 && return _defensive_copy(_problem_initial_state(problem))
    return getfield(problem, name)
end

function _normalize_seed(seed::Integer)
    seed >= 0 || throw(ArgumentError("seed must be nonnegative"))
    seed <= typemax(UInt64) || throw(ArgumentError("seed exceeds UInt64"))
    return UInt64(seed)
end

function _normalize_replica(replica::Integer)
    1 <= replica <= typemax(UInt32) ||
        throw(ArgumentError("replica must be in 1:$(typemax(UInt32))"))
    return UInt32(replica)
end

function _normalize_repeat(repeat::Integer)
    1 <= repeat <= typemax(UInt32) ||
        throw(ArgumentError("repeat must be in 1:$(typemax(UInt32))"))
    return UInt32(repeat)
end

function _normalize_tspan(tspan)
    tspan isa Tuple && length(tspan) == 2 &&
        all(value -> value isa Integer, tspan) ||
        throw(ArgumentError("Potts time span must be two integer MCS boundaries"))
    first_time, last_time = Int.(tspan)
    0 <= first_time <= last_time ||
        throw(ArgumentError("Potts time span must satisfy 0 ≤ t0 ≤ t1"))
    return (first_time, last_time)
end

function _problem_parameter_name(key)
    key isa Symbol && return key
    name = _try_symbolic_name(key)
    name === nothing && throw(ArgumentError(
        "runtime parameter keys must be symbols or symbolic parameters"
    ))
    return name
end

function _validate_problem_parameter_value(entry, value, reference_units)
    if entry.required
        _is_quantity(value) && throw(ArgumentError(
            "required parameter `$(entry.name)` has no declared dimensional default"
        ))
        numeric = _numeric_value(value)
    elseif _is_quantity(entry.default)
        _is_quantity(value) || throw(ArgumentError(
            "parameter `$(entry.name)` requires units compatible with its default"
        ))
        numeric = _numeric_value(
            value, _reference_for(reference_units, entry.default)
        )
    else
        _is_quantity(value) && throw(ArgumentError(
            "parameter `$(entry.name)` is dimensionless"
        ))
        numeric = _numeric_value(value)
    end
    numeric isa Real && isfinite(numeric) || throw(ArgumentError(
        "parameter `$(entry.name)` must be finite and real"
    ))
    return _defensive_copy(value)
end

function _normalize_problem_parameters(system::PottsSystem, supplied)
    schema = _scheduled_data(system).parameters
    runtime = schema.runtime
    names = Tuple(entry.name for entry in runtime)
    length(unique(names)) == length(names) || error(
        "scheduled parameter schema contains duplicate names"
    )
    structural_names = Set(entry.name for entry in schema.structural)
    values = Any[
        entry.required ? nothing : _defensive_copy(entry.default)
        for entry in runtime
    ]
    assigned = falses(length(runtime))
    reference_units = _build_reference_descriptors(system)
    for (key, value) in _normalize_parameter_pairs(supplied)
        name = _problem_parameter_name(key)
        name in structural_names && throw(ArgumentError(
            "parameter `$name` is structural; substitute it before mtkcompile"
        ))
        index = findfirst(==(name), names)
        index === nothing && throw(ArgumentError(
            "unknown runtime parameter $(repr(key))"
        ))
        assigned[index] && throw(ArgumentError(
            "duplicate runtime parameter $(repr(key))"
        ))
        values[index] = _validate_problem_parameter_value(
            runtime[index], value, reference_units
        )
        assigned[index] = true
    end
    missing = Symbol[
        runtime[index].name for index in eachindex(runtime)
        if runtime[index].required && !assigned[index]
    ]
    isempty(missing) || throw(ArgumentError(
        "missing required runtime parameter$(length(missing) == 1 ? "" : "s"): " *
        join(string.(missing), ", ")
    ))
    frozen = Tuple(values)
    return PottsParameters(frozen, NamedTuple{names}(frozen))
end

function _scheduled_domain_shape(system::PottsSystem)
    domains = _scheduled_data(system).capability_requirements.domains
    length(domains) == 1 || throw(ArgumentError(
        "a runnable PottsProblem requires exactly one scheduled lattice domain"
    ))
    return Tuple(Int.(only(domains).shape))
end

function _problem_initial_cell_count(initial::PottsInitialState)
    ownership = initial.ownership
    if ownership isa LabelledCells
        return Int(maximum(ownership.labels; init = Int32(0)))
    end
    return maximum((
        placement isa CellPlacement ? placement.label :
        placement isa RandomSitePlacement ?
            placement.first_label + placement.count - 1 : 0
        for placement in ownership.placements
    ); init = 0)
end

function _validate_problem_initial(system::PottsSystem, initial::PottsInitialState)
    shape = _scheduled_domain_shape(system)
    actual_shape = initial.ownership isa LabelledCells ?
                   size(initial.ownership.labels) : initial.ownership.shape
    Tuple(actual_shape) == shape || throw(ArgumentError(
        "initial ownership shape $(Tuple(actual_shape)) does not match scheduled lattice $shape"
    ))
    domain = only(_scheduled_data(system).capability_requirements.domains)
    max_cells = domain.max_cells
    if max_cells !== nothing
        _problem_initial_cell_count(initial) <= Int(_numeric_value(max_cells)) ||
            throw(ArgumentError(
                "initial finite-cell count exceeds scheduled max_cells=$(max_cells)"
            ))
    end
    component_paths = Tuple(
        native_component_path(component)
        for component in scheduled_native_components(system)
    )
    operating_paths = Tuple(point.path for point in initial.native)
    missing = setdiff(Set(component_paths), Set(operating_paths))
    extra = setdiff(Set(operating_paths), Set(component_paths))
    isempty(missing) || throw(ArgumentError(
        "missing NativeOperatingPoint for component$(length(missing) == 1 ? "" : "s"): " *
        join((join(path, '₊') for path in sort!(collect(missing); by = string)), ", ")
    ))
    isempty(extra) || throw(ArgumentError(
        "NativeOperatingPoint does not resolve to a scheduled component: " *
        join((join(path, '₊') for path in sort!(collect(extra); by = string)), ", ")
    ))
    _validate_problem_relationship_generation_hints(system, initial)
    return nothing
end

function _validate_problem_relationship_generation_hints(
        system::PottsSystem, initial::PottsInitialState
    )
    relationships = _scheduled_data(system).relationships
    isempty(relationships) && return nothing
    for (key, value) in initial.values
        key_name = _state_name(key)
        matches = findall(
            relationship -> relationship.name === key_name,
            relationships,
        )
        if isempty(matches)
            matches = findall(
                relationship ->
                    Symbol(relationship.identity.local_id) === key_name,
                relationships,
            )
        end
        length(matches) <= 1 || throw(ArgumentError(
            "initial relationship key `$key_name` is ambiguous; use its qualified name"
        ))
        isempty(matches) && continue
        relationship = relationships[only(matches)]
        value === nothing && continue
        value isa Union{Tuple, AbstractVector} || continue
        for entry in value
            entry isa Tuple && length(entry) == 3 || continue
            payload = entry[3]
            payload isa NamedTuple || continue
            for generation_name in (:generation_a, :generation_b)
                haskey(payload, generation_name) || continue
                generation = try
                    UInt32(getproperty(payload, generation_name))
                catch
                    throw(ArgumentError(
                        "initial relationship `$(relationship.name)` " *
                        "$(generation_name) must be representable as UInt32"
                    ))
                end
                generation == UInt32(1) || throw(ArgumentError(
                    "initial relationship `$(relationship.name)` carries " *
                    "stale $(generation_name)=$generation; initial cell " *
                    "identities begin at generation 1"
                ))
            end
        end
    end
    return nothing
end

function PottsProblem(
        system::PottsSystem,
        u0::PottsInitialState,
        tspan;
        p = (),
        seed,
        replica::Integer = 1,
        repeat::Integer = 1,
        policies::NamedTuple = NamedTuple(),
    )
    is_scheduled(system) || throw(ArgumentError(
        "PottsProblem requires a scheduled PottsSystem; call mtkcompile first"
    ))
    normalized_u0 = _defensive_copy(u0)
    _validate_problem_initial(system, normalized_u0)
    normalized_p = _normalize_problem_parameters(system, p)
    return PottsProblem(
        system,
        normalized_u0,
        normalized_p,
        _normalize_tspan(tspan),
        _normalize_seed(seed),
        _normalize_replica(replica),
        _normalize_repeat(repeat),
        _defensive_copy(policies),
    )
end

function _with_ensemble_context(
        problem::PottsProblem,
        replica::Integer,
        repeat::Integer,
    )
    return PottsProblem(
        problem.system,
        _problem_initial_state(problem),
        problem.p,
        problem.tspan,
        problem.seed,
        _normalize_replica(replica),
        _normalize_repeat(repeat),
        problem.policies,
    )
end

function _overlay_initial_values(existing, replacements)
    result = Pair{Any, Any}[
        _defensive_copy(first(pair)) => _defensive_copy(last(pair))
        for pair in existing
    ]
    for replacement in replacements
        key = first(replacement)
        index = findfirst(pair -> isequal(first(pair), key), result)
        copied = _defensive_copy(key) => _defensive_copy(last(replacement))
        if index === nothing
            push!(result, copied)
        else
            result[index] = copied
        end
    end
    return Tuple(result)
end

function remake(
        problem::PottsProblem;
        u0 = missing,
        p = missing,
        tspan = missing,
        seed = missing,
        replica = missing,
        repeat = missing,
        policies = missing,
        kwargs...,
    )
    isempty(kwargs) || throw(ArgumentError(
        "PottsProblem remake accepts only u0, p, tspan, seed, replica, repeat, and policies"
    ))
    initial = if ismissing(u0)
        _problem_initial_state(problem)
    elseif u0 isa PottsInitialState
        u0
    else
        stored_initial = _problem_initial_state(problem)
        PottsInitialState(
            ownership = stored_initial.ownership,
            values = _overlay_initial_values(
                stored_initial.values, _initial_value_pairs(u0)
            ),
            native = stored_initial.native,
        )
    end
    parameter_values = ismissing(p) ? problem.p.named : p
    return PottsProblem(
        problem.system,
        initial,
        ismissing(tspan) ? problem.tspan : tspan;
        p = parameter_values,
        seed = ismissing(seed) ? problem.seed : seed,
        replica = ismissing(replica) ? problem.replica : replica,
        repeat = ismissing(repeat) ? problem.repeat : repeat,
        policies = ismissing(policies) ? problem.policies : policies,
    )
end

function Base.show(io::IO, problem::PottsProblem)
    print(
        io,
        "PottsProblem(",
        nameof(problem.system),
        ", ",
        problem.tspan[1],
        ":",
        problem.tspan[2],
        " MCS; replica=",
        problem.replica,
        ", repeat=",
        problem.repeat,
        ")",
    )
end
