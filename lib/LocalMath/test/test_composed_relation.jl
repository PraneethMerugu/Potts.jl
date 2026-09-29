using Test
import LocalMath
const LMC = LocalMath

struct ComposedRelationNode end
struct ComposedEndpointEvaluator end
@inline function (::ComposedEndpointEvaluator)(item::Int32, reads, parameters)
    samples = getfield(reads, 1)
    encoded = samples[1].endpoint + Int32(10) * samples[2].endpoint +
        Int32(100) * samples[3].endpoint +
        Int32(1000) * samples[4].endpoint
    return (value = LMC.UniqueValue(encoded),)
end
struct ComposedFirstEvaluator end
@inline (::ComposedFirstEvaluator)(item::Int32, reads, parameters) =
    (value = LMC.UniqueValue(getfield(reads, 1)[1].endpoint),)

@testset "ComposedRelation is bounded left-to-right mixed-radix composition" begin
    source = LMC.Space(ComposedRelationNode, 2)
    middle = LMC.Space(ComposedRelationNode, 3)
    target = LMC.Space(ComposedRelationNode, 4)
    wrong = LMC.Space(ComposedRelationNode, 3)
    first = LMC.FixedRelation(source => middle; degree = 2)
    second = LMC.FixedRelation(middle => target; degree = 2)
    composed = LMC.compose(first, second)
    @test LMC.domain(composed) == source
    @test LMC.codomain(composed) == target
    @test LMC.degree_bound(composed) == 4
    @test_throws LMC.LocalMathValidationError LMC.compose(first,
        LMC.FixedRelation(wrong => target; degree = 1))
    wide = LMC.compose(
        LMC.FixedRelation(source => middle; degree = 8),
        LMC.FixedRelation(middle => target; degree = 8))
    @test LMC.degree_bound(wide) == 64
    @test_throws LMC.LocalMathValidationError LMC.compose(
        LMC.FixedRelation(source => middle; degree = 33),
        LMC.FixedRelation(middle => target; degree = 33))

    input = LMC.Field(target, Int32)
    output = LMC.Field(source, Int32)
    identity = LMC.IdentityRelation(source)
    access = LMC.Access(input, composed)
    publication = LMC.Publication((LMC.FieldPublication(
        output, identity, LMC.PublicationValue(:value)),),
        LMC.Unique(Int32))
    stage = LMC.Stage(source, (neighbors = access,), (publication,),
        LMC.Evaluator(ComposedEndpointEvaluator()), LMC.Control(),
        LMC.SourceOrigin(:composed_relation_test, 1))

    input_storage = Int32[10, 20, 30, 40]
    output_storage = fill(Int32(-1), 2)
    binding = LMC._StructuralBinding((
        LMC._field_storage_binding(input, input_storage),
        LMC._field_storage_binding(output, output_storage),
    ), (
        LMC._relation_storage_binding(composed),
        LMC._relation_storage_binding(first, (
            endpoints = reshape(Int32[1, 2, 2, 3], 2, 2),
            counts = Int32[1, 2])),
        LMC._relation_storage_binding(second, (
            endpoints = reshape(Int32[1, 2, 2, 3, 3, 4], 2, 3),
            counts = Int32[2, 2, 2])),
        LMC._relation_storage_binding(identity),
    ))
    plan = LMC.plan(LMC._bind_law(LMC.LocalLaw(stage), binding);
        backend = LMC.KernelAbstractions.CPU())
    inspection = LMC.inspect(plan; level = :relations)
    @test length(plan.bound.binding.proofs) == 4
    @test map(fact -> fact.identity, inspection.relations) ==
        (LMC.semantic_identity(composed), LMC.semantic_identity(identity))
    entry = only(LMC._logical_lowering_entries(plan.lowering))
    view = only(entry.admission.stage.accesses).relation
    adapted_view = LMC.Adapt.adapt(identity, view.view)
    @test typeof(adapted_view) === typeof(view.view)
    @test adapted_view.degree == view.view.degree
    @test Tuple(LMC._relation_endpoint(view, (), Int32(1), lane).index
        for lane in Int32(1):Int32(4)) == (1, 0, 2, 0)
    @test Tuple(LMC._relation_endpoint(view, (), Int32(2), lane).index
        for lane in Int32(1):Int32(4)) == (2, 3, 3, 4)
    prepared = LMC.prepare(plan)
    wait(LMC.execute!(prepared))
    @test output_storage == Int32[201, 4332]

    validated = prepared.plan.bound.binding
    composed_slot = LMC._resolve_relation_slot(validated, composed)
    proof = LMC._relation_proof(validated, composed_slot)
    @test proof.evidence.canonical_order ===
        :first_factor_fastest_mixed_radix
    @test proof.evidence.footprint.kind === :composition
    report = LMC._relation_inspection(composed, proof)
    @test report.representation.family === :composed
    @test report.footprint.strength === :bounded
