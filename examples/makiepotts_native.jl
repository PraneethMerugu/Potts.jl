using GLMakie
using MakiePotts

GLMakie.activate!()

dims = (72, 48)
owners = fill(RenderOwner(MediumSite, 1), dims)
cells = RenderCellMetadata[]

for (id, center, radius, cell_type) in (
        (1, (20, 18), (13, 10), 1),
        (2, (43, 18), (14, 11), 2),
        (3, (31, 34), (15, 10), 3))
    identity = CellIdentity(id, 0)
    push!(cells, RenderCellMetadata(identity, cell_type))
    cx, cy = center
    rx, ry = radius
    for site in CartesianIndices(owners)
        x, y = Tuple(site)
        ((x - cx) / rx)^2 + ((y - cy) / ry)^2 <= 1 || continue
        owners[site] = RenderOwner(CellSite, id)
    end
end

for y in 17:31, x in 1:6
    owners[x, y] = RenderOwner(ObstacleSite, 2)
end

frame = PottsRenderFrame(0, owners, cells;
    geometry = RenderGeometry(dims; spacing = (0.5, 0.5)))

figure, axis, plot = plot(frame;
    axis = (; title = "Native MakiePotts recipe",
        xlabel = "x (μm)", ylabel = "y (μm)"),
    boundaries = true)
potts_legend(figure[1, 2], plot)

# Ordinary Makie composition remains available on the returned axis.
scatter!(axis, [4.0], [4.0]; marker = :cross, color = :white, markersize = 18)

figure
