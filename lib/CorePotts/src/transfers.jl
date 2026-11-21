# Host↔device traffic (D-085). Every explicit synchronize and every copy between the host
# and a device that the integrator makes goes through the helpers below, which count into
# the integrator's `PottsStats` (`syncs`, `transfers`, `transfer_bytes`):
#
#   sync!(stats, backend)          _device_wait(backend), 1 sync
#   to_host(stats, a)              Array(a), 1 transfer of sizeof(a)
#   counted_copy!(stats, dst, src)         copyto!(dst, src), 1 transfer when it crosses
#                                          host↔device
#   _readback(stats, a)             the first element of a 1-element array (an `Array` copy)
#   snapshot(stats, backend, st)   host copy of a state: 1 transfer per device array leaf
#
# Device→device copies and device fills are not transfers. Nothing is counted on the CPU:
# `_ondevice(::Array)` is a compile-time `false` and `sync!(stats, ::CPU)` adds nothing, so
# the CPU paths compile to what they were (no allocation, no branch). `stats` is a
# `PottsStats` or `nothing` (a call outside an integrator: nothing is counted).
#
# Every wait for a device goes through `_device_wait` (D-179): `sync!`, and every
# device→host copy (`to_host`, `counted_copy!` and with them `_readback` and `snapshot`),
# which is enqueued without waiting (`_copy_to_host!`) and then waited for. On the CPU the
# wait is a no-op and on Metal `KernelAbstractions.synchronize` (Metal's own copy to the
# host waits the same way); on ROCm (the AMDGPU extension) it spins on the stream without
# allocating: AMDGPU's default wait, which every `copyto!` to the host makes too, wakes up
# through a HIP host callback and Julia's event loop, ~13 ms per read point on the lifecycle
# models.

"""Seconds a device wait spins before it raises (`_device_wait`): far beyond any MCS's
queued work, well before a hang goes unnoticed."""
const DEVICE_WAIT_TIMEOUT = 600.0

"""
    _device_wait(backend; timeout = DEVICE_WAIT_TIMEOUT) -> nothing

Wait until every operation queued on `backend` has finished. A no-op on the CPU and
`KernelAbstractions.synchronize` on other backends; on ROCm (the AMDGPU extension) a
non-allocating `hipStreamQuery` spin (`_spin_until`) and then a blocking stream synchronize,
which returns at once and reports a stream error.
"""
function _device_wait(backend; timeout::Real = DEVICE_WAIT_TIMEOUT)
    (KernelAbstractions.synchronize(backend); nothing)
end
_device_wait(::KernelAbstractions.CPU; timeout::Real = DEVICE_WAIT_TIMEOUT) = nothing

"""
    _spin_until(done, timeout) -> nothing

Spin until `done()` is true: a GC safepoint every turn (another thread's collection can
finish) and a `yield` every 2^12 turns (another task, such as AMDGPU's hostcall service,
can run on this thread); throws once more than `timeout` seconds have passed.
"""
function _spin_until(done::F, timeout::Real) where {F}
    done() && return nothing
    t0 = time_ns()
    limit = timeout * 1.0e9
    k = 0
    while !done()
        # the CPU's spin-wait hint (x86 `pause`, ARM `yield`): Julia has no public form of
        # it (`Base.Threads` uses this ccall in its own spin locks); an upstream gap, see
        # D-294
        ccall(:jl_cpu_pause, Cvoid, ())
        GC.safepoint()
        k += 1
        if k & 0x0fff == 0
            yield()
            time_ns() - t0 > limit && _wait_timed_out(timeout)
        end
    end
    return nothing
end

"""
    DeviceTimeoutError(timeout)

The exception thrown when a wait for queued device work takes more than `timeout`
seconds.

# Fields
- `timeout::Float64`: the time limit of the wait, in seconds.

See also [`sync!`](@ref).
"""
struct DeviceTimeoutError <: Exception
    timeout::Float64
end
function Base.showerror(io::IO, e::DeviceTimeoutError)
    return print(io, "device wait timed out after $(e.timeout) s: the work queued on the \
        device is not done")
end

@noinline _wait_timed_out(timeout) = throw(DeviceTimeoutError(Float64(timeout)))

"""`copyto!(dst, doff, src, soff, n)` from device array `src` into host array `dst`,
finished on return: enqueued without waiting and then waited for (`_device_wait`) where the
backend allows (ROCm: the AMDGPU extension); elsewhere the backend's own copy waits as
`_device_wait` would."""
function _copy_to_host!(
        dst::AbstractArray, doff::Integer, src::AbstractArray, soff::Integer, n::Integer
    )
    return copyto!(dst, doff, src, soff, n)
end
_copy_to_host!(dst::AbstractArray, src::AbstractArray) = copyto!(dst, src)

"""`Array(a)` for device array `a`, finished on return (through `_copy_to_host!`)."""
_host_copy(a::AbstractArray) = Array(a)

