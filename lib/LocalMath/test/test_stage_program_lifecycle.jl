using Test
import LocalMath
const LMP = LocalMath

struct StageProgramNode end
struct StageProgramEvaluator end
@inline (::StageProgramEvaluator)(item::Int32, reads, parameters) =
    (value = LMP.UniqueValue(item + Int32(20)),)
struct MixedStageProgramEvaluator end
@inline (::MixedStageProgramEvaluator)(item::Int32, reads, parameters) =
    (unique = LMP.UniqueValue(item), contribution = LMP.Contribution(item))
struct SecondStageProgramEvaluator end
@inline (::SecondStageProgramEvaluator)(item::Int32, reads, parameters) =
    (second = LMP.UniqueValue(item + Int32(40)),)
@testset "Stage tuple uses the sole Plan receipt lifecycle" begin
    source = LMP.Space(StageProgramNode, 3)
    output = LMP.Field(source, Int32)
    relation = LMP.IdentityRelation(source)
    publication = LMP.Publication((LMP.FieldPublication(
        output, relation, LMP.PublicationValue(:value)),),
        LMP.Unique(Int32))
    work = LMP.LocalLaw(LMP.Stage(source, NamedTuple(), (publication,),
        LMP.Evaluator(StageProgramEvaluator()), LMP.Control(),
        LMP.SourceOrigin(:stage_program_lifecycle, 1)))
    storage = fill(Int32(-1), 3)
    bound = LMP._bind_law(work, LMP._StructuralBinding(
        (LMP._field_storage_binding(output, storage),),
        (LMP._relation_storage_binding(relation),)))
    backend = LMP.KernelAbstractions.get_backend(storage)
    plan = LMP.plan(bound; backend)
    prepared = LMP.prepare(plan)
    work_facts = LMP.inspect(work)
    plan_facts = LMP.inspect(plan)
    prepared_facts = LMP.inspect(prepared)
    @test keys(work_facts) ==
        (:lifecycle, :parameters, :relations, :stages, :planning, :equivalence)
    @test keys(plan_facts) == keys(work_facts)
    @test keys(prepared_facts) == (keys(work_facts)..., :realized)
    @test work_facts.equivalence == plan_facts.equivalence ==
        prepared_facts.equivalence
    @test LMP.inspect(LMP.LocalLaw(work.stages[1])).equivalence ==
        work_facts.equivalence
    @test plan_facts.planning.stage_local_launch_count == 1
    @test hasproperty(plan_facts.planning, :backend_environment)
    @test !hasproperty(plan_facts.planning, :backend_qualification)
    @test plan_facts.planning.program_reset_count == 1
    @test plan_facts.planning.base_provider_launch_count == 2
    @test length(plan_facts.relations) == 1
    @test work_facts.relations[1].proof === nothing
    @test plan_facts.relations[1].proof !== nothing
    @test plan_facts.relations[1].footprint.strength === :exact
    @test length(prepared_facts.realized.bindings.fields) == 1
    @test length(prepared_facts.realized.bindings.relations) == 1
    @test only(prepared_facts.realized.bindings.relations).identity ==
        LMP.semantic_identity(relation)
    @test prepared_facts.planning.workspace ==
        LMP.workspace_requirements(plan).algorithmic
    requirements_1 = LMP.workspace_requirements(
        plan; lease_capacity = 1).algorithmic
    requirements_3 = LMP.workspace_requirements(
        plan; lease_capacity = 3).algorithmic
    @test map(fact -> fact.path, requirements_1) ==
        map(fact -> fact.path, requirements_3)
    @test all(zip(requirements_1, requirements_3)) do (one, three)
        one.alias_scope == three.alias_scope &&
            (one.lease_scaled ?
                (three.size[end] == 3 && three.bytes == 3 * one.bytes) :
                (three.size == one.size && three.bytes == one.bytes))
    end
    @test length(plan.lowering.callable_admissions) == 1
    @test only(plan.lowering.callable_admissions).purpose === :stage_evaluator
    @test length(typeof(prepared).parameters) == 3
    @test fieldtype(typeof(prepared), :workspace) === Any
    @test !hasfield(typeof(prepared), :operation_callbacks)
    before = LMP.inspect(prepared)
    @test all(callback -> hasproperty(callback, :admission) &&
        !hasproperty(callback, :qualification),
        before.realized.callback_methods)
    @test LMP.inspect(prepared).realized.state == before.realized.state
    event = LMP.execute!(prepared)
    @test !hasproperty(LMP.inspect(event), :prepared)
    wait(event)
    after = LMP.inspect(prepared)
    @test storage == Int32[21, 22, 23]
    @test after.realized.state.provider_completions ==
        before.realized.state.provider_completions + 1
    @test after.realized.state.validation_transfers ==
        before.realized.state.validation_transfers + 1
    @test LMP.lowering_identity(plan) ===
        :stage_local_erased_kernelabstractions_v1
    @test LMP.submission_capacity(prepared).outstanding == 0
end

