function capability_test_program(
        program::CorePotts.CompiledPottsProgram;
        backend = program.backend,
        scalar_type = eltype(program.parameter_defaults),
        tracker_plan = program.tracker_plan,
    )
    T = scalar_type
    checkerboard_plan = program.engine isa CorePotts.CheckerboardProgramEngine ?
                        program.checkerboard_plan :
                        CorePotts.NoCheckerboardPlan()
    return CorePotts.CompiledPottsProgram(
        program.shape,
        program.periodic,
        program.proposal_offsets,
        program.kind_count,
        program.medium_kind,
        CorePotts.CompiledScalar(T(3)),
        program.attempts_per_site,
        T[],
        program.relationships,
        tracker_plan,
        program.descriptor_plan,
        program.stage_plan,
        program.engine,
        backend,
        program.fingerprint * "-capability";
        medium_kinds = program.medium_kinds,
        lifecycle_plan = program.lifecycle_plan,
        checkerboard_plan,
        ownership_change_handles = program.ownership_change_handles,
        mechanism_authority = program.mechanism_authority,
    )
end

struct UnqualifiedCapabilityTracker <: CorePotts.AbstractTrackerDescriptor end
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

@testset "structured program capability profiles" begin
    for (engine, expected_engine, suite) in (
            (
                CorePotts.SequentialProgramEngine(),
                CorePotts.SequentialEngine,
                :sequential_cpu_functional_v1,
            ),
            (
                CorePotts.CheckerboardProgramEngine(),
                CorePotts.CheckerboardEngine,
                :checkerboard_cpu_functional_v1,
            ),
        )
        program = test_program(engine)
        report = CorePotts.program_capability_report(program)

        @test report isa CorePotts.ProgramCapabilityReport
        @test report.key isa CorePotts.ProgramCapabilityKey
        @test report.key.engine === expected_engine
        @test report.key.backend === CorePotts.CPUBackend
        @test report.key.device === :host_cpu
        @test report.key.dimension == 2
        @test report.key.topology == (
            CorePotts.PeriodicBoundary,
            CorePotts.PeriodicBoundary,
        )
        @test report.key.scalar_type === Float64
        @test report.key.math_policy == CorePotts.CapabilityMathPolicy(
            :accurate, :deterministic, :checked
        )
        @test report.key.lifecycle.family === :none
        @test report.key.lifecycle.fingerprint == "none"
        @test report.key.component_state.scope === :none
        @test isempty(report.key.component_state.identities)
        @test isempty(report.key.component_state.domains)
        @test report.key.component_state.schema_fingerprint == "none"
        @test report.key.mechanisms isa CorePotts.CapabilityMechanismProfile
        @test report.key.mechanisms.qualification_family ===
              :core_execution_protocol_v1
        @test !isempty(report.key.mechanisms.proposal_fingerprint)
        @test !isempty(report.key.mechanisms.descriptor_fingerprint)
        @test !isempty(report.key.mechanisms.stage_fingerprint)
        @test !isempty(report.key.mechanisms.relationship_fingerprint)
        @test !isempty(report.key.mechanisms.tracker_fingerprint)
        if expected_engine === CorePotts.SequentialEngine
            @test report.key.mechanisms.checkerboard_fingerprint == "none"
        else
            @test !isempty(report.key.mechanisms.checkerboard_fingerprint)
        end
        @test report.key.replay === CorePotts.ExactConfigurationReplay
        environment = report.key.environment
        @test environment.julia_version == VERSION
        @test environment.julia_commit == Base.GIT_VERSION_INFO.commit
        @test environment.kernel === Sys.KERNEL
        @test environment.architecture === Sys.ARCH
        @test environment.machine == Sys.MACHINE
        @test environment.cpu_name == Sys.CPU_NAME
        @test environment.cpu_threads == Sys.CPU_THREADS
        @test environment.julia_threads == Base.Threads.nthreads()
        @test environment.llvm_version == Base.libllvm_version
        @test environment.corepotts.uuid ==
              string(Base.PkgId(CorePotts).uuid)
        @test Set(entry.name for entry in environment.dependencies) == Set((
            :AcceleratedKernels,
            :Adapt,
            :Atomix,
            :KernelAbstractions,
            :LinearAlgebra,
            :SHA,
        ))
        @test all(!isempty(entry.uuid) for entry in environment.dependencies)
        @test CorePotts._capability_digest(environment) in
              CorePotts._REVIEWED_EXACT_ENVIRONMENT_DIGESTS

        @test report.status === CorePotts.Supported
        @test report.maturity === CorePotts.ReplayQualified
        @test report.evidence isa CorePotts.CapabilityEvidenceIdentity
        @test report.evidence.authority === :CorePotts
        @test report.evidence.suite === suite
        @test report.evidence.revision == v"1.0.0"
        @test report.evidence.profile_fingerprint ==
              CorePotts._capability_key_fingerprint(report.key)
        @test occursin("continuation", report.reason)
        @test CorePotts.capability_authorizes_execution(report)
        @test CorePotts.capability_authorizes_replay(report)

        # These remain inspection facts, not independently composable claims.
        @test report.trackers.count == 1
        @test isempty(report.state_domains)
        @test !report.relationships
        @test !hasproperty(report, :sequential)
        @test !hasproperty(report, :checkerboard)
        @test !hasproperty(report, :cpu)
        @test !hasproperty(report, :gpu)
    end
