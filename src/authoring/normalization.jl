"""Typed immutable normalized meaning shared by reports, fingerprints, and lowering."""
struct NormalizedModel{N <: CorePotts.NumericalPolicy}
    numerics::N
    cell_types::Tuple
    media::Tuple
    components::Tuple
    provenance_entries::Tuple
    fingerprint::SemanticFingerprint
end

semantic_fingerprint(model::NormalizedModel) = model.fingerprint
semantic_fingerprint(model::PottsModel) = semantic_fingerprint(normalize(model))
provenance(model::NormalizedModel) = model.provenance_entries
provenance(model::PottsModel) = provenance(normalize(model))

_flatten_declarations(::Tuple{}) = ()

_flatten_declaration(fragment::ModelFragment) =
    _flatten_declarations(_scoped_fragment_declarations(fragment))
_flatten_declaration(declaration) = (declaration,)

function _flatten_declarations(declarations::Tuple)
    head = _flatten_declaration(first(declarations))
    return (head..., _flatten_declarations(Base.tail(declarations))...)
end


_provenance_declaration(declaration) = (ProvenanceEntry(
    semantic_identity(declaration), :direct, nothing, true, false, nothing, ()),)

function _fragment_provenance(declaration, fragment::SemanticName)
    return (ProvenanceEntry(semantic_identity(declaration), :fragment,
        fragment, true, false, nothing, ()),)
end

_fragment_provenance(child::ModelFragment, fragment::SemanticName) =
    _provenance_declaration(child)

function _provenance_declaration(fragment::ModelFragment)
    scoped = _scoped_fragment_declarations(fragment)
    return Tuple(entry for declaration in scoped
        for entry in _fragment_provenance(declaration, fragment.name))
end

_provenance_declarations(::Tuple{}) = ()
function _provenance_declarations(declarations::Tuple)
    return (_provenance_declaration(first(declarations))...,
        _provenance_declarations(Base.tail(declarations))...)
end

_partition_declarations(::Tuple{}) = ((), (), ())

_prepend_partition(value::CellType, cells, media, components) =
    ((value, cells...), media, components)
_prepend_partition(value::Medium, cells, media, components) =
    (cells, (value, media...), components)
_prepend_partition(value, cells, media, components) =
    (cells, media, (value, components...))

function _partition_declarations(declarations::Tuple)
    cells, media, components = _partition_declarations(Base.tail(declarations))
    return _prepend_partition(first(declarations), cells, media, components)
end

struct _ValidationContext{T <: AbstractFloat}
    cell_types::Tuple
    biological_types::Tuple
    components::Tuple
end

_context_real_type(::_ValidationContext{T}) where {T} = T

_validate_declaration(::Union{CellType, Medium}, context::_ValidationContext) = ()

function _validate_volume(component::Union{VolumeConstraint, FluctuatingVolumeConstraint},
        context::_ValidationContext)
    diagnostics = ()
    for binding in component.bindings
        binding.key in context.cell_types || (diagnostics = (diagnostics...,
            Diagnostic(:error, :unknown_cell_type,
                "volume binding references an undeclared cell type";
                identity = semantic_identity(component), related = (binding.key,),
                correction = "declare the cell type or remove the binding")))
    end
    return diagnostics
end


_validate_declaration(component::VolumeConstraint, context::_ValidationContext) =
    _validate_volume(component, context)
_validate_declaration(component::FluctuatingVolumeConstraint,
    context::_ValidationContext) = _validate_volume(component, context)

function _validate_declaration(component::Elongation, context::_ValidationContext)
    diagnostics = ()
    for binding in component.bindings
        binding.key in context.cell_types || (diagnostics = (diagnostics...,
            Diagnostic(:error, :unknown_cell_type,
                "elongation binding references an undeclared cell type";
                identity = semantic_identity(component), related = (binding.key,),
                correction = "declare the cell type or remove the binding")))
    end
    return diagnostics
end

function _validate_boundary(component::Union{
        BoundaryConstraint, FluctuatingBoundaryConstraint}, context::_ValidationContext)
    diagnostics = ()
    for binding in component.bindings
        binding.key in context.cell_types || (diagnostics = (diagnostics...,
            Diagnostic(:error, :unknown_cell_type,
                "boundary binding references an undeclared cell type";
                identity = semantic_identity(component), related = (binding.key,),
                correction = "declare the cell type or remove the binding")))
    end
    return diagnostics
end

