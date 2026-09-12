@testset "cell lifecycle policies address every retained sample" begin
    @variables signal copied reset split sampled
    cell = CellKind(:cell; extinction = RetireAtZero())
    changed = CellKind(:changed; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    anchor = CellBinding(:selected)
    relation = SpatialRelation(:division; neighborhood = VonNeumann())
    source = CellState(signal; initial = 8.0, creation = InitializeFrom(10.0), division = CopyToDaughters(), transition = Preserve(), retirement = RetireTo(0.0))
    copied_history = HistoryState(
        copied; of = signal, depth = 3, cadence = Every(100),
        creation = InitializeFrom(11.0),
        division = CopyToDaughters(), transition = Preserve(), retirement = RetireTo(9.0)
    )
    reset_history = HistoryState(
        reset; of = signal, depth = 3, cadence = Every(100),
        creation = InitializeFrom(12.0),
        division = ResetBoth(20.0, 30.0), transition = ResetTo(40.0), retirement = RetireTo(8.0)
    )
    split_history = HistoryState(
        split; of = signal, depth = 3, cadence = Every(100),
        creation = InitializeFrom(13.0),
        division = SplitConservatively(0.25; rounding = :exact),
        transition = Transform(lag(copied, 0) + 1.0), retirement = RetireTo(7.0)
    )
    sampled_history = HistoryState(
        sampled; of = signal, depth = 3,
        creation = InitializeFrom(14.0),
        division = CopyToDaughters(), transition = Preserve(), retirement = RetireTo(9.0)
    )
    model_source = PottsSystem(
        name = :retained_cell_lifecycle,
        statements = StatementSet(
            (
                Lattice((4, 3); boundary = Closed(), max_cells = 2), cell, changed, medium, relation,
                source, copied_history, reset_history, split_history, sampled_history,
                ProposalConstraint(:fixed_ownership, false),
                LifecycleProcess(
                    :divide; domain = cells(cell), anchor, expression = true,
                    effects = (
                        Divide(
                            anchor; geometry = SpecifiedNormalPlane((1.0, 0.0)), relation,
                            side = CanonicalSide(), parent_kind = PreserveKind(), daughter_kind = SetKind(cell),
                            on_inadmissible = ErrorOnInadmissible()
                        ),
                    ), cadence = AtMCS(1)
                ),
                LifecycleProcess(
                    :transition; domain = cells(cell), anchor, expression = true,
                    effects = (Transition(anchor, changed; on_inadmissible = ErrorOnInadmissible()),), cadence = AtMCS(2)
                ),
                LifecycleProcess(
                    :remove; domain = cells(changed), anchor, expression = true,
                    effects = (RemoveCell(anchor; replacement = medium, on_inadmissible = ErrorOnInadmissible()),), cadence = AtMCS(3)
                ),
                LifecycleProcess(
                    :create; domain = model(), expression = true,
                    effects = (CreateCell(cell; placement = SeedAt(1), on_inadmissible = ErrorOnInadmissible()),),
                    cadence = AtMCS(4)
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = (signal, copied, reset, split, sampled),
    )
    ownership = LabelledCells(ones(Int, 4, 3); cells = [cell], medium)
    initial = PottsInitialState(;
        ownership, values = (
            copied => ([1.0], [2.0], [3.0]),
            reset => ([4.0], [5.0], [6.0]),
            split => ([8.0], [12.0], [16.0]),
            sampled => ([1.0], [2.0], [3.0]),
        )
    )
    problem = PottsProblem(model_source, initial, (0, 4); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm)
        step!(integrator)
        @test integrator.u[:copied] == ([1.0f0, 1.0f0], [2.0f0, 2.0f0], [3.0f0, 3.0f0])
        @test integrator.u[:reset] == ntuple(_ -> [20.0f0, 30.0f0], 3)
        @test integrator.u[:split] == ([2.0f0, 6.0f0], [3.0f0, 9.0f0], [4.0f0, 12.0f0])
        @test integrator.u[:sampled] == ([2.0f0, 2.0f0], [3.0f0, 3.0f0], [8.0f0, 8.0f0])
        @test all(>(0), integrator.u.ownership)
        @test Set(integrator.u.ownership) == Set((1, 2))
        step!(integrator)
        @test integrator.u[:copied] == ([1.0f0, 1.0f0], [2.0f0, 2.0f0], [3.0f0, 3.0f0])
        @test integrator.u[:reset] == ntuple(_ -> [40.0f0, 40.0f0], 3)
        @test integrator.u[:split] == ntuple(_ -> [4.0f0, 4.0f0], 3)
        @test integrator.u[:sampled] == ([3.0f0, 3.0f0], [8.0f0, 8.0f0], [8.0f0, 8.0f0])
        saved = checkpoint(integrator)
        restored = init(problem, algorithm; checkpoint = saved)
        @test restored.u[:copied] == integrator.u[:copied]
        step!(restored)
        @test restored.u[:signal] == [0.0f0, 0.0f0]
        @test restored.u[:copied] == ntuple(_ -> [9.0f0, 9.0f0], 3)
        @test restored.u[:reset] == ntuple(_ -> [8.0f0, 8.0f0], 3)
        @test restored.u[:split] == ntuple(_ -> [7.0f0, 7.0f0], 3)
        @test restored.u[:sampled] == ([9.0f0, 9.0f0], [9.0f0, 9.0f0], [0.0f0, 0.0f0])
        @test all(<=(0), restored.u.ownership)
        @test failure_report(restored) === nothing
        retired_generations = copy(restored.u.cell_generations)
        step!(restored)
        @test restored.u.ownership[1] == 1
        @test count(>(0), restored.u.ownership) == 1
        @test restored.u.cell_generations[1] == retired_generations[1] + UInt32(1)
        @test restored.u.cell_generations[2] == retired_generations[2]
        @test restored.u[:signal] == [10.0f0, 0.0f0]
        @test restored.u[:copied] == ntuple(_ -> [11.0f0, 9.0f0], 3)
        @test restored.u[:reset] == ntuple(_ -> [12.0f0, 8.0f0], 3)
        @test restored.u[:split] == ntuple(_ -> [13.0f0, 7.0f0], 3)
        @test restored.u[:sampled] == ([14.0f0, 9.0f0], [14.0f0, 0.0f0], [10.0f0, 0.0f0])
        @test failure_report(restored) === nothing
    end
end
