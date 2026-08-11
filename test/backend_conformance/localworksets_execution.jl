function run_localworksets_checkerboard_vertical(
        device_array;
        backend_name,
        kernel_convert,
    )
    program = _boundary_program((6, 6); branch = :neutral)
    initial = _boundary_initial((6, 6))
    seed = UInt64(0x1ca1)
    replica = UInt32(3)
    direct = CorePotts.adapt_program_runtime(
        device_array,
        CorePotts.initialize_program(
            program, initial, Float32[], seed, replica
        ),
    )
    candidate = CorePotts._localworksets_candidate_runtime(
        CorePotts.adapt_program_runtime(
            device_array,
            CorePotts.initialize_program(
                program, initial, Float32[], seed, replica
            ),
        )
    )
    @test isbitstype(typeof(kernel_convert(
        candidate.engine_workspace.gates[1]
    )))
    CorePotts.enqueue_program_through!(direct, 12)
    CorePotts.enqueue_program_through!(candidate, 12)
    request = CorePotts.ProgramSettlementRequest(
        CorePotts.PublicStepSettlement; full_snapshot = true
    )
    direct_receipt = CorePotts.settle_program!(direct, request)
    candidate_receipt = CorePotts.settle_program!(candidate, request)

    @test direct_receipt.counters == candidate_receipt.counters
    @test direct_receipt.status == candidate_receipt.status
    @test direct_receipt.snapshot.ownership ==
          candidate_receipt.snapshot.ownership
    @test direct_receipt.snapshot.cell_kinds ==
          candidate_receipt.snapshot.cell_kinds
    @test direct_receipt.snapshot.cell_generations ==
          candidate_receipt.snapshot.cell_generations
    @test direct_receipt.snapshot.trackers.values ==
          candidate_receipt.snapshot.trackers.values
    @test Array(direct.engine_workspace.cell_max_priority) == Array(
        candidate.engine_workspace.direct.cell_max_priority
    )
    @test Array(direct.engine_workspace.cell_min_identity) == Array(
        candidate.engine_workspace.direct.cell_min_identity
    )
    @test Array(direct.engine_workspace.dispositions) == Array(
        candidate.engine_workspace.direct.dispositions
    )
    @test direct.engine_workspace.execution.synchronization_count == 1
    @test candidate.engine_workspace.execution.synchronization_count == 1
    facts = CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    )
    @test facts.wait_count == 1
    @test facts.submitted == facts.drained == UInt64(
        12 * Int(program.checkerboard_plan.color_count)
    )
    @test !facts.poisoned

    return (
        backend = backend_name,
        submitted_mcs = candidate_receipt.submitted_mcs,
        committed_mcs = candidate_receipt.committed_mcs,
        claim_submissions = Int(facts.submitted),
        synchronizations =
            candidate.engine_workspace.execution.synchronization_count,
        ownership_checksum = sum(
            index * Int(owner) for (index, owner) in
                enumerate(candidate_receipt.snapshot.ownership)
        ),
    )
end

function _swap_first_device_color_sites!(workspace, array_convert)
    # MCS zero executes into the alternate bank. Adapted state wrappers may
    # share one underlying plan buffer, so mutating both wrappers could swap
    # the same device data twice and silently restore it.
    state = workspace.alternate_state
    sites = state.program.checkerboard_plan.sites
    host_sites = Array(sites)
    offsets = Array(state.program.checkerboard_plan.color_offsets)
    color = findfirst(1:(length(offsets) - 1)) do candidate
        offsets[candidate + 1] - offsets[candidate] >= Int32(2)
    end
    color === nothing && throw(ArgumentError(
        "provider-failure fixture requires a color with two active sites"
    ))
    first_index = Int(offsets[color])
    second_index = first_index + 1
    first_site = host_sites[first_index]
    second_site = host_sites[second_index]
    host_sites[first_index], host_sites[second_index] =
        host_sites[second_index], host_sites[first_index]
    copyto!(sites, array_convert(host_sites))
    # This is adversarial fixture setup, outside the candidate submission
    # trace. Make the external mutation visible before measuring the one-wait
    # failure path; the production path itself gains no synchronization.
    CorePotts.KernelAbstractions.synchronize(
        CorePotts.KernelAbstractions.get_backend(sites)
    )
    observed = Array(sites)
    observed[first_index] == second_site &&
        observed[second_index] == first_site || throw(ArgumentError(
        "provider-failure fixture mutation was not visible on the backend"
    ))
    return workspace