_validate_declaration(component::BoundaryConstraint, context::_ValidationContext) =
    _validate_boundary(component, context)
_validate_declaration(component::FluctuatingBoundaryConstraint,
    context::_ValidationContext) = _validate_boundary(component, context)
_validate_declaration(::PreserveConnectivity, context::_ValidationContext) = ()

_validate_declaration(component::NamedCoreComponent, context::_ValidationContext) =
    _validate_declaration(component.component, context)

_bound_property_cells(component, role::Symbol) = nothing
_bound_property_cells(component::VolumeConstraint, role::Symbol) =
    role in (:target, :strength) ? Tuple(keys(component.bindings)) : nothing
_bound_property_cells(component::FluctuatingVolumeConstraint, role::Symbol) =
    role in (:target, :strength) ? Tuple(keys(component.bindings)) : nothing
_bound_property_cells(component::Elongation, role::Symbol) =
    role in (:target, :strength) ? Tuple(keys(component.bindings)) : nothing
_bound_property_cells(component::BoundaryConstraint, role::Symbol) =
    role in (:target, :strength) ? Tuple(keys(component.bindings)) : nothing
_bound_property_cells(component::FluctuatingBoundaryConstraint, role::Symbol) =
    role in (:target, :strength) ? Tuple(keys(component.bindings)) : nothing
_bound_property_cells(property::CellProperty, role::Symbol) =
    role === :value ? property.cell_types : nothing

function _validate_declaration(property::CellProperty, context::_ValidationContext)
    diagnostics = ()
    for cell_type in property.cell_types
        cell_type in context.cell_types || (diagnostics = (diagnostics..., Diagnostic(
            :error, :unknown_cell_type,
            "cell property scope references an undeclared cell type";
            identity = property.name, related = (cell_type,),
            correction = "declare the cell type or correct the property scope")))
    end
    property.optionality === OptionalProperty && (diagnostics = (diagnostics...,
        Diagnostic(:error, :optional_property_storage_unavailable,
            "optional cell properties require a qualified CorePotts representation";
            identity = property.name,
            correction = "use RequiredProperty until optional device storage is qualified"),))
    property.persistence === EphemeralProperty && (diagnostics = (diagnostics...,
        Diagnostic(:error, :ephemeral_property_storage_unavailable,
            "ephemeral cell properties require a checkpoint-exclusion protocol";
            identity = property.name,
            correction = "use CheckpointedProperty until checkpoint exclusion is qualified"),))
    return diagnostics
end

function _validate_declaration(rule::PropertyUpdate, context::_ValidationContext)
    diagnostics = ()
    for cell_type in rule.cell_types
        cell_type in context.cell_types || (diagnostics = (diagnostics..., Diagnostic(
            :error, :unknown_cell_type,
            "property update references an undeclared cell type";
            identity = rule.name, related = (cell_type,),
            correction = "declare the cell type or correct the rule scope")))
    end
    source = findfirst(component -> semantic_identity(component) == rule.source,
        context.components)
    if source === nothing
        diagnostics = (diagnostics..., Diagnostic(:error, :missing_property_source,
            "property update references an undeclared source component";
            identity = rule.name, related = (rule.source,),
            correction = "add the property/component declaration or correct the source name"))
    else
        component = context.components[source]
        bound_cells = _bound_property_cells(component, rule.role)
        if bound_cells === nothing
            diagnostics = (diagnostics..., Diagnostic(:error,
                :unsupported_property_source,
                "property update source does not expose the requested Level 2 property role";
                identity = rule.name, related = (rule.source, rule.role),
                correction = "target a declared property role supported by the source"))
        else
            for cell_type in rule.cell_types
                cell_type in bound_cells || (diagnostics = (diagnostics...,
                    Diagnostic(:error, :unbound_property_target,
                        "property update targets a cell type not bound by its source component";
                        identity = rule.name, related = (cell_type, rule.source),
                        correction = "bind the source for this cell type or narrow the rule scope")))
            end
        end
    end
    return diagnostics
end