end

@testset "exact replay binds checkpoint execution environment" begin
    program = test_program(CorePotts.SequentialProgramEngine())
    ownership = zeros(Int32, 6, 6)
    ownership[3:4, 3:4] .= 1
    initial = CorePotts.ProgramInitialState(
        ownership, Int16[2]; scalar_type = Float64
    )
    runtime = CorePotts.initialize_program(
        program,
        initial,
        Float64[],
        UInt64(0x700),
        UInt32(1),
    )
    checkpoint = CorePotts.program_checkpoint(runtime)
    key = CorePotts.program_capability_report(program).key

    @test checkpoint.extensions.CorePotts.environment == key.environment
    @test checkpoint.extensions.CorePotts.capability_fingerprint ==
          CorePotts._capability_key_fingerprint(key)
    @test_throws ArgumentError CorePotts.program_checkpoint(
        runtime; extensions = (CorePotts = (forged = true,),)
    )

    foreign_environment = merge(
        key.environment, (architecture = :foreign_test_architecture,)
    )
    foreign_key = CorePotts.ProgramCapabilityKey(
        key.engine,
        key.backend,
        key.device,
        key.topology,
        key.scalar_type,
        key.math_policy,
        key.lifecycle,
        key.component_state,
        key.mechanisms,
        key.replay;
        environment = foreign_environment,
    )
    @test CorePotts._capability_key_fingerprint(foreign_key) !=
          CorePotts._capability_key_fingerprint(key)
    foreign_status, foreign_maturity, _, foreign_evidence =
        CorePotts._capability_disposition(foreign_key)
    @test foreign_status === CorePotts.Supported
    @test foreign_maturity === CorePotts.Functional
    @test foreign_evidence isa CorePotts.CapabilityEvidenceIdentity
    @test foreign_evidence.suite === :sequential_cpu_protocol_v1
    @test foreign_evidence.profile_fingerprint ==
          CorePotts._capability_key_fingerprint(foreign_key)

    foreign_extensions = merge(checkpoint.extensions, (
        CorePotts = merge(checkpoint.extensions.CorePotts, (
            capability_fingerprint =
                CorePotts._capability_key_fingerprint(foreign_key),
            environment = foreign_environment,
        )),
    ))
    foreign_checksum = CorePotts._program_checkpoint_checksum(
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
        foreign_extensions,
    )
    foreign_checkpoint = CorePotts.ProgramCheckpoint(
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
        foreign_extensions,
        foreign_checksum,
    )
    error = try
        CorePotts.validate_program_checkpoint(program, foreign_checkpoint)
        nothing
    catch caught
        caught
    end
    @test error isa ArgumentError
    @test occursin(
        "execution environment mismatch", sprint(showerror, error)
    )
end

@testset "external all-true support cannot mint replay evidence" begin
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (
            CorePotts.OwnershipCountTracker(),
            ExternalDoubleOccupancyTracker(),
        ),
        "external-all-true-capability-test",
    )
    program = test_program(
        CorePotts.SequentialProgramEngine(); tracker_plan
    )
    report = CorePotts.program_capability_report(program)
    @test report.key.mechanisms.qualification_family ===
          :external_execution_protocol_v1
    @test !isempty(report.key.mechanisms.code_identities)
    @test report.status === CorePotts.Supported
    @test report.maturity === CorePotts.Functional
    @test report.evidence isa CorePotts.CapabilityEvidenceIdentity
    @test report.evidence.suite === :sequential_external_cpu_protocol_v1
    @test report.evidence.profile_fingerprint ==
          CorePotts._capability_key_fingerprint(report.key)
    @test CorePotts.capability_authorizes_execution(report)
    @test !CorePotts.capability_authorizes_replay(report)

    ownership = zeros(Int32, 6, 6)
    ownership[3:4, 3:4] .= 1
    initial = CorePotts.ProgramInitialState(
        ownership, Int16[2]; scalar_type = Float64
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0x704), UInt32(1)
    )
    error = try
        CorePotts.program_checkpoint(runtime)
        nothing
    catch caught
        caught
    end
    @test error isa CorePotts.ProgramCapabilityError
    @test error.operation === :checkpoint
end

@testset "adaptation is not device evidence" begin
    cpu_program = test_program(CorePotts.CheckerboardProgramEngine())
    adapted_program = capability_test_program(
        cpu_program;
        backend = CorePotts.AdaptedProgramBackend{:MetalTestDevice}(),
    )
    report = CorePotts.program_capability_report(adapted_program)

    @test report.key.backend === CorePotts.AdaptedBackend
    @test report.key.device === :MetalTestDevice
    @test report.status === CorePotts.Unsupported
    @test report.maturity === CorePotts.InterfaceOnly
    @test isnothing(report.evidence)
    @test occursin("no real-device evidence", report.reason)
    @test !CorePotts.capability_authorizes_execution(report)
    @test !CorePotts.capability_authorizes_replay(report)

    error = try
        CorePotts.initialize_program(
            adapted_program,
            test_initial(),
            Float64[],
            UInt64(0x701),
            UInt32(1),
        )
        nothing
    catch caught
        caught
    end
    @test error isa CorePotts.ProgramCapabilityError
    @test error.operation === :initialize_program
