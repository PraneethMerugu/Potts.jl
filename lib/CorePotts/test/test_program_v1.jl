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
        tracker_plan = CorePotts.TrackerExecutionPlan(
            (CorePotts.OwnershipCountTracker(),),
            "ownership-count-tracker-v1-test",
        ),
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
        tracker_plan,
        descriptor_plan,
        stage_plan,
        engine,
        CorePotts.CPUProgramBackend(),
        "core-program-v1-test",
    )
end

struct ExternalDoubleOccupancyTracker <: CorePotts.AbstractTrackerDescriptor end
CorePotts.tracker_quantity(::ExternalDoubleOccupancyTracker) =
    Val(:external_double_occupancy)
CorePotts.tracker_checkpoint_policy(::ExternalDoubleOccupancyTracker) =
    :persist_logical_state
CorePotts.tracker_inspection(::ExternalDoubleOccupancyTracker) = (
    quantity = :external_double_occupancy,
    source = :ownership,
    relation = :identity,
    domain = :cell,
    storage = :dense_int32,
    rebuild = :external_double_histogram,
    proposal_update = :external_source_target_double_delta,
    visibility = :accepted_commit,
    concurrency = :claimed_owner_exclusive,
    checkpoint = :persist_logical_state,
    proposal_cost = :constant,
    rebuild_cost = :lattice_linear,
)
function CorePotts.tracker_rebuild(
        ::ExternalDoubleOccupancyTracker, ownership, cell_kinds
    )
    values = zeros(Int32, length(cell_kinds))
    for owner in ownership
        owner > 0 && (values[Int(owner)] += Int32(2))
    end
    return values
end
@inline function CorePotts.tracker_proposal_update!(
        values,
        ::ExternalDoubleOccupancyTracker,
        target,
        old_owner::Int32,
        new_owner::Int32,
    )
    old_owner > 0 && (@inbounds values[Int(old_owner)] -= Int32(2))
    new_owner > 0 && (@inbounds values[Int(new_owner)] += Int32(2))
    return nothing
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
    @test CorePotts.program_tracker_values(
        runtime, Val(:cell_volume)
    )[1] == 0
    @test runtime.cell_kinds[1] == 0
    @test runtime.cell_generations[1] == UInt32(2)
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
        @test report.trackers.quantities === (:cell_volume,)
        @test CorePotts.program_capability_report(program).trackers.count == 1
        if engine isa CorePotts.CheckerboardProgramEngine
            plan_report = CorePotts.checkerboard_plan_report(
                program.checkerboard_plan
            )
            @test plan_report.algorithm === :canonical_realized_greedy_v1
            @test plan_report.site_count == prod(program.shape)
            @test plan_report.color_count >= 2
            @test first.engine_workspace isa CorePotts.CheckerboardWorkspace
            @test isconcretetype(typeof(first.engine_workspace))
            @test first.accepted + first.rejected + first.null_attempts ==
                  length(first.ownership) * Int(program.attempts_per_site)
            @test sum(CorePotts.program_tracker_values(
                first, Val(:cell_volume)
            )) == count(>(0), first.ownership)
        else
            @test program.checkerboard_plan isa CorePotts.NoCheckerboardPlan
        end
    end

    odd_periodic = CorePotts.CheckerboardPlan(
        (3, 3),
        (true, true),
        Int8[1 -1 0 0; 0 0 1 -1],
    )
    colors = Dict{Int32, Int}()
    for color in 1:Int(odd_periodic.color_count)
        first_index = Int(odd_periodic.color_offsets[color])
        stop_index = Int(odd_periodic.color_offsets[color + 1]) - 1
        for site in odd_periodic.sites[first_index:stop_index]
            colors[site] = color
        end
    end
    indices = CartesianIndices((3, 3))
    linear = LinearIndices((3, 3))
    for site in 1:9
        coordinates = Tuple(indices[site])
        for displacement in ((-1, 0), (1, 0), (0, -1), (0, 1))
            neighbor = CartesianIndex(
                mod1(coordinates[1] + displacement[1], 3),
                mod1(coordinates[2] + displacement[2], 3),
            )
            @test colors[Int32(site)] != colors[Int32(linear[neighbor])]
        end
    end

    @test_throws ArgumentError CorePotts.StageExecutionPlan(
        (), (), 1, 0, "inconsistent-stage-plan"
    )

    cleared_schema = CorePotts.StateBlockSchema(
        CorePotts.QualifiedResourceIdentity((), :checkerboard_cleared),
        v"1.0.0",
        :site,
        Float64,
        (6, 6),
        36,
        :structure_of_arrays,
        :provided_or_zero,
        :shape_and_finite,
        :logical,
        (declared = :ClearOnOwnershipChange,),
        :declared,
        :bounded_write,
        :adapt_storage,
        :copy,
        :logical_copy,
        :qualified,
        true,
    )
    cleared_layout = CorePotts.StateLayout([cleared_schema])
    cleared_plan = CorePotts.DescriptorExecutionPlan(
        (),
        cleared_layout,
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "unsupported-checkerboard-lifecycle",
        CorePotts.HamiltonianDomainResources(2, 0),
    )
    cleared_initial = CorePotts.ProgramInitialState(
        test_initial().ownership,
        Int16[2];
        scalar_type = Float64,
        descriptor_state = CorePotts.allocate_auxiliary_state(
            cleared_layout, (ones(Float64, 6, 6),)
        ),
    )
    cleared_runtime = CorePotts.initialize_program(
        test_program(
            CorePotts.CheckerboardProgramEngine();
            descriptor_plan = cleared_plan,
        ),
        cleared_initial,
        Float64[],
        UInt64(1),
        UInt32(1),
    )
    CorePotts.advance_mcs!(cleared_runtime)
    @test cleared_runtime.accepted > 0
    cleared_values = CorePotts.state_block(
        cleared_runtime.descriptor_state,
        only(cleared_layout.entries).handle,
    ).values
    @test any(iszero, cleared_values)

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

    checkerboard_program = test_program(CorePotts.CheckerboardProgramEngine())
    checkerboard_runtime = CorePotts.initialize_program(
        checkerboard_program,
        test_initial(),
        Float64[],
        UInt64(0x9a),
        UInt32(1),
    )
    CorePotts.advance_mcs!(checkerboard_runtime)
    @test @inferred(CorePotts.advance_mcs!(checkerboard_runtime)) ===
          checkerboard_runtime
    checkerboard_bytes = @allocated CorePotts.advance_mcs!(checkerboard_runtime)
    @test checkerboard_bytes <= 512 * 1024
