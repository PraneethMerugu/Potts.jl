# [Reproducibility and persistence](@id reproducibility)

Reproducibility is a set of versioned identities and boundary conditions, not just a seed.

## Record the run identity

For every retained result, record:

- the semantic and execution fingerprints;
- authoring, normalized-IR, RNG, checkpoint, and algorithm contract versions;
- package and dependency versions;
- domain, layout, capacity, numerical policy, and backend identity;
- seed or ensemble seed policy;
- snapshot/observation policy;
- evidence schema and analysis version.

`semantic_manifest` and `scientific_contract_versions` expose the corresponding machine-readable
identities.

## Semantic RNG

Random draws are addressed by semantic operation, entity, time, and stream identity rather than by
incidental thread execution order. Extensions must request a registered RNG namespace and declare
their streams. A matching root seed is insufficient if the algorithm contract, model identity, or
operation addresses differ.

## Checkpoints

A canonical checkpoint contains logical state, semantic identities, continuation data, and an
integrity checksum. `capture_checkpoint` synchronizes at a completed boundary.
`restore_checkpoint` requires exact continuation compatibility; `import_checkpoint` is an explicit
new-run operation with a compatibility report.

```julia
checkpoint = CorePotts.capture_checkpoint(integrator)
store = CorePotts.MemoryCheckpointStore()
CorePotts.write_checkpoint!(store, "after_burnin", checkpoint)

loaded = CorePotts.read_checkpoint(store, "after_burnin")
resumed = CorePotts.restore_checkpoint(loaded, integrator)
```

HDF5 and Zarr stores are adapters over the same canonical payload. Storage format does not weaken
schema, compatibility, completeness, or checksum validation.

## Exact versus statistical claims

Exact continuation requires matching frozen identities and supported execution conditions.
Statistical reproducibility is a different claim and needs a declared statistic, tolerance,
replicate count, and evidence domain. Cross-backend numerical agreement must be supported by
applicable evidence; successful compilation alone is not enough.

## Fingerprint limits

Matching fingerprints establish matching canonical inputs under the recorded contract versions.
They do not establish that two different algorithms share kinetics, equilibrium distributions, or
physical-time semantics.
