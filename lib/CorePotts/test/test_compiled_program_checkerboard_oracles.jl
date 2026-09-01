import LocalMath

function _reference_checkerboard_proposal(state, color, attempt_round, item)
    plan = state.program.checkerboard_plan
    first_index = Int(plan.color_offsets[color])
    target_linear = Int32(plan.sites[first_index + item - 1])
    semantic_id = Int32(
        (attempt_round - 1) * length(state.ownership) + target_linear
    )
    direction_address = CorePotts.RNGAddress(
        stream = CorePotts.ProposalDirectionStream,
        mcs = state.mcs + 1,
        subround = color,
        operation = 2,
        entity_kind = CorePotts.SiteEntity,
        entity = semantic_id,
        draw = 0,
    )
    direction = Int(CorePotts.bounded_uint(
        CorePotts.Philox4x32x10V2(),
        CorePotts._trajectory_seed(state.seed, state.replica, state.repeat),
        direction_address,
        UInt32(size(state.program.proposal_offsets, 2)),
    )) + 1
    target = CartesianIndices(state.ownership)[Int(target_linear)]
    coordinates = ntuple(Val(2)) do axis
        raw = target[axis] + Int(state.program.proposal_offsets[axis, direction])
        if state.program.periodic[axis]
            return mod1(raw, size(state.ownership, axis))
        end
        return 1 <= raw <= size(state.ownership, axis) ? raw : 0
    end
    source = any(iszero, coordinates) ? nothing : CartesianIndex(coordinates)
    source_linear = source === nothing ? Int32(0) :
                    Int32(LinearIndices(state.ownership)[source])
    old_owner = state.ownership[target]
    new_owner = source === nothing ? old_owner : state.ownership[source]
    actionable = source !== nothing && old_owner != new_owner
    priority = if actionable
        priority_address = CorePotts.RNGAddress(
            stream = CorePotts.CheckerboardPriorityStream,
            mcs = state.mcs + 1,
            subround = color,
            operation = 4,
            entity_kind = CorePotts.SiteEntity,
            entity = semantic_id,
            draw = 0,
        )
        CorePotts._rng_word(
            CorePotts.Philox4x32x10V2(),
            CorePotts._trajectory_seed(state.seed, state.replica, state.repeat),
            priority_address,
        )
    else
        UInt32(0)
    end
    return (; target_site = target_linear, source_site = source_linear,
        old_owner, new_owner, priority, semantic_id)
end

function _reference_checkerboard_disposition(
        state, descriptor_plan, proposal, color)
    actionable = proposal.source_site != Int32(0) &&
                 proposal.old_owner != proposal.new_owner
    actionable || return CorePotts._PROGRAM_CHECKERBOARD_NULL
    CorePotts._extinction_copy_admitted(
        state, proposal.old_owner, proposal.new_owner
    ) || return CorePotts._PROGRAM_CHECKERBOARD_CONSTRAINT

    target = CartesianIndices(state.ownership)[Int(proposal.target_site)]
    source = CartesianIndices(state.ownership)[Int(proposal.source_site)]
    context = CorePotts._ProposalEvaluationContext(
        state,
        source,
        target,
        proposal.old_owner,
        proposal.new_owner,
        Int(proposal.semantic_id),
        color,
    )
    plan = descriptor_plan
    contributions = Vector{CorePotts.ProposalEvaluation{Float64}}(
        undef, CorePotts._descriptor_source_count(plan)
    )
    CorePotts.evaluate_proposal_contributions!(contributions, plan, context)
    delta_h = 0.0
    drive_energy = 0.0
    drive_log_bias = 0.0
    kinetic_modifier = 0.0
    constraints_allowed = true
    for source in eachindex(contributions)
        value = contributions[source]
        delta_h += value.delta_h
        drive_energy += value.drive_energy
        drive_log_bias += value.drive_log_bias
        kinetic_modifier += value.kinetic_modifier
        constraints_allowed &= value.constraints_allowed
    end
    evaluation = CorePotts.ProposalEvaluation(
        delta_h,
        drive_energy,
        drive_log_bias,
        kinetic_modifier,
        constraints_allowed,
    )
    temperature = CorePotts.compiled_scalar_value(
        state.program.temperature, state.parameters
    )
    result = CorePotts._proposal_acceptance_result(evaluation, temperature)
    result.code === CorePotts.ProposalAcceptanceConstraintRejected &&
        return CorePotts._PROGRAM_CHECKERBOARD_CONSTRAINT
    result.code === CorePotts.ProposalAcceptanceNonfinite &&
        return CorePotts._PROGRAM_CHECKERBOARD_NONFINITE
    result.code === CorePotts.ProposalAcceptanceZeroTemperatureDrive &&
        return CorePotts._PROGRAM_CHECKERBOARD_ZERO_T_DRIVE
    accepted = result.log_ratio >= zero(temperature)
    if !accepted && isfinite(result.log_ratio)
        address = CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = state.mcs + 1,
            subround = color,
            operation = 3,
            entity_kind = CorePotts.SiteEntity,
            entity = proposal.semantic_id,
            draw = 0,
        )
        draw = CorePotts.uniform_open01(
            Float64,
            CorePotts.Philox4x32x10V2(),
            CorePotts._trajectory_seed(state.seed, state.replica, state.repeat),
            address,
        )
        accepted = log(draw) < result.log_ratio
    end
    return accepted ? CorePotts._PROGRAM_CHECKERBOARD_ACCEPTED :
           CorePotts._PROGRAM_CHECKERBOARD_ENERGY
