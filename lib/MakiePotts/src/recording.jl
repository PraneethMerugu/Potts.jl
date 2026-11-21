function _record_figure(
        first_frame::AbstractPottsRenderFrame{2};
        encoding::AbstractPottsEncoding = CellTypeEncoding(),
        title::AbstractString = "Potts model",
        figure = (;), axis = (;), plot = (;)
    )
    fig = Makie.Figure(; figure...)
    ax = Makie.Axis(
        fig[1, 1];
        title = String(title), aspect = Makie.DataAspect(), axis...
    )
    frame = Makie.Observable(first_frame)
    rendered = pottsplot!(ax, frame; encoding, plot...)
    return fig, ax, rendered, frame
end

function _validate_framerate(framerate::Real)
    value = Float64(framerate)
    isfinite(value) && value > 0 ||
        throw(ArgumentError("recording framerate must be positive and finite; \
            got $framerate"))
    return isinteger(value) ? Int(value) : value
end

function _validate_recording_frames(frames)
    isempty(frames) && throw(ArgumentError("recording requires at least one frame"))
    foreach(assert_render_frame_conformance, frames)
    expected = frame_geometry(first(frames))
    for (index, frame) in pairs(frames)
        actual = frame_geometry(frame)
        actual == expected && continue
        throw(
            ArgumentError(
                "recording frame $index has incompatible geometry; " *
                    "expected $expected, got $actual"
            )
        )
    end
    return expected
end

function _atomic_record(write_recording::Function, filename::AbstractString)
    destination = String(filename)
    extension = splitext(destination)[2]
    isempty(extension) && throw(
        ArgumentError(
            "recording filename must include an output extension"
        )
    )
    parent = dirname(abspath(destination))
    return mktempdir(parent; prefix = ".makiepotts-recording-") do directory
        temporary = joinpath(directory, "makiepotts-recording$extension")
        write_recording(temporary)
        isfile(temporary) && filesize(temporary) > 0 ||
            throw(RecordingError(destination))
        Base.Filesystem.rename(temporary, destination)
        destination
    end
end

"""
    record_potts(filename, frames; framerate = 30, kwargs...) -> String
    record_potts(filename, solution; request = RenderRequest(), kwargs...) -> String

Write a video of 2D render frames, one video frame per render frame, with `Makie.record`.

A vector of frames is checked in full before the first frame is written. A
`CorePotts.PottsSolution` is rendered first ([`renderframes`](@ref)). Frames a run wrote to
disk (`CorePotts.PottsFrames`) are read, rendered and checked one at a time. The file is
written to a temporary file next to `filename` and moved into place when it is complete,
so a failure leaves no file.

# Arguments

  - `filename::AbstractString`: the output file; its extension (`.mp4`, `.gif`, …) sets
    the format. Throws an `ArgumentError` without one.
  - `frames::AbstractVector{<:AbstractPottsRenderFrame{2}}`: the frames, at least one,
    all with the same geometry.
  - `solution`: a `CorePotts.PottsSolution` or `CorePotts.PottsFrames` of a 2D run.

# Keywords

  - `request::RenderRequest = RenderRequest()`: as for [`renderframe`](@ref).
  - `framerate::Real = 30`: frames per second, positive and finite.
  - `encoding::AbstractPottsEncoding = CellTypeEncoding()`: the encoding.
  - `title::AbstractString = "Potts model"`: the axis title.
  - `figure = (;)`, `axis = (;)`, `plot = (;)`: keywords of the figure, the axis and
    [`pottsplot`](@ref).

Throws an `ArgumentError` for no frames, frames of different geometry or a bad
framerate, `MakiePotts.InvalidRenderFrameError` for a frame that fails
[`render_frame_conformance`](@ref), and [`MakiePotts.RecordingError`](@ref) when Makie
writes an empty file.

# Returns

  - `String`: `filename`.

# Examples

```julia
using Potts, MakiePotts, CairoMakie
record_potts("run.mp4", sol; framerate = 10, title = "Mix")
```

See also [`explore_potts`](@ref), [`record_field`](@ref).
"""
function record_potts(
        filename::AbstractString,
        frames::AbstractVector{<:AbstractPottsRenderFrame{2}};
        kwargs...
    )
    _validate_recording_frames(frames)
    return _record_frames(
        i -> frames[i], first(frames), eachindex(frames), filename; kwargs...
    )
end

function record_potts(
        filename::AbstractString,
        solution::CorePotts.PottsSolution;
        request::RenderRequest = RenderRequest(), kwargs...
    )
    return record_potts(filename, renderframes(solution, request); kwargs...)
end

function record_potts(
        filename::AbstractString,
        frames::CorePotts.PottsFrames;
        request::RenderRequest = RenderRequest(), kwargs...
    )
    first_frame = _first_written_frame(frames, request)
    getframe(i) = _next_written_frame(frames, request, i, first_frame)
    return _record_frames(getframe, first_frame, eachindex(frames.t), filename; kwargs...)
end

# record `getframe(i)` for each `i` in `indices`, starting the figure with `first_frame`
function _record_frames(
        getframe::F, first_frame, indices, filename::AbstractString;
        framerate::Real = 30, kwargs...
    ) where {F}
    rate = _validate_framerate(framerate)
    fig, _, _, frame = _record_figure(first_frame; kwargs...)
    return _atomic_record(filename) do temporary
        Makie.record(fig, temporary, indices; framerate = rate) do index
            frame[] = getframe(index)
        end
    end
end
