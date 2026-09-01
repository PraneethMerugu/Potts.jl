@testset "cell moments provide local proposal geometry" begin
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (
            CorePotts.OwnershipCountTracker(),
            CorePotts.CellMomentsTracker{2, Float64}(),
        ),
        "cell-moments-plan-v1-test",
    )
    program = test_program(
        CorePotts.SequentialProgramEngine(); tracker_plan
    )
    runtime = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0xc311), UInt32(1)
    )
    @test CorePotts._cell_center(runtime, Int32(1)) == (3.0, 3.0)
    @test CorePotts._cell_length(runtime, Int32(1)) == 2.0
    target = CartesianIndex(3, 3)
    after_center = CorePotts._cell_center(
        runtime,
        Int32(1);
        replaced_site = target,
        replacement_owner = Int32(0),
    )
    @test all(isapprox.(after_center, (19 / 6, 19 / 6)))
    @test @allocated(CorePotts._cell_center(
        runtime,
        Int32(1);
        replaced_site = target,
        replacement_owner = Int32(0),
    )) == 0
    accesses = Ref(0)
    guarded = SingleSiteOwnershipProbe(
        runtime.ownership, target, accesses
    )
    count, _, old_owner, changed = CorePotts._cell_moment_overlay(
        program.tracker_plan,
        runtime.trackers,
        guarded,
        Int32(1),
        target,
        Int32(0),
    )
    @test (count, old_owner, changed) == (3, Int32(1), true)
    @test accesses[] == 1

    checkpoint_value = CorePotts.program_checkpoint(runtime)
    @test checkpoint_value.snapshot.trackers.values[1] isa Vector{Int32}
    @test checkpoint_value.snapshot.trackers.values[2] === nothing
    restored = CorePotts.restore_program_checkpoint(
        program, checkpoint_value
    )
    @test CorePotts.program_tracker_values(
        restored, Val(:cell_moments)
    ) == CorePotts.program_tracker_values(runtime, Val(:cell_moments))

    source = CorePotts.tracker_source_view(program, runtime.ownership)
    CorePotts.commit_tracker_updates!(
        runtime.trackers,
        program.tracker_plan,
        source,
        target,
        Int32(1),
        Int32(0),
    )
    @inbounds runtime.ownership[target] = Int32(0)
    @test CorePotts.validate_tracker_state!(
        program.tracker_plan,
        runtime.trackers,
        runtime.ownership,
        runtime.cell_kinds,
        program,
    ) === runtime.trackers
end

