using StaticArrays

@testset "cell processes update each eligible finite identity once" begin
    @variables amount direction[1:2]
    selected = CellKind(:selected; extinction = RetireAtZero())
    other = CellKind(:other; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :cell_exchange,
        statements = StatementSet(
            (
                Lattice((4, 3); boundary = Closed(), max_cells = 4), selected, other, medium,
                CellState(amount; initial = 9.0, retirement = RetireTo(0.0)),
                CellState(direction; initial = SVector(8.0, 7.0), retirement = RetireTo(SVector(0.0, 0.0))),
                ProposalConstraint(:fixed_ownership, false),
                Synchronous(
                    :exchange, Assign(amount, direction[1]),
                    Assign(direction, SVector(amount, 0.0)); domain = cells(selected)
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (amount, direction),
    )
    labels = [1 0 0; 2 2 0; 2 0 0; 3 0 0]
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [selected, selected, other], medium),
        values = (
            amount => [2.0, 3.0, 4.0],
            direction => [SVector(5.0, 1.0), SVector(6.0, 1.0), SVector(7.0, 1.0)],
        ),
    )
    problem = PottsProblem(source, initial, (0, 2); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        step!(integrator)
        @test Array(integrator.u[:amount]) == Float32[5, 6, 4, 9]
        @test Array(integrator.u[:direction]) == [
            SVector(2.0f0, 0.0f0), SVector(3.0f0, 0.0f0),
            SVector(7.0f0, 1.0f0), SVector(8.0f0, 7.0f0),
        ]
        step!(integrator)
        @test Array(integrator.u[:amount]) == Float32[2, 3, 4, 9]
        @test Array(integrator.u[:direction]) == [
            SVector(5.0f0, 0.0f0), SVector(6.0f0, 0.0f0),
            SVector(7.0f0, 1.0f0), SVector(8.0f0, 7.0f0),
        ]
        @test failure_report(integrator) === nothing
    end
end

@testset "cell processes require an explicit finite-kind domain" begin
    @variables amount
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    function declaration(domain, state = CellState(amount; initial = 1.0, retirement = RetireTo(0.0)))
        PottsSystem(
            name = :cell_domain, statements = StatementSet(
                (
                    Lattice((2, 2)), cell, medium, state,
                    Synchronous(:increment, Assign(amount, amount + 1); domain),
                    Protocol(Sweep(); name = :main),
                )
            ), unknowns = (amount,)
        )
    end
    @test_throws r"explicit cells\(kind\)" mtkcompile(declaration(nothing))
    @test_throws r"declared CellKind" mtkcompile(declaration(cells(medium)))
    @test_throws Potts.PottsValidationError mtkcompile(declaration(cells(CellKind(:absent))))
    @test_throws r"CellState targets" mtkcompile(declaration(cells(cell), ModelState(amount; initial = 1.0)))
end

@testset "cell processes reject mixed writes and unbound state domains" begin
    @variables amount foreign_value
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    for foreign_state in (ModelState, SiteState)
        function declaration(effects)
            PottsSystem(
                name = :mixed_cell_domain, statements = StatementSet(
                    (
                        Lattice((2, 2); boundary = Closed()), cell, medium,
                        CellState(amount; initial = 1.0, retirement = RetireTo(0.0)), foreign_state(foreign_value; initial = 2.0),
                        Synchronous(:update, effects...; domain = cells(cell)),
                        Protocol(Sweep(); name = :main),
                    )
                ), unknowns = (amount, foreign_value)
            )
        end
        mixed = declaration((Assign(amount, amount + 1), Assign(foreign_value, 3.0)))
        @test_throws r"share one iteration domain" mtkcompile(mixed)
        invalid_read = declaration((Assign(amount, foreign_value),))
        initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
        @test_throws r"CellState reads" init(PottsProblem(invalid_read, initial, (0, 1); seed = 17))
    end
end

@testset "cell process kinds retain component qualification" begin
    @variables amount
    function component(name, increment)
        cell = CellKind(:cell; extinction = RetireAtZero())
        PottsSystem(
            name = name, statements = StatementSet(
                (
                    cell, CellState(amount; initial = 1.0, retirement = RetireTo(0.0)),
                    Synchronous(:advance, Assign(amount, amount + increment); domain = cells(cell)),
                )
            ), unknowns = (amount,)
        )
    end
    medium = MediumKind(:medium)
    system = PottsSystem(
        name = :tissue, statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 2), medium,
                ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), systems = (component(:first, 10.0), component(:second, 20.0))
    )
    initial = PottsInitialState(
        ownership = LabelledCells(
            [1 0; 2 0];
            cells = [:first₊cell, :second₊cell], medium
        )
    )
    problem = PottsProblem(system, initial, (0, 1); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        result = solve(problem, algorithm; scalar_type = Float32)
        @test result.retcode == SciMLBase.ReturnCode.Success
        @test Array(result.u[end][:first₊amount]) == Float32[11, 1]
        @test Array(result.u[end][:second₊amount]) == Float32[1, 21]
    end
end
