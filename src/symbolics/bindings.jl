_potts_token(name::Symbol; T = Real) =
    ModelingToolkitBase.GlobalScope(Symbolics.variable(name; T))

"""
    ProposalContext(name)

A symbolic handle for the proposal snapshot. Property access constructs registered
Symbolics operations; it never reads mutable runtime state.
"""
struct ProposalContext
    name::Symbol
    token::Symbolics.Num
    function ProposalContext(name::Symbol)
        isempty(String(name)) &&
            throw(ArgumentError("a proposal binding name cannot be empty"))
        return new(name, _potts_token(Symbol("__potts_proposal__", name)))
    end
    ProposalContext(name::Symbol, token::Symbolics.Num) = new(name, token)
end

"""A symbolic anchor bound while evaluating one site in an energy domain."""
struct SiteBinding
    name::Symbol
    token::Symbolics.Num
    function SiteBinding(name::Symbol)
        isempty(String(name)) &&
            throw(ArgumentError("a site binding name cannot be empty"))
        return new(
            name,
            _potts_token(Symbol("__potts_energy_site__", name); T = Int),
        )
    end
    SiteBinding(name::Symbol, token::Symbolics.Num) = new(name, token)
end

"""A symbolic anchor bound while evaluating one cell in an energy domain."""
struct CellBinding
    name::Symbol
    token::Symbolics.Num
    function CellBinding(name::Symbol)
        isempty(String(name)) &&
            throw(ArgumentError("a cell binding name cannot be empty"))
        return new(
            name,
            _potts_token(Symbol("__potts_energy_cell__", name); T = Int),
        )
    end
    CellBinding(name::Symbol, token::Symbolics.Num) = new(name, token)
end

"""A symbolic anchor bound to one canonical contact in an energy domain."""
struct ContactBinding{R}
    name::Symbol
    relation::R
    token::Symbolics.Num
    function ContactBinding(name::Symbol, relation)
        isempty(String(name)) &&
            throw(ArgumentError("a contact binding name cannot be empty"))
        token = _potts_token(Symbol("__potts_energy_contact__", name); T = Int)
        return new{typeof(relation)}(name, relation, token)
    end
    ContactBinding(name::Symbol, relation, token::Symbolics.Num) =
        new{typeof(relation)}(name, relation, token)
end

"""
    RelationshipBinding(name, relationship)

A symbolic handle for one edge in a bounded relationship iteration domain.
"""
struct RelationshipBinding{R}
    name::Symbol
    relationship::R
    token::Symbolics.Num
    function RelationshipBinding(name::Symbol, relationship)
        isempty(String(name)) &&
            throw(ArgumentError("a relationship binding name cannot be empty"))
        token = _potts_token(Symbol("__potts_relationship__", name))
        return new{typeof(relationship)}(name, relationship, token)
    end
    RelationshipBinding(name::Symbol, relationship, token::Symbolics.Num) =
        new{typeof(relationship)}(name, relationship, token)
end

Base.show(io::IO, binding::ProposalContext) = print(io, "ProposalContext(", repr(binding.name), ")")
Base.show(io::IO, binding::SiteBinding) =
    print(io, "SiteBinding(", repr(binding.name), ")")
Base.show(io::IO, binding::CellBinding) =
    print(io, "CellBinding(", repr(binding.name), ")")
Base.show(io::IO, binding::ContactBinding) =
    print(io, "ContactBinding(", repr(binding.name), ")")
Base.show(io::IO, binding::RelationshipBinding) =
    print(io, "RelationshipBinding(", repr(binding.name), ", ",
        repr(Symbol(statement_id(binding.relationship))), ")")

_binding_token(binding::ProposalContext) = getfield(binding, :token)
_binding_token(binding::SiteBinding) = getfield(binding, :token)
_binding_token(binding::CellBinding) = getfield(binding, :token)
_binding_token(binding::ContactBinding) = getfield(binding, :token)
_binding_token(binding::RelationshipBinding) = getfield(binding, :token)

"""Return the symbolic value bound by an energy or relationship anchor."""
anchor_value(binding::Union{
    SiteBinding, CellBinding, ContactBinding, RelationshipBinding,
}) = _binding_token(binding)

struct _RelationGather{S, R, A}
    source::S
    relation::R
    anchor::A
end

"""Return whether a unary operation is exactly one direct scalar tracker view."""
is_direct_scalar_tracker_projection(::Any) = false

