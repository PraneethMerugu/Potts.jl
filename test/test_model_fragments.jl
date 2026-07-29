using SciMLBase

@testset "model authoring typed fragment roles" begin
    migrating = PottsToolkit.CellRole(:migrating_cells)
    signal = PottsToolkit.FieldRole(:signal_field)
    volume = PottsToolkit.Volume(
        migrating => (target = 4, strength = 2.0f0))
    adhesion = PottsToolkit.Adhesion(
        (migrating, migrating) => 1.0f0; name = :cohesion, default = 0.0f0)
    age = PottsToolkit.CellProperty(:fragment_age, migrating;
        initial = 0.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    rate = PottsToolkit.CellParameter(:fragment_rate, migrating => 0.25f0)
    drive = PottsToolkit.Chemotaxis(
        signal, migrating => 0.75f0; name = :migration_drive)
    growth = PottsToolkit.Growth(
        volume, migrating; rate = 0.25f0, name = :fragment_growth)
    migration = PottsToolkit.ModelFragment(:migration,
        volume, adhesion, age, rate, drive, growth;
        requires = (migrating, signal), exports = (age,))

    medium = PottsToolkit.Medium(:fragment_medium)
    tumor = PottsToolkit.CellType(:tumor)
    field = PottsToolkit.Field(:chemoattractant)

    unbound = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, tumor, field, migration))
    @test count(item -> item.code === :unresolved_fragment_role, unbound) == 2

    partially_bound = PottsToolkit.bind(migration, migrating => tumor)
    partial_report = PottsToolkit.validate(PottsToolkit.PottsModel(
        medium, tumor, field, partially_bound))
    @test count(item -> item.code === :unresolved_fragment_role, partial_report) == 1

    bound = PottsToolkit.bind(
        migration, migrating => tumor, signal => field)
    bound_model = PottsToolkit.PottsModel(medium, tumor, field, bound)
    @test Base.isvalid(bound_model)
    @test isempty(bound.requirements)

    fragment_namespace = PottsToolkit.Namespace(:migration)
    explicit_volume = PottsToolkit.Volume(
        tumor => (target = 4, strength = 2.0f0);
        namespace = fragment_namespace)
    explicit_adhesion = PottsToolkit.Adhesion(
        (tumor, tumor) => 1.0f0; name = :cohesion,
        namespace = fragment_namespace, default = 0.0f0)
    explicit_age = PottsToolkit.CellProperty(:fragment_age, tumor;
        namespace = PottsToolkit.Namespace(), initial = 0.0f0,
        division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    explicit_rate = PottsToolkit.CellParameter(:fragment_rate, tumor => 0.25f0;
        namespace = fragment_namespace)
    explicit_drive = PottsToolkit.Chemotaxis(
        field, tumor => 0.75f0; name = :migration_drive,
        namespace = fragment_namespace)
    explicit_growth = PottsToolkit.Growth(
        explicit_volume, tumor; rate = 0.25f0, name = :fragment_growth,
        namespace = fragment_namespace)
    explicit_model = PottsToolkit.PottsModel(
        medium, tumor, field, explicit_volume, explicit_adhesion, explicit_age,
        explicit_rate, explicit_drive, explicit_growth)
    @test PottsToolkit.semantic_fingerprint(bound_model) ==
          PottsToolkit.semantic_fingerprint(explicit_model)

    mask = falses(3, 3)
    mask[2, 2] = true
    problem = PottsToolkit.PottsProblem(
        bound_model, PottsToolkit.CartesianDomain((3, 3)),
        PottsToolkit.Layout(PottsToolkit.Place(tumor, mask; identity = 1));
        fields = (field => zeros(Float32, 3, 3),), capacity = 1,
        tspan = (0, 1), seed = 11)
    @test CorePotts.solve(problem,
        PottsToolkit.SequentialCPM(temperature = 1.0f0)).retcode ==
        SciMLBase.ReturnCode.Success

    @test_throws ArgumentError PottsToolkit.bind(
        migration, migrating => field)
    @test_throws ArgumentError PottsToolkit.bind(
        migration, signal => tumor)
    @test_throws ArgumentError PottsToolkit.bind(
        migration, migrating => tumor, migrating => tumor)
    @test_throws ArgumentError PottsToolkit.ModelFragment(
        :ambiguous_roles; requires = (
            PottsToolkit.CellRole(:same), PottsToolkit.FieldRole(:same)))
    @test_throws ArgumentError PottsToolkit.ModelFragment(
        :colliding_role, PottsToolkit.CellType(:same);
        requires = (PottsToolkit.CellRole(:same),))
end
