# What it takes for Potts.jl to be ModelingToolkit-native as a whole (P6.0be)

> **DESIGN, not a decision.** 2026-10-07, ROADMAP P6.0be (D-156). Nothing in `src/`, `lib/` or
> DECISIONS changes. The maintainer decides the route and the paper wording.
>
> **Inputs.** `research/mtk-native-investigation.md` (2026-09-30, written *INV* below; its
> corrections from `mtk-native-review.md` are taken as settled), D-014, D-038, D-039, D-075,
> D-137, D-156. Probes `q1`–`q10` were run on 2026-10-07 and their results are quoted in §7.
> Small probes ran on this Mac (M1 Pro). Anything that scaled ran on the PC (Ryzen AI Max+ 395,
> `taskset -c 0-11,16-27`, Julia 1.12.6), with `--project=~/potts-full`, whose Manifest pins the
> same git trees as this workspace.

## 0. Stop and report (D-156)

Every route that would make the claim "ModelingToolkit-native as a whole" literally true
hits D-156's stop rule. Each one needs either major MTK friction or a major slowdown. None
is recommended here, and none should start without a maintainer ruling.

| Route | Flag | Why (measured unless marked) |
|---|---|---|
| **F**: fields simulated by MTK's array codegen | **Major slowdown** | At 256², `ODEProblem` takes 15–17 s and peaks at about **62 GB RSS**, the PC's whole memory. The OOM killer ended two of the four processes that reached that size. The cause is a dense `n×n` mass matrix (§3.3). With that patched locally, build time is 7.6 s at 256², 34 s at 512² and 140 s at 1024². The warm right-hand side runs at 6–100 ns per element and **allocates** (331 KiB per call at 64², 88 MiB at 1024²), so it fails the warm zero-allocation gate. It has no Metal or ROCm path. Periodic and no-flux boundaries are not expressible without scalarizing |
| **K**: per-cell state as MTK array unknowns | **Major slowdown and friction** | The capacity is fixed per `System`. Growth means a new `System` plus codegen plus RGF compilation, against "remake zero compile" (AUTONOMY §5) and D-013. Unknown-size arrays fail (§3.2) |
| **S**: the sweep as an MTK event or callable parameter | **Major friction** | It is opaque to MTK, so the claim stays nominal. The lattice is outside `u`, so SII, checkpoints and the fingerprint fight MTK's data model. MTK's integrator would drive the MCS loop on the host. Overhead not measured |
| **B**: a Potts model *is* an MTK `System` | **Major friction** | `ODEProblem(sys)` would silently simulate a model with no sweep. There is still no public compatibility hook on MTK master `fd0cbadb` (2026-10-06) |
| **U**: upstream operator and population scopes | **Out of our control** | No issue, PR or roadmap item upstream. It would take months and SciML buy-in |

What does **not** trigger the rule is the Catalyst-spatial completion, Level A (§4, items
P6.0bm–P6.0bq). It costs about 0.3–1.5 s of cold build per model before precompile
workloads absorb it, and nothing on the gate. That is the work the recommended claim (§5)
rests on.

---

## 1. Verdict per blocker, 2026-09-30 vs 2026-10-07

