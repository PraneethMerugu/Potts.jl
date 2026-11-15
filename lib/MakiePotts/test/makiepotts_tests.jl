@testsetup module MP_makiepotts
using Test
using AllocCheck: check_allocs
using Aqua
using CairoMakie
using JET: @test_opt
using MakiePotts
using Random
import Makie
import CorePotts
include("shared/makiepotts.jl")
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "qa_common.jl"))
include("shared/export_all.jl")
end

@testitem "MakiePotts test inventory" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
@testset "MakiePotts test inventory" begin
    discovered = Set(filter(name -> startswith(name, "test_") && endswith(name, ".jl"),
        readdir(@__DIR__)))
    @test discovered == MAKIEPOTTS_TEST_FILES
end
end

@testitem "validated semantic frames" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
@testset "validated semantic frames" begin
    fixture = render_fixture()
    frame = renderframe(fixture.state)
    @test frame isa AbstractPottsRenderFrame{2}
    @test frame_mcs(frame) == 0
    @test frame_size(frame) == (5, 4)
    @test frame_geometry(frame).spacing == (1.0, 1.0)
    @test owner_at(frame, CartesianIndex(1, 1)).kind === MediumSite
    @test cell_metadata(frame, RenderCellIdentity(1, 1)).cell_type == 1
    @test isempty(available_channels(frame))
    @test frame_provenance(frame).source === :saved_state
    @test Base.isvalid(render_frame_conformance(frame))
    @test assert_render_frame_conformance(frame) === frame
    @test_throws ArgumentError RenderCellIdentity(0, 0)
    @test_throws ArgumentError RenderCellIdentity(1, -1)

    source_owners = fill(RenderOwner(MediumSite, 1), 2, 2)
    copied_frame = PottsRenderFrame(0, source_owners, RenderCellMetadata[])
    fill!(source_owners, RenderOwner(ObstacleSite, 2))
    @test owner_at(copied_frame, CartesianIndex(1, 1)).kind === MediumSite

    invalid = fill(RenderOwner(CellSite, 1), 2, 2)
    @test_throws MakiePotts.InvalidRenderFrameError PottsRenderFrame(
        0, invalid, RenderCellMetadata[])
end
end

@testitem "randomized frame invariants" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
@testset "randomized frame invariants" begin
    rng = MersenneTwister(0x4d616b6965)
    for _ in 1:100
        dims = (rand(rng, 2:12), rand(rng, 2:12))
        cell_count = rand(rng, 1:8)
        cells = [
            RenderCellMetadata(
                RenderCellIdentity(id, rand(rng, UInt16)),
                rand(rng, 1:5))
            for id in 1:cell_count
        ]
        owners = Array{RenderOwner}(undef, dims)
        for site in eachindex(owners)
            id = rand(rng, 0:cell_count)
            owners[site] = id == 0 ?
                           RenderOwner(MediumSite, 1) :
                           RenderOwner(CellSite, id)
        end
        frame = PottsRenderFrame(rand(rng, 0:10_000), owners, cells)
        @test assert_render_frame_conformance(frame) === frame
        @test size(encode(frame, CellTypeEncoding()).values) == dims
        @test size(encode(frame, CellIdentityEncoding()).values) == dims
    end
end
end

@testitem "requests, slices, and retained observations" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
@testset "requests, slices, and retained observations" begin
    fixture = render_fixture(dimensions = 3)
    request = RenderRequest(extent = OrthogonalSlice(3, 2))
    frame = renderframe(fixture.state, request)
    @test frame_size(frame) == (5, 4)
    @test frame_geometry(frame).source_axes == (1, 2)
    @test frame_geometry(frame).spacing == (1.0, 1.0)
    @test owner_at(frame, CartesianIndex(1, 1)).kind === MediumSite
    @test size(encode(
        renderframe(fixture.state),
        CellIdentityEncoding()).values) == (5, 4, 3)

    @test assert_render_frame_conformance(frame) === frame
end
end

@testitem "open typed channels and encodings" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
@testset "open typed channels and encodings" begin
    cells = [
        RenderCellMetadata(RenderCellIdentity(1, 2), 4),
        RenderCellMetadata(RenderCellIdentity(2, 1), 7),
    ]
    owners = reshape(RenderOwner[
        RenderOwner(MediumSite, 1), RenderOwner(CellSite, 1),
        RenderOwner(CellSite, 2), RenderOwner(ObstacleSite, 2),
    ], 2, 2)
    key = CellChannelKey(:signal, Float64)
    values = Dict(RenderCellIdentity(1, 2) => 0.25, RenderCellIdentity(2, 1) => missing)
    frame = PottsRenderFrame(2, owners, cells;
        channels = (RenderChannel(key, values; label = "Signal", units = "a.u."),))

    types = encode(frame, CellTypeEncoding())
    @test encoding_kind(types.encoding) === CategoricalEncoding
    @test length(legend_entries(types)) == 3
    @test types.values[1, 1] == 1

    signal = encode(frame, ChannelEncoding(key))
    @test encoding_kind(signal.encoding) === ContinuousEncoding
    @test signal.values[2, 1] == 0.25
    @test isnan(signal.values[1, 2])
    @test signal.finite_range == (-0.25, 0.75)
    @test occursin("Cell 1", inspection_label(frame, ChannelEncoding(key),
        CartesianIndex(2, 1)))
    @test_throws MakiePotts.MissingRenderChannelError encode(
        frame, ChannelEncoding(CellChannelKey(:absent, Float64)))
