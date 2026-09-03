"""Host-only, single-traversal inventory of an authored Potts hierarchy."""
struct _SourceSystemOccurrence
    index::Int32
    system::PottsSystem
    path::Tuple{Vararg{Symbol}}
    parent::Int32
end

struct _SourceStatementOccurrence
    system::Int32
    path::Tuple{Vararg{Symbol}}
    source_order::Int32
    statement::AbstractPottsStatement
end

struct _SourceReferenceOccurrence
    kind::Symbol
    path::Tuple{Vararg{Symbol}}
    value::Any
end

struct _SourceNativeOccurrence
    system::Int32
    system_path::Tuple{Vararg{Symbol}}
    path::Tuple{Vararg{Symbol}}
    component::NativeComponent
end

struct _PottsSourceInventory
    systems::Vector{_SourceSystemOccurrence}
    statements::Vector{_SourceStatementOccurrence}
    references::Vector{_SourceReferenceOccurrence}
    natives::Vector{_SourceNativeOccurrence}
end

const _SOURCE_TRAVERSAL_WITNESS_KEY = :__potts_source_traversal_witness__

function _record_source_visit(kind::Symbol, path::Tuple, value)
    witness = get(task_local_storage(), _SOURCE_TRAVERSAL_WITNESS_KEY, nothing)
    witness === nothing || witness(kind, path, value)
    return nothing
end

"""Run `f` while recording the declarations discovered by source traversal."""
function _with_source_traversal_witness(f, witness)
    storage = task_local_storage()
    had_previous = haskey(storage, _SOURCE_TRAVERSAL_WITNESS_KEY)
    previous = get(storage, _SOURCE_TRAVERSAL_WITNESS_KEY, nothing)
    storage[_SOURCE_TRAVERSAL_WITNESS_KEY] = witness
    try
        return f()
    finally
        if had_previous
            storage[_SOURCE_TRAVERSAL_WITNESS_KEY] = previous
        else
            delete!(storage, _SOURCE_TRAVERSAL_WITNESS_KEY)
        end
    end
end

function _append_source_references!(references, current, path)
    for (kind, values) in (
            :equation => getfield(current, :eqs),
            :variable => getfield(current, :unknowns),
            :parameter => getfield(current, :ps),
            :independent_variable => getfield(current, :ivs),
            :input => _potts_inputs(current, Val(:local)),
            :output => _potts_outputs(current, Val(:local)),
            :observation => getfield(current, :observed),
            :continuous_event => getfield(current, :continuous_events),
            :discrete_event => getfield(current, :discrete_events),
        )
        for value in values
            push!(references, _SourceReferenceOccurrence(
                kind, path, _defensive_copy(value)
            ))
            _record_source_visit(kind, path, value)
        end
    end
    initial_conditions = sort!(
        collect(getfield(current, :initial_conditions));
        by = pair -> _canonical_value(first(pair)),
    )
    for (key, value) in initial_conditions
        pair = _defensive_copy(key) => _defensive_copy(value)
        push!(references, _SourceReferenceOccurrence(
            :initial_condition, path, pair
        ))
        _record_source_visit(:initial_condition, path, pair)
    end
    return references
end

"""Traverse an authored hierarchy exactly once into the host semantic inventory."""
function _source_inventory(system::PottsSystem)
    systems = _SourceSystemOccurrence[]
    statement_values = _SourceStatementOccurrence[]
    references = _SourceReferenceOccurrence[]
    natives = _SourceNativeOccurrence[]
    source_order = Ref(0)
    function visit(current::PottsSystem, parent::Int32, parent_path::Tuple)
        path = (parent_path..., nameof(current))
        system_index = Int32(length(systems) + 1)
        _record_source_visit(:system, path, current)
        push!(systems, _SourceSystemOccurrence(
            system_index, current, path, parent
        ))
        for statement in statements(current)
            _record_source_visit(:statement, path, statement)
            source_order[] += 1
            push!(statement_values, _SourceStatementOccurrence(
                system_index, path, Int32(source_order[]), statement
            ))
        end
        for component in getfield(current, :native_components)
            component_path = (path..., nameof(component))
            _record_source_visit(:native_component, component_path, component)
            push!(natives, _SourceNativeOccurrence(
                system_index,
                path,
                component_path,
                component,
            ))
        end
        _append_source_references!(references, current, path)
        for child in getfield(current, :systems)
            visit(child, system_index, path)
        end
        return nothing
    end
    visit(system, Int32(0), ())
    return _PottsSourceInventory(systems, statement_values, references, natives)
end

function _inventory_statements(inventory::_PottsSourceInventory)
    return AbstractPottsStatement[
        _namespace_statement(occurrence.statement, occurrence.path)
        for occurrence in inventory.statements
    ]
end

function _inventory_statement_groups(inventory::_PottsSourceInventory)
    groups = [AbstractPottsStatement[] for _ in inventory.systems]
    for occurrence in inventory.statements
        push!(groups[Int(occurrence.system)], occurrence.statement)
    end
    return groups
end

function _inventory_child_indices(inventory::_PottsSourceInventory)
    children = [Int32[] for _ in inventory.systems]
    for occurrence in inventory.systems
        iszero(occurrence.parent) && continue
        push!(children[Int(occurrence.parent)], occurrence.index)
    end
    return children
