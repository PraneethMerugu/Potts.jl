using KernelAbstractions
using Unitful

@testset "Level 1 declarations and problem construction" begin
    medium = PottsToolkit.Medium(:extracellular)
    population_a = PottsToolkit.CellType(:population_a)
    population_b = PottsToolkit.CellType(:population_b)

    volume = PottsToolkit.Volume(
        population_a => (target = 4, strength = 2),
        population_b => (target = 4, strength = 2),
    )
    contact_energy = PottsToolkit.PairwiseLaw(
        :contact_energy,
        (medium, medium) => 0,
        (medium, population_a) => 8,
        (medium, population_b) => 8,
        (population_a, population_a) => 2,
        (population_b, population_b) => 2,
        (population_a, population_b) => 15;
        symmetric = true,
        missing = PottsToolkit.RejectMissingPairs(),
    )
    adhesion = PottsToolkit.Adhesion(contact_energy)
    level1 = PottsToolkit.PottsModel(
        population_b, adhesion, medium, volume, population_a)

    level2 = PottsToolkit.PottsModel(
        medium,
        population_a,
        population_b,
        PottsToolkit.VolumeConstraint(
            population_a => (target = 4, strength = 2),
            population_b => (target = 4, strength = 2),
        ),
        PottsToolkit.Adhesion(
            (medium, medium) => 0,
            (medium, population_a) => 8,
            (medium, population_b) => 8,
            (population_a, population_a) => 2,
            (population_b, population_b) => 2,
            (population_a, population_b) => 15;
            name = :contact_energy,
        ),
    )

    @test Base.isvalid(level1)
    @test PottsToolkit.semantic_fingerprint(level1) ==
          PottsToolkit.semantic_fingerprint(level2)
    @test sprint(show, volume) == "Volume(:volume)"

    defaulted = PottsToolkit.PairwiseLaw(
        :defaulted_contact, (population_a, population_a) => 2;
        missing = PottsToolkit.DefaultPairValue(0),
    )
    @test defaulted.default == 0.0f0

    @test_throws UndefKeywordError PottsToolkit.FluctuatingVolumePressure(
        population_a => (target = 4, strength = 2))
    pressure = PottsToolkit.FluctuatingVolumePressure(
        population_a => (target = 4, strength = 2);
        noise = PottsToolkit.IndependentNoise(1),
    )
    @test pressure.declaration.noise isa CorePotts.FixedMechanicalNoise
    @test PottsToolkit.AcceptanceTemperature() isa CorePotts.AlgorithmTemperatureNoise

    labels = UInt64[
        1 1 0 0
        1 1 0 0
        0 0 2 2
        0 0 2 2
    ]
    layout = PottsToolkit.Layout(PottsToolkit.LabelledCells(
        labels, (1 => population_a, 2 => population_b)))
    domain = PottsToolkit.CartesianDomain((4, 4);
        spacing = (1.0, 2.0), boundaries = (
            PottsToolkit.AxisBoundary(PottsToolkit.PeriodicBoundary()),
            PottsToolkit.AxisBoundary(PottsToolkit.ClosedBoundary()),
        ))
    prob = PottsToolkit.PottsProblem(level1, domain, layout;
        capacity = 4, tspan = (0, 1), seed = 42)

    @test prob isa CorePotts.PottsProblem
    @test prob.geometry === domain
    @test prob.seed == 42
    @test CorePotts.lattice_size(prob.u0) == (4, 4)
    @test CorePotts.compatibility_report(prob,
        CorePotts.SequentialCPM(temperature = 0.0f0),
        KernelAbstractions.CPU()).qualified
    solution = CorePotts.solve(prob,
        CorePotts.SequentialCPM(temperature = 0.0f0))
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test solution.t[end] == 1

    placed = PottsToolkit.Place(population_a, labels .== 1; identity = 1)
    @test placed isa PottsToolkit.CellLayout
    @test_throws ArgumentError PottsToolkit.Layout(:not_a_layout)
end

