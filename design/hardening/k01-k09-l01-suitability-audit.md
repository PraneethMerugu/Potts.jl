# K01 + K09 + L01 LocalWorksets suitability audit

Status: committee-reviewed design decision; no production migration authorized  
Audit date: 2026-08-15  
Source baseline: `bc5729f3db636c936ad2dfee46c5d1f1ced56059` plus the preserved dirty worktree listed below

## Decision

Do **not** migrate K01, K09, and L01 as one LocalWorksets bundle.

The three rows share superficially similar gated independent writes, but they do
not form one cohesive operation or one useful LocalWorksets preparation:

- K01 contains already-fused checkerboard clears at distinct MCS and color
  positions;
- K09 contains a program-dependent recursive state projection, a genuine
  inter-bank copy, two currently redundant intra-bank self-copies, and a
  separate scan-tail copy; and
- L01 is an already-fused lifecycle reset/control operation with explicit
  caller workgroup selection and a domain-owned due-clock fold.

The accepted disposition is:

| Row | Suitability | Disposition |
|---|---|---|
| K01 MCS clear | Semantically representable, no launch or source-consolidation advantage | Retain direct |
| K01 per-color claim clear | Coupled to the direct K05 claim path | Retain direct; reconsider only with K05 |
| K09 selected state copies | Exact self-copies on supported checkerboard construction/adaptation paths | Prove and remove directly; do not credit LocalWorksets |
| K09 pre-MCS inter-bank copy | Only plausible remaining adoption candidate | Conditional preimplementation hold after direct cleanup and rebaseline |
| K09 scan-tail copy | Separate due-gated scan mechanic | Retain direct |
| L01 reset and policy clear | Compact, fused, lifecycle-owned, explicit-workgroup operation | Retain direct |
| K01 + K09 + L01 bundle | False unification and likely net source growth | Reject |

This decision refines, rather than reopens, the LW-5C stop decisions in
`lw5c-adoption-matrix.md`. Representability alone is not sufficient. Adoption
must make CorePotts smaller and clearer while preserving execution controls,
ordering, qualification, and ownership.

## Audit boundary

This was a source, API, execution, and adoption-ledger audit. It did not modify
production code, add a LocalWorksets mechanism, change lifecycle semantics, or
run a migration qualification suite. The current dirty worktree was preserved.

The committee reviewed these exact current source identities:

| Source | SHA-256 |
|---|---|
| `checkerboard_kernels.jl` | `4c4f48bccc4afd10a292ecdaebc03e0f9260b385a9cd6ad84f4197d552e003f8` |
| `checkerboard_program.jl` | `642d5267a69b20ba01e1feabe0f4f714a206ac84391849a44139ebb597e1f561` |
| `lifecycle_backend_control.jl` | `82f103e41cd234a1638ea1a8a51b8a6e83b25af848716d40c468228b86aea760` |
| `lifecycle_backend_kernels.jl` | `7c5edf73175b3df549ef067dddb595e78356cb3f5f77dea4bba40d87572cf12a` |
| `lifecycle_backend_enqueue.jl` | `dfaf7c764d3a2282840498aadc31a0b5a2ce2d6589b2cbec74467bbfd1ad7770` |
| `localworksets_adapter.jl` | `e109d85b3cc7a843edc529e069707745386daee2b548d38bbc297b4381330153` |
| LocalWorksets `model.jl` | `ea950412a9864bde4018f9b96f18cdc5cbe60fc5243fc4ad517959e8c9ede284` |
| LocalWorksets generic lowering | `b2b78b7e37d80c9d8c2487fc4ce168376d9d82dfa188802af0fd5050f9b828af` |
| LocalWorksets `preparation.jl` | `99dd94cc9e3f1b7b538beea962c933c78fe221ae18b0c7a6f1dfd4111787a019` |

Because the worktree is not clean, these content identities—not HEAD alone—are
the audit boundary. Any later hold must refresh them.

## Current execution map

### K01: checkerboard workspace clears

`_checkerboard_clear_mcs_kernel!` clears cell priorities, cell identities, and
the report under the conjunctive program/lifecycle-open gate. It is called once
before one checkerboard MCS. `_checkerboard_clear_claims_kernel!` clears the two
claim arrays before each direct claim block.

With `A` attempt batches and `C` colors, the K01 launch count is:

```text
1 + A*C
```

Each clear is already one direct KernelAbstractions launch. The MCS clear has
unequal cell and report domains; the color clear is a fixed two-array operation.

### K09: state and scan copies

Let `L` be the number of physical state-array leaves recursively projected from
ownership, cell metadata, tracker values, relationship banks/payloads, and
descriptor banks. A `CellMomentsState` contributes two leaves. Each packed
relationship bank contributes seven fixed arrays plus its payload leaves.

