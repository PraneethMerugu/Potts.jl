# Typed state, draw, kind, resource, and energy-anchor resolution.

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
    name = _try_symbolic_name(node.payload)
    name === nothing && return nothing
    text = String(name)
    prefix = "__potts_kind__"
    startswith(text, prefix) || return nothing
    owner = ir.source.records[Int(node.record)]
    return _compiled_kind_index(
        ir, owner, Symbol(text[(length(prefix) + 1):end])
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
