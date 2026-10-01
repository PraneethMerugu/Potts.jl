# Internals design — Potts monorepo rewrite

Companion to `MONOREPO_MIGRATION_PLAN.md`. This is the concrete design an implementer
follows. Versions: Julia ≥ 1.12, SciMLBase 3, ModelingToolkitBase 1, Symbolics 7,
KernelAbstractions 0.9, RuntimeGeneratedFunctions 0.5.

```
Potts (symbolic)          lib/CorePotts (numerical)
PottsSystem ──mtkcompile──▶ CompiledPottsSystem ──codegen──▶ CPMFunction ──▶ PottsProblem
                                                                  │
                                            init ──▶ PottsIntegrator ──▶ step!/solve!
                                                                  │
                                       fused MC kernels   +   generated KA phase kernels
                                       (propose/commit)       and host phases (D-033; fields,
                                                              updates, lifecycle, links)
```

(D-033/D-040: LocalMath is not used; the rest of this document's references to LocalMath
stages describe the original plan.)

## 1. lib/CorePotts — numerical layer

Depends on KernelAbstractions, Atomix, SciMLBase, SymbolicIndexingInterface,
RuntimeGeneratedFunctions (only to call generated functions), StaticArrays. **No
Symbolics.** Everything here takes plain Julia functions, exactly as `ODEProblem(f, …)`.

### 1.1 State layout (`CPMState`)

Structure-of-arrays, one struct, kernels receive it whole. Field *names* are structural
(they come from the model), but the types are flat: `NamedTuple` of device arrays.

```julia
struct CPMState{N, S, C, M, F, H, R}
    σ::AbstractArray{Int32, N}          # site → cell id, 0 = medium
    site::S      # NamedTuple{names}(Array{T,N}...)      per-site user state
    cell::C      # NamedTuple(kind::Vector{Int8}, generation::Vector{Int32},
                 #            volume::Vector{Int32}, surface, moments…, user cell state)
    model::M     # NamedTuple of 1-element device arrays (model-level scalars)
    fields::F    # NamedTuple of Array{T,N} (continuous fields)
    history::H   # NamedTuple of ring buffers (depth structural)
    rel::R       # CSR cell–cell relationship store (row_ptr, col, edge state)
end
```

- Cell ids are `1:capacity`, reused lowest-first from the MCS after retirement.
  `generation[c]` disambiguates reused ids. Capacity is preallocated (`max_cells`,
  default 2 × initial + 64). Exhaustion defers that MCS's creations (the cell stays
  eligible), counts them in `stats`, and the host grows capacity at the next sync point
  (types unchanged, so no recompilation).
- Generated code accesses state by name: `st.cell.volume[c]`, `st.site.activity[i]`.
  `getproperty` on a `NamedTuple` is resolved at compile time, so this is flat.

### 1.2 `CPMFunction` — the generated interface

```julia
struct CPMFunction{DH, CM, CN, PH, LC, OB, SYS}
    delta_H::DH        # (st, p, prop) -> T            energy + drives of one copy
    commit!::CM        # (st, p, prop) -> Nothing      accepted-copy affects + trackers
    constraint::CN     # (st, p, prop) -> Bool         hard constraints (connectivity…)
    phases::PH         # NamedTuple of LocalMath laws per phase (fields, sync updates)
    lifecycle::LC      # (trigger, plan, apply) generated functions, or nothing
    observed::OB       # SII observed function generator
    footprint::Footprint   # max read radius per domain → checkerboard stride
    trackers::NTuple{K, Symbol}   # which built-in cell trackers are maintained
    fingerprint::UInt64           # hash of generated code + structural params
    sys::SYS                      # symbolic system or nothing
end
```

- `prop` is an isbits `Proposal`: target index, source index, old cell, new cell, kinds,
  and the RNG counter base for this attempt.
- Built-in trackers (volume, surface, moments, site sums, site minima) are `@inline`
  primitives in CorePotts. **Codegen calls them from `commit!`**; CorePotts does not
  iterate a tuple of tracker objects.
- Every host function that only passes a generated function through is written
  `f::F ... where {F}` (Julia does not specialize otherwise, see FusedCPM).
- Generated functions are `RuntimeGeneratedFunction`s after `drop_expr`, so they are
  `isbits` and GPU-safe.

