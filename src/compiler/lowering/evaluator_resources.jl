# Typed state, draw, kind, resource, and energy-anchor resolution.

function _state_handle_for_leaf(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        handles::Dict{QualifiedStatementID, CorePotts.CompilerSPI.StateHandle},
    )
    if node.payload isa StateBindingPayload
        return get(handles, node.payload.identity, nothing)
    end
    value = node.payload isa VariableBindingPayload ? node.payload.value : nothing
    for record in ir.source.records
        variable = _state_record_variable(record)
        variable === nothing && continue
        isequal(variable, value) || continue
        haskey(handles, record.identity) || continue
        return handles[record.identity]
    end
    return nothing
end

# The package UUID is the durable owner namespace, independent of a model's
# contents and of declaration order.
const _POTTS_RNG_NAMESPACE = CorePotts.CompilerSPI.RNGNamespace(
    (
        0xe4c62a4c88894cc8, 0xad3a75efc86c53b9,
    )
)

function _draw_operation_handles(ir::AnalyzedTermIR)
    sites = Tuple(
        (record, operation)
            for record in ir.source.records
            for operation in record.random_operations if !operation.reserved
    )
    keys = CorePotts.CompilerSPI.rng_operation_keys(
        Tuple(
            (
                    namespace = _POTTS_RNG_NAMESPACE,
                    identity = _canonical_value(
                        (
                            :potts_authored_draw, record.identity, record.phase, operation.identity,
                        )
                    ),
                ) for (record, operation) in sites
        )
    )
    return Dict{Tuple{Tuple, Symbol}, CorePotts.CompilerSPI.RNGOperationKey}(
        (record.identity.path, operation.identity) => key
            for ((record, operation), key) in zip(sites, keys)
    )
end

function _draw_handle_for_leaf(
        handles::Dict{Tuple{Tuple, Symbol}, CorePotts.CompilerSPI.RNGOperationKey},
        node::NormalizedTermNode,
    )
    node.payload isa DrawBindingPayload || return nothing
    return get(handles, (node.payload.path, node.payload.identity), nothing)
end

function _compiled_kind_index(
        ir::AnalyzedTermIR,
        owner::QualifiedStatement,
        requested,
    )
    declaration = _resource_record(
        ir.source, owner, :CellKind, requested
    )
    declaration === nothing && (declaration = _resource_record(
        ir.source, owner, :MediumKind, requested
    ))
    declaration === nothing && return nothing
    declarations = _ordered_kind_records(ir.source.records)
    index = findfirst(
        record -> record.identity == declaration.identity, declarations
    )
    return index === nothing ? nothing : Int16(index)
end

function _compiled_kind_leaf(ir::AnalyzedTermIR, node::NormalizedTermNode)
    node.payload isa KindBindingPayload || return nothing
    declarations = _ordered_kind_records(ir.source.records)
    index = findfirst(
        record -> record.identity == node.payload.identity,
        declarations,
    )
    return index === nothing ? nothing : Int16(index)
end

function _compiled_resource_leaf(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        kind::Symbol,
    )
    node.payload isa ResourceBindingPayload || return nothing
    node.payload.kind === kind || return nothing
    handle = findfirst(
        candidate -> candidate.identity == node.payload.identity,
        ir.source.records,
    )
    return handle === nothing ? nothing : Int32(handle)
end

function _relationship_payload_slot(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
    )
    node.payload isa RelationshipPayloadBindingPayload ||
        throw(ArgumentError("relationship payload leaf is not resolved"))
    selector = node.payload.selector
    declaration_index = findfirst(
        record -> record.identity == node.payload.identity,
        ir.source.records,
    )
    declaration_index === nothing && throw(ArgumentError(
        "resolved relationship payload owner is absent from the source graph"
    ))
    declaration = ir.source.records[declaration_index]
    payload = get(
        _record_options(declaration), :payload, NamedTuple()
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
            declaration.source,
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
    operation = node.callable
    operation === nothing && throw(ArgumentError(
        "energy-anchor callable was not frozen during completion"
    ))
    return CorePotts.CompilerSPI.ContextExpression(operation)
end
