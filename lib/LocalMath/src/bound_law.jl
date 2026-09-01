# Private structural binding envelope for the stage-tuple program. It is
# deliberately not a second semantic representation: it retains the sole
# LocalLaw value and the sole validated descriptor/storage binding verbatim.

mutable struct _BoundLawSeal end
const _BOUND_LAW_SEAL = _BoundLawSeal()

struct _BoundLaw{W<:LocalLaw,B}
    law::W
    binding::B

    function _BoundLaw(
            seal::_BoundLawSeal, law::W, binding::B,
        ) where {W<:LocalLaw,B}
        seal === _BOUND_LAW_SEAL || throw(ArgumentError(
            "bound LocalLaw requires the package-owned construction seal"
        ))
        return new{W,B}(law, binding)
    end
end

struct _EmptyAllocation end

"""
    Allocate(initial)
    Allocate()

Cold request for `bind` to allocate scientific storage on an explicit backend.
Fields admit `undef`, one exact element value, or an exact source array.
Relations recursively copy array leaves. The zero-argument form requests the
exact empty storage of a produced `Collection`.
"""
struct Allocate{I}
    initial::I
end

Allocate() = Allocate(_EmptyAllocation())

"""
    Temporary()

Cold binding declaration for a compiler-private `Field`. The Field must be
totally produced before its first read on every execution. Its storage is
package-owned and intentionally unavailable through [`storage`](@ref).
"""
struct Temporary end

"""Cold, non-array declaration retained only until `plan` owns the backend."""
struct _TemporaryStorageRequest{B}
    backend::B
end

"""
    MutableRelationStorage(storage; generation, status=nothing,
                           validated_generations=nothing, slot=1)

Cold declaration for generation-qualified relation storage. When status
storage is omitted, `bind` allocates it on the explicitly supplied backend.
The declaration never survives into a `Plan`.
"""
struct MutableRelationStorage{S,G,T,V}
    storage::S
    generation::G
    status::T
    validated_generations::V
    slot::Int
end
function MutableRelationStorage(storage; generation, status = nothing,
        validated_generations = nothing, slot::Integer = 1)
    slot > 0 || throw(LocalMathValidationError(
        "a mutable relation slot must be positive";
        stage = :bind, contract = :relation_receipt_slot,
        expected = :positive, actual = slot))
    return MutableRelationStorage(storage, generation, status,
        validated_generations, Int(slot))
end

@kernel function _initialize_allocated_storage_kernel!(destination, value)
    index = @index(Global, Linear)
    index <= length(destination) && (@inbounds destination[index] = value)
end

function _allocate_array(backend, ::Type{T}, shape::Tuple) where {T}
    return KernelAbstractions.allocate(backend, T, shape)
end

function _initialize_allocated_storage!(backend, destination, value)
    isempty(destination) && return destination
    kernel = _initialize_allocated_storage_kernel!(backend)
    kernel(destination, value; ndrange = length(destination))
    KernelAbstractions.synchronize(backend)
    return destination
end

function _copy_allocated_array(backend, source::AbstractArray)
    destination = _allocate_array(backend, eltype(source), size(source))
    copyto!(destination, source)
    KernelAbstractions.synchronize(backend)
    return destination
end

function _copy_allocated_storage(backend, source::StructArrays.StructArray{T}) where {T}
    source_components = StructArrays.components(source)
    copied_values = map(value -> _copy_allocated_storage(backend, value),
        values(source_components))
    copied_components = source_components isa NamedTuple ?
        NamedTuple{keys(source_components)}(copied_values) : copied_values
    return StructArrays.StructArray{T}(copied_components)
end

_copy_allocated_storage(backend, source::AbstractArray) =
    _copy_allocated_array(backend, source)
function _copy_allocated_storage(backend, source::NamedTuple)
    copied = map(value -> _copy_allocated_storage(backend, value), values(source))
    return NamedTuple{keys(source)}(copied)
end
_copy_allocated_storage(backend, source::Tuple) =
    map(value -> _copy_allocated_storage(backend, value), source)
_copy_allocated_storage(backend, source) = source

function _materialize_nested_allocation(backend, declaration::Allocate)
    initial = declaration.initial
    initial isa Union{UndefInitializer,_EmptyAllocation} && throw(
        LocalMathValidationError(
            "a relation allocation requires concrete source storage";
            stage = :bind, contract = :relation_allocation_source,
            expected = :array_or_nested_array_storage, actual = initial,
        ))
    return _copy_allocated_storage(backend, initial)
