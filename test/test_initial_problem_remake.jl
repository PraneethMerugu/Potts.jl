@testset "scheduled initial state, problem, and remake" begin
    @variables initial_marker
    @parameters begin
        initial_target = 8.0
        initial_strength
        initial_temperature
    end
    cell = CellKind(:initial_cell; extinction = RetireAtZero())
    medium = MediumKind(:initial_medium)
    source = PottsSystem(
        name = :initial_problem_model,
        statements = StatementSet((
            Lattice((8, 8); relations = (proposal = VonNeumann(),)),
            cell,
            medium,
            SiteState(initial_marker; name = :initial_marker, initial = 0.0),
            Volume(cell; target = initial_target, strength = initial_strength),
            Protocol(
                Sweep(; temperature = initial_temperature);
                name = :main,
            ),
        )),
        unknowns = [initial_marker],
        parameters = [initial_target, initial_strength, initial_temperature],
    )
    scheduled = mtkcompile(source)

    labels = zeros(Int, 8, 8)
    labels[3:5, 3:5] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (initial_marker => fill(1.0f0, 8, 8),),
    )
    labels .= 7
    @test all(
        getfield(getfield(initial, :ownership), :labels)[3:5, 3:5] .== 1
    )
    @test_throws ArgumentError PottsProblem(
        scheduled,
        initial,
        (0, 5);
        p = (initial_strength => 2.0,),
        seed = 4,
    )
    problem = PottsProblem(
        scheduled,
        initial,
        (0, 5);
        p = (
            initial_strength => 2.0,
            initial_temperature => 4.0,
        ),
        seed = 0x1234,
    )
    @test problem.seed == 0x1234
    @test problem.replica == 1

    # `problem.u0` is a public SciML property, but it must not expose the
    # frozen initialization recipe used by later `init` or ensemble runs.
    exposed_u0 = problem.u0
    fill!(exposed_u0.ownership.labels, Int32(0))
    fill!(last(only(exposed_u0.values)), -99.0f0)
    fresh_u0 = problem.u0
    @test count(==(Int32(1)), fresh_u0.ownership.labels) == 9
    @test all(==(1.0f0), last(only(fresh_u0.values)))
    fresh_u0.ownership.labels[3, 3] = 0
    @test problem.u0.ownership.labels[3, 3] == 1

    @test_throws UndefKeywordError PottsProblem(
        scheduled,
        initial,
        (0, 5);
        p = (
            initial_strength => 2.0,
            initial_temperature => 4.0,
        ),
    )
    @test_throws ArgumentError PottsProblem(
        scheduled,
        initial,
        (0.5, 5);
        p = (
            initial_strength => 2.0,
            initial_temperature => 4.0,
        ),
        seed = 1,
    )
    @test_throws ArgumentError PottsProblem(
        scheduled,
        initial,
        (0, 5);
        p = (
            initial_strength => 2.0,
            initial_temperature => 4.0,
        ),
        seed = 1,
        replica = 0,
    )

    remade = remake(problem; tspan = (2, 8), seed = 99, replica = 3)
    @test remade.tspan == (2, 8)
    @test remade.seed == 99
    @test remade.replica == 3
    @test remade.u0 !== problem.u0
    overlaid = remake(
        problem; u0 = Dict(initial_marker => fill(2.0f0, 8, 8))
    )
    overlaid_integrator = init(
        overlaid, SequentialCPM(); scalar_type = Float32, save_start = false
    )
    original_integrator = init(
        problem, SequentialCPM(); scalar_type = Float32, save_start = false
    )
    @test all(overlaid_integrator.u[:initial_marker] .== 2.0f0)
    @test all(original_integrator.u[:initial_marker] .== 1.0f0)
    @test count(==(Int32(1)), original_integrator.u.ownership) == 9
    @test_throws ArgumentError remake(problem; algorithm = :forbidden)

    layout = OwnershipLayout(
        (8, 8),
        CellPlacement(
            1,
            cell,
            ((3, 3), (3, 4), (4, 3), (4, 4)),
        );
        medium,
    )
    layout_problem = PottsProblem(
        scheduled,
        PottsInitialState(ownership = layout),
        (0, 1);
        p = (
            initial_strength => 2.0,
            initial_temperature => 4.0,
        ),
        seed = 2,
    )
    layout_integrator = init(
        layout_problem,
        SequentialCPM();
        scalar_type = Float32,
        save_start = false,
    )
    @test sum(layout_integrator.u.ownership .== 1) == 4
    labelled_equivalent = zeros(Int, 8, 8)
    labelled_equivalent[3:4, 3:4] .= 1
    labelled_problem = PottsProblem(
        scheduled,
        PottsInitialState(
            ownership = LabelledCells(
                labelled_equivalent; cells = [cell], medium
            ),
        ),
        (0, 1);
        p = (
            initial_strength => 2.0,
            initial_temperature => 4.0,
        ),
        seed = 2,
    )
    @test solve(
        layout_problem, SequentialCPM(); scalar_type = Float32
    )(1).ownership == solve(
        labelled_problem, SequentialCPM(); scalar_type = Float32
    )(1).ownership

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
        scheduled,
        PottsInitialState(ownership = procedural_layout),
        (0, 2);
        p = (
            initial_strength => 2.0,
            initial_temperature => 4.0,
        ),
        seed = 0xabc,
    )
    procedural_ownership = init(
        procedural_problem,
        SequentialCPM();
        scalar_type = Float32,
        save_start = false,
    ).u.ownership
    @test count(==(1), procedural_ownership) == 2
    @test count(==(2), procedural_ownership) == 2
    @test init(
        procedural_problem,
        SequentialCPM();
        scalar_type = Float32,
        save_start = false,
    ).u.ownership == procedural_ownership
    @test init(
        remake(procedural_problem; replica = 2),
        SequentialCPM();
        scalar_type = Float32,
        save_start = false,
    ).u.ownership != procedural_ownership
    explicit_equivalent = PottsProblem(
        scheduled,
        PottsInitialState(
            ownership = LabelledCells(
                procedural_ownership;
                cells = [cell, cell],
                medium,
            ),
            values = (initial_marker => fill(0.0f0, 8, 8),),
        ),
        (0, 2);
        p = (
            initial_strength => 2.0,
            initial_temperature => 4.0,
        ),
        seed = 0xabc,
    )
    procedural_run = solve(
        procedural_problem,
        SequentialCPM();
        scalar_type = Float32,
        save_everystep = true,
    )
    explicit_run = solve(
        explicit_equivalent,
        SequentialCPM();
        scalar_type = Float32,
        save_everystep = true,
    )
    @test getfield.(procedural_run.u, :ownership) ==
          getfield.(explicit_run.u, :ownership)
