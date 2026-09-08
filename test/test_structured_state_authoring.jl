using StaticArrays

@testset "fixed vector state retains its logical value through public execution" begin
    @variables position[1:2]
    initial_value = SVector(1.0f0, 2.0f0)
    for state_constructor in (ModelState, SiteState)
        system = PottsSystem(
            name = :vector_state,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()),
                    CellKind(:cell; extinction = RetireAtZero()),
                    MediumKind(:medium),
                    state_constructor(position; initial = initial_value),
                    ProposalConstraint(:fixed_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (position,),
        )
        initial = PottsInitialState(
            ownership = LabelledCells(
                ones(Int, 2, 2);
                cells = [CellKind(:cell; extinction = RetireAtZero())],
                medium = MediumKind(:medium)
            ),
        )
        for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
            problem = PottsProblem(system, initial, (0, 1); seed = 17)
            integrator = init(problem, algorithm; scalar_type = Float32)
            expected = state_constructor === ModelState ? initial_value : fill(initial_value, 2, 2)
            @test integrator.u[:position] == expected
            logical_type = state_constructor === ModelState ? typeof(integrator.u[:position]) : eltype(integrator.u[:position])
            @test logical_type === typeof(initial_value)
            restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
            @test restored.u[:position] == expected
            solution = solve!(integrator)
            @test solution.retcode == SciMLBase.ReturnCode.Success
            @test solution.u[end][:position] == expected
        end
    end
end
