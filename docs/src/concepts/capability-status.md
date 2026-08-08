# [Capability status](@id capability-status)

This table separates implemented foundations from public product qualification. “Implemented” does
not mean stable, documented, or qualified for every backend.

| Capability | Current state | G5H requirement before public stability |
|:--|:--|:--|
| `PottsSystem` and completion | Implemented V1 foundation | One cohesive constructor/composition path, structural `mtkcompile`, final docs |
| Sequential CPU CPM | Cleared G5 scientific foundation | Revalidate touched semantics and expose through the final SciML lifecycle |
| Checkerboard CPU CPM | Cleared G5 execution foundation | Shared acceptance law, honest distinct-algorithm guarantees, final capability report |
| Checkerboard Metal CPM | Replay-qualified bounded 2D `Float32` profile on the target Apple GPU | Preserve the exact conjunction and finish product documentation; CUDA/ROCm remain unsupported |
| Core lifecycle and relationships | Rich implemented foundation | Consolidated schemas, package-owned tests, lifecycle receipts, memory qualification |
| Checkpoint and symbolic indexing | Implemented in overlapping forms | One logical codec and one problem/integrator/solution indexing authority |
| Native global MTK components | Replay-qualified fixed-step, event-free ODE rows on CPU and bounded Metal; DAE construction is retained but coupled execution rejects | Preserve closed evidence and keep events, DAEs, opaque functions, callbacks, and unreviewed solvers fail-closed |
| Dynamic per-cell MTK components | Compile-once generation-safe pools with serial/batched CPU and bounded Metal execution | Finish final-interface documentation without widening fixed-capacity lifecycle semantics |
| Native and MethodOfLines fields | `DiscreteFieldEuler` CPU oracle, checked native-field Metal row, and exact CPU MethodOfLines weak extension | MethodOfLines GPU, remeshing, incompatible grids, and unreviewed solvers remain unsupported |
| SciML whole-trajectory ensembles | Standard serial, threaded, and distributed `EnsembleProblem` lanes preserve replica/repeat identity | Finish product examples; an inner trajectory must still be an admitted profile |
| Per-cell vectorization | Separate replay-qualified `BatchedNativeExecution` CPU profile with measured benefit | Keep distinct from whole-trajectory ensembles and global islands |
| Dagger scheduling | Measured defer; no package dependency | May be user-owned coarse orchestration, never semantic authority |
| MakiePotts | Existing implementation | Rebind to the final public observation/solution surface |
| Wortel and Merks | Existing internal fixtures, no current public docs claim | Serial final-API docs and target-Mac run before G6; scientific qualification remains G7 |
| Published-model reproduction | No model currently admitted | Separate source and scientific review after integration hardening |

## Backend claims

The sequential CPU profile is the semantic reference. Checkerboard CPU and Metal are distinct
algorithms. Global and per-cell native components have exact CPU references and independent
real-Metal witnesses for their admitted fixed-step subsets. Checked generic native fields have a
real-Metal witness; CPU PDE fields use the separately identified MethodOfLines adapter. Other
vendors, generic CPU native fields, MethodOfLines-on-GPU, and unsupported native systems report
`Unsupported`; compilation or storage adaptation alone is not qualification. External operation
code also requires its own reviewed package/evidence identity before device execution is admitted.

## API claims

The legacy `PottsModel` manual is quarantined and there is no compatibility promise for unpublished
pre-V1 names. The final stable inventory is produced during G5H-2 and qualified with executable
documentation during G5H-5.
