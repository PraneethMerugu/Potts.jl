import ProcessBigraphs
import SciMLBase

const Wortel2021 = PottsToolkit.ReferenceModels.Wortel2021
const Merks2006 = PottsToolkit.ReferenceModels.Merks2006

function _logical_values_equal(left, right)
    CorePotts.lattice_storage(left) == CorePotts.lattice_storage(right) &&
        CorePotts.active_cell_ids(left) == CorePotts.active_cell_ids(right)
end

@testset "ReferenceModels family ownership and profiles" begin
    @test isdefined(PottsToolkit.ReferenceModels, :Wortel2021)
    @test isdefined(PottsToolkit.ReferenceModels, :Merks2006)

    wortel = Wortel2021.model(Wortel2021.reduced_profile())
    merks = Merks2006.model(Merks2006.reduced_profile())
    @test Wortel2021.semantic_manifest(wortel).semantic_version == "1.0.0"
    @test Merks2006.semantic_manifest(merks).semantic_version == "2.0.0"
    @test :no_figure_2_reproduction in
        wortel.profile.scientific_nonclaims
    @test :no_figure_5_reproduction in
        merks.profile.scientific_nonclaims

    differential = Merks2006.differential_from_v1(merks)
    @test differential.semantic_version == (from=1, to=2)
    @test differential.preserved_source_trace
    @test :new_semantic_fingerprint in differential.intentional_changes

    canonical_labels =
        Merks2006.initial_labels(Merks2006.canonical_profile())
    @test size(canonical_labels) == (500, 500)
    @test maximum(canonical_labels) == UInt64(282)
    @test length(Set(filter(!iszero, canonical_labels))) == 282
    @test count(!iszero, canonical_labels) == 28_200

    @test (
        PottsToolkit.ReferenceModels.merks2006_ambiguity_profile()
            isa CorePotts.Merks2006AmbiguityProfile
    )
    @test PottsToolkit.ReferenceModels.merks2006_initial_labels(
        shape=(20, 20),
        cells=2,
        central_extent=16,
        target_area_sites=5.0,
        seed=11,
    ) isa Array{UInt64,2}
    @test isdefined(CorePotts, :merks2006_composite)
    @test isdefined(CorePotts, :merks2006_initial_labels)
end

@testset "Wortel public lifecycle and exact continuation" begin
    spec = Wortel2021.Profile(
        :test_cpu,
        (12, 12);
        cell_side=4,
        observation_every=1,
        mcs=3,
        seed=0x7068617365313402,
    )
    definition = Wortel2021.model(spec)
    experiment = Wortel2021.problem(definition)
    integrator = SciMLBase.init(experiment)
    SciMLBase.step!(integrator)
    oracle_state = CorePotts.logical_state(integrator)
    oracle_labels = map(
        owner -> CorePotts.is_cell_owner(owner) ?
            UInt64(CorePotts.value(CorePotts.cell_id(owner))) : UInt64(0),
        CorePotts.lattice_storage(oracle_state),
    )
    oracle_activity = reshape(
        Float32[
            CorePotts.site_property_value(integrator, site)
            for site in eachindex(oracle_labels)
        ],
        size(oracle_labels),
    )
    oracle_report = CorePotts.current_mcs_report(integrator)
    @test ProcessBigraphs.canonical_fingerprint((
        oracle_labels,
        oracle_activity,
        oracle_report.accepted_copies,
        oracle_report.acceptance_rejections,
        oracle_report.same_owner_no_ops,
    )) == "70fb3041bbf4585f17452453a7c82a8650572f4ae0ce6c4379bce0a6231fc61b"
    activity_semantics =
        CorePotts.component_semantic_data(
            PottsToolkit.lower(definition.activity).hamiltonian)
    @test activity_semantics.maximum == 10.0f0
    @test activity_semantics.strength == 20.0f0
    @test CorePotts.relation_semantics_report(
        definition.activity.neighborhood).direction_count == 8
    checkpoint = CorePotts.capture_checkpoint(integrator)
    SciMLBase.step!(integrator, 2)

    restored = CorePotts.restore_checkpoint(checkpoint, integrator)
    SciMLBase.step!(restored, 2)
    left = CorePotts.logical_state(integrator)
    right = CorePotts.logical_state(restored)
    @test _logical_values_equal(left, right)
    @test all(
        CorePotts.site_property_value(integrator, site) ==
            CorePotts.site_property_value(restored, site)
        for site in eachindex(CorePotts.lattice_storage(left))
    )
    @test ProcessBigraphs.observation_records(integrator) ==
        ProcessBigraphs.observation_records(restored)
    @test CorePotts.current_mcs_report(integrator) !== nothing

    assembled = Wortel2021.composite(
        Wortel2021.model(Wortel2021.Profile(
            :composite_test,
            (12, 12);
            cell_side=4,
            observation_every=1,
            mcs=1,
            seed=18,
        )),
    )
    executor = ProcessBigraphs.SerialExecutor(
        root_seed=18,
        observation_plan=Wortel2021.observation_plan(
            Wortel2021.Profile(
                :composite_test,
                (12, 12);
                cell_side=4,
                observation_every=1,
                mcs=1,
                seed=18,
            ),
        ),
    )
    runtime = ProcessBigraphs.initialize_runtime(assembled, executor)
    ProcessBigraphs.run_until!(
        runtime,
        ProcessBigraphs.LogicalTime(
            1, ProcessBigraphs.TimeScale(1, 1, :mcs)),
    )
    @test length(ProcessBigraphs.observation_records(runtime)) == 1