end
function _materialize_nested_allocation(backend, declaration::NamedTuple)
    materialized = map(value -> _materialize_nested_allocation(backend, value),
        values(declaration))
    return NamedTuple{keys(declaration)}(materialized)
end
_materialize_nested_allocation(backend, declaration::Tuple) =
    map(value -> _materialize_nested_allocation(backend, value), declaration)
_materialize_nested_allocation(backend, declaration) = declaration

function _field_allocation(field::Field, request::Allocate, backend)
    initial = request.initial
    shape = size(field.space)
    T = eltype(field)
    if initial isa UndefInitializer
        return _allocate_array(backend, T, shape)
    elseif typeof(initial) === T
        storage = _allocate_array(backend, T, shape)
        return _initialize_allocated_storage!(backend, storage, initial)
    elseif initial isa StructArrays.StructArray
        eltype(initial) === T || throw(LocalMathValidationError(
            "an allocated Field source must have the exact element type";
            stage = :bind, contract = :field_allocation_element_type,
            expected = T, actual = eltype(initial),
        ))
        size(initial) == shape || throw(LocalMathValidationError(
            "an allocated Field source must have the exact Field shape";
            stage = :bind, contract = :field_allocation_shape,
            expected = shape, actual = size(initial),
        ))
        return _copy_allocated_storage(backend, initial)
    elseif initial isa AbstractArray
        eltype(initial) === T || throw(LocalMathValidationError(
            "an allocated Field source must have the exact element type";
            stage = :bind, contract = :field_allocation_element_type,
            expected = T, actual = eltype(initial),
        ))
        size(initial) == shape || throw(LocalMathValidationError(
            "an allocated Field source must have the exact Field shape";
            stage = :bind, contract = :field_allocation_shape,
            expected = shape, actual = size(initial),
        ))
        return _copy_allocated_array(backend, initial)
    end
    throw(LocalMathValidationError(
        "an allocated Field requires undef, one exact value, or an exact source array";
        stage = :bind, contract = :field_allocation_initialization,
        expected = (undef, T, :exact_source_array), actual = typeof(initial),
    ))
end

_same_descriptor(left, right) =
    semantic_identity(left) == semantic_identity(right) && left == right

function _field_used_at_stage_entry(stage::Stage, field::Field)
    any(values(stage.accesses)) do access
        access isa Access && _same_descriptor(access.field, field) ||
            access isa Access && access.ghost isa Field &&
                _same_descriptor(access.ghost, field)
    end && return true
    control = stage.control
    control.prefix isa _FieldPrefix &&
        _same_descriptor(control.prefix.field, field) && return true
    control.mask isa _MaskSelection &&
        _same_descriptor(control.mask.field, field) && return true
    control.gate isa _FieldGate &&
        _same_descriptor(control.gate.field, field) && return true
    for publication in stage.publications
        publication.law isa OrderedFold || continue
        for component in values(publication.law.state.components)
            _same_descriptor(component.target, field) && return true
            component.source isa Field &&
                _same_descriptor(component.source, field) && return true
        end
    end
    return false
end

function _unconditional_stage(stage::Stage)
    control = stage.control
    return control.prefix isa _NoPrefix && control.mask isa _NoMask &&
        control.subset isa _NoSubset && control.gate isa _NoGate
end

function _publication_initializes_field(
        stage::Stage, publication::Publication, field::Field,
    )
    law = publication.law
    law isa Unique && law.coverage isa TotalCoverage || return false
    _unconditional_stage(stage) || return false
    return any(publication.components) do component
        component isa FieldPublication || return false
        _same_descriptor(component.field, field) || return false
        component.relation.representation isa _IdentityRelation || return false
        domain(component.relation) == stage.source &&
            codomain(component.relation) == field.space
    end
end

function _field_publication_requires_initialization(
        stage::Stage, publication::Publication, field::Field,
    )
    any(publication.components) do component
        component isa FieldPublication &&
            _same_descriptor(component.field, field)
    end || return false
    return !_publication_initializes_field(stage, publication, field)
end

