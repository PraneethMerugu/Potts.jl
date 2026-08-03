# Symbolic Potts V1 lifecycle performance review

Date: 2026-08-03

Scope: the repaired sequential lifecycle candidate before the lifecycle quality-gate handoff

Status: sequential measurements retained; gate disposition superseded by the owner-required
backend-residency contract on 2026-08-03

The measurements below remain valid for the sequential reference. Their former conclusion that no
GPU implementation was required before the current gate is withdrawn. Fully backend-resident
schedule-through-publication execution, device status self-gating, and terminal-only host
synchronization are now correctness requirements. This amendment does not convert unmeasured
optional optimizations into requirements.

## Decision

The current lifecycle architecture is performant enough for the sequential V1 gate after three
bounded corrections found by measurement:

1. skip lattice indexing when no lifecycle descriptor is due;
2. remove duplicate type-erased state-schema validation after validating every lifecycle write at
   its owned boundary; and
3. remove a per-site generator allocation in plane partitioning and inline the shared tracker-copy
   boundary.

No other sequential optimization was justified by these measurements. In particular, they do not
justify a persistent packed active-cell index, a conflict-index subsystem, transaction journals,
copy-on-write state, Morton traversal, or selected-winner division re-evaluation.

The compiler-derived lazy-index hypothesis is credible and measured, but it is not a sequential
correctness blocker. It should remain a bounded measurement/design item until a representative
model demonstrates that due-but-empty lifecycle boundaries are material. The decision becomes
mandatory before a backend-resident GPU lifecycle implementation because an unconditional host
CSR build cannot be part of a GPU claim.

## Authority and invariants

This review is subordinate to CCV1-027 and `spec/lifecycle.md`. Any optimization must preserve:

- fixed-capacity storage established by `max_cells` and finite compiler bounds;
- one immutable pre-lifecycle validation snapshot;
- filtering before conflict priority;
- direct-conflict semantics rather than connected-component suppression;
- canonical semantic ordering and deterministic replay;
- one evaluation of every admitted policy occurrence in planning;
- complete-batch capacity preflight and graceful exhaustion;
- staged atomic publication;
- stable device-sized status values and one host translation boundary; and
- no live registry, symbolic tree, host callback, or mechanism-specific executor branch.

Timing cannot authorize a semantic shortcut. Conversely, a correct but avoidably allocating warm
path does not meet the accepted device-oriented execution contract.

## Method

Measurements used `benchmark/src/lifecycle_performance.jl` with Julia 1.12.1 on a MacBook Pro,
Apple M1 Pro (8 cores), 16 GB RAM, macOS 15.6.1. Each result is the median of five fresh-runtime
executions after one warm execution of the same concrete runtime type. Compilation and runtime
initialization are excluded. Allocation is measured around lifecycle execution only.

These are local engineering measurements, not publication benchmarks. Five samples are adequate
to classify large effects and reject unnecessary machinery; they are not adequate for small
cross-machine timing claims. The script is manual and is not part of ordinary `Pkg.test()`.

## Measured results

### Cadence and lifecycle indexing

Before the cadence-only exit, a no-descriptor-due boundary rebuilt the complete cell-to-site CSR.
The source route was reset -> `_index_lifecycle_representative_sites!` -> descriptor cadence
filtering. After the measured correction, cadence is checked immediately after bounded workspace
reset and before lattice indexing.

| Lattice | No descriptor due, before | No descriptor due, after | Due false cell trigger, after |
|---:|---:|---:|---:|
| 32² | 7.04 μs | 0.375 μs | 5.25 μs |
| 128² | 76.7 μs | 0.208 μs | 69.9 μs |
| 512² | 1.082 ms | 0.250 μs | 1.136 ms |

The after values below one microsecond are timer-resolution-scale; the supported conclusion is that
the no-due path no longer scales with lattice size and remains allocation-free.

Relative to an otherwise identical complete MCS:

| Lattice | No lifecycle | Lifecycle, none due | Due false cell trigger |
|---:|---:|---:|---:|
| 32² | 50.2 μs | 53.9 μs | 58.8 μs |
| 128² | 0.776 ms | 0.806 ms | 0.859 ms |
| 512² | 13.19 ms | 13.37 ms | 14.56 ms |

The no-due overhead is small relative to an MCS. A due false trigger still pays for the complete
CSR even when its evaluator does not require a representative site or cell segment; at 512² this
fixture adds about 1.2 ms relative to the no-due case and about ten percent relative to the control
MCS. That is enough to retain the lazy-index hypothesis, not enough by itself to authorize a
cross-cutting compiler change.

