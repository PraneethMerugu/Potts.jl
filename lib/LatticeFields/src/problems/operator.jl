# The operator of an implicit group: the symmetric Helmholtz part `J̃` of the
# rate Jacobian that a front end extracts from its linearity table, as plain data (no
# Symbolics: LatticePDE builds it in `lower_group`'s deferred `operator`, for both coupled
# and standalone routes). The implicit runtime (`implicit.jl`) turns it into one
# `Solvers.CellOperator` per row.

"""
    RowOperator(key, faces, jloc, field, scaled, domain, local_only, exact, inexact,
                iterate, switch, adv, cross, unseen, bounds, facemax, jmax, linear,
                crossfaces, msign, sitefaces)

One row (state field `key`) of an implicit group's operator `J̃`, the part of the rate's
Jacobian that the linear solve sees.

A front end builds it ([`operator_spec`](@ref)).

# Fields
- `key::String`: the state field of the row.
- `faces::Vector{Vector{Coef}}`: `faces[a]` is the face coefficient to `+e_a` (`K_f/h_a²`
  summed over the row's diffusion terms), as a sum of [`Coef`](@ref LatticeFields.IR.Coef)s
  (numbers, or numbers times parameter slots), when `field` is false.
- `jloc::Vector{Coef}`: the local Jacobian (the row's linear local terms, `−k` for a decay
  `−k c`) as a sum of `Coef`s, when `field` is false.
- `field::Bool`: the operator varies by site (a face coefficient that reads the coordinates
  or an input, a local coefficient that reads an input or a table at an input, a site
  multiplier, an irregular domain): the operator program's kernel `jac:<key>` writes, per
  site, the face coefficients `jac:<key>.w<a>`, the local Jacobian `jac:<key>.j`, the
  boundary diagonal of the face conditions `jac:<key>.d` (`K w d⁺` per boundary face, the
  Dirichlet `d = 2`), and with `scaled` the multiplier `jac:<key>.m`, with `domain` the
  domain indicator `jac:<key>.dom`.
- `domain::Bool`: the row has an irregular domain, whose indicator the `jac:` kernel writes.
- `scaled::Bool`: a site multiplier `m laplacian(c)` (`SiteDiffusion`): the row is scaled by
  `1/m` (faces stay symmetric), and a row with `m = 0` is solved on its own,
  `δ = G/(1/h − J_loc)` (the two-stage solve).
- `local_only::Bool`: the row has no diffusion: each site is solved on its own,
  `δ = G/(1/h − J_loc)`.
- `exact::Bool`: every term of the row is in `J̃` (one Newton step is the Backward Euler
  step of a linear rate).
- `inexact::Vector{String}`: when not `exact`, the terms left in the residual (a defect
  correction), in the user's words.
- `iterate::Bool`: the local Jacobian reads the row's own field (a local nonlinear term
  `f(c)`, `−∂f/∂c` at the iterate, or a switch): the `jac:` kernel runs at every Newton
  iteration.
- `switch::Bool`: the row has a switch term `a max(c − c_T, 0)` (`LaggedSwitch`): its
  Jacobian flips with the iterate, and a group with one takes 2 Newton iterations
  automatically.
- `adv::Vector{Any}`: the bound of the row's advection terms: entries whose absolute values
  sum to the upwind bound `Σ_a 2 max|u_a| / h_a`, each a `Coef` (a velocity of numbers and
  parameters) or `(; f, text)`, `f` a function of the parameters (a velocity that varies by
  site, bounded over the box by the interval evaluator; NaN when not finite, and the term
  `text` is then one no bound sees).
- `cross::Vector{Tuple{String, Coef, String}}`: the row's cross terms `a · o`
  (`CrossLinear`): the other field's key, `a` as a `Coef` (`NaN` when no number or parameter
  bounds it), the term's text.
- `unseen::Vector{String}`: the terms left out of `J̃` that no bound sees (a defect
  correction whose convergence only the device check decides), in the user's words.
- `bounds::Vector{Tuple{Any, String, Any}}`: the diffusion terms left out of a scaled row's
  `J̃` (another face coefficient), each `(bound, text, ratio)`: `bound` a function of the
  parameters (a [`ParamsTables`](@ref), the tables included) giving its Gershgorin bound (a
  bound that is not finite at the parameters makes the term unseen), and `ratio` its
  face-wise ratio θ to the kept term, `max|m K|` of the term over the smallest `m K` kept
  (NaN when the kept multiplier is not bounded below by a positive value, `nothing` when no
  interval bounds it): with `L_out ≼ θ L_kept` the correction contracts by θ at any step
  size, so when the row's θ sum is at most 1/2 the term counts in the Newton count only, not
  in the substeps.
- `facemax`: for a field row with diffusion, a function of the parameters giving the largest
  face coefficient per axis (`Σ max|m| max|K| / h_a²`, NaN when not finite), or `nothing`:
  it bounds the part of a Robin face with a negative diagonal left out of the operator.
- `jmax`: for a field row with local terms, a function of the parameters giving the largest
  value of its local Jacobian over the sites (the interval evaluator over the box; NaN when
  not finite), or `nothing`: the growth that the automatic substep count keeps out of the
  shift.
- `linear::Bool`: every term of the row is linear in the group's state (diffusion, linear
  local, advection, cross-linear terms and sources: a coupled solve's directional difference
  of the residual is then exact at any step, and one Newton step is the solve).
- `crossfaces::Vector{Tuple{String, Vector{Vector{Coef}}}}`: the row's cross diffusion terms
  `D laplacian(o)` with a numeric coefficient, each the other field's key and its faces per
  axis `D/h_a²` as `Coef`s (the coupled steady system's modes).
- `msign::Vector{Tuple{Any, String, String}}`: the row's diffusion multipliers that read the
  coordinates, each `(f, mtext, text)`: `f` a function of the parameters giving the
  multiplier's smallest value over the site centers (the interval evaluator; NaN when it has
  none), `mtext` the multiplier and `text` the term in the user's words. Where one may be
  negative the scaled row drops the diffusion (anti-diffusion), so the operator is not exact
  at those parameters: checked at bind and at every parameter write.
- `sitefaces::Vector{Tuple{Int, Int, Any}}`: the row's Robin faces whose α or β varies by
  site or in time, each `(axis, k, f)` (`k` 1 low, 2 high): `f` a function of the parameters
  giving the smallest and largest ghost diagonal `d = α/(α/2 + β)` over the face's sites at
  any time (NaN when no interval bounds it, or `α/2 + β` may vanish). A negative part stays
  out of the operator per site (the row is a field row), so the operator is exact only where
  `d ≥ 0` at every site.
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
    iterate::Bool
    switch::Bool
    adv::Vector{Any}
    cross::Vector{Tuple{String, Coef, String}}
    unseen::Vector{String}
    bounds::Vector{Tuple{Any, String, Any}}
    facemax::Any
    jmax::Any
    linear::Bool
    crossfaces::Vector{Tuple{String, Vector{Vector{Coef}}}}
    msign::Vector{Tuple{Any, String, String}}
    sitefaces::Vector{Tuple{Int, Int, Any}}
end

"""
    OperatorSpec(rows, jac)

