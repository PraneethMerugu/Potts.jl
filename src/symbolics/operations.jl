# Closed Potts operation vocabulary. Public wrappers are registered through Symbolics and
# are therefore ordinary Symbolics call trees rather than a parallel expression algebra.

"""Return the proposed source-site identity."""
function source_site end
"""Return the proposed destination-site identity."""
function target_site end
"""Return the source site's owning cell identity."""
function source_cell end
"""Return the destination site's owning cell identity."""
function target_cell end
"""Return the source owner's cell-kind identity."""
function source_kind end
"""Return the destination owner's cell-kind identity."""
function target_kind end
"""Return the first canonical contact owner."""
function contact_owner_a end
"""Return the second canonical contact owner."""
function contact_owner_b end
"""Return the first canonical contact owner's kind."""
function contact_kind_a end
"""Return the second canonical contact owner's kind."""
function contact_kind_b end
"""Test whether a proposal extends the source cell."""
function is_extension end
"""Test whether a proposal retracts the destination cell."""
function is_retraction end
"""Return the current cell-volume tracker value."""
function cell_volume end
"""Return the current cell-surface tracker value."""
function cell_surface end
"""Return the current cell-elongation tracker value."""
function cell_elongation end
"""Return the wrapped cell-center coordinates."""
function cell_center end
"""Return the unwrapped cell-center coordinates."""
function unwrapped_center end
"""Return the first endpoint of the current relationship edge."""
function endpoint_a end
"""Return the second endpoint of the current relationship edge."""
function endpoint_b end

"""Return the metric distance between two bounded spatial values."""
function distance end
"""Return the number of lattice edges in a canonical contact."""
function contact_edge_count end
"""Return the number of boundary sites of a finite cell."""
function boundary_site_count end
"""Return the number of distinct neighboring cells selected by a relation."""
function neighbor_cell_count end
"""Sample a declared field at a bounded site."""
function field_value end
"""Sample the gradient of a declared field at a bounded site."""
function field_gradient end
"""Evaluate a declared relation-based field Laplacian."""
function laplacian end
"""Return the occupancy indicator for a kind at a site."""
function occupancy end
"""Read a declared history state at a bounded lag."""
function history_value end
"""Return the live degree of an endpoint in a relationship state."""
function degree end

"""Return the measure associated with a canonical contact."""
function contact_measure end
"""Return the sum of a neighboring-cell property."""
function neighbor_property_sum end
"""Return a model-wide interface measure for a pair of kinds."""
function global_interface_measure end

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
        Symbolics.@register_symbolic $(operation_name)(x)::$(result_type)
    end
end

for (operation_name, result_type) in (
        (:distance, Real),
        (:contact_edge_count, Int),
        (:boundary_site_count, Int),
        (:neighbor_cell_count, Int),
        (:field_value, Real),
        (:field_gradient, Real),
        (:laplacian, Real),
        (:occupancy, Real),
        (:history_value, Real),
        (:degree, Int),
    )
    @eval begin
        Symbolics.@register_symbolic $(operation_name)(x, y)::$(result_type)
    end
end

for (operation_name, result_type) in (
        (:contact_measure, Real),
        (:neighbor_property_sum, Real),
        (:global_interface_measure, Real),
    )
    @eval begin
        Symbolics.@register_symbolic $(operation_name)(x, y, z)::$(result_type)
    end
end

# A mean is total only when its empty-neighborhood behavior is explicit. The
# fourth argument is that policy/value; the compiler deliberately admits no
# ambiguous three-argument spelling.
"""Return the mean of a neighboring-cell property under an explicit empty policy."""
function neighbor_property_mean end
Symbolics.@register_symbolic neighbor_property_mean(x, y, z, empty)::Real

# `neighbor_cells` is collection-valued settled-snapshot vocabulary, not a
# scalar operation in the current executable DAG. Reject at authoring time
# until the bounded snapshot query object exists; pretending it returns a
# scalar would corrupt its distinct-identity semantics.
"""Collection-valued neighbor query; currently rejects until bounded materialization exists."""
function neighbor_cells(owner, filter)
    throw(ArgumentError(
        "neighbor_cells(owner, filter) is a collection-valued settled-snapshot " *
                "query; executable collection materialization is not implemented. " *
        "Use neighbor_cell_count(owner, filter) when only cardinality is needed."
    ))
end

"""Test whether a contact is created by the proposal."""
function new_contact end
"""Test whether a contact is removed by the proposal."""
function lost_contact end
"""Read a named payload component from the current relationship edge."""
function edge_payload end
"""Construct a bounded lagged read of history state."""
function lag end
function _potts_draw end
function _potts_merks_local_connectivity end
function _potts_act_energy end
function _potts_proposal_bound_state_value end
function _potts_iteration_bound_state_value end
function _potts_model_bound_state_value end
function _potts_lifecycle_bound_state_value end
function _potts_bounded_fold end
"""Test whether two endpoints are linked by a relationship state."""
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
Symbolics.@register_symbolic _potts_bounded_fold(
    fold::LocalMath.BoundedFold, field, relation, anchor
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
_spatial_relation_token(relation::SpatialRelation) =
    _spatial_relation_token(Symbol(statement_id(relation)))
_field_token(field::FieldState) =
    _potts_token(
        Symbol("__potts_field__", Symbol(statement_id(field))); T = Real
    )

cell_volume(kind::Union{CellKind, MediumKind}) = cell_volume(_kind_token(kind))
cell_surface(kind::Union{CellKind, MediumKind}) = cell_surface(_kind_token(kind))
cell_volume(binding::CellBinding) = cell_volume(_binding_token(binding))
is_direct_scalar_tracker_projection(::typeof(cell_volume)) = true
is_direct_scalar_tracker_projection(::typeof(cell_surface)) = true
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
