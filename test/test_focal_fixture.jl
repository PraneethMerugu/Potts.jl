@testset "visible focal-point-plasticity fixture" begin
    @parameters begin
        A₀ = 6.0
        λA = 2.0
        λf = 1.5
        Lf = 4.0
        Lbreak = 12.0
        temperature = 8.0
    end
    endothelial = CellKind(:endothelial)
    extracellular = MediumKind(:extracellular)
    focal_links = RelationshipState(
        :focal_links;
        endpoints = Undirected(endothelial, endothelial),
        payload = (strength = λf, target = Lf, maximum = Lbreak),
        capacity = 6,
        maximum_degree = 3,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(:edge, focal_links)
    copy_context = ProposalContext(:copy)
    model_statements = @statements begin
        Lattice(
            (16, 10);
            boundary = Closed(),
            relations = (proposal = VonNeumann(), contact = Moore()),
        )
        endothelial
        extracellular
        focal_links
        Volume(endothelial; target = A₀, strength = λA)
        RelationshipEnergy(
            :focal_spring,
            edge,
            edge.strength * (
                distance(
                    unwrapped_center(edge.a),
                    unwrapped_center(edge.b),
                ) - edge.target
            )^2,
        )
        AcceptedCopy(
            :create_contact_link,
            Create(
                focal_links,
                copy_context.source_cell,
                copy_context.target_cell;
                payload = (
                    strength = λf,
                    target = Lf,
                    maximum = Lbreak,
                ),
            );
            when = new_contact(
                copy_context.source_cell, copy_context.target_cell
            ) & !linked(
                focal_links,
                copy_context.source_cell,
                copy_context.target_cell,
            ),
        )
        LifecycleProcess(
            :cleanup_retired_or_stretched_links;
            domain = edges(focal_links),
            expression = distance(
                unwrapped_center(edge.a), unwrapped_center(edge.b)
            ) > edge.maximum,
            effects = (Remove(focal_links, edge),),
            phase = Lifecycle(),
        )
        Protocol(Sweep(; temperature); name = :main)
        Observation(:link_count, degree(focal_links, 1))
    end
    @named focal = PottsSystem(
        statements = model_statements,
        parameters = [A₀, λA, λf, Lf, Lbreak, temperature],
    )
    completed = complete(focal)
    @test !inspect(completed, Capabilities()).checkerboard
    @test_throws ArgumentError compile(
        completed;
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    executable = compile(
        completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    labels = zeros(Int, 16, 10)
    labels[3:4, 4:5] .= 1
    labels[10:11, 4:5] .= 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [endothelial, endothelial],
            medium = extracellular,
        ),
        values = [focal_links => [(1, 2)]],
    )
    problem = PottsProblem(executable, initial, (0, 4); seed = 0xf0ca1)
    stale_initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [endothelial, endothelial],
            medium = extracellular,
        ),
        values = [
            focal_links => [(
                1,
                2,
                (
                    generation_a = 2,
                    generation_b = 1,
                    strength = 1.5,
                    target = 4.0,
                    maximum = 12.0,
                ),
            )],
        ],
    )
    @test_throws ArgumentError PottsProblem(
        executable, stale_initial, (0, 1); seed = 1
    )
    trajectory = solve(
        problem; save_everystep = true, observables = (:link_count,)
    )
    replay = solve(problem; save_everystep = true)
    independent = solve(
        remake(problem; replica = 2); save_everystep = true
    )
    @test count(trajectory(0).relationships.active) == 1
    @test trajectory(0)[:link_count] == 1
    @test all(
        left.ownership == right.ownership &&
        left.relationships.active == right.relationships.active
        for (left, right) in zip(trajectory, replay)
    )
    @test any(
        left.ownership != right.ownership
        for (left, right) in zip(trajectory, independent)
    )

    # The Core transaction is all-or-nothing under capacity, degree,
    # generation, duplicate, and per-edge conflict validation.
    plan = getfield(getfield(executable, :core_program), :relationships)
    state = CorePotts.ProgramRelationshipState(Float64, plan.capacity)
    cell_kinds = Int16[2, 2, 2]
    cell_generations = UInt32[1, 1, 1]
    first_request = CorePotts.CreateRelationshipRequest(
        1, 2, 1.0, 2.0, 8.0; identity = 1
    )
    CorePotts.apply_relationship_requests!(
        state,
        cell_kinds,
        cell_generations,
        plan,
        [first_request, first_request],
    )
    @test count(state.active) == 1
    before = copy(state)
    invalid_batch = [
        CorePotts.CreateRelationshipRequest(
            1, 3, 1.0, 2.0, 8.0; identity = 2
        ),
        CorePotts.CreateRelationshipRequest(
            2, 3, 1.0, 2.0, 8.0;
            generation_b = 2,
            identity = 3,
        ),
    ]
    @test_throws ArgumentError CorePotts.apply_relationship_requests!(
        state, cell_kinds, cell_generations, plan, invalid_batch
    )
    @test state.active == before.active
    @test state.endpoint_a == before.endpoint_a
    @test state.endpoint_b == before.endpoint_b

    conflict = [
        CorePotts.RetuneRelationshipRequest(
            1, 2.0, 3.0, 9.0; identity = 4
        ),
        CorePotts.RemoveRelationshipRequest(1; identity = 5),
    ]
    @test_throws ArgumentError CorePotts.apply_relationship_requests!(
        state, cell_kinds, cell_generations, plan, conflict
    )
    @test state.active == before.active

    integrator = init(problem; save_start = false)
    step!(integrator)
    captured = checkpoint(integrator)
    resumed = solve!(init(problem; checkpoint = captured, save_start = false))
    uninterrupted = solve(problem)
    @test resumed(4).relationships.active ==
          uninterrupted(4).relationships.active
    @test resumed(4).relationships.endpoint_a ==
          uninterrupted(4).relationships.endpoint_a
end
