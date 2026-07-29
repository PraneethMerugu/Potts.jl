# [Logical state, effects, and reconciliation](@id state-effects-reconciliation)

> **Support level:** qualified serial reconciliation boundary.

A component never receives a mutable store. It receives a projection of one
committed snapshot and returns typed `Delta` values.

```text
committed snapshot
      │ projection
      ▼
  invoke actors ──→ candidate deltas
                         │
             validate type, owner, event,
              target, law, and capability
                         │
                         ▼
                  deterministic reconcile
                         │
                  atomic publication
                         ▼
                 next committed snapshot
```

The leaf schema declares its update-law contract. Additive and multiplicative
updates combine deterministically. Replacement and indexed/keyed updates apply
their explicit conflict laws; ProcessBigraphs does not choose a winner from
arrival order.

Failures before publication leave the prior committed snapshot authoritative.
No reader sees a partially reconciled event.

## Visibility

Reactive steps consume the just-published layer according to the compiled
dependency graph. Observers see only declared paths and cannot feed records
back into model state. Engine candidates are not logical state until
publication.

**Next:** [Time, schedules, and visibility](@ref time-schedules-visibility).
