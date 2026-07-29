#!/usr/bin/env julia

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]

check(condition, message) = condition || push!(failures, message)

module DisplayedWortel
include(joinpath(
    @__DIR__,
    "..",
    "lib",
    "ProcessBigraphs",
    "docs",
    "models",
    "case_studies",
    "wortel_2021.jl",
))
end

module DisplayedMerks
include(joinpath(
    @__DIR__,
    "..",
    "lib",
    "ProcessBigraphs",
    "docs",
    "models",
    "case_studies",
    "merks_2006.jl",
))
end

using PottsToolkit
import CorePotts
import ProcessBigraphs as PB

const PackagedWortel = PottsToolkit.ReferenceModels.Wortel2021
const PackagedMerks = PottsToolkit.ReferenceModels.Merks2006

function wortel_profile(profile)
    return (
        identity=profile.identity,
        dimensions=profile.dimensions,
        cell_side=profile.cell_side,
        maximum_activity=profile.maximum_activity,
        activity_strength=profile.activity_strength,
        volume_strength=profile.volume_strength,
        temperature=profile.temperature,
        observation_every=profile.observation_every,
        mcs=profile.mcs,
        seed=profile.seed,
    )
end

function merks_profile(profile)
    return (
        identity=profile.identity,
        dimensions=profile.dimensions,
        cells=profile.cells,
        central_extent=profile.central_extent,
        target_area_sites=profile.target_area_sites,
        target_length_sites=profile.target_length_sites,
        temperature=profile.temperature,
        chemotaxis_gamma=profile.chemotaxis_gamma,
        volume_strength=profile.volume_strength,
        source_length_strength=profile.source_length_strength,
        secretion_rate=profile.secretion_rate,
        diffusion=profile.diffusion,
        decay=profile.decay,
        subcycles_per_mcs=profile.subcycles_per_mcs,
        mcs=profile.mcs,
        seed=profile.seed,
    )
end

function run_composite(compiled, plan, seed, horizon)
    executor = PB.SerialExecutor(
        root_seed=seed,
        observation_plan=plan,
    )
    runtime = PB.initialize_runtime(compiled, executor)
    PB.run_until!(runtime, horizon)
    return (
        records=Tuple(
            record.payload for record in PB.observation_records(runtime)),
        state=PB.materialize(PB.current_snapshot(runtime)),
        fingerprint=PB.model_fingerprint(compiled),
    )
end

function normalized_wortel(record)
    return (
        mcs=record.tick,
        cells=record.cell_count,
        occupied=record.occupied_sites,
        active_sites=record.active_sites,
        activity_mass=record.activity_mass,
    )
end

function normalized_merks(record)
    return (
        mcs=record.mcs,
        cells=record.cell_count,
        occupied=record.occupied_sites,
        field_mass=record.field_mass,
        field_minimum=record.field_minimum,
        field_maximum=record.field_maximum,
    )
end

function wortel_signature(run)
    return PB.canonical_fingerprint((
        run.labels,
        run.activity,
        run.report.accepted_copies,
        run.report.acceptance_rejections,
        run.report.same_owner_no_ops,
    ))
end

function wortel_seed_profile(seed)
    source = PackagedWortel.reduced_profile()
    return PackagedWortel.Profile(
        :stochastic_probe,
        source.dimensions;
        cell_side=source.cell_side,
        maximum_activity=source.maximum_activity,
        activity_strength=source.activity_strength,
        volume_strength=source.volume_strength,
        temperature=source.temperature,
        observation_every=source.observation_every,
        mcs=source.mcs,
        seed,
        backend_claim=:cpu,
        deviations=(:stochastic_seed_probe,),
    )
end

function merks_seed_profile(seed)
    source = PackagedMerks.reduced_profile()
    return PackagedMerks.Profile(
        :stochastic_probe,
        source.dimensions;
        cells=source.cells,
        central_extent=source.central_extent,
        target_area_sites=source.target_area_sites,
        target_length_sites=source.target_length_sites,
        temperature=source.temperature,
        chemotaxis_gamma=source.chemotaxis_gamma,
        volume_strength=source.volume_strength,
        source_length_strength=source.source_length_strength,
        secretion_rate=source.secretion_rate,
        diffusion=source.diffusion,
        decay=source.decay,
        subcycles_per_mcs=source.subcycles_per_mcs,
        mcs=source.mcs,
        seed,
        backend_claim=:cpu,
        deviations=(:stochastic_seed_probe,),
    )