### Fixed-capacity cell scan

With CSR construction excluded, scanning the fixed-capacity cell table for one due false
cell-domain descriptor cost:

| `max_cells` | Median |
|---:|---:|
| 64 | 0.417 μs |
| 1,024 | 0.791 μs |
| 16,384 | 7.50 μs |

This does not justify maintaining a second packed active-cell authority. A backend implementation
may transiently compact active identities with scan/scatter, but V1 should not add a persistent
mutable active index to optimize these CPU measurements.

### Division and competing division policies

The first measurement found allocation proportional to parent area: 1,984, 7,360, 28,864, and
114,880 bytes for 16, 64, 256, and 1,024 sites. Allocation profiling located an allocating
generator in projection evaluation plus a small uninlined tracker copy. After the bounded repairs:

| Parent sites | Median | Warm allocation |
|---:|---:|---:|
| 16 | 1.58 μs | 0 B |
| 64 | 3.46 μs | 0 B |
| 256 | 11.5 μs | 0 B |
| 1,024 | 37.8 μs | 0 B |

For a 256-site parent with multiple valid same-anchor division requests:

| Competing policies | Median | Warm allocation |
|---:|---:|---:|
| 1 | 15.5 μs | 0 B |
| 2 | 19.3 μs | 0 B |
| 4 | 34.6 μs | 0 B |

Every request must be checked for admissibility before priority can select the highest valid direct
competitor; otherwise an invalid high-priority request could suppress a valid lower-priority one.
The current transaction evaluates each partition once during planning, retains the selected valid
labels in fixed site storage, and does not invoke policy code during commit. Re-evaluating only a
winner would either change filtering semantics or create a second policy evaluation. The measured
cost does not justify that tradeoff.

### Request scaling and conflict resolution

The current deduplication, insertion sorting, and pairwise conflict selection are quadratic in the
request bound. Small model-domain creation batches remain inexpensive:

| Requests | Independent | Overlapping with stable priorities |
|---:|---:|---:|
| 4 | 1.83 μs | 1.25 μs |
| 16 | 4.46 μs | 2.79 μs |
| 64 | 26.7 μs | 14.0 μs |

A more representative cell-domain transition workload makes the growth visible:

| Active cells | One request/cell | Two competing requests/cell |
|---:|---:|---:|
| 32 | 6.33 μs | 18.3 μs |
| 128 | 90.0 μs | 149 μs |
| 512 | 0.810 ms | 2.23 ms |

The algorithms are intentionally bounded and remain acceptable for the V1 proof-model scale, but
they become material around hundreds to one thousand requests on this machine. Preallocated anchor,
site, and relationship-edge stamps could preserve canonical priority traversal while replacing
many selected-request scans with direct footprint lookups. That is a plausible later optimization,
not a current-gate requirement: it adds new fixed storage, relationship-edge indexing, adaptation,
and backend proof obligations. It should be implemented only if representative lifecycle-heavy
models repeatedly reach this range and end-to-end MCS measurements show material overhead.

### Full-state staging and publication

One transition, including full ownership/cell/state/tracker staging and publication, measured:

| Lattice / cell capacity | Median | Warm allocation |
|---|---:|---:|
| 32² / 64 | 3.92 μs | 0 B |
| 128² / 256 | 20.2 μs | 0 B |
| 512² / 1,024 | 0.283 ms | 0 B |

At 512², full staging is roughly two percent of the otherwise identical 13.19 ms control MCS.
This supports the V1 choice: full staging is simple, deterministic, and makes atomic publication
obvious. Journals, copy-on-write state, and affected-range staging would add aliasing, rollback,
and backend complexity without a measured need.

## Index requirement hypothesis

The compiler can in principle distinguish three requirements:

1. **No lifecycle site index:** model-domain triggers and cell-domain operations whose analyzed
   reads do not consume site context or cell-owned sites.
2. **Representative site only:** a cell-domain evaluator that actually consumes its bound site's
   context but no complete cell segment.
3. **Complete cell-site segments:** removal, division, connectivity validation, or another analyzed
   operation whose finite reads or write footprint requires all owned sites.

The existing analyzed expression footprints and closed effect taxonomy contain much of this
information. An external operation must declare context-derived reads honestly through its frozen
operation footprint; a callable's implementation cannot be introspected safely. Before adding plan
flags, a focused design check must prove that every external lifecycle operation can distinguish
site-context use from merely receiving a lifecycle context. Without that proof, lazy indexing could
silently give an external callable a dummy site.

