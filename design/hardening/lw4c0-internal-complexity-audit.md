# LW-4C0 LocalWorksets internal complexity audit

Status: complete candidate for LW-4C1 entry

Date: 2026-08-11

## Boundary and preserved baseline

This audit does not reopen the accepted LocalWorksets architecture, lifecycle, names or
direct/buffered execution-family algebra. It audits the exact LW-R2B candidate before any
production consolidation.

The recoverable baseline is Git commit `44389fc` (`Freeze qualified LW-R2B candidate`). Its
authoritative 61-row content manifest is
`design/hardening/lw4b-b5-final-hashes.sha256`; every row verified immediately before the commit.
The commit also includes that manifest itself, hence Git reports 62 committed files.

Baseline qualification to preserve:

- standalone LocalWorksets: 511/511;
- CorePotts: 17,462/17,462;
- PottsToolkit root: 2,232/2,232 (wall time deliberately excluded because the laptop travelled
  during the run);
- all five controlled CPU witnesses passed;
- complete real-Metal runner passed, including cross-domain 8/8 and native 37/37;
- final Metal D2Q9 upper-95 direct-parity ratio: 1.0102096167;
- final Metal generic z-buffer upper-95 direct-parity ratio: 1.0433520766, with finite margin to
  the 1.05 gate; and
- final Metal CorePotts LW-3 upper-95 ratio: 1.0237674656, with 600 submitted/drained and no poison.

The 84m38 root-suite duration is environmental travel/power-state noise and is not a performance
baseline. Only the controlled CPU and real-Metal measurements are performance evidence.

## Size and ownership inventory

The production package contains 18 source files, 7,745 physical lines, 324 blank lines, 57
comment-only lines and 7,364 nonblank/noncomment lines. Size alone is not a defect; the audit asks
whether each layer has one owner and whether repeated code encodes a real semantic distinction.

| Layer | Current owners | Disposition and justification |
|---|---|---|
| Public lifecycle | `LocalWork`, `WorkPlan`, `PreparedWork`, `WorkEvent` | Retain. Each names one accepted ownership transition: declaration, validated reusable plan, concrete bound state and cumulative execution receipt. |
| Construction boundary | `_ConstructionToken` and inner constructors | Retain. Prevents callers from forging lifecycle values around central validation. |
| Output declarations | independent, combined, generic resolved declarations and emission/candidate values | Retain. They encode materially distinct publication/conflict laws in concrete isbits types. |
| Combination marker | `_AbstractCombinationLaw` with one concrete subtype | Conditional. It currently adds no dispatch or safety value, but may earn a role in the frozen extension API. Remove in C3 if it remains a decorative pseudo-extension point. |
| Legacy masked resolved declaration | `_MaskedEmission`, `_ResolvedOutput`, `_ResolvedSelection` | Removal candidate. It is used by the legacy four-launch fixture path; generic `candidate(rank, value, when)` expresses the accepted public resolved law more directly. Preserve until executable convergence is proved. |
| Ordered composition | `_SequenceOperation`, `_SequenceLowering` | Retain. It composes already admitted stages under KernelAbstractions program order without waits or a scheduler. |
| Submission slots | `_ValueSlot`, `_StorageSlot` | Retain. They freeze scalar bounds and concrete array type/layout/backend/device/access contracts before submission. |
| Direct lowering | `_DirectIndependentLowering`, `_PreparedDirectIndependent` | Retain. One launch, no algorithmic workspace, and the D2Q9 consumer justify a distinct lowering. |
| General buffered lowering | `_BufferedCombinedLowering`, `_PreparedBufferedCombined` | Retain. It is the reusable heterogeneous independent/combined/resolved mechanism and owns deterministic records or qualified fast atomics. |
| Two-launch single-resolved runtime | `_PreparedSingleResolved` and fixed 1–4-read kernels | Retain. This is the performance-qualified generic z-buffer specialization. The Metal upper-95 result is 1.0433520766, so its headroom is finite and every C1 change requires remeasurement. |
| Legacy four-launch resolved lowering | `_ResolvedWinnerLowering`, `_PreparedResolvedWinner` | Conditional removal. It is a parity/test oracle, has no CorePotts or cross-domain production consumer, and is not the performance-qualified generic specialization. Remove only after generic resolved reproduces its mask, active-prefix, topology, empty, failure, lifetime and inspection obligations on CPU and Metal. |
| Conjunctive lowering | `_ConjunctiveResolvedLowering`, `_PreparedConjunctiveResolved` | Retain. Two dynamic claims must both win before an item-aligned result changes; this is not destination publication. It is the qualified CorePotts vertical and has zero static topology transfer. |
| Provider ownership | `_AbstractProviderLane`, `_KernelAbstractionsScope`, `_KernelAbstractionsLane` | Retain. Scope owns shared implicit-order failure/wait state; lane owns one prepared lifecycle and wait count. There is exactly one portable synchronization point and no native scheduler/event fiction. |
| Reviewed backend rows | `localworksets_evidence.jl` | Retain and isolate. It is qualification metadata, not vendor-specific execution code or inferred portability. |

