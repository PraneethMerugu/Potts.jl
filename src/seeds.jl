# Sub-stream seeds (ROADMAP P6.0w, D-093). StableRNG streams at seeds `s` and `s + 1` are
# draw-wise shifted copies of each other (D-082), so a seed derived from another seed must
# go through a mixer, never `seed + k`. The mixer is pinned so that a sub-stream is the same
# on every Julia version (D-075).

"""
    _splitmix64(x::UInt64) -> UInt64

One step of Vigna's SplitMix64 from state `x`: add the golden gamma, then the Stafford
variant-13 finalizer. A bijection of `UInt64`; `_splitmix64(0) == 0xe220a8397b1dcdaf`.
"""
function _splitmix64(x::UInt64)
    z = x + 0x9e3779b97f4a7c15
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end

"""
    _substream_seed(seed::Integer, stream::Union{Symbol, AbstractString}) -> UInt64

The seed of sub-stream `stream` of the top-level seed `seed` (`0 ≤ seed ≤ typemax(UInt64)`):
`_splitmix64(_splitmix64(UInt64(seed)) ⊻ UInt64(CorePotts.stream_id(stream)))`. The name
goes through `stream_id` (FNV-1a), which is stable across sessions, unlike `hash`. For a
fixed stream distinct seeds give distinct sub-seeds, and for a fixed seed distinct stream
ids do too. Use it wherever a seed is derived from another seed, e.g.
`StableRNG(Potts._substream_seed(seed, :clock))` (D-093).
"""
function _substream_seed(seed::Integer, stream::Union{Symbol, AbstractString})
    return _splitmix64(_splitmix64(UInt64(seed)) ⊻ UInt64(CorePotts.stream_id(stream)))
end
