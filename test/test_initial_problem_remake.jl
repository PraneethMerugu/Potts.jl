@testset "initial state, problem, and remake" begin
    @variables t marker(t)
    @parameters target=8.0 strength temperature
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    @named source = PottsSystem(
        statements = StatementSet((
            Lattice((8, 8); relations = (proposal = VonNeumann(),)),
            cell,
            medium,
            SiteState(marker; name = :marker, initial = 0.0),
            Volume(cell; target, strength),
            Protocol(Sweep(; temperature); name = :main),
        )),
        unknowns = [marker],
        parameters = [target, strength, temperature],
        independent_variables = [t],
    )
    executable = compile(
        complete(source);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    labels = zeros(Int, 8, 8)
    labels[3:5, 3:5] .= 1
    labelled = LabelledCells(labels; cells = [cell], medium)
    initial = PottsInitialState(
        ownership = labelled,
        values = (marker => fill(1.0f0, 8, 8),),
    )
    labels .= 7
    @test all(getfield(getfield(initial, :ownership), :labels)[3:5, 3:5] .== 1)
    @test_throws ArgumentError PottsProblem(
        executable, initial, (0, 5); p = [strength => 2.0], seed = 4
    )
    problem = PottsProblem(
        executable,
        initial,
        (0, 5);
        p = [strength => 2.0, temperature => 4.0],
        seed = 0x1234,
    )
    @test problem.seed == 0x1234
    @test problem.replica == 1
    @test_throws UndefKeywordError PottsProblem(
        executable,
        initial,
        (0, 5);
        p = [strength => 2.0, temperature => 4.0],
    )
    @test_throws ArgumentError PottsProblem(
        executable,
        initial,
        (0.5, 5);
        p = [strength => 2.0, temperature => 4.0],
        seed = 1,
    )
    @test_throws ArgumentError PottsProblem(
        executable,
        initial,
        (0, 5);
        p = [strength => 2.0, temperature => 4.0],
        seed = 1,
        replica = 0,
    )

    remade = remake(problem; tspan = (2, 8), seed = 99, replica = 3)
    @test remade.tspan == (2, 8)
    @test remade.seed == 99
    @test remade.replica == 3
    @test remade.initial !== problem.initial
    overlaid = remake(problem; u0 = Dict(marker => fill(2.0f0, 8, 8)))
    @test all(init(overlaid).u[:marker] .== 2.0f0)
    @test all(init(problem).u[:marker] .== 1.0f0)
    @test_throws ArgumentError remake(problem; algorithm = :forbidden)

    layout = OwnershipLayout(
        (8, 8),
        CellPlacement(1, cell, ((3, 3), (3, 4), (4, 3), (4, 4)));
        medium,
    )
    layout_problem = PottsProblem(
        executable,
        PottsInitialState(ownership = layout),
        (0, 1);
        p = [strength => 2.0, temperature => 4.0],
        seed = 2,
    )
    @test sum(init(layout_problem).u.ownership .== 1) == 4
    labelled_equivalent = zeros(Int, 8, 8)
    labelled_equivalent[3:4, 3:4] .= 1
    labelled_problem = PottsProblem(
        executable,
        PottsInitialState(
            ownership = LabelledCells(
                labelled_equivalent; cells = [cell], medium
            ),
        ),
        (0, 1);
        p = [strength => 2.0, temperature => 4.0],
        seed = 2,
    )
    @test solve(layout_problem)(1).ownership ==
          solve(labelled_problem)(1).ownership

    procedural_layout = OwnershipLayout(
        (8, 8),
        RandomSitePlacement(
            :seeded_cells,
            cell;
            count = 2,
            sites_per_cell = 2,
            first_label = 1,
        );
        medium,
    )
    procedural_problem = PottsProblem(
        executable,
        PottsInitialState(ownership = procedural_layout),
        (0, 2);
        p = [strength => 2.0, temperature => 4.0],
        seed = 0xabc,
    )
    procedural_ownership = init(procedural_problem).u.ownership
    @test count(==(1), procedural_ownership) == 2
    @test count(==(2), procedural_ownership) == 2
    @test init(procedural_problem).u.ownership == procedural_ownership
    @test init(remake(procedural_problem; replica = 2)).u.ownership !=
          procedural_ownership
    explicit_equivalent = PottsProblem(
        executable,
        PottsInitialState(ownership = LabelledCells(
            procedural_ownership; cells = [cell, cell], medium
        )),
        (0, 2);
        p = [strength => 2.0, temperature => 4.0],
        seed = 0xabc,
    )
    @test getfield.(solve(procedural_problem; save_everystep = true).u, :ownership) ==
          getfield.(solve(explicit_equivalent; save_everystep = true).u, :ownership)

    border = MediumKind(:border)
    @named multiple_media = PottsSystem(
        statements = StatementSet((
            Lattice((6, 6); boundary = Closed()),
            cell,
            medium,
            border,
            Volume(cell; target = 4.0, strength = 1.0),
            Protocol(Sweep(; temperature = 2.0); name = :main),
            Observation(:medium_sites, occupancy(medium, :lattice)),
            Observation(:border_sites, occupancy(border, :lattice)),
        )),
    )
    multiple_media_executable = compile(
        complete(multiple_media);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    border_sites = Tuple(
        (row, column)
        for row in (1, 6) for column in 1:6
    )
    multiple_media_layout = OwnershipLayout(
        (6, 6),
        MediumPlacement(border, border_sites),
        CellPlacement(1, cell, ((3, 3), (3, 4), (4, 3), (4, 4)));
        medium,
    )
    multiple_media_problem = PottsProblem(
        multiple_media_executable,
        PottsInitialState(ownership = multiple_media_layout),
        (0, 0);
        seed = 3,
    )
    multiple_media_integrator = init(
        multiple_media_problem;
        observables = (:medium_sites, :border_sites),
    )
    @test multiple_media_integrator.u[:border_sites] == 12
    @test multiple_media_integrator.u[:medium_sites] == 20
    @test length(unique(multiple_media_integrator.u.ownership)) == 3
end
