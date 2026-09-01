# LW-5A representability and preservation inventory

Status: preserved as superseded preservation-oriented evidence; completion
withdrawn by the bounded adoption-and-consolidation amendment; no production
migration authorized

Date: 2026-08-13

Baseline review commit: `bc5729f3db636c936ad2dfee46c5d1f1ced56059`

Baseline review tree: `b30a56cc84395225d292a2eca175c8f4e15e99d9`

Qualified source product: `8b710692a84f79b1411a1443a27a9ee099327bcf`

Qualified source tree: `b360f2b06b404b34d448c75f3bdd5b012d839dc7`

Authority:

- [post-LW-R1 extraction and adoption roadmap](../../spec/localworksets-post-lwr1-roadmap.md);
- [LocalWorksets V1 contract](../../spec/localworksets-v1.md);
- [LW-4C final qualification](lw4c-final-qualification-evidence.md);
- [IC-R0 internal-complexity review](icr0-internal-complexity-review.md); and
- [LW-0 direct CorePotts baseline](lw0-corrected-corepotts-baseline.md).

## Supersession notice

This inventory remains the exact preservation-oriented evidence produced from
baseline `bc5729f3`. Its semantic-stage census, hashes and preservation oracles
remain useful, but its completion ruling is withdrawn. It did not require
every eligible family to identify the bespoke execution machinery that a
LocalWorksets adoption would replace, the expected deletion/demotion, the
derivation path, or a second-use consolidation test.

The authoritative redo is the
[LW-5A adoption-and-consolidation amendment](lw5a-adoption-consolidation-amendment.md).
That amendment and its
[focused review](lw5a-adoption-consolidation-review.md) have cleared. This
record remains superseded; only B0 is now open under the amended authority.

## Historical decision (withdrawn)

LW-5A passes as an inventory and preservation gate only. It authorizes no
production execution change, no Potts authoring change, no LocalWorksets
mechanism or public-API change, and no promotion of the existing checkerboard
candidate.

The inventory selects two bounded next artifacts:

1. **LW-5B0, integration plumbing probe:** the checkerboard claim-workspace clear
   is expressed as a two-port, partial-coverage independent LocalWork. B0 is a
   one-launch control for compiler-adapter construction, topology derivation,
   storage binding, capability composition and inspection. It is not by
   itself evidence that LocalWorksets improves CorePotts.
2. **Pilot, evidence-bearing adoption vertical:** the existing fused checkerboard
   proposal-evaluation launch is expressed as a CorePotts-owned concrete local
   operation with independent contribution and disposition outputs. The
   canonical Hamiltonian fold, proposal views, RNG addressing and acceptance
   law remain inside the CorePotts callable. LocalWorksets may validate and
   execute that callable but may not reinterpret those semantics. The pilot must
   replace one launch with one launch and add no intermediate wait.

B0 must pass before pilot implementation. The pilot, not B0, decides whether
later families may migrate. A correct pilot that fails the downstream-value
test is a rejection, not permission to continue.

All other execution families are inventoried below but remain `defer`,
`retain`, or `reject`. Each deferred family requires its own pre-migration
preservation hold after the pilot passes. Classification is not migration authority.

## Meaning of the classifications

| Classification | Exact meaning in this inventory |
| --- | --- |
| `direct` | The frozen public LocalWorksets API can express the complete execution mechanism without a new execution family. Domain semantics may still reside in a concrete caller operation. |
| `independent` | Expressible through fixed, validated independent output routes, possibly with partial coverage and heterogeneous ports. |
| `combined` | Requires an explicitly deterministic or explicitly fast admitted combination law. Bare floating `+` is never sufficient. |
| `heterogeneous` | One operation requires named output ports with different value types, arities or output meanings. |
| `multi-destination` | Requires bounded emission to multiple destinations or a conjunctive/resolved claim. Dynamic destinations are not presumed to be frozen topology routes. |
| `orchestration` | CorePotts owns ordering, clocks, phase choice, transaction cuts, failure propagation or publication. LocalWorksets may execute a bounded child mechanism but cannot own this row. |
| `not appropriate` | The work is compiler validation, host synchronization, global transaction authority, or another responsibility outside LocalWorksets. |

`direct`, `independent`, `combined`, `heterogeneous` and
`multi-destination` describe representability. `orchestration` and
`not appropriate` are ownership vetoes. A row can therefore say, for example,
"independent child; orchestration retained."

## Global preservation boundary

Every selected or later-admitted family must preserve all of the following:

- public PottsToolkit authoring, including `HamiltonianTerm`, `Volume`,
  `ContactEnergy`, `Elongation` and registered external Hamiltonians;
- `complete` and `mtkcompile` proof of operation purity, context domains,
  resource access and bounded affected anchors;
- exact descriptor identity, source handle, source order, footprint and
  scientific fingerprint;
- CorePotts-owned before/after proposal views and canonical source-order
  Hamiltonian folding;
