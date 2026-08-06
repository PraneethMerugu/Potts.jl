# [Capability status](@id capability-status)

This table separates implemented foundations from public product qualification. “Implemented” does
not mean stable, documented, or qualified for every backend.

| Capability | Current state | G5H requirement before public stability |
|:--|:--|:--|
| `PottsSystem` and completion | Implemented V1 foundation | One cohesive constructor/composition path, structural `mtkcompile`, final docs |
| Sequential CPU CPM | Cleared G5 scientific foundation | Revalidate touched semantics and expose through the final SciML lifecycle |
| Checkerboard CPU CPM | Cleared G5 execution foundation | Shared acceptance law, honest distinct-algorithm guarantees, final capability report |
| Checkerboard GPU CPM | Functional selected-device foundation | Exact admitted profile, real-device no-fallback and performance qualification |
| Core lifecycle and relationships | Rich implemented foundation | Consolidated schemas, package-owned tests, lifecycle receipts, memory qualification |
| Checkpoint and symbolic indexing | Implemented in overlapping forms | One logical codec and one problem/integrator/solution indexing authority |
| Native global MTK components | Not integrated; superseded copied-assimilation prototype exists | Preserve native systems; prove initialization, events, coupling, remake, SII, restart |
| Dynamic per-cell MTK components | Not integrated | Compile-once generation-safe pools; CPU reference and bounded GPU batch profile |
| MethodOfLines fields | Not integrated | `symbolic_discretize`, real MTK problem, explicit grid map, profile evidence |
| SciML whole-trajectory ensembles | Partial identity groundwork | Standard `EnsembleProblem` serial/threaded/distributed workflows |
| Per-cell vectorization | Not integrated | Separate API and evidence from whole-trajectory ensembles |
| Dagger scheduling | Not adopted | Measured optional adopt-or-defer decision; never semantic authority |
| MakiePotts | Existing implementation | Rebind to the final public observation/solution surface |
| Wortel and Merks | Existing internal fixtures, no current public docs claim | Serial final-API docs and target-Mac run before G6; scientific qualification remains G7 |
| Published-model reproduction | No model currently admitted | Separate source and scientific review after integration hardening |

## Backend claims

The sequential CPU profile is the semantic reference. Checkerboard CPU and GPU are distinct
algorithms. Every stable global or per-cell component scope requires a CPU reference and at least
one real GPU witness for the explicitly admitted subset. Other vendors and unsupported native
systems must report `Unsupported`; compilation success alone is not qualification.

## API claims

The legacy `PottsModel` manual is quarantined and there is no compatibility promise for unpublished
pre-V1 names. The final stable inventory is produced during G5H-2 and qualified with executable
documentation during G5H-5.
