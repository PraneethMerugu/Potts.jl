# Number types (P5 role model). Bodies bake only a *value type* `V` (Float32, Float64,
# BigFloat); the arrays and the parameter tuple carry the element type, which may wrap `V`
# (a ForwardDiff `Dual{tag, V, N}`). Every conversion an emitted body makes goes through
# `lanecast`, so the same body text runs on plain and Dual values. The ForwardDiff methods
# live in the package extension `LatticeFieldsForwardDiffExt`.

"""
    lanecast(T, x)

`x` converted to value type `T` (a storage lane or the compute type). A plain `Real` becomes
`T(x)`; a Dual keeps its tag and partials, each converted to `T` (the extension). A leaf
primitive of emitted bodies.
"""
@inline lanecast(::Type{T}, x) where {T} = convert(T, x)

"""
    powi(x, n::Int)

`x^n` for an integer `n`, by squaring and multiplying, with one reciprocal for `n < 0`. No
library `pow` is called on any backend (Base's `Float32 ^ Int` and the ROCm device libraries'
`pow` compute in Float64), so a float or Dual `x` keeps its type. An integer `x` with `n < 0`
gives `inv` of an integer; convert it to the compute type first. The relative error grows
to about `(|n| - 1) * eps` against a correctly rounded power. A leaf primitive of emitted
bodies and of Potts' generated code.
"""
@inline function powi(x, n::Int)
    m, r, b = abs(n), one(x), x
    while m > 0
        isodd(m) && (r *= b)
        m >>= 1
        m > 0 && (b *= b)
    end
    return n < 0 ? inv(r) : r
end

"""
    plurality(vals, oks)

The most frequent of the values `vals[i]` whose `oks[i]` holds (a RESTRICT's `:plurality` over
a coarse site's children); a tie goes to the smallest nonzero value, and 0 wins only when no
nonzero value ties. A leaf primitive of emitted bodies.
"""
@inline function plurality(vals::Tuple{T, Vararg{T}}, oks::Tuple{Bool, Vararg{Bool}}) where {T}
    M = length(vals)
    length(oks) == M || return zero(T)                  # (the emitter passes one flag per value)
    best, bc = zero(T), 0
    for j in 1:M
        # (@inbounds: `i` and `j` run over 1:M, the length of both tuples)
        @inbounds oks[j] || continue
        v = @inbounds vals[j]
        n = 0
        for i in 1:M
            n += @inbounds(oks[i] & (vals[i] == v))
        end
        if n > bc || (n == bc && v != zero(T) && (best == zero(T) || v < best))
            best, bc = v, n
        end
    end
    return best
end

"""
    value_type(T)

The value type of number type `T`: `T` itself for a plain number, `V` for `Dual{tag, V, N}`
(recursively, extension).
"""
value_type(::Type{T}) where {T} = T

"""
    primal(x)

The value of `x` with derivative parts removed: `x` for a plain number (extension for Duals).
Values that only drive a policy (substep counts, face checks, float → integer casts) use it.
"""
@inline primal(x) = x

"""
    npartials(T) -> Int

The derivative parts of number type `T`: 0 for a plain number, `N` for `Dual{tag, V, N}`
(extension). With [`dvalue`](@ref), [`dpartial`](@ref), [`dsetpartial`](@ref) and
[`dreplace`](@ref) it is what the implicit solve's tangent steps read and write (F3-21a): one
level of derivative parts, each a value of the value type.
"""
npartials(::Type) = 0
"""
    dvalue(x), dpartial(x, j), dsetpartial(x, j, v), dreplace(x, v)

One level of derivative parts of `x` (extension for Duals): its value, its `j`-th part, `x`
with its `j`-th part set to `v`, and `x` with its value replaced by `v` (its parts kept).
"""
@inline dvalue(x) = x
@inline dpartial(x, j) = zero(x)
@inline dsetpartial(x, j, v) = x
@inline dreplace(x, v) = oftype(x, v)

"""
    withvaltype(E, V)

Element type `E` with its value type replaced by `V`: `V` for a plain `E`,
`Dual{tag, V, N}` for `E = Dual{tag, W, N}` (extension).
"""
withvaltype(::Type{E}, ::Type{V}) where {E, V} = V

"""
    promote_dual(E, P)

The compute element type of state element type `E` with values of type `P` (parameters,
time): `E` unless `P` carries derivative parts, then `E` promoted with `P` at `E`'s value
type (extension). A plain `P` never changes `E` (a Float32 problem with Float64 parameters
stays Float32); a Dual `P` does.
"""
promote_dual(::Type{E}, ::Type{P}) where {E, P} = E

"""
    lanetype(lane, V, lanes = :fixed, fixed = false)

The Julia value type a float storage lane holds under value type `V`. `lanes = :fixed` (raw
IR, the default): `juliatype(lane)`. `lanes = :state` (problems, P5 role model): the IR is
closed, so lanes are value classes; the state lanes `F32` and `F64` hold the problem's value
type `V` (Float32, Float64, BigFloat on the host), and only the explicitly narrow `F16`
(`lattice_storage`) stays Float16. Float64 IR constants and spacing bound a BigFloat
reference near 1e-16 relative in geometry. `fixed = true` (a field with a declared storage,
`lattice_storage`, FE-17): the lane holds its own type under `:state` too.
"""
function lanetype(lane::Scalar, ::Type{V}, lanes::Symbol = :fixed, fixed::Bool = false) where {V}
    lanes == :state && !fixed && lane != F16 && return V
    return juliatype(lane)
end

# a parameter widened for host derivation: at least Float64 (P5: derived in
# `promote_type(Float64, eltype(P))`, then rounded once to the compute type)
_wide(x::Real) = convert(promote_type(Float64, typeof(x)), x)
