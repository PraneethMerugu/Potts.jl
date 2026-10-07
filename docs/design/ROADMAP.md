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

**Gates and compute (D-155–D-157, 2026-10-06).**
- A "Gate:" below never parks an item. Under an open author question the model ships provisional, with a labelled default in its deviations table (D-154).
- Heavy compute runs on the PC (D-157). Metal verification is deferred to P6.0bi.
- Any change that brings major MTK friction or a major slowdown stops for the maintainer (D-156).

**Acceptance for model reproductions.** The file
`lib/PottsModels/test/reproductions/<nn>_<model>.jl` tests the spec's V-targets.
- The CI-sized subset runs in the suite; ensembles run under `REPRO=full`.
- Each quantitative target is an ensemble mean within the spec's tolerance.
- Each qualitative target has a negative control.
- A tutorial `lib/PottsModels/reproductions/<nn>_<model>.jl` (Literate,
  `TUTORIAL_TEMPLATE.md`) builds with its deviations table.

### Step 0 — composition fixes and infrastructure

**Frozen (maintainer, 2026-10-04, D-134).** No new P6.0 rows. In flight and finishing: P6.0c2, P6.0u, P6.0ax. Then P6.0g, then P6.0o; after those two, the paper reproductions (Step 1 on) start. Fingerprint corner cases go to P6.0z or are dropped as best-effort (P6.0az folded into P6.0z). Deferred until after the reproductions start, not blocking them: P6.0ac, P6.0ba, P6.0v4, P6.0v5; P6.0ae is settled inside the Merks reproduction (Step 3). P6.0z runs after P6.0o and does not block Step 1.

- [x] (merge, 2026-09-30; gate CPU ≤ 1.013, Metal A/B = base) **P6.0a** division kinds per rule domain: cell division and cluster division in one
  model (lift `compile.jl` mutual exclusion).
  - Write set: `src/compile.jl`, `src/codegen.jl`, `lib/CorePotts/src/lifecycle.jl`.
  - Accept: a model with both kinds runs both; ΔH self-check; a sibling.
- [x] (merge, 2026-09-30; D-058) **P6.0b** several named relationships per model, each with its own link store and
  claim set. Depends: none. Accept: two relationships with different laws, checked by the
  springs oracle on each; checkerboard equals sequential statistically.
- [x] (merge, 2026-10-04; D-127) **P6.0b2** P6.0b review follow-ups:
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
- [x] (merge, 2026-10-01; D-078) **P6.0c** (D-075) solver placement. `field_solver` (required when the model has a
  field), `ode_solver` and a symbolic-keyed `solvers = [V => …]` map become **`PottsProblem`
  construction keywords**. They are compiled at the existing codegen point and removed from
  `@sweep`; there are no algorithm fields. `Adaptive(alg; abstol, reltol)` stays as the
  bundle, and `ExplicitEuler(; substeps, lower)` keeps `lower`. `track` moved to P6.3a
  (D-078); the `remake` re-layout for `track` lands there.
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
- [x] (merge, 2026-10-01; D-081) **P6.0d** frozen-kind mask recomputed on lifecycle events. Accept: a kind that
  becomes frozen after a transition stops moving; the negative control moves.
- [x] (merge, 2026-09-30; D-061) **P6.0e** contact energies read site values (`x`, `x′`). Accept: brute-force ΔH on a
  contact term that reads a site field.
- [x] (merge, 2026-09-30; D-070; gate CPU ≤ 1.037, Metal A/B 0.96–1.02) **P6.0f** `Every(n)` per lifecycle rule. Accept: two rules at different cadences fire
  at their counts.
- [x] **P6.0g** kind classes. `@kinds` groups; `kind[x] ∈ group` in every gate; `cells(group)`.
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
- [x] (merge, 2026-10-01; D-084) **P6.0k2** P6.0k round-3 follow-ups (D-077):
  - F1: `Pre(grn.x)[j]` and `Pre(grn.x[j])` on a discrete node fail with "cannot index" (`lower.jl:236-241`). Support them, since they equal `x[j]` inside a tick, or give a clear message.
  - F4: `_compile_discrete`'s catch still relabels internal Potts `MethodError`/`BoundsError` as "ModelingToolkit cannot compile" (`components.jl:258-263`).
  - F6: the generated code has a cosmetic `_nonzero(_nonzero(…))`.
  - F7 (MTK-native review, `/tmp/mtknative-review.md` r8): `@components` silently ignores a component System's `initialization_eqs`, `discrete_events`, `continuous_events`, `jumps` and bindings that touch a coupled parameter. For example, `z ~ 5y` is ignored and gives `c₊z_c = 0.0`. Reject each with an ArgumentError that names it.
    - Accept: one negative test per case.
    - Accept: generated code and fingerprints for existing models are byte-identical.
    - Accept: build time and first MCS are unchanged within noise.
- [x] (merge, 2026-10-01; D-086) **P6.0n** Cell ODEs that read another cell's ODE state (P6.0k review N3). As found by the P6.0n test author: `y[j]` on a variable of the same solver group does not compile today (`cannot index __y1`, `_substitute_locals`), and only unhoisted population folds (those reading `time`) are Gauss–Seidel and order-dependent. Use the P6.0k scratch rule. Accept: a two-cell ODE coupling that is order-independent on both algorithms and on Metal.
- [x] **P6.0o** (D-075 §0.1, maintainer-approved 2026-09-30; MTK-native review, `research/mtk-native-review.md`) `PottsSystem <: ModelingToolkitBase.AbstractSystem`. Land it before P6.4a. MTK's `getproperty(::AbstractSystem)` takes over field access, so the ≈281 internal `sys.<field>` reads must change.
  - Accept: `PottsSystem` mirrors the `System` field names read by the MTK accessors it supports. It has an all-fields constructor taking `checks`, sets `namespacing`, and defines Potts-owned `complete`, `extend` and `show`.
  - Accept: every internal `sys.<field>` read uses `getfield` or an accessor. `sys.x` returns the namespaced symbolic, as in MTK.
  - Accept: `equations`, `unknowns`, `parameters`, `observed`, `nameof`, `getmetadata` and `setmetadata` each return a documented value or throw a clear error, never a silently partial view.
  - Accept: `compose` (D-039), `ODEProblem`/`JumpProblem`, and `extend` with a plain `System` throw clear errors.
  - Accept: Aqua (ambiguities, piracy), JET and ExplicitImports are clean.
  - Accept: every PottsModels model and test fixture generates byte-identical code with the same fingerprint.
  - Latency: `@potts_model` construction, `mtkcompile` and `PottsProblem` build time each within +5 % of the pre-change baseline on the five gate models.
  - Latency: fresh-process time to first MCS (`benchmark/graner.jl`, D-047 target under 15 s) within +5 %.
  - Latency: the warm-MCS gate is unchanged.
- [x] (merge, 2026-10-04; D-130) **P6.0c2** P6.0c round-3 follow-ups (D-078):
  - Document the after-MCS phase order in AUTHORING §6 and INTERNALS §1.6: updates, then field steps, then cell ODEs, then model ODEs, then discrete ticks, then links.
  - `_canonical_value` prints only the type below depth 8, so two `Adaptive` solvers that differ deeper would share a group and a fingerprint. Error at the cap, or group by `isequal` within equal strings.
  - `_check_internal_suffix` misses component unknowns (`comp₊x__ode`), `:vector` option names and observed names.
  - Closure canonical strings embed the closure type name (`#12#13`). This is conservative, but makes fingerprints session-dependent for closure-carrying kwargs.
  - Add a script that compares fingerprints across a `git archive` copy (as the coordinator did at merge).
- [x] (merge, 2026-10-01; D-079) **P6.0l** Links to a copy-killed cell (found by the P6.5a0 review, confirmed). When a
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
- [x] (merge, 2026-10-03; D-118) **P6.0p** D-016 gap: the fingerprint ignores the discrete tick cadence (found by the P6.0k2 test author). The P6.0k fixture with `Clock(2.0)` fingerprints the same as with `ShiftIndex(t, 0)`, so a checkpoint loads into a problem with a different schedule. Hash the resolved cadence (every/offset of each `_Gated` phase, or the clock spec).
  - Accept: two problems that differ only in a clock's period or phase have different fingerprints, and a checkpoint of one fails to load into the other with an `ArgumentError`.
  - Accept: fingerprints of models without clocked components are unchanged.