| Blocker | INV (2026-09-30) | Now (MTKB 1.77.0 pinned; 1.77.3 / MTK 11.45.3 latest) | Changed? |
|---|---|---|---|
| **1. The sweep as an MTK object** | No mechanism. `JumpType` and `Affect` are closed unions; only opaque routes exist | Unchanged. On master `fd0cbadb` both unions are identical (`utils.jl:1663`, `callbacks.jl:353`). No custom-operator or partition hook is open or planned | **No** |
| **2. Ragged, growing per-cell state** | Fixed capacity works but is scalarized; a symbolic length throws; `resize!` leaves new entries without symbols | Fixed-capacity array *unknowns* no longer need scalarizing: #5131, merged 2026-09-13, ships in 1.77.0. Capacity is still fixed per `System`. **New:** SymbolicUtils has `Unknown`-shape arrays, but an unknown-size *unknown* is rejected at `System` (`length(::Unknown)`), and an unknown-size *parameter* fails at `ODEProblem` (`ShapeVecT` typeassert), even opaque and non-tunable (§7 q7) | **Slightly**: cheaper fixed capacity, still no growth |
| **3a. Fixed-shape lattice fields** | Expressible, but scalarized: 225 s at 64², 99 % of it the initialization problem | **Partly unblocked upstream.** #5148 (MTKB 1.75+) builds `ODEProblem(complete(sys))` from whole-array differential equations with no `mtkcompile`; the code stays in array form (§7 q1). Three new limits were found. (i) A **dense `zeros(n, n)` mass matrix** (`codegen.jl:744`) plus `u0 .* u0'` in `concrete_massmatrix` make memory O(n²): about 62 GB at 256². (ii) Rows are packed in *equation* order, so unless the equations follow the unknowns' layout the problem gets a **permutation mass matrix** and needs an implicit solver. (iii) Periodic and no-flux stencils cannot be written unscalarized: `mod1` on `@arrayop` indices is a MethodError, and `vcat`/`hcat` of slices produces `Matrix{Num}`. #5139 (keep arrays through `mtkcompile`) is still open, its draft #5102 has been idle since 2026-09-09, and #5100 was closed | **Yes, partly**: see §3.3 for the price |
| **3b. Ownership-indexed terms** (`J[τ(σ(x)), τ(σ(x′))]`, `volume(σ(x))`) | No counterpart | A term `J[τ[σ[1]], τ[σ[2]]]` now *builds*, but `build_function` emits an unbound inner array (`UndefVarError: τ`). An ODE `D(x[i]) ~ x[s[i]]` with an `Int` parameter index builds a `System`, then `ODEProblem` codegen fails the same way, and indexing by an unknown is a MethodError (§7 q10). Upstream has started on discrete-integer indices in affects: #5078 is open, PR #5235 is open | **Started upstream, not usable** |

**Bottom line.** Since 2026-09-30 the *field* half of blocker 3 has moved: whole-array
equations now reach codegen without scalarizing. Blockers 1 and 2 and the ownership half
of 3 have not moved, and nothing upstream targets them. INV's headline holds, with one
amendment: "fully native" is still unachievable, but a *fixed-shape field* is now an MTK
object whose description costs O(1) and whose construction cost is dominated by two
fixable O(n²) and superlinear paths. Its runtime is still far from Potts' fused stencil.

---

## 2. What changed upstream since 2026-09-30

- **Releases.** MTKB 1.77.1, 1.77.2 and 1.77.3 (2026-10-06); MTK 11.45.2 and 11.45.3
  (2026-09-29). The General registry snapshot of 2026-10-05 also has Symbolics 7.43.0,
  SymbolicUtils 4.49.0 and Catalyst 16.5.0. The workspace still pins MTKB 1.77.0, MTK
  11.45.1, Symbolics 7.41.1 and SymbolicUtils 4.48.0, all unchanged since INV.
- **Array work that matters to Potts.**
  - #5131 (merged): array unknowns on a `complete`d system for every problem type.
  - #5148 (merged, MTKB 1.75): array equations reach `ODEFunction`, `DAEFunction` and
    `NonlinearFunction` behind the `accepts_array_equations` trait
    (`problem_utils.jl:2629-2632`).
  - Still open: #5139 (tracking), #5102 (array-aware tearing, draft, idle), #5187 and #5190
    (quadratic `varmap_to_vars`, DAE path), #5242 (contiguous derivative views).
- **Symbolic indices.** Still open: #5078 (indexing an array parameter by a discrete `Int`
  in an affect) and #5235.
- **Not found** (searches on 2026-10-07 for resize, population, agent-based, variable
  number, custom operator): nothing on a population or agent dimension, a runtime-resizable
  unknown, or an opaque operator field in `System`. The only maintainer statement is still
  Discourse 102324 (2023), quoted in INV.
- **Found while probing, not yet reported upstream** (§6, upstream drafts):
  - `calculate_massmatrix` allocates `zeros(n, n)`, and `concrete_massmatrix` builds
    `u0 .* u0'`. Both are O(n²) in memory for any large array ODE on the `complete` path.
  - Unknown-size parameters cannot reach `ODEProblem`.
  - Indirect indexing builds a term but does not generate code.

