using Test
import LocalMath
const LMB = LocalMath

struct SBSource end
struct SBDestination end

@testset "structural binding and sealed relation proof" begin
    source = LMB.Space(SBSource, (4,))
    destination = LMB.Space(SBDestination, (3,))
    values = LMB.Field(source, Int32)
    output = LMB.Field(destination, Float32)
    identity = LMB.IdentityRelation(source)
    fixed = LMB.FixedRelation(source => destination; degree = 2)

    value_storage = Int32[1, 2, 3, 4]
    output_storage = zeros(Float32, 3)
    endpoints = Int32[1 2 3 1; 2 3 1 2]
    counts = fill(Int32(2), 4)

    fields = (
        LMB._field_storage_binding(output, output_storage),
        LMB._field_storage_binding(values, value_storage),
    )
    relations = (
        LMB._relation_storage_binding(
            fixed, (endpoints = endpoints, counts = counts)
        ),
        LMB._relation_storage_binding(identity),
    )
    binding = LMB._StructuralBinding(fields, relations)
    validated = LMB._validate_structural_binding(
        (values, output), (identity, fixed), binding
    )

    @test LMB._field_binding(validated, LMB._FieldSlot(1)).field == values
    @test LMB._field_binding(validated, LMB._FieldSlot(2)).field == output
    @test LMB._relation_binding(
        validated, LMB._RelationSlot(1)
    ).relation == identity
    @test LMB._relation_proof(
        validated, LMB._RelationSlot(2)
    ).relation_id == LMB.semantic_identity(fixed)
    @test LMB._resolve_field_slot(validated, output) == LMB._FieldSlot(2)
    @test LMB._resolve_relation_slot(validated, fixed) == LMB._RelationSlot(2)
    for (constructor, role) in (
            (LMB._FieldSlot, :field),
            (LMB._RelationSlot, :relation),
            (LMB._CollectionSlot, :collection))
        @test constructor(1).index == Int32(1)
        for invalid in (false, 0, Int64(typemax(Int32)) + 1)
            error = try
                constructor(invalid)
                nothing
            catch caught
                caught
            end
            @test error isa LMB.LocalMathValidationError
            @test error.contract == Symbol(role, :_slot_ordinal)
            @test error.expected == 1:typemax(Int32)
            @test error.actual == invalid
        end
    end
    @test length(validated.proofs) == 2
    @test_throws ArgumentError LMB._ValidatedStructuralBinding(
        LMB._ValidatedBindingSeal(),
        binding, validated.fields, validated.relations, validated.collections,
        validated.proofs, validated.field_facts, validated.collection_facts,
        validated.field_slots, validated.relation_slots,
        validated.collection_slots,
    )
    @test count(
        contains("RelationProof("),
        readlines(joinpath(@__DIR__, "../src/structural_binding.jl")),
    ) == 1

    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (values,), (identity, fixed), binding
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (values, output), (identity, identity), binding
    )

    conflicting = LMB.Field(
        LMB.Space(SBSource, (3,); id = source.id), Int32; id = values.id
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (conflicting, output), (identity, fixed), binding
    )

    aliased = LMB._StructuralBinding(
        (
            LMB._field_storage_binding(values, value_storage),
            LMB._field_storage_binding(
                LMB.Field(source, Int32), value_storage
            ),
        ),
        (),
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        Tuple(entry.field for entry in aliased.fields), (), aliased
    )

    too_few_lanes = LMB._StructuralBinding(
        fields,
        (
            LMB._relation_storage_binding(
                fixed, (endpoints = reshape(Int32[1, 2, 3, 1], 1, 4),)
            ),
            LMB._relation_storage_binding(identity),
        ),
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (values, output), (identity, fixed), too_few_lanes
    )

    tuple_fixed = LMB._relation_storage_binding(
        fixed,
        (
            endpoints = (
                Int32[1, 2, 3, 1], Int32[2, 3, 1, 2]
            ),
            counts = nothing,
        ),
    )
    tuple_validated = LMB._validate_structural_binding(
        (values, output), (fixed,),
        LMB._StructuralBinding(fields, (tuple_fixed,))
    )
    @test length(tuple_validated.proofs[1].binding_schema.physical_leaves) == 2

    affine = LMB.AffineRelation(
        destination => destination; offsets = ((-1,), (1,))
    )
    ghosts = LMB.Space(SBSource, (2,))
    ghost = LMB.BoundaryRelation(
        affine, LMB.GhostBoundary((1,), (1,), ghosts)
    )
    ghost_binding = LMB._StructuralBinding(
        (), (
            LMB._relation_storage_binding(
                ghost, (mapping = Int32[1, 0, 0, 0, 2],),
            ),
            LMB._relation_storage_binding(affine),
        )
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (), (ghost,), LMB._StructuralBinding((), (ghost_binding.relations[1],))
    )
    ghost_validated = LMB._validate_structural_binding(
        (), (ghost,), ghost_binding
    )
    @test LMB._relation_proof(
        ghost_validated, LMB._RelationSlot(1)
    ).evidence.bounds.content_validation === :immutable_host_borrow

    alias_parent = Int32[1, 2, 3, 4, 5, 6]
    left_field = LMB.Field(source, Int32)
    right_field = LMB.Field(source, Int32)
    overlapping = LMB._StructuralBinding((
        LMB._field_storage_binding(left_field, @view(alias_parent[1:4])),
        LMB._field_storage_binding(right_field, @view(alias_parent[3:6])),
    ), ())
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (left_field, right_field), (), overlapping
    )

    alias_relation = LMB.FixedRelation(source => destination; degree = 1)
    field_relation_alias = LMB._StructuralBinding(
        (LMB._field_storage_binding(
            left_field, @view(alias_parent[1:4])
        ),),
        (LMB._relation_storage_binding(
            alias_relation,
            (endpoints = (@view(alias_parent[1:4]),), counts = nothing),
        ),),
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (left_field,), (alias_relation,), field_relation_alias
    )
