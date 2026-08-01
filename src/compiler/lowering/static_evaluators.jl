# Symbolic evaluator, descriptor, and layout lowering.

"""
    DescriptorSource

Stable host-side source information supplied to downstream descriptor and
workspace construction hooks. Private compiler IR is deliberately absent.
"""
struct DescriptorSource
    identity::QualifiedStatementID
    kind::Symbol
    schema_version::VersionNumber
    lowering_identity::Symbol
    provenance::Any
end

"""
    DescriptorConstructionContext

Complete, resolved input to a downstream descriptor constructor. Every handle
is compact and every evaluator/tag is concrete before this value is created.
"""
struct DescriptorConstructionContext{A, S, H <: Tuple, W <: Tuple, R}
    access::A
    support::S
    state_handles::H
    workspace_handles::W
    role::R
    source_handle::Int32
    source::DescriptorSource
end

"""
    registered_descriptor_payload(::Val{lowering_identity}, context)

Construct inert isbits metadata for a registered statement family. CorePotts
always owns the proposal descriptor and evaluator execution path; downstream
metadata cannot replace either. The payload value's concrete type must exactly
match the fixed `descriptor_payload_type` in the registered statement contract.
"""
function registered_descriptor_payload end

"""
    registered_workspace_schemas(::Val{lowering_identity}, source, scalar_type, lattice_shape)

Declare reusable workspaces required by a registered descriptor family.
Declarations are host metadata; the compiler resolves them to compact handles.
"""
registered_workspace_schemas(
    ::Val, ::DescriptorSource, ::Type, ::Tuple
) = ()

function _static_literal(value, manifest::ParameterManifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    if value isa Bool || value isa Integer || value isa Symbol
        return CorePotts.LiteralExpression(value)
    elseif value isa Number
        return CorePotts.LiteralExpression(T(_numeric_value(
            value, _reference_for(manifest.reference_units, value)
        )))
    end
    throw(ArgumentError(
        "static evaluator literal is not device-compatible: $(repr(value))"
    ))
end

function _static_parameter(value, manifest::ParameterManifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    scalar = _compiled_scalar(value, manifest, T)
    return CorePotts.ParameterExpression(
        scalar.value, scalar.parameter_index
    )
end

function _static_operation_callable(
        identity::Symbol,
        version::VersionNumber,
        source::QualifiedStatementID,
        provenance,
    )
    operation = try
        CorePotts.operation_callable(
            Val(identity), version
        )
    catch error
        if error isa MethodError && error.f === CorePotts.operation_callable
            throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :missing_concrete_operation_callable,
                    source,
                    String(identity),
                    source.path,
                    "a concrete public CorePotts operation callable",
                    "$identity $version",
                    (),
                    provenance,
                ),),
            ))
        end
        rethrow(error)
    end
    isbits(operation) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_operation_callable,
            source,
            String(identity),
            source.path,
            "an isbits concrete operation callable",
            string(typeof(operation)),
            (),
            provenance,
        ),),
    ))
    return operation
end

_static_operation_callable(node::NormalizedTermNode) =
    _static_operation_callable(
        node.operation,
        node.schema_version,
        node.source,
        UnknownSource(),
    )

function _compiler_operation_expression(
        operation,
        arguments::Tuple,
        record::QualifiedStatement,
    )
    transfer = try
        operation_transfer(operation, length(arguments))
    catch error
        if error isa MethodError && error.f === operation_transfer
            throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :missing_operation_transfer,
                    record.identity,
                    repr(operation),
                    record.identity.path,
                    "a versioned operation transfer rule",
                    repr(operation),
                    (),
                    record.source,
                ),),
            ))
        end
        rethrow(error)
    end
    reason = _operation_transfer_error(transfer, length(arguments))
    reason === nothing || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :invalid_operation_transfer,
            record.identity,
            String(transfer.identity),
            record.identity.path,
            "a valid frozen operation transfer",
            reason,
            (),
            record.source,
        ),),
    ))
    callable = _static_operation_callable(
        transfer.identity,
        transfer.schema_version,
        record.identity,
        record.source,
    )
    return _bounded_static_operation(callable, arguments)
end

