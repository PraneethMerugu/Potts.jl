# [Dynamic structural transactions](@id structural-transactions)

> **Support level:** atomic structural transaction primitives are qualified;
> domain policies remain explicit.

Dynamic structure changes through typed requests addressed to one source
epoch. Requests may add, divide, remove, move, or rewire. Each carries a stable
identity, dependencies, priority, and typed targets.

```text
source epoch
    │ requests
    ▼
deterministic selection ── conflicts/capacity → dispositions
    │
reference validation → rewrite candidate → structural + numeric validation
    │
    ├── failure: source epoch remains authoritative
    └── success: publish one immutable successor epoch + lineage
```

A division cannot guess numeric inheritance, geometry, field deposition,
lineage, or child connection policy. `allow_instances!` declares a reusable
definition and finite capacity; `spawn` and `divide` author requests only when
the caller supplies the required structural identities and policies.

Checkpoints record epoch identity and lineage. Stale requests, stale
candidates, generation mismatches, incomplete owned closures, cycles, and
capacity overruns fail closed.

**Next:** [Engines, adapters, and heavy computation](@ref engines-and-compute).
