"""
The semantic contract of one fragment port.

Port contracts are host-side authoring data. They never become runtime storage and are erased
after fragment validation and canonical lowering.
"""
struct FragmentPortContract{S, U, L, C, B <: Tuple}
    category::Symbol
    owner::Symbol
    schema::S
    units::U
    operation::Symbol
    lifecycle::L
    capabilities::C
    backends::B
end

function FragmentPortContract(; category::Symbol, owner::Symbol = :any,
        schema = nothing, units = nothing, operation::Symbol = :reference,
        lifecycle = (), capabilities = CorePotts.ScientificCapabilities(),
        backends = capabilities.portable ? (:cpu, :metal, :rocm) : (:cpu,))
    isempty(String(category)) && throw(ArgumentError(
        "fragment port category must not be empty"))
    isempty(String(owner)) && throw(ArgumentError(
        "fragment port owner must not be empty"))
    operation in (:reference, :read, :write, :readwrite, :invoke) ||
        throw(ArgumentError(
            "fragment port operation must be reference, read, write, readwrite, or invoke"))
    normalized_backends = Tuple(Symbol(value) for value in backends)
    all(value -> value in (:cpu, :metal, :rocm), normalized_backends) ||
        throw(ArgumentError(
            "fragment port backends must be selected from cpu, metal, and rocm"))
    length(unique(normalized_backends)) == length(normalized_backends) ||
        throw(ArgumentError("fragment port backends must be unique"))
    return FragmentPortContract(category, owner, schema, units, operation,
        Tuple(lifecycle), capabilities,
        Tuple(sort!(collect(normalized_backends); by = String)))
end

"""One named typed input contract of a `ModelFragment`."""
struct FragmentRequirement{R, C <: FragmentPortContract}
    name::Symbol
    reference::R
    contract::C
    satisfied::Bool
end

"""One named immutable public reference of a `ModelFragment`."""
struct FragmentExport{V, C <: FragmentPortContract}
    name::Symbol
    value::V
    contract::C
end

_fragment_owner(::CellType) = :cell
_fragment_owner(::Medium) = :medium
_fragment_owner(::CellProperty) = :cell
_fragment_owner(::CellParameter) = :cell
_fragment_owner(::ModelParameter) = :global
_fragment_owner(::Union{PrescribedField}) = :field
_fragment_owner(::CorePotts.SiteProperty) = :site
_fragment_owner(::CorePotts.SiteDynamics) = :site
_fragment_owner(::CorePotts.AcceptedCopyUpdate) = :site
_fragment_owner(::CorePotts.CellHistory) = :cell
_fragment_owner(::CorePotts.HistorySample) = :cell
_fragment_owner(::CorePotts.RelationshipSet) = :relationship
_fragment_owner(::CorePotts.RelationshipDynamics) = :relationship
_fragment_owner(::CorePotts.CellDynamics) = :cell
_fragment_owner(::CorePotts.FieldDynamics) = :field
_fragment_owner(::CorePotts.FieldExchange) = :field
_fragment_owner(::CorePotts.PhaseObservation) = :observation
function _fragment_owner(value)
    return try
        _is_field_declaration(value) ? :field : :any
    catch
        :any
    end
end

_fragment_category(::CellRole) = :cell_type
_fragment_category(::FieldRole) = :field
_fragment_category(::CellType) = :cell_type
_fragment_category(::Medium) = :medium
_fragment_category(::CellProperty) = :state
_fragment_category(::CellParameter) = :parameter
_fragment_category(::ModelParameter) = :parameter
_fragment_category(::PrescribedField) = :field
function _fragment_category(value)
    field = try
        _is_field_declaration(value)
    catch
        false
    end
    field && return :field
    identity = try
        CorePotts.component_identity(
            value isa NamedCoreComponent ? value.component : value)
    catch
        return :declaration
    end
    return identity.category
end

function _fragment_capabilities(value)
    candidate = value isa NamedCoreComponent ? value.component : value
    return try
        CorePotts.capabilities(candidate)
    catch
        CorePotts.ScientificCapabilities()
    end
end

_fragment_operation(value) = try
    CorePotts.process_reads(value isa NamedCoreComponent ? value.component : value)
    :invoke
catch
    :reference
end

