# Runtime, observation, and checkpoint API

> **Support level:** supported internal beta.

Runtime publication is transactional: an event either publishes every
authorized effect or publishes none. Observations read committed boundaries,
and settled checkpoints capture only replay-safe state.

```@docs
ProcessBigraphs.observation_records
ProcessBigraphs.checkpoint
ProcessBigraphs.restore
```

```julia
runtime = initialize_runtime(problem)
run_until!(runtime, LogicalTime(20, problem.scale))

records = observation_records(runtime)
saved = checkpoint(runtime)
resumed = restore(saved, problem)
```

Checkpoint restoration validates model identity, schedule identity,
continuation schemas, and structural position before returning a runtime.
There is no “best effort” restore mode on the exact path.

For downstream scientific façades such as
`CorePotts.ActivityPottsProblem`, the same generic operation names are
extended. This keeps persistence code independent of coupled runtime
representations.
