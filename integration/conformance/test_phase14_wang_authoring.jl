@testset "Phase 14 Wang generic fragment authoring fixture" begin
    tumor = PottsToolkit.CellType(:wang_tumor)
    medium = PottsToolkit.Medium(:wang_medium)
    migrating_cells = PottsToolkit.CellRole(:wang_migrating_cells)

    secretome = CorePotts.SiteProperty(:wang_secretome;
        initial = 0.0f0, ownership = CorePotts.PreserveAtSite())
    secretome_field_solve = CorePotts.SiteDynamics(
        :wang_secretome_field_solve, secretome;
        update = CorePotts.SetSiteValue(0.0f0))
    secretome_uptake = CorePotts.SiteDynamics(
        :wang_secretome_uptake, secretome;
        update = CorePotts.SaturatingSubtract(0.01f0))
    secretome_coupling = PottsToolkit.ModelFragment(
        :secretome_coupling,
        secretome,
        secretome_field_solve,
        secretome_uptake;
        requires = (
            cells = migrating_cells,
            medium = medium,
        ),
        exports = (
            signal = secretome,
            advance = secretome_field_solve,
            uptake = secretome_uptake,
        ),
    )
    secretome_coupling = PottsToolkit.bind(
        secretome_coupling, secretome_coupling.cells => tumor)

    rac = CorePotts.SiteProperty(:wang_rac;
        initial = 0.0f0, ownership = CorePotts.PreserveAtSite())
    rac_dynamics = CorePotts.SiteDynamics(:wang_rac_dynamics, rac;
        update = CorePotts.SetSiteValue(0.0f0))
    intracellular_signaling = PottsToolkit.ModelFragment(
        :intracellular_signaling,
        rac,
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

    focal_strength = CorePotts.SiteProperty(:wang_focal_strength;
        initial = 0.0f0, ownership = CorePotts.AcceptedCopyManaged())
    junctions = CorePotts.RelationshipSet(:wang_junctions;
        edge = Float32, maximum_degree = 8,
        capacity = CorePotts.RelationshipCapacity(64))
    focal_topology = CorePotts.AcceptedCopyUpdate(
        :wang_focal_topology, focal_strength;
        gained = CorePotts.SetTo(1.0f0))
    focal_retune = CorePotts.RelationshipDynamics(
        :wang_focal_retune, junctions)
    focal_adhesions = PottsToolkit.ModelFragment(
        :focal_adhesions,
        focal_strength,
        junctions,
        focal_topology,
        focal_retune;
        requires = (cells = migrating_cells,),
        exports = (
            strength = focal_strength,
            relationships = junctions,
            topology = focal_topology,
            retune = focal_retune,
        ),
    )
    focal_adhesions = PottsToolkit.bind(
        focal_adhesions, focal_adhesions.cells => tumor)

    polarity = CorePotts.SiteProperty(:wang_polarity;
        initial = 0.0f0, ownership = CorePotts.PreserveAtSite())
    centroid_history = CorePotts.SiteProperty(:wang_centroid_history;
        initial = 0.0f0, ownership = CorePotts.PreserveAtSite())
    centroid_sample = CorePotts.SiteDynamics(
        :wang_centroid_sample, centroid_history;
        update = CorePotts.SetSiteValue(0.0f0))
    polarity_from_history = CorePotts.SiteDynamics(
        :wang_polarity_from_history, polarity;
        update = CorePotts.SetSiteValue(0.0f0))
    neighbor_alignment = CorePotts.SiteDynamics(
        :wang_neighbor_alignment, polarity;
        update = CorePotts.SetSiteValue(0.0f0))
    protrusion_drive = CorePotts.SiteDynamics(
        :wang_protrusion_drive, polarity;
        update = CorePotts.SetSiteValue(0.0f0))
    directed_motility = PottsToolkit.ModelFragment(
        :directed_motility,
        polarity,
        centroid_history,
        centroid_sample,
        polarity_from_history,
        neighbor_alignment,
        protrusion_drive;
        requires = (
            cells = migrating_cells,
            activity = intracellular_signaling.activity,
            adhesions = focal_adhesions.relationships,
        ),
        exports = (
            polarity = polarity,
            history = centroid_history,
            sample = centroid_sample,
            derive = polarity_from_history,
            align = neighbor_alignment,
            force = protrusion_drive,
        ),
    )
    directed_motility = PottsToolkit.bind(
        directed_motility, directed_motility.cells => tumor)

    # CC3D source MCS k maps to normalized target MCS k+1. The source
    # mcs % 10 == 0 cadence over 0:499 is therefore target 1:10:491.
    retune_cadence = CorePotts.PeriodicMCS(1, 10; stop = 491)
    migration_plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(
            on_accept = (focal_adhesions.topology,)),
        CorePotts.CoupledPhase(:secretome_field_solve,
            CorePotts.Advance(secretome_coupling.advance;
                interval = CorePotts.OneMCS())),
        CorePotts.CoupledPhase(:sample_centroids,
            CorePotts.Sample(directed_motility.sample)),
        CorePotts.CoupledPhase(:update_self_polarity,
            CorePotts.Update(directed_motility.derive)),
        CorePotts.CoupledPhase(:secretome_uptake,
            CorePotts.Exchange(secretome_coupling.uptake)),
        CorePotts.CoupledPhase(:intracellular_dynamics,
            CorePotts.Advance(intracellular_signaling.advance;
                interval = CorePotts.OneMCS())),
        CorePotts.CoupledPhase(:retune_focal_relationships,
            CorePotts.Update(focal_adhesions.retune;
                active = retune_cadence)),
        CorePotts.CoupledPhase(:align_neighbor_polarity,
            CorePotts.Update(directed_motility.align)),
        CorePotts.CoupledPhase(:update_protrusion,
            CorePotts.Update(directed_motility.force)),
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
    lowered = PottsToolkit.lower(model; dimensions = 2)
    @test lowered.normalized.fingerprint == normalized.fingerprint
    @test PottsToolkit.required_backends(model) == (:cpu, :metal, :rocm)

    phases = Tuple(entry for entry in migration_plan.entries
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
    )
    @test only((entry for entry in migration_plan.entries
        if entry isa CorePotts.PottsAttempts)).on_accept ==
          (focal_adhesions.topology,)
    @test CorePotts.is_due(
        only(phases[6].invocations).active, 1)
    @test CorePotts.is_due(
        only(phases[6].invocations).active, 121)
    @test CorePotts.is_due(
        only(phases[6].invocations).active, 211)
    @test !CorePotts.is_due(
        only(phases[6].invocations).active, 212)

    public_names = Set(names(PottsToolkit; all = false))
    @test !any(name -> occursin(r"Wang|Jiang|Glazier|Wortel|Merks|CNV"i,
        String(name)), public_names)
end
