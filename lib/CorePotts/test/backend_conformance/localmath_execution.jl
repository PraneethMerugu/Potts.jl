import LocalMath

function _localmath_canonical_runtime(
        array_convert, program, initial, seed, replica
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float32[], seed, replica
    )
    return array_convert === identity ? runtime :
           CorePotts.adapt_program_runtime(array_convert, runtime)
end

function _localmath_execution_preparations(execution)
    return (
        clear_report = execution.clear_report,
        color_mechanics = execution.color_laws.prepared,
        before_lifecycle = map(
            entry -> entry.prepared, execution.stage_boundaries.before),
        after_lifecycle = map(
            entry -> entry.prepared, execution.stage_boundaries.after),
    )
end

function _localmath_execution_facts(execution)
    preparations = _localmath_execution_preparations(execution)
    return (
        clear_report = map(LocalMath.inspect, preparations.clear_report),
        color_mechanics = map(
            LocalMath.inspect, preparations.color_mechanics),
        before_lifecycle = map(preparations.before_lifecycle) do group
            map(LocalMath.inspect, group)
        end,
        after_lifecycle = map(preparations.after_lifecycle) do group
            map(LocalMath.inspect, group)
        end,
    )
end

_localmath_all_facts(facts) = (
    facts.clear_report...,
    facts.color_mechanics...,
    Tuple(Iterators.flatten(facts.before_lifecycle))...,
    Tuple(Iterators.flatten(facts.after_lifecycle))...,
)

function _test_localmath_receipt_parity(cpu, device)
    @test cpu.submitted_mcs == device.submitted_mcs
    @test cpu.drained_mcs == device.drained_mcs
    @test cpu.committed_mcs == device.committed_mcs
    @test cpu.materialized_mcs == device.materialized_mcs
    @test cpu.counters == device.counters
    @test cpu.status == device.status
    @test typeof(cpu.failure) === typeof(device.failure)
    @test cpu.snapshot.ownership == device.snapshot.ownership
    @test cpu.snapshot.cell_kinds == device.snapshot.cell_kinds
    @test cpu.snapshot.cell_generations == device.snapshot.cell_generations
    @test cpu.snapshot.trackers.values == device.snapshot.trackers.values
    @test collect(cpu.snapshot.relationships) ==
          collect(device.snapshot.relationships)
    @test cpu.snapshot.descriptor_state == device.snapshot.descriptor_state
    return nothing
end

function run_localmath_checkerboard_vertical(
        device_array;
        backend_name,
        kernel_convert,
    )
    program = _boundary_program((6, 6); branch = :neutral)
    initial = _boundary_initial((6, 6))
    seed = UInt64(0x1ca1)
    replica = UInt32(3)
    cpu = _localmath_canonical_runtime(
        identity, program, initial, seed, replica
    )
    device = _localmath_canonical_runtime(
        device_array, program, initial, seed, replica
    )
    execution = device.engine_workspace
    @test execution isa CorePotts._CheckerboardExecutionWorkspace
    @test isbitstype(typeof(kernel_convert(execution.core.state)))
    initial_facts = _localmath_execution_facts(execution)

    CorePotts.enqueue_program_through!(cpu, 12)
    CorePotts.enqueue_program_through!(device, 12)
    request = CorePotts.ProgramSettlementRequest(
        CorePotts.PublicStepSettlement; full_snapshot = true
    )
    cpu_receipt = CorePotts.settle_program!(cpu, request)
    device_receipt = CorePotts.settle_program!(device, request)
    _test_localmath_receipt_parity(cpu_receipt, device_receipt)

    facts = _localmath_execution_facts(execution)
    all_facts = _localmath_all_facts(facts)
    states = map(fact -> fact.realized.state, all_facts)
    initial_states = map(
        fact -> fact.realized.state,
        _localmath_all_facts(initial_facts),
    )
    expected = UInt64(
        12 * Int(program.attempts_per_site) *
        Int(program.checkerboard_plan.color_count)
    )
    submitted(group) = sum(fact.realized.state.submitted for fact in group)
    @test submitted(facts.color_mechanics) == expected
    @test submitted(facts.clear_report) == UInt64(12)
    @test all(state -> state.submitted == state.drained, states)
    @test sum(state.provider_completions for state in states) == 1
    @test map(state -> state.provider_scope_completions, states) ==
          map(count -> count + 1,
              map(state -> state.provider_scope_completions, initial_states))
    @test all(state -> !state.poisoned, states)
    @test CorePotts._checkerboard_execution_position(
        cpu.engine_workspace
    ).synchronization_count == 1
    @test execution.core.execution.synchronization_count == 1

    return (
        schema = :corepotts_localmath_mechanics_v2,
        backend = backend_name,
        submitted_mcs = device_receipt.submitted_mcs,
        committed_mcs = device_receipt.committed_mcs,
        color_mechanics_submissions = Int(
            submitted(facts.color_mechanics)),
        provider_waits = Int(sum(
            state.provider_completions for state in states)),
        synchronizations = execution.core.execution.synchronization_count,
        ownership_checksum = sum(
            index * Int(owner) for (index, owner) in
                enumerate(device_receipt.snapshot.ownership)
        ),
    )
