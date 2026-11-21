# Frames written to disk while a run continues (`FrameWritingCallback`), and a lazy reader
# of written frames (`PottsFrames`).
#
# At a frame, the callback copies the state (or the leaves of `save_idxs`) into one of two
# reused host buffers and hands the buffer to a writer task (`Threads.@spawn`), which
# appends it to the file and gives the buffer back. On ROCm the buffers are pinned
# (`KernelAbstractions.pagelock!`) and the copy is enqueued without a wait, with an event
# that the writer task waits for (the AMDGPU extension); on other backends the copy is
# finished when the callback returns. The run waits only when both buffers are still in
# use. A failure of the writer task is raised on the run's task at the next frame or at the
# end of the run (`FrameWriteError`); the writer task closes the writer whatever happens,
# and `solve!` stops the writer task when the run fails or is interrupted.

"""
    AbstractFrameWriter

Supertype of the destinations that [`FrameWritingCallback`](@ref) writes frames to. A
writer implements:

- `open_frames!(w, u)`: start a new set of frames; `u` is a host state shaped like every
  frame (its values are not defined). Called on the run's task when the run starts.
- `write_frame!(w, t, u)`: append the frame `u` (a host `CPMState`) saved at MCS `t`. `u`
  is a reused buffer: copy what you keep before returning.
- `close(w)`: finish the frames (the default does nothing).

`write_frame!` and `close` run on the writer task, in order and never at once. To be read
back by [`PottsFrames`](@ref), a writer or a reader object implements
`frame_times(source)` and `read_frame(source, i)`. [`FrameFile`](@ref) is the built-in
writer and reader.
"""
abstract type AbstractFrameWriter end

"""
    open_frames!(writer, u)

Start a new set of frames in `writer` (an [`AbstractFrameWriter`](@ref)): `u` is a host
state shaped like every frame that follows; its values are not defined. Called once per
run, on the run's task.
"""
function open_frames!(w, u)
    return _no_frame_method(:open_frames!, w)
end

"""
    write_frame!(writer, t, u)

Append the frame `u` (a host `CPMState`) saved at MCS `t` to `writer` (an
[`AbstractFrameWriter`](@ref)). `u` is a reused buffer: a writer copies what it keeps.
Called on the writer task.
"""
function write_frame!(w, t, u)
    return _no_frame_method(:write_frame!, w)
end

"""
    frame_times(source) -> Vector{Int}

The MCS of the frames in `source` (a [`FrameFile`](@ref) or another frame source), in the
order they were written. Part of the reader interface of [`PottsFrames`](@ref).
"""
function frame_times(source)
    return _no_frame_method(:frame_times, source)
end

"""
    read_frame(source, i) -> CPMState

The `i`-th frame of `source` (a [`FrameFile`](@ref) or another frame source), as a host
state. Part of the reader interface of [`PottsFrames`](@ref).
"""
function read_frame(source, i)
    return _no_frame_method(:read_frame, source)
end

Base.close(::AbstractFrameWriter) = nothing

"""
    FrameFile(path)

The built-in frame writer and reader: a JLD2 file at `path` that holds each frame as a
`CPMState` and its MCS. Load JLD2 (`using JLD2`) to write or read one. Each run that writes
to it (`init`, `reinit!`) replaces the file. `PottsFrames(path)` reads it.
"""
mutable struct FrameFile <: AbstractFrameWriter
    const path::String
    io::Any                 # the open file (for writing or for reading), or nothing
    count::Int              # frames written by this writer
end
FrameFile(path::AbstractString) = FrameFile(String(path), nothing, 0)

function Base.show(io::IO, w::FrameFile)
    return print(io, "FrameFile(", repr(w.path), ")")
end

@noinline function _no_frame_method(name::Symbol, w)
    hint = if w isa FrameFile
        "FrameFile writes and reads JLD2 files: load JLD2 (`using JLD2`)"
    else
        "a frame writer implements `open_frames!`, `write_frame!` and `close`, and a frame \
            source `frame_times` and `read_frame`"
    end
    throw(ArgumentError("`$name` has no method for $(typeof(w)); $hint"))
end

"""
    FrameWriteError(error::CapturedException)

Exception raised on the run's task when writing frames failed on the writer task. `error`
holds the writer's exception and its backtrace. The frames written before the failure stay
in the file, which is closed.
"""
struct FrameWriteError <: Exception
    error::CapturedException
end
function Base.showerror(io::IO, e::FrameWriteError)
    print(io, "FrameWriteError: writing frames failed on the writer task: ")
    return showerror(io, e.error)
end

# ---------------------------------------------------------------------------------------
# Backend hooks (the AMDGPU extension overrides them)

