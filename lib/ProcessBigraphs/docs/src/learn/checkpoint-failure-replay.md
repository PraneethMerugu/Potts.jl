# [Checkpoint, fail, restore, and replay](@id checkpoint-failure-replay)

> **Support level:** exact logical checkpoint/replay on the admitted serial
> boundary.

**Outcome.** Stop at a settled boundary, capture a checkpoint, restore against
the same plan, and prove exact continuation against an uninterrupted run.

**Prerequisites.** [Change structure transactionally](@ref dynamic-structure).

## Complete executed source

```@example checkpoint-failure-replay
using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct ReplayIncrement <: AbstractProcess
    amount::Int
end

ports(::ReplayIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::ReplayIncrement) = "1.0.0"
semantic_parameters(law::ReplayIncrement) = (amount=law.amount,)
invoke(law::ReplayIncrement, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), law.amount),
))

scale = TimeScale(1)
model = compose(:Replayable; scale, profile=:reproducible) do system
    state = store!(
        system, :state,
        LeafSchema(Int; default=0, update_law=:add),
    )
    actor = mount!(system, :increment, ReplayIncrement(2))
    attach!(system, actor, (state=state, out=state))
    schedule!(system, actor, Every(Duration(1, scale)))
end
plan = compile(model)

uninterrupted = initialize_runtime(plan)
run_until!(uninterrupted, LogicalTime(5, scale))

interrupted = initialize_runtime(plan)
run_until!(interrupted, LogicalTime(2, scale))
saved = checkpoint(interrupted)
restored = restore(plan, saved)
run_until!(restored, LogicalTime(5, scale))

result = (
    value=current_snapshot(restored)[path("state")],
    exact=snapshot_fingerprint(current_snapshot(restored)) ==
        snapshot_fingerprint(current_snapshot(uninterrupted)),
    events=event_count(restored),
    checkpoint=checkpoint_fingerprint(saved),
)
@assert result.value == 10
@assert result.exact
@assert result.events == event_count(uninterrupted)
```

Checkpoint compatibility validates the model, execution plan, logical time,
continuations, observation state, and integrity envelope. Restore does not
silently reinterpret an incompatible archive.

Failures inside a transaction are fail-stop: no candidate becomes visible,
event counters do not advance, and a settled failure checkpoint records the
diagnostic. See [RNG, observation, checkpoints, and replay](@ref rng-observation-persistence)
for the full guarantee boundary.

**Material defaults.** Add 2 each tick; cut after tick 2; finish at tick 5.

**Expected result.** Final value 10 and the same snapshot fingerprint and event
count as the uninterrupted run.

**Establishes.** Exact compatible replay for this deterministic serial model.

**Does not establish.** It does not promise compatibility after an undeclared
semantic change or bitwise identity for numerical engine adapters.

**Backend / runtime / seed.** CPU serial runtime; deterministic; no RNG draw.

**Reproduction command.**
`julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/models/learn/checkpoint_failure_replay.jl`

**Next step.** Browse the [complete example gallery](@ref examples-index).