end

function _corrupt_first_device_color_site!(workspace, array_convert)
    # MCS zero executes into the alternate bank. Adapted state wrappers may
    # share one underlying plan buffer, so mutate only that executing wrapper.
    state = workspace.alternate_state
    sites = state.program.checkerboard_plan.sites
    host_sites = Array(sites)
    offsets = Array(state.program.checkerboard_plan.color_offsets)
    color = findfirst(1:(length(offsets) - 1)) do color_index
        offsets[color_index + 1] - offsets[color_index] >= Int32(2)
    end
    color === nothing && throw(ArgumentError(
        "provider-failure fixture requires a color with two active sites"
    ))
    first_index = Int(offsets[color])
    host_sites[first_index] = Int32(length(workspace.state.ownership) + 1)
    copyto!(sites, array_convert(host_sites))
    CorePotts.KernelAbstractions.synchronize(
        CorePotts.KernelAbstractions.get_backend(sites)
    )
    observed = Array(sites)
    observed[first_index] == host_sites[first_index] ||
        throw(ArgumentError(
            "provider-failure fixture mutation was not visible on the backend"
        ))
    return workspace
end

function run_localmath_checkerboard_failures(
        device_array;
        backend_name,
    )
    initial = _boundary_initial((6, 6))
    seed = UInt64(0x1ca2)
    replica = UInt32(3)
    request = CorePotts.ProgramSettlementRequest(
        CorePotts.PublicStepSettlement; full_snapshot = true
    )

    # A scientific acceptance failure closes the CorePotts status gate. It is
    # a successful provider execution: no MCS publishes and no prepared work
    # is poisoned.
    failure_program = _boundary_program((6, 6); branch = :nonfinite)
    cpu = _localmath_canonical_runtime(
        identity, failure_program, initial, seed, replica
    )
    device = _localmath_canonical_runtime(
        device_array, failure_program, initial, seed, replica
    )
    CorePotts.enqueue_program_through!(cpu, 12)
    CorePotts.enqueue_program_through!(device, 12)
    cpu_receipt = CorePotts.settle_program!(cpu, request)
    device_receipt = CorePotts.settle_program!(device, request)
    _test_localmath_receipt_parity(cpu_receipt, device_receipt)
    @test device_receipt.failure isa CorePotts.ProposalAcceptanceFailure
    @test device_receipt.committed_mcs == 0
    @test device_receipt.materialized_mcs == 0
    expected_facts = _localmath_execution_facts(
        device.engine_workspace
    )
    @test all(
        fact -> !fact.poisoned,
        _localmath_all_facts(expected_facts),
    )

    # A deliberately out-of-domain checkerboard site reaches the proposal
    # device kernel and raises a real provider failure. This is distinct from
    # an exactly reported publication-validation failure, which must poison
    # only its preparation rather than the complete provider scope.
    provider_program = _boundary_program((6, 6); branch = :neutral)
    provider_runtime = _localmath_canonical_runtime(
        device_array, provider_program, initial, seed, replica
    )
    _corrupt_first_device_color_site!(
        provider_runtime.engine_workspace.core, device_array
    )
    provider_failure = try
        CorePotts.enqueue_program_mcs!(provider_runtime)
        CorePotts.settle_program!(provider_runtime, request)
        nothing
    catch error
        error
    end
    @test provider_failure isa CorePotts.LifecycleBackendFailure
    @test provider_failure.first_possible_mcs == 1
    @test provider_failure.last_possible_mcs == 1
    provider_facts = _localmath_execution_facts(
        provider_runtime.engine_workspace
    )
    @test all(
        fact -> fact.poisoned,
        _localmath_all_facts(provider_facts),
    )

    return (
        schema = :corepotts_checkerboard_canonical_failures_v2,
        backend = backend_name,
        scientific_failure = nameof(typeof(device_receipt.failure)),
        scientific_failure_commit = device_receipt.committed_mcs,
        scientific_failure_poisoned = any(
            getproperty.(_localmath_all_facts(expected_facts), :poisoned)
        ),
        provider_failure_type = nameof(typeof(provider_failure)),
        provider_failure_range = (
            provider_failure.first_possible_mcs,
            provider_failure.last_possible_mcs,
        ),
        provider_poisoned = all(
            getproperty.(_localmath_all_facts(provider_facts), :poisoned)
        ),
    )
end