end

@testset "IndexRelation preserves multidimensional codomain shape in composition" begin
    source = LMC.Space(ComposedRelationNode, 2)
    grid = LMC.Space(ComposedRelationNode, (2, 3))
    keys = LMC.Field(source, Int32)
    values = LMC.Field(grid, Int32)
    output = LMC.Field(source, Int32)
    indexed = LMC.IndexRelation(keys => grid)
    offsets = LMC.AffineRelation(grid => grid; offsets = ((0, 0),))
    periodic = LMC.BoundaryRelation(
        offsets, LMC.PeriodicBoundary((true, true)))
    composed = LMC.compose(indexed, periodic)
    identity = LMC.IdentityRelation(source)
    stage = LMC.Stage(
        source,
        (value = LMC.Access(values, composed; required = true),),
        (LMC.Publication((LMC.FieldPublication(
            output, identity, LMC.PublicationValue(:value)),),
            LMC.Unique(Int32)),),
        LMC.Evaluator(ComposedFirstEvaluator()),
        LMC.Control(),
        LMC.SourceOrigin(:multidimensional_index_composition, 1),
    )
    result = fill(Int32(-1), 2)
    prepared = LMC.prepare(
        LMC.LocalLaw(stage),
        keys => Int32[1, 6],
        values => reshape(Int32.(1:6), 2, 3),
        output => result;
        backend = LMC.KernelAbstractions.CPU(),
    )
    wait(LMC.execute!(prepared))
    @test result == Int32[1, 6]
end

@testset "ComposedRelation includes mutable factor receipts exactly once" begin
    source = LMC.Space(ComposedRelationNode, 2)
    middle = LMC.Space(ComposedRelationNode, 2)
    target = LMC.Space(ComposedRelationNode, 2)
    packed = LMC.PackedRelation(source => middle;
        degree_bound = 1, capacity = 2)
    fixed = LMC.FixedRelation(middle => target; degree = 1)
    composed = LMC.compose(packed, fixed)
    field = LMC.Field(target, Int32)
    output = LMC.Field(source, Int32)
    identity = LMC.IdentityRelation(source)
    access = LMC.Access(field, composed)
    publication = LMC.Publication((LMC.FieldPublication(
        output, identity, LMC.PublicationValue(:value)),),
        LMC.Unique(Int32))
    stage = LMC.Stage(source, (neighbors = access,), (publication,),
        LMC.Evaluator(ComposedFirstEvaluator()),
        LMC.Control(), LMC.SourceOrigin(:composed_relation_test, 2))
    generation = UInt64[3]
    validated_generation = UInt64[3]
    status = Int32[0]
    binding = LMC._StructuralBinding((
        LMC._field_storage_binding(field, Int32[1, 2]),
        LMC._field_storage_binding(output, Int32[-1, -1]),
    ), (
        LMC._relation_storage_binding(composed),
        LMC._relation_storage_binding(packed, (
            active = Bool[true, true],
            endpoints = reshape(Int32[1, 2], 1, 2),
            offsets = Int32[1], counts = Int32[2]);
            generation = LMC._RelationContentGenerationRef(generation, 1),
            status = LMC._RelationStatusRef(
                status, validated_generation, 1)),
        LMC._relation_storage_binding(fixed, (
            endpoints = reshape(Int32[1, 2], 1, 2),
            counts = Int32[1, 1])),
        LMC._relation_storage_binding(identity),
    ))
    bound = LMC._bind_law(LMC.LocalLaw(stage), binding)
    plan = LMC.plan(bound; backend = LMC.KernelAbstractions.CPU())
    @test length(only(LMC._logical_lowering_entries(
        plan.lowering)).relation_dependencies) == 1
end