function _validate_declaration(component::Adhesion, context::_ValidationContext)
    diagnostics = ()
    law = component.law
    for binding in law.values
        pair = binding.key
        pair.left in context.biological_types && pair.right in context.biological_types ||
            (diagnostics = (diagnostics..., Diagnostic(:error, :unknown_pair_member,
                "pairwise law references an undeclared biological type";
                identity = semantic_identity(component), related = (pair,),
                correction = "declare both pair members or remove the pair")))
    end
    if law.default === nothing
        expected = PairIdentity[]
        values = sort!(collect(context.biological_types); by = _identity_text)
        for left_index in eachindex(values), right_index in left_index:length(values)
            push!(expected, PairIdentity(values[left_index], values[right_index];
                symmetric = true))
        end
        missing = Tuple(pair for pair in expected if !haskey(law.values, pair))
        isempty(missing) || (diagnostics = (diagnostics..., Diagnostic(:error,
            :missing_pairwise_values,
            "symmetric pairwise law is incomplete and has no explicit default";
            identity = semantic_identity(component), related = missing,
            correction = "provide every unordered pair or set an explicit default")))
    end
    return diagnostics
end

_validate_declaration(::PrescribedField, context::_ValidationContext) = ()

_is_field_declaration(::Any) = false
_is_field_declaration(::PrescribedField) = true
_field_declaration_dimension(field::PrescribedField) = ndims(field.values)
_field_declaration_values(field::PrescribedField) = field.values

function _validate_declaration(component::Chemotaxis, context::_ValidationContext)
    diagnostics = ()
    field_index = findfirst(value -> semantic_identity(value) == component.field,
        context.components)
    if field_index === nothing
        diagnostics = (diagnostics..., Diagnostic(:error, :missing_prescribed_field,
            "chemotaxis references an undeclared prescribed field";
            identity = component.name, related = (component.field,),
            correction = "add the PrescribedField declaration or correct the field name"))
    elseif !_is_field_declaration(context.components[field_index])
        diagnostics = (diagnostics..., Diagnostic(:error, :invalid_chemotaxis_field,
            "chemotaxis field reference resolves to a non-field declaration";
            identity = component.name, related = (component.field,),
            correction = "reference a Field or PrescribedField declaration"))
    else
        field = context.components[field_index]
        field_dimensions = _field_declaration_dimension(field)
        (field_dimensions === nothing || component.dimensions == 0 ||
            field_dimensions == component.dimensions) ||
            (diagnostics = (diagnostics..., Diagnostic(:error,
                :chemotaxis_field_dimension_mismatch,
                "chemotaxis dimensionality does not match its prescribed field";
                identity = component.name, related = (component.field,
                    Int(component.dimensions), field_dimensions),
                correction = "reconstruct the chemotaxis declaration from this field"),))
        for value in _field_declaration_values(field)
            try
                CorePotts.field_response(component.response, value)
            catch error
                diagnostics = (diagnostics..., Diagnostic(:error,
                    :invalid_field_response_domain,
                    "prescribed field values violate the selected chemotaxis response domain";
                    identity = component.name, related = (component.field, value),
                    correction = "change the field values or select a compatible response law"))
                break
            end
        end
    end
    for entry in component.sensitivity
        entry.key in context.cell_types || (diagnostics = (diagnostics..., Diagnostic(
            :error, :unknown_cell_type,
            "chemotaxis sensitivity references an undeclared cell type";
            identity = component.name, related = (entry.key,),
            correction = "declare the cell type or remove its sensitivity binding")))
    end
    return diagnostics
end

function _validate_lifecycle_cells(rule, context::_ValidationContext)
    diagnostics = ()
    for cell_type in rule.cell_types
        cell_type in context.cell_types || (diagnostics = (diagnostics..., Diagnostic(
            :error, :unknown_cell_type,
            "lifecycle rule references an undeclared cell type";
            identity = rule.name, related = (cell_type,),
            correction = "declare the cell type or correct the lifecycle scope")))
    end
    return diagnostics
end

function _validate_declaration(rule::Transition, context::_ValidationContext)
    diagnostics = _validate_lifecycle_cells(rule, context)
    rule.destination in context.cell_types || (diagnostics = (diagnostics..., Diagnostic(
        :error, :unknown_transition_destination,
        "transition destination is not a declared finite cell type";
        identity = rule.name, related = (rule.destination,),
        correction = "declare the destination cell type or correct the transition")))
    return diagnostics
end

_validate_declaration(rule::Division, context::_ValidationContext) =
    _validate_lifecycle_cells(rule, context)

