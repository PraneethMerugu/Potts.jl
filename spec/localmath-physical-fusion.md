# LM-8: semantic-preserving physical fusion

Status: implemented on the sole LocalMath execution path. This document
records the physical optimization and its legality contract, not a new
mathematical language or execution mode.

## Objective

Reduce KernelAbstractions launch overhead and avoid redundant intermediate
traffic while preserving the exact `LocalLaw` stage order, stage-entry reads,
publication laws, validation barriers, receipt behavior, source provenance,
and one packed CPU/GPU execution path.

The accepted architecture is:

```text
LocalLaw and existing producer dependencies
        ↓
exact fusion legality
        ↓
conservative structural profitability
        ↓
physical launch segments
        ↓
the existing KernelAbstractions executor
```

KernelAbstractions and GPUCompiler compile a supplied kernel; they do not own
the scientific information needed to combine separate LocalMath launches.
Fusion therefore belongs in LocalMath planning. It must not introduce another
semantic IR, scheduler, executor, backend branch, runtime graph, user schedule
language, or compatibility path.

## Research conclusion

The repository already contains the required semantic authorities:

- `Stage` and `LocalLaw` own logical order and authored provenance;
- stage dependency analysis identifies external and preceding-stage reads;
- `Relation` values and proofs own index topology and coverage;
- publication laws own conflict, order, empty, and participation semantics;
- lowering entries own the selected physical algorithm family;
- workspace authority owns materialization and lifetime;
- prepared launches own concrete KernelAbstractions realization.

The first fusion implementation must extend the existing direct identity-
`Unique` executor. A new fusion graph or general tensor compiler would duplicate
facts already present in these authorities.

The design follows the useful parts of established systems without importing
their object models:

- Julia broadcast and Tullio demonstrate that one explicit high-level region
  can generate one traversal or kernel;
- Halide separates algorithm meaning from compute and storage placement;
- MLIR Linalg proves producer-consumer fusion from iteration and indexing maps;
- XLA and Futhark separate legality from profitability and avoid duplicated
  work or lost parallelism;
- Devito clusters equations with compatible iteration and dependency structure;
- AcceleratedKernels may improve unavoidable scans, sorts, and reductions, but
  does not remove their semantic barriers;
- CUDA graphs reduce repeated submission overhead but are not fusion and are
  not a portable LocalMath foundation.

## Transaction foundation

CorePotts relationship `OrderedFold` state now uses package-owned packed shadow
Fields initialized from the active bank. Tracker reductions and accepted
ordinary effects use scratch Fields. Original descriptor ordinals remain in
relationship requests, and one infallible terminal publication commits live
scientific storage only after every preceding LocalMath stage succeeds. No
warm relationship unpacking, copying, or allocation was introduced.

## Exact fusion legality

Consecutive logical stages may share one direct physical launch only when all
of the following hold:

1. Every member already qualifies for the existing direct identity-`Unique`
   layout. It therefore has identity-routed width-one publications, no dynamic
   relation receipt, no bounded-fold rejection, infallible relation keys,
   admissible empty behavior, and pointwise destination aliasing.
2. Every member has the exact same iteration traversal, source identity,
   source count, and lane ownership. Equal extents alone are insufficient.
3. A Field produced earlier in the segment is consumed later only through an
   exact same-item identity read or same-item mask.
4. A produced Field does not feed an off-item access, neighborhood gather,
   routed key, subset relation, collection access, field prefix, or global
   field gate inside the segment. A singleton control may be admitted only
   after an exact proof that it is lane-independent and already available at
   segment entry.
5. No member can create a global failure that later lanes would need to observe
   inside the same kernel. Runtime prefixes are admitted only when their bounds
   prove validity before execution; otherwise they terminate the segment.
6. No grouped `Unique`, `Reduce`, `Resolve`, `Collect`, `OrderedFold`, dynamic
   relationship validation, refreshed program-status gate, or other
   grid-visible transaction boundary crosses the segment.
7. Distinct descriptors with potentially aliasing physical storage terminate
   the segment unless the existing binding proof establishes the exact
   sequential alias behavior.
8. Every logical publication remains materialized initially. A user-visible
   Field retains its exact post-execution value even when a same-item consumer
   can receive the value directly.

The fused kernel executes logical members in authored order for one item.
It must not rely on another workgroup observing an in-kernel status write.
Every source origin and logical stage index remains available for diagnostics.

## Structural profitability

Legality does not imply profitability. Planning forms the longest legal run
that also satisfies one internal structural compilation budget derived from:

- admitted evaluator method count and individual callable complexity;
- combined field, parameter, and control ABI leaves;
- result-port count and concrete aggregate size;
- number of logical members;
- duplicated evaluation and index-map use.

The first policy admits no duplicated producer evaluation, no reduction in
available parallelism, and no differing-index multi-consumer forwarding. It
must eliminate at least one launch. The budget is an internal physical-planner
heuristic calibrated by the ordinary compiler-scaling and real-Metal
benchmarks; it is not a public option, semantic limit, hardware allowlist, or
wall-time gate. Inspection explains a split as `:compile_complexity` without
turning the budget into another execution authority.