function _require_definite_field_initialization(work::LocalLaw, field::Field)
    initialized = false
    for (index, stage) in enumerate(work.stages)
        if !initialized && _field_used_at_stage_entry(stage, field)
            throw(LocalMathValidationError(
                "an uninitialized allocated Field is read before a proven total assignment";
                stage = :bind, contract = :field_definite_initialization,
                expected = :initialized_before_stage_entry,
                actual = (field = semantic_identity(field), stage = index),
                hint = "use Allocate(value) or Allocate(source)",
                origin = stage.origin,
            ))
        end
        for publication in stage.publications
            if !initialized && _field_publication_requires_initialization(
                    stage, publication, field)
                throw(LocalMathValidationError(
                    "an uninitialized allocated Field has publication semantics that preserve or require prior state";
                    stage = :bind, contract = :field_definite_initialization,
                    expected = :unconditional_total_identity_unique,
                    actual = (field = semantic_identity(field), stage = index,
                        law = typeof(publication.law)),
                    hint = "use Allocate(value) or Allocate(source)",
                    origin = publication.origin,
                ))
            end
            _publication_initializes_field(stage, publication, field) &&
                (initialized = true)
        end
    end
    return nothing
end

function _collect_allocation_schema(work::LocalLaw, collection::Collection)
    schemas = Any[]
    for stage in work.stages, publication in stage.publications
        publication.law isa Collect || continue
        any(publication.components) do component
            component isa CollectionPublication &&
                _same_descriptor(component.collection, collection)
        end || continue
        law = publication.law
        push!(schemas, (
            grouped = _is_grouped(law.groups),
            groups = Int(_compacted_group_count(law.groups)),
            persistent_source_positions =
                law.projection isa _PersistentSourcePosition,
            source_position_count =
                length(stage.source) * _publication_width(law),
        ))
    end
    isempty(schemas) && throw(LocalMathValidationError(
        "an allocated Collection requires a producing Collect publication";
        stage = :bind, contract = :collection_allocation_producer,
        expected = :collect_publication,
        actual = semantic_identity(collection),
    ))
    all(schema -> schema == first(schemas), schemas) || throw(
        LocalMathValidationError(
            "Collection producers require inconsistent physical storage";
            stage = :bind, contract = :collection_allocation_schema,
            expected = first(schemas), actual = Tuple(schemas),
        ))
    return first(schemas)
end

function _filled_int32_storage(backend, length::Int, value::Int32)
    storage = _allocate_array(backend, Int32, (length,))
    return _initialize_allocated_storage!(backend, storage, value)
end

function _filled_uint64_storage(backend, length::Int, value::UInt64)
    storage = _allocate_array(backend, UInt64, (length,))
    return _initialize_allocated_storage!(backend, storage, value)
end

_zeroed_int32_storage(backend, length::Int) =
    _filled_int32_storage(backend, length, Int32(0))

function _collection_allocation(
        work::LocalLaw, collection::Collection, request::Allocate, backend,
    )
    request.initial isa _EmptyAllocation || throw(LocalMathValidationError(
        "Collection allocation uses the zero-argument Allocate() form";
        stage = :bind, contract = :collection_allocation_initialization,
        expected = :empty_collection, actual = request.initial,
    ))
    schema = _collect_allocation_schema(work, collection)
    capacity = Int(collection.capacity)
    records = _allocate_compacted_records(backend, eltype(collection), capacity)
    count = _zeroed_int32_storage(backend, 1)
    segment_starts = schema.grouped ? (
        _filled_int32_storage(backend, schema.groups + 1, Int32(1))
    ) : nothing
    source_item = _zeroed_int32_storage(backend, capacity)
    source_lane = _zeroed_int32_storage(backend, capacity)
    source_position = schema.persistent_source_positions ?
        _zeroed_int32_storage(backend, schema.source_position_count) : nothing
    return CompactedStorage(_CONSTRUCTION_TOKEN, records, count,
        segment_starts, source_item, source_lane, source_position)
end

function _append_fold_state_requirements!(fields, law::OrderedFold)
    for component in values(law.state.components)
        _append_descriptor_once!(fields, component.target, :field)
        component.source isa Field &&
            _append_descriptor_once!(fields, component.source, :field)
    end
    return nothing
end