- CorePotts-owned MCS and lifecycle schedules, RNG stream/address identity,
  Metropolis acceptance, counters and failure meanings;
- CorePotts-owned tracker meaning, lifecycle generations and slot reuse,
  relationship identity, atomic commit, inactive-bank publication and
  settlement;
- direct/candidate capability and checkpoint mechanism identity, exact
  continuation, and cross-mechanism mismatch rejection;
- KernelAbstractions implicit ordering, queueable MCSs, immutable scalar color
  launch arguments, no intermediate host wait and exactly one settlement
  synchronization at the existing boundary; and
- the deferred MethodOfLines input-field integration exactly as currently
  documented.

LocalWorksets is inserted beneath compiled descriptor evaluation. Hamiltonian
and model authors do not write `LocalWork`, topology, storage, workspace or
submission declarations.

## Complete semantic-stage inventory

The access column records the bounded mechanism, not every field of the
owning runtime object. `Fixed` means derivable from a compiled topology;
`dynamic` means a destination or footprint depends on scientific state and
must not be smuggled into a frozen route.

Source authority is grouped as follows: C00 is owned by
`static_evaluator.jl` and `descriptor_plan.jl`; C01-C08 by
`sequential_program.jl`, `stage_runtime.jl`, `proposal_context.jl` and the
relationship transaction files; K01-K12 by `checkerboard_kernels.jl`,
`checkerboard_program.jl`, `lifecycle_backend_control.jl` and
`program_settlement.jl`; L01-L12 by `lifecycle_backend_kernels.jl`,
`lifecycle_backend_enqueue.jl` and the CPU lifecycle planning/commit files;
T01-T02 by the tracker plan state/runtime files; and R01 by
`host_relationship_transaction.jl`. The symbol and kernel census below makes
the device portion independently checkable.

