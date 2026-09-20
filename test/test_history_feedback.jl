@testset "scheduled random state publishes history after boundary-entry feedback" begin
    @variables signal memory initial_memory feedback
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    declarations = StatementSet(
        (
            Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
            ModelState(signal; initial = 7.0), ModelState(feedback; initial = 0.0),
            HistoryState(memory; of = signal, depth = 3, cadence = Every(1)),
            HistoryState(initial_memory; of = signal, depth = 3, cadence = AtMCS(0)),
            Synchronous(:sample, Assign(signal, draw(Uniform(), DrawKey(:sample)))),
            Synchronous(:respond, Assign(feedback, lag(memory, 0))),
            ProposalConstraint(:held_ownership, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )
    )
    source = PottsSystem(declarations; name = :random_history_feedback)
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
        values = (memory => (1.0, 2.0, 3.0), initial_memory => (4.0, 5.0, 6.0)),
    )
    problem = PottsProblem(source, initial, (0, 3); seed = 19)
    reference = nothing
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        @test integrator.u[:signal] == 7.0f0
        @test integrator.u[:memory] == (1.0f0, 2.0f0, 3.0f0)
        @test integrator.u[:initial_memory] == (4.0f0, 5.0f0, 7.0f0)
        restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
        expected = (1.0f0, 2.0f0, 3.0f0)
        samples = Float32[]
        for boundary in 1:3
            step!(integrator)
            step!(restored)
            sample = integrator.u[:signal]
            @test 0.0f0 < sample < 1.0f0
            @test integrator.u[:feedback] == last(expected)
            expected = (expected[2], expected[3], sample)
            @test integrator.u[:memory] == expected
            @test integrator.u[:initial_memory] == (4.0f0, 5.0f0, 7.0f0)
            @test integrator.t == restored.t == boundary
            for name in (:signal, :memory, :initial_memory, :feedback)
                @test restored.u[name] == integrator.u[name]
            end
            @test failure_report(integrator) === nothing
            @test failure_report(restored) === nothing
            push!(samples, sample)
        end
        reference === nothing || @test samples == reference
        reference = samples
    end
end

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