function _validate_static_expression_context(
        expression::CorePotts.AbstractStaticExpression,
        context::Type{<:CorePotts.AbstractEvaluatorExecutionContext},
        record::QualifiedStatement,
    )
    operation = if expression isa CorePotts.ContextExpression
        expression.operation
    elseif expression isa CorePotts.OperationExpression
        expression.operation
    else
        nothing
    end
    if operation !== nothing && !CorePotts.operation_context_supported(
            operation, context
        )
        throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unsupported_operation_context,
                record.identity,
                string(typeof(operation)),
                record.identity.path,
                "a concrete callable implemented for $(nameof(context))",
                "no callable implementation for $(nameof(context))",
                (),
                record.source,
            ),),
        ))
    end
    if expression isa CorePotts.OperationExpression
        for argument in expression.arguments
            _validate_static_expression_context(argument, context, record)
        end
    end
    return nothing
end

function _static_evaluator(
        expression::CorePotts.AbstractStaticExpression,
        context::Type{<:CorePotts.AbstractEvaluatorExecutionContext},
        record::QualifiedStatement,
    )
    _validate_static_expression_context(expression, context, record)
    return CorePotts.StaticEvaluator(expression)
end

function _bounded_static_operation(operation, arguments::Tuple)
    length(arguments) <= 8 &&
        return CorePotts.OperationExpression(operation, arguments...)
    (
        operation isa CorePotts.OrderedFold &&
        operation.operation in (+, *)
    ) || return CorePotts.OperationExpression(operation, arguments...)
    result = CorePotts.OperationExpression(operation, arguments[1:8]...)
    index = 9
    while index <= length(arguments)
        final = min(index + 6, length(arguments))
        result = CorePotts.OperationExpression(
            operation, result, arguments[index:final]...
        )
        index = final + 1
    end
    return result
end

function _state_record_variable(record::QualifiedStatement)
    record.kind in (
        :SiteState,
        :CellState,
        :MediumState,
        :ModelState,
        :FieldState,
        :HistoryState,
    ) || return nothing
    payload = record.normalized_payload
    payload isa Tuple && !isempty(payload) || return nothing
    arguments = first(payload)
    arguments isa NamedTuple && haskey(arguments, :variable) ||
        return nothing
    return arguments.variable
end

function _state_handle_for_leaf(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        handles::Dict{QualifiedStatementID, CorePotts.StateHandle},
    )
    for record in ir.source.records
        variable = _state_record_variable(record)
        variable === nothing && continue
        isequal(variable, node.payload) || continue
        haskey(handles, record.identity) || continue
        return handles[record.identity]
    end
    name = _try_symbolic_name(node.payload)
    if name !== nothing
        text = String(name)
        for (prefix, kind) in (
                "__potts_field__" => :FieldState,
                "__potts_state__" => :SiteState,
            )
            startswith(text, prefix) || continue
            requested = Symbol(text[(lastindex(prefix) + 1):end])
            owner = ir.source.records[Int(node.record)]
            record = _resource_record(ir.source, owner, kind, requested)
            record === nothing && continue
            haskey(handles, record.identity) && return handles[record.identity]
        end
    end
    return nothing
end

const _FIRST_EXPLICIT_DRAW_OPERATION = UInt16(0x0010)
const _EXPLICIT_DRAW_OPERATION_COUNT =
    Int(CorePotts.rng_operation_limit() - _FIRST_EXPLICIT_DRAW_OPERATION + 1)

function _stable_draw_operation(path::Tuple, identity::Symbol)
    digest = SHA.sha256(codeunits(_canonical_value((
        :potts_draw_operation_v1,
        path,
        identity,
    ))))
    word = (UInt16(digest[1]) << 8) | UInt16(digest[2])
    return _FIRST_EXPLICIT_DRAW_OPERATION +
           UInt16(Int(word) % _EXPLICIT_DRAW_OPERATION_COUNT)
end

function _draw_operation_handles(ir::AnalyzedTermIR)
    handles = Dict{Tuple{Tuple, Symbol}, UInt16}()
    owners = Dict{UInt16, Tuple{Tuple, Symbol}}()
    for record in ir.source.records
        for operation in record.random_operations
            operation.reserved && continue
            key = (record.identity.path, operation.identity)
            handle = _stable_draw_operation(key...)
            if haskey(owners, handle) && owners[handle] != key
                other = owners[handle]
                throw(PottsValidationError(
                    :descriptor_lowering,
                    (PottsDiagnostic(
                        :draw_operation_identity_collision,
                        record.identity,
                        String(operation.identity),
                        record.identity.path,
                        "a collision-free stable namespace-local draw identity",
                        "$(other[1]).$(other[2]) and $(key[1]).$(key[2]) map to " *
                        "operation $(Int(handle))",
                        (),
                        record.source,
                    ),),
                ))
            end
            handles[key] = handle
            owners[handle] = key
        end
    end
    return handles
