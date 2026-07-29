# [N-way junctions](@id n-way-junctions)

> **Support level:** qualified unpublished internal beta.

**Outcome.** Connect three named producers to one exact-compatible junction and
observe deterministic additive reconciliation.

**Prerequisites.** [Reusable nested composites](@ref nested-composites).

## Complete executed source

```@example n-way-junctions
using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct JunctionSource <: AbstractProcess
    amount::Int
end

ports(::JunctionSource) = (
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::JunctionSource) = "1.0.0"
semantic_parameters(source::JunctionSource) = (amount=source.amount,)
invoke(source::JunctionSource, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), source.amount),
))

scale = TimeScale(1)
model = compose(:NWayJunction; scale) do system
    junction = store!(
        system, :junction,
        LeafSchema(Int; default=0, update_law=:add),
    )
    for (name, amount) in ((:left, 1), (:center, 2), (:right, 3))
        source = mount!(system, name, JunctionSource(amount))
        connect!(system, source.out, junction)
        schedule!(system, source, Every(Duration(1, scale)))
    end
    expose!(system, :sum, junction; role=:export)
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(2, scale))
result = (
    value=current_snapshot(runtime)[path("junction")],
    commits=event_count(runtime),
    diagram=diagram(model),
)
@assert result.value == 12
@assert result.commits == 2
```

![Three bars labeled plus one, plus two, and plus three summarize each source’s contribution to the junction.](../assets/example-results.svg)

The loop reduces repetition but not semantics: every component name, amount,
connection, and schedule is present at the call site. No port is selected by
string similarity.

**Material defaults.** Amounts 1, 2, and 3; cadence 1; two ticks.

**Expected result.** Two publications and value 12.

**Establishes.** N-way exact-compatible additive junction behavior.

**Does not establish.** Other update laws have different conflict contracts.

**Backend / runtime / seed.** CPU serial runtime; no RNG draw.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/examples/n_way_junctions.jl`

**Next step.** [SciML field adapter](@ref sciml-field-adapter-example).