end

function _order_sensitive_descriptor_plan()
    access = CorePotts.ResourceAccess(
        (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
        CorePotts.NoWriteAccess(),
    )
    support = CorePotts.DescriptorSupport(true, true, true, true)
    values = (1.0e16, -1.0e16, 1.0)
    descriptors = [
        CorePotts.ProposalDescriptor(
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(value)),
            access,
            support,
            (),
            (),
            CorePotts.ProposalEnergyDriveRole(),
            source,
        ) for (source, value) in enumerate(values)
    ]
    descriptor = first(descriptors)
    strategy = CorePotts.DescriptorKernelStrategy{
        typeof(descriptor),
        typeof(descriptor.evaluator.expression),
        typeof(descriptor.access),
        typeof(descriptor.role),
        Val{:proposal},
    }()
    groups = (
        CorePotts.DescriptorGroup(
            CorePotts.DescriptorLaunch(strategy, descriptors, (), ()),
            (family = :order_sensitive_float64,),
        ),
    )
    return CorePotts.DescriptorExecutionPlan(
        groups,
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[:large_positive, :large_negative, :unit_residual],
        3,
        "order-sensitive-float64-descriptor-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
end

function _run_test_proposal_segment!(execution, state, color, attempt, count)
    return CorePotts._execute_compiled_checkerboard_color!(
        execution, state, color, attempt, count)
end

function _reference_conjunctive_dispositions(
        old_owners, new_owners, priorities, semantic_ids, dispositions
    )
    winners = Dict{Int32, Tuple{UInt32, Int32}}()
    for item in eachindex(dispositions)
        dispositions[item] == CorePotts._PROGRAM_CHECKERBOARD_ACCEPTED ||
            continue
        candidate = (priorities[item], semantic_ids[item])
        for key in (old_owners[item], new_owners[item])
            key > 0 || continue
            incumbent = get(winners, key, (UInt32(0), typemax(Int32)))
            if candidate[1] > incumbent[1] ||
                    (candidate[1] == incumbent[1] &&
                     candidate[2] < incumbent[2])
                winners[key] = candidate
            end
        end
    end
    result = copy(dispositions)
    for item in eachindex(result)
        result[item] == CorePotts._PROGRAM_CHECKERBOARD_ACCEPTED || continue
        candidate = (priorities[item], semantic_ids[item])
        selected = all(
            key -> key <= 0 || winners[key] == candidate,
            (old_owners[item], new_owners[item]),
        )
        selected || (result[item] = CorePotts._PROGRAM_CHECKERBOARD_CONFLICT)
    end
    return result
end

@testset "proposal records and deterministic folds match an independent scalar oracle" begin
    program = test_program(
        CorePotts.CheckerboardProgramEngine();
        descriptor_plan = _order_sensitive_descriptor_plan(),
    )
    runtime = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0x2303), UInt32(7)
    )
    execution = runtime.engine_workspace
    workspace = execution.core
    state = workspace.state
    attempt_round = 1
    color = findfirst(1:Int(state.program.checkerboard_plan.color_count)) do candidate
        count = Int(workspace.color_sizes[candidate])
        any(1:count) do item
            proposal = _reference_checkerboard_proposal(
                state, candidate, attempt_round, item
            )
            proposal.source_site != Int32(0) &&
                proposal.old_owner != proposal.new_owner
        end
    end
    @test color !== nothing
    active_count = Int(workspace.color_sizes[color])
    expected_proposals = [
        _reference_checkerboard_proposal(
            state, color, attempt_round, item
        ) for item in 1:active_count
    ]
    @test CorePotts._descriptor_source_count(
        program.descriptor_plan
    ) == 3
    actionable = findfirst(proposal ->
        proposal.source_site != Int32(0) &&
        proposal.old_owner != proposal.new_owner,
        expected_proposals,
    )
    @test actionable !== nothing
    proposal = expected_proposals[actionable]
    context = CorePotts._ProposalEvaluationContext(
        state,
        CartesianIndices(state.ownership)[Int(proposal.source_site)],
        CartesianIndices(state.ownership)[Int(proposal.target_site)],
        proposal.old_owner,
        proposal.new_owner,
        Int(proposal.semantic_id),
        color,
    )
    contributions = Vector{CorePotts.ProposalEvaluation{Float64}}(undef, 3)
    CorePotts.evaluate_proposal_contributions!(
        contributions, program.descriptor_plan, context
    )
    @test contributions[1].drive_energy +
          contributions[2].drive_energy +
          contributions[3].drive_energy == 1.0
    @test contributions[1].drive_energy +
          contributions[3].drive_energy +
          contributions[2].drive_energy == 0.0

    wait(CorePotts._clear_checkerboard_bulk!(execution, state))
    receipt = _run_test_proposal_segment!(
        execution,
        state,
        color,
        attempt_round,
        active_count,
    )
    wait(receipt)
    published_proposals = map(1:active_count) do item
        (; target_site = workspace.target_sites[item],
            source_site = workspace.source_sites[item],
            old_owner = workspace.old_owners[item],
            new_owner = workspace.new_owners[item],
            priority = workspace.priorities[item],
            semantic_id = workspace.semantic_ids[item])
    end
    @test published_proposals == expected_proposals
    published_dispositions = [
        _reference_checkerboard_disposition(
            state, program.descriptor_plan, proposal, color)
        for proposal in published_proposals
    ]
    @test workspace.dispositions[1:active_count] == published_dispositions