@testset "Level 1 Act façade canonical equivalence" begin
    neighborhood = CorePotts.static_relation(
        CorePotts.SpatialQueryRole(),
        CorePotts.MooreTopology{2}())
    algorithm = CorePotts.BudgetedSequentialCPM(
        CorePotts.AttemptsPerSite(16); temperature = 20.0f0)
    façade = PottsToolkit.Act(
        maximum_activity = 40.0f0,
        strength = 120.0f0,
        neighborhood = neighborhood,
        algorithm = algorithm,
        observation_every = 5)
    lowered = PottsToolkit.lower(façade)
    direct = CorePotts.ActivityProgram(
        maximum = 40.0f0,
        strength = 120.0f0,
        relation = neighborhood,
        algorithm = algorithm,
        observation_cadence = 5)
    @test CorePotts.canonical_coupled_model(façade) ==
        CorePotts.canonical_coupled_model(direct)
    @test CorePotts.semantic_model_fingerprint(
        CorePotts.canonical_coupled_model(façade)) ==
        CorePotts.semantic_model_fingerprint(
            CorePotts.canonical_coupled_model(direct))
    @test lowered.property.name == :activity
    @test lowered.hamiltonian.reduction isa CorePotts.GeometricActivity
    integer_parameters = PottsToolkit.Act(
        maximum_activity = 40,
        strength = 120,
        neighborhood = CorePotts.MooreTopology{2}())
    @test PottsToolkit.lower(integer_parameters).hamiltonian.maximum == 40.0
    @test PottsToolkit.lower(integer_parameters).hamiltonian.relation ==
          CorePotts.static_relation(
              CorePotts.SpatialQueryRole(), CorePotts.MooreTopology{2}())
    @test_throws ArgumentError PottsToolkit.Act(
        maximum_activity = 40,
        strength = 120,
        neighborhood = CorePotts.MooreTopology{2}(),
        spacing = (1.0,))
    @test_throws ArgumentError PottsToolkit.Act(
        maximum_activity = 40.0,
        strength = 120.0,
        neighborhood = neighborhood,
        algorithm = CorePotts.SequentialEquilibrium())
end

@testset "Level 1 addressed procedural layouts" begin
    medium = PottsToolkit.Medium(:layout_medium)
    cell = PottsToolkit.CellType(:layout_cell)
    model = PottsToolkit.PottsModel(
        medium, cell, PottsToolkit.Volume(cell => (target = 1, strength = 1)))
    domain = PottsToolkit.CartesianDomain((5, 5))

    seeds = PottsToolkit.UniformSiteSeeds(cell, 4;
        name = :initial_population, first_identity = 10)
    layout = PottsToolkit.Layout(seeds)
    seeded_a = PottsToolkit.PottsProblem(model, domain, layout;
        capacity = 4, tspan = (0, 1), seed = 0x1234)
    seeded_b = PottsToolkit.PottsProblem(model, domain, layout;
        capacity = 4, tspan = (0, 1), seed = 0x1234)
    seeded_c = PottsToolkit.PottsProblem(model, domain, layout;
        capacity = 4, tspan = (0, 1), seed = 0x1235)
    @test CorePotts.lattice_storage(seeded_a.u0) ==
          CorePotts.lattice_storage(seeded_b.u0)
    @test CorePotts.lattice_storage(seeded_a.u0) !=
          CorePotts.lattice_storage(seeded_c.u0)
    @test length(CorePotts.active_cell_ids(seeded_a.u0)) == 4
    @test all(id -> CorePotts.finite_volume(seeded_a.u0, id) == 1,
        CorePotts.active_cell_ids(seeded_a.u0))

    rejection = PottsToolkit.SequentialRejectionPlacement(
        cell, 3, PottsToolkit.LatticeBall(0.0f0);
        name = :bounded_population, first_identity = 20, attempt_limit = 256)
    rejected_a = PottsToolkit.PottsProblem(model, domain,
        PottsToolkit.Layout(rejection);
        capacity = 3, tspan = (0, 1), seed = 99)
    rejected_b = PottsToolkit.PottsProblem(model, domain,
        PottsToolkit.Layout(rejection);
        capacity = 3, tspan = (0, 1), seed = 99)
    @test CorePotts.lattice_storage(rejected_a.u0) ==
          CorePotts.lattice_storage(rejected_b.u0)
    @test length(CorePotts.active_cell_ids(rejected_a.u0)) == 3
    @test all(id -> CorePotts.finite_volume(rejected_a.u0, id) == 1,
        CorePotts.active_cell_ids(rejected_a.u0))

    one_center = falses(5, 5)
    one_center[3, 3] = true
    impossible = PottsToolkit.SequentialRejectionPlacement(
        cell, 2, PottsToolkit.LatticeBall(0.0f0);
        name = :impossible_population, eligible_centers = one_center,
        attempt_limit = 2)
    @test_throws CorePotts.InitialPlacementError PottsToolkit.PottsProblem(
        model, domain, PottsToolkit.Layout(impossible);
        capacity = 2, tspan = (0, 1), seed = 1)

    too_many = PottsToolkit.UniformSiteSeeds(cell, 26; name = :too_many)
    invalid = PottsToolkit.validate_problem(model, (5, 5), too_many;
        capacity = 2)
    @test any(item -> item.code === :insufficient_layout_eligibility, invalid)
    @test any(item -> item.code === :initial_capacity_exceeded, invalid)

    explicit = PottsToolkit.Place(cell, trues(5, 5); identity = 11)
    duplicate = PottsToolkit.validate_problem(model, (5, 5), seeds, explicit;
        capacity = 5)
    @test any(item -> item.code === :duplicate_provisional_cell_id, duplicate)

    duplicate_name = PottsToolkit.UniformSiteSeeds(cell, 1;
        name = :initial_population, first_identity = 30)
    duplicate_identity = PottsToolkit.validate_problem(
        model, (5, 5), seeds, duplicate_name; capacity = 5)
    @test any(item -> item.code === :duplicate_layout_identity, duplicate_identity)

    forced_collision = PottsToolkit.UniformSiteSeedLayout(
        PottsToolkit.SemanticName(:forced_collision), cell, UInt32(1), UInt64(40),
        nothing, seeds.operation, Int32(0))
    collision = PottsToolkit.validate_problem(
        model, (5, 5), seeds, forced_collision; capacity = 5)
    @test any(item -> item.code === :layout_rng_identity_collision, collision)

    wrong_box = PottsToolkit.SequentialRejectionPlacement(
        cell, 1, PottsToolkit.LatticeBox((0, 0, 0));
        name = :wrong_box, attempt_limit = 1)
    wrong_box_report = PottsToolkit.validate_problem(
        model, (5, 5), wrong_box; capacity = 1)
    @test any(item -> item.code === :layout_dimension_mismatch, wrong_box_report)
