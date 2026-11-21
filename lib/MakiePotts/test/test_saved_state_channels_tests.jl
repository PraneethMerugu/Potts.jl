@testsetup module MP_test_saved_state_channels
using Test
using Aqua
using CairoMakie
using MakiePotts
using Random
import Makie
import CorePotts
import JLD2
include("shared/makiepotts.jl")

# a frame source that reads from `source` and records each read: its index, and whether a
# recording of `record_potts` (its temporary directory in `dir`) was in progress then
struct CountingFrames{S}
    source::S
    dir::String
    reads::Vector{Int}
    recording::Vector{Bool}
end
CountingFrames(source, dir) = CountingFrames(source, dir, Int[], Bool[])
CorePotts.frame_times(c::CountingFrames) = CorePotts.frame_times(c.source)
function CorePotts.read_frame(c::CountingFrames, i)
    push!(c.reads, i)
    push!(c.recording, any(startswith(".makiepotts-recording-"), readdir(c.dir)))
    return CorePotts.read_frame(c.source, i)
end
Base.close(c::CountingFrames) = close(c.source)
function _site_slice_oracle(values, axis, index)
    retained_axes = Tuple(filter(!=(axis), ntuple(identity, ndims(values))))
    retained_size = ntuple(i -> size(values, retained_axes[i]), Val(2))
    return [
        values[
            CartesianIndex(
                ntuple(
                    source_axis -> if source_axis == axis
                        index
                    else
                        site[findfirst(==(source_axis), retained_axes)]
                    end, Val(3)
                )
            ),
        ]
            for site in CartesianIndices(retained_size)
    ]
end

# D-081: a solution's frames draw each saved state's own obstacles. A frozen cell
# released at MCS 5 leaves its sites; they are medium, not obstacles, in the last frame.
struct _ReleasedFrozenKind
    k::Int32
end
CorePotts.frozen_kinds(s::_ReleasedFrozenKind) = (s.k,)
include("shared/export_all.jl")
end

@testitem "saved-state channels use canonical frame projection and validation" setup = [
    MP_test_saved_state_channels,
] tags = [
    :makiepotts, :saved_state_channels,
] begin
    @testset "saved-state channels use canonical frame projection and validation" begin
        fixture = render_fixture(dimensions = 3)
        state = fixture.state
        site_key = SiteChannelKey(:activity, Float32)
        cell_key = CellChannelKey(:signal, Float64)
        medium_key = MediumChannelKey(:temperature, Float64)
        site_values = reshape(
            Float32.(1:length(CorePotts.ownership(state))),
            size(CorePotts.ownership(state))
        )
        active_identities = [
            RenderCellIdentity(id, CorePotts.cell_generations(state)[id])
                for id in eachindex(CorePotts.volumes(state))
                if CorePotts.volumes(state)[id] > 0
        ]
        cell_values = Dict(
            identity => Float64(identity.id)
                for identity in active_identities
        )
        medium_values = Dict(UInt32(1) => 2.5)
        channels = (
            RenderChannel(site_key, site_values; label = "Activity", units = "a.u."),
            RenderChannel(cell_key, cell_values),
            RenderChannel(medium_key, medium_values; units = "K"),
        )

        full = renderframe(state; channels)
        @test frame_channel(full, site_key).values == site_values
        @test frame_channel(full, site_key).values !== site_values
        @test frame_channel(full, cell_key).values == cell_values
        @test frame_channel(full, cell_key).values !== cell_values
        @test frame_channel(full, medium_key).values == medium_values
        @test frame_channel(full, medium_key).values !== medium_values

        for axis in 1:3, index in (1, size(CorePotts.ownership(state), axis))
            request = RenderRequest(extent = OrthogonalSlice(axis, index))
            frame = renderframe(state, request; channels)
            expected = _site_slice_oracle(site_values, axis, index)
            @test frame_channel(frame, site_key).values == expected
            @test frame_size(frame) == size(expected)
            @test frame_channel(frame, cell_key).values == cell_values
            @test frame_channel(frame, medium_key).values == medium_values
        end

        site_before = copy(site_values)
        cell_before = copy(cell_values)
        medium_before = copy(medium_values)
        first_frame = renderframe(state; channels)
        second_frame = renderframe(state; channels)
        fill!(frame_channel(first_frame, site_key).values, -1.0f0)
        frame_channel(first_frame, cell_key).values[first(active_identities)] = -1.0
        frame_channel(first_frame, medium_key).values[UInt32(1)] = -1.0
        @test frame_channel(second_frame, site_key).values == site_before
        @test frame_channel(second_frame, cell_key).values == cell_before
        @test frame_channel(second_frame, medium_key).values == medium_before
        @test site_values == site_before
        @test cell_values == cell_before
        @test medium_values == medium_before

        solution_fixture = render_fixture()
        solution = CorePotts.solve(solution_fixture.problem, CorePotts.SequentialCPM())
        solution_values = reshape(
            Float32.(1:length(CorePotts.ownership(solution_fixture.state))),
            size(CorePotts.ownership(solution_fixture.state))
        )
        from_solution = renderframe(
            solution;
            index = firstindex(solution.u),
            channels = (RenderChannel(site_key, solution_values),)
        )
        @test frame_channel(from_solution, site_key).values == solution_values
    end
