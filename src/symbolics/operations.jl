# Closed Potts operation vocabulary. Public wrappers are registered through Symbolics and
# are therefore ordinary Symbolics call trees rather than a parallel expression algebra.

for (operation_name, result_type) in (
        (:source_site, Int),
        (:target_site, Int),
        (:source_cell, Int),
        (:target_cell, Int),
        (:source_kind, Int),
        (:target_kind, Int),
        (:contact_owner_a, Int),
        (:contact_owner_b, Int),
        (:contact_kind_a, Int),
        (:contact_kind_b, Int),
        (:is_extension, Bool),
        (:is_retraction, Bool),
        (:cell_volume, Real),
        (:cell_surface, Real),
        (:cell_elongation, Real),
        (:cell_center, Real),
        (:unwrapped_center, Real),
        (:endpoint_a, Int),
        (:endpoint_b, Int),
    )
    @eval begin
        function $(operation_name) end
        Symbolics.@register_symbolic $(operation_name)(x)::$(result_type)
    end
end

for (operation_name, result_type) in (
        (:distance, Real),
        (:contact_measure, Real),
        (:boundary_measure, Real),
        (:neighbor_count, Int),
        (:neighbor_sum, Real),
        (:neighbor_mean, Real),
        (:neighbor_geomean, Real),
        (:field_value, Real),
        (:field_gradient, Real),
        (:laplacian, Real),
        (:occupancy, Real),
        (:history_value, Real),
        (:degree, Int),
    )
    @eval begin
        function $(operation_name) end
        Symbolics.@register_symbolic $(operation_name)(x, y)::$(result_type)
    end
end

function new_contact end
function lost_contact end
function edge_payload end
function lag end
function _potts_draw end
function _potts_merks_local_connectivity end
function _potts_act_energy end
function _potts_explicit_field_euler end
function _potts_proposal_bound_state_value end
function _potts_iteration_bound_state_value end
function linked end

Symbolics.@register_symbolic new_contact(x, y)::Bool
Symbolics.@register_symbolic lost_contact(x, y)::Bool
Symbolics.@register_symbolic linked(relationship, a, b)::Bool
Symbolics.@register_symbolic edge_payload(edge, payload)::Real
Symbolics.@register_symbolic lag(state, amount)::Real
Symbolics.@register_symbolic _potts_draw(family, a, b, key)::Real
Symbolics.@register_symbolic _potts_merks_local_connectivity(
    kind, foreground, background
)::Bool
Symbolics.@register_symbolic _potts_act_energy(
    kind, activity, relation, maximum, strength
)::Real

_kind_token(kind::Union{CellKind, MediumKind}) =
    _potts_token(Symbol("__potts_kind__", Symbol(statement_id(kind))); T = Int)
_relationship_token(relationship::RelationshipState) =
    _potts_token(
        Symbol("__potts_relationship_set__", Symbol(statement_id(relationship)));
        T = Int,
    )
_spatial_relation_token(relation::Symbol) =
    _potts_token(Symbol("__potts_spatial_relation__", relation); T = Int)
_field_token(field::FieldState) =
    _potts_token(
        Symbol("__potts_field__", Symbol(statement_id(field))); T = Real
    )

const _MERKS_CLOCKWISE_OFFSETS = (
    (-1, -1),
    (0, -1),
    (1, -1),
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
)

struct MerksLocalConnectivityCallable <: CorePotts.AbstractContextualOperation end
struct ActEnergyCallable <: CorePotts.AbstractContextualOperation end
struct ExplicitFieldEulerCallable <: CorePotts.AbstractContextualOperation end

CorePotts.operation_context_supported(
    ::MerksLocalConnectivityCallable,
    ::Type{CorePotts.AbstractProposalEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::ActEnergyCallable,
    ::Type{CorePotts.AbstractProposalEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::ExplicitFieldEulerCallable,
    ::Type{CorePotts.AbstractSiteStageEvaluationContext},
) = true

function CorePotts.operation_callable(
        ::Val{:merks_local_connectivity},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported Merks local-connectivity operation version $version"
    ))
    return MerksLocalConnectivityCallable()
end

@inline function (operation::ExplicitFieldEulerCallable)(
        arguments::Tuple, context
    )
    state_handle = arguments[1]
    relation_handle = Int32(arguments[2])
    diffusion = arguments[3]
    decay = arguments[4]
    secretion = arguments[5]
    source_kind = Int16(arguments[6])
    timestep = arguments[7]
    T = promote_type(
        typeof(diffusion), typeof(decay), typeof(secretion), typeof(timestep)
    )
    site = CorePotts.stage_site(CorePotts.IterationStageSite(), context)
    center = T(CorePotts.state_value(context, state_handle, site))
    laplace = zero(T)
    for direction in 1:CorePotts.relation_count(context, relation_handle)
        neighbor = CorePotts.relation_neighbor_site(
            context, relation_handle, site, direction
        )
        neighbor === nothing && continue
        laplace += T(CorePotts.state_value(
            context, state_handle, neighbor
        )) - center
    end
    owner = CorePotts.site_owner(context, site)
    source = owner > 0 && source_kind != 0 &&
             CorePotts.owner_kind(context, owner) == source_kind ?
             T(secretion) : zero(T)
    return max(
        zero(T),
        center + T(timestep) * (
            T(diffusion) * laplace - T(decay) * center + source
        ),
    )
end

function CorePotts.operation_callable(
        ::Val{:explicit_field_euler},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported explicit-field-Euler operation version $version"
    ))
    return ExplicitFieldEulerCallable()
end

function CorePotts.operation_callable(
        ::Val{:act_energy},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported Act-energy operation version $version"
    ))
    return ActEnergyCallable()
end