end

function _draw_handle_for_leaf(
        handles::Dict{Tuple{Tuple, Symbol}, UInt16},
        node::NormalizedTermNode,
    )
    name = _try_symbolic_name(node.payload)
    name === nothing && return nothing
    text = String(name)
    prefix = "__potts_draw__"
    startswith(text, prefix) || return nothing
    identity = Symbol(text[(lastindex(prefix) + 1):end])
    return get(handles, (node.source.path, identity), nothing)
end

function _compiled_kind_index(ir::AnalyzedTermIR, requested::Symbol)
    declarations = filter(
        record -> record.kind in (:CellKind, :MediumKind),
        ir.source.records,
    )
    sort!(declarations; by = record -> (
        record.kind === :MediumKind ? 0 : 1,
        String(Symbol(record.identity.local_id)),
    ))
    index = findfirst(
        record -> Symbol(record.identity.local_id) === requested,
        declarations,
    )
    index === nothing && return nothing
    return Int16(index)
end

function _compiled_kind_leaf(ir::AnalyzedTermIR, node::NormalizedTermNode)
    name = _try_symbolic_name(node.payload)
    name === nothing && return nothing
    text = String(name)
    prefix = "__potts_kind__"
    startswith(text, prefix) || return nothing
    return _compiled_kind_index(
        ir, Symbol(text[(length(prefix) + 1):end])
    )
end

function _compiled_resource_leaf(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        prefix::String,
        kind::Symbol,
    )
    name = _try_symbolic_name(node.payload)
    name === nothing && return nothing
    text = String(name)
    startswith(text, prefix) || return nothing
    requested = Symbol(text[(lastindex(prefix) + 1):end])
    owner = ir.source.records[Int(node.record)]
    record = _resource_record(ir.source, owner, kind, requested)
    record === nothing && return nothing
    handle = findfirst(
        candidate -> candidate.identity == record.identity,
        ir.source.records,
    )
    return handle === nothing ? nothing : Int32(handle)
end

function _relationship_payload_slot(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        selector::Symbol,
    )
    owner = ir.source.records[Int(node.record)]
    declarations = filter(ir.source.records) do record
        record.kind === :RelationshipState && record.identity in owner.resources
    end
    length(declarations) == 1 || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :ambiguous_relationship_payload,
            node.source,
            String(selector),
            node.source.path,
            "one relationship resource owning the payload selector",
            "$(length(declarations)) matching relationship resources",
            (),
            owner.source,
        ),),
    ))
    payload = get(
        _record_options(only(declarations)), :payload, NamedTuple()
    )
    payload isa NamedTuple || throw(ArgumentError(
        "relationship payload declaration must be a named tuple"
    ))
    slot = findfirst(==(selector), keys(payload))
    slot === nothing && throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :unknown_relationship_payload,
            node.source,
            String(selector),
            node.source.path,
            "one field declared by the relationship payload schema",
            join(String.(keys(payload)), ", "),
            (),
            owner.source,
        ),),
    ))
    return Int32(slot)
end

function _energy_anchor_expression(
        kind::Symbol,
        node::NormalizedTermNode,
    )
    identity = kind === :site_anchor ? :energy_anchor_site :
               kind === :cell_anchor ? :energy_anchor_cell :
               kind === :contact_anchor ? :energy_anchor_contact :
               kind === :relationship_context ? :energy_anchor_relationship :
               throw(ArgumentError("unsupported energy anchor leaf `$kind`"))
    operation = _static_operation_callable(
        identity,
        node.schema_version,
        node.source,
        UnknownSource(),
    )
    return CorePotts.ContextExpression(operation)
end

