"""A semantic finite-cell raster used only to construct a problem's initial state."""
struct CellLayout{M <: AbstractArray{Bool}, P <: NamedTuple}
    cell_type::CellType
    provisional_id::UInt64
    mask::M
    priority::Int32
    properties::P
end

function CellLayout(cell_type::CellType, provisional_id::Integer,
        mask::AbstractArray{Bool}; priority::Integer = 0, properties::NamedTuple = NamedTuple())
    0 < provisional_id <= typemax(UInt64) || throw(ArgumentError(
        "provisional cell identity must be positive and fit UInt64"))
    typemin(Int32) <= priority <= typemax(Int32) || throw(ArgumentError(
        "initial claim priority must fit Int32"))
    return CellLayout(cell_type, UInt64(provisional_id), mask, Int32(priority), properties)
end

"""Dense multi-cell raster whose runtime type is independent of the number of cells."""
struct CellLabelLayout{N, A <: Array{UInt64, N}}
    labels::A
    cell_types::Vector{Pair{UInt64, CellType}}
    priority::Int32
end

function CellLabelLayout(labels::AbstractArray{<:Integer, N}, declarations;
        priority::Integer = 0) where {N}
    N in (2, 3) || throw(ArgumentError(
        "dense cell-label layouts support exactly two or three dimensions"))
    all(>=(0), labels) || throw(ArgumentError(
        "dense provisional cell labels must be non-negative"))
    converted = Array{UInt64, N}(labels)
    typed = Pair{UInt64, CellType}[]
    for declaration in declarations
        first(declaration) isa Integer && last(declaration) isa CellType ||
            throw(ArgumentError(
                "cell-label declarations must be `Integer => CellType` pairs"))
        id = first(declaration)
        0 < id <= typemax(UInt64) || throw(ArgumentError(
            "provisional cell identity must be positive and fit UInt64"))
        push!(typed, UInt64(id) => last(declaration))
    end
    ids = first.(typed)
    length(unique(ids)) == length(ids) || throw(ArgumentError(
        "cell-label declarations must use distinct provisional identities"))
    occupied = Set(filter(!iszero, converted))
    occupied == Set(ids) || throw(ArgumentError(
        "dense labels and provisional cell declarations must name the same identities"))
    typemin(Int32) <= priority <= typemax(Int32) || throw(ArgumentError(
        "initial claim priority must fit Int32"))
    sort!(typed; by = first)
    return CellLabelLayout{N, typeof(converted)}(
        converted, typed, Int32(priority))
end

"""A semantic medium raster used only to construct a problem's initial state."""
struct MediumLayout{M <: AbstractArray{Bool}}
    medium::Medium
    mask::M
    priority::Int32
end

function MediumLayout(medium::Medium, mask::AbstractArray{Bool}; priority::Integer = 0)
    typemin(Int32) <= priority <= typemax(Int32) || throw(ArgumentError(
        "initial claim priority must fit Int32"))
    return MediumLayout(medium, mask, Int32(priority))
end

"""One cell-type-indexed property column produced by Level 2 lowering."""
struct CellPropertyBinding{T}
    key::Symbol
    values::BindingTable{CellType, T}
end

"""Inspectable, host-only result of lowering one normalized Level 2 model."""
struct LoweredModel{N, C, S, B, CT, MD}
    normalized::N
    core_model::C
    property_schema::S
    property_bindings::B
    biological_types::Tuple
    cell_type_ids::CT
    medium_ids::MD
end

function Base.show(io::IO, lowered::LoweredModel)
    print(io, "LoweredModel(", length(lowered.normalized.cell_types), " cell types, ",
        length(lowered.normalized.media), " media, ",
        length(lowered.normalized.components), " components)")
end

struct _LoweringContext{T, C, M, D, R, S, K, Q}
    cell_types::C
    media::M
    declarations::D
    contact_relation::R
    surface_relation::S
    connectivity_relation::K
    query_relation::Q
end

struct _LoweredComponents{E <: Tuple, D <: Tuple, C <: Tuple, K <: Tuple, M <: Tuple,
        L <: Tuple, S <: Tuple, P <: Tuple}
    energies::E
    drives::D
    constraints::C
    modifiers::K
    mechanics::M
    lifecycle::L
    schemas::S
    properties::P
end

_LoweredComponents() = _LoweredComponents((), (), (), (), (), (), (), ())

function _merge_lowered(left::_LoweredComponents, right::_LoweredComponents)
    return _LoweredComponents(
        (left.energies..., right.energies...),
        (left.drives..., right.drives...),
        (left.constraints..., right.constraints...),
        (left.modifiers..., right.modifiers...),
        (left.mechanics..., right.mechanics...),
        (left.lifecycle..., right.lifecycle...),
        (left.schemas..., right.schemas...),
        (left.properties..., right.properties...))
end

function _property_prefix(identity::SemanticName)
    parts = (identity.namespace.parts..., identity.name)
    return join(String.(parts), "__")
end

function _property_bindings(component, target_key::Symbol, strength_key::Symbol)
    T = typeof(first(component.bindings).value.target)
    targets = Tuple(Binding{CellType, T}(
        entry.key, entry.value.target) for entry in component.bindings)
    strengths = Tuple(Binding{CellType, T}(
        entry.key, entry.value.strength) for entry in component.bindings)
    return (
        CellPropertyBinding(target_key, BindingTable{CellType, T}(targets)),
        CellPropertyBinding(strength_key, BindingTable{CellType, T}(strengths)))
end