function _validate_declaration(rule::ShrinkDeath, context::_ValidationContext)
    diagnostics = _validate_lifecycle_cells(rule, context)
    source = findfirst(component -> semantic_identity(component) == rule.source,
        context.components)
    if source === nothing
        diagnostics = (diagnostics..., Diagnostic(:error, :missing_property_source,
            "shrink death references an undeclared target-property source";
            identity = rule.name, related = (rule.source,),
            correction = "add the volume/boundary declaration or correct the source"))
    else
        bound_cells = _bound_property_cells(context.components[source], :target)
        if bound_cells === nothing
            diagnostics = (diagnostics..., Diagnostic(:error,
                :unsupported_shrink_target,
                "shrink death source does not expose a Level 2 target property";
                identity = rule.name, related = (rule.source,),
                correction = "target a volume or boundary declaration"))
        else
            for cell_type in rule.cell_types
                cell_type in bound_cells || (diagnostics = (diagnostics..., Diagnostic(
                    :error, :unbound_property_target,
                    "shrink death targets a cell type not bound by its source";
                    identity = rule.name, related = (cell_type, rule.source),
                    correction = "bind the source for this cell type or narrow the death scope")))
            end
        end
    end
    return diagnostics
end

function _validate_declaration(rule::ImmediateDeath, context::_ValidationContext)
    diagnostics = _validate_lifecycle_cells(rule, context)
    rule.medium in context.biological_types && rule.medium isa Medium ||
        (diagnostics = (diagnostics..., Diagnostic(:error, :unknown_death_medium,
            "immediate death references an undeclared medium";
            identity = rule.name, related = (rule.medium,),
            correction = "declare the medium or correct the death destination")))
    return diagnostics
end

function _validate_declaration(component, context::_ValidationContext)
    identity = _core_semantic_identity(component)
    identity === nothing && return (Diagnostic(:error, :unsupported_declaration,
        "declaration does not implement the Level 2 semantic component protocol";
        identity = try semantic_identity(component) catch; nothing end,
        correction = "implement the public CorePotts component protocols or use a supported Level 2 declaration"),)
    return ()
end


_lifecycle_event_id(declaration) = nothing
_lifecycle_event_id(rule::PropertyUpdate) =
    UInt16(1 + _semantic_rng_code(rule.name, :event, UInt16(0x0ffe)))
_lifecycle_event_id(rule::Union{Transition, Division, ShrinkDeath, ImmediateDeath}) =
    UInt16(1 + _semantic_rng_code(rule.name, :event, UInt16(0x0ffe)))

_property_write_target(component) = nothing
_property_write_target(rule::PropertyUpdate) = (rule.source, rule.role)
_property_write_target(rule::ShrinkDeath) = (rule.source, :target)

function _fragment_diagnostics(fragment::ModelFragment, declared::Tuple)
    diagnostics = ()
    direct_identities = Tuple(semantic_identity(value) for value in fragment.declarations)
    for exported in fragment.exports
        exported in direct_identities || (diagnostics = (diagnostics..., Diagnostic(
            :error, :unknown_fragment_export,
            "fragment exports must name one of its direct declarations";
            identity = fragment.name, related = (exported,), fragment = fragment.name,
            correction = "remove the export or add a declaration with that identity"),))
    end
    for requirement in fragment.requirements
        if requirement isa AbstractFragmentRole
            diagnostics = (diagnostics..., Diagnostic(
                :error, :unresolved_fragment_role,
                "fragment has an unbound typed requirement";
                identity = fragment.name, related = (requirement,), fragment = fragment.name,
                correction = "bind the role explicitly before constructing a problem"))
        elseif requirement ∉ declared
            diagnostics = (diagnostics..., Diagnostic(
                :error, :unsatisfied_fragment_requirement,
                "fragment requirement is not provided by the composed model";
                identity = fragment.name, related = (requirement,), fragment = fragment.name,
                correction = "compose a provider for the required identity"))
        end
    end
    for declaration in _scoped_fragment_declarations(fragment)
        declaration isa ModelFragment || continue
        diagnostics = (diagnostics..., _fragment_diagnostics(declaration, declared)...)
    end
    return diagnostics
end

_fragment_diagnostics(declaration, declared::Tuple) = ()

function _composition_diagnostics(model::PottsModel, declarations::Tuple,
        components::Tuple)
    diagnostics = ()
    declared = Tuple(semantic_identity(value) for value in declarations)
    for declaration in model.declarations
        diagnostics = (diagnostics..., _fragment_diagnostics(declaration, declared)...)
    end
    targets = Tuple(filter(value -> !isnothing(value),
        map(_property_write_target, components)))
    for target in unique(targets)
        writers = Tuple(semantic_identity(component) for component in components
            if _property_write_target(component) == target)
        length(writers) <= 1 || (diagnostics = (diagnostics..., Diagnostic(
            :error, :ambiguous_property_writers,
            "multiple rules write the same property role without an explicit combination law";
            identity = first(writers), related = (target, writers...),
            correction = "retain one writer or place an explicit combination law between them"),))
    end
    return diagnostics