end

function run_merks_seed(seed)
    profile = merks_seed_profile(seed)
    definition = PackagedMerks.model(profile)
    return run_merks_definition(definition)
end

function run_merks_definition(definition)
    profile = definition.profile
    scale = PB.TimeScale(2, 1, :second)
    result = run_composite(
        PackagedMerks.composite(definition),
        PackagedMerks.observation_plan(definition),
        profile.seed,
        PB.LogicalTime(profile.mcs * profile.subcycles_per_mcs, scale),
    )
    for record in result.records
        check(record.mcs in 1:profile.mcs,
            "Merks seed $(profile.seed) produced an out-of-range MCS")
        check(0 <= record.cell_count <= profile.cells,
            "Merks seed $(profile.seed) produced an impossible cell count")
        check(0 <= record.occupied_sites <= prod(profile.dimensions),
            "Merks seed $(profile.seed) produced an impossible occupied-site count")
        check(
            isfinite(record.field_mass) && record.field_mass >= 0 &&
            isfinite(record.field_minimum) && record.field_minimum >= 0 &&
            isfinite(record.field_maximum) &&
            record.field_maximum >= record.field_minimum,
            "Merks seed $(profile.seed) produced an invalid field observation",
        )
    end
    return result
end

wortel_profile_packaged = PackagedWortel.reduced_profile()
wortel_definition = PackagedWortel.model(wortel_profile_packaged)
wortel_manifest = PackagedWortel.semantic_manifest(wortel_definition)
check(
    wortel_profile(wortel_profile_packaged) == DisplayedWortel.profile,
    "displayed Wortel profile differs from the packaged reduced profile",
)
check(
    DisplayedWortel.WORTEL_SOURCE_DOI ==
        wortel_profile_packaged.source_trace.doi,
    "displayed Wortel source identity differs from the packaged source trace",
)
check(
    DisplayedWortel.WORTEL_SEMANTIC_VERSION ==
        wortel_manifest.semantic_version,
    "displayed Wortel semantic version differs from the packaged model",
)
check(
    DisplayedWortel.result.model_fingerprint ==
        wortel_manifest.potts_fingerprint,
    "displayed Wortel Potts fingerprint differs from the packaged model",
)
check(
    DisplayedWortel.labels ==
        PackagedWortel.initial_labels(wortel_profile_packaged),
    "displayed Wortel initial state differs from the packaged model",
)

wortel_run = PackagedWortel.run(wortel_definition)
wortel_summary = (
    mcs=wortel_profile_packaged.mcs,
    cells=length(Set(filter(!iszero, wortel_run.labels))),
    occupied=count(!iszero, wortel_run.labels),
    active_sites=count(>(0), wortel_run.activity),
    activity_mass=sum(wortel_run.activity),
)
check(
    DisplayedWortel.result.record == wortel_summary,
    "displayed Wortel fixed-seed result differs from the packaged lifecycle",
)
wortel_scale = PB.TimeScale(1, 1, :mcs)
wortel_semantic =
    PackagedWortel.composite(wortel_definition; compile=false)
wortel_composite = PB.compile(wortel_semantic)
wortel_bounded = run_composite(
    wortel_composite,
    PackagedWortel.observation_plan(wortel_definition),
    wortel_profile_packaged.seed,
    PB.LogicalTime(wortel_profile_packaged.mcs, wortel_scale),
)
check(
    DisplayedWortel.result.composite_fingerprint ==
        PB.semantic_fingerprint(wortel_semantic),
    "displayed Wortel composite fingerprint differs from the packaged assembly",
)
check(
    PB.describe(DisplayedWortel.composite_model).stores ==
        PB.describe(wortel_semantic).stores &&
    PB.describe(DisplayedWortel.composite_model).components ==
        PB.describe(wortel_semantic).components,
    "displayed Wortel stores or components differ from the packaged assembly",
)
check(
    normalized_wortel(only(wortel_bounded.records)) ==
        DisplayedWortel.result.record,
    "displayed Wortel observation differs from the packaged composite",
)