function _boundary_property_bindings(component, target_key::Symbol, strength_key::Symbol)
    parameter = first(component.bindings).value
    Q = typeof(parameter.target)
    T = typeof(parameter.strength)
    targets = Tuple(Binding{CellType, Q}(entry.key, entry.value.target)
        for entry in component.bindings)
    strengths = Tuple(Binding{CellType, T}(entry.key, entry.value.strength)
        for entry in component.bindings)
    return (
        CellPropertyBinding(target_key, BindingTable{CellType, Q}(targets)),
        CellPropertyBinding(strength_key, BindingTable{CellType, T}(strengths)))
end

function _lower_component(property::CellProperty, context::_LoweringContext)
    key = Symbol(_property_prefix(property.name))
    requester = CorePotts.ComponentIdentity(key, v"1.0.0", :property)
    descriptor = CorePotts.PropertyDescriptor(key, typeof(property.initial),
        CorePotts.ConstantInitializer(property.initial);
        mutability = property.mutability, division = property.division,
        transition = property.transition, retirement = property.retirement,
        kind = CorePotts.BiologicalProperty, requester)
    entries = Tuple(Binding{CellType, typeof(property.initial)}(
        cell_type, property.initial) for cell_type in property.cell_types)
    values = BindingTable{CellType, typeof(property.initial)}(entries)
    binding = CellPropertyBinding(key, values)
    return _LoweredComponents((), (), (), (), (), (),
        (CorePotts.PropertySchema(descriptor),), (binding,))
end

function _lower_component(component::VolumeConstraint, context::_LoweringContext{T}) where {T}
    prefix = _property_prefix(component.name)
    target_key = Symbol(prefix, "__target")
    strength_key = Symbol(prefix, "__strength")
    core = CorePotts.QuadraticVolumeHamiltonian(
        target = target_key, strength = strength_key, number_type = T)
    return _LoweredComponents((core,), (), (), (), (), (),
        (CorePotts.required_properties(core),),
        _property_bindings(component, target_key, strength_key))
end

function _lower_component(component::FluctuatingVolumeConstraint,
        context::_LoweringContext{T}) where {T}
    prefix = _property_prefix(component.name)
    target_key = Symbol(prefix, "__target")
    strength_key = Symbol(prefix, "__strength")
    state_key = Symbol(prefix, "__pressure")
    core = CorePotts.FluctuatingVolumePressure(
        target = target_key, strength = strength_key, state = state_key,
        eta = component.eta, noise = component.noise,
        initialization = component.initialization, division = component.division,
        number_type = T)
    return _LoweredComponents((), (), (), (), (core,), (),
        (CorePotts.required_properties(core),),
        _property_bindings(component, target_key, strength_key))
end

function _lower_component(component::Elongation,
        context::_LoweringContext{T}) where {T}
    prefix = _property_prefix(component.name)
    target_key = Symbol(prefix, "__target")
    strength_key = Symbol(prefix, "__strength")
    core = CorePotts.QuadraticElongationHamiltonian(
        target = target_key, strength = strength_key,
        target_division = component.target_division, number_type = T)
    return _LoweredComponents((core,), (), (), (), (), (),
        (CorePotts.required_properties(core),),
        _property_bindings(component, target_key, strength_key))
end

function _lower_component(component::BoundaryConstraint,
        context::_LoweringContext{T}) where {T}
    prefix = _property_prefix(component.name)
    target_key = Symbol(prefix, "__target")
    strength_key = Symbol(prefix, "__strength")
    core = CorePotts.QuadraticBoundaryHamiltonian(
        component.metric, context.surface_relation;
        target = target_key, strength = strength_key, number_type = T)
    return _LoweredComponents((core,), (), (), (), (), (),
        (CorePotts.required_properties(core),),
        _boundary_property_bindings(component, target_key, strength_key))
end

function _lower_component(component::FluctuatingBoundaryConstraint,
        context::_LoweringContext{T}) where {T}
    prefix = _property_prefix(component.name)
    target_key = Symbol(prefix, "__target")
    strength_key = Symbol(prefix, "__strength")
    state_key = Symbol(prefix, "__tension")
    core = CorePotts.FluctuatingSurfaceTension(
        component.metric, context.surface_relation;
        target = target_key, strength = strength_key, state = state_key,
        eta = component.eta, noise = component.noise,
        initialization = component.initialization,
        target_division = component.target_division, division = component.division,
        number_type = T)
    return _LoweredComponents((), (), (), (), (core,), (),
        (CorePotts.required_properties(core),),
        _boundary_property_bindings(component, target_key, strength_key))
end

function _lower_component(::PreserveConnectivity, context::_LoweringContext)
    core = CorePotts.PreserveConnectedCells(context.connectivity_relation)
    return _LoweredComponents((), (), (core,), (), (), (),
        (CorePotts.required_properties(core),), ())
end

function _biological_index(context::_LoweringContext, value::AbstractBiologicalType)
    index = findfirst(==(value), (context.cell_types..., context.media...))
    index === nothing && throw(ArgumentError("undeclared biological identity $value"))
    return index
end

function _pairwise_value(law::PairwiseLaw{T}, left, right) where {T}
    key = PairIdentity(left, right; symmetric = law.symmetric)
    value = get(law.values, key, law.default)
    value === nothing && throw(ArgumentError("missing pairwise value for $key"))
    return value::T
end

