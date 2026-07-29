@testset "Wang model Wang generic fragment authoring fixture" begin
    tumor = PottsToolkit.CellType(:wang_tumor)
    medium = PottsToolkit.Medium(:wang_medium)
    migrating_cells = PottsToolkit.CellRole(:wang_migrating_cells)

    clock = CorePotts.ContinuousClock(
        :wang_clock;
        per_mcs = 1.0f0, unit = :mcs)
    secretome_dynamics = CorePotts.FieldDynamics(
        :wang_secretome_dynamics;
        field = :wang_secretome,
        law = CorePotts.ReactionDiffusion(
            diffusion = 1.0f0, decay = 0.0f0),
        method = CorePotts.FixedStep(
            CorePotts.ExplicitEuler(); substeps = 5),
        clock,
        post_substep = (
            CorePotts.ConstantConcentration(
                :medium, 1.0f0),))
    sensed_secretome = PottsToolkit.CellProperty(
        :sensed_secretome, migrating_cells;
        initial = 0.0f0)
    secretome_uptake = CorePotts.FieldExchange(
        :wang_secretome_uptake;
        field = :wang_secretome,
        sinks = (
            CorePotts.Uptake(
                :cells;
                maximum = 1.0f0,
                relative_rate = 0.0025f0,
                output = :sensed_secretome),))
    secretome_coupling = PottsToolkit.ModelFragment(
        :secretome_coupling,
        clock,
        sensed_secretome,
        secretome_dynamics,
        secretome_uptake;
        requires = (
            cells = migrating_cells,
            medium = medium,
        ),
        exports = (
            signal = sensed_secretome,
            advance = secretome_dynamics,
            uptake = secretome_uptake,
        ),
    )
    secretome_coupling = PottsToolkit.bind(
        secretome_coupling,
        secretome_coupling.cells => tumor)

    rac = PottsToolkit.CellProperty(
        :rac, migrating_cells; initial = 0.0f0)
    rac_baseline = PottsToolkit.CellProperty(
        :rac_baseline, migrating_cells;
        initial = 1.0f0)
    rac_time = PottsToolkit.CellProperty(
        :rac_time, migrating_cells;
        initial = 0.0f0)
    rac_dynamics = CorePotts.AffineCellAdvance(
        :wang_rac_dynamics, :cells;
        state = :rac,
        constant = :rac_baseline,
        input = :sensed_secretome,
        time = :rac_time,
        decay = 0.1f0,
        duration = 2880.0f0)
    intracellular_signaling = PottsToolkit.ModelFragment(
        :intracellular_signaling,
        rac,
        rac_baseline,
        rac_time,
        rac_dynamics;
        requires = (
            cells = migrating_cells,
            signal = secretome_coupling.signal,
        ),
        exports = (
            activity = rac,
            advance = rac_dynamics,
        ),
    )
    intracellular_signaling = PottsToolkit.bind(
        intracellular_signaling,
        intracellular_signaling.cells => tumor)

    focal_strength = PottsToolkit.CellProperty(
        :focal_strength, migrating_cells;
        initial = 20.0f0)
    junctions = CorePotts.RelationshipSet(
        :wang_junctions;
        edge = CorePotts.ElasticLinkParameters{
            Float32},
        maximum_degree = 4,
        capacity = CorePotts.RelationshipCapacity(64))
    focal_relation = CorePotts.static_relation(
        CorePotts.SpatialQueryRole(),
        (
            (-1, 0), (0, -1), (0, 1), (1, 0),
            (-1, -1), (-1, 1), (1, -1), (1, 1),
            (-2, 0), (0, -2), (0, 2), (2, 0),
        );
        spacing = (1.0f0, 1.0f0))
    focal_topology = CorePotts.ContactRelationshipHamiltonian(
        :wang_focal_topology, :wang_junctions;
        relation = focal_relation,
        activation_energy = -50.0f0,
        initial_payload =
            CorePotts.ElasticLinkParameters(
                0.0f0, 0.0f0, 100_000.0f0),
        namespace = CorePotts.RNGNamespaceIdentity(
            UInt128(
                0x77616e675f666f63616c5f746f706f31)))
    focal_retune = CorePotts.ElasticLinkRetune(
        :wang_focal_retune,
        junctions, :cells;
        property = :focal_strength,
        strength = 20.0f0,
        target_length = 8.0f0,
        maximum_length = 12.0f0)
    focal_cleanup = CorePotts.RelationshipCleanup(
        :wang_focal_cleanup, junctions)
    focal_adhesions = PottsToolkit.ModelFragment(
        :focal_adhesions,
        focal_strength,
        junctions,
        focal_topology,
        focal_retune,
        focal_cleanup;
        requires = (cells = migrating_cells,),
        exports = (
            strength = focal_strength,
            relationships = junctions,
            topology = focal_topology,
            retune = focal_retune,
            cleanup = focal_cleanup,
        ),
    )
    focal_adhesions = PottsToolkit.bind(
        focal_adhesions,
        focal_adhesions.cells => tumor)

    polarity_x = PottsToolkit.CellProperty(
        :polarity_x, migrating_cells;
        initial = 0.0f0)
    polarity_y = PottsToolkit.CellProperty(
        :polarity_y, migrating_cells;
        initial = 0.0f0)
    displacement = PottsToolkit.CellProperty(
        :centroid_displacement, migrating_cells;
        initial = 0.0f0)
    alignment_fraction = PottsToolkit.CellProperty(
        :alignment_fraction, migrating_cells;
        initial = 0.0f0)
    force_x = PottsToolkit.CellProperty(
        :force_x, migrating_cells;
        initial = 0.0f0)
    force_y = PottsToolkit.CellProperty(
        :force_y, migrating_cells;
        initial = 0.0f0)
    force_magnitude = PottsToolkit.CellProperty(
        :force_magnitude, migrating_cells;
        initial = 0.0f0)
    hill_coefficient = PottsToolkit.CellProperty(
        :hill_coefficient, migrating_cells;
        initial = 0.0f0)
    centroid_history = CorePotts.CellHistory(
        :wang_centroid_history;
        source = :compiled_unwrapped_centroid,
        length = 5,
        initial = CorePotts.MissingUntilFull())
    centroid_sample = CorePotts.CentroidHistorySample(
        :wang_centroid_sample,
        :wang_centroid_history)
    polarity_from_history =
        CorePotts.HistoryDisplacementDirection(
            :wang_polarity_from_history,
            :wang_centroid_history;
            outputs = (:polarity_x, :polarity_y),
            magnitude = :centroid_displacement,
            lag = CorePotts.Lag(4))
    neighbor_alignment =
        CorePotts.NeighborPolarityAlignment(
            :wang_neighbor_alignment,
            focal_relation;
            x = :polarity_x,
            y = :polarity_y,
            strength = :focal_strength,
            fraction = :alignment_fraction,
            strength_scale = 1000.0f0,
            maximum_fraction = 0.4f0)
    protrusion_drive = CorePotts.HillVectorForce(
        :wang_protrusion_drive;
        polarity_x = :polarity_x,
        polarity_y = :polarity_y,
        signal = :rac,
        force_x = :force_x,
        force_y = :force_y,
        magnitude = :force_magnitude,
        coefficient = :hill_coefficient,
        half_activation = 40.0f0,
        maximum_force = 150.0f0,
        exponent = 4,
        direction = -1.0f0)
    directed_motility = PottsToolkit.ModelFragment(
        :directed_motility,
        polarity_x,
        polarity_y,
        displacement,
        alignment_fraction,
        force_x,
        force_y,
        force_magnitude,
        hill_coefficient,
        centroid_history,
        centroid_sample,
        polarity_from_history,
        neighbor_alignment,
        protrusion_drive;
        requires = (
            cells = migrating_cells,
            activity =
                intracellular_signaling.activity,
            adhesions =
                focal_adhesions.relationships,
        ),
        exports = (
            history = centroid_history,
            sample = centroid_sample,
            derive = polarity_from_history,
            align = neighbor_alignment,
            force = protrusion_drive,
        ),
    )
    directed_motility = PottsToolkit.bind(
        directed_motility,
        directed_motility.cells => tumor)

    # CC3D source MCS k maps to normalized target MCS k+1. The source
    # mcs % 10 == 0 cadence over 0:499 is therefore target 1:10:491.
    retune_cadence =
        CorePotts.PeriodicMCS(1, 10; stop = 491)
    active_migration =
        CorePotts.PeriodicMCS(122, 1; stop = 500)
    migration_plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(
            :secretome_field_solve,
            CorePotts.Advance(
                secretome_coupling.advance;
                interval = CorePotts.OneMCS())),
        CorePotts.CoupledPhase(
            :sample_centroids,
            CorePotts.Sample(
                directed_motility.sample)),
        CorePotts.CoupledPhase(
            :update_self_polarity,
            CorePotts.Update(
                directed_motility.derive;
                active = active_migration)),
        CorePotts.CoupledPhase(
            :secretome_uptake,
            CorePotts.Exchange(
                secretome_coupling.uptake)),
        CorePotts.CoupledPhase(
            :intracellular_dynamics,
            CorePotts.Advance(
                intracellular_signaling.advance;
                interval = CorePotts.OneMCS(),
                active = active_migration)),
        CorePotts.CoupledPhase(
            :retune_focal_relationships,
            CorePotts.Update(
                focal_adhesions.retune;
                active = retune_cadence)),
        CorePotts.CoupledPhase(
            :align_neighbor_polarity,
            CorePotts.Update(
                directed_motility.align;
                active = active_migration)),
        CorePotts.CoupledPhase(
            :update_protrusion,
            CorePotts.Update(
                directed_motility.force;
                active = active_migration)),
        CorePotts.CoupledPhase(
            :cleanup_relationships,
            CorePotts.Update(
                focal_adhesions.cleanup)),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase(),
    )

    model = PottsToolkit.compose(
        PottsToolkit.PottsModel(tumor, medium),
        secretome_coupling,
        intracellular_signaling,
        focal_adhesions,
        directed_motility,
        migration_plan,
    )
    @test Base.isvalid(model)
    normalized = PottsToolkit.normalize(model)
    lowered = PottsToolkit.lower(
        model; dimensions = 2)
    @test lowered.normalized.fingerprint ==
          normalized.fingerprint
    @test PottsToolkit.required_backends(model) ==
          (:cpu, :metal, :rocm)

    phases = Tuple(
        entry for entry in migration_plan.entries
        if entry isa CorePotts.CoupledPhase)
    @test Tuple(phase.name for phase in phases) == (
        :secretome_field_solve,
        :sample_centroids,
        :update_self_polarity,
        :secretome_uptake,
        :intracellular_dynamics,
        :retune_focal_relationships,
        :align_neighbor_polarity,
        :update_protrusion,
        :cleanup_relationships,
    )
    processes = Tuple(
        CorePotts.invocation_process(
            only(phase.invocations))
        for phase in phases)
    @test processes == (
        secretome_dynamics,
        centroid_sample,
        polarity_from_history,
        secretome_uptake,
        rac_dynamics,
        focal_retune,
        neighbor_alignment,
        protrusion_drive,
        focal_cleanup,
    )
    @test CorePotts.is_due(
        only(phases[6].invocations).active, 1)
    @test CorePotts.is_due(
        only(phases[6].invocations).active, 121)
    @test CorePotts.is_due(
        only(phases[6].invocations).active, 211)
    @test !CorePotts.is_due(
        only(phases[6].invocations).active, 212)

    public_names =
        Set(names(PottsToolkit; all = false))
    @test !any(
        name -> occursin(
            r"Wang|Jiang|Glazier|Wortel|Merks|CNV"i,
            String(name)),
        public_names)
end
