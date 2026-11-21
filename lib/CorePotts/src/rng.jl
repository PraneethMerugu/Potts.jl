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

@inline function philox4x32(
        c0::UInt32, c1::UInt32, c2::UInt32, c3::UInt32,
        k0::UInt32, k1::UInt32
    )
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
    RNGKey(seed, replica = 0, repeat = 0)
    RNGKey(k0::UInt32, k1::UInt32)

The key of one trajectory's random streams, for [`draw`](@ref).

The integer form hashes the tuple `(seed, replica, repeat)` with one Philox4x32-10 call
into the two key words, so distinct tuples give distinct keys. The two-word form takes the
words as they are.

# Arguments
- `seed::Integer`: the run's seed, converted to `UInt64`.
- `replica::Integer = 0`: the replicate number, converted to `UInt32`.
- `repeat::Integer = 0`: the repeat number, converted to `UInt32`.

# Fields
- `k0::UInt32`, `k1::UInt32`: the two key words.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.RNGKey(1) == CorePotts.RNGKey(1, 0, 0)
true

julia> CorePotts.RNGKey(1) == CorePotts.RNGKey(1, 1)
false
```

See also [`draw`](@ref).
"""
struct RNGKey
    k0::UInt32
    k1::UInt32
end

const _KEY_TAG = (0x43505331, 0x6b657931)   # "CPS1", "key1"

function RNGKey(seed::Integer, replica::Integer = 0, repeat::Integer = 0)
    s = UInt64(seed)
    r0, r1, _, _ = philox4x32(
        s % UInt32, (s >> 32) % UInt32, UInt32(replica),
        UInt32(repeat), _KEY_TAG...
    )
    return RNGKey(r0, r1)
end

"""
    stream_id(name) -> UInt32

Return the 32-bit identity of a random operation: the FNV-1a hash of its name.

Each random operation draws from its own stream, so a new or edited operation does not
change the draws of another. Use a namespaced name (`"MyModel.noise"`) to avoid
collisions with the solver's own streams.

# Arguments
- `name::Union{AbstractString, Symbol}`: the operation's name.

# Returns
- `UInt32`: the stream number, the same in every session.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.stream_id("MyModel.noise") == CorePotts.stream_id(:var"MyModel.noise")
true
```

See also [`draw`](@ref).
"""
function stream_id(name::AbstractString)
    h = 0x811c9dc5
    for b in codeunits(name)
        h = (h ⊻ b) * 0x01000193
    end
    return h
end
stream_id(name::Symbol) = stream_id(String(name))

# direction, acceptance, priority
const STREAM_PROPOSAL = stream_id("CorePotts.proposal")
const STREAM_SEQUENTIAL_TARGET = stream_id("CorePotts.sequential_target")
const STREAM_COLOR_ORDER = stream_id("CorePotts.color_order")
# block scheme: direction, acceptance, site
const STREAM_BLOCK = stream_id("CorePotts.block")
# skip, target, direction, acceptance
const STREAM_BOUNDARY_SITE = stream_id("CorePotts.boundary_site")
const RESERVED_STREAMS = (
    STREAM_PROPOSAL, STREAM_SEQUENTIAL_TARGET, STREAM_COLOR_ORDER, STREAM_BLOCK,
    STREAM_BOUNDARY_SITE,
)

"""
    draw(key, mcs, entity, stream, local = 0) -> NTuple{4, UInt32}

Return four random 32-bit words for one address: a Philox4x32-10 call keyed by `key`.

Each draw is a pure function of its address, so the result does not depend on thread or
launch order. The counter is `(mcs, entity, stream, local)`, each wrapped to 32 bits,
except `entity`. `entity` is wrapped to 64 bits: its low word is the counter word, and its
high word `hi` is folded into the key as `k0 ⊻ hi * W1`, which is a bijection of `hi`. So
no two entities below 2⁶⁴ share a stream. Wrapping conversions keep the call free of
exceptions, so it runs inside kernels.

# Arguments
- `key::RNGKey`: the trajectory's key.
- `mcs::Integer`: the MCS number.
- `entity::Integer`: a site index, or a cell's [`cell_entity`](@ref)`(id, generation)`.
- `stream::UInt32`: the operation, from [`stream_id`](@ref).
- `local::Integer = 0`: the draw within the address, for example a round, substep or
  retry number.

