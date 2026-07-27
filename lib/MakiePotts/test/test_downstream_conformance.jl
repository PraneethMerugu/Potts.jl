using .DownstreamFixture

@testset "downstream protocol conformance and Makie journey" begin
    foreign = DownstreamFixture.columnar_frame()
    replacement = DownstreamFixture.columnar_frame(1)

    @test Base.isvalid(render_frame_conformance(foreign))
    @test assert_render_frame_conformance(foreign) === foreign
    @test frame_size(foreign) == (4, 3)
    @test frame_geometry(foreign).origin == (-1.5, 2.0)
    @test cell_metadata(foreign, CellIdentity(11, 4)).label == "Alpha"
    @test cell_metadata(
        foreign, RenderOwner(CellSite, 29)).identity == CellIdentity(29, 8)

    encoded = encode(foreign, DownstreamFixture.RootSignalEncoding())
    @test encoding_kind(encoded.encoding) === ContinuousEncoding
    @test encoded.label == "Square-root signal"
    @test encoded.units == "a.u."
    @test isnan(encoded.values[3, 3])
    @test encoded.values[2, 1] ≈ sqrt(0.1)

    observable = Makie.Observable(foreign)
    figure, axis, plot = Makie.plot(
        observable; encoding = DownstreamFixture.RootSignalEncoding(),
        boundaries = true)
    @test axis isa Makie.Axis
    @test plot isa PottsPlot
    @test Makie.Colorbar(figure[1, 2], plot) isa Makie.Colorbar
    @test Makie.DataInspector(figure) isa Makie.DataInspector
    original_children = copy(plot.plots)
    observable[] = replacement
    @test plot.plots == original_children
    @test frame_mcs(plot.frame[]) == 1
    @test CairoMakie.colorbuffer(figure) isa AbstractMatrix

    label = inspection_label(
        foreign, CellTypeEncoding(), CartesianIndex(2, 1))
    @test occursin("Cell 29", label)
    @test occursin("Generation 8", label)
    custom_label = inspection_label(
        foreign, DownstreamFixture.RootSignalEncoding(), CartesianIndex(2, 1))
    @test occursin("Square-root signal", custom_label)
    @test occursin(string(sqrt(0.1)), custom_label)
    @test occursin("a.u.", custom_label)

    output = tempname() * ".png"
    Makie.save(output, figure)
    @test filesize(output) > 1_000

    categorical_figure, _, categorical_plot = Makie.plot(
        foreign; encoding = CellTypeEncoding())
    @test potts_legend(
        categorical_figure[1, 2], categorical_plot) isa Makie.Legend

    spec = Makie.PlotSpec(PottsPlot, foreign;
        encoding = DownstreamFixture.RootSignalEncoding(),
        boundaries = true)
    spec_figure, _, spec_plot = Makie.plot(spec)
    @test spec_plot isa Makie.PlotList
    @test CairoMakie.colorbuffer(spec_figure) isa AbstractMatrix

    Makie.translate!(plot, 2, -1, 0)
    @test Makie.boundingbox(plot) == Makie.Rect3d(
        Makie.Point3d(0.5, 1.0, 0), Makie.Vec3d(3.0, 3.75, 0))

    fixture = render_fixture()
    request = RenderRequest(channels = (
        DownstreamFixture.CheckerboardRequest(),))
    requested = renderframe(fixture.state, fixture.problem, request)
    @test DownstreamFixture.SIGNAL_KEY in available_channels(requested)
    materialized = channel(requested, DownstreamFixture.SIGNAL_KEY)
    @test materialized.label == "Checkerboard"
    @test materialized.units == "fraction"
    @test Set(materialized.values) == Set((0.25, 0.75))
end
