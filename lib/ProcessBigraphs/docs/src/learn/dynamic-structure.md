# [Change structure transactionally](@id dynamic-structure)

> **Support level:** template authoring is supported internal beta; structural
> mutation remains explicitly transaction-bounded.

**Outcome.** Declare a reusable child definition and a capacity-bounded instance
template without instantiating children as a side effect of authoring.

**Prerequisites.** [Integrate adapters and solvers](@ref adapters-and-solvers).

## Complete executed source

```@example dynamic-structure
using ProcessBigraphs

scale = TimeScale(1)
cell = compose(:CellDefinition; scale) do child
    state = store!(
        child, :state,
        LeafSchema(Int; default=0, update_law=:add),
    )
    expose!(child, :state, state; role=:bidirectional)
end

host = compose(:DynamicHost; scale, profile=:reproducible) do system
    shared = store!(
        system, :shared,
        LeafSchema(Int; default=0, update_law=:add),
    )
    allow_instances!(system, :cells, cell; capacity=8)
    observable!(system, :shared, shared)
end

report = validate(host)
plan = compile(host)
result = (
    valid=isempty(report.diagnostics),
    model=semantic_fingerprint(host),
    structure=structural_fingerprint(plan),
    template_policy=(name=:cells, capacity=8),
)
@assert result.valid
```

A template is permission and schema, not a hidden child. Runtime requests
created by [`spawn`](@ref), [`divide`](@ref), [`move`](@ref), or
[`remove`](@ref) identify their source structural epoch. Selection,
reference validation, rewriting, numeric validation, and publication either
produce one new immutable epoch or leave the prior epoch unchanged.

```text
requests → deterministic selection → candidate rewrite → full validation
                                                         │
                                  reject (old epoch) ←───┼──→ publish (new epoch)
```

**Material defaults.** Child endpoint is bidirectional; host capacity is eight;
no initial child exists.

**Expected result.** Valid host, stable model and structure identities, explicit
template policy.

**Establishes.** Public authoring of reusable definitions and finite instance
permission.

**Does not establish.** This compile-only tutorial does not execute a biological
division policy or claim that numeric state can be inferred during a division.

**Backend / runtime / seed.** Compile-only CPU host; no seed.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/learn/dynamic_structure.jl`

**Next step.** [Checkpoint, fail, restore, and replay](@ref checkpoint-failure-replay).
