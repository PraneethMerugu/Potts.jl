"""Marker requesting completion of declared reference-unit values."""
struct DeclaredReferenceUnits end

"""Validated immutable reference-unit values for a completed system."""
struct ReferenceUnits{T <: NamedTuple}
    values::T
end

ReferenceUnits(; kwargs...) = ReferenceUnits((; kwargs...))

"""
    PottsSystem(; name, statements=StatementSet(), equations=(), unknowns=(),
                parameters=(), independent_variables=(), systems=(),
                native_components=(), inputs=(), outputs=(),
                initial_conditions=Dict(), observed=(), events=(),
                continuous_events=(), discrete_events=events)

Declarative Potts model compatible with ModelingToolkit composition. Use
`@named model = PottsSystem(...)` to supply `name`, then call `complete` and
`mtkcompile` before constructing a `PottsProblem`.
"""
struct PottsSystem <: ModelingToolkitBase.AbstractSystem
    name::Symbol
    statements::StatementSet
    eqs::Vector{Any}
    unknowns::Vector{Any}
    ps::Vector{Any}
    iv::Any
    ivs::Vector{Any}
    systems::Vector{PottsSystem}
    native_components::Vector{NativeComponent}
    inputs::Vector{Any}
    outputs::Vector{Any}
    initial_conditions::Dict{Any, Any}
    observed::Vector{Any}
    continuous_events::Vector{Any}
    discrete_events::Vector{Any}
    complete::Bool
    isscheduled::Bool
    namespacing::Bool
    completion::Any

    function PottsSystem(
            name::Symbol,
            statements::StatementSet,
            eqs::Vector{Any},
            unknowns::Vector{Any},
            ps::Vector{Any},
            iv,
            ivs::Vector{Any},
            systems::Vector{PottsSystem},
            native_components::Vector{NativeComponent},
            inputs::Vector{Any},
            outputs::Vector{Any},
            initial_conditions::Dict{Any, Any},
            observed::Vector{Any},
            continuous_events::Vector{Any},
            discrete_events::Vector{Any},
            complete::Bool,
            isscheduled::Bool,
            namespacing::Bool,
            completion;
            checks::Bool = true,
        )
        !checks && complete && throw(ArgumentError(
            "a completed PottsSystem is immutable; rename or compose before `complete`"
        ))
        return new(
            name,
            statements,
            eqs,
            unknowns,
            ps,
            iv,
            ivs,
            systems,
            native_components,
            inputs,
            outputs,
            initial_conditions,
            observed,
            continuous_events,
            discrete_events,
            complete,
            isscheduled,
            namespacing,
            completion,
        )
    end
end


function PottsSystem(;
        name = nothing,
        statements = StatementSet(),
        equations = (),
        unknowns = (),
        parameters = (),
        independent_variables = (),
        systems = (),
        native_components = (),
        inputs = (),
        outputs = (),
        initial_conditions = Dict(),
        observed = (),
        events = (),
        continuous_events = (),
        discrete_events = events,
    )
    name isa Symbol || throw(ArgumentError(
        "PottsSystem requires `name`; use `@named model = PottsSystem(...)`"
    ))
    statement_set = statements isa StatementSet ? StatementSet(statements.values) :
                    StatementSet(statements)
    child_systems = PottsSystem[]
    for system in systems
        system isa PottsSystem || throw(ArgumentError(
            "PottsSystem hierarchy is homogeneous; got subsystem $(typeof(system))"
        ))
        push!(child_systems, system)
    end
    native_values = NativeComponent[]
    for component in native_components
        component isa NativeComponent || throw(ArgumentError(
            "native_components must contain only NativeComponent declarations; " *
            "got $(typeof(component))"
        ))
        push!(native_values, component)
    end
    _assert_unique_namespace_names(child_systems, native_values)
    ivs = Any[_defensive_copy(value) for value in independent_variables]
    iv = length(ivs) == 1 ? only(ivs) : nothing
    return PottsSystem(
        name,
        statement_set,
        Any[_defensive_copy(value) for value in equations],
        Any[_defensive_copy(value) for value in unknowns],
        Any[_defensive_copy(value) for value in parameters],
        iv,
        ivs,
        child_systems,
        native_values,
        Any[_defensive_copy(value) for value in inputs],
        Any[_defensive_copy(value) for value in outputs],
        Dict{Any, Any}(
            _defensive_copy(key) => _defensive_copy(value)
            for (key, value) in pairs(initial_conditions)
        ),
        Any[_defensive_copy(value) for value in observed],
        Any[_defensive_copy(value) for value in continuous_events],
        Any[_defensive_copy(value) for value in discrete_events],
        false,
        false,
        true,
        nothing,
    )
