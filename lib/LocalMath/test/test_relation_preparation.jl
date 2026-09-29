using Test
import LocalMath
const LWRP = LocalMath

struct RPSource end
struct RPDestination end

function _rp_binding(fields, relation_pairs)
    relations = Tuple(first(pair) for pair in relation_pairs)
    bindings = Tuple(last(pair) for pair in relation_pairs)
    structural = LWRP._StructuralBinding(
        Tuple(LWRP._field_storage_binding(field, storage)
              for (field, storage) in fields),
        bindings,
    )
    return LWRP._validate_structural_binding(
        Tuple(first(pair) for pair in fields), relations, structural
    )
end

function _rp_prepare(validated, relation, destination; ghost = nothing)
    # Test-local stand-in for a Stage layout materialization: relation views
    # remain thin, while the stage owns Field freshness validation.
    foreach(slot -> LWRP._validated_field_binding(validated, slot),
        validated.field_slots)
    local_field = field -> begin
        index = findfirst(binding -> binding.field === field, validated.fields)
        index === nothing && error("test local Field is absent")
        LWRP._PreparedFieldSlot{index}()
    end
    local_relation = relation -> begin
        index = findfirst(binding -> binding.relation === relation, validated.relations)
        index === nothing && error("test local Relation is absent")
        validated.relation_slots[index]
    end
    slot = local_relation(relation)
    binding = LWRP._relation_binding(validated, slot)
    view = LWRP._prepare_relation_descriptor(
        validated, relation, local_field(destination),
        ghost === nothing ? nothing : local_field(ghost);
        field_slot_for = local_field, relation_slot_for = local_relation,
    )
    return LWRP._PreparedRelationUse(view, binding.generation, binding.status)
end

@testset "proof-derived stored relation preparation" begin
    source = LWRP.Space(RPSource, (4,))
    packed_source = LWRP.Space(RPSource, (2,))
    destination = LWRP.Space(RPDestination, (3,))
    source_field = LWRP.Field(source, Int32)
    destination_field = LWRP.Field(destination, Int32)

    identity = LWRP.IdentityRelation(source)
    fixed = LWRP.FixedRelation(source => destination; degree = 2)
    runtime = LWRP.RuntimeRelation(
        source => destination; degree_bound = 2,
        key_type = UInt32,
    )
    inverse = LWRP.InverseRelation(fixed; degree_bound = 2)
    packed = LWRP.PackedRelation(
        packed_source => destination; degree_bound = 2, capacity = 2
    )

    fixed_storage = (
        endpoints = Int32[1 2 3 1; 2 3 1 2],
        counts = fill(Int32(2), 4),
    )
    inverse_storage = (
        degrees = Int32[2, 1, 1],
        incidents = Int32[1 2 3; 4 0 0],
    )
    generations = UInt64[5]
    validated_generations = UInt64[5]
    statuses = Int32[0]
    generation = LWRP._RelationContentGenerationRef(generations, 1)
    status = LWRP._RelationStatusRef(statuses, validated_generations, 1)
    packed_storage = (
        active = Bool[true, true],
        endpoints = Int32[1 2; 2 3],
        offsets = Int32[1],
        counts = Int32[2],
    )
    validated = _rp_binding(
        ((source_field, zeros(Int32, 4)),
         (destination_field, zeros(Int32, 3))),
        (
            identity => LWRP._relation_storage_binding(identity),
            fixed => LWRP._relation_storage_binding(fixed, fixed_storage),
            runtime => LWRP._relation_storage_binding(runtime),
            inverse => LWRP._relation_storage_binding(inverse, inverse_storage),
            packed => LWRP._relation_storage_binding(
                packed, packed_storage; generation, status
            ),
        ),
    )

    identity_use = _rp_prepare(validated, identity, source_field)
    fixed_use = _rp_prepare(validated, fixed, destination_field)
    runtime_use = _rp_prepare(validated, runtime, destination_field)
    inverse_use = _rp_prepare(validated, inverse, source_field)
    packed_use = _rp_prepare(validated, packed, destination_field)

    reports = map((identity, fixed, runtime, inverse, packed)) do relation
        slot = LWRP._resolve_relation_slot(validated, relation)
        LWRP._relation_inspection(
            relation, LWRP._relation_proof(validated, slot))
    end
    @test map(report -> report.representation.family, reports) ==
        (:identity, :fixed, :runtime, :inverse, :packed)
    @test reports[1].footprint.strength === :exact
    @test reports[2].footprint.strength === :bounded
    @test reports[3].footprint.strength === :opaque
    @test reports[5].footprint.strength === :opaque
    @test all(report -> report.proof !== nothing, reports)

    @test identity_use.view isa LWRP._IdentityRelationView
    @test LWRP._relation_field_slot_index(
        LWRP._relation_endpoint(identity_use, 3, 1)
    ) == Int32(1)
    @test fixed_use.view.degree isa LWRP._StaticRelationDegree{2}
    @test LWRP._relation_endpoint(fixed_use, 1, 2).index == Int32(2)
    @test LWRP._relation_runtime_endpoint(runtime_use, UInt32(3)).index == Int32(3)
    @test LWRP._relation_endpoint(inverse_use, 1, 2).index == Int32(4)
    @test packed_use.view.active === packed_storage.active
    @test packed_use.view.endpoints === packed_storage.endpoints
    @test packed_use.generation === generation
    @test packed_use.status === status

    fixed_slot = LWRP._resolve_relation_slot(validated, fixed)
    fixed_binding = LWRP._relation_binding(validated, fixed_slot)
    substituted = LWRP._relation_storage_binding(
        fixed,
        (
            endpoints = copy(fixed_storage.endpoints),
            counts = fixed_storage.counts,
        );
        binding_id = fixed_binding.binding_id,
    )
    @test_throws LWRP.LocalMathValidationError begin
        LWRP._validate_relation_preparation_authority(
            substituted, LWRP._relation_proof(validated, fixed_slot)
        )
    end
