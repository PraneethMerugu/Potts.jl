# Roadmap (machine-checkable)

Feature scope per milestone is extended by `research/legacy-spec-adjudication.md` §3 (the "Milestone" column) and AUTHORING.md §12 (Morpheus/CompuCell3D, D-032):

| AUTHORING §12 | Milestone |
|---|---|
| 12.1 energies/acceptance, 12.9 semantics | M2.1 |
| hexagonal geometry, irregular domains | M2.1b |
| 12.4 shape descriptors | M2.2 |
| 12.3 reductions, neighbor-cell iteration | M2.7 |
| 12.5 fields | M2.4 |
| 12.2 motility | M2.5 |
| 12.7 lifecycle | M2.8 |
| 12.6 kind-scoped dynamics, components | M4.1 |
| 12.8 initialization, PIFF, MorpheusML importer, steering | M2.1 (layouts), M4.4 (importers), M5.2a (steering) |

Each milestone: id, depends-on, deliverable, acceptance (commands that must exit 0 or
numbers that must hold). Tick with `[x] <commit> <date>` when merged.

## Phase 1 — Skeleton

- [x] 7b0a81b 2026-09-29 **M1.1** workspace skeleton — root `Project.toml` `[workspace]`, `lib/{CorePotts,LocalMath,MakiePotts,PottsModels}`, `[sources]`, `.gitignore` Manifest, `CLAUDE.md` (rules from INTERNALS §5), JuliaFormatter config.
  Accept: `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'` succeeds from a clean clone.
- [x] 7b0a81b 2026-09-29 **M1.2** LocalMath import (git subtree, history preserved) → `lib/LocalMath`; tests pass unchanged.
  Accept: `GROUP=LocalMath julia --project test/runtests.jl`.
- [x] **M1.3** (bd713f5) MakiePotts import → `lib/MakiePotts`; compiles (recipes may be stubbed against a temporary frame type until M2.10).
- [x] 7b0a81b b5bd201 2026-09-29 (`PottsParameters` moves to M3 with the compiler; native `exp` per D-029) **M1.4** CorePotts seed from FusedCPM: `CPMFunction`, `CPMProblem`, `PottsParameters`, `CPMState`, Philox4x32 (D-005), owned `exp` (D-006), `SequentialCPM`, `CheckerboardCPM` with footprint-derived stride (D-008), `PottsIntegrator <: DEIntegrator`, `PottsSolution`, status word.
  Accept: FusedCPM tests ported and green; `GROUP=Core`; JET `@test_opt init/step!` clean; AllocCheck warm `step!` = 0.
- [x] b5bd201 2026-09-29 (preflight so far covers footprint vs relation radius; extend per feature) **M1.4b** verification harness: exact transition-matrix oracle for tiny lattices (independent of production code; scheduler state lifted), TV-distance comparison; preflight rejection of unsupported algorithm × backend × feature combinations.
- [~] fe8a507 2026-09-29 (local parts done: benchmark suite, `reference/` env, Reference group; CI/Downgrade/docs deferred — GitHub is local-only per AUTONOMY §4) **M1.5** CI matrix (Core, QA, Reference), Downgrade job, docs build, AirspeedVelocity suite with Graner–Glazier; `reference/` environment (D-021) with the legacy models runnable.
  Accept: CI green on `monorepo`; `benchmark/` produces the table from `FusedCPM/README.md` numbers ± noise.

## Phase 2 — CorePotts engine (each with brute-force ΔH + seed determinism + statistical CPU/Metal parity)