function FragmentPortContract(value; category::Symbol = _fragment_category(value),
        owner::Symbol = _fragment_owner(value), schema = nothing, units = nothing,
        operation::Symbol = _fragment_operation(value), lifecycle = (),
        capabilities = _fragment_capabilities(value),
        backends = capabilities.portable ? (:cpu, :metal, :rocm) : (:cpu,))
    return FragmentPortContract(; category, owner, schema, units, operation,
        lifecycle, capabilities, backends)
end

"""
Return the inferred fragment-port contract for a declaration or operation.

Third-party declaration families may extend this host-side protocol to publish richer owner,
schema, unit, lifecycle, capability, or backend requirements.
"""
fragment_port_contract(value) = FragmentPortContract(value)

function FragmentRequirement(reference = nothing; category::Symbol = :any,
        owner::Symbol = :any, schema = nothing, units = nothing,
        operation::Symbol = :reference, lifecycle = (),
        capabilities = reference === nothing ? CorePotts.ScientificCapabilities() :
            _fragment_capabilities(reference),
        backends = capabilities.portable ? (:cpu, :metal, :rocm) : (:cpu,))
    contract = reference === nothing ?
        FragmentPortContract(; category, owner, schema, units, operation,
            lifecycle, capabilities, backends) :
        FragmentPortContract(reference;
            category = category === :any ? _fragment_category(reference) : category,
            owner = owner === :any ? _fragment_owner(reference) : owner,
            schema, units, operation, lifecycle, capabilities, backends)
    satisfied = reference !== nothing && !(reference isa AbstractFragmentRole)
    return FragmentRequirement(:unnamed, reference, contract, satisfied)
end

function FragmentExport(value; category::Symbol = _fragment_category(value),
        owner::Symbol = _fragment_owner(value), schema = nothing, units = nothing,
        operation::Symbol = _fragment_operation(value), lifecycle = (),
        capabilities = _fragment_capabilities(value),
        backends = capabilities.portable ? (:cpu, :metal, :rocm) : (:cpu,))
    return FragmentExport(:unnamed, value,
        FragmentPortContract(value; category, owner, schema, units, operation,
            lifecycle, capabilities, backends))
end

semantic_identity(requirement::FragmentRequirement) =
    requirement.reference isa SemanticName ? requirement.reference :
    requirement.reference === nothing ? SemanticName(requirement.name) :
    semantic_identity(requirement.reference)
semantic_identity(exported::FragmentExport) = semantic_identity(exported.value)

function _named_fragment_values(values, constructor)
    if values isa NamedTuple
        return Tuple(constructor(name, getproperty(values, name))
            for name in propertynames(values))
    end
    values isa Tuple || throw(ArgumentError(
        "fragment requirements and exports must be tuples or named tuples"))
    return Tuple(constructor(semantic_identity(value).name, value) for value in values)
end

function _named_requirement(name::Symbol, value)
    requirement = if value isa FragmentRequirement
        value
    elseif value isa AbstractFragmentRole
        FragmentRequirement(value;
            category = _fragment_category(value),
            owner = value isa CellRole ? :cell : :field)
    else
        FragmentRequirement(:unnamed, value,
            fragment_port_contract(value), true)
    end
    return FragmentRequirement(name, requirement.reference, requirement.contract,
        requirement.satisfied)
end

function _named_export(name::Symbol, value)
    exported = value isa FragmentExport ? value :
        FragmentExport(:unnamed, value, fragment_port_contract(value))
    return FragmentExport(name, exported.value, exported.contract)
end

"""An immutable reusable bundle of declarations with a lexical namespace."""
struct ModelFragment
    name::SemanticName
    declarations::Tuple
    requirements::Tuple
    exports::Tuple
end

