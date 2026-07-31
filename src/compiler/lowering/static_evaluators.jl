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

function _static_operation_callable(node::NormalizedTermNode)
    operation = try
        CorePotts.operation_callable(
            Val(node.operation), node.schema_version
        )
    catch error
        if error isa MethodError && error.f === CorePotts.operation_callable
            throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :missing_concrete_operation_callable,
                    node.source,
                    String(node.operation),
                    node.source.path,
                    "a concrete public CorePotts operation callable",
                    "$(node.operation) $(node.schema_version)",
                    (),
                    UnknownSource(),
                ),),
            ))
        end
        rethrow(error)
    end
    isbits(operation) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_operation_callable,
            node.source,
            String(node.operation),
            node.source.path,
            "an isbits concrete operation callable",
            string(typeof(operation)),
            (),
            UnknownSource(),
        ),),
    ))
    return operation
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
    return nothing
end

function _draw_handle_for_leaf(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
    )
    name = _try_symbolic_name(node.payload)
    name === nothing && return nothing
    text = String(name)
    prefix = "__potts_draw__"
    startswith(text, prefix) || return nothing
    identity = Symbol(text[(lastindex(prefix) + 1):end])
    identities = Symbol[]
    for record in ir.source.records
        for operation in record.random_operations
            operation.reserved && continue
            operation.identity in identities || push!(identities, operation.identity)
        end
    end
    sort!(identities; by = String)
    index = findfirst(==(identity), identities)
    index === nothing && return nothing
    return UInt16(index + 15)
end

function _lower_static_node(
        graph::NormalizedTermGraph,
        ir::AnalyzedTermIR,
        node_index::Int32,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles::Dict{QualifiedStatementID, CorePotts.StateHandle},
        cache::Dict{Int32, CorePotts.AbstractStaticExpression},
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
        CorePotts.StateExpression(handle)
    elseif node.payload_kind in (
            :proposal_context,
            :relationship_context,
            :relation,
            :kind,
            :relationship_payload,
        )
        # Context operations consume these compiler tokens. They are never
        # looked up by name in the executable.
        CorePotts.LiteralExpression(Int32(0))
    elseif node.payload_kind === :symbolic_leaf
        draw_handle = _draw_handle_for_leaf(ir, node)
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
                cache,
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

function _descriptor_footprint(locality::Symbol)
    locality === :scalar && return CorePotts.EmptyFootprint()
    locality === :proposal_context &&
        return CorePotts.ProposalContextFootprint()
    locality === :owner_local && return CorePotts.OwnerFootprint()
    locality === :finite_spatial &&
        return CorePotts.FiniteSpatialFootprint(())
    locality === :bounded_relationship &&
        return CorePotts.IncidentRelationshipFootprint(typemax(Int16))
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