function _lower_component(component::Adhesion{T}, context::_LoweringContext{T}) where {T}
    biological_types = (context.cell_types..., context.media...)
    count = length(biological_types)
    interactions = Matrix{T}(undef, count, count)
    for row in 1:count, column in 1:count
        interactions[row, column] = _pairwise_value(
            component.law, biological_types[row], biological_types[column])
    end
    medium_types = CorePotts.MediumTypeTable(Tuple(
        CorePotts.MediumID(index) => CorePotts.CellTypeID(length(context.cell_types) + index)
        for index in eachindex(context.media)))
    core = CorePotts.UnorderedContactHamiltonian(
        interactions, medium_types, context.contact_relation)
    return _LoweredComponents((core,), (), (), (), (), (),
        (CorePotts.required_properties(core),), ())
end

_lower_component(::PrescribedField, context::_LoweringContext) = _LoweredComponents()
_lower_component(::CorePotts.SpatialRoles, context::_LoweringContext) =
    _LoweredComponents()
_lower_component(::Union{
        CorePotts.SiteProperty,
        CorePotts.AcceptedCopyUpdate,
        CorePotts.SiteDynamics,
        CorePotts.CellHistory,
        CorePotts.RelationshipSet,
        CorePotts.MCSPlan,
        CorePotts.StagedProtocol,
        CorePotts.ScheduledParameter,
        CorePotts.ContinuousClock,
        CorePotts.GlobalProperty,
        CorePotts.MembraneProperty,
        CorePotts.ContinuousSystem,
        CorePotts.CellDynamics,
        CorePotts.FieldDynamics,
        CorePotts.FieldExchange,
        CorePotts.RelationshipDynamics,
        CorePotts.DelayState,
        CorePotts.ContinuousEvent,
        CorePotts.SymbolMap,
        CorePotts.ContinuousModelAdapter,
        CorePotts.PhaseObservation,
        CorePotts.ObservationTransform}, context::_LoweringContext) =
    _LoweredComponents()

function _prescribed_field(context::_LoweringContext, identity::SemanticName)
    index = findfirst(value -> value isa PrescribedField &&
        semantic_identity(value) == identity, context.declarations)
    index === nothing && throw(ArgumentError("missing prescribed field $identity"))
    return context.declarations[index]
end

function _lower_component(component::Chemotaxis{T},
        context::_LoweringContext{T}) where {T}
    field = _field_as_core(_prescribed_field(context, component.field))
    key = Symbol(_property_prefix(component.name), "__sensitivity")
    core_medium_values = Tuple(CorePotts.MediumID(index) => zero(T)
        for index in eachindex(context.media))
    coupling = CorePotts.OwnerScalarCoupling(key, core_medium_values...;
        number_type = T)
    drive = CorePotts.ChemotaxisDrive(
        field, coupling, component.response, component.mode)
    requester = CorePotts.component_identity(drive)
    descriptor = CorePotts.PropertyDescriptor(key, T,
        CorePotts.ConstantInitializer(zero(T));
        mutability = CorePotts.MutableProperty,
        division = CorePotts.CloneOnDivision(),
        transition = CorePotts.PreserveOnTransition(),
        retirement = CorePotts.ResetOnRetirement(),
        kind = CorePotts.BiologicalProperty, requester)
    values = CellPropertyBinding(key, component.sensitivity)
    return _LoweredComponents((), (drive,), (), (), (), (),
        (CorePotts.PropertySchema(descriptor),), (values,))
end

_lower_component(component::NamedCoreComponent, context::_LoweringContext) =
    _lower_component(component.component, context)

function _prepare_direct_component(component)
    _validate_direct_component(component)
    CorePotts.validate_proposal_component(component)
    return CorePotts.required_properties(component)
end


_validate_direct_component(component::CorePotts.AbstractEnergy) =
    CorePotts.validate_energy_component(component)
_validate_direct_component(component::CorePotts.AbstractDrive) =
    CorePotts.validate_drive_component(component)
_validate_direct_component(component::CorePotts.AbstractHardConstraint) =
    CorePotts.validate_constraint_component(component)
_validate_direct_component(component::CorePotts.AbstractMechanicalComponent) =
    CorePotts.validate_mechanical_component(component)
_validate_direct_component(component::CorePotts.AbstractKineticModifier) = component

function _lower_component(component::CorePotts.AbstractEnergy, context::_LoweringContext)
    schema = _prepare_direct_component(component)
    return _LoweredComponents((component,), (), (), (), (), (), (schema,), ())
end
function _lower_component(component::CorePotts.AbstractDrive, context::_LoweringContext)
    schema = _prepare_direct_component(component)
    return _LoweredComponents((), (component,), (), (), (), (), (schema,), ())
end
function _lower_component(component::CorePotts.AbstractHardConstraint,
        context::_LoweringContext)
    schema = _prepare_direct_component(component)
    return _LoweredComponents((), (), (component,), (), (), (), (schema,), ())
end
function _lower_component(component::CorePotts.AbstractKineticModifier,
        context::_LoweringContext)
    schema = _prepare_direct_component(component)
    return _LoweredComponents((), (), (), (component,), (), (), (schema,), ())
end
function _lower_component(component::CorePotts.AbstractMechanicalComponent,
        context::_LoweringContext)
    schema = _prepare_direct_component(component)
    return _LoweredComponents((), (), (), (), (component,), (), (schema,), ())
end

function _lower_component(rule::PropertyUpdate, context::_LoweringContext{T}) where {T}
    trigger = _lower_lifecycle_trigger(rule.cell_types, rule.trigger, context)
    event_id = _lifecycle_event_id(rule.name)
    key = rule.role === :value ? Symbol(_property_prefix(rule.source)) :
        Symbol(_property_prefix(rule.source), "__", rule.role)
    event = CorePotts.LifecycleEvent(
        CorePotts.ActiveCellsTarget(), rule.schedule, trigger,
        CorePotts.AddCellProperty(key, T(rule.amount)); semantic_id = event_id)
    return _LoweredComponents((), (), (), (), (), (event,), (), ())
