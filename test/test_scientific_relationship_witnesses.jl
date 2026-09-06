@testset "relationship constraint blocks linked-cell absorption" begin
    cell = CellKind(:constrained_link_cell; extinction = RetireAtZero())
    medium = MediumKind(:constrained_link_medium)
    links = RelationshipState(
        :constrained_links;
        endpoints = Undirected(cell, cell),
        capacity = 1,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    copy_context = ProposalContext(:constrained_link_copy)
    source = PottsSystem(
        name = :relationship_constraint_witness,
        statements = StatementSet((
            Lattice(
                (2, 1);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            links,
            RelationshipConstraint(
                :preserve_linked_cells,
                links,
                !linked(
                    links,
                    copy_context.source_cell,
                    copy_context.target_cell,
                ),
            ),
            Protocol(Sweep(; temperature = 100.0); name = :main),
        )),
    )
    labels = reshape(Int32[1, 2], 2, 1)
    scheduled = mtkcompile(source)
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell, cell], medium),
        values = (links => [(1, 2)],),
    )
    solution = nothing
    for seed in UInt64(1):UInt64(256)
        candidate = solve(
            PottsProblem(scheduled, initial, (0, 1); seed),
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float64,
            save_everystep = true,
        )
        candidate.stats.constraint_rejections > 0 || continue
        solution = candidate
        break
    end
    @test solution !== nothing
    solution === nothing && error("no relationship-constraint witness found")
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test last(solution).ownership == labels
    @test solution.stats.accepted == 0
    # The witness is selected by the scientific event being exercised rather
    # than by one frozen RNG trajectory.
    @test solution.stats.constraint_rejections > 0
    @test count(last(solution)[:constrained_links].active) == 1
end
@testset "relationship retune publishes payload and survives checkpoint" begin
    cell = CellKind(:retune_cell; extinction = RetireAtZero())
    medium = MediumKind(:retune_medium)
    links = RelationshipState(
        :retune_links;
        endpoints = Undirected(cell, cell),
        payload = (score = 1.0, marker = 1.0),
        capacity = 1,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(:retune_edge, links)
    retune = LifecycleProcess(
        :retune_once;
        domain = edges(links),
        expression = edge.marker > 0,
        effects = (Retune(
            links,
            edge;
            payload = (score = edge.score + 2, marker = 0.0),
        ),),
        cadence = AtMCS(1),
    )
    source = PottsSystem(
        name = :relationship_retune_witness,
        statements = StatementSet((
            Lattice((3, 1); boundary = Closed()),
            cell,
            medium,
            links,
            ProposalConstraint(:freeze_retune_witness, false),
            retune,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
    )
    labels = reshape(Int32[1, 0, 2], 3, 1)
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, cell], medium
        ),
        values = (links => [(1, 2)],),
    )
    scheduled = mtkcompile(source)
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x3307)
    uninterrupted = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    topology = uninterrupted(1)[:retune_links]
    edge_slot = only(findall(topology.active))
    @test topology.payload[1][edge_slot] == 3
    @test topology.payload[2][edge_slot] == 0
    checkerboard = solve(
        problem,
        CheckerboardSweepCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    checkerboard_topology = checkerboard(1)[:retune_links]
    @test checkerboard_topology.active == topology.active
    @test checkerboard_topology.payload == topology.payload

    integrator = init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_start = false,
    )
    step!(integrator)
    captured = checkpoint(integrator)
    resumed = solve!(init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        checkpoint = captured,
        save_start = false,
    ))
    @test last(resumed)[:retune_links].payload ==
          last(uninterrupted)[:retune_links].payload
    @test last(resumed)[:retune_links].active ==
          last(uninterrupted)[:retune_links].active
end

@testset "accepted ownership survives filtered relationship admission" begin
    @variables relationship_filter_mask
    cell = CellKind(:relationship_filter_cell; extinction = RetireAtZero())
    medium = MediumKind(:relationship_filter_medium)
    mask = FieldState(
        relationship_filter_mask;
        name = :relationship_filter_mask,
        initial = 0.0,
    )
    links = RelationshipState(
        :filtered_links;
        endpoints = Undirected(cell, cell),
        payload = (weight = 1.0,),
        capacity = 3,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    copy = ProposalContext(:relationship_filter_copy)
    source = PottsSystem(
        name = :relationship_filter_model,
        statements = StatementSet((
            Lattice(
                (5, 5);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            mask,
            links,
            ProposalConstraint(
                :only_marked_relationship_copy,
                (field_value(
                    relationship_filter_mask, copy.source_site
                ) == 1) &
                (field_value(
                    relationship_filter_mask, copy.target_site
                ) == 2),
            ),
            AcceptedCopy(
                :request_filtered_link,
                Create(
                    links,
                    copy.source_cell,
                    copy.target_cell;
                    payload = (weight = 1.0,),
                );
                when = new_contact(copy.source_cell, copy.target_cell) &
                       !linked(links, copy.source_cell, copy.target_cell),
            ),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [relationship_filter_mask],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 5, 5)
    labels[3, 2] = 1
    labels[1, 1] = 2
    labels[3, 4] = 3
    mask_values = zeros(Float64, 5, 5)
    mask_values[3, 2] = 1
    mask_values[3, 3] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, cell, cell], medium
        ),
        values = (
            relationship_filter_mask => mask_values,
            links => [(1, 2)],
        ),
    )
    witness = nothing
    for seed in UInt64(1):UInt64(512)
        candidate = solve(
            PottsProblem(scheduled, initial, (0, 1); seed),
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float64,
            save_everystep = true,
        )
        last(candidate).ownership[3, 3] == 1 || continue
        witness = candidate
        break
    end
    @test witness !== nothing
    witness === nothing && error("no filtered relationship witness found")
    final = last(witness)
    @test witness.stats.accepted == 1
    @test final.ownership[3, 3] == 1
    topology = final[:filtered_links]
    @test count(topology.active) == 1
    edge = only(findall(topology.active))
    @test (topology.endpoint_a[edge], topology.endpoint_b[edge]) ==
          (Int32(1), Int32(2))
end
