# Host-only compiler representation.
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
        system::PottsSystem,
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
    source_order = Ref(0)

    function visit(current::PottsSystem, parent::Int32, parent_path::Tuple)
        path = (parent_path..., nameof(current))
        system_index = Int32(length(systems) + 1)
        push!(
            systems,
            FrozenSystemNode(system_index, nameof(current), path, parent),
        )
        for statement in statements(current)
            source_order[] += 1
            identity = QualifiedStatementID(path, statement_id(statement))
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
                    system_index,
                    Int32(source_order[]),
                    record_index,
                    record.kind,
                    Int32[],
                    record.provenance,
                ),
            )
        end
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
                _source_graph_reference!(
                    references, kind, path, 0, _defensive_copy(value)
                )
            end
        end
        for child in getfield(current, :systems)
            visit(child, system_index, path)
        end
        return nothing
    end

    visit(system, Int32(0), ())
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

struct OperationTransfer
    identity::Symbol
    schema_version::VersionNumber
    arity::UnitRange{Int}
    result_rule::Symbol
    unit_rule::Symbol
    purity::Symbol
    totality::Symbol
    locality::Symbol
    cpu::Bool
    gpu::Bool
end

function operation_transfer end

_transfer(identity, arity, result_rule, unit_rule;
        purity = :pure,
        totality = :total,
        locality = :scalar,
        cpu = true,
        gpu = true,
    ) = OperationTransfer(
        identity,
        v"1.0.0",
        arity isa Integer ? (Int(arity):Int(arity)) : arity,
        result_rule,
        unit_rule,
        purity,
        totality,
        locality,
        cpu,
        gpu,
    )

for operation in (+, -, *, /, ^, max, min)
    identity = if operation === (+)
        :add
    elseif operation === (-)
        :subtract
    elseif operation === (*)
        :multiply
    elseif operation === (/)
        :divide
    elseif operation === (^)
        :power
    elseif operation === max
        :maximum
    else
        :minimum
    end
    @eval operation_transfer(::typeof($operation), arity::Int) =
        _transfer($(QuoteNode(identity)), arity == 1 ? 1 : (2:typemax(Int)),
            :promote_numeric, :arithmetic)
end

for operation in (<, <=, >, >=, ==, !=)
    identity = if operation === (<)
        :less
    elseif operation === (<=)
        :less_equal
    elseif operation === (>)
        :greater
    elseif operation === (>=)
        :greater_equal
    elseif operation === (==)
        :equal
    else
        :not_equal
    end
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer($(QuoteNode(identity)), 2, :boolean, :comparison)
end

operation_transfer(::typeof(&), ::Int) =
    _transfer(:and, 2, :boolean, :dimensionless)
operation_transfer(::typeof(|), ::Int) =
    _transfer(:or, 2, :boolean, :dimensionless)
operation_transfer(::typeof(!), ::Int) =
    _transfer(:not, 1, :boolean, :dimensionless)
operation_transfer(::typeof(ifelse), ::Int) =
    _transfer(:ifelse, 3, :branch_promote, :branch)

for operation in (abs, exp, log, sqrt)
    identity = if operation === abs
        :absolute
    elseif operation === exp
        :exponential
    elseif operation === log
        :logarithm
    else
        :square_root
    end
    unit_rule = operation in (exp, log) ? :dimensionless : :unary
    totality = operation in (log, sqrt) ? :domain_checked : :total
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)),
            1,
            :preserve_numeric,
            $(QuoteNode(unit_rule));
            totality = $(QuoteNode(totality)),
        )
end

for operation in (
        source_site, target_site, source_cell, target_cell, source_kind,
        target_kind,
    )
    identity = nameof(operation)
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 1, :integer, :dimensionless;
            locality = :proposal_context,
        )
end

for operation in (is_extension, is_retraction, new_contact, lost_contact, linked)
    identity = nameof(operation)
    arity = operation === linked ? 3 : operation in (new_contact, lost_contact) ? 2 : 1
    locality = operation === linked ? :bounded_relationship : :proposal_context
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), $arity, :boolean, :dimensionless;
            locality = $(QuoteNode(locality)),
        )
end

