@testset "adversarial geometry and ownership semantics" begin
    one_geometry = RenderGeometry((1, 1);
        spacing = (0.25, 2.5), origin = (-3.0, 4.0))
    one_medium = PottsRenderFrame(0,
        fill(RenderOwner(MediumSite, 1), 1, 1),
        RenderCellMetadata[]; geometry = one_geometry)
    @test Base.isvalid(render_frame_conformance(one_medium))
    @test encode(one_medium, CellTypeEncoding()).values == fill(1.0, 1, 1)

    figure, _, one_plot = Makie.plot(one_medium; boundaries = true)
    @test Makie.data_limits(one_plot) == Makie.Rect3d(
        Makie.Point3d(-3.0, 4.0, 0), Makie.Vec3d(0.25, 2.5, 0))
    @test Makie.boundingbox(one_plot.plots[1]) == Makie.boundingbox(one_plot)
    @test CairoMakie.colorbuffer(figure) isa AbstractMatrix

    singleton_geometry = RenderGeometry((1, 4);
        spacing = (3.0, 0.5), origin = (2.0, -1.0))
    all_obstacle = PottsRenderFrame(0,
        fill(RenderOwner(ObstacleSite, 7), 1, 4),
        RenderCellMetadata[]; geometry = singleton_geometry)
    obstacle_figure, _, obstacle_plot = Makie.plot(all_obstacle)
    @test potts_legend(
        obstacle_figure[1, 2], obstacle_plot) isa Makie.Legend
    @test all(site -> owner_at(all_obstacle, site).kind === ObstacleSite,
        CartesianIndices(frame_size(all_obstacle)))

    identity = CellIdentity(typemax(UInt32), typemax(UInt64))
    metadata = RenderCellMetadata(identity, typemax(UInt32))
    all_cell = PottsRenderFrame(typemax(Int),
        fill(RenderOwner(CellSite, typemax(UInt32)), 2, 1), [metadata])
    @test cell_metadata(all_cell, identity) == metadata
    @test length(legend_entries(all_cell, CellIdentityEncoding())) == 2
end

@testset "all slice axes and endpoints" begin
    fixture = render_fixture(dimensions = 3)
    source_size = (5, 4, 3)
    source_spacing = (1.0, 1.0, 1.0)
    for axis in 1:3
        retained = Tuple(filter(!=(axis), (1, 2, 3)))
        expected_size = ntuple(i -> source_size[retained[i]], Val(2))
        expected_spacing = ntuple(i -> source_spacing[retained[i]], Val(2))
        for index in (1, source_size[axis])
            request = RenderRequest(extent = OrthogonalSlice(axis, index))
            frame = renderframe(fixture.state, request)
            @test frame_size(frame) == expected_size
            @test frame_geometry(frame).source_axes == retained
            @test frame_geometry(frame).spacing == expected_spacing
            @test frame_mcs(frame) == 0
            @test Base.isvalid(render_frame_conformance(frame))
        end
    end
end