### 1.3 Parameters (`PottsParameters`)

Mirrors `MTKParameters`:

```julia
struct PottsParameters{T, NT, D, C}
    tunable::NTuple{NT, T}   # numeric, remake-able without recompilation
    discrete::D              # integers/bools that may change per run
    constant::C              # structural constants baked as literals (kept for SII)
end
```

`NT` is structural (fixed by the model). `remake(prob; p = …)` with the same model
produces the same type: zero compilation.

### 1.4 RNG — address-keyed Philox4x32-10

```
key     = philox_hash(tag, seed::UInt64, replica::UInt32, repeat::UInt32)   # 2×UInt32
counter = (mcs::UInt32,
           entity::UInt32,          # site index, or (cell id << 8 | generation & 0xff)
           stream::UInt32,          # 32-bit hash of a namespaced operation key
           local::UInt32)           # round(8) | substep(8) | draw(8) | retry(8)
```

- `stream` hashes a stable namespaced operation key, so editing one term never
  renumbers another. Collisions are rejected at compile time. Built-in streams
  (direction, acceptance, priority, color order, initialization) are reserved.
- Cell-addressed draws include the generation, so a reused id never replays a dead
  cell's randomness.
- Nothing depends on thread order or launch order. The same seed reproduces a run on
  a given backend; this is free, and not a published guarantee (D-029).
- Bounded integer draws use Lemire multiply-shift. Uniforms are grid midpoints in (0,1).
- The requested `tspan` must fit the 32-bit MCS field (checked at `init`).
- 4x32 rather than the old 4x64: 32-bit multiplies are native on every GPU.

### 1.5 Algorithms

**`SequentialCPM()`** — host loop; one MCS = N attempts with replacement over mutable
sites; random source direction from the proposal relation (out-of-domain directions
are counted null attempts); the fidelity reference.

**`CheckerboardCPM()`**: KernelAbstractions kernels, on CPU or GPU.

- **One MCS = N copy attempts**, where N counts mutable sites. Each MCS visits every
  mutable site once, in color order.
- **Footprint.** Compile-time analysis gives, per generated function:
  - `r_read`: the largest lattice distance read from the target;
  - `r_write`: the largest distance written by `commit!`/`@on_copy`;
  - the **claim set**: every cell whose quantities ΔH or `commit!` read. That is the
    old and new owner, plus linked partners, and neighbor cells whose quantities
    appear in contact terms.

  Stride per axis is `s = r_read + r_write + 1`. An indivisible periodic axis gets a
  remainder color class. Moore contact with no neighbor writes gives `s = 2`, i.e. 4
  colors in 2D.
- **Per color, 2 launches:**
  1. `propose!`: draw a direction, build `prop`, check `constraint`, compute
     `delta_H`, then Metropolis accept. If accepted, claim every **finite** cell in the
     claim set with `atomic max` of a unique priority (random high bits | canonical
     color-local index). Medium and obstacle domains are never claimed.
  2. `commit!`: if the proposal won every claim, run the generated `commit!`. Also
     clear the alternate claim buffer.

  Every kernel is an `@inline` body `body(i, args...)` under a thin `@kernel` wrapper: the
  phases, field steps and lifecycle share `_each_kernel!`; propose and commit keep their own
  wrappers with `@Const` read-only buffers (the generic wrapper cost 22% on Metal 576²,
  958 → 750 MCS/s). On the CPU backend, a
  launch that fits one workgroup (always single-threaded, and up to `CPU_GRAIN` sites
  otherwise) runs the body as a plain loop (`_launch`). A KernelAbstractions CPU launch
  allocates (argument tuple, boxed indices) even inline, and a warm MCS must allocate
  nothing (AUTONOMY §5, gated in the QA group).
- **Why this is correct.** Claims guarantee each claimed cell changes at most once
  per color, and same-color targets lie outside each other's read/write footprints.
  So ΔH is exact for every term the footprint analysis can bound. Models with terms
  that cannot be bounded (for example exact global connectivity) are **rejected at
  `init`** for checkerboard, and run on `SequentialCPM`.
- **Accept-then-claim** is intentional: it yields more accepted copies per color than
  claim-then-accept. It is an approximate parallel dynamic, documented and validated
  statistically against sequential.

### 1.6 The MCS schedule