---

## 3. Blockers in detail

### 3.1 The sweep

No change. The candidates are as in INV §4.1:
- equations (no form);
- jumps (closed union, and the kinetics change);
- `ImperativeAffect` (opaque, on the host, writes only declared variables);
- callable parameters (opaque);
- `discrete_compile_pass` (needs equations);
- `build_function` (straight-line code only).

One sharpening matters for the claim. Potts already gives the sweep a *symbolic*
description: the Hamiltonian terms are Symbolics expressions (`EnergyTerm`s), ΔH is derived
symbolically (INTERNALS §2.5), and drives and constraints are symbolic. What MTK lacks is a
place to *put* that description so that MTK-generic tools see it. That is a metadata and
accessor question (item P6.0bm), not a codegen one. It gives "the sweep is a typed,
inspectable MTK-side object", but not "MTK executes the sweep".

### 3.2 Ragged, growing per-cell state

- **Works now.** `V(t)[1:cap]` as an unscalarized array unknown on the `complete` path.
- **Does not.**
  - Growth during a solve.
  - A symbolic or unknown length, for unknowns or for parameters (q7).
  - SII on entries added by `resize!` (INV §6.3).
- **Price of emulating growth** (route K). Every capacity change rebuilds `System`,
  `complete`, `ODEProblem` and the RGFs.
  - From q8's scaling, construction at 10⁴–10⁵ entries costs 1–8 s once the mass-matrix
    defect is patched, and needs tens of GB above about 3×10⁴ entries without it.
  - Doubling the capacity gives log₂(n) rebuilds per run. Each one is a compile in the
    middle of a run, which breaks "`remake` zero compile" and D-013's "grow by host
    reallocation without regenerating code".
  - **D-156 flag.**

### 3.3 Lattice quantities

**Fields (3a), route F, priced.** The case is a 2-D diffusion field written as one array
equation over the interior slice plus four edge equations. It is built with
`complete → ODEProblem(build_initializeprob = false)` and checked against a hand stencil.

| Elements | As shipped (MTKB 1.77.0): build, peak RSS | With a local sparse mass-matrix patch: `complete` + `ODEProblem` | Warm RHS (patched) |
|---|---|---|---|
| 64² = 4 096 | 0.3–2.3 s, 1.4 GB | 0.09 + 0.32 s | 6–8 ns/elt, 331 KiB/call |
| 128² = 16 384 | 1.1–4.3 s, **5.3 GB** | 0.48 + 1.1 s | 20 ns/elt, 1.3 MiB/call |
| 181² = 32 761 | 7.7 s, **17.6 GB** | — | — |
| 256² = 65 536 | 15–17 s, **≈ 62 GB** (two of four runs OOM-killed) | 2.5 + 5.1 s | 103 ns/elt, 5.4 MiB/call |
| 512² | — | 8.1 + 25.6 s | 20 ns/elt, 22 MiB/call |
| 1024² | — | 42.8 + 97.1 s | 52 ns/elt, 88 MiB/call |

What this means:
- **Construction.** The O(n²) memory is the dense mass matrix, a small upstream fix (§6).
  Even patched, construction is superlinear: 140 s at 10⁶ elements. The reference models
  run 200² to 300³ (2.7×10⁷), so 3-D is out of reach.
- **Runtime.** The generated code broadcasts slices into about 7 temporaries per call. It
  allocates and runs at 6–100 ns per element per RHS evaluation. Potts' `FieldStep` is
  allocation-free and fused, and the gate forbids warm allocations (AUTONOMY §7.3). Merks
  runs 15 field substeps per MCS (`lib/PottsModels/src/merks.jl:36`). On top of that, MTK
  codegen has no KernelAbstractions target for Metal or ROCm.
- **Semantics.**
  - Only a frozen-ring (Dirichlet-like) boundary is expressible without scalarizing.
    Periodic boundaries need `mod1` on array-op indices (MethodError) or concatenation
    (scalarizes, q2/q3). An `L * c` matrix parameter densifies, taking 496 s and 10.8 GB at
    64² and OOM at 256².
  - Unless the equations are written in the unknowns' memory order, the `ODEFunction`
    carries a permutation mass matrix (q4). That is correct, but it excludes explicit
    solvers.