end

@testitem "saved-state channel rejection is all-or-nothing" setup = [
    MP_test_saved_state_channels,
] tags = [
    :makiepotts, :saved_state_channels,
] begin
    @testset "saved-state channel rejection is all-or-nothing" begin
        fixture = render_fixture(dimensions = 3)
        state = fixture.state
        site_key = SiteChannelKey(:site, Float64)
        cell_key = CellChannelKey(:cell, Float64)
        medium_key = MediumChannelKey(:medium, Float64)
        valid_site = zeros(Float64, size(CorePotts.ownership(state)))
        valid_site_before = copy(valid_site)
        first_identity = RenderCellIdentity(1, CorePotts.cell_generations(state)[1])

        @test_throws MakiePotts.InvalidRenderFrameError renderframe(
            state; channels = (RenderChannel(site_key, zeros(2, 2)),)
        )
        @test_throws MakiePotts.InvalidRenderFrameError renderframe(
            state; channels = (
                RenderChannel(site_key, fill("wrong", size(CorePotts.ownership(state)))),
            )
        )
        @test_throws MakiePotts.InvalidRenderFrameError renderframe(
            state; channels = (
                RenderChannel(
                    cell_key,
                    Dict(
                        RenderCellIdentity(
                            first_identity.id,
                            first_identity.generation + 1
                        ) =>
                            1.0
                    )
                ),
            )
        )
        @test_throws MakiePotts.InvalidRenderFrameError renderframe(
            state; channels = (RenderChannel(medium_key, Dict(UInt32(0) => 1.0)),)
        )
        @test_throws MakiePotts.InvalidRenderFrameError renderframe(
            state; channels = (
                RenderChannel(site_key, valid_site),
                RenderChannel(site_key, valid_site),
            )
        )
        @test_throws MakiePotts.InvalidRenderFrameError renderframe(
            state; channels = (
                RenderChannel(site_key, valid_site),
                RenderChannel(
                    cell_key,
                    Dict(
                        RenderCellIdentity(
                            first_identity.id, first_identity.generation + 1
                        ) => 1.0
                    )
                ),
            )
        )
        @test valid_site == valid_site_before
        @test_throws MakiePotts.InvalidRenderFrameError renderframe(
            state; channels = ("not a channel",)
        )
        @test_throws BoundsError renderframe(
            state,
            RenderRequest(
                extent = OrthogonalSlice(
                    3, size(CorePotts.ownership(state), 3) +
                        1
                )
            );
            channels = (RenderChannel(site_key, valid_site),)
        )
    end
end