end
end

@testitem "Makie-native recipe interoperability and reactivity" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
@testset "Makie-native recipe interoperability and reactivity" begin
    CairoMakie.activate!(type = "png")
    first_fixture = render_fixture()
    first_frame = renderframe(first_fixture.state)
    second_frame = PottsRenderFrame(1,
        fill(RenderOwner(MediumSite, 1), frame_size(first_frame)),
        RenderCellMetadata[];
        geometry = frame_geometry(first_frame))
    frame = Makie.Observable(first_frame)
    figure, axis, plot = Makie.plot(frame)
    @test plot isa PottsPlot
    @test axis isa Makie.Axis
    before = copy(CairoMakie.colorbuffer(figure))
    frame[] = second_frame
    after = CairoMakie.colorbuffer(figure)
    @test before != after
    @test Makie.data_limits(plot) ==
          Makie.Rect3d(Makie.Point3d(0, 0, 0), Makie.Vec3d(5.0, 4.0, 0))
    @test Makie.extract_colormap(plot) isa Makie.ColorMapping
    @test Makie.boundingbox(plot) ==
          Makie.Rect3d(Makie.Point3d(0, 0, 0), Makie.Vec3d(5.0, 4.0, 0))
    categorical_legend = potts_legend(figure[1, 2], plot)
    @test categorical_legend isa Makie.Legend

    spec = Makie.PlotSpec(PottsPlot, first_frame; boundaries = true)
    spec_figure, _, spec_plot = Makie.plot(spec)
    @test spec_plot isa Makie.PlotList
    @test CairoMakie.colorbuffer(spec_figure) isa AbstractMatrix

    key = SiteChannelKey(:field, Float64)
    channel_frame = PottsRenderFrame(0,
        fill(RenderOwner(MediumSite, 1), 2, 2), RenderCellMetadata[];
        channels = (RenderChannel(key, [0.0 1.0; 2.0 3.0]),))
    continuous_figure, _, continuous_plot = Makie.plot(
        channel_frame; encoding = ChannelEncoding(key))
    @test Makie.Colorbar(continuous_figure[1, 2], continuous_plot) isa Makie.Colorbar

    rendered = CairoMakie.colorbuffer(figure)
    @test size(rendered, 1) > 100
    @test size(rendered, 2) > 100
    output = tempname() * ".png"
    Makie.save(output, figure)
    @test filesize(output) > 1_000
    Makie.translate!(plot, 1, 2, 0)
    @test Makie.boundingbox(plot) ==
          Makie.Rect3d(Makie.Point3d(1, 2, 0), Makie.Vec3d(5.0, 4.0, 0))
end
end

@testitem "recording and explorer lifecycle" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
@testset "recording and explorer lifecycle" begin
    fixture = render_fixture()
    first_frame = renderframe(fixture.state)
    second_frame = PottsRenderFrame(1,
        fill(RenderOwner(MediumSite, 1), frame_size(first_frame)),
        RenderCellMetadata[];
        geometry = frame_geometry(first_frame))
    output = tempname() * ".gif"
    recorded = record_duration("package.gif_recording"; kind = "recording") do
        record_potts(output, [first_frame, second_frame];
            framerate = 2, figure = (; size = (180, 140)))
    end
    @test recorded == output
    @test filesize(output) > 1_000

    explorer = explore_potts([first_frame, second_frame]; inspector = false,
        figure = (; size = (240, 200)))
    @test explorer.plot isa PottsPlot
    explorer.slider.value[] = 2
    @test explorer.frame_index[] == 2
    @test frame_mcs(explorer.plot.frame[]) == 1
    @test isopen(explorer)
    @test close(explorer) === explorer
    @test !isopen(explorer)
    @test close(explorer) === explorer
end
end