@testset "missing values and typed channel validation" begin
    identity = CellIdentity(1, 3)
    cells = [RenderCellMetadata(identity, 2)]
    owners = RenderOwner[
        RenderOwner(MediumSite, 1) RenderOwner(CellSite, 1);
        RenderOwner(ObstacleSite, 2) RenderOwner(CellSite, 1);
    ]
    site_key = SiteChannelKey(:site_missing, Float64)
    cell_key = CellChannelKey(:cell_missing, Float64)
    medium_key = MediumChannelKey(:medium_missing, Float64)
    channels = (
        RenderChannel(site_key, Union{Missing, Float64}[
            1.0 missing; missing 4.0]),
        RenderChannel(cell_key, Dict(identity => missing)),
        RenderChannel(medium_key, Dict(UInt32(1) => 2.0)),
    )
    frame = PottsRenderFrame(0, owners, cells; channels)
    @test count(isnan, encode(frame, ChannelEncoding(site_key)).values) == 2
    @test count(isnan, encode(frame, ChannelEncoding(cell_key)).values) == 4
    medium_values = encode(frame, ChannelEncoding(medium_key)).values
    @test medium_values[1, 1] == 2.0
    @test isnan(medium_values[2, 1])
    @test isnan(medium_values[1, 2])

    overlay = MakiePotts._semantic_overlay(
        frame, ChannelEncoding(cell_key), :gray95, :gray20)
    @test overlay[1, 1] == Makie.to_color(:gray95)
    @test overlay[2, 1] == Makie.to_color(:gray20)
    @test overlay[1, 2] == Makie.RGBAf(0, 0, 0, 0)
    site_overlay = MakiePotts._semantic_overlay(
        frame, ChannelEncoding(site_key), :gray95, :gray20)
    @test site_overlay[1, 1] == Makie.RGBAf(0, 0, 0, 0)

    many_cells = [
        RenderCellMetadata(CellIdentity(id, 0), id) for id in 1:3
    ]
    many_owners = reshape(
        [RenderOwner(CellSite, id) for id in 1:3], 3, 1)
    many_frame = PottsRenderFrame(0, many_owners, many_cells)
    @test_throws ArgumentError Makie.plot(
        many_frame; category_palette = [:red, :blue])

    wrong_type = RenderChannel(
        SiteChannelKey(:wrong, Float64), fill("not numeric", 2, 2))
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, fill(RenderOwner(MediumSite, 1), 2, 2),
        RenderCellMetadata[]; channels = (wrong_type,))
end

@testset "invalid frames and requests fail before publication" begin
    @test_throws ArgumentError RenderGeometry((0, 2))
    @test_throws ArgumentError RenderGeometry((2, 2); spacing = (1.0, Inf))
    @test_throws ArgumentError RenderGeometry((2, 2); origin = (0.0, NaN))
    @test_throws ArgumentError OrthogonalSlice(0, 1)
    @test_throws ArgumentError OrthogonalSlice(1, 0)
    @test_throws ArgumentError RenderRequest(channels = (
        CellPropertyRequest(:x), CellPropertyRequest(:x)))

    identity = CellIdentity(1, 0)
    duplicate_cells = [
        RenderCellMetadata(identity, 1),
        RenderCellMetadata(CellIdentity(1, 1), 2),
    ]
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, fill(RenderOwner(CellSite, 1), 2, 2), duplicate_cells)
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, fill(RenderOwner(CellSite, 2), 2, 2),
        [RenderCellMetadata(identity, 1)])
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, fill(RenderOwner(MediumSite, 1), 2, 2),
        RenderCellMetadata[]; geometry = RenderGeometry((3, 2)))

    site_key = SiteChannelKey(:field, Float64)
    duplicate_channel = RenderChannel(site_key, zeros(2, 2))
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, fill(RenderOwner(MediumSite, 1), 2, 2),
        RenderCellMetadata[];
        channels = (duplicate_channel, duplicate_channel))
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, fill(RenderOwner(MediumSite, 1), 2, 2),
        RenderCellMetadata[];
        channels = (RenderChannel(site_key, zeros(3, 2)),))

    cell_key = CellChannelKey(:generation, Float64)
    wrong_generation = RenderChannel(
        cell_key, Dict(CellIdentity(1, 2) => 1.0))
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, fill(RenderOwner(CellSite, 1), 2, 2),
        [RenderCellMetadata(identity, 1)];
        channels = (wrong_generation,))

    medium_key = MediumChannelKey(:domain, Float64)
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, fill(RenderOwner(MediumSite, 1), 2, 2),
        RenderCellMetadata[];
        channels = (RenderChannel(medium_key, Dict("one" => 1.0)),))

    available_key = SiteChannelKey(:available, Float64)
    absent_key = SiteChannelKey(:absent, Float64)
    available_frame = PottsRenderFrame(0,
        fill(RenderOwner(MediumSite, 1), 2, 2), RenderCellMetadata[];
        channels = (RenderChannel(available_key, zeros(2, 2)),))
    missing_error = try
        channel(available_frame, absent_key)
        nothing
    catch error
        error
    end
    @test missing_error isa MakiePotts.MissingRenderChannelError
    missing_message = sprint(showerror, missing_error)
    @test occursin(":absent", missing_message)
    @test occursin(":available", missing_message)
    @test occursin("RenderRequest", missing_message)

    fixture_2d = render_fixture()
    @test_throws ArgumentError renderframe(
        fixture_2d.state,
        RenderRequest(extent = OrthogonalSlice(1, 1)))
    @test_throws ArgumentError renderframe(
        fixture_2d.state,
        RenderRequest(include_cell_metadata = false))

    fixture_3d = render_fixture(dimensions = 3)
    @test_throws BoundsError renderframe(
        fixture_3d.state,
        RenderRequest(extent = OrthogonalSlice(3, 4)))

    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(-1,
        fill(RenderOwner(MediumSite, 1), 1, 1),
        RenderCellMetadata[])