end

function _rebuild(
        system::PottsSystem;
        name = getfield(system, :name),
        statements = getfield(system, :statements),
        equations = getfield(system, :eqs),
        unknowns = getfield(system, :unknowns),
        parameters = getfield(system, :ps),
        independent_variables = getfield(system, :ivs),
        systems = getfield(system, :systems),
        native_components = getfield(system, :native_components),
        inputs = getfield(system, :inputs),
        outputs = getfield(system, :outputs),
        initial_conditions = getfield(system, :initial_conditions),
        observed = getfield(system, :observed),
        continuous_events = getfield(system, :continuous_events),
        discrete_events = getfield(system, :discrete_events),
        complete = getfield(system, :complete),
        isscheduled = getfield(system, :isscheduled),
        namespacing = getfield(system, :namespacing),
        completion = getfield(system, :completion),
    )
    ivs = Any[_defensive_copy(value) for value in independent_variables]
    iv = length(ivs) == 1 ? only(ivs) : nothing
    return PottsSystem(
        name,
        statements isa StatementSet ? StatementSet(statements.values) : StatementSet(statements),
        Any[_defensive_copy(value) for value in equations],
        Any[_defensive_copy(value) for value in unknowns],
        Any[_defensive_copy(value) for value in parameters],
        iv,
        ivs,
        PottsSystem[system for system in systems],
        NativeComponent[component for component in native_components],
        Any[_defensive_copy(value) for value in inputs],
        Any[_defensive_copy(value) for value in outputs],
        Dict{Any, Any}(
            _defensive_copy(key) => _defensive_copy(value)
            for (key, value) in pairs(initial_conditions)
        ),
        Any[_defensive_copy(value) for value in observed],
        Any[_defensive_copy(value) for value in continuous_events],
        Any[_defensive_copy(value) for value in discrete_events],
        Bool(complete),
        Bool(isscheduled),
        Bool(namespacing),
        completion,
    )
end

"""Return the ordered statements owned directly by a Potts system."""
statements(system::PottsSystem) = statements(getfield(system, :statements))
"""Return native component declarations owned directly by a Potts system."""
native_components(system::PottsSystem) =
    Tuple(getfield(system, :native_components))

"""
    is_scheduled(system::PottsSystem) -> Bool

Return whether `system` has passed Potts's structural `mtkcompile`
boundary. This is the Potts-owned scheduling query; the `isscheduled` field is
retained only as part of the `ModelingToolkitBase.AbstractSystem` storage
contract.
"""
is_scheduled(system::PottsSystem) = getfield(system, :isscheduled)
ModelingToolkitBase.has_iv(system::PottsSystem) = getfield(system, :iv) !== nothing
function ModelingToolkitBase.independent_variables(system::PottsSystem)
    result = Any[_defensive_copy(value) for value in getfield(system, :ivs)]
    for child in getfield(system, :systems)
        result = _stable_union(
            result, ModelingToolkitBase.independent_variables(child)
        )
    end
    return result
end

function _recursive_namespaced_io(system::PottsSystem, accessor)
    result = Any[_defensive_copy(value) for value in accessor(system, Val(:local))]
    for child in getfield(system, :systems)
        for value in accessor(child)
            namespaced = ModelingToolkitBase.renamespace(child, value)
            any(isequal(namespaced), result) || push!(result, namespaced)
        end
    end
    return result
end

_potts_inputs(system::PottsSystem, ::Val{:local}) =
    getfield(system, :inputs)
_potts_inputs(system::PottsSystem) =
    _recursive_namespaced_io(system, _potts_inputs)
_potts_outputs(system::PottsSystem, ::Val{:local}) =
    getfield(system, :outputs)
