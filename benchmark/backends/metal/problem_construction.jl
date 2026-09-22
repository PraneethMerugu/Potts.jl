using Test
import Metal
using Potts

function _problem_construction_inputs()
    cell = CellKind(:construction_cell; extinction = RetireAtZero())
    medium = MediumKind(:construction_medium)
    system = PottsSystem(
        name = :problem_construction,
        statements = StatementSet((
            Lattice(
                (4, 4);
                boundary = Periodic(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            Volume(cell; target = 4.0f0, strength = 1.0f0),
            ProposalConstraint(:fixed_problem_construction, false),
            Protocol(Sweep(; temperature = 1.0f0); name = :main),
        )),
    )
    labels = zeros(Int32, 4, 4)
    labels[2:3, 2:3] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
    )
    return system, initial
end

@testset "multiple medium ownership survives Metal checkerboard checkpoints" begin
    Metal.allowscalar(false)
    cell = CellKind(:metal_multiple_medium_cell; extinction = RetireAtZero())
    bulk = MediumKind(:metal_multiple_medium_bulk)
    border = MediumKind(:metal_multiple_medium_border)
    border_coordinates = Tuple(
        (row, column) for row in (1, 6) for column in 1:6
    )
    initial = PottsInitialState(ownership = OwnershipLayout(
        (6, 6),
        MediumPlacement(border, border_coordinates),
        CellPlacement(
            1,
            cell,
            ((3, 3), (3, 4), (4, 3), (4, 4)),
        );
        medium = bulk,
    ))

    for (name, boundary) in ((:closed, Closed()), (:periodic, Periodic()))
        scheduled = mtkcompile(PottsSystem(
            name = Symbol(:metal_multiple_medium_, name),
            statements = StatementSet((
                Lattice((6, 6); boundary = boundary),
                cell,
                bulk,
                border,
                Volume(cell; target = 4.0f0, strength = 1.0f0),
                ProposalConstraint(:fixed_multiple_medium, false),
                Protocol(Sweep(; temperature = 2.0f0); name = :main),
                Observation(:bulk_sites, occupancy(bulk, :lattice)),
                Observation(:border_sites, occupancy(border, :lattice)),
            )),
        ))
        problem = PottsProblem(scheduled, initial, (0, 1); seed = 0x6c09)
        cpu = init(
            problem,
            CheckerboardSweepCPM();
            backend = CPUBackend(),
            scalar_type = Float32,
            observables = (:bulk_sites, :border_sites),
        )
        device = init(
            problem,
            CheckerboardSweepCPM();
            backend = Potts.MetalBackend(),
            scalar_type = Float32,
            observables = (:bulk_sites, :border_sites),
        )
        @test Array(device.u.ownership) == cpu.u.ownership
        @test device.u[:bulk_sites] == cpu.u[:bulk_sites] == 20
        @test device.u[:border_sites] == cpu.u[:border_sites] == 12
        @test any(<(0), Array(device.u.ownership))

        step!(cpu)
        step!(device)
        @test Array(device.u.ownership) == cpu.u.ownership
        @test device.u[:bulk_sites] == cpu.u[:bulk_sites] == 20
        @test device.u[:border_sites] == cpu.u[:border_sites] == 12
        @test device.stats.candidate_attempts == cpu.stats.candidate_attempts
        @test device.stats.accepted == cpu.stats.accepted == 0
        @test device.stats.rejected == cpu.stats.rejected
        @test device.stats.null_attempts == cpu.stats.null_attempts
        @test device.stats.constraint_rejections ==
            cpu.stats.constraint_rejections

        restored = init(
            problem,
            CheckerboardSweepCPM();
            backend = Potts.MetalBackend(),
            scalar_type = Float32,
            observables = (:bulk_sites, :border_sites),
            checkpoint = checkpoint(device),
        )
        @test Array(restored.u.ownership) == Array(device.u.ownership)
        @test restored.u[:bulk_sites] == 20
        @test restored.u[:border_sites] == 12
    end
end

@testset "PottsProblem structural compilation precedes Metal execution" begin
    Metal.allowscalar(false)
    system, initial = _problem_construction_inputs()
    construction_visits = Ref(0)
    implicit = Potts._with_source_traversal_witness(
        (_, _, _) -> (construction_visits[] += 1),
    ) do
        PottsProblem(system, initial, (0, 1); seed = 0x6c08)
    end
    @test construction_visits[] > 0

    scheduled = mtkcompile(system)
    explicit = PottsProblem(scheduled, initial, (0, 1); seed = 0x6c08)
    @test explicit.system === scheduled
    @test inspect(implicit.system, Fingerprints()) ==
          inspect(explicit.system, Fingerprints())

    execution_visits = Ref(0)
    implicit_solution = Potts._with_source_traversal_witness(
        (_, _, _) -> (execution_visits[] += 1),
    ) do
        solve(
            implicit,
            CheckerboardSweepCPM();
            backend = Potts.MetalBackend(),
            scalar_type = Float32,
            save_everystep = true,
        )
    end
    explicit_solution = solve(
        explicit,
        CheckerboardSweepCPM();
        backend = Potts.MetalBackend(),
        scalar_type = Float32,
        save_everystep = true,
    )
    @test iszero(execution_visits[])
    @test implicit_solution.retcode == explicit_solution.retcode
    @test implicit_solution.t == explicit_solution.t
    @test map(state -> Array(state.ownership), implicit_solution.u) ==
          map(state -> Array(state.ownership), explicit_solution.u)
    @test Array(last(implicit_solution).cell_kinds) ==
          Array(last(explicit_solution).cell_kinds)
    @test Array(last(implicit_solution).cell_generations) ==
          Array(last(explicit_solution).cell_generations)
    @test Array(last(implicit_solution).volumes) ==
          Array(last(explicit_solution).volumes)
    @test implicit_solution.stats.candidate_attempts ==
          explicit_solution.stats.candidate_attempts
    @test implicit_solution.stats.accepted == explicit_solution.stats.accepted
    @test implicit_solution.stats.rejected == explicit_solution.stats.rejected
end
