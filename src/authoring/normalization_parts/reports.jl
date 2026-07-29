function _provenance_lowering_path(identity::SemanticName,
        cells::Tuple, media::Tuple, components::Tuple)
    any(value -> semantic_identity(value) == identity, cells) && return (:CellType,)
    any(value -> semantic_identity(value) == identity, media) && return (:Medium,)
    index = findfirst(value -> semantic_identity(value) == identity, components)
    index === nothing && return ()
    return _declaration_report(components[index]).lowering
end

function _lowering_provenance(entries::Tuple, cells::Tuple,
        media::Tuple, components::Tuple)
    return Tuple(ProvenanceEntry(entry.identity, entry.origin, entry.fragment,
        entry.supplied, entry.defaulted, entry.source,
        _provenance_lowering_path(entry.identity, cells, media, components))
        for entry in entries)
end

function normalize(model::PottsModel)
    report = validate(model)
    isvalid(report) || throw(ModelValidationError(report))
    declarations = _flatten_declarations(model.declarations)
    raw_cells, raw_media, raw_components = _partition_declarations(declarations)
    cells = Tuple(sort!(collect(raw_cells); by = _identity_text))
    media = Tuple(sort!(collect(raw_media); by = _identity_text))
    T = CorePotts.real_type(model.numerics)
    components = Tuple(sort!(collect((_normalize_component(value, T)
        for value in raw_components)); by = value ->
            _identity_text(semantic_identity(value))))
    provenance_entries = _lowering_provenance(
        _provenance_declarations(model.declarations), cells, media, components)
    fingerprint = _semantic_fingerprint(model.numerics, cells, media, components)
    return NormalizedModel(model.numerics, cells, media, components,
        provenance_entries, fingerprint)
end

function explain(model::PottsModel)
    normalized = normalize(model)
    return explain(normalized)
end

function explain(model::NormalizedModel)
    declarations = Tuple(_declaration_report(component) for component in model.components)
    return ModelReport(model.fingerprint, model.numerics, model.cell_types, model.media,
        model.components, declarations, model.provenance_entries, ValidationReport())
end

function capabilities(model::NormalizedModel)
    declarations = Tuple((identity = declaration.identity,
        capabilities = declaration.capabilities) for declaration in explain(model).declarations)
    dimensions = Set((2, 3))
    for declaration in declarations
        intersect!(dimensions, Set(declaration.capabilities.dimensions))
    end
    ordered_dimensions = Tuple(sort!(collect(dimensions)))
    portable = all(declaration -> declaration.capabilities.portable, declarations)
    return ModelCapabilityReport(CorePotts.ScientificCapabilities(
        dimensions = ordered_dimensions, portable = portable), declarations,
        ValidationReport())
end

function capabilities(model::PottsModel)
    diagnostics = validate(model)
    isvalid(diagnostics) && return capabilities(normalize(model))
    return ModelCapabilityReport(CorePotts.ScientificCapabilities(
        dimensions = (), portable = false), (), diagnostics)
end

function _declaration_report(component::VolumeConstraint)
    prefix = _property_prefix(component.name)
    return DeclarationReport(component.name, :energy,
        Tuple(entry.key for entry in component.bindings),
        (Symbol(prefix, "__target"), Symbol(prefix, "__strength")),
        (:proposal_energy,), (), (:QuadraticVolumeHamiltonian,),
        (bindings = Tuple((cell_type = semantic_identity(entry.key),
            target = entry.value.target, strength = entry.value.strength)
            for entry in component.bindings),),
        CorePotts.ScientificCapabilities())
end

function _declaration_report(component::FluctuatingVolumeConstraint)
    prefix = _property_prefix(component.name)
    return DeclarationReport(component.name, :mechanical,
        Tuple(entry.key for entry in component.bindings),
        (Symbol(prefix, "__target"), Symbol(prefix, "__strength"),
            Symbol(prefix, "__pressure")),
        (:mechanical_work, :auxiliary_evolution),
        (CorePotts.AuxiliaryEvolutionStream, CorePotts.AuxiliaryInitializationStream),
        (:FluctuatingVolumePressure,),
        (bindings = Tuple((cell_type = semantic_identity(entry.key),
            target = entry.value.target, strength = entry.value.strength)
            for entry in component.bindings), eta = component.eta,
            noise = component.noise, initialization = component.initialization,
            division = component.division), CorePotts.ScientificCapabilities())
end