end

@testset "fixed and inverse content authority" begin
    source = LMB.Space(SBSource, 3)
    destination = LMB.Space(SBDestination, 2)
    fixed = LMB.FixedRelation(source => destination; degree = 2)

    invalid_count = LMB._relation_storage_binding(fixed, (
        endpoints = Int32[1 1 2; 2 2 1],
        counts = Int32[2, 3, 1],
    ))
    @test_throws LMB.LocalMathValidationError begin
        LMB._validate_relation_binding(invalid_count)
    end

    invalid_endpoint = LMB._relation_storage_binding(fixed, (
        endpoints = Int32[1 1 3; 2 2 1],
        counts = Int32[2, 2, 1],
    ))
    @test_throws LMB.LocalMathValidationError begin
        LMB._validate_relation_binding(invalid_endpoint)
    end

    inverse = LMB.InverseRelation(fixed; degree_bound = 2)
    invalid_degree = LMB._relation_storage_binding(inverse, (
        degrees = Int32[3, 1],
        incidents = Int32[1 2; 3 0],
    ))
    @test_throws LMB.LocalMathValidationError begin
        LMB._validate_relation_binding(invalid_degree)
    end

    invalid_offsets = LMB._relation_storage_binding(inverse, (
        offsets = Int32[1, 4, 3], incidents = Int32[1, 2, 3],
    ))
    @test_throws LMB.LocalMathValidationError begin
        LMB._validate_relation_binding(invalid_offsets)
    end

    valid = LMB._relation_storage_binding(fixed, (
        endpoints = Int32[1 1 2; 2 2 1], counts = Int32[2, 2, 1],
    ))
    proof = LMB._validate_relation_binding(valid)
    @test proof.evidence.bounds.content_validation === :immutable_host_borrow
end

@testset "ghost mapping content authority" begin
    interior = LMB.Space(SBSource, (4,))
    ghost_space = LMB.Space(SBDestination, (2,))
    base = LMB.AffineRelation(
        interior => interior; offsets = ((-1,), (1,)))
    ghost = LMB.BoundaryRelation(base,
        LMB.GhostBoundary((1,), (1,), ghost_space))

    @test_throws LMB.LocalMathValidationError LMB._validate_relation_binding(
        LMB._relation_storage_binding(
            ghost, (mapping = Int32[1, 0, 0, 0, 0, 3],)))

    mapping = Int32[1, 0, 0, 0, 0, 2]
    binding = LMB._relation_storage_binding(ghost, (mapping = mapping,))
    proof = LMB._validate_relation_binding(binding)
    @test proof.evidence.bounds.content_validation === :immutable_host_borrow

    generation = LMB._RelationContentGenerationRef(UInt64[1], 1)
    status = LMB._RelationStatusRef(Int32[0], UInt64[0], 1)
    dynamic = LMB._relation_storage_binding(
        ghost, (mapping = Int32[1, 0, 0, 0, 0, 2],);
        generation, status)
    dynamic_proof = LMB._validate_relation_binding(dynamic)
    @test dynamic_proof.evidence.bounds.content_validation ===
        :device_content_validation_required
end

