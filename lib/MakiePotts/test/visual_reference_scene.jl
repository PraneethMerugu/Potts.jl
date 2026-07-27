using CairoMakie
using MakiePotts

function visual_reference_frame()
    dims = (32, 20)
    owners = fill(RenderOwner(MediumSite, 1), dims)
    cells = RenderCellMetadata[]
    values = Dict{CellIdentity, Union{Missing, Float64}}()
    specifications = (
        (1, (8, 7), (6, 5), 1, 0.18),
        (2, (20, 7), (7, 5), 2, 0.47),
        (3, (12, 15), (7, 4), 1, missing),
        (4, (24, 15), (6, 4), 3, 0.86),
    )
    for (id, (cx, cy), (rx, ry), cell_type, value) in specifications
        identity = CellIdentity(id, id == 3 ? 2 : 0)
        push!(cells, RenderCellMetadata(identity, cell_type))
        values[identity] = value
        for site in CartesianIndices(owners)
            x, y = Tuple(site)
            ((x - cx) / rx)^2 + ((y - cy) / ry)^2 <= 1 || continue
            owners[site] = RenderOwner(CellSite, id)
        end
    end
    for y in 8:14, x in 1:3
        owners[x, y] = RenderOwner(ObstacleSite, 2)
    end
    key = CellChannelKey(:reference_signal, Float64)
    geometry = RenderGeometry(dims;
        spacing = (0.6, 0.8), origin = (-1.2, 0.5))
    frame = PottsRenderFrame(80, owners, cells;
        channels = (RenderChannel(key, values;
            label = "Signal", units = "a.u."),),
        geometry)
    return frame, key
end

function visual_reference_figure()
    frame, key = visual_reference_frame()
    figure = Figure(
        size = (920, 380),
        backgroundcolor = :white,
        fontsize = 14,
    )

    categorical_axis = Axis(figure[1, 1];
        title = "Cell type",
        xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
    categorical = pottsplot!(categorical_axis, frame;
        boundaries = true,
        boundary_width = 0.8,
        medium_color = :gray18,
        obstacle_color = :gray48)
    potts_legend(figure[1, 2], categorical;
        title = "Ownership", framevisible = false)

    continuous_axis = Axis(figure[1, 3];
        title = "Cell signal",
        xlabel = "x (μm)", ylabel = "y (μm)", aspect = DataAspect())
    continuous = pottsplot!(continuous_axis, frame;
        encoding = ChannelEncoding(key),
        colormap = :magma,
        boundaries = true,
        boundary_color = (:white, 0.8),
        boundary_width = 0.8,
        medium_color = :gray95,
        nan_color = :gray78,
        obstacle_color = :gray20)
    Colorbar(figure[1, 4], continuous; label = "Signal (a.u.)")

    colsize!(figure.layout, 1, Relative(0.39))
    colsize!(figure.layout, 2, Auto(0.16))
    colsize!(figure.layout, 3, Relative(0.39))
    colsize!(figure.layout, 4, Auto(0.06))
    colgap!(figure.layout, 12)
    return figure
end