# Returns
- `NTuple{4, UInt32}`: four words, each uniform on `0:2³²-1`.

# Examples
```jldoctest
julia> using CorePotts

julia> k = CorePotts.RNGKey(7); s = CorePotts.stream_id("MyModel.noise");

julia> CorePotts.draw(k, 1, 5, s) == CorePotts.draw(k, 1, 5, s, 0)
true

julia> CorePotts.draw(k, 1, 5, s) == CorePotts.draw(k, 2, 5, s)
false
```

See also [`uniform`](@ref), [`normal`](@ref), [`bounded_normal`](@ref).
"""
@inline function draw(
        key::RNGKey, mcs::Integer, entity::Integer, stream::UInt32,
        local_index::Integer = 0
    )
    # wrapping conversions: in range by construction, and no exception branch in kernels
    # (X1)
    e = entity % UInt64
    hi = (e >> 32) % UInt32
    # the branch keeps the key loop-invariant on the common `hi = 0` path, so its schedule
    # is hoisted (the unconditional xor cost ~15% per draw on the CPU); uniform on GPUs
    k0 = hi == 0 ? key.k0 : key.k0 ⊻ (hi * PHILOX_W1)
    return philox4x32(mcs % UInt32, e % UInt32, stream, local_index % UInt32, k0, key.k1)
end

"""
    uniform(T, x::UInt32) -> T

Map a random word `x` to a uniform value on the open interval `(0, 1)`.

The values are grid midpoints, so the result is never 0 or 1. `Float32` uses the top 23
bits of `x` (`(x >> 9 + 0.5) * 2⁻²³`), and `Float64` uses all 32 bits
(`(x + 0.5) * 2⁻³²`). Any other float type `T` converts the `Float64` value.

# Arguments
- `T::Type{<:AbstractFloat}`: the result type.
- `x::UInt32`: one word of a [`draw`](@ref).

# Returns
- `T`: a value strictly between 0 and 1.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.uniform(Float64, 0x00000000)
1.1641532182693481e-10

julia> CorePotts.uniform(Float32, 0xffffffff)
0.99999994f0
```

See also [`draw`](@ref), [`normal`](@ref).
"""
@inline uniform(::Type{Float32}, x::UInt32) = (Float32(x >> 9) + 0.5f0) * Float32(0x1p-23)
@inline uniform(::Type{Float64}, x::UInt32) = (Float64(x) + 0.5) * 0x1p-32
@inline uniform(::Type{T}, x::UInt32) where {T <: AbstractFloat} = T(uniform(Float64, x))

"""Lemire multiply-shift draw on `0:n-1` (bias ≤ n / 2³²)."""
@inline bounded(x::UInt32, n::Integer) = Int((UInt64(x) * UInt64(n)) >> 32)

"""
Multiply-shift draw on `0:n-1` from two words, `hi` and `lo` (bias ≤ n / 2⁶⁴; host only).
"""
@inline function bounded64(hi::UInt32, lo::UInt32, n::Integer)
    return Int((UInt128((UInt64(hi) << 32) | lo) * UInt128(n)) >> 64)
end

# Site picks of the sequential sweeps over `n` sites (D-247): one word up to 2^24 mobile
# sites, where the bias n / 2³² is at most 2⁻⁸ and every existing run keeps its draws; two
# words above (bias ≤ n / 2⁶⁴). The regime is part of the sweep context's type: the caller
# adds `var"#pick" = TwoWordPick()` above the threshold, and a context without it compiles
# to the one-word sweep exactly (a runtime branch in the loop slowed the CPU sweeps). The
# key is not an identifier, so no relation (whose names share the context) can take or
# shadow it.
const PICK_ONE_WORD_MAX = 2^24
struct TwoWordPick end
# tests: the two-word pick on a small lattice (read by the caller once per MCS)
const _FORCE_TWO_WORD_PICK = Ref(false)
const PICK_KEY = Symbol("#pick")
_with_two_word_pick(ctx::NamedTuple) = merge(ctx, NamedTuple{(PICK_KEY,)}((TwoWordPick(),)))
_two_word_pick(n) = _FORCE_TWO_WORD_PICK[] || n > PICK_ONE_WORD_MAX
# resolved at compile time; dispatch on the folded `Val` leaves no branch (`get` left an
# empty block)
@inline function _pick_regime(ctx::NamedTuple{names}) where {names}
    return _pick_regime(
        ctx, Val(
            PICK_KEY in
                names
        )
    )
end
@inline _pick_regime(::NamedTuple, ::Val{false}) = nothing
@inline _pick_regime(ctx::NamedTuple, ::Val{true}) = getfield(ctx, PICK_KEY)
# dispatch, not a ternary, and the one-word method is `bounded`'s body rather than a call to
# it, so it inlines to exactly the old IR (each wrapper layer leaves an empty block)
@inline function site_pick(::Nothing, hi::UInt32, lo::UInt32, n::Integer)
    return Int(
        (
            UInt64(hi) *
                UInt64(n)
        ) >> 32
    )
end
@inline site_pick(::TwoWordPick, hi::UInt32, lo::UInt32, n::Integer) = bounded64(hi, lo, n)

"""
    cell_entity(id, generation) -> UInt64

Return the [`draw`](@ref) entity of a cell: `(id << 8) | (generation & 0xff)`.

The value is 64-bit, so cell numbers at or above 2²⁴ do not wrap onto smaller ones. Only the
low 8 bits of `generation` are used.

# Arguments
- `id::Integer`: the cell number.
- `generation::Integer`: the cell's generation.

# Returns
- `UInt64`: the entity for [`draw`](@ref).

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.cell_entity(3, 1)
0x0000000000000301
```
"""
@inline function cell_entity(id::Integer, generation::Integer)
    return ((id % UInt64) << 8) | ((generation % UInt64) & 0xff)
end

"""
    normal(T, a::UInt32, b::UInt32) -> T
    normal(T, words::NTuple{4, UInt32}) -> T

