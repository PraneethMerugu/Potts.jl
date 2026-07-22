# Phase 13 Algorithmic Conformance and API Freeze Chunk Plan

Status: Accepted plan; blocked on Phase 12.CPU, Phase 12 closure, and Phase 12.5

Date: 2026-07-22

## Objective

Characterize the microscopic and normalized-MCS transition laws of the production sequential and
checkerboard algorithms before freezing their public guarantee profiles. Integrate the resulting
evidence into the existing Phase 13 API, conformance, version, and legacy-removal gate.

The governing semantic contract is
[Transition-Kernel Verification and Algorithm Characterization](../../spec/transition-kernel-verification.md).
The project-owner scope, evidence, and freeze choices are recorded in
[Decision 0028](../../spec/decisions/0028-phase-13-entry-and-freeze-policy.md).
Planning and specification may proceed now. Implementation must not modify qualified algorithm code
or consume self-hosted qualification runners until Phase 12.CPU and Phase 12 close and Phase 12.5
records a promote, experimental, or reject disposition.

## 13A: Independent finite-state oracle

- Define typed logical microstates, destination identity, sparse transition records, and complete
  scheduler-state lifting.
- Enumerate direct logical proposals and compute global-before/global-after energies independently
  of optimized delta and commit paths.
- Use exact rational probabilities where possible and configurable high precision with convergence
  records otherwise.
- Add row nonnegativity, row-sum, support, state-invariant, and global/local energy cross-checks.
- Reproduce one complete hand-derived pedagogical kernel.

Exit: the generated oracle reproduces the reviewed derivation and has no dependency on production
proposal, delta, conflict, or commit implementations.

## 13B: Sequential reference qualification

- Construct primitive-attempt and complete normalized-MCS kernels for conventional sequential CPM.
- Verify exact agreement with its declared with-replacement proposal and acceptance law without
  inferring a Boltzmann stationary claim.
- Qualify applicable equilibrium-targeting sequential fixtures for reversible support, detailed
  balance, stationarity, communicating classes, irreducibility, and aperiodicity.
- Cover required 1D, exhaustive 2D, and selected 3D fixtures with distinct cell labels.

Exit: every stable sequential guarantee points to an independent kernel result on its declared
admissible domain.

## 13C: Production checkerboard characterization

- Encode actual coloring, randomized color order, snapshot visibility, commit law, conflict
  handling, and phase in lifted transition states.
- Construct color-pass and complete normalized-MCS kernels and compare them with the appropriate
  sequential reference.
- Report transition support, self-transitions, total-variation distance, stationary distributions,
  detailed-balance residuals where applicable, probability currents, spectral gaps, relaxation
  modes, and observable drift/diffusion.
- Search for and retain maximum-discrepancy states; minimize selected examples offline.
- Assign only an evidence-supported guarantee-taxonomy label.

Exit: checkerboard's differences from sequential execution are mechanistically explained and its
public guarantee profile is no longer provisional.

## 13D: Fixture and component admission

- Complete von Neumann/Moore and periodic/no-flux fixture coverage.
- Qualify adhesion and volume first, followed separately by surface, connectivity, and applicable
  discrete auxiliary/mechanical families.
- Pre-register a bounded parameter grid over temperature, energy scale, occupancy, topology,
  boundaries, and algorithmic scheduling parameters.
- Keep fields, lifecycle enumeration, interchange, NeuralPotts, and new lattice families outside the
  phase unless required by a paper-core claim.

Exit: each admitted family has global energy, local delta, invariant, and transition-kernel evidence;
excluded families receive no implied matrix qualification.

## 13E: Empirical backend and realistic-scale evidence

- Pre-register confidence levels, multiplicity handling, minimum detectable effects, sample counts,
  seeds, and stopping rules.
- Estimate transition rows through independent replicas from fixed source states on CPU, Metal, and
  ROCm and compare them with the oracle.
- Retain forensic failure artifacts including source state, scheduler phase, exact/high-precision
  row, empirical row, residuals, uncertainty, and RNG identities.
- Run larger ensembles for applicable energy, morphology, sorting, migration, autocorrelation,
  mixing, and effective-sample-size observables.

Exit: all supported backends satisfy the transition criteria, and no realistic-model claim rests on
tiny-state enumeration alone.

## 13F: Evidence publication and CI tiers

- Add tiny deterministic oracle checks to pull-request CI and broader CPU suites to scheduled or
  protected-main CI.
- Add scheduled/release Metal and ROCm empirical transition workflows without per-MCS host
  synchronization in production execution.
- Archive matrices, state encodings, parameter grids, raw counts, thresholds, environments,
  analysis programs, and figure-generation code.
- Generate transition-difference, probability-current, relaxation, observable-drift, and
  speed--fidelity figures from archived machine-readable records.
- Version evidence by model, algorithm, scheduler, RNG, backend, precision, and source revision.

Exit: qualification can be reproduced from retained records and algorithm-semantic changes make
stale evidence visible.

## 13G: Full conformance and API freeze

- Update capability reports with guarantee label, qualified domain, maximum observed discrepancy,
  tested backends, and evidence version.
- Complete export, constructor, extension-point, display, structured-error, Aqua, ambiguity,
  inference, allocation, device-code, clean-install, and documentation audits already assigned to
  Phase 13.
- Remove remaining legacy paths, stale dependencies, provisional claims, and unsupported stable
  surfaces.
- Freeze the paper RNG, IR, checkpoint, fingerprint, result-schema, and admitted algorithm contract
  versions.
- Record Lottery and any retained `TiledCheckerboardCPM` as later protocol consumers unless a paper
  claim requires their full qualification before freeze.

Exit: the independent sequential obligations pass, checkerboard has an evidence-supported label,
CPU/Metal/ROCm pass applicable empirical gates, the conformance index is current, and the owner
approves the paper API freeze.
