@testset "relationship transactions are atomic and canonical" begin
    scalar(value) = CorePotts.CompiledScalar(Float64(value))
    function filtered_transaction(state, status, generations, schema, request)
        buffer = CorePotts.RelationshipTransactionBuffer(state, 1)
        CorePotts.reset_relationship_transaction!(buffer, state)
        CorePotts.emit_relationship_request!(buffer, request)
        CorePotts.prepare_relationship_transaction!(
            buffer, status, generations, schema
        )
        return buffer
    end
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
    @test_throws ArgumentError CorePotts.apply_relationship_requests!(
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

    capacity_schema = CorePotts.RelationshipStoreSchema(1, 2)
    capacity_state = CorePotts.ProgramRelationshipState(Float64, 1, 3, 2, 0)
    CorePotts.apply_relationship_requests!(
        capacity_state,
        Int16[2, 2, 2],
        UInt32[1, 1, 1],
        capacity_schema,
        [CorePotts.CreateRelationshipRequest(1, 2; identity = 1)],
    )
    filtered_capacity = filtered_transaction(
        capacity_state,
        Int16[2, 2, 2],
        UInt32[1, 1, 1],
        capacity_schema,
        CorePotts.CreateRelationshipRequest(
            2,
            3;
            identity = 2,
            on_failure = CorePotts.RelationshipFailureFilter,
        ),
    )
    @test filtered_capacity.filtered == 1
    @test filtered_capacity.filtered_total == 1
    @test filtered_capacity.staged.active == capacity_state.active
    @test filtered_capacity.staged.incident_edges ==
          capacity_state.incident_edges

    degree_schema = CorePotts.RelationshipStoreSchema(2, 1)
    degree_state = CorePotts.ProgramRelationshipState(Float64, 2, 3, 1, 0)
    CorePotts.apply_relationship_requests!(
        degree_state,
        Int16[2, 2, 2],
        UInt32[1, 1, 1],
        degree_schema,
        [CorePotts.CreateRelationshipRequest(1, 2; identity = 1)],
    )
    filtered_degree = filtered_transaction(
        degree_state,
        Int16[2, 2, 2],
        UInt32[1, 1, 1],
        degree_schema,
        CorePotts.CreateRelationshipRequest(
            1,
            3;
            identity = 2,
            on_failure = CorePotts.RelationshipFailureFilter,
        ),
    )
    @test filtered_degree.filtered == 1
    @test count(filtered_degree.staged.active) == 1
    @test filtered_degree.staged.degree == Int16[1, 1, 0]

    stale_state = CorePotts.ProgramRelationshipState(Float64, 2, 2, 2, 0)
    filtered_stale = filtered_transaction(
        stale_state,
        Int16[2, 2],
        UInt32[3, 5],
        CorePotts.RelationshipStoreSchema(2, 2),
        CorePotts.CreateRelationshipRequest(
            1,
            2;
            generation_a = 2,
            generation_b = 5,
            identity = 3,
            on_failure = CorePotts.RelationshipFailureFilter,
        ),
    )
    @test filtered_stale.filtered == 1
    @test iszero(count(filtered_stale.staged.active))

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

@testset "checkerboard relationship folds preserve duplicate policy" begin
    schema = CorePotts._CheckerboardImmutableRelationshipSchema(
        (Int32(1),),
        (Int32(1),),
        (Int32(1),),
        (Int32(2),),
        (Int32(1),),
        (Int32(1),),
    )

    remove = (Int32(1), Int32(1), Int32(1), UInt32(2), true)
    removed = (
        active = [false],
        endpoint_a = Int32[0],
        endpoint_b = Int32[0],
        generation_a = UInt32[0],
        generation_b = UInt32[0],
        degree = Int16[0, 0],
        incident_edges = Int32[0, 0],
        seen = [remove],
    )
    remove_transition = CorePotts._BoundaryRelationshipTransition{
        0,typeof(schema)}(schema)
    duplicate = remove_transition(removed, remove, Int32(1), nothing)
    @test all(write -> write.count == 0, values(duplicate.updates))

    prior_retune = (
        Int32(2), Int32(1), Int32(1), 3.0, UInt32(2), true)
    conflicting_retune = (
        Int32(2), Int32(1), Int32(1), 9.0, UInt32(3), true)
    active = (
        active = [true],
        endpoint_a = Int32[1],
        endpoint_b = Int32[2],
        generation_a = UInt32[1],
        generation_b = UInt32[1],
        payload_1 = [3.0],
        degree = Int16[1, 1],
        incident_edges = Int32[1, 1],
        seen = [prior_retune],
    )
    retune_transition = CorePotts._BoundaryRelationshipTransition{
        1,typeof(schema)}(schema)
    conflict = retune_transition(
        active, conflicting_retune, Int32(1), nothing)
    @test conflict.updates.active.count == 1
    @test only(conflict.updates.active.keys) == 0
    @test all(
        write.count == 0
        for (name, write) in pairs(conflict.updates)
        if name !== :active
    )

    create_transition = CorePotts._CheckerboardCompiledRelationshipTransition{
        1,typeof(schema)}(schema)
    create_state = (
        active = [true],
        endpoint_a = Int32[1],
        endpoint_b = Int32[2],
        generation_a = UInt32[1],
        generation_b = UInt32[1],
        payload_1 = [3.0],
        degree = Int16[1, 1],
        incident_edges = Int32[1, 1],
    )
    exact_create = (
        Int32(1), Int32(1), Int32(2), UInt32(1), UInt32(1), 3.0,
        Int32(1), Int32(1), UInt32(1), Int16(2), Int16(2), true,
    )
    contradictory_create = Base.setindex(exact_create, 9.0, 6)
    exact_step = create_transition(
        create_state, exact_create, Int32(1), nothing
    )
    @test all(write -> write.count == 0, values(exact_step.updates))
    contradictory_step = create_transition(
        create_state, contradictory_create, Int32(1), nothing
    )
    @test contradictory_step.updates.active.count == 1
    @test only(contradictory_step.updates.active.keys) == 0
    @test all(
        write.count == 0
        for (name, write) in pairs(contradictory_step.updates)
        if name !== :active
    )
end

@testset "CPU relationship-bank copies preserve nested isolation" begin
    source_state = CorePotts.ProgramRelationshipState(Float64, 3, 3, 2, 1)
    source_state.active[1] = true
    source_state.endpoint_a[1] = Int32(1)
    source_state.endpoint_b[1] = Int32(2)
    source_state.generation_a[1] = UInt32(3)
    source_state.generation_b[1] = UInt32(4)
    source_state.payload[1][1] = 2.5
    source_state.degree .= Int16[1, 1, 0]
    source_state.incident_edges[1, 1:2] .= Int32(1)

    source = CorePotts._pack_relationship_bank(identity, [source_state])
    source_view = source[1]
    @test Base.mightalias(source_view.active, source.active)
    @test Base.mightalias(source.active, source_view.active)
    @test Base.mightalias(
        source_view.incident_edges, source.incident_edges)
    @test Base.mightalias(
        source.incident_edges, source_view.incident_edges)
    destination = copy(source)
    @test CorePotts._packed_relationship_science(destination) ==
          CorePotts._packed_relationship_science(source)
    @test CorePotts._packed_relationship_schema(destination) ==
          CorePotts._packed_relationship_schema(source)
    for (target, values) in zip(
            (
                CorePotts._packed_relationship_science(destination)...,
                CorePotts._packed_relationship_schema(destination)...,
            ),
            (
                CorePotts._packed_relationship_science(source)...,
                CorePotts._packed_relationship_schema(source)...,
            ),
        )
        @test target !== values
        @test !Base.mightalias(target, values)
    end
    destination.active[1] = false
    destination.payload[1][1] = -1.0
    destination.incident_edges[1] = Int32(0)
    destination.edge_offsets[1] = Int32(7)
    @test source.active[1]
    @test source.payload[1][1] == 2.5
    @test source.incident_edges[1] == 1
    @test source.edge_offsets[1] == 1
end

@testset "settled host relationship transactions rebuild one atomic runtime" begin
    scalar(value) = CorePotts.CompiledScalar(Float64(value))
    schema = CorePotts.RelationshipStoreSchema(
        2, 2, (scalar(1), scalar(2))
    )
    ownership = zeros(Int32, 6, 6)
    ownership[2:3, 2:3] .= 1
    ownership[4:5, 4:5] .= 2
    initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2, 2];
        scalar_type = Float64,
        relationships = (nothing,),
    )
    create = CorePotts.BackendSPI.CreateRelationshipRequest(
        1,
        2,
        (3.0, 4.0);
        generation_a = 1,
        generation_b = 1,
        identity = 1,
    )
    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        program = test_program(engine; relationships = (schema,))
        runtime = CorePotts.initialize_program(
            program, initial, Float64[], UInt64(0x3511), UInt32(2)
        )
        CorePotts.advance_mcs!(runtime)
        if engine isa CorePotts.CheckerboardProgramEngine
            checkerboard = CorePotts._checkerboard_core(
                runtime.engine_workspace
            )
            primary_leaves = last.(CorePotts._program_state_copy_leaves(
                checkerboard.state
            ))
            alternate_leaves = last.(CorePotts._program_state_copy_leaves(
                checkerboard.alternate_state
            ))
            @test all(
                primary_leaf !== alternate_leaf &&
                    !Base.mightalias(primary_leaf, alternate_leaf)
                for primary_leaf in primary_leaves
                for alternate_leaf in alternate_leaves
            )
        end
        before = CorePotts.program_snapshot(runtime)
        candidate = CorePotts.BackendSPI.host_relationship_transaction(
            runtime, (1 => (create,),)
        )
        after = CorePotts.program_snapshot(candidate)
        @test count(before.relationships[1].active) == 0
        @test count(after.relationships[1].active) == 1
        @test after.relationships[1].payload[1][1] == 3.0
        @test after.relationships[1].payload[2][1] == 4.0
        @test after.ownership == before.ownership
        @test after.mcs == before.mcs
        @test candidate.accepted == runtime.accepted
        @test candidate.rejected == runtime.rejected
        @test candidate.null_attempts == runtime.null_attempts
        @test CorePotts.BackendSPI.relationship_edge_index(
            after.relationships[1], 2, 1
        ) == 1
        @test CorePotts.BackendSPI.relationship_edge_index(
            after.relationships[1], 1, 1
        ) === nothing

        @test_throws ArgumentError CorePotts.BackendSPI.host_relationship_transaction(
            runtime,
            (
                1 => (create,),
                1 => (create,),
            ),
        )
        @test_throws ArgumentError CorePotts.BackendSPI.host_relationship_transaction(
            runtime,
            (1 => (CorePotts.BackendSPI.CreateRelationshipRequest(
                1,
                1,
                (9.0, 9.0);
                generation_a = 1,
                generation_b = 1,
                identity = 2,
            ),),),
        )
        @test count(CorePotts.program_snapshot(runtime).relationships[1].active) == 0
    end


    profile_program = test_program(
        CorePotts.CheckerboardProgramEngine(); relationships = (schema,)
    )
    profile_base = CorePotts.initialize_program(
        profile_program,
        initial,
        Float64[],
        UInt64(0x3513),
        UInt32(2),
    )
    selected = profile_base
    @test all(prepared -> prepared isa LocalMath.PreparedPlan,
        selected.engine_workspace.color_laws.prepared)
    selected_identity = selected.engine_workspace.identity
    rebuilt = CorePotts.BackendSPI.host_relationship_transaction(
        selected, (1 => (create,),)
    )
    @test all(prepared -> prepared isa LocalMath.PreparedPlan,
        rebuilt.engine_workspace.color_laws.prepared)
    rebuilt_identity = rebuilt.engine_workspace.identity
    @test rebuilt_identity.queue_policy == selected_identity.queue_policy
    @test rebuilt_identity.scientific_abi == selected_identity.scientific_abi
    @test rebuilt_identity.lowerings == selected_identity.lowerings
    @test count(
        CorePotts.program_snapshot(rebuilt).relationships[1].active
    ) == 1

    sequential = test_program(
        CorePotts.SequentialProgramEngine(); relationships = (schema,)
    )
    unsettled = CorePotts.initialize_program(
        sequential, initial, Float64[], UInt64(0x3512), UInt32(1)
    )
    transaction = CorePotts.BackendSPI.stage_program_mcs!(unsettled)
    @test_throws ArgumentError CorePotts.BackendSPI.host_relationship_transaction(
        unsettled, (1 => (create,),)
    )
    CorePotts.BackendSPI.abort_program_step!(transaction)

    two_store_program = test_program(
        CorePotts.SequentialProgramEngine();
        relationships = (schema, schema),
    )
    two_store_initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2, 2];
        scalar_type = Float64,
        relationships = (nothing, nothing),
    )
    two_store_runtime = CorePotts.initialize_program(
        two_store_program,
        two_store_initial,
        Float64[],
        UInt64(0x3513),
        UInt32(1),
    )
    invalid_create = CorePotts.BackendSPI.CreateRelationshipRequest(
        1,
        1,
        (9.0, 9.0);
        generation_a = 1,
        generation_b = 1,
        identity = 2,
    )
    @test_throws ArgumentError CorePotts.BackendSPI.host_relationship_transaction(
        two_store_runtime,
        (
            1 => (create,),
            2 => (invalid_create,),
        ),
    )
    two_store_after = CorePotts.program_snapshot(two_store_runtime)
    @test all(
        state -> count(state.active) == 0,
        two_store_after.relationships,
    )

    relationship_checkpoint = CorePotts.program_checkpoint(rebuilt)
    @test all(
        bank -> bank isa CorePotts.PackedRelationshipBank,
        relationship_checkpoint.snapshot.relationships.banks,
    )
    @test relationship_checkpoint.snapshot.relationships.slots ==
        rebuilt.relationships.slots
    @test relationship_checkpoint.snapshot.relationships.slots !==
        rebuilt.relationships.slots
    relationship_restored = CorePotts.restore_program_checkpoint(
        profile_program, relationship_checkpoint
    )
    @test all(
        bank -> bank isa CorePotts.PackedRelationshipBank,
        relationship_restored.relationships.banks,
    )
    @test relationship_restored.relationships.slots ==
        relationship_checkpoint.snapshot.relationships.slots
    for _ in 1:4
        CorePotts.advance_mcs!(rebuilt)
        CorePotts.advance_mcs!(relationship_restored)
    end
    uninterrupted_snapshot = CorePotts.program_snapshot(rebuilt)
    restored_snapshot = CorePotts.program_snapshot(relationship_restored)
    @test uninterrupted_snapshot.ownership == restored_snapshot.ownership
    for index in eachindex(uninterrupted_snapshot.relationships)
        uninterrupted_relationship = uninterrupted_snapshot.relationships[index]
        restored_relationship = restored_snapshot.relationships[index]
        @test uninterrupted_relationship.active == restored_relationship.active
        @test uninterrupted_relationship.endpoint_a == restored_relationship.endpoint_a
        @test uninterrupted_relationship.endpoint_b == restored_relationship.endpoint_b
        @test uninterrupted_relationship.generation_a ==
              restored_relationship.generation_a
        @test uninterrupted_relationship.generation_b ==
              restored_relationship.generation_b
        @test uninterrupted_relationship.payload == restored_relationship.payload
        @test uninterrupted_relationship.degree == restored_relationship.degree
        @test uninterrupted_relationship.incident_edges ==
              restored_relationship.incident_edges
    end
    @test rebuilt.accepted == relationship_restored.accepted
    @test rebuilt.rejected == relationship_restored.rejected
    @test rebuilt.null_attempts == relationship_restored.null_attempts
