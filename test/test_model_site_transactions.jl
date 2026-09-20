@testset "model and site updates share boundary-entry values after restoration" begin
    @variables increment amount
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :coupled_boundaries,
        statements = StatementSet(
            (
                Lattice((3, 3); boundary = Closed()), cell, medium,
                ModelState(increment; initial = 2.0),
                SiteState(amount; initial = 1.0),
                ProposalConstraint(:fixed_ownership, false),
                Synchronous(:model_update, Assign(increment, increment + 1)),
                Synchronous(:site_update, Assign(amount, amount + increment)),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (increment, amount),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 3, 3); cells = [cell], medium),
    )
    problem = PottsProblem(source, initial, (0, 3); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        step!(integrator)
        @test integrator.u[:amount] == fill(3.0f0, 3, 3)
        @test integrator.u[:increment] == 3.0f0
        restored = init(
            problem, algorithm; scalar_type = Float32,
            checkpoint = checkpoint(integrator)
        )
        for boundary in 2:3
            step!(integrator)
            step!(restored)
            # Model increments are 2,3,4 at boundary entry, not 3,4,5.
            expected = Float32(1 + sum(2:(boundary + 1)))
            @test restored.u[:amount] == integrator.u[:amount] == fill(expected, 3, 3)
            @test restored.u[:increment] == integrator.u[:increment] == Float32(boundary + 2)
            @test restored.t == integrator.t == boundary
        end
        @test failure_report(integrator) === nothing
        @test failure_report(restored) === nothing
    end
end