The operator of an implicit group.

The program's fields are keyed as the group's, so a runtime binds them to its store's
arrays by key. Built by a front end ([`operator_spec`](@ref)), once per group, only for
implicit algorithms.

# Fields
- `rows::Vector{RowOperator}`: the rows ([`RowOperator`](@ref)), in the group's state
  order.
- `jac::Union{Nothing, Program}`: the operator program, the `jac:<key>` kernels of the rows
  whose operator varies by site, before the semantic passes; `nothing` when every row is
  numeric.
"""
struct OperatorSpec{N}
    rows::Vector{RowOperator}
    jac::Union{Nothing, Program{N}}
end

"""
    operator_spec(spec) -> OperatorSpec

The operator of group `spec` for its implicit algorithms.

Its front end builds it once (`spec.operator`, a builder: LatticePDE's `DeferredOperator`)
at the first implicit use. A group whose front end extracts none
(`spec.operator === nothing`: a map group) is an `ArgumentError`.

# Arguments
- `spec`: the [`GroupSpec`](@ref) of the group. An `OperatorSpec` is returned as it is.

# Returns
- The group's [`OperatorSpec`](@ref).
"""
function operator_spec(spec::GroupSpec)
    spec.operator === nothing && throw(
        ArgumentError(
            string(
                "the fields ", join(("`$k`" for k in spec.state), ", "),
                " have no implicit operator (a map `Shift(t, 1)(m) ~ rhs` is stepped by \
                    `ExplicitMap()`)"
            )
        )
    )
    return build_operator(spec.operator, spec)
end
operator_spec(o::OperatorSpec) = o

"""
    build_operator(builder, spec) -> OperatorSpec

A front end's builder of the operator of group `spec`.

LatticePDE defines it for its `DeferredOperator`, caching the result.

# Arguments
- `builder`: the front end's builder, `spec.operator`.
- `spec`: the [`GroupSpec`](@ref) of the group.

# Returns
- The group's [`OperatorSpec`](@ref).
"""
function build_operator end

# a sum of coefficients at the raw parameters `p` (primal values)
function _coefsum(cs::Vector{Coef}, p)
    return sum(
        (c.param == 0 ? c.value : c.value * Float64(primal(p[c.param])) for c in cs);
        init = 0.0
    )
end
# an advection bound's entry at `p`: a `Coef`'s magnitude, or the value of a bound function
# `(; f, text)` (a velocity that varies by site; `text` the term in the user's words)
_advval(c::Coef, p) = abs(_coefsum(Coef[c], p))
_advval(c::NamedTuple, p) = Float64(c.f(p))

"""
    growth(op, keys, p) -> Float64

The largest positive local derivative the operator `op` sees over the rows `keys` at raw
parameters `p`.

It is `max(J_loc, 0)` of the numeric rows. A row whose local Jacobian varies by site takes
its interval bound over the sites, `jmax`; with none, or one that is not finite, it counts
0: its shift is clamped instead.

# Arguments
- `op::OperatorSpec`: the group's operator.
- `keys`: the state keys of the rows.
- `p`: the raw parameters.

# Returns
- The growth as a `Float64` (0 when no row grows).
"""
function growth(op::OperatorSpec, keys, p)
    g = 0.0
    for r in op.rows
        r.key in keys || continue
        if r.field
            r.jmax === nothing && continue
            v = Float64(r.jmax(p))
            isfinite(v) && (g = max(g, v))
        else
            g = max(g, _coefsum(r.jloc, p))
        end
    end
    return g
end

"""
    inexact_bounds(op, keys, cyclic, p) -> NamedTuple

The bounds of the terms outside the operator `op` of the rows `keys` at raw parameters `p`.

# Arguments
- `op::OperatorSpec`: the group's operator.
- `keys`: the state keys of the rows.
- `cyclic::Bool`: the rows read one another in a cycle.
- `p`: the raw parameters, or a [`ParamsTables`](@ref).

# Returns
- `(; ρ, κ, θ, unseen)`: the largest bound `ρ` (`ρ_adv`) of a row's advection terms and the
  diffusion terms out of a scaled row's operator (`bounds`, read with the tables when `p` is
  a [`ParamsTables`](@ref)) whose face-wise ratio sum to the kept term is unknown or above
  1/2, the largest such ratio sum `θ` of a row where it is at most 1/2 (those terms then
  contract by `θ` at any step size and add nothing to `ρ`), the largest in-group cross sum
  `κ` (`κ_in`) when the rows read one another in a cycle (`cyclic`), and the terms no bound
  sees (`unseen`, in the user's words; an unknown cross coefficient in a cycle counts).
"""
function inexact_bounds(op::OperatorSpec, keys, cyclic::Bool, p)
    ρ, κ, θ = 0.0, 0.0, 0.0
    unseen = String[]
    for r in op.rows
        r.key in keys || continue
        q = 0.0
        for c in r.adv
            v = _advval(c, p)
            # (a site-varying velocity whose bound is not finite here: no bound sees the
            # term)
            c isa Coef || isfinite(v) ? (q += v) : push!(unseen, c.text)
        end
        ts = [g === nothing ? NaN : Float64(g(p)) for (_, _, g) in r.bounds]
        tr = sum(ts; init = 0.0)
        if !isempty(ts) && isfinite(tr) && tr <= 0.5
            θ = max(θ, tr)
        else
            for (f, text, _) in r.bounds
                v = f(p)
                isfinite(v) ? (q += v) : push!(unseen, text)
            end
        end
        ρ = max(ρ, q)
        append!(unseen, r.unseen)
        cyclic || continue
        k = 0.0
        for (o, c, text) in r.cross
            o == "" || o in keys || continue
            v = isnan(c.value) ? NaN : abs(_coefsum(Coef[c], p))
            isfinite(v) ? (k += v) : push!(unseen, text)
        end
        κ = max(κ, k)
    end
    return (; ρ, κ, θ, unseen)
end
