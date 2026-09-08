# Structural replacement operates on ordinary source ownership, before completion.

function _component_reference_identity(inventory, reference)
    owner, value = _component_reference_target(inventory, reference)
    return (owner.path[2:end], value)
end

function _replace_component_subtree(system, path, replacement)
    children = getfield(system, :systems)
    index = findfirst(child -> nameof(child) === first(path), children)
    index === nothing && throw(
        ArgumentError(
            "component replacement target $(repr(path)) is not a PottsSystem child"
        )
    )
    updated = copy(children)
    updated[index] = length(path) == 1 ? replacement :
        _replace_component_subtree(children[index], Base.tail(path), replacement)
    _assert_unique_namespace_names(updated, getfield(system, :native_components))
    return _rebuild(system; systems = updated)
end

function _component_owned_symbols(inventory, path)
    values = Any[]
    for occurrence in inventory.systems
        _inventory_path_iswithin(occurrence.path[2:end], path) || continue
        append!(
            values, (
                _namespace_symbolic_value(value, occurrence.path[2:end])
                    for value in (
                        getfield(occurrence.system, :ps)...,
                        getfield(occurrence.system, :unknowns)...,
                    )
            )
        )
        for statement in statements(occurrence.system)
            arguments = _statement_arguments(statement)
            arguments isa NamedTuple && haskey(arguments, :variable) || continue
            push!(values, _namespace_symbolic_value(arguments.variable, occurrence.path[2:end]))
        end
    end
    return values
end

function _reject_implicit_component_connections(inventory, replaced_path)
    owned = _component_owned_symbols(inventory, replaced_path)
    for occurrence in inventory.systems
        _inventory_path_iswithin(occurrence.path[2:end], replaced_path) && continue
        source = occurrence.system
        aliases = first.(getfield(source, :imports))
        payloads = Any[
            getfield(source, :eqs), getfield(source, :unknowns),
            getfield(source, :inputs), getfield(source, :outputs),
            getfield(source, :initial_conditions), getfield(source, :observed),
            getfield(source, :continuous_events), getfield(source, :discrete_events),
        ]
        for parameter in getfield(source, :ps)
            ModelingToolkitBase.hasdefault(parameter) || continue
            push!(payloads, ModelingToolkitBase.getdefault(parameter))
        end
        for statement in statements(source)
            push!(payloads, (_statement_arguments(statement), _statement_options(statement)))
        end
        for value in _collect_symbolics(payloads)
            any(alias -> isequal(alias, value), aliases) && continue
            qualified = _namespace_symbolic_value(value, occurrence.path[2:end])
            any(target -> isequal(target, qualified), owned) || continue
            throw(
                ArgumentError(
                    "replacement requires explicit component imports for surviving reference $(repr(qualified))"
                )
            )
        end
    end
    for native in inventory.natives
        _inventory_path_iswithin(native.system_path[2:end], replaced_path) && continue
        aliases = first.(getfield(inventory.systems[native.system].system, :imports))
        for port in (native_inputs(native.component)..., native_outputs(native.component)...)
            arguments = _statement_arguments(potts_endpoint(port))
            if arguments isa NamedTuple && haskey(arguments, :variable)
                any(alias -> isequal(alias, arguments.variable), aliases) && continue
            end
            # Direct ports hold declaration references, not consumer-local
            # variable spellings. Resolve them before removing their owner.
            owner = _native_endpoint_occurrence(inventory, native, port)
            _inventory_path_iswithin(owner.path[2:end], replaced_path) || continue
            throw(
                ArgumentError(
                    "replacement requires explicit component imports for surviving native port at $(repr(native.path))"
                )
            )
        end
    end
    return nothing
end

function _component_reference_contract(completed, inventory, reference)
    owner, value = _component_reference_target(inventory, reference)
    qualified = _namespace_symbolic_value(value, owner.path[2:end])
    records = filter(_completion_data(completed).records) do record
        variable = _state_record_variable(record)
        variable !== nothing && isequal(variable, qualified)
    end
    if isempty(records)
        return (:parameter, _symbolic_result_type(value), (), _declared_parameter_unit(value))
    end
    record = only(records)
    return (record.kind, record.result_type, record.shape, _declared_record_unit(record))