"""
    gather(source, relation; at)

Gather the finite values reached from `at` through `relation` as
the input to a `LocalMath.bounded_fold`. This is a cold symbolic declaration;
the Potts compiler resolves both resources and removes the declaration before
execution planning.
"""
function gather(field::FieldState, relation; at)
    relation isa Union{Symbol, SpatialRelation} || throw(ArgumentError(
        "gather relation must be a declared SpatialRelation or its local name"
    ))
    return _RelationGather(field, relation, at)
end

"""
    gather(tracker_operation, relation; at)

Declare tracker values reached by mapping each relation endpoint site to its
finite current owner and reading a unary direct scalar tracker projection such
as `cell_volume`. Extension operations opt in with
`is_direct_scalar_tracker_projection(::typeof(operation)) = true`. Values follow
relation-lane order: repeated owners remain
repeated, while absent boundary lanes and medium endpoints do not participate
in the consuming `LocalMath.BoundedFold`.
"""
function gather(operation, relation; at)
    relation isa Union{Symbol, SpatialRelation} || throw(ArgumentError(
        "gather relation must be a declared SpatialRelation or its local name"
    ))
    transfer = try
        operation_transfer(operation, 1)
    catch error
        error isa MethodError && error.f === operation_transfer || rethrow(error)
        throw(ArgumentError(
            "gather tracker sources must be registered unary Potts operations"
        ))
    end
    transfer.result_rule === :real || throw(ArgumentError(
        "gather tracker operations must return one scalar real value"
    ))
    :Proposal in transfer.allowed_phases || throw(ArgumentError(
        "gather tracker operations must support proposal evaluation"
    ))
    (!isempty(transfer.tracker_requirements) ||
        transfer.identity === :cell_volume) || throw(ArgumentError(
        "gather accepts only operations backed by a declared tracker"
    ))
    is_direct_scalar_tracker_projection(operation) || throw(ArgumentError(
        "gather requires a declared direct scalar tracker projection"
    ))
    all(requirement -> requirement isa NamedSpatialRelationRequirement,
        transfer.source_requirements) || throw(ArgumentError(
        "gathered tracker projections currently require only named spatial resources"
    ))
    return _RelationGather(operation, relation, at)
end

function (fold::LocalMath.BoundedFold)(values::_RelationGather)
    source = values.source isa FieldState ?
             _field_token(values.source) : values.source(values.anchor)
    return _potts_bounded_fold(
        fold,
        source,
        _spatial_relation_token(values.relation),
        values.anchor,
    )
end

function Base.getproperty(binding::ProposalContext, name::Symbol)
    name === :name && return getfield(binding, :name)
    name === :token && return getfield(binding, :token)
    name === :source_site && return source_site(_binding_token(binding))
    name === :target_site && return target_site(_binding_token(binding))
    name === :source_cell && return source_cell(_binding_token(binding))
    name === :target_cell && return target_cell(_binding_token(binding))
    name === :source_kind && return source_kind(_binding_token(binding))
    name === :target_kind && return target_kind(_binding_token(binding))
    name === :is_extension && return is_extension(_binding_token(binding))
    name === :is_retraction && return is_retraction(_binding_token(binding))
    throw(ArgumentError("unknown ProposalContext binding `$name`"))
end

function Base.getproperty(binding::RelationshipBinding, name::Symbol)
    name === :name && return getfield(binding, :name)
    name === :relationship && return getfield(binding, :relationship)
    name === :token && return getfield(binding, :token)
    name === :a && return endpoint_a(_binding_token(binding))
    name === :b && return endpoint_b(_binding_token(binding))
    return edge_payload(_binding_token(binding), Val(name))
end


function Base.getproperty(binding::ContactBinding, name::Symbol)
    name === :name && return getfield(binding, :name)
    name === :relation && return getfield(binding, :relation)
    name === :token && return getfield(binding, :token)
    name === :owner_a && return contact_owner_a(_binding_token(binding))
    name === :owner_b && return contact_owner_b(_binding_token(binding))
    name === :kind_a && return contact_kind_a(_binding_token(binding))
    name === :kind_b && return contact_kind_b(_binding_token(binding))
    throw(ArgumentError("unknown ContactBinding property `$name`"))
end

function map_symbolics(f, binding::ProposalContext)
    return ProposalContext(binding.name, f(_binding_token(binding)))
end

map_symbolics(f, binding::SiteBinding) =
    SiteBinding(binding.name, f(_binding_token(binding)))
map_symbolics(f, binding::CellBinding) =
    CellBinding(binding.name, f(_binding_token(binding)))
map_symbolics(f, binding::ContactBinding) =
    ContactBinding(binding.name, binding.relation, f(_binding_token(binding)))

map_symbolics(f, binding::RelationshipBinding) =
    RelationshipBinding(binding.name, binding.relationship, f(_binding_token(binding)))
