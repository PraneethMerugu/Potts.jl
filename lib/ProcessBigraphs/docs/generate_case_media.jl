using CairoMakie
using MakiePotts
using PottsToolkit
import CorePotts
import ProcessBigraphs as PB
import SciMLBase

CairoMakie.activate!(type="png")

const ASSET_ROOT = joinpath(@__DIR__, "src", "assets")
const FRAME_RATE = 12
const HOLD_FRAMES = 3
const PAPER_WIDTH_PX = 1800
const PAPER_SEQUENCE_HEIGHT_PX = 680
const PAPER_ANIMATION_HEIGHT_PX = 820
const VISUAL_FRAME_EVERY_MCS = 5
const VISUAL_HORIZON_MCS = 60
const WortelModel = PottsToolkit.ReferenceModels.Wortel2021
const MerksModel = PottsToolkit.ReferenceModels.Merks2006

module WortelCaseSource
include(joinpath(@__DIR__, "models", "case_studies", "wortel_2021.jl"))
end

module MerksCaseSource
include(joinpath(@__DIR__, "models", "case_studies", "merks_2006.jl"))
end

function render_frame(labels, values, mcs, key; label, units=nothing)
    ids = sort!(collect(Set(filter(!iszero, labels))))
    cells = [
        RenderCellMetadata(
            CellIdentity(id, 0),
            1;
            label="Cell $id",
        )
        for id in ids
    ]
    owners = map(labels) do id
        iszero(id) ?
            RenderOwner(MediumSite, 1) :
            RenderOwner(CellSite, id)
    end
    return PottsRenderFrame(
        mcs,
        owners,
        cells;
        channels=(
            RenderChannel(key, values; label, units),
        ),
        geometry=RenderGeometry(size(labels)),
    )
end

function wortel_frames()
    source = WortelCaseSource
    base = WortelModel.reduced_profile()
    profile = WortelModel.Profile(
        :visualization_cpu,
        base.dimensions;
        cell_side=base.cell_side,
        maximum_activity=base.maximum_activity,
        activity_strength=base.activity_strength,
        volume_strength=base.volume_strength,
        temperature=base.temperature,
        observation_every=base.observation_every,
        mcs=VISUAL_HORIZON_MCS,
        seed=base.seed,
        backend_claim=:cpu,
        deviations=(:documentation_visualization_profile,),
    )
    definition = WortelModel.model(profile)
    key = SiteChannelKey(:activity, Float32)
    integrator = SciMLBase.init(WortelModel.problem(definition))
    frames = PottsRenderFrame[]
    for mcs in 0:VISUAL_FRAME_EVERY_MCS:profile.mcs
        state = CorePotts.logical_state(integrator)
        labels = zeros(UInt64, profile.dimensions)
        activity = zeros(Float32, profile.dimensions)
        for site in eachindex(labels)
            owner = CorePotts.owner_at(state, site)
            labels[site] = CorePotts.is_cell_owner(owner) ?
                UInt64(CorePotts.value(CorePotts.cell_id(owner))) :
                UInt64(0)
            activity[site] =
                Float32(CorePotts.site_property_value(integrator, site))
        end
        push!(frames, render_frame(
            labels,
            activity,
            mcs,
            key;
            label="Act memory",
            units="activity",
        ))
        mcs == profile.mcs ||
            SciMLBase.step!(integrator, VISUAL_FRAME_EVERY_MCS)
    end
    return frames, key, profile
end

function merks_frames()
    profile = MerksModel.Profile(
        :visualization_cpu,
        (40, 40);
        cells=9,
        central_extent=34,
        target_area_sites=12.0,
        target_length_sites=12.0,
        subcycles_per_mcs=15,
        mcs=VISUAL_HORIZON_MCS,
        seed=UInt64(11),
        backend_claim=:cpu,
        deviations=(:documentation_visualization_profile,),
    )
    definition = MerksModel.model(profile)
    key = SiteChannelKey(:chemoattractant, Float64)
    runtime = PB.initialize_runtime(
        MerksModel.composite(definition),
        PB.SerialExecutor(root_seed=profile.seed),
    )
    scale = PB.TimeScale(2, 1, :second)
    frames = PottsRenderFrame[]
    initial = PB.materialize(PB.current_snapshot(runtime))
    push!(frames, render_frame(
        initial[PB.path("labels")],
        initial[PB.path("field")],
        0,
        key;
        label="Chemoattractant",
        units="concentration",
    ))
    for mcs in VISUAL_FRAME_EVERY_MCS:VISUAL_FRAME_EVERY_MCS:profile.mcs
        PB.run_until!(
            runtime,
            PB.LogicalTime(mcs * profile.subcycles_per_mcs, scale),
        )
        state = PB.materialize(PB.current_snapshot(runtime))
        push!(frames, render_frame(
            state[PB.path("labels")],
            state[PB.path("field")],
            mcs,
            key;
            label="Chemoattractant",
            units="concentration",
        ))
    end
    return frames, key, profile
end

