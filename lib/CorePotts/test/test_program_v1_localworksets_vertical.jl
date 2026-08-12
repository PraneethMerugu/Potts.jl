function _localworksets_acceptance_descriptor_plan(value)
    descriptor = CorePotts.ProposalDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(value)),
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
    launch = CorePotts.DescriptorLaunch(nothing, [descriptor], (), ())
    return CorePotts.DescriptorExecutionPlan(
        (CorePotts.DescriptorGroup(launch, :unsplit),),
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[:localworksets_acceptance_failure],
        1,
        "localworksets-acceptance-failure-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
end

function _localworksets_vertical_runtime(
        ;
        seed = UInt64(0x51a7),
        descriptor_plan = empty_descriptor_plan(),
    )
    ownership = zeros(Int32, 6, 6)
    ownership[2:3, 2:3] .= 1
    ownership[4:5, 4:5] .= 2
    initial = CorePotts.ProgramInitialState(
        ownership, Int16[2, 2]; scalar_type = Float64
    )
    program = test_program(
        CorePotts.CheckerboardProgramEngine(); descriptor_plan
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], seed, UInt32(3);
        repeat = UInt32(2),
    )
    return program, runtime
end

function _swap_first_color_sites!(workspace)
    state = workspace.alternate_state
    sites = state.program.checkerboard_plan.sites
    first_index = Int(state.program.checkerboard_plan.color_offsets[1])
    second_index = first_index + 1
    sites[first_index], sites[second_index] =
        sites[second_index], sites[first_index]
    return workspace
end

function _settle_full!(runtime)
    return CorePotts.settle_program!(
        runtime,
        CorePotts.ProgramSettlementRequest(
            CorePotts.PublicStepSettlement; full_snapshot = true
        ),
    )
end

@testset "LocalWorksets checkerboard queue capacity is checked" begin
    @test CorePotts._checked_checkerboard_capacity_mul(12, 7, :test) == 84
    @test CorePotts._checked_checkerboard_capacity_sub(84, 7, :test) == 77
    @test_throws ArgumentError CorePotts._checked_checkerboard_capacity_mul(
        typemax(Int), 2, :test
    )
    @test_throws ArgumentError CorePotts._checked_checkerboard_capacity_mul(
        big(typemax(Int)) + 1, 1, :test
    )
    @test_throws ArgumentError CorePotts._checked_checkerboard_capacity_sub(
        1, 2, :test
    )
end

