# [Architecture and compute ownership](@id architecture-concept)

> **Support level:** qualified unpublished internal beta architecture.

![Explicit authoring lowers to one canonical structure and execution plan; the runtime schedules external computation and publishes only validated state.](../assets/architecture.svg)

## One owner for each decision

| Concern | ProcessBigraphs owns | Adapter or domain engine owns |
|---|---|---|
| Meaning | stores, ports, schedules, update laws | scientific mechanism and parameters |
| Time | exact logical boundaries and due order | numerical substeps inside authorization |
| State | committed snapshots and projections | private workspaces and staged candidates |
| Publication | reconciliation, validation, atomic commit | candidate construction |
| Persistence | logical checkpoint envelope and compatibility | declared continuation codec/state |
| Hardware | authorization and declared capability | kernels, buffers, streams, devices |

Authoring lowers deterministically:

```text
CompositeModel → LoweredModel → CanonicalModel + ExecutionPlan → SerialRuntime
```

The ACSet-backed canonical model is structural authority. The execution plan is
an immutable indexed view used by runtime; it is not a second authoring model.
Mutable runtime state contains clocks, continuations, projections, committed
state, observations, and diagnostics—not an editable copy of structure.

## Candidate publication is the seam

An engine invocation receives immutable, versioned projections and explicit
resource authorization. `stage_operation!` may perform heavy work.
`complete_operation!` returns a candidate, early return, event request, or
structured failure. A candidate becomes visible only after validation and
`publish_candidate!`.

This boundary prevents a solver buffer or completed GPU kernel from silently
becoming committed model state.

## Current boundary

The qualified internal beta includes the immutable-topology serial runtime,
open composition, typed observations, exact logical checkpoints, atomic
structural transaction primitives, managed engine handoff, and bounded
scientific assemblies. It is not a public registry release or a claim of
feature parity with every process-bigraph system.

**Next:** [Canonical structure and semantic identity](@ref canonical-identity).
