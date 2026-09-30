# Feature roadmap review: general primitives for the 12 published models (2026-09-30)

**Status: proposal, not approved.** The maintainer answers the questions in §7. This review
covers `model-specs/README.md` §2 (features G1–G21), §3 and §6. Only the per-model decisions
in README §4 are approved (D-050).

**Goals (maintainer).**
- Every model in `lib/PottsModels` is a composition of public, general primitives. `src/`
  and `lib/CorePotts` have no model- or author-named paths.
- A capability a model needs becomes a general, dispatch-based feature first. That feature
  must cover its mechanism family as other tools implement it (CC3D, Morpheus, Artistoo,
  Chaste, TST).
- Primitives recombine across models: implementing 12 models should make a plethora of
  other models writable without new code.
- Use SciML wherever a package or interface fits. Only the CPM sweep itself is ours.

Method: three read-only reviewers.
1. Architecture fit of G1–G21, checked against the code at `2a6697c`.
2. A composition sketch per model.
3. An inventory of privileged paths, with guardrail prototypes (scratch copies only).

## 1. Findings

1. **Much of G1–G21 already exists or is expressible now.** It needs tests and library
   sugar, not engine work:
   - kind-restricted copy sources: `@constraint kind[new] == k`;
   - time or position in a drive: a model variable (`@before_mcs G ~ f(mcs)`) or coordinate
     site variables;
   - per-cell pin: a cell variable plus `@constraint`;
   - frame or wall: a frozen kind placed by a layout;
   - discrete field operators and indicator fields: site updates with gathers (D-042);
   - filtered per-cell sums: `integral` with a mask;
   - lagged Zajac director: cell variables written each MCS;
   - Binomial labels and staged temperature: cell and model updates with `rand()` and `mcs`;
   - Merks χ(c,c)/χ(c,M): `ifelse(old == 0 || new == 0, χcM, χcc)`;
   - a soft "threshold" E₀ on connectivity-breaking copies: exactly an additive drive under
     Metropolis.
2. **Several G-items are one missing primitive seen from different models:**
   - cell references (G10, G11, G17 and the destinations for G7);
   - exact after-values of moment-derived quantities (G2, generalising how `major_length`
     already works);
   - topology as a value (G4 hard and soft);
   - site-ownership events (G1 create, G7, G17).
3. **README corrections:**
   - G1: CorePotts has no create event (`lifecycle.jl:13-16` has only divide, remove and
     transition).
   - G8, G16, G18 and G19 are mostly already expressible (finding 1).
   - The "soft penalty" in §6 step 0 is a drive over a connectivity value, not a new
     constraint kind.
4. **Privileged paths today:**
   - `rule = :merks` and `merks_connectivity` (`src/vocabulary.jl:364-371`,
     `src/codegen.jl:276-278`, `lib/CorePotts/src/drives.jl:154-205`). An unknown `rule`
     silently falls back to `:local`.
   - `Chemotaxis(; extension_only)` (`src/vocabulary.jl:545-554`).
   - `act_mean` and `act_delta`, which default to a model-named `ctx.act`
     (`drives.jl:21-73`, a D-046 breach).
   - `geomean_shifted`, whose host and lowered forms disagree on clipping.

   `lib/PottsModels/src` itself is clean: it uses `using Potts` only and builds in a bare
   module. The one model that uses a privileged path is `WortelAct(connected = true)`.

## 2. Family-general primitives replacing the privileged paths

