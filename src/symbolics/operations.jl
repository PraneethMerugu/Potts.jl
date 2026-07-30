# Closed Potts operation vocabulary. Public wrappers are registered through Symbolics and
# are therefore ordinary Symbolics call trees rather than a parallel expression algebra.

for (operation_name, result_type) in (
        (:source_site, Int),
        (:target_site, Int),
        (:source_cell, Int),
        (:target_cell, Int),
        (:source_kind, Int),
        (:target_kind, Int),
        (:is_extension, Bool),
        (:is_retraction, Bool),
        (:cell_volume, Real),
        (:cell_surface, Real),
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
        (:linked, Bool),
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

Symbolics.@register_symbolic new_contact(x, y)::Bool
Symbolics.@register_symbolic lost_contact(x, y)::Bool
Symbolics.@register_symbolic edge_payload(edge, payload)::Real
Symbolics.@register_symbolic lag(state, amount)::Real
Symbolics.@register_symbolic _potts_draw(family, a, b, key)::Real

_kind_token(kind::Union{CellKind, MediumKind}) =
    Symbolics.variable(Symbol("__potts_kind__", Symbol(statement_id(kind))); T = Int)
_relationship_token(relationship::RelationshipState) =
    Symbolics.variable(
        Symbol("__potts_relationship_set__", Symbol(statement_id(relationship))); T = Int
    )

cell_volume(kind::Union{CellKind, MediumKind}) = cell_volume(_kind_token(kind))
cell_surface(kind::Union{CellKind, MediumKind}) = cell_surface(_kind_token(kind))
occupancy(kind::Union{CellKind, MediumKind}, site) = occupancy(_kind_token(kind), site)
linked(relationship::RelationshipState, a, b) =
    linked(_relationship_token(relationship), a, b)
degree(relationship::RelationshipState, cell) =
    neighbor_count(_relationship_token(relationship), cell)
edge_payload(edge, ::Val{name}) where {name} =
    edge_payload(edge, Symbolics.variable(Symbol("__potts_payload__", name); T = Int))

source_site(binding::ProposalContext) = source_site(_binding_token(binding))
target_site(binding::ProposalContext) = target_site(_binding_token(binding))
source_cell(binding::ProposalContext) = source_cell(_binding_token(binding))
target_cell(binding::ProposalContext) = target_cell(_binding_token(binding))
source_kind(binding::ProposalContext) = source_kind(_binding_token(binding))
target_kind(binding::ProposalContext) = target_kind(_binding_token(binding))
is_extension(binding::ProposalContext) = is_extension(_binding_token(binding))
is_retraction(binding::ProposalContext) = is_retraction(_binding_token(binding))