- [x] 0864882 2026-09-29 (per-axis spacing moved to M2.2/M2.4 with its consumers; `Shell` is `NeighborOrder`) **M2.1** N-dimensional lattice with per-axis boundaries/spacing and neighborhoods of any order (`Moore(k)`, `VonNeumann(k)`, `Ball`, `Shell`, `Stencil`, weighted); contact + volume + surface energies; surface tracker; generic cell/site energy functions. Accept: oracle tests; Graner–Glazier reference parity (KS over 16 seeds).
- [x] 2026-09-29 (irregular domains; hexagonal geometry — MakiePotts hexagon glyphs pending) **M2.1b** hexagonal 2D geometry; irregular domains from masks/images/expressions (domain edge is a copy and field boundary).
- [x] 6e525c1 2026-09-29 (lattice units; spacing with M2.4) **M2.2** moments tracker (centroid, elongation, periodic-safe geometry); site sums and minima trackers; structured owner sums.
- [x] 6fd6998 2026-09-29 (phases are KA kernels per D-033) **M2.3** site/cell/medium/model state; history ring buffers; synchronous phase updates ~~via LocalMath stages~~ as generated KA kernels; accepted-copy affects; `ClearOnOwnershipChange`.
- [x] 8f0ac2d 2026-09-29 (Merks parity moves to M2.5: it needs chemotaxis) **M2.4** fields: explicit-rate discrete Euler stages, diffusion stencils, sub-stepping; `field_value`, gradient, laplacian primitives. Accept: Merks reference parity.
- [x] 785ef32 2026-09-29 (Merks + Wortel parity pass) **M2.5** drives: chemotaxis, Act with owner-filtered gathers and geometric-mean fold, generic `ProposalDrive`/`ProposalModifier`; authored draws inside updates and rates (stream assignment). Accept: Wortel reference parity.
- [x] 785ef32 2026-09-29 (RetireAtZero id reclamation lands with lifecycle M2.8) **M2.6** constraints: local connectivity, extinction policies, `ProposalConstraint`.
- [x] 48a43bc 2026-09-29 (contact graph is host-side; its device build is in M2.11) **M2.7** spatial queries and Cartesian ownership domains (fixed owners, immutable sites, per-face boundaries): neighbor counts, weighted contact measures, boundary-site queries, sums/means, predicate filters, interface queries.
- [x] 1c84438 2026-09-29 (D-035; seeding via host API and relationship consequences with M2.9) **M2.8** lifecycle: trigger/plan/apply; divide (principal major/minor, random plane, specified normal, external), remove, retire, create, transition; state rules; placement; conflicts; inadmissibility policies; capacity growth. Accept: OpenVT reference parity; ported CorePotts lifecycle scientific tests; invariants.
- [x] 69b0cfd 2026-09-29 (padded adjacency instead of CSR; directed/anchor links and link age via payloads) **M2.9** relationships: CSR store, energies, create/remove/retune, lifecycle interaction.
- [x] **M2.10** (bd713f5) checkpoint/continuation; `PottsSavedState` accessors; MakiePotts wired to real solutions. Accept: state round-trip exact; MakiePotts tests.
- [x] **M2.11** (f67f82c) Metal: all of the above in the GPU group; statistical parity with CPU. Accept: `GROUP=GPU` locally green.

- [x] **M2.10a** (cf898ab) compartments: compartment cells grouped under a parent; internal vs external contact energies; coordinated division.

## Phase 3 — Potts symbolic front end (spec: AUTHORING.md)

- [x] (units done; namespacing `compose` declined, D-039) **M3.1** `PottsSystem`, `@potts_model` sections and plain constructors, scoped `@variables`, `@kinds`, kind-indexed parameters, `Lattice`/relations of any order in N-D, source locations, composition (`compose/extend/flatten/@named`), units.
- [ ] (partial) **M3.2** `mtkcompile`: global-H → ΔH derivation with simplification and loop fusion (AUTHORING §4), generated `total_energy` self-check, validation, footprint analysis, CSE, scheduling; `CompiledPottsSystem`.
  Accept: `ΔH == H(after) − H(before)` on random flips for every model in `lib/PottsModels`.
- [x] 2026-09-29 (EnsembleProblem, callbacks, parity from lib/PottsModels sources; `eval_module` unnecessary: generated code interpolates function objects, user-registered functions tested) **M3.3** codegen → `CPMFunction`; `PottsProblem(sys, op, tspan)`; `PottsParameters`; SII; `remake`; `EnsembleProblem`; callbacks; `expression = Val(true)`; `eval_module`.
  Accept: every Phase 2 oracle test re-run through symbolic authoring; `remake` zero compile; Graner/Wortel/Merks/OpenVT from `lib/PottsModels` sources.
- [x] 2026-09-29 **M3.4** component imports (`@components`, D-038) and structural replacement (extend replaces updates/equations/observed by target), scoped quantities, vector quantities and vector parameters, symbolic setters, history lags `Pre(x, k)`, per-cell site reductions `integral(x)`, compound assignments with single-writer checks, diagnostics with statement + source line + remedy. (One-block declaration: the `@potts_model` block is the one declaration; plain constructors exist.)

## Phase 4 — Coupling and models

- [ ] (partial, D-038: MTK components as batched cell ODEs, Euler/RK4, CPU+Metal; model-scope ODEs and components; host adaptive/stiff integration via `Adaptive(alg)` done; DAE and MethodOfLines pending) **M4.1** `ODEComponent`/`DAEComponent` init-once integrators; batched per-cell ODEs; scheduling phases; `MethodOfLinesComponent`; Metal via `EnsembleGPUKernel`.
  Accept: Akeeb MTK-bridge targets bytewise vs discrete clock (as in `SCDPotts/research`).