- **Verdict.** MTK may *describe* a field cheaply, but it cannot *run* one at Potts sizes
  without a major slowdown. **D-156 flag on route F.** The non-flagged use is description
  only: P6.0bq takes a `PDESystem` as input, Potts discretizes it, and an MTK array system
  serves as a small-N oracle.

**Ownership-indexed terms (3b).** These include contact `J`, `volume(σ(x))` and folds
over `sites(c)`. The symbolic term exists, but codegen does not (q10). Upstream work on
`table[k]` with a discrete `k` (#5078 and #5235) is the first step toward it. Even when it
lands, it covers a scalar affect, not a vectorized stencil over a state-dependent map. **No
route in the paper's time frame.**

---

## 4. Routes, priced

The cost columns have these meanings:
- **Build**: added cold construction per model.
- **Latency**: time to first MCS. Today 5.8–5.9 s, of which about 4.9 s is package load
  (P6.3b-cold); the budget is 15 s (D-047).
- **Gate**: warm MCS, allocations, and Metal or ROCm.

| Route | What becomes MTK | Build | Latency | Gate | Friction | D-156 |
|---|---|---|---|---|---|---|
| **R0, today** (D-137, D-038, P6.0k) | `PottsSystem <: AbstractSystem`: `equations`, `unknowns`, `parameters`, `observed`, metadata, SII, `complete`, `extend`. `@components` MTK systems go through MTK's `mtkcompile`. Clocked components go through `discrete_compile_pass` | — | — | — | — | — |
| **A2** (P6.0bn): the model's own cell and model ODEs as a per-scope MTK `System` passed through `mtkcompile` before Potts lowers them | Every user ODE is simplified by MTK (observed elimination, bindings, units) | +0.2 s first `mtkcompile` in a session, about 1 ms warm (q9, M1 Pro) | ≤ +0.3 s cold, absorbable by the existing PrecompileTools workload | 0 if the lowered code is byte-identical. Otherwise a D-136 re-pin | Low; components already take this path | no |
| **A1** (P6.0bo): entity-local initialization through MTK's `InitializationProblem` per component class | MTK's initialization engine for per-cell equations | +0.5 s first in a session, about 1 ms warm (q9) | ≤ +0.5 s cold, absorbable | 0 (only at `at_init`) | Medium: D-075 §3.2's engine wording changes | no |
| **A3** (P6.0bp): `@discrete_events` and `@terminate` kept as `SymbolicDiscreteCallback` objects on the compiled system | Events are MTK objects (inspectable, `show`) | 0.03 s first, ~0 warm (q9) | ~0 | 0 (Potts still compiles them) | Low | no |
| **A4+** (P6.0bm): the Hamiltonian, drives, constraints and sweep as a typed MTK metadata payload, with a public `hamiltonian(sys)` returning the symbolic H | The sweep's *definition* is an MTK-visible symbolic object | ~0 | ~0 | 0 (fingerprint unaffected: metadata never enters code, D-137 rule 2) | Low | no |
| **A5** (P6.0bq): `PDESystem` input for fields, Potts' own `discretize(pdesys, ::PottsLattice)`; an MTK array `System` as the small-N oracle | Fields are written as MTK's PDE object (the MOL pattern) | Small; parsing only | ~0 | 0 (FieldStep unchanged) | Medium: a PDE parser for `Differential(x)^2` → stencil, BC mapping | no |
| **F**: fields executed by MTK codegen | Field dynamics compiled by MTK | 7.6 s at 256² patched; ≈ 62 GB unpatched | +several s to minutes | **Fails**: allocates, about 6–100× slower per element, no device | High | **YES (slowdown)** |
| **K**: per-cell state as MTK array unknowns | Cell state is MTK unknowns | Seconds per rebuild, log₂ rebuilds per growing run | Compiles mid-run | Fails "remake zero compile" | High (D-013) | **YES** |
| **S**: sweep in an `ImperativeAffect` or callable parameter | Nominal only | Unmeasured | Unmeasured | Sweep forced onto the host per MCS | High (lattice outside `u`) | **YES (friction)** |
| **B**: the model is an MTK `System` with metadata | Nominal; MTK tools answer about a different model | Scalarized or array costs as F and K | — | — | Very high (silent wrong answers) | **YES** |
| **U**: upstream operator and population scopes (INV Level C) | Truly native | — | — | — | Upstream; months; needs SciML buy-in | **YES (external)** |

**Recommended set (not a decision):** A4+, A3, A2, A1, then A5. That is INV's Level A with
the sweep-as-metadata sharpening and the field-input route made concrete. Total effort:
small to medium per item. Gate cost: none expected. Latency: at most about +1 s cold before
precompile workloads, about 0 after.

---

## 5. The strongest claim the paper can defend

**Recommended wording** (true once P6.0bm–P6.0bp merge; the bracketed clause needs
P6.0bq):

> Potts.jl is built on ModelingToolkit. Every Potts model is a ModelingToolkit system: an
> `AbstractSystem` whose parameters, state variables, equations, observables, events and
> Hamiltonian are Symbolics expressions that ModelingToolkit's generic tools can inspect,
> index and complete. The continuous, clocked and initialization parts of a model are
> ModelingToolkit systems compiled by `mtkcompile`, and existing ModelingToolkit models
> plug in as components [, and diffusing fields are written as ModelingToolkit
> `PDESystem`s]. The stochastic lattice dynamics, a Markov operator over cell ownership
> with no equation form in ModelingToolkit, are compiled from the symbolic Hamiltonian by
> Potts.jl's own code generator into fused CPU and GPU kernels. This is the same division
> of labour Catalyst uses for spatial reaction networks.

**True today, before any new item:**
- "every Potts model is a ModelingToolkit `AbstractSystem`" (D-137);
- "MTK models plug in as components, compiled by `mtkcompile`" (D-038, P6.0k);
- "clocked components go through MTK's discrete compile pass".

**Do not claim.** Each of these is false and checkable by a reviewer in one line:
- "fully MTK-native" or "MTK-native as a whole": `ODEProblem(sys)` is an `ArgumentError`
  (D-137 rule 5);
- "ModelingToolkit compiles the CPM", or "ModelingToolkit simulates the model";
- "Potts.jl models are ModelingToolkit `System`s": they are `AbstractSystem`s, and
  `System` is concrete;
- any claim that `ODEProblem`, `JumpProblem` or `structural_simplify`/`mtkcompile` *of
  MTK* handle a Potts model.

**Gap to the full claim, stated for the maintainer.** The full claim needs:
- (1) an MTK object that carries an operator with declared read and write sets (blocker 1);
- (2) a runtime-resizable unknown dimension with SII support (blocker 2);
- (3) state-dependent indexing in codegen (3b).

None exists or is planned upstream (§2). Routes that fake them (S, B) make the claim
nominal and trip D-156. The honest path to the full claim is route U, proposed upstream
with Catalyst-spatial and agent-based users (INV §7.3 item 6). Its timeline is outside
the paper's.

**Make the claim checkable** (P6.0bs): a frozen test file that runs, on every published
model, each MTK generic the paper names (`equations`, `unknowns`, `parameters`,
`observed`, `getmetadata`, SII `getu`/`setp`/`observed`, `complete`, `extend`,
`hamiltonian`). It also asserts that `ODEProblem` and `JumpProblem` refuse with the Potts
route, so the claim can never drift from the code.

---

## 6. Proposed ROADMAP items

The IDs are suggestions; the coordinator assigns them. Every item takes the standard gate
(+5 % warm MCS, zero warm allocations) and a paired latency check like D-137 rule 8:
`benchmark/p6_0o_latency.jl`, with time to first MCS, construction and `mtkcompile` each
within +5 %. Code and fingerprint pins stay byte-identical unless the item says otherwise.

- **P6.0bm: the sweep as an MTK-visible object (A4+).**
  - Content: a public `Potts.hamiltonian(sys)`, the symbolic H per domain (cell, site,
    contact, relationship) as written; `Potts.drives(sys)` and `Potts.constraints(sys)`.
  - A `PottsSweepSpec` typed metadata key on `PottsSystem` and `CompiledPottsSystem`. It
    holds the algorithm-independent sweep definition (H terms, the proposal neighbourhood,
    temperature symbol, drives and constraints), is readable with `getmetadata`, and is
    shown by `show`.
  - Accept: generic `getmetadata(sys, PottsSweepSpec)` works on every published model, and
    `hamiltonian(sys)` round-trips (`substitute` into the brute-force H oracle of D-048
    equals `CorePotts` H on a 3-state fixture). Code and fingerprint pins unchanged.
  - Effort: small. Decisions: D-137 (accessor list).
- **P6.0bn: model ODEs through MTK (A2).**
  - Content: build one MTK `System` per scope (cell, model) from `@equations` and pass it
    through `ModelingToolkitBase.mtkcompile`, as `@components` systems already are.
    Potts lowers the simplified equations into its `CellPhase`/`ModelPhase`; D-014 and
    D-038's batched kernel are unchanged.
  - Accept:
    - generated code is byte-identical on every published model and fixture, or else
      equal up to MTK's observed elimination, re-pinned under D-136 with a trajectory
      equality test;
    - an algebraic observed in `@equations` is eliminated by MTK (negative control:
      before this item it is lowered as written);
    - latency within +5 % after a precompile-workload update.
  - Effort: medium. Decisions: D-038 wording.
- **P6.0bo: entity-local initialization through MTK (A1).**
  - Content: `@initialization_equations` that touch one entity's variables go to one MTK
    `InitializationProblem` per component class, solved per cell at `at_init`.
    Cross-entity and lattice initialization stay in Potts' `at_init` phase.
  - Accept:
    - per-cell results equal a hand-solved fixture;
    - a cross-entity equation is routed to Potts (negative control);
    - the D-133/F7 rejections stay.
  - Effort: medium. Decisions: D-075 §3.2 amended (maintainer).
- **P6.0bp: events as `SymbolicDiscreteCallback`s (A3).**
  - Content: keep the MTK callback objects on the compiled system; Potts still compiles
    them. Conditions on model scope and `t` only; anything else is the existing error.
  - Accept: `ModelingToolkitBase.discrete_events(sys)` lists them on every model that has
    them, and code pins are unchanged.
  - Effort: small.
- **P6.0bq: `PDESystem` input for fields (A5).**
  - Content: `@fields` (or a `fields = [pdesys]` keyword) accepts a ModelingToolkit
    `PDESystem`. Potts' `SciMLBase.discretize(pdesys, ::PottsLattice)` lowers diffusion,
    decay and source terms and Dirichlet, Neumann and periodic BCs to the existing
    `FieldStep`. PDEBase's scalarizing path is not used.
  - Oracle: the same field as an MTK array `System` on the `complete` path at 32² with a
    Dirichlet ring (q8 form), solved by OrdinaryDiffEq, compared with `FieldStep` after
    10 substeps (rtol 1e-10). It is test-only and never in the hot path.
  - Accept: Merks and OpenVT fields authored both ways give identical `FieldStep` code.
  - Effort: medium. Optional for the paper; it supplies the bracketed clause in §5.
- **P6.0br: upstream drafts (maintainer sends; nothing is posted without them).**
  1. A new issue: `calculate_massmatrix` `zeros(n, n)` and `concrete_massmatrix`
     `u0 .* u0'` are O(n²): about 62 GB at 65 536 array elements. Reproducer q8, with the
     local patch as the proposed fix.
  2. A new issue: an unknown-size parameter (`@parameters w::Vector{Float64}`) fails in
     `ODEProblem` (`ShapeVecT` typeassert) even inside a registered function. Reproducer
     q7.
  3. A comment on #5078: indirect indexing `x[s[i]]` builds but generates code with an
     unbound inner array. Reproducer q10.
  4. A comment on #5139 with q8's scaling table and the boundary limitation (no
     `mod1`/periodic in `@arrayop`).
  5. INV §7.3 items 1, 5 and 6, unchanged; item 6 (the population/operator RFC) is the
     only route to the full claim.
  - Effort: small. Gate: maintainer.