function _declaration_report(component::Elongation)
    prefix = _property_prefix(component.name)
    return DeclarationReport(component.name, :energy,
        Tuple(entry.key for entry in component.bindings),
        (Symbol(prefix, "__target"), Symbol(prefix, "__strength")),
        (:proposal_energy, :unwrapped_first_and_second_moments), (),
        (:UnwrappedMomentTracker, :QuadraticElongationHamiltonian),
        (measure = :major_axis_rms_extent,
            bindings = Tuple((cell_type = semantic_identity(entry.key),
                target = entry.value.target, strength = entry.value.strength)
                for entry in component.bindings),
            target_division = component.target_division),
        CorePotts.ScientificCapabilities())
end


function _declaration_report(component::BoundaryConstraint)
    prefix = _property_prefix(component.name)
    return DeclarationReport(component.name, :energy,
        Tuple(entry.key for entry in component.bindings),
        (Symbol(prefix, "__target"), Symbol(prefix, "__strength")),
        (:proposal_energy, :boundary_measure), (),
        (:BoundaryMeasureTracker, :QuadraticBoundaryHamiltonian),
        (bindings = Tuple((cell_type = semantic_identity(entry.key),
            target = entry.value.target, strength = entry.value.strength)
            for entry in component.bindings), metric = component.metric),
        CorePotts.ScientificCapabilities())
end

function _declaration_report(component::FluctuatingBoundaryConstraint)
    prefix = _property_prefix(component.name)
    return DeclarationReport(component.name, :mechanical,
        Tuple(entry.key for entry in component.bindings),
        (Symbol(prefix, "__target"), Symbol(prefix, "__strength"),
            Symbol(prefix, "__tension")),
        (:mechanical_work, :boundary_measure, :auxiliary_evolution),
        (CorePotts.AuxiliaryEvolutionStream, CorePotts.AuxiliaryInitializationStream),
        (:BoundaryMeasureTracker, :FluctuatingSurfaceTension),
        (bindings = Tuple((cell_type = semantic_identity(entry.key),
            target = entry.value.target, strength = entry.value.strength)
            for entry in component.bindings), eta = component.eta,
            noise = component.noise, initialization = component.initialization,
            metric = component.metric, target_division = component.target_division,
            division = component.division), CorePotts.ScientificCapabilities())
end


function _declaration_report(component::PreserveConnectivity)
    return DeclarationReport(component.name, :constraint, (), (),
        (:reject_fragmenting_copy,), (), (:PreserveConnectedCells,),
        (scope = :all_finite_cells, exact = true),
        CorePotts.ScientificCapabilities())
end

function _declaration_report(component::LocalConnectivity)
    return DeclarationReport(component.name, :constraint, (), (),
        (:reject_local_fragmenting_copy,), (), (:MerksLocalConnectivityConstraint,),
        (
            scope=:copy_neighborhood,
            neighborhood=:clockwise_moore_2d,
            two_cell_exception=true,
        ),
        CorePotts.ScientificCapabilities(dimensions=(2,)))
end

function _declaration_report(component::Adhesion)
    members = Tuple(item for entry in component.law.values
        for item in (entry.key.left, entry.key.right))
    required = Tuple(unique(members))
    return DeclarationReport(component.name, :energy, required, (),
        (:proposal_energy,), (), (:UnorderedContactHamiltonian,),
        (symmetric = component.law.symmetric,
            values = Tuple((left = semantic_identity(entry.key.left),
                right = semantic_identity(entry.key.right), value = entry.value)
                for entry in component.law.values),
            default = component.law.default), CorePotts.ScientificCapabilities())
end

function _declaration_report(field::PrescribedField{N}) where {N}
    return DeclarationReport(field.name, :prescribed_field, (), (field.name,),
        (:field_sampling,), (), (:CellCenteredField,),
        (shape = size(field.values), values = field.values,
            origin = field.origin, spacing = field.spacing,
            boundaries = field.boundaries, interpolation = field.interpolation,
            semantic_time = field.semantic_time,
            synchronization_epoch = field.synchronization_epoch),
        CorePotts.ScientificCapabilities(dimensions = (N,)))
end

function _declaration_report(component::Chemotaxis)
    field = component.field
    dimensions = component.dimensions == 0 ? (2, 3) : (Int(component.dimensions),)
    return DeclarationReport(component.name, :drive,
        (field, Tuple(entry.key for entry in component.sensitivity)...),
        (Symbol(_property_prefix(component.name), "__sensitivity"),),
        (:proposal_drive,), (), (:CellCenteredField, :ChemotaxisDrive),
        (field = field,
            sensitivity = Tuple((cell_type = semantic_identity(entry.key),
                value = entry.value) for entry in component.sensitivity),
            response = component.response, mode = component.mode),
        CorePotts.ScientificCapabilities(; dimensions))
end

_invariant_semantics(::UnboundedProperty) = (kind = :unbounded,)
_invariant_semantics(invariant::ClosedPropertyInterval) =
    (kind = :closed_interval, lower = invariant.lower, upper = invariant.upper)

