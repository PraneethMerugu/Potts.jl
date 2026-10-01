using Test
using Aqua
using CairoMakie
using MakiePotts
using Random
import Makie
import CorePotts

include(joinpath(dirname(@__DIR__), "dev", "ci_telemetry.jl"))
using .CITelemetry: record_duration

include("downstream_fixture.jl")
include("allocation_fixture.jl")

const MAKIEPOTTS_TEST_FILES = Set((
    "test_adversarial.jl",
    "test_allocations.jl",
    "test_downstream_conformance.jl",
    "test_saved_state_channels.jl",
))

@testset "MakiePotts test inventory" begin
    discovered = Set(filter(name -> startswith(name, "test_") && endswith(name, ".jl"),
        readdir(@__DIR__)))
    @test discovered == MAKIEPOTTS_TEST_FILES
end

function render_fixture(; dimensions = 2)
    dims = dimensions == 2 ? (5, 4) : (5, 4, 3)
    labels = zeros(Int, dims)
    if dimensions == 2
        fill!(view(labels, 2:3, 2:3), 1)
        fill!(view(labels, 4:5, 2:3), 2)
    else
        fill!(view(labels, 2:3, 2:3, 2), 1)
        fill!(view(labels, 4:5, 2:3, 2), 2)
    end
    kinds = [1, 2]
    lattice = CorePotts.Lattice(dims)
    temperature(st, p, prop, ctx) = p.T
    energy(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> (v - 4.0)^2)
    f = CorePotts.CPMFunction(energy; temperature)
    problem = CorePotts.PottsProblem(f, CorePotts.initial_state(labels, kinds), lattice, (0, 0),
        (; T = 2.0); seed = 1)
    state = dimensions == 2 ?
            only(CorePotts.solve(problem, CorePotts.SequentialCPM()).u) :
            CorePotts.initial_state(labels, kinds)
    return (; state, problem)
end

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

@testset "MakiePotts package quality" begin
    Aqua.test_all(MakiePotts; persistent_tasks = false)
    @test isempty(Test.detect_ambiguities(MakiePotts; recursive = true))
    @test isempty(Docs.undocumented_names(MakiePotts; private = false))
end

# P6.0j: ExplicitImports guardrails (CLAUDE.md code rules). Every name MakiePotts uses is
# imported explicitly and by its owner. The allowlist names each non-public access the
# package genuinely needs; add to it only by review, with the reason.
using ExplicitImports: ExplicitImports, check_no_implicit_imports, check_all_explicit_imports_are_public,
    check_no_stale_explicit_imports, check_all_qualified_accesses_via_owners, check_all_qualified_accesses_are_public

const MAKIEPOTTS_NONPUBLIC_QUALIFIED = (
    # Makie's recipe interface: methods a recipe package extends, not declared public by Makie
    :plottype,                   # default plot type for `plot(::PottsSavedState)`
    :preferred_axis_type,        # axis choice for the recipe
    :preferred_axis_attributes,  # axis attributes for the recipe
    :automatic,                  # Makie's `automatic` attribute sentinel
    :apply_transform_and_model,  # `boundingbox` of the recipe: data limits through the plot transform
    :extract_colormap,           # extended so colorbars read the child plot colormap
    :RefValue,                   # Base.RefValue: concrete `Ref` type for type-stable fields
)

@testset "QA: ExplicitImports (MakiePotts)" begin
    @test check_no_implicit_imports(MakiePotts) === nothing
    @test check_all_explicit_imports_are_public(MakiePotts) === nothing
    @test check_no_stale_explicit_imports(MakiePotts) === nothing
    @test check_all_qualified_accesses_via_owners(MakiePotts) === nothing
    @test check_all_qualified_accesses_are_public(MakiePotts; ignore = MAKIEPOTTS_NONPUBLIC_QUALIFIED) === nothing
end

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

include("test_downstream_conformance.jl")
include("test_adversarial.jl")
include("test_allocations.jl")
include("test_saved_state_channels.jl")
