@testset "checkerboard evaluates before owner arbitration" begin
    backend = CorePotts.KernelAbstractions.CPU()
    old_owners = Int32[1, 1]
    new_owners = Int32[2, 3]
    priorities = UInt32[typemax(UInt32), 1]
    semantic_ids = Int32[1, 2]
    dispositions = UInt8[
        CorePotts._PROGRAM_CHECKERBOARD_CONSTRAINT,
        CorePotts._PROGRAM_CHECKERBOARD_ACCEPTED,
    ]
    maximums = zeros(UInt32, 3)
    identities = fill(typemax(UInt32), 3)
    state = CorePotts.initialize_program(
        test_program(CorePotts.CheckerboardProgramEngine()),
        test_initial(),
        Float64[],
        UInt64(7),
        UInt32(1),
    ).engine_workspace.state
    claim_priority = CorePotts._checkerboard_claim_priorities_kernel!(backend)
    claim_identity = CorePotts._checkerboard_claim_identities_kernel!(backend)
    select = CorePotts._checkerboard_select_kernel!(backend)
    claim_priority(
        old_owners,
        new_owners,
        priorities,
        dispositions,
        maximums,
        state,
        Int32(2);
        ndrange = 2,
    )
    CorePotts.KernelAbstractions.synchronize(backend)
    claim_identity(
        old_owners,
        new_owners,
        priorities,
        semantic_ids,
        dispositions,
        maximums,
        identities,
        state,
        Int32(2);
        ndrange = 2,
    )
    CorePotts.KernelAbstractions.synchronize(backend)
    select(
        old_owners,
        new_owners,
        priorities,
        semantic_ids,
        dispositions,
        maximums,
        identities,
        state,
        Int32(2);
        ndrange = 2,
    )
    CorePotts.KernelAbstractions.synchronize(backend)
    @test dispositions == UInt8[
        CorePotts._PROGRAM_CHECKERBOARD_CONSTRAINT,
        CorePotts._PROGRAM_CHECKERBOARD_ACCEPTED,
    ]
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
    @test !isdefined(CorePotts, :tracker_proposal_update!)
    external_descriptor = ExternalDoubleOccupancyTracker()
    external_contract = CorePotts.tracker_contract(external_descriptor)
    @test external_contract isa CorePotts.TrackerContract
    @test external_contract.storage isa
          CorePotts.DenseOwnerScalarStorage{Int32}
    @test external_contract.update_bound isa
          CorePotts.SourceTargetOwnerUpdateBound
    probe_program = test_program(CorePotts.SequentialProgramEngine())
    probe_source = CorePotts.tracker_source_view(
        probe_program, test_initial().ownership
    )
    @test CorePotts.tracker_proposal_delta(
        external_descriptor,
        probe_source,
        CartesianIndex(1, 1),
        Int32(1),
        Int32(2),
    ) === CorePotts.OwnerScalarDelta(Int32(2))
    @test CorePotts.tracker_recompute(
        external_descriptor, probe_source, Int16[2]
    ) == CorePotts.tracker_rebuild(
        external_descriptor, probe_source, Int16[2]
    )
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
            program,
        ) === runtime.trackers
        corrupted_trackers = CorePotts.copy_tracker_state(runtime.trackers)
        corrupted_trackers.values[2][1] += Int32(1)
        @test_throws ArgumentError CorePotts.validate_tracker_state!(
            program.tracker_plan,
            corrupted_trackers,
            runtime.ownership,
            runtime.cell_kinds,
            program,
        )
        report = CorePotts.program_capability_report(program)
        @test report.status === CorePotts.Supported
        @test report.maturity === CorePotts.Functional
        @test CorePotts.capability_authorizes_execution(report)
        @test !CorePotts.capability_authorizes_replay(report)
        replay_error = try
            CorePotts.program_checkpoint(runtime)
            nothing
        catch caught
            caught
        end
        @test replay_error isa CorePotts.ProgramCapabilityError
        @test replay_error.operation === :checkpoint
        @test Core.Compiler.return_type(
            CorePotts.commit_tracker_updates!,
            Tuple{
                typeof(runtime.trackers),
                typeof(program.tracker_plan),
                typeof(CorePotts.tracker_source_view(
                    program, runtime.ownership
                )),
                CartesianIndex{2},
                Int32,
                Int32,
            },
        ) === Nothing
    end
end