function _append_stage_requirements!(fields, relations, collections, stage::Stage)
    for access in values(stage.accesses)
        if access isa Access
            _append_descriptor_once!(fields, access.field, :field)
            _append_descriptor_once!(relations, access.relation, :relation)
            access.ghost === nothing ||
                _append_descriptor_once!(fields, access.ghost, :field)
        else
            _append_descriptor_once!(collections, access.collection, :collection)
        end
    end
    for publication in stage.publications
        for component in publication.components
            if component isa FieldPublication
                _append_descriptor_once!(fields, component.field, :field)
                _append_descriptor_once!(relations, component.relation, :relation)
            elseif component isa CollectionPublication
                _append_descriptor_once!(
                    collections, component.collection, :collection,
                )
            end
        end
        publication.law isa OrderedFold &&
            _append_fold_state_requirements!(fields, publication.law)
    end
    control = stage.control
    control.prefix isa _FieldPrefix &&
        _append_descriptor_once!(fields, control.prefix.field, :field)
    control.prefix isa _CollectionCount &&
        _append_descriptor_once!(collections, control.prefix.collection, :collection)
    control.mask isa _MaskSelection &&
        _append_descriptor_once!(fields, control.mask.field, :field)
    control.subset isa _SubsetSelection &&
        _append_descriptor_once!(relations, control.subset.relation, :relation)
    control.gate isa _FieldGate &&
        _append_descriptor_once!(fields, control.gate.field, :field)
    return nothing
end

"""Direct descriptor requirements in Stage first-scientific-encounter order."""
function _law_descriptor_requirements(law::LocalLaw)
    fields = Any[]
    relations = Any[]
    collections = Any[]
    for stage in law.stages
        _append_stage_requirements!(fields, relations, collections, stage)
    end
    return Tuple(fields), Tuple(relations), Tuple(collections)
end

"""Bind a program to cold structural declarations without deriving plan facts."""
function _bind_law(law::LocalLaw, binding::_StructuralBinding)
    return _BoundLaw(_BOUND_LAW_SEAL, law, binding)
end

function _declared_field_binding(entry::Pair)
    field, declaration = entry
    field isa Field || throw(LocalMathValidationError(
        "a field binding key must be a Field";
        stage = :bind, contract = :field_binding_descriptor,
        expected = Field, actual = typeof(field),
    ))
    if declaration isa _TemporaryStorageRequest
        return _FieldStorageBinding(field, declaration,
            _new_semantic_identity(), _TemporaryOwnership())
    elseif declaration isa NamedTuple && hasproperty(declaration, :storage)
        ownership = hasproperty(declaration, :ownership) ?
            declaration.ownership : :local
        return _field_storage_binding(field, declaration.storage; ownership)
    end
    return _field_storage_binding(field, declaration)
end

function _declared_relation_binding(entry::Pair)
    relation, declaration = entry
    relation isa Relation || throw(LocalMathValidationError(
        "a relation binding key must be a Relation";
        stage = :bind, contract = :relation_binding_descriptor,
        expected = Relation, actual = typeof(relation),
    ))
    if declaration isa MutableRelationStorage
        generation = _RelationContentGenerationRef(
            declaration.generation, declaration.slot)
        status = _RelationStatusRef(declaration.status,
            declaration.validated_generations, declaration.slot)
        return _relation_storage_binding(relation, declaration.storage;
            generation, status)
    end
    return _relation_storage_binding(relation, declaration)
end

function _normalize_relation_declaration(relation::Relation, declaration)
    relation.representation isa _FixedRelation && declaration isa AbstractArray &&
        return (; endpoints = declaration)
    return declaration
end

function _declared_collection_binding(entry::Pair)
    collection, storage = entry
    collection isa Collection || throw(LocalMathValidationError(
        "a collection binding key must be a Collection";
        stage = :bind, contract = :collection_binding_descriptor,
        expected = Collection, actual = typeof(collection),
    ))
    return _collection_storage_binding(collection, storage)
end

function _materialized_field_declaration(work, entry::Pair, backend)
    field, declaration = entry
    if declaration isa Temporary
        _require_definite_field_initialization(work, field)
        return field => _TemporaryStorageRequest(backend)
    end
    declaration isa Allocate || return entry
    declaration.initial isa UndefInitializer &&
        _require_definite_field_initialization(work, field)
    return field => _field_allocation(field, declaration, backend)
end

