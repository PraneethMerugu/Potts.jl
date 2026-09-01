using Test
import LocalMath
const LMP = LocalMath

struct SPNode end
struct SPEvaluator end
(::SPEvaluator)(value, count) = value

@testset "cold stage planning projections" begin
    nodes = LMP.Space(SPNode, 4)
    input = LMP.Field(nodes, Float32)
    middle = LMP.Field(nodes, Float32)
    output = LMP.Field(nodes, Float32)
    identity = LMP.IdentityRelation(nodes)
    count = LMP.Parameter(:count, Int32)

    first_access = LMP.Access(input, identity)
    first_publication = LMP.Publication((LMP.FieldPublication(
        middle, identity, LMP.PublicationValue(:value),
    ),), LMP.Unique(Float32))
    first_stage = LMP.Stage(
        nodes, (input = first_access,), (first_publication,),
        LMP.Evaluator(SPEvaluator(), (count,)), LMP.Control(),
        LMP.SourceOrigin(:stage_planning, 1),
    )

    second_access = LMP.Access(middle, identity)
    second_publication = LMP.Publication((LMP.FieldPublication(
        output, identity, LMP.PublicationValue(:value),
    ),), LMP.Unique(Float32))
    second_stage = LMP.Stage(
        nodes, (middle = second_access,), (second_publication,),
        LMP.Evaluator(SPEvaluator()), LMP.Control(),
        LMP.SourceOrigin(:stage_planning, 2),
    )

    work = LMP.sequence(
        LMP.LocalLaw(first_stage), LMP.LocalLaw(second_stage),
    )
    bound = LMP._bind_law(work, LMP._StructuralBinding(
        (
            LMP._field_storage_binding(input, zeros(Float32, 4)),
            LMP._field_storage_binding(middle, zeros(Float32, 4)),
            LMP._field_storage_binding(output, zeros(Float32, 4)),
        ),
        (LMP._relation_storage_binding(identity),),
    ))

    validated_bound = LMP._validate_bound_law(bound)
    facts = map(index -> LMP._stage_planning_entry(validated_bound, index), 1:2)
    @test facts[1].projection.layout.fields == (LMP._FieldSlot(1), LMP._FieldSlot(2))
    @test facts[1].projection.accesses[1].target isa LMP._PreparedFieldSlot{1}
    @test facts[1].projection.accesses[1].relation == LMP._RelationSlot(1)
    @test facts[1].projection.parameters.evaluator == (LMP._ParameterSlot{1}(),)

    external = facts[1].dependencies.accesses.input
    preceding = facts[2].dependencies.accesses.middle
    @test external isa LMP._ExternalFieldDependency
    @test external.field_id == LMP.semantic_identity(input)
    @test preceding isa LMP._PrecedingFieldDependency
    @test preceding.field_id == LMP.semantic_identity(middle)
    @test preceding.stage == 1

    @test LMP._validate_bound_backend(bound,
        LMP.KernelAbstractions.get_backend(
            bound.binding.fields[1].storage)) === nothing
    @test !hasmethod(LMP.plan, Tuple{typeof(bound), NamedTuple})
    @test_throws MethodError LMP.plan(bound, (;))

    # Field-derived prefix/gate controls require preceding total publications;
    # masks remain ordinary stage-entry Field inputs and subset is a relation use.
    singleton = LMP.Space(SPNode, 1)
    scalar = LMP.Field(singleton, Float32)
    prefix = LMP.Field(singleton, Int32)
    gate = LMP.Field(singleton, Bool)
    mask = LMP.Field(singleton, Bool)
    controlled_output = LMP.Field(singleton, Float32)
    scalar_relation = LMP.IdentityRelation(singleton)
    scalar_access = LMP.Access(scalar, scalar_relation)
    scalar_stage(field, label, line; control = LMP.Control()) = LMP.Stage(
        singleton, (scalar = scalar_access,), (LMP.Publication((
            LMP.FieldPublication(field, scalar_relation,
                LMP.PublicationValue(label)),
        ), LMP.Unique(eltype(field))),), LMP.Evaluator(SPEvaluator()),
        control, LMP.SourceOrigin(:stage_planning_control, line),
    )
    prefix_stage = scalar_stage(prefix, :prefix_value, 3)
    gate_stage = scalar_stage(gate, :gate_value, 4)
    controlled = scalar_stage(
        controlled_output, :output_value, 5;
        control = LMP.Control(
            LMP._FieldPrefix(prefix), LMP._MaskSelection(mask),
            LMP._SubsetSelection(scalar_relation), LMP._FieldGate(gate),
        ),
    )
    controlled_work = LMP.sequence(
        LMP.LocalLaw(prefix_stage), LMP.LocalLaw(gate_stage),
        LMP.LocalLaw(controlled),
    )
    controlled_bound = LMP._bind_law(
        controlled_work,
        LMP._StructuralBinding(
            (
                LMP._field_storage_binding(scalar, zeros(Float32, 1)),
                LMP._field_storage_binding(prefix, zeros(Int32, 1)),
                LMP._field_storage_binding(gate, zeros(Bool, 1)),
                LMP._field_storage_binding(mask, zeros(Bool, 1)),
                LMP._field_storage_binding(controlled_output, zeros(Float32, 1)),
            ),
            (LMP._relation_storage_binding(scalar_relation),),
        ),
    )
    controlled_facts = LMP._stage_planning_entry(
        LMP._validate_bound_law(controlled_bound), 3)
    control_dependencies = controlled_facts.dependencies.control
    @test control_dependencies.prefix isa LMP._PrecedingFieldDependency
    @test control_dependencies.prefix.stage == 1
    @test control_dependencies.gate isa LMP._PrecedingFieldDependency
    @test control_dependencies.gate.stage == 2
    @test control_dependencies.mask isa LMP._ExternalFieldDependency
    @test control_dependencies.subset isa LMP._RelationUse
    @test control_dependencies.subset.relation_id == LMP.semantic_identity(scalar_relation)
    subset_projection = controlled_facts.projection.control.subset
    @test subset_projection.target isa LMP._NoPreparedTarget

    partial_prefix = LMP.Stage(
        singleton, (scalar = scalar_access,), (LMP.Publication((
            LMP.FieldPublication(
                prefix, scalar_relation, LMP.PublicationValue(:partial_prefix),
            ),
        ), LMP.Unique(
            Int32; coverage = LMP.PartialCoverage(),
            onempty = LMP.PreserveEmpty(),
        )),), LMP.Evaluator(SPEvaluator()), LMP.Control(),
        LMP.SourceOrigin(:stage_planning_control, 6),
    )
    prefix_consumer = scalar_stage(
        controlled_output, :partial_output, 7;
        control = LMP.Control(; prefix = LMP._FieldPrefix(prefix)),
    )
    partial_bound = LMP._bind_law(
        LMP.sequence(LMP.LocalLaw(partial_prefix), LMP.LocalLaw(prefix_consumer)),
        LMP._StructuralBinding(
            (
                LMP._field_storage_binding(scalar, zeros(Float32, 1)),
                LMP._field_storage_binding(prefix, zeros(Int32, 1)),
                LMP._field_storage_binding(controlled_output, zeros(Float32, 1)),
            ),
            (LMP._relation_storage_binding(scalar_relation),),
        ),
    )
    @test_throws LMP.LocalMathValidationError LMP._stage_planning_entry(
        LMP._validate_bound_law(partial_bound), 2)
end