function panel_label!(figure, row, column, text)
    Label(
        figure[row, column, TopLeft()],
        text;
        fontsize=22,
        font=:bold,
        color=:black,
        padding=(8, 0, 0, 8),
        halign=:left,
        valign=:top,
        tellwidth=false,
        tellheight=false,
    )
end

function add_field_contours!(axis, values, colorrange)
    low, high = colorrange
    high > low || return nothing
    levels = collect(range(low, high; length=9))[2:8]
    contour!(
        axis,
        values;
        levels,
        color=(:limegreen, 0.9),
        linewidth=1.4,
    )
end

function case_figure(
        frames,
        key;
        title,
        colorrange,
        colormap,
        boundary_color,
        contours,
        note)
    frame = Observable(first(frames))
    title_text = lift(frame) do current
        "$title · MCS $(frame_mcs(current))"
    end
    figure = Figure(
        size=(PAPER_WIDTH_PX, PAPER_ANIMATION_HEIGHT_PX),
        backgroundcolor=:white,
        fontsize=22,
    )
    Label(
        figure[0, 1:3],
        title_text;
        fontsize=30,
        font=:bold,
        color=:gray15,
    )
    cells_axis = Axis(
        figure[1, 1];
        title="Cell identity",
        xlabel="lattice x",
        ylabel="lattice y",
        aspect=DataAspect(),
    )
    cells = pottsplot!(
        cells_axis,
        frame;
        encoding=CellIdentityEncoding(),
        boundaries=true,
        boundary_width=1.2,
        medium_color=:gray96,
    )
    field_axis = Axis(
        figure[1, 2];
        title=String(key.name),
        xlabel="lattice x",
        ylabel="lattice y",
        aspect=DataAspect(),
    )
    field = pottsplot!(
        field_axis,
        frame;
        encoding=ChannelEncoding(key),
        colormap,
        colorrange,
        boundaries=true,
        boundary_color,
        boundary_width=1.1,
        medium_color=:gray96,
        nan_color=:gray90,
    )
    if contours
        values = lift(frame) do current
            channel(current, key).values
        end
        add_field_contours!(field_axis, values, colorrange)
    end
    Colorbar(figure[1, 3], field; label=String(key.name))
    panel_label!(figure, 1, 1, "A")
    panel_label!(figure, 1, 2, "B")
    Label(
        figure[2, 1:3],
        note;
        fontsize=18,
        color=:gray30,
        halign=:left,
    )
    colsize!(figure.layout, 1, Relative(0.45))
    colsize!(figure.layout, 2, Relative(0.45))
    colsize!(figure.layout, 3, Auto(0.1))
    colgap!(figure.layout, 14)
    return figure, frame, cells
end

function paper_sequence_figure(
        frames,
        key;
        title,
        colorrange,
        colormap,
        boundary_color,
        contours,
        note)
    selected = unique(round.(Int, range(1, length(frames); length=3)))
    sequence = frames[selected]
    figure = Figure(
        size=(PAPER_WIDTH_PX, PAPER_SEQUENCE_HEIGHT_PX),
        backgroundcolor=:white,
        fontsize=22,
    )
    Label(
        figure[0, 1:4],
        title;
        fontsize=30,
        font=:bold,
        color=:gray15,
    )
    last_plot = nothing
    for (column, frame) in enumerate(sequence)
        axis = Axis(
            figure[1, column];
            title="MCS $(frame_mcs(frame))",
            xlabel="lattice x",
            ylabel=column == 1 ? "lattice y" : "",
            aspect=DataAspect(),
        )
        last_plot = pottsplot!(
            axis,
            frame;
            encoding=ChannelEncoding(key),
            colormap,
            colorrange,
            boundaries=true,
            boundary_color,
            boundary_width=1.1,
            medium_color=:gray96,
            nan_color=:gray90,
        )
        contours &&
            add_field_contours!(axis, channel(frame, key).values, colorrange)
        panel_label!(
            figure,
            1,
            column,
            string(Char(Int('A') + column - 1)),
        )
    end
    Colorbar(figure[1, 4], last_plot; label=String(key.name))
    Label(
        figure[2, 1:4],
        note;
        fontsize=18,
        color=:gray30,
        halign=:left,
    )
    colsize!(figure.layout, 4, Auto(0.08))
    colgap!(figure.layout, 18)
    return figure
end

function expanded_frames(frames)
    return reduce(
        vcat,
        (fill(frame, HOLD_FRAMES) for frame in frames);
        init=PottsRenderFrame[],
    )
end

function save_case_media(
        stem,
        frames,
        key;
        title,
        colorrange,
        colormap,
        boundary_color,
        contours,
        note)
    figure, current, _ = case_figure(
        frames,
        key;
        title,
        colorrange,
        colormap,
        boundary_color,
        contours,
        note,
    )
    sequence = paper_sequence_figure(
        frames,
        key;
        title,
        colorrange,
        colormap,
        boundary_color,
        contours,
        note,
    )
    save(joinpath(ASSET_ROOT, "$stem-state.png"), sequence; px_per_unit=1)
    record_potts(
        joinpath(ASSET_ROOT, "$stem-animation.mp4"),
        figure,
        expanded_frames(frames);
        framerate=FRAME_RATE,
        update! = frame -> (current[] = frame),
    )
