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

"""
    normal(T, a::UInt32, b::UInt32)

A standard normal draw in float type `T` from two uniform words (Box–Muller, cosine branch:
`√(−2 log u₁) cos(2π u₂)` with `u = uniform(T, ·)` on the open interval, so it is finite).
The tails are cut where the smallest `u₁` puts them: `|z| ≤ 5.77` in `Float32` (`u₁ ≥ 2⁻²⁴`,
a tail mass of about 8·10⁻⁹) and `|z| ≤ 6.76` in `Float64` (`u₁ ≥ 2⁻³³`).
"""
@inline function normal(::Type{T}, a::UInt32, b::UInt32) where {T <: AbstractFloat}
    u1 = uniform(T, a)
    u2 = uniform(T, b)
    return sqrt(-2 * log(u1)) * cos(T(6.283185307179586) * u2)
end

"""Most attempts of a bounded normal draw (`bounded_normal`)."""
const MAX_DRAW_ATTEMPTS = 64
"""Status bit: a bounded draw found no value above its bound in `MAX_DRAW_ATTEMPTS` attempts."""
const STATUS_DRAW_EXHAUSTED = UInt32(2)
"""Status bit: a bounded draw was given a negative SD `σ`."""
const STATUS_DRAW_NEGATIVE_SD = UInt32(4)
"""
Name of a model's optional status word in `st.model` (a 1-element `UInt32` array): bits a
model's generated code sets (e.g. `STATUS_DRAW_EXHAUSTED`); the integrator reads it at host
read points and fails the run (`ReturnCode.Failure`) when it is nonzero.
"""
const MODEL_STATUS = Symbol("#status")

"""
    bounded_normal(T, key, mcs, entity, stream, μ, σ, lower, status)

`μ + σ z` with `z` standard normal, redrawn while `≤ lower`: attempt `k = 0, 1, …` is the draw
at local index `k` of the address `(mcs, entity, stream)`, at most `MAX_DRAW_ATTEMPTS`. On
exhaustion the status word `status` (a 1-element `UInt32` array, or `nothing`) takes
`STATUS_DRAW_EXHAUSTED` and the value is NaN: no throw, so it runs inside kernels. A
negative `σ` gives NaN and `STATUS_DRAW_NEGATIVE_SD`.
"""
@inline function bounded_normal(::Type{T}, key::RNGKey, mcs, entity, stream::UInt32, μ, σ, lower, status) where {T}
    σ < 0 && (_set_status!(status, STATUS_DRAW_NEGATIVE_SD); return T(NaN))
    for k in 0:(MAX_DRAW_ATTEMPTS - 1)
        a, b, _, _ = draw(key, mcs, entity, stream, k)
        x = T(μ) + T(σ) * normal(T, a, b)
        x > lower && return x
    end
    _set_status!(status, STATUS_DRAW_EXHAUSTED)
    return T(NaN)
end
@inline _set_status!(::Nothing, bit) = nothing
@inline _set_status!(status, bit) = (Atomix.@atomic status[1] |= bit; nothing)     # status has 1 entry
# the model's status word at a host read point (`_check_status!`); 0 without one
_model_status(stats, model::NamedTuple) = haskey(model, MODEL_STATUS) ? _readback(stats, getfield(model, MODEL_STATUS)) : UInt32(0)
_model_status(stats, model) = UInt32(0)
"""`normal(T, words)`: `normal(T, words[1], words[2])` of a `draw`."""
@inline normal(::Type{T}, w::NTuple{4, UInt32}) where {T <: AbstractFloat} = normal(T, w[1], w[2])