| ID | Current stage and authority | Items, reads, writes and conflict/visibility | Classification | Disposition and reason |
| --- | --- | --- | --- | --- |
| C00 | Static evaluator, descriptor and descriptor-group device probes | One probe item; compiled evaluator/descriptor reads; one probe output; no scientific publication | not appropriate | **Retain.** These are compiler/admission tests, not runtime work and not an adoption target. |
| C01 | Sequential proposal recipient/direction selection in `_advance_sequential!` and `_attempt!` | Serial attempt domain; addressed RNG; ownership and proposal-neighbor reads; chooses a dynamic source/target pair | orchestration | **Retain.** Serial order and RNG scheduling are CorePotts algorithm semantics. |
| C02 | Sequential proposal evaluation, canonical fold and acceptance in `_attempt_selected!` | One chosen proposal; descriptor/tracker/relationship/state reads; contribution scratch, counters and disposition; no competing item because execution is serial | direct child; orchestration | **Retain for the pilot oracle.** The local scientific callable is reusable, but the serial attempt loop and transaction stay CorePotts-owned. |
| C03 | Sequential accepted-copy emission, tracker/ownership commit and relationship publication | One accepted proposal; dynamic old/new owners and relationship endpoints; atomic scientific commit visibility | multi-destination; orchestration | **Defer.** Dynamic destinations and transaction atomicity cannot be approximated as fixed independent routes. |
| C04 | After-MCS site and model assignment | Fixed lattice or one model item; declared state reads; scratch then independent target publication | independent; heterogeneous | **Defer.** Conceptually eligible, but the current direct path is CPU host execution and supplies no qualified real-Metal parity oracle. |
| C05 | Iterated site assignment and shift/append effects | Fixed lattice/depth; repeated read-after-write visibility or overlapping shift order | orchestration | **Defer.** A bounded sequence may be possible, but the iteration and visibility law require a separate hold and direct CPU/Metal evidence. |
| C06 | After-MCS relationship remove/retune emission and publication | Active edge domain; relationship/context reads; bounded dynamic transaction records; keyed conflict and atomic publication | multi-destination; orchestration | **Defer.** Relationship transaction law remains CorePotts; no new dynamic-key mechanism is admitted in LW-5A. |
| C07 | Sequential lifecycle execution | Bounded requests but multi-phase planning, selection, validation and atomic publication | orchestration | **Retain.** Individual mechanics are inventoried as L01-L12; the transaction is never one LocalWork or LocalWorksets sequence. |
| C08 | Sequential/checkerboard program-step staging, rollback, commit and snapshot publication | Whole scientific banks, parameters, counters and receipts; transaction cut controls visibility | not appropriate | **Retain.** This is CorePotts transaction and checkpoint authority. |
| K01 | Checkerboard MCS/claim workspace clear | Fixed cell/report destinations; program-open gate read; zero/identity writes; false gate preserves output | independent, heterogeneous | **Select B0 only.** Two partial-coverage fixed-route ports, one launch, zero algorithmic workspace. B0 does not authorize broader migration. |
| K02 | Checkerboard candidate generation | One item per active color site; fixed color topology plus ownership/RNG reads; unique proposal arrays | independent, heterogeneous | **Defer.** Expressible by a CorePotts callable, but proposal scheduling and RNG isolation remain CorePotts and the pilot must first prove the adapter. |
| K03 | Checkerboard descriptor/Hamiltonian evaluation and acceptance disposition | One proposal item; proposal arrays plus read-only compiled state; unique contribution column and disposition; pending mask gives partial coverage | independent, heterogeneous | **Select as the pilot.** One CorePotts callable and one LocalWorksets launch must replace exactly the existing one fused launch. |
| K04 | Checkerboard acceptance-status reduction | Active proposal dispositions/semantic identities; one sticky scientific status chosen in canonical semantic order | resolved child; orchestration | **Retain during the pilot.** It is the direct scientific-failure boundary and must not be folded into LocalWorksets evidence or poison semantics. |
| K05 | Checkerboard old-owner/new-owner claim arbitration | Accepted proposals emit the same total rank and canonical identity to up to two dynamic positive owner keys; winner must satisfy both keys | multi-destination resolved | **Already represented; retain candidate and direct oracle.** The qualified four-launch conjunctive LocalWorksets candidate is evidence, not a new LW-5 migration. |
| K06 | CPU accepted-copy preparation and publication | Accepted proposal domain; stage evaluations plus relationship requests; dynamic target/endpoint effects; publication after selection | heterogeneous, multi-destination; orchestration | **Defer.** Split site staging from relationship transactions in any later inventory; never migrate this as one family. |
| K07 | Checkerboard ownership/tracker commit | Selected proposal targets are unique; old/new owner tracker destinations are dynamic and protected by the prior conjunction | multi-destination; orchestration | **Defer.** Claim exclusivity is a CorePotts precondition and scientific commit remains indivisible. |
| K08 | Checkerboard report/counter accumulation | Active proposal dispositions; integer counter contributions; one per-MCS report | combined; orchestration | **Defer.** Exact integer combination is plausible, but counters and failure publication stay CorePotts and the row is not needed by the pilot. |
| K09 | Program-state and lifecycle gated bulk copies | Fixed bank arrays and tuple leaves; gate read; independent destination elements; program order supplies visibility | independent, heterogeneous; orchestration | **Defer after B0.** Reusable mechanism, but bank selection and copy placement remain CorePotts. |
| K10 | Checkerboard color/attempt loop | Preallocated randomized color order; immutable scalar color per launch; ordered candidate/evaluate/status/claim/commit/report phases | orchestration | **Retain.** LocalWorksets must not become the checkerboard scheduler. The pilot substitutes one child launch only. |
| K11 | Program-bank publication | One control item; sticky report/status and selected bank; committed-MCS visibility | not appropriate | **Retain.** This is the atomic CorePotts publication cut. |
| K12 | Program settlement and materialization | One host boundary; backend-tail synchronization, status/counter transfer, optional complete snapshot and lifecycle receipt | not appropriate | **Retain.** LocalWorksets cannot invent a scheduler, transferable event or second settlement path. |
| L01 | Lifecycle policy clear, reset and due gate | Fixed workspace/candidate arrays; lifecycle plan/clock reads; independent reset writes | independent child; orchestration | **Defer.** The clock and due decision remain CorePotts; not part of B0. |
| L02 | Lifecycle site-key construction, bounded sort, status reduction and cell indexing | Lattice/cell fixed capacities; ownership reads; key/offset workspace; staged scan/sort visibility | combined/ordered child; orchestration | **Defer.** Current scan/sort are bounded CorePotts device algorithms. A generic family needs two unrelated consumers. |
| L03 | Lifecycle request emission | Bounded source/anchor occurrences; compiled lifecycle evaluator reads; fixed-capacity request records and status | multi-destination buffered | **Defer as the first lifecycle candidate.** Requires a later pre-migration hold after the pilot and preserves clocks, generations, identities and request meaning in CorePotts. |
| L04 | Request marking, scan, compaction and canonical sort | Fixed request capacity; active flags and keys; compacted canonical request order | combined/ordered child; orchestration | **Defer.** These are support algorithms for CorePotts request ordering, not a new LocalWorksets family in LW-5A. |
| L05 | Create/retire/remove/transition planning and planning-status reduction | Canonically sorted request domain; state/capacity reads; planned effects and sticky status | orchestration | **Retain.** Planning choices are lifecycle semantics, not publication policy. |
| L06 | Division planning, relationship validation, selected replan and policy workspace | Selected division requests; topology/geometry/RNG/policy state; bounded daughter/site plans | orchestration | **Retain.** Partition, side, generation, capacity and relationship laws remain CorePotts. |
| L07 | Lifecycle deduplication and conflict selection | Bounded requests with dynamic structure/state/relationship footprints; total canonical request key; selected mask | multi-destination resolved; orchestration | **Defer.** Generic conflict mechanics may eventually lower, but CorePotts validates footprints and owns atomic selection meaning. |
| L08 | Lifecycle structural staging | Selected request domain; generation/kind/slot reads; staged cell structure writes | multi-destination; orchestration | **Retain.** Slot reuse and generation changes are transaction semantics. |
| L09 | Lifecycle relationship staging | Selected requests; dynamic relationship footprints; staged relationship writes | multi-destination; orchestration | **Retain.** Relationship integrity and transaction law remain CorePotts. |
| L10 | Lifecycle descriptor/tracker state staging | Selected requests; action-specific state and tracker reads; staged heterogeneous state outputs | heterogeneous, multi-destination; orchestration | **Retain.** State-action meaning and conservative split rules remain CorePotts. |
| L11 | Effect finalization and complete staged-state validation | Selected requests and staged banks; retirement counters/status; invariant checks | orchestration | **Retain.** Validation evidence cannot be replaced by LocalWorksets execution success. |
| L12 | Failure stamping, gated publication and lifecycle finalization | Sticky status, staged/current banks and control counters; all-or-nothing visibility | not appropriate | **Retain.** This is the CorePotts transaction cut and failure boundary. |
| T01 | Tracker initialization, rebuild and checkpoint reconstruction | Lattice/relationship domains; ownership or relationship reads; per-owner values; possible dynamic owner grouping | combined child; orchestration | **Defer.** Frozen LocalWorksets routes do not by themselves express ownership-dependent destinations; reconstruction and checkpoint policy remain CorePotts. |
| T02 | Proposal tracker before/after views and commit deltas | One proposal; dynamic old/new owners; exact descriptor-specific delta; visibility at accepted commit | multi-destination; orchestration | **Retain through the pilot.** These reads are part of the pilot callable, but publication remains in K07. |
| R01 | Host relationship transaction | Settled host request groups; complete validation and runtime reconstruction; no device local domain | not appropriate | **Retain.** Host mutation is explicitly outside LocalWorksets. |

