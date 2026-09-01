struct UnqualifiedCapabilityTracker <: CorePotts.AbstractTrackerDescriptor end

module QualifiedAdapterNamespace
struct QualifiedArray end
end

CorePotts.tracker_contract(::UnqualifiedCapabilityTracker) =
    CorePotts.TrackerContract(
        Val(:unqualified_capability_tracker),
        CorePotts.OwnershipTrackerSource(),
        CorePotts.DenseOwnerScalarStorage{Int32}(),
        CorePotts.AcceptedCommitTrackerVisibility(),
        CorePotts.ClaimedOwnerExclusiveTrackerConcurrency(),
        CorePotts.SourceTargetOwnerUpdateBound(),
        CorePotts.PersistTrackerCheckpoint(),
        CorePotts.TrackerSupport(true, true, false, false, 0x5a01),
        CorePotts.ConstantTrackerCost(),
        CorePotts.LatticeLinearTrackerCost(),
    )

function _checkpoint_with_extensions(checkpoint, extensions)
    checksum = CorePotts._program_checkpoint_checksum(
        checkpoint.schema, checkpoint.program_fingerprint, checkpoint.snapshot,
        checkpoint.parameters, checkpoint.seed, checkpoint.replica,
        checkpoint.repeat, checkpoint.accepted, checkpoint.rejected,
        checkpoint.null_attempts, checkpoint.constraint_rejections,
        checkpoint.energy_rejections, checkpoint.retired_cells, extensions,
    )
    return CorePotts.ProgramCheckpoint(
        checkpoint.schema, checkpoint.program_fingerprint, checkpoint.snapshot,
        checkpoint.parameters, checkpoint.seed, checkpoint.replica,
        checkpoint.repeat, checkpoint.accepted, checkpoint.rejected,
        checkpoint.null_attempts, checkpoint.constraint_rejections,
        checkpoint.energy_rejections, checkpoint.retired_cells, extensions,
        checksum,
    )
end

@testset "typed program support is environment-independent" begin
    @test CorePotts.BackendSPI.rng_contract_identity() == (
        contract_version = CorePotts.RNG_CONTRACT_VERSION,
        lowering_identity = CorePotts.RNG_LOWERING_IDENTITY,
    )
    for (engine, expected_engine) in (
            (CorePotts.SequentialProgramEngine(), CorePotts.SequentialEngine),
            (CorePotts.CheckerboardProgramEngine(), CorePotts.CheckerboardEngine),
        ), T in (Float32, Float64)
        program = capability_test_program(test_program(engine); scalar_type = T)
        report = CorePotts.program_capability_report(program)
        @test report.status === CorePotts.Supported
        @test report.key.engine === expected_engine
        @test report.key.backend === CorePotts.CPUBackend
        @test report.key.scalar_type === T
        @test report.key.mechanisms.support_family ===
              :core_execution_protocol_v1
        @test report.exact_replay
        @test CorePotts.capability_authorizes_execution(report)
        @test CorePotts.capability_authorizes_replay(report)

        foreign_key = CorePotts.ProgramCapabilityKey(
            report.key.engine, report.key.backend, report.key.device,
            report.key.topology, report.key.scalar_type, report.key.math_policy,
            report.key.lifecycle, report.key.component_state,
            report.key.mechanisms, report.key.replay;
            environment = merge(report.key.environment, (
                architecture = :unreviewed_test_architecture,
            )),
        )
        status, _, exact_replay = CorePotts._capability_disposition(foreign_key)
        @test status === CorePotts.Supported
        @test exact_replay
    end
end


@testset "adapted device identity is namespace-independent" begin
    report = CorePotts.program_capability_report(
        test_program(CorePotts.CheckerboardProgramEngine()))
    adapted = CorePotts._adapted_program_capability_report(
        report, QualifiedAdapterNamespace.QualifiedArray)
    @test adapted.key.device === :QualifiedArray
end

