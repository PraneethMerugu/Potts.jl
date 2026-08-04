using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics

import CorePotts

function _lifecycle_backend_fixture(;
        max_cells = 2,
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        division_mcs::Integer = 1,
    )
    @variables lifecycle_payload
    @parameters lifecycle_division_threshold = 4.0f0
    cell = CellKind(:lifecycle_cell; extinction = RetireAtZero())
    medium = MediumKind(:lifecycle_medium)
    division_relation = SpatialRelation(
        :lifecycle_division; neighborhood = VonNeumann()
    )
    payload = CellState(
        lifecycle_payload;
        initial = 4.0f0,
        retirement = RetireTo(0.0f0),
        division = SplitConservatively(0.5f0; rounding = :exact),
    )
    anchor = CellBinding(:lifecycle_anchor)
    divide = LifecycleProcess(
        :lifecycle_divide;
        domain = cells(cell),
        anchor,
        expression = cell_volume(anchor_value(anchor)) >=
                     lifecycle_division_threshold,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0f0, 0.0f0)),
            relation = division_relation,
            side = CanonicalSide(),
            state = (
                payload => SplitConservatively(0.5f0; rounding = :exact),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(division_mcs),
    )
    system = PottsSystem(
        name = :LifecycleBackendFixture,
        statements = StatementSet((
            Lattice((6, 6); max_cells),
            cell,
            medium,
            division_relation,
            payload,
            divide,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [lifecycle_payload],
        parameters = [lifecycle_division_threshold],
    )
    executable = compile(
        complete(system);
        engine,
        backend,
        scalar_type = Float32,
    )
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    return executable, PottsToolkit._core_initial_state(
        executable, initial, UInt64(0x71), UInt32(1)
    )
end

function run_public_device_lifecycle_execution(backend_selector)
    executable, _ = _lifecycle_backend_fixture(backend = backend_selector)
    reference_executable, _ = _lifecycle_backend_fixture()
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    problem = PottsProblem(executable, initial, (0, 2); seed = 0x71)
    reference_problem = PottsProblem(
        reference_executable, initial, (0, 2); seed = 0x71
    )

    stepped = init(problem; save_start = false)
    @test !(stepped.runtime.engine_workspace.state.ownership isa Array)
    step!(stepped)
    @test stepped.t == 1
    @test stepped.runtime.engine_workspace.execution.settlement_count == 1
    captured = checkpoint(stepped)

    device_integrator = init(problem; save_start = false)
    device_solution = solve!(device_integrator)
    reference_solution = solve(reference_problem; save_start = false)
    @test device_solution.retcode === PottsToolkit.SciMLBase.ReturnCode.Success
    @test device_integrator.t == 2
    @test device_integrator.runtime.engine_workspace.execution.settlement_count == 1
    @test only(device_solution.u).ownership == only(reference_solution.u).ownership
    @test device_integrator.runtime.accepted == reference_solution.stats.accepted
    @test device_integrator.runtime.rejected == reference_solution.stats.rejected
    @test device_integrator.runtime.null_attempts ==
        reference_solution.stats.null_attempts

    resumed = init(
        problem;
        checkpoint = captured,
        save_start = false,
    )
    resumed_solution = solve!(resumed)
    @test resumed_solution.retcode ===
        PottsToolkit.SciMLBase.ReturnCode.Success
    @test resumed.t == 2
    @test only(resumed_solution.u).ownership ==
        only(device_solution.u).ownership

    updated = init(problem; save_start = false)
    setter = PottsToolkit.SymbolicIndexingInterface.setp(
        updated, :lifecycle_division_threshold
    )
    setter(updated, 100.0f0)
    updated_solution = solve!(updated)
    @test updated_solution.retcode ===
        PottsToolkit.SciMLBase.ReturnCode.Success
    @test count(!iszero, only(updated_solution.u).cell_kinds) == 1
    @test updated.runtime.engine_workspace.execution.settlement_count == 1

    capacity_executable, _ = _lifecycle_backend_fixture(
        max_cells = 1, backend = backend_selector
    )
    capacity_problem = PottsProblem(
        capacity_executable, initial, (0, 2); seed = 0x71
    )
    failed = init(capacity_problem; save_start = false)
    failed_solution = solve!(failed)
    @test failed_solution.retcode === PottsToolkit.SciMLBase.ReturnCode.Failure
    @test failed.t == 0
    @test failed.failure_report !== nothing
    @test failed.failure_report.mcs == 1
    @test failed.runtime.engine_workspace.execution.submitted_mcs == 2
    @test failed.runtime.engine_workspace.execution.committed_mcs == 0
    @test failed.runtime.engine_workspace.execution.settlement_count == 1

    return (
        backend = nameof(typeof(backend_selector)),
        stepped_mcs = stepped.t,
        solved_mcs = device_integrator.t,
        settlements = device_integrator.runtime.engine_workspace.execution.settlement_count,
        resumed_mcs = resumed.t,
        updated_cells = count(!iszero, only(updated_solution.u).cell_kinds),
        failure_mcs = failed.failure_report.mcs,
    )
end

function run_public_lifecycle_late_capacity_failure()
    executable, _ = _lifecycle_backend_fixture(
        max_cells = 1, division_mcs = 37
    )
    labels = fill(1, 6, 6)
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    problem = PottsProblem(executable, initial, (0, 100); seed = 0x71)

    reference = init(problem; save_start = false)
    for _ in 1:36
        step!(reference)
    end
    reference_snapshot = CorePotts.program_snapshot(reference.runtime)

    queued = init(problem; save_start = false)
    solution = solve!(queued)
    @test solution.retcode === PottsToolkit.SciMLBase.ReturnCode.Failure
    @test queued.retcode === PottsToolkit.SciMLBase.ReturnCode.Failure
    @test queued.t == 36
    @test queued.runtime.mcs == 36
    @test queued.iterations == 37
    @test queued.failure_report !== nothing
    @test queued.failure_report.mcs == 37
    @test queued.failure_report.stage === CorePotts.LifecycleStageSelection
    @test queued.runtime.engine_workspace.execution.submitted_mcs == 100
    @test queued.runtime.engine_workspace.execution.drained_mcs == 100
    @test queued.runtime.engine_workspace.execution.committed_mcs == 36
    @test queued.runtime.engine_workspace.execution.settlement_count == 1
    queued_snapshot = CorePotts.program_snapshot(queued.runtime)
    @test queued_snapshot.ownership == reference_snapshot.ownership
    @test queued_snapshot.cell_kinds == reference_snapshot.cell_kinds
    @test queued_snapshot.cell_generations == reference_snapshot.cell_generations
    @test queued_snapshot.trackers.values == reference_snapshot.trackers.values

    return (
        submitted_mcs = queued.runtime.engine_workspace.execution.submitted_mcs,
        committed_mcs = queued.runtime.mcs,
        failure_mcs = queued.failure_report.mcs,
        settlements = queued.runtime.engine_workspace.execution.settlement_count,
    )
end

function run_public_settlement_consumers()
    executable, _ = _lifecycle_backend_fixture()
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    problem = PottsProblem(executable, initial, (0, 2); seed = 0x71)

    checkpoint_integrator = init(problem; save_start = false)
    CorePotts.enqueue_program_mcs!(checkpoint_integrator.runtime)
    @test !checkpoint_integrator.runtime.settled
    captured = checkpoint(checkpoint_integrator)
    @test checkpoint_integrator.runtime.settled
    @test checkpoint_integrator.t == 1
    @test captured.core.snapshot.mcs == 1
    @test checkpoint_integrator.runtime.engine_workspace.execution.settlement_count == 1

    index_integrator = init(problem; save_start = false)
    CorePotts.enqueue_program_mcs!(index_integrator.runtime)
    observed_time = PottsToolkit.SymbolicIndexingInterface.current_time(
        index_integrator
    )
    @test observed_time == 1
    @test index_integrator.runtime.engine_workspace.execution.settlement_count == 1

    statistics_integrator = init(problem; save_start = false)
    CorePotts.enqueue_program_mcs!(statistics_integrator.runtime)
    statistics = PottsToolkit.runtime_statistics(statistics_integrator)
    @test statistics.steps == 1
    @test statistics_integrator.runtime.engine_workspace.execution.settlement_count == 1

    return (
        checkpoint = checkpoint_integrator.t,
        index_read = observed_time,
        statistics = statistics.steps,
    )
end

function run_lifecycle_enqueue_allocation()
    executable, initial = _lifecycle_backend_fixture()
    program = executable.core_program
    runtime = CorePotts.initialize_program(
        program,
        initial,
        program.parameter_defaults,
        UInt64(0x71),
        UInt32(1),
    )
    workspace = runtime.engine_workspace
    CorePotts.enqueue_checkerboard_mcs!(workspace, 0)
    CorePotts.settle_program!(
        workspace,
        CorePotts.ProgramSettlementRequest(CorePotts.PublicStepSettlement),
    )
    @test @inferred(CorePotts.enqueue_checkerboard_mcs!(workspace, 1)) isa
        CorePotts.CheckerboardExecutionState
    CorePotts.settle_program!(
        workspace,
        CorePotts.ProgramSettlementRequest(CorePotts.PublicStepSettlement),
    )

    bytes = @allocated CorePotts.enqueue_checkerboard_mcs!(
        workspace, 2
    )
    CorePotts.settle_program!(
        workspace,
        CorePotts.ProgramSettlementRequest(CorePotts.PublicStepSettlement),
    )
    # KernelAbstractions' CPU launch machinery allocates per ordered kernel.
    # This ceiling catches growth in launches or host-side temporary storage;
    # hardware timing and tuning remain outside ordinary tests.
    @test bytes <= 128 * 1024
    return bytes
end

function run_lifecycle_mcs_execution(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_isbits::Bool = true,
    )
    executable, initial = _lifecycle_backend_fixture()
    program = executable.core_program
    parameters = program.parameter_defaults
    seed = UInt64(0x71)
    replica = UInt32(1)
    reference = CorePotts.initialize_program(
        program, initial, parameters, seed, replica
    )
    candidate = CorePotts.initialize_program(
        program, initial, parameters, seed, replica
    )
    CorePotts.advance_mcs!(reference)
    CorePotts.advance_mcs!(reference)

    workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, candidate.engine_workspace
    )
    require_isbits && @test isbitstype(typeof(kernel_convert(workspace.state)))
    CorePotts.enqueue_checkerboard_mcs!(workspace, 0)
    CorePotts.enqueue_checkerboard_mcs!(workspace, 1)
    receipt = CorePotts.settle_program!(
        workspace,
        CorePotts.ProgramSettlementRequest(
            CorePotts.FinalizationSettlement; full_snapshot = true
        ),
    )
    destination = receipt.snapshot

    @test destination.ownership == reference.ownership
    @test destination.cell_kinds == reference.cell_kinds
    @test destination.cell_generations == reference.cell_generations
    @test CorePotts.tracker_values(
        program.tracker_plan,
        destination.trackers,
        Val(:cell_volume),
    ) == CorePotts.program_tracker_values(reference, Val(:cell_volume))
    @test receipt.status.code === CorePotts.LifecycleStatusSuccess
    @test receipt.failure === nothing
    @test receipt.submitted_mcs == 2
    @test receipt.drained_mcs == 2
    @test receipt.committed_mcs == 2
    @test receipt.materialized_mcs == 2
    @test workspace.execution.settlement_count == 1
    @test receipt.counters.accepted == reference.accepted
    @test receipt.counters.rejected == reference.rejected
    @test receipt.counters.null_attempts == reference.null_attempts
    @test receipt.counters.constraint_rejections ==
        reference.constraint_rejections
    @test receipt.counters.energy_rejections == reference.energy_rejections

    return (
        backend = backend_name,
        committed_mcs = receipt.committed_mcs,
        settlements = workspace.execution.settlement_count,
        ownership_checksum = sum(
            index * Int(owner)
            for (index, owner) in enumerate(reference.ownership)
        ),
    )
end

function run_lifecycle_capacity_failure(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_isbits::Bool = true,
    )
    executable, initial = _lifecycle_backend_fixture(max_cells = 1)
    program = executable.core_program
    parameters = program.parameter_defaults
    candidate = CorePotts.initialize_program(
        program, initial, parameters, UInt64(0x71), UInt32(1)
    )
    initial_ownership = copy(candidate.ownership)
    initial_kinds = copy(candidate.cell_kinds)
    initial_generations = copy(candidate.cell_generations)
    reference_candidate = CorePotts.initialize_program(
        program, initial, parameters, UInt64(0x71), UInt32(1)
    )
    reference_workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, reference_candidate.engine_workspace
    )
    CorePotts.enqueue_checkerboard_mcs!(reference_workspace, 0)
    reference_receipt = CorePotts.settle_program!(
        reference_workspace,
        CorePotts.ProgramSettlementRequest(
            CorePotts.PublicStepSettlement; full_snapshot = true
        ),
    )
    workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, candidate.engine_workspace
    )
    require_isbits && @test isbitstype(typeof(kernel_convert(workspace.state)))

    CorePotts.enqueue_checkerboard_mcs!(workspace, 0)
    CorePotts.enqueue_checkerboard_mcs!(workspace, 1)
    receipt = CorePotts.settle_program!(
        workspace,
        CorePotts.ProgramSettlementRequest(
            CorePotts.FinalizationSettlement; full_snapshot = true
        ),
    )

    status = receipt.status
    @test status.code === CorePotts.LifecycleStatusCellCapacity
    @test status.mcs == 1
    @test status.stage === CorePotts.LifecycleStageSelection
    @test status.source > 0
    @test status.action_identity != 0
    @test receipt.failure isa CorePotts.CellCapacityFailure
    @test receipt.submitted_mcs == 2
    @test receipt.drained_mcs == 2
    @test receipt.committed_mcs == 0
    @test receipt.materialized_mcs == 0
    @test workspace.execution.settlement_count == 1
    @test receipt.snapshot.ownership == initial_ownership
    @test receipt.snapshot.cell_kinds == initial_kinds
    @test receipt.snapshot.cell_generations == initial_generations
    @test reference_receipt.failure isa CorePotts.CellCapacityFailure
    @test reference_receipt.status == receipt.status
    @test _lifecycle_workspace_scratch(reference_workspace, to_host) ==
        _lifecycle_workspace_scratch(workspace, to_host)

    return (
        backend = backend_name,
        status = status.code,
        failure_mcs = Int(status.mcs),
        failure_stage = status.stage,
        committed_mcs = receipt.committed_mcs,
        settlements = workspace.execution.settlement_count,
    )
