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

"""A symbolic site anchor for contextual energy or scoped quantity evaluation."""
struct SiteBinding{D}
    domain::D
    token::Symbolics.Num
end
function SiteBinding(name::Symbol)
    isempty(String(name)) && throw(ArgumentError("a site binding name cannot be empty"))
    return SiteBinding(nothing, _potts_token(Symbol("__potts_energy_site__", name); T = Int))
end

"""A symbolic cell anchor for contextual energy or scoped quantity evaluation."""
struct CellBinding{D}
    domain::D
    token::Symbolics.Num
end
function CellBinding(name::Symbol)
    isempty(String(name)) && throw(ArgumentError("a cell binding name cannot be empty"))
    return CellBinding(nothing, _potts_token(Symbol("__potts_energy_cell__", name); T = Int))
end

_scoped_anchor(binding::Union{SiteBinding, CellBinding}) = getfield(binding, :domain) !== nothing
_anchor_token_name(binding::Union{SiteBinding, CellBinding}) =
    Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(_binding_token(binding))))

function Base.getproperty(binding::Union{SiteBinding, CellBinding}, name::Symbol)
    name === :name || return getfield(binding, name)
    scoped = _scoped_anchor(binding)
    text = String(_anchor_token_name(binding))
    local_name = scoped ? last(split(text, '₊')) : text
    prefix = binding isa SiteBinding ?
        (_scoped_anchor(binding) ? "__potts_scoped_site__" : "__potts_energy_site__") :
        (_scoped_anchor(binding) ? "__potts_scoped_cell__" : "__potts_energy_cell__")
    suffix = chopprefix(local_name, prefix)
    # Scoped suffixes encode the lexical name so namespace separators inside a
    # user name cannot be confused with component qualification.
    return scoped ? Symbol(String(hex2bytes(suffix))) : Symbol(suffix)
end
Base.propertynames(::Union{SiteBinding, CellBinding}, private::Bool = false) = (:name, :domain, :token)

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
    print(
    io, "RelationshipBinding(", repr(binding.name), ", ",
    repr(Symbol(statement_id(binding.relationship))), ")"
)

_binding_token(binding::ProposalContext) = getfield(binding, :token)
_binding_token(binding::SiteBinding) = getfield(binding, :token)
_binding_token(binding::CellBinding) = getfield(binding, :token)
_binding_token(binding::ContactBinding) = getfield(binding, :token)
_binding_token(binding::RelationshipBinding) = getfield(binding, :token)

"""Return the symbolic identity selected by a site, cell, contact, or relationship anchor."""
anchor_value(
    binding::Union{
        SiteBinding, CellBinding, ContactBinding, RelationshipBinding,
    }
) = _binding_token(binding)

_gather_anchor(
    binding::Union{
        SiteBinding, CellBinding, ContactBinding, RelationshipBinding,
    }
) = _binding_token(binding)
_gather_anchor(::ProposalContext) = throw(
    ArgumentError(
        "gather requires a concrete proposal property such as " *
            "`proposal.target_site`, not a bare ProposalContext",
    )
)
_gather_anchor(value::Symbolics.Num) = value
_gather_anchor(value) = throw(
    ArgumentError(
        "gather anchor must be a SiteBinding, CellBinding, ContactBinding, " *
            "RelationshipBinding, or a concrete symbolic proposal property; got " *
            string(typeof(value)),
    )
)

struct _GatherSiteValue{S, B <: SiteBinding}
    source::S
    binding::B
end

"""Bind one declared site or field state value to a relation-gather lane."""
function site_value(source::Union{SiteState, FieldState}, binding::SiteBinding)
    return _GatherSiteValue(source, binding)
end

struct _GatherSiteOwner{B <: SiteBinding}
    binding::B
end

"""Return the owner identity at a bound relation-gather site."""
site_owner(binding::SiteBinding) = _GatherSiteOwner(binding)

struct _GatherExactOwnerFilter{B <: SiteBinding, O}
    binding::B
    owner::O
end

function Base.:(==)(site::_GatherSiteOwner, owner::Symbolics.Num)
    return _GatherExactOwnerFilter(site.binding, owner)
end
Base.:(==)(owner::Symbolics.Num, site::_GatherSiteOwner) = site == owner

struct _RelationGather{S, R, A, B, F}
    source::S
    relation::R
    anchor::A
    binding::B
    filter::F
end

function _gather_relation(over)
    over isa Union{Symbol, SpatialRelation} || throw(
        ArgumentError(
            "gather over requires a declared SpatialRelation or its local name"
        )
    )
    return over
end

function _gather_filter(where, binding)
    where === nothing && return nothing
    where isa _GatherExactOwnerFilter || throw(ArgumentError(
        "gather where currently requires `site_owner(binding) == proposal.source_cell` " *
            "or the corresponding target-cell expression"
    ))
    binding isa SiteBinding || throw(ArgumentError(
        "an owner-filtered gather requires one explicit SiteBinding"
    ))
    where.binding === binding || throw(ArgumentError(
        "gather where must reference the binding supplied through `bind`"
    ))
    return where
end

"""Return whether a unary operation is exactly one direct scalar tracker view."""
is_direct_scalar_tracker_projection(::Any) = false

"""
    gather(source; at, over)

Gather the finite values reached from `at` through `relation` as
the input to `LocalMath.fold`. This is a cold symbolic declaration;
the Potts compiler resolves both resources and removes the declaration before
execution planning.
"""
function gather(field::FieldState; at, over)
    return _RelationGather(
        field, _gather_relation(over), _gather_anchor(at), nothing, nothing
    )
