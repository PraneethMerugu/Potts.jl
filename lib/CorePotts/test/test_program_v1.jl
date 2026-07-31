empty_descriptor_plan() = CorePotts.DescriptorExecutionPlan(
    (),
    CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
    CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
    (),
    Any[],
    Int32(0),
    "empty-descriptor-plan-v1",
    CorePotts.HamiltonianDomainResources(0, 0),
)

function test_program(
        engine;
        activity = nothing,
        history = nothing,
        relationships = nothing,
        observations = (),
        volume_target = 9,
        volume_strength = 1,
        temperature = 3,
        cell_state_fields = (),
    )
    T = Float64
    scalar(value) = CorePotts.CompiledScalar(T(value))
    offsets = Int8[
        1 -1 0 0
        0 0 1 -1
    ]
    return CorePotts.CompiledPottsProgram(
        (6, 6),
        (true, true),
        offsets,
        offsets,
        2,
        1,
        [scalar(0), scalar(volume_target)],
        [scalar(0), scalar(volume_strength)],
        [scalar(0) scalar(4); scalar(4) scalar(1)],
        falses(2),
        scalar(temperature),
        1,
        T[],
        activity,
        nothing,
        history,
        nothing,
        relationships,
        observations,
        empty_descriptor_plan(),
        engine,
        CorePotts.CPUProgramBackend(),
        "core-program-v1-test";
        cell_state_fields,
    )
end

@testset "extinction retires a generation at the lifecycle boundary" begin
    program = test_program(
        CorePotts.SequentialProgramEngine();
        volume_target = 0,
        volume_strength = 20,
        temperature = 0,
        cell_state_fields = (:marker,),
    )
    ownership = zeros(Int32, 6, 6)
    ownership[3, 3] = 1
    initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2];
        scalar_type = Float64,
        stored_states = (marker = [7.0],),
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0x77), UInt32(1)
    )
    for _ in 1:8
        CorePotts.advance_mcs!(runtime)
        iszero(runtime.cell_kinds[1]) && break
    end
    @test runtime.volumes[1] == 0
    @test runtime.cell_kinds[1] == 0
    @test runtime.stored_states.marker[1] == 0
    restored = CorePotts.restore_program_checkpoint(
        program, CorePotts.program_checkpoint(runtime)
    )
    @test restored.cell_kinds == runtime.cell_kinds
    @test restored.stored_states == runtime.stored_states
end

function test_initial()
    ownership = zeros(Int32, 6, 6)
    ownership[3:4, 3:4] .= 1
    return CorePotts.ProgramInitialState(
        ownership, Int16[2]; scalar_type = Float64
    )
end

@testset "bounded histories are logical checkpoint state" begin
    scalar(value) = CorePotts.CompiledScalar(Float64(value))
    offsets = Int8[
        1 -1 0 0
        0 0 1 -1
    ]
    activity = CorePotts.CompiledActivityPlan(
        Int16(2), scalar(10), scalar(0), offsets, false, 1.0
    )
    history = CorePotts.CompiledHistoryPlan(2, :activity)
    program = test_program(
        CorePotts.SequentialProgramEngine(); activity, history
    )
    initial = test_initial()
    activity_values = fill(3.0, 6, 6)
    state = CorePotts.ProgramInitialState(
        initial.ownership,
        initial.cell_kinds;
        scalar_type = Float64,
        activity = activity_values,
    )
    runtime = CorePotts.initialize_program(
        program, state, Float64[], UInt64(4), UInt32(1)
    )
    CorePotts.advance_mcs!(runtime)
    snapshot = CorePotts.program_snapshot(runtime)
    @test length(snapshot.history) == 2
    @test snapshot.history[1] == activity_values
    @test snapshot.history[2] == snapshot.activity
    restored = CorePotts.restore_program_checkpoint(
        program, CorePotts.program_checkpoint(runtime)
    )
    @test CorePotts.program_snapshot(restored).history == snapshot.history
end