@testset "private LocalWorksets claim vertical preserves queued CPU execution" begin
    program, direct = _localworksets_vertical_runtime()
    _, candidate_base = _localworksets_vertical_runtime()
    candidate = CorePotts._localworksets_candidate_runtime(candidate_base)

    @test direct.engine_workspace isa CorePotts.CheckerboardWorkspace
    @test candidate.engine_workspace isa
          CorePotts._LocalWorksetsCheckerboardWorkspace
    @test candidate.engine_workspace.mechanism_identity ===
          :corepotts_checkerboard_conjunctive_localworksets_v1
    @test candidate.capability_report.status ===
          CorePotts.BackendSPI.Experimental
    @test candidate.capability_report.maturity ===
          CorePotts.BackendSPI.Functional
    @test candidate.capability_report.evidence.suite ===
          :lw2_localworksets_functional_v1
    @test CorePotts.capability_key_fingerprint(
        candidate.capability_report.key
    ) != CorePotts.capability_key_fingerprint(direct.capability_report.key)
    @test direct.capability_report.status === CorePotts.BackendSPI.Supported
    @test CorePotts.supports_queued_program_execution(candidate)
    @test CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    ).lowering == :resolved_conjunctive_two_key_UInt32_UInt8_v1

    CorePotts.enqueue_program_through!(direct, 12)
    CorePotts.enqueue_program_through!(candidate, 12)
    direct_receipt = _settle_full!(direct)
    candidate_receipt = _settle_full!(candidate)

    @test direct_receipt.submitted_mcs == 12
    @test candidate_receipt.submitted_mcs == 12
    @test direct_receipt.drained_mcs == candidate_receipt.drained_mcs == 12
    @test direct_receipt.committed_mcs == candidate_receipt.committed_mcs == 12
    @test direct_receipt.materialized_mcs ==
          candidate_receipt.materialized_mcs == 12
    @test direct_receipt.counters == candidate_receipt.counters
    @test direct_receipt.status == candidate_receipt.status
    @test direct_receipt.failure === candidate_receipt.failure === nothing
    @test direct_receipt.snapshot.ownership ==
          candidate_receipt.snapshot.ownership
    @test direct_receipt.snapshot.cell_kinds ==
          candidate_receipt.snapshot.cell_kinds
    @test direct_receipt.snapshot.cell_generations ==
          candidate_receipt.snapshot.cell_generations
    @test direct_receipt.snapshot.trackers.values ==
          candidate_receipt.snapshot.trackers.values
    @test collect(direct_receipt.snapshot.relationships) ==
          collect(candidate_receipt.snapshot.relationships)
    @test direct_receipt.snapshot.descriptor_state ==
          candidate_receipt.snapshot.descriptor_state

    direct_workspace = direct.engine_workspace
    candidate_workspace = candidate.engine_workspace
    @test direct_workspace.cell_max_priority ==
          candidate_workspace.direct.cell_max_priority
    @test direct_workspace.cell_min_identity ==
          candidate_workspace.direct.cell_min_identity
    @test direct_workspace.dispositions ==
          candidate_workspace.direct.dispositions
    @test direct_workspace.execution.synchronization_count == 1
    @test candidate_workspace.execution.synchronization_count == 1
    @test CorePotts.LocalWorksets.inspect(
        candidate_workspace.prepared
    ).wait_count == 1
    @test CorePotts.LocalWorksets.inspect(
        candidate_workspace.prepared
    ).submitted == UInt64(
        12 * Int(program.checkerboard_plan.color_count)
    )
    @test CorePotts.LocalWorksets.inspect(
        candidate_workspace.prepared
    ).drained == UInt64(
        12 * Int(program.checkerboard_plan.color_count)
    )

    @test_throws CorePotts.BackendSPI.ProgramCapabilityError begin
        CorePotts.program_checkpoint(candidate)
    end
    _, replay_base = _localworksets_vertical_runtime()
    replay_candidate = CorePotts._localworksets_replay_candidate_runtime(
        replay_base
    )
    @test replay_candidate.capability_report.status ===
          CorePotts.BackendSPI.Experimental
    @test replay_candidate.capability_report.maturity ===
          CorePotts.BackendSPI.ReplayQualified
    @test replay_candidate.capability_report.evidence.suite ===
          :lw3_localworksets_replay_v1
    CorePotts.enqueue_program_through!(replay_candidate, 12)
    replay_receipt = _settle_full!(replay_candidate)
    @test replay_receipt.snapshot.ownership == direct_receipt.snapshot.ownership

    direct_checkpoint = CorePotts.program_checkpoint(direct)
    candidate_checkpoint = CorePotts.program_checkpoint(replay_candidate)
    @test direct_checkpoint.snapshot.ownership ==
          candidate_checkpoint.snapshot.ownership
    @test direct_checkpoint.seed == candidate_checkpoint.seed
    @test direct_checkpoint.replica == candidate_checkpoint.replica
    @test direct_checkpoint.repeat == candidate_checkpoint.repeat
    @test !hasproperty(
        direct_checkpoint.extensions.CorePotts, :execution_lowering
    )
    candidate_block =
        candidate_checkpoint.extensions.CorePotts.execution_lowering
    @test candidate_block.mechanism_identity ===
          :corepotts_checkerboard_conjunctive_localworksets_v1
    @test candidate_block.capability_status ===
          CorePotts.BackendSPI.Experimental
    @test candidate_block.capability_maturity ===
          CorePotts.BackendSPI.ReplayQualified
    @test candidate_block.capability_evidence.suite ===
          :lw3_localworksets_replay_v1
    @test candidate_block.capability_fingerprint ==
          CorePotts.capability_key_fingerprint(
              replay_candidate.capability_report.key
          )
    @test direct_checkpoint.checksum != candidate_checkpoint.checksum
    @test_throws ArgumentError CorePotts.restore_program_checkpoint(
        program, candidate_checkpoint
    )
    @test_throws ArgumentError CorePotts._restore_localworksets_checkpoint(
        program, direct_checkpoint
    )

    foreign_rng = merge(
        candidate_checkpoint.extensions.CorePotts.rng,
        (lowering_identity = :foreign_rng_lowering,),
    )
    foreign_extensions = merge(candidate_checkpoint.extensions, (
        CorePotts = merge(candidate_checkpoint.extensions.CorePotts, (
            rng = foreign_rng,
        )),
    ))
    foreign_checksum = CorePotts._program_checkpoint_checksum(
        candidate_checkpoint.schema,
        candidate_checkpoint.program_fingerprint,
        candidate_checkpoint.snapshot,
        candidate_checkpoint.parameters,
        candidate_checkpoint.seed,
        candidate_checkpoint.replica,
        candidate_checkpoint.repeat,
        candidate_checkpoint.accepted,
        candidate_checkpoint.rejected,
        candidate_checkpoint.null_attempts,
        candidate_checkpoint.constraint_rejections,
        candidate_checkpoint.energy_rejections,
        candidate_checkpoint.retired_cells,
        foreign_extensions,
    )
    foreign_checkpoint = CorePotts.ProgramCheckpoint(
        candidate_checkpoint.schema,
        candidate_checkpoint.program_fingerprint,
        candidate_checkpoint.snapshot,
        candidate_checkpoint.parameters,
        candidate_checkpoint.seed,
        candidate_checkpoint.replica,
        candidate_checkpoint.repeat,
        candidate_checkpoint.accepted,
        candidate_checkpoint.rejected,
        candidate_checkpoint.null_attempts,
        candidate_checkpoint.constraint_rejections,
        candidate_checkpoint.energy_rejections,
        candidate_checkpoint.retired_cells,
        foreign_extensions,
        foreign_checksum,
    )
    rng_error = try
        CorePotts._restore_localworksets_checkpoint(program, foreign_checkpoint)
        nothing
    catch error
        error
    end
    @test rng_error isa ArgumentError
    @test occursin("RNG contract", sprint(showerror, rng_error))

    direct_continuation = CorePotts.restore_program_checkpoint(
        program, direct_checkpoint
    )
    candidate_continuation = CorePotts._restore_localworksets_checkpoint(
        program, candidate_checkpoint
    )
    CorePotts.enqueue_program_through!(direct_continuation, 16)
    CorePotts.enqueue_program_through!(candidate_continuation, 16)
    continued_direct = _settle_full!(direct_continuation)
    continued_candidate = _settle_full!(candidate_continuation)
    @test continued_direct.submitted_mcs == continued_candidate.submitted_mcs == 16
    @test continued_direct.drained_mcs == continued_candidate.drained_mcs == 16
    @test continued_direct.committed_mcs == continued_candidate.committed_mcs == 16
    @test continued_direct.materialized_mcs == continued_candidate.materialized_mcs == 16
    @test continued_direct.counters == continued_candidate.counters
    @test continued_direct.status == continued_candidate.status
    @test continued_direct.failure === continued_candidate.failure === nothing
    @test continued_direct.snapshot.ownership ==
          continued_candidate.snapshot.ownership
    @test continued_direct.snapshot.cell_kinds ==
          continued_candidate.snapshot.cell_kinds
    @test continued_direct.snapshot.cell_generations ==
          continued_candidate.snapshot.cell_generations
    @test continued_direct.snapshot.trackers.values ==
          continued_candidate.snapshot.trackers.values
    @test collect(continued_direct.snapshot.relationships) ==
          collect(continued_candidate.snapshot.relationships)
    @test continued_direct.snapshot.descriptor_state ==
          continued_candidate.snapshot.descriptor_state