for operation in (
        cell_volume, cell_surface, cell_center, unwrapped_center, endpoint_a,
        endpoint_b, degree,
    )
    identity = nameof(operation)
    result_rule = operation in (endpoint_a, endpoint_b, degree) ? :integer : :real
    locality = operation in (endpoint_a, endpoint_b, degree) ?
               :bounded_relationship : :owner_local
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 1, $(QuoteNode(result_rule)), :declared;
            locality = $(QuoteNode(locality)),
        )
end

for operation in (
        distance, contact_measure, boundary_measure, neighbor_count, neighbor_sum,
        neighbor_mean, neighbor_geomean, field_value, field_gradient, laplacian,
        occupancy, history_value, edge_payload, lag,
    )
    identity = nameof(operation)
    result_rule = operation === neighbor_count ? :integer : :real
    locality = operation in (edge_payload, lag) ?
               :bounded_relationship : :finite_spatial
    @eval operation_transfer(::typeof($operation), ::Int) =
        _transfer(
            $(QuoteNode(identity)), 2, $(QuoteNode(result_rule)), :declared;
            locality = $(QuoteNode(locality)),
        )
end

operation_transfer(::typeof(_potts_draw), ::Int) =
    _transfer(
        :draw, 4, :real, :distribution;
        purity = :semantic_rng,
        locality = :proposal_context,
    )

struct NormalizedTermNode
    identity::Int32
    operation::Symbol
    schema_version::VersionNumber
    operands::Vector{Int32}
    payload_kind::Symbol
    payload::Any
    transfer::Union{Nothing, OperationTransfer}
    structural_key::String
    record::Int32
    source::QualifiedStatementID
end

struct NormalizedTermRoot
    record::Int32
    role::Symbol
    node::Int32
end

struct NormalizedTermGraph
    nodes::Vector{NormalizedTermNode}
    roots::Vector{NormalizedTermRoot}
    structural_key::String
end

mutable struct _TermGraphBuilder
    nodes::Vector{NormalizedTermNode}
    interned::Dict{String, Int32}
    diagnostics::Vector{PottsDiagnostic}
end

function _compiler_leaf_kind(value, completed::PottsSystem)
    parameters = ModelingToolkitBase.parameters(completed)
    any(candidate -> isequal(candidate, value), parameters) && return :parameter
    unknowns = ModelingToolkitBase.unknowns(completed)
    any(candidate -> isequal(candidate, value), unknowns) && return :variable
    name = _try_symbolic_name(value)
    name === nothing && return :literal
    text = String(name)
    startswith(text, "__potts_proposal__") && return :proposal_context
    startswith(text, "__potts_relationship__") && return :relationship_context
    startswith(text, "__potts_relationship_set__") && return :relation
    startswith(text, "__potts_kind__") && return :kind
    startswith(text, "__potts_field__") && return :state
    startswith(text, "__potts_payload__") && return :relationship_payload
    return :symbolic_leaf
end

function _compiler_literal(value)
    unwrapped = try
        Symbolics.unwrap(value)
    catch
        value
    end
    return try
        Symbolics.value(unwrapped)
    catch
        value
    end
end

function _push_term_node!(
        builder::_TermGraphBuilder,
        operation::Symbol,
        version::VersionNumber,
        operands::Vector{Int32},
        payload_kind::Symbol,
        payload,
        transfer::Union{Nothing, OperationTransfer},
        record::Int32,
        source::QualifiedStatementID;
        intern::Bool,
    )
    operand_keys = Tuple(builder.nodes[index].structural_key for index in operands)
    key = _sha256_hex(
        "potts-normalized-term-node-v1",
        operation,
        version,
        operand_keys,
        payload_kind,
        payload_kind === :literal ? repr(payload) : _try_symbolic_name(payload),
    )
    intern_key = _sha256_hex("potts-term-intern-v1", record, key)
    intern && haskey(builder.interned, intern_key) &&
        return builder.interned[intern_key]
    index = Int32(length(builder.nodes) + 1)
    push!(
        builder.nodes,
        NormalizedTermNode(
            index,
            operation,
            version,
            operands,
            payload_kind,
            payload,
            transfer,
            key,
            record,
            source,
        ),
    )
    intern && (builder.interned[intern_key] = index)
    return index
end

