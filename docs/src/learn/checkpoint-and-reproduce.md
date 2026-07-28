# [Checkpoint and reproduce](@id checkpoint-and-reproduce)

A checkpoint is a versioned continuation boundary, not merely a serialized array. It records
logical state, algorithm and RNG contracts, numerical profile, continuation data, integrity, and
ancestry.

## Exact stop and resume

```@example checkpoint-and-reproduce
restart = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials",
    "checkpoint_and_reproduce.jl"))
(restart.checkpoint.mcs, restart.exact_lattice_continuation,
    restart.final_mcs)
```

The canonical program runs two MCS, captures a checkpoint, continues both the original and restored
integrators, and requires exact final lattice equality.

## Restore versus import

- `restore_checkpoint` requires exact continuation compatibility.
- `import_checkpoint` starts a new run through an explicit compatibility report and weaker
  guarantee.

Do not catch a restore incompatibility and silently import. That changes the scientific claim.

## Storage

`MemoryCheckpointStore`, HDF5, and Zarr adapters use the same canonical payload and integrity
rules. Storage format does not weaken completeness or compatibility. Write through the store API
so failed writes cannot look complete.

## Reproducibility record

Retain semantic and execution fingerprints; package and manifest identities; authoring, RNG,
checkpoint, and algorithm contracts; backend and numerical policy; seed policy; observation
policy; analysis version; and applicable evidence identity.

A matching seed is insufficient if any semantic address, algorithm, model, or continuation
contract differs. [Stop and Resume](@ref stop-and-resume) is the complete gallery example.