function ModelFragment(name::Symbol, declarations...; namespace::Namespace = Namespace(),
        requires = (), requirements = nothing, exports = ())
    requirements === nothing || isempty(requires) || throw(ArgumentError(
        "use either `requires` or `requirements`, not both"))
    requested = requirements === nothing ? requires : requirements
    normalized_requirements = _named_fragment_values(requested, _named_requirement)
    normalized_exports = _named_fragment_values(exports, _named_export)
    requirement_names = Tuple(value.name for value in normalized_requirements)
    export_names = Tuple(value.name for value in normalized_exports)
    isempty(intersect(Set(requirement_names), Set(export_names))) ||
        throw(ArgumentError(
            "fragment requirement and export names must be distinct"))
    reserved = Set(fieldnames(ModelFragment))
    isempty(intersect(reserved, Set((requirement_names..., export_names...)))) ||
        throw(ArgumentError(
            "fragment ports may not shadow ModelFragment structural fields"))
    length(unique(requirement_names)) == length(requirement_names) ||
        throw(ArgumentError("fragment requirement names must be unique"))
    length(unique(export_names)) == length(export_names) ||
        throw(ArgumentError("fragment export names must be unique"))
    requirement_identities = Tuple(semantic_identity(value)
        for value in normalized_requirements)
    length(unique(requirement_identities)) == length(requirement_identities) ||
        throw(ArgumentError("fragment requirements must be unique"))
    export_identities = Tuple(semantic_identity(value) for value in normalized_exports)
    length(unique(export_identities)) == length(export_identities) ||
        throw(ArgumentError("fragment exports must be unique"))
    role_identities = Tuple(semantic_identity(value.reference)
        for value in normalized_requirements
        if value.reference isa AbstractFragmentRole)
    declaration_identities = Tuple(semantic_identity(value) for value in declarations)
    isempty(intersect(Set(role_identities), Set(declaration_identities))) ||
        throw(ArgumentError(
            "fragment role identities must be distinct from direct declaration identities"))
    return ModelFragment(SemanticName(name; namespace), Tuple(declarations),
        normalized_requirements, normalized_exports)
end

semantic_identity(fragment::ModelFragment) = fragment.name

function Base.getproperty(fragment::ModelFragment, name::Symbol)
    name in fieldnames(ModelFragment) && return getfield(fragment, name)
    exported = findfirst(value -> value.name === name, getfield(fragment, :exports))
    exported === nothing || return getfield(fragment, :exports)[exported].value
    requirement = findfirst(value -> value.name === name,
        getfield(fragment, :requirements))
    requirement === nothing || return getfield(fragment, :requirements)[requirement]
    throw(ArgumentError(
        "fragment `$(_identity_text(getfield(fragment, :name)))` has no public port `$name`"))
end

function Base.propertynames(fragment::ModelFragment, private::Bool = false)
    public = (Tuple(value.name for value in getfield(fragment, :requirements))...,
        Tuple(value.name for value in getfield(fragment, :exports))...)
    return (fieldnames(ModelFragment)..., public...)
end

_role_accepts(::CellRole, value) = value isa CellType
_role_accepts(::FieldRole, value) = _is_field_declaration(value)
_role_expected(::CellRole) = "CellType"
_role_expected(::FieldRole) = "Field or PrescribedField"

"""
    bind(fragment, role => value...)

Return an immutable fragment with the supplied typed requirements substituted. Partial binding is
allowed for inspection; composing a fragment with unresolved roles produces structured validation
diagnostics and cannot construct a problem.
"""
function bind(fragment::ModelFragment, pairs::Pair...)
    requirements = fragment.requirements
    supplied = Tuple(first(pair) for pair in pairs)
    all(value -> value isa Union{AbstractFragmentRole, FragmentRequirement},
        supplied) || throw(ArgumentError(
        "fragment bindings must use a typed role or FragmentRequirement key"))
    length(unique(supplied)) == length(supplied) || throw(ArgumentError(
        "each fragment requirement may be bound at most once"))
    function matching_requirement(key)
        return findfirst(requirements) do requirement
            key isa FragmentRequirement ? key == requirement :
            requirement.reference == key
        end
    end
    matches = Tuple(matching_requirement(key) for key in supplied)
    all(!isnothing, matches) || throw(ArgumentError(
        "a binding key is not a requirement of this fragment"))
    for (pair, index) in zip(pairs, matches)
        requirement = requirements[index]
        value = last(pair)
        reference = requirement.reference
        reference isa AbstractFragmentRole &&
            !_role_accepts(reference, value) && throw(ArgumentError(
                "$(reference) requires $(_role_expected(reference)), not $(typeof(value))"))
        _port_contract_accepts(requirement.contract,
            fragment_port_contract(value)) || throw(ArgumentError(
                "binding for fragment requirement `$(requirement.name)` does not satisfy " *
                "its typed port contract"))
    end
    mapping = Tuple(semantic_identity(requirements[index]) =>
        semantic_identity(last(pair)) for (pair, index) in zip(pairs, matches))
    declarations = Tuple(_scope_declaration(declaration, fragment, mapping)
        for declaration in fragment.declarations)
    matched = Set(matches)
    remaining = Tuple(requirement for (index, requirement) in enumerate(requirements)
        if index ∉ matched)
    exports = Tuple(FragmentExport(exported.name,
        _scope_declaration(exported.value, fragment, mapping), exported.contract)
        for exported in fragment.exports)
    return ModelFragment(fragment.name, declarations, remaining, exports)
