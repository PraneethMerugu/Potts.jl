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
        (:degree, Int),
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
function linked end

Symbolics.@register_symbolic new_contact(x, y)::Bool
Symbolics.@register_symbolic lost_contact(x, y)::Bool
Symbolics.@register_symbolic linked(relationship, a, b)::Bool
Symbolics.@register_symbolic edge_payload(edge, payload)::Real
Symbolics.@register_symbolic lag(state, amount)::Real
Symbolics.@register_symbolic _potts_draw(family, a, b, key)::Real

_kind_token(kind::Union{CellKind, MediumKind}) =
    _potts_token(Symbol("__potts_kind__", Symbol(statement_id(kind))); T = Int)
_relationship_token(relationship::RelationshipState) =
    _potts_token(
        Symbol("__potts_relationship_set__", Symbol(statement_id(relationship)));
        T = Int,
    )
_field_token(field::FieldState) =
    _potts_token(
        Symbol("__potts_field__", Symbol(statement_id(field))); T = Real
    )

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
    neighbor_count(_relationship_token(relationship), cell)
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