function _declaration_report(property::CellProperty)
    return DeclarationReport(property.name, :property, property.cell_types,
        (Symbol(_property_prefix(property.name)),), (:state_storage,), (),
        (:PropertyDescriptor,),
        (value_type = nameof(typeof(property.initial)), initial = property.initial,
            invariant = _invariant_semantics(property.invariant),
            mutability = property.mutability, division = property.division,
            transition = property.transition, retirement = property.retirement,
            visibility = property.visibility, persistence = property.persistence,
            optionality = property.optionality), CorePotts.ScientificCapabilities())
end

_trigger_rng_streams(::Any) = ()
_trigger_rng_streams(::CorePotts.BernoulliCellTrigger) = (CorePotts.EventStream,)

function _declaration_report(rule::PropertyUpdate)
    streams = _trigger_rng_streams(rule.trigger)
    return DeclarationReport(rule.name, :lifecycle_rule,
        (rule.source, rule.cell_types...), (), (:simultaneous_property_addition,),
        streams, (:LifecycleEvent, :AddCellProperty),
        (source = rule.source, role = rule.role,
            cell_types = Tuple(semantic_identity(value) for value in rule.cell_types),
            amount = rule.amount, schedule = rule.schedule, trigger = rule.trigger),
        CorePotts.ScientificCapabilities())
end


_lifecycle_rng_streams(trigger, effect = nothing) = _trigger_rng_streams(trigger)
_lifecycle_rng_streams(trigger, ::CorePotts.RandomOrientationDivision) =
    (_trigger_rng_streams(trigger)..., CorePotts.DivisionOrientationStream)

function _division_capabilities(::CorePotts.VectorDivision{N}) where {N}
    return CorePotts.ScientificCapabilities(dimensions = (N,))
end
_division_capabilities(::CorePotts.AbstractDivisionGeometry) =
    CorePotts.ScientificCapabilities()

function _declaration_report(rule::Transition)
    return DeclarationReport(rule.name, :lifecycle_rule,
        (rule.cell_types..., rule.destination), (), (:cell_type_transition,),
        _trigger_rng_streams(rule.trigger), (:LifecycleEvent, :TransitionCell),
        (cell_types = Tuple(semantic_identity(value) for value in rule.cell_types),
            destination = semantic_identity(rule.destination), schedule = rule.schedule,
            trigger = rule.trigger, priority = rule.priority),
        CorePotts.ScientificCapabilities())
end

function _declaration_report(rule::Division)
    return DeclarationReport(rule.name, :lifecycle_rule, rule.cell_types, (),
        (:binary_cell_division,), _lifecycle_rng_streams(rule.trigger, rule.geometry),
        (:LifecycleEvent, :DivideCell),
        (cell_types = Tuple(semantic_identity(value) for value in rule.cell_types),
            geometry = rule.geometry, schedule = rule.schedule,
            trigger = rule.trigger, priority = rule.priority),
        _division_capabilities(rule.geometry))
end

function _declaration_report(rule::ShrinkDeath)
    return DeclarationReport(rule.name, :lifecycle_rule,
        (rule.source, rule.cell_types...), (), (:target_shrinkage, :cell_retirement),
        _trigger_rng_streams(rule.trigger), (:LifecycleEvent, :InitiateShrinkDeath),
        (source = rule.source,
            cell_types = Tuple(semantic_identity(value) for value in rule.cell_types),
            decrement = rule.decrement, schedule = rule.schedule,
            trigger = rule.trigger, priority = rule.priority),
        CorePotts.ScientificCapabilities())
end

function _declaration_report(rule::ImmediateDeath)
    return DeclarationReport(rule.name, :lifecycle_rule,
        (rule.cell_types..., rule.medium), (), (:immediate_cell_removal,),
        _trigger_rng_streams(rule.trigger), (:LifecycleEvent, :RemoveCellImmediately),
        (cell_types = Tuple(semantic_identity(value) for value in rule.cell_types),
            medium = semantic_identity(rule.medium), schedule = rule.schedule,
            trigger = rule.trigger, priority = rule.priority),
        CorePotts.ScientificCapabilities())
end

function _declaration_report(component::NamedCoreComponent)
    report = _declaration_report(component.component)
    return DeclarationReport(component.name, report.kind, report.requires,
        report.provides, report.effects, report.rng_streams, report.lowering,
        report.semantic_data, report.capabilities)
end

_report_semantic_data(value::NamedTuple) = value
_report_semantic_data(value) = (value = value,)

function _declaration_report(component)
    metadata = CorePotts.component_metadata(component)
    return DeclarationReport(semantic_identity(component), metadata.identity.category,
        (metadata.required_properties, metadata.required_observables,
            metadata.required_relations), metadata.provided_properties,
        metadata.effects, metadata.rng_streams, (nameof(typeof(component)),),
        _report_semantic_data(metadata.semantic_data), metadata.capabilities)
