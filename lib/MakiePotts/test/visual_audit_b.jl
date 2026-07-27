using CairoMakie
using MakiePotts
import Makie
include(joinpath(@__DIR__, "downstream_fixture.jl"))
using .DownstreamFixture

CairoMakie.activate!(type = "png")

function canonical_frame(mcs::Integer)
    dims = (48, 32)
    owners = fill(RenderOwner(MediumSite, 1), dims)
    cells = RenderCellMetadata[
        RenderCellMetadata(CellIdentity(1, 2), 1; label = "Leader"),
        RenderCellMetadata(CellIdentity(2, 0), 2; label = "Follower A"),
        RenderCellMetadata(CellIdentity(3, 4), 3; label = "Follower B"),
        RenderCellMetadata(CellIdentity(4, 1), 1; label = "Follower C"),
        RenderCellMetadata(CellIdentity(5, 3), 2; label = "Follower D"),
    ]
    phase = clamp(Float64(mcs) / 100, 0, 1)
    centers = (
        (9.0 + 4phase, 9.0 + phase),
        (22.0 + 2phase, 9.0 + 3phase),
        (37.0 - 2phase, 10.0 + phase),
        (15.0 + 3phase, 23.0 - 2phase),
        (33.0 - phase, 23.0 + phase),
    )
    radii = ((7.0, 6.0), (8.0, 6.0), (7.0, 6.0), (9.0, 6.0), (9.0, 6.0))
    for (index, ((cx, cy), (rx, ry))) in enumerate(zip(centers, radii))
        for j in axes(owners, 2), i in axes(owners, 1)
            ((i - cx) / rx)^2 + ((j - cy) / ry)^2 <= 1 || continue
            owners[i, j] = RenderOwner(CellSite, index)
        end
    end
    for j in 13:21, i in 1:4
        owners[i, j] = RenderOwner(ObstacleSite, 2)
    end
    geometry = RenderGeometry(dims;
        spacing = (0.5, 0.75), origin = (-2.0, 1.0))
    provenance = RenderProvenance(
        :visual_audit_b, typeof(owners), :host, RenderRequest())
    return PottsRenderFrame(mcs, owners, cells; geometry, provenance)
end

function downstream_frame()
    shape = (36, 24)
    spatial = RenderGeometry(shape;
        spacing = (0.6, 0.6), origin = (0.0, -1.0))
    identities = (
        CellIdentity(11, 4),
        CellIdentity(29, 8),
        CellIdentity(47, 1),
    )
    metadata = (
        RenderCellMetadata(identities[1], 2; label = "Alpha"),
        RenderCellMetadata(identities[2], 5; label = "Beta"),
        RenderCellMetadata(identities[3], 7; label = "Gamma"),
    )
    centers = ((9.0, 8.0), (24.0, 8.0), (18.0, 18.0))
    owner_array = fill(RenderOwner(MediumSite, 1), shape)
    for j in axes(owner_array, 2), i in axes(owner_array, 1)
        distances = map(((cx, cy),) -> (i - cx)^2 + (j - cy)^2, centers)
        nearest = argmin(distances)
        distances[nearest] <= 82 &&
            (owner_array[i, j] = RenderOwner(CellSite, identities[nearest].id))
    end
    for j in 18:24, i in 32:36
        owner_array[i, j] = RenderOwner(ObstacleSite, 2)
    end
    site_records = Dict(site => owner_array[site]
        for site in CartesianIndices(shape))
    identity_records = Dict(item.identity => item for item in metadata)
    owner_records = Dict(item.identity.id => item for item in metadata)
    values = Matrix{Float64}(undef, shape)
    for j in axes(values, 2), i in axes(values, 1)
        values[i, j] = clamp(0.05 + 0.72 * (i - 1) / (shape[1] - 1) +
                                    0.18 * (j - 1) / (shape[2] - 1), 0, 1)
    end
    values[map(owner -> owner == RenderOwner(ObstacleSite, 2), owner_array)] .= NaN
    stream_records = Dict{Any, Any}(
        DownstreamFixture.SIGNAL_KEY => RenderChannel(
            DownstreamFixture.SIGNAL_KEY, values;
            label = "Foreign signal", units = "a.u."),
    )
    lineage = RenderProvenance(
        :unrelated_downstream, DownstreamFixture.ColumnarFrame,
        :host, RenderRequest())
    return DownstreamFixture.ColumnarFrame(
        100, shape, spatial, site_records, identity_records,
        owner_records, stream_records, lineage)
end

frames = canonical_frame.((0, 50, 100))
current_frame = frames[end]
foreign_frame = downstream_frame()
foreign_encoding = DownstreamFixture.RootSignalEncoding()

category_keys = map(frames) do frame
    map(entry -> entry.color_key, legend_entries(frame, CellTypeEncoding()))
end
all(keys -> keys == first(category_keys), category_keys) ||
    error("categorical identity keys drifted across the MCS sequence")