@testset "compiled and initial program boundaries own mutable inputs" begin
    marker_schema = CorePotts.StateBlockSchema(
        CorePotts.QualifiedResourceIdentity((), :owned_marker),
        v"1.0.0",
        :site,
        Float64,
        (6, 6),
        36,
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
    marker_layout = CorePotts.StateLayout([marker_schema])
    marker_handle = only(marker_layout.entries).handle

    descriptor = CorePotts.ProposalDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
        CorePotts.ResourceAccess(
            (),
            (),
            CorePotts.EmptyFootprint(),
            CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        (),
        (),
        CorePotts.ProposalDriveRole(),
        1,
    )
    descriptor_instances = typeof(descriptor)[descriptor]
    descriptor_strategy = CorePotts.DescriptorKernelStrategy{
        typeof(descriptor),
        typeof(descriptor.evaluator.expression),
        typeof(descriptor.access),
        typeof(descriptor.role),
        Val{:proposal},
    }()
    descriptor_groups = (
        CorePotts.DescriptorGroup(
            CorePotts.DescriptorLaunch(
                descriptor_strategy, descriptor_instances, (), ()
            ),
            (family = :owned_test,),
        ),
    )
    constraint = CorePotts.ParameterDomainConstraint(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(1.0)),
        0x01,
        Int32(1),
    )
    constraint_instances = typeof(constraint)[constraint]
    source_table = Any[:owned_source]
    domain_offsets = reshape(Int8[1, 0], 2, 1)
    domain_resources = CorePotts.HamiltonianDomainResources(
        domain_offsets,
        Int32[1],
        Int32[1],
        Int32[0],
    )
    descriptor_plan = CorePotts.DescriptorExecutionPlan(
        descriptor_groups,
        marker_layout,
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (CorePotts.ConstraintGroup(constraint_instances),),
        source_table,
        1,
        "owned-descriptor-plan-v1",
        domain_resources,
    )

    stage_descriptor = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
        CorePotts.SiteAssignmentEffect(marker_handle),
        CorePotts.AcceptedCopyStage(),
        CorePotts.ResourceAccess(
            (marker_handle,),
            (marker_handle,),
            CorePotts.FiniteSpatialFootprint(
                CorePotts.ProposalTargetFootprintAnchor(), ((0, 0),)
            ),
            CorePotts.FiniteSpatialFootprint(
                CorePotts.ProposalTargetFootprintAnchor(), ((0, 0),)
            ),
            CorePotts.ExclusiveWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        1,
        1,
    )
    stage_instances = typeof(stage_descriptor)[stage_descriptor]
    stage_plan = CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup(stage_instances),),
        (),
        1,
        0,
        "owned-stage-plan-v1",
    )

    surface_descriptors = CorePotts.CellSurfaceTracker[
        CorePotts.CellSurfaceTracker(Int32(1), Int16(1)),
    ]
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (
            CorePotts.OwnershipCountTracker(),
            CorePotts.DenseScalarTrackerGroup(surface_descriptors),
        ),
        "owned-tracker-plan-v1",
    )
    lifecycle_forbid_extinction = falses(2)
    lifecycle_plan = CorePotts.LifecycleExecutionPlan(
        CorePotts.LifecycleDescriptor{2, Float64}[],
        CorePotts.LifecycleEvaluatorStorage(Any[], Symbol[]),
        CorePotts.LifecycleStateRuleStorage(Any[]),
        CorePotts.LifecycleRelationshipRule[],
        (),
        NTuple{2, Int16}[],
        CorePotts.LifecycleRelationStorage(Any[], Val(2)),
        CorePotts.StablePriorityLifecycleConflicts,
        1,
        1,
        1,
        0,
        lifecycle_forbid_extinction,
    )
    relationship_storage = CorePotts.RelationshipStorage((
        CorePotts.RelationshipStoreSchema(2, 1),
    ))
    proposal_offsets = Int8[1 -1 0 0; 0 0 1 -1]
    parameter_defaults = Float64[2.0]
    authority_labels = Symbol[:reviewed]
    program = CorePotts.CompiledPottsProgram(
        (6, 6),
        (true, true),
        proposal_offsets,
        2,
        1,
        CorePotts.CompiledScalar(2.0, 1),
        1,
        parameter_defaults,
        relationship_storage,
        tracker_plan,
        descriptor_plan,
        stage_plan,
        CorePotts.SequentialProgramEngine(),
        CorePotts.CPUProgramBackend(),
        "owned-program-v1";
        medium_kinds = BitVector((true, false)),
        lifecycle_plan,
        ownership_change_handles = (marker_handle,),
        mechanism_authority = (labels = authority_labels,),
    )
    sealed_fingerprint = program.integrity_fingerprint

    fill!(proposal_offsets, Int8(0))
    parameter_defaults[1] = 99.0
    empty!(relationship_storage.slots)
    empty!(surface_descriptors)
    empty!(descriptor_instances)
    empty!(constraint_instances)
    empty!(source_table)
    fill!(domain_offsets, Int8(0))
    empty!(marker_layout.entries)
    empty!(stage_instances)
    fill!(lifecycle_forbid_extinction, true)
    push!(authority_labels, :mutated)

    @test count(!iszero, program.proposal_offsets) == 4
    @test program.parameter_defaults == [2.0]
    @test length(program.relationships) == 1
    @test length(program.tracker_plan.descriptors[2].descriptors) == 1
    @test length(program.descriptor_plan.groups[1].launch.instances) == 1
    @test length(program.descriptor_plan.constraints[1].instances) == 1
    @test program.descriptor_plan.source_table == Any[:owned_source]
    @test program.descriptor_plan.domain_resources.contact_offsets ==
          reshape(Int8[1, 0], 2, 1)
    @test length(program.descriptor_plan.state_layout.entries) == 1
    @test length(program.stage_plan.accepted_copy[1].instances) == 1
    @test program.lifecycle_plan.forbid_extinction == (false, false)
    @test program.mechanism_authority.labels == Symbol[:reviewed]
    @test program.integrity_fingerprint == sealed_fingerprint

    tampered = deepcopy(program)
    tampered.parameter_defaults[1] = 7.0
    @test_throws ArgumentError CorePotts.program_execution_report(tampered)

    reusable_layout = CorePotts.StateLayout([marker_schema])
    reusable_handle = only(reusable_layout.entries).handle
    reusable_plan = CorePotts.DescriptorExecutionPlan(
        (),
        reusable_layout,
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "reusable-initial-state-v1",
        CorePotts.HamiltonianDomainResources(2, 0),
    )
    reusable_program = test_program(
        CorePotts.SequentialProgramEngine(); descriptor_plan = reusable_plan
    )
    supplied_ownership = zeros(Int32, 6, 6)
    supplied_ownership[3:4, 3:4] .= 1
    supplied_kinds = Int16[2]
    supplied_descriptor_state = CorePotts.allocate_auxiliary_state(
        reusable_layout, (fill(2.0, 6, 6),)
    )
    reusable_initial = CorePotts.ProgramInitialState(
        supplied_ownership,
        supplied_kinds;
        scalar_type = Float64,
        descriptor_state = supplied_descriptor_state,
    )
    fill!(supplied_ownership, Int32(0))
    supplied_kinds[1] = 0
    fill!(
        CorePotts.state_block(
            supplied_descriptor_state, reusable_handle
        ).values,
        9.0,
    )
    exposed_ownership = reusable_initial.ownership
    fill!(exposed_ownership, Int32(0))
    exposed_descriptor_state = reusable_initial.descriptor_state
    fill!(
        CorePotts.state_block(
            exposed_descriptor_state, reusable_handle
        ).values,
        8.0,
    )
    @test count(==(Int32(1)), reusable_initial.ownership) == 4
    @test reusable_initial.cell_kinds == Int16[2]
    @test all(==(
        2.0
    ), CorePotts.state_block(
        CorePotts.program_initial_descriptor_state(reusable_initial),
        reusable_handle,
    ).values)

    first_runtime = CorePotts.initialize_program(
        reusable_program,
        reusable_initial,
        Float64[],
        UInt64(0x51),
        UInt32(1),
    )
    second_runtime = CorePotts.initialize_program(
        reusable_program,
        reusable_initial,
        Float64[],
        UInt64(0x51),
        UInt32(1),
    )
    fill!(
        CorePotts.state_block(
            first_runtime.descriptor_state, reusable_handle
        ).values,
        5.0,
    )
    @test all(==(
        2.0
    ), CorePotts.state_block(
        second_runtime.descriptor_state, reusable_handle
    ).values)
    @test first_runtime.program !== reusable_program
    fill!(reusable_program.proposal_offsets, Int8(0))
    @test CorePotts.advance_mcs!(second_runtime) === second_runtime
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
            CorePotts.FiniteSpatialFootprint(
                CorePotts.IterationSiteFootprintAnchor(),
                (),
            ),
            CorePotts.FiniteSpatialFootprint(
                CorePotts.IterationSiteFootprintAnchor(),
                (ntuple(_ -> 0, 2),),
            ),
            CorePotts.ExclusiveWriteAccess(),
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

    checkerboard_program = test_program(
        CorePotts.CheckerboardProgramEngine(); descriptor_plan, stage_plan
    )
    checkerboard = CorePotts.initialize_program(
        checkerboard_program, state, Float64[], UInt64(4), UInt32(1)
    )
    CorePotts.advance_mcs!(checkerboard)
    checkerboard_history = CorePotts.state_block(
        CorePotts.program_snapshot(checkerboard).descriptor_state,
        memory_entry.handle,
    ).values
    @test checkerboard_history == saved_history