- **P6.0bs: the nativeness test and the paper sentence.** The frozen
  `lib/PottsModels/test/acceptance/mtk_interface.jl` described in §5, plus the claim text
  in the paper draft and the docs' "Relation to ModelingToolkit" page, each sentence
  cited to the test that checks it. Effort: small. Depends on the chosen subset of
  P6.0bm–P6.0bq.
- **P6.0bt (optional, non-gating): an upstream watch.** On each MTKB minor bump, rerun
  q1, q7, q8 and q10 on the PC under a `systemd-run -p MemoryMax=16G` scope; the q1
  baseline exceeded 56 GB. Record build time, RSS and warm ns/elt. If the dense mass
  matrix is fixed, #5139 lands, and periodic `@arrayop` indices work, reopen route F as a
  *host-only adaptive field solver* option (D-038 "Deferred"), not as the hot path. This
  measures construction directly, which avoids the mis-attribution the review struck from
  INV §7.1.

Order: P6.0bm → P6.0bp → P6.0bn → P6.0bo → P6.0bs. P6.0bq and P6.0br run in parallel.
Write sets: P6.0bm, P6.0bp and P6.0bn all touch `src/compile.jl` and `src/system.jl`, so
they run in series. P6.0bq touches `src/` field lowering and a new file. P6.0bs touches
`lib/PottsModels/test/acceptance/` and the docs.