end

function save_trace(wortel, merks, wortel_profile, merks_profile)
    wortel_mcs = frame_mcs.(wortel)
    wortel_occupied = [
        count(site -> owner_at(frame, site).kind === CellSite,
            CartesianIndices(frame_size(frame)))
        for frame in wortel
    ]
    activity_key = SiteChannelKey(:activity, Float32)
    wortel_active = [
        count(>(0), channel(frame, activity_key).values)
        for frame in wortel
    ]
    merks_mcs = frame_mcs.(merks)
    chemoattractant_key = SiteChannelKey(:chemoattractant, Float64)
    field_mass = [
        sum(channel(frame, chemoattractant_key).values) for frame in merks
    ]
    cell_count = [
        length(Set(
            owner_at(frame, site).id
            for site in CartesianIndices(frame_size(frame))
            if owner_at(frame, site).kind === CellSite
        ))
        for frame in merks
    ]

    figure = Figure(
        size=(PAPER_WIDTH_PX, 760),
        backgroundcolor=:white,
        fontsize=22,
    )
    Label(
        figure[0, 1:2],
        "Fixed-seed bounded observations";
        fontsize=30,
        font=:bold,
        color=:gray15,
    )
    wortel_axis = Axis(
        figure[1, 1];
        title="Wortel 2021 · 60-MCS visualization profile",
        xlabel="MCS",
        ylabel="lattice sites",
        xticks=wortel_mcs,
    )
    lines!(wortel_axis, wortel_mcs, wortel_occupied;
        color=:steelblue, linewidth=3, label="occupied")
    scatter!(wortel_axis, wortel_mcs, wortel_occupied; color=:steelblue)
    lines!(wortel_axis, wortel_mcs, wortel_active;
        color=:darkorange, linewidth=3, label="active")
    scatter!(wortel_axis, wortel_mcs, wortel_active; color=:darkorange)
    axislegend(wortel_axis; position=:lb)

    merks_axis = Axis(
        figure[1, 2];
        title="Merks 2006 · 60-MCS visualization profile",
        xlabel="MCS",
        ylabel="field mass",
        xticks=collect(merks_mcs),
    )
    lines!(merks_axis, merks_mcs, field_mass;
        color=:darkorange, linewidth=3, label="field mass")
    scatter!(merks_axis, merks_mcs, field_mass; color=:darkorange)
    cells_axis = Axis(
        figure[1, 2];
        yaxisposition=:right,
        ylabel="occupied cell identities",
        yticks=0:1:merks_profile.cells,
        backgroundcolor=:transparent,
    )
    hidespines!(cells_axis)
    hidexdecorations!(cells_axis)
    ylims!(cells_axis, 0, merks_profile.cells + 0.5)
    lines!(cells_axis, merks_mcs, cell_count;
        color=:steelblue, linewidth=3)
    scatter!(cells_axis, merks_mcs, cell_count; color=:steelblue)
    linkxaxes!(merks_axis, cells_axis)
    Label(
        figure[2, 2],
        "Field mass $(round(first(field_mass); digits=3)) → $(round(last(field_mass); digits=3)) · cells $(first(cell_count)) → $(last(cell_count))";
        fontsize=18,
        color=:gray25,
    )
    Label(
        figure[3, 1:2],
        "Reduced fixed-seed diagnostics · not speed–persistence, lacuna, branch-point, or ensemble reproduction";
        fontsize=17,
        color=:gray30,
        halign=:left,
    )
    save(joinpath(ASSET_ROOT, "case-traces.png"), figure; px_per_unit=1)
end

wortel, wortel_key, wortel_profile = wortel_frames()
merks, merks_key, merks_profile = merks_frames()
save_case_media(
    "wortel",
    wortel,
    wortel_key;
    title="Wortel et al. (2021) · reduced Act-CPM trajectory",
    colorrange=(0.0, Float64(maximum(
        maximum(channel(frame, wortel_key).values) for frame in wortel))),
    colormap=[:black, :darkgreen, :gold, :red],
    boundary_color=(:white, 0.85),
    contours=false,
    note="Paper-inspired Act-memory time strip · fixed seed · bounded mechanism check, not UCSP or figure reproduction",
)
save_case_media(
    "merks",
    merks,
    merks_key;
    title="Merks et al. (2006) · reduced vasculogenesis trajectory",
    colorrange=(0.0, maximum(
        maximum(channel(frame, merks_key).values) for frame in merks)),
    colormap=:grays,
    boundary_color=(:firebrick, 0.95),
    contours=true,
    note="Paper-inspired cell/field time strip · fixed seed · bounded integration check, not network morphometry or figure reproduction",
)
save_trace(wortel, merks, wortel_profile, merks_profile)

println("Makie case-study media generated:")
for name in (
        "wortel-state.png",
        "wortel-animation.mp4",
        "merks-state.png",
        "merks-animation.mp4",
        "case-traces.png")
    path = joinpath(ASSET_ROOT, name)
    println("  $name: $(filesize(path)) bytes")
end
