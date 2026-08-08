function _g5h_host_relationship_fixture(name::Symbol)
    cell = CellKind(Symbol(name, :_cell); extinction = RetireAtZero())
    medium = MediumKind(Symbol(name, :_medium))
    links = RelationshipState(
        Symbol(name, :_links);
        endpoints = Undirected(cell, cell),
        payload = (score = 1.0, marker = 2.0),
        capacity = 2,
        maximum_degree = 2,
        lifecycle = RemoveWithEndpoint(),
    )
    source = PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice((3, 1); boundary = Closed()),
            cell,
            medium,
            links,
            ProposalConstraint(Symbol(name, :_frozen), false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
    )
    scheduled = mtkcompile(source)
    initial = PottsInitialState(
        ownership = LabelledCells(
            reshape(Int32[1, 0, 2], 3, 1);
            cells = [cell, cell],
            medium,
        ),
    )
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x3501)
    return (; cell, medium, links, scheduled, problem)
end

function _g5h_active_edge(topology)
    active = findall(topology.active)
    return length(active) == 1 ? only(active) : nothing
end

@testset "settled host relationship transaction is atomic and generation-safe" begin
    fixture = _g5h_host_relationship_fixture(:g5h_host_relationship)
    integrator = init(
        fixture.problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_start = false,
    )
    relationship_name = Symbol(:g5h_host_relationship, :_links)
    @test count(integrator.u[relationship_name].active) == 0

    first_identity = CellIdentity(
        1,
        integrator.u.cell_generations[1],
        integrator.u.cell_kinds[1],
    )
    second_identity = CellIdentity(
        2,
        integrator.u.cell_generations[2],
        integrator.u.cell_kinds[2],
    )
    returned = relationship_transaction!(
        integrator,
        Create(
            fixture.links,
            first_identity,
            second_identity;
            payload = (marker = 4.0, score = 3.0),
        ),
    )
    @test returned === integrator
    topology = integrator.u[relationship_name]
    edge = _g5h_active_edge(topology)
    @test edge !== nothing
    @test topology.payload[1][edge] == 3.0
    @test topology.payload[2][edge] == 4.0

    # Named payload order is author-facing; lowering restores schema order.
    relationship_transaction!(
        integrator,
        Retune(
            fixture.links,
            first_identity ↔ second_identity;
            payload = (marker = 6.0, score = 5.0),
        ),
    )
    topology = integrator.u[relationship_name]
    edge = _g5h_active_edge(topology)
    @test topology.payload[1][edge] == 5.0
    @test topology.payload[2][edge] == 6.0

    captured = checkpoint(integrator)
    resumed = init(
        fixture.problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        checkpoint = captured,
        save_start = false,
    )
    @test resumed.u[relationship_name].active == topology.active
    @test resumed.u[relationship_name].payload == topology.payload

    before = integrator.u[relationship_name]
    @test_throws ArgumentError relationship_transaction!(
        integrator,
        Retune(
            fixture.links,
            1 ↔ 2;
            payload = (score = 9.0, marker = 10.0),
        ),
        Create(
            fixture.links,
            1,
            1;
            payload = (score = 11.0, marker = 12.0),
        ),
    )
    after = integrator.u[relationship_name]
    @test after.active == before.active
    @test after.payload == before.payload

    stale = CellIdentity(
        first_identity.slot,
        first_identity.generation + UInt32(1),
        first_identity.kind,
    )
    @test_throws ArgumentError relationship_transaction!(
        integrator, Remove(fixture.links, stale ↔ second_identity)
    )
    @test integrator.u[relationship_name].active == before.active
    @test_throws ArgumentError relationship_transaction!(
        integrator, Remove(fixture.links, edge)
    )
    @test_throws ArgumentError relationship_transaction!(
        integrator,
        Retune(
            fixture.links,
            1 ↔ 2;
            payload = (score = 1.0,),
        ),
    )

    relationship_transaction!(
        integrator, Remove(fixture.links, 1 ↔ 2)
    )
    @test count(integrator.u[relationship_name].active) == 0
end

@testset "host relationship mutation rolls back with a failing callback set" begin
    fixture = _g5h_host_relationship_fixture(:g5h_host_callback)
    relationship_name = Symbol(:g5h_host_callback, :_links)
    mutate = SciMLBase.DiscreteCallback(
        (_, time, _) -> time == 1,
        integrator -> relationship_transaction!(
            integrator,
            Create(
                fixture.links,
                1,
                2;
                payload = (score = 7.0, marker = 8.0),
            ),
        );
        save_positions = (false, false),
    )
    fail = SciMLBase.DiscreteCallback(
        (_, time, _) -> time == 1,
        _ -> error("failure after relationship mutation");
        save_positions = (false, false),
    )
    integrator = init(
        fixture.problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        callback = SciMLBase.CallbackSet(mutate, fail),
        save_start = false,
    )
    @test_throws ErrorException step!(integrator)
    @test count(integrator.u[relationship_name].active) == 0
    @test integrator.retcode == SciMLBase.ReturnCode.Failure
end

@testset "host relationship transaction rebuilds checkerboard banks" begin
    fixture = _g5h_host_relationship_fixture(:g5h_host_checkerboard)
    relationship_name = Symbol(:g5h_host_checkerboard, :_links)
    integrator = init(
        fixture.problem,
        CheckerboardSweepCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_start = false,
    )
    relationship_transaction!(
        integrator,
        Create(
            fixture.links,
            1,
            2;
            payload = (score = 2.0, marker = 3.0),
        ),
    )
    @test count(integrator.u[relationship_name].active) == 1
    step!(integrator)
    @test count(integrator.u[relationship_name].active) == 1
end