end

_lifecycle_event_id(identity::SemanticName) =
    1 + _semantic_rng_code(identity, :event, UInt16(0x0ffe))

function _lower_lifecycle_trigger(cell_types::Tuple, trigger,
        context::_LoweringContext)
    type_ids = Tuple(CorePotts.CellTypeID(
        _biological_index(context, cell_type)) for cell_type in cell_types)
    return CorePotts.AllLifecycleTriggers(CorePotts.CellTypeIn(type_ids...), trigger)
end

function _lower_lifecycle_event(rule, effect, context::_LoweringContext)
    trigger = _lower_lifecycle_trigger(rule.cell_types, rule.trigger, context)
    return CorePotts.LifecycleEvent(CorePotts.ActiveCellsTarget(), rule.schedule,
        trigger, effect; semantic_id = _lifecycle_event_id(rule.name),
        priority = rule.priority)
end

function _lower_component(rule::Transition, context::_LoweringContext)
    destination = CorePotts.CellTypeID(_biological_index(context, rule.destination))
    event = _lower_lifecycle_event(
        rule, CorePotts.TransitionCell(destination), context)
    return _LoweredComponents((), (), (), (), (), (event,), (), ())
end

function _lower_component(rule::Division, context::_LoweringContext)
    event = _lower_lifecycle_event(rule, CorePotts.DivideCell(rule.geometry), context)
    return _LoweredComponents((), (), (), (), (), (event,), (), ())
end

function _lower_component(rule::ShrinkDeath{T},
        context::_LoweringContext{T}) where {T}
    key = Symbol(_property_prefix(rule.source), "__target")
    event = _lower_lifecycle_event(
        rule, CorePotts.InitiateShrinkDeath(key, rule.decrement), context)
    return _LoweredComponents((), (), (), (), (), (event,), (), ())
end

function _lower_component(rule::ImmediateDeath, context::_LoweringContext)
    index = findfirst(==(rule.medium), context.media)
    index === nothing && throw(ArgumentError("undeclared death medium $(rule.medium)"))
    event = _lower_lifecycle_event(
        rule, CorePotts.RemoveCellImmediately(CorePotts.MediumID(index)), context)
    return _LoweredComponents((), (), (), (), (), (event,), (), ())
end

function _lower_components(components::Tuple, context::_LoweringContext)
    isempty(components) && return _LoweredComponents()
    return _merge_lowered(_lower_component(first(components), context),
        _lower_components(Base.tail(components), context))
end

function _id_table(values::Tuple, constructor)
    entries = Tuple(Binding(value, constructor(index)) for (index, value) in enumerate(values))
    K = eltype(values)
    V = typeof(constructor(1))
    return BindingTable{K, V}(entries)
end

function _component_dimension_diagnostics(normalized::NormalizedModel,
        dimensions::Integer)
    diagnostics = ()
    for component in normalized.components
        report = _declaration_report(component)
        dimensions in report.capabilities.dimensions && continue
        diagnostics = (diagnostics..., Diagnostic(
            :error, :unsupported_component_dimension,
            "a model component does not support the selected lattice dimensionality";
            stage = :problem, identity = report.identity,
            related = (dimensions, report.capabilities.dimensions),
            correction = "select a supported dimension or replace the component"),)
    end
    return diagnostics
end

function _check_component_dimensions(normalized::NormalizedModel,
        dimensions::Integer)
    diagnostics = _component_dimension_diagnostics(normalized, dimensions)
    isempty(diagnostics) || throw(ArgumentError(
        first(diagnostics).message * ": " * string(first(diagnostics).identity)))
    return normalized
end

function _requires_unwrapped_moments(lowered::_LoweredComponents)
    required = (:center_unwrapping, :unwrapped_first_and_second_moments)
    components = (lowered.energies..., lowered.drives..., lowered.constraints...,
        lowered.modifiers..., lowered.mechanics...)
    return any(components) do component
        dependencies = (CorePotts.required_observables(component)...,
            CorePotts.required_relations(component)...)
        any(dependency -> dependency in required, dependencies)
    end
end

_observable_symbol(component) = nothing

function _declared_spatial_roles(components::Tuple)
    entries = Tuple(component for component in components
        if component isa CorePotts.SpatialRoles)
    length(entries) <= 1 || throw(ArgumentError(
        "a model may declare at most one SpatialRoles value"))
    return isempty(entries) ? nothing : only(entries)
end

_resolved_spatial_role(::Nothing, field::Symbol, default) = default
function _resolved_spatial_role(roles::CorePotts.SpatialRoles,
        field::Symbol, default)
    value = getfield(roles, field)
    return value isa CorePotts.OmittedSpatialRole ? default : value
end