end

@testset "Merks public lifecycle, orchestration, and restart" begin
    spec = Merks2006.Profile(
        :test_cpu,
        (12, 12);
        cells=2,
        central_extent=10,
        target_area_sites=5.0,
        target_length_sites=5.0,
        mcs=2,
        seed=19,
    )
    definition = Merks2006.model(spec)
    labels = Merks2006.initial_labels(spec)
    experiment = Merks2006.problem(
        definition;
        labels,
        tspan=(0, 1),
    )
    integrator = SciMLBase.init(
        experiment,
        PottsToolkit.SequentialCPM(
            temperature=spec.temperature),
    )
    SciMLBase.step!(integrator)
    @test CorePotts.n_cells(CorePotts.logical_state(integrator)) == 2
    @test CorePotts.current_mcs_report(integrator) !== nothing
    scientific_checkpoint = CorePotts.capture_checkpoint(integrator)
    remade = SciMLBase.remake(experiment; tspan=(0, 2))
    restored_scientific = CorePotts.restore_checkpoint(
        scientific_checkpoint,
        remade,
        PottsToolkit.SequentialCPM(
            temperature=spec.temperature),
    )
    @test _logical_values_equal(
        CorePotts.logical_state(integrator),
        CorePotts.logical_state(restored_scientific),
    )

    assembled = Merks2006.composite(definition; labels)
    executor = ProcessBigraphs.SerialExecutor(
        root_seed=spec.seed,
        observation_plan=Merks2006.observation_plan(spec),
    )
    runtime = ProcessBigraphs.initialize_runtime(assembled, executor)
    scale = ProcessBigraphs.TimeScale(2, 1, :second)
    ProcessBigraphs.run_until!(
        runtime, ProcessBigraphs.LogicalTime(15, scale))
    encoded =
        ProcessBigraphs.encode_checkpoint(
            ProcessBigraphs.logical_checkpoint(runtime))
    resumed = ProcessBigraphs.restore(assembled, executor, encoded)
    ProcessBigraphs.run_until!(
        runtime, ProcessBigraphs.LogicalTime(30, scale))
    ProcessBigraphs.run_until!(
        resumed, ProcessBigraphs.LogicalTime(30, scale))
    @test ProcessBigraphs.materialize(
        ProcessBigraphs.current_snapshot(runtime)) ==
        ProcessBigraphs.materialize(
            ProcessBigraphs.current_snapshot(resumed))
    @test ProcessBigraphs.observation_records(runtime) ==
        ProcessBigraphs.observation_records(resumed)
    @test map(
        record -> record.payload.mcs,
        ProcessBigraphs.observation_records(runtime),
    ) == (1, 2)

    legacy_labels = CorePotts.merks2006_initial_labels(
        shape=(10, 10),
        cells=1,
        central_extent=8,
        target_area_sites=4.0,
        seed=23,
    )
    legacy_composite = CorePotts.merks2006_native_composite(
        legacy_labels;
        subcycles_per_mcs=1,
        root_seed=23,
    )
    legacy_executor = ProcessBigraphs.SerialExecutor(root_seed=23)
    legacy_runtime = ProcessBigraphs.initialize_runtime(
        legacy_composite, legacy_executor)
    ProcessBigraphs.run_until!(
        legacy_runtime, ProcessBigraphs.LogicalTime(1, scale))
    legacy_bytes = ProcessBigraphs.encode_checkpoint(
        ProcessBigraphs.logical_checkpoint(legacy_runtime))
    @test ProcessBigraphs.restore(
        legacy_composite, legacy_executor, legacy_bytes) !== nothing
    @test_throws Merks2006.MigrationRequiredError Merks2006.restore_v2(
        legacy_bytes,
        definition;
        acknowledge_v1=true,
    )
end