end

function _diagnose_model(model::PottsModel)
    declarations = _flatten_declarations(model.declarations)
    diagnostics = ()
    identities = map(_declaration_identity, declarations)
    for identity in unique(identities)
        count(==(identity), identities) > 1 && (diagnostics = (diagnostics...,
            Diagnostic(:error, :duplicate_identity,
                "semantic identity is declared more than once"; identity,
                correction = "remove the duplicate or use replace/rename explicitly")))
    end

    cell_types, media, components = _partition_declarations(declarations)
    isempty(cell_types) && (diagnostics = (diagnostics..., Diagnostic(:error,
        :missing_cell_type, "a runnable model must declare at least one finite CellType";
        correction = "add a CellType declaration")))
    isempty(media) && (diagnostics = (diagnostics..., Diagnostic(:error,
        :missing_medium, "a runnable model must declare at least one Medium";
        correction = "add a Medium declaration")))

    T = CorePotts.real_type(model.numerics)
    context = _ValidationContext{T}(
        cell_types, (cell_types..., media...), components)
    for component in components
        diagnostics = (diagnostics..., _validate_declaration(component, context)...)
    end
    diagnostics = (diagnostics...,
        _composition_diagnostics(model, declarations, components)...)
    diagnostics = (diagnostics..., _phase_diagnostics(components)...)
    lifecycle_ids = Tuple(filter(value -> !isnothing(value),
        map(_lifecycle_event_id, components)))
    any(component -> component isa Rule, components) &&
        (lifecycle_ids = (lifecycle_ids..., _rule_program_event_id()))
    for event_id in unique(lifecycle_ids)
        count(==(event_id), lifecycle_ids) > 1 && (diagnostics = (diagnostics...,
            Diagnostic(:error, :lifecycle_rng_identity_collision,
                "lifecycle declarations collide in the v1 semantic RNG event domain";
                related = (event_id,),
                correction = "rename one lifecycle declaration or choose a distinct RNG label")))
    end
    return ValidationReport(diagnostics)
end

validate(model::PottsModel) = _diagnose_model(model)
isvalid(model::PottsModel) = isvalid(validate(model))

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

function _canonical_open(io::IO, value)
    print(io, nameof(typeof(value)), '{')
    return io
end

_canonical_close(io::IO) = (print(io, '}'); io)

function _canonical_write(io::IO, value::Symbol)
    _canonical_open(io, value)
    print(io, sizeof(String(value)), ':', String(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::AbstractString)
    _canonical_open(io, value)
    print(io, ncodeunits(value), ':', value)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Type)
    _canonical_open(io, value)
    print(io, parentmodule(value), '.', nameof(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::AbstractFloat)
    _canonical_open(io, value)
    print(io, bitstring(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Union{Integer, Bool, VersionNumber})
    _canonical_open(io, value)
    print(io, value)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Enum)
    _canonical_open(io, value)
    print(io, Int(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, ::Nothing)
    print(io, "Nothing{nothing}")
    return io
end

function _canonical_write(io::IO, value::Tuple)
    _canonical_open(io, value)
    for item in value
        _canonical_write(io, item)
        print(io, ';')
    end
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::NamedTuple)
    _canonical_open(io, value)
    for key in propertynames(value)
        _canonical_write(io, key)
        _canonical_write(io, getproperty(value, key))
    end
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Pair)
    _canonical_open(io, value)
    _canonical_write(io, first(value))
    _canonical_write(io, last(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::AbstractArray)
    _canonical_open(io, value)
    _canonical_write(io, eltype(value))
    _canonical_write(io, size(value))
    for item in value
        _canonical_write(io, item)
        print(io, ';')
    end
    return _canonical_close(io)
end

_canonical_write(io::IO, value::Namespace) =
    (_canonical_open(io, value); _canonical_write(io, value.parts); _canonical_close(io))

function _canonical_write(io::IO, value::SemanticName)
    _canonical_open(io, value)
    _canonical_write(io, value.namespace)
    _canonical_write(io, value.name)
    return _canonical_close(io)
end

_canonical_write(io::IO, value::Union{CellType, Medium}) =
    (_canonical_open(io, value); _canonical_write(io, semantic_identity(value));
     _canonical_close(io))

function _canonical_write(io::IO, value::Binding)
    _canonical_open(io, value)
    _canonical_write(io, value.key)
    _canonical_write(io, value.value)
    return _canonical_close(io)
end

_canonical_write(io::IO, value::BindingTable) =
    (_canonical_open(io, value); _canonical_write(io, value.entries); _canonical_close(io))

function _canonical_write(io::IO, value::PairIdentity)
    _canonical_open(io, value)
    _canonical_write(io, value.left)
    _canonical_write(io, value.right)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::PairwiseLaw)
    _canonical_open(io, value)
    _canonical_write(io, value.name)
    _canonical_write(io, value.values)
    _canonical_write(io, value.symmetric)
    _canonical_write(io, value.default)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::VolumeParameters)
    _canonical_open(io, value)
    _canonical_write(io, value.target)
    _canonical_write(io, value.strength)
    return _canonical_close(io)
