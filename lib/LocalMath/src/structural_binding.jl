# Cold structural binding for the LocalMath spatial waist. This layer matches
# semantic descriptor identities to concrete storage once, assigns positional
# slots, validates physical schemas, and is the sole owner of relation-proof
# construction. It is deliberately not an execution path.

function _checked_structural_slot(index::Integer, role::Symbol)
    index isa Bool && throw(LocalMathValidationError(
        "a global structural slot requires an integer ordinal";
        stage = :plan, contract = Symbol(role, :_slot_ordinal),
        expected = 1:typemax(Int32), actual = index,
    ))
    1 <= index <= typemax(Int32) || throw(LocalMathValidationError(
        "a global structural slot is outside the Int32 positional ABI";
        stage = :plan, contract = Symbol(role, :_slot_ordinal),
        expected = 1:typemax(Int32), actual = index,
    ))
    return Int32(index)
end

"""Cold value-indexed field slot; only stage-local prepared slots are type-indexed."""
struct _FieldSlot
    index::Int32
    _FieldSlot(index::Integer) = new(_checked_structural_slot(index, :field))
end

"""Cold value-indexed relation slot; it never enters a device ABI."""
struct _RelationSlot
    index::Int32
    _RelationSlot(index::Integer) = new(_checked_structural_slot(index, :relation))
end

"""Cold value-indexed finite-sequence Collection slot."""
struct _CollectionSlot
    index::Int32
    _CollectionSlot(index::Integer) = new(_checked_structural_slot(index, :collection))
end

abstract type _StructuralOwnership end
struct _ComputedOwnership <: _StructuralOwnership end
struct _LocalOwnership <: _StructuralOwnership end
struct _SharedOwnership <: _StructuralOwnership end
struct _GhostOwnership <: _StructuralOwnership end
struct _ExternalOwnership <: _StructuralOwnership end
struct _TemporaryOwnership <: _StructuralOwnership end

function _structural_ownership(value::Symbol)
    value === :computed && return _ComputedOwnership()
    value === :local && return _LocalOwnership()
    value === :shared && return _SharedOwnership()
    value === :ghost && return _GhostOwnership()
    value === :external && return _ExternalOwnership()
    value === :temporary && return _TemporaryOwnership()
    throw(LocalMathValidationError(
        "structural ownership is not a closed admitted law";
        stage = :bind, contract = :structural_ownership,
        expected = (:computed, :local, :shared, :ghost, :external, :temporary),
        actual = value,
    ))
end

struct _StructuralLeafFact
    name::Symbol
    storage_type::DataType
    logical::NamedTuple
    prepared::Any
end

_collect_structural_leaves!(leaves, prefix::Symbol, ::Nothing) = leaves
function _collect_structural_leaves!(
        leaves, prefix::Symbol, storage::NamedTuple
    )
    for (name, value) in pairs(storage)
        _collect_structural_leaves!(leaves, Symbol(prefix, :_, name), value)
    end
    return leaves
end
function _collect_structural_leaves!(leaves, prefix::Symbol, storage::Tuple)
    for (index, value) in pairs(storage)
        _collect_structural_leaves!(leaves, Symbol(prefix, :_, index), value)
    end
    return leaves
end
function _collect_structural_leaves!(leaves, prefix::Symbol, storage)
    for pair in _binding_physical_leaves(prefix, storage)
        push!(leaves, pair)
    end
    return leaves
end

function _structural_physical_leaves(prefix::Symbol, storage)
    leaves = Pair{Symbol,Any}[]
    _collect_structural_leaves!(leaves, prefix, storage)
    return Tuple(leaves)
end

function _structural_leaf_facts(storage, prefix::Symbol)
    storage === nothing && return ()
    leaves = _structural_physical_leaves(prefix, storage)
    isempty(leaves) && throw(LocalMathValidationError(
        "a structural storage binding has no physical leaves";
        stage = :bind, contract = :structural_physical_leaves,
        binding = prefix,
    ))
    facts = _StructuralLeafFact[]
    sizehint!(facts, length(leaves))
    for (name, leaf) in leaves
        push!(facts, _StructuralLeafFact(
            name, typeof(leaf), _binding_logical_facts(leaf),
            _prepared_array_fact(leaf),
        ))
    end
    return Tuple(facts)
end

struct _FieldStorageBinding{F,S,O<:_StructuralOwnership}
    field::F
    storage::S
    binding_id::UUIDs.UUID
    ownership::O
end

function _field_storage_binding(
        field::Field, storage;
        binding_id::UUIDs.UUID = _new_semantic_identity(),
        ownership::Symbol = :local,
    )
    law = _structural_ownership(ownership)
    law isa _ComputedOwnership && throw(LocalMathValidationError(
        "a Field binding cannot use computed ownership";
        stage = :bind, contract = :field_ownership,
    ))
    logical = _binding_logical_facts(storage)
    logical.element_type === eltype(field) || throw(LocalMathValidationError(
        "Field storage has the wrong element type";
        stage = :bind, contract = :field_storage_element_type,
        expected = eltype(field), actual = logical.element_type,
    ))
    Tuple(logical.size) == size(field.space) || throw(LocalMathValidationError(
        "Field storage shape does not match its Space";
        stage = :bind, contract = :field_storage_shape,
        expected = size(field.space), actual = logical.size,
    ))
    return _FieldStorageBinding(
        field, storage, binding_id, law,
    )
end

struct _RelationStorageBinding{R,S,O<:_StructuralOwnership,G,V}
    relation::R
    storage::S
    binding_id::UUIDs.UUID
    ownership::O
    generation::G
    status::V
end

"""Cold binding of one `Collection` to its sole `CompactedStorage` authority."""
struct _CollectionStorageBinding{C<:Collection,S<:CompactedStorage}
    collection::C
    storage::S
    binding_id::UUIDs.UUID
end

function _collection_storage_binding(
        collection::Collection{T}, storage::CompactedStorage;
        binding_id::UUIDs.UUID = _new_semantic_identity(),
    ) where {T}
    capacity = Int(collection.capacity)
    try
        _validate_compacted_record_storage(storage.records, T, capacity)
        eltype(storage.count) === Int32 && size(storage.count) == (1,) ||
            throw(ArgumentError("count"))
        for provenance in (storage.source_item, storage.source_lane)
            eltype(provenance) === Int32 && size(provenance) == (capacity,) ||
                throw(ArgumentError("provenance"))
        end
    catch error
        throw(LocalMathValidationError(
            "Collection storage disagrees with its exact Collection schema";
            stage = :bind, contract = :collection_storage_schema,
            expected = (element_type = T, capacity = capacity,
                count = (Int32, (1,)), provenance = (Int32, (capacity,))),
            actual = sprint(showerror, error),
        ))
    end
    return _CollectionStorageBinding(collection, storage, binding_id)
end

_relation_declared_ownership(::_IdentityRelation) = :computed
_relation_declared_ownership(::_AffineRelation) = :computed
_relation_declared_ownership(::_ProductRelation) = :computed
_relation_declared_ownership(::_ComposedRelation) = :computed
_relation_declared_ownership(representation::_BoundaryRelation) =
    representation.policy isa GhostBoundary ? :ghost : :computed
_relation_declared_ownership(::_MaskedRelation) = :computed
_relation_declared_ownership(::_SelectedRelation) = :computed
_relation_declared_ownership(::_FieldIndexRelation) = :computed
_relation_declared_ownership(representation::_RuntimeRelation) =
    representation.ownership
_relation_declared_ownership(::_FixedRelation) = :local
_relation_declared_ownership(::_InverseRelation) = :local
_relation_declared_ownership(representation::_PackedRelation) =
    representation.ownership

_relation_requires_storage(::_FixedRelation) = true
_relation_requires_storage(::_InverseRelation) = true
_relation_requires_storage(::_PackedRelation) = true
_relation_requires_storage(representation::_BoundaryRelation) =
    representation.policy isa GhostBoundary
_relation_requires_storage(_) = false

_relation_requires_generation(::_PackedRelation) = true
_relation_requires_generation(_) = false
_relation_admits_dynamic_content(::_FixedRelation) = true
_relation_admits_dynamic_content(::_InverseRelation) = true
_relation_admits_dynamic_content(::_PackedRelation) = true
_relation_admits_dynamic_content(representation::_BoundaryRelation) =
    representation.policy isa GhostBoundary