"""
    lower(model; dimensions, spacing)

Normalize and lower a Level 2 model into public CorePotts scientific values. This operation is
host-only and performs no backend allocation or kernel compilation.
"""
function lower(model::PottsModel; dimensions::Integer,
        spacing = ntuple(_ -> one(CorePotts.real_type(model.numerics)), dimensions))
    dimensions in (2, 3) || throw(ArgumentError("CPM models support two or three dimensions"))
    length(spacing) == dimensions || throw(ArgumentError(
        "spacing must have one value per lattice dimension"))
    normalized = _check_component_dimensions(normalize(model), dimensions)
    T = CorePotts.real_type(normalized.numerics)
    typed_spacing = ntuple(index -> T(spacing[index]), dimensions)
    proposal_relation = CorePotts.first_shell_relation(
        CorePotts.ProposalRole(), Val(dimensions); spacing = typed_spacing)
    contact_relation = CorePotts.first_shell_relation(
        CorePotts.ContactRole(), Val(dimensions); spacing = typed_spacing)
    surface_relation = CorePotts.first_shell_relation(
        CorePotts.SurfaceRole(), Val(dimensions); spacing = typed_spacing)
    connectivity_relation = CorePotts.first_shell_relation(
        CorePotts.ConnectivityRole(), Val(dimensions); spacing = typed_spacing)
    query_relation = CorePotts.first_shell_relation(
        CorePotts.SpatialQueryRole(), Val(dimensions); spacing = typed_spacing)
    declared_roles = _declared_spatial_roles(normalized.components)
    proposal_relation = _resolved_spatial_role(
        declared_roles, :proposal, proposal_relation)
    contact_relation = _resolved_spatial_role(
        declared_roles, :contact, contact_relation)
    surface_relation = _resolved_spatial_role(
        declared_roles, :surface, surface_relation)
    connectivity_relation = _resolved_spatial_role(
        declared_roles, :connectivity, connectivity_relation)
    query_relation = _resolved_spatial_role(
        declared_roles, :query, query_relation)
    context = _LoweringContext{T, typeof(normalized.cell_types),
        typeof(normalized.media), typeof(normalized.components), typeof(contact_relation),
        typeof(surface_relation), typeof(connectivity_relation), typeof(query_relation)}(
        normalized.cell_types, normalized.media, normalized.components,
        contact_relation, surface_relation, connectivity_relation, query_relation)
    lowered = _lower_components(normalized.components, context)
    rule_lifecycle = _lower_rule_program(normalized.components, context)
    components = CorePotts.ScientificComponentSet(
        energies = lowered.energies, drives = lowered.drives,
        constraints = lowered.constraints, kinetic_modifiers = lowered.modifiers,
        mechanics = lowered.mechanics)
    tracker = CorePotts.BoundaryMeasureTracker(
        CorePotts.BoundaryEdgeCount(), surface_relation)
    moment_tracker = _requires_unwrapped_moments(lowered) ?
        CorePotts.UnwrappedMomentTracker(connectivity_relation; number_type = T) : nothing
    observables = Tuple(symbol for component in normalized.components
        for symbol in (_observable_symbol(component),) if symbol !== nothing)
    core_model = CorePotts.PottsModel(proposal_relation, tracker; components,
        moment_tracker,
        lifecycle_events = (lowered.lifecycle..., rule_lifecycle...), observables)
    schema = CorePotts.merge_property_schemas(lowered.schemas...)
    cell_type_ids = _id_table(normalized.cell_types, CorePotts.CellTypeID)
    medium_ids = _id_table(normalized.media, CorePotts.MediumID)
    return LoweredModel(normalized, core_model, schema, lowered.properties,
        (normalized.cell_types..., normalized.media...), cell_type_ids, medium_ids)
end

"""Return the explicit Phase 14 spatial-role declaration, or `nothing` for a Phase 13 model."""
spatial_roles(lowered::LoweredModel) =
    _declared_spatial_roles(lowered.normalized.components)

function _property_overrides(lowered::LoweredModel, cell_type::CellType,
        explicit::NamedTuple)
    keys = ()
    values = ()
    for binding in lowered.property_bindings
        haskey(binding.values, cell_type) || continue
        keys = (keys..., binding.key)
        values = (values..., binding.values[cell_type])
    end
    explicit_keys = Tuple(propertynames(explicit))
    overlap = Tuple(key for key in keys if key in explicit_keys)
    isempty(overlap) || throw(ArgumentError(
        "initial properties conflict with model bindings for $(join(overlap, ", "))"))
    all_keys = (keys..., explicit_keys...)
    all_values = (values..., Tuple(explicit)...)
    return NamedTuple{all_keys}(all_values)
end

function _lower_layout(lowered::LoweredModel, layout::CellLayout, shape::Tuple)
    dimensions = length(shape)
    haskey(lowered.cell_type_ids, layout.cell_type) || throw(ArgumentError(
        "initial layout references undeclared cell type $(layout.cell_type)"))
    ndims(layout.mask) == dimensions || throw(ArgumentError(
        "initial cell layout dimensionality does not match the problem"))
    type_id = lowered.cell_type_ids[layout.cell_type]
    geometry = CorePotts.InitialCellLayout(layout.provisional_id, type_id,
        layout.mask; priority = layout.priority)
    properties = CorePotts.InitialCellProperties(layout.provisional_id, type_id,
        _property_overrides(lowered, layout.cell_type, layout.properties);
        dimensions)
    return (geometry, properties)
end

function _lower_layout(lowered::LoweredModel, layout::CellLabelLayout,
        shape::Tuple)
    dimensions = length(shape)
    ndims(layout.labels) == dimensions || throw(ArgumentError(
        "dense cell-label dimensionality does not match the problem"))
    declarations = Pair{UInt64, CorePotts.CellTypeID}[]
    properties = CorePotts.InitialCellProperties[]
    for (id, cell_type) in layout.cell_types
        haskey(lowered.cell_type_ids, cell_type) || throw(ArgumentError(
            "dense cell-label layout references undeclared cell type $cell_type"))
        type_id = lowered.cell_type_ids[cell_type]
        push!(declarations, id => type_id)
        push!(properties, CorePotts.InitialCellProperties(id, type_id,
            _property_overrides(lowered, cell_type, NamedTuple()); dimensions))
    end
    return (CorePotts.DenseCellLabels(
        layout.labels, declarations; priority = layout.priority), properties...)