end

function _port_contract_accepts(required::FragmentPortContract,
        actual::FragmentPortContract)
    (required.category === :any || required.category === actual.category) || return false
    (required.owner === :any || required.owner === actual.owner) || return false
    (required.schema === nothing || required.schema == actual.schema) || return false
    (required.units === nothing || required.units == actual.units) || return false
    (required.operation === :reference ||
        required.operation === actual.operation) || return false
    all(value -> value in actual.lifecycle, required.lifecycle) || return false
    all(value -> value in actual.capabilities.dimensions,
        required.capabilities.dimensions) || return false
    (!required.capabilities.portable || actual.capabilities.portable) || return false
    all(value -> value in actual.backends, required.backends) || return false
    return true
end

function _prepend_namespace(prefix::Namespace, identity::SemanticName)
    return SemanticName(Namespace((prefix.parts..., identity.namespace.parts...)), identity.name)
end

function _fragment_prefix(fragment::ModelFragment)
    return Namespace((fragment.name.namespace.parts..., fragment.name.name))
end

_is_fragment_export(fragment::ModelFragment, identity::SemanticName) =
    any(exported -> semantic_identity(exported) == identity, fragment.exports)

function _scoped_identity(fragment::ModelFragment, identity::SemanticName)
    _is_fragment_export(fragment, identity) && return identity
    return _prepend_namespace(_fragment_prefix(fragment), identity)
end

function _identity_mapping(fragment::ModelFragment)
    return Tuple(semantic_identity(declaration) =>
        _scoped_identity(fragment, semantic_identity(declaration))
        for declaration in fragment.declarations)
end

function _mapped_identity(mapping::Tuple, identity::SemanticName)
    entry = findfirst(pair -> first(pair) == identity, mapping)
    return entry === nothing ? identity : last(mapping[entry])
end

function _scope_biological(value::CellType, mapping::Tuple)
    return CellType(_mapped_identity(mapping, value.identity))
end
function _scope_biological(value::Medium, mapping::Tuple)
    return Medium(_mapped_identity(mapping, value.identity))
end

_scope_declaration(value::CellType, fragment::ModelFragment, mapping) =
    CellType(_mapped_identity(mapping, value.identity))
_scope_declaration(value::Medium, fragment::ModelFragment, mapping) =
    Medium(_mapped_identity(mapping, value.identity))

function _scope_volume_bindings(bindings::BindingTable{CellType, VolumeParameters{T}},
        mapping::Tuple) where {T}
    entries = Tuple(Binding{CellType, VolumeParameters{T}}(
        _scope_biological(entry.key, mapping), entry.value) for entry in bindings)
    return BindingTable{CellType, VolumeParameters{T}}(entries)
end

function _scope_declaration(component::VolumeConstraint{T},
        fragment::ModelFragment, mapping) where {T}
    return VolumeConstraint{T}(_mapped_identity(mapping, component.name),
        _scope_volume_bindings(component.bindings, mapping))
end

function _scope_declaration(component::FluctuatingVolumeConstraint{T, N, D},
        fragment::ModelFragment, mapping) where {T, N, D}
    return FluctuatingVolumeConstraint{T, N, D}(
        _mapped_identity(mapping, component.name),
        _scope_volume_bindings(component.bindings, mapping), component.eta,
        component.noise, component.initialization, component.division)
end

function _scope_elongation_bindings(
        bindings::BindingTable{CellType, ElongationParameters{T}},
        mapping::Tuple) where {T}
    entries = Tuple(Binding{CellType, ElongationParameters{T}}(
        _scope_biological(entry.key, mapping), entry.value) for entry in bindings)
    return BindingTable{CellType, ElongationParameters{T}}(entries)