```
for each MCS:
  phases.before_mcs          (LocalMath stages)
  for color in permuted colors (one permutation per MCS): propose! ; commit!
  phases.after_mcs           (synchronous site/cell updates, field steps, history push)
  lifecycle (device-gated)   (see 1.7)
  relationships rebuild      (only if relationships exist and something changed)
  save hook                  (only if this MCS is in saveat)
```

- **No host synchronization inside the loop.** Everything is enqueued; the integrator
  synchronizes only at save points, on `integrator.u` access, at the end, or when a
  callback needs host state.
- A device `status` word (UInt32 bitflags) records non-finite ΔH, invariant
  violations and deferred creations. It is read at every synchronization; a nonzero status ends the solve with
  `ReturnCode.Failure` and the MCS index. Phases validate before they write, so a
  failing MCS leaves the previous boundary state intact.

### 1.7 Lifecycle (division, removal, retirement, creation, transition)

Event-driven and validate-then-commit:

1. `lifecycle.trigger(st, p, c)` (generated) marks candidate cells; a device counter
   accumulates the count. All later kernels exit immediately when the count is zero, so
   the pipeline costs one tiny launch on quiet MCS and never synchronizes.
2. Plan: per candidate, the generated `plan` computes the event (partition plane,
   destination kind, state rule). Conflicts resolve by stable priority (same claim
   pattern as proposals). Capacity is checked here.
3. Apply: LocalMath `Collect`/`KeyedReduce` stages assign sites to daughters, allocate
   ids (`generation += 1`), apply state rules (split conservatively, copy, redraw,
   reset…), update relationships, then rebuild trackers of affected cells.

All lifecycle vocabulary from the survival matrix maps onto (trigger, plan, apply) plus
a small set of CorePotts primitives (partition by plane, place at stencil, retire id).

### 1.8 Relationships

Cell–cell edges live in a CSR store rebuilt at MCS boundaries when edges change.
Relationship-domain energies iterate `row_ptr[c]:row_ptr[c+1]` inside generated
`delta_H`. Create/remove/retune requests are collected with LocalMath `Collect` and
applied at the boundary.

### 1.9 Integrator, solution, checkpoint

- `PottsIntegrator <: SciMLBase.DEIntegrator`, modeled on JumpProcesses' `SSAIntegrator`:
  `init`, `step!`, `solve!`, `reinit!`, `terminate!`, `check_error`, `u`/`t`/`p`,
  `DiscreteCallback` support, `stats` (attempts, accepted, launches), `retcode`.
- `PottsSolution <: AbstractTimeseriesSolution`; `sol[x]`, `sol(t)`, SII through
  `f.sys`.
