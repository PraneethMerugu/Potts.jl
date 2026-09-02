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

function _source_graph_reference!(
        references, kind, path, source, value
    )
    push!(
        references,
        FrozenSourceReference(kind, path, Int32(source), value),
    )
    return nothing
end

function _freeze_source_graph(
        inventory::_PottsSourceInventory,
        records,
        registry::StatementRegistry,
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
    return FrozenSourceGraph(
        systems,
        source_nodes,
        record_table,
        references,
        registry_snapshot,
        structural_key,
    )
end
