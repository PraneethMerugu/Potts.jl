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

"""
    Potts.layer_rng(seed) -> StableRNG
    Potts.layer_rng(seed, stream) -> StableRNG

The random stream of a randomized layout layer or initial-state builder with top-level seed
`seed` (an integer in `0:typemax(UInt64)`): `StableRNG(UInt64(seed))`, or, for the named
sub-stream `stream` (a `Symbol` or string), `StableRNG(Potts._substream_seed(seed, stream))`
(D-093). Both are the same on every Julia version (StableRNGs). Use the two-argument form for
a second, independent stream drawn from the same seed (for example a builder's clocks next
to its layout): a seed derived as `seed + 1` would give a shifted copy of the first stream.
Throws an `ArgumentError` for a seed outside `0:typemax(UInt64)`.

```julia
rng = Potts.layer_rng(seed, :clock)
clocks = [rand(rng, 0:74) for _ in 1:n]
```
"""
layer_rng(seed::Integer) = (_check_seed(seed, "layer_rng"); StableRNG(UInt64(seed)))
function layer_rng(seed::Integer, stream::Union{Symbol, AbstractString})
    _check_seed(seed, "layer_rng")
    return StableRNG(_substream_seed(seed, stream))
end

function _check_seed(seed::Integer, what)
    0 <= seed <= typemax(UInt64) || throw(ArgumentError("$what: seed must be in 0:typemax(UInt64), got $seed"))
    return nothing
end
