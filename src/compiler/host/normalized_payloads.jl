# Normalized, ordered symbolic term DAG construction and verification.

abstract type AbstractNormalizedPayload end

struct LiteralPayload{T} <: AbstractNormalizedPayload
    value::T
end

struct ParameterBindingPayload{T} <: AbstractNormalizedPayload
    value::T
end

struct VariableBindingPayload{T} <: AbstractNormalizedPayload
    identity::QualifiedStatementID
    value::T
end

struct StateBindingPayload{T} <: AbstractNormalizedPayload
    identity::QualifiedStatementID
    value::T
end

struct ContextBindingPayload <: AbstractNormalizedPayload
    kind::Symbol
    name::Symbol
end

struct AnchorBindingPayload <: AbstractNormalizedPayload
    kind::Symbol
    name::Symbol
    resource::Union{Nothing, QualifiedStatementID}
end

struct ResourceBindingPayload <: AbstractNormalizedPayload
    kind::Symbol
    identity::QualifiedStatementID
end

struct KindBindingPayload <: AbstractNormalizedPayload
    identity::QualifiedStatementID
end

struct RelationshipPayloadBindingPayload <: AbstractNormalizedPayload
    identity::QualifiedStatementID
    selector::Symbol
end

struct DrawBindingPayload <: AbstractNormalizedPayload
    path::Tuple{Vararg{Symbol}}
    identity::Symbol
end

struct NormalizedTermNode
    identity::Int32
    operation::Symbol
    schema_version::VersionNumber
    operands::Vector{Int32}
    payload_kind::Symbol
    payload::Any
    transfer::Union{Nothing, OperationTransfer}
    callable::Any
    structural_key::String
    record::Int32
    source::QualifiedStatementID
end

struct NormalizedTermRoot
    record::Int32
    role::Symbol
    node::Int32
end

struct FrozenOperationSchema
    surface_operation::Any
    arity::Int
    transfer::OperationTransfer
    callable::Any
end

struct NormalizedTermGraph
    nodes::Vector{NormalizedTermNode}
    roots::Vector{NormalizedTermRoot}
    operation_snapshot::Tuple
    structural_key::String
end

mutable struct _TermGraphBuilder
    nodes::Vector{NormalizedTermNode}
    interned::Dict{String, Int32}
    diagnostics::Vector{PottsDiagnostic}
end

function _qualified_source_reference(reference::FrozenSourceReference)
    return _namespace_symbolic_value(
        reference.value, reference.path[2:end]
    )
end

function _compiler_leaf_kind(value, source::FrozenSourceGraph)
    any(source.references) do reference
        reference.kind === :parameter &&
            isequal(_qualified_source_reference(reference), value)
    end && return :parameter
    for record in source.records
        state_variable = _state_record_variable(record)
        state_variable === nothing && continue
        isequal(state_variable, value) && return :state
    end
    any(source.references) do reference
        reference.kind === :variable &&
            isequal(_qualified_source_reference(reference), value)
    end && return :variable
    name = _try_symbolic_name(value)
    name === nothing && return :literal
    text = String(name)
    startswith(text, "__potts_proposal__") && return :proposal_context
    startswith(text, "__potts_energy_site__") && return :site_anchor
    startswith(text, "__potts_energy_cell__") && return :cell_anchor
    startswith(text, "__potts_energy_contact__") && return :contact_anchor
    startswith(text, "__potts_relationship__") && return :relationship_context
    startswith(text, "__potts_relationship_set__") && return :relationship_set
    startswith(text, "__potts_spatial_relation__") && return :spatial_relation
    startswith(text, "__potts_kind__") && return :kind
    startswith(text, "__potts_field__") && return :state
    startswith(text, "__potts_payload__") && return :relationship_payload
    startswith(text, "__potts_draw__") && return :draw
    return :symbolic_leaf
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

function _normalized_token_suffix(value, prefix::String)
    name = _try_symbolic_name(value)
    name === nothing && return nothing
    text = String(name)
    startswith(text, prefix) || return nothing
    first_index = lastindex(prefix) + 1
    first_index <= lastindex(text) || return nothing
    return Symbol(text[first_index:end])
