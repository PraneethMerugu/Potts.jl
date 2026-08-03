# Lifecycle Fixed-Capacity Mask Pipeline Review

Date: 2026-08-03

Branch: `codex/symbolic-potts-v1`

Status: narrowed architecture implemented for the first complete division witness; independent
quality clearance and all-effect qualification remain pending

## Implementation checkpoint

The subsequent candidate resolves the blocking semantic prerequisites identified below without
introducing the speculative parallel mask matrix:

- lifecycle state evaluators now have distinct immutable before and planned-after views;
- structural/tracker planning precedes relationship and state-policy application;
- structure, relationships, state policies, finalization, validation, and publication are separate
  ordered backend stages over the same frozen descriptors;
- the entire proposal-plus-lifecycle MCS executes in an inactive complete scientific-state bank;
- publication changes the active bank and committed MCS only while sticky status remains successful;
- exact first failure MCS, stage, source, and action identity are stamped on-device;
- two MCS can be queued before one CorePotts settlement on CPU and real Metal; and
- a capacity failure in the first queued MCS leaves the original bank at committed MCS zero while
  the second queued MCS drains as status-gated no-op work.

The measured Metal results for that bounded candidate are:

```text
success: submitted=2, drained=2, committed=2, settlements=1
capacity failure: submitted=2, drained=2, committed=0,
                  failure_mcs=1, stage=selection, settlements=1
```

This accepts the small ordered-kernel direction in narrowed form. It does not yet claim every
lifecycle effect/policy family, CUDA/ROCm qualification, or an end-to-end PottsToolkit SciML GPU
runtime. Those remain explicit gate work rather than inferred from the division witness.

## Verdict

Revise and narrow the fixed-capacity mask architecture before accepting it as the lifecycle
execution design. Compile-time reachability masks, runtime request masks, cell-selected request
maps, and compact site labels are useful categories, and small ordered kernels remain preferable
to one all-policy kernel. They address generated-code pressure; they do not by themselves solve
lifecycle transaction planning, deterministic tracker repair, or whole-MCS atomicity.

A single site label cannot represent competing division geometries for the same source cell. A
request-by-site matrix is rejected, while choosing a high-priority candidate before validating it
would let an inadmissible request suppress a valid lower-priority competitor. The conservative V1
choice is canonical request-local validation, conflict resolution after invalid requests are
removed, and deterministic re-materialization of selected winners into one compact site-label
vector. A per-cell worker that validates that cell's competing requests serially while cells run in
parallel is a valid measured alternative; it is not required now.

Real Metal now compiles the isolated specified-normal/canonical division planner and selected-winner
replanner. The traced full compilation attempt next stalled at synthesized retirement application,
before division application. This does not justify blindly decomposing the existing mutating
application code. The next design task is a plan-before-mutate pipeline whose evaluators can observe
immutable before and compiler-defined planned-after views.

## Preserved invariants and current gap

The design must preserve:

- one frozen lifecycle plan and evaluator closure;
- one request-emission, canonicalization, conflict, capacity, validation, and publication authority;
- immutable pre-lifecycle evaluation state;
- filtering of inadmissible requests before final conflict winners;
- canonical first-failure, conflict, and addressed-RNG ordering;
- fixed-capacity cell, relationship, request, and workspace storage;
- the sequential transaction as the scientific oracle;
- backend-neutral KernelAbstractions and AcceleratedKernels execution; and
- status-gated inactive-bank mutation followed by validation and one publication point.

The current working tree does not yet establish whole-MCS atomicity. Lifecycle staging is local to
the lifecycle transaction, while checkerboard proposal commits mutate the current state earlier in
the same MCS. Two complete scientific-state banks, sticky status, and a single whole-MCS publication
point remain blocking requirements.

Compile-time and runtime masks remain different facts:

| Category | Representation | Meaning |
| --- | --- | --- |
| structural reachability | immutable scalar masks in the compiled plan | Which effect, partition, side, state-action, and relationship-action kernel families can launch. |
| request state | fixed request vectors and request-local status | Which emitted requests remain eligible in this transaction. |
| selected cell action | one fixed request slot per cell | Which selected request owns that cell's ownership mutation. |
| site result | one compact label/action per canonical packed site position | The selected, nonconflicting mutation, never every candidate geometry. |

