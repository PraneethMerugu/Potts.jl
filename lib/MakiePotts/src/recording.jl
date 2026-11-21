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
    record_potts(filename, frames; framerate=30, kwargs...)
    record_potts(filename, solution; request=RenderRequest(), kwargs...)

Thin recording wrapper over `Makie.record`. All frames are validated before the
first output frame is written. `solution` is a `PottsSolution`, whose states are rendered
first (`renderframes`), or the frames a run wrote to disk (`CorePotts.PottsFrames`), which
are read and rendered one at a time; each is validated when it is rendered, and a failure
leaves no file.
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
