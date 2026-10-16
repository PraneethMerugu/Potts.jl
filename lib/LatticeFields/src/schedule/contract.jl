# The contract between Schedule and Exec (v3 §4.4). C5 builds descriptions only; Exec (C2)
# turns them into launches. The merge with Exec is mechanical: Exec implements the four
# items below for a `LaunchSpec`, and nothing else in this package depends on Exec.
#
# 1. Bodies. `body_function(spec.kernel)` is a drop_expr'd RuntimeGeneratedFunction,
#    content-addressed by `spec.kernel.hash` (equal bodies share one compile).
#      linear    (strategy :linear):    body(s, S, P, G)    s::I, 1-based linear site
#      Cartesian (strategy :cartesian): body(x, S, P, G)    x::NTuple{N,I}, 1-based
#    `spec.ndrange` is `(n,)` for linear bodies and the space's dims for Cartesian ones;
#    `spec.workgroup` is `(256,)`, `(64, 4)` or `(64, 2, 2)`. The linear wrapper guards with
#    `if s <= G.n` (KA 0.9 refuses `return` in a kernel). A Cartesian body guards every axis
#    itself (`x[d] <= dims[d]`) and derives `s` from `x`, so padded threads are no-ops.
#    `spec.static` marks a body launched at one ndrange (eligible for a static ndrange).
# 2. Arrays. `S` is a tuple of homogeneous lane tuples, `S[l][j]` the array bound to
#    `spec.bind[l][j] = (id, role)`: role `:cur` / `:next` select the current or next slot
#    of a two-buffer field (`:cur` only for a one-buffer field), `:table` a table array.
#    Lanes are `spec.kernel.lanes[l]`. Multi-component fields are one array of planes.
# 3. Parameters. `P = derive_function(spec.kernel)(Praw)`: `Praw::NTuple{nparams,Float64}`
#    on the host; `P::NTuple{NP, T}` reaches the device (no Float64 on Metal), with
#    `NP = nparams + length(spec.kernel.derived)` (the hoisted parameters follow the raw ones).
# 4. Geometry `G`, any isbits object with fields
#      n::I                          sites of the launch space (`spec.ndrange`)
#      dims::NTuple{L,NTuple{N,I32}} per level in `spec.kernel.levels` order
#      rt::NTuple{R,T}               launch-varying values (`RUNTIME` slots: t, dt, parity, …)
# After the step's launches, the host swaps the slots of `plan.swaps` (no copy, no wait).
#
# Conventions the front end (C6) and the solvers (C7b) build on:
# - Coarse levels. Each coarsening halves every axis with floor: `nc = n ÷ 2` (at least 1).
#   Fine sites pair up; on an odd axis the last aggregate takes width 3 at the high end
#   (P4-mg42). A fine `x` maps to coarse `min((x − 1) ÷ 2 + 1, nc)`; a coarse `x` has its
#   children at `2(x − 1) + 1 + o`, `o ∈ 0:1` (also `o = 2` at the last site of an odd axis).
#   `Level.widths` is refused; the widths follow from this rule.
# - Boundary coefficients are in lattice units. A `FaceRule` `α c + β ∂c/∂n = g` takes
#   `β` already divided by the spacing h (LatticePDE pre-scales it; the IR never reads
#   `Program.spacing`). Flux ghost: `c + g/β`; Robin: `(g − (α/2 − β) c) / (α/2 + β)`.
#   α = β = 0 is refused.
