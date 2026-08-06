# Phase 14.1 G3-A Generic Authoring Evidence

Status: Complete

Date: 2026-07-25

Governing decisions:

- [Decision 0031](../../spec/decisions/0031-phase-14-single-semantic-kernel.md)
- [Decision 0032](../../spec/decisions/0032-phase-14-gpu-native-promotion.md)
- [Decision 0033](../../spec/decisions/0033-phase-14-generic-hierarchical-authoring.md)

## Scope

G3-A is the authoring and canonical-lowering entry gate for Wang. It does not claim that Wang's
scientific execution capabilities are implemented or GPU-qualified. Those remain G3-B and G3-C.

G3-A requires:

1. named typed fragment requirements and exports;
2. nested lexical composition and private declaration enforcement;
3. one explicit root plan with no fragment-local scheduler;
4. fragment versus direct-leaf canonical identity;
5. typed binding mismatch rejection before lowering;
6. transitive backend requirements without fragment-local fallback;
7. unchanged flat Phase 13 construction; and
8. one generic Wang authoring fixture that lowers and preserves the accepted execution order.

## Implementation evidence

The existing `ModelFragment` is extended in place. `FragmentPortContract`,
`FragmentRequirement`, and `FragmentExport` are immutable host authoring values. Contracts cover
semantic category, owner, schema, units, operation kind, lifecycle obligations, scientific
capabilities, and CPU/Metal/ROCm requirements. `fragment_port_contract` is the open extension
protocol for third-party declaration families.

Named exports are available as immutable property-like values, while unknown or private names
reject. Nested fragments qualify private identities lexically. A child export becomes private to
its parent unless explicitly re-exported.

Composition validation now rejects:

- unresolved typed requirements;
- category, owner, schema, unit, operation, lifecycle, capability, and backend mismatches;
- unknown exports;
- private operations referenced by the root plan;
- fragment-local execution plans;
- missing plan operations; and
- more than one root `MCSPlan`.

`required_backends(model)` reports the transitive pre-launch backend requirement set for the fully
validated authoring graph. It is deliberately not a qualification claim; runtime preflight still
rejects unsupported law/storage/backend tuples.

CorePotts process invocations now accept an explicit integer-MCS schedule as their root-plan
activation. Because CompuCell3D source MCS `k` maps to normalized target MCS `k+1`, Wang's source
`mcs % 10 == 0` focal retuning is represented by `PeriodicMCS(1, 10; stop = 491)` in the sole plan
instead of a hidden subsystem scheduler.

## Conformance evidence

The historical generic-fragment tests, formerly at
`test/test_phase14_generic_fragments.jl`, established:

- named requirements and property-like exports;
- nested re-export and private qualification;
- binding and complete mismatch truth tables;
- direct-leaf versus fragment-packaged fingerprint identity;
- substitution locality;
- one-root-plan enforcement;
- fragment-local-plan and private-plan rejection;
- transitive backend requirement identity; and
- explicit periodic process cadence.

The historical Wang authoring fixture, formerly at
`integration/conformance/test_phase14_wang_authoring.jl`, established that four
generic fragments—secretome coupling, intracellular signaling, focal adhesions, and directed
motility—compose with one root plan, lower through the ordinary PottsToolkit path, and retain:

- accepted-copy focal topology during Potts attempts;
- field solve;
- centroid sampling;
- self-polarity update;
- uptake;
- intracellular dynamics;
- focal retuning every ten MCS;
- neighbor alignment;
- protrusion update;
- lifecycle; and
- final observation.

The fixture checks source MCS 0, 120, 210, and 211 through normalized target MCS 1, 121, 211, and
212 and contains no paper-specific CorePotts or PottsToolkit export.

## Reproducer

```sh
julia --project=. scripts/check_phase14_g3a.jl
julia --project=. scripts/check_phase14_0.jl
julia --project=. scripts/check_phase13_api_inventory.jl
julia --project=. scripts/check_structure.jl
julia --project=. scripts/validate_wang_order_oracle.jl \
  design/evidence/phase-14/wang-order/cc3d-4.2.5-trace.csv
```

Recorded local result on Julia 1.12.6:

- dedicated G3-A gate: 40/40 assertions passed;
- complete CorePotts suite: 3,023/3,023 tests passed;
- complete PottsToolkit suite: 702/702 tests passed;
- Phase 14 architecture checker: passed;
- frozen Phase 13 API inventory: unchanged, with only reviewed Phase 14 additions;
- repository structure and legacy-containment checkers: passed; and
- accepted Wang CC3D 4.2.5 execution-order trace: passed.

## Boundary

G3-A closes only the generic authoring and lowering gate. It does not count structural placeholder
laws in the Wang fixture as scientific Wang implementations. G3-B must replace those placeholders
with the registered CPU-reference state, field, ODE, relationship, and observation laws. G3-C
then closes the same capability set on real Metal and ROCm with residency, restart, transfer,
allocation, and performance evidence.