- [x] (merge, 2026-10-03; D-119; already fixed by D-103/D-104, regression guard added) **P6.0q** An unhoisted population fold that reads `time` inside a cell ODE fails to compile for Metal (`InvalidIRError`, `jl_new_opaque_closure_jlcall`), with or without the P6.0n fix. Found by the P6.0n test author. A fold that reads `mcs` is hoisted and runs on Metal.
  - Accept: the P6.0n fold fixture runs on Metal and matches the CPU in Float32.
- [x] (merge, 2026-10-01; D-083, maintainer) **P6.0r** D-066 item 4 (from the P6.0l review).
  - `total_energy` sums cell and cluster terms over alive cells only, and the killing copy's ΔH removes the dying cell's edges; no edge credit (D-083).
  - The self-check helpers get the same credit: `selfcheck` in `lib/PottsModels/test/runtests.jl:7-25`, `test/symbolic.jl:141` and `test/audit.jl:473`.
  - Add a Metal test in which the partner is killed during the run (`lib/CorePotts/test/gpu.jl:264-293` only has a partner that is dead from the start).
  - Accept: for every copy, including a killing copy, ΔH equals the H difference on a linked model.
- [x] **P6.0s** Fair machine lock (tooling; found 2026-10-01). (merge, 2026-10-01; D-090)
  - `benchmark/ab.jl` takes `tools/exclusive.sh` per process and re-takes it at once, so a waiter polling every 20 s starved for the whole A/B (a P6.0n Metal suite waited about 40 minutes).
  - Fix: `ab.jl` holds one lock for all its rounds (its per-run calls skip the lock when the holder is the parent), or the lock becomes a ticket queue.
  - Accept: a waiter queued before an A/B starts runs before the A/B's second round.
- [x] (merge, 2026-10-04; D-120) **P6.0t** Integral refresh waste (from the P6.0m3 review; low priority).
  - `src/codegen.jl` refreshes every integral that is not dirty after the sweep at the start of the after block once any after reader exists, including integrals read only by the before block or the temperature (fresh from `end_mcs`). `end_mcs` also refreshes observed-only integrals, which observed queries recompute anyway.
  - Fix: filter the start-of-after refresh to integrals read after the sweep; give observed-only integrals no slot or refresh.
  - Accept: probe `PWaste` (`/tmp/p60m3/rv1/`) emits 1 `CellReduce` at the start of the after block and none for the observed integral; fingerprints of models without such integrals unchanged.
- [x] (merge, 2026-10-04; D-133) **P6.0u** Remaining `@components` gaps (from the P6.0k2 review; small).
  - MTK `tstops` and `assertions` are accepted and ignored; reject them like F7's fields.
  - Binding rejections that do not name the component (`2k` does not reduce…, unknown symbol `k2`, "no initial value" for `y(t) = 2z`) should name it.
  - Hand-written (non-`@potts_model`) `@extend` bases: an untranslated `x′` error from inside the base is labelled with the outer model's description (P6.0e2 review; wrap the base call in its own catch, about 3 lines).
  - `init`'s `frozen_varies` warning cannot be silenced by a system that deliberately keeps a mask static (P6.0d review N1): skip it when `frozen_varies` is defined outside CorePotts.
  - The temperature's `integral(Pre)` error lacks its "in @sweep" location (P6.0m3 review nit).
- [x] (merge, 2026-10-01; D-085; audit `research/gpu-host-transfer-audit.md`) **P6.0v** GPU host-transfer audit and instrumentation (user, 2026-10-01). Goal: every synchronize, device↔host copy or host-side work during a Metal MCS is either unavoidable or removed.
  - **Audit** `docs/design/research/gpu-host-transfer-audit.md`: every `synchronize`, `Array(…)`, `_snapshot`, `_readback`, host↔device `copyto!`, and every host loop over sites or cells that runs during `step!` on a non-CPU backend, in CorePotts, Potts and the generated code. Per entry: when it fires (every MCS / event MCS / setup), how much it moves (O(1), O(events), O(cells), O(cells × quantities), O(sites)), whether it is necessary, and the device-side replacement. Measure before assuming (Akeeb: 185 ns/site Metal vs 47 CPU).
  - **Codegen quality on Metal** (same document): kernel launches per MCS and phases that could be fused; Float64 leaking into Float32 kernels; dynamic dispatch, allocations or boxed values in device code; redundant per-MCS passes over all sites (e.g. P6.0t).
  - **Known starting points** (verify; not complete):
    1. Lifecycle on an event MCS (`lib/CorePotts/src/lifecycle.jl:274-403`): host-planned divisions copy down `events`, `volume`, `cluster`; every cell column is copied down, edited and copied back (`_copy_columns!`); `generation` round-trips; `σ` and all trackers come down for `rebuild_trackers!` (host O(sites) recompute); `volume` comes down again to count empty daughters.
    2. P6.0d's `refresh_frozen!` copies the whole state to rebuild a Bool mask, even for a domain-only mask. **Handled in P6.0d round 2** (device kernel for the standard rule, host hook only as fallback, skip when no kind is frozen).
    3. `_AdaptiveODE` (`src/codegen.jl:591-599`) copies the whole state and `p` to the host every MCS it runs; it needs only the ODE columns.
    4. `HostPhase` (`relationships.jl:222-229`) copies the whole state down and every cell column back up; copy only the columns it reads and writes.
    5. The lifecycle trigger readback (`lifecycle.jl:281-282`): confirm it is the only synchronize on a quiet MCS.
  - **Instrumentation:** route every device→host and host→device transfer and every synchronize in the step path through one helper that counts transfers and bytes in `integ.stats` (as `stats.launches` counts launches).
  - The implementation is split into P6.0v1–P6.0v4; the audit assigns each entry to one of them, files it as its own row, or justifies it as unavoidable.
  - Accept: the audit document with every entry classified; the transfer counters exist and count exactly on a fixture with known transfers (CPU: always zero); on Metal, a quiet MCS of every gate model reports its current transfers (recorded in the audit as the baseline).
