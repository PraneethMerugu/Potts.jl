"""Thrown when a render frame is incomplete or internally inconsistent."""
struct InvalidRenderFrameError <: Exception
    messages::Vector{String}
end

function Base.showerror(io::IO, error::InvalidRenderFrameError)
    print(io, "invalid Potts render frame:\n  - ", join(error.messages, "\n  - "))
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
        print(io, "; available channels: ",
            join(map(item -> sprint(show, item), error.available), ", "))
    end
    print(io, ". Construct the frame with an explicit RenderChannel value")
end