end


function _canonical_write(io::IO, value::BoundaryParameters)
    _canonical_open(io, value)
    _canonical_write(io, value.target)
    _canonical_write(io, value.strength)
    return _canonical_close(io)
end

_canonical_write(io::IO, value::ElongationParameters) = _canonical_fields(io, value)

function _canonical_fields(io::IO, value)
    _canonical_open(io, value)
    for field in fieldnames(typeof(value))
        _canonical_write(io, getfield(value, field))
    end
    return _canonical_close(io)
end

_canonical_write(io::IO, value::VolumeConstraint) = _canonical_fields(io, value)
_canonical_write(io::IO, value::FluctuatingVolumeConstraint) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Elongation) = _canonical_fields(io, value)
_canonical_write(io::IO, value::BoundaryConstraint) = _canonical_fields(io, value)
_canonical_write(io::IO, value::FluctuatingBoundaryConstraint) =
    _canonical_fields(io, value)
_canonical_write(io::IO, value::PreserveConnectivity) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Adhesion) = _canonical_fields(io, value)
_canonical_write(io::IO, value::PrescribedField) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Chemotaxis) = _canonical_fields(io, value)
_canonical_write(io::IO, value::PropertyUpdate) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Transition) = _canonical_fields(io, value)
_canonical_write(io::IO, value::Division) = _canonical_fields(io, value)
_canonical_write(io::IO, value::ShrinkDeath) = _canonical_fields(io, value)
_canonical_write(io::IO, value::ImmediateDeath) = _canonical_fields(io, value)
_canonical_write(io::IO, value::NamedCoreComponent) = _canonical_fields(io, value)
_canonical_write(io::IO, value::CellProperty) = _canonical_fields(io, value)
_canonical_write(io::IO, value::ClosedPropertyInterval) = _canonical_fields(io, value)
_canonical_write(io::IO, value::CorePotts.FixedMechanicalNoise) = _canonical_fields(io, value)
_canonical_write(io::IO, value::CorePotts.AxisFieldBoundary) = _canonical_fields(io, value)

function _canonical_write(io::IO, value::CorePotts.NumericalPolicy)
    _canonical_open(io, value)
    _canonical_write(io, Symbol(string(CorePotts.real_type(value))))
    _canonical_write(io, Symbol(string(CorePotts.accumulation_type(value))))
    _canonical_write(io, Symbol(string(typeof(value.math))))
    _canonical_write(io, Symbol(string(typeof(value.reductions))))
    _canonical_write(io, Symbol(string(typeof(value.overflow))))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value)
    identity = _core_semantic_identity(value)
    identity === nothing && throw(ArgumentError(
        "$(typeof(value)) does not provide canonical semantic fingerprint data"))
    core_identity = CorePotts.component_identity(value)
    semantic_data = CorePotts.component_semantic_data(value)
    semantic_data === value && fieldcount(typeof(value)) != 0 && throw(ArgumentError(
        "parameterized CorePotts component $(typeof(value)) must provide the public component_semantic_data protocol"))
    _canonical_open(io, value)
    _canonical_write(io, identity)
    _canonical_write(io, core_identity.version)
    _canonical_write(io, core_identity.category)
    semantic_data === value || _canonical_write(io, semantic_data)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Bool)
    _canonical_open(io, value)
    print(io, value)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Real)
    _canonical_open(io, value)
    print(io, value)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::CorePotts.MechanicalInitialization)
    _canonical_open(io, value)
    print(io, Int(value))
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Union{CorePotts.AlgorithmTemperatureNoise,
        CorePotts.ConstitutiveResetAfterDivision, CorePotts.PreserveMechanicalOnDivision,
        CorePotts.StationaryRedrawAfterDivision, CorePotts.EveryMCS,
        CorePotts.AlwaysLifecycleTrigger})
    _canonical_open(io, value)
    print(io, '}')
    return io
