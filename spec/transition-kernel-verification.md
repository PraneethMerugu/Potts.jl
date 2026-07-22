# Transition-Kernel Verification and Algorithm Characterization

Status: Accepted; implementation deferred to Phase 13

The project-owner entry, evidence, and API-freeze policy is recorded in
[Decision 0028](decisions/0028-phase-13-entry-and-freeze-policy.md).

## Purpose

This document defines the mathematical and empirical evidence required to characterize Potts.jl
execution algorithms as finite-state stochastic processes. Its first purpose is to determine exactly
how `CheckerboardSweepCPM` differs from the declared sequential process at proposal, internal-round,
and normalized-MCS resolution. It also establishes a reusable qualification protocol for later
algorithms without treating one small-state result as proof for realistic tissues.

The transition oracle is research and conformance machinery. It does not become part of ordinary
simulation execution and MUST NOT add dependencies, compilation, allocation, dispatch, tracing, or
synchronization to the production engine.

## Phase Ordering

The specification and implementation plan MAY be completed before execution begins. Phase 13
implementation MUST NOT begin, consume self-hosted qualification runners, or modify qualified
algorithm code until Phase 12.CPU and the remaining Phase 12 closure work are complete and Phase
12.5 has recorded its promote, experimental, or reject disposition.

Phase 13 initially qualifies the sequential and ordinary checkerboard families. `LotteryCPM` and a
retained `TiledCheckerboardCPM` MUST use the same protocol later, but their full matrix
characterization does not block the initial sequential--checkerboard result unless a paper claim
depends on it.

## Markov State and Time Resolution

For an admissible finite fixture, the oracle defines a transition kernel `P(x, y)` over the complete
logical state needed to determine the distribution of the next transition. The state initially
contains distinct ownership labels, applicable discrete cell state, and any scheduler state that
affects the next transition. Cell identifiers remain distinct. Symmetry quotienting is prohibited
until a proof shows that the quotient preserves the transition law being tested.

The oracle MUST construct, where applicable:

- the primitive candidate-attempt kernel;
- each algorithmic sub-round or color-pass kernel; and
- the complete kernel for exactly one normalized MCS.

These kernels MUST use the proposal budgets and time laws in
[Time and Monte Carlo Steps](time-and-mcs.md). Comparing algorithms after unequal declared time or
unequal proposal-budget semantics is invalid.

If color, phase, sub-round index, randomized color order, residual-round placement, or other
scheduler state changes the next-step law, that state MUST appear in a lifted Markov state. A
configuration-only kernel MAY additionally be reported after an explicit, documented
marginalization. Phase dependence MUST NOT be hidden.

## Independent Reference Oracle

The oracle MUST be independent of optimized proposal, local-delta, transaction, and kernel code. It
computes a hypothetical destination through direct logical-state mutation, evaluates global energy
before and after the move, applies the declared proposal and acceptance equations, and accumulates
all paths leading to the same destination. Rejected, invalid-boundary, same-owner, constraint, and
conflict outcomes contribute to the appropriate self-transition or destination probability.

The oracle MAY reuse stable semantic values and state accessors. It MUST NOT establish correctness by
calling the same optimized `delta_H`, proposal, conflict, or commit implementation being tested.
Global-before/global-after energy checks independently validate optimized local deltas.

Combinatorial probabilities use exact integer or rational arithmetic where possible. Metropolis
exponentials and other non-rational values use configurable high-precision arithmetic. Reports MUST
retain precision and convergence evidence and MUST NOT call a floating approximation symbolically
exact. Row nonnegativity and row sums receive explicit error bounds.

The initial implementation uses ordinary typed Julia, sparse matrices, and multiple dispatch. A
symbolic-algebra dependency is admitted only after a measured or scientific need that the explicit
oracle cannot satisfy.

## Initial Fixture Domain

The first exhaustive domain is frozen and discrete. It covers occupancy, distinct cell labels and
types, Cartesian topology, boundary realization, proposal law, acceptance law, and admitted energy
or hard-constraint state. Evolving fields, lifecycle events, division, continuous auxiliary state,
general fragmentation-state enumeration, XML interchange, NeuralPotts, and new lattice families are
excluded unless one is required to resolve a paper-core algorithm claim.

Required fixture progression is:

1. one hand-auditable one-dimensional derivation reproduced independently by generated code;
2. exhaustive two-dimensional suites on deliberately tiny lattices; and
3. selected minimal three-dimensional fixtures proving dimensional lowering rather than attempting
   exhaustive realistic 3D enumeration.

The initial topology and boundary matrix includes von Neumann and Moore proposal neighborhoods and
periodic and no-flux boundaries. Additional topology families use the same admission protocol.

Adhesion and volume form the first complete energy slice. Surface, connectivity, and discrete
auxiliary or mechanical families are admitted separately. Each family MUST pass global-energy,
local-delta, state-invariant, and transition-kernel checks before receiving a qualification result.

## Sequential Obligations

For the conventional sequential family, the oracle verifies exact agreement with the declared
with-replacement proposal and modified-Metropolis transition law. This does not imply a Boltzmann
stationary distribution; the prohibition in
[Energy, Proposals, Acceptance, and Trackers](energy-proposals-and-trackers.md) remains controlling.

For an equilibrium-targeting sequential family, applicable fixtures additionally test reversible
support, stationary distribution, pairwise detailed balance, communicating classes, irreducibility,
and aperiodicity. A result is scoped to the declared admissible state space and acceptance law.