end

@testset "conjunctive arbitration applies two-key all-wins selection" begin
    program = test_program(CorePotts.CheckerboardProgramEngine())
    ownership = zeros(Int32, 6, 6)
    ownership[2, 2] = 1
    ownership[2, 5] = 2
    ownership[5, 2] = 3
    ownership[5, 5] = 4
    initial = CorePotts.ProgramInitialState(
        ownership, fill(Int16(2), 4); scalar_type = Float64
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0x5005), UInt32(1)
    )
    execution = runtime.engine_workspace
    workspace = execution.core
    color = 1
    active_count = Int(workspace.color_sizes[color])
    @test all(prepared -> prepared isa LocalMath.PreparedPlan,
        execution.color_laws.prepared)
    @test length(LocalMath.storage(
        execution.color_laws.prepared[1],
        execution.color_laws.declaration.winners,
    )) == length(workspace.state.cell_kinds) == 4
    wait(CorePotts._clear_checkerboard_bulk!(execution, workspace.state))
    receipt = CorePotts._execute_compiled_checkerboard_color!(
        execution, workspace.state, color, 1, active_count)
    wait(receipt)
    initial = map(1:active_count) do item
        proposal = (; target_site = workspace.target_sites[item],
            source_site = workspace.source_sites[item],
            old_owner = workspace.old_owners[item],
            new_owner = workspace.new_owners[item],
            priority = workspace.priorities[item],
            semantic_id = workspace.semantic_ids[item])
        _reference_checkerboard_disposition(
            workspace.state, program.descriptor_plan, proposal, color)
    end
    expected = _reference_conjunctive_dispositions(
        workspace.old_owners[1:active_count],
        workspace.new_owners[1:active_count],
        workspace.priorities[1:active_count],
        workspace.semantic_ids[1:active_count], initial)
    @test workspace.dispositions[1:active_count] == expected