end

function _resolved_state_payload(
        source::FrozenSourceGraph,
        value,
    )
    for record in source.records
        variable = _state_record_variable(record)
        variable === nothing && continue
        isequal(variable, value) || continue
        return StateBindingPayload(record.identity, value)
    end
    return nothing
end

function _resolved_resource_payload(
        source::FrozenSourceGraph,
        record::QualifiedStatement,
        kind::Symbol,
        requested,
    )
    resource = _resource_record(source, record, kind, requested)
    resource === nothing && return nothing
    return ResourceBindingPayload(kind, resource.identity)
end

function _bound_anchor_resource(
        source::FrozenSourceGraph,
        record::QualifiedStatement,
        kind::Symbol,
    )
    arguments = _record_arguments(record)
    arguments isa NamedTuple && haskey(arguments, :domain) || return nothing
    domain = arguments.domain
    requested, resource_kind = if kind === :contact_anchor && domain isa Contacts
        (domain.relation, :SpatialRelation)
    elseif kind === :cell_anchor && domain isa Cells
        (domain.kind, :CellKind)
    elseif kind === :relationship_context && domain isa Edges
        (domain.relationship, :RelationshipState)
    else
        return nothing
    end
    resource = _resource_record(source, record, resource_kind, requested)
    return resource === nothing ? nothing : resource.identity
end

function _resolved_relationship_payload(
        source::FrozenSourceGraph,
        record::QualifiedStatement,
        selector::Symbol,
    )
    declarations = filter(source.records) do candidate
        candidate.kind === :RelationshipState &&
            candidate.identity in record.resources
    end
    if length(declarations) == 1
        return RelationshipPayloadBindingPayload(
            only(declarations).identity, selector
        )
    end
    resource_ids = filter(
        identity -> any(candidate -> candidate.kind === :RelationshipState &&
            candidate.identity == identity, source.records),
        record.resources,
    )
    length(resource_ids) == 1 || return nothing
    return RelationshipPayloadBindingPayload(only(resource_ids), selector)
end

function _resolve_normalized_payload(
        kind::Symbol,
        value,
        source::FrozenSourceGraph,
        record::QualifiedStatement,
    )
    kind === :literal && return LiteralPayload(_compiler_literal(value))
    kind === :parameter && return ParameterBindingPayload(value)
    if kind in (:state, :variable)
        state = _resolved_state_payload(source, value)
        state !== nothing && return state
        if kind === :variable
            name = _try_symbolic_name(value)
            name === nothing && return nothing
            return VariableBindingPayload(
                QualifiedStatementID(record.identity.path, StatementID(name)),
                value,
            )
        end
        field_name = _normalized_token_suffix(value, "__potts_field__")
        state_name = _normalized_token_suffix(value, "__potts_state__")
        requested = field_name === nothing ? state_name : field_name
        requested === nothing && return nothing
        resource_kind = field_name === nothing ? :SiteState : :FieldState
        resource = _resource_record(source, record, resource_kind, requested)
        if resource !== nothing
            return StateBindingPayload(resource.identity, value)
        end
        identity = findfirst(
            candidate -> candidate.local_id == StatementID(requested),
            record.resources,
        )
        identity === nothing && return nothing
        return StateBindingPayload(record.resources[identity], value)
    elseif kind === :proposal_context
        name = _normalized_token_suffix(value, "__potts_proposal__")
        return name === nothing ? nothing : ContextBindingPayload(:proposal, name)
    elseif kind in (:site_anchor, :cell_anchor, :contact_anchor, :relationship_context)
        prefix = kind === :site_anchor ? "__potts_energy_site__" :
                 kind === :cell_anchor ? "__potts_energy_cell__" :
                 kind === :contact_anchor ? "__potts_energy_contact__" :
                 "__potts_relationship__"
        name = _normalized_token_suffix(value, prefix)
        name === nothing && return nothing
        return AnchorBindingPayload(
            kind,
            name,
            _bound_anchor_resource(source, record, kind),
        )
    elseif kind === :relationship_set
        requested = _normalized_token_suffix(value, "__potts_relationship_set__")
        return requested === nothing ? nothing : _resolved_resource_payload(
            source, record, :RelationshipState, requested
        )
    elseif kind === :spatial_relation
        requested = _normalized_token_suffix(value, "__potts_spatial_relation__")
        return requested === nothing ? nothing : _resolved_resource_payload(
            source, record, :SpatialRelation, requested
        )
    elseif kind === :kind
        requested = _normalized_token_suffix(value, "__potts_kind__")
        requested === nothing && return nothing
        resource = _resource_record(source, record, :CellKind, requested)
        resource === nothing &&
            (resource = _resource_record(source, record, :MediumKind, requested))
        return resource === nothing ? nothing : KindBindingPayload(resource.identity)
    elseif kind === :relationship_payload
        selector = _normalized_token_suffix(value, "__potts_payload__")
        return selector === nothing ? nothing :
            _resolved_relationship_payload(source, record, selector)
    elseif kind === :draw
        identity = _normalized_token_suffix(value, "__potts_draw__")
        identity === nothing && return nothing
        any(operation -> operation.identity === identity, record.random_operations) ||
            return nothing
        return DrawBindingPayload(record.identity.path, identity)
    elseif kind === :symbolic_leaf
        any(read -> isequal(read, value), record.reads) || return nothing
        name = _try_symbolic_name(value)
        name === nothing && return nothing
        return VariableBindingPayload(
            QualifiedStatementID(record.identity.path, StatementID(name)),
            value,
        )
    end
    return nothing