end

@testset "Level 1 scientific observations" begin
    medium = PottsToolkit.Medium(:observation_medium)
    cell = PottsToolkit.CellType(:observed_cell)
    age = PottsToolkit.CellProperty(:observed_age, cell; initial = 2.0f0,
        division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    volume_component = PottsToolkit.Volume(cell => (target = 1, strength = 1))
    volumes = PottsToolkit.CellVolume()
    cell_types = PottsToolkit.CellTypeObservable()
    boundaries = PottsToolkit.CellBoundaryMeasure()
    ages = PottsToolkit.CellPropertyValues(age; name = :age)
    ownership = PottsToolkit.LatticeOwnership()
    set = PottsToolkit.ObservationSet(volumes, cell_types, boundaries, ages, ownership)
    model = PottsToolkit.PottsModel(medium, cell, age, volume_component,
        volumes, cell_types, boundaries, ages, ownership)

    mask = falses(3, 3)
    mask[2, 2] = true
    problem = PottsToolkit.PottsProblem(
        model, PottsToolkit.CartesianDomain((3, 3)),
        PottsToolkit.Layout(PottsToolkit.Place(cell, mask; identity = 1));
        capacity = 2, tspan = (0, 1), seed = 3)
    @test Set(CorePotts.observable_symbols(problem.model)) ==
          Set((:volume, :cell_type, :boundary_measure, :age, :ownership))
    solution = CorePotts.solve(problem,
        CorePotts.SequentialCPM(temperature = 0.0f0);
        snapshot_policy = PottsToolkit.observation_policy(set))
    volume_series = PottsToolkit.observe(solution, volumes)
    @test length(volume_series) == length(solution.t)
    @test only(volume_series.frames[1].values).value == 1
    @test length(solution[CorePotts.PottsObservableHandle(:age)]) ==
          length(solution.t)
    ownership_series = PottsToolkit.observe(solution, ownership)
    @test length(ownership_series) == length(solution.t)
    first_spatial = first(ownership_series)
    @test PottsToolkit.spatial_mcs(first_spatial) ==
          CorePotts.snapshot_mcs(solution[firstindex(solution)])
    ownership_values = PottsToolkit.spatial_values(first_spatial)
    observed_cell = only(PottsToolkit.ownership_cells(ownership_values))
    @test PottsToolkit.observed_cell_id(observed_cell) == CorePotts.CellID(1)
    @test PottsToolkit.observed_cell_generation(observed_cell) ==
          CorePotts.CellGeneration(0)
    @test PottsToolkit.observed_cell_type(observed_cell) == CorePotts.CellTypeID(1)
    @test PottsToolkit.ownership_size(ownership_values) == (3, 3)
    @test PottsToolkit.ownership_owner_at(
        ownership_values, CartesianIndex(2, 2)) == CorePotts.CellOwner(1)
    table = PottsToolkit.observation_table(solution, volumes, ages)
    @test !isempty(table)
    @test all(row -> hasproperty(row, :mcs) && hasproperty(row, :generation) &&
        hasproperty(row, :volume) && hasproperty(row, :age), table)

    host_solution = CorePotts.solve(problem,
        CorePotts.SequentialCPM(temperature = 0.0f0);
        snapshot_policy = CorePotts.HostSnapshotPolicy())
    @test length(PottsToolkit.observe(host_solution, boundaries)) ==
          length(host_solution.t)
    @test length(PottsToolkit.observe(host_solution, ownership)) ==
          length(host_solution.t)
    @test_throws ArgumentError PottsToolkit.observation_table(
        host_solution, ownership)

    model_fingerprint = PottsToolkit.semantic_fingerprint(model)
    scale = PottsToolkit.PhysicalScale(
        lattice_spacing = (0.5 * Unitful.μm, 0.5 * Unitful.μm),
        mcs_duration = 2 * Unitful.s,
        method = "explicit test calibration")
    physical = PottsToolkit.with_units(host_solution, scale)
    @test parent(physical) === host_solution
    @test PottsToolkit.mcs(physical) == host_solution.t
    @test physical.t == host_solution.t .* (2 * Unitful.s)
    physical_volumes = PottsToolkit.observe(physical, volumes)
    @test Unitful.dimension(only(physical_volumes.frames[1].values).value) ==
          Unitful.dimension(Unitful.μm^2)
    physical_table = PottsToolkit.observation_table(physical, volumes)
    @test hasproperty(first(physical_table), :physical_time)
    @test PottsToolkit.semantic_fingerprint(model) == model_fingerprint
end

@testset "Level 1 reusable field binding" begin
    medium = PottsToolkit.Medium(:field_medium)
    cell = PottsToolkit.CellType(:chemotactic_cell)
    volume = PottsToolkit.Volume(cell => (target = 4, strength = 2))
    chemo = PottsToolkit.Field(:chemo;
        placement = PottsToolkit.CellCentered(),
        boundary = PottsToolkit.NoFlux(),
        interpolation = PottsToolkit.Multilinear())
    drive = PottsToolkit.Chemotaxis(chemo, cell => 2.0)
    model = PottsToolkit.PottsModel(medium, cell, volume, chemo, drive)

    @test Base.isvalid(model)
    fingerprint = PottsToolkit.semantic_fingerprint(model)
    @test fingerprint == PottsToolkit.semantic_fingerprint(model)

    mask = falses(4, 4)
    mask[2:3, 2:3] .= true
    domain = PottsToolkit.CartesianDomain((4, 4))
    layout = PottsToolkit.Layout(PottsToolkit.Place(cell, mask; identity = 1))
    profile = map(site -> Float32(site[1] / 4), CartesianIndices((4, 4)))
    problem = PottsToolkit.PottsProblem(model, domain, layout;
        fields = (chemo => profile,), capacity = 2, tspan = (0, 1), seed = 4)
    @test problem isa CorePotts.PottsProblem
    realized = CorePotts.realize_components(
        problem.model, CorePotts.default_parameters(problem.model))
    @test length(realized.drives) == 1
    @test CorePotts.solve(problem,
        CorePotts.SequentialCPM(temperature = 1.0f0)).retcode ==
        SciMLBase.ReturnCode.Success
    @test_throws ArgumentError PottsToolkit.PottsProblem(
        model, domain, layout; capacity = 2)
    @test_throws ArgumentError PottsToolkit.PottsProblem(
        PottsToolkit.PottsModel(medium, cell, volume), domain, layout;
        fields = (chemo => profile,), capacity = 2)

    nearest = PottsToolkit.Field(:nearest_chemo;
        boundary = (PottsToolkit.FixedValue(0.0f0), PottsToolkit.PeriodicField()),
        interpolation = PottsToolkit.Nearest())
    nearest_drive = PottsToolkit.Chemotaxis(nearest, cell => 1.0f0;
        response = PottsToolkit.MichaelisMentenResponse(1.0f0),
        mode = PottsToolkit.RetractionChemotaxis())
    nearest_model = PottsToolkit.PottsModel(
        medium, cell, volume, nearest, nearest_drive)
    nearest_problem = PottsToolkit.PottsProblem(nearest_model, domain, layout;
        fields = (nearest => profile,), capacity = 2, tspan = (0, 1), seed = 5)
    nearest_components = CorePotts.realize_components(
        nearest_problem.model, CorePotts.default_parameters(nearest_problem.model))
    @test only(nearest_components.drives).field.interpolation isa
          CorePotts.NearestFieldInterpolation
    unsafe_boundary = PottsToolkit.Field(:unsafe_boundary;
        boundary = PottsToolkit.FixedValue(0.0))
    unsafe_boundary_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell, volume, unsafe_boundary))
    @test any(item -> item.code === :unsafe_field_boundary_conversion,
        unsafe_boundary_report)
    @test PottsToolkit.SequentialCPM === CorePotts.SequentialCPM
    @test PottsToolkit.CheckerboardSweepCPM === CorePotts.CheckerboardSweepCPM
    @test PottsToolkit.LotteryCPM === CorePotts.LotteryCPM
