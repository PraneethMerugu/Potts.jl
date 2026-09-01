@testset "executor rejects an undeclared extinction mechanism" begin
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
        iszero(CorePotts.program_tracker_values(
            runtime, Val(:cell_volume)
        )[1]) && break
    end
    @test CorePotts.program_tracker_values(
        runtime, Val(:cell_volume)
    )[1] >= 1
    @test runtime.cell_kinds[1] == 2
    @test runtime.cell_generations[1] == UInt32(1)
    @test CorePotts.state_block(
        runtime.descriptor_state, marker_handle
    ).values[1] == 7
    checkpoint = CorePotts.program_checkpoint(runtime)
    restored = CorePotts.restore_program_checkpoint(program, checkpoint)
    @test CorePotts.program_checkpoint(restored).checksum == checkpoint.checksum
end

@testset "all engines admit positive repeated attempt budgets" begin
    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        program = test_program(engine; attempts_per_site = 2)
        @test program.attempts_per_site == 2
        runtime = CorePotts.initialize_program(
            program, test_initial(), Float64[], UInt64(0xa77), UInt32(1)
        )
        CorePotts.advance_mcs!(runtime)
        @test runtime.mcs == 1
    end
    @test_throws ArgumentError test_program(
        CorePotts.CheckerboardProgramEngine(); attempts_per_site = 0
    )
end

@testset "checkerboard colors use the versioned unbiased permutation" begin
    program = test_program(CorePotts.CheckerboardProgramEngine())
    runtime_a = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0xc010), UInt32(3);
        repeat = UInt32(2),
    )
    runtime_b = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0xc010), UInt32(3);
        repeat = UInt32(2),
    )
    foreign_replica = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0xc010), UInt32(4);
        repeat = UInt32(2),
    )
    first_workspace = CorePotts._checkerboard_core(runtime_a.engine_workspace)
    second_workspace = CorePotts._checkerboard_core(runtime_b.engine_workspace)
    foreign_workspace = CorePotts._checkerboard_core(
        foreign_replica.engine_workspace
    )
    color_count = Int(program.checkerboard_plan.color_count)
    canonical = collect(Int32, 1:color_count)

    orders = Tuple[]
    foreign_orders = Tuple[]
    first_counts = zeros(Int, color_count)
    sample_count = 8192
    for mcs in 0:sample_count-1
        first_state = CorePotts._checkerboard_state_at_mcs(
            first_workspace.state, mcs
        )
        second_state = CorePotts._checkerboard_state_at_mcs(
            second_workspace.state, mcs
        )
        foreign_state = CorePotts._checkerboard_state_at_mcs(
            foreign_workspace.state, mcs
        )
        first_order = CorePotts._checkerboard_color_order!(
            first_workspace.color_order, first_state, 1
        )
        second_order = CorePotts._checkerboard_color_order!(
            second_workspace.color_order, second_state, 1
        )
        foreign_order = CorePotts._checkerboard_color_order!(
            foreign_workspace.color_order, foreign_state, 1
        )
        @test sort(first_order) == canonical
        @test first_order == second_order
        first_counts[Int(first(first_order))] += 1
        mcs < 16 && push!(orders, Tuple(first_order))
        mcs < 16 && push!(foreign_orders, Tuple(foreign_order))
    end
    expected = sample_count / color_count
    @test maximum(abs.(first_counts .- expected)) < 0.06 * expected
    @test orders != foreign_orders

    state = CorePotts._checkerboard_state_at_mcs(
        first_workspace.state, sample_count
    )
    CorePotts._checkerboard_color_order!(
        first_workspace.color_order, state, 1
    )
    @test @allocated(CorePotts._checkerboard_color_order!(
        first_workspace.color_order, state, 1
    )) == 0
    @test CorePotts.RNG_CONTRACT_VERSION == v"2.0.0"
    @test CorePotts.RNG_LOWERING_IDENTITY ===
          :philox4x32x10_semantic_address_fisher_yates_v2
end

