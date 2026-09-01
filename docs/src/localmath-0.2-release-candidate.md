# LocalMath 0.2 release candidate

LocalMath `0.2.0-rc1` is the first release candidate for the typed, bounded,
conflict-aware local-computation interface used by CorePotts and the scientific
witness corpus.

## Frozen contract

The release candidate freezes:

- `Space`, `Field`, `Relation`, `Collection`, and `LocalLaw`;
- `@localmath` Cartesian, gathered, routed, collected, and ordered-state forms;
- explicit descriptor-keyed preparation and storage ownership;
- `Unique`, `Reduce`, `Resolve`, `Collect`, and `OrderedFold` semantics;
- `IndexRelation`, bounded folds, and transparent scalar functions;
- `Plan`, `PreparedPlan`, `ExecutionReceipt`, and dependency settlement;
- canonical inspection, focused inspection levels, and compilation reports;
- the qualified low-level constructors used by scientific domain compilers.

LocalMath owns spatial access, validation, publication, ordering, workspace,
and physical KernelAbstractions execution. Domain packages retain equations,
solvers, scientific RNG, scheduling, transactions, checkpoints, and capability
claims.

## Backend statement

The implementation contains one packed KernelAbstractions path and no vendor-
specific launch or synchronization branch. The release suite exercises CPU and
real Metal with the same laws and storage model. Other conforming
KernelAbstractions providers remain possible inputs to cold preparation, but
this release makes no scientific support claim without corresponding hardware
evidence.

## Deliberate limitations

- Distributed partitioning and scheduling are outside LocalMath.
- Halo inspection reports communication requirements but does not execute MPI.
- Compilation reports expose structure and realized methods, not predicted
  wall time.
- Static bounds, boundary behavior, initialization, conflict semantics, and
  backend choice remain explicit.
- CUDA and ROCm qualification are deferred.

This release candidate is not a registry submission. Publication and any later
provider qualification are separate release activities.