- [ ] (started 2026-09-29: package + Graner–Glazier, Wortel Act, Merks, OpenVT with reference parity; Akeeb invasion ported, statistical parity vs SCDPotts pending) **M4.2** `lib/PottsModels`: Wortel, Merks, OpenVT, Graner–Glazier, Wortel-Act 150², Akeeb leader/follower; tutorials; tested in CI. The published-model subset (Graner–Glazier/Osborne sorting, Merks 2006/2008, Akeeb) follows `research/model-specs/README.md` (unified features G1–G21, per-model decisions §4) and ships one reproduction tutorial each per `research/model-specs/TUTORIAL_TEMPLATE.md`.
  Accept (D-048): per model, brute-force ΔH, independent drive/effect checks, invariants
  and mechanism tests with negative controls; TTFX table in docs.

- [ ] **M4.3** extended model library per `research/legacy-spec-adjudication.md` §3 "Models" (Mombach 3D, Shirinifard CNV, Wang 2025, OpenVT categories, Jiang 2005, Bauer 2007/2009, Zajac, Jafari Nivlouei, Starruß, Fortuna, Jiang 1999 foam, FBCA via COBREXA, hard-model set). Each: ordinary tests per D-048, plus the paper's qualitative results as mechanism tests.
  The 12 published models (Merks, Jiang 1999 foam, Bauer 2009, Jiang 2005, Bauer 2007, FBCA, sorting, Akeeb, item 11 = Jafari Nivlouei 2021, Zajac, Starruß, Fortuna/Thomas/Dal-Castel) are specified in `research/model-specs/` and built in the order of its README §6; each ships a reproduction tutorial per `research/model-specs/TUTORIAL_TEMPLATE.md` with ensemble validation against pre-registered tolerances.

- [ ] (PIFF done 2026-09-29; MorpheusML pending) **M4.4** importers: PIFF (import/export) and MorpheusML (EzXML.jl → Symbolics); run the importable part of the Morpheus model repository as a regression corpus.

## Phase 5 — Slim, docs, cut-over

- [x] ~~**M5.1** LocalMath slimming (INTERNALS §3); TTFX benchmark for 1/4/8/32-stage programs.~~ Withdrawn by D-040: `lib/LocalMath` removed from the monorepo.
- [ ] **M5.2** docs site (Learn / Published models / API per package). "Published models" renders the Literate reproduction tutorials `lib/PottsModels/reproductions/<nn>_<model>.jl` (structure: `research/model-specs/TUTORIAL_TEMPLATE.md`), one per published model.
- [ ] **M5.2a** MakiePotts: vector/arrow channels, relationship overlays, lineage, tensor ellipses, true-3D volume, WGLMakie, DataInspector, rerun controller.
- [ ] **M5.3** cut-over per AUTONOMY.md §5; registration; archive legacy repos; `PottsStudies` repo for SCD material.

## Phase 6 — Model families (D-051, D-053; run by the agent protocol, AUTONOMY §7)

Scope and order: `research/model-specs/README.md` §6 (the build sequence) and
`research/feature-roadmap-review.md` §3–§4 (R-features, composability). Each item lists
its dependencies, its write set, its acceptance and, where one applies, its **gate**: an
open maintainer or author question that parks the item until it is answered.

Every item's acceptance also includes the standing checks:
- all suites green (AUTONOMY §7.4);
- the performance gate passes;
- reviewer APPROVE;
- every new primitive is used by a sibling, and a new published model adds its sibling
  and gate case;
- no frozen file edited.

"Frozen:" names the files the coordinator commits first.

**Acceptance for model reproductions.** The file
`lib/PottsModels/test/reproductions/<nn>_<model>.jl` tests the spec's V-targets.
- The CI-sized subset runs in the suite; ensembles run under `REPRO=full`.
- Each quantitative target is an ensemble mean within the spec's tolerance.
- Each qualitative target has a negative control.
- A tutorial `lib/PottsModels/reproductions/<nn>_<model>.jl` (Literate,
  `TUTORIAL_TEMPLATE.md`) builds with its deviations table.

### Step 0 — composition fixes and infrastructure

- [x] (merge, 2026-09-30; gate CPU ≤ 1.013, Metal A/B = base) **P6.0a** division kinds per rule domain: cell division and cluster division in one
  model (lift `compile.jl` mutual exclusion).
  - Write set: `src/compile.jl`, `src/codegen.jl`, `lib/CorePotts/src/lifecycle.jl`.
  - Accept: a model with both kinds runs both; ΔH self-check; a sibling.
- [x] (merge, 2026-09-30; D-058) **P6.0b** several named relationships per model, each with its own link store and
  claim set. Depends: none. Accept: two relationships with different laws, checked by the
  springs oracle on each; checkerboard equals sequential statistically.
- [ ] **P6.0b2** P6.0b review follow-ups:
  - An extension that re-declares a base edge variable while adding its own single
    relationship re-binds it to the new relationship, which gives a confusing error. Keep
    the base's binding, or improve the message.
  - Edge-variable values in the operating point (`:rest => 9.0`) are accepted but ignored.
    Honour them in `_initial_state` or reject them. This predates P6.0b.