- [x] (merge, 2026-10-02; D-096) **P6.0v1** Lifecycle on the device (after P6.0v and P6.0v7). Per D-089 (user): the whole lifecycle, including event planning, runs on the device with no host decision and no trigger read-back; re-freeze `p6_0v_transfer_counters.jl` target (b) to 0 / 0 / 0 B. Daughter column copies run as a device kernel; trackers update on the device (or incrementally from the partition kernel's changes); no host O(sites) or O(cells × quantities) work on an event MCS.
  - Accept: on Metal, total host traffic on an event MCS is O(events): bytes independent of lattice size and of the number of cell quantities, on a division fixture scaled in both; Akeeb Metal improves measurably in `ab.jl` against the pre-change base; results unchanged up to floating-point differences ordinary tests allow (D-048).
- [x] **P6.0v2** (merge, 2026-10-01; D-092) ODE and `HostPhase` column-only copies (after P6.0v). `_AdaptiveODE` and `HostPhase` move only the columns they read and write, or run on the device.
  - Accept: per-MCS bytes of an adaptive-ODE fixture and a `HostPhase` fixture scale with the columns used, not with all cell quantities; results unchanged up to floating-point tolerance.
- [x] (merge, 2026-10-04; D-128) **P6.0v2b** (from the P6.0v2 review) Audit R4: a custom-rule `refresh_frozen!` snapshots the whole state to the host; copy only the leaves `remake_frozen` reads, or run the standard rule on the device. Accept: per-refresh bytes independent of unused cell quantities on Metal.
- [x] (merge, 2026-10-02; D-101) **P6.0v3** Launch fusion and Metal codegen fixes from the audit (after P6.0v): fuse the phases the audit lists, remove Float64 leaks, boxed values and redundant per-site passes (absorbs P6.0t if not done first). Also from the P6.0v2 review: an MCS with two adaptive-ODE phases syncs twice although the second sync waits on an idle queue (merge consecutive host phases, or skip a sync when nothing was enqueued since the last one).
  - Accept: launches per MCS reduced as listed in the audit, per gate model; no gate case regresses.
- [x] **P6.0v7** (merge, 2026-10-01; D-090) (top priority within P6.0v, before v1–v3; from the P6.0v audit and review) `benchmark/gate.jl` and `benchmark/ab_one.jl` time Metal `step!` to GPU completion (`synchronize`), then rebaseline Metal once. Today Graner–Glazier and Wortel Metal numbers measure only host enqueue time, so Metal A/B verdicts on them say nothing about GPU cost.
  - Accept: a Metal gate case's time includes a synchronize; baseline.toml's Metal rows re-measured under one lock; CPU rows unchanged.
- [ ] **P6.0v4** Shared-storage host-visible scalars (from the P6.0v audit): values the host reads at saves and checkpoints (status word, lifecycle stats, P6.0d counts) live in shared-storage buffers instead of a private-storage copy (≈ 200 µs → 0.3 µs per read here), still counted as transfers. Decide with ab.jl after P6.0v7.
- [ ] **P6.0v5** (optional backlog) Device adaptive ODE solves and a device `@link` contact graph (audit A5, H5).
- **P6.0v3 also includes P6.0v8** (from the audit): every device→device copy in the step path goes through a `_device_copy!` KA kernel (Metal.jl's `copyto!` waits on the GPU twice per copy; Merks makes 6 per MCS, probe 306 → 60 ns/site), and a Metal test wraps `Metal.synchronize` to assert that the GPU waits in a quiet MCS equal the counted syncs (Merks: 0).
- **P6.0v overall accept** (checked when P6.0v1–v3 are merged; the last of them freezes it): quiet MCS has zero host transfers and zero GPU waits (counted or implicit) on Metal, on every gate model, lifecycle models included (D-089); event MCS traffic is O(events); no gate case regresses on CPU or Metal; CPU paths unchanged in performance, zero allocations where zero today.
- [x] (merge, 2026-10-02; D-103) **P6.0x** A `gather` inside a cell-ODE rate allocates on every warm step (544–1408 B per MCS, e.g. `sum(volume[owner[n]] for n in Moore(1)(42))`), on base too (found by the P6.0n implementer). The ODE's `rhs` closure is heap-allocated and dispatched dynamically.
  - Accept: zero warm allocations for a cell ODE whose rate contains a gather, on both algorithms; fingerprints of models without one unchanged.
- [x] **P6.0w** (merge, 2026-10-01; D-093) Sub-stream seeds through a stable mixer (from the P6.2a2 review; small).
  - StableRNG (Lehmer) streams for seeds `s` and `s + 1` differ by a draw-wise constant shift. New code derives sub-stream seeds as `seed + k` (e.g. `akeeb_state`'s clocks use `StableRNG(seed + 1)`, the leader stream of `seed + 1`).
  - Fix: one internal helper (splitmix64 of `(seed, stream)`) used wherever a sub-stream seed is derived; changing `akeeb_state`'s clock seed changes its state, so revalidate the frozen `papers.jl` band as in P6.2a2.
  - Accept: consecutive top-level seeds give uncorrelated first draws of each sub-stream.
- [x] (merge, 2026-10-02; D-102) **P6.0y** Explicit-Euler field substeps sit exactly on the stability edge (found by the docs author, 2026-10-01). `CorePotts.stable_substeps(D, dt, h) = ceil(dt·D·Σ2/h²)` (`fields.jl:145`, used by `ExplicitEuler()` with `substeps = nothing`, `codegen.jl:962`) ignores reaction/decay terms and has no margin, so `D = 0.5` with decay blows up. Include the linear reaction rate (|∂f/∂u| bound, e.g. decay) and a safety factor in the count.
  - Accept: a diffusion–decay fixture at the old edge stays bounded and matches the analytic decay of a Fourier mode; Merks' substep count change (if any) re-checked against its papers.jl gates (D-048); fingerprints of models with explicit `substeps` unchanged.
- [x] (merge, 2026-10-02; D-099) **P6.0aa** `connectivity(k; rule = :arc_or_pair)` exempts a two-cell ring even when medium is on it, so multicell `WortelAct(connected = true)` runs accept copies that split cells (topology audit §6.4; TST `ConnectivityPreservedP` needs no medium on the ring, ca.cpp:1218). Add a copy-scope `ring_medium` (out-of-domain sites are not medium) and use `ring_arcs ≤ 1 || (ring_cells == 2 && ring_medium == 0)`; fix AUTHORING §4 and the WortelAct tutorial claim. No frozen gate uses `connected = true`.
  - Accept: a three-site junction fixture (cell–cell–medium) where the old rule splits a cell and the new one refuses; single-cell runs unchanged.
- [x] (merge, 2026-10-03; D-111) **P6.0ab** Small API defects found by the docs authors (2026-10-01): a kind table computed from parameters raises a `MethodError`, and `observe` does not accept a `Symbol` on a solution. Reproduce each from the docs-lab notes, fix, and add a test for each.
- [ ] **P6.0ac** AUTHORING §12.9 wording: proposals draw a uniform mobile target, then a uniform source offset (topology audit §1); add Morpheus `boundaryLengthScaling` and CC3D's hex `surfaceMF` to the pair-counting notes.
- [x] (merge, 2026-10-02; D-100) **P6.0ad** `Barker(; offset)` silently drops the offset: `_acceptance` (`src/problem.jl:194`) returns `CorePotts.Barker()` and `sweep_spec` accepts an offset for `:barker` without error (found by the docs author, 2026-10-01). Either carry the offset into Barker (`1/(1 + e^{(ΔH − δ)/T})`) or reject it at model build with a clear error.
  - Accept: a test that a Barker offset either changes acceptance as specified or raises at build.
- [ ] **P6.0ae** `:arc_or_pair` at a closed edge: TST counts its frame (σ = −1) as a distinct cell on the ring, ours treats out-of-domain sites as neither medium nor a cell (D-099 review). Decide with the Merks 2008 / Act ports whether to count out-of-domain sites as a cell in `ring_cells` (re-freezing `p6_0aa_arc_or_pair_medium.jl`'s edge testset) or keep and document the difference; also make the `ring_*` sentinel independent of σ's eltype.
- [x] (merge, 2026-10-03; D-108) **P6.0af** P6.0v3 follow-ups (review notes, D-101): a CorePotts test for a device lifecycle whose later stage fails after the fused `before` ran (`before_ran = true` handover; checked by injection only); `generated_code` should show the fused lifecycle; audit X4 typed literals in generated code (changes fingerprints, so batch it with another fingerprint change).
- [x] (merge, 2026-10-03; D-104, D-105) **P6.0ag** (high: a Metal compile failure) Every fixed-step ODE system is expanded in place, not called through the per-cell `rhs` closure (D-103 review). Today any non-inlined rate without a gather — a Hill gene circuit, an `ifelse` chain, a long sum, a model ODE with population folds — allocates 128–640 B per MCS on the CPU and does not compile on Metal (`jl_new_opaque_closure_jlcall`). Fix: `_ode_expand(odes) = true` (or drop the closure), re-record the fingerprints `p6_0x_gather_ode_alloc.jl` pins under a new decision (D-060 style).
  - Accept: zero warm bytes and Metal compilation, bitwise equal to the CPU Float32 run, for the Hill, `ifelse`, long-sum and model-fold shapes (`/tmp/p60x_rev/` has them); values bitwise unchanged on the CPU; a non-frozen gather-ODE case in `test/gpu.jl`.
- [x] (merge, 2026-10-03; D-107) **P6.0ah** Canonical term order in generated code (D-105): Symbolics orders sum/product terms by build-dependent hashes, so a rate's floating-point result can change by a few ulp after a package rebuild of identical source (seen in `p6_0ag_ode_expand_all.jl`'s model-scope shapes). Sort commutative operands in `lower`/codegen as `_commutative_order!` does for fingerprints; then restore item 3's bitwise comparison (re-freeze under a new decision).
  - Accept: the generated code of a multi-term rate with Potts operators (`population`, `gather`, `at`) is identical across two fresh package builds and across repeated builds in one session, and its results bitwise equal (the D-105 review harness in `/tmp/p60ag_rev/` compares 188 models); fingerprints change at most once.
- [x] (merge, 2026-10-03; D-110) **P6.0ai** `integral(expr)` whose `expr` contains a population fold that reads neither the cell nor the site re-evaluates the fold at every site, once per tracker: O(sites × cells) per MCS (400², 1600 cells: 971 ms vs 6.3 ms with the fold factored out; D-107 review). Hoist such folds out of the integrand (a model-scope slot, as `_hoist_populations` does elsewhere) and name the tracker after the hoisted operand.
  - Accept: the factored and unfactored forms give equal results (within rounding) and cost within 1.2× of each other at 200², 400 cells; names stay canonical (p6_0ah salts).
- [x] (merge, 2026-10-03; D-109) **P6.0aj** Concurrent model builds are not deterministic: `_GATHER_COUNT` (`src/vocabulary.jl`) is one global `Ref`, incremented without atomics and reset by any non-nested build (`src/macro.jl`), so 16 models built under `Threads.@threads` get different bound-variable names (and could reuse one within a model). Make the counter per build (task-local or carried in the macro's build state).
  - Accept: models built concurrently on 4 threads have the same generated code and fingerprints as built serially.
- [x] (merge, 2026-10-03; D-112) **P6.0ak** A computed parameter (scalar `V = 2A` or a kind table from parameters) is re-derived from its expression by every `remake` and integrator setter that does not set it, so an explicit value is lost at the next change of an unrelated parameter (P6.0ab review; e.g. a `J_LF` scan whose ensemble `prob_func` remakes another parameter). Re-derive a parameter only when one of its expression's inputs is in the change (or it was never set explicitly), keeping explicit values otherwise; update the parameters page.
  - Accept: `remake(remake(prob; p = [:J => M]); p = [:λ => 3])` keeps `M`; changing an input re-derives; same for `integ.ps` setters and the operating point; scalars and tables alike.
- [x] (merge, 2026-10-03; D-113) **P6.0al** One name in two categories: `@extend` merges by name only within each category, so a base parameter `x` and an extension variable `x(cell)` coexist; `observe(sol, :x)`/`getu` return the variable, `Potts.lookup(sys, :x)` the parameter (P6.0ab review). Reject a name declared in two categories at build (next to `_check_primed_names`), with a clear error.
- [x] (merge, 2026-10-03; D-114) **P6.0am** `@extend λ = base = Base(); @parameters λ = 3.0` builds, but the extension's `λ` default is the base's symbolic `λ`, not 3.0, so `PottsProblem` throws "parameter `λ` = `λ` does not reduce to numbers" (found by the P6.0al test author). Likely the constructor's keyword-override check (`λ === nothing ? default : λ`) sees the local that `@extend` rebound. Fix so a redeclared parameter's own default wins over the bound base name.
  - Accept: the extension's default is 3.0 at build and in `PottsProblem`; a constructor keyword `λ = 5` still overrides; a base-bound name not redeclared keeps the base's value.
- [x] (merge, 2026-10-03; D-115) **P6.0an** `remake(prob; p = (p₁ = 3.0,))` with a NamedTuple silently replaces `prob.p` with a one-field NamedTuple (falls back to CorePotts' default `remake_parameters`; P6.0ak review). Accept a NamedTuple like a `Dict`/pairs, or reject it with a clear error; test both.
- [x] (merge, 2026-10-03; D-117) **P6.0ao** Computed parameter defaults that call functions (`sqrt(a₀) + π`, `ifelse(a₀ > 1, …)`) or read a kind-table entry (`w = V₀[2] + 1`) fail at build with "does not reduce to numbers" (P6.0ak review). Evaluate them numerically (substitute, then evaluate registered/Base functions and indexing), keeping the parameter type; the input graph of D-112 must see through them.
- [x] (merge, 2026-10-03; D-116) **P6.0ap** Parameter-setter loose ends (P6.0ak review): a `setp` list mixing states and parameters throws a `MethodError` (raise an `ArgumentError` pointing to `setu`/`setsym`); `SII.setsym(integ, [names…])` is applied one name at a time (batch it like `setp`); `SII.remake_buffer(prob, prob.p, [:x], [v])` overflows the stack; `setp` on a hand-written CorePotts problem raises `MethodError` (`symbolic_container(::Nothing)`). A test for each.
- [x] (merge, 2026-10-04; D-121) **P6.0aq** The acceptance law's parameters (`Metropolis(; offset)`, `Barker(; offset)`) are solver data outside the generated code and are not fingerprinted: `offset = 0` and `offset = 2` fingerprint alike, so a checkpoint loads across them (P6.0p review). Hash non-default acceptance parameters (pins unchanged) or document why not.
- [x] (merge, 2026-10-04; D-122) **P6.0ar** `@relations proposal` and `@relations contact` neighbourhoods are not fingerprinted (P6.0aq test author): `Moore(1)` and the default collide, so a checkpoint loads across copy neighbourhoods and across contact neighbourhoods although the contact one changes the energy. Hash them; this moves the WortelAct/OpenVT/Merks pins (they set `proposal = Moore(1)`), so re-pin the affected frozen fingerprints under the decision (or hash only when different from the lattice default and show the pins hold).
- [x] (merge, 2026-10-04; D-123) **P6.0as** `@sweep` validation and combine hashing (P6.0aq review): `sweep_spec` accepts a non-finite `offset` (NaN makes acceptance meaningless) — reject it; a user closure as the temperature `combine` is fingerprinted through its printed, compiler-generated name, which may differ between sessions — hash a stable identity or document that closures make checkpoints session-bound.
- [x] (merge, 2026-10-04; D-124) **P6.0at** Named relations (`@relations far = Ball(2.0)` read by `contacts(far)` or a fold `far(site)`) and inline gather relations (`Moore(1)(42)` vs `Moore(2)(42)`) are not fingerprinted (P6.0ar test author): models differing only in them collide. They have no default, so hashing them moves every pin of a fixture that uses one (e.g. the p6_0x XPlain/XPair pins) — decide whether they are already reflected in the generated code (then close as no-gap) or hash them and re-pin under the decision.
- [x] (merge, 2026-10-04; D-125) **P6.0au** `integral(...)` inside `@drive` and constraint expressions is accepted (`_check_geometry` rejects it only in energies) but `_integrals_folds` never collects it, so it has no column (P6.0t review). Either collect and refresh it like other readers or reject it at build with a clear error; test both a drive and a constraint.
- [x] (merge, 2026-10-04; D-126) **P6.0av** `@sweep mcs_duration` is not validated (P6.0as test author): NaN, Inf, zero or negative durations are accepted and silently break the `Adaptive` ODE step and cadences. Reject non-finite and non-positive values at `sweep_spec` with an `ArgumentError` naming `mcs_duration`.
  - Accept: each invalid `mcs_duration` is an `ArgumentError` naming it when the model is built; valid values behave and fingerprint as before.
- [x] (merge, 2026-10-04; D-129) **P6.0aw** `@on_copy` right-hand sides that read an `integral` run during the sweep and see the value from the last boundary (P6.0au follow-up, D-125). Reject at build like drives (same message and workaround), or document that they read the start-of-MCS value; test both a site and a cell `@on_copy`.
- [x] **P6.0ax** An inline gather in a `@divide when` (`count(owner[n] == id for n in Ball(2.0)(40)) > 100`) fails at build with `KeyError: key Ball(2.0, false) not found` (P6.0at review): gather numbering (`src/compile.jl` ~362) scans `all_exprs`, which leaves out division `when`/rules and `@link when`. A named fold there works. Include them in the scan; test a gather in a division `when` and a link `when`, and that it is fingerprinted (D-124).
- [x] (merge, 2026-10-04; D-131) **P6.0ay** P6.0t's frozen cost check ("observed-only integrals cost nothing per MCS", `to <= 1.1 * tl`, `p6_0t_integral_refresh.jl` ~425) fails under parallel agent load (1.854 vs 1.545 ms at the P6.0au merge; again in the P6.0av implementer's run, load average 11–13) and passes alone each time. Make it load-robust under a new decision (e.g. more interleaved rounds with the minimum ratio of paired rounds, or a structural check that observed-only integrals emit no per-MCS `CellReduce`, which P6.0t's accept already names), re-freezing the file. Priority: a failure there aborts the acceptance include chain, so every later frozen file goes unrun in that suite run (P6.0aw implementer); at minimum the cost check must not stop the chain.
- [ ] (→ P6.0z, D-134) **P6.0az** A closure-weighted lattice neighbourhood is not fingerprinted by value and not session-bound (P6.0c2 review; pre-existing, D-122 path): `@lattice Lattice((12, 12); neighborhood = Weighted(Moore(1), o -> $W))` with `@energy contacts => 1.0 * weight` gives the same fingerprint for W = 2.0 and 3.0 in two fresh processes, so a checkpoint loads across different dynamics. Cause: `src/problem.jl` (~165–176) skips the contact relation equal to its default (`sys.lattice.neighborhood`), and `_fingerprint_seed` prints only the closure type; `_session_bound` checks only the solver string. Always hash the resolved lattice neighbourhood (offsets, weights), or apply the D-130 session token when the seed contains `var"#`; decide which, re-pin if needed.
- [ ] **P6.0ba** CheckerboardCPM's preflight refuses a relation that reaches beyond the copy footprint even when only an MCS-boundary rule reads it (P6.0ax test author; pre-existing, named and inline alike): a named `far = Ball(2.0)` read only in a division `when` fails with "declares Footprint(read = 1) but … reach distance 2". A relation read only at the boundary (lifecycle, link rules, boundary updates, observed) needs no copy footprint; restrict the preflight reach to relations read in the copy step. Test a boundary-only Ball(2.0) under Checkerboard, and that a copy-step read still raises.
- [ ] **P6.0bb** Make `benchmark/ab.jl` reliable. P6.2b measured 5–16% offsets between two checkouts of the same commit on `akeeb_99x60` Metal: a false 1.16, and a 1.24 reading that was mostly this artefact. P6.3a's Merks 1.098 was probably the same artefact.
  - Interleave base and candidate in one process when only the workload or the parameters change (see the P6.2b interleaved μ A/B).
  - Otherwise, rotate which checkout runs first and add a same-commit control (base vs base) whose ratio bounds what can be read from the A/B.
  - Accept: a same-commit A/B reads within ±3% on all five Metal cases.
  - **Expanded (D-157).** The backend is an argument of `gate.jl` and `ab.jl`. `baseline.toml` is keyed by machine and backend, and absolute baselines are informational.
  - `ab.jl` seeds the type cache equally on both sides, runs a same-commit control, and interleaves base and candidate by default. On the PC it pins to one logical CPU on reserved cores 12–15.
  - Accept on the PC: a pinned same-commit control within ±1% on every CPU and ROCm case. A pinned Akeeb pair read 1.001 / 1.001 on 2026-10-06.
- [ ] **P6.0bc** Cache compiled `HostKernel`s per model and backend (P6.3b review, D-145). The Metal OpenVT A/B read 1.07–1.115 until both sides' global Tuple type cache was seeded equally; then it read 0.996, against 1.001 for the same-commit control. Kernel compilation interns per-model Tuple types, so the steady-state speed depends on how many unrelated types a session has created.
  - Look up compiled kernels by (generated-function ids, backend, workgroup) instead of recompiling them per integrator.
  - Accept: the unseeded and seeded Metal OpenVT A/B agree within ±2%, and a second `init` on the same problem compiles no kernel.
- [x] (merge, 2026-10-07; D-157) **P6.0bg** (D-157) A backend-neutral device harness for Metal and ROCm.
  - One shared helper, `test/shared/devices.jl`: `POTTS_GPU ∈ {metal, rocm}`, `device_backend()`, `device_sync()`, `device_name()` and a uniform skip.
  - Every test project includes it. The frozen acceptance files are re-frozen to use it (23 `Main.Metal.MetalBackend()` sites); the change is mechanical and no assertion changes. `GROUP=GPU` reads the backend from the environment.
  - Check the Metal.jl workaround in `lifecycle_device.jl` (~853) on ROCm.
  - Add a ROCm check that no device kernel's LLVM IR contains `double` (extends D-047), so Metal-breaking code is caught without a Mac.
  - Accept: the full GPU group passes under `POTTS_GPU=rocm` on the PC, and the double-IR check fails on a deliberate Float64 literal (negative control).
- [x] (2026-10-07; first green run 37582486493 at fd9a519c, after D-158) **P6.0bh** (D-157; approved by the maintainer) The repository's first workflow: on pushes to `monorepo`, run the CPU suites and the GPU group under `POTTS_GPU=rocm` on the self-hosted runner ("rocm,amd").
  - Jobs pin to `taskset -c 0-11,16-27`.
  - Accept: a push runs green, and a deliberately broken commit on a scratch branch runs red.
- [ ] **P6.0bi** (D-157) Metal verification batch, after all paper models are done, on the maintainer's Mac Studio.
  - The Metal suites, the Metal gate rows (new baselines for the new machine), and a seeded Metal A/B of every gate case against the last Metal-verified commit (ebb0f823; its OpenVT pair was skipped).
  - Confirm p6_0v3's Metal Merks digest equals the CPU Float32 digest re-pinned under D-153 (`0x2aba158700292a8c, 0x6529835b3477095c`), and run the Float32 Merks2006/2008 device paths.
- [ ] **P6.0bj** (GE0, `research/gpu-ensembles.md` §9; approved by the maintainer) Measure first, on the PC, before any GPU-ensemble code is built.
  - K0: `EnsembleThreads` with a ROCm backend, with no new code.
  - K1: a minimal batched-checkerboard prototype (replicas as an extra array dimension, one launch per colour).
  - K2: S-a, one replica per work-item, for tiny lattices.
  - K3: a CPU-only census of S-b's mean conflict-free commit window on OpenVT growth.
  - Accept: a table of measured ns/site·MCS per case, naming machine and backend, against 24-thread `EnsembleThreads` (pinned, D-157). GE1/2/4–8 then need a maintainer ruling. A device `SequentialCPM` would amend D-009; moving a frozen reproduction to checkerboard means a deviation row and re-run targets. S-b and device stop conditions fall under D-156's stop-and-ask rule.
- [ ] **P6.0bk** (GE3; approved by the maintainer) An exact null-region skip in both algorithms, CPU first: proposals whose whole neighbourhood is medium are skipped without changing the trajectory.
  - Accept: bit-identical trajectories with and without the skip on every gate case and one OpenVT growth case. Requires the per-attempt counter-RNG keying to stay unchanged; check this first.
  - Report the pinned speedup on the PC, naming machine and backend.
- [ ] **P6.0bl** (P6.3d review) Are CheckerboardCPM's kinetics statistically equivalent to SequentialCPM's? On every Merks model they differ measurably. Eight seeds at 400 MCS: `MerksVasculogenesis` 100² H is +4140 ± 790 under checkerboard; Merks2008 sprout compactness is 0.821 (sequential) vs 0.869 (checkerboard).
  - Quantify it across the gate models.
  - Decide whether it is expected (the colouring order, proposal law) and document it, or whether it is a defect.
  - This matters for P6.0bj: GPU ensembles are checkerboard-only, and frozen reproductions use SequentialCPM.
- [x] (merge 2026-10-07, D-161) **P6.0bd** (D-154, D-156) Deviations tables in the four-column form: our value, the paper's value, suspected cause, author-question status.
  - Apply it to the frozen 09 and 10 pages and the tutorial template, re-freezing under D-154.
  - Retire the 09 V-OS1–V-OS5 rows (Graner–Glazier only, D-156).
  - Label every timing with its machine (spec 10 is done).
- [x] (2026-10-07; D-159, `research/mtk-native-plan.md`) **P6.0be** (D-156) Design: what it takes for Potts.jl to be ModelingToolkit-native as a whole. The maintainer's aim is the full claim; `research/mtk-native-investigation.md` §1 found it unachievable as of 2026-10.
  - Re-check the three blockers (the sweep as an MTK object, ragged growing per-cell state, lattice quantities) against current MTK.
  - Price each route in build time, latency and gate cost.
  - Propose the strongest claim the paper can defend, plus the work items.
  - **Stop and report** if a route needs major MTK friction or a major slowdown (D-156).
  - Output: `research/mtk-native-plan.md`. The maintainer decides.
- [x] (merge 2026-10-07, D-161) **P6.0bf** (D-156) No cell outlines anywhere.
  - Remove `boundaries = true` and `pottsboundaries` from `docs/paper_runs/*.jl` (GG, Akeeb, Merks, OpenVT), the docs tutorials, and the frozen 09 page (~line 427; re-freeze under D-156).
  - Re-render the paper-run videos and the 09 FULL video on the PC. Replace the release asset `09_cell_sorting_full-2026-10-05_replicate1.mp4`, and link it from the 09 page.
- [x] (merge 2026-10-07, D-160) **P6.0bm** (D-159; plan §6) A public `hamiltonian(sys)` and a typed metadata payload describing the sweep. Small. Runs first in the chain bm → bp → bn → bo, because these items edit the same files.
- [x] (merge 2026-10-07, D-164) **P6.0bp** (D-159, re-scoped by D-162) A public `Potts.updates(sys)` returning every update statement as written: phase (`:before_mcs`/`:after_mcs`/`:on_copy`), scope (`:cell`/`:site`/`:model`/`:edge`), cadence (`Every(n)`) and its `Equation` in MTK `Pre` form. It works on the plain, `complete`, `extend` and `mtkcompile` forms (the compiled form reads the authored model, as in D-160). Small.
  - Events as MTK callbacks move to P6.4c (D-162).
- [x] **P6.0bn** (D-159; plan §6) The model's own cell and model ODEs go through `mtkcompile` before Potts lowers them. Medium; about +0.2 s cold, to be absorbed by the precompile workload.
- [ ] **P6.0bo** (D-159; plan §6) Initialization equations that touch one cell go through MTK's `InitializationProblem`. Medium; about +0.5 s cold.
  - All four items (bm, bp, bn, bo) pass the standard +5% performance gate and the paired latency check. Stop and ask on major MTK friction or a major slowdown (D-156).
- [x] (drafts done 2026-10-07, `research/upstream-drafts/`; filing is the maintainer's) **P6.0br** (D-159) Upstream drafts, written locally for the maintainer to file:
  - the O(n²) dense mass-matrix bug;
  - the unknown-size parameter failure at `ODEProblem`;
  - an indirect-indexing comment on MTK #5078;
  - a scaling comment on #5139.
  Nobody here posts them.
- [ ] **P6.0bv** (D-164) `mtkcompile` of an edge-scope `@after_mcs` fails with an opaque `KeyError: :edge`. Support edge-scope MCS updates, or refuse them with a clear `ArgumentError` naming the construct; then extend the P6.0bp test to the compiled form. Small.
- [ ] **P6.0bw** (from P6.0bb) ROCm synchronize cost in library code. AMDGPU's default `synchronize` spins briefly, then waits on a HIP host callback through Julia's event loop. A benchmarked Graner–Glazier MCS read about 20, 47 or 2500 ns/site depending on which path it took; spinning on `hipStreamQuery` reads a stable 13.7.
  - Measure what every `KernelAbstractions.synchronize` inside `step!` costs on ROCm: host passes, lifecycle readbacks, saves.
  - If it is material, add a backend-neutral wait helper. It must be safe for hostcall kernels: a GC safepoint, a yield and a timeout.
  - Gate it with the paired A/B on ROCm.
- [x] (merge 2026-10-07, D-167) **P6.0bx** (from the P6.0bb review) The frozen `p6_0s_v7_tooling.jl` L2 check fails on Linux. It asserts that no `/tmp/` path appears in the sandboxed `exclusive.sh`, but `mktempdir` lives under `/tmp`; base 9efdf924 fails the same way.
  - CI never runs `benchmark/test`, which is why CI is green.
  - Fix through a test-author re-freeze, and add a CI step that runs `benchmark/test` with `TMPDIR=$RUNNER_TEMP`.
- [ ] **P6.0bs** (D-159; after bm–bo) A frozen test that checks every MTK claim the paper makes, plus the paper and docs wording (plan §5).
- [ ] **P6.0z** API surface audit and correction. This is the last item of step 0: it starts only when every other P6.0 row is merged, so it audits the API those rows leave behind (D-075 breaking batch, P6.0o `AbstractSystem`, P6.0k2/P6.0c2/P6.0m3/P6.0n fixes). Include from `research/initial-state-review.md`: `Any()` cannot be a Potts name (shadows `Base.Any`: layout `into`, D-075 Q5 `clamp = Any()`), and `Box` in `@create … at = Box(lo, hi)` clashes with Makie's `Box`. Also folds in the fingerprint corner cases (D-134): P6.0az; fix if cheap, else document as best-effort. Also (D-136, maintainer): consolidate the fingerprint tests into one frozen suite `lib/PottsModels/test/acceptance/fingerprint.jl` — the fingerprint testsets of p6_0p, p6_0aq, p6_0ar, p6_0as, p6_0at, p6_0ah, p6_0c2 and the pin blocks of p6_0t, p6_0x, p6_0au, p6_0aw, p6_0av, p6_0u, p6_0ag, p6_0ax, p6_0g; every distinctness, checkpoint-refusal and cross-session check kept; each published model and fixture pinned exactly once; touched files re-frozen under D-136. Also (P6.0ax review, D-134): gather bound-variable names, population variables and `rand()` addresses share one build counter (`_next_number!`, src/vocabulary.jl), so an `@observed` fold written before other statements shifts later names and `rand()` addresses — the fingerprint changes and, under a fixed seed, the trajectory changes (adding a diagnostic changes results). Give `rand()` addresses and bound names per-statement or canonical numbering at `mtkcompile`; re-pin under D-136. Priority before reproductions that add observables to seeded runs. Also (P6.0o review): a component's algebraic observed queried as `dc₊z` gets "namespaced by another system" — say it is substituted and suggest `@observed`; `s.λ` on a `CompiledPottsSystem` is a FieldError; `Potts.parameters` vs `ModelingToolkitBase.parameters` differ for component models.
  - **Scope.** Every exported and `public` name of Potts, CorePotts, MakiePotts and PottsModels: types, functions, macros, DSL vocabulary, keyword arguments and their defaults, and error messages a user sees.
  - **Audit.** An adversarial review writes `research/api-surface-audit.md`, one table row per name: what it is, who uses it, and the finding. It checks:
    - naming consistency, e.g. the `CPM*` names left after `PottsProblem` (`CPMAlgorithm`, `CPMFunction`, `CPMState`, `SequentialCPM`, `CheckerboardCPM`), and SciML/MTK conventions (D-075);
    - keyword names and defaults that are consistent across constructors, `solve`, `remake` and layouts;
    - names that should not be public (internal helpers reachable through exports or the ExplicitImports allowlists);
    - public names missing a docstring, and docstrings that are stale after D-075/D-076/D-077/D-078;
    - leftovers: names no code path, test or tutorial uses;
    - the `POTTS_NONPUBLIC_QUALIFIED` and other ExplicitImports allowlists, each entry justified or removed.
  - **Correction.**
    - Non-breaking fixes land directly: docstrings, `public` markers, error messages, allowlist trimming.
    - Breaking ones (renames, removals, keyword changes) are collected into ONE proposal for the maintainer to ratify as a single DECISIONS entry, as D-075 was. They land with no aliases (D-028), with PottsModels, tests, benchmarks and tutorials updated in the same change.
  - Accept: the audit document exists and every finding is resolved, ratified for later, or rejected with a reason.
  - Accept: a frozen public-API snapshot test lists every exported or `public` name per package, so any later change to the surface needs a DECISIONS entry.
  - Accept: Documenter `checkdocs = :exports` passes with no missing docstrings, and Aqua and ExplicitImports are clean, with allowlists no larger than before.
  - Accept: the gate is unchanged, and generated code and fingerprints are unchanged except where a ratified rename touches them.

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
- [x] (merge, 2026-10-05; D-138) **P6.1a5** Move `VoronoiBall` (added to PottsModels in P6.1b2) into `src/layouts.jl` as
  - Initial-state vocabulary (`research/initial-state-review.md` §2, §4): shapes and points scoped to 09/11 (`Sphere`, `RandomPoints`, `Voronoi(points; region, lloyd)`, `Center()`); the GeometryBasics decision (Q1: reuse only round shapes and `Point`, closed membership; index boxes stay ranges); `Voronoi` replaces `VoronoiBall` only if it reproduces its σ or D-063's area statistics (Q3); shape layers clip to the domain and report `clipped` (Q5, D-057 amendment).
  a core layout, next to the planned `Spheres`. It needs a DSL and export review, and moves
  the StableRNGs dependency to Potts only.
- [x] **P6.1a6** (merge, 2026-10-01; D-091) Layout protocol of D-075 (amends D-057): `paint!(op::LayoutState, l, lat)`, the layout report, `Tiling(partial)` and `splits`. From `research/initial-state-review.md` §4 (coordinator-adopted 2026-10-01; peer research from the user's "using morpheus as a heavy heavy inspiration"). Land before P6.0z.
  - The public extension method becomes `paint!(op::LayoutState, l, lat)`; every layer is rewritten in the same change (`Tiling`, `Scattered`, `Frame`, `InsertUntil`, `Overlay`, PottsModels' `VoronoiBall`). Public accessors `new_cell!`, `assign!`, `owner`, `kindof`, `ncells`, `record!`, plus lattice queries so no layer reads `LatticeSpec` fields. `paint!(σ, kinds, …)` and `layout_tally` are removed, no alias (D-028).
  - `layout(l, x; report = true) -> (op, report)`: one row per leaf layer in paint order (`requested`, `painted`, `dropped`, `misses`, `counted`, `splits`).
  - `Tiling(…; partial = :skip | :clip)`: `:clip` keeps boxes cut by region ∩ lattice; the docstring states the CC3D difference (CC3D clips at the lattice only).
  - `splits = :warn | :allow` on every layer; a cell is exempt from the split warning only if every layer that cut it allows splits.
  - `SciMLBase.remake(::AbstractLayout; kw...)` re-runs the keyword constructor (it throws today).
  - `akeeb_layout = overlay(Tiling(…; partial = :clip), InsertUntil(…; splits = :allow))`; `_AkeebSlab` and the `NullLogger` in `akeeb_state` are deleted; the width check stays.
  - Accept: Akeeb σ, kinds and painted/misses/counted byte-identical to today at 500×300 and 99×60, both seedings, ≥ 4 seeds (reproducer `/tmp/initstate-review/p1_akeeb_clip.jl`); `akeeb_state` emits no log record while an unrelated `@warn` inside a layer still surfaces; the custom test layer uses no `LatticeSpec` field; `remake(Scattered(…); seed = 2)` and `remake(InsertUntil(…); misses = :retry)` work and validate; re-freeze (D-060 style, assertions unchanged, API calls only) of `acceptance/p6_2a_akeeb_analysis.jl` and `acceptance/p6_2a2_akeeb_inventory.jl`; gate and fingerprints unchanged; Aqua, JET, ExplicitImports clean.
  - Not in this row: `into`, `shortfall`, `set_column!`, `add_link!`, shapes.
- [x] **P6.1a7** (merge, 2026-10-01; D-094) `Scattered` overlap test against an occupancy mask (after P6.1a6; same file). Today O(placed) per draw (`layouts.jl:179`): 3.5 s for 4·10⁴ squares at 3000².
  - Accept: σ identical to the pre-change version over a seed grid, closed and periodic (the dilation wraps), 2D, 3D and hex; 10⁴ cubes of 5³ at 200³ under 50 ms (≈ 480 ms today, `/tmp/initstate-review/p3_scattered_cost.jl`).
- [x] (merge, 2026-10-01; D-088) **P6.0e2** Using `m′` for a cell variable `m` gives a bare UndefVarError. Emit a Potts
  error ("primes exist only for site/field variables"). Also check programmatically built
  `PottsSystem`s for declarations named `x′`.
- [x] (merge, 2026-10-05; D-139) **P6.1b** R16 analysis in the docs: boundary-length decomposition, annealed-copy
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

- [x] (run 2026-10-05, 8eb9d210; every binding row passes except V-PRE3 (b)) **P6.1d** Run reproduction 09 in FULL on an idle machine: `POTTS_FULL_REPRODUCTION=true`, 1000 cells
  per replicate, about 25–40 CPU-min each. Record the verdict table in PROGRESS and send it to the spec
  owner. There is no code change: the page is frozen (D-072).
- [x] (run 2026-10-05, 0eb1ea72; every binding row passes except V-PRE5 "one dark cluster @ 10⁴", 0.815 vs ≥ 0.90; sent to the spec owner) **P6.1f** (D-144; spec 09 §9.4, peer spec-owner ruling) Rerun reproduction 09 in FULL on an idle machine with the
  amended page: `MARGIN = 60` (347²) and the isolation-guard row. It costs about 2× P6.1d. It replaces P6.1d as the record for
  every row; P6.1d stays on record as a FAIL of V-PRE3 (b) caused by periodic-image contact. Record the table in PROGRESS,
  send it to the spec owner, and report it in the phase report as a pre-registered failure explained after the run.
- [x] (run 2026-10-06, 192 runs on the PC; D-151 outcome: stays a reported deviation) **P6.1g** (D-151; spec 09 §9.5) Late-stage coarsening in reproduction 09 is an open deviation: V-PRE5's one-cluster clause fails in P6.1f, and both published runs coarsen faster than almost all of our 22 replicates after 10³.
  - First, cheaply: the distribution of the time to a single dark cluster over ≥ 20 replicates, against the paper's ≈ 5000.
  - Then test the candidate causes: T against the effective line tension, the cell-size difference (V-GG6), and the aggregate size and spread.
  - The targets are unchanged. It is reported in the phase report as a science question (AUTONOMY §7.5), and the author question is in README §5.
  - **Bounded pass (D-156, running on the PC).** ≥ 20 more replicates, then one scan per candidate cause; if none explains the gap, a fresh seed set. After that it stays a reported deviation. The question goes to Glazier through the PI sheet.
- [x] (merge 2026-10-07, D-166; T = 80 is a deviation: cells disappear too slowly) **P6.1h** (D-151 outcome) Put V-PRE7, the sorting temperature regimes (spec 09 §8.5), on the 09 page, as an independent check of our temperature scale. P6.1g found that late coarsening is strongly T-sensitive.
  - It needs a re-freeze of the page and test under a new D-entry; it can share the re-freeze with P6.0bd/P6.0bf.
  - Runs at FULL on the PC.
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
- [x] (merge, 2026-10-01; D-080) **P6.0m3** `s ~ integral(Pre(w))` in `@after_mcs` fails with `FieldError: no field
  integral_…` (pre-existing on 8b14051; found by the P6.0m reviewer, `/tmp/p60m/rv1/probe_pre.jl`).
  The start-of-after integral refresh also runs before the Pre-snapshot `CopyPhase`.
  - Accept: an integral of a `Pre` operand reads the block-start values over the σ the block sees (post-sweep in `@after_mcs`; the frozen test's definition).
  - Accept: a regression test covering both orders.
- [x] (merge, 2026-09-30) **P6.0m2** (D-075, breaking batch part 1) `CPMProblem → PottsProblem`, supertype
  unchanged, no alias; `SciMLBase.isdiscrete(::AbstractPottsAlgorithm) = true`. Every
  package, test, benchmark and tutorial is updated in the same change. Accept: all suites
  pass, the gate is unchanged, and no `CPMProblem` remains outside DECISIONS and PROGRESS.
- [x] (merge, 2026-10-01; D-082) **P6.2a2** Refactor `akeeb_state` onto `InsertUntil` (`misses = :count`, `fraction = 1//4`)
  and expose the counted inventory (spec 10 V-A1(a)). This changes the RNG stream from
  MersenneTwister to StableRNG, so the frozen `papers.jl` band must be revalidated.
  StableRNG only (D-075): the `clock`/`cue` expression defaults move to P6.4a.

- [x] (merge, 2026-10-03; D-106) **P6.1e** `graner_glazier_aggregate`'s default 10-site margin lets a long sorting run join the aggregate to its periodic image (seen in the 10⁴-MCS paper run, which uses `margin = 60`). Raise the default margin (≥ 60) or make the default lattice closed, and re-check the frozen sorting reproductions that call it.

### Step 2 — Akeeb

- [x] (merge, 2026-09-30; D-073) **P6.2a** R2 `InsertUntil` (general "repeat until ratio" placement; refactor P6.2c's
  seeding onto it, with a counted-miss option); R16 code-definition metrics (per-column
  areas, the `find_peaks` port per D-069, BFS clusters).
- [x] (merge, 2026-09-30; D-068, D-071) **P6.2c** Akeeb seeding per D-068 (MD-1).
  - Default: emulate the authors' ghost leaders; keyword variant: retry.
  - Re-baseline the frozen `papers.jl` Akeeb testset (ensemble band; μ = 24) and the gate's Akeeb case.
- [x] (merge, 2026-10-05; D-142, D-143) **P6.2b** (V-target audit done 2026-09-30: freeze from spec 10 §5.3, with 12 READY rows and 3 PARKED; SciPy 1.7 `find_peaks` finger detection is exact against stored outputs; do not reuse `akeeb_metrics.jl`). Reproduction 10 against the authors' 13,310-run data (10 §5).
  Frozen: `reproductions/10_akeeb.jl`. **Gate:** A5 default μ (D-050: μ = 24, pending
  confirmation).

- [x] (merge 2026-10-07, D-163) **P6.2d** (D-156) Akeeb FULL extras.
  - Un-park V-A6 with the area-equality classifier.
  - Run the V-A7 full-sweep |r|, and V-A3–A5 at FULL, on the PC, with D-146 records.
  - V-A8/A9 go on the PI sheet.

### Step 3 — Merks 2006 + 2008

- [x] (merge 2026-10-07, D-167) **P6.2e** (D-163) The page-10 FULL-record test recomputes V-A6's R3 (phenotype counts from the committed `sweep.tsv` against A's classified counts) and V-A7's six |r| values, instead of reading the PASS strings. Small; test-author re-freeze.
- [x] (merge, 2026-10-05; D-140) **P6.3a** R4 topology values dispatched on geometry; the soft E₀ drive; `Global()`
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
- [x] (merge, 2026-10-06; D-145) **P6.3b** R5 `@boundary` per face with a masked clamp every substep; field phase
  placement and an explicit phase order. The phase order **is** `@schedule`, with the
  `step!` restructuring of api-synthesis §2.12; D-035 is amended (D-075) in the same change.
  - Accept: the gate is unchanged on CPU, and the Metal A/B is ≤ 1.01 for the five gate
    models.
  - Accept: the absorbing frame keeps c = 0 on the ring after every substep.
  - Accept: PDE-before-sweep ordering is observable in a two-phase test.
- [x] (merge, 2026-10-05; D-141) **P6.3c** R2 `Eden` + splits.
  - Initial-state vocabulary (`research/initial-state-review.md` §2, §4): `Eden`, a host-routine `Splits` (not the lifecycle routine), `RandomPoints(replace = true)`, and `shortfall` with its first `:allow` consumer.
- [x] (merge, 2026-10-06; D-153) **P6.3d** Merks split into `Merks2006` and `Merks2008` per D-050 M1–M11: the frame,
  - Initial-state vocabulary (`research/initial-state-review.md` §2, §4): port `merks_state` to `Scattered(282, (7,7); region, kinds = [:endothelial], seed, gap = 1)` (same algorithm, draw-for-draw identical under a shared RNG) — **user-approved 2026-10-01 (D-087)**; it changes the gate's Merks initial state, so re-check the gate and the `mechanisms.jl` seeds.
  15 FTCS substeps, relaxation and `mode = :extension_retraction`. Frozen:
  `reproductions/01_merks.jl` (V-E1…, V-C1…). **Gate:** M1–M7 sign-off (approved, D-050);
  L 50 vs 60 remains an author question.

  - **Maintainer rulings (D-156).**
    - The ring rule at a closed edge matches TST: out-of-domain sites count as a cell in `ring_cells` (P6.0ae).
    - Digitise 01b Figs 5, 7–10, 12 and 13 and target them through the continuous-χ superset (M7), with inferred parameters flagged.
    - Show both clocks: relaxation-end time is the primary axis, with a note giving the code-MCS offset.
- [x] (merge, 2026-10-06; D-153, folded into P6.3d) **P6.3e** The 2008 contact-inhibited variant uses 20 neighbours (`NeighborOrder(4)`) for contacts and copies, as the authors' parameter files do; `contact_inhibited = true` keeps `Moore(1)` today (topology audit §6.1). Folds into P6.3d's 2008 set; a `Frame` border must then be 2 sites thick (TST border contacts reach through the √5 stencil). No frozen gate uses `contact_inhibited = true`.

### Step 3b — OpenVT monolayer benchmark (parallel track; D-147, spec 15)

Goal (user, 2026-10-05): put Potts.jl in the OpenVT monolayer lineup.
- Follow the manuscript wherever possible.
- Recreate every simulation figure and meet every submission requirement.
- Include the 1D-chain mechanical calibration.
- Publish all results as offline files in the docs.

Full runs are offline (D-146).

- [ ] (page parts merged 2026-10-07, D-161; FULL run, 01b figure targets and video clock overlays open) **P6.3f** (D-153–D-156; after P6.3d merges) Re-freeze reproduction 01's page and test through a test author.
  - Remove the cell outlines (page lines ~179, 203, 234).
  - Add the four-column deviations table, seeded from D-153 Applied's rows. Drop the wrong "Attempts per MCS" row (CorePotts already matches TST's interior-site count) and fix §2 Units.
  - Make the relaxation-end time the primary axis, with the code-MCS offset noted.
  - Add digitised 01b Figs 5, 7–10, 12 and 13 as targets through the M7 continuous-χ superset, with inferred parameters flagged. The model side is ready: `χcc`, `merks2008_sprout(; divisions = 8)` on 502², and `track = (:ΔH,)`.
  - Run the FULL tier on the PC, with D-146 records; the FULL run decides V-C3's low plateau.
- [x] (2026-10-05; D-147) **P6.15a** Spec 15 (`research/model-specs/15_openvt_monolayer.md`).
  - Written by the peer session "Potts.jl models and publications".
  - Verified as v3 against M, G at 54f375f and TSTgh at 7ae1636. The verification log is in the spec.
- [x] (merge, 2026-10-05; D-148; FULL record 2026-10-05, every V6–V8 row passes) **P6.15b** F2 and Table S5 mechanical calibration (spec 15 §4.2, P1–P12; gap G10).
  - The test author freezes V6–V8 and a P11 unit test: the 11-bead free-end spring–dashpot reference matches `relaxation_exact.csv` to 1e-6.
  - Implement the fixture: strips on a 5-row periodic lattice (one `Tiling` per region plus `overlay`), the A* switch at t = 0, unwrapped centroids, the 90% crossing and the MSE.
  - FULL run: 100 seeds × λ ∈ {1, 2, 3, 5}, for the 11- and 21-chains. It sets T_Potts, which every other row uses.
- [x] (merge, 2026-10-06; D-150) **P6.15c** Model update to Table S1 (spec 15 §5) with a D-entry: replace the 2024 defaults or keep them as a documented variant. Close these gaps:
  - G1: per-cell free-surface fraction f_i over Moore(1), exact and incremental, as a general contact fold, not model-named.
  - G2: a per-daughter normal draw of X, redrawn while ≤ 0, on the counter RNG, with a deterministic X ≡ 2 mode. Start it in parallel with P6.15b.
  - G5: a disc start.
  - G6: a domain guard.
  - G11: stops at 1000 and 10⁴ cells and the O2 snapshot writer. Use the existing `DiscreteCallback` plus `terminate!` (G7).
- [x] (merge, 2026-10-05; D-149) **P6.15d** Analysis port (G8; can run in parallel with P6.15b):
  - a concaveman port and a `metrics.cpp` port, with the inhibition fractions of M's Category 3 analysis (spec item A3);
  - the O1–O6 writers.
  - Accept: byte-identical `metrics.csv` on the consortium parameter-plane set, against a `-ffp-contract=off` reference build (spec 15 D11). No `fma`, `muladd` or `@fastmath` in the geometry kernels.
- [ ] **P6.15e** F5: 100 runs of 1000 cells, case (b). Target V4, with a negative control.
- [ ] **P6.15f** F3 (deterministic case (f) and stochastic case (b)) and F8 (V5), overlaid on the consortium data.
- [ ] **P6.15g** Profile throughput first (G9; `BoundarySite` is P6.4b), then the sweeps for F6, T1 and F7 (spec 15 §4.3). Targets V1, V2, V2b, V3 and V3b; runs past 20× are capped.
- [ ] **P6.15h** F1 (the Potts.jl panel and banner) and F4 (the free-surface schematic, with a unit test that G1 equals the drawn count).
- [ ] **P6.15i** Docs page "OpenVT monolayer benchmark":
  - every figure in M's layout;
  - a differences table, which is spec 15 §1.1 plus the deviations;
  - offline data and provenance under `reproductions/data/15/`, with videos as release assets (D-146).
- [ ] **P6.15j** The submission package in the consortium layout (`implementations/Potts.jl`, `results/Potts.jl`), prepared locally. Submitting it to the consortium is the maintainer's call.

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
  - (D-162) `@discrete_events` (model scope, `t`/`mcs` conditions) and `@terminate` are stored as MTK `SymbolicDiscreteCallback`s from the start, so `ModelingToolkitBase.discrete_events(sys)` lists them. Per-cell, per-site, per-copy and structural rules are never listed as callbacks.
- [ ] **P6.4d** R2 `BrickWall`; R16 T1 counts, topology moments.
  - Initial-state vocabulary (`research/initial-state-review.md` §2, §4): `Tiling(stagger, widths, partial = :wrap)` in place of `BrickWall` (04 is periodic in x); amends D-075 §3.3, **user-approved 2026-10-01 (D-087)**; confirm 04's layout reproduces exactly; the docs show a brick-wall recipe.
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
  - Initial-state vocabulary (`research/initial-state-review.md` §2, §4): `Fill`, `Objects(Sphere…)` and `Group` (with `set_column!`) in place of `Plane`/`Spheres`; amends D-075 §3.3, **user-approved 2026-10-01 (D-087)**; the docs show `Plane`/`Spheres` recipes.
- [ ] **P6.5d** reproduction 14a/14b (and 14c, D-156). C4 resolved from the CC3D source (D-155); no gate.

### Steps 6–12

These are listed so that dependencies are visible. They are expanded into items when step 5
merges (phase-end checkpoint).

- **P6.6** myxobacteria:
  - Initial-state vocabulary (`research/initial-state-review.md` §2, §4): `Chain` with `add_link!`.
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
  - Initial-state vocabulary (`research/initial-state-review.md` §2, §4): `Rod` and `InsertUntil(shape; occupied, collective)`.
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
