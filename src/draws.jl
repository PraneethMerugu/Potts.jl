# Random draws inside a model (D-150 G2): `randn()`, the bounded form `randn(μ, σ; lower)`,
# and the guard that turns any other RNG call in a model body into an error naming it (a
# Base RNG call would otherwise run once, at build time, and become a constant).
#
# A draw is addressed by (seed, MCS, cell or site, occurrence): the occurrence is the draw's
# number in the model (`_next_number!`), shared by `rand()` and `randn()`.

"""`random_normal(n)`: the `n`-th authored draw of a model, standard normal."""
random_normal(n) = error("`random_normal` is symbolic-only")
"""`random_normal_above(n, μ, σ, lower)`: the `n`-th authored draw, `μ + σ z` redrawn while `≤ lower`."""
random_normal_above(n, μ, σ, lower) = error("`random_normal_above` is symbolic-only")
Symbolics.@register_symbolic random_normal(n)
Symbolics.@register_symbolic random_normal_above(n, μ, σ, lower)

"""
`randn()` inside a model: a standard normal draw with `rand()`'s contract, fresh per MCS and
per cell (or site), from its own counter-based stream (a pure function of the seed, the MCS,
the cell or site and the draw's occurrence in the model, so it is the same on every algorithm,
backend and thread count). Available in updates, equations, division conditions and rules;
not in energies, drives or constraints.

`randn(μ, σ)` is `μ + σ * randn()`. `randn(μ, σ; lower)` redraws while the value is `≤ lower`
(a truncated normal, e.g. `randn(2.0, 0.4; lower = 0.0)` for a positive size threshold): each
attempt is a new draw of the same address, at most `CorePotts.MAX_DRAW_ATTEMPTS` (64); if
every attempt is `≤ lower` the value is NaN and the run's status word fails it
(`ReturnCode.Failure`). For a bound below `μ + 2σ` that never happens in practice (p⁶⁴).

Base's other forms (`randn(dims…)`, `randn(rng)`, `randn(T)`) are not model quantities; they
are errors when the model is built. Note that `randn(a, b)` is the mean and the SD here, not
dimensions.
"""
function _randn(args...; lower = nothing)
    isempty(args) && lower === nothing && return random_normal(Num(_next_number!()))
    length(args) == 2 || _rng_error(:randn, args, lower === nothing ? (;) : (; lower))
    μ, σ = args
    for (what, v) in (("μ", μ), ("σ", σ), ("lower", lower))
        (v === nothing || v isa Real || v isa Num) ||
            throw(ArgumentError("`randn(μ, σ; lower)`: `$what` must be a number or a model expression, got $(repr(v))"))
    end
    σ isa Real && !(σ isa Num) && σ < 0 && throw(ArgumentError("`randn(μ, σ$(lower === nothing ? "" : "; lower"))`: σ = $σ is negative"))
    lower === nothing && return μ + σ * random_normal(Num(_next_number!()))
    Threads.atomic_add!(_BOUNDED_BUILT, 1)
    return random_normal_above(Num(_next_number!()), μ, σ, lower)
end

"""`rand()` inside a model (`_rand()`, vocabulary.jl); any other form of `rand` is an error naming the call."""
_rand(args...) = _rng_error(:rand, args, (;))

# What a model's construction built (D-150 review F1): every contact fold and bounded draw
# bumps a counter, and the constructor records whether its own window saw any in the
# system's metadata, so models without them skip the walks that look for them at
# `mtkcompile` and `PottsProblem`. A concurrent build can only turn a `false` into `true`
# (a walk, never a miss); systems built without the macro carry no record and are walked.
const _FOLDS_BUILT = Threads.Atomic{Int}(0)
const _BOUNDED_BUILT = Threads.Atomic{Int}(0)
"""Metadata key: `(; folds, bounded)`, what the model constructor built."""
struct _BuiltFeatures end
_feature_counts() = (_FOLDS_BUILT[], _BOUNDED_BUILT[])
_built_metadata(c0) = Base.ImmutableDict(Base.ImmutableDict{DataType, Any}(), _BuiltFeatures => (; folds = _FOLDS_BUILT[] != c0[1],
                                                                                                bounded = _BOUNDED_BUILT[] != c0[2]))