## Duplication map and C1 seams

### C1-A — common checked topology and route structure

Duplicated owners:

- `_generic_topology_header`;
- `_resolved_topology`;
- `_conjunctive_topology`;
- `_validate_independent_route`; and
- `_validate_combined_route`.

Shared facts are exact `UInt64` epoch, lossless host-`Int` conversion, nonnegative or positive
capacity, Int32 kernel-ABI bounds, one-based item-domain equality, dense matrix type/shape,
concrete integer route type, checked `item_count * maximum`, and destination bounds.

C1 may centralize only those structural facts. Independent uniqueness/coverage, buffered segment
construction, resolved semantic-ID uniqueness, static versus dynamic routing, and conjunctive
two-key laws remain family-owned.

### C1-B — binding requirements

Every lowering separately implements some combination of `_required_bindings`, `_binding_access`
and `_validate_binding_schema`. Resolved and conjunctive repeat exact element type, rank, shape and
access checks; direct and buffered repeat output-binding and operation-result checks.

C1 introduces one private immutable binding requirement representation containing logical name,
role, element type, dimensions, exact shape and access. Central helpers derive required names and
access and validate static/submission bindings. Family code retains operation return inference,
rank/mask/gate/eligibility laws, conjunctive pointwise read/write proof and sequence access merging.
No dictionary, abstract container or external validation hook is admitted.

### C1-C — algorithmic workspace specification

The generic buffered, legacy resolved and conjunctive paths independently calculate workspace
shape and bytes, validate caller arrays, enumerate identity-protected arrays, and reconstruct
actual inspection facts. This is the largest clear duplication with one semantic owner.

C1 introduces a private immutable workspace specification whose statically named leaves declare
logical path, exact element type, dense dimensions/strides, capacity and role. One package-owned
implementation drives validation, `_workspace_arrays`, checked byte evidence and prepared
inspection. Physical caller `NamedTuple` shapes and lease ownership remain unchanged. Direct work
has an empty algorithmic specification; sequence composes stage specifications. C1 does not
allocate workspace—automatic bounded construction belongs to C2.

### C1-D — static topology payload

Direct, buffered and legacy resolved paths independently choose the arrays copied during
preparation, repeat CPU-versus-generic-backend dispatch, calculate transfer bytes elsewhere, and
hash related topology in a third place. Conjunctive correctly has an empty static payload.

Each lowering should expose one package-owned, concrete tuple/named-tuple payload. Central leaf
walking copies arrays with the existing `_device_copy` rule and sums checked bytes; no aggregate
`Adapt`, host fallback or vendor branch is allowed. Family-specific semantic headers remain part
of stale-topology fingerprints. Fingerprints must hash validated typed values rather than `show`
or unordered containers.

### C1-E — evidence and inspection construction

Direct and buffered paths repeat per-port route/count/maximum/coverage/law/publication/failure/
empty/determinism fields. Resolved and conjunctive construct the same required envelope and add
semantically important extras. All four determinism builders repeat construction of the same
eight named dimensions.

C1 centralizes the eight-dimension constructor and a required per-port evidence envelope. Callers
must provide every semantic field explicitly; resolved mask facts and conjunctive item-result,
private-key empty state and total-win facts cannot become optional defaults. Phase metadata may be
shared for inspection, but it must never select executable launches.

