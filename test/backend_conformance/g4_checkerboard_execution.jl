using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics

import CorePotts

isdefined(@__MODULE__, :NeutralExternalTerms) ||
    include("../fixtures/NeutralExternalTerms.jl")

function _g4_external_checkerboard_fixture()
    @variables checkerboard_activity
    @parameters checkerboard_weight = 0.25
    cell = CellKind(:checkerboard_cell)
    medium = MediumKind(:checkerboard_medium)
    anchor = SiteBinding(:checkerboard_energy_site)
    activity = SiteState(
        checkerboard_activity;
        name = :checkerboard_activity,
        initial = 1.0,
        owner = cell,
        lifecycle = PreserveOnOwnershipChange(),
    )
    term = NeutralExternalTerms.ExternalWeightedSiteTerm(
        :external_tracker_checkerboard_energy,
        checkerboard_weight,
        checkerboard_activity,
        cell,
        anchor,
    )
    @named model = PottsSystem(
        statements = StatementSet((
            Lattice(
                (6, 6);
                boundary = Periodic(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            activity,
            term,
            Protocol(Sweep(; temperature = 2.0); name = :main),
        )),
        unknowns = [checkerboard_activity],
        parameters = [checkerboard_weight],
    )
    executable = compile(
        complete(model; registry = NeutralExternalTerms.registry());
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    labels = zeros(Int, 6, 6)
    labels[2:5, 2:5] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = [checkerboard_activity => reshape(
            collect(Float32, 1:36), 6, 6
        )],
    )
    return executable, PottsToolkit._core_initial_state(executable, initial)
end

"""
    run_g4_checkerboard_execution(
        device_array; backend_name, kernel_convert, to_host=Array
    )

Execute the same external-descriptor checkerboard MCS through the CPU and a
backend adaptor. Vendor runners provide only storage adaptation; all semantic
inputs and exact assertions remain shared.
"""
function run_g4_checkerboard_execution(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_device_isbits::Bool = true,
    )
    executable, initial = _g4_external_checkerboard_fixture()
    program = executable.core_program
    parameters = program.parameter_defaults
    # This fixed address exercises both a successful commit and rejection.
    seed = UInt64(1)
    replica = UInt32(3)

    cpu_runtime = CorePotts.initialize_program(
        program, initial, parameters, seed, replica
    )
    device_runtime = CorePotts.initialize_program(
        program, initial, parameters, seed, replica
    )
    cpu_workspace = cpu_runtime.engine_workspace
    device_workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, device_runtime.engine_workspace
    )
    if require_device_isbits
        @test isbitstype(typeof(kernel_convert(device_workspace.state)))
    end

    CorePotts.execute_checkerboard_mcs!(cpu_workspace, 0)
    CorePotts.execute_checkerboard_mcs!(device_workspace, 0)
    CorePotts.copy_checkerboard_state!(cpu_runtime, cpu_workspace, identity)
    CorePotts.copy_checkerboard_state!(
        device_runtime, device_workspace, to_host
    )

    @test device_runtime.ownership == cpu_runtime.ownership
    @test CorePotts.program_tracker_values(
        device_runtime, Val(:cell_volume)
    ) == CorePotts.program_tracker_values(
        cpu_runtime, Val(:cell_volume)
    )
    @test CorePotts.program_tracker_values(
        device_runtime, Val(:external_double_occupancy)
    ) == CorePotts.program_tracker_values(
        cpu_runtime, Val(:external_double_occupancy)
    )
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
    attempts = length(cpu_runtime.ownership) * Int(program.attempts_per_site)
    @test cpu_runtime.accepted + cpu_runtime.rejected +
          cpu_runtime.null_attempts == attempts
    @test sum(CorePotts.program_tracker_values(
        cpu_runtime, Val(:cell_volume)
    )) == count(>(0), cpu_runtime.ownership)
    @test CorePotts.program_tracker_values(
        cpu_runtime, Val(:external_double_occupancy)
    ) == 2 .* CorePotts.program_tracker_values(
        cpu_runtime, Val(:cell_volume)
    )
    @test isconcretetype(typeof(device_workspace))
    @test CorePotts.KernelAbstractions.get_backend(
        device_workspace.state.ownership
    ) == CorePotts.KernelAbstractions.get_backend(
        device_workspace.dispositions
    )

    return (
        backend = backend_name,
        colors = Int(program.checkerboard_plan.color_count),
        attempts,
        accepted = cpu_runtime.accepted,
        rejected = cpu_runtime.rejected,
        null_attempts = cpu_runtime.null_attempts,
        ownership_checksum = sum(
            index * Int(owner)
            for (index, owner) in enumerate(cpu_runtime.ownership)
        ),
    )
end

function _g4_boundary_program(shape::NTuple{2, Int})
    offsets = Int8[1 -1 0 0; 0 0 1 -1]
    descriptor_plan = CorePotts.DescriptorExecutionPlan(
        (),
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "g4-boundary-descriptor-plan",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (CorePotts.OwnershipCountTracker(),),
        "g4-boundary-tracker-plan",
    )
    checkerboard_plan = CorePotts.CheckerboardPlan(
        shape, (true, true), offsets
    )
    return CorePotts.CompiledPottsProgram(
        shape,
        (true, true),
        offsets,
        2,
        1,
        CorePotts.CompiledScalar(2.0f0),
        2,
        Float32[],
        (),
        tracker_plan,
        descriptor_plan,
        CorePotts.StageExecutionPlan(),
        CorePotts.CheckerboardProgramEngine(),
        CorePotts.CPUProgramBackend(),
        "g4-boundary-program-$(shape)";
        medium_kinds = Bool[true, false],
        checkerboard_plan,
    )
end

function _g4_boundary_initial(shape::NTuple{2, Int})
    ownership = zeros(Int32, shape)
    if prod(shape) == 1
        ownership[1] = Int32(1)
    else
        first_site = max(1, fld(shape[1], 4))
        last_site = min(shape[1], max(first_site, fld(3 * shape[1], 4)))
        ownership[first_site:last_site, 1] .= Int32(1)
    end
    return CorePotts.ProgramInitialState(
        ownership, Int16[2]; scalar_type = Float32
    )
end

function _run_g4_boundary_shape(
        shape,
        device_array;
        kernel_convert,
        to_host,
        require_device_isbits,
    )
    program = _g4_boundary_program(shape)
    initial = _g4_boundary_initial(shape)
    cpu_runtime = CorePotts.initialize_program(
        program, initial, Float32[], UInt64(0xb04d), UInt32(1)
    )
    device_runtime = CorePotts.initialize_program(
        program, initial, Float32[], UInt64(0xb04d), UInt32(1)
    )
    cpu_workspace = cpu_runtime.engine_workspace
    device_workspace = CorePotts.adapt_checkerboard_workspace(
        device_array, device_runtime.engine_workspace
    )
    if require_device_isbits
        @test isbitstype(typeof(kernel_convert(device_workspace.state)))
    end
    CorePotts.execute_checkerboard_mcs!(cpu_workspace, 0)
    CorePotts.execute_checkerboard_mcs!(device_workspace, 0)
    CorePotts.copy_checkerboard_state!(cpu_runtime, cpu_workspace, identity)
    CorePotts.copy_checkerboard_state!(
        device_runtime, device_workspace, to_host
    )
    @test device_runtime.ownership == cpu_runtime.ownership
    @test CorePotts.program_tracker_values(
        device_runtime, Val(:cell_volume)
    ) == CorePotts.program_tracker_values(
        cpu_runtime, Val(:cell_volume)
    )
    cpu_report = (
        cpu_runtime.accepted,
        cpu_runtime.rejected,
        cpu_runtime.null_attempts,
        cpu_runtime.constraint_rejections,
        cpu_runtime.energy_rejections,
    )
    device_report = (
        device_runtime.accepted,
        device_runtime.rejected,
        device_runtime.null_attempts,
        device_runtime.constraint_rejections,
        device_runtime.energy_rejections,
    )
    @test device_report == cpu_report
    @test sum(cpu_report[1:3]) == 2 * prod(shape)
    return cpu_report
end

"""Shared CPU/vendor workgroup-edge and realized-boundary conformance."""
function run_g4_checkerboard_boundary_sizes(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_device_isbits::Bool = true,
    )
    shapes = ((1, 1), (255, 1), (256, 1), (257, 1), (17, 19))
    reports = map(shapes) do shape
        _run_g4_boundary_shape(
            shape,
            device_array;
            kernel_convert,
            to_host,
            require_device_isbits,
        )
    end
    @test any(report -> report[1] > 0, reports)
    @test any(report -> report[2] > 0, reports)
    @test any(report -> report[3] > 0, reports)
    return (; backend = backend_name, shapes, reports)
end
