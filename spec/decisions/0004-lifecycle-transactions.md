# Decision 0004: Transactional Deterministic Lifecycle

Status: Accepted

Date: 2026-07-17

Symbolic Potts V1 clarification: CCV1-027 in the
[compiler construction contract](../symbolic-potts-v1-compiler-construction.md) supersedes the
unconditional-retirement and retirement-time generation wording below. Each finite kind explicitly
selects `RetireAtZero` or `ForbidExtinction`; the latter makes zero occupancy an invariant failure.
Retirement preserves the consumed generation, which advances exactly once only when the slot is
allocated to a new identity.

## Context

Current lifecycle kernels allocate IDs through racing atomics, may partially handle capacity
exhaustion, retain stale property values, allocate before proving valid division geometry, and use a
global event interval.

## Decision

Lifecycle events execute at integer-MCS boundaries from one common trigger snapshot. Identity-
changing conflicts require explicit resolution. Division batches are stable and deterministic by
parent ID.

Division validates geometry before ID allocation and aborts the complete valid batch without mutation
if fixed capacity is insufficient. The parent retains its ID and the child receives the lowest
available ID. Derived state is recomputed; biological state follows schema inheritance.

Progressive shrink death and immediate death are distinct. Under `RetireAtZero`, a due ordinary
lifecycle retirement resets schema-owned state before publication. A `ForbidExtinction` kind
prevents normal final-site loss and treats any impossible zero-occupancy state as nonfilterable
corruption. Retired IDs become reusable on the next MCS in ascending order; generation advances on
the later allocation, not retirement.

Each event owns its integer-MCS schedule. Stable V1 GPU lifecycle actions are device executable;
host lifecycle actions are outside the V1/R2 support claim.

## Consequences

- Deterministic scans/compaction replace identity-allocation races.
- Capacity failure may require a lifecycle synchronization to raise a host exception.
- `N_cells` must be replaced by separate active-count, capacity, free-slot, and high-water concepts.
- Every property needs lifecycle metadata.
- Same-MCS death-to-birth ID reuse is prohibited.

## Required Evidence

- Atomic batch-abort capacity tests
- Deterministic parent/child assignment tests on all backends
- Geometry conservation and connectivity tests
- Complete retired-slot reset tests
- Event conflict and common-snapshot tests
- Cross-backend lifecycle diagnostics