_relation_admits_dynamic_content(_) = false
_relation_requires_status(::_PackedRelation) = true
_relation_requires_status(_) = false

function _validate_relation_storage_schema(relation::Relation, ::Nothing)
    _relation_requires_storage(relation.representation) && throw(
        LocalMathValidationError(
            "this relation representation requires physical storage";
            stage = :bind, contract = :relation_storage_schema,
            actual = typeof(relation.representation),
        )
    )
    return nothing
end

function _require_storage_keys(storage::NamedTuple, expected::Tuple, relation)
    keys(storage) == expected || throw(LocalMathValidationError(
        "relation storage does not have the exact representation schema";
        stage = :bind, contract = :relation_storage_schema,
        expected, actual = keys(storage),
    ))
    return nothing
end

function _validate_relation_storage_schema(
        relation::Relation{<:_FixedRelation}, storage::NamedTuple
    )
    keys(storage) in ((:endpoints,), (:endpoints, :counts)) || throw(
        LocalMathValidationError(
            "fixed relation storage requires endpoints and optional counts";
            stage = :bind, contract = :relation_storage_schema,
            expected = ((:endpoints,), (:endpoints, :counts)),
            actual = keys(storage),
        )
    )
    return nothing
end

function _validate_relation_storage_schema(
        relation::Relation{<:_PackedRelation}, storage::NamedTuple
    )
    _require_storage_keys(
        storage, (:active, :endpoints, :offsets, :counts), relation
    )
end

function _validate_relation_storage_schema(
        relation::Relation{<:_InverseRelation}, storage::NamedTuple
    )
    keys(storage) in ((:degrees, :incidents), (:offsets, :incidents)) || throw(
        LocalMathValidationError(
            "inverse relation storage requires lane or grouped incidence";
            stage = :bind, contract = :relation_storage_schema,
            expected = ((:degrees, :incidents), (:offsets, :incidents)),
            actual = keys(storage),
        )
    )
    return nothing
end

function _validate_relation_storage_schema(
        relation::Relation{<:_BoundaryRelation}, storage::NamedTuple
    )
    relation.representation.policy isa GhostBoundary || throw(
        LocalMathValidationError(
            "only a ghost boundary relation admits bound mapping storage";
            stage = :bind, contract = :relation_storage_schema,
            actual = typeof(relation.representation.policy),
        )
    )
    _require_storage_keys(storage, (:mapping,), relation)
end

function _validate_relation_storage_schema(relation::Relation, storage)
    throw(LocalMathValidationError(
        "relation storage is not admitted for this representation";
        stage = :bind, contract = :relation_storage_schema,
        expected = _relation_requires_storage(relation.representation) ?
            :representation_storage : nothing,
        actual = typeof(storage),
    ))
end

function _relation_storage_binding(
        relation::Relation, storage = nothing;
        binding_id::UUIDs.UUID = _new_semantic_identity(),
        ownership::Symbol = _relation_declared_ownership(
            relation.representation
        ),
        generation = nothing,
        status = nothing,
    )
    law = _structural_ownership(ownership)
    expected = _structural_ownership(
        _relation_declared_ownership(relation.representation)
    )
    typeof(law) === typeof(expected) || throw(LocalMathValidationError(
        "relation binding ownership disagrees with its descriptor";
        stage = :bind, contract = :relation_ownership,
        expected = typeof(expected), actual = typeof(law),
    ))
    _validate_relation_storage_schema(relation, storage)
    representation = relation.representation
    dynamic_content = generation !== nothing ||
        (status !== nothing && !(representation isa _BoundaryRelation))
    if _relation_requires_generation(representation) || dynamic_content
        _relation_admits_dynamic_content(representation) || throw(
            LocalMathValidationError(
                "this relation representation cannot own mutable content authority";
                stage = :bind, contract = :relation_content_generation,
                actual = typeof(representation),
            )
        )
        generation isa _RelationContentGenerationRef || throw(
            LocalMathValidationError(
                "mutable relation storage requires a device generation reference";
                stage = :bind, contract = :relation_content_generation,
                expected = _RelationContentGenerationRef,
                actual = typeof(generation),
            )
        )
    else
        generation === nothing || throw(
            LocalMathValidationError(
                "this relation representation cannot own a content generation";
                stage = :bind, contract = :relation_content_generation,
            )
        )
    end
    if _relation_requires_status(representation) || dynamic_content
        status isa _RelationStatusRef || throw(LocalMathValidationError(
            "relation validation requires a device status reference";
            stage = :bind, contract = :relation_content_status,
            expected = _RelationStatusRef, actual = typeof(status),
        ))
    else
        status === nothing || throw(LocalMathValidationError(
            "this relation representation cannot own a validation status";
            stage = :bind, contract = :relation_content_status,
        ))
    end
    return _RelationStorageBinding(
        relation, storage, binding_id, law, generation, status,
    )
end

"""One storage-only lifecycle envelope; it owns no derived semantic facts."""
struct _StructuralBinding{F<:Tuple,R<:Tuple,C<:Tuple}
    fields::F
    relations::R
    collections::C
    function _StructuralBinding(
            fields::F, relations::R, collections::C,
        ) where {F<:Tuple,R<:Tuple,C<:Tuple}
        all(binding -> binding isa _FieldStorageBinding, fields) || throw(
            LocalMathValidationError(
                "structural field entries must be Field storage bindings";
                stage = :bind, contract = :structural_field_bindings,
            )
        )
        all(binding -> binding isa _RelationStorageBinding, relations) || throw(
            LocalMathValidationError(
                "structural relation entries must be Relation storage bindings";
                stage = :bind, contract = :structural_relation_bindings,
            )
        )
        all(binding -> binding isa _CollectionStorageBinding, collections) || throw(
            LocalMathValidationError(
                "structural collection entries must be Collection storage bindings";
                stage = :bind, contract = :structural_collection_bindings,
            )
        )
        return new{F,R,C}(fields, relations, collections)
    end
end

# The two-argument form is the canonical empty-Collection default, not a
# separate binding representation or validation path.
_StructuralBinding(fields::Tuple, relations::Tuple) =
    _StructuralBinding(fields, relations, ())

struct _RelationBindingSchema{O,R}
    binding_id::UUIDs.UUID
    ownership::O
    representation::R
    physical_leaves::Tuple{Vararg{_StructuralLeafFact}}
end

mutable struct _ValidatedBindingSeal end
const _VALIDATED_BINDING_SEAL = _ValidatedBindingSeal()

struct _ValidatedStructuralBinding{B,F,R,C,P,FF,CF,FS,RS,CS}
    binding::B
    fields::F
    relations::R
    collections::C
    proofs::P
    field_facts::FF
    collection_facts::CF
    field_slots::FS
    relation_slots::RS
    collection_slots::CS

    function _ValidatedStructuralBinding(
            seal::_ValidatedBindingSeal, binding::B, fields::F,
            relations::R, collections::C, proofs::P, field_facts::FF,
            collection_facts::CF, field_slots::FS, relation_slots::RS,
            collection_slots::CS,
        ) where {B,F,R,C,P,FF,CF,FS,RS,CS}
        seal === _VALIDATED_BINDING_SEAL || throw(ArgumentError(
            "validated structural binding requires the planner-owned seal"
        ))
        return new{B,F,R,C,P,FF,CF,FS,RS,CS}(
            binding, fields, relations, collections, proofs, field_facts,
            collection_facts, field_slots, relation_slots, collection_slots,
        )
    end
end

function _relation_binding_leaf_facts(binding::_RelationStorageBinding)
    physical_leaves = _structural_leaf_facts(binding.storage, :relation)
    binding.generation === nothing || (physical_leaves = (
        physical_leaves..., _structural_leaf_facts(
            binding.generation.generations, :relation_generation
        )...
    ))
    if binding.status !== nothing
        physical_leaves = (physical_leaves...,
            _structural_leaf_facts(binding.status.statuses,
                :relation_status)...)
        if binding.status.validated_generations !== nothing
            physical_leaves = (physical_leaves...,
                _structural_leaf_facts(binding.status.validated_generations,
                    :relation_validated_generation)...)
        end
    end
    return physical_leaves
end

function _relation_multiplicity(representation)
    representation isa _IdentityRelation && return :exactly_one
    representation isa _RuntimeRelation && return :runtime_bounded
    return :bounded
end

