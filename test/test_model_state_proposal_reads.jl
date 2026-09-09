@testset "model Boolean state controls actionable proposals" begin
    @variables allowed::Bool
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    system = PottsSystem(
        name = :global_predicate,
        statements = StatementSet(
            (
                Lattice((6, 6); boundary = Closed()), cell, medium,
                ModelState(allowed; initial = false),
                ProposalConstraint(:model_permission, allowed),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (allowed,),
    )
    labels = zeros(Int, 6, 6)
    labels[3:4, 3:4] .= 1
    initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell], medium))
    problem = PottsProblem(system, initial, (0, 3); seed = 17)
    @testset "$(typeof(algorithm))" for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        solution = solve(problem, algorithm; scalar_type = Float32)
        @test solution.retcode == SciMLBase.ReturnCode.Success
        @test last(solution).ownership == labels
        @test last(solution)[:allowed] === false
        @test solution.stats.constraint_rejections > 0
        @test solution.stats.accepted == 0
    end
end

@testset "site updates read model-wide and site-owned values" begin
    @variables increment amount
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    system = PottsSystem(
        name = :global_increment,
        statements = StatementSet(
            (
                Lattice((3, 3); boundary = Closed()), cell, medium,
                ModelState(increment; initial = 2.0),
                SiteState(amount; initial = 1.0),
                Synchronous(:accumulate, Assign(amount, amount + increment)),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (increment, amount),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 3, 3); cells = [cell], medium),
    )
    @testset "$(typeof(algorithm))" for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        solution = solve(
            PottsProblem(system, initial, (0, 3); seed = 17), algorithm;
            scalar_type = Float32
        )
        @test solution.retcode == SciMLBase.ReturnCode.Success
        @test last(solution)[:amount] == fill(7.0f0, 3, 3)
        @test last(solution)[:increment] == 2.0f0
    end
end