@testset "parameter schema composition" begin
    count = LMB.Parameter(
        :count, Int32; bounds = LMB._ClosedParameterBounds(Int32(0), Int32(8))
    )
    flag = LMB.Parameter(:flag, Bool)
    schema = LMB._merge_parameter_schemas((
        LMB.ParameterSchema(count),
        LMB.ParameterSchema(flag, count),
    ))
    @test map(entry -> entry.name, schema.declarations) == (:count, :flag)
    @test LMB._parameter_type(schema.declarations[1]) === Int32
    mismatch = LMB.Parameter(
        :count, Int32; bounds = LMB._ClosedParameterBounds(Int32(0), Int32(7))
    )
    @test_throws LMB.LocalMathValidationError LMB._merge_parameter_schemas((
        LMB.ParameterSchema(count), LMB.ParameterSchema(mismatch)
    ))
end

@testset "packed relation receipts remain device references" begin
    domain = LMB.Space(SBSource, (2,))
    codomain = LMB.Space(SBDestination, (3,))
    packed = LMB.PackedRelation(
        domain => codomain; degree_bound = 2, capacity = 2
    )
    generations = UInt64[4]
    validated_generations = UInt64[4]
    statuses = Int32[0]
    generation = LMB._RelationContentGenerationRef(generations, 1)
    status = LMB._RelationStatusRef(statuses, validated_generations, 1)
    storage = (
        active = Bool[true, true],
        endpoints = Int32[1 2; 2 3],
        offsets = Int32[1],
        counts = Int32[2],
    )
    relation_binding = LMB._relation_storage_binding(
        packed, storage; generation, status
    )
    proof = LMB._validate_structural_binding(
        (), (packed,), LMB._StructuralBinding((), (relation_binding,))
    ).proofs[1]
    @test length(proof.binding_schema.physical_leaves) == 7
    @test relation_binding.generation.generations === generations
    @test relation_binding.status.statuses === statuses
    generations[1] = 5
    @test LMB._relation_content_generation(relation_binding.generation) == 5
    @test_throws LMB.LocalMathValidationError LMB._relation_storage_binding(
        packed, storage
    )
    mismatched_status = LMB._RelationStatusRef(Int32[0, 0], UInt64[0, 0], 2)
    mismatched = LMB._relation_storage_binding(
        packed, storage; generation, status = mismatched_status
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (), (packed,), LMB._StructuralBinding((), (mismatched,))
    )

    bad_active = LMB._relation_storage_binding(
        packed, merge(storage, (active = Int32[1, 1],)); generation, status
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (), (packed,), LMB._StructuralBinding((), (bad_active,))
    )

    oversized = LMB.PackedRelation(
        domain => codomain; degree_bound = 2, capacity = 3
    )
    oversized_binding = LMB._relation_storage_binding(
        oversized, storage; generation, status
    )
    @test_throws LMB.LocalMathValidationError LMB._validate_structural_binding(
        (), (oversized,), LMB._StructuralBinding((), (oversized_binding,))
    )

    runtime = LMB.RuntimeRelation(
        domain => codomain; degree_bound = 1,
        key_type = Int32, ownership = :external,
    )
    runtime_binding = LMB._relation_storage_binding(runtime)
    runtime_proof = LMB._validate_structural_binding(
        (), (runtime,), LMB._StructuralBinding((), (runtime_binding,))
    ).proofs[1]
    @test runtime_proof.binding_schema.ownership isa LMB._ExternalOwnership
    @test_throws LMB.LocalMathValidationError LMB._relation_storage_binding(
        LMB.RuntimeRelation(
            domain => codomain; degree_bound = 1,
            key_type = Int32, ownership = :not_an_ownership,
        )
    )

    shared_generations = UInt64[1, 1]
    shared_validated_generations = UInt64[1, 1]
    shared_statuses = Int32[0, 0]
    shared_storage = (
        active = Bool[true, true],
        endpoints = Int32[1 2; 2 3],
        offsets = Int32[1, 1],
        counts = Int32[2, 2],
    )
    packed_peer = LMB.PackedRelation(
        domain => codomain; degree_bound = 2, capacity = 2
    )
    shared_first = LMB._relation_storage_binding(
        packed, shared_storage;
        generation = LMB._RelationContentGenerationRef(shared_generations, 1),
        status = LMB._RelationStatusRef(
            shared_statuses, shared_validated_generations, 1),
    )
    shared_second = LMB._relation_storage_binding(
        packed_peer, shared_storage;
        generation = LMB._RelationContentGenerationRef(shared_generations, 2),
        status = LMB._RelationStatusRef(
            shared_statuses, shared_validated_generations, 2),
    )
    shared_validated = LMB._validate_structural_binding(
        (), (packed, packed_peer),
        LMB._StructuralBinding((), (shared_first, shared_second)),
    )
    @test length(shared_validated.proofs) == 2
end