@testset "narrow compiled-program interface" begin
    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        program = test_program(engine)
        first = CorePotts.initialize_program(
            program, test_initial(), Float64[], UInt64(0x1234), UInt32(1)
        )
        second = CorePotts.initialize_program(
            program, test_initial(), Float64[], UInt64(0x1234), UInt32(1)
        )
        CorePotts.advance_mcs!(first)
        CorePotts.advance_mcs!(second)
        @test CorePotts.program_snapshot(first).ownership ==
              CorePotts.program_snapshot(second).ownership
        @test first.mcs == 1
        @test first.settled
        report = CorePotts.program_execution_report(program)
        @test report.backend === :CPUProgramBackend
        @test report.numerical_policy.reductions === :deterministic
    end

    sequential = test_program(CorePotts.SequentialProgramEngine())
    first = CorePotts.initialize_program(
        sequential, test_initial(), Float64[], UInt64(7), UInt32(1)
    )
    other_replica = CorePotts.initialize_program(
        sequential, test_initial(), Float64[], UInt64(7), UInt32(2)
    )
    for _ in 1:4
        CorePotts.advance_mcs!(first)
        CorePotts.advance_mcs!(other_replica)
    end
    @test CorePotts.program_snapshot(first).ownership !=
          CorePotts.program_snapshot(other_replica).ownership
end

@testset "owned runtime barriers remain inferred and bounded" begin
    program = test_program(CorePotts.SequentialProgramEngine())
    runtime = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0x99), UInt32(1)
    )
    CorePotts.advance_mcs!(runtime)
    report = @inferred CorePotts.program_execution_report(program)
    snapshot = @inferred CorePotts.program_snapshot(runtime)
    @test report.engine === :SequentialProgramEngine
    @test snapshot.mcs == 1

    # This is deliberately a generous regression ceiling, not a performance
    # qualification claim. It catches accidental per-site heap traffic at the
    # public whole-MCS barrier while leaving hardware tuning out of normal CI.
    bytes = @allocated CorePotts.advance_mcs!(runtime)
    @test bytes <= 256 * 1024
end

@testset "relationship transactions are atomic and canonical" begin
    scalar(value) = CorePotts.CompiledScalar(Float64(value))
    plan = CorePotts.CompiledRelationshipPlan(
        2, 1, 2, 2, scalar(1), scalar(2), scalar(5)
    )
    state = CorePotts.ProgramRelationshipState(Float64, 2)
    generations = UInt32[4, 7]
    create = CorePotts.CreateRelationshipRequest(
        2,
        1,
        1.0,
        2.0,
        5.0;
        generation_a = 7,
        generation_b = 4,
        identity = 9,
    )
    CorePotts.apply_relationship_requests!(
        state, Int16[2, 2], generations, plan, [create]
    )
    @test count(state.active) == 1
    @test (state.endpoint_a[1], state.endpoint_b[1]) == (1, 2)
    @test (state.generation_a[1], state.generation_b[1]) == (4, 7)
    @test state.degree == Int16[1, 1]
    @test state.incident_edges[1, :] == Int32[1, 1]

    # The exact duplicate policy is idempotent.
    CorePotts.apply_relationship_requests!(
        state, Int16[2, 2], generations, plan, [create]
    )
    @test count(state.active) == 1

    before = copy(state)
    stale = CorePotts.CreateRelationshipRequest(
        1, 2, 1.0, 2.0, 5.0; identity = 10
    )
    @test_throws ArgumentError CorePotts.apply_relationship_requests!(
        state, Int16[2, 2], generations, plan, [stale]
    )
    @test state.generation_a == before.generation_a
    @test state.generation_b == before.generation_b

    invalid = CorePotts.CreateRelationshipRequest(
        1, 3, 1.0, 2.0, 5.0; identity = 11
    )
    @test_throws ArgumentError CorePotts.apply_relationship_requests!(
        state, Int16[2, 2], generations, plan, [invalid]
    )
    @test state.active == before.active
    @test state.endpoint_a == before.endpoint_a
    @test state.endpoint_b == before.endpoint_b

    conflict = [
        CorePotts.RetuneRelationshipRequest(1, 2.0, 2.0, 5.0; identity = 1),
        CorePotts.RemoveRelationshipRequest(1; identity = 2),
    ]
    @test_throws ArgumentError CorePotts.apply_relationship_requests!(
        state, Int16[2, 2], generations, plan, conflict
    )
    @test state.active == before.active
    @test state.degree == before.degree
    @test state.incident_edges == before.incident_edges

    CorePotts.apply_relationship_requests!(
        state,
        Int16[2, 2],
        generations,
        plan,
        [CorePotts.RemoveRelationshipRequest(1; identity = 12)],
    )
    @test iszero(count(state.active))
    @test all(iszero, state.degree)
    @test all(iszero, state.incident_edges)
