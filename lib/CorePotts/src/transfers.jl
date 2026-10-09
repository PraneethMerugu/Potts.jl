# Host↔device traffic (D-085). Every explicit synchronize and every copy between the host
# and a device that the integrator makes goes through the helpers below, which count into
# the integrator's `PottsStats` (`syncs`, `transfers`, `transfer_bytes`):
#
#   _sync!(stats, backend)          _device_wait(backend), 1 sync
#   _to_host(stats, a)              Array(a), 1 transfer of sizeof(a)
#   _copy!(stats, dst, src)         copyto!(dst, src), 1 transfer when it crosses host↔device
#   _readback(stats, a)             the first element of a 1-element array (an `Array` copy)
#   _snapshot(stats, backend, st)   host copy of a state: 1 transfer per device array leaf
#
# Device→device copies and device fills are not transfers. Nothing is counted on the CPU:
# `_ondevice(::Array)` is a compile-time `false` and `_sync!(stats, ::CPU)` adds nothing, so
# the CPU paths compile to what they were (no allocation, no branch). `stats` is a
# `PottsStats` or `nothing` (a call outside an integrator: nothing is counted).
#
# Every wait for a device goes through `_device_wait` (D-179): `_sync!`, and every
# device→host copy (`_to_host`, `_copy!` and with them `_readback` and `_snapshot`), which is
# enqueued without waiting (`_copy_to_host!`) and then waited for. On the CPU the wait is a
# no-op and on Metal `KernelAbstractions.synchronize` (Metal's own copy to the host waits the
# same way); on ROCm (the AMDGPU extension) it spins on the stream without allocating:
# AMDGPU's default wait, which every `copyto!` to the host makes too, wakes up through a HIP
# host callback and Julia's event loop, ~13 ms per read point on the lifecycle models.

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
_device_wait(backend; timeout::Real = DEVICE_WAIT_TIMEOUT) = (KernelAbstractions.synchronize(backend); nothing)
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
        ccall(:jl_cpu_pause, Cvoid, ())
        ccall(:jl_gc_safepoint, Cvoid, ())
        k += 1
        if k & 0x0fff == 0
            yield()
            time_ns() - t0 > limit && _wait_timed_out(timeout)
        end
    end
    return nothing
end

@noinline _wait_timed_out(timeout) =
    error("device wait timed out after $(timeout) s: the work queued on the device is not done")

"""`copyto!(dst, doff, src, soff, n)` from device array `src` into host array `dst`, finished
on return: enqueued without waiting and then waited for (`_device_wait`) where the backend
allows (ROCm: the AMDGPU extension); elsewhere the backend's own copy waits as
`_device_wait` would."""
_copy_to_host!(dst::AbstractArray, doff::Integer, src::AbstractArray, soff::Integer, n::Integer) =
    copyto!(dst, doff, src, soff, n)
_copy_to_host!(dst::AbstractArray, src::AbstractArray) = copyto!(dst, src)

"""`Array(a)` for device array `a`, finished on return (through `_copy_to_host!`)."""
_host_copy(a::AbstractArray) = Array(a)

"""Whether array `a` lives on a device (not host memory)."""
_ondevice(::Array) = false
_ondevice(::BitArray) = false
_ondevice(a::AbstractArray) = !(KernelAbstractions.get_backend(a) isa KernelAbstractions.CPU)

"""The one counter: add `syncs` synchronizations and `transfers` copies of `bytes` in total to `stats`."""
@inline _count_transfer!(::Nothing, syncs, transfers, bytes) = nothing
@inline function _count_transfer!(stats, syncs, transfers, bytes)
    stats.syncs += syncs
    stats.transfers += transfers
    stats.transfer_bytes += bytes
    return nothing
end

"""`_device_wait(backend)`, counted on a device backend."""
function _sync!(stats, backend)
    _device_wait(backend)
    _count_transfer!(stats, 1, 0, 0)
    return nothing
end
_sync!(stats, backend::KernelAbstractions.CPU) = _device_wait(backend)

"""Bytes of the elements of `a` (`sizeof` is not defined alike for every array type)."""
_nbytes(a::AbstractArray) = length(a) * sizeof(eltype(a))

"""`Array(a)`: a host copy, counted when `a` lives on a device."""
function _to_host(stats, a::AbstractArray)
    _ondevice(a) || return Array(a)
    _count_transfer!(stats, 0, 1, _nbytes(a))
    return _host_copy(a)
end

"""`copyto!(dst, src)`, counted when it crosses between the host and a device."""
function _copy!(stats, dst::AbstractArray, src::AbstractArray)
    d, s = _ondevice(dst), _ondevice(src)
    d == s || _count_transfer!(stats, 0, 1, _nbytes(d ? dst : src))
    return s && !d ? _copy_to_host!(dst, src) : copyto!(dst, src)
end

"""`copyto!(dst, doff, src, soff, n)`: `n` elements, counted (`n` elements' bytes) when it
crosses between the host and a device."""
function _copy!(stats, dst::AbstractArray, doff::Integer, src::AbstractArray, soff::Integer, n::Integer)
    d, s = _ondevice(dst), _ondevice(src)
    d == s || _count_transfer!(stats, 0, 1, n * sizeof(eltype(src)))
    return s && !d ? _copy_to_host!(dst, doff, src, soff, n) : copyto!(dst, doff, src, soff, n)
end

"""The first element of a 1-element array, on the host (no copy on the CPU)."""
_readback(stats, a::Array) = a[1]
_readback(stats, a) = _to_host(stats, a)[1]

"""Adaptor for host snapshots: each device array leaf is one counted copy (`Array(a)`); a
host leaf is kept as `Adapt.adapt(Array, …)` keeps it."""
struct _HostCopy{S}
    stats::S
end
Adapt.adapt_storage(h::_HostCopy, a::AbstractArray) =
    _ondevice(a) ? _to_host(h.stats, a) : Adapt.adapt_storage(Array, a)

"""`Adapt.adapt(Array, x)`, counting every device array leaf of `x`."""
_adapt_host(stats, x) = Adapt.adapt(_HostCopy(stats), x)

"""Host snapshot of a state, independent of the live state (a `deepcopy` on the CPU, not
counted). Does not synchronize."""
_snapshot(stats, backend, st) = _adapt_host(stats, st)
_snapshot(stats, ::KernelAbstractions.CPU, st) = deepcopy(st)

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
        h = _to_host(stats, a)
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

"""Uninitialized host array shaped like `a` (no transfer): a buffer host code fills."""
_host_buffer(a::AbstractArray) = Array{eltype(a)}(undef, size(a))

"""
Host state for host code that touches only some leaves of `st`: `σ` (when `σ`) and the
leaves named in `cell`, `site`, `model` and `history` are host copies (counted on a device;
the live arrays themselves on the host); every other leaf is the live array, which on a
device must not be read on the host.
"""
function _host_leaves(stats, st::CPMState; σ::Bool = false, cell = (), site = (), model = (), history = ())
    part(nt, names) = isempty(names) ? nt :
                      merge(nt, NamedTuple{Tuple(names)}(map(n -> _adapt_host(stats, getfield(nt, n)), Tuple(names))))
    return CPMState(σ ? _adapt_host(stats, st.σ) : st.σ, part(st.cell, cell), part(st.site, site),
        part(st.model, model), part(st.history, history))
end
