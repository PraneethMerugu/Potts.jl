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
_validate_declaration(::LocalConnectivity, context::_ValidationContext) = ()

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

function _fragment_exportable_identities(fragment::ModelFragment)
    direct = Tuple(semantic_identity(value) for value in fragment.declarations
        if !(value isa ModelFragment))
    nested = Tuple(identity for value in fragment.declarations
        if value isa ModelFragment for identity in
            Tuple(semantic_identity(exported) for exported in value.exports))
    return (direct..., nested...)
end

function _fragment_provider(declarations::Tuple, identity::SemanticName)
    index = findfirst(value -> semantic_identity(value) == identity, declarations)
    return index === nothing ? nothing : declarations[index]
end

function _fragment_export_contracts!(contracts::Dict{SemanticName, FragmentPortContract},
        fragment::ModelFragment)
    for declaration in _scoped_fragment_declarations(fragment)
        declaration isa ModelFragment || continue
        _fragment_export_contracts!(contracts, declaration)
    end
    for exported in fragment.exports
        contracts[semantic_identity(exported)] = exported.contract
    end
    return contracts
end

_fragment_export_contracts!(contracts, ::Any) = contracts

function _fragment_diagnostics(fragment::ModelFragment, declared::Tuple,
        declarations::Tuple,
        export_contracts::Dict{SemanticName, FragmentPortContract})
    diagnostics = ()
    exportable = _fragment_exportable_identities(fragment)
    for exported in fragment.exports
        identity = semantic_identity(exported)
        identity in exportable || (diagnostics = (diagnostics..., Diagnostic(
            :error, :unknown_fragment_export,
            "fragment exports must name a direct declaration or a nested-fragment export";
            identity = fragment.name, related = (exported.name, identity),
            fragment = fragment.name,
            correction = "remove the export or export the declaration from the nested fragment"),))
    end
    for requirement in fragment.requirements
        reference = requirement.reference
        identity = semantic_identity(requirement)
        if !requirement.satisfied || reference isa AbstractFragmentRole ||
                reference === nothing
            diagnostics = (diagnostics..., Diagnostic(
                :error, :unresolved_fragment_role,
                "fragment has an unbound typed requirement";
                identity = fragment.name,
                related = (requirement.name, requirement.contract),
                fragment = fragment.name,
                correction = "bind the role explicitly before constructing a problem"))
        elseif identity ∉ declared
            diagnostics = (diagnostics..., Diagnostic(
                :error, :unsatisfied_fragment_requirement,
                "fragment requirement is not provided by the composed model";
                identity = fragment.name, related = (requirement.name, identity),
                fragment = fragment.name,
                correction = "compose a provider for the required identity"))
        else
            provider = _fragment_provider(declarations, identity)
            provider_contract = get(export_contracts, identity,
                provider === nothing ? requirement.contract :
                fragment_port_contract(provider))
            provider === nothing || _port_contract_accepts(requirement.contract,
                provider_contract) ||
                (diagnostics = (diagnostics..., Diagnostic(
                    :error, :fragment_requirement_contract_mismatch,
                    "fragment requirement provider does not satisfy its typed port contract";
                    identity = fragment.name,
                    related = (requirement.name, requirement.contract,
                        provider_contract),
                    fragment = fragment.name,
                    correction = "bind a provider with matching category, owner, schema, units, lifecycle, capabilities, and backends"),))
        end
    end
    any(value -> value isa CorePotts.MCSPlan, fragment.declarations) &&
        (diagnostics = (diagnostics..., Diagnostic(
            :error, :fragment_local_execution_plan,
            "fragments may export operations but cannot own an execution plan";
            identity = fragment.name, fragment = fragment.name,
            correction = "move the plan to the root model and reference fragment exports"),))
    for declaration in _scoped_fragment_declarations(fragment)
        declaration isa ModelFragment || continue
        diagnostics = (diagnostics...,
            _fragment_diagnostics(declaration, declared, declarations,
                export_contracts)...)
    end
    return diagnostics
