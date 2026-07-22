# Specification-to-Conformance Evidence Index

Semantic status: Accepted index structure

Implementation maturity: Phases 5–10 complete on the CPU/Metal/ROCm backend contract

This index is the authoritative map from accepted semantics to executable evidence. A green
package-local regression suite does not satisfy a row by itself: evidence must exercise a stable
logical contract, a scalar reference, a validator, or a defined statistical procedure.

| Semantic contract | Reference or validator | Reference maturity | Production/backend maturity | Remaining gate |
| --- | --- | --- | --- | --- |
| [State Model](state-model.md) | `LogicalPottsState`, state validators, canonical snapshots, minimal layout finalization, uniform site-seed law, bounded rejection placement, and periodic rasterization | Phase 8 reference initialization and invariant semantics implemented | CPU/Metal/ROCm 2D/3D built-in and downstream layouts with explicit device lowering | PottsToolkit compiler migration remains Phase 10–11 |
| [Time and MCS](time-and-mcs.md) | `ReferenceMCSReport`, `AttemptAccounting`, `ScientificMCSReport`, normalized-round validators | Reference sequential `N`-attempt MCS plus production sequential, checkerboard, and lottery accounting implemented | CPU, Metal, and ROCm 2D/3D algorithm accounting/replay; CPU lottery boundary-degree, repetition, waiting-time, and neighbor-covariance fixtures | Broader kinetic/equilibrium comparison is required only before making such a future claim |
| [Transition-Kernel Verification](transition-kernel-verification.md) | Independent finite-state proposal/sub-round/MCS oracle, lifted scheduler states, sparse transition matrices, and independent-replica backend tests | Specified for Phase 13; hand-derived and generated reference evidence pending | CPU/Metal/ROCm empirical transition qualification deferred until Phase 13 after Phase 12.CPU and Phase 12.5 close | Sequential reference obligations, checkerboard guarantee label, realistic-scale corroboration, and evidence archive |
| [Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md) | exact scalar OU transition, mechanical-work fixtures, initialization laws, semantic RNG, normalized-clock validators, and accepted division/transition/death/reuse laws | Stable pressure/tension evolution and lifecycle laws derived; historical real-HST claim rejected | `FluctuatingVolumePressure` and `FluctuatingSurfaceTension` pass CPU/Metal/ROCm sequential/checkerboard/lottery 2D/3D clocks, replay, initialization/evolution moments, lifecycle operations, and zero internal sync | PottsToolkit migration owns legacy HST deletion |
| [Energy, Proposals, and Trackers](energy-proposals-and-trackers.md) | full/local volume, contact, raw/weighted/normalized surface laws; proposal/acceptance fixtures; tracker reconstruction | Required Phase 6 paper slice implemented | Phase 6 CPU/Metal/ROCm `Float32`; sequential and capability-qualified checkerboard/lottery CPU/Metal/ROCm 2D/3D integration with tracker reconciliation | Parallel private/coupled access is deferred unless a paper workload requires it |
| [Lifecycle](lifecycle.md) | logical transactions, common pre-event snapshot, open schedule/trigger/effect/resolver/geometry/property/derived protocols, and extinction/reuse | Scalar and compiled Phase 8 paths implemented | CPU/Metal/ROCm 2D/3D schedule-through-commit, rollback, mechanics, derived repair, and zero-core-edit downstream fixture | Later PottsToolkit compiler migration must target these protocols |
| [Persistence](persistence.md) | completed-MCS snapshot/checkpoint distinction, canonical logical record, exact resume/import compatibility, integrity, and shared storage conformance | Canonical checkpoint, strict profile, exact restore, and logical import implemented | Memory/HDF5/Zarr equivalence and fault injection; CPU/Metal all-algorithm 2D/3D exact continuation; ROCm storage/restore qualification | Later paper-scale performance capture |
| [Randomness and Reproducibility](randomness-and-reproducibility.md) | Philox v1 known-answer vectors, semantic-address fixtures, distribution batteries, algorithm and mechanical replay qualification | Accepted reference contract implemented | CPU, Metal, and ROCm Phase 5 qualification plus strict same-backend sequential, checkerboard, lottery, and mechanical-state replay | Later algorithm-level guarantees must add their own evidence |
| [Numerical and Cross-Backend Semantics](numerical-and-cross-backend-semantics.md) | typed `ReferenceNumericalPolicy`, `ConformanceCase`, and statistical procedure tiers | `integration/conformance/test_harness.jl` | precision/backend matrix | Foundation present; adapters pending |
| [Topology and Spatial Relations](topology-and-spatial-relations.md) | canonical static 2D/3D relations, role separation, periodic/fixed/closed realization, obstacles | Required Cartesian slice implemented | Compiled CPU/Metal/ROCm qualification; CPU/Metal/ROCm sequential plus realized-graph checkerboard/lottery integration; historical algorithm topologies quarantined | Broader topology families require independent qualification |
| [Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md) | global/local surface laws, edge/site/distinct-owner queries, aligned field sampling, chemotaxis modes, reports | Required Phase 6 paper slice implemented | CPU, Metal, and ROCm qualification in 2D/3D | PDE evolution remains deferred |
| [CorePotts Public Interfaces](corepotts-public-interface-semantics.md) | typed proposal, five category-preserving component folds, proposal context, acceptance inputs, staged transaction, access traits, algorithm values and reports | Required Phase 6 inner-loop protocol and Phase 7 algorithms/mechanics slices implemented | CPU/Metal/ROCm execution for all three algorithm families and both stable mechanical families; explicit sequential-only connectivity/focal capabilities; old algorithms quarantined | PottsToolkit production compiler migration in Phases 10--11 |
| [Sequential Reference Engine](reference-engine-semantics.md) | checked sequential CPU execution | Reference implemented for the 2D volume/contact slice | Deferred; it is not a production engine | Extend per later algorithm/component phases |
| [SciML Interface Semantics](sciml-interface-semantics.md) | thin `ScientificPottsIntegrator`, `init_scientific`, and integer-MCS `step!` execution boundary | Final problem/solution oracle pending | CPU/Metal/ROCm sequential, checkerboard, and lottery stepping with explicit observation qualified | Final problem, solution, callbacks, and saving semantics in Phase 8 |
| [PottsToolkit Rule and Model Semantics](pottstoolkit-rule-and-model-semantics.md) | typed Level 2 property/lifecycle declarations, simultaneous compiled transactions, semantic RNG, five reference families | Level 2 reference and lowering implemented | CPU/Metal/ROCm compiled lifecycle and reference-workload qualification; historical rule compiler deleted | Phase 11 adds only the Level 1 spelling over these semantics |
| [PottsToolkit Authoring and API Semantics](pottstoolkit-authoring-composition-and-api-semantics.md) | immutable `CellType`/`Medium`/binding/law/fragment/model/layout path, structured reports, public CorePotts lowering | Complete Level 2 normalized model and external-extension route | CPU/Metal/ROCm 2D/3D execution, curated exports, one CorePotts problem, schema `2.0.0` benchmark evidence | Phase 11 DSL coverage over the completed Level 2 path |

Legacy rows retain their Phase 3 wording until their executable slices are revised, but no
`Foundation present` entry claims that a shipping algorithm or backend conforms. New and revised
rows use the maturity vocabulary in `README.md`; rows assigned to later phases remain open
implementation obligations.

The historical engine is an implementation quarantine, not a Phase 7 deletion gate. A required CI
check freezes inventoried production files by SHA-256, freezes ordered quarantined-line signatures
for every existing non-production consumer, scans the replacement path for fallback edges, and
rejects uninventoried consumers independently of pull-request history. Phases 10--11 own production
compiler parity and source deletion; later documentation migration cannot restore a removed legacy
dependency.

## Failure Reproduction Record

Every randomized conformance failure MUST report:

- semantic master seed and RNG contract version;
- model fingerprint;
- initial logical-state checksum;
- algorithm, numeric policy, dimension, and backend report; and
- one command that selects the failing suite or case.

The test-only `ReproductionContext` gives all Phase 3 cases a common record now. Final public
provenance is implemented through CorePotts and PottsToolkit interfaces in later phases.