end


function _canonical_write(io::IO, value::Union{CorePotts.OnceAtMCS, CorePotts.AtMCS,
        CorePotts.PeriodicMCS, CorePotts.BernoulliCellTrigger,
        CorePotts.PropertyAtLeast, CorePotts.CellTypeIn,
        CorePotts.AllLifecycleTriggers})
    return _canonical_fields(io, value)
end

function _canonical_write(io::IO, value::Union{AbstractPropertyInvariant,
        CorePotts.AbstractDivisionPolicy, CorePotts.AbstractTransitionPolicy,
        CorePotts.AbstractRetirementPolicy, CorePotts.AbstractFieldBoundary,
        CorePotts.AbstractFieldInterpolation, CorePotts.AbstractFieldResponse,
        CorePotts.AbstractChemotaxisMode, CorePotts.AbstractBoundaryMetric,
        CorePotts.AbstractDivisionGeometry})
    fieldcount(typeof(value)) == 0 && return (
        _canonical_open(io, value); _canonical_close(io))
    return _canonical_fields(io, value)
end

function _canonical_write(io::IO, value::Union{
        CorePotts.AbstractSiteInitializer,
        CorePotts.AbstractSiteOwnershipPolicy,
        CorePotts.NoSiteInvariant,
        CorePotts.AbstractAcceptedCopyAssignment,
        CorePotts.AbstractSiteUpdateLaw,
        CorePotts.AbstractHistoryFill,
        CorePotts.AbstractHistoryDivisionPolicy,
        CorePotts.AbstractHistoryTransitionPolicy,
        CorePotts.AbstractEndpointLifecyclePolicy,
        CorePotts.RelationshipCapacity,
        CorePotts.AlwaysAcceptedCopy,
        CorePotts.CoupledPhase,
        CorePotts.PottsAttempts,
        CorePotts.LifecyclePhase,
        CorePotts.ObservationPhase,
        CorePotts.Advance,
        CorePotts.Exchange,
        CorePotts.Sample,
        CorePotts.Update,
        CorePotts.MCSRange,
        CorePotts.During,
        CorePotts.ProtocolStage,
        CorePotts.ContinuousInterval,
        CorePotts.OneMCS,
        CorePotts.HalfMCS,
        CorePotts.EveryGlobal,
        CorePotts.AbstractDelayInterpolation,
        CorePotts.RepeatInitialDelay,
        CorePotts.AbstractTriggerMemory,
        CorePotts.SampledTrigger,
        CorePotts.RootTrigger,
        CorePotts.EventAssignment,
        CorePotts.FromTriggerSnapshot,
        CorePotts.FromExecutionSnapshot,
        CorePotts.NoImmediateCascade,
        CorePotts.CascadeUntilStable,
        CorePotts.LifecycleRequest,
        CorePotts.SymbolIdentity,
        CorePotts.SymbolRef,
        CorePotts.InputRef,
        CorePotts.IdentityMap,
        CorePotts.AbstractCompatibilityLevel,
        CorePotts.CompatibilityItem,
        CorePotts.MorpheusSemanticProfile,
        CorePotts.SBMLSemanticProfile,
        CorePotts.GlobalClock,
        CorePotts.MCSDuration,
        CorePotts.AbstractMCSPosition,
        CorePotts.AbstractScheduledEntry,
        CorePotts.TimedLifecyclePhase,
        CorePotts.MultirateSchedule,
        CorePotts.AbstractObservationPhase,
        CorePotts.AbstractObservationFailurePolicy,
        CorePotts.AbstractObservationSchema})
    return _canonical_fields(io, value)
end

function _canonical_write(io::IO, law::CorePotts.DirectLaw)
    _canonical_open(io, law)
    _canonical_write(io, law.name)
    _canonical_write(io, law.version)
    return _canonical_close(io)
end