end

@testset "checkerboard accepted effects use the compiled color law" begin
    schema = CorePotts.StateBlockSchema(
        CorePotts.QualifiedResourceIdentity((), :accepted_marker),
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
    layout = CorePotts.StateLayout([schema])
    handle = only(layout.entries).handle
    descriptor_plan = CorePotts.DescriptorExecutionPlan(
        (),
        layout,
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "accepted-marker-descriptor-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
    descriptor = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(7.0)),
        CorePotts.SiteAssignmentEffect(handle),
        CorePotts.AcceptedCopyStage(),
        CorePotts.ResourceAccess(
            (handle,),
            (handle,),
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
    stage_plan = CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup([descriptor]),),
        (),
        1,
        0,
        "accepted-marker-stage-plan-v1",
    )
    program = test_program(
        CorePotts.CheckerboardProgramEngine(); descriptor_plan, stage_plan
    )
    initial = test_initial()
    initial = CorePotts.ProgramInitialState(
        initial.ownership,
        initial.cell_kinds;
        scalar_type = Float64,
        descriptor_state = CorePotts.allocate_auxiliary_state(
            layout, (zeros(6, 6),)
        ),
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0xacce), UInt32(1)
    )
    CorePotts.advance_mcs!(runtime)
    marker = CorePotts.state_block(runtime.descriptor_state, handle).values
    @test runtime.engine_workspace isa CorePotts._CheckerboardExecutionWorkspace
    @test runtime.accepted > 0
    @test any(==(7.0), marker)

end