function _lower_static_node(
        graph::NormalizedTermGraph,
        ir::AnalyzedTermIR,
        node_index::Int32,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles::Dict{QualifiedStatementID, CorePotts.StateHandle},
        draw_handles::Dict{Tuple{Tuple, Symbol}, UInt16},
        cache::Dict{Int32, CorePotts.AbstractStaticExpression},
        state_binding::Union{
            Nothing, CorePotts.AbstractStageSiteSelector,
        } = nothing,
    ) where {T <: AbstractFloat}
    haskey(cache, node_index) && return cache[node_index]
    node = graph.nodes[node_index]
    expression = if node.payload_kind === :literal
        _static_literal(node.payload, manifest, T)
    elseif node.payload_kind === :parameter
        _static_parameter(node.payload, manifest, T)
    elseif node.payload_kind in (:state, :variable)
        handle = _state_handle_for_leaf(ir, node, state_handles)
        handle === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_state_handle,
                node.source,
                repr(node.payload),
                node.source.path,
                "one qualified state resource",
                "no matching state block",
                (),
                UnknownSource(),
            ),),
        ))
        state_expression = CorePotts.StateExpression(handle)
        state_binding === nothing ? state_expression :
        _compiler_operation_expression(
            state_binding isa CorePotts.ProposalTargetStageSite ?
                _potts_proposal_bound_state_value :
                _potts_iteration_bound_state_value,
            (state_expression,),
            ir.source.records[node.record],
        )
    elseif node.payload_kind === :proposal_context
        # Context operations consume these compiler tokens. They are never
        # looked up by name in the executable.
        CorePotts.LiteralExpression(Int32(0))
    elseif node.payload_kind === :spatial_relation
        handle = _compiled_resource_leaf(
            ir,
            node,
            "__potts_spatial_relation__",
            :SpatialRelation,
        )
        handle === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_spatial_relation_handle,
                node.source,
                repr(node.payload),
                node.source.path,
                "a declared finite SpatialRelation",
                "no matching spatial relation",
                (),
                UnknownSource(),
            ),),
        ))
        CorePotts.LiteralExpression(handle)
    elseif node.payload_kind === :relationship_set
        handle = _compiled_resource_leaf(
            ir,
            node,
            "__potts_relationship_set__",
            :RelationshipState,
        )
        handle === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_relationship_handle,
                node.source,
                repr(node.payload),
                node.source.path,
                "a declared RelationshipState",
                "no matching relationship resource",
                (),
                UnknownSource(),
            ),),
        ))
        CorePotts.LiteralExpression(handle)
    elseif node.payload_kind === :relationship_payload
        name = _try_symbolic_name(node.payload)
        name === nothing && throw(ArgumentError(
            "relationship payload selector has no symbolic identity"
        ))
        text = String(name)
        prefix = "__potts_payload__"
        startswith(text, prefix) || throw(ArgumentError(
            "relationship payload selector has an invalid identity"
        ))
        selector = Symbol(text[(length(prefix) + 1):end])
        CorePotts.LiteralExpression(
            _relationship_payload_slot(ir, node, selector)
        )
    elseif node.payload_kind in (
            :site_anchor, :cell_anchor, :contact_anchor,
            :relationship_context,
        )
        _energy_anchor_expression(node.payload_kind, node)
    elseif node.payload_kind === :kind
        kind = _compiled_kind_leaf(ir, node)
        kind === nothing && throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_kind_handle,
                node.source,
                repr(node.payload),
                node.source.path,
                "a declared value-level kind index",
                "no matching cell or medium kind",
                (),
                UnknownSource(),
            ),),
        ))
        CorePotts.LiteralExpression(kind)
    elseif node.payload_kind === :symbolic_leaf
        draw_handle = _draw_handle_for_leaf(draw_handles, node)
        draw_handle === nothing ? throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unresolved_symbolic_leaf,
                node.source,
                repr(node.payload),
                node.source.path,
                "a parameter, context token, state handle, or RNG handle",
                "unresolved symbolic leaf",
                (),
                UnknownSource(),
            ),),
        )) : CorePotts.LiteralExpression(draw_handle)
    else
        operation = _static_operation_callable(node)
        arguments = Tuple(
            _lower_static_node(
                graph,
                ir,
                operand,
                manifest,
                T,
                state_handles,
                draw_handles,
                cache,
                state_binding,
            )
            for operand in node.operands
        )
        if operation isa CorePotts.ContextOperation
            CorePotts.ContextExpression(operation)
        else
            _bounded_static_operation(operation, arguments)
        end
    end
    cache[node_index] = expression
    return expression
end

function _reachable_term_nodes(graph::NormalizedTermGraph, root::Int32)
    pending = Int32[root]
    seen = Set{Int32}()
    while !isempty(pending)
        node = pop!(pending)
        node in seen && continue
        push!(seen, node)
        append!(pending, graph.nodes[Int(node)].operands)
    end
    return sort!(collect(seen))