end

_fragment_diagnostics(declaration, declared::Tuple, declarations::Tuple,
    export_contracts::Dict{SemanticName, FragmentPortContract}) = ()

function _fragment_public_private_identities(fragment::ModelFragment)
    exported = Set(semantic_identity(value) for value in fragment.exports)
    private = Set{SemanticName}()
    for declaration in fragment.declarations
        if declaration isa ModelFragment
            child_public, child_private =
                _fragment_public_private_identities(declaration)
            union!(private, child_private)
            for identity in child_public
                identity in exported || push!(private, identity)
            end
        else
            identity = semantic_identity(declaration)
            identity in exported || push!(private, identity)
        end
    end
    return exported, private
end

_fragment_public_private_identities(::Any) =
    (Set{SemanticName}(), Set{SemanticName}())

_authoring_scheduled_process(entry::CorePotts.ScheduledSystem) = entry.process
_authoring_scheduled_process(entry::CorePotts.ScheduledEvent) = entry.event
_authoring_scheduled_process(entry::CorePotts.ScheduledProcess) = entry.process
_authoring_scheduled_process(entry) = nothing

function _plan_reference_identities(plan::CorePotts.MCSPlan)
    references = SemanticName[]
    if plan.timeline === nothing
        for entry in plan.entries
            if entry isa CorePotts.PottsAttempts
                append!(references,
                    (semantic_identity(effect) for effect in entry.on_accept))
            elseif entry isa CorePotts.CoupledPhase
                append!(references, (semantic_identity(
                    CorePotts.invocation_process(invocation))
                    for invocation in entry.invocations))
            end
        end
    else
        for entry in plan.timeline.entries
            process = _authoring_scheduled_process(entry)
            process === nothing || push!(references, semantic_identity(process))
        end
    end
    return Tuple(references)
end

function _root_plan_diagnostics(model::PottsModel, declarations::Tuple,
        components::Tuple)
    plans = Tuple(value for value in components if value isa CorePotts.MCSPlan)
    diagnostics = ()
    length(plans) <= 1 || (diagnostics = (diagnostics..., Diagnostic(
        :error, :multiple_root_execution_plans,
        "a composed model may contain at most one root MCSPlan";
        related = (length(plans),),
        correction = "merge all explicit stages into one globally ordered root plan"),))
    isempty(plans) && return diagnostics
    length(plans) == 1 || return diagnostics

    public = Set{SemanticName}()
    private = Set{SemanticName}()
    for declaration in model.declarations
        visible, hidden = _fragment_public_private_identities(declaration)
        union!(public, visible)
        union!(private, hidden)
    end
    declared = Set(semantic_identity(value) for value in declarations)
    for reference in _plan_reference_identities(only(plans))
        if reference in private && !(reference in public)
            diagnostics = (diagnostics..., Diagnostic(
                :error, :private_fragment_reference,
                "the root plan references a fragment-private operation";
                identity = reference,
                correction = "name and export the operation from its fragment before scheduling it"))
        elseif !(reference in declared)
            diagnostics = (diagnostics..., Diagnostic(
                :error, :unresolved_plan_reference,
                "the root plan references an operation absent from the canonical model";
                identity = reference,
                correction = "compose the provider fragment and reference one of its named exports"))
        end
    end
    return diagnostics
end

function _composition_diagnostics(model::PottsModel, declarations::Tuple,
        components::Tuple)
    diagnostics = ()
    declared = Tuple(semantic_identity(value) for value in declarations)
    export_contracts = Dict{SemanticName, FragmentPortContract}()
    for declaration in model.declarations
        _fragment_export_contracts!(export_contracts, declaration)
    end
    for declaration in model.declarations
        diagnostics = (diagnostics...,
            _fragment_diagnostics(declaration, declared, declarations,
                export_contracts)...)
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
    diagnostics = (diagnostics...,
        _root_plan_diagnostics(model, declarations, components)...)
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
