module MakiePottsBackendSmoke

using MakiePotts
import Makie

export smoke_figure

function smoke_frame(phase::Integer = 0)
    identity = CellIdentity(7, 3)
    cells = [RenderCellMetadata(identity, 2; label = "Backend cell")]
    owners = RenderOwner[
        RenderOwner(MediumSite, 1) RenderOwner(CellSite, 7) RenderOwner(CellSite, 7);
        RenderOwner(ObstacleSite, 2) RenderOwner(CellSite, 7) RenderOwner(MediumSite, 1);
        RenderOwner(ObstacleSite, 2) RenderOwner(MediumSite, 1) RenderOwner(MediumSite, 1);
        RenderOwner(MediumSite, 1) RenderOwner(MediumSite, 1) RenderOwner(MediumSite, 1);
    ]
    phase == 0 || reverse!(owners; dims = 1)
    geometry = RenderGeometry(size(owners);
        spacing = (0.5, 1.25), origin = (-1.0, 2.0))
    return PottsRenderFrame(phase, owners, cells; geometry)
end

function smoke_figure()
    first_frame = smoke_frame()
    observable = Makie.Observable(first_frame)
    figure, axis, plot = Makie.plot(observable;
        boundaries = true, boundary_width = 1.5)
    plot isa PottsPlot || error("backend did not construct PottsPlot")
    axis isa Makie.Axis || error("backend did not construct Axis")
    length(plot.plots) == 3 ||
        error("PottsPlot did not retain its three atomic children")
    children = copy(plot.plots)
    observable[] = smoke_frame(1)
    plot.plots == children ||
        error("reactive update reconstructed PottsPlot children")
    frame_mcs(plot.frame[]) == 1 ||
        error("reactive update did not publish the replacement frame")
    expected = Makie.Rect3d(
        Makie.Point3d(-1.0, 2.0, 0), Makie.Vec3d(2.0, 3.75, 0))
    Makie.data_limits(plot) == expected ||
        error("backend changed physical PottsPlot limits")
    return figure, plot
end

end
