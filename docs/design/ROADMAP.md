# Roadmap (machine-checkable)

Each milestone: id, depends-on, deliverable, acceptance (commands that must exit 0 or
numbers that must hold). Tick with `[x] <commit> <date>` when merged.

## Phase 1 — Skeleton

- [ ] **M1.1** workspace skeleton — root `Project.toml` `[workspace]`, `lib/{CorePotts,LocalMath,MakiePotts,PottsModels}`, `[sources]`, `.gitignore` Manifest, `CLAUDE.md` (rules from INTERNALS §5), JuliaFormatter config.
  Accept: `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'` succeeds from a clean clone.
- [ ] **M1.2** LocalMath import (git subtree, history preserved) → `lib/LocalMath`; tests pass unchanged.
  Accept: `GROUP=LocalMath julia --project test/runtests.jl`.
- [ ] **M1.3** MakiePotts import → `lib/MakiePotts`; compiles (recipes may be stubbed against a temporary frame type until M2.10).
- [ ] **M1.4** CorePotts seed from FusedCPM: `CPMFunction`, `CPMProblem`, `PottsParameters`, `CPMState`, Philox4x32 (D-005), owned `exp` (D-006), `SequentialCPM`, `CheckerboardCPM` with footprint-derived stride (D-008), `PottsIntegrator <: DEIntegrator`, `PottsSolution`, status word.
  Accept: FusedCPM tests ported and green; `GROUP=Core`; JET `@test_opt init/step!` clean; AllocCheck warm `step!` = 0.
- [ ] **M1.5** CI matrix (Core, QA, Reference), Downgrade job, docs build, AirspeedVelocity suite with Graner–Glazier; `reference/` environment (D-021) with the legacy models runnable.
  Accept: CI green on `monorepo`; `benchmark/` produces the table from `FusedCPM/README.md` numbers ± noise.

## Phase 2 — CorePotts engine (each with brute-force ΔH + seed determinism + statistical CPU/Metal parity)

- [ ] **M2.1** N-dimensional lattice with per-axis boundaries/spacing and neighborhoods of any order (`Moore(k)`, `VonNeumann(k)`, `Ball`, `Shell`, `Stencil`, weighted); contact + volume + surface energies; surface tracker; generic cell/site energy functions. Accept: oracle tests; Graner–Glazier reference parity (KS over 16 seeds).
- [ ] **M2.2** moments tracker (centroid, elongation, periodic-safe geometry); site sums and minima trackers; structured owner sums.
- [ ] **M2.3** site/cell/medium/model state; history ring buffers; synchronous phase updates via LocalMath stages; accepted-copy affects; `ClearOnOwnershipChange`.
- [ ] **M2.4** fields: explicit-rate discrete Euler stages, diffusion stencils, sub-stepping; `field_value`, gradient, laplacian primitives. Accept: Merks reference parity.
- [ ] **M2.5** drives: chemotaxis, Act with owner-filtered gathers and geometric-mean fold, generic `ProposalDrive`/`ProposalModifier`; authored draws inside updates and rates (stream assignment). Accept: Wortel reference parity.
- [ ] **M2.6** constraints: local connectivity, extinction policies, `ProposalConstraint`.
- [ ] **M2.7** spatial queries and Cartesian ownership domains (fixed owners, immutable sites, per-face boundaries): neighbor counts, weighted contact measures, boundary-site queries, sums/means, predicate filters, interface queries.
- [ ] **M2.8** lifecycle: trigger/plan/apply; divide (principal major/minor, random plane, specified normal, external), remove, retire, create, transition; state rules; placement; conflicts; inadmissibility policies; capacity growth. Accept: OpenVT reference parity; ported CorePotts lifecycle scientific tests; invariants.
- [ ] **M2.9** relationships: CSR store, energies, create/remove/retune, lifecycle interaction.
- [ ] **M2.10** checkpoint/continuation; `PottsSavedState` accessors; MakiePotts wired to real solutions. Accept: state round-trip exact; MakiePotts tests.
- [ ] **M2.11** Metal: all of the above in the GPU group; statistical parity with CPU. Accept: `GROUP=GPU` locally green.

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

## Phase 5 — Slim, docs, cut-over

- [ ] **M5.1** LocalMath slimming (INTERNALS §3); TTFX benchmark for 1/4/8/32-stage programs.
- [ ] **M5.2** docs site (Learn / Published models / API per package).
- [ ] **M5.3** cut-over per AUTONOMY.md §5; registration; archive legacy repos; `PottsStudies` repo for SCD material.