end

function run_localworksets_checkerboard_failures(
        device_array;
        backend_name,
    )
    program = _boundary_program((6, 6); branch = :nonfinite)
    initial = _boundary_initial((6, 6))
    seed = UInt64(0x1ca2)
    replica = UInt32(3)
    make_runtime() = CorePotts.adapt_program_runtime(
        device_array,
        CorePotts.initialize_program(
            program, initial, Float32[], seed, replica
        ),
    )
    direct = make_runtime()
    candidate = CorePotts._localworksets_candidate_runtime(make_runtime())
    rank_pattern = UInt32[0x31415926]
    identity_pattern = UInt32[0x12345678]
    copyto!(direct.engine_workspace.cell_max_priority, device_array(rank_pattern))
    copyto!(direct.engine_workspace.cell_min_identity, device_array(identity_pattern))
    copyto!(
        candidate.engine_workspace.direct.cell_max_priority,
        device_array(rank_pattern),
    )
    copyto!(
        candidate.engine_workspace.direct.cell_min_identity,
        device_array(identity_pattern),
    )
    CorePotts.enqueue_program_through!(direct, 12)
    CorePotts.enqueue_program_through!(candidate, 12)
    request = CorePotts.ProgramSettlementRequest(
        CorePotts.PublicStepSettlement; full_snapshot = true
    )
    direct_receipt = CorePotts.settle_program!(direct, request)
    candidate_receipt = CorePotts.settle_program!(candidate, request)
    @test direct_receipt.status == candidate_receipt.status
    @test direct_receipt.committed_mcs ==
          candidate_receipt.committed_mcs == 0
    @test direct_receipt.snapshot.ownership ==
          candidate_receipt.snapshot.ownership
    @test Array(direct.engine_workspace.cell_max_priority) == UInt32[0]
    @test Array(direct.engine_workspace.cell_min_identity) ==
          UInt32[typemax(UInt32)]
    @test Array(candidate.engine_workspace.direct.cell_max_priority) ==
          Array(direct.engine_workspace.cell_max_priority)
    @test Array(candidate.engine_workspace.direct.cell_min_identity) ==
          Array(direct.engine_workspace.cell_min_identity)
    expected_facts = CorePotts.LocalWorksets.inspect(
        candidate.engine_workspace.prepared
    )
    @test expected_facts.wait_count == 1
    @test !expected_facts.poisoned

    # A scientific failure closes the Core-owned execution gate before the
    # LocalWorksets identity stage. Use a scientifically valid program for the
    # independent provider-failure witness so the invalid active-prefix proof
    # is observed by the provider and poisons the prepared work.
    provider_program = _boundary_program((6, 6); branch = :neutral)
    provider_runtime = CorePotts.adapt_program_runtime(
        device_array,
        CorePotts.initialize_program(
            provider_program, initial, Float32[], seed, replica
        ),
    )
    provider_candidate = CorePotts._localworksets_candidate_runtime(
        provider_runtime
    )
    _swap_first_device_color_sites!(
        provider_candidate.engine_workspace.direct, device_array
    )
    provider_failure = try
        CorePotts.enqueue_program_mcs!(provider_candidate)
        CorePotts.settle_program!(provider_candidate, request)
        nothing
    catch error
        error
    end
    @test provider_failure isa CorePotts.LifecycleBackendFailure
    @test provider_failure.first_possible_mcs == 1
    @test provider_failure.last_possible_mcs == 1
    @test CorePotts.LocalWorksets.inspect(
        provider_candidate.engine_workspace.prepared
    ).poisoned

    return (
        backend = backend_name,
        expected_failure_commit = candidate_receipt.committed_mcs,
        expected_failure_poisoned = expected_facts.poisoned,
        provider_failure_type = nameof(typeof(provider_failure)),
        provider_poisoned = CorePotts.LocalWorksets.inspect(
            provider_candidate.engine_workspace.prepared
        ).poisoned,
    )
end