- **Mobility (frozen sites, D-081).** `ctx.mobility` is `AllMobile()` (no mask) or
  `MaskMobility(frozen, sites)`: the Bool mask (Checkerboard reads `is_mobile`) and, on
  the host only, the mobile sites as `Int32` (Sequential draws targets from them; on a
  device `sites === nothing`). The integrator keeps the mobile count on the host
  (`integ.nmobile`, the attempts of an MCS, read before the sweep).
  - Hooks on `f.sys`: `frozen_varies(sys)` (default `false`: a static mask, never
    recomputed) and `frozen_kinds(sys)` (a tuple of `Int32` kinds: the standard rule, or
    `nothing`: the custom rule `remake_frozen`). Potts: `!isempty(frozen_kinds)` and its
    frozen kinds.
  - `run_lifecycle!` returns `(launches, events)`; on an MCS with events (already
    synchronized, D-035) `step!` calls `refresh_frozen!`. `reinit!`, `set_state!` on
    `kind` and `u_modified!(integ, true)` call it too.
  - Standard rule: one `_frozen_body!` launch over the sites (frozen when outside the
    domain or the owner's kind is listed) that rewrites `frozen` in place and counts, with
    atomics in a 2-element device array, the change of the mobile count and the number of
    changed sites. The host reads those two integers (the only transfer); on the CPU the
    site list is rebuilt in place when a site changed.
  - Custom rule: a host copy of the state (`_snapshot` off the CPU), `frozen_sites`, copy
    of the mask to the device.
  - `frozen_sites(prob, u)` is the same rule on a host state, with the domain complement;
    MakiePotts uses it per saved frame.
- `checkpoint(integ)` = host copy of `CPMState` + `mcs` + RNG key + `fingerprint` + `p`.
  `init(prob, alg; checkpoint = ck)` continues the run (statistically correct; D-029).
  Fingerprint mismatch is an error.

### 1.10 Backends

`backend = CPU()` / `MetalBackend()` / `CUDABackend()` passed directly. `init` adapts
arrays with `Adapt`. Sequential requires `CPU()`. The scalar type defaults to `Float32`
on every backend; a model or solve may declare `Float64`, and a backend that cannot
provide it errors rather than narrowing (F9).

## 2. Potts — symbolic layer

Depends on ModelingToolkitBase, Symbolics, SymbolicIndexingInterface, DynamicQuantities,
CorePotts. Full ModelingToolkit, MethodOfLines and Unitful are extensions.

### 2.1 `PottsSystem <: ModelingToolkitBase.AbstractSystem`

> Planned (P6.0o, D-075 §0.1): today `PottsSystem` is a plain struct; the subtype and the MTK accessor contract land with P6.0o.

Fields: `name`, `lattice`, `kinds`, `unknowns` (with scope metadata: Site, Cell,
Medium, Model, Field, History), `ps`, `energies::Vector{EnergyTerm}`,
`drives`, `constraints`, `updates::Vector{PhaseUpdate}`, `lifecycle::Vector{LifecycleRule}`,
`relationships`, `observed`, `systems`, `native_components`, `statements` (authored form,
kept for display and diagnostics), `metadata` (source locations).

Composition: `compose`, `extend`, `flatten`, `@named`, namespacing — reused from
ModelingToolkitBase.

### 2.2 Statements expand into primitive terms

A statement is a value with `expand(stmt, ctx) -> (energies, updates, …)`; registering a
new statement means defining `expand` for a new type. Library statements:

| Statement | Expands to |
|---|---|
| `Volume(kind; target, strength)` | `EnergyTerm(CellDomain, ifelse(cell_kind == k, strength*(cell_volume - target)^2, 0))` |
| `Surface(kind; …)` | cell-domain term in `cell_surface` (adds the surface tracker) |
| `ContactEnergy(pairs)` | `EnergyTerm(ContactDomain, J[kind_a, kind_b])` |
| `Chemotaxis(field; μ)` | `Drive(μ * (field_value(target) - field_value(source)))` |
| `ActEnergy(...)` | `Drive` over `gather(site_value(act), Moore, source/target)` with geometric-mean fold |
| `Synchronous(name, x ~ f(Pre(x)); phase)` | `PhaseUpdate` |
| `AcceptedCopy(name, x ~ …; when)` | accepted-copy affect |
| `LifecycleProcess(Divide(...); trigger, when)` | `LifecycleRule` |
| `LocalConnectivity(kind)` | `Constraint` |
| `Observation(name, expr)` | `observed` equation |

`SourceLocation` is attached as symbolic metadata and surfaces in every diagnostic.

### 2.3 Symbolic primitives and their lowering

Registered with `@register_symbolic`; each has a codegen rule:

| Primitive | Lowers to |
|---|---|
| `cell_volume(c)`, `cell_surface(c)`, `cell_center(c)`, `cell_elongation(c)` | tracker reads; in ΔH, the *after* value is tracker + generated delta |
| `site_value(x, s)`, `cell_value(x, c)`, `model_value(x)`, `field_value(f, s)` | array reads |
| `history_value(x, lag)` | ring-buffer read |
| `gather(expr; over = relation, at = anchor, where = pred)` + `fold(...)` | an unrolled loop over the relation's literal offsets with the fold's accumulator |
| `field_gradient`, `laplacian` | literal stencils |
| `draw(dist)` | Philox call with a codegen-assigned stream |
| `linked(a, b)`, `edges(c)`, `edge_payload` | CSR reads |
| `kind_matches`, `site_owner`, `source_*`/`target_*` | `prop` fields |

### 2.4 `mtkcompile(sys)`

Symbolic in, symbolic out (`CompiledPottsSystem`, `iscomplete = true`):

1. flatten + namespace
2. expand statements
3. unit validation (DynamicQuantities), domain validation
4. **footprint analysis**: for each generated function, the max read radius from the
   target → `Footprint`; and the set of trackers referenced → `trackers`
5. ΔH derivation per domain (see 2.5), symbolic summation of all terms per domain
6. CSE (`Symbolics.cse`)
7. phase scheduling of updates; lifecycle rule ordering
8. structural parameters resolved to literals

### 2.5 ΔH derivation

For a proposal copying `new` into target site `t` (old owner `old`):

- **Cell domain** `E_cell(c)`: `ΔH = Σ_{c ∈ {old,new}} E(c | q + δq) − E(c | q)`, where `δq`
  are the tracker deltas of the copy (`δvolume = ∓1`, `δsurface` from the neighbor
  count, `δmoments` from the site coordinates). Substitution is symbolic; the result is
  straight-line code.
- **Site domain** `E_site(s)`: summed over the sites whose value changes: `t` itself and,
  for expressions that read neighbors, the neighborhood of `t`.
- **Contact domain** `J(a, b)`: loop over the literal offsets of the contact relation,
  `Σ_n [J(new, σ_n)·(σ_n≠new) − J(old, σ_n)·(σ_n≠old)]`.
- **Relationship domain**: loop over incident edges of `old` and `new`.
- **Drives** are added with their declared scale; **constraints** become `constraint`.

### 2.6 Code generation and the problem

```julia
PottsProblem(sys, op, tspan; seed, replica, repeat, eval_expression = false,
             eval_module = @__MODULE__, cse = true)
```

- `op` is one map: initial ownership (`LabelledCells`, placements), initial state
  values, parameter values — like MTK's operating point.
- Generation: `generate_delta_H`, `generate_commit`, `generate_constraint`,
  `generate_phase_laws` (LocalMath laws with RGF evaluators), `generate_lifecycle`,
  `generate_observed`. Each goes through `build_function(...; expression = Val(false),
  cse)` conventions and `drop_expr`. `expression = Val(true)` returns the code.
- Returns `CorePotts.PottsProblem` with `f.sys = sys`. SII: `symbolic_container(prob) =
  f.sys`; `getu`, `setp`, `observed`, `remake` work as in MTK.
- `EnsembleProblem(prob; prob_func)` changes only `seed`/`replica`, reusing `f`.
- **Solvers (D-075, P6.0c).** `field_solver`, `ode_solver` and `solvers` are construction
  keywords resolved in Potts (`src/solvers.jl`: `_resolve_solvers` → `SolverSpec`, one
  solver per integrated variable by name) and compiled at the one codegen point
  (`_problem_function` → `_phases`): each field's `FieldStep` takes its `ExplicitEuler`;
  the cell and model ODEs are grouped by solver (`_ode_groups`, by the canonical string of the resolved
  objects), one phase per group (a fixed-step `CellPhase`/`ModelPhase`, or a host
  `_AdaptiveODE`). A model whose ODEs share one solver generates exactly the code it did
  before. Nothing reaches CorePotts algorithm types (D-046). The fingerprint seed adds the
  spec's canonical string (types printed fully qualified, primitives and ranges by `repr`,
  closures by their captures, dictionaries and keyword bundles sorted) when the model
  integrates anything.
