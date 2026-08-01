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
        :checkerboard_external_energy,
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
    run_g4_checkerboard_execution(device_array; backend_name, to_host=Array)

Execute the same external-descriptor checkerboard MCS through the CPU and a
backend adaptor. Vendor runners provide only storage adaptation; all semantic
inputs and exact assertions remain shared.
"""
function run_g4_checkerboard_execution(
        device_array;
        backend_name::Symbol,
        to_host = Array,
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

    CorePotts.execute_checkerboard_mcs!(cpu_workspace, 0)
    CorePotts.execute_checkerboard_mcs!(device_workspace, 0)
    CorePotts.copy_checkerboard_state!(cpu_runtime, cpu_workspace, identity)
    CorePotts.copy_checkerboard_state!(
        device_runtime, device_workspace, to_host
    )

    @test device_runtime.ownership == cpu_runtime.ownership
    @test device_runtime.volumes == cpu_runtime.volumes
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
    @test sum(cpu_runtime.volumes) == count(>(0), cpu_runtime.ownership)
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