_relation_coverage(::_IdentityRelation) = :total
_relation_coverage(::_ProductRelation) = :derived
_relation_coverage(::_ComposedRelation) = :derived
_relation_coverage(_) = :unknown
_relation_order(::_IdentityRelation) = :canonical
_relation_order(::_AffineRelation) = :declared_lane_order
_relation_order(::_ProductRelation) = :mixed_radix
_relation_order(::_ComposedRelation) = :mixed_radix_composition
_relation_order(::_PackedRelation) = :physical_lane_order
_relation_order(::_FixedRelation) = :physical_lane_order
_relation_order(::_InverseRelation) = :physical_lane_order
_relation_order(_) = :canonical

function _affine_directional_halos(offsets::Tuple)
    dimension = length(first(offsets))
    lower = ntuple(axis -> maximum(
        offset -> max(0, -Int(offset[axis])), offsets), dimension)
    upper = ntuple(axis -> maximum(
        offset -> max(0, Int(offset[axis])), offsets), dimension)
    return (
        read = (; lower, upper),
        reverse_publication = (; lower=upper, upper=lower),
    )
end

function _relation_footprint(relation::Relation)
    representation = relation.representation
    if representation isa _AffineRelation
        return (kind = :affine, offsets = representation.offsets,
            halos = _affine_directional_halos(representation.offsets))
    elseif representation isa _BoundaryRelation
        base = representation.base
        base_footprint = _relation_footprint(base)
        return base.representation isa _AffineRelation ? (
            kind = :boundary,
            base = semantic_identity(base),
            policy = _boundary_policy_facts(representation.policy),
            offsets = base_footprint.offsets,
            halos = base_footprint.halos,
        ) : (kind = :boundary, base = semantic_identity(base))
    elseif representation isa _ProductRelation
        return (kind = :product, factors = map(semantic_identity, representation.factors))
    elseif representation isa _ComposedRelation
        return (kind = :composition,
            factors = map(semantic_identity, representation.factors))
    elseif representation isa _FieldIndexRelation
        return (kind = :bounded_indirect,
            keys = semantic_identity(representation.keys),
            degree = representation.degree,
            optional = representation.optional)
    end
    return (kind = :bounded, degree = degree_bound(relation))
end

_boundary_policy_facts(::StrictBoundary) = (kind = :strict,)
_boundary_policy_facts(policy::PeriodicBoundary) =
    (kind = :periodic, axes = policy.axes)
_boundary_policy_facts(::ExteriorBoundary) = (kind = :exterior,)
_boundary_policy_facts(policy::MaskedBoundary) = (
    kind = :masked,
    mask_field = semantic_identity(policy.mask),
    fallback = _boundary_policy_facts(policy.fallback),
)
_boundary_policy_facts(policy::GhostBoundary) = (
    kind = :ghost,
    lower = policy.lower,
    upper = policy.upper,
    ghost_space = semantic_identity(policy.ghost_space),
)

function _lane_storage_layout(storage)
    storage isa Tuple && return :tuple_lanes
    storage isa AbstractMatrix && return :matrix_lanes
    return Symbol(nameof(typeof(storage)))
end

function _relation_representation_facts(
        relation::Relation, binding::_RelationStorageBinding
    )
    representation = relation.representation
    representation isa _IdentityRelation && return (family = :identity,)
    representation isa _AffineRelation && return (
        family = :affine, offsets = representation.offsets,
        origin = representation.origin,
    )
    representation isa _FixedRelation && return (
        family = :fixed,
        degree = representation.degree,
        lane_layout = _lane_storage_layout(binding.storage.endpoints),
        has_counts = hasproperty(binding.storage, :counts) &&
            binding.storage.counts !== nothing,
    )
    representation isa _ProductRelation && return (
        family = :product,
        factors = map(semantic_identity, representation.factors),
        degree = representation.degree,
    )
    representation isa _ComposedRelation && return (
        family = :composed,
        factors = map(semantic_identity, representation.factors),
        degree = representation.degree,
        lane_order = :first_factor_fastest_mixed_radix,
    )
    representation isa _BoundaryRelation && return (
        family = :boundary,
        base = semantic_identity(representation.base),
        policy = _boundary_policy_facts(representation.policy),
        degree = representation.degree,
        validation_slot = representation.policy isa GhostBoundary &&
                binding.status !== nothing ? binding.status.slot : nothing,
    )
    representation isa _RuntimeRelation && return (
        family = :runtime_ordinal,
        degree = representation.degree,
        key_type = representation.key_type,
    )
    representation isa _FieldIndexRelation && return (
        family = :field_index,
        keys = semantic_identity(representation.keys),
        degree = representation.degree,
        optional = representation.optional,
    )
    representation isa _MaskedRelation && return (
        family = :source_mask,
        base = semantic_identity(representation.base),
        mask_field = semantic_identity(representation.mask),
        degree = representation.degree,
    )
    representation isa _SelectedRelation && return (
        family = :selected,
        base = semantic_identity(representation.base),
        injection = semantic_identity(representation.injection),
        degree = representation.degree,
    )
    representation isa _InverseRelation && return (
        family = :inverse,
        forward = semantic_identity(representation.forward),
        degree = representation.degree,
        layout = hasproperty(binding.storage, :degrees) ?
            :fixed_lanes : :grouped_csr,
    )
    representation isa _PackedRelation && return (
        family = :packed,
        degree = representation.degree,
        capacity = representation.capacity,
        layout = representation.layout,
        lane_layout = _lane_storage_layout(binding.storage.endpoints),
        bank_slot = binding.generation.slot,
    )
    throw(LocalMathValidationError(
        "relation representation has no closed proof schema";
        stage = :plan, contract = :relation_representation_schema,
        actual = typeof(representation),
    ))
end

function _require_integer_storage(value::Tuple, purpose::Symbol)
    all(lane -> eltype(lane) <: Integer && eltype(lane) !== Bool,
        value) || throw(
        LocalMathValidationError(
            "relation index lanes must contain integers";
            stage = :bind, contract = purpose,
            expected = Integer, actual = map(eltype, value),
        )
    )
    return nothing
end

function _require_integer_storage(value, purpose::Symbol)
    eltype(value) <: Integer && eltype(value) !== Bool || throw(
        LocalMathValidationError(
            "relation index storage must contain integers";
            stage = :bind, contract = purpose,
            expected = Integer, actual = eltype(value),
        ))
    return nothing
end

_relation_uses_dynamic_content(binding::_RelationStorageBinding) =
    binding.generation !== nothing

function _validate_dynamic_relation_content_authority(
        binding::_RelationStorageBinding)
    generation, status = binding.generation, binding.status
    generation isa _RelationContentGenerationRef &&
        status isa _RelationStatusRef || throw(LocalMathValidationError(
            "dynamic relation content requires generation and status authority";
            stage = :bind, contract = :relation_content_authority,
            expected = (_RelationContentGenerationRef, _RelationStatusRef),
            actual = (typeof(generation), typeof(status)),
        ))
    eltype(generation.generations) === UInt64 || throw(
        LocalMathValidationError(
            "relation generations must use UInt64 device storage";
            stage = :bind, contract = :relation_content_generation_type,
            expected = UInt64, actual = eltype(generation.generations),
        ))
    eltype(status.statuses) === Int32 || throw(LocalMathValidationError(
        "relation validation status must use Int32 device storage";
        stage = :bind, contract = :relation_content_status_type,
        expected = Int32, actual = eltype(status.statuses),
    ))
    status.validated_generations !== nothing || throw(
        LocalMathValidationError(
            "dynamic relation content requires validated-generation storage";
            stage = :bind, contract = :relation_validated_generation,
            expected = UInt64, actual = nothing,
        ))
    eltype(status.validated_generations) === UInt64 || throw(
        LocalMathValidationError(
            "validated relation generations must use UInt64 device storage";
            stage = :bind, contract = :relation_validated_generation_type,
            expected = UInt64,
            actual = eltype(status.validated_generations),
        ))
    generation.slot == status.slot || throw(LocalMathValidationError(
        "relation generation and validation status must use the same slot";
        stage = :bind, contract = :relation_content_authority_slot,
        expected = generation.slot, actual = status.slot,
    ))
    _might_alias(generation.generations,
        status.validated_generations) === false || throw(
        LocalMathValidationError(
            "current and validated relation generations must not alias";
            stage = :bind, contract = :relation_content_generation_alias,
            expected = :nonaliasing, actual = :aliased,
        ))
    return nothing
end