end

@testset "logical checkpoints preserve exact continuation" begin
    program = test_program(CorePotts.SequentialProgramEngine())
    uninterrupted = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0x55), UInt32(1)
    )
    for _ in 1:3
        CorePotts.advance_mcs!(uninterrupted)
    end
    checkpoint = CorePotts.program_checkpoint(uninterrupted)
    restored = CorePotts.restore_program_checkpoint(program, checkpoint)
    for _ in 1:3
        CorePotts.advance_mcs!(uninterrupted)
        CorePotts.advance_mcs!(restored)
    end
    @test CorePotts.program_snapshot(uninterrupted).ownership ==
          CorePotts.program_snapshot(restored).ownership
    @test uninterrupted.accepted == restored.accepted
    @test uninterrupted.rejected == restored.rejected

    corrupted = CorePotts.ProgramCheckpoint(
        checkpoint.schema,
        checkpoint.program_fingerprint,
        checkpoint.snapshot,
        checkpoint.parameters,
        checkpoint.seed,
        checkpoint.replica,
        checkpoint.repeat,
        checkpoint.accepted,
        checkpoint.rejected,
        checkpoint.null_attempts,
        "corrupt",
    )
    @test_throws ArgumentError CorePotts.restore_program_checkpoint(
        program, corrupted
    )
end
@testset "initialization uses the semantic RNG address" begin
    first_draw = CorePotts.initialization_bounded(
        UInt64(0x1234), UInt32(1), 1, 0, 17
    )
    repeated_draw = CorePotts.initialization_bounded(
        UInt64(0x1234), UInt32(1), 1, 0, 17
    )
    next_draw = CorePotts.initialization_bounded(
        UInt64(0x1234), UInt32(1), 1, 1, 17
    )
    @test 1 <= first_draw <= 17
    @test first_draw == repeated_draw
    @test 1 <= next_draw <= 17
end

struct ExternalSquareOperation <: CorePotts.AbstractContextualOperation end

(::ExternalSquareOperation)(arguments, context) = only(arguments)^2

@testset "external descriptor operation stays open" begin
    expression = CorePotts.OperationExpression(
        CorePotts.operation_callable(Val(:add), v"1.0.0"),
        CorePotts.OperationExpression(
            ExternalSquareOperation(),
            CorePotts.ParameterExpression(2.0f0, 1),
        ),
        CorePotts.LiteralExpression(1.0f0),
    )
    evaluator = CorePotts.StaticEvaluator(expression)
    context = CorePotts.EvaluatorProbeContext(
        Float32[3],
        (
            source_site = Int32(1),
            target_site = Int32(1),
            source_cell = Int32(1),
            target_cell = Int32(1),
            source_kind = Int16(1),
            target_kind = Int16(1),
            is_extension = false,
            is_retraction = false,
        ),
    )
    descriptor = CorePotts.ProposalDescriptor(
        evaluator,
        CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint()
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        1,
    )
    @test CorePotts.evaluate_static(descriptor.evaluator, context) == 10.0f0
    @test Core.Compiler.return_type(
        CorePotts.evaluate_static,
        Tuple{typeof(descriptor.evaluator), typeof(context)},
    ) === Float32
    output = zeros(Float32, 4)
    backend = CorePotts.KernelAbstractions.CPU()
    kernel = CorePotts.descriptor_probe_kernel!(backend)
    kernel(output, descriptor, context; ndrange = length(output))
    CorePotts.KernelAbstractions.synchronize(backend)
    @test output == fill(10.0f0, 4)
end