end

function _lower_layout(lowered::LoweredModel, layout::MediumLayout, shape::Tuple)
    dimensions = length(shape)
    haskey(lowered.medium_ids, layout.medium) || throw(ArgumentError(
        "initial layout references undeclared medium $(layout.medium)"))
    ndims(layout.mask) == dimensions || throw(ArgumentError(
        "initial medium layout dimensionality does not match the problem"))
    return (CorePotts.InitialMediumLayout(lowered.medium_ids[layout.medium],
        layout.mask; priority = layout.priority),)
end

function _procedural_declarations(lowered::LoweredModel,
        layout::AbstractProceduralLayout)
    type_id = lowered.cell_type_ids[layout.cell_type]
    return Pair{UInt64, CorePotts.CellTypeID}[
        (layout.first_identity + UInt64(index - 1)) => type_id
        for index in 1:Int(layout.count)]
end

function _procedural_mask(mask, shape::Tuple)
    mask === nothing && return trues(shape)
    return mask
end

function _lower_layout(lowered::LoweredModel, layout::UniformSiteSeedLayout,
        shape::Tuple)
    declarations = _procedural_declarations(lowered, layout)
    eligible = _procedural_mask(layout.eligible, shape)
    return (CorePotts.UniformSiteSeeds(declarations, eligible;
        operation = layout.operation, priority = layout.priority),)
end

function _lower_layout(lowered::LoweredModel, layout::SequentialRejectionLayout,
        shape::Tuple)
    dimensions = length(shape)
    declarations = _procedural_declarations(lowered, layout)
    eligible = _procedural_mask(layout.eligible_centers, shape)
    periodic = isempty(layout.periodic) ? ntuple(_ -> false, dimensions) : layout.periodic
    return (CorePotts.SequentialRejectionPlacement(
        declarations, layout.shape, eligible; periodic,
        attempt_limit = layout.attempt_limit, operation = layout.operation,
        priority = layout.priority),)
end

function _lower_layout_tuple(lowered::LoweredModel, layouts::Tuple, shape::Tuple)
    isempty(layouts) && return ()
    return (_lower_layout(lowered, first(layouts), shape)...,
        _lower_layout_tuple(lowered, Base.tail(layouts), shape)...)
end

function _layout_diagnostics(layout::CellLayout, shape::Tuple,
        cells::Tuple, media::Tuple)
    diagnostics = ()
    layout.cell_type in cells || (diagnostics = (diagnostics..., Diagnostic(
        :error, :undeclared_layout_cell_type,
        "initial cell layout references an undeclared cell type";
        stage = :problem, identity = semantic_identity(layout.cell_type),
        correction = "declare the cell type or correct the layout"),))
    size(layout.mask) == shape || (diagnostics = (diagnostics..., Diagnostic(
        :error, :layout_shape_mismatch,
        "initial cell layout mask shape does not match the problem lattice";
        stage = :problem, identity = semantic_identity(layout.cell_type),
        related = (size(layout.mask), shape),
        correction = "provide a Boolean mask with exactly the problem shape"),))
    return diagnostics
end

function _layout_diagnostics(layout::MediumLayout, shape::Tuple,
        cells::Tuple, media::Tuple)
    diagnostics = ()
    layout.medium in media || (diagnostics = (diagnostics..., Diagnostic(
        :error, :undeclared_layout_medium,
        "initial medium layout references an undeclared medium";
        stage = :problem, identity = semantic_identity(layout.medium),
        correction = "declare the medium or correct the layout"),))
    size(layout.mask) == shape || (diagnostics = (diagnostics..., Diagnostic(
        :error, :layout_shape_mismatch,
        "initial medium layout mask shape does not match the problem lattice";
        stage = :problem, identity = semantic_identity(layout.medium),
        related = (size(layout.mask), shape),
        correction = "provide a Boolean mask with exactly the problem shape"),))
    return diagnostics
end


function _layout_diagnostics(layout::CellLabelLayout, shape::Tuple,
        cells::Tuple, media::Tuple)
    diagnostics = ()
    size(layout.labels) == shape || (diagnostics = (diagnostics..., Diagnostic(
        :error, :layout_shape_mismatch,
        "dense cell-label raster shape does not match the problem lattice";
        stage = :problem, related = (size(layout.labels), shape),
        correction = "provide a label raster with exactly the problem shape"),))
    for (_, cell_type) in layout.cell_types
        cell_type in cells || (diagnostics = (diagnostics..., Diagnostic(
            :error, :undeclared_layout_cell_type,
            "dense cell-label layout references an undeclared cell type";
            stage = :problem, identity = semantic_identity(cell_type),
            correction = "declare the cell type or correct the label declaration")))
    end
    return diagnostics
end

