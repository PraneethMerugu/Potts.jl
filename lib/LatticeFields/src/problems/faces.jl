# Robin faces with parameter coefficients: `α c + β ∂c/∂n = g` has the ghost value
# `(g − (α/2 − β) c) / (α/2 + β)`, undefined when `α/2 + β = 0`. The front end checks the
# defaults when it lowers; every later parameter set (remake, `setp`, an ODE call with new
# `p`) is checked again here.

"""
    FaceCheck(alpha::Coef, beta::Coef, field::String, axis::Int8, side::Int8)

One face rule's coefficients, for the parameter check: `(α, β, field key, axis, side)`.

# Fields
- `alpha`, `beta`: the coefficients `α` and `β` (`LatticeFields.IR.Coef`).
- `field`: the field key, for messages.
- `axis`, `side`: the face.
"""
struct FaceCheck
    alpha::Coef
    beta::Coef
    field::String
    axis::Int8
    side::Int8
end

"""
    face_checks(p) -> Vector{FaceCheck}

The face rules of `p` whose `α/2 + β` depends on a parameter (one value on the face: a face
whose α or β varies by site or in time is bounded by the front end's stability bound).

# Arguments
- `p`: the program.

# Returns
- One [`FaceCheck`](@ref) per such face rule.
"""
function face_checks(p::Program)
    return [
        FaceCheck(r.alpha, r.beta, p.fields[r.field].key, r.axis, r.side)
            for r in p.rules
            if r isa FaceRule && !sitecoefs(r) && (r.alpha.param != 0 || r.beta.param != 0)
    ]
end

# on the primal value: a face check is a policy, constant across a derivative
_coefval(c::Coef, P) = c.param == 0 ? c.value : c.value * Float64(primal(P[c.param]))

"""
    face_ratio(α, β) -> Float64

`(α/2 − β)/(α/2 + β)`: the ghost value's coefficient of the cell value (−1 no flux, 1
Dirichlet up to sign; a magnitude above 1 stiffens the boundary row).

# Arguments
- `α`, `β`: the face coefficients.

# Returns
- The ratio.

# Examples
```jldoctest
julia> using LatticeFields

julia> LatticeFields.Problems.face_ratio(0.0, 1.0)  # no flux
-1.0
```
"""
face_ratio(a::Real, b::Real) = (a / 2 - b) / (a / 2 + b)

"""
    degenerate_face(checks, P) -> Int

Index of the first face that is [`degenerate`](@ref) at parameters `P` (0 if none).
Allocates nothing.

# Arguments
- `checks`: the [`FaceCheck`](@ref)s of [`face_checks`](@ref).
- `P`: the parameter values; the check uses their primal values.

# Returns
- The index of the first degenerate face, or 0.
"""
function degenerate_face(checks::Vector{FaceCheck}, P)
    for (i, f) in enumerate(checks)
        degenerate(_coefval(f.alpha, P), _coefval(f.beta, P)) && return i
    end
    return 0
end

"""
    check_faces(checks, P)

Throw an `ArgumentError` naming the face if a Robin face is degenerate at parameters `P`.

# Arguments
- `checks`: the [`FaceCheck`](@ref)s of [`face_checks`](@ref).
- `P`: the parameter values.

# Returns
- `nothing` if no face is degenerate.
"""
function check_faces(checks::Vector{FaceCheck}, P)
    i = degenerate_face(checks, P)
    i == 0 && return nothing
    f = checks[i]
    throw(
        ArgumentError(
            string(
                "field `", f.field, "`: the face (axis ", f.axis, ", side ",
                f.side, ") has α/2 + β/h = 0 (to a relative ", FACE_RTOL,
                ") at these parameter ",
                "values, which leaves the ghost value undefined"
            )
        )
    )
end