function _normalize_term!(
        builder::_TermGraphBuilder,
        value,
        completed::PottsSystem,
        record::Int32,
        source::QualifiedStatementID,
)
    classified = _compiler_leaf_kind(value, completed)
    if classified in (
            :parameter,
            :variable,
            :state,
            :proposal_context,
            :relationship_context,
            :relation,
            :kind,
            :relationship_payload,
        )
        return _push_term_node!(
            builder,
            classified,
            v"1.0.0",
            Int32[],
            classified,
            value,
            nothing,
            record,
            source;
            intern = true,
        )
    end
    unwrapped = try
        Symbolics.unwrap(value)
    catch
        value
    end
    is_call = try
        Symbolics.iscall(unwrapped)
    catch
        false
    end
    if !is_call
        kind = classified
        literal = kind === :literal ? _compiler_literal(value) : value
        return _push_term_node!(
            builder,
            kind,
            v"1.0.0",
            Int32[],
            kind,
            literal,
            nothing,
            record,
            source;
            intern = true,
        )
    end

    operation = Symbolics.operation(unwrapped)
    arguments = Tuple(Symbolics.arguments(unwrapped))
    transfer = try
        operation_transfer(operation, length(arguments))
    catch error
        if error isa MethodError && error.f === operation_transfer
            nothing
        else
            rethrow(error)
        end
    end
    if transfer === nothing
        push!(
            builder.diagnostics,
            PottsDiagnostic(
                :missing_operation_transfer,
                source,
                repr(value),
                source.path,
                "a versioned operation transfer rule",
                repr(operation),
                (),
                UnknownSource(),
            ),
        )
        return Int32(0)
    elseif !(length(arguments) in transfer.arity)
        push!(
            builder.diagnostics,
            PottsDiagnostic(
                :invalid_operation_arity,
                source,
                repr(value),
                source.path,
                string(transfer.arity),
                string(length(arguments)),
                (),
                UnknownSource(),
            ),
        )
        return Int32(0)
    end
    operands = Int32[
        _normalize_term!(
            builder, argument, completed, record, source
        )
        for argument in arguments
    ]
    any(iszero, operands) && return Int32(0)
    return _push_term_node!(
        builder,
        transfer.identity,
        transfer.schema_version,
        operands,
        :operation,
        nothing,
        transfer,
        record,
        source;
        intern = transfer.purity === :pure,
    )
end

const _RESULT_TRANSFER_RULES = Set((
    :promote_numeric,
    :boolean,
    :branch_promote,
    :preserve_numeric,
    :integer,
    :real,
))
const _UNIT_TRANSFER_RULES = Set((
    :arithmetic,
    :comparison,
    :dimensionless,
    :branch,
    :unary,
    :declared,
    :distribution,
))
const _PURITY_TRANSFER_RULES = Set((:pure, :semantic_rng))
const _TOTALITY_TRANSFER_RULES = Set((
    :total, :domain_checked, :requires_prelaunch_validation
))
const _LOCALITY_TRANSFER_RULES = Set((
    :scalar,
    :proposal_context,
    :owner_local,
    :finite_spatial,
    :bounded_relationship,
))

function _operation_transfer_error(transfer::OperationTransfer, arity::Int)
    isempty(String(transfer.identity)) &&
        return "operation identity must be nonempty"
    transfer.schema_version > v"0.0.0" ||
        return "operation schema version must be positive"
    arity in transfer.arity ||
        return "arity $arity is outside $(transfer.arity)"
    transfer.result_rule in _RESULT_TRANSFER_RULES ||
        return "unknown result transfer rule $(transfer.result_rule)"
    transfer.unit_rule in _UNIT_TRANSFER_RULES ||
        return "unknown unit transfer rule $(transfer.unit_rule)"
    transfer.purity in _PURITY_TRANSFER_RULES ||
        return "unknown purity transfer rule $(transfer.purity)"
    transfer.totality in _TOTALITY_TRANSFER_RULES ||
        return "unknown totality transfer rule $(transfer.totality)"
    transfer.locality in _LOCALITY_TRANSFER_RULES ||
        return "unknown locality transfer rule $(transfer.locality)"
    transfer.cpu ||
        return "V1 operations must admit the CPU reference backend"
    return nothing
end

