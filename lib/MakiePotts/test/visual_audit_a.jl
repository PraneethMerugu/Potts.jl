using CairoMakie
using MakiePotts
import CorePotts
import Makie

CairoMakie.activate!(type = "png")

function planar_audit_frame()
    dims = (42, 28)
    owners = fill(RenderOwner(MediumSite, 1), dims)
    cells = RenderCellMetadata[]
    centers = ((9, 8), (20, 8), (32, 9), (14, 20), (29, 20))
    radii = ((6, 5), (7, 5), (6, 6), (8, 5), (8, 5))
    types = (1, 2, 3, 1, 2)
    signals = (0.15, 0.42, missing, 0.58, 0.91)
    signal_values = Dict{CellIdentity, Union{Missing, Float64}}()
    for (index, ((cx, cy), (rx, ry), cell_type, signal)) in
            enumerate(zip(centers, radii, types, signals))
        identity = CellIdentity(index, index == 4 ? 2 : 0)
        push!(cells, RenderCellMetadata(identity, cell_type))
        signal_values[identity] = signal
        for j in axes(owners, 2), i in axes(owners, 1)
            ((i - cx) / rx)^2 + ((j - cy) / ry)^2 <= 1 || continue
            owners[i, j] = RenderOwner(CellSite, index)
        end
    end
    for j in 10:18, i in 1:4
        owners[i, j] = RenderOwner(ObstacleSite, 2)
    end
    key = CellChannelKey(:signal, Float64)
    geometry = RenderGeometry(dims;
        spacing = (0.6, 0.8), origin = (-3.0, 1.5))
    provenance = RenderProvenance(
        :visual_audit, typeof(owners), :host, RenderRequest())
    frame = PottsRenderFrame(120, owners, cells;
        channels = (RenderChannel(key, signal_values;
            label = "Signal", units = "a.u."),),
        geometry, provenance)
    return frame, key
end

function slice_audit_frame()
    dims = (28, 12, 22)
    owners = fill(CorePotts.MediumOwner(1), dims)
    centers = ((8, 6, 7), (15, 6, 11), (22, 6, 16))
    radii = ((6, 4, 5), (7, 5, 6), (6, 4, 5))
    for (id, ((cx, cy, cz), (rx, ry, rz))) in
            enumerate(zip(centers, radii))
        for k in axes(owners, 3), j in axes(owners, 2), i in axes(owners, 1)
            ((i - cx) / rx)^2 + ((j - cy) / ry)^2 +
                ((k - cz) / rz)^2 <= 1 || continue
            owners[i, j, k] = CorePotts.CellOwner(id)
        end
    end
    obstacle = CartesianIndex(2, 6, 11)
    owners[obstacle] = CorePotts.MediumOwner(2)
    state = CorePotts.LogicalPottsState(owners, CorePotts.CellCapacity(3);
        cell_types = Dict(
            CorePotts.CellID(1) => CorePotts.CellTypeID(1),
            CorePotts.CellID(2) => CorePotts.CellTypeID(2),
            CorePotts.CellID(3) => CorePotts.CellTypeID(3)),
        generations = (1, 4, 2),
        medium_domains = (CorePotts.MediumID(1), CorePotts.MediumID(2)))
    domain = CorePotts.CartesianDomain(dims;
        spacing = (0.5, 1.0, 0.75),
        obstacles = (obstacle => CorePotts.MediumOwner(2),))
    proposal = CorePotts.first_shell_relation(CorePotts.ProposalRole(), Val(3))
    surface = CorePotts.first_shell_relation(CorePotts.SurfaceRole(), Val(3))
    tracker = CorePotts.BoundaryMeasureTracker(
        CorePotts.BoundaryEdgeCount(), surface)
    model = CorePotts.PottsModel(proposal, tracker)
    problem = CorePotts.PottsProblem(model, state, domain, (0, 1))
    request = RenderRequest(extent = OrthogonalSlice(2, 6))
    return renderframe(state, problem, request; mcs = 120)