| Today | Family variants to cover | General primitive |
|---|---|---|
| `connectivity(; rule = :local \| :merks)` | CC3D one arc; Merks arc-or-two-cells; Morpheus local; Artistoo global flood fill and soft λ(components − 1); CC3D ConnectivityGlobal; Bauer α; Akeeb 1e5 | Proposal-scope values `local_components(old; relation)` and `ring_cells`, plus `components(old; scope = Global())` (BFS only when the local test fails). Hard rule: `@constraint … <= 1`. Soft rule: `@drive copy => E₀*(… > 1)`. `connectivity(…)` stays as shorthand, and unknown options throw |
| `Chemotaxis(; kinds, extension_only)` | Savill–Hogeweg every copy; Merks 2008 extension only; CC3D regular, saturation c/(s+c), saturation-linear, gaining-type gate; Morpheus retraction switch; Akeeb either-cell-leader | `Chemotaxis(c; strength, response = identity \| saturating(s) \| saturating_linear(s) \| log, when = <copy condition>)`, with `chemotaxis_delta` taking `response` |
| `act_mean`, `act_delta`, `ctx.act`, `geomean_shifted` | Niculescu geometric mean; Artistoo arithmetic mean; legacy log1p mean; per-tool decay and refresh | `neighborhood_mean(x; relation, fold = geomean \| mean \| log1p_geomean)` with no default relation. Optional `ActivityMemory(x; strength, scale, fold, relation, refresh, decay)` library sugar emitting drive, on-copy and after-MCS statements. `act_*` move to the test ports |

Already verified: the Act model with an arithmetic mean and chemotaxis with a saturating
response each build from `using Potts` alone. Soft or global connectivity cannot be written
today.

## 3. Revised minimal feature list (dependency order)

| R | Feature | Absorbs | Where | SciML delegation | Cost |
|---|---|---|---|---|---|
| R0 | Hygiene: §2 primitives; unknown DSL options throw; `public` declarations for generic CorePotts names | P-15 | Potts, CorePotts | – | S |
| R1 | Copy-scope `position`, `direction`, `mcs`/`time`; `Metropolis(tie)` | G3, G8a | Potts, CorePotts | `time` = SciMLBase `integ.t` | S |
| R2 | Layout library with an overlay algebra: Tiling, Scatter, Eden, BrickWall, Chains, Spheres, Fibres, InsertUntil, Frame, Plane | G13, G16 | Potts / host utilities | output is an SII operating point | S–M |
| R3 | `@retire`, `@transition`, `rand(dist)`, `hazard(k)` (a per-MCS Bernoulli), `@discrete_events`, `@terminate` | G1a, G1c, G14 | Potts | Distributions `quantile`; MTK `SymbolicDiscreteCallback` → SciMLBase `DiscreteCallback`; DiffEqCallbacks | S |
| R4 | Topology values (§2): local rules dispatched on geometry, `Global()` | G4 | CorePotts + Potts | – | S / M |
| R5 | `@boundary` per face and a masked clamp applied every substep; field phase placement and order | G5a, G15a, G18 | Potts + CorePotts `FieldStep` | MTK/MethodOfLines-style boundary syntax; our stencils | S–M |
| R6 | Cell references (`sibling`, `root`, `partner`, `x[ref]`) + explicit liveness; claim sets widened automatically | G10 | CorePotts + Potts | – | M+M |
| R7 | Moment-derived builtins with exact after-values (centroid, covariance, minor length, orientation, eccentricity); centroid allowed in energies; cluster moments | G2 | CorePotts + Potts | – | M |
| R8 | Site-ownership events: `@create`, `@convert`, `@retire … sites => ref`, scatter-add rules. One shared host "apply ownership delta" routine (trackers, links, cluster roots, integrals, mobility; fixed priority per MCS) | G1b, G7, G17 | CorePotts host + Potts | – | M–L |
| R9 | Relationship 3-body (angle) terms; several named relationships per model | G11 | Potts + CorePotts | – | M |
| R10 | `ProposalLaw` dispatch: `UniformNeighbor`, `UnlikeNeighbor`, `BoundarySite`; attempts counted over all sites; fractional attempts per MCS | G8b | CorePotts | – | M |
| R11 | `neighbors(c)` and `contact(c, n)` at MCS cadence; later, per-copy pair trackers with an `interfaces => E(a, b)` energy | G21a / G21b | Potts over `ContactPhase` / CorePotts | Graphs.jl only for analysis | S–M / L |
| R12 | `Pre(x, k)` on cell variables (rings grow with capacity, follow division) | G20 | CorePotts + Potts | – | M |
| R13 | Integer-indexed tables; Boolean networks | G9b | Potts | MTK discrete `Shift` systems; Catalyst → MTK (ODE or jump); JumpProcesses inside components (extensions) | S–M |
| R14 | Implicit and steady fields | G5b | extension | OrdinaryDiffEq IMEX/implicit (`Adaptive(KenCarp4(linsolve = KrylovJL_GMRES()))`); LinearSolve; SteadyStateDiffEq / NonlinearSolve | M–L |
| R15 | Per-cell host operator protocol (`CellOperator(f!; inputs, outputs, order, every)`); FBA; rim reductions; `uptake`/`secrete` sugar | G9c, G6, G19 | CorePotts + extension | COBREXA/JuMP (HiGHS, warm start, pFBA); Optimization.jl has no LP warm start | L |
| R16 | Analysis package: observables, fits, graph components, annealed-copy measurement | G12 | new `lib/PottsAnalysis` + extensions | NonlinearSolve least squares for fits; SciMLBase ensemble summaries | M |