end

_dependency_edges(component) = ()
_dependency_edges(component::VolumeConstraint) = Tuple(DependencyEdge(
    component.name, semantic_identity(entry.key), :cell_scope) for entry in component.bindings)
_dependency_edges(component::FluctuatingVolumeConstraint) = Tuple(DependencyEdge(
    component.name, semantic_identity(entry.key), :cell_scope) for entry in component.bindings)
_dependency_edges(component::Elongation) = Tuple(DependencyEdge(
    component.name, semantic_identity(entry.key), :cell_scope) for entry in component.bindings)
_dependency_edges(component::BoundaryConstraint) = Tuple(DependencyEdge(
    component.name, semantic_identity(entry.key), :cell_scope) for entry in component.bindings)
_dependency_edges(component::FluctuatingBoundaryConstraint) = Tuple(DependencyEdge(
    component.name, semantic_identity(entry.key), :cell_scope) for entry in component.bindings)
_dependency_edges(component::Adhesion) = Tuple(DependencyEdge(component.name,
    semantic_identity(value), :pairwise_member) for value in unique(Tuple(
        item for entry in component.law.values for item in (entry.key.left, entry.key.right))))
_dependency_edges(property::CellProperty) = Tuple(DependencyEdge(
    property.name, semantic_identity(value), :cell_scope) for value in property.cell_types)
_dependency_edges(rule::PropertyUpdate) = (DependencyEdge(
    rule.name, rule.source, :property_source),)
_dependency_edges(rule::Transition) = (
    (DependencyEdge(rule.name, semantic_identity(value), :cell_scope)
        for value in rule.cell_types)...,
    DependencyEdge(rule.name, semantic_identity(rule.destination),
        :transition_destination))
_dependency_edges(rule::Division) = Tuple(DependencyEdge(
    rule.name, semantic_identity(value), :cell_scope) for value in rule.cell_types)
_dependency_edges(rule::ShrinkDeath) = (
    DependencyEdge(rule.name, rule.source, :target_property_source),
    (DependencyEdge(rule.name, semantic_identity(value), :cell_scope)
        for value in rule.cell_types)...)
_dependency_edges(rule::ImmediateDeath) = (
    (DependencyEdge(rule.name, semantic_identity(value), :cell_scope)
        for value in rule.cell_types)...,
    DependencyEdge(rule.name, semantic_identity(rule.medium), :death_medium))
_dependency_edges(component::Chemotaxis) = (
    DependencyEdge(component.name, component.field, :prescribed_field),
    (DependencyEdge(component.name, semantic_identity(entry.key), :cell_scope)
        for entry in component.sensitivity)...)

function dependencies(model::NormalizedModel)
    edges = Tuple(edge for component in model.components for edge in _dependency_edges(component))
    declared = Set((semantic_identity(value) for value in
        (model.cell_types..., model.media..., model.components...)))
    unresolved = Tuple(edge for edge in edges if !(edge.provider in declared))
    return DependencyReport(edges, unresolved)
end

dependencies(model::PottsModel) = dependencies(normalize(model))

"""
Return a stable semantic manifest for comparison, provenance, and paper artifacts.

The manifest intentionally declares `:not_claimed` reconstruction: runtime checkpoints remain a
CorePotts concern, and executable model serialization requires a separate opt-in protocol.
"""
function semantic_manifest(model::NormalizedModel)
    report = explain(model)
    numerical = (
        real_type = nameof(CorePotts.real_type(model.numerics)),
        accumulation_type = nameof(CorePotts.accumulation_type(model.numerics)),
        math_policy = nameof(typeof(model.numerics.math)),
        reduction_policy = nameof(typeof(model.numerics.reductions)),
        overflow_policy = nameof(typeof(model.numerics.overflow)),
    )
    return SemanticManifest(CorePotts.NORMALIZED_IR_CONTRACT_VERSION,
        CorePotts.AUTHORING_DSL_CONTRACT_VERSION,
        CorePotts.NORMALIZED_IR_CONTRACT_VERSION,
        model.fingerprint, numerical, report.declarations,
        dependencies(model), :not_claimed)
end

semantic_manifest(model::PottsModel) = semantic_manifest(normalize(model))

function Base.show(io::IO, model::NormalizedModel)
    print(io, "Normalized PottsToolkit.PottsModel(", length(model.cell_types),
        " cell types, ", length(model.media), " media, ", length(model.components),
        " components; ", first(model.fingerprint.digest, 12), "…)")
end

Base.show(io::IO, mime::MIME"text/plain", model::NormalizedModel) =
    show(io, mime, explain(model))
