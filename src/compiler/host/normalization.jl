# Ordered DAG construction from resolved normalized payloads.

function _push_term_node!(
        builder::_TermGraphBuilder,
        operation::Symbol,
        version::VersionNumber,
        operands::Vector{Int32},
        payload_kind::Symbol,
        payload,
        transfer::Union{Nothing, OperationTransfer},
        callable,
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
        _normalized_payload_key(payload),
        transfer === nothing ? nothing : (
                transfer.serialization_identity,
                transfer.footprint_rule,
                transfer.tracker_requirements,
                transfer.lifecycle_abi,
            ),
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
            callable,
            key,
            record,
            source,
        ),
    )
    intern && (builder.interned[intern_key] = index)
    return index
end

function _insert_operation_schema!(snapshot, schema::FrozenOperationSchema, record::QualifiedStatement)
    existing = findfirst(
        candidate -> candidate.transfer.identity === schema.transfer.identity &&
            candidate.transfer.schema_version == schema.transfer.schema_version,
        snapshot,
    )
    if existing === nothing
        push!(snapshot, schema)
        return snapshot
    end
    previous = snapshot[existing]
    if _canonical_value(previous.transfer) != _canonical_value(schema.transfer) ||
            !isequal(previous.callable, schema.callable)
        throw(
            PottsValidationError(
                :normalization, (
                    PottsDiagnostic(
                        :conflicting_operation_schema, record.identity, String(schema.transfer.identity), record.identity.path,
                        "one consistent transfer and callable for operation identity/version",
                        "conflicting scientific or execution contracts", (), record.source,
                    ),
                )
            )
        )
    end
    if previous.surface_operation === nothing && schema.surface_operation !== nothing
        snapshot[existing] = schema
    end
    return snapshot
end

Base.@noinline function _fixed_vector_literal_arguments(operation, arguments::Tuple)
    operation isa Function || return nothing
    nameof(operation) === :array_literal || return nothing
    parentmodule(operation) === SymbolicUtils || return nothing
    isempty(arguments) && return nothing
    shape = SymbolicUtils.unwrap_const(first(arguments))
    shape isa Tuple{<:Integer} || return nothing
    only(shape) == length(arguments) - 1 || return nothing
    return Base.tail(arguments)
end