end

@testset "Level 1 phases, closed rules, and triggers" begin
    cell_type = PottsToolkit.CellType(:rule_cell)
    medium = PottsToolkit.Medium(:rule_medium)
    age = PottsToolkit.CellProperty(:age, cell_type; initial = 0.0f0,
        division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    target = PottsToolkit.CellProperty(:target, cell_type; initial = 2.0f0,
        division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())

    mechanics = PottsToolkit.Phase(:mechanics)
    growth_phase = PottsToolkit.Phase(:growth; after = mechanics)
    @test PottsToolkit.semantic_identity(growth_phase) ==
          PottsToolkit.SemanticName(:growth)
    @test growth_phase.after == (PottsToolkit.SemanticName(:mechanics),)
    @test_throws ArgumentError PottsToolkit.Phase(:bad;
        after = (mechanics, mechanics))

    growth = PottsToolkit.@rule phase = growth_phase age(cell) = age(cell) + 1.0f0
    @test growth isa PottsToolkit.Rule
    @test growth.phase === growth_phase
    @test growth.source isa PottsToolkit.SourceLocation
    @test PottsToolkit.evaluate(growth, (age = 2.0f0,)) == 3.0f0
    owner = PottsToolkit.OwnerReference(:cell)
    programmatic_growth = PottsToolkit.Rule(age, :cell, age(owner) + 1.0f0;
        phase = growth_phase)
    macro_model = PottsToolkit.PottsModel(medium, cell_type, age, growth)
    programmatic_model = PottsToolkit.PottsModel(
        medium, cell_type, age, programmatic_growth)
    @test PottsToolkit.semantic_fingerprint(macro_model) ==
          PottsToolkit.semantic_fingerprint(programmatic_model)

    mask = trues(3, 3)
    growth_problem = PottsToolkit.PottsProblem(
        macro_model, PottsToolkit.CartesianDomain((3, 3)),
        PottsToolkit.Layout(PottsToolkit.Place(cell_type, mask; identity = 1));
        capacity = 1, tspan = (0, 1), seed = 7)
    growth_solution = CorePotts.solve(growth_problem,
        CorePotts.SequentialCPM(temperature = 0.0f0);
        snapshot_policy = CorePotts.HostSnapshotPolicy())
    @test CorePotts.property_value(growth_solution.u[end].state,
        :age, CorePotts.CellID(1)) == 1.0f0

    growth_rate = PottsToolkit.CellParameter(:growth_rate, cell_type => 0.5f0)
    global_rate = PottsToolkit.ModelParameter(:global_rate, 0.25f0)
    typed_growth = PottsToolkit.@rule phase = growth_phase age(cell) =
        age(cell) + growth_rate(cell)
    global_growth = PottsToolkit.@rule phase = growth_phase target(cell) =
        target(cell) + global_rate(cell)
    parameter_model = PottsToolkit.PottsModel(medium, cell_type, age, target,
        growth_rate, global_rate, typed_growth, global_growth)
    @test Base.isvalid(parameter_model)
    @test length(CorePotts.lifecycle_events(
        PottsToolkit.lower(parameter_model; dimensions = 2).core_model)) == 1
    @test PottsToolkit.evaluate(typed_growth,
        (age = 2.0, growth_rate = 0.5)) == 2.5

    narrowing = PottsToolkit.@rule phase = growth_phase age(cell) = age(cell) + 1.0
    narrowing_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, age, narrowing))
    @test any(diagnostic -> diagnostic.code === :unsafe_rule_output_conversion,
        narrowing_report)
    integer_state = PottsToolkit.CellProperty(:integer_state, cell_type;
        initial = Int64(0), division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    exact_integer = PottsToolkit.Rule(integer_state, :cell, Int32(2);
        phase = growth_phase)
    @test Base.isvalid(PottsToolkit.PottsModel(
        medium, cell_type, integer_state, exact_integer))
    rounded_integer = PottsToolkit.Rule(integer_state, :cell, 2.0f0;
        phase = growth_phase, name = :rounded_integer)
    rounded_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, integer_state, rounded_integer))
    @test any(diagnostic -> diagnostic.code === :unsafe_rule_output_conversion,
        rounded_report)

    stochastic = PottsToolkit.@rule phase = growth_phase age(cell) =
        age(cell) + draw(Bernoulli(1.0); label = :aging_draw)
    @test stochastic.expression.arguments[2] isa PottsToolkit.RandomDraw
    stochastic_model = PottsToolkit.PottsModel(
        medium, cell_type, age, stochastic)
    @test Base.isvalid(stochastic_model)
    stochastic_problem = PottsToolkit.PottsProblem(
        stochastic_model, PottsToolkit.CartesianDomain((3, 3)),
        PottsToolkit.Layout(PottsToolkit.Place(
            cell_type, trues(3, 3); identity = 1));
        capacity = 1, tspan = (0, 1), seed = 9)
    stochastic_solution = CorePotts.solve(stochastic_problem,
        CorePotts.SequentialCPM(temperature = 0.0f0);
        snapshot_policy = CorePotts.HostSnapshotPolicy())
    @test CorePotts.property_value(stochastic_solution.u[end].state,
        :age, CorePotts.CellID(1)) == 1.0f0

    duplicate_draws = PottsToolkit.@rule phase = growth_phase age(cell) =
        age(cell) + draw(Bernoulli(0.5); label = :same) +
        draw(Bernoulli(0.5); label = :same)
    duplicate_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, age, duplicate_draws))
    @test any(diagnostic -> diagnostic.code === :duplicate_random_draw_label &&
        diagnostic.source isa PottsToolkit.SourceLocation, duplicate_report)

    invalid_draw = PottsToolkit.@rule phase = growth_phase age(cell) =
        age(cell) + draw(Bernoulli(1.5); label = :invalid_probability)
    invalid_draw_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, age, invalid_draw))
    @test any(diagnostic -> diagnostic.code === :invalid_distribution_parameter,
        invalid_draw_report)
    invalid_uniform = PottsToolkit.@rule phase = growth_phase age(cell) =
        draw(Uniform(2.0, 1.0); label = :invalid_uniform)
    invalid_normal = PottsToolkit.@rule phase = growth_phase age(cell) =
        draw(Normal(0.0, 0.0); label = :invalid_normal)
    for invalid_rule in (invalid_uniform, invalid_normal)
        report = PottsToolkit.validate(PottsToolkit.PottsModel(
            medium, cell_type, age, invalid_rule))
        @test any(diagnostic ->
            diagnostic.code === :invalid_distribution_parameter, report)
    end

    invalid_arity = PottsToolkit.Rule(age, :cell,
        PottsToolkit.ScalarCall(PottsToolkit.Authoring.AddOperation(),
            (PottsToolkit.RuleLiteral(1),)); phase = growth_phase,
        name = :invalid_arity)
    invalid_arity_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, age, invalid_arity))
    @test any(diagnostic -> diagnostic.code === :invalid_scalar_operation_arity,
        invalid_arity_report)

    second_cell_type = PottsToolkit.CellType(:second_cell_type)
    shared_age = PottsToolkit.CellProperty(:shared_age, cell_type, second_cell_type;
        initial = 0.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    partial_rate = PottsToolkit.CellParameter(:partial_rate, cell_type => 0.5)
    incomplete_binding = PottsToolkit.@rule phase = growth_phase shared_age(cell) =
        shared_age(cell) + partial_rate(cell)
    incomplete_binding_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, second_cell_type, shared_age, partial_rate,
        incomplete_binding))
    @test any(diagnostic -> diagnostic.code === :missing_cell_parameter_binding,
        incomplete_binding_report)

    operation_owners = Dict{UInt16, Symbol}()
    collision = nothing
    for index in 1:4096
        name = Symbol(:rng_collision_rule_, index)
        operation = UInt16(PottsToolkit.Authoring._semantic_rng_code(
            PottsToolkit.SemanticName(name), :collision, UInt16(0x03ff)))
        if haskey(operation_owners, operation)
            collision = (operation_owners[operation], name)
            break
        end
        operation_owners[operation] = name
    end
    first_name, second_name = something(collision)
    collision_draw = PottsToolkit.draw(PottsToolkit.Bernoulli(0.5);
        label = :collision)
    first_collision_rule = PottsToolkit.Rule(age, :cell, collision_draw;
        phase = growth_phase, name = first_name)
    second_collision_rule = PottsToolkit.Rule(target, :cell, collision_draw;
        phase = growth_phase, name = second_name)
    collision_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, age, target,
        first_collision_rule, second_collision_rule))
    @test any(diagnostic ->
        diagnostic.code === :random_draw_rng_identity_collision,
        collision_report)
    @test PottsToolkit.draw(PottsToolkit.UnitVector(2);
        label = :polarity) isa PottsToolkit.RandomDraw

    bounded = PottsToolkit.@rule phase = growth_phase target(cell) =
        if age(cell) >= 5
            max(target(cell) - 1, 0)
        else
            target(cell)
        end
    @test PottsToolkit.evaluate(bounded, (age = 6, target = 2)) == 1
    @test PottsToolkit.evaluate(bounded, (age = 1, target = 2)) == 2

    simultaneous = PottsToolkit.@rules phase = growth_phase begin
        age(cell) = age(cell) + 1
        target(cell) = age(cell) + 2
    end
    @test simultaneous isa PottsToolkit.RuleGroup
    @test length(simultaneous.rules) == 2
    @test PottsToolkit.evaluate(simultaneous.rules[1], (age = 3, target = 4)) == 4
    @test PottsToolkit.evaluate(simultaneous.rules[2], (age = 3, target = 4)) == 5
    @test_throws ArgumentError PottsToolkit.RuleGroup(
        (simultaneous.rules[1], simultaneous.rules[1]))

    simultaneous_model = PottsToolkit.PottsModel(
        medium, cell_type, age, target, simultaneous)
    simultaneous_problem = PottsToolkit.PottsProblem(
        simultaneous_model, PottsToolkit.CartesianDomain((3, 3)),
        PottsToolkit.Layout(PottsToolkit.Place(
            cell_type, trues(3, 3); identity = 1));
        capacity = 1, tspan = (0, 1), seed = 1)
    simultaneous_solution = CorePotts.solve(simultaneous_problem,
        CorePotts.SequentialCPM(temperature = 0.0f0);
        snapshot_policy = CorePotts.HostSnapshotPolicy())
    simultaneous_state = simultaneous_solution.u[end].state
    @test CorePotts.property_value(simultaneous_state,
        :age, CorePotts.CellID(1)) == 1.0f0
    @test CorePotts.property_value(simultaneous_state,
        :target, CorePotts.CellID(1)) == 2.0f0

    dependent_phase = PottsToolkit.Phase(:dependent; after = growth_phase)
    first_ordered = PottsToolkit.@rule phase = growth_phase age(cell) = age(cell) + 1
    second_ordered = PottsToolkit.@rule phase = dependent_phase target(cell) = age(cell) + 2
    ordered_model = PottsToolkit.PottsModel(
        medium, cell_type, age, target, first_ordered, second_ordered)
    ordered_problem = PottsToolkit.PottsProblem(
        ordered_model, PottsToolkit.CartesianDomain((3, 3)),
        PottsToolkit.Layout(PottsToolkit.Place(
            cell_type, trues(3, 3); identity = 1));
        capacity = 1, tspan = (0, 1), seed = 1)
    ordered_solution = CorePotts.solve(ordered_problem,
        CorePotts.SequentialCPM(temperature = 0.0f0);
        snapshot_policy = CorePotts.HostSnapshotPolicy())
    ordered_state = ordered_solution.u[end].state
    @test CorePotts.property_value(ordered_state,
        :target, CorePotts.CellID(1)) == 3.0f0

    contact_edges = PottsToolkit.CellProperty(:contact_edges, cell_type;
        initial = Int64(0), division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    contact_weight = PottsToolkit.CellProperty(:contact_weight, cell_type;
        initial = 0.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    boundary_sites = PottsToolkit.CellProperty(:boundary_sites, cell_type;
        initial = Int64(0), division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    neighbor_count = PottsToolkit.CellProperty(:neighbor_count, cell_type;
        initial = Int64(0), division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    neighbor_signal = PottsToolkit.CellProperty(:neighbor_signal, cell_type;
        initial = 5.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    neighbor_sum = PottsToolkit.CellProperty(:neighbor_sum, cell_type;
        initial = 0.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    neighbor_mean = PottsToolkit.CellProperty(:neighbor_mean, cell_type;
        initial = 0.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    contact_rules = PottsToolkit.@rules phase = growth_phase begin
        contact_edges(cell) = contact_edge_count(
            cell, Contacting(), AnyFiniteCell())
        contact_weight(cell) = contact_measure(
            cell, Contacting(), CellTypeFilter(cell_type))
        boundary_sites(cell) = boundary_site_count(
            cell, Contacting(), AnyFiniteCell())
        neighbor_count(cell) = neighbor_cell_count(
            cell, Contacting(), AnyFiniteCell())
        neighbor_sum(cell) = neighbor_property_sum(
            neighbor_signal, cell, Contacting(), AnyFiniteCell())
        neighbor_mean(cell) = neighbor_property_mean(
            neighbor_signal, cell, Contacting(), AnyFiniteCell(); empty = 0.0f0)
    end
    query_model = PottsToolkit.PottsModel(
        medium, cell_type, contact_edges, contact_weight, boundary_sites,
        neighbor_count, neighbor_signal, neighbor_sum, neighbor_mean, contact_rules)
    query_labels = UInt64[
        1 1 2 2
        1 1 2 2
        0 0 0 0
        0 0 0 0
    ]
    query_domain = PottsToolkit.CartesianDomain((4, 4); boundaries = (
        PottsToolkit.AxisBoundary(PottsToolkit.ClosedBoundary()),
        PottsToolkit.AxisBoundary(PottsToolkit.ClosedBoundary())))
    query_problem = PottsToolkit.PottsProblem(
        query_model, query_domain,
        PottsToolkit.Layout(PottsToolkit.LabelledCells(
            query_labels, (1 => cell_type, 2 => cell_type)));
        capacity = 2, tspan = (0, 1), seed = 3)
    query_solution = CorePotts.solve(query_problem,
        CorePotts.SequentialCPM(temperature = 0.0f0);
        snapshot_policy = CorePotts.HostSnapshotPolicy())
    query_state = query_solution.u[end].state
    query_relation = CorePotts.first_shell_relation(
        CorePotts.SpatialQueryRole(), Val(2); spacing = query_domain.spacing)
    query_medium_types = CorePotts.MediumTypeTable(
        CorePotts.MediumID(1) => CorePotts.CellTypeID(2))
    for id in (CorePotts.CellID(1), CorePotts.CellID(2))
        owner = CorePotts.CellOwner(id)
        expected_edges = CorePotts.contact_edge_count(query_state, query_domain,
            query_relation, owner, CorePotts.AnyFiniteCell(), query_medium_types)
        expected_measure = CorePotts.contact_measure(query_state, query_domain,
            query_relation, owner, CorePotts.CellTypeFilter(CorePotts.CellTypeID(1)),
            query_medium_types)
        expected_boundary_sites = CorePotts.boundary_site_count(
            query_state, query_domain, query_relation, owner,
            CorePotts.AnyFiniteCell(), query_medium_types)
        expected_neighbor_count = CorePotts.neighbor_cell_count(
            query_state, query_domain, query_relation, owner,
            CorePotts.AnyFiniteCell(), query_medium_types)
        expected_neighbor_sum = CorePotts.neighbor_property_sum(
            query_state, CorePotts.CellPropertyRef(:neighbor_signal),
            query_domain, query_relation, owner,
            CorePotts.AnyFiniteCell(), query_medium_types)
        expected_neighbor_mean = CorePotts.neighbor_property_mean(
            query_state, CorePotts.CellPropertyRef(:neighbor_signal),
            query_domain, query_relation, owner,
            CorePotts.AnyFiniteCell(), query_medium_types; empty = 0.0f0)
        @test CorePotts.property_value(query_state, :contact_edges, id) == expected_edges
        @test CorePotts.property_value(query_state, :contact_weight, id) == expected_measure
        @test CorePotts.property_value(query_state, :boundary_sites, id) ==
            expected_boundary_sites
        @test CorePotts.property_value(query_state, :neighbor_count, id) ==
            expected_neighbor_count == 1
        @test CorePotts.property_value(query_state, :neighbor_sum, id) ==
            expected_neighbor_sum == 5.0f0
        @test CorePotts.property_value(query_state, :neighbor_mean, id) ==
            expected_neighbor_mean == 5.0f0
    end

    owner_reference = PottsToolkit.OwnerReference(:cell)
    @test_throws UndefKeywordError PottsToolkit.neighbor_property_mean(
        neighbor_signal, owner_reference, PottsToolkit.Contacting(),
        PottsToolkit.AnyFiniteCell())
    other_type = PottsToolkit.CellType(:query_other_type)
    scoped_signal = PottsToolkit.CellProperty(:scoped_signal, cell_type;
        initial = 1.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    unsafe_sum = PottsToolkit.Rule(neighbor_sum, :cell,
        PottsToolkit.neighbor_property_sum(scoped_signal, owner_reference,
            PottsToolkit.Contacting(), PottsToolkit.AnyFiniteCell());
        phase = growth_phase, name = :unsafe_neighbor_sum)
    unsafe_query_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, other_type, scoped_signal, neighbor_sum, unsafe_sum))
    @test any(diagnostic -> diagnostic.code === :query_property_scope_mismatch,
        unsafe_query_report)

    unordered_phase = PottsToolkit.Phase(:unordered)
    unordered_rule = PottsToolkit.@rule phase = unordered_phase target(cell) = age(cell) + 2
    unordered_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, age, target, first_ordered, unordered_rule))
    @test any(diagnostic -> diagnostic.code === :unordered_phase_dependency,
        unordered_report)

    unchanged = PottsToolkit.@rule phase = growth_phase age(cell) = NoChange()
    @test PottsToolkit.evaluate(unchanged, (age = 2,)) isa PottsToolkit.NoChange

    ready = PottsToolkit.@trigger ready_to_retire(cell) = age(cell) >= 10
    @test ready isa PottsToolkit.TriggerRule
    @test PottsToolkit.evaluate(ready, (age = 10,))
    death = PottsToolkit.ImmediateDeath(cell_type; medium, trigger = ready,
        schedule = PottsToolkit.AtMCS(10))
    @test death.trigger isa CorePotts.PropertyAtLeast
    @test CorePotts.is_due(death.schedule, 10)
    @test CorePotts.is_due(PottsToolkit.EveryMCS(5; start = 5), 10)
    @test !CorePotts.is_due(PottsToolkit.BetweenMCS(3, 9; every = 3), 10)
    @test_throws ArgumentError PottsToolkit.AtMCS(0)

    syntax_error = try
        macroexpand(@__MODULE__, :(
            PottsToolkit.@rule phase = growth_phase age(cell) = begin
                x = age(cell)
                x + 1
            end))
        nothing
    catch error
        error
    end
    @test syntax_error isa ArgumentError

    first_cycle = PottsToolkit.Phase(:first_cycle;
        after = PottsToolkit.Phase(:second_cycle))
    second_cycle = PottsToolkit.Phase(:second_cycle;
        after = PottsToolkit.Phase(:first_cycle))
    cycle_age = PottsToolkit.@rule phase = first_cycle age(cell) = age(cell) + 1
    cycle_target = PottsToolkit.@rule phase = second_cycle target(cell) = target(cell) + 1
    cycle_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, cell_type, age, target, cycle_age, cycle_target))
    @test any(diagnostic -> diagnostic.code === :phase_dependency_cycle,
        cycle_report)
end