The current active-lifecycle path issues:

```text
pre-MCS source-bank -> destination-bank copy   L
current -> staged selected copy                L
staged -> current selected copy                L
optional scan-tail due copy                    delta
                                                --------
current K09 total                               3L + delta
```

`delta` is one when the final scan source is scratch and zero otherwise.

The pre-MCS copy at `checkerboard_program.jl:1776` is a genuine transfer between
the active and inactive checkerboard banks. The scan-tail copy at
`lifecycle_backend_kernels.jl:557-565` is a separate due-gated array copy.

The other two recursive copies are self-copies on every centrally constructed
checkerboard lifecycle bank:

```text
workspace.staged_ownership        === state.ownership
workspace.staged_cell_kinds       === state.cell_kinds
workspace.staged_cell_generations === state.cell_generations
workspace.staged_trackers         === state.trackers
workspace.staged_relationships    === state.relationships
workspace.staged_descriptor_state === state.descriptor_state
```

`_checkerboard_state_banks` installs that invariant for both banks
(`checkerboard_program.jl:714-763`), and checkerboard adaptation reconstructs
the same invariant. `_lifecycle_workspace_with_staged_state` installs the
complete objects directly (`lifecycle_backend_control.jl:200-239`). Therefore
the selected copies at `lifecycle_backend_enqueue.jl:202-213` and `307-310`
recursively execute `x[i] = x[i]`.

Those launches do not supply a barrier. They are ordinary implicitly ordered
KernelAbstractions launches; after their removal the neighboring planning,
staging, validation, and finalize launches remain ordered. Transactional
visibility is provided by mutation of the inactive checkerboard bank followed
by final bank publication, not by these aliases.

After a proved direct cleanup, useful K09 work becomes:

```text
L + delta
```

The cleanup removes `2L` launches per active-lifecycle MCS without introducing
topology, preparations, leases, events, capability branches, or adapters.

### L01: lifecycle policy clear and reset

L01 consists of:

- zeroing the optional policy workspace in one launch; and
- one fused reset launch over the candidate domain that resets roughly 27
  logical destinations and, in lane one, computes the due flag by folding the
  lifecycle descriptors.

Its launch count is:

```text
1 + I(length(policy_workspace) > 0)
```

The caller's `workgroup_size` is deliberately applied to both launch factories.
The due decision, open gate, counter placement, and reset constants remain
CorePotts lifecycle semantics even if their stores are mechanically described
as independent outputs.

## Why one bundle does not work

### It is not one ordered LocalWorksets sequence

The operations occur at non-contiguous semantic positions:

- once before an MCS;
- once before every direct color/attempt claim block;
- before the destination-bank transaction;
- conditionally after a scan; and
- at multiple points inside lifecycle orchestration.

Public `sequence` composes consecutive work over a compatible item domain and
ordered visibility boundary. Treating these rows as one sequence would require
LocalWorksets to absorb CorePotts transaction and scheduling decisions. It
would also fail on their heterogeneous domains. Internal `Seq`/barrier nodes
must not be exposed or fabricated.

### Per-leaf preparation preserves complexity

One independent output or LocalWork per physical leaf is semantically exact,
but it preserves K09's `L` launches, introduces one or more preparations and
event/lease ledgers, and leaves recursive schema projection in CorePotts. It
deletes only thin direct kernel wrappers and is net-positive source.

### One maximum-domain work is an expensive fiction

A single mega-work over the largest domain would need a prefix-identity route
for every shorter output. LocalWorksets currently provides a zero-transfer
identity route only when destination count equals item count. Explicit padded
routes add topology storage and transfers, and a maximum-domain kernel performs
inflated `items x ports` work. Adding a new prefix-route API solely for this
migration violates the two-unrelated-consumer rule.

### Capacity grouping is plausible only for K09

The strongest bounded design for the remaining pre-MCS K09 copy is:

1. flatten genuine inter-bank physical leaves;
2. partition them by exact item count/axes;
3. construct one independent heterogeneous work per group;
4. bind corresponding source reads and destination outputs;
5. use the shared lifecycle-open mask and allocation-free identity routes; and
6. retain CorePotts bank selection and transaction placement.

If `g` is the number of exact capacity groups, this changes pre-MCS launches
from `L` to `g`, with a possible saving of `L - g` where `1 <= g <= L`.

It still requires stable port naming, recursive schema projection, preparation
and inspection, both bank directions or submission-time storage binding,
complete event/lease aggregation, adaptation/repreparation, capability and
checkpoint identity, and qualification of schema-sized generated kernels.
It is therefore a conditional experiment, not a presumptively good migration.

## API and execution mismatches

### Explicit workgroup selection