function _materialized_relation_declaration(entry::Pair, backend)
    relation, declaration = entry
    declaration = _normalize_relation_declaration(relation, declaration)
    if declaration isa MutableRelationStorage
        storage = _materialize_nested_allocation(backend, declaration.storage)
        generation = _materialize_nested_allocation(backend,
            declaration.generation)
        length(generation) >= declaration.slot || throw(
            LocalMathValidationError(
                "mutable relation generation storage does not contain its slot";
                stage = :bind, contract = :relation_receipt_slot,
                expected = declaration.slot, actual = length(generation)))
        status = declaration.status === nothing ?
            _zeroed_int32_storage(backend, length(generation)) :
            _materialize_nested_allocation(backend, declaration.status)
        validated = declaration.validated_generations === nothing ?
            _filled_uint64_storage(backend, length(generation), UInt64(0)) :
            _materialize_nested_allocation(
                backend, declaration.validated_generations)
        return relation => MutableRelationStorage(storage;
            generation, status, validated_generations = validated,
            slot = declaration.slot)
    end
    materialized = _normalize_relation_declaration(relation,
        _materialize_nested_allocation(backend, declaration))
    return relation => materialized
end

function _materialized_collection_declaration(work, entry::Pair, backend)
    collection, declaration = entry
    declaration isa Allocate || return entry
    return collection => _collection_allocation(
        work, collection, declaration, backend)
end

function _contains_allocation(declaration::Allocate)
    return true
end
_contains_allocation(::Temporary) = true
_contains_allocation(declaration::NamedTuple) =
    any(_contains_allocation, values(declaration))
_contains_allocation(declaration::Tuple) = any(_contains_allocation, declaration)
_contains_allocation(declaration::MutableRelationStorage) =
    declaration.status === nothing ||
    declaration.validated_generations === nothing ||
    _contains_allocation(declaration.storage) ||
    _contains_allocation(declaration.generation) ||
    _contains_allocation(declaration.status) ||
    _contains_allocation(declaration.validated_generations)
_contains_allocation(declaration) = false

function _descriptor_storage_expectation(field::Field)
    return (
        role = :field,
        element_type = eltype(field),
        shape = size(field.space),
    )
end

function _descriptor_storage_expectation(relation::Relation)
    representation = relation.representation
    base = (
        role = :relation,
        family = _relation_display_name(representation),
        domain_extent = size(domain(relation)),
        codomain_extent = size(codomain(relation)),
        degree = degree_bound(relation),
    )
    if representation isa _FixedRelation
        return merge(base, (
            endpoints = (
                minimum_lanes = degree_bound(relation),
                minimum_items = length(domain(relation)),
            ),
            counts = (
                required = false,
                minimum_items = length(domain(relation)),
            ),
        ))
    elseif representation isa _InverseRelation
        return merge(base, (
            accepted_layouts = (
                (:degrees, :incidents),
                (:offsets, :incidents),
            ),
        ))
    elseif representation isa _PackedRelation
        return merge(base, (
            required_keys = (:active, :endpoints, :offsets, :counts),
            capacity = representation.capacity,
        ))
    elseif representation isa _BoundaryRelation &&
            representation.policy isa GhostBoundary
        return merge(base, (required_keys = (:mapping,),))
    end
    return merge(base, (storage = :computed,))
end

_descriptor_storage_expectation(collection::Collection) = (
    role = :collection,
    element_type = eltype(collection),
    capacity = Int(collection.capacity),
)

function _stage_requirement_contains(stage::Stage, descriptor, role::Symbol)
    fields, relations, collections = Any[], Any[], Any[]
    _append_stage_requirements!(fields, relations, collections, stage)
    closed_fields, closed_relations = _required_descriptor_closure(
        Tuple(fields), Tuple(relations))
    values = role === :field ? closed_fields :
        role === :relation ? closed_relations : Tuple(collections)
    identity = semantic_identity(descriptor)
    return any(candidate -> semantic_identity(candidate) == identity, values)
end

function _first_descriptor_origin(law::LocalLaw, descriptor, role::Symbol)
    for stage in law.stages
        _stage_requirement_contains(stage, descriptor, role) &&
            return stage.origin
    end
    return _NO_SOURCE_ORIGIN
end