### Inventory conclusions

1. Existing LocalWorksets mechanisms are sufficient to attempt B0 and the pilot.
   LW-5A admits no new output family, execution family, dynamic-route protocol
   or backend qualification.
2. Dynamic owner, relationship and lifecycle destinations are not silently
   reclassified as frozen topology. Tracker commit, accepted-copy effects and
   lifecycle conflict work therefore remain deferred.
3. `sequence` may describe ordered admitted child work, but it cannot absorb
   checkerboard, lifecycle, settlement or scientific transaction
   orchestration.
4. The entire lifecycle backend is not a LocalWorksets candidate. L03 and L07
   are the only later bounded mechanism candidates selected for future
   reconsideration; all transaction cuts remain CorePotts.
5. CPU-only after-MCS execution is not sufficient for adoption qualification.
   It remains inventoried but cannot be selected until a direct qualified
   Metal oracle exists or the authoritative backend requirement is amended.

## Kernel census and row coverage

The baseline contains 41 `@kernel` declarations under `lib/CorePotts/src`.
Every declaration maps to exactly one semantic row above:

| Inventory row | Kernel declarations |
| --- | --- |
| C00 | `evaluator_probe_kernel!`, `descriptor_probe_kernel!`, `descriptor_group_probe_kernel!` |
| C08 | `_rollback_checkerboard_program_step_kernel!` |
| K01 | `_checkerboard_clear_mcs_kernel!`, `_checkerboard_clear_claims_kernel!` |
| K02 | `_checkerboard_candidates_kernel!` |
| K03 | `_checkerboard_evaluate_kernel!` |
| K04 | `_checkerboard_acceptance_status_kernel!` |
| K05 | `_checkerboard_claim_priorities_kernel!`, `_checkerboard_claim_identities_kernel!`, `_checkerboard_select_kernel!` |
| K07 | `_checkerboard_commit_kernel!` |
| K08 | `_checkerboard_report_kernel!` |
| K09 | `_lifecycle_gated_copy_kernel!` |
| K11 | `_publish_program_bank_kernel!` |
| L01 | `_reset_lifecycle_backend_kernel!`, `_clear_lifecycle_policy_workspace_kernel!` |
| L02 | `_lifecycle_site_key_kernel!`, `_lifecycle_sort_step_kernel!`, `_reduce_lifecycle_status_kernel!`, `_index_lifecycle_sites_kernel!` |
| L03 | `_emit_lifecycle_backend_kernel!` |
| L04 | `_mark_lifecycle_requests_kernel!`, `_lifecycle_scan_step_kernel!`, `_compact_lifecycle_requests_kernel!`, `_sort_lifecycle_backend_kernel!` |
| L05 | `_plan_lifecycle_effect_backend_kernel!`, `_reduce_lifecycle_planning_status_kernel!` |
| L06 | `_plan_lifecycle_division_backend_kernel!`, `_validate_lifecycle_division_relationships_backend_kernel!`, `_clear_selected_division_workspace_backend_kernel!`, `_replan_selected_lifecycle_division_backend_kernel!` |
| L07 | `_select_lifecycle_backend_kernel!` |
| L08 | `_stage_lifecycle_structure_backend_kernel!` |
| L09 | `_stage_lifecycle_relationships_backend_kernel!` |
| L10 | `_stage_lifecycle_state_backend_kernel!` |
| L11 | `_finalize_lifecycle_effect_backend_kernel!`, `_validate_lifecycle_backend_kernel!`, `_finalize_lifecycle_backend_kernel!` |
| L12 | `_stamp_lifecycle_failure_kernel!` |

