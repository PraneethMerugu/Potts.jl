# [Logical time, scheduling, and publication](@id time-scheduling-publication)

> **Support level:** qualified unpublished internal beta.

**Outcome.** Combine an exact periodic cadence with a one-shot boundary and
inspect the order of atomic publications.

**Prerequisites.** [Compose and inspect a system](@ref compose-and-inspect).

## Complete executed source

```@example time-scheduling-publication
using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct TimedPulse <: AbstractProcess
    amount::Int
end

ports(::TimedPulse) = (
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::TimedPulse) = "1.0.0"
semantic_parameters(pulse::TimedPulse) = (amount=pulse.amount,)
invoke(pulse::TimedPulse, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), pulse.amount),
))

scale = TimeScale(1, 100, :second)
model = compose(:TimedPublication; scale) do system
    total = store!(
        system, :total,
        LeafSchema(Int; default=0, update_law=:add),
    )
    periodic = mount!(system, :periodic, TimedPulse(1))
    connect!(system, periodic.out, total)
    schedule!(system, periodic, Every(Duration(2, scale)))
    one_shot = mount!(system, :one_shot, TimedPulse(10))
    connect!(system, one_shot.out, total)
    schedule!(system, one_shot, At(LogicalTime(3, scale)))
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(6, scale))

result = (
    value=current_snapshot(runtime)[path("total")],
    commits=event_count(runtime),
    times=Tuple(record.time.tick for record in event_trace(runtime)),
)
@assert result.value == 13
@assert result.times == (2, 3, 4, 6)
```

```text
logical tick     0     2     3     4     6
periodic               +1          +1    +1
one-shot                     +10
published total  0     1     11    12    13
```

[`At`](@ref) is exhausted after its listed boundary. [`Every`](@ref) advances
by exact integer ticks. Visibility changes only after reconciliation and
publication; a due component cannot expose a partial update.

**Material defaults.** 0.01-second ticks, periodic cadence 2, one-shot tick 3,
horizon tick 6.

**Expected result.** Publications at `(2, 3, 4, 6)` and final value 13.

**Establishes.** Exact schedule ordering and published-state visibility.

**Does not establish.** The declared seconds are not an empirical calibration.

**Backend / runtime / seed.** CPU serial runtime; deterministic; no RNG draw.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/learn/time_scheduling_publication.jl`

**Next step.** [Write processes, steps, and observers](@ref write-components).
