@testset "authored draw identities survive unrelated source edits" begin
    cell = CellKind(:random_cell; extinction = RetireAtZero())
    medium = MediumKind(:random_medium)
    drive(name, key; distribution = Uniform()) =
        ProposalDrive(name, draw(distribution, DrawKey(key)))
    first_draw = drive(:first_drive, :first_noise)
    second_draw = drive(:second_drive, :second_noise)
    source(statements; systems = []) = PottsSystem(
        name = :addressed_model,
        statements = StatementSet(
            (
                Lattice((3, 3)), cell, medium, statements...,
                Protocol(Sweep(); name = :main),
            )
        ), systems = systems,
    )
    handles(system) = Potts._draw_operation_handles(
        Potts._analyze_completed_system(mtkcompile(system))
    )
    baseline = handles(source((first_draw, second_draw)))
    reordered = handles(source((second_draw, first_draw)))
    extended = handles(
        source(
            (
                drive(:unrelated_drive, :unrelated_noise), first_draw, second_draw,
            )
        )
    )
    changed_distribution = handles(
        source(
            (
                drive(:first_drive, :first_noise; distribution = Normal(4.0, 2.0)),
                second_draw,
            )
        )
    )
    @test baseline == reordered == changed_distribution
    @test all(extended[key] == value for (key, value) in baseline)
    @test all(!iszero, values(baseline))
    @test length(unique(values(baseline))) == 2

    renamed_process = handles(source((drive(:renamed_drive, :first_noise), second_draw)))
    key = ((:addressed_model,), :first_noise)
    @test renamed_process[key] != baseline[key]
    @variables stored_noise
    accepted_draw = handles(
        source(
            (
                SiteState(stored_noise; initial = 0.0),
                AcceptedCopy(:first_drive, Assign(stored_noise, draw(Uniform(), DrawKey(:first_noise)))),
            )
        )
    )
    @test accepted_draw[key] != baseline[key]
    child(name) = PottsSystem(; name, statements = StatementSet((first_draw,)))
    nested = handles(source((); systems = [child(:left), child(:right)]))
    @test nested[((:addressed_model, :left), :first_noise)] !=
        nested[((:addressed_model, :right), :first_noise)]

    many = handles(
        source(
            Tuple(
                drive(Symbol(:drive_, index), Symbol(:noise_, index)) for index in 1:512
            )
        )
    )
    @test length(unique(values(many))) == 512

    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell], medium))
    problem = PottsProblem(source((first_draw, second_draw)), initial, (0, 3); seed = 0xa291)
    for scalar_type in (Float32, Float64)
        run = solve(problem, SequentialCPM(); scalar_type)
        reordered_run = solve(
            PottsProblem(source((second_draw, first_draw)), initial, (0, 3); seed = problem.seed),
            SequentialCPM(); scalar_type,
        )
        @test run.retcode == SciMLBase.ReturnCode.Success
        @test getfield.(run.u, :ownership) == getfield.(reordered_run.u, :ownership)
        integrator = init(problem, SequentialCPM(); scalar_type)
        step!(integrator)
        resumed = init(problem, SequentialCPM(); scalar_type, checkpoint = checkpoint(integrator))
        step!(integrator)
        step!(resumed)
        @test integrator.u.ownership == resumed.u.ownership
    end
end

@testset "named procedural initialization retains trajectory identity" begin
    cell = CellKind(:seed_cell; extinction = RetireAtZero())
    medium = MediumKind(:seed_medium)
    system = PottsSystem(
        name = :named_seeding,
        statements = StatementSet(
            (
                Lattice((8, 8)), cell, medium,
                Protocol(Sweep(); name = :main),
            )
        ),
    )
    first = RandomSitePlacement(:first, cell; count = 1, sites_per_cell = 5)
    second = RandomSitePlacement(:second, cell; count = 1, sites_per_cell = 5, first_label = 2)
    problem(placements; seed = UInt64(0x8f12), replica = 1, repeat = 1) = PottsProblem(
        system,
        PottsInitialState(ownership = OwnershipLayout((8, 8), placements...; medium)),
        (0, 1); seed, replica, repeat,
    )
    ownership(problem) = init(problem, SequentialCPM(); save_start = false).u.ownership
    baseline = ownership(problem((first, second)))
    @test baseline == ownership(problem((second, first)))
    @test baseline == ownership(problem((first, second)))
    @test count(==(1), baseline) == count(==(2), baseline) == 5
    @test baseline != ownership(problem((first, second); replica = 2))
    @test baseline != ownership(problem((first, second); repeat = 2))
    @test baseline != ownership(problem((first, second); seed = UInt64(0x8f12) | (UInt64(1) << 63)))
    full = RandomSitePlacement(:full, cell; count = 1, sites_per_cell = 64)
    @test ownership(problem((full,))) == ones(Int32, 8, 8)
end

@testset "lifecycle draws share ordinary source identity validation" begin
    cell = CellKind(:draw_cell; extinction = RetireAtZero())
    medium = MediumKind(:draw_medium)
    relation = SpatialRelation(:draw_relation; neighborhood = VonNeumann())
    anchor = CellBinding(:dividing_cell)
    divide(key, side_key) = LifecycleProcess(
        :random_division; domain = cells(cell), anchor, expression = true,
        effects = (
            Divide(
                anchor; geometry = RandomPlane(draw = key), relation,
                side = StableRandomSide(side_key), on_inadmissible = ErrorOnInadmissible(),
            ),
        ), cadence = AtMCS(1),
    )
    source(process; extra = ()) = PottsSystem(
        name = :lifecycle_draw_identity,
        statements = StatementSet(
            (
                Lattice((3, 3); max_cells = 2), cell, medium, relation,
                process, extra..., Protocol(Sweep(); name = :main),
            )
        ),
    )
    completed = complete(source(divide(:geometry, :side)))
    operations = Tuple(Iterators.flatten(last.(inspect(completed, RandomOperations()))))
    @test count(operation -> !operation.reserved, operations) == 2
    @test any(
        operation -> operation.identity == :geometry &&
            operation.family == :division_geometry, operations
    )
    @test any(
        operation -> operation.identity == :side &&
            operation.family == :division_side, operations
    )
    for invalid in (
            source(divide(:shared, :shared)),
            source(
                divide(:geometry, :side); extra = (
                    ProposalDrive(:noise, draw(Uniform(), DrawKey(:geometry))),
                )
            ),
        )
        error = try
            complete(invalid)
            nothing
        catch caught
            caught
        end
        @test error isa Potts.PottsValidationError
        @test any(diagnostic -> diagnostic.kind == :duplicate_draw_key, error.diagnostics)
    end
end