@testset "multi-stage lowering has typed entries and exact cold context" begin
    source = LMP.Space(StageProgramNode, 3)
    first_output = LMP.Field(source, Int32)
    second_output = LMP.Field(source, Int32)
    relation = LMP.IdentityRelation(source)
    first_publication = LMP.Publication((LMP.FieldPublication(
        first_output, relation, LMP.PublicationValue(:value)),),
        LMP.Unique(Int32))
    second_publication = LMP.Publication((LMP.FieldPublication(
        second_output, relation, LMP.PublicationValue(:second)),),
        LMP.Unique(Int32))
    first_origin = LMP.SourceOrigin(:typed_stage_entry, 11; label = :first)
    second_origin = LMP.SourceOrigin(:typed_stage_entry, 22; label = :second)
    work = LMP.sequence(
        LMP.LocalLaw(LMP.Stage(source, NamedTuple(), (first_publication,),
            LMP.Evaluator(StageProgramEvaluator()), LMP.Control(),
            first_origin)),
        LMP.LocalLaw(LMP.Stage(source, NamedTuple(), (second_publication,),
            LMP.Evaluator(SecondStageProgramEvaluator()), LMP.Control(),
            second_origin)),
    )
    first_storage = fill(Int32(-1), 3)
    second_storage = fill(Int32(-1), 3)
    bound = LMP._bind_law(work, LMP._StructuralBinding((
        LMP._field_storage_binding(first_output, first_storage),
        LMP._field_storage_binding(second_output, second_storage),
    ), (LMP._relation_storage_binding(relation),)))
    backend = LMP.KernelAbstractions.get_backend(first_storage)
    plan = LMP.plan(bound; backend)
    entries = LMP._logical_lowering_entries(plan.lowering)
    @test entries isa Tuple
    @test length(entries) == 2
    @test all(entry -> entry.executor isa LMP._CandidateStageExecutor, entries)
    lowering_leaves = plan.lowering.workspace.leaves
    @test lowering_leaves isa Tuple
    @test !(lowering_leaves isa Vector{Any})
    @test map(entry -> entry.context.origin, entries) ==
        (first_origin, second_origin)
    @test entries[1].context.publications[1].ports == (:value,)
    @test entries[2].context.publications[1].ports == (:second,)
    @test entries[1].context.publications[1].law ===
        typeof(first_publication.law)
    @test !hasproperty(entries[1].context, :field_dependencies)
    @test hasproperty(LMP.inspect(plan).stages[1], :reads)

    automatic = LMP.allocate_workspace(plan)
    requirements = LMP.workspace_requirements(plan).algorithmic
    buffer_names = Tuple(requirement.name for requirement in requirements)
    buffers = NamedTuple{buffer_names}(Tuple(
        LMP._workspace_leaf_value(automatic, leaf)
        for leaf in plan.lowering.workspace.leaves
    ))
    caller_workspace = LMP.allocate_workspace(plan; buffers)
    @test caller_workspace.stages isa Vector
    @test length(caller_workspace.stages) == 2
    @test caller_workspace.stages == Any[(), ()]
    prepared = LMP.prepare(plan; workspace = caller_workspace)
    wait(LMP.execute!(prepared))
    @test first_storage == Int32[21, 22, 23]
    @test second_storage == Int32[41, 42, 43]
end

@testset "heterogeneous Unique and Reduce share one Stage evaluator pass" begin
    source = LMP.Space(StageProgramNode, 3)
    unique_field = LMP.Field(source, Int32)
    reduced_field = LMP.Field(source, Int32)
    relation = LMP.IdentityRelation(source)
    unique = LMP.Publication((LMP.FieldPublication(unique_field, relation,
        LMP.PublicationValue(:unique)),), LMP.Unique(Int32))
    reduce = LMP.Publication((LMP.FieldPublication(reduced_field, relation,
        LMP.PublicationValue(:contribution)),),
        LMP.Reduce(Int32, +; seed = LMP.IdentitySeed(Int32(0))))
    work = LMP.LocalLaw(LMP.Stage(source, NamedTuple(), (unique, reduce),
        LMP.Evaluator(MixedStageProgramEvaluator()), LMP.Control(),
        LMP.SourceOrigin(:stage_program_lifecycle, 2)))
    unique_storage = fill(Int32(-1), 3)
    reduced_storage = fill(Int32(-1), 3)
    bound = LMP._bind_law(work, LMP._StructuralBinding((
        LMP._field_storage_binding(unique_field, unique_storage),
        LMP._field_storage_binding(reduced_field, reduced_storage),
    ), (LMP._relation_storage_binding(relation),)))
    backend = LMP.KernelAbstractions.get_backend(unique_storage)
    plan = LMP.plan(bound; backend)
    automatic = LMP.allocate_workspace(plan)
    requirements = LMP.workspace_requirements(plan).algorithmic
    buffer_names = Tuple(requirement.name for requirement in requirements)
    buffers = NamedTuple{buffer_names}(Tuple(
        LMP._workspace_leaf_value(automatic, leaf)
        for leaf in plan.lowering.workspace.leaves
    ))
    prepared = LMP.prepare(plan; workspace =
        LMP.allocate_workspace(plan; buffers))
    @test map(callback -> callback.purpose,
        plan.lowering.callable_admissions) ==
        [:stage_evaluator, :reduce_operation]
    wait(LMP.execute!(prepared))
    @test unique_storage == Int32[1, 2, 3]
    @test reduced_storage == Int32[1, 2, 3]
    publications = LMP.inspect(prepared).stages[1].publications
    @test publications[1].details.components[1].field ==
        LMP.semantic_identity(unique_field)
    @test publications[1].details.components[1].relation ==
        LMP.semantic_identity(relation)
    @test publications[1].details.law.kind === :unique
    @test publications[1].details.law.coverage === unique.law.coverage
    @test publications[1].details.law.onempty === unique.law.onempty
    @test publications[2].details.law.kind === :reduce
    @test publications[2].details.law.operation === reduce.law.operation
    @test publications[2].details.law.seed === reduce.law.seed
    @test publications[2].details.law.order === reduce.law.order
end