end

@testset "CPU scalar evidence and unsupported preflight" begin
    base = test_program(CorePotts.SequentialProgramEngine())
    qualified_evidence = String[]
    qualified_key_fingerprints = String[]
    for T in (Float32, Float64)
        program = capability_test_program(base; scalar_type = T)
        report = CorePotts.program_capability_report(program)
        @test report.key.scalar_type === T
        @test report.status === CorePotts.Supported
        @test report.maturity === CorePotts.ReplayQualified
        @test CorePotts.capability_authorizes_execution(report)
        @test CorePotts.capability_authorizes_replay(report)
        push!(qualified_evidence, report.evidence.profile_fingerprint)
        push!(qualified_key_fingerprints,
              CorePotts._capability_key_fingerprint(report.key))
    end
    @test allunique(qualified_evidence)
    @test allunique(qualified_key_fingerprints)
    @test qualified_evidence == qualified_key_fingerprints

    float16_program = capability_test_program(base; scalar_type = Float16)
    report = CorePotts.program_capability_report(float16_program)
    @test report.key.scalar_type === Float16
    @test report.status === CorePotts.Unsupported
    @test report.maturity === CorePotts.Compiles
    @test isnothing(report.evidence)
    @test occursin("no functional evidence", report.reason)
    @test !CorePotts.capability_authorizes_execution(report)

    error = try
        CorePotts.initialize_program(
            float16_program,
            test_initial(),
            Float16[],
            UInt64(0x702),
            UInt32(1),
        )
        nothing
    catch caught
        caught
    end
    @test error isa CorePotts.ProgramCapabilityError
    @test error.operation === :initialize_program
    rendered = sprint(showerror, error)
    @test occursin("engine=SequentialEngine", rendered)
    @test occursin("backend=CPUBackend", rendered)
    @test occursin("device=host_cpu", rendered)
    @test occursin("dimension=2", rendered)
    @test occursin("scalar_type=Float16", rendered)
    @test occursin("replay=ExactConfigurationReplay", rendered)
end

@testset "changed mechanism keys do not manufacture evidence" begin
    base = test_program(CorePotts.SequentialProgramEngine())
    base_report = CorePotts.program_capability_report(base)
    unqualified_plan = CorePotts.TrackerExecutionPlan(
        (UnqualifiedCapabilityTracker(),),
        "unqualified-capability-tracker-v1-test",
    )
    changed = capability_test_program(base; tracker_plan = unqualified_plan)
    changed_report = CorePotts.program_capability_report(changed)

    @test changed_report.key.mechanisms.tracker_fingerprint !=
          base_report.key.mechanisms.tracker_fingerprint
    @test changed_report.key.mechanisms.qualification_family === :unqualified
    @test changed_report.status === CorePotts.Unsupported
    @test changed_report.maturity === CorePotts.Compiles
    @test isnothing(changed_report.evidence)
    @test !CorePotts.capability_authorizes_execution(changed_report)
end

@testset "BackendSPI cannot bypass adapted-workspace preflight" begin
    program = test_program(CorePotts.CheckerboardProgramEngine())
    runtime = CorePotts.initialize_program(
        program,
        test_initial(),
        Float64[],
        UInt64(0x703),
        UInt32(1),
    )
    adapted = CorePotts.BackendSPI.adapt_program_runtime(Array, runtime)
    workspace = adapted.engine_workspace

    @test workspace.capability_report.status === CorePotts.Unsupported
    @test workspace.capability_report.key.backend === CorePotts.AdaptedBackend
    @test isnothing(workspace.capability_report.evidence)
    submitted = workspace.execution.submitted_mcs
    ownership = copy(workspace.state.ownership)

    for (operation, thunk) in (
            (
                :backend_execute_checkerboard_mcs,
                () -> CorePotts.BackendSPI.execute_checkerboard_mcs!(workspace),
            ),
            (
                :backend_enqueue_checkerboard_mcs,
                () -> CorePotts.BackendSPI.enqueue_checkerboard_mcs!(
                    workspace, submitted
                ),
            ),
            (
                :backend_settle_program,
                () -> CorePotts.BackendSPI.settle_program!(
                    workspace,
                    CorePotts.BackendSPI.ProgramSettlementRequest(
                        CorePotts.BackendSPI.PublicStepSettlement;
                        full_snapshot = true,
                    ),
                ),
            ),
        )
        error = try
            thunk()
            nothing
        catch caught
            caught
        end
        @test error isa CorePotts.BackendSPI.ProgramCapabilityError
        @test error.operation === operation
    end
    @test workspace.execution.submitted_mcs == submitted
    @test workspace.state.ownership == ownership
end