Return a standard normal value of float type `T` made from two random words.

The method is the cosine branch of Box–Muller: `√(−2 log u₁) cos(2π u₂)`, with
`u = uniform(T, ·)` on the open interval, so the value is finite. The smallest `u₁` cuts
the tails: `|z| ≤ 5.77` in `Float32` (`u₁ ≥ 2⁻²⁴`, a tail mass of about 8·10⁻⁹) and
`|z| ≤ 6.76` in `Float64` (`u₁ ≥ 2⁻³³`). The tuple form uses `words[1]` and `words[2]` of a
[`draw`](@ref).

# Arguments
- `T::Type{<:AbstractFloat}`: the result type.
- `a::UInt32`, `b::UInt32`: two words of a [`draw`](@ref).
- `words::NTuple{4, UInt32}`: a [`draw`](@ref) result.

# Returns
- `T`: the normal value.

# Examples
```jldoctest
julia> using CorePotts

julia> w = CorePotts.draw(CorePotts.RNGKey(1), 0, 0, CorePotts.stream_id("x"));

julia> CorePotts.normal(Float64, w) == CorePotts.normal(Float64, w[1], w[2])
true
```

See also [`uniform`](@ref), [`bounded_normal`](@ref).
"""
@inline function normal(::Type{T}, a::UInt32, b::UInt32) where {T <: AbstractFloat}
    u1 = uniform(T, a)
    u2 = uniform(T, b)
    return sqrt(-2 * log(u1)) * cos(T(6.283185307179586) * u2)
end

"""Most attempts of a bounded normal draw (`bounded_normal`)."""
const MAX_DRAW_ATTEMPTS = 64
"""
Status bit: a bounded draw found no value above its bound in `MAX_DRAW_ATTEMPTS` attempts.
"""
const STATUS_DRAW_EXHAUSTED = UInt32(2)
"""Status bit: a bounded draw was given a negative SD `σ`."""
const STATUS_DRAW_NEGATIVE_SD = UInt32(4)
"""
Name of a model's optional status word in `st.model`, the `Symbol` `Symbol("#status")`.

