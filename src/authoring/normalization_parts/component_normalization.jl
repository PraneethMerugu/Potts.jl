function _convert_volume(component::VolumeConstraint, ::Type{T}) where {T <: AbstractFloat}
    entries = Tuple(Binding{CellType, VolumeParameters{T}}(entry.key,
        VolumeParameters(T(entry.value.target), T(entry.value.strength)))
        for entry in component.bindings)
    return VolumeConstraint{T}(component.name,
        BindingTable{CellType, VolumeParameters{T}}(entries))
end

function _convert_volume(component::FluctuatingVolumeConstraint,
        ::Type{T}) where {T <: AbstractFloat}
    entries = Tuple(Binding{CellType, VolumeParameters{T}}(entry.key,
        VolumeParameters(T(entry.value.target), T(entry.value.strength)))
        for entry in component.bindings)
    return FluctuatingVolumeConstraint{T, typeof(component.noise), typeof(component.division)}(
        component.name, BindingTable{CellType, VolumeParameters{T}}(entries), T(component.eta),
        component.noise, component.initialization, component.division)
end

function _convert_adhesion(component::Adhesion, ::Type{T}) where {T <: AbstractFloat}
    entries = Tuple(Binding{PairIdentity, T}(entry.key, T(entry.value))
        for entry in component.law.values)
    law = PairwiseLaw{T}(component.law.name, BindingTable{PairIdentity, T}(entries),
        component.law.symmetric,
        component.law.default === nothing ? nothing : T(component.law.default))
    return Adhesion{T}(component.name, law)
end

function _normalize_component(component::Elongation,
        ::Type{T}) where {T <: AbstractFloat}
    entries = Tuple(Binding{CellType, ElongationParameters{T}}(entry.key,
        ElongationParameters(T(entry.value.target), T(entry.value.strength)))
        for entry in component.bindings)
    return Elongation{T, typeof(component.target_division)}(
        component.name, BindingTable{CellType, ElongationParameters{T}}(entries),
        component.target_division)
end

function _convert_boundary_bindings(component, ::Type{T}) where {T <: AbstractFloat}
    parameter = first(component.bindings).value
    Q = typeof(parameter.target) <: Integer ? Int64 : T
    entries = Tuple(Binding{CellType, BoundaryParameters{Q, T}}(entry.key,
        BoundaryParameters(Q(entry.value.target), T(entry.value.strength)))
        for entry in component.bindings)
    return BindingTable{CellType, BoundaryParameters{Q, T}}(entries)
end

function _normalize_component(component::BoundaryConstraint,
        ::Type{T}) where {T <: AbstractFloat}
    bindings = _convert_boundary_bindings(component, T)
    Q = typeof(first(bindings).value.target)
    return BoundaryConstraint{Q, T, typeof(component.metric)}(
        component.name, bindings, component.metric)
end

function _normalize_component(component::FluctuatingBoundaryConstraint,
        ::Type{T}) where {T <: AbstractFloat}
    bindings = _convert_boundary_bindings(component, T)
    Q = typeof(first(bindings).value.target)
    return FluctuatingBoundaryConstraint{Q, T, typeof(component.noise),
        typeof(component.metric), typeof(component.target_division),
        typeof(component.division)}(component.name, bindings, T(component.eta),
        component.noise, component.initialization, component.metric,
        component.target_division, component.division)
end

_normalize_component(component::VolumeConstraint, type) = _convert_volume(component, type)
_normalize_component(component::FluctuatingVolumeConstraint, type) =
    _convert_volume(component, type)
_normalize_component(component::Adhesion, type) = _convert_adhesion(component, type)

function _normalize_component(field::PrescribedField, ::Type{T}) where {T <: AbstractFloat}
    return PrescribedField(field.name.name, T.(field.values);
        namespace = field.name.namespace, origin = T.(field.origin),
        spacing = T.(field.spacing), boundaries = field.boundaries,
        interpolation = field.interpolation, semantic_time = T(field.semantic_time),
        synchronization_epoch = field.synchronization_epoch)
end