end

function _lifecycle_workspace_scratch(workspace, to_host)
    lifecycle = workspace.state.lifecycle_workspace
    control = workspace.state.lifecycle_control
    host(value) = copy(to_host(value))
    return (
        checkerboard = (
            target_sites = host(workspace.target_sites),
            source_sites = host(workspace.source_sites),
            old_owners = host(workspace.old_owners),
            new_owners = host(workspace.new_owners),
            priorities = host(workspace.priorities),
            semantic_ids = host(workspace.semantic_ids),
            dispositions = host(workspace.dispositions),
            maximum_priority = host(workspace.cell_max_priority),
            minimum_identity = host(workspace.cell_min_identity),
            report = host(workspace.report),
        ),
        lifecycle = (
            request_count = host(lifecycle.request_count),
            descriptor = host(lifecycle.descriptor),
            anchor = host(lifecycle.anchor),
            generation = host(lifecycle.generation),
            occurrence = host(lifecycle.occurrence),
            active = host(lifecycle.active),
            selected = host(lifecycle.selected),
            filtered = host(lifecycle.filtered),
            filtered_detail = host(lifecycle.filtered_detail),
            planned_site_count = host(lifecycle.planned_site_count),
            planned_sites = host(lifecycle.planned_sites),
            partition_labels = host(lifecycle.partition_labels),
            partition_scratch = host(lifecycle.partition_scratch),
            partition_owner = host(lifecycle.partition_owner),
            cell_site_starts = host(lifecycle.cell_site_starts),
            cell_site_counts = host(lifecycle.cell_site_counts),
            cell_site_cursor = host(lifecycle.cell_site_cursor),
            cell_sites = host(lifecycle.cell_sites),
            site_position = host(lifecycle.site_position),
            policy_workspace = host(lifecycle.policy_workspace),
            allocation = host(lifecycle.allocation),
            canonical_order = host(lifecycle.canonical_order),
            conflict_seen = host(lifecycle.conflict_seen),
            site_seen = host(lifecycle.site_seen),
            site_queue = host(lifecycle.site_queue),
            free_slots = host(lifecycle.free_slots),
            representative_site = host(lifecycle.representative_site),
            status = host(lifecycle.status),
        ),
        control = (
            counters = host(control.counters),
            request_scan = host(control.request_scan),
            request_scan_scratch = host(control.request_scan_scratch),
            candidate_status = host(control.candidate_status),
            site_keys = host(control.site_keys),
            statistics = host(control.statistics),
        ),
    )