end

_normalized_payload_key(::Nothing) = nothing
_normalized_payload_key(payload::LiteralPayload) = (:literal, repr(payload.value))
_normalized_payload_key(payload::ParameterBindingPayload) =
    (:parameter, _try_symbolic_name(payload.value))
_normalized_payload_key(payload::VariableBindingPayload) =
    (:variable, payload.identity)
_normalized_payload_key(payload::StateBindingPayload) =
    (:state, payload.identity)
_normalized_payload_key(payload::ContextBindingPayload) =
    (:context, payload.kind, payload.name)
_normalized_payload_key(payload::AnchorBindingPayload) =
    (:anchor, payload.kind, payload.name, payload.resource)
_normalized_payload_key(payload::ResourceBindingPayload) =
    (:resource, payload.kind, payload.identity)
_normalized_payload_key(payload::KindBindingPayload) =
    (:kind, payload.identity)
_normalized_payload_key(payload::RelationshipPayloadBindingPayload) =
    (:relationship_payload, payload.identity, payload.selector)
_normalized_payload_key(payload::DrawBindingPayload) =
    (:draw, payload.path, payload.identity)

_normalized_payload_kind(::LiteralPayload) = :literal
_normalized_payload_kind(::ParameterBindingPayload) = :parameter
_normalized_payload_kind(::VariableBindingPayload) = :variable
_normalized_payload_kind(::StateBindingPayload) = :state
_normalized_payload_kind(payload::ContextBindingPayload) =
    payload.kind === :proposal ? :proposal_context : :context
_normalized_payload_kind(payload::AnchorBindingPayload) = payload.kind
_normalized_payload_kind(payload::ResourceBindingPayload) =
    payload.kind === :SpatialRelation ? :spatial_relation : :relationship_set
_normalized_payload_kind(::KindBindingPayload) = :kind
_normalized_payload_kind(::RelationshipPayloadBindingPayload) =
    :relationship_payload
_normalized_payload_kind(::DrawBindingPayload) = :draw

function _normalized_leaf_callable(kind::Symbol, version::VersionNumber)
    identity = kind === :site_anchor ? :energy_anchor_site :
               kind === :cell_anchor ? :energy_anchor_cell :
               kind === :contact_anchor ? :energy_anchor_contact :
               kind === :relationship_context ? :energy_anchor_relationship :
               nothing
    identity === nothing && return nothing
    return CorePotts.CompilerSPI.operation_callable(Val(identity), version)
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
