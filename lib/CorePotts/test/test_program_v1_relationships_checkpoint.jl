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
end

@testset "logical checkpoints preserve exact continuation" begin
    for engine in (
            CorePotts.SequentialProgramEngine(),
            CorePotts.CheckerboardProgramEngine(),
        )
        program = test_program(engine; attempts_per_site = 2)
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
        @test checkpoint.schema == v"2.0.0"
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
    @test retry_draw != first_draw
end

struct ExternalSquareOperation <: CorePotts.AbstractContextualOperation end

(::ExternalSquareOperation)(arguments, context) = only(arguments)^2