function _layout_diagnostics(layout::AbstractProceduralLayout, shape::Tuple,
        cells::Tuple, media::Tuple)
    diagnostics = ()
    layout.cell_type in cells || (diagnostics = (diagnostics..., Diagnostic(
        :error, :undeclared_layout_cell_type,
        "procedural layout references an undeclared cell type";
        stage = :problem, identity = semantic_identity(layout.cell_type),
        correction = "declare the cell type or correct the layout"),))
    mask = layout isa UniformSiteSeedLayout ? layout.eligible : layout.eligible_centers
    mask === nothing || size(mask) == shape || (diagnostics = (diagnostics...,
        Diagnostic(:error, :layout_shape_mismatch,
            "procedural layout eligibility shape does not match the problem lattice";
            stage = :problem, identity = layout.name,
            related = (size(mask), shape),
            correction = "provide a Boolean mask with exactly the problem shape"),))
    if layout isa UniformSiteSeedLayout &&
            (mask === nothing || size(mask) == shape)
        eligible_count = mask === nothing ? prod(shape) : count(mask)
        Int(layout.count) <= eligible_count || (diagnostics = (diagnostics...,
            Diagnostic(:error, :insufficient_layout_eligibility,
                "uniform site seeding requests more cells than eligible lattice sites";
                stage = :problem, identity = layout.name,
                related = (Int(layout.count), eligible_count),
                correction = "reduce the seed count or enlarge the eligible region"),))
    end
    if layout isa SequentialRejectionLayout
        isempty(layout.periodic) || length(layout.periodic) == length(shape) ||
            (diagnostics = (diagnostics..., Diagnostic(:error,
                :layout_dimension_mismatch,
                "sequential-rejection periodicity must have one value per dimension";
                stage = :problem, identity = layout.name,
                related = layout.periodic,
                correction = "provide one periodic Boolean per lattice axis"),))
        layout.shape isa CorePotts.LatticeBox &&
            length(layout.shape.half_widths) != length(shape) &&
            (diagnostics = (diagnostics..., Diagnostic(:error,
                :layout_dimension_mismatch,
                "sequential-rejection box shape dimensionality must match the lattice";
                stage = :problem, identity = layout.name,
                related = (length(layout.shape.half_widths), length(shape)),
                correction = "provide one box half-width per lattice axis"),))
    end
    return diagnostics
end

_layout_diagnostics(layout, shape::Tuple, cells::Tuple, media::Tuple) = (Diagnostic(
    :error, :unsupported_initial_layout,
    "initial layouts must implement the PottsToolkit CellLayout or MediumLayout protocol";
    stage = :problem,
    correction = "use CellLayout/MediumLayout or add a public lowering method"),)

_cell_layout_count(layout) = UInt64(0)
_cell_layout_count(layout::CellLayout) = UInt64(1)
_cell_layout_count(layout::CellLabelLayout) = UInt64(length(layout.cell_types))
_cell_layout_count(layout::AbstractProceduralLayout) = UInt64(layout.count)

_cell_layout_id_ranges(layout) = ()
_cell_layout_id_ranges(layout::CellLayout) =
    ((layout.provisional_id, layout.provisional_id),)
_cell_layout_id_ranges(layout::CellLabelLayout) =
    Tuple((first(pair), first(pair)) for pair in layout.cell_types)
_cell_layout_id_ranges(layout::AbstractProceduralLayout) = ((layout.first_identity,
    layout.first_identity + UInt64(layout.count) - UInt64(1)),)

function _duplicate_provisional_identity(layouts)
    ranges = [(first(range), last(range)) for layout in layouts
        for range in _cell_layout_id_ranges(layout)]
    sort!(ranges; by = first)
    isempty(ranges) && return nothing
    previous = first(ranges)
    for current in Iterators.drop(ranges, 1)
        first(current) <= last(previous) && return (previous, current)
        last(current) > last(previous) && (previous = current)
    end
    return nothing
end

function _procedural_layout_identity_diagnostics(layouts)
    diagnostics = ()
    identities = Dict{SemanticName, AbstractProceduralLayout}()
    operations = Dict{UInt16, AbstractProceduralLayout}()
    for layout in layouts
        layout isa AbstractProceduralLayout || continue
        if haskey(identities, layout.name)
            diagnostics = (diagnostics..., Diagnostic(:error,
                :duplicate_layout_identity,
                "procedural layouts must have distinct semantic identities";
                stage = :problem, identity = layout.name,
                correction = "give each procedural layout a unique name and namespace"),)
        else
            identities[layout.name] = layout
        end
        if haskey(operations, layout.operation) &&
                operations[layout.operation].name != layout.name
            diagnostics = (diagnostics..., Diagnostic(:error,
                :layout_rng_identity_collision,
                "procedural layout RNG identities collide in the v1 operation domain";
                stage = :problem, identity = layout.name,
                related = (operations[layout.operation].name, layout.operation),
                correction = "rename or re-namespace one layout so its RNG identity is unique"),)
        else
            operations[layout.operation] = layout
        end
    end
    return diagnostics
end

