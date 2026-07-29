const StochasticWortel2021 = PottsToolkit.ReferenceModels.Wortel2021
const StochasticMerks2006 = PottsToolkit.ReferenceModels.Merks2006

function _wortel_stochastic_signature(seed)
    profile = StochasticWortel2021.Profile(
        :stochastic_test,
        (12, 12);
        cell_side=4,
        observation_every=1,
        mcs=3,
        seed,
    )
    run = StochasticWortel2021.run(
        StochasticWortel2021.model(profile))
    return ProcessBigraphs.canonical_fingerprint((
        run.labels,
        run.activity,
        run.report.accepted_copies,
        run.report.acceptance_rejections,
        run.report.same_owner_no_ops,
    ))
end

function _merks_stochastic_signature(seed)
    profile = StochasticMerks2006.Profile(
        :stochastic_test,
        (10, 10);
        cells=2,
        central_extent=8,
        target_area_sites=4.0,
        target_length_sites=4.0,
        mcs=1,
        seed,
    )
    definition = StochasticMerks2006.model(profile)
    composite = StochasticMerks2006.composite(
        definition;
        labels=StochasticMerks2006.initial_labels(profile),
    )
    runtime = ProcessBigraphs.initialize_runtime(
        composite,
        ProcessBigraphs.SerialExecutor(
            root_seed=seed,
            observation_plan=
                StochasticMerks2006.observation_plan(profile),
        ),
    )
    ProcessBigraphs.run_until!(
        runtime,
        ProcessBigraphs.LogicalTime(
            profile.mcs * profile.subcycles_per_mcs,
            ProcessBigraphs.TimeScale(2, 1, :second),
        ),
    )
    snapshot = ProcessBigraphs.current_snapshot(runtime)
    field = snapshot[ProcessBigraphs.path("field")]
    @test all(isfinite, field)
    @test minimum(field) >= 0
    return ProcessBigraphs.canonical_fingerprint((
        ProcessBigraphs.materialize(snapshot),
        Tuple(
            record.payload
            for record in ProcessBigraphs.observation_records(runtime)
        ),
    ))
end

@testset "Published models are reproducible and stochastic" begin
    wortel = _wortel_stochastic_signature(41)
    @test wortel == _wortel_stochastic_signature(41)
    @test wortel != _wortel_stochastic_signature(42)

    merks = _merks_stochastic_signature(51)
    @test merks == _merks_stochastic_signature(51)
    @test merks != _merks_stochastic_signature(52)
end