The initial direct segment limit is four logical members. Focused 2/4/8-member
CPU and Metal measurements determine whether that internal limit should move;
it is not inferred from a backend name and is not part of the public contract.

Do not construct an unbounded tuple containing a complete program. Physical
segments remain stage-local erased entries so compilation scales with segment
schemas rather than program length or stage position.

## Direct implementation slices

### LM-8A: truthful physical baseline

- Derive a launch histogram from existing `inspect(plan)` and
  `inspect(prepared)` projections. Store no benchmark-side phase schedule.
- Replace the stale hard-coded CorePotts benchmark launch formula with this
  source-owned projection.
- Record the current 1/4/8/13/32-stage programs, the two-stage pointwise
  witness, multi-port Collect, OrderedFold at several bounded sizes, and
  minimal/contact/tracker/relationship Core programs on CPU and Metal.
- Measure cold planning, preparation, first compilation, warm submission,
  workspace, host bookkeeping, and representative throughput using ordinary
  benchmark programs. Add no timing threshold or qualification script.

### LM-8B: direct pointwise launch segments

- Coalesce consecutive legal direct entries during the existing stage-program
  lowering.
- Use `_DirectPointwiseSegmentPreparation` for one to four logical direct
  members and one bounded tuple-specialized KernelAbstractions kernel.
- Replace the singular direct kernel and preparation in the same edit; retain
  no single-stage alternate executor.
- Change prepared runtime ownership from a logical-stage-aligned vector to an
  erased physical-launch vector. Singleton Candidate, Collect, and OrderedFold
  launches remain ordinary entries in that vector.
- Preserve all intermediate writes. Forward same-item produced values to later
  evaluators only after launch fusion itself is qualified, and continue writing
  every observable destination.
- Preserve per-stage source provenance and deterministic error attribution.

The two-stage direct pointwise witness must change from one program reset plus
two direct launches to one program reset plus one direct launch. Independent
stages and vertical same-item producer-consumer stages both qualify when the
legality predicate holds.

### LM-8C: proven administrative launch deletion

Perform these direct replacements independently; each deletes its replaced
kernel or host launch loop in the same edit.

1. Combine program-status reset with the first unresolved dependency join in
   one one-lane KA kernel. Zero-dependency submissions retain the reset; later
   unresolved dependencies retain ordinary joins.
2. Move Candidate diagnostic finalization into Candidate publication only
   after proving that every globally failing evaluation, grouping, validation,
   and optional atomic phase has completed. Publication lanes continue to
   check the finalized diagnostic status before writing; lane one records the
   contextual receipt status. If this proof fails for any Candidate family,
   that family retains the separate barrier.
3. Combine OrderedFold order validation and shadow-state initialization in one
   parallel kernel. Initialization remains package-owned shadow work; serial
   recurrence and final failure-atomic publication remain separate.
4. Publish independently validated Collect ports in heterogeneous chunks of at
   most four, using the maximum required extent and per-port bounds, replacing
   the current one-launch-per-port loop. The existing Collection uniqueness
   proof must also establish physical nonaliasing between ports.

Reset/evaluation fusion is explicitly excluded. Candidate, Collect, and
OrderedFold reset kernels clear shared status, padded ordering, grouping, or
destination state that evaluation lanes do not uniquely own. Clearing that
state while other workgroups update it would race.

### LM-8D: Core compiler adoption

After the Core transaction precondition is corrected:

- place compatible independent direct stages consecutively and allow the same
  LocalMath segmenter to fuse them;
- qualify contact/reverse-contact owner and kind construction as the first
  concrete case;
- consolidate tracker publications into an existing multi-port Candidate only
  when they share source traversal, control, reads, and failure semantics;
- retain refreshed Core status gates, owner resolution, relationship shadow
  settlement, lifecycle, rollback, and bank publication as explicit barriers.

CorePotts gains no fusion planner or schedule language. It supplies domain
semantics and ordinary `LocalLaw`; LocalMath remains the sole physical fusion
authority.

### LM-8E: same-item value forwarding

After direct launch fusion is stable, allow a produced identity value to feed
same-item downstream reads from a lane-local value rather than reloading it
from global memory. The corresponding Field write remains unless the public
storage contract is separately changed; LM-8 does not invent non-observable
Fields or eliminate bound scientific storage.

Forwarding rejects differing index maps, off-item reads, recomputation, and
unproven aliases. Inspection reports forwarded values and retained
materializations from the actual prepared segment.

## Required physical barriers

The following remain separate launches unless a later physical algorithm
removes the global dependency while preserving the same mathematical law:

- every global grouping local-sort/merge/directory dependency;
- every hierarchical scan level and scan-add dependency;
- every global bitonic pass;
- Candidate validation before relaxed atomic work or publication;
- Collect finalization before scientific publication;
- OrderedFold initialization, serial recurrence, and final commit;
- relationship content reset, validation, finalization, and receipt
  publication;
- off-item consumption of a preceding publication;
- refreshed program-status, lifecycle, rollback, authorization, and bank-
  publication boundaries.