"""Validate model-instance facts without compiling a backend or allocating device storage."""
function validate_problem(model::PottsModel, shape::Tuple, layouts...;
        capacity::Integer, tspan = (0, 1), seed::Integer = 0,
        spacing = ntuple(_ -> one(CorePotts.real_type(model.numerics)), length(shape)))
    model_report = validate(model)
    diagnostics = model_report.diagnostics
    dimensions = length(shape)
    dimensions in (2, 3) || (diagnostics = (diagnostics..., Diagnostic(
        :error, :unsupported_dimension,
        "CPM problems support exactly two or three lattice dimensions";
        stage = :problem, related = (dimensions,),
        correction = "use a 2D or 3D lattice shape"),))
    all(value -> value isa Integer && value > 0, shape) ||
        (diagnostics = (diagnostics..., Diagnostic(:error, :invalid_lattice_shape,
            "every lattice extent must be a positive integer";
            stage = :problem, related = shape,
            correction = "replace zero, negative, or non-integer extents"),))
    0 < capacity <= typemax(UInt32) || (diagnostics = (diagnostics..., Diagnostic(
        :error, :invalid_cell_capacity, "cell capacity must be positive and fit UInt32";
        stage = :problem, related = (capacity,),
        correction = "choose a fixed maximum cell count in 1:typemax(UInt32)"),))
    0 <= seed <= typemax(UInt64) || (diagnostics = (diagnostics..., Diagnostic(
        :error, :invalid_seed, "problem seed must fit UInt64";
        stage = :problem, related = (seed,),
        correction = "choose an integer seed between 0 and typemax(UInt64)"),))
    tspan_values = tspan isa Tuple ? tspan : (tspan,)
    valid_tspan = length(tspan_values) == 2 &&
        all(value -> value isa Integer, tspan_values) &&
        0 <= tspan_values[1] <= tspan_values[2] <= typemax(Int)
    valid_tspan || (diagnostics = (diagnostics..., Diagnostic(
        :error, :invalid_mcs_tspan,
        "problem tspan must be two ordered non-negative integer MCS values";
        stage = :problem, related = tspan_values,
        correction = "use `(start_mcs, end_mcs)` with integer `0 ≤ start ≤ end`"),))
    spacing_values = spacing isa Tuple ? spacing : (spacing,)
    length(spacing_values) == dimensions && all(value -> value isa Real &&
        isfinite(value) && value > 0, spacing_values) ||
        (diagnostics = (diagnostics..., Diagnostic(:error, :invalid_spacing,
            "spacing must contain one positive finite value per dimension";
            stage = :problem, related = spacing_values,
            correction = "provide positive finite lattice spacing for every axis"),))

    if isvalid(model_report)
        normalized = normalize(model)
        dimensions in (2, 3) && (diagnostics = (diagnostics...,
            _component_dimension_diagnostics(normalized, dimensions)...))
        for layout in layouts
            diagnostics = (diagnostics..., _layout_diagnostics(
                layout, shape, normalized.cell_types, normalized.media)...)
        end
    end
    diagnostics = (diagnostics..., _procedural_layout_identity_diagnostics(layouts)...)
    duplicate_ids = _duplicate_provisional_identity(layouts)
    duplicate_ids === nothing ||
        (diagnostics = (diagnostics..., Diagnostic(
            :error, :duplicate_provisional_cell_id,
            "initial cell layouts must use distinct provisional identities";
            stage = :problem, related = duplicate_ids,
            correction = "assign one unique positive provisional ID per initial cell"),))
    initial_count = sum((BigInt(_cell_layout_count(layout)) for layout in layouts);
        init = BigInt(0))
    initial_count <= capacity || (diagnostics = (diagnostics..., Diagnostic(
        :error, :initial_capacity_exceeded,
        "the number of initial cells exceeds fixed cell capacity";
        stage = :problem, related = (initial_count, capacity),
        correction = "increase capacity or reduce the initial cell count"),))
    return ValidationReport(diagnostics)
end

"""
    problem(model, shape, layouts...; capacity, tspan, seed, ...)

Construct the single public CorePotts/SciML `PottsProblem` from a Level 2 model and typed initial
layouts. No PottsToolkit runtime wrapper is introduced.
"""
function _problem(model::PottsModel, domain::CorePotts.CartesianDomain{N}, layouts...;
        capacity::Integer, tspan = (0, 1), seed::Integer = 0,
        overlap_policy::CorePotts.AbstractInitialOverlapPolicy =
            CorePotts.RejectInitialOverlap()) where {N}
    shape = domain.dims
    spacing = Tuple(domain.spacing)
    report = validate_problem(model, shape, layouts...;
        capacity, tspan, seed, spacing)
    isvalid(report) || throw(ProblemValidationError(report))
    lowered = lower(model; dimensions = N, spacing)
    realized_layouts = _lower_layout_tuple(lowered, Tuple(layouts), shape)
    medium_ids = Tuple(entry.value for entry in lowered.medium_ids)
    initialized = CorePotts.finalize_initial_state(shape, realized_layouts...;
        capacity = CorePotts.CellCapacity(capacity), medium_domains = medium_ids,
        property_schema = lowered.property_schema, overlap_policy, seed)
    return CorePotts.PottsProblem(lowered.core_model, CorePotts.logical_state(initialized),
        domain, tspan; capacity = CorePotts.CellCapacity(capacity), seed)
end

function problem(model::PottsModel, shape::NTuple{N, <:Integer}, layouts...;
        capacity::Integer, tspan = (0, 1), seed::Integer = 0,
        spacing = ntuple(_ -> one(CorePotts.real_type(model.numerics)), Val(N)),
        boundaries = nothing, obstacles = (),
        overlap_policy::CorePotts.AbstractInitialOverlapPolicy =
            CorePotts.RejectInitialOverlap()) where {N}
    domain = boundaries === nothing ?
        CorePotts.CartesianDomain(shape; spacing, obstacles) :
        CorePotts.CartesianDomain(shape; spacing, boundaries, obstacles)
    return _problem(model, domain, layouts...;
        capacity, tspan, seed, overlap_policy)
end

function problem(model::PottsModel, domain::CorePotts.CartesianDomain, layouts...;
        capacity::Integer, tspan = (0, 1), seed::Integer = 0,
        overlap_policy::CorePotts.AbstractInitialOverlapPolicy =
            CorePotts.RejectInitialOverlap())
    return _problem(model, domain, layouts...;
        capacity, tspan, seed, overlap_policy)
end

"""Return CorePotts's public, allocation-free host compatibility preflight report."""
backend_report(problem::CorePotts.PottsProblem, algorithm, backend) =
    CorePotts.compatibility_report(problem, algorithm, backend)

backend_report(problem::CorePotts.PottsProblem, algorithm) =
    CorePotts.compatibility_report(problem, algorithm)