**Dropped or narrowed:**
- G16 → R2.
- G17 → R8.
- G18 and G19 become conformance tests.
- G20 moves to R12, needed only for the multi-cell variant of model 14c.
- G3 becomes sugar.
- G11 is narrowed to 3-body terms.
- G15 fractional sweeps move to R10 (fractional attempts).
- G9 is needed only by 06 (Boolean networks) and 08 (LP).

**New gaps** that no G-row covers:
- a division plane from an expression or a discrete draw (FBCA);
- field writes at copy time (FBCA 08b nutrient displacement).

**Hand-rolled code:**
- Keep the explicit-stencil `FieldStep` and the fused fixed-step cell ODEs (GPU, Metal
  Float32, D-038). MethodOfLines compiles per grid point and cannot express masked, moving
  domains; it stays useful as a small-grid test oracle.
- Delegate only implicit and steady solves (R14).
- `@discrete_events` must lower to SciMLBase callbacks. `Every(n)` stays internal.
- Calibration (Zajac T/α, Jafari χ, foam γ₀) is tutorial-level: derivative-free
  Optimization.jl over ensembles, or NonlinearSolve bracketing. SciMLSensitivity does not
  fit, because acceptance is discontinuous (D-012).
- Time-varying inputs: DataInterpolations evaluated on the host into a model variable each
  MCS (not Metal-safe on the device).

## 4. Composability

**Checklist for every feature:**
- no required companion feature;
- no model-named context field;
- works on square, hex and 3D lattices, and with sequential and checkerboard sweeps;
- adds its reads to the footprint and claim set;
- is filtered by kind in the model's expression, not in the engine.

**Pairs that do not compose today, and the fix:**

| Pair | Fix |
|---|---|
| Cell references × checkerboard | Referenced cells join the claim set (as contact owners do, D-036). Sequential is the reference |
| Ownership events × division × relationships × clusters | One shared ownership-delta routine with a fixed event priority (remove > convert > transition > divide > create); also fixes A-17 |
| Moment after-values × clusters | Cluster moment trackers, committed atomically; `cluster_claims` on checkerboard |
| Host operators × GPU | Copy only the declared inputs and outputs, once per MCS (as lifecycle and `Adaptive` already do) |
| `ProposalLaw` × checkerboard | Draw among unlike neighbours locally; count all-site attempts |
| Cell division × cluster division | Mutually exclusive today (`compile.jl:236-238`) → resolve per rule domain |
| Relationship × relationship | One per model (`compile.jl:118`) → a link store and claim set per name |
| Components of different stiffness | One solver per model → solver metadata per equation or component |
| Lifecycle transitions × frozen kinds | Frozen mask computed once → recompute on events |
| Fields × contact energies | Contact terms cannot read site values → bind `x`/`x′` |
| Hex/3D × boundaries and connectivity | Dispatch R4 and R5 on the geometry |
| Retain-empty cells × extinction and id reuse | One `alive` definition |
| Lifecycle cadence | `Every(n)` per rule |

The cheap fixes go into step 0 (both division kinds, several relationships, per-equation
solvers, frozen-mask refresh, contact `x`/`x′`, per-rule cadence). The ownership-delta
routine lands with R8, claim widening with R6.