## Checkerboard Obligations

The normative checkerboard matrix represents the production scheduler exactly: actual coloring,
color-order randomization, snapshot visibility, proposal selection, transaction law, conflict
handling, and full-MCS construction. An idealized schedule is a separately named experiment and
cannot qualify production execution.

The oracle begins without presuming that checkerboard execution preserves sequential kinetics,
detailed balance, or a sequential stationary distribution. It determines which properties hold.
An unexpected difference is first recorded as a scientific result. Changing the algorithm is a
separate decision and MUST NOT erase the evidence that motivated it.

For commuting proposals the oracle MAY factor a joint color-pass kernel into proposal kernels. When
shared cell state, snapshot reads, conflicts, or reconciliation prevent commutation, it MUST
enumerate the actual joint transition law.

## Guarantee Taxonomy

An algorithm receives only evidence-supported labels from this taxonomy:

- detailed-balance preserving on a declared admissible domain;
- stationary-distribution preserving without detailed balance;
- convergent to a declared reference under an explicit limit;
- observably comparable within a qualified model and parameter domain; or
- unqualified.

The unqualified word `exact` is not a guarantee. Reports distinguish exact combinatorial
enumeration, bounded high-precision numerical evaluation, proof, empirical agreement, and
large-ensemble evidence.

## Required Matrix Characterization

Total-variation distance is the principal row-wise and stationary-distribution discrepancy measure.
Absolute transition residuals are always retained. KL divergence and null-hypothesis p-values MAY
supplement but MUST NOT replace metrics that remain meaningful under unequal transition support.

Applicable exhaustive fixtures report:

- transition support and self-transition probability;
- stationary distributions and stationarity residuals;
- pairwise detailed-balance residuals when claimed;
- probability currents and cycle behavior;
- eigenvalues, spectral gaps, and relaxation modes; and
- conditional drift and diffusion of declared observables.

The oracle searches its bounded fixture domain for states maximizing sequential--checkerboard
discrepancy. Found states become versioned regression fixtures. Offline tooling SHOULD minimize a
counterexample's lattice, labels, and active interactions while retaining its discrepancy; this
minimization is not a pull-request CI requirement.

Parameter characterization uses a small preregistered grid spanning temperature, energy scale,
topology, boundary class, occupancy, active fraction where applicable, and internal-round count.
Deterministic limits and degenerate cases are included deliberately. The grid MUST remain bounded
and justified rather than grow combinatorially.

## Empirical and Cross-Backend Verification

Empirical transition rows use many independent replicas initialized from one source state. A single
correlated trajectory is not the primary row estimator. Statistical plans declare confidence
levels, multiplicity handling, minimum detectable discrepancies, sample counts, seeds, and stopping
rules before qualification results are examined.

CPU, Metal, and ROCm compare empirical destination counts against the independent oracle where the
fixture is supported. Same-backend replay remains governed by the semantic RNG contract. Cross-
backend bitwise or trajectory identity is not required; cross-backend transition distributions MUST
meet the preregistered scientific criteria.

Exact microstate results do not establish realistic-tissue equivalence by themselves. Algorithm
claims about practical kinetics or equilibrium require larger ensemble studies with applicable
energy, morphology, sorting, migration, autocorrelation, mixing, and effective-sample-size
observables.

## Evidence Identity and Invalidation

Every matrix and empirical record retains at least:

- model and initial-state fingerprints;
- algorithm semantic identity and scheduler version;
- RNG contract version and semantic seed/address information;
- topology, boundary, dimension, acceptance law, temperature, and admitted components;
- backend, precision, high-precision convergence settings, and source revision; and
- fixture, sampling plan, raw counts, thresholds, and analysis-program identity.

A change to proposal selection, coloring, conflict handling, acceptance, MCS normalization,
snapshot visibility, reconciliation, or scheduler order invalidates affected qualification. A
mechanical change may retain qualification only when structural and transition evidence establishes
that the scientific kernel is unchanged.

User-facing capability or adjacent algorithm reports state the verified guarantee, qualified model
domain, maximum observed discrepancy, tested backends, and evidence version. They MUST NOT imply the
same guarantee outside the admitted domain.

## CI and Failure Artifacts

Verification is tiered:

- tiny deterministic oracle checks on every pull request;
- broader CPU matrix suites on scheduled or protected-main CI;
- empirical Metal and ROCm transition tests on scheduled and release CI; and
- exhaustive paper sweeps in archived research workflows.

Failures retain the source state, destination residuals, model and algorithm identities, parameters,
scheduler phase, seed/address information, exact or high-precision row, empirical row, uncertainty,
and visualization-ready data. A red statistical result without a reproducible forensic artifact is
not a sufficient release gate.

The paper archive retains machine-readable matrices, state encodings, parameter grids, raw empirical
counts, analysis programs, thresholds, environments, and figure-generation code.

## Phase 13 Closure

Phase 13 cannot close until:

1. sequential production behavior passes its applicable independent reference obligations;
2. checkerboard execution receives an evidence-supported guarantee label;
3. CPU, Metal, and ROCm pass applicable empirical transition tests;
4. exact microstate conclusions are reconciled with required larger-ensemble evidence;
5. the specification-to-evidence index and user-facing reports point to current records; and
6. every resulting stable, experimental, limited-domain, or rejected claim is reflected in the API
   freeze and paper semantics.