end

@testset "external trackers use the generic execution path" begin
    plan = CorePotts.TrackerExecutionPlan(
        (
            CorePotts.OwnershipCountTracker(),
            ExternalDoubleOccupancyTracker(),
        ),
        "external-double-occupancy-plan-v1-test",
    )
    @test_throws ArgumentError CorePotts.TrackerExecutionPlan(
        (
            ExternalDoubleOccupancyTracker(),
            ExternalDoubleOccupancyTracker(),
        ),
        "duplicate-external-tracker",
    )
    @test isbitstype(typeof(CorePotts.tracker_kernel_plan(plan)))
    @test CorePotts.tracker_plan_report(plan).quantities ==
          (:cell_volume, :external_double_occupancy)
    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        program = test_program(engine; tracker_plan = plan)
        runtime = CorePotts.initialize_program(
            program,
            test_initial(),
            Float64[],
            UInt64(0x51),
            UInt32(1),
        )
        CorePotts.advance_mcs!(runtime)
        volumes = CorePotts.program_tracker_values(
            runtime, Val(:cell_volume)
        )
        external = CorePotts.program_tracker_values(
            runtime, Val(:external_double_occupancy)
        )
        @test external == Int32(2) .* volumes
        @test CorePotts.validate_tracker_state!(
            program.tracker_plan,
            runtime.trackers,
            runtime.ownership,
            runtime.cell_kinds,
        ) === runtime.trackers
        corrupted_trackers = CorePotts.copy_tracker_state(runtime.trackers)
        corrupted_trackers.values[2][1] += Int32(1)
        @test_throws ArgumentError CorePotts.validate_tracker_state!(
            program.tracker_plan,
            corrupted_trackers,
            runtime.ownership,
            runtime.cell_kinds,
        )
        restored = CorePotts.restore_program_checkpoint(
            program, CorePotts.program_checkpoint(runtime)
        )
        @test CorePotts.program_tracker_values(
            restored, Val(:external_double_occupancy)
        ) == external
        @test Core.Compiler.return_type(
            CorePotts.commit_tracker_updates!,
            Tuple{
                typeof(runtime.trackers),
                typeof(program.tracker_plan),
                CartesianIndex{2},
                Int32,
                Int32,
            },
        ) === Nothing
    end
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

    contradictory_create = CorePotts.CreateRelationshipRequest(
        1,
        2,
        (9.0, 2.0, 5.0);
        generation_a = 4,
        generation_b = 7,
        identity = 10,
    )
    duplicate_before = copy(state)
    CorePotts.apply_relationship_requests!(
        state,
        Int16[2, 2],
        generations,
        plan,
        [create, contradictory_create],
    )
    @test state.active == duplicate_before.active
    @test state.payload == duplicate_before.payload
    @test state.incident_edges == duplicate_before.incident_edges
    @test (state.endpoint_a[1], state.endpoint_b[1]) == (1, 2)
    @test (state.generation_a[1], state.generation_b[1]) == (4, 7)
    @test state.degree == Int16[1, 1]
    @test state.incident_edges[1, :] == Int32[1, 1]
    @test CorePotts.validate_relationship_integrity(
        state, plan, Int16[2, 2], generations
    ) === state

    invalid_incidence = copy(state)
    invalid_incidence.incident_edges[1, 1] = Int32(2)
    @test_throws ArgumentError CorePotts.validate_relationship_integrity(
        invalid_incidence, plan, Int16[2, 2], generations
    )
    invalid_degree = copy(state)
    invalid_degree.degree[1] = Int16(0)
    @test_throws ArgumentError CorePotts.validate_relationship_integrity(
        invalid_degree, plan, Int16[2, 2], generations
    )
    invalid_payload = copy(state)
    invalid_payload.payload[1][1] = NaN
    @test_throws DomainError CorePotts.validate_relationship_integrity(
        invalid_payload, plan, Int16[2, 2], generations
    )

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

    replacement_plan = CorePotts.RelationshipStoreSchema(
        1, 1, (scalar(0),)
    )
    function replaced_state(requests)
        value = CorePotts.ProgramRelationshipState(Float64, 1, 3, 1, 1)
        CorePotts.apply_relationship_requests!(
            value,
            Int16[2, 2, 2],
            UInt32[1, 1, 1],
            replacement_plan,
            [CorePotts.CreateRelationshipRequest(
                1, 2, (1.0,); identity = 1
            )],
        )
        CorePotts.apply_relationship_requests!(
            value,
            Int16[2, 2, 2],
            UInt32[1, 1, 1],
            replacement_plan,
            requests,
        )
        return value
    end
    remove = CorePotts.RemoveRelationshipRequest(1; identity = 20)
    replacement = CorePotts.CreateRelationshipRequest(
        2, 3, (2.0,); identity = 10
    )
    forward = replaced_state([remove, replacement])
    reverse = replaced_state([replacement, remove])
    for result in (forward, reverse)
        @test count(result.active) == 1
        @test (result.endpoint_a[1], result.endpoint_b[1]) == (2, 3)
        @test result.payload[1][1] == 2.0
        @test result.degree == Int16[0, 1, 1]
    end
    @test forward.active == reverse.active
    @test forward.endpoint_a == reverse.endpoint_a
    @test forward.endpoint_b == reverse.endpoint_b
    @test forward.payload == reverse.payload

    duplicate_remove_state = CorePotts.ProgramRelationshipState(
        Float64, 1, 2, 1, 1
    )
    CorePotts.apply_relationship_requests!(
        duplicate_remove_state,
        Int16[2, 2],
        UInt32[1, 1],
        replacement_plan,
        [CorePotts.CreateRelationshipRequest(1, 2, (1.0,); identity = 1)],
    )
    CorePotts.apply_relationship_requests!(
        duplicate_remove_state,
        Int16[2, 2],
        UInt32[1, 1],
        replacement_plan,
        [
            CorePotts.RemoveRelationshipRequest(1; identity = 2),
            CorePotts.RemoveRelationshipRequest(1; identity = 3),
        ],
    )
    @test iszero(count(duplicate_remove_state.active))
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

    state_layouts = map((1, 32, 1024)) do count
        CorePotts.StateLayout([
            state_schema(Symbol(:state_, index), Float64)
            for index in 1:count
        ])
    end
    workspace_layouts = map((1, 32, 1024)) do count
        CorePotts.WorkspaceLayout([
            workspace_schema(Symbol(:workspace_, index), Float64)
            for index in 1:count
        ])
    end
    @test allequal(typeof(layout) for layout in state_layouts)
    @test allequal(typeof(layout) for layout in workspace_layouts)

    states = map(CorePotts.allocate_auxiliary_state, state_layouts)
    workspaces = map(CorePotts.allocate_runtime_workspaces, workspace_layouts)
    @test allequal(typeof(state) for state in states)
    @test allequal(typeof(workspace) for workspace in workspaces)
    @test all(length(state.banks) == 1 for state in states)
    @test all(length(workspace.banks) == 1 for workspace in workspaces)
    @test size(CorePotts.state_block(
        last(states), last(last(state_layouts).entries).handle
    ).values) == (2,)
    @test size(CorePotts.workspace_block(
        last(workspaces), last(last(workspace_layouts).entries).handle
    ).values) == (2,)

    plans = map(state_layouts, workspace_layouts) do state_layout, workspace_layout
        CorePotts.DescriptorExecutionPlan(
            (),
            state_layout,
            workspace_layout,
            (),
            Any[],
            0,
            "count-stable-storage-plan",
            CorePotts.HamiltonianDomainResources(2, 0),
        )
    end
    programs = map(plans) do plan
        test_program(
            CorePotts.SequentialProgramEngine(); descriptor_plan = plan
        )
    end
    runtimes = map(programs, states) do program, descriptor_state
        initial = CorePotts.ProgramInitialState(
            zeros(Int32, program.shape),
            Int16[];
            scalar_type = Float64,
            descriptor_state,
        )
        CorePotts.initialize_program(
            program, initial, Float64[], UInt64(0x726), UInt32(1)
        )
    end
    @test allequal(typeof(program) for program in programs)
    @test allequal(typeof(runtime) for runtime in runtimes)