function _require_host_static_relation_content(storage)
    leaves = _structural_physical_leaves(:relation_content, storage)
    all(pair -> _array_backend(last(pair)) isa KernelAbstractions.CPU,
        leaves) || throw(LocalMathValidationError(
        "this device-resident relation content requires generation/status authority";
        stage = :bind, contract = :relation_content_authority,
        expected = :device_generation_and_status,
        actual = map(pair -> typeof(_array_backend(last(pair))), leaves),
    ))
    return nothing
end

@kernel function _validate_immutable_fixed_relation_kernel!(
        status, endpoints, counts, degree::Int32, domain_count::Int32,
        codomain_count::Int32, ::Val{HasCounts},
    ) where {HasCounts}
    item = @index(Global, Linear)
    if item <= domain_count
        count = HasCounts ? Int32(@inbounds counts[item]) : degree
        failure = !(Int32(0) <= count <= degree)
        if !failure
            for lane in Int32(1):count
                endpoint = Int32(_fixed_relation_endpoint(
                    endpoints, Int32(item), lane))
                failure |= !(Int32(1) <= endpoint <= codomain_count)
            end
        end
        failure && Atomix.@atomic max(status[1], Int32(1))
    end
end

function _validate_device_fixed_relation_content(relation, storage)
    backend = _array_backend(storage.endpoints)
    counts = hasproperty(storage, :counts) ? storage.counts : nothing
    counts === nothing || isequal(_array_backend(counts), backend) ||
        throw(LocalMathValidationError(
            "fixed relation endpoints and counts must use one backend";
            stage = :bind, contract = :relation_storage_backend,
            expected = typeof(backend), actual = typeof(_array_backend(counts))))
    status = KernelAbstractions.allocate(backend, Int32, (1,))
    _initialize_allocated_storage!(backend, status, Int32(0))
    _validate_immutable_fixed_relation_kernel!(backend)(
        status, storage.endpoints, counts, Int32(degree_bound(relation)),
        Int32(length(domain(relation))), Int32(length(codomain(relation))),
        Val(counts !== nothing); ndrange = max(length(domain(relation)), 1))
    KernelAbstractions.synchronize(backend)
    host_status = zeros(Int32, 1)
    copyto!(host_status, status)
    KernelAbstractions.synchronize(backend)
    iszero(only(host_status)) || throw(LocalMathValidationError(
        "fixed relation device content violates its count or endpoint bounds";
        stage = :bind, contract = :fixed_relation_content,
        expected = (
            count = 0:degree_bound(relation),
            endpoint = 1:length(codomain(relation))),
        actual = :invalid_device_content))
    return nothing
end

function _validate_fixed_relation_content(relation, storage)
    degree = degree_bound(relation)
    domain_count = length(domain(relation))
    codomain_count = length(codomain(relation))
    counts = hasproperty(storage, :counts) ? storage.counts : nothing
    for item in 1:domain_count
        count = counts === nothing ? degree : Int(@inbounds counts[item])
        0 <= count <= degree || throw(LocalMathValidationError(
            "fixed relation count is outside its proved degree";
            stage = :bind, contract = :fixed_relation_count,
            expected = 0:degree, actual = count,
        ))
        for lane in 1:count
            endpoint = Int(_fixed_relation_endpoint(
                storage.endpoints, item, lane))
            1 <= endpoint <= codomain_count || throw(
                LocalMathValidationError(
                    "fixed relation endpoint is outside its codomain";
                    stage = :bind, contract = :fixed_relation_endpoint,
                    expected = 1:codomain_count, actual = endpoint,
                ))
        end
    end
    return nothing
end

function _validate_inverse_relation_content(relation, storage)
    degree = degree_bound(relation)
    domain_count = length(domain(relation))
    incident_count = length(codomain(relation))
    if hasproperty(storage, :degrees)
        for item in 1:domain_count
            count = Int(@inbounds storage.degrees[item])
            0 <= count <= degree || throw(LocalMathValidationError(
                "inverse relation degree is outside its proved bound";
                stage = :bind, contract = :inverse_relation_degree,
                expected = 0:degree, actual = count,
            ))
            for lane in 1:count
                incident = Int(_inverse_incident(
                    storage.incidents, item, lane))
                1 <= incident <= incident_count || throw(
                    LocalMathValidationError(
                        "inverse relation incident is outside its codomain";
                        stage = :bind, contract = :inverse_relation_incident,
                        expected = 1:incident_count, actual = incident,
                    ))
            end
        end
        return nothing
    end
    offsets = storage.offsets
    for item in 1:domain_count
        start = Int(@inbounds offsets[item])
        stop = Int(@inbounds offsets[item + 1])
        1 <= start <= length(storage.incidents) + 1 || throw(
            LocalMathValidationError(
                "grouped inverse offset is outside its incidence storage";
                stage = :bind, contract = :inverse_relation_offset,
                expected = 1:(length(storage.incidents) + 1), actual = start,
            ))
        start <= stop <= length(storage.incidents) + 1 || throw(
            LocalMathValidationError(
                "grouped inverse offsets are not a bounded monotone range";
                stage = :bind, contract = :inverse_relation_offsets,
                expected = (start, length(storage.incidents) + 1),
                actual = stop,
            ))
        stop - start <= degree || throw(LocalMathValidationError(
            "grouped inverse incidence count exceeds its proved degree";
            stage = :bind, contract = :inverse_relation_degree,
            expected = 0:degree, actual = stop - start,
        ))
        for position in start:(stop - 1)
            incident = Int(@inbounds storage.incidents[position])
            1 <= incident <= incident_count || throw(
                LocalMathValidationError(
                    "grouped inverse incident is outside its codomain";
                    stage = :bind, contract = :inverse_relation_incident,
                    expected = 1:incident_count, actual = incident,
                ))
        end
    end
    return nothing
end

function _static_relation_content_evidence(relation, binding)
    _relation_uses_dynamic_content(binding) && begin
        _validate_dynamic_relation_content_authority(binding)
        return :device_content_validation_required
    end
    representation = relation.representation
    if representation isa _FixedRelation
        leaves = _structural_physical_leaves(
            :relation_content, binding.storage)
        if all(pair -> _array_backend(last(pair)) isa KernelAbstractions.CPU,
                leaves)
            _validate_fixed_relation_content(relation, binding.storage)
            return :immutable_host_borrow
        end
        _validate_device_fixed_relation_content(relation, binding.storage)
        return :immutable_device_borrow
    elseif representation isa _InverseRelation
        _require_host_static_relation_content(binding.storage)
        _validate_inverse_relation_content(relation, binding.storage)
    elseif representation isa _BoundaryRelation &&
            representation.policy isa GhostBoundary
        _require_host_static_relation_content(binding.storage)
        _validate_ghost_relation_content(relation, binding.storage)
    else
        throw(LocalMathValidationError(
            "this stored relation has no exact content validator";
            stage = :bind, contract = :relation_content_validator,
            actual = typeof(representation),
        ))
    end
    return :immutable_host_borrow
end

function _validate_ghost_relation_content(relation, storage)
    ghost_count = length(relation.representation.policy.ghost_space)
    for endpoint in storage.mapping
        0 <= endpoint <= ghost_count || throw(LocalMathValidationError(
            "ghost mapping endpoint is outside its bound ghost storage";
            stage = :bind, contract = :ghost_relation_endpoint,
            expected = 0:ghost_count, actual = endpoint,
        ))
    end
    return nothing
end

