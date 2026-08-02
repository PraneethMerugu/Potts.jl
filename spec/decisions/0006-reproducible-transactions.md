# Decision 0006: Algorithm-Scoped Reproducibility and Deterministic Transactions

Status: Accepted

Date: 2026-07-17

The cell-lifecycle specialization of this decision is CCV1-027 in the
[compiler construction contract](../symbolic-potts-v1-compiler-construction.md): lifecycle requests
derive finite read/write/emission footprints, conflicts, semantic priorities, RNG addresses, and
canonical allocation from one immutable pre-lifecycle snapshot.

## Context

Reproducible random bits do not ensure a reproducible or scientifically correct trajectory.
Order-sensitive floating-point reductions, racing tracker updates, shared cell-wide properties,
workgroup-dependent subgroup operations, and stale proposal reads can change state even when every
random draw is stable. Spatial coloring alone does not eliminate conflicts between distant sites that
belong to the same cell.

Unqualified claims that an algorithm is "exact" conflate its proposal schedule, equilibrium
distribution, kinetics, transactions, time normalization, and reproducibility.

## Decision

Each algorithm has a programmatically inspectable guarantee profile. Exactness claims are qualified
by property. Sequential Metropolis remains the reference `N`-attempt process. Checkerboard and
lottery are distinct parallel dynamics whose equilibrium guarantees require separate proofs.

Every component declares semantic read and write scopes. The compiled model derives conflicts from
the union of those scopes. The default strict parallel transaction generates candidates from a
snapshot, selects a conflict-free subset using semantic random priorities, evaluates the subset
against that snapshot, and commits compatible accepted changes. Conflict losers are no-ops and are
not resampled.

Strict reductions have a defined logical order. Order-sensitive floating atomics and undeclared fast
math do not define strict state. Hardware dispatch, subgroup width, thread count, workgroup size,
scheduling, and memory pressure do not silently change the requested semantics.

Paper-facing supported algorithms default to strict execution. Unsupported strict execution is an
error. A preflight report explains the promised guarantee, limitations, numeric profile, custom
components, and workspace requirements.

## Consequences

- Components require auditable access-scope metadata.
- Algorithm compatibility becomes a compilation concern.
- Some models require deterministic conflict selection even under perfect lattice coloring.
- Intrinsic kernels are internal optimizations only when they match the generic transaction law.
- Relaxed high-performance dynamics remain possible but cannot inherit unproven exactness claims.
- Debug proposal traces and release-level conformance artifacts become part of validation.
- Reproducibility metadata and model fingerprints become public solution behavior.

## Alternatives Considered

Treating lattice coloring as sufficient conflict avoidance was rejected because cell-wide state
connects distant sites. Allowing atomic arrival order to define reductions was rejected for strict
profiles. Silently falling back to relaxed arithmetic or racing updates was rejected because users
could not determine which scientific process was executed.

## Required Evidence

- Access-scope and conflict-derivation tests
- Deterministic transaction traces across workgroup configurations
- Generic-versus-intrinsic equivalence tests when they share an algorithm name
- Numerical-profile and fixed-reduction tests
- Small-system equilibrium validation for every equilibrium claim
- Kinetic characterization for every named parallel dynamics
- Preflight and incompatibility-report tests
- Strict and relaxed performance benchmarks on all first-class backends