end

@testset "computed composition and boundary preparation" begin
    space = LWRP.Space(RPSource, (4,))
    ghost_space = LWRP.Space(RPDestination, (2,))
    product_space = LWRP.Space((space, space))
    output = LWRP.Field(space, Int32)
    source_mask = LWRP.Field(space, Bool)
    boundary_mask = LWRP.Field(space, Bool)
    ghost_output = LWRP.Field(ghost_space, Int32)
    product_output = LWRP.Field(product_space, Int32)

    identity = LWRP.IdentityRelation(space)
    affine = LWRP.AffineRelation(
        space => space; offsets = ((-1,), (1,))
    )
    strict = LWRP.BoundaryRelation(affine, LWRP.StrictBoundary())
    periodic = LWRP.BoundaryRelation(
        affine, LWRP.PeriodicBoundary((true,))
    )
    exterior = LWRP.BoundaryRelation(
        affine, LWRP.ExteriorBoundary()
    )
    masked_boundary = LWRP.BoundaryRelation(
        affine, LWRP.MaskedBoundary(
            boundary_mask, LWRP.StrictBoundary()
        )
    )
    ghost = LWRP.BoundaryRelation(
        affine, LWRP.GhostBoundary((1,), (1,), ghost_space)
    )
    masked = LWRP.MaskedRelation(affine, source_mask)
    selected = LWRP.SelectedRelation(affine, identity)
    product = LWRP.ProductRelation(
        product_space => product_space, (identity, identity)
    )

    ghost_mapping = Int32[1, 0, 0, 0, 0, 2]
    ghost_storage = zeros(Int32, 2)
    relations = (
        identity, affine, strict, periodic, exterior, masked_boundary,
        ghost, masked, selected, product,
    )
    relation_bindings = Tuple(
        relation => LWRP._relation_storage_binding(
            relation,
            relation === ghost ? (mapping = ghost_mapping,) : nothing,
        ) for relation in relations
    )
    validated = _rp_binding(
        (
            (output, zeros(Int32, 4)),
            (source_mask, Bool[true, false, true, true]),
            (boundary_mask, Bool[true, true, false, true]),
            (ghost_output, ghost_storage),
            (product_output, zeros(Int32, 16)),
        ),
        relation_bindings,
    )
    prepared_fields = Tuple(binding.storage for binding in validated.fields)

    reports = map((affine, strict, product)) do relation
        slot = LWRP._resolve_relation_slot(validated, relation)
        LWRP._relation_inspection(
            relation, LWRP._relation_proof(validated, slot))
    end
    @test map(report -> report.representation.family, reports) ==
        (:affine, :boundary, :product)
    @test reports[1].footprint.strength === :exact
    @test reports[2].footprint.strength === :exact
    @test reports[2].footprint.offsets == ((-1,), (1,))
    @test reports[2].footprint.halos == (
        read=(lower=(1,), upper=(1,)),
        reverse_publication=(lower=(1,), upper=(1,)),
    )
    @test reports[3].footprint.strength === :bounded

    @test _rp_prepare(validated, affine, output).view.boundary isa
        LWRP._StrictRelationBoundary
    @test _rp_prepare(validated, strict, output).view.boundary isa
        LWRP._StrictRelationBoundary
    periodic_use = _rp_prepare(validated, periodic, output)
    @test LWRP._relation_endpoint(periodic_use, 1, 1).index == Int32(4)
    outside = LWRP._relation_endpoint(
        _rp_prepare(validated, exterior, output), 1, 1
    )
    @test outside.exterior && !outside.present
    masked_boundary_use = _rp_prepare(validated, masked_boundary, output)
    @test !LWRP._relation_participates(
        LWRP._relation_endpoint(masked_boundary_use, prepared_fields, 4, 1)
    )
    # A C2 stage is free to choose a compact local Field tuple order. Relation
    # preparation receives that cold resolver and embeds only typed local slots.
    local_masked_boundary = LWRP._prepare_relation_descriptor(
        validated, masked_boundary, LWRP._PreparedFieldSlot{2}();
        field_slot_for = field -> field === boundary_mask ?
            LWRP._PreparedFieldSlot{1}() : error("unexpected local Field"),
        relation_slot_for = relation -> begin
            index = findfirst(binding -> binding.relation === relation, validated.relations)
            index === nothing && error("unexpected local Relation")
            validated.relation_slots[index]
        end,
    )
    @test local_masked_boundary.boundary.mask_slot ===
        LWRP._PreparedFieldSlot{1}()
    @test !LWRP._relation_participates(
        LWRP._relation_endpoint(
            local_masked_boundary,
            (Bool[true, true, false, true],), 4, 1,
        )
    )
    ghost_use = _rp_prepare(
        validated, ghost, output; ghost = ghost_output
    )
    ghost_endpoint = LWRP._relation_endpoint(ghost_use, 1, 1)
    @test LWRP._relation_field_slot_index(ghost_endpoint) == Int32(4)
    @test ghost_endpoint.index == Int32(1)
    ghost_mapping[1] = Int32(999)
    @test !LWRP._relation_participates(
        LWRP._relation_endpoint(ghost_use, 1, 1)
    )
    ghost_mapping[1] = Int32(1)
    @test !LWRP._relation_participates(
        LWRP._relation_endpoint(
            _rp_prepare(validated, masked, output), prepared_fields, 2, 1
        )
    )
    @test LWRP._relation_endpoint(
        _rp_prepare(validated, selected, output), 2, 2
    ).index == Int32(3)
    product_use = _rp_prepare(validated, product, product_output)
    @test product_use.view isa LWRP._ProductRelationView
    @test LWRP._relation_endpoint(product_use, 16, 1).index == Int32(16)

    ghost_slot = LWRP._resolve_relation_slot(validated, ghost)
    ghost_binding = LWRP._relation_binding(validated, ghost_slot)
    substituted_ghost = LWRP._relation_storage_binding(
        ghost, (mapping = Int32[2, 0, 0, 0, 0, 2],);
        binding_id = ghost_binding.binding_id,
    )
    @test_throws LWRP.LocalMathValidationError begin
        LWRP._validate_relation_preparation_authority(
            substituted_ghost, LWRP._relation_proof(validated, ghost_slot)
        )
    end
    resize!(ghost_storage, 1)
    @test_throws LWRP.LocalMathValidationError begin
        _rp_prepare(validated, ghost, output; ghost = ghost_output)
    end
end

@testset "dynamic degree preparation remains array-backed" begin
    source = LWRP.Space(RPSource, (1,))
    destination = LWRP.Space(RPDestination, (1,))
    output = LWRP.Field(destination, Int32)
    dynamic = LWRP.FixedRelation(source => destination; degree = 40)
    endpoints = fill(Int32(1), 40, 1)
    validated = _rp_binding(
        ((output, zeros(Int32, 1)),),
        (dynamic => LWRP._relation_storage_binding(
            dynamic, (endpoints = endpoints,)
        ),),
    )
    use = _rp_prepare(validated, dynamic, output)
    @test use.view.degree isa LWRP._DynamicRelationDegree
    @test use.view.endpoints === endpoints
    @test LWRP._relation_endpoint(use, 1, 40).index == Int32(1)
end