- [x] (merge, 2026-09-30; A/B akeeb 0.993) **P6.0b3** Find the ≈ 3 % Metal cost that P6.0b added to akeeb_99x60, a model with
  no relationships (A/B 1.031, consistent). The no-reads path is meant to be free. Accept:
  A/B ≤ 1.01 against 5258ab9.
- [x] (merge, 2026-09-30) **P6.0b4** a permanent Metal (Float32) test of a model with reads in
  `lib/CorePotts/test/gpu.jl` (the P6.0b3 reviewer used a scratch version,
  `/tmp/rv-p6-0b3-metal.jl`).
- [ ] **P6.0c** (D-075) solver placement. `field_solver` (required when the model has a
  field), `ode_solver` and a symbolic-keyed `solvers = [V => …]` map become **`PottsProblem`
  construction keywords**. They are compiled at the existing codegen point and removed from
  `@sweep`; there are no algorithm fields. `Adaptive(alg; abstol, reltol)` stays as the
  bundle, and `ExplicitEuler(; substeps, lower)` keeps `lower`. `track` is a construction
  keyword too.
  - Accept: a stiff component (`Adaptive(Rodas5P())`) beside an explicit field in one
    model; conformance against each solver alone.
  - Accept: every `PottsProblem(MerksVasculogenesis(…), …)` call passes
    `field_solver = ExplicitEuler(substeps = 2, lower = 0.0)` explicitly
    (`benchmark/gate.jl:29`, `mechanisms.jl:324-348`, the tutorials). The Merks mechanism
    tests and the `merks_100` gate case are unchanged in result, and a bare call is a
    construction error.
  - Accept: the D-016 fingerprint hashes a **canonical string of the solver spec**, not the
    host objects (the `Adaptive` objects are not in the code strings). A checkpoint from
    before the change, or from a differently discretised problem, fails the check.
  - Accept: `remake(prob; field_solver/ode_solver/solvers/track = …)` goes through a
    Potts-side rebuild hook. CorePotts `remake` accepts only fixed keywords
    (`problem.jl:72-73`) today.
    - The hook rebuilds `f` and keeps `u0`, `p` and the RNG key.
    - Changing `track` re-lays out the state.
    - Measure and document the cost: full codegen plus JIT, in seconds, with identical
      specs reusing the compiled RGF specialisations.
    - Test that `remake(prob; p/u0/seed)` never regenerates.
  - Accept: CorePotts' ensemble `__solve(::AbstractEnsembleProblem, ::AbstractPottsAlgorithm)`
    (Threads on CPU, Serial otherwise) forwards `backend` explicitly to the three-argument
    call, and `detect_ambiguities` stays clean (verified at the pinned versions in
    `/tmp/apirev/ens3.jl`).
- [ ] **P6.0d** frozen-kind mask recomputed on lifecycle events. Accept: a kind that
  becomes frozen after a transition stops moving; the negative control moves.
- [x] (merge, 2026-09-30; D-061) **P6.0e** contact energies read site values (`x`, `x′`). Accept: brute-force ΔH on a
  contact term that reads a site field.
- [x] (merge, 2026-09-30; D-070; gate CPU ≤ 1.037, Metal A/B 0.96–1.02) **P6.0f** `Every(n)` per lifecycle rule. Accept: two rules at different cadences fire
  at their counts.
- [ ] **P6.0g** kind classes. `@kinds` groups; `kind[x] ∈ group` in every gate; `cells(group)`.
  Accept: a Bauer-style model where the matrix is a cell kind uses class gates; the
  denylist and DSL snapshots are updated with the reviewer's justification.
- [x] (merge, 2026-09-30; docs build ≈ 2 min) **P6.0h** Literate + Documenter "Published models" pipeline; `TUTORIAL_TEMPLATE.md`
  rendered for Graner–Glazier as the pilot. Accept: `julia --project=docs docs/make.jl`
  builds offline.
- [x] (merge, 2026-09-30; D-064) **P6.0j** ExplicitImports checks for Potts, CorePotts and MakiePotts, as the
  CLAUDE.md code rules require. Only PottsModels is checked today (found during P6.1a).
  - Accept: `check_no_implicit_imports`, `check_all_explicit_imports_are_public` (with a
    reviewed allowlist), `check_no_stale_explicit_imports` and
    `check_all_qualified_accesses_via_owners` pass in each package's QA.
  - Negative control: a deliberate implicit import fails the check.
- [x] (merge, 2026-09-30; D-077) **P6.0k** MTK discrete-component spike (D-065 Q9, unparked 2026-09-30). A per-cell
  MTK clocked component (`Shift`, a Boolean update rule) lowered into the per-cell phases.
  - Accept: a 3-node Boolean network per cell matches a hand-written truth-table
    reference, under both algorithms and on Metal.
  - Accept: zero warm allocations.
  - Every part of MTK's discrete support that is not usable yet is recorded in DECISIONS
    with its workaround.