end

@testset "model assignment is one buffered after-MCS transaction" begin
    schema = CorePotts.StateBlockSchema(
        CorePotts.QualifiedResourceIdentity((), :model_signal),
        v"1.0.0",
        :model,
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
    layout = CorePotts.StateLayout([schema])
    handle = only(layout.entries).handle
    descriptor_plan = CorePotts.DescriptorExecutionPlan(
        (),
        layout,
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "model-assignment-descriptor-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
    read_model = CorePotts.OperationExpression(
        CorePotts.operation_callable(Val(:model_bound_state_value), v"1.0.0"),
        CorePotts.StateExpression(handle),
    )
    value = CorePotts.OperationExpression(
        CorePotts.operation_callable(Val(:add), v"1.0.0"),
        read_model,
        CorePotts.LiteralExpression(1.0),
    )
    descriptor = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(value),
        CorePotts.ModelAssignmentEffect(handle),
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            (handle,),
            (handle,),
            CorePotts.EmptyFootprint(),
            CorePotts.ModelFootprint(),
            CorePotts.ExclusiveWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        1,
        1,
    )
    group = CorePotts.StageDescriptorGroup([descriptor])
    stage_plan = CorePotts.StageExecutionPlan(
        (), (group,), 0, 0, "model-assignment-stage-plan-v1"
    )
    program = test_program(
        CorePotts.SequentialProgramEngine(); descriptor_plan, stage_plan
    )
    base = test_initial()
    initial = CorePotts.ProgramInitialState(
        base.ownership,
        base.cell_kinds;
        scalar_type = Float64,
        descriptor_state = CorePotts.allocate_auxiliary_state(
            layout, ([2.0],)
        ),
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0x51a1), UInt32(1)
    )
    model_value(state) = only(CorePotts.state_block(
        state, handle
    ).values)
    snapshot_model_value(snapshot) = model_value(snapshot.descriptor_state)

    transaction = CorePotts.stage_program_mcs!(runtime)
    @test model_value(runtime.descriptor_state) == 2.0
    @test_throws ArgumentError CorePotts.program_snapshot(runtime)
    @test snapshot_model_value(
        CorePotts.program_step_snapshot(transaction)
    ) == 3.0
    CorePotts.abort_program_step!(transaction)
    @test snapshot_model_value(CorePotts.program_snapshot(runtime)) == 2.0

    committed = CorePotts.stage_program_mcs!(runtime)
    CorePotts.publish_program_step_transaction!(committed)
    @test snapshot_model_value(CorePotts.program_snapshot(runtime)) == 3.0

    checkerboard_program = test_program(
        CorePotts.CheckerboardProgramEngine(); descriptor_plan, stage_plan
    )
    checkerboard = CorePotts.initialize_program(
        checkerboard_program, initial, Float64[], UInt64(0x51a1), UInt32(1)
    )
    CorePotts.advance_mcs!(checkerboard)
    @test snapshot_model_value(CorePotts.program_snapshot(checkerboard)) == 3.0
    @test_throws ArgumentError CorePotts.StageExecutionPlan(
        (), (CorePotts.StageDescriptorGroup([
            CorePotts.CompiledStageDescriptor(
                descriptor.condition,
                descriptor.value,
                descriptor.effect,
                descriptor.stage,
                descriptor.access,
                descriptor.support,
                descriptor.source_handle,
                2,
            ),
        ]),), 0, 0, "sparse-model-buffer-slots"
    )
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
        @test report.backend === :CPUBackend
        @test report.numerical_policy.reductions === :deterministic
        @test report.trackers.quantities === (:cell_volume,)
        @test CorePotts.program_capability_report(program).trackers.count == 1
        if engine isa CorePotts.CheckerboardProgramEngine
            plan_report = CorePotts.checkerboard_plan_report(
                program.checkerboard_plan
            )
            @test plan_report.algorithm === :canonical_realized_greedy_v1
            @test plan_report.shape == program.shape
            @test plan_report.periodic == program.periodic
            @test plan_report.site_order == Tuple(
                program.checkerboard_plan.sites
            )
            @test plan_report.site_count == prod(program.shape)
            @test plan_report.color_count >= 2
            @test first.engine_workspace isa
                  CorePotts._CheckerboardExecutionWorkspace
            @test CorePotts._checkerboard_core(first.engine_workspace) isa
                  CorePotts.CheckerboardWorkspace
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
    @test_throws ArgumentError CorePotts.CheckerboardPlan(
        odd_periodic.shape,
        odd_periodic.periodic,
        reverse(copy(odd_periodic.sites)),
        copy(odd_periodic.color_offsets),
        copy(odd_periodic.conflict_displacements),
        odd_periodic.color_count,
        odd_periodic.maximum_color_size,
    )
    @test_throws MethodError CorePotts.CheckerboardPlan(
        copy(odd_periodic.sites),
        copy(odd_periodic.color_offsets),
        copy(odd_periodic.conflict_displacements),
        odd_periodic.color_count,
        odd_periodic.maximum_color_size,
    )
    supplied_sites = copy(odd_periodic.sites)
    supplied_offsets = copy(odd_periodic.color_offsets)
    supplied_displacements = copy(odd_periodic.conflict_displacements)
    owned_plan = CorePotts.CheckerboardPlan(
        odd_periodic.shape,
        odd_periodic.periodic,
        supplied_sites,
        supplied_offsets,
        supplied_displacements,
        odd_periodic.color_count,
        odd_periodic.maximum_color_size,
    )
    owned_report = CorePotts.checkerboard_plan_report(owned_plan)
    reverse!(supplied_sites)
    fill!(supplied_offsets, Int32(1))
    fill!(supplied_displacements, Int16(0))
    @test CorePotts.checkerboard_plan_report(owned_plan) == owned_report

    checkerboard_program = test_program(CorePotts.CheckerboardProgramEngine())
    function replace_checkerboard_plan(program, plan)
        return CorePotts.CompiledPottsProgram(
            program.shape,
            program.periodic,
            program.proposal_offsets,
            program.kind_count,
            program.medium_kind,
            program.temperature,
            program.attempts_per_site,
            program.parameter_defaults,
            program.relationships,
            program.tracker_plan,
            program.descriptor_plan,
            program.stage_plan,
            program.engine,
            program.backend,
            program.fingerprint;
            medium_kinds = program.medium_kinds,
            checkerboard_plan = plan,
        )
    end
    @test_throws ArgumentError replace_checkerboard_plan(
        checkerboard_program,
        CorePotts.CheckerboardPlan(
            (1, 1), (true, true), Int8[1 -1 0 0; 0 0 1 -1]
        ),
    )
    @test_throws ArgumentError replace_checkerboard_plan(
        checkerboard_program,
        CorePotts.CheckerboardPlan(
            checkerboard_program.shape,
            (false, true),
            checkerboard_program.proposal_offsets,
        ),
    )
    supplied_plan = CorePotts.CheckerboardPlan(
        checkerboard_program.shape,
        checkerboard_program.periodic,
        checkerboard_program.proposal_offsets,
    )
    rebound_program = replace_checkerboard_plan(
        checkerboard_program, supplied_plan
    )
    original_schedule = copy(rebound_program.checkerboard_plan.sites)
    reverse!(supplied_plan.sites)
    @test rebound_program.checkerboard_plan.sites == original_schedule

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
            ownership_change_handles = (
                only(cleared_layout.entries).handle,
            ),
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