_potts_outputs(system::PottsSystem) =
    _recursive_namespaced_io(system, _potts_outputs)

ModelingToolkitBase.inputs(system::PottsSystem) = _potts_inputs(system)
ModelingToolkitBase.outputs(system::PottsSystem) = _potts_outputs(system)

function _substitute_value(value, rules)
    return try
        Symbolics.substitute(value, rules)
    catch error
        if SymbolicIndexingInterface.symbolic_type(value) isa
                SymbolicIndexingInterface.NotSymbolic
            value
        else
            rethrow(error)
        end
    end
end

function Symbolics.substitute(
        system::PottsSystem, rules::Union{Vector{<:Pair}, Dict}
    )
    _ensure_incomplete(system, "substitute")
    normalized = Dict(rules)
    if !isempty(normalized) && all(key -> key isa Symbol, keys(normalized))
        children = PottsSystem[
            Symbolics.substitute(child, normalized)
            for child in getfield(system, :systems)
        ]
        renamed = get(normalized, nameof(system), nameof(system))
        renamed isa Symbol ||
            throw(ArgumentError("a substituted system name must be a Symbol"))
        return _rebuild(system; name = renamed, systems = children)
    end

    _has_native_components(system) && throw(ArgumentError(
        "symbolic substitution of a PottsSystem with NativeComponent " *
        "declarations is not defined; remake native problem data after scheduling"
    ))

    substitute_one = value -> _substitute_value(value, normalized)
    substituted_statements = StatementSet(
        map_symbolics(substitute_one, statement) for statement in statements(system)
    )
    substituted_unknowns = map(substitute_one, getfield(system, :unknowns))
    substituted_parameters = map(substitute_one, getfield(system, :ps))
    is_symbolic = value -> !isempty(try
        Symbolics.get_variables(value)
    catch
        ()
    end)

    return _rebuild(
        system;
        statements = substituted_statements,
        equations = map(substitute_one, getfield(system, :eqs)),
        unknowns = filter(is_symbolic, substituted_unknowns),
        parameters = filter(is_symbolic, substituted_parameters),
        independent_variables = filter(
            is_symbolic, map(substitute_one, getfield(system, :ivs))
        ),
        systems = PottsSystem[
            Symbolics.substitute(child, normalized)
            for child in getfield(system, :systems)
        ],
        inputs = filter(is_symbolic, map(substitute_one, getfield(system, :inputs))),
        outputs = filter(is_symbolic, map(substitute_one, getfield(system, :outputs))),
        initial_conditions = Dict(
            substitute_one(key) => substitute_one(value)
            for (key, value) in getfield(system, :initial_conditions)
        ),
        observed = map(substitute_one, getfield(system, :observed)),
        continuous_events = map(substitute_one, getfield(system, :continuous_events)),
        discrete_events = map(substitute_one, getfield(system, :discrete_events)),
    )
end

function _has_native_components(system::PottsSystem)
    !isempty(getfield(system, :native_components)) && return true
    return any(_has_native_components, getfield(system, :systems))
end

function _assert_unique_system_names(systems)
    seen = Set{Symbol}()
    for system in systems
        name = nameof(system)
        name in seen && throw(ArgumentError("duplicate subsystem name `$name`"))
        push!(seen, name)
    end
    return nothing
end

function _assert_unique_namespace_names(systems, natives)
    _assert_unique_system_names(systems)
    seen = Set(nameof(system) for system in systems)
    for component in natives
        name = nameof(component)
        name in seen && throw(ArgumentError(
            "duplicate subsystem or native component name `$name`"
        ))
        push!(seen, name)
    end
    return nothing
end

function _ensure_incomplete(system::PottsSystem, operation::AbstractString)
    ModelingToolkitBase.iscomplete(system) && throw(ArgumentError(
        "$operation requires an incomplete PottsSystem; begin from symbolic source"
    ))
    return nothing
end

