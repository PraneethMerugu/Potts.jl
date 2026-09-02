# Decision 0016: Phase 7 Algorithms, Normalized Time, and First-Class Auxiliary State

Status: Accepted

Current disposition: superseded in part by [Decision 0044](0044-pre-g6-cohesion-and-mtk-hardening.md).
The scientific distinction between sequential and parallel processes survives; the old active
algorithm inventory and product-roadmap placement do not govern G5H.

Date: 2026-07-18

## Context

The reference, execution, RNG, topology, and scientific-inner-loop foundations are complete, but the
historical algorithms still expose `active_fraction` and `sweeps_per_step`, conflate implementation
technique with scientific process, and contain unqualified HST and detailed-balance claims.

Conventional CPM literature defines one MCS by `N` random copy attempts on an `N`-site lattice.
Parallel schedules can change recipient waiting times, shared-cell interactions, and biological
kinetics even when their aggregate attempt count is similar. Phase 7 therefore cannot treat
checkerboard, lottery, or subgroup execution as transparent accelerations of the sequential chain.

The project also considers auxiliary constraint and pressure/tension dynamics a defining feature.
Deferring their state and clock until after algorithm design would make them special cases, while
accepting the historical HST claims without derivation would be scientifically unsafe.

## Decision

The stable Phase 7 algorithm families are `SequentialCPM`, `SequentialEquilibrium`,
`CheckerboardSweepCPM`, and `LotteryCPM`. The no-algorithm SciML default is `SequentialCPM` on every
backend. GPU initialization with that default emits one informational message and never changes the
algorithm.

`SequentialCPM` and `SequentialEquilibrium` perform exactly `N` independent recipient selections
with replacement. `CheckerboardSweepCPM` schedules every mutable site exactly once without
replacement in randomized color order and makes no sequential-kinetic claim. `LotteryCPM` gives
every mutable site one activated attempt per MCS in expectation through a statically compiled,
topology-qualified schedule. Once activated, no-op, dynamic-conflict, constraint-rejected, rejected,
and accepted outcomes all consume the opportunity. Runtime contention never causes compensating
rounds.

Stable lottery support is limited to realized topologies whose per-site activation and schedule have
been derived and qualified. Residual round placement and semantically meaningful round order are
randomized. Attempt diagnostics expose scheduler work, activated attempts, conflicts, rejections,
and accepted moves.

Algorithm names identify the process. The word `exact` qualifies a specific guarantee rather than
serving as an algorithm name. Intrinsic implementations retain an algorithm name only when they
preserve its complete semantics. Deliberately relaxed implementations use separately visible
approximate names.

Fluctuating mechanical state is a first-class Phase 7 component category. The historical real
`HST...Penalty` law is rejected: its positive constitutive mean and positive copy-work sign cannot
come from one real Gibbs joint, and a genuine positive-quadratic Hubbard-Stratonovich identity uses
an imaginary coupling. Exact classical quadratic volume and surface Hamiltonians remain the stable
equilibrium constraints. Separately named fluctuating volume pressure and surface tension follow a
derived OU mechanical law and make no detailed-balance or marginal-equivalence claim. They use
normalized MCS subintervals, semantic RNG, ordinary component and lifecycle protocols,
backend-resident storage, and explicit algorithm capability checking. Length and focal-point state
remain experimental until independently qualified.

## Consequences

- Backend selection cannot silently change scientific dynamics.
- Parallel MCS values are comparable declared units, not claims of sequential kinetic equivalence.
- `active_fraction` and `sweeps_per_step` disappear from the public time API.
- Lottery topology or component combinations lacking qualification fail before execution.
- Connectivity workspaces and focal/moment coupling are stable sequential capabilities and explicit
  checkerboard/lottery rejections; speculative parallel support does not block Phase 7.
- HST claims and historical type names are removed before the paper API freeze; no migration alias
  is required.
- Volume-pressure and surface-tension mechanical integration are on the Phase 7 critical path;
  family-specific division and transition distributions complete with lifecycle in Phase 8.
- The historical engine remains a frozen implementation quarantine only until PottsToolkit's
  production compiler reaches conformance parity in Phases 10--11. Premature deletion is not a
  Phase 7 gate; frozen production digests, exhaustive consumer signatures, and a replacement-path
  scan prohibit edits, fallback edges, and new consumers independently of pull-request history
  until the owning migration deletes it.
- GPU optimization remains free to change storage, kernel decomposition, and intrinsic use while
  preserving the selected algorithm and auxiliary contracts.

## Alternatives Considered

- Automatically select a faster algorithm when a GPU backend is requested.
- Count only accepted moves or compensate dynamically for conflicts when advancing MCS time.
- Describe checkerboard and lottery as ordinary sequential CPM accelerations.
- Permit lottery execution on unqualified topologies with documentation alone.
- Preserve historical HST names and claims as compatibility behavior.
- Defer all auxiliary state until after the algorithm refactor.
- Design a universal auxiliary-variable framework before implementing a concrete family.

## Required Conformance Evidence

- Exact sequential `N`-attempt accounting and strict CPU replay.
- Checkerboard once-per-site accounting, randomized color order, explicit scheduling law, and
  declared absence of sequential-kinetic/equilibrium equivalence.
- Lottery per-site and boundary-class activation, waiting-time, spatial-correlation, conflict, and
  normalized-budget evidence.
- Common-snapshot transaction, tracker, RNG-address, and diagnostic reconciliation fixtures.
- Small-state invariant-distribution evidence before any parallel equilibrium claim.
- Valid auxiliary joint or mechanical laws, normalized-time integration, semantic RNG, and required
  CPU, Metal, and ROCm statistical qualification.

## Migration Impact

The project has not frozen a public paper API. Legacy algorithms using `active_fraction`,
`sweeps_per_step`, ambiguous sampler names, or historical `HST...Penalty` claims are replaced rather
than supported through migration aliases. Documentation, tutorials, and benchmarks are migrated only
after the package implementations and conformance tests stabilize.