end

function _scope_declaration(component::Elongation{T, D},
        fragment::ModelFragment, mapping) where {T, D}
    return Elongation{T, D}(_mapped_identity(mapping, component.name),
        _scope_elongation_bindings(component.bindings, mapping),
        component.target_division)
end

function _scope_boundary_bindings(bindings::BindingTable{
        CellType, BoundaryParameters{Q, T}}, mapping::Tuple) where {Q, T}
    entries = Tuple(Binding{CellType, BoundaryParameters{Q, T}}(
        _scope_biological(entry.key, mapping), entry.value) for entry in bindings)
    return BindingTable{CellType, BoundaryParameters{Q, T}}(entries)
end

function _scope_declaration(component::BoundaryConstraint{Q, T, M},
        fragment::ModelFragment, mapping) where {Q, T, M}
    return BoundaryConstraint{Q, T, M}(_mapped_identity(mapping, component.name),
        _scope_boundary_bindings(component.bindings, mapping), component.metric)
end

function _scope_declaration(component::FluctuatingBoundaryConstraint{Q, T, N, M, TD, D},
        fragment::ModelFragment, mapping) where {Q, T, N, M, TD, D}
    return FluctuatingBoundaryConstraint{Q, T, N, M, TD, D}(
        _mapped_identity(mapping, component.name),
        _scope_boundary_bindings(component.bindings, mapping), component.eta,
        component.noise, component.initialization, component.metric,
        component.target_division, component.division)
end

function _scope_declaration(component::PreserveConnectivity,
        fragment::ModelFragment, mapping)
    return PreserveConnectivity(_mapped_identity(mapping, component.name))
end

function _scope_declaration(component::LocalConnectivity,
        fragment::ModelFragment, mapping)
    return LocalConnectivity(_mapped_identity(mapping, component.name))
end

function _scope_declaration(component::Adhesion{T},
        fragment::ModelFragment, mapping) where {T}
    entries = Tuple(Binding{PairIdentity, T}(
        PairIdentity(_scope_biological(entry.key.left, mapping),
            _scope_biological(entry.key.right, mapping);
            symmetric = component.law.symmetric), entry.value)
        for entry in component.law.values)
    name = _mapped_identity(mapping, component.name)
    law = PairwiseLaw{T}(name, BindingTable{PairIdentity, T}(entries),
        component.law.symmetric, component.law.default)
    return Adhesion{T}(name, law)
end

function _scope_declaration(field::PrescribedField{N, T, V, O, S, B, I},
        fragment::ModelFragment, mapping) where {N, T, V, O, S, B, I}
    return PrescribedField{N, T, V, O, S, B, I}(
        _mapped_identity(mapping, field.name), field.values, field.origin, field.spacing,
        field.boundaries, field.interpolation, field.semantic_time,
        field.synchronization_epoch)
end

function _scope_declaration(component::Chemotaxis{T, R, M},
        fragment::ModelFragment, mapping) where {T, R, M}
    entries = Tuple(Binding{CellType, T}(
        _scope_biological(entry.key, mapping), entry.value)
        for entry in component.sensitivity)
    return Chemotaxis{T, R, M}(
        _mapped_identity(mapping, component.name),
        _mapped_identity(mapping, component.field),
        component.dimensions,
        BindingTable{CellType, T}(entries), component.response, component.mode)
end

function _scope_declaration(rule::PropertyUpdate{T, S, G},
        fragment::ModelFragment, mapping) where {T, S, G}
    return PropertyUpdate{T, S, G}(
        _mapped_identity(mapping, rule.name), _mapped_identity(mapping, rule.source),
        rule.role, Tuple(_scope_biological(value, mapping) for value in rule.cell_types),
        rule.amount, rule.schedule, rule.trigger)
end

function _scope_declaration(rule::Transition{S, G},
        fragment::ModelFragment, mapping) where {S, G}
    return Transition{S, G}(_mapped_identity(mapping, rule.name),
        Tuple(_scope_biological(value, mapping) for value in rule.cell_types),
        _scope_biological(rule.destination, mapping), rule.schedule, rule.trigger,
        rule.priority)
end