function _validate_relation_physical_shape(
        relation::Relation{<:_FixedRelation}, binding::_RelationStorageBinding
    )
    storage = binding.storage
    endpoints = storage.endpoints
    degree = degree_bound(relation)
    _fixed_lane_count(endpoints) >= degree || throw(LocalMathValidationError(
        "fixed relation storage has fewer lanes than its proved degree";
        stage = :bind, contract = :fixed_relation_lanes,
        expected = (
            relation = relation,
            minimum_lanes = degree,
            minimum_items = length(domain(relation)),
        ),
        actual = (
            lanes = _fixed_lane_count(endpoints),
            shape = size(endpoints),
            element_type = eltype(endpoints),
        ),
        hint = "store fixed endpoints lane-major with at least degree × domain-length entries",
    ))
    for lane in 1:degree
        _fixed_lane_capacity(endpoints, lane) >= length(domain(relation)) ||
            throw(LocalMathValidationError(
                "fixed relation lane storage is shorter than its domain";
                stage = :bind, contract = :fixed_relation_lane_capacity,
                expected = (
                    relation = relation,
                    lane = lane,
                    minimum_items = length(domain(relation)),
                ),
                actual = (
                    lane_capacity = _fixed_lane_capacity(endpoints, lane),
                    shape = size(endpoints),
                    element_type = eltype(endpoints),
                ),
                hint = "provide one endpoint entry per source item in every declared lane",
            ))
    end
    _require_integer_storage(endpoints, :fixed_relation_endpoint_type)
    if hasproperty(storage, :counts) && storage.counts !== nothing
        length(storage.counts) >= length(domain(relation)) || throw(
            LocalMathValidationError(
            "fixed relation counts are shorter than its domain";
            stage = :bind, contract = :fixed_relation_counts,
            expected = (
                relation = relation,
                minimum_items = length(domain(relation)),
                count_range = 0:degree,
            ),
            actual = (
                items = length(storage.counts),
                shape = size(storage.counts),
                element_type = eltype(storage.counts),
            ),
            hint = "omit counts for a full-degree relation or provide one bounded count per source item",
        )
        )
        _require_integer_storage(storage.counts, :fixed_relation_count_type)
    end
    return _static_relation_content_evidence(relation, binding)
end

function _validate_relation_physical_shape(
        relation::Relation{<:_PackedRelation}, binding::_RelationStorageBinding
    )
    storage = binding.storage
    degree = degree_bound(relation)
    relation.representation.capacity == length(domain(relation)) || throw(
        LocalMathValidationError(
            "packed relation capacity must equal its semantic domain cardinality";
            stage = :bind, contract = :packed_relation_domain_capacity,
            expected = length(domain(relation)),
            actual = relation.representation.capacity,
        )
    )
    eltype(storage.active) === Bool || throw(LocalMathValidationError(
        "packed active storage must contain Bool values";
        stage = :bind, contract = :packed_relation_active_type,
        expected = Bool, actual = eltype(storage.active),
    ))
    relation.representation.capacity <= length(storage.active) || throw(
        LocalMathValidationError(
            "packed descriptor capacity exceeds its active storage";
            stage = :bind, contract = :packed_relation_capacity,
            expected = length(storage.active),
            actual = relation.representation.capacity,
        )
    )
    _packed_lane_count(storage.endpoints) >= degree || throw(
        LocalMathValidationError(
            "packed relation storage has fewer lanes than its proved degree";
            stage = :bind, contract = :packed_relation_lanes,
            expected = degree, actual = _packed_lane_count(storage.endpoints),
        )
    )
    length(storage.active) <= _packed_endpoint_storage_length(storage.endpoints) ||
        throw(LocalMathValidationError(
            "packed active storage exceeds endpoint column capacity";
            stage = :bind, contract = :packed_relation_capacity,
            expected = _packed_endpoint_storage_length(storage.endpoints),
            actual = length(storage.active),
        ))
    slot = binding.generation.slot
    slot == binding.status.slot || throw(LocalMathValidationError(
        "packed generation and status references must use the same bank slot";
        stage = :bind, contract = :packed_relation_receipt_slot,
        expected = slot, actual = binding.status.slot,
    ))
    slot <= length(storage.offsets) && slot <= length(storage.counts) || throw(
        LocalMathValidationError(
            "packed receipt slot is outside offsets/counts storage";
            stage = :bind, contract = :packed_relation_receipt_slot,
            expected = :bound_bank_slot, actual = slot,
        )
    )
    _require_integer_storage(storage.endpoints, :packed_relation_endpoint_type)
    _require_integer_storage(storage.offsets, :packed_relation_offset_type)
    _require_integer_storage(storage.counts, :packed_relation_count_type)
    eltype(binding.generation.generations) === UInt64 || throw(
        LocalMathValidationError(
            "packed generation storage must use UInt64";
            stage = :bind, contract = :packed_relation_generation_type,
            expected = UInt64,
            actual = eltype(binding.generation.generations),
        )
    )
    eltype(binding.status.statuses) <: Integer || throw(
        LocalMathValidationError(
            "packed status storage must use an integer status code";
            stage = :bind, contract = :packed_relation_status_type,
            expected = Integer, actual = eltype(binding.status.statuses),
        )
    )
    binding.status.validated_generations === nothing && throw(
        LocalMathValidationError(
            "packed relation status requires a validated-generation device reference";
            stage = :bind,
            contract = :packed_relation_validated_generation,
            expected = UInt64, actual = nothing,
        )
    )
    eltype(binding.status.validated_generations) === UInt64 || throw(
        LocalMathValidationError(
            "packed validated-generation storage must use UInt64";
            stage = :bind,
            contract = :packed_relation_validated_generation_type,
            expected = UInt64,
            actual = eltype(binding.status.validated_generations),
        )
    )
    _arrays_mightalias(:relation_generation,
        binding.generation.generations, :relation_validated_generation,
        binding.status.validated_generations) === nothing || throw(
        LocalMathValidationError(
            "current and validated relation generations must use distinct device storage";
            stage = :bind,
            contract = :packed_relation_generation_alias,
            expected = :nonaliasing, actual = :aliased,
        )
    )
    return :device_content_validation_required
end

function _validate_relation_physical_shape(
        relation::Relation{<:_InverseRelation}, binding::_RelationStorageBinding
    )
    storage = binding.storage
    domain_count = length(domain(relation))
    if hasproperty(storage, :degrees)
        length(storage.degrees) >= domain_count || throw(
            LocalMathValidationError(
                "inverse degree storage is shorter than its domain";
                stage = :bind, contract = :inverse_relation_degrees,
                expected = domain_count, actual = length(storage.degrees),
            )
        )
        _inverse_lane_count(storage.incidents) >= degree_bound(relation) ||
            throw(LocalMathValidationError(
                "inverse incidence storage has fewer lanes than its degree";
                stage = :bind, contract = :inverse_relation_lanes,
                expected = degree_bound(relation),
                actual = _inverse_lane_count(storage.incidents),
            ))
        for lane in 1:degree_bound(relation)
            _inverse_lane_capacity(storage.incidents, lane) >= domain_count ||
                throw(LocalMathValidationError(
                    "inverse incidence lane storage is shorter than its domain";
                    stage = :bind, contract = :inverse_relation_lane_capacity,
                    expected = domain_count,
                    actual = _inverse_lane_capacity(storage.incidents, lane),
                ))
        end
        _require_integer_storage(storage.degrees, :inverse_relation_degree_type)
    else
        length(storage.offsets) >= domain_count + 1 || throw(
            LocalMathValidationError(
                "grouped inverse storage requires a terminal offset";
                stage = :bind, contract = :inverse_relation_offsets,
                expected = domain_count + 1, actual = length(storage.offsets),
            )
        )
        _require_integer_storage(storage.offsets, :inverse_relation_offset_type)
    end
    _require_integer_storage(storage.incidents, :inverse_relation_incident_type)
    return _static_relation_content_evidence(relation, binding)
end

function _validate_relation_physical_shape(
        relation::Relation{<:_BoundaryRelation},
        binding::_RelationStorageBinding,
    )
    policy = relation.representation.policy
    policy isa GhostBoundary || return :computed
    codomain_extent = size(codomain(relation))
    padded_extent = ntuple(
        axis -> codomain_extent[axis] + policy.lower[axis] + policy.upper[axis],
        length(codomain_extent),
    )
    padded_count = _checked_semantic_product(
        padded_extent, :ghost_boundary_padded_cardinality
    )
    length(binding.storage.mapping) == padded_count || throw(
        LocalMathValidationError(
            "ghost mapping must cover the dense padded coordinate Space";
            stage = :bind, contract = :ghost_relation_mapping,
            expected = padded_count,
            actual = length(binding.storage.mapping),
        )
    )
    _require_integer_storage(
        binding.storage.mapping, :ghost_relation_mapping_type
    )
    return _static_relation_content_evidence(relation, binding)
end

_validate_relation_physical_shape(
    relation::Relation, binding::_RelationStorageBinding
) = :computed

function _mint_relation_proof(relation, schema, evidence)
    # Sole RelationProof constructor call site. Inputs are produced only by
    # the closed validators below, never accepted from an external trait.
    return RelationProof(_RELATION_PROOF_SEAL, relation, schema, evidence)
end