end

@testset "rapid reactive replacement and recording guards" begin
    geometry = RenderGeometry((3, 2);
        spacing = (0.5, 2.0), origin = (1.0, -2.0))
    frames = [
        PottsRenderFrame(index,
            fill(index % 2 == 0 ?
                 RenderOwner(MediumSite, 1) :
                 RenderOwner(ObstacleSite, 2), 3, 2),
            RenderCellMetadata[]; geometry)
        for index in 0:20
    ]
    observable = Makie.Observable(first(frames))
    figure, _, plot = Makie.plot(observable; boundaries = true)
    children = copy(plot.plots)
    for frame in frames[2:end]
        observable[] = frame
    end
    @test plot.plots == children
    @test frame_mcs(plot.frame[]) == 20
    @test CairoMakie.colorbuffer(figure) isa AbstractMatrix
    @test Makie.data_limits(plot) == Makie.Rect3d(
        Makie.Point3d(1.0, -2.0, 0), Makie.Vec3d(1.5, 4.0, 0))

    @test_throws ArgumentError record_potts(
        tempname() * ".gif", PottsRenderFrame{2}[])

    singleton_output = tempname() * ".gif"
    @test record_potts(singleton_output, [first(frames)];
        framerate = 1, figure = (; size = (120, 100))) == singleton_output
    @test filesize(singleton_output) > 1_000

    shifted = PottsRenderFrame(21,
        fill(RenderOwner(MediumSite, 1), 3, 2),
        RenderCellMetadata[];
        geometry = RenderGeometry((3, 2);
            spacing = (0.5, 2.0), origin = (2.0, -2.0)))
    incompatible_output = tempname() * ".gif"
    @test_throws ArgumentError record_potts(
        incompatible_output, [first(frames), shifted])
    @test !isfile(incompatible_output)
    @test_throws ArgumentError explore_potts(
        [first(frames), shifted]; inspector = false)

    @test_throws ArgumentError record_potts(
        tempname() * ".gif", [first(frames)]; framerate = 0)
    @test_throws ArgumentError record_potts(
        tempname() * ".gif", [first(frames)]; framerate = Inf)
    @test_throws ArgumentError record_potts(
        tempname(), [first(frames)])

    preserved_output = tempname() * ".gif"
    write(preserved_output, "previous valid artifact")
    owned_figure = Makie.Figure(size = (120, 100))
    Makie.Axis(owned_figure[1, 1])
    @test_throws ErrorException record_potts(
        preserved_output, owned_figure, 1:2;
        framerate = 1, update! = _ -> error("update failed"))
    @test read(preserved_output, String) == "previous valid artifact"

    inspected = explore_potts(
        frames[1:2]; inspector = true, figure = (; size = (180, 140)))
    @test isopen(inspected)
    @test close(inspected) === inspected
    @test !isopen(inspected)
end