These masks must not become an interpreter, registry, model-specific branch, or source of
specialization by statement name, request identity, cell identity, or MCS value.

## Minimal kernel decomposition

The smallest defensible target is:

```text
reset transaction scratch while preserving sticky failure
→ build canonical cell→site indexes
→ emit, compact, and canonically sort due requests
→ validate request-local effects through reachable structural planners
→ validate relationship admissibility
→ reduce request-local status in canonical request order
→ resolve conflicts and capacity
→ clear selected partition-evaluator workspace slices
→ re-materialize selected division winners into compact site labels
→ build selected-request-per-cell maps
→ plan and validate every selected relationship and state consequence
  against immutable before and compiler-defined planned-after views
→ stage the inactive whole-MCS scientific-state bank
→ apply pre-structural relationship policies
→ apply structural cell/site mutations
→ repair trackers and indexes in deterministic canonical order
→ apply post-structural relationship policies
→ apply already validated state updates
→ finalize retirement metadata and counters
→ validate staged invariants
→ publish the complete bank and cumulative status/counters
```

Allocation-dependent create and division initialization may be planned after capacity assigns
identities, but before scientific-state application. Transition values must be planned before
kind/property mutation. Division policies depending on derived observables must see repaired
planned-after observables, and equilibrium policies must see final post-division observable values.
Existing evaluator contexts read current runtime trackers, so the planned-after evaluator view is a
missing, blocking boundary.

The selected-winner replan is deterministic re-materialization of an already validated winner, not
a second filtering opportunity. A changed admissibility result is a nonfilterable internal invariant
failure; it must not silently select a fallback. `partition_labels` is indexed by canonical position
in the packed cell-site CSR, not directly by lattice site; application resolves labels through
`site_position`. Selected requests cannot share source ownership sites after conflict resolution.

Removal and death use a lighter structural path:

```text
selected request per cell
→ parallel ownership clearing/replacement in the inactive bank
→ deterministic tracker/index repair
→ separately ordered relationship and state retirement
→ metadata finalization
```

Only ownership-site writes are presently proven unique. Tracker updates and relationship incidence
can target common neighboring cells or endpoints. Relationships therefore remain canonical-serial
until exact footprints justify disjoint batching. Tracker repair must either reconstruct all active
cells in canonical CSR/site order or use a proven neighbor-expanded affected set. Floating
schedule-dependent atomics are incompatible with exact replay.

## Fixed workspace

Existing fixed storage already supplies:

- request activity, filtering, selection, and canonical-order vectors;
- request-local status;
- cell-site CSR and representative-site data;
- one request owner per cell and one byte label per canonical packed site position;
- staged ownership, metadata, tracker, relationship, and descriptor-state storage; and
- fixed scan/sort/status/counter scratch.

The minimum known addition for parallel ownership application is one generic
`selected_request_by_cell::Vector{Int32}` of length `max_cells`, unless `partition_owner` is safely
generalized. That is not a complete workspace specification. Planned-after evaluation and
deterministic tracker reconstruction may require fixed tracker/index scratch or a canonical
affected-cell mask. Those additions must follow from the tracker protocol and measurements. No
request×site mask, visited, or label matrix is admitted.

Request-local geometry and count arrays are optional. Add them only if splitting geometry from
connectivity materially reduces generated code or improves an end-to-end workload.

## Authoritative semantics

The decomposition must reuse or factor these authorities rather than duplicate their meaning:

- `_lifecycle_due` and frozen trigger evaluators;
- `_sort_lifecycle_requests!` and `_lifecycle_request_key`;
- `_plan_division!`, its pure structural labeling helpers, and `_partition_connected`;
- `_lifecycle_relationships_admissible`;
- `_resolve_lifecycle_conflicts!`;
- `_preflight_lifecycle_capacity!`;
- `_stage_owner_change!` as the sequential consequence oracle;
- action-specialized forms of existing state-rule evaluators;
- existing relationship-rule operations;
- `_validate_staged_lifecycle!`; and
- one status-gated publication authority.