@testset "checkerboard accepted-copy relationship publication is transactional" begin
    schema = CorePotts.RelationshipStoreSchema(
        4, 2, (CorePotts.CompiledScalar(0.0),)
    )
    relationship_schemas = CorePotts.RelationshipStorage((schema,))
    effect = CorePotts.RelationshipCreateEffect(
        1,
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(Int32(1))),
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(Int32(2))),
        (
            CorePotts.StaticEvaluator(
                CorePotts.LiteralExpression(4.0)
            ),
        ),
    )
    descriptor = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
        effect,
        CorePotts.AcceptedCopyStage(),
        CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, true),
        1,
        1,
    )
    stage_plan = CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup([descriptor]),),
        (),
        1,
        0,
        "accepted-relationship-stage-plan-v1",
    )
    program = test_program(
        CorePotts.CheckerboardProgramEngine();
        relationships = relationship_schemas,
        stage_plan,
    )
    ownership = zeros(Int32, 6, 6)
    ownership[2:3, 2:3] .= 1
    ownership[4:5, 4:5] .= 2
    initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2, 2];
        scalar_type = Float64,
        relationships = ((),),
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0xacce), UInt32(1)
    )
    CorePotts.advance_mcs!(runtime)
    relationship = only(runtime.relationships)
    edge = only(findall(relationship.active))
    @test runtime.accepted > 0
    @test (relationship.endpoint_a[edge], relationship.endpoint_b[edge]) ==
          (Int32(1), Int32(2))
    @test relationship.payload[1][edge] == 4.0

    ordered_descriptor(payload, source_handle, buffer_slot) =
        CorePotts.CompiledStageDescriptor(
            descriptor.condition,
            descriptor.value,
            CorePotts.RelationshipCreateEffect(
                1,
                effect.endpoint_a,
                effect.endpoint_b,
                (CorePotts.StaticEvaluator(
                    CorePotts.LiteralExpression(payload)
                ),),
            ),
            descriptor.stage,
            descriptor.access,
            descriptor.support,
            source_handle,
            buffer_slot,
        )
    permuted_stage_plan = CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup([
            ordered_descriptor(11.0, 1, 2),
            ordered_descriptor(22.0, 2, 1),
        ]),),
        (),
        2,
        0,
        "accepted-relationship-permuted-buffer-order-v1",
    )
    permuted_program = test_program(
        CorePotts.CheckerboardProgramEngine();
        relationships = relationship_schemas,
        stage_plan = permuted_stage_plan,
    )
    permuted = CorePotts.initialize_program(
        permuted_program, initial, Float64[], UInt64(0xacce), UInt32(1)
    )
    ownership_before_conflict = copy(permuted.ownership)
    relationship_before_conflict = copy(only(permuted.relationships))
    @test_throws CorePotts.LifecycleBackendFailure CorePotts.advance_mcs!(
        permuted
    )
    permuted_relationship = only(permuted.relationships)
    @test permuted.mcs == 0
    @test permuted.ownership == ownership_before_conflict
    @test permuted_relationship.active == relationship_before_conflict.active
    @test permuted_relationship.payload == relationship_before_conflict.payload

    second_slot_effect = CorePotts.RelationshipCreateEffect(
        2,
        effect.endpoint_a,
        effect.endpoint_b,
        effect.payload,
    )
    second_slot_descriptor = CorePotts.CompiledStageDescriptor(
        descriptor.condition,
        descriptor.value,
        second_slot_effect,
        descriptor.stage,
        descriptor.access,
        descriptor.support,
        descriptor.source_handle,
        descriptor.buffer_slot,
    )
    second_slot_stage_plan = CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup([second_slot_descriptor]),),
        (),
        1,
        0,
        "accepted-relationship-shared-packed-bank-slot-v1",
    )
    second_slot_program = test_program(
        CorePotts.CheckerboardProgramEngine();
        relationships = CorePotts.RelationshipStorage((schema, schema)),
        stage_plan = second_slot_stage_plan,
    )
    second_slot_initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2, 2];
        scalar_type = Float64,
        relationships = ((), ()),
    )
    second_slot = CorePotts.initialize_program(
        second_slot_program,
        second_slot_initial,
        Float64[],
        UInt64(0xacce),
        UInt32(1),
    )
    CorePotts.advance_mcs!(second_slot)
    first_relationship, second_relationship = second_slot.relationships
    @test !any(first_relationship.active)
    second_edge = only(findall(second_relationship.active))
    @test second_relationship.payload[1][second_edge] == 4.0

    portable = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0xacce), UInt32(1)
    )
    adapted = CorePotts.adapt_checkerboard_workspace(
        Array, portable.engine_workspace.core
    )
    declaration = portable.engine_workspace.color_laws.declaration
    relationship_group = only(declaration.relationship_groups)
    @test keys(relationship_group.live_fields) ==
          keys(CorePotts._packed_relationship_science(
              adapted.state.relationships.banks[1]))
    @test keys(relationship_group.shadow_fields) ==
        keys(relationship_group.live_fields)
    @test all(zip(values(relationship_group.shadow_fields),
            values(relationship_group.live_fields))) do pair
        first(pair) != last(pair)
    end
    inspection = CorePotts.LocalMath.inspect(
        first(portable.engine_workspace.color_laws.prepared))
    labels = map(stage -> stage.origin.label, inspection.stages)
    @test :checkerboard_relationship_settlement in labels
    @test any(label -> startswith(
        String(label), "checkerboard_relationship_commit_"), labels)

    nonfinite_effect = CorePotts.RelationshipCreateEffect(
        1,
        CorePotts.StaticEvaluator(
            CorePotts.LiteralExpression(Int32(1))
        ),
        CorePotts.StaticEvaluator(
            CorePotts.LiteralExpression(Int32(2))
        ),
        (
            CorePotts.StaticEvaluator(
                CorePotts.LiteralExpression(NaN)
            ),
        ),
    )
    nonfinite_descriptor = CorePotts.CompiledStageDescriptor(
        descriptor.condition,
        descriptor.value,
        nonfinite_effect,
        descriptor.stage,
        descriptor.access,
        descriptor.support,
        descriptor.source_handle,
        descriptor.buffer_slot,
    )
    nonfinite_stage_plan = CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup([nonfinite_descriptor]),),
        (),
        1,
        0,
        "accepted-relationship-nonfinite-stage-plan-v1",
    )
    nonfinite_program = test_program(
        CorePotts.CheckerboardProgramEngine();
        relationships = relationship_schemas,
        stage_plan = nonfinite_stage_plan,
    )
    nonfinite = CorePotts.initialize_program(
        nonfinite_program,
        initial,
        Float64[],
        UInt64(0xacce),
        UInt32(1),
    )
    CorePotts.enqueue_program_mcs!(nonfinite)
    receipt = CorePotts.settle_program!(
        nonfinite,
        CorePotts.ProgramSettlementRequest(
            CorePotts.PublicStepSettlement; full_snapshot = true
        ),
    )
    @test receipt.status.code === CorePotts.ProgramStatusEvaluator
    @test receipt.status.detail === CorePotts.LifecycleDetailNonfiniteResult
    @test receipt.status.source == Int32(1)
    @test receipt.failure isa CorePotts.LifecycleEvaluatorFailure
    @test receipt.committed_mcs == 0
    @test !any(only(receipt.snapshot.relationships).active)
    @test all(prepared -> prepared isa LocalMath.PreparedPlan,
        nonfinite.engine_workspace.color_laws.prepared)

    second_schema = CorePotts.RelationshipStoreSchema(
        4, 2, (
            CorePotts.CompiledScalar(0.0),
            CorePotts.CompiledScalar(0.0),
        )
    )
    later_nonfinite_effect = CorePotts.RelationshipCreateEffect(
        2,
        effect.endpoint_a,
        effect.endpoint_b,
        (
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(NaN)),
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(7.0)),
        ),
    )
    later_nonfinite_descriptor = CorePotts.CompiledStageDescriptor(
        descriptor.condition,
        descriptor.value,
        later_nonfinite_effect,
        descriptor.stage,
        descriptor.access,
        descriptor.support,
        2,
        2,
    )
    cross_bank_stage_plan = CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup([
            descriptor,
            later_nonfinite_descriptor,
        ]),),
        (),
        2,
        0,
        "accepted-relationship-cross-bank-atomicity-v1",
    )
    cross_bank_program = test_program(
        CorePotts.CheckerboardProgramEngine();
        relationships = CorePotts.RelationshipStorage((schema, second_schema)),
        stage_plan = cross_bank_stage_plan,
    )
    cross_bank_initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2, 2];
        scalar_type = Float64,
        relationships = ((), ()),
    )
    cross_bank = CorePotts.initialize_program(
        cross_bank_program,
        cross_bank_initial,
        Float64[],
        UInt64(0xacce),
        UInt32(1),
    )
    CorePotts.enqueue_program_mcs!(cross_bank)
    cross_bank_receipt = CorePotts.settle_program!(
        cross_bank,
        CorePotts.ProgramSettlementRequest(
            CorePotts.PublicStepSettlement; full_snapshot = true
        ),
    )
    @test cross_bank_receipt.status.code === CorePotts.ProgramStatusEvaluator
    @test cross_bank_receipt.status.detail ===
        CorePotts.LifecycleDetailNonfiniteResult
    @test cross_bank_receipt.committed_mcs == 0
    @test cross_bank_receipt.snapshot.ownership == ownership
    @test all(relationship -> !any(relationship.active),
        cross_bank_receipt.snapshot.relationships)
