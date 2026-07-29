# [RNG, observation, checkpoints, and replay](@id rng-observation-persistence)

> **Support level:** qualified semantic RNG, typed observation, and logical
> checkpoint/replay on the admitted serial boundary.

Semantic RNG draws are addressed by immutable lineage: root seed, owner,
event, purpose, and draw ordinal. Actor order, observer presence, and unrelated
draws cannot consume a shared mutable stream and shift another component’s
random sequence. Observers use an isolated namespace.

An `ObserverSpec` declares its identity, reconstructable observer, allowed
paths, schedule, record schema, continuation, and failure policy. Observation
records are outputs, not state effects.

## Settled checkpoint contents

- model, structural, execution, and runtime policy identities;
- committed snapshot and logical time;
- process, step, and observer clocks;
- typed continuations and their compatibility contracts;
- event and observation position;
- structural epoch and lineage when applicable;
- integrity fingerprint and schema version.

Exact replay means compatible logical state and event history match the
qualified contract. Numerical engine continuations may instead declare
`:numerical`, `:statistical`, or `:unsupported`; those labels must not be
upgraded by a successful run.

Fail-stop transactions retain the prior committed state and record the stage
of failure. Restore rejects corrupt, future, or semantically incompatible
archives.

**Next:** [Capability status, migration, and troubleshooting](@ref capability-migration-troubleshooting).