assert_render_frame_conformance(foreign_frame)
foreign_label = inspection_label(
    foreign_frame, foreign_encoding, CartesianIndex(10, 8))
occursin("Square-root signal", foreign_label) ||
    error("downstream inspection label lost the custom encoding label")
occursin("a.u.", foreign_label) ||
    error("downstream inspection label lost channel units")

figure = Figure(
    size = (1600, 940),
    backgroundcolor = :white,
    fontsize = 17,
)

Label(figure[0, 1:2], "MakiePotts · native recipes in a standard Makie composition";
    fontsize = 28, font = :bold, tellwidth = false)

hero = GridLayout()
figure[1, 1] = hero
hero_axis = Axis(hero[1, 1];
    title = "Canonical frame · categorical cell type",
    xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
hero_plot = pottsplot!(hero_axis, current_frame;
    boundaries = true, boundary_width = 0.85,
    medium_color = :gray93, obstacle_color = :gray30,
    boundary_color = (:black, 0.72))
potts_legend(hero[1, 2], hero_plot;
    title = "Cell type", framevisible = false, patchsize = (26, 18))

foreign = GridLayout()
figure[1, 2] = foreign
foreign_axis = Axis(foreign[1, 1];
    title = "Downstream frame + downstream encoding",
    xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
foreign_plot = pottsplot!(foreign_axis, foreign_frame;
    encoding = foreign_encoding,
    colormap = :viridis,
    boundaries = true, boundary_width = 0.65,
    medium_color = :gray94, obstacle_color = :gray25,
    boundary_color = (:white, 0.72), nan_color = :gray78)
Colorbar(foreign[1, 2], foreign_plot;
    label = "Square-root signal (a.u.)", width = 18)

sequence = GridLayout()
figure[2, 1] = sequence
Label(sequence[0, 1:3], "Stable categorical identity across Monte Carlo time";
    fontsize = 20, font = :bold, tellwidth = false)
sequence_plots = PottsPlot[]
for (column, frame) in enumerate(frames)
    axis = Axis(sequence[1, column];
        title = "MCS $(frame_mcs(frame))",
        xlabel = column == 2 ? "x (μm)" : "",
        ylabel = column == 1 ? "y (μm)" : "",
        aspect = DataAspect())
    plot = pottsplot!(axis, frame;
        boundaries = true, boundary_width = 0.55,
        medium_color = :gray93, obstacle_color = :gray30,
        boundary_color = (:black, 0.65))
    push!(sequence_plots, plot)
    column == 1 || hideydecorations!(axis; grid = false)
end

timeseries = GridLayout()
figure[2, 2] = timeseries
series_axis = Axis(timeseries[1, 1];
    title = "Ordinary Makie time series",
    xlabel = "Monte Carlo step", ylabel = "Interface energy (a.u.)")
mcs_values = collect(0:10:100)
energy_values = @. 78 - 0.34mcs_values + 3.2sin(mcs_values / 14)
lines!(series_axis, mcs_values, energy_values;
    color = :dodgerblue3, linewidth = 3, label = "Interface energy")
scatter!(series_axis, mcs_values, energy_values;
    color = :dodgerblue3, markersize = 7)
current_mcs = Observable(100.0)
current_energy = Observable(energy_values[end])
vlines!(series_axis, lift(value -> [value], current_mcs);
    color = :orangered3, linewidth = 2.5, linestyle = :dash,
    label = "Current frame")
scatter!(series_axis, current_mcs, current_energy;
    color = :orangered3, marker = :diamond, markersize = 15)
xlims!(series_axis, -3, 105)
axislegend(series_axis; position = :rt, framevisible = false)
Label(timeseries[2, 1],
    lift(value -> "Linked marker · MCS $(round(Int, value))", current_mcs);
    tellwidth = false, color = :gray35)

colsize!(figure.layout, 1, Relative(0.61))
colsize!(figure.layout, 2, Relative(0.39))
rowsize!(figure.layout, 1, Relative(0.53))
rowsize!(figure.layout, 2, Relative(0.47))
rowgap!(figure.layout, 26)
colgap!(figure.layout, 30)

output = only(ARGS)
save(output, figure; px_per_unit = 2)

expected_bounds = Makie.Rect3d(
    Makie.Point3d(-2.0, 1.0, 0), Makie.Vec3d(24.0, 24.0, 0))
Makie.data_limits(hero_plot) ≈ expected_bounds ||
    error("canonical physical bounds changed during Visual Audit B")
all(plot -> Makie.data_limits(plot) ≈ expected_bounds, sequence_plots) ||
    error("MCS sequence geometry drifted during Visual Audit B")
map(plot -> length(plot.plots), (hero_plot, foreign_plot)) == (3, 3) ||
    error("native recipes no longer have the stable three-child composition")
isfile(output) && filesize(output) > 30_000 ||
    error("Visual Audit B did not produce a nonempty publication render")

println("Visual Audit B render written to $output")