@inline function (operation::MerksLocalConnectivityCallable)(
        arguments::Tuple, context
    )
    kind = Int16(arguments[1])
    foreground = Int32(arguments[2])
    background = Int32(arguments[3])
    CorePotts.proposal_relation_count(context, foreground) == 8 || return false
    CorePotts.proposal_relation_count(context, background) == 4 || return false

    losing = CorePotts.proposal_target_owner(context)
    losing <= 0 && return true
    CorePotts.proposal_target_kind(context) == kind || return true
    owners = ntuple(Val(8)) do position
        CorePotts.proposal_relation_neighbor_owner(
            context,
            foreground,
            _MERKS_CLOCKWISE_OFFSETS[position],
        )
    end
    any(==(typemin(Int32)), owners) && return false
    same = map(owner -> owner == losing, owners)
    collisions = 0
    for position in 1:8
        same[position] || continue
        previous = position == 1 ? 8 : position - 1
        next = position == 8 ? 1 : position + 1
        collisions += 2 - Int(same[previous]) - Int(same[next])
    end
    collisions <= 2 && return true

    distinct_cells = 0
    for position in 1:8
        owner = owners[position]
        owner > 0 || continue
        seen = false
        for earlier in 1:(position - 1)
            if owners[earlier] == owner
                seen = true
                break
            end
        end
        distinct_cells += !seen
    end
    return distinct_cells == 2
end

@inline function _act_local_geomean(
        context,
        state_handle,
        relation_handle,
        center,
        owner::Int32,
        ::Type{T},
    ) where {T <: AbstractFloat}
    owner <= 0 && return zero(T)
    total = zero(T)
    count = 0
    if CorePotts.proposal_site_owner(context, center) == owner
        value = T(CorePotts.state_value(context, state_handle, center))
        total += log1p(max(zero(T), value))
        count += 1
    end
    for direction in 1:CorePotts.proposal_relation_count(
            context, relation_handle
        )
        neighbor = CorePotts.proposal_relation_neighbor_site(
            context, relation_handle, center, direction
        )
        neighbor === nothing && continue
        CorePotts.proposal_site_owner(context, neighbor) == owner || continue
        value = T(CorePotts.state_value(context, state_handle, neighbor))
        total += log1p(max(zero(T), value))
        count += 1
    end
    return iszero(count) ? zero(T) : exp(total / T(count)) - one(T)
end

@inline function (operation::ActEnergyCallable)(arguments::Tuple, context)
    kind = Int16(arguments[1])
    state_handle = arguments[2]
    relation_handle = Int32(arguments[3])
    maximum = arguments[4]
    strength = arguments[5]
    T = promote_type(typeof(maximum), typeof(strength))
    new_owner = Int32(CorePotts.proposal_source_owner(context))
    new_owner > 0 || return zero(T)
    CorePotts.proposal_source_kind(context) == kind || return zero(T)
    maximum > zero(T) || return zero(T)
    source_activity = _act_local_geomean(
        context,
        state_handle,
        relation_handle,
        CorePotts.proposal_source_site(context),
        new_owner,
        T,
    )
    old_owner = Int32(CorePotts.proposal_target_owner(context))
    target_activity = _act_local_geomean(
        context,
        state_handle,
        relation_handle,
        CorePotts.proposal_target_site(context),
        old_owner,
        T,
    )
    return -(strength / maximum) * (source_activity - target_activity)
end

cell_volume(kind::Union{CellKind, MediumKind}) = cell_volume(_kind_token(kind))
cell_surface(kind::Union{CellKind, MediumKind}) = cell_surface(_kind_token(kind))
cell_volume(binding::CellBinding) = cell_volume(_binding_token(binding))
cell_surface(binding::CellBinding) = cell_surface(_binding_token(binding))
cell_elongation(binding::CellBinding) = cell_elongation(_binding_token(binding))
contact_owner_a(binding::ContactBinding) = contact_owner_a(_binding_token(binding))
contact_owner_b(binding::ContactBinding) = contact_owner_b(_binding_token(binding))
contact_kind_a(binding::ContactBinding) = contact_kind_a(_binding_token(binding))
contact_kind_b(binding::ContactBinding) = contact_kind_b(_binding_token(binding))
occupancy(kind::Union{CellKind, MediumKind}, site) = occupancy(_kind_token(kind), site)
occupancy(kind::Union{CellKind, MediumKind}, site::SiteBinding) =
    occupancy(_kind_token(kind), _binding_token(site))
occupancy(kind::Union{CellKind, MediumKind}, site::Symbol) =
    occupancy(_kind_token(kind), _potts_token(site; T = Int))
linked(relationship::RelationshipState, a, b) =
    linked(_relationship_token(relationship), a, b)
field_value(field::FieldState, site) = field_value(_field_token(field), site)
field_gradient(field::FieldState, site) = field_gradient(_field_token(field), site)
laplacian(field::FieldState, relation) =
    laplacian(_field_token(field), relation)
degree(relationship::RelationshipState, cell) =
    degree(_relationship_token(relationship), cell)
edge_payload(edge, ::Val{name}) where {name} =
    edge_payload(
        edge, _potts_token(Symbol("__potts_payload__", name); T = Int)
    )

source_site(binding::ProposalContext) = source_site(_binding_token(binding))
target_site(binding::ProposalContext) = target_site(_binding_token(binding))
source_cell(binding::ProposalContext) = source_cell(_binding_token(binding))
target_cell(binding::ProposalContext) = target_cell(_binding_token(binding))
source_kind(binding::ProposalContext) = source_kind(_binding_token(binding))
target_kind(binding::ProposalContext) = target_kind(_binding_token(binding))
is_extension(binding::ProposalContext) = is_extension(_binding_token(binding))
is_retraction(binding::ProposalContext) = is_retraction(_binding_token(binding))
