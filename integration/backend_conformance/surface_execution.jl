using Test
using Potts
using ModelingToolkitBase

import CorePotts

isdefined(@__MODULE__, :ExternalSurfaceOperationFixture) ||
    include("../../test/fixtures/ExternalSurfaceOperationFixture.jl")

function _surface_backend_fixture()
    cell = CellKind(:surface_backend_cell; extinction = RetireAtZero())
    medium = MediumKind(:surface_backend_medium)
    anchor = CellBinding(:surface_backend_anchor)
    @named model = PottsSystem(statements = StatementSet((
        Lattice(
            (6, 6);
            boundary = Periodic(),
            relations = (
                proposal = VonNeumann(),
                surface = VonNeumann(),
            ),
        ),
        cell,
        medium,
        HamiltonianTerm(
            :surface_backend_energy;
            domain = cells(cell),
            anchor,
            expression = 0.5f0 * (
                ExternalSurfaceOperationFixture.external_cell_surface(
                    anchor_value(anchor)
                ) - 12.0f0
            )^2,
        ),
        Protocol(Sweep(; temperature = 2.0f0); name = :main),
    )))
    executable = Potts._lower_execution_plan(
        mtkcompile(complete(model)),
        CheckerboardSweepCPM(),
        CPUBackend(),
        Float32,
    )
    labels = zeros(Int32, 6, 6)
    labels[2:5, 2:5] .= 1
    labels[3, 3] = 0
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
    )
    return executable, Potts._core_initial_state(executable, initial)
end

"""Backend-neutral surface evaluator/tracker/checkerboard qualification."""
function run_surface_execution(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_device_isbits::Bool = true,
    )
    executable, initial = _surface_backend_fixture()
    program = executable.core_program
    surface_descriptor = only(filter(
        descriptor -> CorePotts.tracker_inspection(descriptor).quantity ===
                      :cell_surface,
        CorePotts.tracker_instances(program.tracker_plan),
    ))
    surface_key = CorePotts.tracker_quantity(surface_descriptor)
    seed = UInt64(0x5fa)
    replica = UInt32(2)
    cpu_runtime = CorePotts.initialize_program(
        program, initial, program.parameter_defaults, seed, replica
    )
    device_runtime = CorePotts.initialize_program(
        program, initial, program.parameter_defaults, seed, replica
    )
    cpu_workspace = _test_checkerboard_core(cpu_runtime)
    device_workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, _test_checkerboard_core(device_runtime)
    )
    require_device_isbits &&
        @test isbitstype(typeof(kernel_convert(device_workspace.state)))

    CorePotts.execute_checkerboard_mcs!(cpu_workspace, 0)
    CorePotts.execute_checkerboard_mcs!(device_workspace, 0)
    _observe_checkerboard_boundary!(cpu_runtime, cpu_workspace, identity)
    _observe_checkerboard_boundary!(
        device_runtime, device_workspace, to_host
    )

    @test device_runtime.ownership == cpu_runtime.ownership
    for quantity in (Val(:cell_volume), surface_key)
        @test CorePotts.program_tracker_values(device_runtime, quantity) ==
              CorePotts.program_tracker_values(cpu_runtime, quantity)
    end
    @test CorePotts.validate_tracker_state!(
        program.tracker_plan,
        device_runtime.trackers,
        device_runtime.ownership,
        device_runtime.cell_kinds,
        program,
    ) === device_runtime.trackers
    @test (
        device_runtime.accepted,
        device_runtime.rejected,
        device_runtime.null_attempts,
        device_runtime.constraint_rejections,
        device_runtime.energy_rejections,
    ) == (
        cpu_runtime.accepted,
        cpu_runtime.rejected,
        cpu_runtime.null_attempts,
        cpu_runtime.constraint_rejections,
        cpu_runtime.energy_rejections,
    )
    surface_values = CorePotts.tracker_values(
        program.tracker_plan,
        device_workspace.state.trackers,
        surface_key,
    )
    @test CorePotts.KernelAbstractions.get_backend(surface_values) ==
          CorePotts.KernelAbstractions.get_backend(
              device_workspace.state.ownership
          )
    @test program.checkerboard_plan.color_count > 1

    return (
        backend = backend_name,
        colors = Int(program.checkerboard_plan.color_count),
        accepted = cpu_runtime.accepted,
        surface = Tuple(CorePotts.program_tracker_values(
            cpu_runtime, surface_key
        )),
    )
end