@testset "exact checkpoints compare explicit execution contracts" begin
    program = test_program(CorePotts.SequentialProgramEngine())
    ownership = zeros(Int32, 6, 6)
    ownership[3:4, 3:4] .= 1
    runtime = CorePotts.initialize_program(
        program,
        CorePotts.ProgramInitialState(
            ownership, Int16[2]; scalar_type = Float64
        ),
        Float64[], UInt64(0x700), UInt32(1),
    )
    checkpoint = CorePotts.program_checkpoint(runtime)
    core = checkpoint.extensions.CorePotts
    @test core.schema == v"3.0.0"
    @test core.execution_contract == CorePotts._exact_execution_contract(
        CorePotts.program_capability_report(program).key
    )
    @test core.rng == (
        contract_version = CorePotts.RNG_CONTRACT_VERSION,
        lowering_identity = CorePotts.RNG_LOWERING_IDENTITY,
    )

    foreign_contract = merge(core.execution_contract, (
        environment = merge(core.execution_contract.environment, (
            architecture = :foreign_test_architecture,
        )),
    ))
    extensions = merge(checkpoint.extensions, (
        CorePotts = merge(core, (execution_contract = foreign_contract,)),
    ))
    foreign = _checkpoint_with_extensions(checkpoint, extensions)
    error = try
        CorePotts.validate_program_checkpoint(program, foreign)
        nothing
    catch caught
        caught
    end
    @test error isa ArgumentError
    @test occursin("execution contract mismatch", sprint(showerror, error))

    extensions = merge(checkpoint.extensions, (
        CorePotts = merge(core, (
            rng = merge(core.rng, (contract_version = v"99.0.0",)),
        )),
    ))
    @test_throws ArgumentError CorePotts.validate_program_checkpoint(
        program, _checkpoint_with_extensions(checkpoint, extensions)
    )
end

@testset "external execution support does not imply exact replay" begin
    plan = CorePotts.TrackerExecutionPlan(
        (CorePotts.OwnershipCountTracker(), ExternalDoubleOccupancyTracker()),
        "external-double-occupancy-plan-v1",
    )
    program = test_program(CorePotts.SequentialProgramEngine(); tracker_plan = plan)
    report = CorePotts.program_capability_report(program)
    @test report.status === CorePotts.Supported
    @test report.key.mechanisms.support_family ===
          :external_execution_protocol_v1
    @test !report.exact_replay
    @test CorePotts.capability_authorizes_execution(report)
    @test !CorePotts.capability_authorizes_replay(report)
    runtime = CorePotts.initialize_program(
        program, test_initial(), Float64[], UInt64(0x704), UInt32(1)
    )
    @test_throws CorePotts.ProgramCapabilityError CorePotts.program_checkpoint(runtime)
end

@testset "unsupported contracts fail before runtime mutation" begin
    base = test_program(CorePotts.SequentialProgramEngine())
    float16_program = capability_test_program(base; scalar_type = Float16)
    report = CorePotts.program_capability_report(float16_program)
    @test report.status === CorePotts.Unsupported
    @test !CorePotts.capability_authorizes_execution(report)
    @test_throws CorePotts.ProgramCapabilityError CorePotts.initialize_program(
        float16_program, test_initial(), Float16[], UInt64(0x702), UInt32(1)
    )

    plan = CorePotts.TrackerExecutionPlan(
        (UnqualifiedCapabilityTracker(),), "unsupported-tracker-plan-v1"
    )
    changed = capability_test_program(base; tracker_plan = plan)
    changed_report = CorePotts.program_capability_report(changed)
    @test changed_report.key.mechanisms.support_family === :unsupported
    @test changed_report.status === CorePotts.Unsupported

    adapted = capability_test_program(
        test_program(CorePotts.CheckerboardProgramEngine());
        backend = CorePotts.AdaptedProgramBackend{:UnknownTestDevice}(),
    )
    adapted_report = CorePotts.program_capability_report(adapted)
    @test adapted_report.status === CorePotts.Unsupported
    @test occursin("adaptation", adapted_report.reason)
    @test_throws CorePotts.ProgramCapabilityError CorePotts.initialize_program(
        adapted, test_initial(), Float64[], UInt64(0x703), UInt32(1)
    )

    cpu_only_plan = CorePotts.TrackerExecutionPlan(
        (CPUOnlyCapabilityTracker(),), "cpu-only-tracker-plan-v1"
    )
    cpu_only_adapted = capability_test_program(
        test_program(CorePotts.CheckerboardProgramEngine());
        backend = CorePotts.AdaptedProgramBackend{:UnknownTestDevice}(),
        tracker_plan = cpu_only_plan,
    )
    cpu_only_report = CorePotts.program_capability_report(cpu_only_adapted)
    @test cpu_only_report.key.mechanisms.support_family === :unsupported
    @test cpu_only_report.status === CorePotts.Unsupported

    for candidate in (
            capability_test_program(
                test_program(CorePotts.CheckerboardProgramEngine());
                backend = CorePotts.AdaptedProgramBackend{:UnknownTestDevice}(),
                descriptor_plan = cpu_only_descriptor_plan(),
            ),
            capability_test_program(
                test_program(CorePotts.CheckerboardProgramEngine());
                backend = CorePotts.AdaptedProgramBackend{:UnknownTestDevice}(),
                stage_plan = cpu_only_stage_plan(),
            ),
        )
        candidate_report = CorePotts.program_capability_report(candidate)
        @test candidate_report.key.mechanisms.support_family === :unsupported
        @test candidate_report.status === CorePotts.Unsupported
    end
end