@testitem "Float32 render frames and channels (TS2-7)" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
    @testset "Float32 render frames and channels (TS2-7)" begin
        CairoMakie.activate!(type = "png")
        owners = fill(RenderOwner(MediumSite, 1), 3, 3)
        owners[2, 2] = RenderOwner(CellSite, 1)
        cells = [RenderCellMetadata(RenderCellIdentity(1, 1), 1)]
        site_key = SiteChannelKey(:field32, Float32)
        cell_key = CellChannelKey(:signal32, Float32)
        site_vals = Float32[0.0 1.0 2.0; 0.5 1.5 2.5; 1.0 2.0 3.0]
        cell_vals = Dict(RenderCellIdentity(1, 1) => Float32(0.75))
        frame = PottsRenderFrame(
            0, owners, cells;
            channels = (
                RenderChannel(site_key, site_vals; label = "Field32", units = "a.u."),
                RenderChannel(cell_key, cell_vals; label = "Signal32", units = "a.u."),
            )
        )
        @test assert_render_frame_conformance(frame) === frame
        site_enc = encode(frame, ChannelEncoding(site_key))
        @test eltype(site_enc.values) <: AbstractFloat
        @test site_enc.values ≈ Float64.(site_vals)
        @test site_enc.finite_range == (0.0, 3.0)
        cell_enc = encode(frame, ChannelEncoding(cell_key))
        @test eltype(cell_enc.values) <: AbstractFloat
        @test cell_enc.values[2, 2] == 0.75

        fig, _, plt = Makie.plot(frame; encoding = ChannelEncoding(site_key))
        @test plt isa PottsPlot
        @test Makie.Colorbar(fig[1, 2], plt) isa Makie.Colorbar
        buf = CairoMakie.colorbuffer(fig)
        @test size(buf, 1) > 100 && size(buf, 2) > 100
    end
end

@testitem "clean install-to-PNG journey (TS3-3)" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
    @testset "clean install-to-PNG journey (TS3-3)" begin
        CairoMakie.activate!(type = "png")
        frame = PottsRenderFrame(
            0,
            fill(RenderOwner(MediumSite, 1), 2, 2),
            RenderCellMetadata[],
        )
        @test frame_size(frame) == (2, 2)
        figure, axis, plot = CairoMakie.plot(frame; boundaries = true)
        @test plot isa PottsPlot
        @test axis isa CairoMakie.Axis
        @test potts_legend(figure[1, 2], plot) isa Makie.Legend
        buffer = CairoMakie.colorbuffer(figure)
        @test size(buffer, 1) > 100 && size(buffer, 2) > 100
        mktempdir() do directory
            output = joinpath(directory, "makiepotts-clean-install.png")
            CairoMakie.save(output, figure)
            @test filesize(output) > 1_000
        end
    end
end

@testitem "MakiePotts package quality" setup = [MP_makiepotts] tags = [:makiepotts, :qa] begin
@testset "MakiePotts package quality" begin
        # `persistent_tasks = false`: Makie/CairoMakie may hold background font/render tasks.
        qa_aqua(MakiePotts; persistent_tasks = false)
        qa_api_docs(MakiePotts; docs_dir = joinpath(@__DIR__, "..", "..", "..", "docs"))
end
end

@testitem "QA: ExplicitImports (MakiePotts)" setup = [MP_makiepotts] tags = [:makiepotts, :qa] begin
@testset "QA: ExplicitImports (MakiePotts)" begin
        qa_explicit_imports(MakiePotts; nonpublic_qualified = MAKIEPOTTS_NONPUBLIC_QUALIFIED)
    end
end

@testitem "QA: JET (MakiePotts)" setup = [MP_makiepotts] tags = [:makiepotts, :qa] begin
    @testset "QA: JET (MakiePotts)" begin
        fixture = render_fixture()
        frame = renderframe(fixture.state)
        @test_opt target_modules = (MakiePotts,) frame_size(frame)
        @test_opt target_modules = (MakiePotts,) frame_mcs(frame)
        @test_opt target_modules = (MakiePotts,) owner_at(frame, CartesianIndex(1, 1))
        @test_opt target_modules = (MakiePotts,) encode(frame, CellTypeEncoding())
        @test_opt target_modules = (MakiePotts,) encode(frame, CellIdentityEncoding())
        @test isempty(check_allocs(frame_size, (typeof(frame),)))
        @test isempty(check_allocs(frame_mcs, (typeof(frame),)))
        @test isempty(check_allocs(owner_at, (typeof(frame), CartesianIndex{2})))
end
end

@testitem "fresh-process MakiePotts load orders" setup = [MP_makiepotts] tags = [:makiepotts, :core] begin
@testset "fresh-process MakiePotts load orders" begin
    # Pkg.test owns a resolved temporary environment. Reuse that exact graph
    # rather than a developer's ignored package-local Manifest.toml.
    project = dirname(Base.active_project())
    orders = (
        raw"""
        using MakiePotts
        loaded = Set(pkgid.name for pkgid in keys(Base.loaded_modules))
        @assert "CorePotts" in loaded
        @assert !("ModelingToolkit" in loaded)
        print("makie-first-ok")
        """,
        raw"""
        using CorePotts
        using MakiePotts
        loaded = Set(pkgid.name for pkgid in keys(Base.loaded_modules))
        @assert "CorePotts" in loaded
        @assert "MakiePotts" in loaded
        @assert !("ModelingToolkit" in loaded)
        print("corepotts-first-ok")
        """,
    )
    for (script, output) in zip(orders, ("makie-first-ok", "corepotts-first-ok"))
        command = `$(Base.julia_cmd()) --startup-file=no --project=$(project) -e $script`
        @test read(command, String) == output
    end
end
end