The census covers device kernels, but the semantic inventory also covers the
host sequential loop, accepted/after-MCS stages, trackers, relationship
transactions, enqueue orchestration, settlement and checkpoints. Kernel count
alone is not the definition of an execution stage.

## LW-5B0 frozen contract — independent clear integration probe

### Declaration target

- Items: `1:destination_count`, where `destination_count` is the compiled
  cell-capacity claim workspace length.
- Reads: one CorePotts-owned program-open gate.
- Outputs:
  - `maximums`: partial-coverage independent `UInt32`, identity route, value
    `UInt32(0)`;
  - `identities`: partial-coverage independent `UInt32`, identity route, value
    `typemax(UInt32)`.
- False gate: no emission; existing values are preserved.
- Topology epoch: derived from the compiled checkerboard plan and claim
  workspace capacity, not chosen by a model author.
- Workspace: no algorithmic array; prebound LocalWorksets lease storage only.
- Launch: exactly one, replacing one direct clear launch in isolated evidence.
- Visibility: KernelAbstractions program order; no wait before the following
  claim launch.

### B0 pass and veto

B0 passes only if the CorePotts adapter derives the declaration, topology,
bindings and inspection without hand-written per-model code; CPU and qualified
Metal results match the direct clear; warm execution allocates no algorithmic
workspace; and no new wait or vendor branch appears.

B0 is rejected if it requires a new LocalWorksets mechanism, a CorePotts
private reach from LocalWorksets, an opaque host callback, a second settlement
path, or more than one execution launch. B0 success does not open later
families; it opens pilot implementation only.

## Evidence-pilot frozen contract — proposal evaluation vertical

### Current direct execution unit

The oracle is the one `_checkerboard_evaluate_kernel!` launch per color in
`_execute_checkerboard_mcs!`. It executes before acceptance-status reduction,
conjunctive owner arbitration, accepted-copy preparation, commit and report.
Those surrounding stages remain byte-for-byte on the direct path during the
isolated pilot comparison.

### Local declaration target

- Items: the compiled maximum checkerboard color size with a submission-bound
  `Int32` active count.
- Submission scalars: immutable `color::Int32` and active count; the current
  state bank is bound through validated storage rather than captured by an
  opaque host closure.
- Reads: target/source sites, old/new owners, semantic identities, prior
  dispositions, ownership, cell kinds/generations, trackers, relationships,
  descriptor state, parameters and the already-qualified compiled descriptor
  plan/resources needed by `_ProposalEvaluationContext`.
- Outputs:
  - one partial-coverage independent contribution column per proposal, with
    the compiled source count as the bounded lane count;
  - one partial-coverage independent disposition per proposal.
- Routes: fixed unique column/item routes derived from the checkerboard
  workspace layout. No dynamic owner destination enters this work.
- Operation: one concrete, isbits, GPU-compilable CorePotts callable derived
  from qualified descriptor IR. It constructs the existing proposal view,
  evaluates the existing descriptor groups, writes contributions in canonical
  source order, folds using the existing `OrderedFold`, applies the existing
  acceptance law and uses the existing addressed RNG function.
- LocalWorksets responsibility: validate topology/bindings/aliases/capability,
  prepare bounded workspace/lifetime, launch the caller operation, publish its
  independent outputs and expose inspection.
- CorePotts responsibility: operation meaning, proposal views, descriptor
  identity/order, Hamiltonian fold, RNG, acceptance, status translation,
  claims, commit, counters, MCS scheduling, banks, settlement and checkpoint
  identity.

The callable may execute CorePotts scientific functions. That does not make
LocalWorksets their owner. Conversely, moving `OrderedFold`, RNG addressing or
acceptance into a LocalWorksets output law is forbidden.

### Pilot isolation and launch rule

The direct and pilot candidates use the same candidate-generation, status,
direct-claim, commit, report, lifecycle and settlement implementations. Only
the evaluation launch differs. A later composition with the already-qualified
LocalWorksets claim candidate requires a separate post-pilot parity row and
mechanism identity.

The pilot must preserve the direct `1 + 9C` MCS launch formula by replacing
exactly one of the nine per-color launches one-for-one. It may not add a
preparation launch per MCS, an intermediate host wait, a host fallback, a
device allocation or a dynamic-dispatch escape.

### Pilot value test

Correctness is necessary but insufficient. Before later migration, the pilot
review must report:

- custom kernel and launch-orchestration code removed or made reference-only;
- shared compiler-adapter code added;
- pilot-specific declaration, topology, binding and inspection code added;
- number of manual logical bindings and whether each follows mechanically
  from compiled `ResourceAccess`/domain metadata;
- specialized operation/plan types before warm-up and after warm-up;
- preparation and warm-run allocations;
- launch, wait, transfer, workspace and throughput deltas; and
- whether a second qualified descriptor shape uses the same adapter without
  new family-specific machinery.

There is no arbitrary line-count target. The pilot fails the value test if it
merely replaces one small kernel wrapper with a large hand-written adapter,
repeats topology/storage/workspace assembly for the operation, requires model
authors to know LocalWorksets, or leaves two equally authoritative production
paths with no promotion/retirement disposition.

## Frozen preservation oracles

The selected B0 and pilot rows inherit the exact qualified source product and
the following current oracles. Hashes freeze the pre-migration artifacts; a
later change to one of them requires an explicit re-freeze rather than silent
inheritance.

### Source and execution oracles

| Artifact | Baseline SHA-256 | Preserved fact |
| --- | --- | --- |
| `checkerboard_kernels.jl` | `4c4f48bccc4afd10a292ecdaebc03e0f9260b385a9cd6ad84f4197d552e003f8` | B0 direct clear and pilot fused evaluation kernels; exact output/failure behavior |
| `checkerboard_program.jl` | `21f6863aae720069467c2889088e5ea21a6ca06d8dd5e32c951c772d78a5edd4` | color/launch order, claims, commit, report, immutable scalar color and existing candidate boundary |
| `sequential_program.jl` | `0fc81f39755fc7988e5e95e0c82a6de003f24a4e468db4025afdbb4f16800226` | direct scientific transaction, queue and checkpoint publication authority |
| `stage_runtime.jl` | `b25db93ff94c044c1f2b7059123f1dfce9d0b3412fe75887669678dc613ee330` | accepted/after-MCS effect and relationship transaction semantics |
| `tracker_plan_runtime.jl` | `f02388de4d271ddfa96faccfc413d0c789c8427234c4fb11a7cb2c5bd75ff517` | before/after tracker views and accepted-copy deltas |
| `proposal_context.jl` | `97aa6f574c713977f6d30d782db4af28b7a38eaabf19db2a97f71b06cefdccf0` | proposal view and CorePotts commit authority |
| `program_settlement.jl` | `2910af15dfe5999341d9653e37415225b13b42c913bb480637e0dc19f918f606` | sole wait/transfer/publication boundary |
| `lifecycle_backend_enqueue.jl` | `dfaf7c764d3a2282840498aadc31a0b5a2ce2d6589b2cbec74467bbfd1ad7770` | ordered lifecycle orchestration remains outside LocalWorksets |
| `lifecycle_backend_kernels.jl` | `7c5edf73175b3df549ef067dddb595e78356cb3f5f77dea4bba40d87572cf12a` | direct bounded lifecycle mechanics and status behavior |
| `lifecycle_execution.jl` | `a88fb250de05828ab9ee0950114131aac0b89a684118b3e5e472e07a8630fd5b` | CPU lifecycle phase/transaction oracle |

### Test and hardware oracles

| Oracle | Baseline SHA-256 | Required preservation |
| --- | --- | --- |
| `test_program_v1_execution.jl` | `c1c43c9edd84c6b5b4d508d04480b797e2d7d823b435815d85ded6232bc75583` | unbiased color order, direct transaction publication, rollback and bank isolation |
| `test_program_v1_localworksets_vertical.jl` | `3f865074e64a1291c453f18cf60b7199ab672eaa4687147d7d6a63225d6dbec0` | Core ownership, queued execution, lease rejection, scientific/provider failures and trusted adapter attacks |
| `test_program_v1_parallel_trackers.jl` | `c989a63471e335234cb6d788a782c82152ea5d285177d38372b86b9ed43f141f` | evaluation-before-arbitration and exact tracker behavior |
| `test_program_v1_relationships_checkpoint.jl` | `fa5f962198704015524412ec9c20e429b62a8764c03a8594967d4de6d8763c63` | relationship atomicity, exact continuation and semantic RNG initialization |
| `test_lifecycle_receipts.jl` | `b69cdeade7c480fa1c136c98c40f3f1fb90bf7643739c463885aa52023cf356c` | lifecycle request/receipt meaning and publication |
| `test_rng_contract.jl` | `40a23edde914a04a443fc93a61576c54a0aaff377e5e51a0cd69ffd06f0020e2` | Philox known answers, stream/address isolation and RNG identity |
| `test_acceptance.jl` | `130ee35a68203ac76cd426fd7a612042a92768b5ac15b2dfc2d9610bcb32d20f` | shared acceptance law, nonfinite failure and atomic preflight behavior |
| `test_capabilities.jl` | `7a4afe03919acd2cbcfad1ddf341ecfc1985cdc56db94a5daf293463a435b4c3` | fail-closed scientific/backend capability and mechanism identity |
| `checkerboard_execution.jl` | `f5cc93f0eb828c8604c82cf7c6066246cc207a47e0efca4f710a922dc1b864b3` | shared backend direct scientific and launch behavior |
| `lifecycle_execution.jl` | `7e802fd043dd16e56e9f5d4062b80c957015fa6c727f2eb5c0cd88965f53d30a` | real-backend lifecycle semantics |
| `lifecycle_policy_execution.jl` | `a0d8f3c9aaec9e2dfaec42a40ed31e31a5ac14cd303f4e1515dae04c5ada44fb` | compiled lifecycle policy and failure semantics |
| real-Metal runner | `643b48d65476cb95bde3b9682b085637af4b0f995e9cf280577762ad8c40a438` | qualified Metal execution, cross-domain witnesses, queue/wait/lifetime and fail-closed admission |
| LW-3 parity driver | `092aaca44a191591e248c8d13bf3ac6e7a7dd3f32b85bd0423bf80533404b452` | direct/candidate scientific, checkpoint, launch, allocation and paired-throughput protocol |