# `dst` (a host buffer) gets the values of `src`: on a device, enqueued (finished when the
# token of `_frame_copied` is waited for); here finished on return
_frame_copy_async!(dst::Array, src::AbstractArray) = (_copy_to_host!(dst, src); nothing)
# a token for the copies enqueued so far on this task's queue, or nothing when they are done
_frame_copied(backend) = nothing
# wait (on the writer task) until the copies of `token` are done
_wait_frame_copied(::Nothing) = nothing
# release a host buffer pinned by `KernelAbstractions.pagelock!`
_unpin!(backend, a::Array) = nothing

# ---------------------------------------------------------------------------------------
# Host buffers

"""Adaptor: each array leaf becomes an uninitialized host array of its shape, pinned for
`backend` (`KernelAbstractions.pagelock!`; a no-op on the CPU)."""
struct _PinnedBuffer{B}
    backend::B
end
function Adapt.adapt_storage(b::_PinnedBuffer, a::AbstractArray)
    h = Array{eltype(a)}(undef, size(a))
    # (pinning an empty array is not allowed on every backend; an empty copy needs none)
    isempty(h) || KernelAbstractions.pagelock!(b.backend, h)
    return h
end

# the array leaves of a state, in a fixed order (an unselected ownership is `nothing`)
function _frame_leaves(st::CPMState)
    return (
        st.ownership, values(st.cell)..., values(st.site)..., values(st.model)...,
        values(st.history)...,
    )
end

struct _LeafCopy{S}
    stats::S
end
(c::_LeafCopy)(::Nothing, ::Nothing) = nothing
function (c::_LeafCopy)(dst::Array, src::AbstractArray)
    if _ondevice(src)
        _count_transfer!(c.stats, 0, 1, _nbytes(src))
        _frame_copy_async!(dst, src)
    else
        copyto!(dst, src)
    end
    return nothing
end

struct _Unpin{B}
    backend::B
end
(u::_Unpin)(::Nothing) = nothing
(u::_Unpin)(a::Array) = (isempty(a) || _unpin!(u.backend, a); nothing)

# ---------------------------------------------------------------------------------------
# The callback

# One run's writing: the two buffers, the channels of free buffers and of frames to write,
# and the writer task. `failure` is set by the writer task before it closes the channels.
mutable struct _FrameSession{B, K}
    const buffers::Tuple{B, B}
    const backend::K
    const owner::UInt                   # objectid of the integrator
    const free::Channel{Int}
    const work::Channel{Tuple{Int, Int, Any}}
    task::Union{Nothing, Task}
    @atomic failure::Union{Nothing, CapturedException}
    last::Int                           # the MCS of the last frame sent
end

mutable struct _FrameWriting{W}
    const writer::W
    const saveat::Any
    const save_everystep::Bool
    const save_start::Bool
    const save_end::Bool
    const save_idxs::Any
    times::Vector{Int}                  # the `saveat` MCS of the current run
    leaves::Any                         # the resolved `save_idxs` (or nothing)
    session::Any                        # a `_FrameSession` while a run writes, or nothing
end

struct _FrameDue{F}
    fw::F
end
function (d::_FrameDue)(u, t, integ)
    fw = d.fw
    return fw.session !== nothing && (fw.save_everystep || insorted(t, fw.times))
end

(fw::_FrameWriting)(integ) = (_send_frame!(fw, integ); nothing)

"""
    FrameWritingCallback(writer; saveat = Int[], save_everystep = isempty(saveat),
        save_start = true, save_end = true, save_idxs = nothing)

A `DiscreteCallback` that writes frames of a `PottsProblem` run to `writer` (a
[`FrameFile`](@ref) or another [`AbstractFrameWriter`](@ref)) while the run continues. Its
saving keywords read as `solve`'s: frames at `saveat` (MCS, or a number: every that many MCS
from `t0`), at every MCS when `save_everystep`, at the start and at the end; `save_idxs`
names the state leaves to write. The callback saves nothing in the solution
(`save_positions = (false, false)`): pass `save_everystep = false` or `saveat` to `solve` so
that the solution holds few states.

A frame is copied into one of two reused host buffers (pinned on ROCm, where the copy does
not wait for the device), and a writer task (`Threads.@spawn`) appends it to the file. The
run waits only when both buffers are still being written. Start Julia with 2 or more
threads (`julia -t 2`) to write while the run continues.

A failure of the writer is raised as a [`FrameWriteError`](@ref) at the next frame or at
the end of the run. The file is closed at the end of the run, after a writer failure and
when `solve` fails or is interrupted. A hand-driven integrator (`init` and `step!`) closes
it at `solve!`. One callback writes one run at a time; give each trajectory of an ensemble
its own callback and writer. Runs with derivative parts are refused.
"""
function FrameWritingCallback(
        writer; saveat = Int[], save_everystep::Bool = isempty(saveat),
        save_start::Bool = true, save_end::Bool = true, save_idxs = nothing
    )
    if saveat isa Number
        _mcs(saveat, "saveat") > 0 || throw(
            ArgumentError("`saveat`: a step of $saveat MCS; give a positive number of MCS")
        )
    else
        foreach(s -> _mcs(s, "saveat"), saveat)
    end
    fw = _FrameWriting(
        writer, saveat, save_everystep, save_start, save_end, save_idxs, Int[], nothing,
        nothing
    )
    return DiscreteCallback(
        _FrameDue(fw), fw; initialize = _frames_initialize, finalize = _frames_finalize,
        save_positions = (false, false)
    )