function ModelingToolkitBase.compose(
        system::PottsSystem, children::AbstractArray; name = nameof(system)
    )
    _ensure_incomplete(system, "compose")
    typed_children = PottsSystem[]
    native_children = NativeComponent[]
    for child in children
        if child isa PottsSystem
            _ensure_incomplete(child, "compose")
            push!(typed_children, child)
        elseif child isa NativeComponent
            push!(native_children, child)
        else
            throw(ArgumentError(
                "PottsSystem compose admits PottsSystem and NativeComponent " *
                "children, got $(typeof(child))"
            ))
        end
    end
    merged = [getfield(system, :systems); typed_children]
    merged_natives = [getfield(system, :native_components); native_children]
    _assert_unique_namespace_names(merged, merged_natives)
    return _rebuild(
        system; name, systems = merged, native_components = merged_natives
    )
end

function ModelingToolkitBase.extend(
        system::PottsSystem, base::PottsSystem; name::Symbol = nameof(system), kwargs...
    )
    isempty(kwargs) || throw(ArgumentError(
        "unsupported PottsSystem extend options: $(join(keys(kwargs), ", "))"
    ))
    _ensure_incomplete(system, "extend")
    _ensure_incomplete(base, "extend")

    statement_values = (statements(base)..., statements(system)...)
    ids = StatementID[statement_id(statement) for statement in statement_values]
    length(unique(ids)) == length(ids) || throw(ArgumentError(
        "extend encountered duplicate statement identities"
    ))
    _reject_duplicates(getfield(base, :eqs), getfield(system, :eqs), "equation")
    _reject_duplicates(
        getfield(base, :observed), getfield(system, :observed),
        "observed equation",
    )
    _reject_duplicates(
        getfield(base, :continuous_events),
        getfield(system, :continuous_events),
        "continuous event",
    )
    _reject_duplicates(
        getfield(base, :discrete_events),
        getfield(system, :discrete_events),
        "discrete event",
    )

    initial_conditions = copy(getfield(base, :initial_conditions))
    for (key, value) in getfield(system, :initial_conditions)
        if haskey(initial_conditions, key) && !isequal(initial_conditions[key], value)
            throw(ArgumentError("conflicting initial condition for $(repr(key))"))
        end
        initial_conditions[key] = value
    end

    children = [getfield(base, :systems); getfield(system, :systems)]
    natives = [
        getfield(base, :native_components);
        getfield(system, :native_components)
    ]
    _assert_unique_namespace_names(children, natives)
    return _rebuild(
        system;
        name,
        statements = StatementSet(statement_values),
        equations = [getfield(base, :eqs); getfield(system, :eqs)],
        unknowns = _stable_union(getfield(base, :unknowns), getfield(system, :unknowns)),
        parameters = _stable_union(getfield(base, :ps), getfield(system, :ps)),
        independent_variables = _stable_union(getfield(base, :ivs), getfield(system, :ivs)),
        systems = children,
        native_components = natives,
        inputs = _stable_union(getfield(base, :inputs), getfield(system, :inputs)),
        outputs = _stable_union(getfield(base, :outputs), getfield(system, :outputs)),
        initial_conditions,
        observed = [getfield(base, :observed); getfield(system, :observed)],
        continuous_events = [
            getfield(base, :continuous_events); getfield(system, :continuous_events)
        ],
        discrete_events = [
            getfield(base, :discrete_events); getfield(system, :discrete_events)
        ],
    )
end

function _reject_duplicates(left, right, noun)
    for item in left
        any(isequal(item), right) &&
            throw(ArgumentError("extend encountered duplicate $noun $(repr(item))"))
    end
    return nothing
end

function _stable_union(left, right)
    result = Any[_defensive_copy(item) for item in left]
    for item in right
        any(isequal(item), result) || push!(result, _defensive_copy(item))
    end
    return result
end

function ModelingToolkitBase.flatten(system::PottsSystem, args...)
    isempty(args) || throw(ArgumentError("PottsSystem flatten accepts no positional options"))
    _ensure_incomplete(system, "flatten")
    isempty(getfield(system, :systems)) && return system
    return _flatten(system, ())
end