end

function run_public_lifecycle_capacity_failure(;
        engine = CheckerboardEngine()
    )
    executable, _ = _lifecycle_backend_fixture(max_cells = 1; engine)
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    problem = PottsProblem(executable, initial, (0, 2); seed = 0x71)
    integrator = init(problem)
    initial_ownership = copy(integrator.runtime.ownership)

    step!(integrator)

    @test integrator.retcode === PottsToolkit.SciMLBase.ReturnCode.Failure
    @test PottsToolkit.SciMLBase.check_error(integrator) ===
        PottsToolkit.SciMLBase.ReturnCode.Failure
    @test integrator.t == 0
    @test integrator.runtime.mcs == 0
    @test integrator.runtime.settled
    @test integrator.runtime.ownership == initial_ownership
    @test integrator.failure_report !== nothing
    @test integrator.failure_report.mcs == 1
    @test integrator.failure_report.code ===
        CorePotts.LifecycleStatusCellCapacity
    settlements = engine isa CheckerboardEngine ?
        integrator.runtime.engine_workspace.execution.settlement_count : 0
    engine isa CheckerboardEngine && @test settlements == 1

    solve_integrator = init(problem)
    solution = solve!(solve_integrator)
    @test solution.retcode === PottsToolkit.SciMLBase.ReturnCode.Failure
    @test !PottsToolkit.SciMLBase.successful_retcode(solution)
    @test solution.t == [0]
    @test solution.failure_report !== nothing
    @test solution.failure_report.mcs == 1
    engine isa CheckerboardEngine && @test(
        solve_integrator.runtime.engine_workspace.execution.settlement_count == 1
    )
    return (
        retcode = solution.retcode,
        committed_mcs = integrator.runtime.mcs,
        failure_mcs = integrator.failure_report.mcs,
        settlements,
    )