end

@testset "checkerboard rejects undeclared host stage callbacks" begin
    program = test_program(
        CorePotts.CheckerboardProgramEngine();
        stage_plan = unsupported_host_callback_stage_plan(Ref(0)),
    )
    error = try
        CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0xa11c), UInt32(1)
        )
        nothing
    catch caught
        caught
    end
    @test error isa ArgumentError
    @test occursin("does not support UnsupportedHostCallbackEffect",
        sprint(showerror, error))
end

@testset "checkerboard configuration preflight is atomic" begin
    program = test_program(CorePotts.CheckerboardProgramEngine())
    raw = CorePotts._materialize_program(
        program, test_initial(), Float64[], UInt64(0xcafe), UInt32(1)
    )
    runtime = CorePotts._prepare_checkerboard_execution(
        raw; queue_mcs_capacity = 1
    )
    execution = runtime.engine_workspace
    workspace = execution.core
    _, destination, _ = CorePotts._checkerboard_transaction_banks(workspace, 0)
    destination = CorePotts._checkerboard_state_at_mcs(destination, 0)
    color_prepared = execution.color_laws.prepared
    destination_ownership = copy(destination.ownership)
    @test all(prepared -> prepared isa LocalMath.PreparedPlan,
        color_prepared)
    @test_throws ArgumentError CorePotts._enqueue_checkerboard_mcs!(
        execution, 0; workgroup_size = 0
    )
    @test destination.ownership == destination_ownership
    @test workspace.execution.submitted_mcs == 0
    wait(CorePotts._clear_checkerboard_bulk!(execution, destination))
    receipt = _run_test_proposal_segment!(
        execution,
        destination,
        1,
        1,
        Int(workspace.color_sizes[1]),
    )
    @test_throws ArgumentError CorePotts._preflight_checkerboard_mcs!(
        execution, 0)
    wait(receipt)
    @test isnothing(CorePotts._preflight_checkerboard_mcs!(execution, 0))
    @test workspace.execution.submitted_mcs == 0
    @test runtime.settled
    CorePotts.KernelAbstractions.synchronize(execution.color_laws.backend)