@testset "sequential and checkerboard share units, not trajectories" begin
    initial = test_initial()
    sequential = CorePotts.initialize_program(
        test_program(CorePotts.SequentialProgramEngine()),
        initial,
        Float64[],
        UInt64(0x5c1e),
        UInt32(1),
    )
    checkerboard = CorePotts.initialize_program(
        test_program(CorePotts.CheckerboardProgramEngine()),
        initial,
        Float64[],
        UInt64(0x5c1e),
        UInt32(1),
    )
    mcs_count = 12
    for _ in 1:mcs_count
        CorePotts.advance_mcs!(sequential)
        CorePotts.advance_mcs!(checkerboard)
    end
    expected_attempts = UInt64(mcs_count * length(initial.ownership))
    for runtime in (sequential, checkerboard)
        @test runtime.accepted + runtime.rejected + runtime.null_attempts ==
              expected_attempts
        @test only(CorePotts.program_tracker_values(
            runtime, Val(:cell_volume)
        )) == count(==(Int32(1)), runtime.ownership)
        @test runtime.mcs == mcs_count
    end
    @test sequential.ownership != checkerboard.ownership
end

@testset "successful runtime boundaries publish deterministic lifecycle receipts" begin
    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        program = test_program(engine)
        runtime = CorePotts.initialize_program(
            program, test_initial(), Float64[], UInt64(0x51ce), UInt32(3);
            repeat = UInt32(2),
        )
        mirror = CorePotts.initialize_program(
            program, test_initial(), Float64[], UInt64(0x51ce), UInt32(3);
            repeat = UInt32(2),
        )
        @test CorePotts.program_lifecycle_receipt(runtime) === nothing

        CorePotts.advance_mcs!(runtime)
        CorePotts.advance_mcs!(mirror)
        first = CorePotts.program_lifecycle_receipt(runtime)
        @test first isa CorePotts.LifecycleReceipt
        @test first.completed_mcs == 1
        @test isempty(first)
        @test first.transaction_identity ==
              CorePotts.program_lifecycle_receipt(mirror).transaction_identity

        restored = CorePotts.restore_program_checkpoint(
            program, CorePotts.program_checkpoint(runtime)
        )
        @test CorePotts.program_lifecycle_receipt(restored) === nothing
        CorePotts.advance_mcs!(runtime)
        CorePotts.advance_mcs!(restored)
        continued = CorePotts.program_lifecycle_receipt(runtime)
        replayed = CorePotts.program_lifecycle_receipt(restored)
        @test continued.completed_mcs == replayed.completed_mcs == 2
        @test continued.transaction_identity == replayed.transaction_identity
        @test continued.transaction_identity != first.transaction_identity
    end
end

@testset "program-step candidates publish only on explicit commit" begin
    program = test_program(
        CorePotts.SequentialProgramEngine(); parameter_defaults = [2.0]
    )
    runtime = CorePotts.initialize_program(
        program, test_initial(), [2.0], UInt64(0x57a9), UInt32(1)
    )
    before = CorePotts.program_snapshot(runtime)
    published_banks = (
        ownership = runtime.ownership,
        cell_kinds = runtime.cell_kinds,
        cell_generations = runtime.cell_generations,
        trackers = runtime.trackers,
        relationships = runtime.relationships,
        descriptor_state = runtime.descriptor_state,
    )

    staged = CorePotts.stage_program_mcs!(runtime)
    @test staged isa CorePotts.ProgramStepTransaction
    @test !runtime.settled
    @test runtime.ownership === published_banks.ownership
    @test runtime.cell_kinds === published_banks.cell_kinds
    @test runtime.cell_generations === published_banks.cell_generations
    @test runtime.trackers === published_banks.trackers
    @test runtime.relationships === published_banks.relationships
    @test runtime.descriptor_state === published_banks.descriptor_state
    @test_throws ArgumentError CorePotts.program_snapshot(runtime)
    @test CorePotts.program_step_lifecycle_receipt(staged).completed_mcs == 1
    candidate = CorePotts.program_step_snapshot(staged)
    @test candidate.mcs == 1
    @test_throws ArgumentError CorePotts.program_step_parameter_view(staged)
    CorePotts.stage_program_parameters!(staged, [3.0])
    @test CorePotts.program_step_parameter_view(staged) == [3.0]
    @test runtime.parameters == [2.0]
    @test_throws ArgumentError CorePotts.stage_program_parameters!(staged, [4.0])
    @test CorePotts.program_step_parameter_view(staged) == [3.0]
    @test CorePotts.abort_program_step!(staged) === runtime
    @test runtime.settled
    @test runtime.mcs == 0
    @test runtime.parameters == [2.0]
    @test CorePotts.program_lifecycle_receipt(runtime) === nothing
    after_abort = CorePotts.program_snapshot(runtime)
    @test after_abort.ownership == before.ownership
    @test after_abort.cell_kinds == before.cell_kinds
    @test after_abort.cell_generations == before.cell_generations

    committed = CorePotts.stage_program_mcs!(runtime)
    CorePotts.stage_program_parameters!(committed, [3.0])
    @test CorePotts.prevalidate_program_step_transaction(committed) === committed
    @test CorePotts.publish_program_step_transaction!(committed) === runtime
    @test runtime.settled
    @test runtime.mcs == 1
    @test runtime.parameters == [3.0]
    @test CorePotts.program_lifecycle_receipt(runtime).completed_mcs == 1
    @test_throws ArgumentError CorePotts.abort_program_step!(committed)

    wrapped = CorePotts.stage_program_mcs!(runtime)
    @test CorePotts.commit_program_step!(wrapped) === runtime
    @test runtime.mcs == 2
    @test runtime.parameters == [3.0]