"""Whether array `a` lives on a device (not host memory)."""
_ondevice(::Array) = false
_ondevice(::BitArray) = false
function _ondevice(a::AbstractArray)
    return !(KernelAbstractions.get_backend(a) isa KernelAbstractions.CPU)
end

"""
The one counter: add `syncs` synchronizations and `transfers` copies of `bytes` in total to
`stats`.
"""
@inline _count_transfer!(::Nothing, syncs, transfers, bytes) = nothing
@inline function _count_transfer!(stats, syncs, transfers, bytes)
    stats.syncs += syncs
    stats.transfers += transfers
    stats.transfer_bytes += bytes
    return nothing
end

"""
    sync!(stats, backend) -> nothing

Wait until every operation queued on `backend` has finished, and count one
synchronization in `stats`.

On the CPU the call does nothing and counts nothing.

# Arguments
- `stats`: a `PottsStats`, or `nothing` to count nothing.
- `backend`: a KernelAbstractions backend.

# Returns
- `nothing`.

See also [`to_host`](@ref), [`counted_copy!`](@ref).
"""
function sync!(stats, backend)
    _device_wait(backend)
    _count_transfer!(stats, 1, 0, 0)
    return nothing
end
sync!(stats, backend::KernelAbstractions.CPU) = _device_wait(backend)

"""Bytes of the elements of `a` (`sizeof` is not defined alike for every array type)."""
_nbytes(a::AbstractArray) = length(a) * sizeof(eltype(a))

"""
    to_host(stats, a) -> Array

Return a host copy of `a`, as `Array(a)`.

When `a` lives on a device, the copy is counted in `stats` as one transfer of the bytes
of `a`, and it is finished when the call returns.

# Arguments
- `stats`: a `PottsStats`, or `nothing` to count nothing.
- `a::AbstractArray`: the array.

# Returns
- `Array`: the host copy.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.to_host(nothing, [1, 2, 3])
3-element Vector{Int64}:
 1
 2
 3
```

See also [`counted_copy!`](@ref), [`adapt_host`](@ref).
"""
function to_host(stats, a::AbstractArray)
    _ondevice(a) || return Array(a)
    _count_transfer!(stats, 0, 1, _nbytes(a))
    return _host_copy(a)
end

"""
    counted_copy!(stats, dst, src) -> dst

Copy `src` into `dst`, as `copyto!(dst, src)`.

When the copy crosses between the host and a device, it is counted in `stats` as one
transfer. A copy from a device to the host is finished when the call returns.

# Arguments
- `stats`: a `PottsStats`, or `nothing` to count nothing.
- `dst::AbstractArray`: the destination.
- `src::AbstractArray`: the source.

# Returns
- `dst`.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.counted_copy!(nothing, zeros(Int, 2), [4, 5])
2-element Vector{Int64}:
 4
 5
```

See also [`to_host`](@ref), [`sync!`](@ref).
"""
function counted_copy!(stats, dst::AbstractArray, src::AbstractArray)
    d, s = _ondevice(dst), _ondevice(src)
    d == s || _count_transfer!(stats, 0, 1, _nbytes(d ? dst : src))
    return s && !d ? _copy_to_host!(dst, src) : copyto!(dst, src)
end

"""
    counted_copy!(stats, dst, doff, src, soff, n) -> dst

Copy `n` elements of `src` from index `soff` into `dst` from index `doff`, as
`copyto!(dst, doff, src, soff, n)`.

When the copy crosses between the host and a device, it is counted in `stats` as one
transfer of the bytes of `n` elements. A copy from a device to the host is finished when
the call returns.

# Arguments
- `stats`: a `PottsStats`, or `nothing` to count nothing.
- `dst::AbstractArray`, `doff::Integer`: the destination and its first index.
- `src::AbstractArray`, `soff::Integer`: the source and its first index.
- `n::Integer`: the number of elements.

# Returns
- `dst`.
"""
function counted_copy!(
        stats, dst::AbstractArray, doff::Integer,
        src::AbstractArray, soff::Integer, n::Integer
    )
    d, s = _ondevice(dst), _ondevice(src)
    d == s || _count_transfer!(stats, 0, 1, n * sizeof(eltype(src)))
    return if s && !d
        _copy_to_host!(dst, doff, src, soff, n)
    else
        copyto!(dst, doff, src, soff, n)
    end
end

"""The first element of a 1-element array, on the host (no copy on the CPU)."""
_readback(stats, a::Array) = a[1]
_readback(stats, a) = to_host(stats, a)[1]

"""Adaptor for host snapshots: each device array leaf is one counted copy (`Array(a)`); a
host leaf is kept as `Adapt.adapt(Array, …)` keeps it."""
struct _HostCopy{S}
    stats::S
end
function Adapt.adapt_storage(h::_HostCopy, a::AbstractArray)
    return _ondevice(a) ? to_host(h.stats, a) : Adapt.adapt_storage(Array, a)
end

