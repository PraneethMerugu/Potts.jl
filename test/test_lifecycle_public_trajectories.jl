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
    resumed = solve!(
        init(
            problem,
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float32,
            checkpoint = captured,
            save_start = false,
        )
    )
    @test last(resumed).ownership == solution(5).ownership
    @test last(resumed).cell_kinds == solution(5).cell_kinds
    @test last(resumed).cell_generations == solution(5).cell_generations
    @test last(resumed)[:lifecycle_activity] ==
        solution(5)[:lifecycle_activity]
end

@testset "remove-cell replacement preserves Cartesian medium ownership" begin
    cell = CellKind(:replacement_cell; extinction = RetireAtZero())
    bulk = MediumKind(:a_replacement_bulk)
    alternate = MediumKind(:z_replacement_alternate)
    bulk_owner = MediumDomainOwner(:replacement_bulk_domain, bulk)
    alternate_owner = MediumDomainOwner(:replacement_alternate_domain, alternate)
    anchor = CellBinding(:replacement_anchor)
    labels = zeros(Int, 5, 5)
    labels[3, 3] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium = bulk_owner),
    )

    for (replacement_name, replacement, expected_bulk, expected_alternate) in (
            (:default, bulk_owner, 25, 0),
            (:nondefault, alternate_owner, 24, 1),
        )
        remove = LifecycleProcess(
            Symbol(:remove_to_, replacement_name);
            domain = cells(cell),
            anchor,
            expression = true,
            effects = (RemoveCell(
                anchor;
                replacement,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        )
        scheduled = mtkcompile(PottsSystem(
            name = Symbol(:remove_replacement_, replacement_name),
            statements = StatementSet((
                Lattice((5, 5); boundary = Closed(),
                    default_owner = bulk_owner,
                    domain_owners = (alternate_owner,), max_cells = 1),
                cell,
                bulk,
                alternate,
                ProposalConstraint(:freeze_remove_replacement, false),
                remove,
                Observation(:bulk_sites, occupancy(bulk, :lattice)),
                Observation(
                    :alternate_sites, occupancy(alternate, :lattice),
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )),
        ))
        problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x524d)
        for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
            integrator = init(
                problem,
                algorithm;
                scalar_type = Float32,
                observables = (:bulk_sites, :alternate_sites),
            )
            step!(integrator)
            @test integrator.u[:bulk_sites] == expected_bulk
            @test integrator.u[:alternate_sites] == expected_alternate
            @test count(<(0), integrator.u.ownership) == expected_alternate
            @test integrator.u.cell_kinds[1] == 0

            restored = init(
                problem,
                algorithm;
                scalar_type = Float32,
                observables = (:bulk_sites, :alternate_sites),
                checkpoint = checkpoint(integrator),
            )
            @test restored.u.ownership == integrator.u.ownership
            @test restored.u[:bulk_sites] == expected_bulk
            @test restored.u[:alternate_sites] == expected_alternate
            step!(integrator)
            step!(restored)
            @test restored.u.ownership == integrator.u.ownership
        end
    end
end

@testset "lifecycle relationship consequence is public and generation safe" begin
    cell = CellKind(:linked_cell; extinction = RetireAtZero())
    medium = MediumKind(:linked_medium)
    medium_owner = MediumDomainOwner(:linked_medium_domain, medium)
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
        expression = Potts.anchor_value(anchor) == 1,
        effects = (
            RemoveCell(
                anchor;
                replacement = medium_owner,
                on_inadmissible = ErrorOnInadmissible(),
            ),
        ),
        cadence = AtMCS(1),
    )
    scheduled = mtkcompile(
        PottsSystem(
            name = :lifecycle_relationship_model,
            statements = StatementSet(
                (
                    Lattice((5, 5); default_owner = medium_owner, max_cells = 2),
                    cell,
                    medium,
                    links,
                    ProposalConstraint(:freeze_linked_lifecycle, false),
                    remove,
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
        )
    )
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
