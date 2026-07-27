using CairoMakie
using MakiePotts

CairoMakie.activate!(type = "png")

function audit_frame()
    dims = (42, 28)
    owners = fill(RenderOwner(MediumSite, 1), dims)
    cells = RenderCellMetadata[]
    centers = ((10, 9), (20, 9), (31, 9), (14, 20), (27, 20))
    radii = ((6, 5), (7, 5), (6, 6), (8, 5), (8, 5))
    types = (1, 2, 3, 1, 2)
    signals = (0.15, 0.42, 0.76, 0.58, 0.91)
    signal_values = Dict{CellIdentity, Float64}()
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
    for j in 11:18, i in 1:4
        owners[i, j] = RenderOwner(ObstacleSite, 2)
    end
    key = CellChannelKey(:signal, Float64)
    geometry = RenderGeometry(dims; spacing = (0.6, 0.6))
    frame = PottsRenderFrame(120, owners, cells;
        channels = (RenderChannel(key, signal_values;
            label = "Signal", units = "a.u."),),
        geometry)
    return frame, key
end

frame, signal_key = audit_frame()
figure = Figure(size = (1240, 480), backgroundcolor = :white)

type_axis = Axis(figure[1, 1];
    title = "Cell type · categorical",
    xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
type_plot = pottsplot!(type_axis, frame;
    boundaries = true, boundary_width = 0.8,
    obstacle_color = :gray35)
potts_legend(figure[1, 2], type_plot;
    title = "Ownership", framevisible = false)

signal_axis = Axis(figure[1, 3];
    title = "Requested cell channel · continuous",
    xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
signal_plot = pottsplot!(signal_axis, frame;
    encoding = ChannelEncoding(signal_key),
    colormap = :magma, boundaries = true,
    boundary_color = (:white, 0.75), boundary_width = 0.7,
    nan_color = :gray92, obstacle_color = :gray25)
Colorbar(figure[1, 4], signal_plot; label = "Signal (a.u.)")

colsize!(figure.layout, 1, Relative(0.42))
colsize!(figure.layout, 2, Auto(0.18))
colsize!(figure.layout, 3, Relative(0.42))
colgap!(figure.layout, 20)

save(only(ARGS), figure; px_per_unit = 2)
