# Proof-derived, backend-neutral preparation of structural relation bindings.
# This is the only descriptor/binding -> executable relation-view bridge.

struct _PreparedRelationUse{V,G,S}
    view::V
    generation::G
    status::S
end
Adapt.@adapt_structure _PreparedRelationUse

@inline _relation_domain_extent(use::_PreparedRelationUse) =
    _relation_domain_extent(getfield(use, :view))
@inline _relation_codomain_extent(use::_PreparedRelationUse) =
    _relation_codomain_extent(getfield(use, :view))
@inline _relation_degree_bound(use::_PreparedRelationUse) =
    _relation_degree_bound(getfield(use, :view))
@inline _relation_keys_valid(use::_PreparedRelationUse,
    fields::Tuple, item::Integer) =
    _relation_keys_valid(getfield(use, :view), fields, item)
@inline _relation_endpoint(use::_PreparedRelationUse, item, lane) =
    _relation_endpoint(getfield(use, :view), item, lane)
@inline _relation_endpoint(
        use::_PreparedRelationUse, fields::Tuple, item::Integer,
    ) = _relation_endpoint(use, fields, item, 1)
@inline _relation_endpoint(
        use::_PreparedRelationUse, fields::Tuple,
        item::Integer, lane::Integer,
    ) =
    _relation_endpoint(getfield(use, :view), fields, item, lane)
@inline _relation_runtime_endpoint(use::_PreparedRelationUse, key) =
    _relation_runtime_endpoint(getfield(use, :view), key)
@inline _relation_runtime_endpoint(
        use::_PreparedRelationUse, fields::Tuple, key::Union{Int32,UInt32},
    ) = _relation_runtime_endpoint(getfield(use, :view), fields, key)
@inline function _relation_content_generation(
        use::_PreparedRelationUse{V,G,S}
    ) where {V,G<:_RelationContentGenerationRef,S}
    return _relation_content_generation(use.generation)
end
@inline function _relation_content_status(
        use::_PreparedRelationUse{V,G,S}
    ) where {V,G,S<:_RelationStatusRef}
    return _relation_content_status(use.status)
end

function _validated_field_binding(
        validated::_ValidatedStructuralBinding, slot::_FieldSlot,
    )
    binding = _field_binding(validated, slot)
    current = _structural_leaf_facts(binding.storage, :field)
    expected = @inbounds validated.field_facts[Int(slot.index)]
    current == expected || throw(LocalMathValidationError(
        "Field physical leaf schema changed after structural validation";
        stage = :prepare, contract = :field_preparation_authority,
        expected, actual = current,
    ))
    return binding
end

function _prepared_relation_degree(bound::Integer)
    checked = _checked_relation_view_int32(
        bound, :prepared_relation_degree; positive = true
    )
    return checked <= 32 ? _StaticRelationDegree(Val(Int(checked))) :
        _DynamicRelationDegree(checked)
end

function _require_dynamic_relation_arrays(degree, storage, family::Symbol)
    degree isa _DynamicRelationDegree && storage isa Tuple && throw(
        LocalMathValidationError(
            "a dynamic-degree relation requires array-backed lane storage";
            stage = :prepare, contract = :dynamic_relation_storage,
            expected = :array_backed, actual = (family, typeof(storage)),
        ))
    return nothing
end

function _validate_relation_preparation_authority(
        binding::_RelationStorageBinding, proof::RelationProof
    )
    relation = binding.relation
    proof.relation_id == semantic_identity(relation) &&
        proof.domain_id == semantic_identity(domain(relation)) &&
        proof.codomain_id == semantic_identity(codomain(relation)) &&
        proof.schema_epoch == schema_epoch(relation) || throw(
        LocalMathValidationError(
            "relation proof no longer matches its descriptor";
            stage = :prepare, contract = :relation_proof_schema,
            expected = semantic_identity(relation), actual = proof.relation_id,
        ))
    proof.binding_schema.binding_id == binding.binding_id || throw(
        LocalMathValidationError(
            "relation proof no longer matches its physical binding";
            stage = :prepare, contract = :relation_proof_binding,
            expected = binding.binding_id,
            actual = proof.binding_schema.binding_id,
        ))
    current_representation = _relation_representation_facts(relation, binding)
    current_representation == proof.binding_schema.representation || throw(
        LocalMathValidationError(
            "relation representation facts changed after proof validation";
            stage = :prepare, contract = :relation_proof_representation,
            expected = proof.binding_schema.representation,
            actual = current_representation,
        ))
    typeof(binding.ownership) === typeof(proof.binding_schema.ownership) &&
        isequal(binding.ownership, proof.binding_schema.ownership) || throw(
        LocalMathValidationError(
            "relation ownership changed after proof validation";
            stage = :prepare, contract = :relation_proof_ownership,
            expected = proof.binding_schema.ownership,
            actual = binding.ownership,
        ))
    current_leaf_facts = _relation_binding_leaf_facts(binding)
    current_leaf_facts == proof.binding_schema.physical_leaves || throw(
        LocalMathValidationError(
            "relation physical leaf schema changed after proof validation";
            stage = :prepare, contract = :relation_proof_physical_leaves,
            expected = proof.binding_schema.physical_leaves,
            actual = current_leaf_facts,
        ))
    proof.evidence.bounds.degree == degree_bound(relation) &&
        proof.evidence.bounds.domain_count == length(domain(relation)) &&
        proof.evidence.bounds.codomain_count == length(codomain(relation)) ||
        throw(LocalMathValidationError(
            "relation proof bounds changed before preparation";
            stage = :prepare, contract = :relation_proof_bounds,
            expected = (
                degree_bound(relation), length(domain(relation)),
                length(codomain(relation)),
            ),
            actual = proof.evidence.bounds,
        ))
    return nothing