function _flatten(system::PottsSystem, prefix::Tuple)
    inventory = _source_inventory(system)
    flat_statements = AbstractPottsStatement[]
    for occurrence in inventory.statements
        relative_path = occurrence.path[2:end]
        push!(flat_statements, _namespace_statement_for_lowering(
            occurrence.statement, (prefix..., relative_path...)
        ))
    end
    flat_natives = NativeComponent[]
    for occurrence in inventory.natives
        relative_system_path = occurrence.system_path[2:end]
        native_path = (prefix..., relative_system_path..., nameof(occurrence.component))
        name = isempty(native_path[1:(end - 1)]) ? nameof(occurrence.component) :
               Symbol(join(String.(native_path), "₊"))
        mapped = _map_native_potts_endpoints(
            endpoint -> _namespace_statement_for_lowering(
                endpoint, (prefix..., relative_system_path...)
            ),
            occurrence.component;
            name,
        )
        push!(flat_natives, mapped)
    end
    _assert_unique_namespace_names(PottsSystem[], flat_natives)

    return _rebuild(
        system;
        statements = StatementSet(flat_statements),
        equations = ModelingToolkitBase.equations(system),
        unknowns = ModelingToolkitBase.unknowns(system),
        parameters = ModelingToolkitBase.parameters(system),
        independent_variables =
            ModelingToolkitBase.independent_variables(system),
        systems = PottsSystem[],
        native_components = flat_natives,
        inputs = ModelingToolkitBase.inputs(system),
        outputs = ModelingToolkitBase.outputs(system),
        initial_conditions =
            ModelingToolkitBase.initial_conditions(system),
        observed = ModelingToolkitBase.observed(system),
        continuous_events =
            ModelingToolkitBase.continuous_events(system),
        discrete_events =
            ModelingToolkitBase.discrete_events(system),
    )
end

function ModelingToolkitBase.complete(
        system::PottsSystem;
        reference_units = DeclaredReferenceUnits(),
        registry = default_statement_registry(),
        kwargs...,
    )
    isempty(kwargs) || throw(ArgumentError(
        "unsupported PottsSystem completion options: $(join(keys(kwargs), ", "))"
    ))
    registry isa StatementRegistry ||
        throw(ArgumentError("registry must be a StatementRegistry"))
    reference_units isa Union{DeclaredReferenceUnits, ReferenceUnits} ||
        throw(ArgumentError(
            "reference_units must be DeclaredReferenceUnits() or ReferenceUnits(...)"
        ))

    if ModelingToolkitBase.iscomplete(system)
        completion = getfield(system, :completion)
        isequal(completion.registry, registry) &&
            isequal(completion.reference_units, reference_units) && return system
        throw(ArgumentError("a completed PottsSystem cannot be completed with new options"))
    end

    # This is the sole hierarchy discovery for completion. Every later pass
    # transforms or projects these occurrences without walking `systems` again.
    inventory = _source_inventory(system)
    _, inventory, structural_parameters =
        _resolve_structural_parameters(inventory)
    diagnostics = PottsDiagnostic[]
    expanded_system, inventory = _expand_registered_inventory(
        inventory, registry, diagnostics
    )
    _throw_diagnostics(:completion, diagnostics)
    expanded_system, inventory = _expand_structural_policies(inventory)
    return _complete_inventory_hierarchy(
        expanded_system,
        inventory,
        reference_units,
        registry,
        structural_parameters,
    )
end

function _validate_statement_identities(system::PottsSystem)
    ids = StatementID[]
    for statement in statements(system)
        id = statement_id(statement)
        id in ids && throw(ArgumentError(
            "duplicate statement identity `$(Symbol(id))` in system `$(nameof(system))`"
        ))
        push!(ids, id)
    end
    return nothing
end

function Base.show(io::IO, system::PottsSystem)
    print(
        io,
        "PottsSystem(",
        repr(nameof(system)),
        "; ",
        length(statements(system)),
        " statement",
        length(statements(system)) == 1 ? "" : "s",
        ", ",
        length(getfield(system, :systems)),
        " subsystem",
        length(getfield(system, :systems)) == 1 ? "" : "s",
        ", ",
        length(getfield(system, :native_components)),
        " native component",
        length(getfield(system, :native_components)) == 1 ? "" : "s",
        is_scheduled(system) ? ", scheduled)" :
        ModelingToolkitBase.iscomplete(system) ? ", complete)" : ", incomplete)",
    )
end
