# Address-keyed Philox4x32-10 (Salmon et al. 2011).
#
#   key     = philox of the tagged tuple (seed, replica, repeat)
#   counter = (mcs, entity, stream, local)
#
# Every draw is a pure function of its address, so results do not depend on thread or
# launch order. The same seed reproduces a run on a given backend (a free debugging aid,
# not a published guarantee; see DECISIONS D-029).

const PHILOX_M0 = 0xD2511F53
const PHILOX_M1 = 0xCD9E8D57
const PHILOX_W0 = 0x9E3779B9
const PHILOX_W1 = 0xBB67AE85

@inline function _mulhilo(a::UInt32, b::UInt32)
    p = UInt64(a) * UInt64(b)
    return (p >> 32) % UInt32, p % UInt32
end

@inline function philox4x32(c0::UInt32, c1::UInt32, c2::UInt32, c3::UInt32,
        k0::UInt32, k1::UInt32)
    for _ in 1:10
        hi0, lo0 = _mulhilo(PHILOX_M0, c0)
        hi1, lo1 = _mulhilo(PHILOX_M1, c2)
        c0, c1, c2, c3 = hi1 ⊻ c1 ⊻ k0, lo1, hi0 ⊻ c3 ⊻ k1, lo0
        k0 += PHILOX_W0
        k1 += PHILOX_W1
    end
    return c0, c1, c2, c3
end

"""
    RNGKey

The trajectory key: two words derived from `(seed, replica, repeat)` without collisions
between distinct tuples.
"""
struct RNGKey
    k0::UInt32
    k1::UInt32
end

const _KEY_TAG = (0x43505331, 0x6b657931)   # "CPS1", "key1"

function RNGKey(seed::Integer, replica::Integer = 0, repeat::Integer = 0)
    s = UInt64(seed)
    r0, r1, _, _ = philox4x32(s % UInt32, (s >> 32) % UInt32, UInt32(replica),
        UInt32(repeat), _KEY_TAG...)
    return RNGKey(r0, r1)
end

"""
    stream_id(name) -> UInt32

Stable 32-bit identity of a random operation (FNV-1a of its namespaced name). Editing
one operation never renumbers another.
"""
function stream_id(name::AbstractString)
    h = 0x811c9dc5
    for b in codeunits(name)
        h = (h ⊻ b) * 0x01000193
    end
    return h
end
stream_id(name::Symbol) = stream_id(String(name))

const STREAM_PROPOSAL = stream_id("CorePotts.proposal")      # direction, acceptance, priority
const STREAM_SEQUENTIAL_TARGET = stream_id("CorePotts.sequential_target")
const STREAM_COLOR_ORDER = stream_id("CorePotts.color_order")
const RESERVED_STREAMS = (STREAM_PROPOSAL, STREAM_SEQUENTIAL_TARGET, STREAM_COLOR_ORDER)

"""
    draw(key, mcs, entity, stream, local = 0) -> NTuple{4, UInt32}

Four independent 32-bit words for one address. `entity` is a site index or a cell's
`(id << 8) | (generation & 0xff)`; `local` packs round/substep/draw/retry.
"""
@inline function draw(key::RNGKey, mcs::Integer, entity::Integer, stream::UInt32,
        local_index::Integer = 0)
    # wrapping conversions: in range by construction, and no exception branch in kernels (X1)
    return philox4x32(mcs % UInt32, entity % UInt32, stream, local_index % UInt32,
        key.k0, key.k1)
end

"""Uniform draw on the open interval (0, 1): grid midpoints, never 0 or 1."""
@inline uniform(::Type{Float32}, x::UInt32) = (Float32(x >> 9) + 0.5f0) * Float32(0x1p-23)
@inline uniform(::Type{Float64}, x::UInt32) = (Float64(x) + 0.5) * 0x1p-32
@inline uniform(::Type{T}, x::UInt32) where {T <: AbstractFloat} = T(uniform(Float64, x))

"""Lemire multiply-shift draw on `0:n-1` (bias ≤ n / 2³²)."""
@inline bounded(x::UInt32, n::Integer) = Int((UInt64(x) * UInt64(n)) >> 32)

@inline cell_entity(id::Integer, generation::Integer) =
    (UInt32(id) << 8) | (UInt32(generation) & 0xff)