function _canonical_write(io::IO, value::Union{
        CorePotts.AbstractContinuousDomain,
        CorePotts.AngularMembrane,
        CorePotts.FillMembrane,
        CorePotts.ConservativeMembraneRemap,
        CorePotts.PartitionMembraneByGeometry,
        CorePotts.PreserveMembrane,
        CorePotts.ResetMembrane,
        CorePotts.StateVariable,
        CorePotts.InputVariable,
        CorePotts.Constant,
        CorePotts.IntermediateVariable,
        CorePotts.ObservableVariable,
        CorePotts.TimeVariable,
        CorePotts.AbstractContinuousStatement,
        CorePotts.AbstractReactionInterpretation,
        CorePotts.AbstractFixedStepper,
        CorePotts.SystemStep,
        CorePotts.FixedStep,
        CorePotts.AdaptiveStep,
        CorePotts.SystemClock,
        CorePotts.ReactionDiffusion,
        CorePotts.ByCellVolume,
        CorePotts.ConstantConcentration,
        CorePotts.Uptake,
        CorePotts.SteadyStateAdvance})
    return _canonical_fields(io, value)
end

function _canonical_write(io::IO, value::Union{
        CorePotts.StableRelationshipPriority,
        CorePotts.AbstractRelationshipRequest,
        CorePotts.RelationshipPolicyBundle})
    return _canonical_fields(io, value)
end

function _semantic_fingerprint(numerics, cells, media, components)
    io = IOBuffer()
    print(io, "PottsToolkitNormalizedIR|", CorePotts.NORMALIZED_IR_CONTRACT_VERSION, '|')
    _canonical_write(io, numerics)
    _canonical_write(io, cells)
    _canonical_write(io, media)
    _canonical_write(io, components)
    digest = bytes2hex(SHA.sha256(take!(io)))
    return SemanticFingerprint(CorePotts.SEMANTIC_FINGERPRINT_VERSION, digest)
end

function _execution_write(io::IO, value::Tuple)
    print(io, "Tuple[")
    for item in value
        _execution_write(io, item)
        print(io, ';')
    end
    print(io, ']')
    return io
end

function _execution_write(io::IO, value::NamedTuple)
    print(io, "NamedTuple[")
    for key in propertynames(value)
        _execution_write(io, key)
        _execution_write(io, getproperty(value, key))
    end
    print(io, ']')
    return io
end

function _execution_write(io::IO, value::Union{Symbol, AbstractString, Number,
        VersionNumber, Enum, Nothing})
    print(io, nameof(typeof(value)), ':', repr(value), ';')
    return io
end

function _execution_write(io::IO, value::Type)
    print(io, parentmodule(value), '.', nameof(value), ';')
    return io
end

function _execution_write(io::IO, value)
    type = typeof(value)
    print(io, parentmodule(type), '.', nameof(type), '{')
    for field in fieldnames(type)
        print(io, field, '=')
        _execution_write(io, getfield(value, field))
    end
    print(io, '}')
    return io
end

"""Execution identity for cache keys, reports, and exact-replay qualification."""
function execution_fingerprint(model::NormalizedModel, algorithm, backend;
        dimensions::Integer,
        execution = CorePotts.DefaultPottsExecution())
    dimensions in (2, 3) || throw(ArgumentError(
        "execution fingerprints require a 2D or 3D model realization"))
    io = IOBuffer()
    print(io, "PottsToolkitExecution|", CorePotts.EXECUTION_FINGERPRINT_VERSION, '|')
    _execution_write(io, model.fingerprint.version)
    _execution_write(io, model.fingerprint.digest)
    _execution_write(io, model.numerics)
    _execution_write(io, CorePotts.component_identity(algorithm))
    _execution_write(io, CorePotts.algorithm_guarantees(algorithm))
    _execution_write(io, typeof(backend))
    _execution_write(io, CorePotts.backend_capabilities(backend))
    _execution_write(io, dimensions)
    _execution_write(io, execution)
    _execution_write(io, CorePotts.rng_contract_version(CorePotts.Philox4x32x10V1()))
    _execution_write(io, VERSION)
    _execution_write(io, Base.pkgversion(CorePotts))
    _execution_write(io, Base.pkgversion(parentmodule(@__MODULE__)))
    return ExecutionFingerprint(CorePotts.EXECUTION_FINGERPRINT_VERSION,
        bytes2hex(SHA.sha256(take!(io))))
end

execution_fingerprint(model::PottsModel, algorithm, backend; kwargs...) =
    execution_fingerprint(normalize(model), algorithm, backend; kwargs...)

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
