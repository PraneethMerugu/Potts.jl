using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics

import CorePotts

function _observe_checkerboard_boundary!(runtime, workspace, to_host)
    copyto!(runtime.ownership, to_host(workspace.state.ownership))
    CorePotts.copyto_tracker_state!(
        runtime.trackers, workspace.state.trackers, to_host
    )
    report = to_host(workspace.report)
    runtime.accepted += Int(report[1])
    runtime.rejected += Int(report[2])
    runtime.null_attempts += Int(report[3])
    runtime.constraint_rejections += Int(report[4])
    runtime.energy_rejections += Int(report[5])
    return runtime
end

isdefined(@__MODULE__, :NeutralExternalTerms) ||
    include("../fixtures/NeutralExternalTerms.jl")

function _external_checkerboard_fixture()
    @variables checkerboard_activity
    @parameters checkerboard_weight = 0.25
    cell = CellKind(:checkerboard_cell; extinction = RetireAtZero())
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
    run_checkerboard_execution(
        device_array; backend_name, kernel_convert, to_host=Array
    )

Execute the same external-descriptor checkerboard MCS through the CPU and a
backend adaptor. Vendor runners provide only storage adaptation; all semantic
inputs and exact assertions remain shared.
"""
function run_checkerboard_execution(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_device_isbits::Bool = true,
    )
    executable, initial = _external_checkerboard_fixture()
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
    _observe_checkerboard_boundary!(cpu_runtime, cpu_workspace, identity)
    _observe_checkerboard_boundary!(
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

function _boundary_descriptor_plan(branch::Symbol)
    branch === :neutral && return CorePotts.DescriptorExecutionPlan(
        (),
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[],
        0,
        "boundary-descriptor-plan",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
    evaluator, role = if branch === :constraint
        (
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(false)),
            CorePotts.ProposalConstraintRole(),
        )
    elseif branch === :energy
        (
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(1.0f6)),
            CorePotts.ProposalEnergyDriveRole(),
        )
    else
        throw(ArgumentError("unknown checkerboard boundary branch `$branch`"))
    end
    access = CorePotts.ResourceAccess(
        (),
        (),
        CorePotts.EmptyFootprint(),
        CorePotts.EmptyFootprint(),
        CorePotts.NoWriteAccess(),
    )
    descriptor = CorePotts.ProposalDescriptor(
        evaluator,
        access,
        CorePotts.DescriptorSupport(true, true, true, true),
        (),
        (),
        role,
        1,
    )
    return CorePotts.DescriptorExecutionPlan(
        PottsToolkit._descriptor_groups(Any[descriptor]),
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (),
        Any[(path = (:checkerboard_boundary,), local_id = branch)],
        1,
        "boundary-$branch-descriptor-plan",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
end

function _boundary_program(
        shape::NTuple{2, Int}; branch::Symbol = :neutral
    )
    offsets = Int8[1 -1 0 0; 0 0 1 -1]
    descriptor_plan = _boundary_descriptor_plan(branch)
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (CorePotts.OwnershipCountTracker(),),
        "boundary-tracker-plan",
    )
    checkerboard_plan = CorePotts.CheckerboardPlan(
        shape, (true, true), zeros(Int8, 2, 0)
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
        "boundary-program-$(shape)";
        medium_kinds = Bool[true, false],
        checkerboard_plan,
    )
end

function _boundary_initial(shape::NTuple{2, Int})
    ownership = zeros(Int32, shape)
    if prod(shape) == 1
        ownership[1] = Int32(1)
    else
        for first_dimension in axes(ownership, 1)
            isodd(first_dimension) &&
                (ownership[first_dimension, 1] = Int32(1))
        end
    end
    return CorePotts.ProgramInitialState(
        ownership, Int16[2]; scalar_type = Float32
    )
end

function _run_boundary_shape(
        shape,
        device_array;
        kernel_convert,
        to_host,
        require_device_isbits,
        workgroup_size,
        branch = :neutral,
    )
    program = _boundary_program(shape; branch)
    initial = _boundary_initial(shape)
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
    CorePotts.execute_checkerboard_mcs!(
        cpu_workspace, 0; workgroup_size
    )
    CorePotts.execute_checkerboard_mcs!(
        device_workspace, 0; workgroup_size
    )
    _observe_checkerboard_boundary!(cpu_runtime, cpu_workspace, identity)
    _observe_checkerboard_boundary!(
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
    @test program.checkerboard_plan.color_count == 1
    @test program.checkerboard_plan.maximum_color_size == prod(shape)
    return (; shape, workgroup_size, branch, cpu_report)
end

"""Shared CPU/vendor workgroup-edge and realized-boundary conformance."""
function run_checkerboard_boundary_sizes(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_device_isbits::Bool = true,
    )
    shapes = ((1, 1), (255, 1), (256, 1), (257, 1), (17, 19))
    workgroup_sizes = (32, 64, 128, 256)
    reports = map(Iterators.product(shapes, workgroup_sizes)) do entry
        shape, workgroup_size = entry
        _run_boundary_shape(
            shape,
            device_array;
            kernel_convert,
            to_host,
            require_device_isbits,
            workgroup_size,
        )
    end
    @test any(report -> report.cpu_report[1] > 0, reports)
    @test any(report -> report.cpu_report[2] > 0, reports)
    @test any(report -> report.cpu_report[3] > 0, reports)
    @test Set(report.workgroup_size for report in reports) ==
          Set(workgroup_sizes)
    constraint_report = _run_boundary_shape(
        (257, 1),
        device_array;
        kernel_convert,
        to_host,
        require_device_isbits,
        workgroup_size = 64,
        branch = :constraint,
    )
    energy_report = _run_boundary_shape(
        (257, 1),
        device_array;
        kernel_convert,
        to_host,
        require_device_isbits,
        workgroup_size = 64,
        branch = :energy,
    )
    @test constraint_report.cpu_report[4] > 0
    @test energy_report.cpu_report[5] > 0
    return (;
        backend = backend_name,
        shapes,
        workgroup_sizes,
        reports,
        constraint_report,
        energy_report,
    )
end