end

@testset "descriptor-state staging is atomic and bank isolated" begin
    schema = CorePotts.StateBlockSchema(
        CorePotts.QualifiedResourceIdentity((), :coupled_marker),
        v"1.0.0",
        :model,
        Float64,
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
    layout = CorePotts.StateLayout([schema])
    handle = only(layout.entries).handle
    descriptor_plan = CorePotts.DescriptorExecutionPlan(
        (),
        layout,
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "coupled-state-descriptor-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
    program = test_program(
        CorePotts.SequentialProgramEngine(); descriptor_plan
    )
    base = test_initial()
    initial = CorePotts.ProgramInitialState(
        base.ownership,
        base.cell_kinds;
        scalar_type = Float64,
        descriptor_state = CorePotts.CompilerSPI.allocate_auxiliary_state(
            layout, (Float64[11, 12],)
        ),
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0xc0a1), UInt32(1)
    )
    initial_published_bank = runtime.descriptor_state

    aborted = CorePotts.BackendSPI.stage_program_mcs!(runtime)
    abort_candidate = CorePotts.BackendSPI.program_step_snapshot(
        aborted
    ).descriptor_state
    CorePotts.CompilerSPI.state_block(
        abort_candidate, handle
    ).values .= (21, 22)
    @test CorePotts.BackendSPI.stage_program_descriptor_state!(
        aborted, abort_candidate
    ) === aborted
    CorePotts.CompilerSPI.state_block(
        abort_candidate, handle
    ).values .= (91, 92)
    @test collect(CorePotts.CompilerSPI.state_block(
        CorePotts.BackendSPI.program_step_snapshot(aborted).descriptor_state,
        handle,
    ).values) == [21, 22]
    @test collect(CorePotts.CompilerSPI.state_block(
        initial_published_bank, handle
    ).values) == [11, 12]
    @test_throws ArgumentError CorePotts.program_snapshot(runtime)
    @test CorePotts.BackendSPI.prevalidate_program_step_transaction(aborted) ===
          aborted
    @test CorePotts.BackendSPI.abort_program_step!(aborted) === runtime
    @test runtime.descriptor_state === initial_published_bank
    @test collect(CorePotts.CompilerSPI.state_block(
        CorePotts.program_snapshot(runtime).descriptor_state, handle
    ).values) == [11, 12]
    @test_throws ArgumentError CorePotts.BackendSPI.stage_program_descriptor_state!(
        aborted, abort_candidate
    )

    committed = CorePotts.BackendSPI.stage_program_mcs!(runtime)
    commit_candidate = CorePotts.BackendSPI.program_step_snapshot(
        committed
    ).descriptor_state
    CorePotts.CompilerSPI.state_block(
        commit_candidate, handle
    ).values .= (31, 32)
    @test CorePotts.BackendSPI.stage_program_descriptor_state!(
        committed, commit_candidate
    ) === committed
    @test collect(CorePotts.CompilerSPI.state_block(
        initial_published_bank, handle
    ).values) == [11, 12]
    @test CorePotts.BackendSPI.commit_program_step!(committed) === runtime
    @test collect(CorePotts.CompilerSPI.state_block(
        CorePotts.program_snapshot(runtime).descriptor_state, handle
    ).values) == [31, 32]
    @test_throws ArgumentError CorePotts.BackendSPI.stage_program_descriptor_state!(
        committed, commit_candidate
    )

    rejected = CorePotts.BackendSPI.stage_program_mcs!(runtime)
    rejected_before = CorePotts.BackendSPI.program_step_snapshot(rejected)
    published_before_rejections = rejected.workspace.descriptor_state

    wrong_shape_schema = CorePotts.StateBlockSchema(
        schema.identity,
        schema.version,
        schema.domain,
        schema.element_type,
        (3,),
        3,
        schema.layout,
        schema.initialization,
        schema.validation,
        schema.persistence,
        schema.lifecycle,
        schema.read_policy,
        schema.write_policy,
        schema.adaptation,
        schema.settled_export,
        schema.checkpoint_codec,
        schema.inspection,
        schema.checkpoint,
    )
    wrong_shape = CorePotts.CompilerSPI.allocate_auxiliary_state(
        CorePotts.StateLayout([wrong_shape_schema]),
        (Float64[1, 2, 3],),
    )
    @test_throws ArgumentError CorePotts.BackendSPI.stage_program_descriptor_state!(
        rejected, wrong_shape
    )

    wrong_type_schema = CorePotts.StateBlockSchema(
        schema.identity,
        schema.version,
        schema.domain,
        Float32,
        schema.shape,
        schema.capacity,
        schema.layout,
        schema.initialization,
        schema.validation,
        schema.persistence,
        schema.lifecycle,
        schema.read_policy,
        schema.write_policy,
        schema.adaptation,
        schema.settled_export,
        schema.checkpoint_codec,
        schema.inspection,
        schema.checkpoint,
    )
    wrong_type = CorePotts.CompilerSPI.allocate_auxiliary_state(
        CorePotts.StateLayout([wrong_type_schema]),
        (Float32[1, 2],),
    )
    @test_throws ArgumentError CorePotts.BackendSPI.stage_program_descriptor_state!(
        rejected, wrong_type
    )

    nonfinite = CorePotts.CompilerSPI.allocate_auxiliary_state(
        layout, (Float64[1, 2],)
    )
    CorePotts.CompilerSPI.state_block(
        nonfinite, handle
    ).values[1] = NaN
    @test_throws ArgumentError CorePotts.BackendSPI.stage_program_descriptor_state!(
        rejected, nonfinite
    )
    @test_throws ArgumentError CorePotts.BackendSPI.stage_program_descriptor_state!(
        rejected, rejected.runtime.descriptor_state
    )
    @test_throws ArgumentError CorePotts.BackendSPI.stage_program_descriptor_state!(
        rejected, (Float64[1, 2],)
    )

    @test collect(CorePotts.CompilerSPI.state_block(
        CorePotts.BackendSPI.program_step_snapshot(rejected).descriptor_state,
        handle,
    ).values) == collect(CorePotts.CompilerSPI.state_block(
        rejected_before.descriptor_state, handle
    ).values) == [31, 32]
    @test collect(CorePotts.CompilerSPI.state_block(
        published_before_rejections, handle
    ).values) == [31, 32]
    @test CorePotts.BackendSPI.abort_program_step!(rejected) === runtime
    @test collect(CorePotts.CompilerSPI.state_block(
        CorePotts.program_snapshot(runtime).descriptor_state, handle
    ).values) == [31, 32]
end

@testset "unexpected staged-program failures restore a settled boundary" begin
    program = test_program(
        CorePotts.SequentialProgramEngine();
        stage_plan = injected_failure_stage_plan(),
        parameter_defaults = [2.0],
    )
    runtime = CorePotts.initialize_program(
        program, test_initial(), [2.0], UInt64(0x5afe), UInt32(1)
    )
    # The injected test-only stage effect is intentionally an external
    # mechanism and therefore supports execution but not exact replay,
    # capability evidence.  Exercise rollback through settled public state
    # instead of manufacturing a checkpoint for an unqualified mechanism.
    before = CorePotts.program_snapshot(runtime)
    counters = (
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
    )

    @test_throws ErrorException CorePotts.stage_program_mcs!(runtime)

    @test runtime.settled
    @test !CorePotts.program_failed(runtime)
    @test runtime.mcs == 0
    @test runtime.parameters == [2.0]
    @test CorePotts.program_lifecycle_receipt(runtime) === nothing
    @test (
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
    ) == counters
    after = CorePotts.program_snapshot(runtime)
    @test after.mcs == before.mcs
    @test after.ownership == before.ownership
    @test after.cell_kinds == before.cell_kinds
    @test after.cell_generations == before.cell_generations
    @test after.trackers.values == before.trackers.values
    @test collect(after.relationships) == collect(before.relationships)
    @test after.descriptor_state.banks == before.descriptor_state.banks
end
