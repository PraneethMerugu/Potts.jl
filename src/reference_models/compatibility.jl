# Phase 17 keeps the supported flat `ReferenceModels.merks2006_*` spellings
# while the model-family module becomes the canonical ownership boundary.
merks2006_ambiguity_profile(; kwargs...) =
    CorePotts.Merks2006AmbiguityProfile(; kwargs...)

function merks2006_initial_labels(;
        shape::NTuple{2,<:Integer}=(500, 500),
        cells::Integer=282,
        central_extent::Integer=333,
        target_area_sites::Real=100.0,
        seed::Integer=2006)
    spec = Merks2006.Profile(
        :legacy_forwarding,
        shape;
        cells,
        central_extent,
        target_area_sites,
        seed,
        deviations=(:legacy_flat_call_shape,),
    )
    return Merks2006.initial_labels(spec)
end

function _legacy_merks_definition(
        labels;
        subcycles_per_mcs::Integer,
        root_seed::Integer,
        profile)
    source_profile = profile isa CorePotts.Merks2006AmbiguityProfile ?
        profile : CorePotts.Merks2006AmbiguityProfile()
    cells = Int(maximum(labels; init=zero(eltype(labels))))
    spec = Merks2006.Profile(
        :legacy_forwarding,
        size(labels);
        cells=max(cells, 1),
        central_extent=minimum(size(labels)),
        subcycles_per_mcs,
        seed=root_seed,
        volume_strength=source_profile.volume_strength,
        source_length_strength=source_profile.source_length_strength,
        deviations=(:legacy_flat_call_shape,),
    )
    return Merks2006.model(spec)
end

function merks2006_composite(
        labels,
        declaration;
        time_scale=ProcessBigraphs.TimeScale(2, 1, :second),
        resource_authorization=(
            backend=:cpu,
            precision=:float64,
            residency=:host,
        ),
        subcycles_per_mcs::Integer=15,
        root_seed::Integer=2006,
        profile=CorePotts.Merks2006AmbiguityProfile(),
        initial_field=zeros(Float64, size(labels)))
    time_scale == ProcessBigraphs.TimeScale(2, 1, :second) ||
        throw(ArgumentError(
            "the retained Merks call shape requires a two-second time scale"))
    definition = _legacy_merks_definition(
        labels;
        subcycles_per_mcs,
        root_seed,
        profile,
    )
    return Merks2006.composite(
        definition;
        labels=UInt64.(labels),
        declaration,
        initial_field,
        resource_authorization,
    )
end

function merks2006_native_composite(
        labels;
        time_scale=ProcessBigraphs.TimeScale(2, 1, :second),
        initial_field=zeros(Float64, size(labels)),
        subcycles_per_mcs::Integer=15,
        root_seed::Integer=2006,
        profile=CorePotts.Merks2006AmbiguityProfile())
    time_scale == ProcessBigraphs.TimeScale(2, 1, :second) ||
        throw(ArgumentError(
            "the retained Merks call shape requires a two-second time scale"))
    definition = _legacy_merks_definition(
        labels;
        subcycles_per_mcs,
        root_seed,
        profile,
    )
    return Merks2006.composite(
        definition;
        labels=UInt64.(labels),
        initial_field,
    )
end

function merks2006_observation_plan(
        time_scale=ProcessBigraphs.TimeScale(2, 1, :second);
        subcycles_per_mcs::Integer=15)
    time_scale == ProcessBigraphs.TimeScale(2, 1, :second) ||
        throw(ArgumentError(
            "the retained Merks call shape requires a two-second time scale"))
    base = Merks2006.reduced_profile()
    spec = Merks2006.Profile(
        :legacy_forwarding,
        base.dimensions;
        cells=base.cells,
        central_extent=base.central_extent,
        target_area_sites=base.target_area_sites,
        target_length_sites=base.target_length_sites,
        subcycles_per_mcs,
        mcs=base.mcs,
        seed=base.seed,
        deviations=(:legacy_flat_call_shape,),
    )
    return Merks2006.observation_plan(spec)
end

# CNV remains outside the Phase 17 model-productization scope. Its existing
# call shapes remain forwarding compatibility entry points.
cnv2012_ambiguity_profile(; kwargs...) =
    CorePotts.CNV2012AmbiguityProfile(; kwargs...)
cnv2012_initial_state(; kwargs...) =
    CorePotts.cnv2012_initial_state(; kwargs...)
cnv2012_composite(args...; kwargs...) =
    CorePotts.cnv2012_composite(args...; kwargs...)
cnv2012_native_composite(args...; kwargs...) =
    CorePotts.cnv2012_native_composite(args...; kwargs...)
cnv2012_observation_plan(args...; kwargs...) =
    CorePotts.cnv2012_observation_plan(args...; kwargs...)
