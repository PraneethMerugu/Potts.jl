@testset "model authoring Level 1/2 semantic equivalence" begin
    medium = PottsToolkit.Medium(:equivalence_medium)
    cell = PottsToolkit.CellType(:equivalence_cell)

    fingerprint(component) = PottsToolkit.semantic_fingerprint(
        PottsToolkit.PottsModel(medium, cell, component))

    volume_values = cell => (target = 4, strength = 2.0f0)
    @test fingerprint(PottsToolkit.Volume(volume_values)) ==
          fingerprint(PottsToolkit.VolumeConstraint(volume_values))

    surface_values = cell => (target = 8, strength = 1.5f0)
    @test fingerprint(PottsToolkit.Surface(surface_values)) ==
          fingerprint(PottsToolkit.BoundaryConstraint(surface_values))

    fixed_noise = PottsToolkit.IndependentNoise(0.5f0)
    @test fingerprint(PottsToolkit.FluctuatingVolumePressure(volume_values;
        noise = fixed_noise, eta = 0.25f0)) ==
        fingerprint(PottsToolkit.FluctuatingVolumeConstraint(volume_values;
            noise = fixed_noise, eta = 0.25f0))
    @test fingerprint(PottsToolkit.FluctuatingSurfaceTension(surface_values;
        noise = fixed_noise, eta = 0.25f0)) ==
        fingerprint(PottsToolkit.FluctuatingBoundaryConstraint(surface_values;
            noise = fixed_noise, eta = 0.25f0))

    contacts = (
        (medium, medium) => 0.0f0,
        (medium, cell) => 4.0f0,
        (cell, cell) => 1.0f0,
    )
    level1_law = PottsToolkit.PairwiseLaw(
        :equivalence_contacts, contacts...; symmetric = true)
    @test fingerprint(PottsToolkit.Adhesion(level1_law)) ==
          fingerprint(PottsToolkit.Adhesion(
              contacts...; name = :equivalence_contacts))

    level1_growth = PottsToolkit.Growth(
        PottsToolkit.VolumeConstraint(volume_values), cell;
        rate = 0.25f0, name = :equivalence_growth)
    level2_growth = PottsToolkit.PropertyUpdate(
        PottsToolkit.VolumeConstraint(volume_values), cell;
        role = :target, amount = 0.25f0, name = :equivalence_growth)
    @test PottsToolkit.semantic_fingerprint(PottsToolkit.PottsModel(
        medium, cell, PottsToolkit.VolumeConstraint(volume_values), level1_growth)) ==
        PottsToolkit.semantic_fingerprint(PottsToolkit.PottsModel(
            medium, cell, PottsToolkit.VolumeConstraint(volume_values), level2_growth))

    @test PottsToolkit.LinearResponse === CorePotts.LinearResponse
    @test PottsToolkit.MichaelisMentenResponse === CorePotts.MichaelisMentenResponse
    @test PottsToolkit.RetractionChemotaxis === CorePotts.RetractionChemotaxis
    @test PottsToolkit.PositiveYield === CorePotts.PositiveYield
    @test PottsToolkit.SequentialCPM === CorePotts.SequentialCPM
    @test PottsToolkit.SequentialEquilibrium === CorePotts.SequentialEquilibrium
    @test PottsToolkit.CheckerboardSweepCPM === CorePotts.CheckerboardSweepCPM
    @test PottsToolkit.LotteryCPM === CorePotts.LotteryCPM
    for name in (
            :ReadOnlyProperty, :MutableProperty,
            :CloneOnDivision, :SplitOnDivision, :ResetChildOnDivision,
            :ResetBothOnDivision, :AsymmetricResetOnDivision, :UnsupportedDivision,
            :ConstitutiveResetAfterDivision, :PreserveMechanicalOnDivision,
            :StationaryRedrawAfterDivision, :PreserveOnTransition,
            :ResetOnTransition, :RecomputeOnTransition, :UnsupportedTransition,
            :ResetOnRetirement, :ConstitutiveMeanInitialization,
            :StationaryMechanicalInitialization, :PreserveMechanicalInitialization)
        @test getfield(PottsToolkit, name) === getfield(CorePotts, name)
    end
    @test PottsToolkit.AcceptanceTemperature() isa CorePotts.AlgorithmTemperatureNoise
    @test PottsToolkit.IndependentNoise(1.0f0) isa CorePotts.FixedMechanicalNoise

    field_values = reshape(Float32.(1:9), 3, 3)
    domain = PottsToolkit.CartesianDomain((3, 3))
    mask = falses(3, 3)
    mask[2, 2] = true
    layout = PottsToolkit.Layout(PottsToolkit.Place(cell, mask; identity = 1))
    response = PottsToolkit.MichaelisMentenResponse(2.0f0)
    mode = PottsToolkit.RetractionChemotaxis()

    level1_field = PottsToolkit.Field(:equivalence_signal;
        boundary = (PottsToolkit.FixedValue(0.0f0), PottsToolkit.PeriodicField()),
        interpolation = PottsToolkit.Nearest())
    level1_drive = PottsToolkit.Chemotaxis(
        level1_field, cell => 0.75f0; response, mode)
    level1_problem = PottsToolkit.PottsProblem(PottsToolkit.PottsModel(
        medium, cell, PottsToolkit.Volume(volume_values), level1_field, level1_drive),
        domain, layout; fields = (level1_field => field_values,),
        capacity = 1, tspan = (0, 1), seed = 9)

    boundaries = (
        CorePotts.AxisFieldBoundary(CorePotts.DirichletFieldBoundary(0.0f0)),
        CorePotts.AxisFieldBoundary(CorePotts.PeriodicFieldBoundary()),
    )
    level2_field = PottsToolkit.PrescribedField(
        :equivalence_signal, field_values;
        spacing = (1.0f0, 1.0f0), boundaries,
        interpolation = CorePotts.NearestFieldInterpolation())
    level2_drive = PottsToolkit.Chemotaxis(
        level2_field, cell => 0.75f0; response, mode)
    level2_problem = PottsToolkit.problem(PottsToolkit.PottsModel(
        medium, cell, PottsToolkit.VolumeConstraint(volume_values),
        level2_field, level2_drive), domain, layout.entries...;
        capacity = 1, tspan = (0, 1), seed = 9)

    level1_components = CorePotts.realize_components(
        level1_problem.model, level1_problem.p)
    level2_components = CorePotts.realize_components(
        level2_problem.model, level2_problem.p)
    @test CorePotts.component_semantic_data(only(level1_components.drives)) ==
          CorePotts.component_semantic_data(only(level2_components.drives))
end