end

@testset "logical checkpoints preserve exact continuation" begin
    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        program = test_program(engine; attempts_per_site = 1)
        uninterrupted = CorePotts.initialize_program(
            program, test_initial(), Float64[], UInt64(0x55), UInt32(1)
        )
        extension_values = Int32[3, 5]
        checkpoint = CorePotts.program_checkpoint(
            uninterrupted;
            extensions = (
                test_owner = (
                    schema = v"1.0.0",
                    label = :logical_state,
                    values = extension_values,
                ),
            ),
        )
        extension_values[1] = 99
        @test checkpoint.schema == v"3.0.0"
        @test checkpoint.extensions.test_owner.values == Int32[3, 5]
        @test CorePotts.validate_program_checkpoint(program, checkpoint) ===
              checkpoint
        restored = CorePotts.restore_program_checkpoint(program, checkpoint)
        for _ in 1:6
            CorePotts.advance_mcs!(uninterrupted)
            CorePotts.advance_mcs!(restored)
        end
        @test CorePotts.program_snapshot(uninterrupted).ownership ==
              CorePotts.program_snapshot(restored).ownership
        @test uninterrupted.accepted == restored.accepted
        @test uninterrupted.rejected == restored.rejected
        @test uninterrupted.null_attempts == restored.null_attempts
        @test uninterrupted.constraint_rejections ==
              restored.constraint_rejections
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
            checkpoint.extensions,
            "corrupt",
        )
        @test_throws ArgumentError CorePotts.restore_program_checkpoint(
            program, corrupted
        )

        tampered_extensions = (
            test_owner = (
                schema = v"1.0.0",
                label = :logical_state,
                values = Int32[9, 5],
            ),
        )
        tampered = CorePotts.ProgramCheckpoint(
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
            tampered_extensions,
            checkpoint.checksum,
        )
        @test_throws ArgumentError CorePotts.restore_program_checkpoint(
            program, tampered
        )
        @test_throws ArgumentError CorePotts.validate_program_checkpoint(
            program, tampered
        )
    end
end
@testset "initialization uses the semantic RNG address" begin
    first_draw = CorePotts.initialization_bounded(
        UInt64(0x1234), UInt32(1), UInt32(1), 1, 0, 17
    )
    repeated_draw = CorePotts.initialization_bounded(
        UInt64(0x1234), UInt32(1), UInt32(1), 1, 0, 17
    )
    next_draw = CorePotts.initialization_bounded(
        UInt64(0x1234), UInt32(1), UInt32(1), 1, 1, 17
    )
    retry_draw = CorePotts.initialization_bounded(
        UInt64(0x1234), UInt32(1), UInt32(2), 1, 0, 17
    )
    @test 1 <= first_draw <= 17
    @test first_draw == repeated_draw
    @test 1 <= next_draw <= 17
    @test 1 <= retry_draw <= 17
    @test CorePotts._trajectory_seed(
        UInt64(0x1234), UInt32(1), UInt32(1)
    ) != CorePotts._trajectory_seed(
        UInt64(0x1234), UInt32(1), UInt32(2)
    )
end

struct ExternalSquareOperation <: CorePotts.AbstractContextualOperation end

(::ExternalSquareOperation)(arguments, context) = only(arguments)^2