KernelAbstractions workgroup synchronization is not a portable grid barrier.
Cooperative kernels, vendor events, CUDA graphs, or raw backend APIs must not
be introduced to bypass this rule.

## Inspection

Logical inspection remains unchanged: `stages`, accesses, producers,
publications, controls, origins, and equivalence continue to describe the
authored `LocalLaw`.

Physical inspection is derived from actual lowering or prepared launch values
and adds a compact projection such as:

```julia
(
    kind = :direct_identity_unique,
    logical_stages = (1, 2, 3),
    launch_count = 1,
    forwarded = (:source, :owner),
    materialized = (:source, :owner, :accepted),
    boundary_after = :routed_conflict,
)
```

`base_provider_launch_count` is computed from physical segments rather than a
sum that assumes one physical entry per logical stage. Prepared inspection
reports prepared launch types, not fictional prepared-stage types. Boundary
reasons include at least `:different_traversal`, `:off_item_visibility`,
`:global_failure`, `:routed_conflict`, `:relationship_validation`,
`:ordered_state`, `:alias_uncertain`, and `:compile_complexity`.

This projection is not stored as a second report and is never consumed by
planning or execution.

## Validation and performance evidence

Use ordinary LocalMath, CorePotts, PottsToolkit, integration, documentation,
compiler-scaling, scientific-witness, and real-Metal tests on the repository
Julia version.

Required correctness cases include:

- independent, vertical same-item, conditional preserve/fill, mask, gate, and
  statically valid prefix pointwise chains;
- exact rejection of off-item producer reads, global produced controls,
  uncertain aliases, routed publications, relationship guards, and fallible
  evaluator stages;
- logical stage-entry behavior and final observable intermediate Fields;
- earliest authored-source failure attribution;
- dependency arities 0/1/2/4 and deterministic predecessor failure;
- Candidate, Collect, and OrderedFold success and intentional failure with no
  scientific publication before their final barriers;
- identical CPU and Metal laws, numerical results, conflict selection, empty
  behavior, receipts, and inspection structure;
- zero warm Julia compilation, relationship packing, device allocation, and
  hidden synchronization.

The existing alternating synthetic stage programs remain useful because direct
pointwise fusion should not change their launch count. If Candidate
finalization is safely absorbed by publication, their current counts
`2, 22, 53, 90, 231` become `2, 20, 49, 84, 218` for 1/4/8/13/32 stages.
OrderedFold saves one launch per fold, multi-port Collect publication changes
from `P` launches to `ceil(P / 4)`, and a chained submission saves one
reset/join launch. Exact Core savings are reported only after physical-segment
inspection measures them.

Performance review compares launch count, global intermediate bytes, workspace,
cold typed-IR and preparation cost, first device compilation, warm submission,
register or occupancy evidence where the backend exposes it, and end-to-end
throughput across small, medium, and large problems. Retain a fusion only when
it actually removes physical work and improves repeated measurements beyond
noise without materially worsening cold compilation. This is an engineering
decision from reproducible benchmarks, not a frozen wall-time gate.

## Explicit non-goals

LM-8 does not add:

- a public fusion or scheduling API;
- another semantic or executable IR;
- a task graph, persistent kernel, or alternate executor;
- fusion across grid-visible conflict or transaction barriers;
- unrestricted recursive inlining or mandatory recomputation;
- a large autotuner or XLA-style general cost model;
- backend-specific graphs, cooperative launch, events, or raw Metal/CUDA code;
- a claim that all logical stages, one MCS, or one checkerboard color become one
  kernel;
- removal of CorePotts shadow-bank storage or full-array copy bandwidth merely
  because its copy stages share a launch;
- tiled stencil fusion or distributed scheduling. Those require separate
  evidence after same-item fusion is established.

LM-8 succeeds when LocalMath can explain and execute fewer physical launches
from the same logical law, with source-visible boundaries wherever the
mathematics, transaction contract, or portable hardware model requires them.

## Research references

- [Julia fused broadcast](https://docs.julialang.org/en/v1/manual/functions/#man-vectorized)
- [KernelAbstractions synchronization](https://juliagpu.github.io/KernelAbstractions.jl/v0.9/api/)
- [Tullio indexed-kernel generation](https://github.com/mcabbott/Tullio.jl)
- [AcceleratedKernels portable algorithms](https://github.com/JuliaGPU/AcceleratedKernels.jl)
- [Halide multi-stage scheduling](https://halide-lang.org/docs/tutorial/lesson_08_scheduling_2.html)
- [MLIR Linalg producer-consumer fusion](https://mlir.llvm.org/docs/Tutorials/transform/Ch0/#producerconsumer-fusion-and-rematerialization)
- [MLIR bufferization and alias analysis](https://mlir.llvm.org/docs/Bufferization/)
- [XLA GPU fusion architecture](https://openxla.org/xla/gpu_architecture)
- [XLA GPU emitters](https://openxla.org/xla/emitters)
- [Devito compiler pipeline](https://www.devitoproject.org/examples/compiler/00_index.html)
- [Futhark fusion research](https://hjemmesider.diku.dk/~zgh600/Publications/TroelsPhD.pdf)