function _validate_relation_binding(binding::_RelationStorageBinding)
    relation = binding.relation
    _validate_relation_storage_schema(relation, binding.storage)
    content_validation = _validate_relation_physical_shape(relation, binding)
    physical_leaves = _relation_binding_leaf_facts(binding)
    representation_facts = _relation_representation_facts(relation, binding)
    schema = _RelationBindingSchema(
        binding.binding_id,
        binding.ownership,
        representation_facts,
        physical_leaves,
    )
    evidence = _ValidatedRelationEvidence(
        _RELATION_PROOF_SEAL,
        (
            degree = degree_bound(relation),
            domain_count = length(domain(relation)),
            codomain_count = length(codomain(relation)),
            content_validation,
        ),
        _relation_multiplicity(relation.representation),
        _relation_coverage(relation.representation),
        _relation_order(relation.representation),
        _relation_footprint(relation),
    )
    return _mint_relation_proof(relation, schema, evidence)
end

Base.@nospecializeinfer Base.@noinline function _find_prior_relation_proof(
        relation::Relation, bindings, proofs)
    Base.@nospecialize relation bindings proofs
    identity = semantic_identity(relation)
    for index in eachindex(bindings)
        semantic_identity(bindings[index].relation) == identity &&
            return proofs[index]
    end
    throw(LocalMathValidationError(
        "a composed Relation factor was not proven before its composition";
        stage = :plan, contract = :composed_relation_factor_proof,
        expected = identity, actual = :missing,
    ))
end

Base.@nospecializeinfer Base.@noinline function _validate_composed_relation_binding(
        binding::_RelationStorageBinding, prior_bindings, prior_proofs)
    Base.@nospecialize binding prior_bindings prior_proofs
    relation = binding.relation
    representation = relation.representation
    factor_values = Any[]
    sizehint!(factor_values, length(representation.factors))
    for factor in representation.factors
        push!(factor_values, _find_prior_relation_proof(
            factor, prior_bindings, prior_proofs))
    end
    factor_proofs = Tuple(factor_values)
    base = _validate_relation_binding(binding)
    coverage = all(proof -> proof.evidence.coverage === :total,
        factor_proofs) ? :total : :derived
    evidence = _ValidatedRelationEvidence(_RELATION_PROOF_SEAL,
        base.evidence.bounds, :derived, coverage,
        :first_factor_fastest_mixed_radix,
        (kind = :composition,
            factors = Tuple((relation_id = proof.relation_id,
                schema_epoch = proof.schema_epoch,
                footprint = proof.evidence.footprint) for proof in factor_proofs)),
    )
    return _mint_relation_proof(relation, base.binding_schema, evidence)
end

Base.@nospecializeinfer Base.@noinline function _validate_relation_bindings(
        bindings::Tuple, prior_bindings::Tuple = (), prior_proofs::Tuple = ())
    Base.@nospecialize bindings prior_bindings prior_proofs
    binding_values = Any[]
    proof_values = Any[]
    sizehint!(binding_values, length(prior_bindings) + length(bindings))
    sizehint!(proof_values, length(prior_proofs) + length(bindings))
    append!(binding_values, prior_bindings)
    append!(proof_values, prior_proofs)
    for binding in bindings
        proof = binding.relation.representation isa _ComposedRelation ?
            _validate_composed_relation_binding(
                binding, binding_values, proof_values) :
            _validate_relation_binding(binding)
        push!(binding_values, binding)
        push!(proof_values, proof)
    end
    return Tuple(proof_values)
end

function _validate_field_binding(binding::_FieldStorageBinding)
    logical = _binding_logical_facts(binding.storage)
    field = binding.field
    logical.element_type === eltype(field) || throw(LocalMathValidationError(
        "Field storage element type changed before validation";
        stage = :plan, contract = :field_storage_element_type,
        expected = eltype(field), actual = logical.element_type,
    ))
    Tuple(logical.size) == size(field.space) || throw(LocalMathValidationError(
        "Field storage shape changed before validation";
        stage = :plan, contract = :field_storage_shape,
        expected = size(field.space), actual = logical.size,
    ))
    return _structural_leaf_facts(binding.storage, :field)
end

function _validate_collection_binding(binding::_CollectionStorageBinding{C}) where {T,C<:Collection{T}}
    # Recheck the non-law-specific portion at the one validated cold boundary;
    # grouping and source-position shape are law facts checked by Stage prepare.
    collection = binding.collection
    storage = binding.storage
    capacity = Int(collection.capacity)
    try
        _validate_compacted_record_storage(storage.records, T, capacity)
        eltype(storage.count) === Int32 && size(storage.count) == (1,) ||
            throw(ArgumentError("count"))
        all(provenance -> eltype(provenance) === Int32 &&
            size(provenance) == (capacity,),
            (storage.source_item, storage.source_lane)) ||
            throw(ArgumentError("provenance"))
    catch error
        throw(LocalMathValidationError(
            "Collection storage changed before structural validation";
            stage = :bind, contract = :collection_storage_schema,
            expected = (element_type = T, capacity = capacity),
            actual = sprint(showerror, error),
        ))
    end
    return _structural_leaf_facts(storage, :collection)
end

function _descriptor_identity(binding::_FieldStorageBinding)
    semantic_identity(binding.field)
end
function _descriptor_identity(binding::_RelationStorageBinding)
    semantic_identity(binding.relation)
end
function _descriptor_identity(binding::_CollectionStorageBinding)
    semantic_identity(binding.collection)
end

function _reject_duplicate_identities(bindings::Tuple, role::Symbol)
    descriptor_ids = map(_descriptor_identity, bindings)
    binding_ids = map(binding -> binding.binding_id, bindings)
    length(unique(descriptor_ids)) == length(descriptor_ids) || throw(
        LocalMathValidationError(
            "duplicate descriptor identity in structural bindings";
            stage = :bind, contract = Symbol(role, :_descriptor_identity),
            expected = :unique, actual = descriptor_ids,
        )
    )
    length(unique(binding_ids)) == length(binding_ids) || throw(
        LocalMathValidationError(
            "duplicate physical binding identity in structural bindings";
            stage = :bind, contract = Symbol(role, :_binding_identity),
            expected = :unique, actual = binding_ids,
        )
    )
    return nothing
end

function _reject_cross_role_collisions(
        fields::Tuple, relations::Tuple, collections::Tuple,
    )
    field_descriptor_ids = map(_descriptor_identity, fields)
    relation_descriptor_ids = map(_descriptor_identity, relations)
    collection_descriptor_ids = map(_descriptor_identity, collections)
    isempty(intersect(Set(field_descriptor_ids), Set(relation_descriptor_ids))) &&
        isempty(intersect(Set(field_descriptor_ids), Set(collection_descriptor_ids))) &&
        isempty(intersect(Set(relation_descriptor_ids), Set(collection_descriptor_ids))) ||
        throw(LocalMathValidationError(
            "Field, Relation, and Collection descriptor identities must be disjoint";
            stage = :bind, contract = :cross_role_descriptor_identity,
        ))
    field_binding_ids = map(binding -> binding.binding_id, fields)
    relation_binding_ids = map(binding -> binding.binding_id, relations)
    collection_binding_ids = map(binding -> binding.binding_id, collections)
    isempty(intersect(Set(field_binding_ids), Set(relation_binding_ids))) &&
        isempty(intersect(Set(field_binding_ids), Set(collection_binding_ids))) &&
        isempty(intersect(Set(relation_binding_ids), Set(collection_binding_ids))) ||
        throw(LocalMathValidationError(
            "Field, Relation, and Collection physical binding identities must be disjoint";
            stage = :bind, contract = :cross_role_binding_identity,
        ))
    return nothing
end

Base.@nospecializeinfer Base.@noinline function _resolve_collection_slot(
        validated::_ValidatedStructuralBinding, collection::Collection,
    )
    Base.@nospecialize validated collection
    identity = semantic_identity(collection)
    for index in eachindex(validated.collections)
        candidate = validated.collections[index].collection
        semantic_identity(candidate) == identity || continue
        candidate == collection || throw(LocalMathValidationError(
            "Collection slot identity has conflicting schema";
            stage = :plan, contract = :collection_slot_schema,
            expected = collection, actual = candidate,
        ))
        return validated.collection_slots[index]
    end
    throw(LocalMathValidationError(
        "Collection has no validated positional slot";
        stage = :plan, contract = :collection_slot,
        expected = identity, actual = :missing,
    ))
end

