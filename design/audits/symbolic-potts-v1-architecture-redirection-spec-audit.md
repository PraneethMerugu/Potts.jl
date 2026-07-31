# Symbolic Potts V1 Architecture Redirection Specification Audit

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: complete; implementation remains prohibited pending explicit owner send-off

## Audited authority

- [`spec/symbolic-potts-v1-architecture-redirection.md`](../../spec/symbolic-potts-v1-architecture-redirection.md)
- [`spec/symbolic-potts-v1-consolidation.md`](../../spec/symbolic-potts-v1-consolidation.md)
- [`spec/symbolic-potts-v1.md`](../../spec/symbolic-potts-v1.md)
- [`spec/decisions/0017-open-protocol-extensibility.md`](../../spec/decisions/0017-open-protocol-extensibility.md)
- [`design/open-protocol-and-extensibility-standard.md`](../open-protocol-and-extensibility-standard.md)
- [`design/metaprogramming-and-compiler-architecture.md`](../metaprogramming-and-compiler-architecture.md)
- [`design/juliagpu-and-performance-programming-standard.md`](../juliagpu-and-performance-programming-standard.md)
- the accepted architecture-redirection owner interview;
- the current branch implementation; and
- the read-only previous-engine clone used during research.

## Result

The Architecture Redirection Contract is internally coherent and closes the architectural choices
needed for autonomous implementation. It corrects the current mechanism-shaped executor while
preserving the accepted scientific, stochastic, symbolic, SciML, clean-break, and proof-model
requirements.

No unresolved product or scientific question blocks implementation. Remaining choices are internal
representations, measured optimizations, backend support levels, or qualified naming beneath the
public contract.

## Conflict resolutions

| Earlier authority | Conflict | Resolution |
| --- | --- | --- |
| SPV1-016 | stored `ProposalEnergy` suggests proposal-delta-first semantics | ARV1-003 replaces it with `HamiltonianTerm`; the 23-kind inventory cardinality survives |
| SPV1-017 | registered statements had to lower into qualified built-in IR | ARV1-005 permits registered scientific IR and external concrete descriptors subject to the same validation |
| SPV1-019 | effect classes could be mistaken for term categories | ARV1-003 makes scientific category and mutation effect two orthogonal axes |
| SPV1-021 | initial focal-point fixture was sequential-only | ARV1-014 admits checkerboard snapshot reads and ordered deferred relationship requests |
| SPV1-022 | named protocol stages could become an open DAG | ARV1-010 maps public protocol names onto one closed nested stage schedule |
| SPV1-032 | mechanism-first implementation order | ARV1-020 replaces it with architecture-first gates and an external-term gate before proof-model completion |
| SPV1-033 / SPV1-049 | broad platform/evidence readings could recreate qualification bureaucracy | ARV1-019 makes ordinary CI authoritative and moves large statistics and GPU matrices to manual, scheduled, or release qualification |
| ACV1-002 | CorePotts ownership named fields, histories, relationships, and other science without a general storage rule | ARV1-008 limits central ownership to universal CPM invariants and requires typed auxiliary blocks |
| ACV1-005 | “closed vocabulary” was implemented as closed biological execution | ARV1-004 through ARV1-007 keep ordinary operations and stages closed while opening qualified scientific records and descriptors |
| ACV1-009 / ACV1-010 | one compiled program was interpreted as one mechanism-shaped struct and proposal loop | ARV1-007 through ARV1-009 require one general program containing grouped descriptors |
| ACV1-015 | accepted-copy relationship mutation required full touched-set exclusion or sequential rejection | ARV1-011 and ARV1-014 use snapshot reads, bounded requests, and ordered publication |
| ACV1-019 | test inventory did not distinguish exact, invariant, statistical, and engine-specific claims | ARV1-019 establishes layered authority |
| ACV1-021 | Wortel/Merks mechanisms were implemented before the general execution boundary | ARV1-020 requires descriptors, both engines, deferred requests, and an external fixture first |
| ACV1-022 | failure to fit the closed built-in vocabulary forced an owner stop | ARV1-005 permits qualified external descriptors; stopping is required only when the accepted extension boundary itself is insufficient |
| ACV1-023 | phase exit could succeed with named mechanisms in CorePotts | ARV1-021 makes zero-Core-edit downstream execution and absence of mechanism names terminal gates |
| Decision 0017 | its architecture was open, but its mandatory multi-GPU evidence language exceeded the accepted standard-library CI policy | ARV1-005 preserves zero-Core-edit openness; ARV1-019 requires device evidence only for support levels actually claimed |