Therefore this remains measurement/design work. It is not safe to infer index requirements merely
from a callable name, role, or observed behavior.

## Backend-residency finding

There is no backend-resident GPU lifecycle path today. `LifecycleExecutionPlan`, flat relation
storage, and `LifecycleWorkspace` adapt structurally, but lifecycle orchestration is a set of host
Julia loops with scalar indexing. Neither `KernelAbstractions` nor `AcceleratedKernels` is invoked
by the lifecycle execution files. The common post-MCS route calls this host executor for the
sequential engine; adapting its arrays does not make that route a device program.

The minimum honest accelerator boundary is a backend-dispatched schedule-through-publication
pipeline over adapted plan and workspace storage:

1. evaluate due descriptors and bounded trigger domains;
2. build any required canonical cell-site representation with count, scan, and scatter;
3. emit and compact requests;
4. plan placement/partition and validate request-local admissibility;
5. resolve conflicts in canonical semantic order;
6. scan free identities and preflight complete-batch capacity;
7. stage ownership, cell, tracker, state, and relationship changes;
8. reduce postconditions into the fixed status payload; and
9. publish atomically, with only the declared status/capacity synchronization visible to the host.

KernelAbstractions should own portable kernels and launch boundaries. AcceleratedKernels scan,
compact, scatter, fill, and copy primitives are appropriate where they preserve the canonical
representation. A GPU claim is invalid until the entire route runs without host scalar access,
hidden fallback, or policy re-evaluation on every claimed backend.

## Bounded options

### Essential before the current lifecycle gate

- Keep the measured no-due cadence exit.
- Keep zero warm allocation for state-bearing external operations and divisions.
- Keep one-evaluation division planning and fixed selected-label storage.
- Replace adaptable-storage-only host orchestration with the backend-resident transaction DAG in
  the amended lifecycle contract.
- Keep status and stop state on the backend and translate only at an explicit terminal boundary.
- Run the focused correctness, inference, allocation, and artifact-inventory checks on the exact
  candidate.

### Measurement-only additions

- Retain `benchmark/src/lifecycle_performance.jl` as an explicitly manual workload matrix.
- Repeat the due-empty, request-scaling, division, and staging cases when checkerboard/device
  lifecycle execution exists.
- Add representative Wortel/Merks lifecycle request counts only after those models migrate; do not
  turn them into ordinary CI timing thresholds.
- Prototype compiler-derived index requirements only behind an inspection/benchmark comparison,
  including external-operation footprint audit, before changing the plan schema.

### Optimizations that wait for evidence

- Lazy representative-site and full-segment CSR construction for due descriptors.
- Anchor/site/relationship-edge stamping when real workloads repeatedly approach hundreds or
  thousands of simultaneous requests.
- Optional affected-range staging only if full-state copy becomes a material fraction of measured
  end-to-end MCS cost on representative workloads.

### Explicitly rejected V1 complexity

- A persistent packed active-cell index on CPU or GPU solely to avoid the measured cell-table scan.
- Transaction journals or copy-on-write state for the measured V1 staging costs.
- Morton ordering inside cell segments without an end-to-end division benchmark that beats
  canonical linear-site traversal and preserves exact replay.
- Re-evaluating a selected division policy during commit.
- A general footprint query/index language, dynamic registry, or alternate lifecycle executor.
- Absolute wall-time pass/fail thresholds in ordinary CI.

## Performance contract to freeze

The V1 lifecycle contract should be structural and comparative:

- concrete inference for the complete warm sequential transaction path;
- zero warm allocations for no-due, due-empty, create, transition, remove, retire, division,
  external-operation, relationship, and failure-status paths;
- no-due work scales with descriptor count, not lattice size;
- cell-domain emission scales linearly with fixed cell capacity before request interaction;
- plane division scales linearly with the source-cell site count and invokes each policy occurrence
  once;
- current request selection is documented as bounded quadratic and is measured outside ordinary CI
  at representative request counts;
- full-state staging scales linearly with authoritative fixed storage;
- lifecycle overhead is reported relative to an otherwise identical MCS; and
- every future optimization re-runs deterministic replay, canonical conflict, atomic failure,
  fixed-capacity, checkpoint, and backend conformance tests.

This contract avoids arbitrary nanosecond thresholds while still preventing allocation,
asymptotic, and backend-residency regressions.
