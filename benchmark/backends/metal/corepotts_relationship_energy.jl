using Test
import Metal
import LocalMath
using Potts
using ModelingToolkitBase: @variables

function _relationship_energy_problem()
    @variables relationship_energy_signal
    cell = CellKind(:relationship_energy_cell; extinction = RetireAtZero())
    medium = MediumKind(:relationship_energy_medium)
    signal = FieldState(
        relationship_energy_signal;
        name = :relationship_energy_signal,
        initial = 1.0f0,
    )
    site = SiteBinding(:relationship_energy_site)
    neighbor_sum = LocalMath.bounded_fold(
        identity,
        +,
        0.0f0,
        (sum, count) -> sum;
        domain = LocalMath.Where(isfinite),
        oninvalid = LocalMath.RejectInvalid(),
        onempty = LocalMath.FillEmpty(0.0f0),
        order = LocalMath.CanonicalLeftFold(),
    )
    links = RelationshipState(
        :relationship_energy_links;
        endpoints = Undirected(cell, cell),
        payload = (strength = 1.5f0, target = 2.0f0, maximum = 8.0f0),
        capacity = 1,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(:relationship_energy_edge, links)
    system = PottsSystem(
        name = :relationship_energy_metal,
        statements = StatementSet((
            Lattice(
                (3, 1);
                boundary = Closed(),
                relations = (
                    contact = VonNeumann(),
                    proposal = VonNeumann(),
                ),
            ),
            cell,
            medium,
            signal,
            links,
            HamiltonianTerm(
                :relationship_energy_bounded_signal;
                domain = sites(:lattice),
                anchor = site,
                expression = neighbor_sum(bounded_values(
                    signal, :contact, anchor_value(site))),
            ),
            RelationshipEnergy(
                :relationship_energy,
                edge,
                edge.strength * (
                    distance(
                        unwrapped_center(edge.a),
                        unwrapped_center(edge.b),
                    ) - edge.target
                )^2,
            ),
            ProposalConstraint(:relationship_energy_freeze, false),
            Protocol(Sweep(; temperature = 0.0f0); name = :main),
        )),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(
            reshape(Int32[1, 0, 2], 3, 1);
            cells = [cell, cell],
            medium,
        ),
        values = (
            signal => ones(Float32, 3, 1),
            links => [(1, 2)],
        ),
    )
    return PottsProblem(mtkcompile(system), initial, (0, 1); seed = 0x6c07)
end

@testset "CorePotts relationship energy uses LocalMath on Metal" begin
    Metal.allowscalar(false)
    problem = _relationship_energy_problem()
    cpu = solve(
        problem,
        CheckerboardSweepCPM();
        backend = Potts.CPUBackend(),
        scalar_type = Float32,
        save_everystep = true,
    )
    device = solve(
        problem,
        CheckerboardSweepCPM();
        backend = Potts.MetalBackend(),
        scalar_type = Float32,
        save_everystep = true,
    )
    cpu_statistics = (
        accepted = cpu.stats.accepted,
        rejected = cpu.stats.rejected,
        null_attempts = cpu.stats.null_attempts,
        constraint_rejections = cpu.stats.constraint_rejections,
        energy_rejections = cpu.stats.energy_rejections,
        retired_cells = cpu.stats.retired_cells,
    )
    device_statistics = (
        accepted = device.stats.accepted,
        rejected = device.stats.rejected,
        null_attempts = device.stats.null_attempts,
        constraint_rejections = device.stats.constraint_rejections,
        energy_rejections = device.stats.energy_rejections,
        retired_cells = device.stats.retired_cells,
    )
    @test device_statistics == cpu_statistics
    @test Array(last(device).ownership) == last(cpu).ownership
    device_relationship = last(device)[:relationship_energy_links]
    cpu_relationship = last(cpu)[:relationship_energy_links]
    @test Array(device_relationship.active) == cpu_relationship.active
    @test map(Array, device_relationship.payload) == cpu_relationship.payload
end