end

frame, signal_key = planar_audit_frame()
slice_frame = slice_audit_frame()

figure = Figure(
    size = (1540, 920),
    backgroundcolor = :white,
    fontsize = 18,
)

type_axis = Axis(figure[1, 1];
    title = "Cell type · categorical",
    xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
type_plot = pottsplot!(type_axis, frame;
    boundaries = true, boundary_width = 0.9,
    medium_color = :gray15, obstacle_color = :gray48)
potts_legend(figure[1, 2], type_plot;
    title = "Ownership", framevisible = false)

signal_axis, signal_plot = Makie.with_theme(potts_theme(
        medium_color = :gray95,
        obstacle_color = :gray22,
        boundary_color = (:white, 0.8),
        boundary_width = 0.8,
    )) do
    axis = Axis(figure[1, 3];
        title = "Requested channel · continuous + missing",
        xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
    plot = pottsplot!(axis, frame;
        encoding = ChannelEncoding(signal_key),
        colormap = :magma,
        boundaries = true,
        nan_color = :gray82)
    return axis, plot
end
signal_key_layout = GridLayout()
figure[1, 4] = signal_key_layout
Colorbar(signal_key_layout[1, 1], signal_plot; label = "Signal (a.u.)")
Legend(signal_key_layout[2, 1],
    [PolyElement(color = :gray95), PolyElement(color = :gray82),
        PolyElement(color = :gray22)],
    ["Medium", "Missing", "Obstacle"];
    framevisible = false, orientation = :vertical)

slice_axes = frame_geometry(slice_frame).source_axes
slice_axis = Axis(figure[2, 1];
    title = "Orthogonal 3D slice · source axes $(slice_axes)",
    xlabel = "source axis $(slice_axes[1]) (μm)",
    ylabel = "source axis $(slice_axes[2]) (μm)",
    aspect = DataAspect())
slice_plot = pottsplot!(slice_axis, slice_frame;
    encoding = CellIdentityEncoding(),
    boundaries = true, boundary_width = 0.9,
    medium_color = :gray12, obstacle_color = :gray50)
potts_legend(figure[2, 2], slice_plot;
    title = "Generation-aware identity", framevisible = false)

transformed_axis = Axis(figure[2, 3];
    title = "Makie transform · translated (+4, −2 μm)",
    xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
transformed_plot = pottsplot!(transformed_axis, frame;
    boundaries = true, boundary_width = 0.9,
    medium_color = :gray15, obstacle_color = :gray48)
Makie.translate!(transformed_plot, 4, -2, 0)
Makie.autolimits!(transformed_axis)
potts_legend(figure[2, 4], transformed_plot;
    title = "Transformed recipe", framevisible = false)

for column in (1, 3)
    colsize!(figure.layout, column, Relative(0.39))
end
for column in (2, 4)
    colsize!(figure.layout, column, Auto(0.17))
end
rowgap!(figure.layout, 34)
colgap!(figure.layout, 18)

output = only(ARGS)
save(output, figure; px_per_unit = 2)

expected_type_limits = Makie.Rect3d(
    Makie.Point3d(-3.0, 1.5, 0), Makie.Vec3d(25.2, 22.4, 0))
Makie.data_limits(type_plot) ≈ expected_type_limits ||
    error("categorical plot limits changed during Visual Audit A")
expected_transformed_limits = Makie.Rect3d(
    Makie.Point3d(1.0, -0.5, 0), Makie.Vec3d(25.2, 22.4, 0))
Makie.boundingbox(transformed_plot) ≈ expected_transformed_limits ||
    error("transformed plot bounds changed during Visual Audit A")
frame_geometry(slice_frame).source_axes == (1, 3) ||
    error("slice source-axis provenance was not preserved")
isfile(output) && filesize(output) > 20_000 ||
    error("Visual Audit A did not produce a nonempty publication render")

println("Visual Audit A render written to $output")
