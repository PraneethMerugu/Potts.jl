# Adapter and solver guide

## The ownership boundary

An adapter translates a ProcessBigraphs authorization into one solver-owned operation. It does not
introduce another scheduler. ProcessBigraphs decides when the operation is due, why it is invoked,
which immutable input projection is visible, its logical target, semantic identity, RNG
coordinates, and whether the completed candidate may publish.

The engine decides how to reach the target: algorithm, internal timesteps or sweeps, arrays,
layout, workspaces, caches, device buffers, kernels, streams, preconditioners, and completion
mechanism.

## Lifecycle

1. `prepare_engine` realizes an immutable declaration as one private engine instance.
2. `stage_operation!` receives an `EngineInvocation` and returns an opaque candidate, a typed early
   return, or a typed failure. Published state must remain untouched.
3. `complete_operation!` resolves asynchronous work at the semantic boundary.
4. `validate_candidate` checks target time, schema, version, conservation or domain invariants,
   and declared effects.
5. `publish_candidate!` performs the authorized atomic publication.
6. `discard_candidate!` cleans up any rejected or failed unpublished work.

Capabilities are declared up front. Unsupported ranks, boundaries, precision, placement,
continuation, exact-target behavior, or device residency fail before execution; adapters do not
silently fall back to a different solver or host path.

## Exact targets and early returns

`IntervalAdvance` supplies an exact logical target. An engine either reaches it, returns a typed
earlier boundary request that ProcessBigraphs can schedule, or fails. Floating solvers must use
their standard exact-target or stop-time facility and verify the reached time. ProcessBigraphs
does not implement the solver loop and does not infer success from a custom wrapper when the
solver ecosystem provides standard return-code and integrator-error interfaces.

## SciML adapter

The SciML path is a weak-dependency extension. Authors inject a real algorithm object and bounded,
canonical options. Each invocation reconstructs from published canonical state, so default replay
is numerical. Retaining a live integrator requires a separately qualified clone/codec and
invalidation envelope.

Automatic algorithm selection is experimental. A concrete SciML solver is not a core dependency,
and the internal integrator or cache is never part of a model, checkpoint, or public API.

## Independent adapters

A third-party adapter can implement the same open protocol without depending on SciML or sharing a
numerical stepping helper with the SciML realization. The qualified independent fixture proves
this boundary. New adapters should supply:

- immutable, canonically fingerprinted declarations;
- explicit capability and negative-capability records;
- exact input projection and target handling;
- isolated staging and idempotent discard;
- standard completion and failure reporting;
- restart behavior at every admitted settled boundary; and
- analytic or manufactured correctness, convergence, conservation, and failure evidence
  appropriate to the method.

Adapter equality is never established merely by duplicating the same Euler loop. Cross-adapter
evidence uses independent mathematical or source-derived oracles with declared tolerances.

## Native and CorePotts adapters

The native Cartesian field engine is owned by CorePotts and uses co-resident buffers. Metal and
ROCm qualification proves zero staging transfer, zero warm device allocation, and no hidden host
fallback for the declared workload. Construction and requested observation transfers remain
explicit.

The CorePotts CPM adapter likewise keeps lattice topology and optimized sweeps in CorePotts.
ProcessBigraphs schedules the sweep and atomically publishes typed numeric and structural effects.
ProcessBigraphs core does not depend on CorePotts.
