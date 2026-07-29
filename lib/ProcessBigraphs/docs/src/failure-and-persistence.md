# Failure, checkpoint, and restart guide

## Transaction boundary

Every scheduled batch reads one committed snapshot. Process, engine, observation, continuation,
and structural results remain unpublished until completion, reconciliation, validation, and
authorization all succeed. Publication commits numeric state, topology, clocks, continuations,
observer positions, records, and event identity atomically.

Failure before publication leaves the prior committed state authoritative. ProcessBigraphs calls
the relevant discard path for unpublished engine candidates and records a typed failure. There is
no partial numeric publication, partial structural rewrite, silent retry with changed inputs, or
host fallback.

## Failure stages

The qualified envelopes cover failure during selection, invocation/staging, asynchronous
completion, numeric reconciliation, structural rewrite, combined validation, observation, and
publication authorization. Conflicts, capacity violations, invalid lineage, nonfinite values,
unstable native-field steps, unsupported capabilities, and changed continuation declarations fail
closed.

Retry uses the same committed snapshot and semantic RNG coordinates unless an explicit external
decision changes the model or input. A failed attempt does not consume published logical time.

## Settled checkpoints

Checkpoints are admitted only at settled event boundaries. The coupled logical envelope records
canonical state, exact time, structural identities and lineage, scheduler positions, continuation
payloads, observer positions, model/plan identity, and integrity hashes. It excludes live tasks,
pointers, device buffers, solver caches, and ordinary Julia object serialization.

Restore verifies schema, model, execution plan, engine declarations, continuation codecs,
topology, and payload integrity before constructing a run. Exact-compatible integer scheduling and
semantic RNG replay exactly. Floating solver trajectories are numerical unless a stronger
continuation envelope has been separately qualified.

## Engine continuation

The default SciML adapter reconstructs from published canonical state on each invocation. Native
and custom adapters declare their own continuation and invalidation behavior. A retained solver
session is private engine state and may be restored only through a registered logical codec or
deterministic reconstruction; copying an integrator, cache, task, or device pointer is not a
checkpoint protocol.

Structural changes invalidate engine state according to the declared dependency envelope. Divide,
remove, move, and rewire operations apply typed store and solver-session transfer rules before the
next authorization.

## Legacy conversion

Previously attested checkpoint readers remain available. Conversion to the coupled envelope is
explicit and non-destructive: read the old logical record, validate it under its original
contract, produce a new record, and retain the source. Conversion never infers scientific units,
solver state, lineage, or missing topology. Unsupported or corrupt inputs fail without modifying
the original artifact.

Filesystem, object-store, and database persistence are extension concerns. They must preserve the
canonical logical bytes and integrity contract; external storage success is not part of the
in-memory publication transaction unless an adapter explicitly supplies a separately qualified
transactional protocol.