---

## 7. Probe results (2026-10-07)

The scripts were in the session scratchpad and on the PC in `~/p6-0be-probe/`. They are
short; the essential lines are quoted.

**q1/q1b: array field on the `complete` path** (`D(c[2:N-1, 2:N-1]) ~ Dc .* (stencil)` plus
4 edge equations).
- The generated RHS keeps slices and broadcasts. The interior block is the same
  `copyto!(view(du, 1:(N-2)^2), vec(Dc .* (…)))` at any N; only the zero edge rows are
  scalar.
- Shipped MTKB 1.77.0, PC: `ODEProblem` takes 0.65 s at 64², 4.3 s at 128² (5.3 GB) and
  7.7 s at 181² (17.6 GB), and 15–17 s at 256² with a peak of about 62 GB. Two of the four processes that reached 256² were OOM-killed. With
  `build_initializeprob = true`, the 32² build takes 7.9 s.

**q4: row order.**
```
D(u[2:3]) ~ [1, 2]; D(u[1]) ~ 10; D(u[4]) ~ 20         (complete → ODEProblem)
du = [1.0, 2.0, 10.0, 20.0]
mass_matrix = [0 1 0 0; 0 0 1 0; 1 0 0 0; 0 0 0 1]       ← permutation, not I
mtkcompile instead reorders unknowns to [u[2], u[3], u[1], u[4]] with M = I
```

