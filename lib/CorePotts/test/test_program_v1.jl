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
        relationships = (),
        temperature = 3,
        descriptor_plan = empty_descriptor_plan(),
        stage_plan = CorePotts.StageExecutionPlan(),
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
        2,
        1,
        scalar(temperature),
        1,
        T[],
        relationships,
        descriptor_plan,
        stage_plan,
        engine,
        CorePotts.CPUProgramBackend(),
        "core-program-v1-test",
    )
end

@testset "extinction retires a generation at the lifecycle boundary" begin
    marker_schema = CorePotts.StateBlockSchema(
        CorePotts.QualifiedResourceIdentity((), :marker),
        v"1.0.0",
        :cell,
        Float64,
        (1,),
        1,
        :structure_of_arrays,
        :provided_or_zero,
        :shape_and_finite,
        :logical,
        :preserve,
        :declared,
        :bounded_write,
        :adapt_storage,
        :copy,
        :logical_copy,
        :qualified,
        true,
    )
    layout = CorePotts.StateLayout([marker_schema])
    descriptor_plan = CorePotts.DescriptorExecutionPlan(
        (),
        layout,
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "cell-state-descriptor-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
    marker_handle = only(layout.entries).handle
    program = test_program(
        CorePotts.SequentialProgramEngine();
        temperature = 0,
        descriptor_plan,
    )
    ownership = zeros(Int32, 6, 6)
    ownership[3, 3] = 1
    initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2];
        scalar_type = Float64,
        descriptor_state = CorePotts.allocate_auxiliary_state(
            layout, ([7.0],)
        ),
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
    @test CorePotts.state_block(
        runtime.descriptor_state, marker_handle
    ).values[1] == 0
    restored = CorePotts.restore_program_checkpoint(
        program, CorePotts.program_checkpoint(runtime)
    )
    @test restored.cell_kinds == runtime.cell_kinds
    @test CorePotts.state_block(
        restored.descriptor_state, marker_handle
    ).values == CorePotts.state_block(
        runtime.descriptor_state, marker_handle
    ).values
end

function test_initial()
    ownership = zeros(Int32, 6, 6)
    ownership[3:4, 3:4] .= 1
    return CorePotts.ProgramInitialState(
        ownership, Int16[2]; scalar_type = Float64
    )
end

