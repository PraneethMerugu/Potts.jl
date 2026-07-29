# [Stores, ports, schemas, and updates](@id stores-ports-updates)

> **Support level:** qualified unpublished internal beta.

**Outcome.** Declare structured state, bind typed input and output ports, and
observe additive and replacement publication without touching representation
fields.

**Prerequisites.** [Your first multirate composite](@ref first-multirate-composite).

## Complete executed source

```@example stores-ports-updates
using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct TypedTransfer <: AbstractProcess
    increment::Int
end

ports(::TypedTransfer) = (
    InputPort(Int, :source; interval_behavior=:frozen),
    OutputPort(Int, :source_out; update_law=:add),
    OutputPort(Int, :published; update_law=:replace),
)
semantic_version(::TypedTransfer) = "1.0.0"
semantic_parameters(law::TypedTransfer) = (increment=law.increment,)
function invoke(law::TypedTransfer, inputs, context)
    next = inputs[:source] + law.increment
    InvocationResult((
        emit(context, :source_out, AdditiveUpdate(), law.increment),
        emit(context, :published, ReplaceUpdate(), next),
    ))
end

scale = TimeScale(1)
schema = BranchSchema(
    source=LeafSchema(Int; default=1, update_law=:add, units="molecule"),
    published=LeafSchema(Int; default=0, update_law=:replace, units="molecule"),
)
model = compose(:TypedStores, schema; scale) do system, stores
    transfer = mount!(system, :transfer, TypedTransfer(2))
    connect!(system, transfer.source, stores.source)
    connect!(system, transfer.source_out, stores.source)
    connect!(system, transfer.published, stores.published)
    schedule!(system, transfer, Every(Duration(1, scale)))
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(3, scale))
snapshot = current_snapshot(runtime)

result = (
    leaves=first.(schema_leaves(schema)),
    source=snapshot[path("source")],
    published=snapshot[path("published")],
    commits=event_count(runtime),
)
@assert result.source == 7
@assert result.published == 7
```

The process reads a frozen projection. It emits data, not mutations. The
runtime validates each `Delta`, reconciles by the store’s declared update law,
and atomically publishes the next committed snapshot.

Use [`schema_at`](@ref) and [`schema_leaves`](@ref) for inspection. Concrete
schema fields are representation, not model API.

**Material defaults.** `source` begins at 1; cadence 1; additive increment 2;
three logical ticks.

**Expected result.** Both leaves contain 7 after three commits.

**Establishes.** Typed binding and two explicit update laws in one process.

**Does not establish.** It does not show conflicting replacement proposals;
see [logical state, effects, and reconciliation](@ref state-effects-reconciliation).

**Backend / runtime / seed.** CPU serial runtime; deterministic; no RNG draw.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/learn/stores_ports_updates.jl`

**Next step.** [Compose and inspect a system](@ref compose-and-inspect).
