# The JLD2 format of `FrameFile`: each frame is a `CPMState` at `u/<k>` and its MCS at
# `t/<k>`, with a format marker. Written through an `IOStream` (JLD2's memory-mapped
# writer was 2.5–4× slower on frames of 4–17 MiB; D-300).
module CorePottsJLD2Ext

using CorePotts: CorePotts, FrameFile
using JLD2: JLD2

const FORMAT = "Potts.jl frames 1"

function CorePotts.open_frames!(w::FrameFile, u)
    close(w)
    w.io = JLD2.jldopen(w.path, "w"; iotype = IOStream)
    w.io["format"] = FORMAT
    w.count = 0
    return nothing
end

function CorePotts.write_frame!(w::FrameFile, t::Integer, u)
    f = w.io
    (f isa JLD2.JLDFile && f.writable) ||
        throw(ArgumentError("$w is not open for writing: call `open_frames!` first"))
    k = w.count + 1
    f["u/$k"] = u
    f["t/$k"] = Int(t)
    w.count = k
    return nothing
end

function Base.close(w::FrameFile)
    f = w.io
    f === nothing && return nothing
    w.io = nothing
    close(f)
    return nothing
end

function reading(w::FrameFile)
    f = w.io
    if f === nothing
        f = JLD2.jldopen(w.path, "r")
        if !haskey(f, "format") || f["format"] != FORMAT
            close(f)
            throw(ArgumentError("$(repr(w.path)) is not a frame file (no `format` = \
                $(repr(FORMAT)))"))
        end
        w.io = f
    end
    f.writable && throw(ArgumentError("$w is open for writing; read it after the run"))
    return f
end

function CorePotts.frame_times(w::FrameFile)
    f = reading(w)
    haskey(f, "t") || return Int[]
    g = f["t"]
    return Int[g[string(k)] for k in 1:length(keys(g))]
end

function CorePotts.read_frame(w::FrameFile, i::Integer)
    f = reading(w)
    k = string(i)
    (haskey(f, "u") && haskey(f["u"], k)) ||
        throw(BoundsError(w, i))
    return f["u"][k]
end

end # module CorePottsJLD2Ext
