# Normalized, ordered symbolic term DAG construction and verification.

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
    for statement in _all_system_statements(completed)
        statement isa Union{
            SiteState,
            CellState,
            MediumState,
            ModelState,
            FieldState,
            HistoryState,
        } || continue
        arguments = _statement_arguments(statement)
        haskey(arguments, :variable) || continue
        isequal(arguments.variable, value) && return :state
    end
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
    isempty(transfer.serialization_identity) &&
        return "operation serialization identity must be nonempty"
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
        operation = try
            CorePotts.operation_callable(
                Val(transfer.identity), transfer.schema_version
            )
        catch error
            push!(
                diagnostics,
                PottsDiagnostic(
                    :missing_concrete_operation_callable,
                    node.source,
                    string(node.operation),
                    node.source.path,
                    "a concrete public CorePotts operation callable",
                    sprint(showerror, error),
                    (),
                    UnknownSource(),
                ),
            )
            nothing
        end
        operation === nothing || isbits(operation) || push!(
            diagnostics,
            PottsDiagnostic(
                :device_illegal_operation_callable,
                node.source,
                string(node.operation),
                node.source.path,
                "an isbits concrete operation callable",
                string(typeof(operation)),
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
