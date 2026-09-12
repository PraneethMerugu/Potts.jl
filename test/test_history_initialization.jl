@testset "initial capture observes callback edits and does not repeat on checkpoint restore" begin
    @variables signal memory periodic_memory feedback
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :initial_capture,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                ModelState(signal; initial = 7.0), ModelState(feedback; initial = 0.0),
                HistoryState(memory; of = signal, depth = 3, cadence = AtMCS(0)),
                HistoryState(periodic_memory; of = signal, depth = 3, cadence = Every(2)),
                Synchronous(:respond, Assign(signal, signal + 1), Assign(feedback, lag(memory, 0))),
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (signal, memory, periodic_memory, feedback),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
        values = (memory => (1.0, 2.0, 3.0), periodic_memory => (4.0, 5.0, 6.0)),
    )
    problem = PottsProblem(source, initial, (0, 2); seed = 17)
    function publish_initial_value!(integrator, value; edit_prehistory = false)
        if edit_prehistory
            setu(integrator, (signal, memory))(integrator, (value, (70.0, 2.0, 3.0)))
        else
            setu(integrator, signal)(integrator, value)
        end
    end
    initial_callback = SciMLBase.DiscreteCallback(
        (_, _, _) -> false, _ -> nothing;
        initialize = (_, _, _, integrator) -> publish_initial_value!(integrator, 11; edit_prehistory = true),
    )
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32, callback = initial_callback)
        @test integrator.t == 0
        @test integrator.u[:signal] == 11.0f0
        @test integrator.u[:feedback] == 0.0f0
        @test integrator.u[:memory] == (70.0f0, 2.0f0, 11.0f0)
        @test integrator.u[:periodic_memory] == (4.0f0, 5.0f0, 6.0f0)
        @test_throws r"callback identity and state" checkpoint(integrator)
        checkpoint_source = init(problem, algorithm; scalar_type = Float32)
        @test checkpoint_source.u[:memory] == (1.0f0, 2.0f0, 7.0f0)
        publish_initial_value!(checkpoint_source, 99)
        restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(checkpoint_source))
        @test restored.u[:signal] == 99.0f0
        @test restored.u[:memory] == (1.0f0, 2.0f0, 7.0f0)
        step!(restored)
        @test restored.u[:signal] == 100.0f0
        @test restored.u[:feedback] == 7.0f0
        @test restored.u[:memory] == (1.0f0, 2.0f0, 7.0f0)
        solution = solve!(integrator)
        @test first(solution.u)[:memory] == (70.0f0, 2.0f0, 11.0f0)
        @test last(solution.u)[:signal] == 13.0f0
        @test last(solution.u)[:memory] == (70.0f0, 2.0f0, 11.0f0)
        @test last(solution.u)[:periodic_memory] == (5.0f0, 6.0f0, 13.0f0)
        @test failure_report(integrator) === nothing
    end
end
