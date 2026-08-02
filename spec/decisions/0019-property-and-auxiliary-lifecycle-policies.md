# Decision 0019: Schema-Owned Property and Auxiliary Lifecycle Policies

Status: Accepted

Date: 2026-07-19

The closed Symbolic Potts V1 structural effects, pure lifecycle-policy ABI, policy resolution,
immutable semantic before/planned-after views, and external conformance boundary are specified by
CCV1-027 in the
[compiler construction contract](../symbolic-potts-v1-compiler-construction.md). This decision
continues to own schema-level biological, auxiliary, and derived-state lifecycle behavior.

## Context

The future property schema already needs initialization, division, transition, and retirement
behavior, but current and historical code encode parts of that behavior through several enums,
central switches, and a separate inheritance hierarchy. Keeping both models would make extension
require CorePotts edits and would permit built-in defaults to acquire undocumented meaning for user
properties.

Derived state and auxiliary state also require different scientific treatment. Derived observables
must follow authoritative ownership state, while an auxiliary family may require a conditional
distribution, conservation law, transformation, or explicit incompatibility.

## Decision

The compiled property schema is the sole authority for property lifecycle behavior. Each property
has separate typed policy values for initialization, division, type transition, and retirement.
Policies implement small operation-specific Julia protocols; there is no stable behavioral enum,
universal lifecycle-policy object, parallel inheritance hierarchy, or central concrete-policy
switch.

Built-in schemas may provide explicit documented policies. Every custom property must select a
policy or explicitly declare the corresponding operation unsupported. Missing behavior is a
construction error, and an event override must be explicit, compatible, unambiguous, and recorded
in provenance.

Derived properties never use ordinary biological inheritance or transition policies. Their open
family protocol declares authoritative dependencies, invalidation, recomputation or incremental
repair, and execution capabilities. The engine must restore derived-state consistency after commit
before publishing the completed lifecycle boundary.

Each auxiliary family owns its initialization, division, transition, death, extinction, retirement,
and reuse laws where applicable. Missing family mathematics makes only that combination unsupported;
there is no generic clone, reset, zero, or conservation fallback. Equilibrium families require a
derived post-operation distribution. Mechanical families state their physical law without
inheriting an equilibrium claim.

Compiled policies plan from the common pre-lifecycle snapshot into compact bounded update
descriptions. All plans validate before atomic commit. GPU-qualified policies lower to concrete,
allocation-free, device-resident behavior under the current CPU, Metal, and ROCm contract.

## Consequences

- Phase 8 replaces, rather than wraps, competing enums and the legacy `InheritanceRule` path.
- Small policy values can be reused and extended through ordinary multiple dispatch.
- Custom properties cannot accidentally clone, reset, or survive retirement.
- New derived-property families remain extensible without weakening state consistency.
- An unsupported lifecycle operation is visible during construction with property and event
  provenance.
- Family-specific auxiliary lifecycle distributions remain required scientific evidence.

## Alternatives Considered

- Retain separate modern enums and legacy inheritance objects.
- Put every operation on one large lifecycle-policy subtype.
- Give all custom properties a clone-on-division and zero-on-retirement default.
- Let derived properties participate in ordinary inheritance.
- Apply a generic clone or reset rule to every auxiliary family.
- Allow host callbacks to repair unsupported GPU lifecycle behavior.

These alternatives create duplicate authority, accidental scientific meaning, closed implementation
switches, or hidden loss of GPU residency.

## Required Conformance Evidence

- A downstream custom biological property with non-built-in division, transition, and retirement
  policies, added without CorePotts source edits.
- Missing-policy, explicit-unsupported, incompatible-override, and ambiguous-override diagnostics.
- Derived-property invalidation and reconstruction tests after division, transition, death, and slot
  reuse.
- Atomic multi-property rollback tests when one plan is invalid.
- Family-specific equilibrium-distribution or mechanical-law evidence for every supported auxiliary
  operation.
- Semantic RNG isolation for stochastic inheritance and auxiliary initialization.
- CPU, Metal, and ROCm compile-and-run tests for GPU-qualified downstream policies.
- Inference, allocation, bounded-workspace, synchronization, compile-latency, and steady-state
  performance gates before API freeze.