- [ ] **P6.0k2** P6.0k round-3 follow-ups (D-077):
  - F1: `Pre(grn.x)[j]` and `Pre(grn.x[j])` on a discrete node fail with "cannot index" (`lower.jl:236-241`). Support them, since they equal `x[j]` inside a tick, or give a clear message.
  - F4: `_compile_discrete`'s catch still relabels internal Potts `MethodError`/`BoundsError` as "ModelingToolkit cannot compile" (`components.jl:258-263`).
  - F6: the generated code has a cosmetic `_nonzero(_nonzero(…))`.
  - F7 (MTK-native review, `/tmp/mtknative-review.md` r8): `@components` silently ignores a component System's `initialization_eqs`, `discrete_events`, `continuous_events`, `jumps` and bindings that touch a coupled parameter. For example, `z ~ 5y` is ignored and gives `c₊z_c = 0.0`. Reject each with an ArgumentError that names it.
    - Accept: one negative test per case.
    - Accept: generated code and fingerprints for existing models are byte-identical.
    - Accept: build time and first MCS are unchanged within noise.
- [ ] **P6.0n** Cell ODEs that read another cell's ODE state are Gauss–Seidel across cells and race on the GPU (P6.0k review N3). Use the P6.0k scratch rule. Accept: a two-cell ODE coupling that is order-independent on both algorithms and on Metal.
- [ ] **P6.0o** (D-075 §0.1, maintainer-approved 2026-09-30; MTK-native review, `research/mtk-native-review.md`) `PottsSystem <: ModelingToolkitBase.AbstractSystem`. Land it before P6.4a. MTK's `getproperty(::AbstractSystem)` takes over field access, so the ≈281 internal `sys.<field>` reads must change.
  - Accept: `PottsSystem` mirrors the `System` field names read by the MTK accessors it supports. It has an all-fields constructor taking `checks`, sets `namespacing`, and defines Potts-owned `complete`, `extend` and `show`.
  - Accept: every internal `sys.<field>` read uses `getfield` or an accessor. `sys.x` returns the namespaced symbolic, as in MTK.
  - Accept: `equations`, `unknowns`, `parameters`, `observed`, `nameof`, `getmetadata` and `setmetadata` each return a documented value or throw a clear error, never a silently partial view.
  - Accept: `compose` (D-039), `ODEProblem`/`JumpProblem`, and `extend` with a plain `System` throw clear errors.
  - Accept: Aqua (ambiguities, piracy), JET and ExplicitImports are clean.
  - Accept: every PottsModels model and test fixture generates byte-identical code with the same fingerprint.
  - Latency: `@potts_model` construction, `mtkcompile` and `PottsProblem` build time each within +5 % of the pre-change baseline on the five gate models.
  - Latency: fresh-process time to first MCS (`benchmark/graner.jl`, D-047 target under 15 s) within +5 %.
  - Latency: the warm-MCS gate is unchanged.
- [ ] **P6.0l** Links to a copy-killed cell (found by the P6.5a0 review, confirmed). When a
  linked cell loses its last site through copies, its centroid is 0/0. `link_delta` is then
  NaN, `accept` rejects every copy touching the partner so it freezes silently, and
  `total_energy` is NaN. Links are dropped only on `EVENT_REMOVE` (`lifecycle.jl:358`).
  - Accept: a regression test where two linked cells lose one partner through copies; the
    survivor keeps moving, with finite ΔH and a finite total H.
  - Accept: the link is dropped at a named boundary, per the D-066 liveness decision, or
    skipped while the partner has zero volume.
- [x] (merge, 2026-09-30; D-067) **P6.0i2** author-letter pre-send checks (D-065): fetch the openly available sources,
  settle the HOLD questions, and list what could not be obtained for the maintainer.
- [x] **P6.0i** author question batch 1, drafted for the maintainer to send (model-specs
  README §5). Accept: the drafts exist in `research/author-questions/`; this is not a
  send.

### Step 1 — Sorting (GG + Osborne CP), pilot reproduction

- [x] (merge, 2026-09-30; D-056, D-057) **P6.1a** R2 first slice: `Tiling`, `Scatter`, `Frame`, with an overlay algebra;
  the output is an SII operating point. Accept: layouts round-trip through `PottsProblem`;
  3D and hex tilings.
- [x] (merge, 2026-09-30) **P6.1a3** P6.1a review nits:
  - on periodic axes, clamp the grown box side to `min(s + gap, n)` in the Scattered area
    bound (it now rejects feasible requests when gap ≥ n − s);
  - warm the 300² split-timing test;
  - optionally, dense per-cell buffers in the split bucketing.
- [x] (merge, 2026-09-30) **P6.1a4** `_warn_split` allocates its `Int32` visited array lazily, only when a cell
  needs a flood fill (it is 32 MB at 200³ today).