end

function _spatial_footprint_offsets(ir::AnalyzedTermIR, root::Int32)
    offsets = Tuple[]
    for index in _reachable_term_nodes(ir.graph, root)
        node = ir.graph.nodes[Int(index)]
        node.payload_kind === :spatial_relation || continue
        name = _try_symbolic_name(node.payload)
        name === nothing && continue
        text = String(name)
        prefix = "__potts_spatial_relation__"
        startswith(text, prefix) || continue
        requested = Symbol(text[(lastindex(prefix) + 1):end])
        owner = ir.source.records[Int(node.record)]
        record = _resource_record(ir.source, owner, :SpatialRelation, requested)
        record === nothing && continue
        neighborhood = get(_record_options(record), :neighborhood, nothing)
        neighborhood isa Union{VonNeumann, Moore} || continue
        matrix = _neighborhood_offsets(
            neighborhood, length(_lattice_shape(ir))
        )
        for column in axes(matrix, 2)
            push!(offsets, Tuple(matrix[:, column]))
        end
    end
    sort!(unique!(offsets))
    return Tuple(offsets)
end

function _relationship_footprint_degree(ir::AnalyzedTermIR, root::Int32)
    maximum_degree = 0
    for index in _reachable_term_nodes(ir.graph, root)
        node = ir.graph.nodes[Int(index)]
        node.payload_kind === :relationship_set || continue
        name = _try_symbolic_name(node.payload)
        name === nothing && continue
        text = String(name)
        prefix = "__potts_relationship_set__"
        startswith(text, prefix) || continue
        requested = Symbol(text[(lastindex(prefix) + 1):end])
        owner = ir.source.records[Int(node.record)]
        record = _resource_record(ir.source, owner, :RelationshipState, requested)
        record === nothing && continue
        maximum_degree = max(
            maximum_degree,
            Int(_numeric_value(get(
                _record_options(record), :maximum_degree, 0
            ))),
        )
    end
    return Int32(maximum_degree)
end

function _descriptor_footprint(
        ir::AnalyzedTermIR, root::Int32, locality::Symbol
    )
    locality === :scalar && return CorePotts.EmptyFootprint()
    locality === :site_local && return CorePotts.FiniteSpatialFootprint(())
    locality === :contact_local && return CorePotts.FiniteSpatialFootprint(())
    locality === :proposal_context &&
        return CorePotts.ProposalContextFootprint()
    locality === :owner_local && return CorePotts.OwnerFootprint()
    locality === :finite_spatial &&
        return CorePotts.FiniteSpatialFootprint(
            _spatial_footprint_offsets(ir, root)
        )
    locality === :bounded_relationship &&
        return CorePotts.IncidentRelationshipFootprint(
            _relationship_footprint_degree(ir, root)
        )
    throw(ArgumentError("unsupported descriptor locality `$locality`"))
end

function _descriptor_support(
        ir::AnalyzedTermIR,
        candidate::DescriptorCandidate,
    )
    roots = Int.(candidate.roots)
    sequential = all(roots) do root
        any(admission ->
            admission.engine === :sequential && admission.admitted,
            ir.facts.engine_admission[root])
    end
    checkerboard = all(roots) do root
        any(admission ->
            admission.engine === :checkerboard && admission.admitted,
            ir.facts.engine_admission[root])
    end
    cpu = all(root -> ir.facts.backend_admission[root].cpu, roots)
    gpu = all(root -> ir.facts.backend_admission[root].gpu, roots)
    reason_code = UInt16(
        (!sequential ? 0x01 : 0x00) |
        (!checkerboard ? 0x02 : 0x00) |
        (!cpu ? 0x04 : 0x00) |
        (!gpu ? 0x08 : 0x00)
    )
    return CorePotts.DescriptorSupport(
        sequential,
        checkerboard,
        cpu,
        gpu,
        reason_code,
    )
end

_qualified_resource_identity(identity::QualifiedStatementID) =
    CorePotts.QualifiedResourceIdentity(
        identity.path, Symbol(identity.local_id)
    )

_storage_class_sort_key(value::Tuple) =
    join((_storage_class_sort_key(item) for item in value), "\u001f")
_storage_class_sort_key(value::Type) =
    "type:" * string(parentmodule(value)) * "." * string(value)
_storage_class_sort_key(value) =
    string(typeof(value), ":", repr(value))
