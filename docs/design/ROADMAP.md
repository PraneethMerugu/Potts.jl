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
- [ ] **M2.1b** hexagonal 2D geometry; irregular domains from masks/images/expressions (domain edge is a copy and field boundary).
- [x] 6e525c1 2026-09-29 (lattice units; spacing with M2.4) **M2.2** moments tracker (centroid, elongation, periodic-safe geometry); site sums and minima trackers; structured owner sums.
- [x] 6fd6998 2026-09-29 (phases are KA kernels per D-033) **M2.3** site/cell/medium/model state; history ring buffers; synchronous phase updates ~~via LocalMath stages~~ as generated KA kernels; accepted-copy affects; `ClearOnOwnershipChange`.
- [x] 8f0ac2d 2026-09-29 (Merks parity moves to M2.5: it needs chemotaxis) **M2.4** fields: explicit-rate discrete Euler stages, diffusion stencils, sub-stepping; `field_value`, gradient, laplacian primitives. Accept: Merks reference parity.
- [x] 785ef32 2026-09-29 (Merks + Wortel parity pass) **M2.5** drives: chemotaxis, Act with owner-filtered gathers and geometric-mean fold, generic `ProposalDrive`/`ProposalModifier`; authored draws inside updates and rates (stream assignment). Accept: Wortel reference parity.
- [x] 785ef32 2026-09-29 (RetireAtZero id reclamation lands with lifecycle M2.8) **M2.6** constraints: local connectivity, extinction policies, `ProposalConstraint`.
- [x] 48a43bc 2026-09-29 (contact graph is host-side; its device build is in M2.11) **M2.7** spatial queries and Cartesian ownership domains (fixed owners, immutable sites, per-face boundaries): neighbor counts, weighted contact measures, boundary-site queries, sums/means, predicate filters, interface queries.
- [x] 1c84438 2026-09-29 (D-035; seeding via host API and relationship consequences with M2.9) **M2.8** lifecycle: trigger/plan/apply; divide (principal major/minor, random plane, specified normal, external), remove, retire, create, transition; state rules; placement; conflicts; inadmissibility policies; capacity growth. Accept: OpenVT reference parity; ported CorePotts lifecycle scientific tests; invariants.
- [x] 69b0cfd 2026-09-29 (padded adjacency instead of CSR; directed/anchor links and link age via payloads) **M2.9** relationships: CSR store, energies, create/remove/retune, lifecycle interaction.
- [x] **M2.10** (bd713f5) checkpoint/continuation; `PottsSavedState` accessors; MakiePotts wired to real solutions. Accept: state round-trip exact; MakiePotts tests.
- [ ] **M2.11** Metal: all of the above in the GPU group; statistical parity with CPU. Accept: `GROUP=GPU` locally green.

- [ ] **M2.10a** compartments: compartment cells grouped under a parent; internal vs external contact energies; coordinated division.

## Phase 3 — Potts symbolic front end (spec: AUTHORING.md)

- [ ] **M3.1** `PottsSystem`, `@potts_model` sections and plain constructors, scoped `@variables`, `@kinds`, kind-indexed parameters, `Lattice`/relations of any order in N-D, source locations, composition (`compose/extend/flatten/@named`), units.
- [ ] **M3.2** `mtkcompile`: global-H → ΔH derivation with simplification and loop fusion (AUTHORING §4), generated `total_energy` self-check, validation, footprint analysis, CSE, scheduling; `CompiledPottsSystem`.
  Accept: `ΔH == H(after) − H(before)` on random flips for every model in `lib/PottsModels`.
- [ ] **M3.3** codegen → `CPMFunction`; `PottsProblem(sys, op, tspan)`; `PottsParameters`; SII; `remake`; `EnsembleProblem`; callbacks; `expression = Val(true)`; `eval_module`.
  Accept: every Phase 2 oracle test re-run through symbolic authoring; `remake` zero compile; Graner/Wortel/Merks/OpenVT from `lib/PottsModels` sources.
- [ ] **M3.4** component imports and structural replacement, scoped quantities, logical vector parameters, symbolic setters, one-block declaration, compound assignments, diagnostics with expression + remedy.

## Phase 4 — Coupling and models

- [ ] **M4.1** `ODEComponent`/`DAEComponent` init-once integrators; batched per-cell ODEs; scheduling phases; `MethodOfLinesComponent`; Metal via `EnsembleGPUKernel`.
  Accept: Akeeb MTK-bridge targets bytewise vs discrete clock (as in `SCDPotts/research`).
- [ ] **M4.2** `lib/PottsModels`: Wortel, Merks, OpenVT, Graner–Glazier, Wortel-Act 150², Akeeb leader/follower; tutorials; tested in CI.
  Accept: reference parity for each; TTFX table in docs.

- [ ] **M4.3** extended model library per `research/legacy-spec-adjudication.md` §3 "Models" (Mombach 3D, Shirinifard CNV, Wang 2025, OpenVT categories, Jiang 2005, Bauer 2007/2009, Zajac, Jafari Nivlouei, Starruß, Fortuna, Jiang 1999 foam, FBCA via COBREXA, hard-model set). Each: reference or literature parity.

- [ ] **M4.4** importers: PIFF (import/export) and MorpheusML (EzXML.jl → Symbolics); run the importable part of the Morpheus model repository as a regression corpus.

## Phase 5 — Slim, docs, cut-over

- [ ] **M5.1** LocalMath slimming (INTERNALS §3); TTFX benchmark for 1/4/8/32-stage programs.
- [ ] **M5.2** docs site (Learn / Published models / API per package).
- [ ] **M5.2a** MakiePotts: vector/arrow channels, relationship overlays, lineage, tensor ellipses, true-3D volume, WGLMakie, DataInspector, rerun controller.
- [ ] **M5.3** cut-over per AUTONOMY.md §5; registration; archive legacy repos; `PottsStudies` repo for SCD material.
