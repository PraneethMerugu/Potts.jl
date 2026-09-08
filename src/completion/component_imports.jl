# Explicit source bindings are resolved once into ordinary MTK-scoped symbols.
# The source inventory remains the sole declaration/ownership authority.

function _component_reference_target(inventory::_PottsSourceInventory, reference::ComponentReference)
    matches = filter(occurrence -> occurrence.path[2:end] == reference.path, inventory.systems)
    length(matches) == 1 || throw(
        ArgumentError(
            "component reference has no unique owner at $(repr(reference.path))"
        )
    )
    owner = only(matches)
    requested = reference.reference
    candidates = Any[]
    for statement in statements(owner.system)
        arguments = _statement_arguments(statement)
        arguments isa NamedTuple && haskey(arguments, :variable) || continue
        matches_reference = requested isa AbstractPottsStatement ?
            statement_kind(statement) === statement_kind(requested) &&
            statement_id(statement) == statement_id(requested) &&
            _canonical_value(statement) == _canonical_value(requested) :
            isequal(arguments.variable, requested)
        matches_reference && push!(candidates, arguments.variable)
    end
    if !(requested isa AbstractPottsStatement)
        append!(candidates, filter(value -> isequal(value, requested), getfield(owner.system, :ps)))
    end
    length(candidates) == 1 || throw(
        ArgumentError(
            "component reference $(repr(requested)) must identify exactly one owned declaration at $(repr(reference.path))"
        )
    )
    return owner, only(candidates)
end

function _component_scoped_value(owner, value, consumer_path)
    scoped = _namespace_symbolic_value(value, owner.path[2:end])
    # Qualification subsequently traverses the consuming namespace. ParentScope
    # skips those levels while preserving the actual owner's ordinary identity.
    for _ in consumer_path[2:end]
        scoped = ModelingToolkitBase.ParentScope(scoped)
    end
    return scoped
end

function _map_component_source(system::PottsSystem, rules)
    substitute_one = value -> _substitute_value(value, rules)
    return _rebuild(
        system;
        statements = StatementSet(map_symbolics(substitute_one, item) for item in statements(system)),
        equations = map(substitute_one, getfield(system, :eqs)),
        unknowns = map(substitute_one, getfield(system, :unknowns)),
        parameters = map(substitute_one, getfield(system, :ps)),
        inputs = map(substitute_one, getfield(system, :inputs)),
        outputs = map(substitute_one, getfield(system, :outputs)),
        initial_conditions = Dict(
            substitute_one(key) => substitute_one(value)
                for (key, value) in getfield(system, :initial_conditions)
        ),
        observed = map(substitute_one, getfield(system, :observed)),
        continuous_events = map(substitute_one, getfield(system, :continuous_events)),
        discrete_events = map(substitute_one, getfield(system, :discrete_events)),
        imports = (),
    )
end

function _resolve_component_imports(inventory::_PottsSourceInventory)
    any(occurrence -> !isempty(getfield(occurrence.system, :imports)), inventory.systems) ||
        return inventory.systems[1].system, inventory
    local_systems = PottsSystem[]
    statement_groups = Vector{AbstractPottsStatement}[]
    for occurrence in inventory.systems
        system = occurrence.system
        bindings = getfield(system, :imports)
        if isempty(bindings)
            push!(local_systems, system)
            push!(statement_groups, collect(AbstractPottsStatement, statements(system)))
            continue
        end
        isempty(getfield(system, :native_components)) || throw(
            ArgumentError(
                "source imports in a component with native declarations are not yet supported"
            )
        )
        owned = Any[getfield(system, :ps)...; getfield(system, :unknowns)...]
        for statement in statements(system)
            arguments = _statement_arguments(statement)
            arguments isa NamedTuple && haskey(arguments, :variable) && push!(owned, arguments.variable)
        end
        rules = Dict{Any, Any}()
        for (alias, reference) in bindings
            any(value -> isequal(value, alias), owned) && throw(
                ArgumentError(
                    "an imported alias cannot also be owned in $(repr(occurrence.path[2:end]))"
                )
            )
            owner, value = _component_reference_target(inventory, reference)
            owner.index == occurrence.index && throw(
                ArgumentError(
                    "a component import must refer to another declaration owner"
                )
            )
            rules[alias] = _component_scoped_value(owner, value, occurrence.path)
        end
        mapped = _map_component_source(system, rules)
        push!(local_systems, mapped)
        push!(statement_groups, collect(AbstractPottsStatement, statements(mapped)))
    end
    return _rebuild_source_inventory(inventory, local_systems, statement_groups)
end