end

function _relation_schema_facts(
        binding::_RelationStorageBinding, proof::RelationProof
    )
    relation = binding.relation
    _validate_relation_preparation_authority(binding, proof)
    return _RelationSchemaFacts(
        semantic_identity(relation), schema_epoch(relation), binding.binding_id,
        ntuple(
            axis -> Int32(size(domain(relation))[axis]),
            length(size(domain(relation))),
        ),
        ntuple(
            axis -> Int32(size(codomain(relation))[axis]),
            length(size(codomain(relation))),
        ),
        proof.evidence.footprint,
    )
end

function _prepare_relation_descriptor(
        validated::_ValidatedStructuralBinding, relation::Relation,
        destination_slot::_PreparedFieldSlot, ghost_destination = nothing;
        field_slot_for, relation_slot_for,
    )
    slot = relation_slot_for(relation)
    binding = _relation_binding(validated, slot)
    proof = _relation_proof(validated, slot)
    _validate_relation_preparation_authority(binding, proof)
    return _prepare_relation_view(
        validated, binding, proof,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
end

function _prepare_relation_view(
        validated, binding::_RelationStorageBinding,
        proof::RelationProof, destination_slot::_PreparedFieldSlot,
        ghost_destination, field_slot_for, relation_slot_for,
    )
    return _prepare_relation_representation(
        validated, binding, proof, binding.relation.representation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
end

function _prepare_relation_representation(
        validated, binding, proof, ::_IdentityRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    extent = size(domain(binding.relation))
    if space_kind(domain(binding.relation)) === _IndexSpaceKind
        return _IndexRelationView(extent, destination_slot)
    end
    return _IdentityRelationView(extent, destination_slot)
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_AffineRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    relation = binding.relation
    offsets = map(representation.offsets) do offset
        ntuple(axis -> offset[axis] + representation.origin[axis],
            length(offset))
    end
    return _AffineRelationView(
        size(domain(relation)), size(codomain(relation)),
        offsets, _StrictRelationBoundary(), destination_slot,
    )
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_FixedRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    storage = binding.storage
    degree = _prepared_relation_degree(representation.degree)
    _require_dynamic_relation_arrays(degree, storage.endpoints, :fixed)
    counts = hasproperty(storage, :counts) ? storage.counts : nothing
    return _FixedDegreeRelationView(
        degree, storage.endpoints, counts, size(domain(binding.relation)),
        length(codomain(binding.relation)), destination_slot,
    )
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_FieldIndexRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    return _field_index_relation_view(
        _prepared_relation_degree(representation.degree),
        size(domain(binding.relation)), size(codomain(binding.relation)),
        field_slot_for(representation.keys), destination_slot,
        representation.optional,
    )
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_ProductRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    factors = map(representation.factors) do factor
        _prepare_relation_descriptor(
            validated, factor, destination_slot;
            field_slot_for = field_slot_for,
            relation_slot_for = relation_slot_for,
        )
    end
    return _ProductRelationView(factors, destination_slot)
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_ComposedRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    factors = map(representation.factors) do factor
        _prepare_relation_descriptor(
            validated, factor, destination_slot;
            field_slot_for = field_slot_for,
            relation_slot_for = relation_slot_for,
        )
    end
    return _ComposedRelationView(factors, destination_slot)
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_BoundaryRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    base = representation.base
    policy = _prepare_boundary_view(
        validated, binding, proof, representation.policy, base,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    offsets = map(base.representation.offsets) do offset
        ntuple(axis -> offset[axis] + base.representation.origin[axis],
            length(offset))
    end
    return _AffineRelationView(
        size(domain(base)), size(codomain(base)),
        offsets, policy, destination_slot,
    )
end

_prepare_boundary_view(
    validated, binding, proof, ::StrictBoundary, base,
    destination_slot, ghost_destination, field_slot_for, relation_slot_for,
) = _StrictRelationBoundary()

_prepare_boundary_view(
    validated, binding, proof, policy::PeriodicBoundary, base,
    destination_slot, ghost_destination, field_slot_for, relation_slot_for,
) = _PeriodicRelationBoundary(policy.axes)

_prepare_boundary_view(
    validated, binding, proof, ::ExteriorBoundary, base,
    destination_slot, ghost_destination, field_slot_for, relation_slot_for,
) = _ExteriorRelationBoundary(nothing)

function _prepare_boundary_view(
        validated, binding, proof, policy::MaskedBoundary, base,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    mask_slot = field_slot_for(policy.mask)
    fallback = _prepare_boundary_view(
        validated, binding, proof, policy.fallback, base,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    return _MaskedRelationBoundary(mask_slot, fallback)
end

function _prepare_boundary_view(
        validated, binding, proof, policy::GhostBoundary, base,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    ghost_destination isa _PreparedFieldSlot || throw(LocalMathValidationError(
        "a ghost boundary use requires a resolved ghost destination Field";
        stage = :prepare, contract = :ghost_relation_destination,
        expected = _PreparedFieldSlot, actual = typeof(ghost_destination),
    ))
    # The cold Stage projection proves that this local slot denotes a Field on
    # `policy.ghost_space` before calling this bridge.  A local slot is
    # intentionally not invertible back into a global structural binding.
    return _GhostRelationBoundary(
        proof,
        ntuple(
            axis -> Int32(size(codomain(base))[axis]),
            length(size(codomain(base))),
        ),
        ntuple(axis -> Int32(policy.lower[axis]), length(policy.lower)),
        ntuple(axis -> Int32(policy.upper[axis]), length(policy.upper)),
        binding.storage.mapping, Int32(length(policy.ghost_space)),
        ghost_destination,
    )
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_MaskedRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    base = _prepare_relation_descriptor(
        validated, representation.base, destination_slot, ghost_destination;
        field_slot_for = field_slot_for,
        relation_slot_for = relation_slot_for,
    )
    mask_slot = field_slot_for(representation.mask)
    return _SourceMaskRelationView(base, mask_slot)
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_SelectedRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    base = _prepare_relation_descriptor(
        validated, representation.base, destination_slot, ghost_destination;
        field_slot_for = field_slot_for,
        relation_slot_for = relation_slot_for,
    )
    injection = _prepare_relation_descriptor(
        validated, representation.injection, destination_slot;
        field_slot_for = field_slot_for,
        relation_slot_for = relation_slot_for,
    )
    return _SelectedRelationView(base, injection)
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_InverseRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    storage = binding.storage
    degree = _prepared_relation_degree(representation.degree)
    _require_dynamic_relation_arrays(degree, storage.incidents, :inverse)
    if hasproperty(storage, :degrees)
        return _InverseRelationView(
            degree, storage.degrees, storage.incidents,
            size(domain(binding.relation)), length(codomain(binding.relation)),
            destination_slot,
        )
    end
    return _GroupedInverseRelationView(
        degree, storage.offsets, storage.incidents,
        size(domain(binding.relation)), length(codomain(binding.relation)),
        destination_slot,
    )
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_PackedRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    storage = binding.storage
    degree = _prepared_relation_degree(representation.degree)
    _require_dynamic_relation_arrays(degree, storage.endpoints, :packed)
    generation = binding.generation
    return _PackedIncidenceRelationView(
        degree, storage.active, storage.endpoints, storage.offsets,
        storage.counts, generation.generations, generation.slot,
        length(codomain(binding.relation)), representation.capacity,
        destination_slot,
    )
end

function _prepare_relation_representation(
        validated, binding, proof, representation::_RuntimeRelation,
        destination_slot, ghost_destination, field_slot_for, relation_slot_for,
    )
    return _RuntimeKeyRelationView(
        _prepared_relation_degree(representation.degree),
        size(domain(binding.relation)), length(codomain(binding.relation)),
        destination_slot,
    )
end