"""Whether `sys` may contain feature `k` (`:folds`, `:bounded`): `false` only if its constructor built none."""
function _may_have(sys, k::Symbol)
    m = get(getfield(sys, :metadata), _BuiltFeatures, nothing)
    return m === nothing || getfield(m, k)::Bool
end

function _rng_error(name, args, kws)
    shown = join([map(repr, args)..., ("$k = $(repr(v))" for (k, v) in pairs(kws))...], ", ")
    throw(ArgumentError("`$name($shown)` is not available in a model: the model's random draws are `rand()` " *
                        "(uniform on (0, 1)), `randn()` and `randn(μ, σ; lower)`, each fresh per MCS and per " *
                        "cell or site. A Base RNG call would run once, when the model is built"))
end

# Random-number functions a model body may not call (Base and the Random stdlib): `rand`
# and `randn` are the model's own (`_rand`, `_randn`) unless qualified, the others are errors
const _RNG_NAMES = (:rand, :randn, :randexp, :rand!, :randn!, :randexp!, :randperm, :randperm!, :randcycle,
    :randcycle!, :shuffle, :shuffle!, :bitrand, :randstring, :randsubseq, :randsubseq!, :seed!)

"""
`_rng_call(name, args...; kws...)`: a call of an RNG function `name` written in a model body,
unqualified for the names the model does not bind (`randexp(…)`, `shuffle(…)`, …) or
qualified (`Base.rand(…)`, `Random.randn(…)`, …). `rand()`, `randn()` and `randn(μ, σ; lower)`
are the model's draws; anything else is an `ArgumentError` naming the call.
"""
function _rng_call(name::Symbol, args...; kws...)
    name === :rand && isempty(args) && isempty(kws) && return _rand()
    name === :randn && return _randn(args...; kws...)
    return _rng_error(name, args, NamedTuple(kws))
end

# The callee of a call expression, if it is an RNG function: `rand`, `Base.rand`,
# `Random.shuffle`, … (`nothing` otherwise). `rand` and `randn` unqualified are the model's own.
function _rng_callee(f)
    f isa Symbol && return f in _RNG_NAMES && !(f in (:rand, :randn)) ? f : nothing
    if f isa Expr && f.head === :. && length(f.args) == 2 && f.args[2] isa QuoteNode
        m, n = f.args[1], f.args[2].value
        (n isa Symbol && n in _RNG_NAMES) || return nothing
        (m === :Base || m === :Random || m == :(Random.Random)) && return n
    end
    return nothing
end

"""
The binding of `count` inside a model: `Base.count`, and the fold over a cell's contact pairs
`count(pred for _ in contacts)` / `count(pred for _ in contacts(rel))` (D-150 G1; the macro
routes generator folds to `_fold_iter`/`_fold_or_gather`, which recognise `contacts`).
"""
struct _Count end
(::_Count)(args...; kws...) = count(args...; kws...)
Base.nameof(::_Count) = :count
Base.show(io::IO, ::_Count) = print(io, "count")

# `randn()` (two words of the draw at local index 0) and the bounded form (`bounded_normal`,
# its status word in the model state), lowered like `rand()` (lower.jl)
function _lower_normal(op, args, env)
    haskey(env.bind, :__draw) ||
        error("`randn()` is only available in updates, equations, division conditions and rules (not in $(_MODE_NAMES[env.mode]))")
    key, mcs, entity = env.bind[:__draw]
    stream = CorePotts.stream_id("Potts.draw.$(SymbolicUtils.unwrap_const(_unwrap(args[1])))")
    op === random_normal && return :(CorePotts.normal($(env.T), CorePotts.draw($key, $mcs, $entity, $stream)))
    μ, σ, lo = map(a -> lower(a, env), args[2:4])
    return :(CorePotts.bounded_normal($(env.T), $key, $mcs, $entity, $stream, $μ, $σ, $lo,
        st.model.$(CorePotts.MODEL_STATUS)))
end
