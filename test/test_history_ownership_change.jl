@testset "Eulerian fields and explicit site histories retain distinct ownership laws" begin
    @variables signal field_memory marked marked_memory activity activity_memory
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    anchor = CellBinding(:selected)
    model_source = PottsSystem(
        name = :site_history_lifetimes,
        statements = StatementSet(
            (
                Lattice((3, 3); boundary = Closed(), max_cells = 1), cell, medium,
                FieldState(signal; initial = 7.0),
                HistoryState(field_memory; of = signal, depth = 3, initial = 4.0, cadence = Every(100)),
                FieldState(marked; initial = 5.0, lifecycle = ClearOnOwnershipChange()),
                HistoryState(
                    marked_memory; of = marked, depth = 3, initial = 6.0,
                    cadence = Every(100), lifecycle = ClearOnOwnershipChange()
                ),
                SiteState(activity; initial = 9.0, lifecycle = ClearOnOwnershipChange()),
                HistoryState(
                    activity_memory; of = activity, depth = 3, initial = 8.0,
                    cadence = Every(100), lifecycle = ClearOnOwnershipChange()
                ),
                ProposalConstraint(:fixed_ownership, false),
                LifecycleProcess(
                    :remove; domain = cells(cell), anchor, expression = true,
                    effects = (RemoveCell(anchor; replacement = medium, on_inadmissible = ErrorOnInadmissible()),),
                    cadence = AtMCS(1)
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = (signal, field_memory, marked, marked_memory, activity, activity_memory),
    )
    owners = zeros(Int, 3, 3)
    owners[2, 2] = 1
    problem = PottsProblem(
        model_source, PottsInitialState(;
            ownership = LabelledCells(owners; cells = [cell], medium)
        ), (0, 1); seed = 17
    )
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm)
        step!(integrator)
        @test failure_report(integrator) === nothing
        @test all(<=(0), integrator.u.ownership)
        @test integrator.u[:signal] == fill(7.0f0, 3, 3)
        @test integrator.u[:field_memory] == ntuple(_ -> fill(4.0f0, 3, 3), 3)
        for (name, initial) in ((:marked, 5.0f0), (:activity, 9.0f0))
            expected = fill(initial, 3, 3)
            expected[2, 2] = 0.0f0
            @test integrator.u[name] == expected
        end
        for (name, initial) in ((:marked_memory, 6.0f0), (:activity_memory, 8.0f0))
            expected = fill(initial, 3, 3)
            expected[2, 2] = 0.0f0
            @test integrator.u[name] == ntuple(_ -> copy(expected), 3)
        end
    end
end