function _scope_declaration(rule::Division{S, G, D},
        fragment::ModelFragment, mapping) where {S, G, D}
    return Division{S, G, D}(_mapped_identity(mapping, rule.name),
        Tuple(_scope_biological(value, mapping) for value in rule.cell_types),
        rule.geometry, rule.schedule, rule.trigger, rule.priority)
end

function _scope_declaration(rule::ShrinkDeath{T, S, G},
        fragment::ModelFragment, mapping) where {T, S, G}
    return ShrinkDeath{T, S, G}(_mapped_identity(mapping, rule.name),
        _mapped_identity(mapping, rule.source),
        Tuple(_scope_biological(value, mapping) for value in rule.cell_types),
        rule.decrement, rule.schedule, rule.trigger, rule.priority)
end

function _scope_declaration(rule::ImmediateDeath{S, G},
        fragment::ModelFragment, mapping) where {S, G}
    return ImmediateDeath{S, G}(_mapped_identity(mapping, rule.name),
        Tuple(_scope_biological(value, mapping) for value in rule.cell_types),
        _scope_biological(rule.medium, mapping), rule.schedule, rule.trigger,
        rule.priority)
end


function _scope_declaration(property::CellProperty{T, I, D, X, R},
        fragment::ModelFragment, mapping) where {T, I, D, X, R}
    return CellProperty{T, I, D, X, R}(
        _mapped_identity(mapping, property.name),
        Tuple(_scope_biological(value, mapping) for value in property.cell_types),
        property.initial, property.invariant, property.mutability, property.division,
        property.transition, property.retirement, property.visibility,
        property.persistence, property.optionality)
end

function _scope_declaration(component::NamedCoreComponent,
        fragment::ModelFragment, mapping)
    return NamedCoreComponent(_mapped_identity(mapping, component.name), component.component)
end

CorePotts.process_reads(component::NamedCoreComponent) =
    CorePotts.process_reads(component.component)
CorePotts.process_writes(component::NamedCoreComponent) =
    CorePotts.process_writes(component.component)

function _scope_declaration(child::ModelFragment, fragment::ModelFragment, mapping)
    name = _mapped_identity(mapping, child.name)
    renamed_child = ModelFragment(name, child.declarations,
        child.requirements, child.exports)
    child_exports = Tuple(semantic_identity(value) for value in child.exports)
    parent_exports = Set(semantic_identity(value) for value in fragment.exports)
    export_mapping = Tuple(identity => (identity in parent_exports ? identity :
        _prepend_namespace(_fragment_prefix(renamed_child), identity))
        for identity in child_exports)
    nested_mapping = (mapping..., export_mapping...)
    requirements = Tuple(FragmentRequirement(value.name,
        value.reference isa AbstractFragmentRole || value.reference === nothing ?
            value.reference : _mapped_identity(nested_mapping, semantic_identity(value)),
        value.contract, value.satisfied) for value in child.requirements)
    exports = Tuple(FragmentExport(value.name,
        _scope_declaration(value.value, fragment, nested_mapping), value.contract)
        for value in child.exports)
    declarations = Tuple(_scope_declaration(value, fragment, nested_mapping)
        for value in child.declarations)
    return ModelFragment(name, declarations, requirements, exports)
end

function _scope_declaration(component, fragment::ModelFragment, mapping)
    original = semantic_identity(component)
    scoped = _mapped_identity(mapping, original)
    return scoped == original ? component : NamedCoreComponent(scoped, component)
end

function _scoped_fragment_declarations(fragment::ModelFragment)
    mapping = _identity_mapping(fragment)
    return Tuple(_scope_declaration(declaration, fragment, mapping)
        for declaration in fragment.declarations)
end

"""Persistent Julia-native Level 2 biological model."""
struct PottsModel{N <: CorePotts.NumericalPolicy}
    declarations::Tuple
    numerics::N
end

function PottsModel(declarations...;
        numerics::CorePotts.NumericalPolicy = CorePotts.NumericalPolicy(Float32))
    return PottsModel(Tuple(declarations), numerics)
end

Base.length(model::PottsModel) = length(model.declarations)
Base.isempty(model::PottsModel) = isempty(model.declarations)
Base.iterate(model::PottsModel, state...) = iterate(model.declarations, state...)

function Base.show(io::IO, model::PottsModel)
    print(io, "PottsToolkit.PottsModel(", length(model.declarations),
        " declarations; real=", CorePotts.real_type(model.numerics), ")")