## Compatibility findings

The following accepted directions remain unchanged:

- one immutable `PottsSystem` and the completion/compile/problem/solve lifecycle;
- genuine ModelingToolkitBase and SciMLBase behavior;
- DynamicQuantities as the canonical unit implementation and optional Unitful boundaries;
- ProcessBigraphs as an optional domain-neutral orchestration boundary;
- semantic addressed randomness and explicit stochastic replay scopes;
- exactly two engine families;
- no migration, compatibility, documentation, or wrapper obligation on this branch;
- visible complete Wortel and Merks model fixtures;
- immutable logical checkpoints at settled boundaries;
- no Symbolics, units, registries, closures, or source ASTs in CorePotts execution data;
- no silent backend fallback; and
- ordinary repository testing rather than a parity/evidence oracle.

## Current implementation nonconformance

The audit confirms that the current branch is a valuable semantic prototype, not a conforming
runtime architecture.

The replacement work MUST remove these present violations:

- `CompiledPottsProgram` contains named mechanism fields;
- the proposal loop explicitly invokes built-in biological deltas;
- lowering switches on mechanism identities;
- `RegisteredStatement` cannot produce an external runtime descriptor;
- checkerboard execution is a serial color loop rather than a staged portable engine;
- CorePotts lacks the accepted KernelAbstractions, AcceleratedKernels, Adapt, Atomix, and
  StaticArrays boundary;
- proposal execution performs whole-lattice or whole-relationship scans;
- hot paths construct dynamic sets/vectors and use unsuitable dense operations;
- some per-MCS workspaces allocate repeatedly; and
- the current RNG construction path has a broader package-test constructor regression.

These are implementation defects and refactor targets, not unresolved owner questions.

## Previous-engine recovery disposition

Recover conceptually and selectively:

- parametric structure-of-arrays state where benchmarked;
- Adapt recursion;
- KernelAbstractions kernels;
- AcceleratedKernels bulk algorithms where applicable;
- explicit reusable workspaces;
- staged checkerboard candidate/evaluate/resolve/commit organization;
- incremental volume, boundary, moment, centroid, field, history, and relationship tracking;
- Atomix operations under the closed concurrency policies;
- backend extension structure; and
- warm-allocation, transfer, synchronization, and device-validity checks.

Do not recover:

- coupled biological authoring;
- paper-specific runtime assemblies;
- Lottery or tiled engines;
- private subgroup/warp intrinsics;
- obsolete KernelAbstractions event APIs;
- hidden host waits or transfer;
- a universal block size;
- a single-lane relationship implementation presented as scalable; or
- historical evidence, archive, and parity infrastructure.

## Autonomy audit

The implementation agent has authority to:

- select concrete private type and function names satisfying the descriptor protocols;
- split or move source files within the accepted package ownership;
- change implementation order between adjacent internal gates;
- choose ordinary array, AcceleratedKernels, or KernelAbstractions implementations under the
  specified abstraction ladder;
- select data layouts by measured hot-path evidence;
- define backend support levels according to available compile-and-run evidence;
- repair tests while preserving their appropriate exact, invariant, or statistical authority; and
- delete superseded runtime scaffolding once its replacement passes the relevant gate.

The agent does not have authority to:

- add another engine or scheduler;
- add compatibility or migration behavior;
- weaken scientific semantics to satisfy checkerboard;
- introduce private upstream API coupling;
- move symbolic or process-composition dependencies into CorePotts;
- add documentation or browser QA;
- claim untested GPU support;
- hard-code a proof-model mechanism into CorePotts; or
- treat old execution as a scientific oracle.

## Specification quality checks

- Authority precedence is explicit.
- Every accepted interview decision maps to ARV1 clauses.
- The phase scope and exclusions are explicit.
- The extension acceptance test is executable and falsifiable.
- Sequential and checkerboard have distinct, specified stochastic schedules.
- Relationship mutation has an explicit snapshot, request, order, validation, and publication
  protocol.
- Compilation and specialization have machine-independent asymptotic/allocation budgets.
- Test claims are separated by exact, replay, property, statistical, analytic, engine, and backend
  authority.
- CI does not depend on expiring evidence.
- Implementation gates are ordered by architecture rather than named mechanisms.
- Exit requires both external extensibility and proof-model completion.

## Readiness conclusion

The specification is ready for owner review and explicit implementation send-off. No production
implementation is authorized by this audit alone.