function _descriptor_use_sites(law::LocalLaw, descriptor, role::Symbol)
    identity = semantic_identity(descriptor)
    uses = Any[]
    for (stage_index, stage) in enumerate(law.stages)
        for (access_role, access) in pairs(stage.accesses)
            if role === :field && access isa Access &&
                    semantic_identity(access.field) == identity
                push!(uses, (stage = stage_index, role = access_role,
                    use = access.mode isa _RequiredAccess ?
                        :required_read : :sample_read,
                    origin = stage.origin))
            elseif role === :relation && access isa Access &&
                    semantic_identity(access.relation) == identity
                push!(uses, (stage = stage_index, role = access_role,
                    use = :read_relation,
                    degree = degree_bound(access.relation),
                    origin = stage.origin))
            elseif role === :collection && access isa CollectionAccess &&
                    semantic_identity(access.collection) == identity
                push!(uses, (stage = stage_index, role = access_role,
                    use = :collection_consumer, origin = stage.origin))
            end
        end
        for publication in stage.publications
            origin = _has_source_origin(publication.origin) ?
                publication.origin : stage.origin
            for component in publication.components
                port = _evaluator_value_name(component.role)
                if role === :field && component isa FieldPublication &&
                        semantic_identity(component.field) == identity
                    push!(uses, (stage = stage_index, role = port,
                        use = :publication_destination, origin))
                elseif role === :relation && component isa FieldPublication &&
                        semantic_identity(component.relation) == identity
                    push!(uses, (stage = stage_index, role = port,
                        use = :publication_relation,
                        degree = degree_bound(component.relation), origin))
                elseif role === :collection &&
                        component isa CollectionPublication &&
                        semantic_identity(component.collection) == identity
                    push!(uses, (stage = stage_index, role = port,
                        use = :collection_producer, origin))
                end
            end
        end
        control = stage.control
        controls = ((:prefix, control.prefix), (:mask, control.mask),
            (:subset, control.subset), (:gate, control.gate))
        for (control_role, control_value) in controls
            candidate = control_value isa _FieldPrefix ? control_value.field :
                control_value isa _MaskSelection ? control_value.field :
                control_value isa _FieldGate ? control_value.field :
                control_value isa _SubsetSelection ? control_value.relation :
                control_value isa _CollectionCount ? control_value.collection :
                nothing
            candidate === nothing || semantic_identity(candidate) != identity ||
                push!(uses, (stage = stage_index, role = control_role,
                    use = :control, origin = stage.origin))
        end
    end
    return Tuple(uses)
end

function _missing_binding_facts(
        law::LocalLaw, required::Tuple, entries::Tuple, role::Symbol,
    )
    supplied = map(entry -> semantic_identity(first(entry)), entries)
    return Tuple((
            role,
            descriptor,
            requirement = _descriptor_storage_expectation(descriptor),
            uses = _descriptor_use_sites(law, descriptor, role),
            origin = _first_descriptor_origin(law, descriptor, role),
        ) for descriptor in required
        if !(semantic_identity(descriptor) in supplied))
end

function _preflight_binding_coverage(
        law::LocalLaw,
        fields::Tuple,
        relations::Tuple,
        collections::Tuple,
        required_fields::Tuple,
        required_relations::Tuple,
        required_collections::Tuple,
    )
    missing = (
        _missing_binding_facts(
            law, required_fields, fields, :field)...,
        _missing_binding_facts(
            law, required_relations, relations, :relation)...,
        _missing_binding_facts(
            law, required_collections, collections, :collection)...,
    )
    isempty(missing) || throw(LocalMathValidationError(
        "scientific storage is missing for $(length(missing)) descriptor$(length(missing) == 1 ? "" : "s")";
        stage = :bind,
        contract = :binding_coverage,
        expected = missing,
        actual = (
            fields = map(entry -> first(entry), fields),
            relations = map(entry -> first(entry), relations),
            collections = map(entry -> first(entry), collections),
        ),
        hint = "bind every listed Field, stored Relation, and Collection exactly once",
    ))
    return nothing
end