**q6 (profile at 128²).** Of 427 samples in `ODEProblem`, 201 are in
`calculate_massmatrix` (`codegen.jl:717-722`) and 82 in `concrete_massmatrix`
(`codegen.jl:757-765`). The cause is `M = zeros(n, n)` (master `codegen.jl:744`), then
`u0 .* u0'` for a non-diagonal M.

**q8: the same field with a sparse `calculate_massmatrix` and a pass-through
`concrete_massmatrix`** (local method overrides in the probe only). `f = M·u′` is checked
against the hand stencil, `true` at every N. Peak RSS is 1.2 GB at 128² and 5.3 GB at
1024². Timings are in the §3.3 table.

**q2/q3: periodic boundaries.**
- `vcat(c[N:N, :], c[1:N-1, :])` builds a `Matrix{Num}`, and `ODEProblem` then fails in
  `_copy_broadcast!`.
- `@arrayop (i, j) c[mod1(i + 1, N), j]` fails with `MethodError: no method matching
  mod1(::BasicSymbolic, ::Int64)`.
- A sparse Laplacian as an array parameter `L[1:N², 1:N²] = L0` works at 16², but at 64²
  `complete` takes 274 s, `ODEProblem` 222 s and 10.8 GB, and 256² goes OOM: the matrix is
  densified symbolically. A `SparseMatrixCSC`-typed array parameter fails an assertion.

**q7: unknown-size arrays.**
```
@parameters w::Vector{Float64}           shape = Unknown(1)
System with unknown-size parameter       OK
ODEProblem (sum(w), or opaque mysum(w), tunable = false)
                                          ERR → TypeError: expected ShapeVecT, got Unknown
@variables V(t)::Vector{Float64} as unknown
                                          ERR → MethodError: no method matching length(::Unknown)
```

