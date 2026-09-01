# LW-5A adoption-and-consolidation amendment

Status: passed by the focused preservation-and-consolidation review; revised
LW-5A complete; non-promoted B0 and bounded B2 subsequently passed; isolated
B3 proposal comparison passed after bounded CorePotts bridge remediation and
fresh review; `K02` is open only as the non-promoted B4 second-use witness;
production migration remains closed. Outcome:
[LW-5B3 review](lw5b3-proposal-adoption-review.md).

Date: 2026-08-13

Reviewed source commit: `bc5729f3db636c936ad2dfee46c5d1f1ced56059`

Reviewed source tree: `b30a56cc84395225d292a2eca175c8f4e15e99d9`

Qualified behavioral product: `8b710692a84f79b1411a1443a27a9ee099327bcf`

Qualified behavioral tree: `b360f2b06b404b34d448c75f3bdd5b012d839dc7`

Authority and evidence:

- [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md);
- [LocalWorksets V1 contract](../../spec/localworksets-v1.md);
- [superseded preservation inventory](lw5a-representability-and-preservation.md);
- [LW-4C final qualification](lw4c-final-qualification-evidence.md);
- [IC-R0 review](icr0-internal-complexity-review.md); and
- [LW-3 direct-parity evidence](lw3-localworksets-parity.md).

Review:
[LW-5A focused adoption-and-consolidation review](lw5a-adoption-consolidation-review.md).

## Amendment purpose

The prior LW-5A correctly froze scientific semantics but did not make
execution consolidation an admission requirement. It could therefore have
allowed LocalWorksets to wrap unchanged CorePotts kernels while retaining all
bespoke preparation, workspace, validation and launch machinery. Its
completion ruling is withdrawn; its census, source hashes and preservation
oracles remain evidence.

This amendment asks a stronger question for every stage:

> Can the frozen LocalWorksets API replace meaningful generic execution
> machinery while CorePotts retains the complete scientific operation and
> transaction semantics?

Representability without replacement is insufficient. Exact parity without
smaller and clearer downstream execution code is insufficient.

## Closed architecture and governing ownership

This amendment does not reopen the package name, public lifecycle
`localwork -> plan -> prepare -> run! -> wait`, topology ownership,
independent/combined/resolved output meanings, central lowering, bounded
workspace, KernelAbstractions implicit ordering, or declarative extension
rules.

CorePotts retains:

- scientific operation bodies and proposal before/after views;
- Hamiltonian meaning, descriptor identity/source order and `OrderedFold`;
- tracker meaning, addressed RNG, acceptance and failure classification;
- MCS clocks, color/attempt schedules and phase ordering;
- relationship and lifecycle laws, generations, slot reuse and transactions;
- scientific publication cuts, settlement and checkpoint identity.

PottsToolkit retains authoring, `complete`, `mtkcompile`, symbolic identity,
MTK integration and SciML problem/solver ownership.

LocalWorksets should replace, when an inventory row earns adoption:

- custom KernelAbstractions kernel wrappers and kernel factories;
- topology/routing validation and transfer;
- storage binding, access and alias validation;
- bounded workspace construction and accounting;
- independent publication, qualified combination and resolution mechanics;
- launch preparation, queued lifetime and backend admission; and
- declaration/plan/preparation/execution inspection.

KernelAbstractions continues to own portable kernel execution and implicit
ordering. LocalWorksets does not acquire a scheduler, stream, clock, solver,
transaction or checkpoint.

## Dispositions

Every row receives one of four dispositions:

| Disposition | Meaning |
| --- | --- |
| `selected` | Bounded next work is specified here. It still requires its implementation hold and evidence. |
| `conditional-after-pilot` | Credible adoption target, but no source migration is authorized until the decisive proposal pilot passes and the row receives its own pre-migration hold. |
| `retain-domain-orchestration` | The row or its governing loop/transaction remains CorePotts. An explicitly identified child mechanism may still have a conditional row elsewhere. |
| `reject` | Not an LW-5 adoption target under the frozen architecture. Reconsideration requires new evidence and, where applicable, the two-unrelated-consumer rule. |

There is no broad `defer` bucket. Conditional rows identify an actual
replacement, deletion target, reuse path and blocker.

## Oracle abbreviations