end

@testset "obsolete checkerboard checkpoint identities are rejected" begin
    program = test_program(CorePotts.CheckerboardProgramEngine())
    runtime = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0x1d), UInt32(1)
    )
    checkpoint = CorePotts.program_checkpoint(runtime)
    core = checkpoint.extensions.CorePotts
    obsolete_execution = merge(
        core.execution_lowering,
        (; mechanism_identity = :corepotts_checkerboard_direct_v1),
    )
    extensions = merge(
        checkpoint.extensions,
        (; CorePotts = merge(
            core, (; execution_lowering = obsolete_execution)
        )),
    )
    checksum = CorePotts._program_checkpoint_checksum(
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
        extensions,
    )
    obsolete = CorePotts.ProgramCheckpoint(
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
        extensions,
        checksum,
    )
    @test_throws ArgumentError CorePotts.restore_program_checkpoint(
        program, obsolete
    )
end

@testset "no-work and repeated settlement do not count a provider sync" begin
    program = test_program(CorePotts.CheckerboardProgramEngine())
    runtime = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0x5e77), UInt32(1)
    )
    position = runtime.engine_workspace.core.execution
    request = CorePotts.ProgramSettlementRequest(
        CorePotts.ObservationSettlement
    )
    initial_synchronizations = position.synchronization_count
    initial_settlements = position.settlement_count
    CorePotts.settle_program!(runtime, request)
    CorePotts.settle_program!(runtime, request)
    @test position.synchronization_count == initial_synchronizations
    @test position.settlement_count == initial_settlements + 2

    CorePotts.advance_mcs!(runtime)
    settled_synchronizations = position.synchronization_count
    settled_count = position.settlement_count
    CorePotts.settle_program!(runtime, request)
    @test position.synchronization_count == settled_synchronizations
    @test position.settlement_count == settled_count + 1
end