end

"""
    replace_component(source, path => replacement; reconnect=())

Replace an owned PottsSystem subtree in incomplete symbolic source. `path` is a
nonempty root-relative tuple. Surviving imports of removed outputs require
explicit `ComponentReference => ComponentReference` reconnections, including
when the replacement reuses their names. External declaration owners are retained.

Cross-component consumers, including native Potts ports, must use explicit imports.
Replacement accepts PottsSystem subtrees, including their owned native components;
it does not accept a bare NativeComponent as the replacement target.
This operation rebuilds and validates source; it does not modify a running problem.
"""
function replace_component(source::PottsSystem, replacement_pair::Pair; reconnect = ())
    _ensure_incomplete(source, "replace_component")
    path, replacement = replacement_pair
    path isa Tuple{Vararg{Symbol}} && !isempty(path) || throw(
        ArgumentError(
            "component replacement requires a nonempty root-relative path tuple"
        )
    )
    replacement isa PottsSystem || throw(
        ArgumentError(
            "component replacement currently requires a PottsSystem source"
        )
    )
    _ensure_incomplete(replacement, "replace_component")
    before = _source_inventory(source)
    target = filter(item -> item.path[2:end] == path, before.systems)
    length(target) == 1 || throw(ArgumentError("unknown component replacement path $(repr(path))"))
    _resolve_component_imports(before)
    _reject_implicit_component_connections(before, path)
    completed_before = complete(source)
    candidate = _replace_component_subtree(source, path, replacement)
    after = _source_inventory(candidate)
    new_path = (path[1:(end - 1)]..., nameof(replacement))
    rules = Dict{Any, ComponentReference}()
    for rule in reconnect
        rule isa Pair && first(rule) isa ComponentReference && last(rule) isa ComponentReference ||
            throw(ArgumentError("reconnections require ComponentReference => ComponentReference pairs"))
        old_reference, new_reference = rule
        _inventory_path_iswithin(old_reference.path, path) || throw(
            ArgumentError(
                "a reconnection must identify an output of the removed component"
            )
        )
        identity = _component_reference_identity(before, old_reference)
        haskey(rules, identity) && throw(ArgumentError("duplicate component output reconnection"))
        _component_reference_target(after, new_reference)
        rules[identity] = new_reference
    end
    used = Set{Any}()
    locals = PottsSystem[]
    groups = Vector{AbstractPottsStatement}[]
    for occurrence in after.systems
        system = occurrence.system
        if !_inventory_path_iswithin(occurrence.path[2:end], new_path)
            bindings = Pair[]
            for (alias, reference) in getfield(system, :imports)
                if _inventory_path_iswithin(reference.path, path)
                    identity = _component_reference_identity(before, reference)
                    haskey(rules, identity) || throw(
                        ArgumentError(
                            "surviving import of $(repr(reference.path)) requires an explicit output reconnection"
                        )
                    )
                    push!(used, identity)
                    reference = rules[identity]
                end
                push!(bindings, alias => reference)
            end
            system = _rebuild(system; imports = Tuple(bindings))
        end
        push!(locals, system)
        push!(groups, collect(AbstractPottsStatement, statements(system)))
    end
    length(used) == length(rules) || throw(ArgumentError("unused component output reconnection"))
    rebuilt, _ = _rebuild_source_inventory(after, locals, groups)
    # Completion owns binding and operation validation. Retain the editable
    # source, not its completed graph, as the structural operation's result.
    completed_after = complete(rebuilt)
    for (identity, reference) in rules
        isequal(
            _component_reference_contract(completed_before, before, ComponentReference(identity...)),
            _component_reference_contract(completed_after, after, reference)
        ) || throw(ArgumentError("component reconnection has incompatible declaration contracts"))
    end
    return rebuilt
end