end

@testset "scheduled multiple-medium placement" begin
    cell = CellKind(:multiple_medium_cell; extinction = RetireAtZero())
    medium = MediumKind(:multiple_medium_bulk)
    border = MediumKind(:multiple_medium_border)
    scheduled = mtkcompile(PottsSystem(
        name = :multiple_medium_model,
        statements = StatementSet((
            Lattice((6, 6); boundary = Closed()),
            cell,
            medium,
            border,
            Volume(cell; target = 4.0, strength = 1.0),
            Protocol(Sweep(; temperature = 2.0); name = :main),
            Observation(:bulk_sites, occupancy(medium, :lattice)),
            Observation(:border_sites, occupancy(border, :lattice)),
        )),
    ))
    border_coordinates = Tuple(
        (row, column) for row in (1, 6) for column in 1:6
    )
    layout = OwnershipLayout(
        (6, 6),
        MediumPlacement(border, border_coordinates),
        CellPlacement(
            1,
            cell,
            ((3, 3), (3, 4), (4, 3), (4, 4)),
        );
        medium,
    )
    problem = PottsProblem(
        scheduled,
        PottsInitialState(ownership = layout),
        (0, 0);
        seed = 3,
    )
    integrator = init(
        problem,
        SequentialCPM();
        scalar_type = Float64,
        observables = (:bulk_sites, :border_sites),
    )
    @test integrator.u[:border_sites] == 12
    @test integrator.u[:bulk_sites] == 20
    @test length(unique(integrator.u.ownership)) == 3
end