function _verify_normalized_graph!(
        diagnostics,
        graph::NormalizedTermGraph,
    )
    for (expected, node) in enumerate(graph.nodes)
        node.identity == expected || push!(
            diagnostics,
            PottsDiagnostic(
                :noncanonical_term_identity,
                node.source,
                string(node.operation),
                node.source.path,
                string(expected),
                string(node.identity),
                (),
                UnknownSource(),
            ),
        )
        all(operand -> 0 < operand < node.identity, node.operands) || push!(
            diagnostics,
            PottsDiagnostic(
                :invalid_term_dag_edge,
                node.source,
                string(node.operation),
                node.source.path,
                "operands defined before their consumer",
                repr(node.operands),
                (),
                UnknownSource(),
            ),
        )
        node.payload_kind === :operation || continue
        transfer = node.transfer
        if transfer === nothing
            push!(
                diagnostics,
                PottsDiagnostic(
                    :missing_normalized_transfer,
                    node.source,
                    string(node.operation),
                    node.source.path,
                    "a frozen operation transfer",
                    "nothing",
                    (),
                    UnknownSource(),
                ),
            )
            continue
        end
        reason = _operation_transfer_error(transfer, length(node.operands))
        reason === nothing || push!(
            diagnostics,
            PottsDiagnostic(
                :invalid_operation_transfer,
                node.source,
                string(node.operation),
                node.source.path,
                "a valid frozen operation transfer",
                reason,
                (),
                UnknownSource(),
            ),
        )
        transfer.identity === node.operation || push!(
            diagnostics,
            PottsDiagnostic(
                :operation_identity_transfer_mismatch,
                node.source,
                string(node.operation),
                node.source.path,
                String(node.operation),
                String(transfer.identity),
                (),
                UnknownSource(),
            ),
        )
        transfer.schema_version == node.schema_version || push!(
            diagnostics,
            PottsDiagnostic(
                :operation_version_transfer_mismatch,
                node.source,
                string(node.operation),
                node.source.path,
                string(node.schema_version),
                string(transfer.schema_version),
                (),
                UnknownSource(),
            ),
        )
    end
    for root in graph.roots
        0 < root.node <= length(graph.nodes) || push!(
            diagnostics,
            PottsDiagnostic(
                :invalid_term_root,
                QualifiedStatementID((), StatementID(:compiler)),
                string(root.role),
                (),
                "a node in the normalized graph",
                string(root.node),
                (),
                UnknownSource(),
            ),
        )
    end
    return diagnostics
end

function _record_expression_roots(record::QualifiedStatement)
    arguments = first(record.normalized_payload)
    roots = Pair{Symbol, Any}[]
    arguments isa NamedTuple || return roots
    haskey(arguments, :expression) && arguments.expression !== nothing &&
        push!(roots, :expression => arguments.expression)
    if haskey(arguments, :equations)
        for (index, equation) in enumerate(arguments.equations)
            push!(roots, Symbol(:equation_, index) => equation)
        end
    end
    if haskey(arguments, :effects)
        for (effect_index, effect) in enumerate(arguments.effects)
            for field in fieldnames(typeof(effect))
                value = getfield(effect, field)
                isempty(try
                    Symbolics.get_variables(value)
                catch
                    ()
                end) && continue
                push!(
                    roots,
                    Symbol(:effect_, effect_index, :_, field) => value,
                )
            end
        end
    end
    return roots
end

function _normalize_source_graph(
        graph::FrozenSourceGraph,
        completed::PottsSystem,
    )
    builder = _TermGraphBuilder(
        NormalizedTermNode[],
        Dict{String, Int32}(),
        PottsDiagnostic[],
    )
    roots = NormalizedTermRoot[]
    for source_node in graph.statements
        record = graph.records[source_node.record]
        for (role, value) in _record_expression_roots(record)
            node = _normalize_term!(
                builder,
                value,
                completed,
                source_node.record,
                source_node.identity,
            )
            iszero(node) || push!(
                roots,
                NormalizedTermRoot(source_node.record, role, node),
            )
        end
    end
    _throw_diagnostics(:normalization, builder.diagnostics)
    key = _sha256_hex(
        "potts-normalized-term-graph-v1",
        graph.structural_key,
        Tuple((
            node.operation,
            node.schema_version,
            Tuple(node.operands),
            node.payload_kind,
            node.structural_key,
        ) for node in builder.nodes),
        Tuple((root.record, root.role, root.node) for root in roots),
    )
    graph = NormalizedTermGraph(builder.nodes, roots, key)
    diagnostics = PottsDiagnostic[]
    _verify_normalized_graph!(diagnostics, graph)
    _throw_diagnostics(:analysis, diagnostics)
    return graph
