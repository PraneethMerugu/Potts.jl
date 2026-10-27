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
    valtype(T)

The value type of number type `T`: `T` itself for a plain number, `V` for `Dual{tag, V, N}`
(recursively, extension).
"""
valtype(::Type{T}) where {T} = T

"""
    primal(x)

The value of `x` with derivative parts removed: `x` for a plain number (extension for Duals).
Values that only drive a policy (substep counts, face checks, float → integer casts) use it.
"""
@inline primal(x) = x

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
