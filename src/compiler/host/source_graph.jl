# Host-only compiler representation and analysis pipeline.
#
# These tables deliberately erase the concrete type topology of the source
# PottsSystem.  They are compiler data, not an authoring API and never cross
# the CorePotts execution boundary.

struct FrozenSystemNode
    index::Int32
    name::Symbol
    path::Tuple{Vararg{Symbol}}
    parent::Int32
end

struct FrozenSourceNode
    index::Int32
    identity::QualifiedStatementID
    system::Int32
    source_order::Int32
    record::Int32
    kind::Symbol
    references::Vector{Int32}
    provenance::Any
end

struct FrozenSourceReference
    kind::Symbol
    path::Tuple{Vararg{Symbol}}
    source::Int32
    value::Any
end

struct FrozenSourceGraph
    systems::Vector{FrozenSystemNode}
    statements::Vector{FrozenSourceNode}
    records::Vector{QualifiedStatement}
    references::Vector{FrozenSourceReference}
    registry_snapshot::Vector{Any}
    structural_key::String
end

function _state_sample_record(source::FrozenSourceGraph, record::QualifiedStatement)
    return _state_sample_record(source.records, record)
end
function _state_sample_record(records::AbstractVector, record::QualifiedStatement)
    record.kind === :HistoryState || return record
    source_variable = get(_record_options(record), :of, nothing)
    sources = filter(
        candidate -> candidate.identity in record.resources &&
            candidate.kind in (:ModelState, :CellState, :SiteState, :FieldState) &&
            isequal(_state_record_variable(candidate), source_variable), records
    )
    length(sources) == 1 || throw(ArgumentError("history `$(record.identity)` requires exactly one completed source"))
    return only(sources)
end

function _source_graph_reference!(
        references, kind, path, source, value
    )
    push!(
        references,
        FrozenSourceReference(kind, path, Int32(source), value),
    )
    return nothing
end

function _source_graph_context!(references, record_table, source_nodes, context_inventory, context_records)
    known_records = Set(record.identity for record in record_table)
    context_users = Dict{QualifiedStatementID, Int32}()
    pending = Tuple{Int32, QualifiedStatement}[(node.index, record_table[node.record]) for node in source_nodes]
    cursor = 1
    while cursor <= length(pending)
        consumer, record = pending[cursor]
        cursor += 1
        variables = Any[]
        for expression in _collect_symbolics(record.normalized_payload)
            append!(variables, Symbolics.get_variables(expression; is_atomic = _declared_symbolic_atom))
        end
        for reference in context_inventory.references
            reference.kind === :parameter || continue
            canonical = _qualified_source_reference(reference)
            any(value -> isequal(value, canonical), variables) || continue
            any(item -> item.kind === :parameter && isequal(_qualified_source_reference(item), canonical), references) && continue
            # A statement use retains the original qualified owner. Source zero
            # remains reserved for declarations in this inventory projection.
            _source_graph_reference!(references, :parameter, reference.path, consumer, reference.value)
        end
        for candidate in context_records
            candidate.identity in known_records && continue
            variable = _state_record_variable(candidate)
            variable === nothing && continue
            candidate.identity in record.resources || any(value -> isequal(value, variable), variables) || continue
            push!(known_records, candidate.identity)
            context_users[candidate.identity] = consumer
            push!(record_table, candidate)
            # Reading stored state needs its declaration, not its producer's
            # evolution coefficients. History additionally depends on its source.
            candidate.kind === :HistoryState && push!(pending, (consumer, candidate))
        end
    end
    if !isempty(context_users)
        owned_initials = filter(reference -> reference.kind === :initial_condition, references)
        filter!(reference -> reference.kind !== :initial_condition, references)
        # Rebuild only initial-reference ordering from the enclosing authority;
        # an imported field must see the same parent-first initial as its owner.
        for reference in context_inventory.references
            reference.kind === :initial_condition || continue
            owned = findfirst(item -> item.path == reference.path && isequal(item.value, reference.value), owned_initials)
            if owned !== nothing
                push!(references, owned_initials[owned])
                continue
            end
            variable = first(_qualified_source_reference(reference))
            dependency = findfirst(
                record -> haskey(context_users, record.identity) &&
                    isequal(_state_record_variable(record), variable), record_table
            )
            dependency === nothing && continue
            consumer = context_users[record_table[dependency].identity]
            _source_graph_reference!(references, :initial_condition, reference.path, consumer, reference.value)
        end
    end
    return nothing
end