### C1-F — arbitration primitives, not kernels

Legacy resolved and conjunctive paths duplicate sentinel, min/max rank claim, minimum canonical
identity claim, winner predicate and winner-pair workspace logic. Generic resolved instead emits
bounded records and performs canonical segmented publication.

C1 may share typed inline winner primitives and workspace specifications. It must keep top-level
kernels separate: conjunctive work has two dynamic destinations, requires both claims, observes a
gate and eligibility value, writes an item-aligned result and has no copied topology. It must not
be forced through destination-oriented generic publication.

### C1-G — trusted lifecycle machinery is not duplication

The repeated package-ownership checks around planning, preparation, submission and waiting are
intentional security boundaries. `planning.jl`, `preparation.jl`, `execution.jl` and the
KernelAbstractions provider already have single owners. C1 may factor mechanically repeated
checked callbacks only when hostile-method tests prove that the exact `which`/`invoke` boundary is
unchanged. It must not introduce an executor hierarchy, provider policy or scheduler.

## Specialization decision gate

| Specialization | Present evidence | C1 decision |
|---|---|---|
| direct independent | D2Q9 cross-domain witness; one launch; Metal upper-95 1.0102096167 | Keep. |
| general buffered | springs, FEM, heterogeneous and generic resolved witnesses | Keep. |
| two-launch single resolved | restored generic z-buffer below the 1.05 Metal gate | Keep and monitor finite margin. |
| four-launch legacy resolved | tests/backend fixture only; no independent production consumer or performance advantage | Prove generic equivalence, then remove or retain solely with a documented unmet obligation. |
| four-launch conjunctive | CorePotts semantic parity, Metal upper-95 1.0237674656, 600/600 queued drain | Keep; share primitives only. |

No additional specialization or execution family is admitted without two unrelated concrete
consumers. A specialization may be retained for measured performance with one broad mechanism
consumer only when the generic path demonstrably fails a frozen qualification gate.

## C1 non-regression contract

Every C1 slice must preserve:

- exact public lifecycle and names;
- direct/buffered semantic-family boundary;
- launch counts: direct 1, buffered `1 + has_fast + has_deterministic`, generic single-resolved 2,
  legacy resolved 4 while present, conjunctive 4, sequence exact sum;
- no intermediate wait, asynchronous `run!`, KernelAbstractions implicit ordering and one
  cumulative portable synchronization;
- no plan/run workspace allocation, warm growth, hidden launch, host fallback or vendor branch;
- checked host-Int/Int32 counts and bytes;
- exact array type, element type, rank, shape, strides, backend, device, access and alias checks;
- concrete isbits operations and tuple/named-tuple device specialization;
- canonical `(item, local-slot)` deterministic folds, explicitly unqualified fast floating-point
  order, total rank plus canonical identity resolution, false-lane no-emission and explicit empty
  behavior;
- CorePotts ownership of RNG, Hamiltonian folding, acceptance, clocks, settlement, lifecycle,
  checkpoints and commit semantics;
- lease retention, cumulative drain, poison and post-submit method-substitution behavior;
- exact CPU and Apple-M1/Metal qualification without claims for CUDA or ROCm; and
- the recorded controlled performance gates, with generic z-buffer finite-margin dissent retained.

## C0 reviewer findings

Three independent implementation advisers reviewed the current source from API/scope,
JuliaGPU/provider and numerical/determinism perspectives. They agree on common topology, binding,
workspace, evidence and arbitration seams; retaining direct, buffered, two-launch single-resolved
and conjunctive mechanisms; deferring automatic workspace to C2; and requiring executable parity
before deleting the legacy resolved path. Substantive caution is preserved: do not merge generic
record reduction with conjunctive claim semantics, and do not let inspection descriptors become
launch authority.

## C0 ballot

- Baseline preserved and recoverable: **yes**.
- Every current abstraction/specialization classified: **yes**.
- Safe internal seams identified without reopening architecture: **yes**.
- Production consolidation begun during C0: **no**.
- LW-4C1 may begin under the non-regression contract: **yes**.