L01 preserves a caller-specified workgroup size. The current LocalWorksets
direct-independent public lifecycle does not expose an equivalent per-call
control. Silently dropping it is not parity. Adding it solely for L01 would
reopen the API and needs unrelated consumers and a separate review.

### Zero-size execution

Current direct callers can skip optional empty work. LocalWorksets direct
execution uses a nonzero launch domain for prepared work. Any probe must prove
empty policy, empty leaf, and zero-item behavior rather than inherit parity.

### Implicit ordering and settlement

Sequential kernels must continue relying on KernelAbstractions 0.9 implicit
ordering. LocalWorksets must not introduce intermediate host waits, queues,
streams, command buffers, transferable events, or a scheduler.

If multiple `PreparedWork` values participate in one MCS, CorePotts must:

- preflight every required lease before submitting any prefix;
- retain the cumulative event from every preparation;
- issue exactly one same-scope final `waitall`/portable synchronization;
- release the complete submitted tail; and
- report poison/failure at the portable synchronization boundary.

The present checkerboard settlement profiles do not provide an arbitrary
schema-sized maintenance-work registry. Adding one would be material
orchestration, not a free use of existing machinery.

### Alias validation

LocalWorksets correctly rejects logically distinct read/write bindings that
alias in unsupported ways. It must not be weakened to encode K09's two useless
self-copies. The direct CorePotts invariant should instead make the redundancy
explicit and remove it.

## Source and complexity ledger

The gross K01/K09/L01 definition footprint is approximately 374 raw / 361
executable lines. The separate lifecycle-enqueue tuple/call/debug cleanup adds
16 raw / 16 executable call-site lines, for approximately 390 raw / 377
executable lines across the complete audited surface. The broad raw count
includes one separator line, so the row estimates below sum to 389 rather than
390:

| Area | Gross footprint | Honest migration credit |
|---|---:|---|
| K01 definitions/wrappers | about 54 / 53 | Small; gate and reset values remain as operation logic |
| K09 array kernel/wrapper | 31 / 30 | Remains live for scan-tail copy unless separately replaced |
| K09 recursive tuple/storage/state/program machinery | 211 / 201 | Maximum standalone K09 deletion ceiling |
| K09 redundant selected-copy tuple/calls/debug markers | 16 / 16 | Direct cleanup only; never LocalWorksets credit |
| L01 definitions/launch construction | about 77 / 77 | Small; fused reset/due operation remains |

The gross total is misleading. A credible bundle still needs the scientific
operation bodies, lifecycle gates, phase calls, bank choice, due-clock fold,
and nested state schema. The committee estimated roughly 360-690 new
production lines for operation descriptors, schema/binding derivation,
preparations, event settlement, capability/checkpoint/adaptation, and
inspection before tests. No reviewed design reverses that ledger.

The historical K01 B0 probe reinforces this conclusion: it proved
representability and KernelAbstractions ordering, but its adapter exceeded the
direct value, retained one launch, incurred positive warm host allocation, and
added Metal compilation specializations. A new plan must not equate
representability with consolidation.

## Capability and qualification consequences

The promoted K02/K03 selector currently excludes active lifecycle execution.
L01 and scan-tail K09 are active-lifecycle work, but the remaining pre-MCS K09
copy exists for no-, inert-, and active-lifecycle checkerboard profiles. Under
`NoLifecycleWorkspace`, its lifecycle-open gate is unconditionally open. Any
K09 candidate therefore needs a distinct orthogonal execution identity in all
cases because it changes an additional launch, binding, and lifetime path;
active-lifecycle applicability is an additional separately qualified row and
cannot inherit K02/K03 evidence.

Any later K09 candidate needs a distinct capability/checkpoint identity that
includes, at minimum:

- exact child manifest and port schema;
- source/destination bank binding mode;
- lifecycle applicability and open-gate semantics;
- exact LocalWorksets lowering/provider/compiler identity;
- backend, element types, operations, address spaces, and qualification rows;
- required lease capacity and completion discipline; and
- composition with the selected claim/proposal execution profiles.

Source portability is not qualification. Current admission may remain
fail-closed for the exact reviewed CPU and Apple M1/Metal environments. CUDA or
ROCm support cannot be inferred from vendor-neutral source.

## Required direct K09 cleanup gate

Before any LocalWorksets K09 hold, perform a separate CorePotts cleanup with the
following evidence:

| Requirement | Required proof |
|---|---|
| Construction invariant | Recursive `===` for all six staged/science fields on both banks |
| Bank separation | Primary and secondary science leaves remain physically distinct |
| Adaptation | Repeat the invariant after supported CPU-to-Metal adaptation |
| Rich schemas | Tracker, `CellMomentsState`, descriptor banks, relationship fixed fields and payloads |
| Lifecycle branches | due false, due true/selected zero, selected nonzero, every sticky failure class |
| Transactions | success, validation failure, abort, receipt, continuation and checkpoint/replay parity |
| Ordering | No new wait; neighboring KA launches remain implicitly ordered |
| Launch evidence | Exactly `2L` launches removed for each active-lifecycle MCS |
| Performance | Updated CPU/real-Metal launch, allocation, queued-MCS and throughput baselines |
| Construction scope | Reject unsupported nonconforming private alternate-state construction or prove it |
| Identity | Reseal execution/capability evidence because the direct launch trace changes |

Only the unused `staged_state` tuple, the two selected copy calls, and their now
obsolete debug markers are in this cleanup. The shared gated-copy kernel and
recursion remain live until a separate K09 adoption proves it can replace the
genuine inter-bank path.

## Conditional K09 preimplementation hold

After direct cleanup and a fresh baseline, a disposable grouped-copy probe may
open only if a design ledger answers all of these before production coding:

1. What are `L` and `g` for minimal, tracker-heavy, relationship-heavy, and
   descriptor-heavy programs?
2. Can stable named output/read tuples be derived without a new generated schema
   framework or per-program handwritten adapters?
3. Can the route representation remain zero-transfer and use only accepted
   LocalWorksets mechanisms?
4. How many preparations, events, leases, and specializations are introduced?
5. Can twelve queued MCSs preflight and settle with one final synchronization,
   no stranded leases, and no warm growth?
6. Do first- and second-warm CPU and real-Metal compilation, allocation, launch,
   and throughput results improve materially?
7. Can the final production patch delete the 211 raw / 201 executable lines of
   state-specific recursive machinery and remain materially below that ceiling
   after capability, adaptation, inspection, and settlement are included?
8. Can the scan-tail array copy remain direct without pretending that the whole
   gated-copy family was deleted?

Kill the probe immediately if it:

- adds a new execution family or a CorePotts-specific LocalWorksets API;
- weakens alias, backend, admission, determinism, or evidence rules;
- retains the old recursive production path beside the new path;
- needs dense padded route matrices or a new prefix route with no unrelated
  consumer;
- adds more source than it can honestly delete;
- increases launches, physical synchronizations, topology transfers, or steady
  workspace materially; or
- fails schema-rich real-Metal compilation or noninferiority.

Even if this hold passes, production K09 adoption requires a fresh review. It
does not authorize K01 or L01 migration.

## Committee process and ballots

Three reviewers independently audited the exact candidate before seeing the
chair synthesis:

1. Julia/API and consolidation reviewer;
2. JuliaGPU execution, compilation, allocation, and ordering reviewer; and
3. CorePotts lifecycle semantics, determinism, capability, and checkpoint
   reviewer.

The independent round agreed that the combined bundle was likely net-positive
source and that L01's workgroup/control semantics were not preserved. During
the contradiction round, all three reviewers independently confirmed the K09
self-copy invariant and challenged whether any bundle design had been missed.
No reviewer found a credible net-negative three-row design under the accepted
LocalWorksets API.

| Question | API reviewer | GPU reviewer | Semantics reviewer | Final ballot |
|---|---|---|---|---|
| Is K01 representable? | Yes | Yes | Yes | Yes |
| Should K01 migrate now? | No | No | No | Retain direct |
| Are the two selected K09 copies redundant on supported construction paths? | Yes | Yes | Yes | Direct proof/cleanup first |
| Should remaining K09 enter production now? | No | No | No | No |
| May a post-cleanup grouped K09 probe be considered? | Conditional | Conditional | Deferred/conditional | Conditional hold only |
| Should L01 migrate? | No | No | No | Retain direct |
| Should the combined bundle proceed? | Reject | Reject | Reject | **Reject** |

Substantive dissent is preserved in the wording of the K09 result: the GPU
reviewer considered a capacity-grouped disposable probe technically promising;
the semantics reviewer required an additional design-only hold before even that
probe. The chair adopts the stricter intersection: direct cleanup and rebaseline
first, then a preimplementation ledger; executable probing is conditional on
that ledger.

The committee then reviewed this exact written artifact. The API reviewer
required separation of the 374/361 definition footprint from the additional
16/16 direct cleanup surface. The semantics reviewer required correction of the
pre-MCS K09 scope across no-, inert-, and active-lifecycle profiles. Both
corrections are incorporated above. The API, GPU, and semantics reviewers each
signed off with no remaining P0 or P1 finding.

## Final authorization

This audit authorizes no migration. It authorizes proposing a bounded direct
K09 self-copy cleanup gate. K01 and L01 remain direct. The remaining pre-MCS
K09 copy remains a conditional research item and must not begin until the
cleanup baseline is frozen and the entry ledger above passes review.