function _normalize_term!(
        builder::_TermGraphBuilder,
        value,
        source_graph::FrozenSourceGraph,
        record::Int32,
        source::QualifiedStatementID,
    )
    classified = _compiler_leaf_kind(value, source_graph)
    if classified in (
            :parameter,
            :variable,
            :state,
            :proposal_context,
            :site_anchor,
            :cell_anchor,
            :contact_anchor,
            :relationship_context,
            :relationship_set,
            :spatial_relation,
            :kind,
            :relationship_payload,
            :draw,
        )
        record_value = source_graph.records[Int(record)]
        payload = _resolve_normalized_payload(
            classified, value, source_graph, record_value
        )
        if payload === nothing
            push!(
                builder.diagnostics,
                PottsDiagnostic(
                    :unresolved_symbolic_leaf,
                    source,
                    repr(value),
                    source.path,
                    "a qualified normalized binding payload",
                    string(classified, " ", repr(value)),
                    (),
                    record_value.source,
                ),
            )
            return Int32(0)
        end
        return _push_term_node!(
            builder,
            classified,
            v"1.0.0",
            Int32[],
            classified,
            payload,
            nothing,
            _normalized_leaf_callable(classified, v"1.0.0"),
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
    symbolic_operation = is_call ? Symbolics.operation(unwrapped) : nothing
    symbolic_arguments = is_call ? Tuple(Symbolics.arguments(unwrapped)) : ()
    array_literal_arguments =
        _fixed_vector_literal_arguments(symbolic_operation, symbolic_arguments)
    fixed_vector = value isa StaticArrays.SVector || array_literal_arguments !== nothing
    if !is_call && !fixed_vector
        kind = classified
        payload = _resolve_normalized_payload(
            kind,
            value,
            source_graph,
            source_graph.records[Int(record)],
        )
        if payload === nothing
            record_value = source_graph.records[Int(record)]
            push!(
                builder.diagnostics,
                PottsDiagnostic(
                    :unresolved_symbolic_leaf,
                    source,
                    repr(value),
                    source.path,
                    "a literal or qualified normalized binding payload",
                    "unresolved symbolic leaf",
                    (),
                    record_value.source,
                ),
            )
            return Int32(0)
        end
        normalized_kind = _normalized_payload_kind(payload)
        return _push_term_node!(
            builder,
            normalized_kind,
            v"1.0.0",
            Int32[],
            normalized_kind,
            payload,
            nothing,
            nothing,
            record,
            source;
            intern = true,
        )
    end

    # A materialized immutable vector is syntax for one logical construction,
    # not a literal containing unevaluated symbolic element expressions.
    operation = fixed_vector ? StaticArrays.SVector : symbolic_operation
    arguments = value isa StaticArrays.SVector ? Tuple(value) :
        array_literal_arguments === nothing ? symbolic_arguments : array_literal_arguments
    if operation isa _ProductField
        # Field spelling is source syntax. The closed evaluator receives one
        # ordinary product-field operation and a declaration-derived ordinal.
        source_type, field = typeof(operation).parameters
        ordinal = findfirst(==(field), fieldnames(source_type))
        ordinal === nothing && throw(ArgumentError("unknown declared product field `$field`"))
        arguments = (only(arguments), ordinal)
    end
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
                (
                    "Express this function using supported Julia operations.",
                    "For an opaque operation, define its public Potts.operation_transfer " *
                        "and CorePotts.CompilerSPI.operation_callable bindings.",
                ),
                source_graph.records[Int(record)].source,
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
                source_graph.records[Int(record)].source,
            ),
        )
        return Int32(0)
    end
    operands = Int32[
        _normalize_term!(
                builder, argument, source_graph, record, source
            )
            for argument in arguments
    ]
    any(iszero, operands) && return Int32(0)
    callable = try
        CorePotts.CompilerSPI.operation_callable(
            Val(transfer.identity), transfer.schema_version
        )
    catch error
        push!(
            builder.diagnostics,
            PottsDiagnostic(
                :missing_concrete_operation_callable,
                source,
                string(transfer.identity),
                source.path,
                "a concrete public CorePotts operation callable",
                sprint(showerror, error),
                (),
                source_graph.records[Int(record)].source,
            ),
        )
        return Int32(0)
    end
    return _push_term_node!(
        builder,
        transfer.identity,
        transfer.schema_version,
        operands,
        :operation,
        nothing,
        transfer,
        callable,
        record,
        source;
        intern = transfer.purity === :pure,
    )
end

function _push_effect_expression_roots!(roots, role::Symbol, value)
    if value isa StaticArrays.SVector
        push!(roots, role => value)
        return roots
    elseif value isa NamedTuple
        for name in keys(value)
            _push_effect_expression_roots!(
                roots,
                Symbol(role, :_, name),
                getproperty(value, name),
            )
        end
        return roots
    elseif value isa Tuple
        for (index, item) in enumerate(value)
            _push_effect_expression_roots!(
                roots, Symbol(role, :_, index), item
            )
        end
        return roots
    end
    isempty(
        try
            Symbolics.get_variables(value)
        catch
            ()
        end
    ) || push!(roots, role => value)
    return roots
end

function _push_lifecycle_expression_roots!(roots, role::Symbol, value)
    value isa Symbol && return roots
    if value isa NamedTuple
        for name in keys(value)
            _push_lifecycle_expression_roots!(
                roots, role, getproperty(value, name)
            )
        end
        return roots
    elseif value isa Tuple || value isa AbstractArray
        for item in value
            _push_lifecycle_expression_roots!(roots, role, item)
        end
        return roots
    elseif value isa Pair
        _push_lifecycle_expression_roots!(roots, role, last(value))
        return roots
    elseif value isa AbstractPottsDistribution
        for field in fieldnames(typeof(value))
            _push_lifecycle_expression_roots!(
                roots, role, getfield(value, field)
            )
        end
        return roots
    elseif value isa AbstractLifecyclePolicy
        for field in fieldnames(typeof(value))
            _push_lifecycle_expression_roots!(
                roots, role, getfield(value, field)
            )
        end
        return roots
    elseif value isa Union{
            AbstractPottsStatement,
            AbstractIterationDomain,
            CellBinding,
            SiteBinding,
            ContactBinding,
            RelationshipBinding,
        }
        return roots
    end
    symbolic = !(
        SymbolicIndexingInterface.symbolic_type(value) isa
            SymbolicIndexingInterface.NotSymbolic
    )
    symbolic && push!(roots, role => value)
    return roots
end

