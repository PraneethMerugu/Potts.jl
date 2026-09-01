@testset "spatial descriptor foundation" begin
    struct TestNode end
    struct TestEdge end
    struct TestLane end

    anonymous = LocalMath.Space((2, 3))
    @test size(anonymous) == (2, 3)
    @test length(LocalMath.Space(4)) == 4

    nodes = LocalMath.Space(TestNode, 7)
    same_shape = LocalMath.Space(TestNode, 7)
    restored = LocalMath.Space(
        TestNode, 7; id = LocalMath.semantic_identity(nodes)
    )
    conflicting = LocalMath.Space(
        TestNode, 6; id = LocalMath.semantic_identity(nodes)
    )
    edges = LocalMath.Space(TestEdge, 5)
    lanes = LocalMath._IndexSpace(3)

    @test size(nodes) == (7,)
    @test length(nodes) == 7
    @test LocalMath.space_kind(nodes) === TestNode
    @test nodes != same_shape
    @test nodes == restored
    @test nodes != conflicting
    @test typeof(nodes) === typeof(same_shape)
    @test typeof(nodes) === typeof(conflicting)

    position = LocalMath.Field(nodes, Float32)
    mask = LocalMath.Field(nodes, Bool)
    @test eltype(position) === Float32
    @test position.space == nodes
    @test !hasfield(typeof(position), :storage)
    @test typeof(position) === typeof(LocalMath.Field(nodes, Float32))
    @test_throws LocalMath.LocalMathValidationError LocalMath.Field(
        nodes, Symbol
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.Field(
        nodes, LocalMath.UUIDs.UUID
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.Field(
        nodes, Ptr{Cvoid}
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.Field(
        nodes, Base.RefValue{Int32}
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.Field(
        nodes, NamedTuple{(:label,),Tuple{Int32}}
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.Field(
        nodes, Val{1}
    )

    identity = LocalMath.IdentityRelation(nodes)
    lane_identity = LocalMath.IdentityRelation(lanes)
    affine = LocalMath.AffineRelation(
        nodes => nodes; offsets = ((-1,), (0,), (1,))
    )
    fixed = LocalMath.FixedRelation(edges => nodes; degree = 2)

    product_domain = LocalMath.Space((edges, lanes))
    product_codomain = LocalMath.Space((nodes, lanes))
    product = LocalMath.ProductRelation(
        product_domain => product_codomain, (fixed, lane_identity)
    )

    strict = LocalMath.BoundaryRelation(
        affine, LocalMath.StrictBoundary()
    )
    periodic = LocalMath.BoundaryRelation(
        affine, LocalMath.PeriodicBoundary((true,))
    )
    exterior = LocalMath.BoundaryRelation(
        affine, LocalMath.ExteriorBoundary()
    )
    boundary_mask = LocalMath.Field(nodes, Bool)
    masked_boundary = LocalMath.BoundaryRelation(
        affine,
        LocalMath.MaskedBoundary(
            boundary_mask, LocalMath.StrictBoundary()
        ),
    )
    ghost_space = LocalMath.Space(TestNode, 2)
    ghost = LocalMath.BoundaryRelation(
        affine,
        LocalMath.GhostBoundary((1,), (1,), ghost_space),
    )

    runtime = LocalMath.RuntimeRelation(
        edges => nodes;
        degree_bound = 4, key_type = UInt32,
        schema_epoch = 3,
    )
    scalar_keys = LocalMath.Field(edges, Int32)
    tuple_keys = LocalMath.Field(edges, Tuple{Int32,UInt32})
    indexed = LocalMath.IndexRelation(scalar_keys => nodes)
    optional_indexed = LocalMath.IndexRelation(
        tuple_keys => nodes; optional = true)
    masked = LocalMath.MaskedRelation(identity, mask)
    selected_space = LocalMath.Space(TestEdge, 3)
    injection = LocalMath.FixedRelation(
        selected_space => nodes; degree = 1
    )
    selected = LocalMath.SelectedRelation(identity, injection)
    inverse = LocalMath.InverseRelation(fixed; degree_bound = 5)
    packed = LocalMath.PackedRelation(
        nodes => edges;
        degree_bound = 6, capacity = 42,
        layout = :bounded_columns, schema_epoch = 8,
    )

    @test LocalMath.degree_bound(identity) == 1
    @test LocalMath.degree_bound(affine) == 3
    @test LocalMath.degree_bound(fixed) == 2
    @test LocalMath.degree_bound(product) == 2
    @test all(
        relation -> LocalMath.degree_bound(relation) == 3,
        (strict, periodic, exterior, masked_boundary, ghost),
    )
    @test LocalMath.degree_bound(runtime) == 4
    @test LocalMath.degree_bound(indexed) == 1
    @test LocalMath.degree_bound(optional_indexed) == 2
    @test LocalMath.domain(indexed) == edges
    @test LocalMath.codomain(indexed) == nodes
    @test LocalMath.degree_bound(masked) == 1
    @test LocalMath.degree_bound(selected) == 1
    @test LocalMath.domain(selected) == selected_space
    @test LocalMath.codomain(selected) == nodes
    @test LocalMath.degree_bound(inverse) == 5
    @test LocalMath.degree_bound(packed) == 6
    @test LocalMath.domain(inverse) == nodes
    @test LocalMath.codomain(inverse) == edges
    @test LocalMath.schema_epoch(runtime) == UInt64(3)
    @test LocalMath.schema_epoch(packed) == UInt64(8)
    large_epoch = LocalMath.IdentityRelation(
        nodes; schema_epoch = typemax(UInt64)
    )
    @test LocalMath.schema_epoch(large_epoch) == typemax(UInt64)

    # Ordinary counts and epochs remain values, not specialization keys.
    fixed_other = LocalMath.FixedRelation(edges => nodes; degree = 17)
    packed_other = LocalMath.PackedRelation(
        nodes => edges; degree_bound = 2, capacity = 900
    )
    @test typeof(fixed) === typeof(fixed_other)
    @test typeof(packed) === typeof(packed_other)
    @test typeof(runtime) === typeof(LocalMath.RuntimeRelation(
        edges => nodes;
        degree_bound = 9, key_type = UInt32,
        schema_epoch = 99,
    ))

    # Structural validation is now the sole package-owned proof minter;
    # callers still cannot construct a proof or validated evidence directly.
    @test isdefined(LocalMath, :_mint_relation_proof)
    @test_throws MethodError LocalMath.RelationProof()
    fresh_seal = LocalMath._RelationProofSeal()
    @test_throws ArgumentError LocalMath._ValidatedRelationEvidence(
        fresh_seal, (), (), (), (), ()
    )

    @test_throws LocalMath.LocalMathValidationError LocalMath.Space(
        TestNode, -1
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.Space(
        TestNode, (typemax(Int32), 2)
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.Field(
        nodes, Vector{Float32}
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.RuntimeRelation(
        edges => nodes;
        degree_bound = 1, key_type = Vector{Int32},
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.IndexRelation(
        LocalMath.Field(edges, Float32) => nodes)
    @test_throws LocalMath.LocalMathValidationError LocalMath.PackedRelation(
        nodes => edges;
        degree_bound = 2, capacity = 5, layout = :compressed_offsets,
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.FixedRelation(
        edges => nodes; degree = 0
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.SelectedRelation(
        identity, LocalMath.FixedRelation(edges => edges; degree = 1)
    )
    @test_throws LocalMath.LocalMathValidationError LocalMath.ProductRelation(
        product_domain => product_codomain, (lane_identity, fixed)
    )
end
