using Test
import Metal
using Potts

function _cartesian_domain_problem()
    cell = CellKind(:cartesian_domain_cell; extinction = RetireAtZero())
    medium = MediumKind(:cartesian_domain_medium)
    wall_kind = MediumKind(:cartesian_domain_wall_kind)
    bulk = MediumDomainOwner(:cartesian_domain_bulk, medium)
    wall = WallDomainOwner(:cartesian_domain_wall, wall_kind)
    obstacle_mask = falses(4, 4)
    obstacle_mask[2, 2] = true
    system = PottsSystem(
        name = :cartesian_domain_metal,
        statements = StatementSet(
            (
                Lattice(
                    (4, 4);
                    boundary = (
                        AxisBoundary(
                            negative = FixedExterior(bulk),
                            positive = FixedExterior(wall),
                        ),
                        AxisBoundary(Periodic()),
                    ),
                    default_owner = bulk,
                    domain_owners = (wall,),
                    obstacles = Obstacle(obstacle_mask; owner = wall),
                    relations = (
                        proposal = VonNeumann(),
                        contact = VonNeumann(),
                    ),
                ),
                cell,
                medium,
                wall_kind,
                ContactEnergy(
                    [
                        (cell ↔ medium) => 1.0f0,
                        (cell ↔ wall_kind) => 5.0f0,
                        (cell ↔ cell) => 0.0f0,
                    ];
                    relation = :contact,
                ),
                Protocol(Sweep(; temperature = 0.0f0); name = :main),
            )
        ),
    )
    labels = zeros(Int32, 4, 4)
    # These sites force contact reads at the obstacle and both fixed faces.
    labels[1, 3] = 1
    labels[2, 3] = 1
    labels[4, 3] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
    )
    return PottsProblem(mtkcompile(system), initial, (0, 4); seed = 0x0c11)
end

@testset "typed Cartesian domains execute through one CPU/Metal path" begin
    Metal.allowscalar(false)
    problem = _cartesian_domain_problem()
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
    @test device.retcode == cpu.retcode
    @test length(device) == length(cpu) == 5
    for index in eachindex(cpu.u)
        device_ownership = Array(device.u[index].ownership)
        @test device_ownership == cpu.u[index].ownership
        # Saved ownership exposes the immutable wall owner; the mutable-site
        # population excludes this obstacle.
        @test device_ownership[2, 2] == -1
    end
    @test device.stats.candidate_attempts == cpu.stats.candidate_attempts == 60
    @test device.stats.accepted == cpu.stats.accepted
    @test device.stats.rejected == cpu.stats.rejected
end
