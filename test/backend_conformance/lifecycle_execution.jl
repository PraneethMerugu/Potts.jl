using Test
using PottsToolkit
using Symbolics

import CorePotts

function _lifecycle_backend_fixture(; max_cells = 2)
    @variables lifecycle_payload
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
        expression = cell_volume(anchor_value(anchor)) >= 4,
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
        cadence = AtMCS(1),
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
    )
    executable = compile(
        complete(system);
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
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

    return (
        backend = backend_name,
        status = status.code,
        failure_mcs = Int(status.mcs),
        failure_stage = status.stage,
        committed_mcs = receipt.committed_mcs,
        settlements = workspace.execution.settlement_count,
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
