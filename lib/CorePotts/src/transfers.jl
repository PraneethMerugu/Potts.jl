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
