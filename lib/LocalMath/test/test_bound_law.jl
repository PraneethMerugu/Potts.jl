using Test
import LocalMath
const LMBW = LocalMath

struct BWNode end
struct BWUnused end

struct BWIdentityEvaluator end
(::BWIdentityEvaluator)(value) = value

@testset "sealed stage structural binding" begin
    nodes = LMBW.Space(BWNode, 4)
    singleton = LMBW.Space(BWNode, 1)
    values = LMBW.Field(nodes, Float32)
    output = LMBW.Field(nodes, Float32)
    mask = LMBW.Field(nodes, Bool)
    prefix = LMBW.Field(singleton, Int32)
    gate = LMBW.Field(singleton, Bool)
    identity = LMBW.IdentityRelation(nodes)

    count = LMBW.Parameter(:count, Int32)
    enabled = LMBW.Parameter(:enabled, Bool)
    access = LMBW.Access(values, identity)
    component = LMBW.FieldPublication(
        output, identity, LMBW.PublicationValue(:value)
    )
    publication = LMBW.Publication(
        (component,), LMBW.Unique(Float32)
    )
    stage = LMBW.Stage(
        nodes,
        (value = access,),
        (publication,),
        LMBW.Evaluator(BWIdentityEvaluator(), (count,)),
        LMBW.Control(
            LMBW._FieldPrefix(prefix),
            LMBW._MaskSelection(mask),
            LMBW._SubsetSelection(identity),
            LMBW._FieldGate(gate),
        ),
        LMBW.SourceOrigin(:bound_law_test, 1),
    )
    work = LMBW.LocalLaw(
        stage; parameters = LMBW.ParameterSchema(count, enabled)
    )
    binding = LMBW._StructuralBinding(
        (
            LMBW._field_storage_binding(gate, Bool[true]),
            LMBW._field_storage_binding(mask, Bool[true, false, true, true]),
            LMBW._field_storage_binding(output, zeros(Float32, 4)),
            LMBW._field_storage_binding(values, Float32[1, 2, 3, 4]),
            LMBW._field_storage_binding(prefix, Int32[4]),
        ),
        (LMBW._relation_storage_binding(identity),),
    )

    required_fields, required_relations = LMBW._law_descriptor_requirements(work)
    @test required_fields == (values, output, prefix, mask, gate)
    @test required_relations == (identity,)

    raw_bound = LMBW._bind_law(work, binding)
    bound = LMBW._validate_bound_law(raw_bound)
    @test bound.law === work
    @test bound.binding isa LMBW._ValidatedStructuralBinding
    @test length(bound.binding.fields) == 5
    @test length(bound.binding.relations) == 1
    @test_throws ArgumentError LMBW._BoundLaw(
        LMBW._BoundLawSeal(), work, bound.binding
    )

    unused = LMBW.Field(LMBW.Space(BWUnused, 4), Float32)
    redundant = LMBW._StructuralBinding(
        (
            binding.fields...,
            LMBW._field_storage_binding(unused, zeros(Float32, 4)),
        ),
        binding.relations,
    )
    @test_throws LMBW.LocalMathValidationError LMBW._validate_bound_law(
        LMBW._bind_law(work, redundant))
end
