# Phase 12.5 Tiled Checkerboard Chunk Plan

Status: Accepted plan; not started

Date: 2026-07-21

## Objective

Implement and evaluate `TiledCheckerboardCPM` as a separately named, deterministic-sub-round,
tile-local CPM algorithm. The phase seeks Sultan-class throughput through shared-memory locality,
static physics specialization, and launch amortization while preserving the accepted Potts.jl
scientific and open-protocol contracts.

Phase 12.CPU must close before implementation begins. Phase 13 remains blocked until this phase
records a promote, experimental, or reject decision.

## 12.5A: Published evidence and matched baseline

- Extract the Sultan et al. 2D sorting and applicable 3D/motility configurations into an assumption
  ledger with direct paper citations.
- Separate published facts, inferred reconstruction choices, and unavailable implementation details.
- Add a minimal tile-local benchmark and paper-model fixtures with pinned timing boundaries.
- Capture current `CheckerboardSweepCPM` CPU, Metal, and ROCm baselines at publication-scale sizes.
- Retain activated attempts/s and accepted copies/s so lattice size cannot obscure throughput.

Exit: every comparison identity is explicit and no published speedup ratio is treated as an absolute
Potts.jl measurement.

## 12.5B: Reference semantics and conformance model

- Add the `TiledCheckerboardCPM` configuration and versioned semantic identity.
- Implement a small CPU reference for tile coloring, proposal order, snapshot visibility, delta
  reconciliation, normalized MCS, and counter RNG addresses.
- Specify topology-derived halos and reject incompatible tile/topology/component combinations before
  execution.
- Define the open tiled-component protocol skeleton, including dependency-radius, snapshot-state,
  scratch, energy, and reconciliation traits, before the optimized vertical slice depends on it.
- Add exact invariant, known-answer RNG, observation-invariance, and same-backend replay tests.
- Pre-register statistical observables, ensemble sizes, seeds, and equivalence tolerances.

Exit: the algorithm has executable semantics independent of GPU optimization.

## 12.5C: Resident 2D vertical slice

- Implement volume and adhesion on nonconflicting 2D tiles with sequential local proposals.
- Add deterministic cell-statistic snapshots, exact atomic deltas, and sub-round reconciliation.
- Implement shared-memory tile/halo loading and a semantically identical device-global fallback.
- Keep unobserved MCS execution allocation-free, transfer-free, and free of host synchronization.
- Validate CPU, Metal, and ROCm before adding further physics.

Exit: a 2D sorting model passes exact and statistical gates on all three backends with complete
proposal accounting and native traces.

## 12.5D: Open physics and 3D qualification

- Complete the open tiled-component compatibility and reconciliation implementations.
- Qualify surface/perimeter, prescribed-field chemotaxis, directional motility, Act-like state, and
  applicable HST state without duplicating Hamiltonian formulas.
- Add local connectivity support only where its bounded device protocol is valid; reject global
  traversal requirements explicitly.
- Implement 3D tiles and choose smaller-tile, streamed-halo, or device-global storage from static
  qualified policies.
- Verify custom compatible components can obtain the optimized path without CorePotts edits.

Exit: required 2D and 3D physics compile and execute on CPU, Metal, and ROCm; unsupported capability
fails during lowering rather than in a kernel.

## 12.5E: Profile-directed performance work

- Profile paper-scale end-to-end execution before changing mechanisms.
- Specialize concrete component tuples and fuse energy evaluation without dynamic kernel dispatch or
  per-component launches.
- Tune tiles, switching intervals, workgroups, layouts, atomics, shared memory, and justified
  intrinsics behind generic fallbacks.
- Track compilation, native code size, registers, spills, occupancy, traffic, launches, waits, and
  memory alongside throughput.
- Retain an optimization only when an end-to-end scientific workload justifies its complexity.

Exit: at least two representative paper-scale GPU workloads improve by 2x over
`CheckerboardSweepCPM`, the supported GPU matrix geometric mean improves, and all independent gates
pass.

## 12.5F: Scientific and external comparison battery

- Run the pre-registered proposal-frequency, waiting-time, acceptance, sorting, chemotaxis,
  persistence, morphology, Act-like, and collective-order ensembles.
- Confirm same-backend trajectory reproducibility and cross-backend statistical agreement.
- Run the reconstructed Sultan workloads and clearly separate matched absolute measurements from
  descriptive published ratios.
- Repeat full CPU, Metal, and ROCm performance groups in fresh processes and archive raw records,
  manifests, configurations, seeds, traces, and analysis programs.
- Re-run all existing algorithm regressions after shared infrastructure changes.

Exit: scientific equivalence and performance conclusions are reproducible from retained evidence;
no incomparable result enters a fastest claim.

## 12.5G: PottsToolkit integration and disposition

- Add the ordinary `solve(model, TiledCheckerboardCPM(); ...)` path and natural Level 1 coverage for
  compatible components.
- Document defaults, expert controls, provenance, failure modes, guarantee profile, and algorithm
  selection guidance.
- Verify package load, representative precompilation, first use, full tests, docs, structure,
  legacy-containment, and real-backend workflows on the exact candidate revision.
- Audit every contract item and record one disposition: promote, experimental, or reject.
- Update the Phase 13 entry gate and Phase 15 paper plan with the retained outcome.

Exit: the phase has a completion audit, green protected CI, and an explicit owner disposition. Phase
13 may then freeze the resulting public surface.

## Validation after every retained implementation change

- affected unit, integration, invariant, and reference tests;
- semantic RNG and observation-invariance checks;
- CPU plus available real Metal and ROCm device compilation and execution;
- zero-allocation, residency, transfer, and synchronization assertions;
- generic/shared-memory and generic/intrinsic equivalence where applicable;
- native resource and chronological trace comparison; and
- affected end-to-end baseline comparison before the full closure matrix.
