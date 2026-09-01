# LM-1 C2 runtime-relation cutover

## Decision

Runtime-keyed publication is spatial addressing, not a fourth publication law.
A prepared `RuntimeRelation` is the sole bounded partial map from an `Int32` or
`UInt32` evaluator key to a codomain endpoint. Typed routed carriers feed the
ordinary `Unique`, `Reduce`, and `Resolve` laws through the existing candidate
Stage executor.

Exact key semantics:

- a nonparticipating carrier is inert;
- key zero is intentional absence and does not fail;
- a participating nonzero key in `1:length(codomain)` routes normally;
- any other participating nonzero key fails the Stage with `ROUTE_KEY` and
  suppresses every publication;
- `Resolve` validates every participating rank before classifying its route.

Status precedence remains deterministic:

```text
INVALID_CONTROL > RELATION > ROUTE_KEY > RANK_BOUNDS >
DUPLICATE_TIE > CONFLICT > COVERAGE > SUCCESS
```

This is the named package-owned diagnostic receipt priority; it does not alter
candidate, conflict, routing, or numerical semantics.

## One execution path

Routed carriers enter the same candidate materialization, destination grouping,
validation, settlement, and guarded publication phases as structurally routed
carriers. The prepared runtime relation view is an isbits ordinal-address law;
there is no host lookup, route table, warm conversion, backend branch, or
`ProgramRelationshipState` involvement. CPU and Metal execute the same
KernelAbstractions kernels and workspace representation.

## Direct deletion

The cutover deleted the prior runtime-keyed semantic and execution authority:

- `_RuntimeRoute` and `runtime_route`;
- the old keyed emission/candidate carrier family;
- `_KeyedGroupedLowering`, `_KeyedPortPlan`, and `_lower_keyed`;
- keyed-only plan, prepared-phase, workspace, evidence, inspection, binding,
  and execution hooks; and
- `execution/localworksets_keyed.jl` and its include/export.

There is no adapter, compatibility constructor, execution selector, or retained
legacy production path.

## Focused evidence

- CPU routed Stage witness: 10/10 assertions for `Unique`, canonical `Reduce`,
  `Resolve`, zero-key absence, invalid-key failure, and failure no-write.
- Real Metal (`Metal.allowscalar(false)`, `N = 513`): 4/4 routed assertions,
  including deterministic invalid-key no-write.
- Existing real-Metal candidate witnesses after the generalized claim ABI:
  Unique 6/6, Reduce 9/9, Resolve 15/15, grouping 4/4.
- Production exact-word scan for `_RuntimeRoute`, `runtime_route`,
  `_KeyedGroupedLowering`, and `_lower_keyed`: clean.

## Review gate

Scientific semantics and legacy-authority deletion: PASS. GPU kernel behavior:
PASS for the focused same-device KA candidate spine. Lifecycle integration:
REVISE.

The candidate Stage preparation is not yet dispatched by the sole
`WorkPlan`/`PreparedWork`/`WorkEvent` lifecycle; focused evidence currently
materializes its workspace and invokes it directly. Therefore this document is
evidence for the runtime-routing semantic/executor cut, not final LM-1 adoption.
The gate remains open until the candidate status and relation receipt enter the
single cumulative event ABI with ordinary lease ownership, poisoning, and
inspection, and the manual orchestration ceases to be a production authority.

Collection and ordered recurrence remain separate pending C3 because neither
is mathematically a runtime destination-conflict law.