function _find_descriptor_binding(descriptor, bindings::Tuple, role::Symbol)
    identity = semantic_identity(descriptor)
    matches = Tuple(binding for binding in bindings
        if _descriptor_identity(binding) == identity)
    length(matches) == 1 || throw(LocalMathValidationError(
        isempty(matches) ? "missing structural descriptor binding" :
            "duplicate structural descriptor binding";
        stage = :bind, contract = Symbol(role, :_resolution),
        expected = identity, actual = length(matches),
    ))
    binding = only(matches)
    bound_descriptor = role === :field ? binding.field :
        role === :relation ? binding.relation : binding.collection
    bound_descriptor == descriptor || throw(LocalMathValidationError(
        "a stable descriptor identity was restored with conflicting schema";
        stage = :bind, contract = Symbol(role, :_schema_identity),
        expected = descriptor, actual = bound_descriptor,
    ))
    return binding
end

Base.@nospecializeinfer Base.@noinline function _resolve_field_slot(
        validated::_ValidatedStructuralBinding, field::Field
    )
    Base.@nospecialize validated field
    identity = semantic_identity(field)
    for index in eachindex(validated.fields)
        candidate = validated.fields[index].field
        semantic_identity(candidate) == identity || continue
        candidate == field || throw(LocalMathValidationError(
            "Field slot identity has conflicting schema";
            stage = :plan, contract = :field_slot_schema,
            expected = field, actual = candidate,
        ))
        return validated.field_slots[index]
    end
    throw(LocalMathValidationError(
        "Field has no validated positional slot";
        stage = :plan, contract = :field_slot,
        expected = identity, actual = :missing,
    ))
end

Base.@nospecializeinfer Base.@noinline function _resolve_relation_slot(
        validated::_ValidatedStructuralBinding, relation::Relation
    )
    Base.@nospecialize validated relation
    identity = semantic_identity(relation)
    for index in eachindex(validated.relations)
        candidate = validated.relations[index].relation
        semantic_identity(candidate) == identity || continue
        candidate == relation || throw(LocalMathValidationError(
            "Relation slot identity has conflicting schema";
            stage = :plan, contract = :relation_slot_schema,
            expected = relation, actual = candidate,
        ))
        return validated.relation_slots[index]
    end
    throw(LocalMathValidationError(
        "Relation has no validated positional slot";
        stage = :plan, contract = :relation_slot,
        expected = identity, actual = :missing,
    ))
end

function _reject_unreferenced(required::Tuple, bindings::Tuple, role::Symbol)
    required_ids = map(semantic_identity, required)
    extras = Tuple(_descriptor_identity(binding) for binding in bindings
        if !(_descriptor_identity(binding) in required_ids))
    isempty(extras) || throw(LocalMathValidationError(
        "structural binding contains unreferenced descriptors";
        stage = :bind, contract = Symbol(role, :_unreferenced),
        expected = required_ids, actual = extras,
    ))
    return nothing
end

function _append_descriptor_once!(values, descriptor, role::Symbol)
    identity = semantic_identity(descriptor)
    position = findfirst(
        candidate -> semantic_identity(candidate) == identity, values
    )
    if position === nothing
        push!(values, descriptor)
        return true
    end
    values[position] == descriptor || throw(LocalMathValidationError(
        "a dependency reuses a descriptor identity with conflicting schema";
        stage = :bind, contract = Symbol(role, :_dependency_schema),
        expected = values[position], actual = descriptor,
    ))
    return false
end

_collect_boundary_field_dependencies!(fields, ::StrictBoundary) = nothing
_collect_boundary_field_dependencies!(fields, ::PeriodicBoundary) = nothing
_collect_boundary_field_dependencies!(fields, ::ExteriorBoundary) = nothing
_collect_boundary_field_dependencies!(fields, ::GhostBoundary) = nothing
function _collect_boundary_field_dependencies!(
        fields, policy::MaskedBoundary
    )
    _append_descriptor_once!(fields, policy.mask, :field)
    _collect_boundary_field_dependencies!(fields, policy.fallback)
    return nothing
end

function _collect_relation_dependencies!(fields, relations, relation::Relation)
    if relation.representation isa _ComposedRelation
        foreach(factor -> _collect_relation_dependencies!(
            fields, relations, factor), relation.representation.factors)
        _append_descriptor_once!(relations, relation, :relation)
        return nothing
    end
    _append_descriptor_once!(relations, relation, :relation) || return nothing
    representation = relation.representation
    if representation isa _ProductRelation
        foreach(
            factor -> _collect_relation_dependencies!(fields, relations, factor),
            representation.factors,
        )
    elseif representation isa _BoundaryRelation
        _collect_relation_dependencies!(fields, relations, representation.base)
        _collect_boundary_field_dependencies!(fields, representation.policy)
    elseif representation isa _MaskedRelation
        _collect_relation_dependencies!(fields, relations, representation.base)
        _append_descriptor_once!(fields, representation.mask, :field)
    elseif representation isa _SelectedRelation
        _collect_relation_dependencies!(fields, relations, representation.base)
        _collect_relation_dependencies!(
            fields, relations, representation.injection
        )
    elseif representation isa _FieldIndexRelation
        _append_descriptor_once!(fields, representation.keys, :field)
    end
    return nothing
end

function _required_descriptor_closure(
        required_fields::Tuple, required_relations::Tuple
    )
    field_values = Any[]
    relation_values = Any[]
    foreach(
        field -> _append_descriptor_once!(field_values, field, :field),
        required_fields,
    )
    foreach(
        relation -> _collect_relation_dependencies!(
            field_values, relation_values, relation
        ),
        required_relations,
    )
    return Tuple(field_values), Tuple(relation_values)
end

function _reject_required_duplicates(required::Tuple, role::Symbol)
    identities = map(semantic_identity, required)
    length(unique(identities)) == length(identities) || throw(
        LocalMathValidationError(
            "required descriptor identities must be unique";
            stage = :bind, contract = Symbol(role, :_required_identity),
            expected = :unique, actual = identities,
        )
    )
    return nothing
end


_binding_arrays(binding::_FieldStorageBinding) = Tuple(
    last(pair) for pair in _structural_physical_leaves(:field, binding.storage)
)
_relation_data_arrays(binding::_RelationStorageBinding) =
    binding.storage === nothing ? () : Tuple(
        last(pair) for pair in
        _structural_physical_leaves(:relation, binding.storage)
    )
_relation_generation_arrays(binding::_RelationStorageBinding) =
    binding.generation === nothing ? () : (binding.generation.generations,)
_relation_status_arrays(binding::_RelationStorageBinding) =
    binding.status === nothing ? () :
        binding.status.validated_generations === nothing ?
            (binding.status.statuses,) :
            (binding.status.statuses, binding.status.validated_generations)
_collection_arrays(binding::_CollectionStorageBinding) = Tuple(
    last(pair) for pair in _structural_physical_leaves(
        :collection, binding.storage
    )
)

function _might_alias(left, right)
    left === right && return true
    return try
        Base.mightalias(left, right)
    catch
        objectid(left) == objectid(right)
    end
end

function _any_alias(left::Tuple, right::Tuple)
    return any(a -> any(b -> _might_alias(a, b), right), left)
end

function _shared_packed_bank(left, right)
    left.relation.representation isa _PackedRelation &&
        right.relation.representation isa _PackedRelation || return false
    left.storage.active === right.storage.active &&
        left.storage.endpoints === right.storage.endpoints &&
        left.storage.offsets === right.storage.offsets &&
        left.storage.counts === right.storage.counts &&
        left.generation.generations === right.generation.generations &&
        left.status.statuses === right.status.statuses &&
        left.generation.slot != right.generation.slot &&
        left.status.slot != right.status.slot
end