end

@testset "LocalWorksets evidence remains conjunctive with Core authority" begin
    _, runtime = _localworksets_vertical_runtime()
    unsupported = CorePotts.adapt_program_runtime(Array, runtime)
    @test unsupported.capability_report.status ===
          CorePotts.BackendSPI.Unsupported
    @test unsupported.capability_report.maturity ===
          CorePotts.BackendSPI.InterfaceOnly
    @test unsupported.capability_report.evidence === nothing
    @test_throws CorePotts.BackendSPI.ProgramCapabilityError begin
        CorePotts._localworksets_candidate_runtime(unsupported)
    end
    @test_throws CorePotts.BackendSPI.ProgramCapabilityError begin
        CorePotts._localworksets_replay_candidate_runtime(unsupported)
    end
    source = read(joinpath(
        dirname(pathof(CorePotts)), "execution", "sequential_program.jl"
    ), String)
    @test !occursin("prepared.workplan", source)
    @test !occursin("prepared.leases", source)
end

@testset "LocalWorksets candidate rejects whole-MCS lease exhaustion prelaunch" begin
    _, runtime = _localworksets_vertical_runtime()
    candidate = CorePotts._localworksets_candidate_runtime(runtime)
    plan = candidate.program.checkerboard_plan
    color_count = Int(plan.color_count)
    CorePotts.enqueue_program_through!(candidate, 12)
    before_submitted = candidate.engine_workspace.execution.submitted_mcs
    before_claims = CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    ).submitted
    @test_throws ArgumentError begin
        CorePotts.enqueue_program_mcs!(candidate)
    end
    @test candidate.engine_workspace.execution.submitted_mcs == before_submitted
    @test CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    ).submitted == before_claims == UInt64(12 * color_count)
    @test !CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    ).poisoned
    _settle_full!(candidate)
    @test CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    ).drained == before_claims
    CorePotts.enqueue_program_mcs!(candidate)
    receipt = _settle_full!(candidate)
    @test receipt.committed_mcs == 13
end