end

struct AnalyzedFactTable
    result_type::Vector{Any}
    shape::Vector{Any}
    units::Vector{Any}
    parameter_role::Vector{Symbol}
    purity::Vector{Symbol}
    totality::Vector{Symbol}
    reads::Vector{Any}
    writes::Vector{Any}
    locality::Vector{Symbol}
    affected_region::Vector{Any}
    effect::Vector{Any}
    emission_bound::Vector{EffectBound}
    scientific_category::Vector{Symbol}
    stage::Vector{Any}
    dependencies::Vector{Any}
    rng_sites::Vector{Any}
    state_participation::Vector{Bool}
    workspace_participation::Vector{Bool}
    adaptation_participation::Vector{Bool}
    checkpoint_participation::Vector{Bool}
    engine_admission::Vector{Any}
    backend_admission::Vector{Any}
    source_chain::Vector{Any}
end

struct DescriptorCandidate
    source::QualifiedStatementID
    record::Int32
    category::Symbol
    roots::Vector{Int32}
    structural_key::String
    provenance::Any
end

struct AnalyzedTermIR
    source::FrozenSourceGraph
    graph::NormalizedTermGraph
    facts::AnalyzedFactTable
    candidates::Vector{DescriptorCandidate}
    structural_key::String
end

_join_locality(values) =
    :bounded_relationship in values ? :bounded_relationship :
    :finite_spatial in values ? :finite_spatial :
    :owner_local in values ? :owner_local :
    :proposal_context in values ? :proposal_context : :scalar