- **Jacobi scratch.** A scope (cell, model) with several solver groups gets state slots
  `x__ode` for its ODE unknowns (`_ode_layout`, applied at construction, `remake_state`
  and the solver remake). Each group's phase reads the variables and writes the scratch
  (an empty cell slot copies its value through; the adaptive phase writes its host
  scratch and copies that to the device), then one `CopyPhase` per unknown publishes after
  the scope's last group. Cell groups publish before the model groups run (D-077 N3).
  One group: no scratch, direct writes, unchanged code.
- **Rebuild hook.** CorePotts `remake` passes keywords beyond its fixed ones to
  `remake_function(f.sys, prob; kwargs...)` (default: an `ArgumentError`). Potts'
  method on `PottsModelInfo` (which keeps the compiled system, `T`, the host context and
  the `SolverSpec`) merges the named solver keywords into the stored ones, re-resolves and
  returns `(f, u0)`: `_problem_function`'s new `f` and `prob.u0` re-laid out for its
  scratch. CorePotts keeps `p`, `seed`/`replica`/`repeat` and the frozen mask. A `u0`
  given in the same call, or to `remake`/`reinit!` alone, goes through `remake_state`
  for the (new) `f`: a symbolic map builds a fresh state, a `CPMState` is re-laid out
  for the scratch (`_ode_layout`, which touches only the `x__ode` slots of the ODE
  unknowns; declared names may not end in `__ode`, `__tick` or `__next`).
  `remake(prob; p | u0 | seed)` never calls it.
