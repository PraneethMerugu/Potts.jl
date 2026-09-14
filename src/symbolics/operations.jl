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
function _potts_cell_bound_state_value end
function _potts_lifecycle_bound_state_value end
function _potts_bounded_fold end
function _potts_cell_site_sum end
function _potts_cell_site_minimum end
"""Test whether two endpoints are linked by a relationship state."""
function linked end

Symbolics.@register_symbolic new_contact(x, y)::Bool
Symbolics.@register_symbolic lost_contact(x, y)::Bool
Symbolics.@register_symbolic linked(relationship, a, b)::Bool
Symbolics.@register_symbolic edge_payload(edge, payload)::Real
function lag(state, amount)
    SymbolicIndexingInterface.symbolic_type(state) isa Union{
        SymbolicIndexingInterface.ScalarSymbolic,
        SymbolicIndexingInterface.ArraySymbolic,
    } || throw(ArgumentError("lag requires a symbolic history reference"))
    value = Symbolics.unwrap(state)
    if SymbolicUtils.iscall(value) && SymbolicUtils.operation(value) isa _ProductField
        # Field selection commutes with a read-only sample selection. Keep the
        # whole history variable as the sole sampled storage owner.
        field = SymbolicUtils.operation(value)
        sampled = lag(only(SymbolicUtils.arguments(value)), amount)
        return Symbolics.wrap(Symbolics.term(field, Symbolics.unwrap(sampled)))
    end
    return Symbolics.wrap(Symbolics.term(lag, value, Symbolics.unwrap(amount)))
end
SymbolicUtils.promote_symtype(::typeof(lag), ::Type{T}, ::Type) where {T} = T
SymbolicUtils.promote_shape(::typeof(lag), state::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT) = state

"""
    aggregate(expression; over::SiteBinding, by::CellBinding, combine=+, empty=nothing,
              maximum_sites=nothing, atol=0, rtol=0)

Sum a site-local expression over the lattice sites owned by the bound cell.
`over` and `by` are declared lexical site and cell bindings, including those
supplied by `scoped`. The expression may use declared site values and runtime
parameters. Floating scalar contributions preserve their units; literal integer
one reuses the exact owner count. Empty owners have
the corresponding typed additive zero. Identical contributions share maintained
storage even when read by different consumers.

`atol` and `rtol` declare elementwise acceptance tolerances when cached sums are
compared with an independent canonical rebuild. Both default to exact zero;
they are not promised accumulation-error bounds and never trigger silent repair.
Nonzero `atol` has the contribution's physical units; `rtol` is dimensionless.

With `combine=min`, `empty` declares the finite result for an owner with no
sites and `maximum_sites` declares the finite full-lattice reconstruction bound.
Both are required. Minimum is restricted to scalar `Float32` execution.

This is a live owner-grouped quantity, not a bounded neighborhood fold or an
independently writable state. Other reductions require their own explicit
maintenance/rebuild contract. Scalar CPU sum execution is qualified. Fixed-array
sum contributions and scheduled source updates use the same maintained-quantity
path. Backend support is established by the selected execution profile's
behavioral tests.
"""
function aggregate(
        expression; over, by, combine = +, empty = nothing,
        maximum_sites = nothing, atol = 0, rtol = 0,
    )
    over isa SiteBinding && _scoped_anchor(over) ||
        throw(ArgumentError("aggregate over requires a declared SiteBinding from sites(lattice)"))
    by isa CellBinding && _scoped_anchor(by) ||
        throw(ArgumentError("aggregate by requires a declared CellBinding from cells(kind)"))
    operation = if combine === (+)
        empty === nothing || throw(ArgumentError("additive aggregate does not accept an empty-owner override"))
        maximum_sites === nothing || throw(ArgumentError("additive aggregate does not accept a reconstruction bound"))
        _potts_cell_site_sum
    elseif combine === min
        empty === nothing && throw(ArgumentError("minimum aggregate requires a finite empty-owner value"))
        maximum_sites === nothing && throw(ArgumentError("minimum aggregate requires a maximum_sites reconstruction bound"))
        isequal(atol, 0) && isequal(rtol, 0) || throw(ArgumentError(
            "minimum aggregate does not use additive comparison tolerances"
        ))
        _potts_cell_site_minimum
    else
        throw(ArgumentError(
            "aggregate supports combine=+ and bounded scalar combine=min; other laws require an explicit maintenance/rebuild contract"
        ))
    end
    operands = operation === _potts_cell_site_sum ?
        (
            Symbolics.unwrap(expression), Symbolics.unwrap(_binding_token(over)),
            Symbolics.unwrap(_binding_token(by)), Symbolics.unwrap(atol),
            Symbolics.unwrap(rtol),
        ) :
        (
            Symbolics.unwrap(expression), Symbolics.unwrap(_binding_token(over)),
            Symbolics.unwrap(_binding_token(by)), Symbolics.unwrap(empty),
            Symbolics.unwrap(maximum_sites),
        )
    return Symbolics.wrap(
        Symbolics.term(operation, operands...)
    )
end
SymbolicUtils.promote_symtype(::typeof(_potts_cell_site_sum), ::Type{T}, ::Type, ::Type, ::Type, ::Type) where {T} = T
SymbolicUtils.promote_shape(::typeof(_potts_cell_site_sum), source::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT) = source
SymbolicUtils.promote_symtype(::typeof(_potts_cell_site_minimum), ::Type{T}, ::Type, ::Type, ::Type, ::Type) where {T} = T
SymbolicUtils.promote_shape(::typeof(_potts_cell_site_minimum), source::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT, ::SymbolicUtils.ShapeT) = source
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

# Reduction tags are cold and scalar-profile independent. Completion replaces
# them with a checked concrete `BoundedFold` before Core planning.
function _potts_bounded_fold(
        fold::_GatherReduction,
        field::Symbolics.Num,
        relation::Symbolics.Num,
        anchor::Symbolics.Num,
    )
    return Symbolics.wrap(Symbolics.term(
        _potts_bounded_fold,
        fold,
        Symbolics.unwrap(field),
        Symbolics.unwrap(relation),
        Symbolics.unwrap(anchor);
        type = Real,
    ))
end

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