end

function Base.show(io::IO, mime::MIME"text/plain", model::PottsModel)
    diagnostics = validate(model)
    if isvalid(diagnostics)
        return show(io, mime, explain(model))
    end
    println(io, "PottsToolkit model (invalid)")
    println(io, "  real type:    ", CorePotts.real_type(model.numerics))
    println(io, "  declarations: ", length(model.declarations))
    limit = min(length(model.declarations), 20)
    for index in 1:limit
        declaration = model.declarations[index]
        identity = try semantic_identity(declaration) catch; nothing end
        println(io, "    - ", identity === nothing ? nameof(typeof(declaration)) :
            _identity_text(identity), " :: ", nameof(typeof(declaration)))
    end
    length(model.declarations) > limit && println(io, "    … ",
        length(model.declarations) - limit, " more")
    println(io, "  diagnostics:")
    diagnostic_limit = min(length(diagnostics), 20)
    for index in 1:diagnostic_limit
        item = diagnostics.diagnostics[index]
        println(io, "    - [", item.code, "] ", item.message)
    end
    length(diagnostics) > diagnostic_limit && println(io, "    … ",
        length(diagnostics) - diagnostic_limit, " more")
end

function _declaration_identity(declaration)
    return semantic_identity(declaration)
end

"""Return a new model with one declaration appended; the original remains unchanged."""
function add(model::PottsModel, declaration)
    return PottsModel((model.declarations..., declaration), model.numerics)
end

"""Return a new model without the declaration of `identity`."""
function remove(model::PottsModel, identity::SemanticName)
    kept = Tuple(declaration for declaration in model.declarations
        if _declaration_identity(declaration) != identity)
    length(kept) == length(model.declarations) && throw(KeyError(identity))
    return PottsModel(kept, model.numerics)
end

remove(model::PottsModel, declaration) = remove(model, _declaration_identity(declaration))

"""Replace exactly one declaration by semantic identity."""
function replace(model::PottsModel, identity::SemanticName, replacement)
    count = 0
    declarations = map(model.declarations) do declaration
        if _declaration_identity(declaration) == identity
            count += 1
            replacement
        else
            declaration
        end
    end
    count == 1 || throw(ArgumentError(
        count == 0 ? "no declaration matches $identity" :
        "replacement identity $identity is ambiguous"))
    return PottsModel(Tuple(declarations), model.numerics)
end

replace(model::PottsModel, pair::Pair) =
    replace(model, _declaration_identity(first(pair)), last(pair))

"""Compose declarations or fragments without assigning precedence to argument order."""
_compose_value(model::PottsModel, fragment::ModelFragment) =
    add(model, fragment)
_compose_value(model::PottsModel, value) = add(model, value)

function compose(model::PottsModel, values...)
    result = model
    for value in values
        result = _compose_value(result, value)
    end
    return result
end

function _declared_fragment_backends(value)
    contract = fragment_port_contract(value)
    return contract.backends
end

function _declared_fragment_backends(fragment::ModelFragment)
    nested = Tuple(backend for declaration in fragment.declarations
        for backend in _declared_fragment_backends(declaration))
    requirements = Tuple(backend for requirement in fragment.requirements
        for backend in requirement.contract.backends)
    exports = Tuple(backend for exported in fragment.exports
        for backend in exported.contract.backends)
    return (nested..., requirements..., exports...)
end

"""
Return the transitive backend requirements of the fully validated authoring graph.

This is a pre-launch requirement set, not a claim that each backend has qualified execution
evidence. Runtime preflight remains responsible for rejecting unsupported law/storage/backend
tuples before mutation.
"""
function required_backends(model::PottsModel)
    report = validate(model)
    isvalid(report) || throw(ModelValidationError(report))
    requested = Set{Symbol}()
    for declaration in model.declarations,
            backend in _declared_fragment_backends(declaration)
        push!(requested, backend)
    end
    order = Dict(:cpu => 1, :metal => 2, :rocm => 3)
    return Tuple(sort!(collect(requested); by = value -> order[value]))
end

function SciMLBase.remake(model::PottsModel;
        declarations = model.declarations, numerics = model.numerics)
    return PottsModel(Tuple(declarations), numerics)
end
