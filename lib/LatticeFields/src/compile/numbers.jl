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
    lanetype(lane, V, lanes = :fixed)

The Julia value type a float storage lane holds under value type `V`. `lanes = :fixed` (raw
IR, the default): `juliatype(lane)`. `lanes = :state` (problems, P5 role model): the IR is
closed, so lanes are value classes; the state lanes `F32` and `F64` hold the problem's value
type `V` (Float32, Float64, BigFloat on the host), and only the explicitly narrow `F16`
(`lattice_storage`) stays Float16. Float64 IR constants and spacing bound a BigFloat
reference near 1e-16 relative in geometry.
"""
function lanetype(lane::Scalar, ::Type{V}, lanes::Symbol = :fixed) where {V}
    lanes == :state && lane != F16 && return V
    return juliatype(lane)
end

# a parameter widened for host derivation: at least Float64 (P5: derived in
# `promote_type(Float64, eltype(P))`, then rounded once to the compute type)
_wide(x::Real) = convert(promote_type(Float64, typeof(x)), x)