function _validate_runtime_ownership(source::FrozenSourceGraph)
    owned_records = Set(node.record for node in source.statements)
    missing = String[
        string(record.identity) for (index, record) in enumerate(source.records)
            if !(index in owned_records)
    ]
    for reference in source.references
        reference.kind === :parameter && reference.source > 0 || continue
        canonical = _qualified_source_reference(reference)
        any(
            item -> item.kind === :parameter && item.source == 0 &&
                isequal(_qualified_source_reference(item), canonical), source.references
        ) && continue
        push!(missing, string(join(reference.path, "₊"), "₊", _scheduled_symbolic_name(reference.value)))
    end
    isempty(missing) || throw(
        ArgumentError(
            "runtime materialization is missing enclosing-owned declarations: " *
                join(sort!(unique(missing)), ", ") *
                "; materialize the enclosing system or explicitly recompose the source with those owners"
        )
    )
    return nothing
end

function _freeze_source_graph(
        inventory::_PottsSourceInventory,
        records,
        registry::StatementRegistry,
        ; context_inventory = inventory, context_records = records,
    )
    systems = FrozenSystemNode[]
    source_nodes = FrozenSourceNode[]
    references = FrozenSourceReference[]
    record_table = QualifiedStatement[record for record in records]
    record_indices = Dict(
        record.identity => Int32(index)
        for (index, record) in enumerate(record_table)
    )
    source_indices = Dict{QualifiedStatementID, Int32}()

    for occurrence in inventory.systems
        push!(
            systems,
            FrozenSystemNode(
                occurrence.index,
                nameof(occurrence.system),
                occurrence.path,
                occurrence.parent,
            ),
        )
    end
    for occurrence in inventory.statements
        identity = QualifiedStatementID(
            occurrence.path, statement_id(occurrence.statement)
        )
        record_index = get(record_indices, identity, Int32(0))
        record_index == 0 && error(
            "completed statement $identity is absent from its qualified record table"
        )
        record = record_table[record_index]
        node_index = Int32(length(source_nodes) + 1)
        source_indices[identity] = node_index
        push!(
            source_nodes,
            FrozenSourceNode(
                node_index,
                identity,
                occurrence.system,
                occurrence.source_order,
                record_index,
                record.kind,
                Int32[],
                record.provenance,
            ),
        )
    end
    for occurrence in inventory.references
        _source_graph_reference!(
            references,
            occurrence.kind,
            occurrence.path,
            0,
            occurrence.value,
        )
    end
    for index in eachindex(source_nodes)
        node = source_nodes[index]
        record = record_table[node.record]
        resolved = Int32[]
        for identity in record.resources
            haskey(source_indices, identity) || continue
            candidate = source_indices[identity]
            candidate in resolved || push!(resolved, candidate)
        end
        sort!(resolved)
        source_nodes[index] = FrozenSourceNode(
            node.index,
            node.identity,
            node.system,
            node.source_order,
            node.record,
            node.kind,
            resolved,
            node.provenance,
        )
        if node.kind === :SpatialRelation
            _source_graph_reference!(
                references, :relation, node.identity.path, node.index, node.identity
            )
        elseif node.kind in (
                :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
                :HistoryState, :RelationshipState,
            )
            _source_graph_reference!(
                references, :state, node.identity.path, node.index, node.identity
            )
        elseif node.kind === :Observation
            _source_graph_reference!(
                references, :observation, node.identity.path, node.index, node.identity
            )
        elseif node.kind === :Protocol
            _source_graph_reference!(
                references, :protocol, node.identity.path, node.index, node.identity
            )
        end
    end
    inventory.systems[1].path == context_inventory.systems[1].path ||
        _source_graph_context!(references, record_table, source_nodes, context_inventory, context_records)
    registry_snapshot = Any[
        (
            schema = definition.schema,
            version = definition.version,
            contract = definition.contract,
        )
        for definition in registry.definitions
    ]
    structural_key = _sha256_hex(
        "potts-frozen-source-graph-v1",
        Tuple((node.path, node.parent) for node in systems),
        Tuple((
            node.identity,
            node.source_order,
            node.kind,
            Tuple(node.references),
            node.provenance,
        ) for node in source_nodes),
        Tuple((item.kind, item.path, item.source, item.value) for item in references),
        Tuple(registry_snapshot),
    )
    if length(record_table) > length(records)
        dependencies = view(record_table, (length(records) + 1):length(record_table))
        structural_key = _sha256_hex(
            "potts-contextual-source-graph-v1", structural_key,
            Tuple((_semantic_record_payload(record), _completed_record_summary(record)) for record in dependencies),
        )
    end
    return FrozenSourceGraph(
        systems,
        source_nodes,
        record_table,
        references,
        registry_snapshot,
        structural_key,
    )
end
