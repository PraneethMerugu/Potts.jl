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
