function _record_figure(first_frame::AbstractPottsRenderFrame{2};
        encoding::AbstractPottsEncoding = CellTypeEncoding(),
        title::AbstractString = "Potts model",
        figure = (;), axis = (;), plot = (;))
    fig = Makie.Figure(; figure...)
    ax = Makie.Axis(fig[1, 1];
        title = String(title), aspect = Makie.DataAspect(), axis...)
    frame = Makie.Observable(first_frame)
    rendered = pottsplot!(ax, frame; encoding, plot...)
    return fig, ax, rendered, frame
end

function _validate_framerate(framerate::Real)
    value = Float64(framerate)
    isfinite(value) && value > 0 ||
        throw(ArgumentError("recording framerate must be positive and finite; got $framerate"))
    return isinteger(value) ? Int(value) : value
end

function _validate_recording_frames(frames)
    isempty(frames) && throw(ArgumentError("recording requires at least one frame"))
    foreach(assert_render_frame_conformance, frames)
    expected = frame_geometry(first(frames))
    for (index, frame) in pairs(frames)
        actual = frame_geometry(frame)
        actual == expected && continue
        throw(ArgumentError(
            "recording frame $index has incompatible geometry; " *
            "expected $expected, got $actual"))
    end
    return expected
end

function _atomic_record(write_recording::Function, filename::AbstractString)
    destination = String(filename)
    extension = splitext(destination)[2]
    isempty(extension) && throw(ArgumentError(
        "recording filename must include an output extension"))
    return mktempdir() do directory
        temporary = joinpath(directory, "makiepotts-recording$extension")
        write_recording(temporary)
        isfile(temporary) && filesize(temporary) > 0 ||
            error("Makie recording completed without producing a nonempty artifact")
        mv(temporary, destination; force = true)
        destination
    end
end

"""
    record_potts(filename, frames; framerate=30, kwargs...)

Thin recording wrapper over `Makie.record`. All frames are validated before the
first output frame is written.
"""
function record_potts(filename::AbstractString,
        frames::AbstractVector{<:AbstractPottsRenderFrame{2}};
        framerate::Real = 30, kwargs...)
    _validate_recording_frames(frames)
    rate = _validate_framerate(framerate)
    fig, _, _, frame = _record_figure(first(frames); kwargs...)
    return _atomic_record(filename) do temporary
        Makie.record(fig, temporary, eachindex(frames);
                framerate = rate) do index
            frame[] = frames[index]
        end
    end
end

function record_potts(filename::AbstractString,
        solution::PottsToolkit.PottsSolution;
        request::RenderRequest = RenderRequest(), kwargs...)
    return record_potts(filename, renderframes(solution, request); kwargs...)
end

"""
Lower-level thin wrapper for recording a caller-owned composition. `update!`
receives the current item and must atomically publish its own Observables.
"""
function record_potts(filename::AbstractString, figure,
        items; framerate::Real = 30, update!::Function)
    rate = _validate_framerate(framerate)
    return _atomic_record(filename) do temporary
        Makie.record(figure, temporary, items;
                framerate = rate) do item
            update!(item)
        end
    end
end
