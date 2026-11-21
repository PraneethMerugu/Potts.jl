# The JLD2 format of `FrameFile`: a directory of segment files `frames-<n>.jld2`, each with
# a format marker and up to `checkpoint` frames, a `CPMState` at `u/<k>` and its MCS at
# `t/<k>`. JLD2 writes a file's group tables and header only when it closes the file, so a
# killed process leaves the open segment unreadable; closed segments are never written
# again, so they survive. Reopening one file in append mode instead patches its group
# headers in place at each close (a kill then can break the whole file) and costs more as
# the file grows. Segments cost about as much as one file closed at the end. Written through
# an `IOStream` (JLD2's memory-mapped writer was 2.5–4× slower on frames of 4–17 MiB).
# D-300.
module CorePottsJLD2Ext

using CorePotts: CorePotts, FrameFile
using JLD2: JLD2

const FORMAT = "Potts.jl frames 1"

segment_name(n::Integer) = string("frames-", lpad(n, 6, '0'), ".jld2")
function segment_number(name::AbstractString)
    m = match(r"^frames-(\d{6,})\.jld2$", name)
    return m === nothing ? nothing : parse(Int, m.captures[1])
end

function CorePotts.open_frames!(w::FrameFile, u)
    (@atomicreplace w.state 0 => 1).success || throw(
        ArgumentError(
            "$w holds a run already (or is writing one); give each run (each `solve`, \
                `reinit!` or trajectory) its own FrameFile"
        )
    )
    ispath(w.path) && !isdir(w.path) && throw(
        ArgumentError(
            "FrameFile writes a directory of segments, and $(repr(w.path)) is a file"
        )
    )
    mkpath(w.path)
    # a new run replaces the segments of an earlier one
    for name in readdir(w.path)
        segment_number(name) === nothing || rm(joinpath(w.path, name))
    end
    w.segment = 0
    w.count = 0
    return nothing
end

function CorePotts.write_frame!(w::FrameFile, t::Integer, u)
    (@atomic w.state) == 1 ||
        throw(ArgumentError("$w is not open for writing: call `open_frames!` first"))
    if w.io === nothing
        w.segment += 1
        f = JLD2.jldopen(joinpath(w.path, segment_name(w.segment)), "w"; iotype = IOStream)
        f["format"] = FORMAT
        w.io = f
        w.count = 0
    end
    f = w.io
    k = w.count + 1
    f["u/$k"] = u
    f["t/$k"] = Int(t)
    w.count = k
    k >= w.checkpoint && close_segment!(w)
    return nothing
end

function close_segment!(w::FrameFile)
    f = w.io
    f === nothing && return nothing
    w.io = nothing
    close(f)
    return nothing
end

# the reader: where each frame is (segment, k), the frames' MCS, and one open segment
mutable struct Reader
    const segments::Vector{String}
    const where::Vector{Tuple{Int, Int}}
    const t::Vector{Int}
    open::Int                   # the index in `segments` of the open file, or 0
    file::Any
end

function Base.close(w::FrameFile)
    if (@atomic w.state) == 1
        close_segment!(w)
        @atomic w.state = 2
    end
    r = w.reader
    if r !== nothing
        w.reader = nothing
        r.file === nothing || close(r.file)
    end
    return nothing
end

function open_segment(path)
    f = JLD2.jldopen(path, "r")
    if !haskey(f, "format") || f["format"] != FORMAT
        close(f)
        throw(ArgumentError("$(repr(path)) is not a frame segment (no `format` = \
            $(repr(FORMAT)))"))
    end
    return f
end

function reader(w::FrameFile)
    (@atomic w.state) == 1 &&
        throw(ArgumentError("$w is open for writing; read it after the run"))
    w.reader === nothing || return w.reader
    isdir(w.path) || throw(
        ArgumentError("$(repr(w.path)) is not a frame directory (a FrameFile writes one)")
    )
    names = filter(n -> segment_number(n) !== nothing, readdir(w.path))
    sort!(names; by = segment_number)
    segments = String[]
    where = Tuple{Int, Int}[]
    t = Int[]
    for (j, name) in enumerate(names)
        path = joinpath(w.path, name)
        f = try
            JLD2.jldopen(path, "r")
        catch e
            # a run that was killed (or is still writing) leaves its last segment open
            j == length(names) || throw(
                ArgumentError("frame segment $(repr(path)) cannot be read: $e")
            )
            @warn "the last segment $(repr(path)) cannot be read (a run that stopped \
                while writing it, or that still writes it); its frames are skipped"
            break
        end
        try
            if !haskey(f, "format") || f["format"] != FORMAT
                throw(ArgumentError("$(repr(path)) is not a frame segment (no `format` \
                    = $(repr(FORMAT)))"))
            end
            push!(segments, path)
            if haskey(f, "t")
                g = f["t"]
                for k in 1:length(keys(g))
                    push!(where, (length(segments), k))
                    push!(t, g[string(k)])
                end
            end
        finally
            close(f)
        end
    end
    return w.reader = Reader(segments, where, t, 0, nothing)
end

CorePotts.frame_times(w::FrameFile) = copy(reader(w).t)

function CorePotts.read_frame(w::FrameFile, i::Integer)
    r = reader(w)
    checkbounds(Bool, r.where, i) || throw(BoundsError(w, i))
    s, k = r.where[i]
    if r.open != s
        r.file === nothing || close(r.file)
        r.file = nothing
        r.file = open_segment(r.segments[s])
        r.open = s
    end
    return r.file["u/$k"]
end

end # module CorePottsJLD2Ext
