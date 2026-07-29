# [Time, schedules, and visibility](@id time-schedules-visibility)

> **Support level:** qualified normalized-integer logical time and serial
> scheduling.

`TimeScale` is an exact rational unit. `LogicalTime` is a point; `Duration` is
an interval. Conversion is allowed only when scales have an exact common
representation.

| Authoring schedule | Meaning |
|---|---|
| `Every(duration)` | periodic temporal process |
| `At(times...)` | finite exact one-shot boundaries |
| `On(store)` | activation after committed publication changes a store |
| `After(steps...)` | zero-time reactive dependency layer |

At one logical boundary, the runtime determines the complete due batch,
captures authorized projections, invokes processes, validates and reconciles
their effects, publishes atomically, evaluates reactive layers, records
observations, and settles.

```text
t=1 due → publish → observe → settled
t=2 due process A + B → one reconciled publish → reactive layers → observe
```

`ExactHorizon` may require partial-interval support to reach a noncadence
target. `StopPrior` stops before an unsupported partial boundary. Neither
policy rounds floating time.

Logical units are declarations, not evidence that one tick equals a measured
physical duration.

**Next:** [Hierarchy and open composition](@ref hierarchy-open-composition).