@testset "expected scientific failure preserves the direct commit cut" begin
    descriptor_plan = _localworksets_acceptance_descriptor_plan(NaN)
    program, direct = _localworksets_vertical_runtime(; descriptor_plan)
    _, candidate_base = _localworksets_vertical_runtime(; descriptor_plan)
    candidate = CorePotts._localworksets_candidate_runtime(candidate_base)

    direct_workspace = direct.engine_workspace
    candidate_workspace = candidate.engine_workspace
    rank_pattern = UInt32[0x31415926, 0x27182818]
    identity_pattern = UInt32[0x12345678, 0x23456789]
    copyto!(direct_workspace.cell_max_priority, rank_pattern)
    copyto!(direct_workspace.cell_min_identity, identity_pattern)
    copyto!(candidate_workspace.direct.cell_max_priority, rank_pattern)
    copyto!(candidate_workspace.direct.cell_min_identity, identity_pattern)

    CorePotts.enqueue_program_through!(direct, 12)
    CorePotts.enqueue_program_through!(candidate, 12)
    direct_receipt = _settle_full!(direct)
    candidate_receipt = _settle_full!(candidate)

    @test direct_receipt.submitted_mcs ==
          candidate_receipt.submitted_mcs == 12
    @test direct_receipt.drained_mcs ==
          candidate_receipt.drained_mcs == 12
    @test direct_receipt.committed_mcs ==
          candidate_receipt.committed_mcs == 0
    @test direct_receipt.materialized_mcs ==
          candidate_receipt.materialized_mcs == 0
    @test direct_receipt.status == candidate_receipt.status
    @test direct_receipt.failure isa CorePotts.ProposalAcceptanceFailure
    @test candidate_receipt.failure isa CorePotts.ProposalAcceptanceFailure
    @test direct_receipt.snapshot.ownership ==
          candidate_receipt.snapshot.ownership
    @test direct_receipt.counters == candidate_receipt.counters
    # The Core-owned once-per-MCS bulk clear precedes candidate evaluation.
    # Once acceptance closes the gate, the four claim launches leave those
    # sentinel values unchanged.
    @test direct_workspace.cell_max_priority == fill(UInt32(0), 2)
    @test direct_workspace.cell_min_identity == fill(typemax(UInt32), 2)
    @test candidate_workspace.direct.cell_max_priority ==
          direct_workspace.cell_max_priority
    @test candidate_workspace.direct.cell_min_identity ==
          direct_workspace.cell_min_identity
    @test direct_workspace.execution.synchronization_count == 1
    @test candidate_workspace.execution.synchronization_count == 1
    facts = CorePotts.LocalWorksets.inspect(candidate_workspace.prepared)
    @test facts.submitted == facts.drained == UInt64(
        12 * Int(program.checkerboard_plan.color_count)
    )
    @test facts.wait_count == 1
    @test !facts.poisoned
end

@testset "Core trusted adapter bypasses more-specific public dispatch" begin
    _, direct = _localworksets_vertical_runtime()
    _, candidate_base = _localworksets_vertical_runtime()
    candidate = CorePotts._localworksets_candidate_runtime(candidate_base)
    prepared = candidate.engine_workspace.prepared

    function CorePotts.LocalWorksets.run!(
            value::typeof(prepared), submission::NamedTuple
        )
        error("external run! dispatch intercepted CorePotts")
    end
    @test which(
        CorePotts.LocalWorksets.run!,
        Tuple{typeof(prepared), NamedTuple},
    ).module === Main

    CorePotts.enqueue_program_mcs!(direct)
    CorePotts.enqueue_program_mcs!(candidate)
    event = candidate.engine_workspace.last_event
    @test event isa CorePotts.LocalWorksets.WorkEvent

    function Base.wait(value::typeof(event))
        error("external wait dispatch intercepted CorePotts")
    end
    @test which(Base.wait, Tuple{typeof(event)}).module === Main

    direct_receipt = _settle_full!(direct)
    candidate_receipt = _settle_full!(candidate)
    @test direct_receipt.committed_mcs ==
          candidate_receipt.committed_mcs == 1
    @test direct_receipt.counters == candidate_receipt.counters
    @test direct_receipt.snapshot.ownership ==
          candidate_receipt.snapshot.ownership
    @test CorePotts.LocalWorksets.inspect(prepared).submitted ==
          CorePotts.LocalWorksets.inspect(prepared).drained
end

@testset "provider failure poisons and maps through Core settlement" begin
    _, runtime = _localworksets_vertical_runtime()
    candidate = CorePotts._localworksets_candidate_runtime(runtime)
    _swap_first_color_sites!(candidate.engine_workspace.direct)
    failure = try
        CorePotts.enqueue_program_mcs!(candidate)
        _settle_full!(candidate)
        nothing
    catch error
        error
    end
    @test failure isa CorePotts.LifecycleBackendFailure
    @test failure.first_possible_mcs == 1
    @test failure.last_possible_mcs == 1
    @test candidate.mcs == 0
    @test candidate.engine_workspace.execution.committed_mcs == 0
    @test CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    ).poisoned
end
