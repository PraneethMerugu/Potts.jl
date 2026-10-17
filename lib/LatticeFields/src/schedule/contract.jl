# The contract between Schedule and Exec (v3 §4.4). Schedule builds descriptions only;
# `Problems.bind` turns a `LaunchSpec` into an `Exec.Launch` (linear: the guarded wrapper
# with `n = G.n`; Cartesian: the Cartesian wrapper), and nothing in Schedule depends on Exec.
# Exec passes the site `s` (or `x`) as `Int`; the body converts it to its index type `I`.
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
# 3. Parameters. `P = derive_function(spec.kernel)(Praw, c, t)`: `Praw::NTuple{nparams}` of
#    any `Real` eltype on the host, `c` a value of the compute element type, `t` the time;
#    `P::NTuple{NP, typeof(c)}` reaches the device (no Float64 on Metal), with
#    `NP = nparams + length(spec.kernel.derived)` (the hoisted parameters follow the raw ones;
#    a kernel with `timed` hoisted values is derived again at each launch).
# 4. Geometry `G`, any isbits object with fields
#      n::I                          sites of the launch space (`spec.ndrange`)
#      dims::NTuple{L,NTuple{N,I32}} per level in `spec.kernel.levels` order
#      rt::NTuple{R,T}               launch-varying values (`RUNTIME` slots: t, dt, parity, …)
# After the step's launches, the host swaps the slots of `plan.swaps` (no copy, no wait).
# 5. Workgroup launches (`workgroup.jl`). A kernel with reductions has the workgroup form
#    `body(ph, g, t, lds, S, P, G)`: `reduction_blocks(n)` workgroups of `WG = 256` items
#    (`spec.ndrange = (256·blocks,)`), `REDUCE_PHASES = 9` phases with a barrier after each,
#    `reduce_lds(spec.kernel)` elements of workgroup memory of the lane type. Phase 1: item
#    `t` runs site `256(g − 1) + t` (coalesced); phases 2–9: the halving tree in workgroup
#    memory (fixed order); item 1 writes `target[g]` (tables of at least `blocks` entries,
#    combined by a finishing pass). Exec runs every phase for every item (uniform barriers);
#    `Schedule.host_workgroups!` is the host form, `Schedule.workgroups!` the KA device
#    wrapper. The solvers' finishing pass, bottom and Gershgorin pass use the same form.
#    Gated kernels (`Kernel.gate`) read their flag from a table; Exec may skip a gated
#    block but must keep the pass-through.
#
# Conventions the front end (C6) and the solvers (C7b) build on:
# - Coarse levels. Each coarsening halves every axis with floor: `nc = n ÷ 2` (at least 1).
#   Fine sites pair up; on an odd axis the last aggregate takes width 3 at the high end
#   (P4-mg42). A fine `x` maps to coarse `min((x − 1) ÷ 2 + 1, nc)`; a coarse `x` has its
#   children at `2(x − 1) + 1 + o`, `o ∈ 0:1` (also `o = 2` at the last site of an odd axis).
#   Access offsets are in the finer frame: a level +1 access at offset `o` reads the parent of
#   the fine site `x + o` (wrapped or clamped first). An axis of size 1 is never coarsened;
#   a level that would coarsen it is refused. `Level.widths` is refused; the widths follow
#   from this rule (level-ℓ width 2^ℓ, the last cell `n₀ − (n_ℓ − 1)·2^ℓ`).
# - Boundary coefficients are in lattice units. A `FaceRule` `α c + β ∂c/∂n = g` takes
#   `β` already divided by the spacing h (LatticePDE pre-scales it; the IR never reads
#   `Program.spacing`). Flux ghost: `c + g/β`; Robin: `(g − (α/2 − β) c) / (α/2 + β)`.
#   α = β = 0 is refused.

# 6. Number types. `supports(exec, S)`: can the executor's device run arithmetic and hold
#    arrays of number type `S`? An executor declares what it supports by adding methods;
#    the default is conservative: Float32 only (Metal has no Float64). Callers ask only when
#    a choice depends on the answer (the solvers' `solver_T = :auto`, an explicit type).
"""
    supports(exec, ::Type{S})

Can executor `exec` run number type `S` on its device? Default: `S === Float32` only; an
executor adds methods for the types it supports (contract item 6).
"""
supports(exec, ::Type{S}) where {S} = S === Float32