Public authoring and compiler preservation additionally require the existing
PottsToolkit tests for completion/diagnostics
(`870c4967cab907e931b93669d079fb0dc78cdd32531bd9980cf25bf1858c2e7e`),
`mtkcompile`
(`5b67d7f6eb85956b679b1f9deb556b037b373e62452b5be65452ac731f6e5ef1`),
scientific operation SPI
(`1c921f45fc83edc27ed0b4abb14a5cea2f0a8f7d1304b23fa97735c3e13e11d5`),
external compiler SPI
(`11fd77a6f2f9990c91b83adfc27a242faf1eb6ecc21337b928e76cc8ff88a469`),
scientific witnesses
(`8c07fbda34698708294ff2ba2d9bb8dbf382aa27ac0e1761e1a8b9530e3c2404`),
backend descriptor execution
(`f91fbcfb284b81b84ad502ab3804b3d85f3e7436492ec03d3ee6bf6435265fc4`)
and relationship execution
(`8b36db1fcf6984df5874f6f7655c0053d51f4781e647c1139d146ebeda8d69da`).
The statements/traversal and public-API tests remain covered by the complete
package inventory. These tests cover built-in `Volume`, `ContactEnergy`,
`Elongation`, source-ordered
`HamiltonianTerm`s and registered external Hamiltonians. Their package suite,
not a copied assertion total, remains the authority.

The performance oracle remains the accepted LW-3 direct/candidate protocol:
the checkerboard body is `1 + 9C` launches, queued MCSs settle once, no
intermediate wait occurs, and paired CPU/qualified-Metal noninferiority uses
the unchanged one-sided 95% upper bound of `1.05`. The pilot must record a new
paired comparison because it changes a measured launch; B0 performance is
diagnostic and cannot substitute for the pilot.

## Adapter boundary frozen for LW-5B

"One adapter" means one CorePotts-owned lowering authority with ordinary
multiple dispatch over qualified IR. It does not mean one monolithic function
or one hand-written adapter per operation.

The adapter may produce:

- a concrete CorePotts operation value;
- a `LocalWork` declaration using the standalone public API;
- topology derived from compiled domains/footprints and the current topology
  epoch;
- a logical binding specification derived from resource access;
- output and submission declarations;
- a composed LocalWorksets-mechanism/CorePotts-scientific capability record;
  and
- inspection links from semantic stage/source handles to `WorkPlan` and
  launches.

It may not:

- generate per-model package code;
- reach into LocalWorksets private types or let LocalWorksets reach into
  CorePotts private state;
- use a family-symbol switch as a second compiler registry when Julia
  dispatch over existing qualified IR suffices;
- capture mutable arrays or host callbacks inside an opaque operation;
- self-authorize a backend, element type, operation or address space;
- change descriptor/Hamiltonian order or reconstruct symbolic arithmetic;
- create a scheduler, stream, native event, host fallback or synchronization;
  or
- reuse the claim-only checkpoint mechanism identity for a candidate that
  also changes proposal evaluation.

The pilot must receive a distinct composite candidate/checkpoint mechanism
identity before checkpoint qualification. Cross-restore rejection remains
mandatory.

## Verification tiers for LW-5B and later families

The IC-R0 verification-cost decision remains in force:

1. run focused adapter/declaration/plan tests during an edit loop;
2. run the affected CorePotts family and exact direct/candidate comparison at
   a candidate hold;
3. run targeted real Metal whenever device execution, adaptation, admission,
   lifetime or evidence changes;
4. run complete LocalWorksets and CorePotts suites at each family review;
5. run the complete PottsToolkit, integration, strict documentation and
   qualified Metal suites at LW-5D; and
6. run expensive paired performance campaigns at the pilot and final review
   boundaries, not on every ordinary test invocation.

