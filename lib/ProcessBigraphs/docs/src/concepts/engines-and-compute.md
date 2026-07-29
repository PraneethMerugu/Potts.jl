# [Engines, adapters, and heavy computation](@id engines-and-compute)

> **Support level:** qualified public extension protocol.

An `EngineDeclaration` binds a reconstructable adapter, semantic version,
semantic parameters, and a narrow `EngineCapabilities` envelope. Capability is
evidence scope—not everything a dependency could theoretically do.

## Required call order

```text
prepare_engine
      │
stage_operation! ── returns completion handle
      │
complete_operation! ── returns candidate / early return / event / failure
      │
validate_candidate + runtime authorization
      │
publish_candidate!  OR  discard_candidate!
```

Adapter instances, solver integrators, candidate buffers, streams, tasks,
device allocations, and caches remain implementor-owned. Public protocol
values carry only the information the runtime needs to authorize the handoff.

An extension must document operation families, problem envelopes, backend,
precision, residency, input modes, boundary kinds, continuation actions,
replay class, diagnostics, cancellation, resize, and bridges. It must reject
requests outside that envelope before heavy work.

Use [`managed_field_process`](@ref) for the standard scheduled field pattern,
or implement the [complete custom adapter example](@ref custom-engine-adapter).

**Next:** [RNG, observation, checkpoints, and replay](@ref rng-observation-persistence).
