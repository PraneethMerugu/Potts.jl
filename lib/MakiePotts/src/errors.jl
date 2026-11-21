"""Thrown when a render frame is incomplete or internally inconsistent."""
struct InvalidRenderFrameError <: Exception
    messages::Vector{String}
end

function Base.showerror(io::IO, error::InvalidRenderFrameError)
    return print(io, "invalid Potts render frame:\n  - ", join(error.messages, "\n  - "))
end

"""Thrown when an encoding's declared requirements are absent from a frame."""
struct MissingRenderChannelError <: Exception
    key
    available::Vector{Any}
end

MissingRenderChannelError(key) = MissingRenderChannelError(key, Any[])

function Base.showerror(io::IO, error::MissingRenderChannelError)
    print(io, "render channel ", error.key, " is not available in this frame")
    if isempty(error.available)
        print(io, "; the frame declares no channels")
    else
        print(
            io, "; available channels: ",
            join(map(item -> sprint(show, item), error.available), ", ")
        )
    end
    return print(io, ". Construct the frame with an explicit RenderChannel value")
end

"""
    RecordingError(destination)

Thrown when a Makie recording finishes without a nonempty output file.

[`record_potts`](@ref) and [`record_field`](@ref) write to a temporary file next to
`destination` and move it into place only when it is nonempty, so on this error
`destination` is left as it was.

# Fields

  - `destination::String`: the requested output file.

See also [`record_potts`](@ref).
"""
struct RecordingError <: Exception
    destination::String
end

function Base.showerror(io::IO, error::RecordingError)
    return print(
        io, "Makie recording completed without producing a nonempty artifact at ",
        repr(error.destination)
    )
end
