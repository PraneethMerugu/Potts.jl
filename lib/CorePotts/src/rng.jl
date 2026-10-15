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
const STREAM_BOUNDARY_SITE = stream_id("CorePotts.boundary_site")  # skip, target, direction, acceptance
const STREAM_CLAIM_ORDER = stream_id("CorePotts.claim_order")      # permuted claim priorities (> 2^24 sites per color)
const RESERVED_STREAMS = (STREAM_PROPOSAL, STREAM_SEQUENTIAL_TARGET, STREAM_COLOR_ORDER, STREAM_BOUNDARY_SITE,
    STREAM_CLAIM_ORDER)

"""
    draw(key, mcs, entity, stream, local = 0) -> NTuple{4, UInt32}

Four independent 32-bit words for one address. `entity` is a site index or a cell's
`cell_entity(id, generation)`; `local` packs round/substep/draw/retry.

`entity` is 64-bit: its low word is the counter word, and its high word is folded into the
key as `k0 ⊻ hi * W1` (a bijection of `hi`; `hi = 0` leaves the key as it is). An entity below
2³² therefore draws exactly as before, and no two entities below 2⁶⁴ share a stream.
"""
@inline function draw(key::RNGKey, mcs::Integer, entity::Integer, stream::UInt32,
        local_index::Integer = 0)
    # wrapping conversions: in range by construction, and no exception branch in kernels (X1)
    e = entity % UInt64
    hi = (e >> 32) % UInt32
    # the branch keeps the key loop-invariant on the common `hi = 0` path, so its schedule
    # is hoisted (the unconditional xor cost ~15% per draw on the CPU); uniform on GPUs
    k0 = hi == 0 ? key.k0 : key.k0 ⊻ (hi * PHILOX_W1)
    return philox4x32(mcs % UInt32, e % UInt32, stream, local_index % UInt32, k0, key.k1)
end

"""Uniform draw on the open interval (0, 1): grid midpoints, never 0 or 1."""
@inline uniform(::Type{Float32}, x::UInt32) = (Float32(x >> 9) + 0.5f0) * Float32(0x1p-23)
@inline uniform(::Type{Float64}, x::UInt32) = (Float64(x) + 0.5) * 0x1p-32
@inline uniform(::Type{T}, x::UInt32) where {T <: AbstractFloat} = T(uniform(Float64, x))

"""Lemire multiply-shift draw on `0:n-1` (bias ≤ n / 2³²)."""
@inline bounded(x::UInt32, n::Integer) = Int((UInt64(x) * UInt64(n)) >> 32)

"""Multiply-shift draw on `0:n-1` from two words, `hi` and `lo` (bias ≤ n / 2⁶⁴; host only)."""
@inline bounded64(hi::UInt32, lo::UInt32, n::Integer) =
    Int((UInt128((UInt64(hi) << 32) | lo) * UInt128(n)) >> 64)

# Site picks of the sequential sweeps over `n` sites (D-247): one word up to 2^24 mobile sites,
# where the bias n / 2³² is at most 2⁻⁸ and every existing run keeps its draws; two words
# above (bias ≤ n / 2⁶⁴). The regime is part of the sweep context's type: the caller adds
# `var"#pick" = TwoWordPick()` above the threshold, and a context without it compiles to the
# one-word sweep exactly (a runtime branch in the loop slowed the CPU sweeps). The key is not
# an identifier, so no relation (whose names share the context) can take or shadow it.
const PICK_ONE_WORD_MAX = 2^24
struct TwoWordPick end
# tests: the two-word pick on a small lattice (read by the caller once per MCS)
const _FORCE_TWO_WORD_PICK = Ref(false)
const PICK_KEY = Symbol("#pick")
_with_two_word_pick(ctx::NamedTuple) = merge(ctx, NamedTuple{(PICK_KEY,)}((TwoWordPick(),)))
_two_word_pick(n) = _FORCE_TWO_WORD_PICK[] || n > PICK_ONE_WORD_MAX
# resolved at compile time; dispatch on the folded `Val` leaves no branch (`get` left an empty block)
@inline _pick_regime(ctx::NamedTuple{names}) where {names} = _pick_regime(ctx, Val(PICK_KEY in names))
@inline _pick_regime(::NamedTuple, ::Val{false}) = nothing
@inline _pick_regime(ctx::NamedTuple, ::Val{true}) = getfield(ctx, PICK_KEY)
# dispatch, not a ternary, and the one-word method is `bounded`'s body rather than a call to it,
# so it inlines to exactly the old IR (each wrapper layer leaves an empty block)
@inline site_pick(::Nothing, hi::UInt32, lo::UInt32, n::Integer) = Int((UInt64(hi) * UInt64(n)) >> 32)
@inline site_pick(::TwoWordPick, hi::UInt32, lo::UInt32, n::Integer) = bounded64(hi, lo, n)

"""
    cell_entity(id, generation) -> UInt64

The `draw` entity of a cell: `(id << 8) | (generation & 0xff)`, 64-bit so that ids at
or above 2²⁴ do not wrap onto smaller ids (equal to the old 32-bit value below 2²⁴).
"""
@inline cell_entity(id::Integer, generation::Integer) =
    ((id % UInt64) << 8) | ((generation % UInt64) & 0xff)

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
# a diagnostic counter (`Potts`' `track = (:references,)`): entry `j` of `cnt` (j in range by
# construction) incremented atomically, on the host or the device
@inline _bump!(cnt, j) = (Atomix.@atomic cnt[j] += one(eltype(cnt)); nothing)
# `a[j] += v` atomically, for `j` in `1:length(a)` (0, the medium, and a stale index are skipped):
# `@convert` transfers and writes
@inline function _atomic_add!(a, j, v)
    ((0 < j) & (j <= length(a))) && (@inbounds Atomix.@atomic a[j] += convert(eltype(a), v))   # bound checked here
    return nothing
end
# the model's status word at a host read point (`_check_status!`); 0 without one
_model_status(stats, model::NamedTuple) = haskey(model, MODEL_STATUS) ? _readback(stats, getfield(model, MODEL_STATUS)) : UInt32(0)
_model_status(stats, model) = UInt32(0)
"""`normal(T, words)`: `normal(T, words[1], words[2])` of a `draw`."""
@inline normal(::Type{T}, w::NTuple{4, UInt32}) where {T <: AbstractFloat} = normal(T, w[1], w[2])