"""
    adapt_host(stats, x)

Return `Adapt.adapt(Array, x)`: `x` with every device array leaf replaced by a host copy.

Each device array leaf is counted in `stats` as one transfer. A host leaf is kept as
`Adapt.adapt(Array, …)` keeps it.

# Arguments
- `stats`: a `PottsStats`, or `nothing` to count nothing.
- `x`: any object that Adapt can walk, such as a state or a `NamedTuple` of arrays.

# Returns
- The adapted object.

See also [`snapshot`](@ref), [`to_host`](@ref).
"""
adapt_host(stats, x) = Adapt.adapt(_HostCopy(stats), x)

"""
    snapshot(stats, backend, st)

Return a host copy of the state `st` that does not share memory with the live state.

On the CPU this is a `deepcopy`, not counted. On a device each array leaf is one counted
transfer (as [`adapt_host`](@ref)). The call does not synchronize first.

# Arguments
- `stats`: a `PottsStats`, or `nothing` to count nothing.
- `backend`: the KernelAbstractions backend of `st`.
- `st`: the state.

# Returns
- The host copy of `st`.

See also [`host_leaves`](@ref).
"""
snapshot(stats, backend, st) = adapt_host(stats, st)
snapshot(stats, ::KernelAbstractions.CPU, st) = deepcopy(st)

# Host copies of device arrays that nothing writes during a run: the lattice's domain mask
# (D-092; audit A4, H3). Copied (counted) the first time host code asks, then reused while
# the device array lives: keyed by its identity, held weakly (as `_AdaptiveODE` keys its
# integrators), so concurrent trajectories each get their own entry and a freed array's
# entry is dropped. The copy is shared: host code must not write it. Not for parameter
# arrays: a user or a host phase may write those in place.
const _HOST_CACHE = Dict{UInt, Tuple{WeakRef, Any}}()
const _HOST_CACHE_LOCK = ReentrantLock()

"""Host copy of the run-constant device array `a`, copied (counted) once and then reused."""
function _cached_host(stats, a::AbstractArray)
    _ondevice(a) || return Adapt.adapt_storage(Array, a)
    return lock(_HOST_CACHE_LOCK) do
        e = get(_HOST_CACHE, objectid(a), nothing)
        e !== nothing && e[1].value === a && return e[2]
        filter!(kv -> kv[2][1].value !== nothing, _HOST_CACHE)     # drop freed arrays
        h = to_host(stats, a)
        _HOST_CACHE[objectid(a)] = (WeakRef(a), h)
        return h
    end::Array{eltype(a), ndims(a)}
end

"""Adaptor: each device array leaf becomes its cached host copy (`_cached_host`)."""
struct _CachedHostCopy{S}
    stats::S
end
Adapt.adapt_storage(h::_CachedHostCopy, a::AbstractArray) = _cached_host(h.stats, a)

"""`Adapt.adapt(Array, x)` for run-constant `x` (the lattice): each device array leaf is
copied once per run (`_cached_host`)."""
_adapt_host_cached(stats, x) = Adapt.adapt(_CachedHostCopy(stats), x)

"""
    host_buffer(a) -> Array

Return an uninitialized host array with the element type and size of `a`.

No data is copied: it is a buffer for host code to fill.

# Arguments
- `a::AbstractArray`: the array to match.

# Returns
- `Array{eltype(a)}`: the buffer, of size `size(a)`.

# Examples
```jldoctest
julia> using CorePotts

julia> size(CorePotts.host_buffer(zeros(Float32, 3, 2)))
(3, 2)
```
"""
host_buffer(a::AbstractArray) = Array{eltype(a)}(undef, size(a))

"""
    host_leaves(stats, st; ownership = false, cell = (), site = (), model = (),
                history = ())

Return a host state for host code that touches only some leaves of `st`.

The `ownership` array (when `ownership` is true) and the leaves named in `cell`, `site`,
`model` and `history` are host copies: counted transfers on a device, and the live arrays
themselves on the host. Every other leaf is the live array, which on a device must not be
read on the host.

# Arguments
- `stats`: a `PottsStats`, or `nothing` to count nothing.
- `st::CPMState`: the state.

# Keywords
- `ownership::Bool = false`: copy the `ownership` array.
- `cell = ()`, `site = ()`, `model = ()`, `history = ()`: the names of the leaves to copy
  in each part of the state.

# Returns
- `CPMState`: the state with the named leaves on the host.

See also [`snapshot`](@ref), [`adapt_host`](@ref).
"""
function host_leaves(
        stats, st::CPMState; ownership::Bool = false,
        cell = (), site = (), model = (), history = ()
    )
    function part(nt, names)
        if isempty(names)
            return nt
        else
            return merge(
                nt,
                NamedTuple{Tuple(names)}(
                    map(n -> adapt_host(stats, getfield(nt, n)), Tuple(names))
                )
            )
        end
    end
    return CPMState(
        ownership ? adapt_host(stats, st.ownership) : st.ownership, part(st.cell, cell),
        part(st.site, site),
        part(st.model, model), part(st.history, history)
    )
end