end

function run_public_lifecycle_settlement_schedule()
    executable, _ = _lifecycle_backend_fixture()
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    long_problem = PottsProblem(executable, initial, (0, 100); seed = 0x71)

    frequent = init(long_problem; save_start = false)
    for _ in 1:100
        step!(frequent)
    end
    frequent_state = CorePotts.program_snapshot(frequent.runtime)
    @test frequent.runtime.engine_workspace.execution.settlement_count == 100

    chunked = init(long_problem; save_start = false)
    chunked_solution = solve!(chunked)
    @test chunked_solution.retcode === PottsToolkit.SciMLBase.ReturnCode.Success
    @test chunked.t == 100
    @test chunked.runtime.engine_workspace.execution.settlement_count == 1
    chunked_state = CorePotts.program_snapshot(chunked.runtime)
    @test chunked_state.ownership == frequent_state.ownership
    @test chunked_state.cell_kinds == frequent_state.cell_kinds
    @test chunked_state.cell_generations == frequent_state.cell_generations
    @test chunked_state.trackers.values == frequent_state.trackers.values
    @test (
        chunked.runtime.accepted,
        chunked.runtime.rejected,
        chunked.runtime.null_attempts,
        chunked.runtime.constraint_rejections,
        chunked.runtime.energy_rejections,
        chunked.runtime.retired_cells,
    ) == (
        frequent.runtime.accepted,
        frequent.runtime.rejected,
        frequent.runtime.null_attempts,
        frequent.runtime.constraint_rejections,
        frequent.runtime.energy_rejections,
        frequent.runtime.retired_cells,
    )

    saved = init(
        long_problem;
        save_start = false,
        saveat = (25, 50, 75, 100),
    )
    saved_solution = solve!(saved)
    @test saved_solution.retcode === PottsToolkit.SciMLBase.ReturnCode.Success
    @test saved_solution.t == [25, 50, 75, 100]
    @test saved.runtime.engine_workspace.execution.settlement_count == 4

    step_problem = remake(long_problem; tspan = (0, 4))
    stepped = init(step_problem; save_start = false)
    for _ in 1:4
        step!(stepped)
    end
    @test stepped.t == 4
    @test stepped.runtime.engine_workspace.execution.settlement_count == 4

    return (
        final_only = chunked.runtime.engine_workspace.execution.settlement_count,
        saveat = saved.runtime.engine_workspace.execution.settlement_count,
        public_steps = stepped.runtime.engine_workspace.execution.settlement_count,
    )
