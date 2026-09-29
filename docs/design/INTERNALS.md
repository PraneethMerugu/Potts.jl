# Internals design — Potts monorepo rewrite

Companion to `MONOREPO_MIGRATION_PLAN.md`. This is the concrete design an implementer
follows. Versions: Julia ≥ 1.12, SciMLBase 3, ModelingToolkitBase 1, Symbolics 7,
KernelAbstractions 0.9, RuntimeGeneratedFunctions 0.5.

```
Potts (symbolic)          lib/CorePotts (numerical)             lib/LocalMath
PottsSystem ──mtkcompile──▶ CompiledPottsSystem ──codegen──▶ CPMFunction ──▶ CPMProblem
                                                                  │
                                            init ──▶ PottsIntegrator ──▶ step!/solve!
                                                                  │
                                       fused MC kernels   +   LocalMath stages (fields,
                                       (propose/commit)       sync updates, lifecycle,
                                                              relationships, queries)
```

## 1. lib/CorePotts — numerical layer

Depends on KernelAbstractions, Atomix, LocalMath, SciMLBase, SymbolicIndexingInterface,
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

- Cell ids are dense `1:capacity`. `generation[c]` disambiguates reused ids. Capacity
  grows only at an MCS boundary, on the host, by reallocation (types unchanged, so no
  recompilation).
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
key     = (seed ⊕ replica ⊕ repeat) hashed to 2×UInt32
counter = (mcs::UInt32, phase_round::UInt32, entity::UInt32, (stream << 24) | draw)
```

- `stream` is an 8-bit id assigned by codegen to every distinct random operation in the
  model (direction, acceptance, priority, each authored `draw`, lifecycle side, …), from
  a namespaced operation key. `draw` indexes repeated draws inside one operation.
- `entity` is the site linear index, cell id or attempt counter depending on the stream.
- Nothing depends on thread order, launch order or backend → exact replay.
- 4x32 rather than the old 4x64: 32-bit multiplies are native on every GPU.

### 1.5 Algorithms

**`SequentialCPM(; attempts_per_site = 1)`** — host loop, random target site, random
source direction; the fidelity reference.

**`CheckerboardCPM(; attempts_per_site = 1)`** — KA kernels, CPU or GPU.

- Coloring stride per axis `s = r + 1`, where `r = footprint.max_read_radius`, the
  largest lattice distance any generated function reads from a target. Moore contact
  only → `r = 1`, `s = 2`, 4 colors in 2D. Act with neighborhood-of-source → `r = 2`,
  `s = 3`. If `n % s != 0` on a periodic axis, `s` is raised to the next divisor (or the
  axis gets an extra remainder color class).
- Per color: **2 launches**.
  1. `propose!`: draw direction, build `prop`, `constraint`, `delta_H`, Metropolis
     accept, then claim both cells with `atomic max` of a unique priority
     (random high bits | color-local index).
  2. `commit!`: if the proposal won both claims, run the generated `commit!` and clear
     the alternate claim buffer.
  Claims guarantee each cell changes at most once per color, so ΔH is exact and the
  tracker updates need no atomics.
- Same-color targets are ≥ `s` apart, so no target lies inside another's read
  footprint. Sources are read-only. This makes contact and site-domain ΔH exact.
- Dynamics differ from sequential (mutual maxima); documented and tested
  statistically.

**Metropolis** uses a package-owned `exp` (pure Julia, no fast-math) so CPU and GPU
agree bitwise for the same scalar type. The acceptance test is `u < exp(-ΔH/T)` with
`ΔH ≤ 0` short-circuited.

### 1.6 The MCS schedule

```
for each MCS:
  phases.before_mcs          (LocalMath stages)
  for round in 1:attempts_per_site
      for color in permuted colors: propose! ; commit!
  phases.after_mcs           (synchronous site/cell updates, field steps, history push)
  lifecycle (device-gated)   (see 1.7)
  relationships rebuild      (only if relationships exist and something changed)
  save hook                  (only if this MCS is in saveat)
```

- **No host synchronization inside the loop.** Everything is enqueued; the integrator
  synchronizes only at save points, on `integrator.u` access, at the end, or when a
  callback needs host state.
- A device `status` word (UInt32 bitflags) records capacity overflow and invariant
  violations. It is read at every synchronization; a nonzero status ends the solve with
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
- `checkpoint(integ)` = host copy of `CPMState` + `mcs` + RNG key + `fingerprint` + `p`.
  `init(prob, alg; checkpoint = ck)` continues bitwise (counter RNG makes this exact).
  Fingerprint mismatch is an error.

### 1.10 Backends

`backend = CPU()` / `MetalBackend()` / `CUDABackend()` passed directly. `init` adapts
arrays with `Adapt`. Sequential requires `CPU()`. Scalar type defaults to `Float64` on
CPU and `Float32` on GPU.

## 2. Potts — symbolic layer

Depends on ModelingToolkitBase, Symbolics, SymbolicIndexingInterface, DynamicQuantities,
CorePotts. Full ModelingToolkit, MethodOfLines and Unitful are extensions.

### 2.1 `PottsSystem <: ModelingToolkitBase.AbstractSystem`

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
- Returns `CorePotts.CPMProblem` with `f.sys = sys`. SII: `symbolic_container(prob) =
  f.sys`; `getu`, `setp`, `observed`, `remake` work as in MTK.
- `EnsembleProblem(prob; prob_func)` changes only `seed`/`replica`, reusing `f`.

### 2.7 Hybrid coupling (extensions)

- `ODEComponent(sys; inputs, outputs, cadence)`: at `PottsProblem` construction the
  component's system is `mtkcompile`d once and its `ODEProblem` built once. At `init`
  one ODE integrator is created. Each coupling point: `setp` inputs, `step!` to the
  target time, `getu` outputs into CPM state.
- Per-cell ODEs: one batched system over the cell dimension (`u[c, :]`); on GPU
  via `EnsembleGPUKernel`.
- `MethodOfLinesComponent`: `symbolic_discretize` once, then the same integrator path.
- Native lifecycle phases (`BeforeLifecycle`, …) are schedule slots in §1.6.

## 3. lib/LocalMath — what changes

Kept: `Space`, `Field`, relation algebra, all publication laws, `@localmath`,
`@prepare`, bind → plan → prepare → execute!, launch fusion.

Slimmed:

- no plan-time `code_typed` admission (moved to test-time JET)
- no receipts, leases, poisoning; errors and the device status word instead
- `_WorkspaceLeafSlot{Name}` / `_PreparedFieldSlot{I}` become value fields
- `PreparedPlan` is concrete and typed on the stage schema only

Used by CorePotts for: field stages, synchronous updates, history push, lifecycle
compaction/assignment, relationship rebuild, spatial queries (neighbor counts, sums,
means, predicate filters, interface queries — all `Reduce`/`KeyedReduce` stages).

## 4. Testing and verification

| Layer | Oracle |
|---|---|
| `delta_H` | brute-force total Hamiltonian difference on random flips, every model |
| trackers | full recomputation after N steps equals the maintained value |
| checkerboard | sequential statistics (heterotypic fraction, cell counts, volume histograms) over ≥ 12 seeds |
| replay | identical results across runs, thread counts, and CPU vs GPU (same scalar type) |
| checkpoint | split run == straight run, bitwise |
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