end

@testset "relationship declarations grow data rather than specialization" begin
    function repeated_relationship_program(count)
        schema = CorePotts.RelationshipStoreSchema(1, 1)
        return test_program(
            CorePotts.SequentialProgramEngine();
            relationships = ntuple(_ -> schema, count),
        )
    end
    programs = map(repeated_relationship_program, (1, 32, 1024))
    @test allequal(typeof(program.relationships) for program in programs)
    @test allequal(typeof(program) for program in programs)
    @test all(
        length(program.relationships.banks) == 1 for program in programs
    )

    runtimes = map(programs) do program
        initial = CorePotts.ProgramInitialState(
            zeros(Int32, program.shape),
            Int16[];
            scalar_type = Float64,
            relationships = fill(nothing, length(program.relationships)),
        )
        CorePotts.initialize_program(
            program, initial, Float64[], UInt64(0x725), UInt32(1)
        )
    end
    @test allequal(typeof(runtime.relationships) for runtime in runtimes)
    @test allequal(
        typeof(runtime.stage_buffers.relationship_transactions)
        for runtime in runtimes
    )
    @test all(
        length(runtime.relationships.banks) == 1 for runtime in runtimes
    )

    packed = map(
        runtime -> CorePotts.Adapt.adapt(Array, runtime.relationships), runtimes
    )
    @test allequal(typeof(storage) for storage in packed)
    @test allequal(typeof(only(storage.banks)) for storage in packed)
    @test length(last(packed)) == 1024
    final_view = last(packed)[1024]
    @test length(final_view.active) == 1
    @test size(final_view.incident_edges) == (1, 0)
end