@testset "bounded histories are logical checkpoint state" begin
    function state_schema(name, domain, shape)
        return CorePotts.StateBlockSchema(
            CorePotts.QualifiedResourceIdentity((), name),
            v"1.0.0",
            domain,
            Float64,
            shape,
            prod(shape),
            :structure_of_arrays,
            :provided_or_zero,
            :shape_and_finite,
            :logical,
            :preserve,
            :declared,
            :bounded_write,
            :adapt_storage,
            :copy,
            :logical_copy,
            :qualified,
            true,
        )
    end
    layout = CorePotts.StateLayout([
        state_schema(:signal, :site, (6, 6)),
        state_schema(:signal_memory, :history, (6, 6, 2)),
    ])
    signal_entry = only(filter(
        entry -> entry.schema.identity.name === :signal,
        layout.entries,
    ))
    memory_entry = only(filter(
        entry -> entry.schema.identity.name === :signal_memory,
        layout.entries,
    ))
    descriptor_plan = CorePotts.DescriptorExecutionPlan(
        (),
        layout,
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "history-descriptor-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
    shift = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
        CorePotts.ShiftAppendEffect(
            memory_entry.handle, signal_entry.handle, 3
        ),
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            (memory_entry.handle, signal_entry.handle),
            (memory_entry.handle,),
            CorePotts.FiniteSpatialFootprint(()),
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        1,
        0,
    )
    stage_plan = CorePotts.StageExecutionPlan(
        (),
        (CorePotts.StageDescriptorGroup([shift]),),
        0,
        0,
        "history-stage-plan-v1",
    )
    program = test_program(
        CorePotts.SequentialProgramEngine(); descriptor_plan, stage_plan
    )
    initial = test_initial()
    activity_values = fill(3.0, 6, 6)
    history_values = Array{Float64}(undef, 6, 6, 2)
    fill!(selectdim(history_values, 3, 1), 1.0)
    fill!(selectdim(history_values, 3, 2), 2.0)
    descriptor_values = map(layout.entries) do entry
        entry.schema.identity.name === :signal ?
        activity_values : history_values
    end
    state = CorePotts.ProgramInitialState(
        initial.ownership,
        initial.cell_kinds;
        scalar_type = Float64,
        descriptor_state = CorePotts.allocate_auxiliary_state(
            layout, descriptor_values
        ),
    )
    runtime = CorePotts.initialize_program(
        program, state, Float64[], UInt64(4), UInt32(1)
    )
    CorePotts.advance_mcs!(runtime)
    snapshot = CorePotts.program_snapshot(runtime)
    saved_history = CorePotts.state_block(
        snapshot.descriptor_state, memory_entry.handle
    ).values
    @test selectdim(saved_history, 3, 1) == fill(2.0, 6, 6)
    @test selectdim(saved_history, 3, 2) == activity_values
    restored = CorePotts.restore_program_checkpoint(
        program, CorePotts.program_checkpoint(runtime)
    )
    restored_history = CorePotts.state_block(
        CorePotts.program_snapshot(restored).descriptor_state,
        memory_entry.handle,
    ).values
    @test restored_history == saved_history
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
    @test_throws ArgumentError CorePotts.RelationshipStoreSchema(
        Int(typemax(Int32)) + 1, 1
    )
    @test_throws ArgumentError CorePotts.RelationshipStoreSchema(
        1, Int(typemax(Int16)) + 1
    )
    @test_throws ArgumentError CorePotts.ProgramRelationshipState(
        Float64, 1, 1, Int(typemax(Int16)) + 1, 0
    )
    plan = CorePotts.RelationshipStoreSchema(
        2, 1, (scalar(1), scalar(2), scalar(5))
    )
    state = CorePotts.ProgramRelationshipState(Float64, 2, 2, 1, 3)
    generations = UInt32[4, 7]
    create = CorePotts.CreateRelationshipRequest(
        2,
        1,
        (1.0, 2.0, 5.0);
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
        1, 2, (1.0, 2.0, 5.0); identity = 10
    )
    @test_throws ArgumentError CorePotts.apply_relationship_requests!(
        state, Int16[2, 2], generations, plan, [stale]
    )
    @test state.generation_a == before.generation_a
    @test state.generation_b == before.generation_b

    invalid = CorePotts.CreateRelationshipRequest(
        1, 3, (1.0, 2.0, 5.0); identity = 11
    )
    @test_throws ArgumentError CorePotts.apply_relationship_requests!(
        state, Int16[2, 2], generations, plan, [invalid]
    )
    @test state.active == before.active
    @test state.endpoint_a == before.endpoint_a
    @test state.endpoint_b == before.endpoint_b

    nonfinite_create_state = CorePotts.ProgramRelationshipState(
        Float64, 2, 2, 1, 3
    )
    nonfinite_create = CorePotts.CreateRelationshipRequest(
        1,
        2,
        (NaN, 2.0, 5.0);
        generation_a = 4,
        generation_b = 7,
        identity = 12,
    )
    @test_throws DomainError CorePotts.apply_relationship_requests!(
        nonfinite_create_state,
        Int16[2, 2],
        generations,
        plan,
        [nonfinite_create],
    )
    @test iszero(count(nonfinite_create_state.active))

    nonfinite_retune = CorePotts.RetuneRelationshipRequest(
        1, (2.0, Inf, 5.0); identity = 13
    )
    @test_throws DomainError CorePotts.apply_relationship_requests!(
        state, Int16[2, 2], generations, plan, [nonfinite_retune]
    )
    @test state.payload == before.payload

    conflict = [
        CorePotts.RetuneRelationshipRequest(
            1, (2.0, 2.0, 5.0); identity = 1
        ),
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
    @test uninterrupted.null_attempts == restored.null_attempts
    @test uninterrupted.constraint_rejections == restored.constraint_rejections
    @test uninterrupted.energy_rejections == restored.energy_rejections
    @test uninterrupted.retired_cells == restored.retired_cells

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
        checkpoint.constraint_rejections,
        checkpoint.energy_rejections,
        checkpoint.retired_cells,
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
    @test Core.Compiler.return_type(
        CorePotts._compiled_evaluate_static,
        Tuple{typeof(descriptor.evaluator), typeof(context)},
    ) === Float32
    output = zeros(Float32, 4)
    backend = CorePotts.KernelAbstractions.CPU()
    kernel = CorePotts.descriptor_probe_kernel!(backend)
    kernel(output, descriptor, context; ndrange = length(output))
    CorePotts.KernelAbstractions.synchronize(backend)
    @test output == fill(10.0f0, 4)
end

@testset "public storage layouts canonicalize representation banks" begin
    function state_schema(name, element_type)
        return CorePotts.StateBlockSchema(
            CorePotts.QualifiedResourceIdentity((), name),
            v"1.0.0",
            :site,
            element_type,
            (2,),
            2,
            :structure_of_arrays,
            :provided_or_zero,
            :shape_and_finite,
            :logical,
            :preserve,
            :declared,
            :bounded_write,
            :adapt_storage,
            :copy,
            :logical_copy,
            :qualified,
            true,
        )
    end
    function workspace_schema(name, element_type)
        return CorePotts.WorkspaceSchema(
            CorePotts.QualifiedResourceIdentity((), name),
            v"1.0.0",
            element_type,
            (2,),
            2,
            Array,
            :zero,
            :proposal,
            :bounded_write,
            :adapt_storage,
            :qualified,
            false,
        )
    end
    function banks_by_representation(layout)
        return Dict(
            CorePotts.handle_representation(entry.handle) =>
                CorePotts.handle_bank(entry.handle)
            for entry in layout.entries
        )
    end

    states = [
        state_schema(:float64_state, Float64),
        state_schema(:float32_state, Float32),
    ]
    workspaces = [
        workspace_schema(:float64_workspace, Float64),
        workspace_schema(:float32_workspace, Float32),
    ]
    @test banks_by_representation(CorePotts.StateLayout(states)) ==
          banks_by_representation(CorePotts.StateLayout(reverse(states)))
    @test banks_by_representation(CorePotts.WorkspaceLayout(workspaces)) ==
          banks_by_representation(CorePotts.WorkspaceLayout(reverse(workspaces)))
end