end

"""
Rebuild a hierarchy and its inventory from already discovered occurrences.

This is the only completion-time hierarchy reconstruction primitive. It does
not rediscover source declarations and deliberately does not emit traversal
witness events.
"""
function _rebuild_source_inventory(
        inventory::_PottsSourceInventory,
        local_systems::AbstractVector{<:PottsSystem},
        statement_groups::AbstractVector,
    )
    count = length(inventory.systems)
    length(local_systems) == count || throw(ArgumentError(
        "source-inventory rebuild requires one local system per occurrence"
    ))
    length(statement_groups) == count || throw(ArgumentError(
        "source-inventory rebuild requires one statement group per occurrence"
    ))
    children = _inventory_child_indices(inventory)
    rebuilt = Vector{PottsSystem}(undef, count)
    for index in count:-1:1
        rebuilt_children = PottsSystem[
            rebuilt[Int(child)] for child in children[index]
        ]
        rebuilt[index] = _rebuild(
            local_systems[index];
            statements = StatementSet(statement_groups[index]),
            systems = rebuilt_children,
        )
    end

    systems = _SourceSystemOccurrence[
        _SourceSystemOccurrence(
            occurrence.index,
            rebuilt[Int(occurrence.index)],
            occurrence.path,
            occurrence.parent,
        ) for occurrence in inventory.systems
    ]
    statement_values = _SourceStatementOccurrence[]
    references = _SourceReferenceOccurrence[]
    natives = _SourceNativeOccurrence[]
    source_order = Int32(0)
    for occurrence in systems
        index = Int(occurrence.index)
        for statement in statement_groups[index]
            source_order += Int32(1)
            push!(statement_values, _SourceStatementOccurrence(
                occurrence.index,
                occurrence.path,
                source_order,
                statement,
            ))
        end
        current = occurrence.system
        for component in getfield(current, :native_components)
            push!(natives, _SourceNativeOccurrence(
                occurrence.index,
                occurrence.path,
                (occurrence.path..., nameof(component)),
                component,
            ))
        end
        # Reification is from known system occurrences, not a source traversal.
        for (kind, values) in (
                :equation => getfield(current, :eqs),
                :variable => getfield(current, :unknowns),
                :parameter => getfield(current, :ps),
                :independent_variable => getfield(current, :ivs),
                :input => _potts_inputs(current, Val(:local)),
                :output => _potts_outputs(current, Val(:local)),
                :observation => getfield(current, :observed),
                :continuous_event => getfield(current, :continuous_events),
                :discrete_event => getfield(current, :discrete_events),
            )
            for value in values
                push!(references, _SourceReferenceOccurrence(
                    kind, occurrence.path, _defensive_copy(value)
                ))
            end
        end
        initial_conditions = sort!(
            collect(getfield(current, :initial_conditions));
            by = pair -> _canonical_value(first(pair)),
        )
        for (key, value) in initial_conditions
            push!(references, _SourceReferenceOccurrence(
                :initial_condition,
                occurrence.path,
                _defensive_copy(key) => _defensive_copy(value),
            ))
        end
    end
    next_inventory = _PottsSourceInventory(
        systems, statement_values, references, natives
    )
    return rebuilt[1], next_inventory
end

function _inventory_path_iswithin(path::Tuple, prefix::Tuple)
    length(path) >= length(prefix) || return false
    return path[1:length(prefix)] == prefix
end

"""Create a rebased subtree view without walking the source hierarchy."""
function _source_subinventory(
        inventory::_PottsSourceInventory, root_index::Integer
    )
    root = inventory.systems[root_index]
    prefix = root.path
    included = filter(
        occurrence -> _inventory_path_iswithin(occurrence.path, prefix),
        inventory.systems,
    )
    old_to_new = Dict(
        occurrence.index => Int32(index)
        for (index, occurrence) in enumerate(included)
    )
    rebase = path -> path[length(prefix):end]
    systems = _SourceSystemOccurrence[
        _SourceSystemOccurrence(
            old_to_new[occurrence.index],
            occurrence.system,
            rebase(occurrence.path),
            occurrence.index == root.index ? Int32(0) :
                old_to_new[occurrence.parent],
        ) for occurrence in included
    ]
    statements = _SourceStatementOccurrence[]
    order = Int32(0)
    for occurrence in inventory.statements
        haskey(old_to_new, occurrence.system) || continue
        order += Int32(1)
        push!(statements, _SourceStatementOccurrence(
            old_to_new[occurrence.system],
            rebase(occurrence.path),
            order,
            occurrence.statement,
        ))
    end
    references = _SourceReferenceOccurrence[
        _SourceReferenceOccurrence(
            occurrence.kind,
            rebase(occurrence.path),
            occurrence.value,
        ) for occurrence in inventory.references
        if _inventory_path_iswithin(occurrence.path, prefix)
    ]
    natives = _SourceNativeOccurrence[
        _SourceNativeOccurrence(
            old_to_new[occurrence.system],
            rebase(occurrence.system_path),
            rebase(occurrence.path),
            occurrence.component,
        ) for occurrence in inventory.natives
        if haskey(old_to_new, occurrence.system)
    ]
    return _PottsSourceInventory(systems, statements, references, natives)
end
