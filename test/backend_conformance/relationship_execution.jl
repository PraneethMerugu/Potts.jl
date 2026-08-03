using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics

import CorePotts

isdefined(@__MODULE__, :NeutralExternalTerms) ||
    include("../fixtures/NeutralExternalTerms.jl")

function _external_relationship_fixture()
    @parameters relationship_weight = 1.25
    cell = CellKind(:relationship_cell; extinction = RetireAtZero())
    medium = MediumKind(:relationship_medium)
    relationships = RelationshipState(
        :external_relationships;
        endpoints = Undirected(cell, cell),
        payload = (
            score = relationship_weight,
            cutoff = zero(relationship_weight),
            marker = relationship_weight,
        ),
        capacity = 8,
        maximum_degree = 2,
        lifecycle = RejectEndpointRetirement(),
    )
    edge = RelationshipBinding(:external_relationship, relationships)
    term = NeutralExternalTerms.ExternalBoundedPairTerm(
        :external_relationship_energy,
        relationship_weight,
        relationships,
        edge,
    )
    @named model = PottsSystem(
        statements = StatementSet((
            Lattice(
                (5, 5);
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            relationships,
            term,
            Protocol(Sweep(; temperature = 1.5); name = :main),
        )),
        parameters = [relationship_weight],
    )
    executable = compile(
        complete(model; registry = NeutralExternalTerms.registry());
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    labels = zeros(Int, 5, 5)
    labels[2, 2] = 1
    labels[2, 3:4] .= 2
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell, cell], medium),
        values = [relationships => [(
            1,
            2,
            (score = 1.25f0, cutoff = 0.0f0, marker = 1.25f0),
        )]],
    )
    return executable, PottsToolkit._core_initial_state(executable, initial)
end

"""
    run_relationship_execution(
        device_array; backend_name, kernel_convert, to_host=Array
    )

Run an external incident-relationship Hamiltonian through the same checkerboard
program on CPU and one vendor adaptor. Relationship mutation remains a staged
host-qualified family; this witness qualifies immutable incident-local reads.
"""
function run_relationship_execution(
        device_array;
        backend_name::Symbol,
        kernel_convert,
        to_host = Array,
        require_device_isbits::Bool = true,
    )
    executable, initial = _external_relationship_fixture()
    program = executable.core_program
    parameters = program.parameter_defaults
    seed = UInt64(5)
    replica = UInt32(4)

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
    relationship_bank = only(device_workspace.state.relationships.banks)
    @test relationship_bank isa CorePotts.PackedRelationshipBank
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
    @test count(only(cpu_runtime.relationships).active) == 1
    @test sum(CorePotts.program_tracker_values(
        cpu_runtime, Val(:cell_volume)
    )) == count(>(0), cpu_runtime.ownership)

    return (
        backend = backend_name,
        relationship_stores = length(program.relationships),
        attempts = length(cpu_runtime.ownership) *
                   Int(program.attempts_per_site),
        accepted = cpu_runtime.accepted,
        rejected = cpu_runtime.rejected,
        null_attempts = cpu_runtime.null_attempts,
        ownership_checksum = sum(
            index * Int(owner)
            for (index, owner) in enumerate(cpu_runtime.ownership)
        ),
    )
end
