# The operator of an implicit group (F3 design §3.4): the symmetric Helmholtz part `J̃` of the
# rate Jacobian that a front end extracts from its linearity table, as plain data (no Symbolics:
# LatticePDE builds it in `lower_group`'s deferred `operator`, for both front ends). The
# implicit runtime (`implicit.jl`) turns it into one `Solvers.CellOperator` per row.

"""
    RowOperator

One row (state field `key`) of an implicit group's operator `J̃`, the part of the rate's
Jacobian that the linear solve sees:

- `faces[a]`: the face coefficient to `+e_a` (`K_f/h_a²` summed over the row's diffusion
  terms), as a sum of [`Coef`](@ref LatticeFields.IR.Coef)s (numbers, or numbers times
  parameter slots), when `field` is false;
- `jloc`: the local Jacobian (the row's linear local terms, `−k` for a decay `−k c`) as a sum
  of `Coef`s, when `field` is false;
- `field`: the operator varies by site (a face coefficient that reads the coordinates or an
  input, a local coefficient that reads an input or a table at an input, a site multiplier,
  an irregular domain): the operator program's kernel `jac:<key>` writes, per site, the face
  coefficients `jac:<key>.w<a>`, the local Jacobian `jac:<key>.j`, the boundary diagonal of the
  face conditions `jac:<key>.d` (`K w d⁺` per boundary face, the Dirichlet `d = 2`), and with
  `scaled` the multiplier `jac:<key>.m`, with `domain` the domain indicator `jac:<key>.dom`;
- `scaled`: a site multiplier `m Δ(c)` (`SiteDiffusion`): the row is scaled by `1/m` (faces
  stay symmetric), and a row with `m = 0` is solved on its own, `δ = G/(1/h − J_loc)` (the
  two-stage solve, M3);
- `local_only`: the row has no diffusion: each site is solved on its own, `δ = G/(1/h − J_loc)`;
- `exact`: every term of the row is in `J̃` (one Newton step is the Backward Euler step of a
  linear rate), else `inexact` lists the terms left in the residual (a defect correction), in
  the user's words.
"""
struct RowOperator
    key::String
    faces::Vector{Vector{Coef}}
    jloc::Vector{Coef}
    field::Bool
    scaled::Bool
    domain::Bool
    local_only::Bool
    exact::Bool
    inexact::Vector{String}
end

"""
    OperatorSpec

The operator of an implicit group (F3 design §3.4): its rows ([`RowOperator`](@ref), in the
group's state order) and the operator program `jac` (the `jac:<key>` kernels of the rows whose
operator varies by site, before the semantic passes; `nothing` when every row is numeric). The
program's fields are keyed as the group's, so a runtime binds them to its store's arrays by key.
Built by a front end ([`operator_spec`](@ref)), once per group, only for implicit algorithms.
"""
struct OperatorSpec{N}
    rows::Vector{RowOperator}
    jac::Union{Nothing, Program{N}}
end

"""
    operator_spec(spec) -> OperatorSpec

The operator of group `spec` for its implicit algorithms, built by its front end once
(`spec.operator`, a builder: LatticePDE's `DeferredOperator`) at the first implicit use. A
group whose front end extracts none (`spec.operator === nothing`: a map group) is an
`ArgumentError`.
"""
function operator_spec(spec::GroupSpec)
    spec.operator === nothing && throw(ArgumentError(string("the fields ", join(("`$k`" for k in spec.state), ", "),
        " have no implicit operator (a map `Shift(t, 1)(m) ~ rhs` is stepped by `ExplicitMap()`)")))
    return build_operator(spec.operator, spec)
end
operator_spec(o::OperatorSpec) = o

"""
    build_operator(builder, spec) -> OperatorSpec

A front end's builder of the operator of group `spec` (LatticePDE defines it for its
`DeferredOperator`, caching the result).
"""
function build_operator end

# a sum of coefficients at the raw parameters `p` (primal values)
_coefsum(cs::Vector{Coef}, p) = sum((c.param == 0 ? c.value : c.value * Float64(primal(p[c.param])) for c in cs); init = 0.0)

"""
    growth(op, keys, p) -> Float64

The largest positive local derivative the operator `op` sees over the rows `keys` at raw
parameters `p` (`max(J_loc, 0)` of the numeric rows; a row whose local Jacobian varies by site
counts 0: its shift is clamped instead, F3 design §3.4 Positivity).
"""
function growth(op::OperatorSpec, keys, p)
    g = 0.0
    for r in op.rows
        r.key in keys && !r.field || continue
        g = max(g, _coefsum(r.jloc, p))
    end
    return g
end
