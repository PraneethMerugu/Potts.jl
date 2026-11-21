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

# Arguments
- `T`: the target value type.
- `x`: the value to convert.

# Returns
- `convert(T, x)` for a plain value. For a ForwardDiff `Dual` (with the extension loaded),
  a `Dual` with the same tag whose value and partials are of type `T`.

# Examples
```jldoctest
julia> using LatticeFields

julia> LatticeFields.Compile.lanecast(Float32, 0.5)
0.5f0
```
"""
@inline lanecast(::Type{T}, x) where {T} = convert(T, x)

"""
    powi(x, n::Int)

`x^n` for an integer `n`, by squaring and multiplying, with one reciprocal for `n < 0`. No
library `pow` is called on any backend (Base's `Float32 ^ Int` and the ROCm device
libraries' `pow` compute in Float64), so a float or Dual `x` keeps its type. An integer `x`
with `n < 0` gives `inv` of an integer; convert it to the compute type first. The relative
error grows to about `(|n| - 1) * eps` against a correctly rounded power. A leaf primitive
of emitted bodies and of Potts' generated code.

# Arguments
- `x`: the base, any number type with `*`, `one` and (for `n < 0`) `inv`.
- `n`: the integer exponent.

# Returns
- `x^n`, of the type of `x` for `n ≥ 0`, and of the type of `inv(x)` for `n < 0`.

# Examples
```jldoctest
julia> using LatticeFields

julia> LatticeFields.Compile.powi(2.0f0, 3), LatticeFields.Compile.powi(2.0, -2)
(8.0f0, 0.25)
```
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

The most frequent of the values `vals[i]` whose `oks[i]` holds (a RESTRICT's `:plurality`
over a coarse site's children); a tie goes to the smallest nonzero value, and 0 wins only
when no nonzero value ties. A leaf primitive of emitted bodies.
"""
@inline function plurality(
        vals::Tuple{T, Vararg{T}}, oks::Tuple{
            Bool, Vararg{Bool},
        }
    ) where {T}
    M = length(vals)
    # (the emitter passes one flag per value)
    length(oks) == M || return zero(T)
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

# Arguments
- `T`: a number type.

# Returns
- The value type of `T`.

# Examples
```jldoctest
julia> using LatticeFields

julia> LatticeFields.Compile.value_type(Float32)
Float32
```

See also [`withvaltype`](@ref), [`npartials`](@ref).
"""
value_type(::Type{T}) where {T} = T

"""
    primal(x)

The value of `x` with derivative parts removed: `x` for a plain number (extension for
Duals). Values that only drive a policy (substep counts, face checks, float → integer casts)
use it.

# Arguments
- `x`: a number.

# Returns
- `x` itself for a plain number; the primal value of a ForwardDiff `Dual` with the
  extension loaded.
"""
@inline primal(x) = x

"""
    npartials(T) -> Int

The number of derivative parts of number type `T`: 0 for a plain number, `N` for
`Dual{tag, V, N}` (extension). With [`dvalue`](@ref), [`dpartial`](@ref),
[`dsetpartial`](@ref) and [`dreplace`](@ref) it is what the implicit solve's tangent steps
read and write: one level of derivative parts, each a value of the value type.

# Arguments
- `T`: a number type.

# Returns
- The number of partials of one derivative level, as an `Int`.
"""
npartials(::Type) = 0
"""
    dvalue(x)

The value of `x` at one level of derivative parts (extension for Duals).

# Arguments
- `x`: a number.

# Returns
- `x` for a plain number; the value of a `Dual` (one level unwrapped).

See also [`dpartial`](@ref), [`dsetpartial`](@ref), [`dreplace`](@ref), [`npartials`](@ref).
"""
@inline dvalue(x) = x
"""
    dpartial(x, j)

The `j`-th derivative part of `x` at one level (extension for Duals).

# Arguments
- `x`: a number.
- `j`: the index of the part, `1 ≤ j ≤ npartials(typeof(x))`.

# Returns
- `zero(x)` for a plain number; the `j`-th partial of a `Dual`.

See also [`dvalue`](@ref), [`dsetpartial`](@ref).
"""
@inline dpartial(x, j) = zero(x)
"""
    dsetpartial(x, j, v)

`x` with its `j`-th derivative part set to `v` (extension for Duals).

# Arguments
- `x`: a number.
- `j`: the index of the part.
- `v`: the new value of the part.

# Returns
- `x` unchanged for a plain number; a `Dual` with the same value and the `j`-th partial
  replaced.

See also [`dpartial`](@ref), [`dreplace`](@ref).
"""
@inline dsetpartial(x, j, v) = x
"""
    dreplace(x, v)

`x` with its value replaced by `v` and its derivative parts kept (extension for Duals).

# Arguments
- `x`: a number.
- `v`: the new value.

# Returns
- `oftype(x, v)` for a plain number; a `Dual` with value `v` and the partials of `x`.

See also [`dvalue`](@ref), [`dsetpartial`](@ref).
"""
@inline dreplace(x, v) = oftype(x, v)

"""
    withvaltype(E, V)

Element type `E` with its value type replaced by `V`: `V` for a plain `E`,
`Dual{tag, V, N}` for `E = Dual{tag, W, N}` (extension).

# Arguments
- `E`: an element type.
- `V`: the new value type.

# Returns
- The element type `E` with value type `V`.

# Examples
```jldoctest
julia> using LatticeFields

julia> LatticeFields.Compile.withvaltype(Float32, Float64)
Float64
```

See also [`value_type`](@ref).
"""
withvaltype(::Type{E}, ::Type{V}) where {E, V} = V

"""
    promote_dual(E, P)

The compute element type of state element type `E` with values of type `P` (parameters,
time): `E` unless `P` carries derivative parts, then `E` promoted with `P` at `E`'s value
type (extension). A plain `P` never changes `E` (a Float32 problem with Float64 parameters
stays Float32); a Dual `P` does.

# Arguments
- `E`: the state element type.
- `P`: the element type of the parameters or of time.

# Returns
- The compute element type.

# Examples
```jldoctest
julia> using LatticeFields

julia> LatticeFields.Compile.promote_dual(Float32, Float64)
Float32
```
"""
promote_dual(::Type{E}, ::Type{P}) where {E, P} = E

"""
    lanetype(lane, V, lanes = :fixed, fixed = false)

The Julia value type a float storage lane holds under value type `V`. `lanes = :fixed` (raw
IR, the default): `juliatype(lane)`. `lanes = :state` (problems): the IR is
closed, so lanes are value classes; the state lanes `F32` and `F64` hold the problem's value
type `V` (Float32, Float64, BigFloat on the host), and only the explicitly narrow `F16`
(`lattice_storage`) stays Float16. Float64 IR constants and spacing bound a BigFloat
reference near 1e-16 relative in geometry. `fixed = true` (a field with a declared storage,
`lattice_storage`): the lane holds its own type under `:state` too.

# Arguments
- `lane`: the storage lane, a `LatticeFields.IR.Scalar` (`F16`, `F32`, `F64`, ...).
- `V`: the value type of the problem.
- `lanes = :fixed`: `:fixed` or `:state`.
- `fixed = false`: whether the field declared its storage type.

# Returns
- `V` when `lanes == :state`, `fixed` is false and `lane != F16`; otherwise
  `juliatype(lane)`.

# Examples
```jldoctest
julia> using LatticeFields

julia> using LatticeFields.IR: F32

julia> LatticeFields.Compile.lanetype(F32, Float64)
Float32

julia> LatticeFields.Compile.lanetype(F32, Float64, :state)
Float64
```
"""
function lanetype(
        lane::Scalar, ::Type{V}, lanes::Symbol = :fixed,
        fixed::Bool = false
    ) where {V}
    lanes == :state && !fixed && lane != F16 && return V
    return juliatype(lane)
end

# a parameter widened for host derivation: at least Float64 (P5: derived in
# `promote_type(Float64, eltype(P))`, then rounded once to the compute type)
_wide(x::Real) = convert(promote_type(Float64, typeof(x)), x)
