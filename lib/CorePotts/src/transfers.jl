# Host↔device traffic (D-085). Every explicit synchronize and every copy between the host
# and a device that the integrator makes goes through the helpers below, which count into
# the integrator's `PottsStats` (`syncs`, `transfers`, `transfer_bytes`):
#
#   _sync!(stats, backend)          KernelAbstractions.synchronize, 1 sync
#   _to_host(stats, a)              Array(a), 1 transfer of sizeof(a)
#   _copy!(stats, dst, src)         copyto!(dst, src), 1 transfer when it crosses host↔device
#   _readback(stats, a)             the first element of a 1-element array (an `Array` copy)
#   _snapshot(stats, backend, st)   host copy of a state: 1 transfer per device array leaf
#
# Device→device copies and device fills are not transfers. Nothing is counted on the CPU:
# `_ondevice(::Array)` is a compile-time `false` and `_sync!(stats, ::CPU)` adds nothing, so
# the CPU paths compile to what they were (no allocation, no branch). `stats` is a
# `PottsStats` or `nothing` (a call outside an integrator: nothing is counted).

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

"""`KernelAbstractions.synchronize(backend)`, counted on a device backend."""
function _sync!(stats, backend)
    KernelAbstractions.synchronize(backend)
    _count_transfer!(stats, 1, 0, 0)
    return nothing
end
_sync!(stats, backend::KernelAbstractions.CPU) = KernelAbstractions.synchronize(backend)

"""Bytes of the elements of `a` (`sizeof` is not defined alike for every array type)."""
_nbytes(a::AbstractArray) = length(a) * sizeof(eltype(a))

"""`Array(a)`: a host copy, counted when `a` lives on a device."""
function _to_host(stats, a::AbstractArray)
    _ondevice(a) && _count_transfer!(stats, 0, 1, _nbytes(a))
    return Array(a)
end

"""`copyto!(dst, src)`, counted when it crosses between the host and a device."""
function _copy!(stats, dst::AbstractArray, src::AbstractArray)
    d, s = _ondevice(dst), _ondevice(src)
    d == s || _count_transfer!(stats, 0, 1, _nbytes(d ? dst : src))
    return copyto!(dst, src)
end

"""`copyto!(dst, doff, src, soff, n)`: `n` elements, counted (`n` elements' bytes) when it
crosses between the host and a device."""
function _copy!(stats, dst::AbstractArray, doff::Integer, src::AbstractArray, soff::Integer, n::Integer)
    _ondevice(dst) == _ondevice(src) || _count_transfer!(stats, 0, 1, n * sizeof(eltype(src)))
    return copyto!(dst, doff, src, soff, n)
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