function _analyze_term_graph(
        source::FrozenSourceGraph,
        graph::NormalizedTermGraph,
    )
    count = length(graph.nodes)
    result_type = Any[Any for _ in 1:count]
    shape = Any[() for _ in 1:count]
    units = Any[:unknown for _ in 1:count]
    parameter_role = fill(:none, count)
    purity = fill(:pure, count)
    totality = fill(:total, count)
    reads = Any[() for _ in 1:count]
    writes = Any[() for _ in 1:count]
    locality = fill(:scalar, count)
    affected_region = Any[() for _ in 1:count]
    effect = Any[PureRead() for _ in 1:count]
    emission_bound = EffectBound[EffectBound(0, :read_only) for _ in 1:count]
    scientific_category = fill(:expression, count)
    stage = Any[nothing for _ in 1:count]
    dependencies = Any[() for _ in 1:count]
    rng_sites = Any[() for _ in 1:count]
    state_participation = falses(count)
    workspace_participation = falses(count)
    adaptation_participation = falses(count)
    checkpoint_participation = falses(count)
    engine_admission = Any[() for _ in 1:count]
    backend_admission = Any[() for _ in 1:count]
    source_chain = Any[() for _ in 1:count]

    for node in graph.nodes
        index = Int(node.identity)
        record = source.records[node.record]
        operand_indices = Int.(node.operands)
        operand_locality = Symbol[locality[item] for item in operand_indices]
        transfer = node.transfer
        result_type[index] = if node.payload_kind === :literal
            typeof(node.payload)
        elseif node.payload_kind in (:parameter, :variable, :state, :symbolic_leaf)
            record.result_type === Nothing ? Real : record.result_type
        elseif node.payload_kind in (
                :proposal_context, :relationship_context, :relation, :kind,
                :relationship_payload,
            )
            Real
        elseif transfer.result_rule === :boolean
            Bool
        elseif transfer.result_rule === :integer
            Int
        elseif transfer.result_rule === :branch_promote && length(operand_indices) == 3
            promote_type(
                result_type[operand_indices[2]],
                result_type[operand_indices[3]],
            )
        elseif transfer.result_rule in (:preserve_numeric, :promote_numeric) &&
                !isempty(operand_indices)
            promote_type((result_type[item] for item in operand_indices)...)
        else
            Real
        end
        units[index] = isempty(record.units) ? :dimensionless : record.units
        parameter_role[index] = node.payload_kind === :parameter ? :runtime :
                                node.payload_kind === :literal ? :literal : :none
        purity[index] = transfer === nothing ? :pure : transfer.purity
        totality[index] = transfer === nothing ? :total : transfer.totality
        reads[index] = record.reads
        writes[index] = record.writes
        locality[index] = transfer === nothing ?
                          _join_locality(operand_locality) :
                          _join_locality((
                              operand_locality..., transfer.locality
                          ))
        affected_region[index] = (
            locality = locality[index],
            resources = record.resources,
            bound = record.bound,
        )
        effect[index] = record.effect
        emission_bound[index] = record.bound
        scientific_category[index] = if record.kind in (
                :ProposalEnergy, :ProposalDrive, :ProposalConstraint,
                :ProposalModifier,
            )
            :proposal
        elseif record.kind in (
                :RelationshipProcess, :LifecycleProcess, :RelationshipState,
            )
            :relationship
        elseif record.kind in (
                :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
                :HistoryState,
            )
            :state
        elseif record.kind === :Observation
            :observation
        else
            :process
        end
        stage[index] = record.phase
        dependencies[index] = record.ordering_dependencies
        rng_sites[index] = record.random_operations
        state_participation[index] = record.persistence === :logical ||
                                     !isempty(record.reads) ||
                                     !isempty(record.writes)
        workspace_participation[index] = !(record.effect isa PureRead) ||
                                         locality[index] !== :scalar
        adaptation_participation[index] =
            state_participation[index] || workspace_participation[index]
        checkpoint_participation[index] = record.persistence === :logical
        engine_admission[index] = record.engine_admission
        backend_admission[index] = (
            cpu = transfer === nothing ? true : transfer.cpu,
            gpu = transfer === nothing ? true : transfer.gpu,
            reason = transfer !== nothing && !transfer.gpu ?
                     "operation $(transfer.identity) rejects GPU execution" : "",
        )
        source_chain[index] = (
            identity = record.identity,
            source = record.source,
            provenance = record.provenance,
        )
    end

    facts = AnalyzedFactTable(
        result_type,
        shape,
        units,
        parameter_role,
        purity,
        totality,
        reads,
        writes,
        locality,
        affected_region,
        effect,
        emission_bound,
        scientific_category,
        stage,
        dependencies,
        rng_sites,
        state_participation,
        workspace_participation,
        adaptation_participation,
        checkpoint_participation,
        engine_admission,
        backend_admission,
        source_chain,
    )
    candidates = DescriptorCandidate[]
    roots_by_record = Dict{Int32, Vector{Int32}}()
    for root in graph.roots
        push!(get!(roots_by_record, root.record, Int32[]), root.node)
    end
    for (record_index, roots) in sort!(
            collect(roots_by_record); by = first
        )
        record = source.records[record_index]
        category = scientific_category[Int(first(roots))]
        push!(
            candidates,
            DescriptorCandidate(
                record.identity,
                record_index,
                category,
                roots,
                _sha256_hex(
                    "potts-descriptor-candidate-v1",
                    record.lowering_identity,
                    Tuple(graph.nodes[root].structural_key for root in roots),
                    category,
                ),
                record.provenance,
            ),
        )
    end
    key = _sha256_hex(
        "potts-analyzed-term-ir-v1",
        graph.structural_key,
        Tuple((
            result_type[index],
            shape[index],
            units[index],
            parameter_role[index],
            purity[index],
            totality[index],
            locality[index],
            emission_bound[index].maximum,
            emission_bound[index].basis,
            scientific_category[index],
            backend_admission[index],
        ) for index in eachindex(graph.nodes)),
        Tuple(candidate.structural_key for candidate in candidates),
    )
    return AnalyzedTermIR(source, graph, facts, candidates, key)
end

function _analyze_completed_system(completed::PottsSystem)
    data = _completion_data(completed)
    graph = _normalize_source_graph(data.source_graph, completed)
    return _analyze_term_graph(data.source_graph, graph)
end

function _compiler_analysis_report(ir::AnalyzedTermIR)
    return (
        source_graph = (
            systems = length(ir.source.systems),
            statements = length(ir.source.statements),
            references = length(ir.source.references),
            structural_key = ir.source.structural_key,
        ),
        normalized = (
            nodes = length(ir.graph.nodes),
            roots = length(ir.graph.roots),
            structural_key = ir.graph.structural_key,
        ),
        analyzed = (
            candidates = length(ir.candidates),
            structural_key = ir.structural_key,
            candidate_keys =
                Tuple(candidate.structural_key for candidate in ir.candidates),
        ),
    )
end