No focused result can be reported as a complete family or LW-5 pass.

## Preservation review

The review asked four separate questions so representability, correctness,
ownership and product value were not conflated.

| Question | Ruling | Reason |
| --- | --- | --- |
| Is the stage inventory complete enough to begin bounded adapter work? | **PASS** | It covers all 41 device kernels plus sequential, staged-effect, tracker, relationship, enqueue, transaction, settlement and checkpoint execution authorities. |
| Are B0 and the pilot expressible without reopening the accepted LocalWorksets architecture? | **PASS WITH IMPLEMENTATION VETOES** | Both use existing independent/heterogeneous output and lifecycle APIs. Actual GPU compilation, binding and one-launch evidence remain LW-5B/pilot obligations. |
| Are scientific and package boundaries preserved? | **PASS** | Hamiltonian order, proposal views, RNG, acceptance, commit, lifecycle, settlement, checkpoints and MTK/SciML ownership are explicitly retained. |
| Does LW-5A prove that later migration is valuable? | **NO CLAIM** | Only the completed pilot value/parity review can answer this. B0 cannot. |

### Contradiction and red-team findings

- A whole lifecycle transaction is bounded in storage but is still not a
  local work item. Treating bounded capacity as sufficient representability
  would turn LocalWorksets into a hidden domain scheduler; the inventory
  rejects that inference.
- Checkerboard tracker destinations are bounded but depend on old/new owner
  values. Treating those values as frozen topology would be incorrect; K07
  and T02 remain deferred/domain-owned.
- Proposal evaluation is scientifically cohesive. Splitting descriptor
  evaluation, `OrderedFold`, acceptance and RNG into extra launches would make
  the abstraction worse and could change floating order or visibility. The
  pilot therefore preserves the fused CorePotts callable and one-launch
  boundary.
- The existing checkerboard LocalWorksets adapter is evidence of feasibility,
  not a template for one bespoke adapter per operation. The pilot must
  demonstrate a mechanically derived binding/topology path and report its
  complexity.
- Exact parity does not prove value. The post-pilot ballot must separately
  reject a correct but larger, less inspectable or more specialized result.
- Source portability does not qualify CUDA or ROCm. LW-5 remains fail-closed
  to CPU and the reviewed Metal environment until separate evidence exists.

Findings: P0=0, P1=0, P2=0. There is no substantive dissent to preserve. The
review clears only the bounded B0 adapter/probe work, followed by the pilot if
B0 passes. It does not clear later families, default promotion, direct-oracle
deletion, LW-R3, or G6.

## Documentation-only verification

No production source, test, kernel, launch, workspace or runtime environment
changed in LW-5A, so this gate does not inherit a new runtime pass or rerun an
irrelevant performance campaign. The following static checks were run on the
exact working candidate:

| Check | Result |
| --- | --- |
| Compare `lib/CorePotts`, `lib/LocalWorksets`, root `src`/`test`/`integration`, and the Metal runner against qualified product `8b710692` | no changed production or test path |
| Parse all CorePotts `@kernel function` declarations and require each exact name in this inventory | `41/41` |
| Recompute every frozen source/test/runner SHA-256 recorded above and require it in this record | `30/30` |
| Resolve every local Markdown target in this record, the roadmap, README and G5H control | pass |
| `git diff --check` | pass |

Runtime qualification remains the exact IC-R0 product evidence. B0 must
produce fresh focused CPU/qualified-Metal evidence because it will change an
execution candidate; the proposal pilot must then produce its own complete
parity and performance evidence.

## LW-5A exit audit

| Requirement from the roadmap | Evidence | Result |
| --- | --- | --- |
| Classify every CorePotts execution stage | Complete semantic inventory plus exact 41-kernel census and non-kernel execution rows | PASS |
| Enforce bounded-local eligibility | Every row records domain/access/conflict/visibility and rejects orchestration or dynamic-route shortcuts | PASS |
| Freeze public authoring oracle | Global boundary and existing complete/`mtkcompile`/Hamiltonian/external-operation suite ownership | PASS |
| Freeze direct execution oracle | Exact source hashes, launch formula and isolated B0/pilot direct units | PASS |
| Freeze checkpoint and RNG oracles | Exact checkpoint/RNG tests, distinct candidate-identity rule and cross-restore rejection | PASS |
| Freeze capability oracle | Existing fail-closed CorePotts/LocalWorksets capability boundary; no new backend claim | PASS |
| Freeze performance oracle | Existing `1 + 9C`, one-final-wait and paired 1.05 protocol; mandatory fresh pilot comparison | PASS |
| Preservation review approves inventory before compiler work | Four-question review and contradiction round above | PASS |
| Do not authorize migration from classification alone | Only B0 is opened; the pilot remains conditional on B0; every later row deferred/retained/rejected | PASS |

This historical exit ruling is withdrawn. It is retained only to show the
prior evidence and may not be cited as authority to begin LW-5B or migration.