end

"""
    gather(site_value(state, binding); bind, at, over, where=nothing)

Gather one declared site-local state through a bounded relation. `bind` names
the visited lane and `where` may select the exact owner visible at proposal
entry. The declaration is removed during lowering.
"""
function gather(value::_GatherSiteValue; bind, at, over, where = nothing)
    bind isa SiteBinding || throw(ArgumentError(
        "a lane-bound gather requires `bind` to be a SiteBinding"
    ))
    value.binding === bind || throw(ArgumentError(
        "site_value and gather must use the same SiteBinding"
    ))
    filter = _gather_filter(where, bind)
    return _RelationGather(
        value, _gather_relation(over), _gather_anchor(at), bind, filter
    )
end

"""
    gather(tracker_operation; at, over)

Declare tracker values reached by mapping each relation endpoint site to its
finite current owner and reading a unary direct scalar tracker projection such
as `cell_volume`. Extension operations opt in with
`is_direct_scalar_tracker_projection(::typeof(operation)) = true`. Values follow
relation-lane order: repeated owners remain
repeated, while absent boundary lanes and medium endpoints do not participate
in the consuming `LocalMath.BoundedFold`.
"""
function gather(operation; at, over)
    relation = _gather_relation(over)
    transfer = try
        operation_transfer(operation, 1)
    catch error
        error isa MethodError && error.f === operation_transfer || rethrow(error)
        throw(
            ArgumentError(
                "gather tracker sources must be registered unary Potts operations"
            )
        )
    end
    transfer.result_rule === :real || throw(
        ArgumentError(
            "gather tracker operations must return one scalar real value"
        )
    )
    :Proposal in transfer.allowed_phases || throw(
        ArgumentError(
            "gather tracker operations must support proposal evaluation"
        )
    )
    (
        !isempty(transfer.tracker_requirements) ||
            transfer.identity === :cell_volume
    ) || throw(
        ArgumentError(
            "gather accepts only operations backed by a declared tracker"
        )
    )
    is_direct_scalar_tracker_projection(operation) || throw(
        ArgumentError(
            "gather requires a declared direct scalar tracker projection"
        )
    )
    all(
        requirement -> requirement isa NamedSpatialRelationRequirement,
        transfer.source_requirements
    ) || throw(
        ArgumentError(
            "gathered tracker projections currently require only named spatial resources"
        )
    )
    return _RelationGather(
        operation, relation, _gather_anchor(at), nothing, nothing
    )
end

@enum _GatherReductionKind::UInt8 begin
    _GatherSum = 0x01
    _GatherMinimum = 0x02
    _GatherMaximum = 0x03
    _GatherMean = 0x04
    _GatherGeometricMean = 0x05
end

struct _GatherReduction
    kind::_GatherReductionKind
end

# SymbolicUtils canonically orders literal operation arguments while building a
# normalized expression. This cold tag order is part of Potts's deterministic
# source representation; the tag is replaced by a checked BoundedFold before
# Core planning.
Base.isless(left::_GatherReduction, right::_GatherReduction) =
    UInt8(left.kind) < UInt8(right.kind)
Base.isless(::Type{_GatherReduction}, ::Type{_GatherReduction}) = false

function _symbolic_gather_fold(fold, values::_RelationGather)
    source = if values.source isa FieldState
        _field_token(values.source)
    elseif values.source isa _GatherSiteValue
        state = values.source.source
        state isa SiteState ? _site_state_token(state) : _field_token(state)
    else
        values.source(values.anchor)
    end
    filter_enabled = values.filter !== nothing
    filter_owner = filter_enabled ? values.filter.owner : 0
    return _potts_bounded_fold(
        fold,
        source,
        _spatial_relation_token(values.relation),
        values.anchor,
        filter_enabled,
        filter_owner,
    )
end

function (fold::LocalMath.BoundedFold)(values::_RelationGather)
    return _symbolic_gather_fold(fold, values)
end

"""Lower data-first LocalMath folds over Potts relation gathers symbolically."""
function LocalMath.fold(values::_RelationGather; kwargs...)
    return invoke(LocalMath.fold, Tuple{Any}, values; kwargs...)
end

Base.sum(values::_RelationGather) =
    _symbolic_gather_fold(_GatherReduction(_GatherSum), values)
Base.minimum(values::_RelationGather) =
    _symbolic_gather_fold(_GatherReduction(_GatherMinimum), values)
Base.maximum(values::_RelationGather) =
    _symbolic_gather_fold(_GatherReduction(_GatherMaximum), values)
Statistics.mean(values::_RelationGather) =
    _symbolic_gather_fold(_GatherReduction(_GatherMean), values)
LocalMath.geometric_mean(values::_RelationGather) =
    _symbolic_gather_fold(_GatherReduction(_GatherGeometricMean), values)

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
    SiteBinding(_map_symbolic_payload(f, binding.domain), f(_binding_token(binding)))
map_symbolics(f, binding::CellBinding) =
    CellBinding(_map_symbolic_payload(f, binding.domain), f(_binding_token(binding)))
map_symbolics(f, binding::ContactBinding) =
    ContactBinding(binding.name, binding.relation, f(_binding_token(binding)))

map_symbolics(f, binding::RelationshipBinding) =
    RelationshipBinding(binding.name, binding.relationship, f(_binding_token(binding)))