**q9: Level-A latencies** (Mac, MTKB 1.77.0, 3-unknown per-cell system with one algebraic
equation and initialization equations).
- MTKB load: 4.5–5.6 s. Potts already pays this.
- First call in the session: `mtkcompile` 0.22 s, `generate_rhs` 0.08 s,
  `InitializationProblem` 0.52 s, `SymbolicDiscreteCallback` 0.03 s, `ODEProblem` 0.89 s.
- Second call: 0.001, 0.000, 0.001, 0.000 and 0.004 s.

**q10: indirect indexing.**
```
J[τ[σ[1]], τ[σ[2]]]                       builds as a term
build_function(…) then call               ERR → UndefVarError: `τ` not defined
D(x[i]) ~ x[s[i]], s::Int parameter       System OK; ODEProblem ERR → UndefVarError: `x`
D(k) ~ y[Int(k)]                          ERR → MethodError: no method matching Int64(::Num)
```

**Upstream state read on 2026-10-07.**
- GitHub API: MTK #5139 (open, last updated 2026-09-13), #5100 (closed unmerged), #5101
  (closed, folded into #5148), #5102 (draft, idle since 2026-09-09), #5131 (merged
  2026-09-13), #5187 and #5190 (open), #5078 (open), #5235 (open). The MTK issue and PR
  stream from 2026-09-25 to 2026-10-07 was read in full by title.
- MTK master `fd0cbadb`, shallow clone: `JumpType` and `Affect` are unchanged, and
  `check_compatible_system` is internal (it lives in `problems/compatibility.jl` and the
  per-problem files).
- Web search (agent-based, resizable state) found AgentBasedModeling.jl (PLOS CB 2026)
  and ABMax (JAX). Both run their own population loop; neither describes an MTK
  population scope *(search, not re-verified)*.

---

## 8. Questions for the maintainer

1. **Claim.** Adopt §5's wording, which is defensible after P6.0bm–P6.0bp, or keep
   pressing for the full claim? The full claim needs route U (upstream) and is not
   reachable within the paper's time frame. Routes S and B reach it in name only and trip
   D-156.
2. **Items.** Which of P6.0bm–P6.0bt enter Phase 6, and when? Step 0 is frozen (D-134), so
   these would be new rows after the reproductions start, unless you rule otherwise.
3. **Upstream.** May the P6.0br drafts be sent? The mass-matrix issue is new and cheap for
   SciML to fix.
4. **Route F.** Even if every upstream fix lands, should a host-only MTK-executed field
   solver ever exist (D-038 "Deferred")? Or are fields description-only (P6.0bq)?
5. **PC hygiene.** The unpatched 256² probes drove the PC to its memory limit, and two
   processes were OOM-killed. `~/actions-runner` was not touched, but CI jobs that ran at
   the same moment may have been squeezed. Later heavy probes ran
   under a 16 GB `systemd-run` scope. Should that scope be standard for PC probes?


## 9. Corrections from P6.0br (2026-10-07)

The upstream-draft MWEs (`research/upstream-drafts/`) re-ran the probes on MTK 11.45.1/MTKB 1.77.0 and on 11.45.3/1.77.3. Two findings above are narrower than stated:

- **Unknown-size parameter (q7).**
  - It does not fail at `ODEProblem` once `using ModelingToolkit` is loaded: `ODEProblem(complete(sys))`, `remake` and `setp` to other lengths all work.
  - It fails in `mtkcompile`, with a `ShapeVecT` TypeError in MTKTearing clock inference. It also fails in an MTKB-only `ODEProblem` with default initialization, which goes through `mtkcompile`.
  - The q7 probes had loaded MTKB alone.
- **Indirect indexing (q10).**
  - Symbolics alone is fine: `build_function` with whole arrays returns the correct value. The earlier `UndefVarError: τ` came from passing `collect(τ)`.
  - The bug is in MTK codegen. With PR #5235, the `StableIndex` typeassert is gone, and the generated RHS emits an unbound `J`/`x`.

Neither correction changes the §0 verdicts or the D-159 claim.
