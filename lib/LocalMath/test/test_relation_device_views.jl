const LM = LocalMath

@testset "relation device-view foundation" begin
    static1 = LM._StaticRelationDegree(Val(1))
    static2 = LM._StaticRelationDegree(Val(2))
    dynamic40 = LM._DynamicRelationDegree(40)
    identity = LM._IdentityRelationView((2, 3), 3)
    @test LM._relation_domain_extent(identity) == (Int32(2), Int32(3))
    @test LM._relation_degree_bound(identity) == Int32(1)
    identity_endpoint = LM._relation_endpoint(identity, 5, 1)
    @test identity_endpoint.index == Int32(5)
    @test identity_endpoint.present && !identity_endpoint.exterior
    @test LM._relation_field_slot_index(identity_endpoint) == Int32(3)
    @test !LM._relation_participates(LM._relation_endpoint(identity, 7, 1))

    index = LM._IndexRelationView((2, 3), 3)
    @test LM._relation_coordinates(index, 5) == (Int32(1), Int32(3))
    @test LM._relation_index(index, (1, 3)) == Int32(5)

    offsets = ((1, 0), (-1, 0))
    strict = LM._AffineRelationView(
        (3, 2), (3, 2), offsets, LM._StrictRelationBoundary()
        , 4
    )
    @test LM._relation_endpoint(strict, 2, 1).index == Int32(3)
    @test !LM._relation_participates(LM._relation_endpoint(strict, 3, 1))

    periodic = LM._AffineRelationView(
        (3, 2), (3, 2), offsets,
        LM._PeriodicRelationBoundary((true, false)),
        4,
    )
    @test LM._relation_endpoint(periodic, 3, 1).index == Int32(1)

    exterior = LM._AffineRelationView(
        (3, 2), (3, 2), offsets, LM._ExteriorRelationBoundary(-1.0f0), 4
    )
    outside = LM._relation_endpoint(exterior, 3, 1)
    @test LM._relation_participates(outside)
    @test !outside.present && outside.exterior
    @test LM._relation_boundary_value(exterior.boundary) === -1.0f0

    ghost_indices = ntuple(index -> index == 5 ? Int32(7) : Int32(0), 10)
    ghost = LM._AffineRelationView(
        (3, 2), (3, 2), offsets,
        LM._GhostRelationBoundary(
            (3, 2), (1, 0), (1, 0), ghost_indices, 7, 9
        ),
        4,
    )
    @test LM._relation_endpoint(ghost, 3, 1).index == Int32(7)
    @test LM._relation_field_slot_index(
        LM._relation_endpoint(ghost, 3, 1)
    ) == Int32(9)
    @test LM._relation_field_slot_index(
        LM._relation_endpoint(ghost, 2, 1)
    ) == Int32(4)
    masked_ghost = LM._AffineRelationView(
        (3, 2), (3, 2), offsets,
        LM._MaskedRelationBoundary(LM._PreparedFieldSlot(1), ghost.boundary),
        4,
    )
    @test LM._relation_field_slot_index(
        LM._relation_endpoint(masked_ghost, (ntuple(_ -> false, 6),), 3, 1)
    ) == Int32(9)
    @test !LM._relation_participates(
        LM._relation_endpoint(masked_ghost, (ntuple(_ -> false, 6),), 2, 1)
    )

    masked = LM._AffineRelationView(
        (3, 2), (3, 2), ((0, 0),),
        LM._MaskedRelationBoundary(
            LM._PreparedFieldSlot(1), LM._StrictRelationBoundary(),
        ),
        4,
    )
    @test !LM._relation_participates(
        LM._relation_endpoint(
            masked, ((true, false, true, true, true, true),), 2, 1
        )
    )

    fixed = LM._FixedDegreeRelationView(
        static2, ((Int32(2), Int32(3)), (Int32(3), Int32(1))),
        (Int32(2), Int32(1)), (2,), 3, 5,
    )
    @test LM._relation_endpoint(fixed, 1, 2).index == Int32(3)
    @test !LM._relation_participates(LM._relation_endpoint(fixed, 2, 2))

    product = LM._ProductRelationView((
        LM._IdentityRelationView((2,), 1), LM._IdentityRelationView((3,), 2),
    ), 6)
    @test LM._relation_domain_extent(product) == (Int32(6),)
    @test LM._relation_endpoint(product, 5, 1).index == Int32(5)

    prefix_injection = LM._PrefixInjectionRelationView(Int32(2), 2, 4, 2)
    prefix = LM._SelectedRelationView(
        LM._IdentityRelationView((4,), 7), prefix_injection,
    )
    @test LM._relation_endpoint(prefix, 2, 1).index == Int32(2)
    @test !LM._relation_participates(LM._relation_endpoint(prefix, 3, 1))
    @test LM._relation_domain_extent(prefix) == (Int32(2),)

    index_injection = LM._IndexInjectionRelationView(
        (Int32(4), Int32(2)), Int32(2), 2, 4, 2
    )
    indexed = LM._SelectedRelationView(
        LM._IdentityRelationView((4,), 7), index_injection,
    )
    @test LM._relation_endpoint(indexed, 1, 1).index == Int32(4)
    short_injection = LM._IndexInjectionRelationView(
        (Int32(4),), Int32(2), 2, 4, 2
    )
    @test !LM._relation_participates(
        LM._relation_endpoint(short_injection, 2, 1)
    )

    source_mask = LM._SourceMaskRelationView(
        LM._IdentityRelationView((4,), 7), LM._PreparedFieldSlot(1)
    )
    @test LM._relation_domain_extent(source_mask) == (Int32(4),)
    @test !LM._relation_participates(
        LM._relation_endpoint(source_mask, ((true, false, true, true),), 2, 1)
    )

    packed = LM._PackedIncidenceRelationView(
        static2, (true, false, true),
        ((Int32(2), Int32(4), Int32(3)),
         (Int32(5), Int32(1), Int32(6))),
        (Int32(1),), (Int32(3),), (UInt64(7),), 1, 6, 3, 8,
    )
    @test LM._relation_endpoint(packed, 1, 2).index == Int32(5)
    @test !LM._relation_participates(LM._relation_endpoint(packed, 2, 1))
    @test LM._relation_content_generation(packed) == UInt64(7)
    unsafe_packed = LM._PackedIncidenceRelationView(
        static1, (true,), ((Int32(1),),), (Int32(9),), (Int32(1),),
        (UInt64(1),), 1, 1, 1, 8,
    )
    @test !LM._relation_participates(LM._relation_endpoint(unsafe_packed, 1, 1))

    inverse = LM._InverseRelationView(
        static2, (Int32(2), Int32(1)),
        ((Int32(3), Int32(2)), (Int32(1), Int32(0))), (2,), 3, 9,
    )
    @test LM._relation_endpoint(inverse, 1, 2).index == Int32(1)
    @test !LM._relation_participates(LM._relation_endpoint(inverse, 2, 2))

    grouped_inverse = LM._GroupedInverseRelationView(
        static2, (Int32(1), Int32(3), Int32(4)),
        (Int32(3), Int32(1), Int32(2)), (2,), 3, 9,
    )
    @test LM._relation_endpoint(grouped_inverse, 1, 2).index == Int32(1)
    @test LM._relation_endpoint(grouped_inverse, 2, 1).index == Int32(2)

    keyed = LM._RuntimeKeyRelationView(static1, (4,), 6, 10)
    @test LM._relation_runtime_endpoint(keyed, Int32(6)).index == Int32(6)
    @test LM._relation_field_slot_index(
        LM._relation_runtime_endpoint(keyed, UInt32(6))
    ) == Int32(10)
    @test !LM._relation_participates(
        LM._relation_runtime_endpoint(keyed, Int32(0))
    )
    @test_throws MethodError LM._relation_runtime_endpoint(keyed, Int64(1))

    dynamic_endpoints = fill(Int32(1), 40, 1)
    dynamic_fixed = LM._FixedDegreeRelationView(
        dynamic40, dynamic_endpoints, nothing, (1,), 1, 11
    )
    @test LM._relation_degree_bound(dynamic_fixed) == Int32(40)
    @test LM._relation_field_slot_index(
        LM._relation_endpoint(dynamic_fixed, 1, 40)
    ) == Int32(11)
    dynamic_packed = LM._PackedIncidenceRelationView(
        dynamic40, (true,), dynamic_endpoints, (Int32(1),), (Int32(1),),
        (UInt64(2),), 1, 1, 1, 12,
    )
    @test LM._relation_endpoint(dynamic_packed, 1, 40).index == Int32(1)
    dynamic_inverse = LM._InverseRelationView(
        dynamic40, (Int32(40),), dynamic_endpoints, (1,), 1, 13
    )
    @test LM._relation_field_slot_index(
        LM._relation_endpoint(dynamic_inverse, 1, 40)
    ) == Int32(13)
    dynamic_keyed = LM._RuntimeKeyRelationView(dynamic40, (1,), 1, 14)
    @test LM._relation_degree_bound(dynamic_keyed) == Int32(40)

    schema = LM._RelationSchemaFacts(
        UInt128(0x1), UInt64(3), UInt64(0x4), (Int32(4),),
        (Int32(6),), ((Int32(-1),), (Int32(1),)),
    )
    generation = LM._RelationContentGenerationRef((UInt64(9),), Int32(1))
    status = LM._RelationStatusRef(
        (Int32(0),), (UInt64(9),), Int32(1))

    @test_throws LM.LocalMathValidationError LM._IdentityRelationView((-1,), 1)
    @test_throws LM.LocalMathValidationError LM._StaticRelationDegree(
        Val(LM._MAX_STATIC_COMPOSED_RELATION_DEGREE + 1))
    @test_throws LM.LocalMathValidationError LM._DynamicRelationDegree(32)
    @test_throws LM.LocalMathValidationError LM._GhostRelationBoundary(
        (3, 2), (1, 0), (1, 0), ntuple(_ -> Int32(0), 9), 1, 2
    )
    @test_throws LM.LocalMathValidationError LM._GhostRelationBoundary(
        (1,), (1,), (1,), (Int32(0), Int32(2), Int32(0)), 1, 2
    )
    @test_throws LM.LocalMathValidationError LM._RuntimeKeyRelationView(
        static1, (1,), typemax(Int64), 1
    )
    @test_throws LM.LocalMathValidationError LM._SelectedRelationView(
        LM._IdentityRelationView((4,), 1),
        LM._PrefixInjectionRelationView(Int32(2), 2, 3, 1),
    )

    for view in (
            identity, index, strict, periodic, exterior, ghost, masked_ghost,
            masked, fixed,
            product, prefix_injection, prefix, index_injection, indexed,
            source_mask, packed, inverse, grouped_inverse, keyed, schema,
            generation, status,
        )
        @test isbitstype(typeof(view))
    end
    for view in (dynamic_fixed, dynamic_packed, dynamic_inverse, dynamic_keyed)
        @test isconcretetype(typeof(view))
    end

    # A relation view owns no global binding/storage index. Its only Field
    # identity is a typed stage-local tuple ordinal, and tuple lookup remains
    # concrete for the kernel compiler.
    local_fields = (Int32[1, 2], Float32[3, 4])
    local_slot = LM._PreparedFieldSlot{2}()
    @test @inferred(LM._prepared_stage_field(local_fields, local_slot)) ===
        local_fields[2]
    @test isbitstype(typeof(local_slot))
    @test :storage_slot ∉ fieldnames(typeof(identity))
    @test fieldtype(typeof(identity), :field_slot) === LM._PreparedFieldSlot{3}
end
