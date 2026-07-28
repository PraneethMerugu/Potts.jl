# [Checkpoint and reproduce](@id checkpoint-and-reproduce)

A checkpoint is a versioned continuation boundary, not merely a serialized array. It records
logical state, algorithm and RNG contracts, numerical profile, continuation data, integrity, and
ancestry.

## Exact stop and resume

```@example checkpoint-and-reproduce
using PottsToolkit
import CorePotts

# The exact-continuation contract starts from a fully explicit public problem.
medium = Medium(:Medium)
cell = CellType(:Cell)
model = PottsModel(medium, cell, Volume(cell => (target = 12, strength = 2)))
mask = falses(10, 10)
mask[4:6, 4:7] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 4),
    seed = 33,
)
algorithm = SequentialCPM(temperature = 2.0f0)
uninterrupted = CorePotts.init(
    problem, algorithm; save_start = false, save_end = false)
CorePotts.step!(uninterrupted, 2)
checkpoint = CorePotts.capture_checkpoint(uninterrupted)
resumed = CorePotts.restore_checkpoint(checkpoint, problem, algorithm)
CorePotts.step!(uninterrupted, 2)
CorePotts.step!(resumed, 2)
expected = CorePotts.logical_state(uninterrupted)
observed = CorePotts.logical_state(resumed)

@assert CorePotts.lattice_storage(expected) == CorePotts.lattice_storage(observed)
@assert checkpoint.mcs == 2
result = (; checkpoint, exact_lattice_continuation = true,
    final_mcs = resumed.t)

(result.checkpoint.mcs, result.exact_lattice_continuation,
    result.final_mcs)
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