end

function _frames_initialize(cb, u, t, integ)
    fw = cb.affect!
    integ isa PottsIntegrator ||
        throw(ArgumentError("FrameWritingCallback writes the frames of a PottsProblem run"))
    s = fw.session
    if s !== nothing
        s.owner == objectid(integ) || throw(
            ArgumentError(
                "this FrameWritingCallback is writing another run; give each run (each \
                    trajectory of an ensemble) its own callback and writer"
            )
        )
        # `reinit!` of the run that writes: its frames end here, the new run's start
        _finish_frames!(fw)
    end
    tangent_on(integ.ctx) isa Val{true} && throw(
        ArgumentError(
            "FrameWritingCallback: this run has derivative parts, which frames do not hold"
        )
    )
    fw.times = fw.save_everystep ? Int[] : _saveat_list(fw.saveat, integ.t, integ.tstop)
    fw.leaves = _saved_leaves(integ.prob, fw.save_idxs)
    src = _select(integ.state, fw.leaves)
    b = _PinnedBuffer(integ.backend)
    buffers = (Adapt.adapt(b, src), Adapt.adapt(b, src))
    try
        open_frames!(fw.writer, buffers[1])
    catch err
        _unpin_buffers!(integ.backend, buffers)
        rethrow(err)
    end
    s = _FrameSession(
        buffers, integ.backend, objectid(integ), Channel{Int}(2),
        Channel{Tuple{Int, Int, Any}}(2), nothing, nothing, typemin(Int)
    )
    put!(s.free, 1)
    put!(s.free, 2)
    s.task = Threads.@spawn _frame_writer_loop($(fw.writer), $s)
    fw.session = s
    fw.save_start && _send_frame!(fw, integ)
    return nothing
end

function _frames_finalize(cb, u, t, integ)
    fw = cb.affect!
    fw.session === nothing && return nothing
    fw.save_end && _send_frame!(fw, integ)
    _finish_frames!(fw)
    return nothing
end

# Copy the frame at `integ.t` into a free buffer and hand it to the writer task (once per
# MCS). Raises the writer's failure, if any.
function _send_frame!(fw::_FrameWriting, integ)
    s = fw.session::_FrameSession
    integ.t == s.last && return nothing
    (@atomic s.failure) === nothing || _finish_frames!(fw)
    i = try
        take!(s.free)
    catch e
        # the writer task failed and closed the channel
        e isa InvalidStateException || (_abort_frames!(fw); rethrow())
        _finish_frames!(fw)
        rethrow()
    end
    try
        map(
            _LeafCopy(_stats(integ)), _frame_leaves(s.buffers[i]),
            _frame_leaves(_select(integ.state, fw.leaves))
        )
        token = _frame_copied(integ.backend)
        s.last = integ.t
        put!(s.work, (i, integ.t, token))
    catch e
        e isa InvalidStateException || (_abort_frames!(fw); rethrow())
        _finish_frames!(fw)
        rethrow()
    end
    return nothing
end

# The writer task: write each frame once its copy is done, give its buffer back; close the
# writer at the end, after a failure too. Never throws: a failure is kept in the session.
function _frame_writer_loop(w::W, s::_FrameSession) where {W}
    try
        for (i, t, token) in s.work
            _wait_frame_copied(token)
            write_frame!(w, t, s.buffers[i])
            put!(s.free, i)
        end
    catch e
        @atomic s.failure = CapturedException(e, catch_backtrace())
    finally
        try
            close(w)
        catch e
            (@atomic s.failure) === nothing &&
                (@atomic s.failure = CapturedException(e, catch_backtrace()))
        end
        close(s.free)
        close(s.work)
    end
    return nothing
end