**Cross-model compositions the set enables (no new code):**
1. Merks length constraint + Akeeb clock division + FBCA per-cell FBA: metabolically
   limited elongating growth.
2. Act motility + Bauer 2009 ECM collectives with degradation + a soft `components`
   penalty.
3. Myxobacteria chains + contact inhibition (`contact(c, n)`) + a chemoattractant field.
4. Fortuna three-compartment cells + Merks autocrine chemotaxis + Akeeb leader–follower
   bonds, in 3D.
5. Jiang 2005 necrotic core (retire into a cell) + OpenVT growth + Jafari Boolean
   phenotypes.
6. Foam shear on `direction`/`time` + Graner–Glazier sorting + Zajac anisotropic adhesion.

**More composition gaps**, found by writing cross-model sketches (the reviewer's letters in
brackets):

| Gap | Why | Fix |
|---|---|---|
| Kind classes [j] | Gates like `old == 0` assume the matrix is the medium; in Bauer, fluid and matrix are cells | First-class kind sets (`@kinds` groups, `kind[x] ∈ ecm`) used in every gate |
| Ownership hooks [f] | `@convert`, divide, retire and create change ownership without firing `@on_copy` / `clear_on_ownership_change`, so site state such as `act` goes stale | Every ownership change fires the site hooks (part of R8's shared routine) |
| Scope across transitions [g] | Components and drives scoped to one kind are lost after `@transition` | Scope by kind set or predicate; component state survives transitions |
| Phase order [h] | The order between components, host operators (LP) and lifecycle rules is undefined | Explicit phase order (with R5 field placement) |
| Non-local reads [i] | Related centroids, BFS and pair energies silently break checkerboard exactness | A declared footprint: the compiler adds claims or rejects checkerboard with a clear error |
| Solvers [e] | One global `field_solver` | Solver per field or equation block (same fix as the stiffness row) |

**Too-narrow shapes to avoid:**
- `@convert` must take any `from`/`to` expressions, a predicate, a probability, a budget
  and field writes (not a matrix → fluid flag).
- "Tip / leading cell" is a population argmax of any cell expression.
- `sibling(kind)` must allow several members, so it is a `members(c, kind)` fold.
- Chain order is a mutable cell index, so a reversal clock can swap head and tail.
- A pair energy takes any function of both cells' tensors and interface aggregates.
- Uptake site sets are a site predicate relative to the cell.
- Boolean networks are MTK clocked/discrete components, not a new type (question 9).
- Per-MCS Bernoulli gates stay `rand() < p`. JumpProcesses is used only inside components.

## 5. Per-model compositions

All 12 are writable from existing primitives plus R-features, with no model-specific hook.
| Model | Needs beyond today | Blocked on authors |
|---|---|---|
| 01 Merks | R4 value (E₀ drive), R5 (absorbing frame each substep, field before the sweep), R2 Eden/Frame | L 50 vs 60; E₀; relaxation origin |
| 04 Foam | R10 boundary-only law, R16 T1/μ₂, R3 `@terminate`, R2 brick wall | shear form and γ₀; wall type |
| 05 Bauer 2009 | R4 `Global`, R5, R15 uptake, R3/R8 `@create`, R8 convert, R16, R2 | pixel size, neighbourhood, recruitment |
| 06 Jiang 2005 | R3, R8 retire-into, R5/R14 (implicit, moving Dirichlet; coarse grid Q5), R15 uptake, R10 fractional attempts, R13 | Rb→E2F; T, α, θ; 162 vs 216 |
| 07 Bauer 2007 | R5/R14 steady init and switchable BC, R15 uptake, R8 convert, R10 unlike-neighbour law, R2 | pixel size, neighbourhood |
| 08 FBCA | R15 FBA and sequential write-back, R3, R5 flux BC, R10 attempts, R16, R2; division plane by draw; copy-time field write | HMR CORE file, starvation rule, D values |
| 09 Sorting | R16 boundary decomposition and annealed copy, R2; Osborne via a frozen ring | engulfment wording |
| 10 Akeeb | R0 rename only, R16, R2 | none blocking |
| 11 Jafari | R3, R4, R5 EC clamp, R15 uptake, R16, R2 | χ values, CC3D project, rules |
| 12 Zajac | R7 tensor ΔH, R11b pair energy (exact), R10, R16, R2; lagged variant needs only R7 at cell scope | all parameters; the 57 % definition |
| 13 Myxobacteria | R9 3-body terms, R6 related centroids in drives, R7 unwrapped centroids, R16, R2 | θ normalisation, Eq 10 loser term |
| 14 Fortuna | R8 `@convert` + R6 (sibling, cluster fold, retain-empty), R16, R2, 3D | solver order C4, J_CL |

## 6. Guardrails (prototyped in /tmp on the current tree)

| Guardrail | Current tree | After the R0 renames |
|---|---|---|
| (a) ExplicitImports on PottsModels: public explicit imports, public qualified accesses, via owners, no stale imports | pass (implicit imports: 13 names) | pass; add explicit `using Potts: …` |
| (a′) ExplicitImports on Potts → CorePotts | 19 non-public names | ratchet with a shrinking `ignore` list as names become `public` |
| (b) Syntax-tree denylist of model/author names in `src/`, `lib/CorePotts/src`, `lib/MakiePotts/src` (comments and docstrings skipped; allowlist file) | 26 violations | 0 |
| (c) Each model builds in a bare module with only `using Potts`; model names absent from `names(Potts)`, `names(CorePotts)` and `keys(Potts.DSL)` | builds pass; namespaces fail on `act_*`, `merks_connectivity` | pass |
| (d) DSL surface snapshot: every DSL entry, its keywords and allowed Symbol values against a reviewed list | catches `extension_only` | – |
| (e) One sibling per model (`lib/PottsModels/test/siblings.jl`): another tool's variant of the defining mechanism, built from `using Potts`, with selfcheck and one qualitative check; a registry test requires an entry for every exported model | Act arithmetic mean passes; saturating chemotaxis passes; soft connectivity fails | acceptance test for R4 |

Placement:
- (b) and (c) go in `test/qa.jl`.
- (a), (d) and (e) go in `lib/PottsModels/test`.

## 7. Questions for the maintainer

1. **Fractional MCS.** Jiang 2005's ¼-MCS sweeps conflict with D-031 (1 MCS = N attempts).
   The options are fractional attempts per MCS (reopens D-031) or integer MCS with a
   recorded deviation (O₂ is quasi-static anyway).
2. **Global connectivity on the checkerboard.** BFS reads only the claimed cell's sites,
   so it is arguably exact, but it costs O(V) and diverges on the GPU. Allow it, or make
   it sequential-only?
3. **Non-symmetric proposal laws** break detailed balance. Match the papers only, or also
   offer an optional Hastings correction?
4. **Zajac exact default** needs per-copy pair trackers (L, sequential only in practice)
   for one weakly specified model. Build the lagged variant first for development,
   keeping exact as the reference?
5. **Coarse field grid** (Jiang 2005). Run at full resolution with a documented deviation
   (D-029), or build multigrid fields (L)?
6. **Explicit liveness** (separate from volume > 0) changes id reuse (D-035) and the
   empty-cell energy convention (D-037). Is that a new decision or an amendment?
7. **Cell references widen claim sets** and lower checkerboard parallelism. Confirm that
   sequential is the reference for every reference-reading energy (as Y2).
8. **Uptake operator split** once per MCS (exactly conservative, lags within the MCS) or
   inside substeps. Recommendation: per MCS.
9. **Boolean networks**: Potts cell updates with an expansion helper first, or MTK
   discrete (`Shift`) components (extends D-038)? Recommendation: the helper first.
10. **Float32 moment after-values** on Metal: accept statistical agreement (D-029)?
11. **Adopt the guardrails** (a)–(e) in the test suite now, together with the R0 renames?
12. **Analysis package**: a new `lib/PottsAnalysis`, or a module inside PottsModels or
    MakiePotts?