@testitem "solution frames follow a frozen mask that changes during the run" setup = [
    MP_test_saved_state_channels,
] tags = [
    :makiepotts, :saved_state_channels,
] begin
    @testset "solution frames follow a frozen mask that changes during the run" begin
        kindidx(st, c) = c == 0 ? 1 : Int(@inbounds st.cell.kind[c]) + 1
        function dH(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            return CorePotts.contact_delta(st.ownership, ctx, prop, J) +
                CorePotts.volume_delta(
                st.cell.volume, prop, (v, c) -> p.λ *
                    (v - p.V0)^2
            )
        end
        lat = CorePotts.Lattice((30, 30))
        σ = zeros(Int32, 30, 30)
        σ[5:10, 5:10] .= 1
        σ[18:23, 18:23] .= 2
        st = CorePotts.with_capacity(
            CorePotts.initial_state(
                σ, Int32[1, 2];
                cell = CorePotts.init_moments(σ, lat, 2)
            ),
            2
        )
        release = CorePotts.Lifecycle(
            (st, p, ctx, key, mcs, c) -> if mcs == 5 && c == 2
                CorePotts.EVENT_TRANSITION
            else
                CorePotts.EVENT_NONE
            end;
            kind = (st, p, ctx, key, mcs, c) -> Int32(1)
        )
        f = CorePotts.CPMFunction(
            dH; temperature = (st, p, prop, ctx) -> p.T,
            lifecycle = release, sys = _ReleasedFrozenKind(2)
        )
        p = (; J = [0.0 16 16; 16 2 11; 16 11 14], λ = 1.0, V0 = 40.0, T = 10.0)
        sol = CorePotts.solve(
            CorePotts.PottsProblem(f, st, lat, (0, 40), p; frozen = σ .== 2),
            CorePotts.SequentialCPM()
        )
        obstacles(fr) = count(o -> o.kind === MakiePotts.ObstacleSite, fr.owners)
        @test CorePotts.frozen_sites(sol.prob, sol.u[1]) == (σ .== 2)
        @test CorePotts.frozen_sites(sol.prob, sol.u[end]) == falses(30, 30)
        # released: no obstacle left
        @test obstacles(renderframe(sol)) == 0
        # negative control: the problem's t0 mask draws the vacated medium sites as
        # obstacles
        vacated = count((σ .== 2) .& (CorePotts.ownership(sol.u[end]) .== 0))
        @test vacated > 0
        @test obstacles(renderframe(sol.u[end]; frozen = sol.prob.frozen)) == vacated
    end
end

@testitem "written frames render and record like the solution" setup = [
    MP_test_saved_state_channels,
] tags = [
    :makiepotts, :saved_state_channels,
] begin
    @testset "written frames render and record like the solution" begin
        kindidx(st, c) = c == 0 ? 1 : Int(@inbounds st.cell.kind[c]) + 1
        function dH(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            return CorePotts.contact_delta(st.ownership, ctx, prop, J) +
                CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
        end
        lat = CorePotts.Lattice((30, 30))
        σ = zeros(Int32, 30, 30)
        σ[5:10, 5:10] .= 1
        σ[18:23, 18:23] .= 2
        st = CorePotts.with_capacity(
            CorePotts.initial_state(
                σ, Int32[1, 2]; cell = CorePotts.init_moments(σ, lat, 2)
            ),
            2
        )
        release = CorePotts.Lifecycle(
            (st, p, ctx, key, mcs, c) -> if mcs == 5 && c == 2
                CorePotts.EVENT_TRANSITION
            else
                CorePotts.EVENT_NONE
            end;
            kind = (st, p, ctx, key, mcs, c) -> Int32(1)
        )
        f = CorePotts.CPMFunction(
            dH; temperature = (st, p, prop, ctx) -> p.T,
            lifecycle = release, sys = _ReleasedFrozenKind(2)
        )
        p = (; J = [0.0 16 16; 16 2 11; 16 11 14], λ = 1.0, V0 = 40.0, T = 10.0)
        prob = CorePotts.PottsProblem(f, st, lat, (0, 40), p; frozen = σ .== 2)
        path = tempname() * ".jld2"
        cb = CorePotts.FrameWritingCallback(CorePotts.FrameFile(path); saveat = 10)
        sol = CorePotts.solve(prob, CorePotts.SequentialCPM(); saveat = 10, callback = cb)
        frames = CorePotts.PottsFrames(path; prob)
        obstacles(fr) = count(o -> o.kind === MakiePotts.ObstacleSite, fr.owners)
        @test frames.t == sol.t
        for i in eachindex(sol.t)
            a, b = renderframe(frames; index = i), renderframe(sol; index = i)
            @test a.owners == b.owners
            @test frame_mcs(a) == frame_mcs(b)
        end
        # the last frame draws its own mask: the released cell left no obstacle
        @test obstacles(renderframe(frames)) == 0
        @test length(renderframes(frames)) == length(sol.t)
        output = tempname() * ".gif"
        @test record_potts(
            output, frames; framerate = 2, figure = (; size = (180, 140))
        ) == output
        @test filesize(output) > 1_000
        # negative control: the problem's t0 mask draws the vacated medium sites
        vacated = count((σ .== 2) .& (CorePotts.ownership(frames[end]) .== 0))
        @test vacated > 0
        @test obstacles(renderframe(frames[end]; frozen = prob.frozen)) == vacated
        close(frames)
        # recording and exploring read and render one frame at a time
        mktempdir() do dir
            source = CountingFrames(CorePotts.FrameFile(path), dir)
            lazy = CorePotts.PottsFrames(source; prob)
            output = joinpath(dir, "lazy.gif")
            record_potts(output, lazy; framerate = 2, figure = (; size = (180, 140)))
            @test source.reads == eachindex(sol.t)
            # every frame after the first was read while the recording was in progress
            @test all(source.recording[2:end])
            # negative control: `renderframes` reads every frame before any recording
            empty!(source.reads)
            empty!(source.recording)
            record_potts(output, renderframes(lazy); framerate = 2)
            @test source.reads == eachindex(sol.t)
            @test !any(source.recording)
            # the explorer reads a frame when the slider shows it
            empty!(source.reads)
            explorer = explore_potts(lazy; inspector = false)
            @test source.reads == [1]
            Makie.set_close_to!(explorer.slider, 3)
            @test source.reads == [1, 3]
            close(explorer)
            close(lazy)
        end
    end
end