function _unpin_buffers!(backend, buffers)
    for b in buffers
        foreach(_Unpin(backend), _frame_leaves(b))
    end
    return nothing
end

# The end of a run's writing: the writer task writes the frames sent so far and closes the
# writer; a failure of it is raised here. Does nothing when no run writes.
function _finish_frames!(fw::_FrameWriting)
    s = fw.session
    s === nothing && return nothing
    fw.session = nothing
    close(s.work)
    s.task === nothing || wait(s.task)
    _unpin_buffers!(s.backend, s.buffers)
    f = @atomic s.failure
    f === nothing || throw(FrameWriteError(f))
    return nothing
end

# The run failed or was interrupted: the writing ends as `_finish_frames!`, and a failure
# of the writer is logged, not raised (the run's own error is the one to see).
function _abort_frames!(fw::_FrameWriting)
    try
        _finish_frames!(fw)
    catch e
        e isa FrameWriteError || rethrow()
        @error "writing frames also failed" exception = e.error
    end
    return nothing
end

# `solve!` calls this for each callback when the run fails or is interrupted
_abort_callback!(cb) = (_abort_affect!(cb.affect!); nothing)
_abort_affect!(affect) = nothing
_abort_affect!(fw::_FrameWriting) = _abort_frames!(fw)

# ---------------------------------------------------------------------------------------
# The lazy reader

"""The frames of a source as a lazy vector: element `i` is read when it is indexed."""
struct LazyFrames{S} <: AbstractVector{Any}
    source::S
    n::Int
end
Base.size(v::LazyFrames) = (v.n,)
Base.IndexStyle(::Type{<:LazyFrames}) = IndexLinear()
function Base.getindex(v::LazyFrames, i::Int)
    @boundscheck checkbounds(v, i)
    return read_frame(v.source, i)
end

"""
    PottsFrames(path::AbstractString; prob = nothing)
    PottsFrames(source; prob = nothing)

Written frames read like a solution, each frame read from disk only when indexed. `path`
is a [`FrameFile`](@ref)'s file; `source` is any object with `frame_times` and
`read_frame`. `frames[i]` is the `i`-th frame (a host `CPMState`), `frames(t)` the frame
written at MCS `t`, `frames.t` the MCS of every frame and `frames.u` the frames as a lazy
vector. Give `prob`, the problem of the run, to draw each frame's frozen sites and the
lattice spacing in MakiePotts plots and videos, as for a solution. `close(frames)` closes
the file.
"""
struct PottsFrames{S, P}
    source::S
    t::Vector{Int}
    u::LazyFrames{S}
    prob::P
end
function PottsFrames(path::AbstractString; prob = nothing)
    return PottsFrames(FrameFile(path); prob)
end
function PottsFrames(source; prob = nothing)
    t = Vector{Int}(frame_times(source))
    issorted(t) || throw(ArgumentError("the frames' MCS are not in order: $t"))
    return PottsFrames(source, t, LazyFrames(source, length(t)), prob)
end

Base.length(f::PottsFrames) = length(f.t)
Base.firstindex(f::PottsFrames) = 1
Base.lastindex(f::PottsFrames) = length(f.t)
Base.eachindex(f::PottsFrames) = eachindex(f.t)
Base.getindex(f::PottsFrames, i::Int) = f.u[i]
Base.getindex(f::PottsFrames, i::AbstractVector{<:Integer}) = [f.u[j] for j in i]
function Base.iterate(f::PottsFrames, i::Int = 1)
    return i > length(f) ? nothing : (f.u[i], i + 1)
end
Base.eltype(::Type{<:PottsFrames}) = Any
Base.close(f::PottsFrames) = close(f.source)

function (f::PottsFrames)(t::Real)
    r = isinteger(t) ? searchsorted(f.t, t) : 1:0
    isempty(r) && throw(
        ArgumentError(
            string(
                "frames(t): no frame was written at MCS t = ", t, "; frames at ",
                length(f.t) <= 12 ? f.t :
                    "[$(join(f.t[1:5], ", ")), …, $(join(f.t[(end - 4):end], ", "))]"
            )
        )
    )
    return f.u[first(r)]
end

function Base.show(io::IO, f::PottsFrames)
    return print(io, "PottsFrames(", length(f), " frames)")
end
function Base.show(io::IO, ::MIME"text/plain", f::PottsFrames)
    n = length(f)
    print(io, "PottsFrames: ", n, " frame", n == 1 ? "" : "s", " of ", f.source)
    n == 0 && return nothing
    return print(
        io, "\nt: ", n <= 12 ? f.t :
            "[$(join(f.t[1:5], ", ")), …, $(join(f.t[(end - 4):end], ", "))]"
    )
end