function _validate_structural_aliases(
        fields::Tuple, relations::Tuple, collections::Tuple,
    )
    field_arrays = map(_binding_arrays, fields)
    relation_data = map(_relation_data_arrays, relations)
    relation_generation = map(_relation_generation_arrays, relations)
    relation_status = map(_relation_status_arrays, relations)
    collection_arrays = map(_collection_arrays, collections)

    for left in eachindex(fields), right in (left + 1):length(fields)
        _any_alias(field_arrays[left], field_arrays[right]) && throw(
            LocalMathValidationError(
                "distinct Fields cannot alias without an explicit law";
                stage = :bind, contract = :field_storage_alias,
                expected = :disjoint,
                actual = (
                    semantic_identity(fields[left].field),
                    semantic_identity(fields[right].field),
                ),
            )
        )
    end
    for field_index in eachindex(fields), relation_index in eachindex(relations)
        all_relation_arrays = (
            relation_data[relation_index]...,
            relation_generation[relation_index]...,
            relation_status[relation_index]...,
        )
        _any_alias(field_arrays[field_index], all_relation_arrays) && throw(
            LocalMathValidationError(
                "Field storage cannot alias relation or receipt storage";
                stage = :bind, contract = :field_relation_alias,
                expected = :disjoint,
                actual = (
                    semantic_identity(fields[field_index].field),
                    semantic_identity(relations[relation_index].relation),
                ),
            )
        )
    end
    for field_index in eachindex(fields), collection_index in eachindex(collections)
        _any_alias(field_arrays[field_index], collection_arrays[collection_index]) &&
            throw(LocalMathValidationError(
                "Field storage cannot alias Collection storage";
                stage = :bind, contract = :field_collection_alias,
                expected = :disjoint,
                actual = (
                    semantic_identity(fields[field_index].field),
                    semantic_identity(collections[collection_index].collection),
                ),
            ))
    end
    for relation_index in eachindex(relations), collection_index in eachindex(collections)
        relation_arrays = (
            relation_data[relation_index]...,
            relation_generation[relation_index]...,
            relation_status[relation_index]...,
        )
        _any_alias(relation_arrays, collection_arrays[collection_index]) &&
            throw(LocalMathValidationError(
                "Relation storage cannot alias Collection storage";
                stage = :bind, contract = :relation_collection_alias,
                expected = :disjoint,
                actual = (
                    semantic_identity(relations[relation_index].relation),
                    semantic_identity(collections[collection_index].collection),
                ),
            ))
    end
    for left in eachindex(collections), right in (left + 1):length(collections)
        _any_alias(collection_arrays[left], collection_arrays[right]) &&
            throw(LocalMathValidationError(
                "distinct Collections cannot alias storage";
                stage = :bind, contract = :collection_storage_alias,
                expected = :disjoint,
                actual = (
                    semantic_identity(collections[left].collection),
                    semantic_identity(collections[right].collection),
                ),
            ))
    end
    for left in eachindex(relations), right in (left + 1):length(relations)
        data_alias = _any_alias(relation_data[left], relation_data[right])
        generation_alias = _any_alias(
            relation_generation[left], relation_generation[right]
        )
        status_alias = _any_alias(
            relation_status[left], relation_status[right]
        )
        cross_alias = _any_alias(
            (relation_data[left]..., relation_generation[left]...,
             relation_status[left]...),
            (relation_data[right]..., relation_generation[right]...,
             relation_status[right]...),
        )
        cross_alias || continue
        data_alias && generation_alias && status_alias &&
            _shared_packed_bank(relations[left], relations[right]) && continue
        throw(LocalMathValidationError(
            "relation storage aliases without an admitted shared-bank law";
            stage = :bind, contract = :relation_storage_alias,
            expected = :disjoint_or_shared_packed_bank,
            actual = (
                semantic_identity(relations[left].relation),
                semantic_identity(relations[right].relation),
            ),
        ))
    end

    all_arrays = Any[]
    foreach(arrays -> append!(all_arrays, arrays), field_arrays)
    foreach(arrays -> append!(all_arrays, arrays), relation_data)
    foreach(arrays -> append!(all_arrays, arrays), relation_generation)
    foreach(arrays -> append!(all_arrays, arrays), relation_status)
    foreach(arrays -> append!(all_arrays, arrays), collection_arrays)
    if !isempty(all_arrays)
        device = _array_device_identity(first(all_arrays))
        all(array -> _array_device_identity(array) == device, all_arrays) ||
            throw(LocalMathValidationError(
                "structural bindings span devices or contexts";
                stage = :bind, contract = :structural_device_coherence,
                expected = device,
                actual = map(_array_device_identity, all_arrays),
            ))
    end
    return nothing
end

function _validate_binding_backend(binding, backend, role::Symbol)
    binding.storage === nothing && return nothing
    for (name, leaf) in _structural_physical_leaves(role, binding.storage)
        _validate_array_backend(leaf, backend, name)
    end
    return nothing
end


function _validate_binding_backend(
        binding::_RelationStorageBinding, backend, role::Symbol
    )
    if binding.storage !== nothing
        for (name, leaf) in _structural_physical_leaves(role, binding.storage)
            _validate_array_backend(leaf, backend, name)
        end
    end
    if binding.generation !== nothing
        _validate_array_backend(
            binding.generation.generations, backend, :relation_generation
        )
    end
    if binding.status !== nothing
        _validate_array_backend(
            binding.status.statuses, backend, :relation_status
        )
    end
    return nothing
end

Base.@nospecializeinfer Base.@noinline function _validate_structural_binding(
        required_fields::Tuple, required_relations::Tuple,
        required_collections::Tuple,
        binding::_StructuralBinding; backend = nothing,
    )
    Base.@nospecialize required_fields required_relations required_collections binding backend
    _reject_required_duplicates(required_fields, :field)
    _reject_required_duplicates(required_relations, :relation)
    _reject_required_duplicates(required_collections, :collection)
    closed_fields, closed_relations = _required_descriptor_closure(
        required_fields, required_relations
    )
    _reject_duplicate_identities(binding.fields, :field)
    _reject_duplicate_identities(binding.relations, :relation)
    _reject_cross_role_collisions(
        binding.fields, binding.relations, binding.collections,
    )
    _reject_unreferenced(closed_fields, binding.fields, :field)
    _reject_unreferenced(closed_relations, binding.relations, :relation)
    _reject_unreferenced(required_collections, binding.collections, :collection)
    field_values, relation_values, collection_values = Any[], Any[], Any[]
    sizehint!(field_values, length(closed_fields))
    sizehint!(relation_values, length(closed_relations))
    sizehint!(collection_values, length(required_collections))
    for field in closed_fields
        push!(field_values,
            _find_descriptor_binding(field, binding.fields, :field))
    end
    for relation in closed_relations
        push!(relation_values,
            _find_descriptor_binding(relation, binding.relations, :relation))
    end
    for collection in required_collections
        push!(collection_values,
            _find_descriptor_binding(collection, binding.collections, :collection))
    end
    fields = Tuple(field_values)
    relations = Tuple(relation_values)
    collections = Tuple(collection_values)
    _validate_structural_aliases(fields, relations, collections)
    if backend !== nothing
        foreach(entry -> _validate_binding_backend(entry, backend, :field), fields)
        foreach(entry -> _validate_binding_backend(entry, backend, :relation), relations)
        foreach(entry -> _validate_binding_backend(entry, backend, :collection), collections)
    end
    proofs = _validate_relation_bindings(relations)
    field_fact_values, collection_fact_values = Any[], Any[]
    sizehint!(field_fact_values, length(fields))
    sizehint!(collection_fact_values, length(collections))
    for field in fields
        push!(field_fact_values, _validate_field_binding(field))
    end
    for collection in collections
        push!(collection_fact_values, _validate_collection_binding(collection))
    end
    field_facts = Tuple(field_fact_values)
    collection_facts = Tuple(collection_fact_values)
    field_slots = ntuple(_FieldSlot, length(fields))
    relation_slots = ntuple(_RelationSlot, length(relations))
    collection_slots = ntuple(_CollectionSlot, length(collections))
    return _ValidatedStructuralBinding(
        _VALIDATED_BINDING_SEAL,
        binding, fields, relations, collections, proofs, field_facts,
        collection_facts, field_slots, relation_slots, collection_slots,
    )
end

_validate_structural_binding(
        required_fields::Tuple, required_relations::Tuple,
        binding::_StructuralBinding; backend = nothing,
    ) = _validate_structural_binding(
        required_fields, required_relations, (), binding; backend,
    )

@inline _field_binding(validated::_ValidatedStructuralBinding, slot::_FieldSlot) =
    @inbounds validated.fields[Int(slot.index)]
@inline _relation_binding(validated::_ValidatedStructuralBinding, slot::_RelationSlot) =
    @inbounds validated.relations[Int(slot.index)]
@inline _relation_proof(validated::_ValidatedStructuralBinding, slot::_RelationSlot) =
    @inbounds validated.proofs[Int(slot.index)]
@inline _collection_binding(
        validated::_ValidatedStructuralBinding, slot::_CollectionSlot) =
    @inbounds validated.collections[Int(slot.index)]
