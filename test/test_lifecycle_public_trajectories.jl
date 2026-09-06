@testset "scheduled public lifecycle trajectory and restart" begin
    fixture = lifecycle_public_fixture()
    scheduled = mtkcompile(fixture.source)
    plans = inspect(scheduled, LifecyclePlans())
    @test Set(plan.effect for plan in plans) ==
          Set((:CreateCell, :Transition, :Divide, :RemoveCell, :Retire))
    @test count(plan -> plan.effect === :Retire, plans) == 2
    problem = PottsProblem(scheduled, fixture.initial, (0, 5); seed = 0x51f3)
    solution = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test solution.t == collect(0:5)
    @test count(!iszero, solution(1).cell_kinds) == 2
    @test solution(1).cell_generations[1:2] == UInt32[1, 1]
    @test solution(1)[:lifecycle_activity][1:2] == Float32[1, 2]
    @test count(!iszero, solution(2).cell_kinds) == 2
    @test solution(2)[:lifecycle_activity][1:2] == Float32[2, 3]
    @test count(!iszero, solution(3).cell_kinds) == 4
    @test sum(solution(3).volumes) == 6
    @test sum(solution(3)[:lifecycle_activity][1:4]) == 5
    @test all(iszero, solution(4).cell_kinds)
    @test all(solution(4).ownership .<= 0)
    @test solution(5).cell_kinds[1] != 0
    @test solution(5).cell_generations[1] == 2
    @test solution(5)[:lifecycle_activity][1] == 5

    integrator = init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    step!(integrator)
    step!(integrator)
    captured = checkpoint(integrator)
    resumed = solve!(init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        checkpoint = captured,
        save_start = false,
    ))
    @test last(resumed).ownership == solution(5).ownership
    @test last(resumed).cell_kinds == solution(5).cell_kinds
    @test last(resumed).cell_generations == solution(5).cell_generations
    @test last(resumed)[:lifecycle_activity] ==
          solution(5)[:lifecycle_activity]
end
@testset "lifecycle relationship consequence is public and generation safe" begin
    cell = CellKind(:linked_cell; extinction = RetireAtZero())
    medium = MediumKind(:linked_medium)
    links = RelationshipState(
        :linked_edges;
        endpoints = Undirected(cell, cell),
        capacity = 2,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    anchor = CellBinding(:linked_remove_anchor)
    remove = LifecycleProcess(
        :remove_linked_endpoint;
        domain = cells(cell),
        anchor,
        expression = anchor_value(anchor) == 1,
        effects = (RemoveCell(
            anchor;
            replacement = medium,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    scheduled = mtkcompile(PottsSystem(
        name = :lifecycle_relationship_model,
        statements = StatementSet((
            Lattice((5, 5); max_cells = 2),
            cell,
            medium,
            links,
            ProposalConstraint(:freeze_linked_lifecycle, false),
            remove,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
    ))
    labels = zeros(Int, 5, 5)
    labels[2, 2] = 1
    labels[4, 4] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, cell], medium
        ),
        values = (links => [(1, 2)],),
    )
    solution = solve(
        PottsProblem(scheduled, initial, (0, 1); seed = 12),
        SequentialCPM();
        scalar_type = Float64,
        save_everystep = true,
    )
    @test count(solution(0)[:linked_edges].active) == 1
    @test count(solution(1)[:linked_edges].active) == 0
    @test solution(1).cell_kinds[1] == 0
    @test solution(1).cell_generations[1] == 1
end
