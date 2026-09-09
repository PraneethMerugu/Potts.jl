module ExternalHistoryName
    import Potts
    import Symbolics
    function lag end
    Symbolics.@register_symbolic lag(history, amount)::Real
    Potts.operation_transfer(::typeof(lag), ::Int) = Potts.OperationTransfer(
        :lag;
        arity = 2, result_rule = :real, unit_rule = :dimensionless,
        footprint_rule = Potts.InheritFootprintRule(), owner = :ExternalHistoryName
    )
end

@testset "retained samples feed model, site, and cell processes at declared cadence" begin
    @variables signal feedback memory
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    for constructor in (ModelState, SiteState, CellState)
        process = constructor === CellState ?
            Synchronous(:respond, Assign(signal, signal + 1), Assign(feedback, lag(memory, 0) + 10lag(memory, 1)); domain = cells(cell)) :
            Synchronous(:respond, Assign(signal, signal + 1), Assign(feedback, lag(memory, 0) + 10lag(memory, 1)))
        source = PottsSystem(
            name = :retained_feedback, statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                    constructor(signal; initial = 1.0), constructor(feedback; initial = 0.0),
                    HistoryState(memory; of = signal, depth = 3, initial = 0.0, cadence = Every(2)),
                    process, ProposalConstraint(:fixed_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ), unknowns = (signal, feedback, memory)
        )
        initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
        problem = PottsProblem(source, initial, (0, 5); seed = 17)
        snapshot(value) = constructor === ModelState ? value : fill(value, constructor === CellState ? (1,) : (2, 2))
        for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
            integrator = init(problem, algorithm; scalar_type = Float32)
            @test integrator.u[:memory] == ntuple(_ -> snapshot(0.0f0), 3)
            for expected in (0.0f0, 0.0f0, 3.0f0)
                step!(integrator)
                @test integrator.u[:feedback] == snapshot(expected)
            end
            @test integrator.u[:memory] == (snapshot(0.0f0), snapshot(0.0f0), snapshot(3.0f0))
            restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
            for current in (integrator, restored)
                step!(current)
                @test current.u[:feedback] == snapshot(3.0f0)
                @test current.u[:memory] == (snapshot(0.0f0), snapshot(3.0f0), snapshot(5.0f0))
                step!(current)
                @test current.u[:feedback] == snapshot(35.0f0)
                @test failure_report(current) === nothing
            end
        end
    end
end

@testset "an external operation named lag does not acquire history projection admission" begin
    @variables signal memory
    source = PottsSystem(
        name = :external_history_name, statements = StatementSet(
            (
                ModelState(signal; initial = 1.0), HistoryState(memory; of = signal, depth = 3),
                Synchronous(:respond, Assign(signal, ExternalHistoryName.lag(memory, 0))),
            )
        ), unknowns = (signal, memory)
    )
    @test_throws r"frozen callable.*no implementation" mtkcompile(complete(source))
end

@testset "history feedback rejects invalid sample indices at the source" begin
    @variables signal memory
    for amount in (true, -1, 3)
        source = PottsSystem(
            name = :invalid_sample, statements = StatementSet(
                (
                    ModelState(signal; initial = 1.0),
                    HistoryState(memory; of = signal, depth = 3),
                    Synchronous(:respond, Assign(signal, lag(memory, amount))),
                )
            ), unknowns = (signal, memory)
        )
        @test_throws r"invalid_history_lag" mtkcompile(complete(source))
    end
end
