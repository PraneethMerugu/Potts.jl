"""Sentinel distinguishing an omitted spatial role from an explicitly disabled role."""
struct OmittedSpatialRole end

const OMITTED_SPATIAL_ROLE = OmittedSpatialRole()

"""
    SpatialRoles(; proposal, contact, surface, connectivity, query, field)

Immutable explicit scientific-role record. Omitted entries retain the Phase 13 lowering for that
role. `connectivity=nothing` is an explicit disable request and is therefore distinct from
omission.
"""
struct SpatialRoles{P, C, S, K, Q, F}
    proposal::P
    contact::C
    surface::S
    connectivity::K
    query::Q
    field::F
end

function _validate_spatial_role(value, ::Type{R}, label::Symbol;
        allow_nothing::Bool = false) where {R <: AbstractSpatialRole}
    value isa OmittedSpatialRole && return value
    allow_nothing && value === nothing && return value
    value isa StaticCartesianRelation{<:R} || throw(ArgumentError(
        "spatial role `$label` requires a $(nameof(R))-typed StaticCartesianRelation"))
    return value
end

function SpatialRoles(; proposal = OMITTED_SPATIAL_ROLE,
        contact = OMITTED_SPATIAL_ROLE, surface = OMITTED_SPATIAL_ROLE,
        connectivity = OMITTED_SPATIAL_ROLE, query = OMITTED_SPATIAL_ROLE,
        field = OMITTED_SPATIAL_ROLE)
    _validate_spatial_role(proposal, ProposalRole, :proposal)
    _validate_spatial_role(contact, ContactRole, :contact)
    _validate_spatial_role(surface, SurfaceRole, :surface)
    _validate_spatial_role(connectivity, ConnectivityRole, :connectivity;
        allow_nothing = true)
    _validate_spatial_role(query, SpatialQueryRole, :query)
    _validate_spatial_role(field, FieldDiscretizationRole, :field)
    return SpatialRoles(proposal, contact, surface, connectivity, query, field)
end

component_identity(::SpatialRoles) =
    ComponentIdentity(:spatial_roles, v"1.0.0", :spatial_roles)

_spatial_role_semantics(::OmittedSpatialRole) = :omitted
_spatial_role_semantics(::Nothing) = :disabled
function _spatial_role_semantics(relation::StaticCartesianRelation)
    report = relation_semantics_report(relation)
    version = report.canonicalization_version
    return (
        role = report.role,
        dimensions = report.dimensions,
        direction_count = report.direction_count,
        canonicalization_version = (version.major, version.minor, version.patch),
        offsets = report.offsets,
        weights = report.weights,
        opposite_directions = report.opposite_directions,
        symmetric = report.symmetric,
    )
end

component_semantic_data(roles::SpatialRoles) = (
    proposal = _spatial_role_semantics(roles.proposal),
    contact = _spatial_role_semantics(roles.contact),
    surface = _spatial_role_semantics(roles.surface),
    connectivity = _spatial_role_semantics(roles.connectivity),
    query = _spatial_role_semantics(roles.query),
    field = _spatial_role_semantics(roles.field),
)
required_relations(roles::SpatialRoles) = Tuple(value for value in (
    roles.proposal, roles.contact, roles.surface, roles.connectivity,
    roles.query, roles.field) if value isa StaticCartesianRelation)
component_effects(::SpatialRoles) = (:model_spatial_roles,)

"""Return the relation assigned to one explicit scientific role."""
relation_for(roles::SpatialRoles, ::ProposalRole) = roles.proposal
relation_for(roles::SpatialRoles, ::ContactRole) = roles.contact
relation_for(roles::SpatialRoles, ::SurfaceRole) = roles.surface
relation_for(roles::SpatialRoles, ::ConnectivityRole) = roles.connectivity
relation_for(roles::SpatialRoles, ::SpatialQueryRole) = roles.query
relation_for(roles::SpatialRoles, ::FieldDiscretizationRole) = roles.field
spatial_roles(roles::SpatialRoles) = roles