Backend execution additionally needs a reusable, nonallocating deterministic tracker-repair
authority. Current whole-state tracker rebuild/recompute functions allocate, while the sequential
lifecycle path updates trackers serially through `_stage_owner_change!`; neither is yet the required
generic backend implementation.

Parallel kernels may factor shared pure primitives from these functions. They must not create a
second partition formula, evaluator, conflict rule, or mutation authority.

## Atomicity and deterministic ordering

Masks and labels are transaction scratch. In the target design, scientific mutation touches only
the inactive whole-MCS bank. No mask is host-read between kernels. Sticky first failure gates every
later write and queued MCS. These are required target properties, not current conformance evidence.

Canonical behavior requires:

1. request-local failures reduce by canonical request order, never kernel launch order;
2. invalid requests are removed before conflict selection;
3. selected division winners are re-materialized deterministically after grouping;
4. selected partition scratch is reset on-device before re-materialization;
5. daughter identities follow canonical selected-request order;
6. all selected relationship and state consequences are planned and validated before mutation;
7. pre/post-structural relationship and state application retains accepted effect ordering;
8. tracker folds have a documented deterministic order; and
9. committed time advances only after complete validation and publication.

An iterative provisional-selection algorithm could avoid validating all competitors, but it needs a
proof that bounded iterations reproduce the accepted greedy winner set. It is deferred unless
candidate validation is measured as material.

## Generated-code and Metal evidence

| Candidate | Observed result |
| --- | --- |
| one all-effect planner | about 1.6 MiB LLVM; Metal native compilation failed or remained unbounded; about 197 million compilation-inclusive Julia allocations at termination |
| reachable effect grouping | unused effects disappeared, but reachable monolithic division remained outside the bounded run |
| partition×side planner plus relationship validation | specified-normal/canonical planning and selected-winner re-materialization compiled and enqueued on real Metal |
| isolated current division planner | 1,068,378 bytes optimized LLVM; real Metal compilation and execution completed in a bounded run |
| traced lifecycle compilation attempt | reached planning, relationship validation, conflict/capacity, selected replan, and state staging; stalled at synthesized retirement application; no complete transaction executed |

The division kernel remains large. Generated-code inspection and bounded compile qualification
should remain explicit tools, but this result does not prove an end-to-end performance improvement.
The compiler pressure moved to application/state code; semantic planning must be repaired before
that code is decomposed further.

The backend-neutral fixture is not full lifecycle conformance evidence. It currently covers one
specified-normal/canonical division and one split state rule, not all effects, relationships,
failure paths, whole-MCS banks, or publication. It exposed a genuine initialization defect: backend
control counters were allocated uninitialized, so a fresh cumulative retired count was
nondeterministic. That defect requires a bounded regression test before even the narrower fixture is
cited as passing.

## Disposition

Accept as architectural direction:

- structural reachability masks;
- fixed runtime request masks and canonical request-local status;
- selected-winner deterministic re-materialization;
- one selected request per cell and one compact selected label per packed site position;
- small ordered planning, application, validation, and publication kernels; and
- parallel unique ownership-site writes followed by deterministic repair.

Essential before implementation continues:

- immutable before and planned-after evaluator views;
- planning and validation of all selected consequences before mutation;
- a nonallocating deterministic backend tracker-repair authority;
- two-bank whole-MCS atomicity with sticky failure publication; and
- broader backend-neutral correctness coverage before conformance claims.

Defer pending evidence:

- per-cell parallel candidate workers or iterative provisional selection;
- fully parallel connectivity analysis;
- packed active-cell indexes;
- request-local geometry/count buffers;
- retained snapshots, fusion, or backend-specific tuning.

Reject:

- request-by-site matrices;
- winner-first validation without a proved fallback algorithm;
- host polling, fallback, transfer, or scalar device indexing;
- backend-specific scientific branches;
- launch-order-dependent winners, folds, or failure identity;
- a second lifecycle evaluator or mutation authority; and
- weakening whole-MCS atomicity to simplify execution.

The mask approach is therefore **revised and narrowed before acceptance**. It is the right
generated-code shape for selected ownership mutations and reachable planning, but not yet a complete
transaction architecture. Plan-before-mutate evaluation, deterministic tracker repair, whole-MCS
banking, and wider correctness evidence are the next constraints.
