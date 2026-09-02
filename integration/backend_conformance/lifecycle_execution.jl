using Test
using Potts
using ModelingToolkitBase
using Symbolics

import CorePotts
import LocalMath

_lifecycle_adapted_execution(to, runtime) = to === Array ?
    runtime.engine_workspace :
    CorePotts.adapt_program_runtime(to, runtime).engine_workspace

function _lifecycle_backend_fixture(;
        max_cells = 2,
        engine = CheckerboardSweepCPM(),
        backend = CPUBackend(),
        division_mcs::Integer = 1,
        freeze_proposals::Bool = false,
        lower::Bool = true,
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
            (freeze_proposals ? (
                ProposalConstraint(:lifecycle_freeze, false),
            ) : ())...,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [lifecycle_payload],
        parameters = [lifecycle_division_threshold],
    )
    scheduled = mtkcompile(complete(system))
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    lower || return scheduled, initial
    executable = Potts._lower_execution_plan(
        scheduled, engine, backend, Float32
    )
    return executable, Potts._core_initial_state(
        executable, initial, UInt64(0x71), UInt32(1)
    )
end

function _canonical_state_failure_fixture(reverse_declarations::Bool)
    @variables probe_time probe_value(probe_time) probe_reset_value(probe_time)
    @parameters probe_zero = 0.0f0
    cell = CellKind(:probe_cell; extinction = RetireAtZero())
    medium = MediumKind(:probe_medium)
    relation = SpatialRelation(
        :probe_division; neighborhood = VonNeumann()
    )
    state = CellState(
        probe_value;
        name = :probe_state,
        initial = 1.0f0,
        retirement = RetireTo(0.0f0),
        division = CopyToDaughters(),
    )
    reset_state = CellState(
        probe_reset_value;
        name = :probe_reset_state,
        initial = 4.0f0,
        retirement = RetireTo(0.0f0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:probe_anchor)
    divide = LifecycleProcess(
        :z_probe_divide;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0f0, 0.0f0)),
            relation,
            side = CanonicalSide(),
            state = (
                state => TransformDaughters(
                    1.0f0 / probe_zero,
                    1.0f0 / probe_zero,
                ),
                reset_state => ResetBoth(
                    1.0f0 / probe_zero,
                    1.0f0 / probe_zero,
                ),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    create = LifecycleProcess(
        :a_probe_create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedAt(1),
            state = (
                state => InitializeFrom(1.0f0 / probe_zero),
                reset_state => InitializeFrom(4.0f0),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    lifecycle = reverse_declarations ? (create, divide) : (divide, create)
    system = PottsSystem(
        name = :LifecycleFailureOrderProbe,
        statements = StatementSet((
            Lattice((6, 6); max_cells = 3),
            cell,
            medium,
            relation,
            state,
            reset_state,
            lifecycle...,
            ProposalConstraint(:probe_freeze, false),
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [probe_value, probe_reset_value],
        parameters = [probe_zero],
        independent_variables = [probe_time],
    )
    labels = zeros(Int, 6, 6)
    labels[3:4, 2:5] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    return complete(system), initial
end

function _canonical_state_failure_runtime(executable, initial)
    core_initial = Potts._core_initial_state(
        executable, initial, UInt64(0x77), UInt32(1)
    )
    return CorePotts.initialize_program(
        executable.core_program,
        core_initial,
        executable.core_program.parameter_defaults,
        UInt64(0x77),
        UInt32(1),
    )
end

function _lifecycle_scientific_state(state)
    host = CorePotts.Adapt.adapt(Array, state)
    relationships = Tuple((
        active = copy(value.active),
        endpoint_a = copy(value.endpoint_a),
        endpoint_b = copy(value.endpoint_b),
        generation_a = copy(value.generation_a),
        generation_b = copy(value.generation_b),
        payload = deepcopy(value.payload),
        degree = copy(value.degree),
        incident_edges = copy(value.incident_edges),
    ) for value in host.relationships)
    descriptor_state = Tuple(
        copy(bank.values) for bank in host.descriptor_state.banks
    )
    return (
        ownership = copy(host.ownership),
        cell_kinds = copy(host.cell_kinds),
        cell_generations = copy(host.cell_generations),
        trackers = deepcopy(host.trackers.values),
        relationships,
        descriptor_state,
    )
end

function run_lifecycle_canonical_state_failure(
        device_array;
        backend_name::Symbol,
        kernel_convert = identity,
        to_host = Array,
        require_isbits::Bool = true,
    )
    statuses = CorePotts.ProgramStatus[]
    program_types = DataType[]
    selected_counts = Int[]
    for reverse_declarations in (false, true)
        completed, initial = _canonical_state_failure_fixture(
            reverse_declarations
        )
        scheduled = mtkcompile(completed)
        sequential = Potts._lower_execution_plan(
            scheduled,
            SequentialCPM(),
            CPUBackend(),
            Float32,
        )
        checkerboard_executable = Potts._lower_execution_plan(
            scheduled,
            CheckerboardSweepCPM(),
            CPUBackend(),
            Float32,
        )
        push!(program_types, typeof(checkerboard_executable.core_program))

        host = _canonical_state_failure_runtime(sequential, initial)
        host_before = _lifecycle_scientific_state(host)
        host_error = try
            CorePotts.execute_lifecycle!(host)
            nothing
        catch error
            error
        end
        host_status = CorePotts.lifecycle_workspace_status(
            host.lifecycle_workspace
        )
        @test host_error isa CorePotts.LifecycleEvaluatorFailure
        @test _lifecycle_scientific_state(host) == host_before

        candidate = _canonical_state_failure_runtime(
            checkerboard_executable, initial
        )
        device_before = _lifecycle_scientific_state(
            CorePotts.program_snapshot(candidate)
        )
        workspace = _lifecycle_adapted_execution(device_array, candidate)
        checkerboard = CorePotts._checkerboard_core(workspace)
        require_isbits &&
            @test isbitstype(typeof(kernel_convert(checkerboard.state)))
        destination = CorePotts.enqueue_checkerboard_mcs!(workspace, 0)
        receipt = CorePotts.settle_program!(
            workspace,
            CorePotts.ProgramSettlementRequest(
                CorePotts.FinalizationSettlement; full_snapshot = true
            ),
        )
        device_status = receipt.status
        destination_workspace = destination.lifecycle_workspace
        selected_mask = to_host(destination_workspace.selection.selected)
        selected = count(selected_mask)
        anchors = to_host(destination_workspace.anchor)
        descriptors = to_host(destination_workspace.descriptor)
        candidate_status = CorePotts.Adapt.adapt(
            Array,
            checkerboard.state.lifecycle_control.candidate_status
        )
        failure_rank = to_host(
            checkerboard.state.lifecycle_control.state_rule_failure_rank
        )
        divide_request = only(findall(
            request -> selected_mask[request] && anchors[request] == 1,
            eachindex(selected_mask),
        ))
        divide_descriptor =
            checkerboard_executable.core_program.lifecycle_plan.descriptors[
                descriptors[divide_request]
            ]

        @test device_status == host_status
        @test _lifecycle_scientific_state(receipt.snapshot) == device_before
        @test receipt.failure isa CorePotts.LifecycleEvaluatorFailure
        @test receipt.submitted_mcs == 1
        @test receipt.drained_mcs == 1
        @test receipt.committed_mcs == 0
        @test receipt.materialized_mcs == 0
        @test selected == 2
        @test candidate_status[divide_request].detail ===
            CorePotts.LifecycleDetailNonfiniteResult
        @test failure_rank[divide_request] ==
            divide_descriptor.state_rule_offset
        @test device_status.code === CorePotts.ProgramStatusEvaluator
        @test device_status.mcs == 1
        @test device_status.stage === CorePotts.ProgramStageState
        @test device_status.source > 0
        @test device_status.action_identity != 0
        # The public mtkcompile schedule canonically orders the model-scoped
        # create failure before the cell-scoped divide failure.  Its created
        # slot is therefore the reported failing anchor, independent of source
        # declaration order.
        @test device_status.anchor == 2
        @test device_status.detail ===
            CorePotts.LifecycleDetailNonfiniteResult
        push!(statuses, device_status)
        push!(selected_counts, selected)
    end
    @test allequal(program_types)
    @test allequal(statuses)
    return (
        backend = backend_name,
        permutations = length(statuses),
        selected = Tuple(selected_counts),
        status = first(statuses),
    )
end

function run_public_device_lifecycle_execution(backend_selector)
    scheduled, _ = _lifecycle_backend_fixture(lower = false)
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x71)

    stepped = init(
        problem,
        CheckerboardSweepCPM();
        backend = backend_selector,
        scalar_type = Float32,
        save_start = false,
    )
    @test !(_test_checkerboard_core(stepped.runtime).state.ownership isa Array)
    step!(stepped)
    @test stepped.t == 1
    @test _test_checkerboard_execution(stepped.runtime).settlement_count == 1
    captured = checkpoint(stepped)

    device_integrator = init(
        problem,
        CheckerboardSweepCPM();
        backend = backend_selector,
        scalar_type = Float32,
        save_start = false,
    )
    device_solution = solve!(device_integrator)
    reference_solution = solve(
        problem,
        CheckerboardSweepCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    @test device_solution.retcode === Potts.SciMLBase.ReturnCode.Success
    @test device_integrator.t == 2
    @test _test_checkerboard_execution(
        device_integrator.runtime
    ).settlement_count == 1
    @test only(device_solution.u).ownership == only(reference_solution.u).ownership
    @test device_integrator.runtime.accepted == reference_solution.stats.accepted
    @test device_integrator.runtime.rejected == reference_solution.stats.rejected
    @test device_integrator.runtime.null_attempts ==
        reference_solution.stats.null_attempts

    resumed = init(
        problem,
        CheckerboardSweepCPM();
        backend = backend_selector,
        scalar_type = Float32,
        checkpoint = captured,
        save_start = false,
    )
    resumed_solution = solve!(resumed)
    @test resumed_solution.retcode ===
        Potts.SciMLBase.ReturnCode.Success
    @test resumed.t == 2
    @test only(resumed_solution.u).ownership ==
        only(device_solution.u).ownership

    updated = init(
        problem,
        CheckerboardSweepCPM();
        backend = backend_selector,
        scalar_type = Float32,
        save_start = false,
    )
    setter = Potts.SymbolicIndexingInterface.setp(
        updated, :lifecycle_division_threshold
    )
    setter(updated, 100.0f0)
    updated_solution = solve!(updated)
    @test updated_solution.retcode ===
        Potts.SciMLBase.ReturnCode.Success
    @test count(!iszero, only(updated_solution.u).cell_kinds) == 1
    @test _test_checkerboard_execution(updated.runtime).settlement_count == 1

    capacity_scheduled, _ = _lifecycle_backend_fixture(
        max_cells = 1, lower = false
    )
    capacity_problem = PottsProblem(
        capacity_scheduled, initial, (0, 2); seed = 0x71
    )
    failed = init(
        capacity_problem,
        CheckerboardSweepCPM();
        backend = backend_selector,
        scalar_type = Float32,
        save_start = false,
    )
    failed_solution = solve!(failed)
    @test failed_solution.retcode === Potts.SciMLBase.ReturnCode.Failure
    @test failed.t == 0
    @test failed.failure_report !== nothing
    @test failed.failure_report.mcs == 1
    @test _test_checkerboard_execution(failed.runtime).submitted_mcs == 2
    @test _test_checkerboard_execution(failed.runtime).committed_mcs == 0
    @test _test_checkerboard_execution(failed.runtime).settlement_count == 1

    return (
        backend = nameof(typeof(backend_selector)),
        stepped_mcs = stepped.t,
        solved_mcs = device_integrator.t,
        settlements = _test_checkerboard_execution(
            device_integrator.runtime
        ).settlement_count,
        resumed_mcs = resumed.t,
        updated_cells = count(!iszero, only(updated_solution.u).cell_kinds),
        failure_mcs = failed.failure_report.mcs,
    )
end

function run_public_lifecycle_late_capacity_failure()
    scheduled, _ = _lifecycle_backend_fixture(
        max_cells = 1, division_mcs = 37, lower = false
    )
    labels = fill(1, 6, 6)
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    problem = PottsProblem(scheduled, initial, (0, 100); seed = 0x71)

    reference = init(
        problem, CheckerboardSweepCPM(); save_start = false
    )
    for _ in 1:36
        step!(reference)
    end
    reference_snapshot = CorePotts.program_snapshot(reference.runtime)

    queued = init(problem, CheckerboardSweepCPM(); save_start = false)
    solution = solve!(queued)
    @test solution.retcode === Potts.SciMLBase.ReturnCode.Failure
    @test queued.retcode === Potts.SciMLBase.ReturnCode.Failure
    @test queued.t == 36
    @test queued.runtime.mcs == 36
    @test queued.iterations == 37
    @test queued.failure_report !== nothing
    @test queued.failure_report.mcs == 37
    @test queued.failure_report.stage === CorePotts.ProgramStageSelection
    @test _test_checkerboard_execution(queued.runtime).submitted_mcs == 100
    @test _test_checkerboard_execution(queued.runtime).drained_mcs == 100
    @test _test_checkerboard_execution(queued.runtime).committed_mcs == 36
    @test _test_checkerboard_execution(queued.runtime).settlement_count == 1
    queued_snapshot = CorePotts.program_snapshot(queued.runtime)
    @test queued_snapshot.ownership == reference_snapshot.ownership
    @test queued_snapshot.cell_kinds == reference_snapshot.cell_kinds
    @test queued_snapshot.cell_generations == reference_snapshot.cell_generations
    @test queued_snapshot.trackers.values == reference_snapshot.trackers.values

    return (
        submitted_mcs = _test_checkerboard_execution(queued.runtime).submitted_mcs,
        committed_mcs = queued.runtime.mcs,
        failure_mcs = queued.failure_report.mcs,
        settlements = _test_checkerboard_execution(queued.runtime).settlement_count,
    )
end

function run_public_settlement_consumers()
    scheduled, _ = _lifecycle_backend_fixture(lower = false)
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x71)

    checkpoint_integrator = init(
        problem, CheckerboardSweepCPM(); save_start = false
    )
    CorePotts.enqueue_program_mcs!(checkpoint_integrator.runtime)
    @test !checkpoint_integrator.runtime.settled
    captured = checkpoint(checkpoint_integrator)
    @test checkpoint_integrator.runtime.settled
    @test checkpoint_integrator.t == 1
    @test captured.core.snapshot.mcs == 1
    @test _test_checkerboard_execution(
        checkpoint_integrator.runtime
    ).settlement_count == 1

    index_integrator = init(
        problem, CheckerboardSweepCPM(); save_start = false
    )
    CorePotts.enqueue_program_mcs!(index_integrator.runtime)
    observed_time = Potts.SymbolicIndexingInterface.current_time(
        index_integrator
    )
    @test observed_time == 1
    @test _test_checkerboard_execution(
        index_integrator.runtime
    ).settlement_count == 1

    statistics_integrator = init(
        problem, CheckerboardSweepCPM(); save_start = false
    )
    CorePotts.enqueue_program_mcs!(statistics_integrator.runtime)
    statistics = Potts.runtime_statistics(statistics_integrator)
    @test statistics.steps == 1
    @test _test_checkerboard_execution(
        statistics_integrator.runtime
    ).settlement_count == 1

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

function run_lifecycle_bank_alias_invariant(
        device_array;
        backend_name::Symbol,
        kernel_convert = identity,
        require_isbits::Bool = true,
    )
    executable, initial = _lifecycle_backend_fixture()
    program = executable.core_program
    runtime = CorePotts.initialize_program(
        program,
        initial,
        program.parameter_defaults,
        UInt64(0x71),
        UInt32(1),
    )
    runtime = device_array === nothing ? runtime :
        CorePotts.adapt_program_runtime(device_array, runtime)
    workspace = _test_checkerboard_core(runtime)
    require_isbits && @test isbitstype(typeof(kernel_convert(workspace.state)))
    for state in (workspace.state, workspace.alternate_state)
        lifecycle = state.lifecycle_workspace
        @test lifecycle.staged_ownership === state.ownership
        @test lifecycle.staged_cell_kinds === state.cell_kinds
        @test lifecycle.staged_cell_generations === state.cell_generations
        @test lifecycle.staged_trackers === state.trackers
        @test lifecycle.staged_relationships === state.relationships
        @test lifecycle.staged_descriptor_state === state.descriptor_state
    end
    primary = last.(CorePotts._program_state_copy_leaves(workspace.state))
    alternate = last.(CorePotts._program_state_copy_leaves(
        workspace.alternate_state
    ))
    @test length(primary) == length(alternate)
    @test all(
        primary_leaf !== alternate_leaf &&
            !Base.mightalias(primary_leaf, alternate_leaf)
        for primary_leaf in primary for alternate_leaf in alternate
    )
    return (
        backend = backend_name,
        physical_leaves = length(primary),
        initialization_stage_counts = map(
            fact -> length(fact.stages) - 2,
            CorePotts._inspect_checkerboard_execution(
                runtime.engine_workspace).clear_report),
        staged_aliases = true,
        banks_disjoint = true,
    )
end

function run_queued_lifecycle_mcs(
        device_array;
        backend_name::Symbol,
        kernel_convert = identity,
        require_isbits::Bool = true,
        queue_mcs::Integer = 12,
    )
    queue_mcs == 12 || throw(ArgumentError(
        "the lifecycle queue witness is fixed at twelve MCSs"
    ))
    executable, initial = _lifecycle_backend_fixture(division_mcs = 1000)
    program = executable.core_program
    runtime = CorePotts.initialize_program(
        program,
        initial,
        program.parameter_defaults,
        UInt64(0x71),
        UInt32(1),
    )
    runtime = device_array === nothing ? runtime :
        CorePotts.adapt_program_runtime(device_array, runtime)
    execution_workspace = runtime.engine_workspace
    workspace = _test_checkerboard_core(runtime)
    require_isbits && @test isbitstype(typeof(kernel_convert(workspace.state)))
    physical_leaves = last.(CorePotts._program_state_copy_leaves(
        workspace.state
    ))
    clear_report_facts = CorePotts._inspect_checkerboard_execution(
        execution_workspace
    ).clear_report
    initialization_stage_counts = map(
        fact -> length(fact.stages) - 2, clear_report_facts)
    length_histogram = unique(map(length, physical_leaves))
    enqueue_bytes = Int[]
    for mcs in 0:(queue_mcs - 1)
        bytes = @allocated CorePotts.enqueue_program_mcs!(runtime)
        mcs >= 2 && push!(enqueue_bytes, bytes)
    end
    receipt = CorePotts.settle_program!(
        runtime,
        CorePotts.ProgramSettlementRequest(
            CorePotts.FinalizationSettlement; full_snapshot = true
        ),
    )
    execution = workspace.execution
    @test receipt.submitted_mcs == queue_mcs
    @test receipt.drained_mcs == queue_mcs
    @test receipt.committed_mcs == queue_mcs
    @test receipt.materialized_mcs == queue_mcs
    @test receipt.status.code === CorePotts.ProgramStatusSuccess
    @test receipt.failure === nothing
    @test execution.settlement_count == 1
    @test execution.synchronization_count == 1
    return (
        backend = backend_name,
        queued_mcs = queue_mcs,
        physical_leaf_count = length(physical_leaves),
        initialization_stage_count = only(unique(
            initialization_stage_counts)),
        initialization_stage_counts,
        preliminary_length_group_count = length(length_histogram),
        preliminary_length_groups = Tuple(sort!(collect(length_histogram))),
        warm_enqueue_bytes = Tuple(enqueue_bytes),
        settlements = execution.settlement_count,
        synchronizations = execution.synchronization_count,
        committed_mcs = receipt.committed_mcs,
    )
end

function run_lifecycle_mcs_execution(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_isbits::Bool = true,
    )
    executable, initial = _lifecycle_backend_fixture(freeze_proposals = true)
    reference_executable, reference_initial = _lifecycle_backend_fixture(
        engine = SequentialCPM(), freeze_proposals = true
    )
    program = executable.core_program
    parameters = program.parameter_defaults
    seed = UInt64(0x71)
    replica = UInt32(1)
    reference = CorePotts.initialize_program(
        reference_executable.core_program,
        reference_initial,
        reference_executable.core_program.parameter_defaults,
        seed,
        replica,
    )
    candidate = CorePotts.initialize_program(
        program, initial, parameters, seed, replica
    )
    CorePotts.advance_mcs!(reference)
    CorePotts.advance_mcs!(reference)

    workspace = _lifecycle_adapted_execution(device_array, candidate)
    checkerboard = CorePotts._checkerboard_core(workspace)
    require_isbits &&
        @test isbitstype(typeof(kernel_convert(checkerboard.state)))
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
    @test receipt.status.code === CorePotts.ProgramStatusSuccess
    @test receipt.failure === nothing
    @test receipt.submitted_mcs == 2
    @test receipt.drained_mcs == 2
    @test receipt.committed_mcs == 2
    @test receipt.materialized_mcs == 2
    @test CorePotts._checkerboard_execution_position(
        workspace
    ).settlement_count == 1
    @test iszero(receipt.counters.accepted)
    @test receipt.counters.rejected ==
        receipt.counters.constraint_rejections
    @test iszero(receipt.counters.energy_rejections)
    ownership_checksum = sum(
        index * Int(owner)
        for (index, owner) in enumerate(reference.ownership)
    )
    @test ownership_checksum == 95

    return (
        backend = backend_name,
        committed_mcs = receipt.committed_mcs,
        settlements = CorePotts._checkerboard_execution_position(
            workspace
        ).settlement_count,
        ownership_checksum,
    )
end

function run_lifecycle_compaction_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
    )
    LW = LocalMath
    ownership = device_array(Int32[0, 1, 1, 2, 0, 2])
    backend = CorePotts.KernelAbstractions.get_backend(ownership)
    gate = device_array(Bool[true])
    site_spec = CorePotts._lifecycle_site_compaction_work(6, 2)

    source = CorePotts.StructArrays.StructArray{
        CorePotts._LifecycleRequestSource
    }((
        priority = Int32[2, 0, 1, 0],
        source_high = UInt32[1, 0, 1, 0],
        source_low = UInt32[2, 0, 1, 0],
        action_high = UInt32[3, 0, 2, 0],
        action_low = UInt32[4, 0, 3, 0],
        anchor = Int32[2, 0, 1, 0],
        generation = UInt32[5, 0, 7, 0],
        active = Bool[true, false, true, false],
    ))
    source = CorePotts.Adapt.adapt(backend, source)
    request_spec = CorePotts._lifecycle_request_compaction_work(4)
    allocate_records(T, count) = LW._allocate_compacted_records(
        backend, T, count)
    site_storage = LW.CompactedStorage(LW._CONSTRUCTION_TOKEN,
        allocate_records(CorePotts._LifecycleOwnedSite, 6),
        allocate_records(Int32, 1), allocate_records(Int32, 3),
        allocate_records(Int32, 6), allocate_records(Int32, 6),
        allocate_records(Int32, 6))
    request_storage = LW.CompactedStorage(LW._CONSTRUCTION_TOKEN,
        allocate_records(CorePotts._LifecycleCanonicalRequest, 4),
        allocate_records(Int32, 1), nothing, allocate_records(Int32, 4),
        allocate_records(Int32, 4), allocate_records(Int32, 4))
    site_gate_endpoints = similar(ownership, Int32, 1, length(ownership))
    CorePotts._fill_lifecycle_singleton_endpoints_kernel!(backend)(
        site_gate_endpoints; ndrange = length(ownership))
    request_gate_endpoints = similar(ownership, Int32, 1, 4)
    CorePotts._fill_lifecycle_singleton_endpoints_kernel!(backend)(
        request_gate_endpoints; ndrange = 4)
    CorePotts.KernelAbstractions.synchronize(backend)

    site_prepared = LW.prepare(site_spec.law,
        site_spec.ownership => ownership,
        site_spec.gate => gate,
        site_spec.gate_relation => (endpoints = site_gate_endpoints,),
        site_spec.sites => site_storage;
        backend, lease_capacity = 1)
    request_prepared = LW.prepare(request_spec.law,
        request_spec.requests => source,
        request_spec.gate => gate,
        request_spec.gate_relation => (endpoints = request_gate_endpoints,),
        request_spec.canonical => request_storage;
        backend, lease_capacity = 1)

    wait(LW.execute!(site_prepared))
    wait(LW.execute!(request_prepared))
    host_sites = CorePotts.Adapt.adapt(Array, site_storage)
    host_requests = CorePotts.Adapt.adapt(Array, request_storage)
    site_count = Int(only(host_sites.count))
    request_count = Int(only(host_requests.count))
    site_snapshot = (
        count = site_count,
        owners = copy(host_sites.records.owner[1:site_count]),
        sites = copy(host_sites.records.site[1:site_count]),
        starts = copy(host_sites.segment_starts),
        positions = copy(host_sites.source_position),
    )
    request_snapshot = (
        count = request_count,
        slots = copy(host_requests.records.slot[1:request_count]),
        keys = copy(host_requests.records.key[1:request_count]),
        identities = copy(
            host_requests.records.identity[1:request_count]
        ),
    )
    @test site_snapshot.count == 4
    @test site_snapshot.owners == Int32[1, 1, 2, 2]
    @test site_snapshot.sites == Int32[2, 3, 4, 6]
    @test site_snapshot.starts == Int32[1, 3, 5]
    @test site_snapshot.positions == Int32[0, 1, 2, 3, 0, 4]
    @test request_snapshot.count == 2
    @test request_snapshot.slots == Int32[3, 1]
    return (
        backend = backend_name,
        scalar_indexing = backend_name === :metal ? :disabled : :not_applicable,
        sites = site_snapshot,
        requests = request_snapshot,
    )
end

function run_lifecycle_capacity_failure(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_isbits::Bool = true,
    )
    executable, initial = _lifecycle_backend_fixture(
        max_cells = 1, freeze_proposals = true
    )
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
    reference_workspace = _lifecycle_adapted_execution(
        device_array, reference_candidate
    )
    CorePotts.enqueue_checkerboard_mcs!(reference_workspace, 0)
    reference_receipt = CorePotts.settle_program!(
        reference_workspace,
        CorePotts.ProgramSettlementRequest(
            CorePotts.PublicStepSettlement; full_snapshot = true
        ),
    )
    workspace = _lifecycle_adapted_execution(device_array, candidate)
    checkerboard = CorePotts._checkerboard_core(workspace)
    require_isbits &&
        @test isbitstype(typeof(kernel_convert(checkerboard.state)))

    CorePotts.enqueue_checkerboard_mcs!(workspace, 0)
    CorePotts.enqueue_checkerboard_mcs!(workspace, 1)
    receipt = CorePotts.settle_program!(
        workspace,
        CorePotts.ProgramSettlementRequest(
            CorePotts.FinalizationSettlement; full_snapshot = true
        ),
    )

    status = receipt.status
    @test status.code === CorePotts.ProgramStatusCellCapacity
    @test status.mcs == 1
    @test status.stage === CorePotts.ProgramStageSelection
    @test status.source > 0
    @test status.action_identity != 0
    @test receipt.failure isa CorePotts.CellCapacityFailure
    @test receipt.submitted_mcs == 2
    @test receipt.drained_mcs == 2
    @test receipt.committed_mcs == 0
    @test receipt.materialized_mcs == 0
    @test CorePotts._checkerboard_execution_position(
        workspace
    ).settlement_count == 1
    @test receipt.snapshot.ownership == initial_ownership
    @test receipt.snapshot.cell_kinds == initial_kinds
    @test receipt.snapshot.cell_generations == initial_generations
    @test reference_receipt.failure isa CorePotts.CellCapacityFailure
    @test reference_receipt.status == receipt.status

    return (
        backend = backend_name,
        status = status.code,
        failure_mcs = Int(status.mcs),
        failure_stage = status.stage,
        committed_mcs = receipt.committed_mcs,
        settlements = CorePotts._checkerboard_execution_position(
            workspace
        ).settlement_count,
    )
end

function run_public_lifecycle_capacity_failure(;
        engine = CheckerboardSweepCPM()
    )
    scheduled, _ = _lifecycle_backend_fixture(
        max_cells = 1; engine, freeze_proposals = true, lower = false
    )
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x71)
    integrator = init(problem, engine)
    initial_ownership = copy(integrator.runtime.ownership)

    step!(integrator)

    @test integrator.retcode === Potts.SciMLBase.ReturnCode.Failure
    @test Potts.SciMLBase.check_error(integrator) ===
        Potts.SciMLBase.ReturnCode.Failure
    @test integrator.t == 0
    @test integrator.runtime.mcs == 0
    @test integrator.runtime.settled
    @test integrator.runtime.ownership == initial_ownership
    @test integrator.failure_report !== nothing
    @test integrator.failure_report.mcs == 1
    @test integrator.failure_report.code ===
        CorePotts.ProgramStatusCellCapacity
    settlements = engine isa CheckerboardSweepCPM ?
        _test_checkerboard_execution(integrator.runtime).settlement_count : 0
    engine isa CheckerboardSweepCPM && @test settlements == 1

    solve_integrator = init(problem, engine)
    solution = solve!(solve_integrator)
    @test solution.retcode === Potts.SciMLBase.ReturnCode.Failure
    @test !Potts.SciMLBase.successful_retcode(solution)
    @test solution.t == [0]
    @test solution.failure_report !== nothing
    @test solution.failure_report.mcs == 1
    engine isa CheckerboardSweepCPM && @test(
        _test_checkerboard_execution(
            solve_integrator.runtime
        ).settlement_count == 1
    )
    return (
        retcode = solution.retcode,
        committed_mcs = integrator.runtime.mcs,
        failure_mcs = integrator.failure_report.mcs,
        settlements,
    )
end

function run_public_lifecycle_settlement_schedule()
    scheduled, _ = _lifecycle_backend_fixture(lower = false)
    labels = zeros(Int, 6, 6)
    labels[2:5, 3] .= 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [:lifecycle_cell], medium = :lifecycle_medium
    ))
    long_problem = PottsProblem(scheduled, initial, (0, 100); seed = 0x71)

    frequent = init(long_problem, CheckerboardSweepCPM(); save_start = false)
    for _ in 1:100
        step!(frequent)
    end
    frequent_state = CorePotts.program_snapshot(frequent.runtime)
    @test _test_checkerboard_execution(frequent.runtime).settlement_count == 100

    chunked = init(long_problem, CheckerboardSweepCPM(); save_start = false)
    chunked_solution = solve!(chunked)
    @test chunked_solution.retcode === Potts.SciMLBase.ReturnCode.Success
    @test chunked.t == 100
    @test _test_checkerboard_execution(chunked.runtime).settlement_count == 1
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
        long_problem,
        CheckerboardSweepCPM();
        save_start = false,
        saveat = (25, 50, 75, 100),
    )
    saved_solution = solve!(saved)
    @test saved_solution.retcode === Potts.SciMLBase.ReturnCode.Success
    @test saved_solution.t == [25, 50, 75, 100]
    @test _test_checkerboard_execution(saved.runtime).settlement_count == 4

    step_problem = remake(long_problem; tspan = (0, 4))
    stepped = init(
        step_problem, CheckerboardSweepCPM(); save_start = false
    )
    for _ in 1:4
        step!(stepped)
    end
    @test stepped.t == 4
    @test _test_checkerboard_execution(stepped.runtime).settlement_count == 4

    return (
        final_only = _test_checkerboard_execution(chunked.runtime).settlement_count,
        saveat = _test_checkerboard_execution(saved.runtime).settlement_count,
        public_steps = _test_checkerboard_execution(stepped.runtime).settlement_count,
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

    workspace = _lifecycle_adapted_execution(device_array, candidate)
    state = CorePotts._checkerboard_core(workspace).state
    require_isbits && @test isbitstype(typeof(kernel_convert(state)))
    bank = CorePotts._checkerboard_authorized_bank(workspace, state)
    CorePotts.enqueue_lifecycle_backend_index!(
        state, workspace.lifecycle_reductions[bank]
    )
    backend = CorePotts.KernelAbstractions.get_backend(state.ownership)
    CorePotts.KernelAbstractions.synchronize(backend)

    status = only(CorePotts.Adapt.adapt(
        Array, state.lifecycle_workspace.status
    ))
    @test status.code === CorePotts.ProgramStatusSuccess
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
    statistics = to_host(state.lifecycle_control.statistics)
    selection = CorePotts.Adapt.adapt(
        Array, state.lifecycle_workspace.selection
    )
    selected_count = Int(only(selection.selected_requests.count))
    @test selected_count == 1
    @test statistics[CorePotts._PROGRAM_STAT_RETIRED] == 0

    return (
        backend = backend_name,
        selected = selected_count,
        active_cells = count(!iszero, reference.cell_kinds),
        ownership_checksum = sum(
            index * Int(owner)
            for (index, owner) in enumerate(reference.ownership)
        ),
    )
end