function _cell_lifecycle_effects(record::QualifiedStatement)
    record.kind === :LifecycleProcess || return ()
    arguments = first(record.normalized_payload)
    arguments isa NamedTuple && haskey(arguments, :effects) || return ()
    return Tuple(filter(_cell_lifecycle_effect, arguments.effects))
end

function _push_cell_lifecycle_effect_roots!(roots, effect)
    if effect isa CreateCell
        _push_lifecycle_expression_roots!(
            roots, :lifecycle_placement, effect.placement
        )
        _push_lifecycle_expression_roots!(
            roots, :lifecycle_state_transform, effect.state
        )
    elseif effect isa RemoveCell || effect isa Retire || effect isa Transition
        _push_lifecycle_expression_roots!(
            roots, :lifecycle_state_transform, effect.state
        )
    elseif effect isa Divide
        _push_lifecycle_expression_roots!(
            roots, :lifecycle_partition, effect.geometry
        )
        _push_lifecycle_expression_roots!(
            roots, :lifecycle_state_transform, effect.state
        )
    end
    return roots
end

function _record_expression_roots(record::QualifiedStatement)
    arguments = first(record.normalized_payload)
    roots = Pair{Symbol, Any}[]
    arguments isa NamedTuple || return roots
    if record.kind === :FieldState && haskey(_record_options(record), :rhs)
        push!(roots, :field_rhs => _record_options(record).rhs)
    end
    lifecycle_effects = _cell_lifecycle_effects(record)
    if haskey(arguments, :expression) && arguments.expression !== nothing
        role = isempty(lifecycle_effects) ? :expression : :lifecycle_trigger
        push!(roots, role => arguments.expression)
    end
    if haskey(arguments, :equations)
        for (index, equation) in enumerate(arguments.equations)
            push!(roots, Symbol(:equation_, index) => equation)
        end
    end
    if haskey(arguments, :effects)
        for (effect_index, effect) in enumerate(arguments.effects)
            if _cell_lifecycle_effect(effect)
                _push_cell_lifecycle_effect_roots!(roots, effect)
                continue
            end
            for field in fieldnames(typeof(effect))
                value = getfield(effect, field)
                _push_effect_expression_roots!(
                    roots,
                    Symbol(:effect_, effect_index, :_, field),
                    value,
                )
            end
        end
    end
    return roots
end

function _normalize_source_graph(graph::FrozenSourceGraph)
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
                graph,
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
    internal_operations = _compiler_synthesized_operation_requirements(
        graph, builder.nodes, roots
    )
    operation_snapshot = FrozenOperationSchema[]
    for node in builder.nodes
        node.transfer === nothing && continue
        schema = FrozenOperationSchema(
            nothing,
            length(node.operands),
            node.transfer,
            node.callable,
        )
        _insert_operation_schema!(operation_snapshot, schema, graph.records[node.record])
    end
    for requirement in internal_operations
        operation, arity = requirement.operation, requirement.arity
        transfer = operation_transfer(operation, arity)
        callable = CorePotts.CompilerSPI.operation_callable(
            Val(transfer.identity), transfer.schema_version
        )
        schema = FrozenOperationSchema(operation, arity, transfer, callable)
        _insert_operation_schema!(operation_snapshot, schema, requirement.record)
    end
    sort!(
        operation_snapshot; by = schema -> (
            String(schema.transfer.identity), schema.transfer.schema_version,
        )
    )
    key = _sha256_hex(
        "potts-normalized-term-graph-v1",
        graph.structural_key,
        Tuple(
            (
                    node.operation,
                    node.schema_version,
                    Tuple(node.operands),
                    node.payload_kind,
                    node.structural_key,
                ) for node in builder.nodes
        ),
        Tuple((root.record, root.role, root.node) for root in roots),
        Tuple(
            (
                    schema.transfer.serialization_identity,
                    schema.transfer.owner,
                    schema.transfer.operand_rule,
                    schema.transfer.allowed_roles,
                    schema.transfer.allowed_phases,
                    schema.transfer.required_context,
                    schema.transfer.source_requirements,
                    schema.transfer.lifecycle_abi,
                    schema.transfer.callable_identity,
                    string(typeof(schema.callable)),
                ) for schema in operation_snapshot
        ),
    )
    graph = NormalizedTermGraph(
        builder.nodes, roots, Tuple(operation_snapshot), key
    )
    diagnostics = PottsDiagnostic[]
    _verify_normalized_graph!(diagnostics, graph)
    _throw_diagnostics(:analysis, diagnostics)
    return graph
end