end

"""
    run_lifecycle_execution(device_array; backend_name, kernel_convert, to_host=Array)

Run one complete lifecycle transaction through the shared backend-resident
KernelAbstractions/AcceleratedKernels path. Vendor runners provide only storage adaptation and the
single explicit terminal observation boundary.
"""
function run_lifecycle_execution(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_isbits::Bool = true,
    )
    executable, initial = _lifecycle_backend_fixture()
    program = executable.core_program
    parameters = program.parameter_defaults
    seed = UInt64(0x71)
    replica = UInt32(1)
    reference = CorePotts.initialize_program(
        program, initial, parameters, seed, replica
    )
    candidate = CorePotts.initialize_program(
        program, initial, parameters, seed, replica
    )
    CorePotts.execute_lifecycle!(reference)

    workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, candidate.engine_workspace
    )
    state = workspace.state
    require_isbits && @test isbitstype(typeof(kernel_convert(state)))
    CorePotts.enqueue_lifecycle_backend_index!(state)
    backend = CorePotts.KernelAbstractions.get_backend(state.ownership)
    CorePotts.KernelAbstractions.synchronize(backend)

    status = only(to_host(state.lifecycle_workspace.status))
    @test status.code === CorePotts.LifecycleStatusSuccess
    @test to_host(state.ownership) == reference.ownership
    @test to_host(state.cell_kinds) == reference.cell_kinds
    @test to_host(state.cell_generations) == reference.cell_generations
    @test CorePotts.tracker_values(
        state.program.tracker_plan,
        CorePotts.Adapt.adapt(Array, state.trackers),
        Val(:cell_volume),
    ) == CorePotts.program_tracker_values(reference, Val(:cell_volume))
    payload_handle = only(executable.reports.states).handle
    device_payload = CorePotts.state_block(
        CorePotts.Adapt.adapt(Array, state.descriptor_state), payload_handle
    ).values
    reference_payload = CorePotts.state_block(
        reference.descriptor_state, payload_handle
    ).values
    @test device_payload == reference_payload
    counters = to_host(state.lifecycle_control.counters)
    statistics = to_host(state.lifecycle_control.statistics)
    @test counters[CorePotts._LIFECYCLE_CONTROL_SELECTED] == 1
    @test statistics[CorePotts._PROGRAM_STAT_RETIRED] == 0

    return (
        backend = backend_name,
        selected = Int(counters[CorePotts._LIFECYCLE_CONTROL_SELECTED]),
        active_cells = count(!iszero, reference.cell_kinds),
        ownership_checksum = sum(
            index * Int(owner)
            for (index, owner) in enumerate(reference.ownership)
        ),
    )
end