- [x] (merge, 2026-09-30) **P6.1a2** `Frame` on a masked lattice paints the domain boundary (P6.1a review).
  Today a frame on a lattice with a domain always throws.
- [ ] **P6.1a5** Move `VoronoiBall` (added to PottsModels in P6.1b2) into `src/layouts.jl` as
  a core layout, next to the planned `Spheres`. It needs a DSL and export review, and moves
  the StableRNGs dependency to Potts only.
- [ ] **P6.0e2** Using `m′` for a cell variable `m` gives a bare UndefVarError. Emit a Potts
  error ("primes exist only for site/field variables"). Also check programmatically built
  `PottsSystem`s for declarations named `x′`.
- [ ] **P6.1b** R16 analysis in the docs: boundary-length decomposition, annealed-copy
  measurement (D-051 item 6: in Potts.jl's docs unless a composable package is merited).
- [x] (merge, 2026-09-30) **P6.0a2** capacity-limited mixed-division test in `lib/CorePotts/test/compartments.jl` (P6.0a review nit 2).
- [x] (merge, 2026-09-30; D-059, D-060, D-063) **P6.1b2** follow-ups from the P6.0h review:
  - `graner_glazier_state` gains a paper-size single-aggregate generator (≈ 1000 cells),
    so the FULL run can test the size-driven targets.
  - `papers.jl` anneals each regime with that run's own J and T. The frozen file is edited
    under a DECISIONS entry. The reviewer measured a bias of 0.005–0.01 toward the effect.
  - The public-names guardrail (`guardrails.jl`) is extended to `lib/PottsModels/reproductions/`.
- [x] (merge, 2026-09-30) **P6.0h2** P6.0h review nits for the 09 tutorial:
  - "consistent with the medium share" instead of "which passes";
  - a caveat on the time-dependence and uncertainty of `PAPER_MEDIUM`;
  - a plateau criterion that also checks the slope over the last decade;
  - hide the diagnosis helper code (`#hide`).
- [x] (merge + freeze, 2026-09-30; D-072) **P6.1c** reproduction 09 (V-target audit done 2026-09-30: freeze from spec 09 §9.1 only; the tutorial prose was ratified with 8 changes). Reproduction 09. Frozen: `reproductions/09_cell_sorting.jl` from 09 §5.
  **Gate:** S1 provenance flag.

- [ ] **P6.1d** Run reproduction 09 in FULL on an idle machine: `POTTS_FULL_REPRODUCTION=true`, 1000 cells
  per replicate, about 25–40 CPU-min each. Record the verdict table in PROGRESS and send it to the spec
  owner. There is no code change: the page is frozen (D-072).
- [x] (merge, 2026-09-30; D-076) **P6.0m** Confirmed small defects, found in the API-synthesis review and verified by
  script:
  - `Chemotaxis` forces `new != 0` (`src/vocabulary.jl:636`), so a retraction drive reads 0.
  - `connectivity(k)` accepts 0 components: a copy into an isolated fragment or into a
    cell's last pixel is allowed. Fix it to match CC3D's `!= 1` rule (D-074, maintainer), and
    revalidate the frozen Akeeb tests.
  - `a` and `b` are not reserved: a parameter `b` is shadowed by the edge endpoint inside
    edge terms.
  - `integral` reads the previous MCS's site values when they are written in the same
    `@after_mcs`. Document the ordering, or fix it.
- [ ] **P6.0m3** `s ~ integral(Pre(w))` in `@after_mcs` fails with `FieldError: no field
  integral_…` (pre-existing on 8b14051; found by the P6.0m reviewer, `/tmp/p60m/rv1/probe_pre.jl`).
  The start-of-after integral refresh also runs before the Pre-snapshot `CopyPhase`.
  - Accept: an integral of a `Pre` operand reads the pre-MCS values.
  - Accept: a regression test covering both orders.
- [x] (merge, 2026-09-30) **P6.0m2** (D-075, breaking batch part 1) `CPMProblem → PottsProblem`, supertype
  unchanged, no alias; `SciMLBase.isdiscrete(::AbstractPottsAlgorithm) = true`. Every
  package, test, benchmark and tutorial is updated in the same change. Accept: all suites
  pass, the gate is unchanged, and no `CPMProblem` remains outside DECISIONS and PROGRESS.
- [ ] **P6.2a2** Refactor `akeeb_state` onto `InsertUntil` (`misses = :count`, `fraction = 1//4`)
  and expose the counted inventory (spec 10 V-A1(a)). This changes the RNG stream from
  MersenneTwister to StableRNG, so the frozen `papers.jl` band must be revalidated.
  StableRNG only (D-075): the `clock`/`cue` expression defaults move to P6.4a.

### Step 2 — Akeeb

- [x] (merge, 2026-09-30; D-073) **P6.2a** R2 `InsertUntil` (general "repeat until ratio" placement; refactor P6.2c's
  seeding onto it, with a counted-miss option); R16 code-definition metrics (per-column
  areas, the `find_peaks` port per D-069, BFS clusters).
- [x] (merge, 2026-09-30; D-068, D-071) **P6.2c** Akeeb seeding per D-068 (MD-1).
  - Default: emulate the authors' ghost leaders; keyword variant: retry.
  - Re-baseline the frozen `papers.jl` Akeeb testset (ensemble band; μ = 24) and the gate's Akeeb case.
- [ ] **P6.2b** (V-target audit done 2026-09-30: freeze from spec 10 §5.3, with 12 READY rows and 3 PARKED; SciPy 1.7 `find_peaks` finger detection is exact against stored outputs; do not reuse `akeeb_metrics.jl`). Reproduction 10 against the authors' 13,310-run data (10 §5).
  Frozen: `reproductions/10_akeeb.jl`. **Gate:** A5 default μ (D-050: μ = 24, pending
  confirmation).

### Step 3 — Merks 2006 + 2008

- [ ] **P6.3a** R4 topology values dispatched on geometry; the soft E₀ drive; `Global()`
  placeholder. Accept: the soft-connectivity sibling; hex and 3D ring tests.
  - D-075: `track = (:ΔH,)` → `stats.accepted_ΔH` (01 F9); `nothing` when off, and the
    A/B is unchanged.
  - Accept: sequential `track` needs a CorePotts hook, so the generated accumulator sees
    `dH` inside `sequential_mcs!`. This changes the CPMFunction signature.
  - Accept: on the checkerboard (§2.13), propose writes ΔH, and likewise `count`, to
    **per-colour scratch**. Commit adds it to the lattice-indexed accumulator only if the
    copy won, so earlier sub-cycles are never zeroed.
  - Accept: the per-MCS reduction into a host `Float64` is a device sync. Either reduce
    only at save points, or state and measure the per-MCS sync on Metal.
- [ ] **P6.3b** R5 `@boundary` per face with a masked clamp every substep; field phase
  placement and an explicit phase order. The phase order **is** `@schedule`, with the
  `step!` restructuring of api-synthesis §2.12; D-035 is amended (D-075) in the same change.
  - Accept: the gate is unchanged on CPU, and the Metal A/B is ≤ 1.01 for the five gate
    models.
  - Accept: the absorbing frame keeps c = 0 on the ring after every substep.
  - Accept: PDE-before-sweep ordering is observable in a two-phase test.
- [ ] **P6.3c** R2 `Eden` + splits.
- [ ] **P6.3d** Merks split into `Merks2006` and `Merks2008` per D-050 M1–M11: the frame,
  15 FTCS substeps, relaxation and `mode = :extension_retraction`. Frozen:
  `reproductions/01_merks.jl` (V-E1…, V-C1…). **Gate:** M1–M7 sign-off (approved, D-050);
  L 50 vs 60 remains an author question.

### Step 4 — Foam

- [ ] **P6.4a** R1: copy-scope `direction`, `time`, `mcs`; `Metropolis(tie)`.
  - D-075: **R17** initialization, as the `at_init` host phase: `A(cell) = volume`,
    `remake(u0 = sol[end])`, and `at_init` re-run on `remake(p = …)`.
  - D-075: the small folds (`argmax`/`only`/`var`, `init`/`default`, `Pre(neighbors(c))`)
    and the §2.6 energy ban.
  - D-075: Akeeb `cue`/`clock` become expression defaults from `Potts.init.<var>`
    streams. They get their own `papers.jl` re-baseline.
- [ ] **P6.4b** R10: `ProposalLaw` (`UniformNeighbor`, `UnlikeNeighbor`, `BoundarySite`);
  all-site attempt counting; fractional attempts per MCS at zero cost when unused (D-051
  item 2). Hastings acceptance (D-052).
  - Accept: the enumeration oracle for `MetropolisHastings()`.
  - Accept: the performance gate is unchanged for the default law.
  - D-075: the checkerboard thinning form (stream `CorePotts.thinning`); a sub-cycle index
    in `draw`/`_color_order!` for `attempts > 1`, bit-identical at 1; `@sweep
    MetropolisHastings` is an error.
- [ ] **P6.4c** R3: `@retire`, `@transition`, `rand(dist)`, `hazard`, `@discrete_events` →
  SciMLBase callbacks, `@terminate`.
- [ ] **P6.4d** R2 `BrickWall`; R16 T1 counts, topology moments.
- [ ] **P6.4e** reproduction 04. **Gate:** F1 (the shear form, γ₀); ships as provisional.

### Step 5 — Fortuna (14a/14b), 3D

- [x] (merge, 2026-09-30; D-066) **P6.5a0** Liveness survey (D-065 Q6): CompuCell3D, Morpheus and Artistoo death,
  id reuse and exclusion semantics. The output is `research/liveness-survey.md` and a
  decision amending D-035/D-037, with performance deviations recorded.
- [ ] **P6.5a** R6: cell references (`sibling`, `members`, `root`, `partner`, `x[ref]`);
  liveness per D-066 (alive ⇔ volume > 0; `birth` serial; `CellRef` references cleared
  at allocation boundaries; exact self-check credits); claim widening, with checkerboard validated
  statistically against sequential (D-065 Q7).
- [ ] **P6.5b** R8: the shared ownership-delta routine (priority remove > convert >
  transition > divide > create); `@convert` (block form with `Fresh`, `created`,
  `budget`, each one a named `@schedule` phase costed per D-035 as amended by D-075);
  ownership hooks apply `clear_on_ownership_change`, and `@on_copy` never fires from the
  lifecycle (D-075 clarify). Fixes A-17.
- [ ] **P6.5c** R2 `Plane`, `Spheres`; R5 predicate-sourced PDE; R16 MSD / Fürth fits.
- [ ] **P6.5d** reproduction 14a/14b. **Gate:** C4 blocks the quantitative S/P/D targets.

### Steps 6–12

These are listed so that dependencies are visible. They are expanded into items when step 5
merges (phase-end checkpoint).

- **P6.6** myxobacteria:
  - R9 3-body terms and ordered chains;
  - R7 unwrapped centroids and cluster moments;
  - related centroids with declared footprints;
  - R2 `Chains`;
  - D-075: `ordered = true`, `prev`/`next`/`rank`/`linked`, `angles(rel)` energies. Gate: Y1, Y2.
- **P6.7** Zajac:
  - R7 tensor ΔH;
  - R11a `neighbors`/`contact`;
  - R11b exact pair trackers (D-051 item 3);
  - D-075: `interfaces(k, k)` sequential-exact first; the checkerboard form behind an A/B,
    or a time-boxed D-051 item 5 exception; `count = true`;
  - the 12a Eq 7 unit test. Labelled as a reconstruction.
- **P6.7b** the 14c chemotaxis variant: R12 `Pre(x, k)` on cell variables.
- **P6.8** Bauer 2007:
  - R3 symbolic `@transition` with scope that survives it;
  - R14 steady init (SteadyStateDiffEq / NonlinearSolve);
  - R15 `CellOperator` and `uptake` (once per MCS, D-065 Q8);
  - R10 `UnlikeNeighbor`;
  - R2 `Fibres`;
  - D-075: `uptake` is one host round trip per MCS on Metal (D-035 as amended);
    `solvers = [V => …]` for the steady/implicit field. Gate: B2.
- **P6.9** Bauer 2009:
  - R4 `Global()` on both algorithms, with the D-075 device BFS (api-synthesis §8.1 Q6):
    - a deferred kernel over the compacted list of local-test failures, with an
      `MVector` stack and an AllocCheck proof on the CPU path;
    - the deferred kernel also raises the claims, so commit runs unchanged;
    - `window` on `components`/`Global()`, and a conservative-rejection counter;
    - state the extra launches: 4 per MCS in 2D;
    - a late-state benchmark via `benchmark/ab.jl`;
    - record `exp(−α/T)` for 05 and 11. Where it fails, widen `W` or fall back to
      sequential; that fallback is a D-051 item 5 exception under D-075's time-boxed row;
  - R8 `@create`;
  - R16 branch and loop detection. Gate: B2.
- **P6.10** Jafari Nivlouei:
  - R13 tables;
  - Boolean networks as MTK discrete (clocked, `Shift`) components lowered into the
    per-cell phases (D-065 Q9: no Potts helper; record MTK gaps and workarounds);
  - two periodic PDEs with EC clamps;
  - D-075: `directed = true`, `links(c, rel)`, integer-indexed tables;
  - the Andasari ODE conformance test. Gate: N1–N3.
- **P6.11** Jiang 2005:
  - 3D;
  - fractional attempts;
  - coarse field grids (D-051 item 4);
  - R14 implicit transient;
  - `@retire … sites => ref`;
  - D-075: `Coarse(k; clamp = All())` default, with T10 run under `Any()` and `All()`. Gate: J3.
- **P6.12** FBCA (X5 settled by D-067: published `mmc1.xls`, flagged):
  - R15 FBA `CellOperator` (COBREXA/JuMP extension, warm start);
  - the Eq 6 averaging operator;
  - division plane by draw;
  - copy-time field writes: the `@on_copy` neighbour-target form, sequential first with the
    08b conservation test. The checkerboard form (write footprint, 4 → 9 colours) is a
    second item with an A/B. Until it lands, `CheckerboardCPM` rejects the model
    (D-075). Gate: X5.
