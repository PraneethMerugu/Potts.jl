# [Your first multirate composite](@id first-multirate-composite)

> **Support level:** qualified unpublished internal beta.

**Outcome.** Build and run two processes with different cadences against one
typed store, then inspect committed state.

**Prerequisites.** [The mental model](@ref mental-model).

## Complete executed source

```@example first-multirate-composite
using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct ScheduledPulse <: AbstractProcess
    amount::Int
end

ports(::ScheduledPulse) = (
    InputPort(Int, :state),
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::ScheduledPulse) = "1.0.0"
semantic_parameters(pulse::ScheduledPulse) = (amount=pulse.amount,)
invoke(pulse::ScheduledPulse, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), pulse.amount),
))

scale = TimeScale(1, 1, :minute)
model = compose(:FirstMultirate; scale, profile=:reproducible) do system
    total = store!(
        system, :total,
        LeafSchema(Int; default=0, update_law=:add),
    )

    fast = mount!(system, :fast, ScheduledPulse(1))
    attach!(system, fast, (state=total, out=total))
    schedule!(system, fast, Every(Duration(1, scale)))

    slow = mount!(system, :slow, ScheduledPulse(10))
    attach!(system, slow, (state=total, out=total))
    schedule!(system, slow, Every(Duration(2, scale)))

    observable!(system, :total, total)
end

problem = SimulationProblem(
    model;
    tspan=(LogicalTime(0, scale), LogicalTime(4, scale)),
    observations=(model.observables.total,),
    seed=2021,
)
runtime = initialize_runtime(problem)
run_until!(runtime, last(problem.tspan))

result = (
    total=current_snapshot(runtime)[path("total")],
    events=event_count(runtime),
    settled=settled(runtime),
    fingerprint=problem_fingerprint(problem),
)
@assert result == (
    total=24,
    events=4,
    settled=true,
    fingerprint=problem_fingerprint(problem),
)
```

At minutes 2 and 4 both processes are due. Their additive effects reconcile
within one atomic event boundary, so six activations produce four committed
events. Readers never observe a half-published batch.

```text
minute       1          2          3          4
fast        +1         +1         +1         +1
slow                    +10                    +10
committed    1          12         13          24
```

**Material defaults.** Exact minute scale, amounts 1 and 10, cadences 1 and 2,
four-minute horizon, master seed 2021.

**Expected result.** `total == 24`, four committed events, settled runtime.

**Establishes.** Exact multirate scheduling and deterministic additive
reconciliation for this bounded serial example.

**Does not establish.** Logical minutes are declared units, not validated
physical time; this run is not a performance benchmark.

**Backend / runtime / seed.** CPU serial runtime, seed 2021.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/learn/first_multirate_composite.jl`

**Next step.** Learn [stores, ports, schemas, and updates](@ref stores-ports-updates).