wortel_replay = PackagedWortel.run(wortel_definition)
check(
    wortel_run.labels == wortel_replay.labels &&
    wortel_run.activity == wortel_replay.activity &&
    wortel_signature(wortel_run) == wortel_signature(wortel_replay),
    "Wortel fixed-seed replay is not exact",
)
wortel_alternate =
    PackagedWortel.run(PackagedWortel.model(wortel_seed_profile(
        wortel_profile_packaged.seed + 1)))
check(
    wortel_signature(wortel_run) != wortel_signature(wortel_alternate),
    "Wortel stochastic probe did not respond to a changed seed",
)

merks_profile_packaged = PackagedMerks.reduced_profile()
merks_definition = PackagedMerks.model(merks_profile_packaged)
merks_manifest = PackagedMerks.semantic_manifest(merks_definition)
check(
    merks_profile(merks_profile_packaged) == DisplayedMerks.profile,
    "displayed Merks profile differs from the packaged reduced profile",
)
check(
    DisplayedMerks.MERKS_SOURCE_DOI ==
        merks_profile_packaged.source_trace.doi,
    "displayed Merks source identity differs from the packaged source trace",
)
check(
    DisplayedMerks.MERKS_SEMANTIC_VERSION ==
        merks_manifest.semantic_version,
    "displayed Merks semantic version differs from the packaged model",
)
check(
    DisplayedMerks.result.model_fingerprint ==
        merks_manifest.fingerprint,
    "displayed Merks Potts fingerprint differs from the packaged model",
)
check(
    DisplayedMerks.labels ==
        PackagedMerks.initial_labels(merks_profile_packaged),
    "displayed Merks initial state differs from the packaged model",
)

merks_scale = PB.TimeScale(2, 1, :second)
merks_semantic =
    PackagedMerks.composite(merks_definition; compile=false)
merks_bounded = run_composite(
    PB.compile(merks_semantic),
    PackagedMerks.observation_plan(merks_definition),
    merks_profile_packaged.seed,
    PB.LogicalTime(
        merks_profile_packaged.mcs *
            merks_profile_packaged.subcycles_per_mcs,
        merks_scale,
    ),
)
check(
    DisplayedMerks.result.composite_fingerprint ==
        PB.semantic_fingerprint(merks_semantic),
    "displayed Merks composite fingerprint differs from the packaged assembly",
)
check(
    PB.describe(DisplayedMerks.composite_model).stores ==
        PB.describe(merks_semantic).stores &&
    PB.describe(DisplayedMerks.composite_model).components ==
        PB.describe(merks_semantic).components,
    "displayed Merks stores or components differ from the packaged assembly",
)
check(
    Tuple(normalized_merks(record) for record in merks_bounded.records) ==
        DisplayedMerks.records,
    "displayed Merks fixed-seed observations differ from the packaged composite",
)

merks_replay = run_merks_definition(merks_definition)
check(
    merks_replay.records == merks_bounded.records &&
    merks_replay.state == merks_bounded.state,
    "Merks fixed-seed replay is not exact",
)
merks_ensemble = (
    merks_bounded,
    run_merks_seed(merks_profile_packaged.seed + 1),
    run_merks_seed(merks_profile_packaged.seed + 2),
)
merks_signatures = Set(
    PB.canonical_fingerprint((run.records, run.state))
    for run in merks_ensemble
)
check(
    length(merks_signatures) > 1,
    "Merks three-seed stochastic probe produced no seed-sensitive outputs",
)

if isempty(failures)
    println("ProcessBigraphs Phase 17 case-study equivalence passed:")
    println("  Wortel: exact semantic and fixed-seed package/tutorial equality")
    println("  Merks: exact semantic and fixed-seed package/tutorial equality")
    println("  stochastic probes: exact replay plus seed-sensitive bounded outputs")
    println("  distributional or reproduction claim: none")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 case-study equivalence failed with $(
        length(failures)) error(s)")
end