"""
    bind(law, bindings::Pair...; backend=nothing)

Bind semantic descriptors to physical storage. Descriptor dispatch separates
Fields, stored Relations, and Collections. Storage-free Relations are derived
from the law and cannot be redundantly supplied. Supplying a backend permits
explicit [`Allocate`](@ref) declarations, which are completely materialized
before the ordinary structural binding is constructed. [`Temporary`](@ref)
remains storage-free through binding and becomes private scratch only once
`plan` owns the backend.
"""
function bind(law::LocalLaw, bindings::Pair...; backend = nothing)
    fields = Pair[]
    relations = Pair[]
    collections = Pair[]
    for entry in bindings
        descriptor = first(entry)
        if descriptor isa Field
            push!(fields, entry)
        elseif descriptor isa Relation
            _relation_requires_storage(descriptor.representation) || throw(
                LocalMathValidationError(
                    "storage-free Relations are derived and must not be bound";
                    stage = :bind, contract = :computed_relation_binding,
                    expected = :omitted, actual = descriptor))
            push!(relations, entry)
        elseif descriptor isa Collection
            push!(collections, entry)
        else
            throw(LocalMathValidationError(
                "a binding key must be a Field, stored Relation, or Collection";
                stage = :bind, contract = :binding_descriptor,
                expected = (Field, Relation, Collection),
                actual = typeof(descriptor)))
        end
    end
    required_fields, required_relations, required_collections =
        _law_descriptor_requirements(law)
    closed_fields, closed_relations = _required_descriptor_closure(
        required_fields, required_relations)
    stored_relations = Tuple(relation for relation in closed_relations
        if _relation_requires_storage(relation.representation))
    fields = Tuple(fields)
    caller_relations = Tuple(relations)
    collections = Tuple(collections)
    _preflight_binding_coverage(
        law, fields, caller_relations, collections,
        closed_fields, stored_relations, required_collections,
    )
    computed = Pair[relation => nothing for relation in closed_relations
        if !_relation_requires_storage(relation.representation)]
    relations = (caller_relations..., Tuple(computed)...)
    declarations = (fields..., relations..., collections...)
    if backend === nothing
        any(entry -> _contains_allocation(last(entry)), declarations) && throw(
            LocalMathValidationError(
                "package-owned storage declarations require an explicit binding backend";
                stage = :bind, contract = :allocation_backend,
                expected = :kernelabstractions_backend, actual = nothing,
            ))
        relations = map(relations) do entry
            relation = first(entry)
            declaration = _normalize_relation_declaration(
                relation, last(entry))
            if relation.representation isa _FixedRelation &&
                    declaration isa NamedTuple &&
                    hasproperty(declaration, :endpoints)
                inferred = _array_backend(declaration.endpoints)
                inferred isa KernelAbstractions.CPU ||
                    return _materialized_relation_declaration(
                        relation => declaration, inferred)
            end
            return relation => declaration
        end
    else
        fields = map(entry -> _materialized_field_declaration(
            law, entry, backend), fields)
        relations = map(entry -> _materialized_relation_declaration(
            entry, backend), relations)
        collections = map(entry -> _materialized_collection_declaration(
            law, entry, backend), collections)
    end
    binding = _StructuralBinding(
        map(_declared_field_binding, fields),
        map(_declared_relation_binding, relations),
        map(_declared_collection_binding, collections),
    )
    return _bind_law(law, binding)
end

_storage_binding(bound::_BoundLaw) = bound.binding
_storage_binding(bound::_BoundLaw{<:LocalLaw,<:_ValidatedStructuralBinding}) =
    bound.binding.binding

"""`storage(bound_or_plan_or_prepared, descriptor)` returns its associated storage without copying."""
function storage(bound::_BoundLaw, descriptor::Field)
    binding = _find_descriptor_binding(
        descriptor, _storage_binding(bound).fields, :field)
    binding.ownership isa _TemporaryOwnership && throw(
        LocalMathValidationError(
            "a compiler-private Temporary Field has no public storage";
            stage = :storage, contract = :temporary_field_observability,
            expected = :private, actual = semantic_identity(descriptor)))
    return binding.storage
end

function storage(bound::_BoundLaw, descriptor::Relation)
    binding = _find_descriptor_binding(
        descriptor, _storage_binding(bound).relations, :relation)
    return binding.storage
end

function storage(bound::_BoundLaw, descriptor::Collection)
    binding = _find_descriptor_binding(
        descriptor, _storage_binding(bound).collections, :collection)
    return binding.storage
end

storage(plan::Plan, descriptor) = storage(plan.bound, descriptor)
storage(prepared::PreparedPlan, descriptor) = storage(prepared.plan, descriptor)

"""Planning-only transition that validates slots and mints RelationProofs."""
Base.@nospecializeinfer Base.@noinline function _validate_bound_law(
        bound::_BoundLaw{<:LocalLaw,<:_StructuralBinding})
    Base.@nospecialize bound
    cold = Base.inferencebarrier(bound)::_BoundLaw
    fields, relations, collections = _law_descriptor_requirements(cold.law)
    validated = _validate_structural_binding(
        fields, relations, collections, cold.binding,
    )
    return _BoundLaw(_BOUND_LAW_SEAL, cold.law, validated)
end