The following exact baseline oracles are frozen by hash in the
[preservation inventory](lw5a-representability-and-preservation.md#frozen-preservation-oracles):

| Abbreviation | Oracle responsibility |
| --- | --- |
| O-CB | checkerboard scientific state, color order, launch order, counters and direct CPU/Metal execution |
| O-HAM | built-in and external Hamiltonian authoring, qualification, proposal views and canonical source-order fold |
| O-RNG | Philox known answers, semantic stream/address isolation, accepted trajectory and RNG identity |
| O-ACC | acceptance, nonfinite/zero-temperature failure and failure atomicity |
| O-LW | current LocalWorksets claim vertical, lifetime, trusted admission and one-final-wait behavior |
| O-STAGE | accepted-copy and after-MCS state/effect tests |
| O-TRACK | tracker rebuild, before/after views, parallel updates and checkpoint policy |
| O-REL | relationship transaction integrity, external relationship operations and checkpoints |
| O-LIFE | CPU/Metal lifecycle request, planning, conflict, staging, failure and receipt tests |
| O-CHK | exact direct/candidate continuation, distinct mechanism identity and cross-restore rejection |
| O-CAP | fail-closed backend/scientific capability and external-operation admission |
| O-PERF | `1 + 9C`, one-final-wait, allocation/transfer/workspace and paired 1.05 noninferiority protocol |

## Complete adoption matrix A — ownership and current machinery

The IDs and stage coverage are unchanged from the prior 41-kernel plus
non-kernel census. “Custom machinery” names the present CorePotts execution
mechanism that an adoption must either replace or deliberately retain.

| ID | Current scientific owner | Current custom kernel and preparation/launch machinery | Domain semantics that must remain |
| --- | --- | --- | --- |
| C00 | CorePotts compiler/admission | `evaluator_probe_kernel!`, `descriptor_probe_kernel!`, `descriptor_group_probe_kernel!` and direct probe launches | Purity, context support, type inference and backend admission evidence |
| C01 | CorePotts sequential engine | `_advance_sequential!` and `_attempt!` host loops; recipient/direction RNG and dynamic source selection | Serial algorithm, attempt identity, RNG schedule and immediate visibility |
| C02 | CorePotts evaluator/acceptance | `_attempt_selected!`, evaluator calls, contribution scratch and direct canonical fold; no generic KA wrapper | Proposal view, Hamiltonian order, tracker before/after view, acceptance and RNG |
| C03 | CorePotts accepted transaction | `_emit_accepted_copy_stage!`, `_apply_accepted_copy_stage!`, `_commit_copy!`, relationship buffers and per-effect loops | Eligibility, tracker/ownership mutation order, relationship atomicity and publication |
| C04 | CorePotts staged effects | `_emit_after_mcs_descriptor!`/`_apply_after_mcs_descriptor!` site/model loops and `StageRuntimeBuffers` scratch allocation | Condition/value semantics, before/after-lifecycle phase and target state meaning |
| C05 | CorePotts staged effects | Iterated site loops and shift/append loops/copies in `_apply_after_mcs_descriptor!` | Iteration count, read-after-write visibility, shift axis and phase ordering |
| C06 | CorePotts relationship transaction | `_emit_after_mcs_relationship_descriptor!`, edge loop, request buffer sizing/preparation/publication | Endpoint generations, request identity, integrity and atomic transaction law |
| C07 | CorePotts MCS/lifecycle orchestration | `_after_mcs!` and `execute_lifecycle!` phase calls | Before/after ordering, lifecycle clock, failure cut and transaction boundary |
| C08 | CorePotts program transaction | bank-copy/swap helpers, rollback kernel, stage/commit/abort, snapshot/receipt publication | Atomic staged step, counter rollback, settled state and checkpoint meaning |
| K01 | CorePotts checkerboard workspace phase | `_checkerboard_clear_claims_kernel!`, `_clear_checkerboard_claims!`; B0 also compares `_checkerboard_clear_mcs_kernel!` boundaries | Phase choice, open gate and zero/identity values |
| K02 | CorePotts checkerboard scheduler/RNG | `_checkerboard_candidates_kernel!`, its factory/call in `_execute_checkerboard_mcs!`, and proposal arrays allocated by `_allocate_checkerboard_workspace` | Color schedule, addressed direction/priority RNG, neighbor law and proposal identity |
| K03 | CorePotts evaluator/acceptance | `_checkerboard_evaluate_kernel!`, `evaluate_kernel = launch(...)`, one per-color invocation and contribution array construction | `_ProposalEvaluationContext`, descriptor evaluation, `OrderedFold`, tracker views, acceptance and addressed RNG |
| K04 | CorePotts scientific failure control | `_checkerboard_acceptance_status_kernel!`, one-thread launch and sticky status write | Which expected failure wins, semantic identity ordering and failure publication cut |
| K05 | CorePotts claim meaning; LocalWorksets mechanism candidate | Three direct claim kernels plus `_prepare/_execute_checkerboard_claim_*`; four-launch prepared conjunctive LocalWorksets path | Old-owner/new-owner conjunction, total rank, canonical identity and eligibility |
| K06 | CorePotts accepted transaction | `_prepare_checkerboard_accepted_stage!`, `_publish_checkerboard_accepted_stage!`, CPU loops and relationship buffers | Accepted-only eligibility, source order, relationship transaction and phase visibility |
| K07 | CorePotts commit | `_checkerboard_commit_kernel!`, launch call and inline tracker delta recursion | Ownership mutation, exact tracker deltas and atomic accepted-copy meaning |
| K08 | CorePotts statistics | `_checkerboard_report_kernel!`, one-thread loop and per-MCS report buffer | Disposition-to-counter mapping and cumulative statistic meaning |
| K09 | CorePotts bank/lifecycle orchestration | `_lifecycle_gated_copy_kernel!` plus many array/tuple/state enqueue overloads and backend checks | Source/destination bank choice, gate and placement in transaction sequence |
| K10 | CorePotts checkerboard scheduler | nested attempt/color loop, color permutation and preparation/calls for all stage kernels | MCS schedule, immutable scalar color, phase order and queueability |
| K11 | CorePotts publication | `_publish_program_bank_kernel!` and `_enqueue_program_bank_publication!` | Active bank, committed MCS, sticky status and atomic publication cut |
| K12 | CorePotts settlement | `settle_program!`, backend synchronization, transfer/materialization and receipt publication | Sole host visibility boundary, error translation, committed/drained counts and checkpoint view |
| L01 | CorePotts lifecycle clock/control | reset and policy-clear kernels, launch factories and due/open gates | Due clock, lifecycle availability and sticky control status |
| L02 | CorePotts lifecycle indexing | site-key, bitonic-sort step, status-reduction and owner-index kernels plus `_enqueue_lifecycle_sort!` | Canonical owner/site order, capacity failure and indexed-cell meaning |
| L03 | CorePotts lifecycle operation compiler/runtime | `_emit_lifecycle_backend_kernel!`, fixed-capacity request arrays and direct launch | Request meaning, source/action identity, generations, policy evaluation and clock |
| L04 | CorePotts lifecycle request ordering | mark, scan, compact and sort kernels plus `_enqueue_lifecycle_scan!` and request sort | Canonical request order and overflow/failure behavior |
| L05 | CorePotts lifecycle planning | effect-plan and planning-status kernels plus per-effect launch loop | Create/retire/remove/transition plan semantics and capacity reasons |
| L06 | CorePotts division planning | division/replan/relationship-validation kernels and ten variant launch loops | Partition/side law, geometry, RNG, generations and relationship admissibility |
| L07 | CorePotts lifecycle conflict authority | CPU conflict/dedup functions and `_select_lifecycle_backend_kernel!` | Complete structure/state/relationship footprint, canonical key and atomic selected set |
| L08 | CorePotts lifecycle transaction | `_stage_lifecycle_structure_backend_kernel!` and per-effect launch loop | Slot allocation/reuse, generations, kinds and structural staging |
| L09 | CorePotts relationship transaction | `_stage_lifecycle_relationships_backend_kernel!` and action launch loop | Incident/incompatible removal law and relationship integrity |
| L10 | CorePotts lifecycle state transaction | `_stage_lifecycle_state_backend_kernel!` and action × effect launch loops | State initialization/reset/transform/split/redraw and tracker semantics |
| L11 | CorePotts lifecycle validation | finalize-effect, validate and finalize kernels plus failure stamping | Retired counts, complete staged-state invariants and success/failure meaning |
| L12 | CorePotts transaction/publication | failure-stamp kernel and gated staged/current state-copy orchestration | All-or-nothing lifecycle publication and durable failure cut |
| T01 | CorePotts tracker compiler/runtime | tracker rebuild/recompute loops, storage allocation and checkpoint reconstruct/persist paths | Quantity meaning, owner/relationship domain and checkpoint policy |
| T02 | CorePotts accepted commit | generated/recursive tracker delta evaluation and in-place old/new owner updates | Before/after semantics, exact delta and commit atomicity |
| R01 | CorePotts public host transaction | `host_relationship_transaction`, complete copy/validate/rebuild/checkpoint work | Settled host mutation, runtime identity and atomic relationship replacement |

## Complete adoption matrix B — replacement and expected consolidation

“Adapter” means operation-specific code after the shared CorePotts
IR-to-LocalWorksets boundary exists. A conditional row is admitted only if its
actual adapter is materially smaller than the machinery it demotes.

| ID | Generic machinery LocalWorksets could replace | Proposed LocalWork/output representation | Expected custom source demoted or deleted | Expected operation-specific adapter |
| --- | --- | --- | --- | --- |
| C00 | None; this proves compiler/device callability rather than executing model work | none | none | none |
| C01 | None without changing the sequential algorithm | none | none | none |
| C02 | Shared callable/resource projection may be reused by K03, but no sequential launch is replaced | CorePotts scientific callable invoked directly by the sequential engine | no sequential source deletion | shared scientific operation type only; no LocalWork declaration |
| C03 | Output publication, bounded records, workspace and conflict mechanics for child effects | heterogeneous independent site effects plus bounded relationship candidates | per-effect buffer/publication loops only after split qualification; `_commit_copy!` remains | one effect-family descriptor projection; no per-model code |
| C04 | Site/model loops, scratch construction, binding/alias checks and independent publication | site-domain independent output; scalar model-domain independent output | matching `_emit/_apply_after_mcs_descriptor!` loops and redundant scratch allocation | effect callable plus mechanically derived state read/target binding |
| C05 | Per-substep launch preparation and disjoint shift publication | ordered `sequence` of independent site work only when visibility/launch count is proved | iterated site/shift loops after qualified replacement | iteration/axis declaration derived from `IteratedSiteAssignmentEffect`/`ShiftAppendEffect` |
| C06 | Bounded emission records, workspace sizing and generic resolution | relationship-domain buffered/resolved candidate ports; CorePotts publishes transaction | edge emission loop and duplicate buffer sizing after mechanism qualification | request construction callable and relationship-slot projection |
| C07 | No whole-row replacement | none; child work remains separately prepared | none | none |
| C08 | K09 may replace copy children; transaction remains | no transaction-level LocalWork | no stage/commit/abort/rollback source deletion | none |
| K01 | Kernel wrapper, route validation, binding/alias checks, launch preparation and inspection | two partial independent identity-route ports with an open-gate mask | B0 is non-production and need not delete source; production adoption later may demote a clear kernel/wrapper | one small clear operation and phase-derived bindings; no model-specific code |
| K02 | Kernel wrapper, output publication, proposal-array binding and launch preparation | heterogeneous independent ports for target/source/owners/priority/identity/disposition | candidate kernel wrapper/factory/call and redundant output validation after later adoption | proposal-generation callable; schedule/RNG inputs projected through shared checkerboard execution view |
| K03 | Entire generic KA wrapper, output publication, route/binding/alias validation, preparation, lifetime, backend admission and inspection | one active-prefix LocalWork with independent heterogeneous contribution/disposition ports and fixed unique routes | candidate production path removes `_checkerboard_evaluate_kernel!` and bespoke factory/call; direct kernel is reference-only during qualification and is not a permanent coequal production path | `ProposalEvaluationOperation` plus a shared derived checkerboard read/binding projection; no per-descriptor/model adapter |
| K04 | Resolved winner mechanics and result publication | one resolved status candidate per failed proposal, canonical semantic identity; CorePotts translates result | one-thread scan kernel/factory/call after separate proof | status-code/rank mapping only |
| K05 | Conflict workspace, clear/rank/identity/select kernels, preparation, lifetime and inspection | existing bounded two-key conjunctive resolved LocalWork | direct three-kernel path and claim preparation demoted after promotion; reference retained outside default production | existing claim descriptor mapping, consolidated with shared adapter/trust boundary |
| K06 | Heterogeneous output publication and relationship record workspace | accepted-item independent state ports plus buffered relationship candidates | CPU per-candidate prepare/publish loops and duplicated buffer handling after split reviews | accepted-effect projection; CorePotts eligibility/transaction wrapper remains |
| K07 | Independent ownership store plus deterministic/qualified tracker contribution mechanics | selected-item ownership port and bounded keyed tracker contribution ports | commit kernel publication plumbing and generic tracker update recursion only where replacement is exact | tracker descriptors projected to typed contributions; commit transaction stays CorePotts |
| K08 | Deterministic integer combination, empty identity, workspace and publication | five named combined `UInt64` counter ports | report scan kernel/factory/call after exact combination proof | disposition-to-five-contributions callable |
| K09 | Copy kernels, tuple recursion, backend/device/alias checks, preparation and inspection | independent identity-route copy work; `sequence` only for ordered child copies | gated copy kernel and duplicated enqueue overloads for adopted leaves | bank/storage schema projection; bank choice/gate remains CorePotts |
| K10 | Prepared child plans may remove repeated kernel factories, but LocalWorksets cannot own the loop | CorePotts calls prepared child work in existing order | only redundant per-call child launch construction; loop remains | tuple of prepared child handles owned by CorePotts |
| K11 | None without moving the publication cut | none | none | none |
| K12 | None; LocalWorksets event wait may be one child receipt but settlement remains sole authority | no settlement LocalWork | none | none |
| L01 | Clear/reset publication and generic preparation for fixed arrays | independent partial-coverage clear/reset ports gated by CorePotts due/open state | clear wrappers for qualified arrays; clock/reset semantics remain | lifecycle control schema projection |
| L02 | No currently admitted generic sort/index family | none in LW-5 | none | none |
| L03 | Bounded record emission, capacity/workspace validation, binding, launch and inspection | buffered heterogeneous request records with CorePotts-defined values/identities | emission kernel wrapper, request-array plumbing and duplicated capacity validation after a separate mechanism hold | lifecycle operation callable derived from compiled descriptor/resource access |
| L04 | A future generic scan/compact primitive could replace mechanics, but it lacks two unrelated consumers | none in LW-5 | none | none |
| L05 | No generic execution replacement without moving planning semantics | none | none | none |
| L06 | No generic execution replacement without moving division semantics | none | none | none |
| L07 | Generic keyed arbitration workspace and winner mechanics beneath a caller-defined footprint | resolved candidate records after CorePotts computes complete conflict keys/claims | device selection mechanics and duplicated workspace validation only; Core conflict proof remains | conflict-record projection plus CorePotts validator; requires exact representability proof |
| L08 | Independent publication is mechanically possible but inseparable from slot/generation transaction in current form | none at this gate | none | none |
| L09 | Same for relationship staging | none at this gate | none | none |
| L10 | Same for heterogeneous state staging | none at this gate | none | none |
| L11 | Validation/finalization is domain evidence, not output publication | none | none | none |
| L12 | Publication cut is domain authority | none | none | none |
| T01 | Deterministic combination workspace/publication for rebuildable quantities | lattice/edge item work with explicitly qualified combined owner outputs | generic rebuild loops and per-tracker scratch construction for admitted tracker families | tracker descriptor callable; owner routes must be derived or emitted dynamically, never frozen incorrectly |
| T02 | Bounded keyed contribution mechanics for old/new owners | two-lane combined contributions per selected proposal, followed by CorePotts commit | generic update recursion/publication for admitted deltas; scientific delta functions remain | descriptor-to-contribution projection shared with T01/K07 |
| R01 | None; host transaction is already the correct boundary | none | none | none |

## Complete adoption matrix C — evidence, blockers and disposition

| ID | Applicable direct oracle | Concrete blocker before adoption | Disposition |
| --- | --- | --- | --- |
| C00 | O-CAP, O-HAM | Not runtime work; wrapping probes would add a layer | `reject` |
| C01 | O-RNG, O-CB, O-CHK | LocalWork would alter serial scheduling/visibility | `retain-domain-orchestration` |
| C02 | O-HAM, O-RNG, O-ACC, O-TRACK | No generic execution wrapper to delete on sequential path | `retain-domain-orchestration` |
| C03 | O-STAGE, O-TRACK, O-REL, O-CHK | Dynamic targets and transaction atomicity require the row to be split | `conditional-after-pilot` |
| C04 | O-STAGE, O-CHK | Current path lacks qualified direct Metal oracle; derived state binding must be proved | `conditional-after-pilot` |
| C05 | O-STAGE | Read-after-write visibility and launch count; no direct Metal oracle | `conditional-after-pilot` |
| C06 | O-REL, O-STAGE, O-CHK | Dynamic keyed emission and relationship transaction split | `conditional-after-pilot` |
| C07 | O-LIFE, O-CHK | It is domain phase orchestration, not one local mechanism | `retain-domain-orchestration` |
| C08 | O-CB, O-LIFE, O-CHK | Transaction and rollback authority cannot move | `retain-domain-orchestration` |
| K01 | O-CB, O-LW, O-PERF | B0 must prove derived bindings, CPU/Metal compilation and one launch; it is non-decisive | `selected` (B0 only) |
| K02 | O-CB, O-RNG, O-PERF | Shared execution-view derivation and exact RNG/state binding; corrected pilot passed | `selected` only as the non-promoted B4 second-use witness |
| K03 | O-CB, O-HAM, O-RNG, O-ACC, O-TRACK, O-CHK, O-CAP, O-PERF | Existing nested runtime/program data cannot be hand-flattened; shared projection must derive qualified reads and compile on CPU/Metal. The current evaluator mutates an `AbstractVector`, whereas the generic lowering requires one concrete returned `NamedTuple`; a bounded type-stable return bridge must preserve exact source order without hidden output writes | `selected` decisive pilot after B0 |
| K04 | O-ACC, O-CB, O-PERF | Exact failure ranking/publication and one-launch nonregression | `conditional-after-pilot` |
| K05 | O-LW, O-CB, O-CHK, O-PERF | Promotion/reference disposition and trust-boundary consolidation | `conditional-after-pilot` |
| K06 | O-STAGE, O-REL, O-CB | CPU-only accepted stages and mixed transaction effects need separate holds | `conditional-after-pilot` |
| K07 | O-TRACK, O-CB, O-CHK, O-PERF | Dynamic owner keys, atomic commit and deterministic/fast qualification | `conditional-after-pilot` |
| K08 | O-CB, O-PERF | Preserve exact counters and avoid extra clear/publish launches | `conditional-after-pilot` |
| K09 | O-LIFE, O-CB, O-PERF | Many heterogeneous leaves; sequence must not add waits/launches | `conditional-after-pilot` |
| K10 | O-CB, O-RNG, O-LW, O-PERF | Scheduling must remain CorePotts; only child preparation may consolidate | `retain-domain-orchestration` |
| K11 | O-CB, O-LIFE, O-CHK | This is the scientific publication cut | `retain-domain-orchestration` |
| K12 | O-CB, O-LW, O-LIFE, O-CHK | Sole synchronization/transfer authority | `retain-domain-orchestration` |
| L01 | O-LIFE, O-PERF | Clock/gate split and no launch inflation | `conditional-after-pilot` |
| L02 | O-LIFE, O-PERF | No admitted LocalWorksets scan/sort family and no two unrelated consumers | `reject` |
| L03 | O-LIFE, O-CAP, O-CHK, O-PERF | Dynamic bounded records and exact external-operation compilation need a separate mechanism hold | `conditional-after-pilot` |
| L04 | O-LIFE, O-PERF | No admitted scan/compact family or unrelated second consumer | `reject` |
| L05 | O-LIFE, O-CHK | Planning choices and failure reasons are domain semantics | `retain-domain-orchestration` |
| L06 | O-LIFE, O-RNG, O-REL, O-CHK | Division planning is scientific policy and transaction preparation | `retain-domain-orchestration` |
| L07 | O-LIFE, O-REL, O-CHK, O-PERF | Must prove complete dynamic footprints can lower without weakening conflicts; Core validation stays | `conditional-after-pilot` |
| L08 | O-LIFE, O-CHK | Generation/slot structural transaction cannot be extracted safely | `retain-domain-orchestration` |
| L09 | O-LIFE, O-REL, O-CHK | Relationship transaction authority cannot move | `retain-domain-orchestration` |
| L10 | O-LIFE, O-TRACK, O-CHK | State-action and conservative split semantics dominate mechanics | `retain-domain-orchestration` |
| L11 | O-LIFE, O-CHK | Validation/finalization is the scientific proof boundary | `retain-domain-orchestration` |
| L12 | O-LIFE, O-CB, O-CHK | All-or-nothing publication and durable failure must remain CorePotts | `retain-domain-orchestration` |
| T01 | O-TRACK, O-CHK, O-PERF | Owner destinations are state-dependent; dynamic emission/epoch cost and numerical mode must be explicit | `conditional-after-pilot` |
| T02 | O-TRACK, O-CB, O-CHK, O-PERF | Dynamic old/new owner keys and commit atomicity; cannot silently use floating atomics | `conditional-after-pilot` |
| R01 | O-REL, O-CHK | Host transaction has no backend-local mechanism to replace | `reject` |

## Selected B0 — non-decisive integration probe

B0 remains a disposable/non-promoted comparison around the claim-workspace
clear. It may prove only:

- construction through the public LocalWorksets lifecycle;
- topology/routes derived from checkerboard workspace capacity;
- storage, access and alias binding;
- one-launch independent heterogeneous output;
- KernelAbstractions implicit visibility without an intermediate wait;
- inspection linking the CorePotts phase to the LocalWork plan/launch; and
- actual CPU and qualified real-Metal compilation/admission.

B0 need not enter the production path and need not delete the direct clear.
It fails if it adds a new mechanism, vendor branch, host callback, device
allocation, hidden wait or manually repeated per-model binding construction.
B0 success opens only the decisive proposal pilot.

Outcome: the [B0 implementation and focused hold](lw5b0-integration-probe-review.md)
passed on exact CPU and real-Metal evidence. Its operation/projection remain
disposable test support; only the shared private derivation boundary enters
CorePotts source provisionally. Proposal-pilot implementation is therefore
open under its separate holds. Production promotion remains closed.

Subsequent bounded outcome: the
[LW-5B2 proposal bridge](lw5b2-proposal-bridge-review.md) passed exact CPU and
real-Metal derivation, inference and implicit-ordering evidence without
production promotion. Source inspection corrected one provisional assumption:
the contribution matrix is transient evaluator scratch, not a downstream
publication. B2 therefore returns a fixed, inferred tuple of native-scalar
`ProposalEvaluation`s, folds it canonically inside CorePotts, and exposes only
the partial independent disposition output to LocalWorksets. This preserves
the scientific boundary and does not amend the accepted output algebra. The
isolated B3 one-for-one comparison was then executed; its
[review](lw5b3-proposal-adoption-review.md) preserves the original CPU
noninferiority failure and records the corrected canonical-schedule bridge,
exact functional parity and passing unchanged CPU/real-Metal protocol. The
fresh remediation review opens `K02` only as the non-promoted B4 second-use
witness.

## Selected decisive pilot — proposal evaluation

### Scientific body retained in CorePotts

The pilot preserves, rather than rewrites:

- `_ProposalEvaluationContext` and current before/after views;
- `evaluate_proposal_contributions!` and qualified external operations;
- descriptor identity, bounded affected anchors and source order;
- `fold_proposal_contributions` and `OrderedFold`;
- tracker reads and proposed before/after values;
- `_proposal_acceptance_result`, expected failure classification; and
- `_program_uniform` with `AcceptanceStream`, operation 3, semantic proposal
  identity and immutable color subround.

These functions form a CorePotts-owned concrete local operation. They are not
reimplemented as LocalWorksets combination/resolution laws.

### Execution machinery replaced

In the candidate production path, the generic LocalWorksets independent/
heterogeneous lowering must replace:

- `_checkerboard_evaluate_kernel!` as the executing kernel wrapper;
- `evaluate_kernel = launch(_checkerboard_evaluate_kernel!)`;
- the bespoke per-color kernel argument/publication call;
- duplicate validation of unique contribution/disposition destinations;
- operation-specific launch preparation and lifetime handling; and
- opaque inspection that cannot connect the compiled descriptor stage to its
  launch.

One LocalWorksets launch replaces exactly one existing launch. Candidate
generation, acceptance-status reduction, direct claim arbitration, accepted
stage, commit, report, lifecycle and settlement are identical between the
isolated direct and pilot arms.

The current direct kernel is frozen as a reference/parity oracle during
qualification. If the pilot is promoted later, it becomes reference-only or
is replaced by an independently maintained semantic oracle; it does not
remain a permanently coequal production implementation. Promotion/deletion is
a separate reviewed disposition, not an automatic effect of pilot success.

### Derived adapter requirement

The difficult seam is explicit. LocalWorksets static bindings are arrays and
submission values are bounded scalars, while the direct kernel receives a
nested `CheckerboardExecutionState`. The pilot may not solve this by manually
enumerating a private runtime object for every descriptor/model.

The CorePotts adapter must mechanically derive a reusable execution view:

1. descriptor and stage `ResourceAccess` supplies qualified scientific reads;
2. the checkerboard proposal ABI supplies target/source/owner/identity/
   disposition reads and the immutable color/active-count submission values;
3. compiled domain resources supply topology arrays and epochs;
4. stage/output metadata supplies contribution lane count, value types,
   unique routes and partial-coverage rules;
5. CorePotts capability requirements compose with LocalWorksets mechanism
   capability; and
6. one shared projection builds the lightweight device-call context consumed
   by the existing `_ProposalEvaluationContext`.

A small typed `ProposalEvaluationOperation` and a phase-specific projection
method are allowed. Per-descriptor or per-model generated package code,
repeated named-tuple assembly, captured mutable host arrays, opaque callbacks
and LocalWorksets private reach are forbidden.

There is a second, independent seam. The current
`evaluate_proposal_contributions!` writes through a caller-owned
`AbstractVector`, while the admitted direct/heterogeneous LocalWorksets kernel
expects the operation to return one concrete inferred `NamedTuple` of
emissions. The pilot must supply a bounded, type-stable CorePotts return bridge
whose source count is fixed by the compiled descriptor plan. It may share the
existing per-descriptor evaluation methods and must preserve canonical source
order. It may not mutate LocalWorksets output bindings inside the operation,
smuggle output arrays through logical reads or captured callable fields, or
make an undeclared read of a write-only binding. The operation can derive
whether a proposal is actionable from the proposal ABI and the program-open
gate; it must not rely on an unreported read/write alias of `dispositions`.

If exact contribution return, inference, or Metal compilation cannot be
obtained through the accepted independent/heterogeneous mechanism, the pilot
is rejected and returns to LW-5A. That failure does not authorize a new output
or execution family.

### Second-use witness

Before the decisive pilot review can pass, K02 candidate generation must be
constructed and compiled through the same adapter as a non-promoted second-use
witness. It need not replace production candidate generation during the
pilot. It must reuse topology/binding/capability/inspection construction and
require materially less family-specific integration than K03.

The second witness fails if it copies the K03 named bindings, constructs a
second execution-view framework, adds a family-symbol registry or requires
LocalWorksets changes. Existing LBM/spring/FEM witnesses prove the mechanism's
cross-domain generality but do not substitute for this CorePotts adapter reuse
test.

### Decisive evidence

The pilot must prove:

- exact contributions, dispositions, expected failure, final state, trackers,
  accepted trajectory and counters;
- identical RNG addresses and canonical Hamiltonian fold;
- exact checkpoint continuation, distinct candidate/checkpoint mechanism
  identity and direct/pilot cross-restore rejection;
- one-for-one launch replacement, no intermediate wait and queueable MCSs;
- no host fallback, device allocation, vendor branch or new scheduling layer;
- bounded preparation/warm allocations, topology transfer, workspace,
  specialization and compile-cache behavior;
- a concrete inferred operation result with no hidden mutation or undeclared
  read/write access to output bindings;
- CPU and qualified real Metal;
- the unchanged O-PERF paired protocol; and
- the deletion, derivation and second-use tests below.

Correct parity without consolidation is a failed pilot.

## Mandatory adoption tests

### Deletion test

An adopted family must retire or demote meaningful custom kernel,
preparation, launch, workspace, validation or inspection machinery. An
alternative wrapper beside an unchanged production path fails.

For the pilot, the minimum deletion unit is the candidate production
evaluation kernel wrapper plus its bespoke factory/call. Merely having
LocalWorksets call `_checkerboard_evaluate_kernel!` is an automatic veto.

### Derivation test

Reads, routes, topology, outputs, submission slots and capability requirements
must be mechanically derived from qualified CorePotts IR wherever the
information exists. The evidence records which fields are derived from
`ResourceAccess`, domain resources, stage/output metadata or the fixed
proposal ABI. Hand assembly is permitted only for information that has no
existing authority, must be isolated in one shared projection and must be
reported as debt.

Per-model generated code and repeated binding/workspace construction are
forbidden.

### Second-use test

A second operation using the same mechanism must require materially less
operation-specific integration. The pilot uses K02 as the required
non-promoted second-use witness. Review reports shared versus family-specific
source and construction sites rather than relying on an arbitrary line count.

Failure means the adapter is another framework per operation, not reusable
consolidation.

## Mandatory consolidation ledger

Every adopted family freezes a before row before implementation and fills the
after row before its review. Counts include candidate production code; frozen
reference-only oracle code is reported separately so it cannot hide duplicate
production maintenance.

| Measure | B0 baseline | Proposal-pilot baseline | Required after evidence |
| --- | ---: | ---: | --- |
| custom production kernels | 1 claim-clear kernel | 1 evaluation kernel (77 source lines including wrapper/scientific body) | executing wrapper removed/demoted; retained scientific callable identified |
| launch/preparation functions/sites | `_clear_checkerboard_claims!` plus one direct factory/call | one factory assignment plus one per-color call site in `_execute_checkerboard_mcs!` | generic `PreparedWork` construction and `run!`; no bespoke kernel factory/call |
| topology construction sites | 0 explicit; array length is implicit | 0 explicit; layout implicit in workspace arrays | one derived topology authority, not family hand assembly |
| storage/binding construction sites | direct positional kernel arguments | direct positional kernel arguments | one shared derived binding projection; family-specific fields enumerated |
| workspace construction sites | claim arrays in `_allocate_checkerboard_workspace` | contribution/disposition arrays in `_allocate_checkerboard_workspace` | reused scientific arrays distinguished from LocalWorksets-owned algorithmic workspace |
| shared adapter code | 0 | 0 | exact shared source/functions used by B0, pilot and K02 witness |
| family-specific adapter code | 0 | direct wrapper only | exact operation/projection source; must be materially smaller than demoted machinery |
| specialized types/compile footprint | direct KA kernel specialization | direct KA kernel specialization per concrete state | before/after method instances or backend compile-cache evidence after warm-up |
| launches/waits | one clear launch; no intermediate wait | one evaluation launch/color; total `1 + 9C`; one settlement | unchanged or better; exactly one pilot launch replaces one direct launch |
| allocations/transfers/workspace | included in O-PERF/IC-R0 baseline | included in O-PERF/IC-R0 baseline | preparation and warm-run allocations, topology bytes, algorithmic/provider workspace |
| throughput | diagnostic only | paired CPU/Metal direct baseline | unchanged one-sided 95% upper bound `<= 1.05` |
| inspection coverage | direct phase not represented | kernel name/launch not linked to descriptor stage | semantic stage -> declaration -> plan -> preparation -> launch/capability |
| direct-oracle maintenance | direct production only | direct production implementation | reference-only cost separated; promotion/retirement disposition recorded |

Later family ledgers use the same measures and additionally record all custom
kernels, launch/preparation functions, topology/storage/workspace construction
sites, shared/family adapter code, specializations, launches, waits,
allocations, transfers, throughput and inspection facts.

No arbitrary line-count threshold applies. Performance-qualified
specialization may remain when measured evidence shows that generic lowering
cannot preserve the bound, but the retained specialization must have at least
two consumers or be reported honestly as domain code rather than generalized
LocalWorksets machinery.

## Hard vetoes

Any one of the following rejects an adoption candidate:

1. a large bespoke adapter replaces a small kernel;
2. LocalWorksets merely invokes an unchanged custom CorePotts kernel;
3. model, Hamiltonian, lifecycle-operation or ordinary Potts authors must
   understand or write LocalWorksets declarations;
4. topology, binding or workspace assembly is repeated per operation;
5. a fused scientific operation is split into extra launches;
6. direct and LocalWorksets implementations remain permanently coequal with
   no default/reference/promotion disposition;
7. LocalWorksets gains domain scheduling, RNG, acceptance, transaction,
   checkpoint, MTK or solver authority;
8. correct parity is used to claim consolidation despite increased
   complexity;
9. CPU-only source portability is reported as Metal/CUDA/ROCm qualification;
10. hidden synchronization, allocation, host fallback, opaque callbacks or a
    new runtime/scheduler appear; or
11. a new mechanism/family is added without its separate admission rule and
    two unrelated concrete consumers; or
12. the caller operation mutates an output binding, captures array-backed
    runtime state outside validated storage, or reads a binding whose declared
    access does not include reads.

## Conditional post-pilot roadmap

Pilot success does not migrate these rows automatically. It makes them
eligible for ordered pre-migration holds:

1. K02 checkerboard candidate generation as the first adapter-reuse target;
2. K01/K09/L01 bulk clear and state/workspace copy mechanisms;
3. K08 report and counter combination;
4. C04/C05 site/model assignment and bounded iterated local updates after a
   direct Metal oracle exists;
5. T01/T02/K07 tracker contribution mechanics with explicit dynamic keys and
   deterministic/fast numerical qualification;
6. C03/K06/C06 bounded accepted-copy and relationship emission, split from
   CorePotts transaction authority;
7. L03 bounded lifecycle request emission; and
8. K04/K05/L07 reusable resolution mechanics beneath CorePotts validation and
   transactions.

The roadmap may stop after any family. Failure does not weaken LocalWorksets,
force adoption or permit skipping to a more complex row.

Checkerboard/MCS scheduling, settlement, bank publication, Hamiltonian fold,
RNG scheduling, acceptance, lifecycle planning/commit, generation and slot
reuse, relationship transaction authority, checkpoints, MTK compilation and
SciML solver ownership remain outside LocalWorksets throughout.

## Focused preservation-and-consolidation review

The review must ballot these questions separately:

1. inventory completeness;
2. scientific ownership preservation;
3. credible execution-machinery replacement;
4. adapter derivability;
5. pilot decisiveness;
6. conditional later-family roadmap; and
7. whether the work can make CorePotts/PottsToolkit materially smaller and
   clearer.

Reviewers must inspect the exact source inventory, the current LocalWorksets
public binding constraints, the proposed nested-runtime projection, the
baseline ledger, all vetoes and the unchanged preservation hashes. A pass may
carry implementation blockers that are explicitly assigned to B0/pilot
evidence; it may not waive an architectural contradiction.

Substantive dissent is recorded even if the final ballot passes.

The focused review passed all seven questions at the specification boundary,
with one owned P1 implementation hold and two owned P2 risks. Adapter
derivability remains deliberately unproved: B0 may establish only the shared
binding skeleton, and the decisive pilot must prove the nested execution view
and bounded return bridge on CPU and real Metal. The review opens B0 only.

## Amendment exit conditions

LW-5A clears only when:

- all prior semantic rows contain every field required by matrices A-C;
- selected, conditional, retained and rejected work is explicit;
- B0 is non-decisive and non-promoted;
- the proposal pilot replaces, rather than wraps, its custom execution unit;
- the deletion, derivation, second-use and ledger obligations are normative;
- direct code has a qualification/reference disposition rather than permanent
  coequal production status;
- the seven-question review clears without an unowned P0/P1 finding; and
- the authoritative roadmap and living status are updated only after that
  review.

No production or test execution source changes in this amendment. A passing
documentation/static audit therefore does not claim fresh runtime
qualification; B0 and the pilot must generate fresh evidence when they change
candidate execution.
