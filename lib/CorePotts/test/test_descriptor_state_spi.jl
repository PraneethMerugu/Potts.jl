function _descriptor_state_spi_plan()
    schema = CorePotts.CompilerSPI.StateBlockSchema(
        CorePotts.CompilerSPI.QualifiedResourceIdentity((), :coupled_state),
        v"1.0.0",
        :site,
        Float64,
        (2, 2),
        4,
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
    layout = CorePotts.CompilerSPI.StateLayout([schema])
    descriptor_plan = CorePotts.CompilerSPI.DescriptorExecutionPlan(
        (),
        layout,
        CorePotts.CompilerSPI.WorkspaceLayout(
            CorePotts.CompilerSPI.WorkspaceSchema[]
        ),
        (),
        Any[],
        Int32(0),
        "descriptor-state-spi-v1",
        CorePotts.CompilerSPI.HamiltonianDomainResources(0, 0),
    )
    return descriptor_plan, only(layout.entries).handle
end

@testset "state and workspace handles share checked indices" begin
    location = CorePotts.BlockLocation(1, (1,))
    for (Handle, Representation, owner) in (
            (
                CorePotts.CompilerSPI.StateHandle,
                CorePotts.DefaultStateStorageRepresentation,
                "state",
            ),
            (
                CorePotts.CompilerSPI.WorkspaceHandle,
                CorePotts.DefaultWorkspaceStorageRepresentation,
                "workspace",
            ),
        )
        handle = Handle(2, 3)
        @test CorePotts.CompilerSPI.handle_bank(handle) == 2
        @test CorePotts.CompilerSPI.handle_slot(handle) == 3
        bank_error = try
            Handle(0, 1)
            nothing
        catch caught
            caught
        end
        slot_error = try
            Handle{Representation}(1, 0, location)
            nothing
        catch caught
            caught
        end
        @test bank_error isa ArgumentError
        @test slot_error isa ArgumentError
        @test occursin("$owner bank ordinal", sprint(showerror, bank_error))
        @test occursin("$owner handle slot", sprint(showerror, slot_error))
    end
end

@testset "copy-returning descriptor-state backend SPI" begin
    ownership = zeros(Int32, 6, 6)
    ownership[3, 3] = 1

    no_state = CorePotts.ProgramInitialState(
        ownership, Int16[2]; scalar_type = Float64
    )
    @test CorePotts.BackendSPI.program_initial_descriptor_state(no_state) ===
          nothing

    descriptor_plan, handle = _descriptor_state_spi_plan()
    state = CorePotts.CompilerSPI.allocate_auxiliary_state(
        descriptor_plan.state_layout,
        (reshape(collect(1.0:4.0), 2, 2),),
    )
    initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2];
        scalar_type = Float64,
        cell_generations = UInt32[7],
        relationships = (Dict(:payload => [11]),),
        descriptor_state = state,
    )

    initial_copy =
        CorePotts.BackendSPI.program_initial_descriptor_state(initial)
    initial_values = CorePotts.CompilerSPI.state_block(
        initial_copy, handle
    ).values
    initial_values[1] = 99.0
    fresh_initial_copy =
        CorePotts.BackendSPI.program_initial_descriptor_state(initial)
    @test CorePotts.CompilerSPI.state_block(
        fresh_initial_copy, handle
    ).values[1] == 1.0

    replaced = CorePotts.BackendSPI.with_program_initial_descriptor_state(
        initial, initial_copy
    )
    initial_values[2] = 88.0
    @test CorePotts.CompilerSPI.state_block(
        CorePotts.BackendSPI.program_initial_descriptor_state(replaced),
        handle,
    ).values == [99.0 3.0; 2.0 4.0]

    # Rebuilding is an ownership boundary for every logical initial-state
    # field, not just the replacement auxiliary state.
    initial.ownership[1, 1] = 1
    initial.cell_kinds[1] = 3
    initial.cell_generations[1] = 8
    initial.relationships[1][:payload][1] = 12
    @test replaced.ownership[1, 1] == 0
    @test replaced.cell_kinds == Int16[2]
    @test replaced.cell_generations == UInt32[7]
    @test replaced.relationships[1][:payload] == [11]

    @test_throws ArgumentError CorePotts.BackendSPI.with_program_initial_descriptor_state(
        initial, (not = :auxiliary_state,)
    )
    expected_bank = only(fresh_initial_copy.banks)
    representation = typeof(expected_bank).parameters[1]
    short_state = CorePotts.AuxiliaryState((
        CorePotts.BlockBank{
            representation, Vector{Float64},
        }(ones(Float64, 3)),
    ))
    @test_throws ArgumentError CorePotts.BackendSPI.with_program_initial_descriptor_state(
        initial, short_state
    )
    wrong_type_state = CorePotts.AuxiliaryState((
        CorePotts.BlockBank{
            representation, Vector{Float32},
        }(ones(Float32, 4)),
    ))
    @test_throws ArgumentError CorePotts.BackendSPI.with_program_initial_descriptor_state(
        initial, wrong_type_state
    )
    nonfinite_state =
        CorePotts.BackendSPI.program_initial_descriptor_state(replaced)
    CorePotts.CompilerSPI.state_block(
        nonfinite_state, handle
    ).values[1] = NaN
    @test_throws ArgumentError CorePotts.BackendSPI.with_program_initial_descriptor_state(
        replaced, nonfinite_state
    )

    runtime_initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2];
        scalar_type = Float64,
        descriptor_state = state,
    )
    program = test_program(
        CorePotts.BackendSPI.SequentialProgramEngine(); descriptor_plan
    )
    runtime = CorePotts.initialize_program(
        program, runtime_initial, Float64[], UInt64(0x5a17), UInt32(1)
    )
    snapshot = CorePotts.program_snapshot(runtime)
    snapshot_copy =
        CorePotts.BackendSPI.program_snapshot_descriptor_state(snapshot)
    snapshot_values = CorePotts.CompilerSPI.state_block(
        snapshot_copy, handle
    ).values
    snapshot_values[1] = -1.0
    @test CorePotts.CompilerSPI.state_block(
        CorePotts.BackendSPI.program_snapshot_descriptor_state(snapshot),
        handle,
    ).values[1] == 1.0

    replacement_state = CorePotts.CompilerSPI.copy_auxiliary_state(
        descriptor_plan.state_layout, runtime.descriptor_state
    )
    CorePotts.CompilerSPI.state_block(
        replacement_state, handle
    ).values .= 6.0
    @test CorePotts.CompilerSPI.update_program_descriptor_state!(
        runtime, replacement_state
    ) === runtime
    published_before_failure = CorePotts.program_snapshot(runtime)
    invalid_replacement = CorePotts.CompilerSPI.copy_auxiliary_state(
        descriptor_plan.state_layout, replacement_state
    )
    CorePotts.CompilerSPI.state_block(
        invalid_replacement, handle
    ).values[1] = NaN
    @test_throws ArgumentError CorePotts.CompilerSPI.update_program_descriptor_state!(
        runtime, invalid_replacement
    )
    @test CorePotts.CompilerSPI.state_block(
        CorePotts.BackendSPI.program_snapshot_descriptor_state(
            CorePotts.program_snapshot(runtime)
        ),
        handle,
    ).values == CorePotts.CompilerSPI.state_block(
        CorePotts.BackendSPI.program_snapshot_descriptor_state(
            published_before_failure
        ),
        handle,
    ).values
    checkpoint = CorePotts.program_checkpoint(runtime)
    restored = CorePotts.restore_program_checkpoint(program, checkpoint)
    @test CorePotts.CompilerSPI.state_block(
        restored.descriptor_state, handle
    ).values == fill(6.0, 2, 2)

    malformed_initial = CorePotts.ProgramInitialState(
        ownership,
        Int16[2];
        scalar_type = Float64,
        descriptor_state = (not = :auxiliary_state,),
    )
    @test_throws ArgumentError CorePotts.BackendSPI.program_initial_descriptor_state(
        malformed_initial
    )

    malformed_payload = (not = :auxiliary_state,)
    malformed_snapshot = CorePotts.ProgramSnapshot{
        Float64,
        2,
        Tuple{},
        typeof(malformed_payload),
        Nothing,
    }(
        0,
        copy(ownership),
        Int16[2],
        UInt32[1],
        nothing,
        (),
        malformed_payload,
    )
    @test_throws ArgumentError CorePotts.BackendSPI.program_snapshot_descriptor_state(
        malformed_snapshot
    )
end