_normalize_field_response(response, ::Type) = response
_normalize_field_response(response::CorePotts.MichaelisMentenResponse,
        ::Type{T}) where {T <: AbstractFloat} = CorePotts.MichaelisMentenResponse(T(response.scale))
_normalize_field_response(response::CorePotts.SaturationLinearResponse,
        ::Type{T}) where {T <: AbstractFloat} = CorePotts.SaturationLinearResponse(T(response.scale))

function _normalize_component(component::Chemotaxis, ::Type{T}) where {T <: AbstractFloat}
    entries = Tuple(Binding{CellType, T}(entry.key, T(entry.value))
        for entry in component.sensitivity)
    response = _normalize_field_response(component.response, T)
    return Chemotaxis{T, typeof(response), typeof(component.mode)}(
        component.name, component.field, component.dimensions,
        BindingTable{CellType, T}(entries),
        response, component.mode)
end

_normalize_trigger(trigger, ::Type) = trigger
_normalize_trigger(trigger::CorePotts.BernoulliCellTrigger,
        ::Type{T}) where {T <: AbstractFloat} =
    CorePotts.BernoulliCellTrigger(T(trigger.probability), trigger.operation)
function _normalize_trigger(trigger::CorePotts.PropertyAtLeast{Key},
        ::Type{T}) where {Key, T <: AbstractFloat}
    return CorePotts.PropertyAtLeast(Key, T(trigger.threshold))
end

function _normalize_component(rule::PropertyUpdate, ::Type{T}) where {T <: AbstractFloat}
    trigger = _normalize_trigger(rule.trigger, T)
    return PropertyUpdate(rule.name, rule.source, rule.role, rule.cell_types,
        T(rule.amount), rule.schedule, trigger)
end


function _normalize_component(rule::Transition, ::Type{T}) where {T <: AbstractFloat}
    trigger = _normalize_trigger(rule.trigger, T)
    return Transition(rule.name, rule.cell_types, rule.destination,
        rule.schedule, trigger, rule.priority)
end


_normalize_division_geometry(geometry, ::Type) = geometry
function _normalize_division_geometry(geometry::CorePotts.VectorDivision{N},
        ::Type{T}) where {N, T <: AbstractFloat}
    return CorePotts.VectorDivision(Tuple(geometry.direction); number_type = T)
end

function _normalize_component(rule::Division, ::Type{T}) where {T <: AbstractFloat}
    trigger = _normalize_trigger(rule.trigger, T)
    geometry = _normalize_division_geometry(rule.geometry, T)
    return Division(rule.name, rule.cell_types, geometry,
        rule.schedule, trigger, rule.priority)
end

function _normalize_component(rule::ShrinkDeath, ::Type{T}) where {T <: AbstractFloat}
    trigger = _normalize_trigger(rule.trigger, T)
    return ShrinkDeath(rule.name, rule.source, rule.cell_types, T(rule.decrement),
        rule.schedule, trigger, rule.priority)
end

function _normalize_component(rule::ImmediateDeath, ::Type{T}) where {T <: AbstractFloat}
    trigger = _normalize_trigger(rule.trigger, T)
    return ImmediateDeath(rule.name, rule.cell_types, rule.medium,
        rule.schedule, trigger, rule.priority)
end
_normalize_invariant(invariant, type) = invariant
_normalize_invariant(invariant::ClosedPropertyInterval, ::Type{T}) where {T} =
    ClosedPropertyInterval(T(invariant.lower), T(invariant.upper))

function _normalize_component(property::CellProperty{V, I, D, X, R},
        ::Type{T}) where {V <: AbstractFloat, I <: AbstractPropertyInvariant,
        D, X, R, T <: AbstractFloat}
    invariant = _normalize_invariant(property.invariant, T)
    return CellProperty{T, typeof(invariant), D, X, R}(
        property.name, property.cell_types, T(property.initial), invariant,
        property.mutability, property.division, property.transition,
        property.retirement, property.visibility, property.persistence,
        property.optionality)
end
_normalize_component(property::CellProperty, ::Type{T}) where {T} = property
_normalize_component(component, type) = component