- **Fingerprint and paths.** `_code_hash` strips every line number, including the
  `LineNumberNode`s macro calls carry (`@inbounds` records the generating file), so the
  fingerprint depends neither on the checkout path nor on line moves (D-016). The
  structural seed is a canonical string (`_fingerprint_seed`: lattice, spacing,
  neighbourhood, `T` by content), not a hash of package structs, which falls back to
  `objectid` and so to the build. Symbolics orders the terms of sums and products by
  hashes involving function identities, so the operand order of generated `+`/`*` calls
  can differ between builds of one source; `_code_hash` reads those operands in printed
  order (`_commutative_order!`). The same source at another path or build fingerprints
  alike (checked against a `git archive` copy, P6.0c review 2); the code itself may differ
  in operand order, i.e. in rounding only.

### 2.7 Hybrid coupling (extensions)

- `ODEComponent(sys; inputs, outputs, cadence)`: at `PottsProblem` construction the
  component's system is `mtkcompile`d once and its `ODEProblem` built once. At `init`
  one ODE integrator is created. Each coupling point: `setp` inputs, `step!` to the
  target time, `getu` outputs into CPM state.
- Per-cell ODEs: one batched system over the cell dimension (`u[c, :]`); on GPU
  via `EnsembleGPUKernel`.
- `MethodOfLinesComponent`: `symbolic_discretize` once, then the same integrator path.
- Native lifecycle phases (`BeforeLifecycle`, …) are schedule slots in §1.6.

## 3. lib/LocalMath — what changes (historical: D-040 removed LocalMath from the monorepo)

Kept: `Space`, `Field`, relation algebra, all publication laws, `@localmath`,
`@prepare`, bind → plan → prepare → execute!, launch fusion.

Slimmed:

- no plan-time `code_typed` admission (moved to test-time JET)
- no receipts, leases, poisoning; errors and the device status word instead
- `_WorkspaceLeafSlot{Name}` / `_PreparedFieldSlot{I}` become value fields
- `PreparedPlan` is concrete and typed on the stage schema only

~~Used by CorePotts for: field stages, synchronous updates, history push, …~~ Superseded
by D-033: CorePotts phases are plain generated KA kernels. LocalMath is an optional
stage-program runtime, wrapped as a phase `(st, p, ctx, key, mcs, backend)` when a model
needs its ordered folds, collections or keyed reductions.

## 4. Testing and verification

| Layer | Oracle |
|---|---|
| `delta_H` | brute-force total Hamiltonian difference on random flips, every model |
| trackers | full recomputation after N steps equals the maintained value |
| checkerboard | sequential statistics (heterotypic fraction, cell counts, volume histograms) over ≥ 12 seeds |
| determinism | same seed + backend → same run (debug aid); CPU vs GPU agree statistically |
| checkpoint | state round-trips exactly; continuation is statistically correct |
| lifecycle | invariants: dense ids, volumes sum to occupied sites, no orphan sites; scientific tests ported from CorePotts |
| reference parity | each published model vs the frozen `reference/` environment, KS test on saved observables over 16 seeds |
| quality | Aqua, ExplicitImports, JET `@test_opt` on `init`/`step!`, AllocCheck on the warm step, Downgrade CI |
| performance | AirspeedVelocity: fresh-process load, build, first MCS, remake, warm step (CPU + Metal) |

## 5. Code style rules (enforced by review)

- No `@generated`, no recursion over heterogeneous tuples in package code; the model
  varies through generated functions only.
- No type parameters that encode model content (names, counts, expressions). Structural
  parameters are literals in generated code.
- `@inline` only on leaf primitives; no `@inbounds` without an adjacent bounds
  argument.
- No `throw` inside kernels; set the status word.
- Every pass-through of a function argument is `::F where {F}`.
- Every generated function is `drop_expr`'d.
- SciML formatter style; ExplicitImports clean.

## 6. Amendments from the legacy-spec adjudication

`research/legacy-spec-adjudication.md` is authoritative where it is more specific than
this document. §1 of that file (F1–F13) is already applied above; §2 semantics and §3
features are scheduled in ROADMAP.md.