The status word is a 1-element `UInt32` array. A model's generated code sets bits in it,
for example when a [`bounded_normal`](@ref) draw finds no value. The integrator reads it at
each host read point, and a nonzero word ends the run with `ReturnCode.Failure`.
"""
const MODEL_STATUS = Symbol("#status")

"""
    bounded_normal(T, key, mcs, entity, stream, μ, σ, lower, status) -> T

Return `μ + σ z`, with `z` standard normal, redrawn while the value is `≤ lower`.

Attempt `k = 0, 1, …` uses the draw at local index `k` of the address
`(mcs, entity, stream)`, for at most 64 attempts. The function never throws, so it runs
inside kernels. Instead it sets a bit in `status` and returns `NaN`:

- bit `2` when all 64 attempts were `≤ lower`;
- bit `4` when `σ < 0` (no draw is made).

# Arguments
- `T`: the result type.
- `key::RNGKey`, `mcs`, `entity`, `stream::UInt32`: the address, as for [`draw`](@ref).
- `μ`, `σ`: the mean and the standard deviation (`σ ≥ 0`).
- `lower`: the exclusive lower bound.
- `status`: a 1-element `UInt32` array that takes the error bit (atomically), or
  `nothing`.

# Returns
- `T`: a value `> lower`, or `NaN` on an error.

# Examples
```jldoctest
julia> using CorePotts

julia> k = CorePotts.RNGKey(1); s = CorePotts.stream_id("MyModel.size");

julia> CorePotts.bounded_normal(Float64, k, 0, 1, s, 10.0, 2.0, 5.0, nothing) > 5
true

julia> st = UInt32[0];

julia> isnan(CorePotts.bounded_normal(Float64, k, 0, 1, s, 1.0, -1.0, 0.0, st))
true

julia> st
1-element Vector{UInt32}:
 0x00000004
```

See also [`normal`](@ref), [`MODEL_STATUS`](@ref CorePotts.MODEL_STATUS).
"""
@inline function bounded_normal(
        ::Type{T}, key::RNGKey, mcs, entity, stream::UInt32, μ, σ, lower, status
    ) where {T}
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
# status has 1 entry
@inline _set_status!(status, bit) = (Atomix.@atomic status[1] |= bit; nothing)
"""
    bump!(cnt, j) -> nothing

Add one to entry `j` of the counter array `cnt`, atomically, on the host or a device.

Potts' generated code calls it for its diagnostic counters (`track = (:references,)`).
The caller passes an index in range.

# Arguments
- `cnt::AbstractArray`: the counter array.
- `j`: the entry to increment.

# Returns
- `nothing`.

See also [`atomic_add!`](@ref).
"""
@inline bump!(cnt, j) = (Atomix.@atomic cnt[j] += one(eltype(cnt)); nothing)
"""
    atomic_add!(a, j, v) -> nothing

Add `v`, converted to `eltype(a)`, to `a[j]` atomically.

An index outside `1:length(a)` is skipped: `0` (the medium) and stale indices write
nothing. Generated `@convert` transfers and writes use it.

# Arguments
- `a::AbstractVector`: the target array, on the host or a device.
- `j`: the entry.
- `v`: the amount to add.

# Returns
- `nothing`.

# Examples
```jldoctest
julia> using CorePotts

julia> a = zeros(3); CorePotts.atomic_add!(a, 2, 1.5); CorePotts.atomic_add!(a, 0, 9.0);

julia> a
3-element Vector{Float64}:
 0.0
 1.5
 0.0
```

See also [`bump!`](@ref).
"""
@inline function atomic_add!(a, j, v)
    # bound checked here
    ((0 < j) & (j <= length(a))) && (@inbounds Atomix.@atomic a[j] += convert(eltype(a), v))
    return nothing
end
# the model's status word at a host read point (`_check_status!`); 0 without one
function _model_status(stats, model::NamedTuple)
    return if haskey(model, MODEL_STATUS)
        _readback(stats, getfield(model, MODEL_STATUS))
    else
        UInt32(0)
    end
end
_model_status(stats, model) = UInt32(0)
@inline function normal(::Type{T}, w::NTuple{4, UInt32}) where {T <: AbstractFloat}
    return normal(
        T, w[1],
        w[2]
    )
end
