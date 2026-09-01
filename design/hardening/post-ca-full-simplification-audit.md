# Post-CA full simplification audit

Status: audit complete; S0-S2 implemented and qualified

Date: 2026-08-15

This audit covers the production and active verification surfaces of
LocalWorksets, CorePotts, and PottsToolkit after CA-0 through CA-4. It did not
modify production code or run qualification suites. It preserves the dirty
worktree and treats the current qualified CA candidate as the behavioral
baseline.

The objective is narrower than another IC or API phase:

> Deduplicate machinery and produce a net reduction in source lines with zero
> loss of public behavior, scientific semantics, backend behavior, evidence,
> performance qualification, or maintainability.

The labels below organize an implementation ledger; they do not introduce a
new architecture, lifecycle, execution family, or public phase vocabulary.

## Committee method

Three independent agents first produced read-only memos:

1. LocalWorksets API, construction, validation, and execution-family audit;
2. CorePotts execution, JuliaGPU, lifetime, and preservation audit; and
3. cross-package SPI, external-adopter, and verification-cost audit.

The chair independently measured the exact worktree and compared it with the
sealed LW-4C and IC-R0 baselines. The reviewers then received the combined
candidate and performed a contradiction round. The final ledger incorporates
their reachability corrections, overlap corrections, backend vetoes, and
lowered line-count estimates rather than averaging their initial memos.

No severity below denotes a current correctness failure. It denotes priority
and risk for simplification work.

## Size regression

Counts are nonblank, non-comment Julia source lines:

| Boundary | LW-4C baseline `44389fc` | IC-R0/HEAD | Current | Since IC-R0 |
|---|---:|---:|---:|---:|
| LocalWorksets production | 7,364 | 8,677 | 10,580 | +1,903 |
| CorePotts production | 21,696 | 21,725 | 23,889 | +2,164 |
| PottsToolkit production | 22,645 | 22,687 | 22,687 | 0 |
| total production | 51,705 | 53,089 | 57,156 | +4,067 |

Current physical inventory (raw lines, including comments and blanks):

| Boundary | Source files | Production lines | Test files | Test lines |
|---|---:|---:|---:|---:|
| LocalWorksets | 25 | 11,136 | 9 | 5,248 |
| CorePotts | 58 | 25,530 | 23 | 6,032 |
| PottsToolkit | 70 | 24,093 | 43 | 12,104 |

The growth is therefore real and localized to LocalWorksets and its CorePotts
adoption. It is not evidence that every added line is accidental: later work
added heterogeneous storage, fixed lanes, shared completion, K02/K03 adoption,
construction integrity, topology reads, caller workspace construction, and
qualification. The audit found a credible zero-loss reduction of only part of
the 4,067-line increase.

The one-thousand-line source guard is retained as a warning, but it is not a
simplification metric. `preparation.jl` is exactly 1,000 executable lines and
three lowering files are near the limit. Moving unchanged code into a new file
earns no credit. Every implementation slice reports total package lines before
and after.

## Preservation boundary

No accepted simplification may change:

- public names, signatures, lifecycle, topology ownership, output semantics,
  validation errors, inspection keys/order, or workspace construction;
- direct, buffered, resolved, conjunctive, and sequence behavior;
- checked counts, routes, capacity, bytes, array facts, backend/device facts,
  alias rules, topology freshness, or fail-closed admission;
- KernelAbstractions implicit ordering, asynchronous submission, launch counts,
  one final synchronization, cumulative completion, leases, or poisoning;
- CPU/qualified-Metal results, allocation bounds, inference, or performance
  evidence;
- CorePotts RNG addresses, Hamiltonian source-order folding, proposal science,
  acceptance, lifecycle, transactions, failure cuts, settlement, or clocks;
- direct checkerboard oracle/fallback/accepted-copy behavior;
- capability keys, evidence identities, checkpoint field order, serialized
  fingerprints, continuation, or mismatch rejection;
- PottsToolkit authoring, MTK/SciML behavior, compiled reports, or executable
  fingerprints;
- CompilerSPI and BackendSPI role separation or package dependency direction;
  and
- external cross-domain LocalWorksets witnesses.

Line reduction by macros, generated code, opaque callbacks, registries, broad
fallback methods, or code movement is not simplification.

## Accepted implementation ledger

Ledger net estimates use raw physical additions and deletions, matching the
eventual `git diff --numstat` report. Final evidence must also report
nonblank/non-comment executable lines separately; a comment or blank-line
change cannot satisfy the simplification gate.

### S0 -- proven dead production code

These rows have repository-wide reachability evidence and require deletion, not
replacement abstraction.

| ID | Exact cluster | Canonical surviving authority | Expected net |
|---|---|---|---:|
| S0-1 | LocalWorksets `_validate_value`, `_validate_storage`, their dead trusted-callback entries, two-argument `_scalar_values`, and `_record_arrays` | generated `_canonical_submission`, one-argument generated `_scalar_values`, and live lowering paths | -97 |
| S0-2 | CorePotts ungated `_enqueue_lifecycle_array_copy!` recursive family and root `_enqueue_lifecycle_staging_copy!` | gated lifecycle state-copy protocol | -139 |
| S0-3 | CorePotts `_prepare_core_localwork(phase, work, backend; ...)` and `_prepare_core_localwork_sequence` | `_plan_core_localwork[_sequence]` plus `_prepare_core_localwork(planned, storage; ...)` | -45 |
| S0-4 | unreachable post-engine tail of `advance_mcs!` and `_advance_checkerboard!` | `_advance_checkerboard_transaction!`, `_advance_sequential_transaction!`, and an explicit unsupported-engine error | about -22 |

Expected S0 production reduction: approximately 303 lines.

S0 must add a focused hostile-method check showing that replacement of the live
generated `_canonical_submission` still rejects. Deleting dead monitored
callbacks must not weaken the live method-authority boundary.

### S1 -- LocalWorksets internal deduplication

| ID | Exact cluster | Required form | Expected net |
|---|---|---|---:|
| S1-1 | repeated workspace traversal in `_validate_workspace_aliases`, `_validate_device_coherence`, `_validate_prepared_topology_coherence`, `_workspace_identities`, `_validate_prepared_identities`, and `prepare` | compute one centrally admitted immutable tuple of physical workspace arrays and consume it everywhere | -55 to -65 |
| S1-2 | direct/buffered `_required_bindings` and `_binding_access`; direct/buffered/single-resolved active-prefix checks; repeated static-payload preparation prefix | concrete package-owned helpers with thin family methods and exact `invoke` ownership | -35 to -43 |
| S1-3 | repeated topology-transfer, phase/launch, compiler/Atomix, and independent-port evidence envelope | narrowly typed helpers in `evidence_support.jl`; every semantic field remains explicit and returned tuple order remains exact | about -38 |
| S1-4 | `_workspace_tree_from_buffers` and `_allocate_workspace_tree` | one package-owned typed tree constructor with internal modes, never an external callback | -20 to -26 |

Expected S1 production reduction: approximately 148 to 172 lines.

S1 must preserve concrete family admission methods. It must not turn trusted
dispatch into a generic callback surface or merge topology host validation with
prepared-device validation.

### S2 -- CorePotts profile and preparation consolidation

| ID | Exact cluster | Required form | Expected net |
|---|---|---|---:|
| S2-1 | candidate/promoted capability builders and duplicate checkpoint profile tails in `sequential_program.jl`; repeated provider/compiler/lowering extraction in proposal-stage inspection | one immutable execution-lowering profile, qualification-specific policy validation, one exact capability builder, and one checkpoint serializer | -70 to -95 credited after overlap |
| S2-2 | common plan, epoch, backend, color, proposal-offset, bank, and capacity validation in `_prepare_localworksets_checkerboard_claims` and `_prepare_proposal_stages_bridge` | one CorePotts-owned immutable validation result consumed by both profiles | -20 to -30 credited after overlap |
| S2-3 | repeated normalized proposal descriptor identity across validation, provenance, bridge state, epoch, and inspection | materialize the exact ordered identity tuple once | 0 to -5 credited after overlap |

The S2 clusters overlap in profile extraction, preparation facts, and
descriptor identity. The accepted aggregate credit is therefore only 90 to 130
production lines, not the sum of the reviewers' initial gross estimates. S2
does not share scientific calculation or publication logic between the direct
oracle and LocalWorksets path.

### Held S3 -- narrow cross-package ownership proposal

PottsToolkit currently reconstructs CorePotts storage and workspace reports in
`src/compiler/execution/boundary.jl`. A single immutable
`CompilerSPI.program_layout_report(program)` may become the Core-owned authority
only if it preserves `reports.storage`, `reports.workspace`, concrete value
types, field order, and executable fingerprint exactly.

This is primarily an ownership correction, not a line-count win: expected net
reduction is only 5 to 15 lines. Reject it if the new SPI surface or forwarding
machinery is larger or less discoverable than the two current walkers. Do not
use automatic re-export generation. Because CompilerSPI is a public
compiler-facing facade, this proposal is not part of the zero-public-API-change
simplification candidate. It remains held for a separate SPI compatibility
decision.

## Accepted production target

The evidence-backed preimplementation target was:

- direct deletion floor from S0: approximately 295 to 305 lines;
- arithmetic forecast from the reviewed S0-S2 rows: approximately 533 to 607
  raw production lines removed;
- conservative acceptance claim before an exact implementation diff: at least
  500 and no more than 600 net production lines; and
- no implementation claim above the exact final `git diff --numstat` result.

The 500-line lower bound and 600-line upper bound above were originally stated
as acceptance criteria, not merely as estimates. During the postimplementation
contradiction review, the committee unanimously amended that numerical
criterion: the 500-line floor and 600-line ceiling are waived for S0-S2. The
replacement acceptance rule is that every slice is independently net-negative
and the complete zero-functionality-loss evidence matrix passes. This amendment
does not claim that the original numerical criterion was met; it records why
unsafe forecasted factoring was rejected instead of being performed to satisfy
it.

Every slice must be net-negative independently. A new abstraction that only
moves code, grows type parameters, adds generated functions, or creates another
SPI layer fails even if individual files become shorter.

## Implementation outcome

S0-S2 completed on 2026-08-15. The exact implementation, qualification, identity
oracle, hashes, held debt, and fresh committee ballots are recorded in the
[implementation review](post-ca-simplification-review.md).

The final reduction is 367 raw and 358 executable production lines. By slice:
S0 removed 313/289, the deliberately narrowed S1 removed 30/34, and the
authority-hardened S2 removed 24/35 raw/executable lines. The original 533-607
raw estimate remains a preimplementation forecast; its associated 500-600
acceptance band was explicitly amended as described above. Review rejected
forecasted factoring wherever it would have weakened concrete family admission,
validation order, backend authority, or specialization.

S1 did not consolidate active-prefix, static-topology, topology-transfer, or
compiler-evidence paths. The existing `_determinism_report`, `_port_evidence`,
and winner-evidence authority debt is explicitly held. S2's private bridge
fields retained for tests and lifetime reasoning are also held. None is counted
as completed simplification.

## Verification simplification

Test tiering changes cost, not LoC, and is not counted in the production target.
The active authority remains the complete package and qualified hardware suites.

Safe test/support consolidation is estimated at 160 to 260 net lines:

1. share construction-only LocalWorksets CPU/backend fixture builders while
   retaining the reusable real-device harness and hostile-world fixtures;
2. add one test-only `CompiledPottsProgram` reconstruction helper;
3. replace bounded stochastic seed searches with frozen witnessed seeds bound
   to the exact RNG contract identity; and
4. remove an assertion only after a row-by-row oracle ledger proves an
   identical authoritative assertion remains.

Execution tiers:

1. focused tests during each edit;
2. complete changed-package CPU suites at each S0/S1/S2 handoff;
3. one final complete LocalWorksets, CorePotts, and PottsToolkit CPU
   qualification;
4. one final qualified real-Metal semantic/lifetime/admission run; and
5. performance campaigns only if a kernel, launch schedule, workspace hot path,
   synchronization, or measured path changes.

Smoke results can never mint capability evidence. Fresh-process method-world
tests, full Metal qualification, and cross-domain external witnesses remain
required evidence even when they are isolated into separate jobs.

## Held and rejected simplifications

### Held pending separate policy or evidence

- recursive topology/fact-tree walkers: plausible extra reduction, but callback
  or traversal abstraction can obscure host/device authority and allocate;
- settlement wait factoring: three concrete paths preserve different trusted
  wait and failure laws;
- merging lifecycle/no-lifecycle gate types: requires CPU/Metal device-code
  proof of no runtime branch and offers little gain;
- legacy resolved implementation retirement: public legacy and conjunctive
  spellings remain real functionality;
- claim-only LocalWorksets candidate retirement: could remove roughly 350 to
  500 production lines, but private checkpoints, replay tools, benchmarks, and
  witnesses still observe it; and
- direct-oracle demotion: forbidden while it remains fallback, accepted-copy
  implementation, and independent scientific/performance oracle; and
- the S3 `CompilerSPI.program_layout_report` ownership proposal: it adds a
  public SPI name for a small mostly-relocational reduction and therefore needs
  a separate compatibility decision.

### Rejected in the contradiction round

- sharing candidate generation or final acceptance-to-disposition logic between
  direct and LocalWorksets paths. This would create common-mode failures and
  weaken the parity oracle even if it reduces lines;
- deleting `_CheckerboardCandidate`, `_CheckerboardProposalRead`, or their
  StructArray-backed physical ABI without independent allocation, identity,
  binding, and device evidence;
- merging direct, buffered, single-resolved, legacy-resolved, or conjunctive
  kernels and launch schedules;
- genericizing provider settlement, package-owned `which`/`invoke` admission,
  or externalizing traversal callbacks;
- removing `identity_route`, `topology_read`, `workspace_requirements`,
  `allocate_workspace`, or complete inspection facts;
- moving CorePotts science, RNG, checkpoints, or provenance into LocalWorksets;
- replacing explicit CompilerSPI/BackendSPI facades with automatic exports; and
- counting file splits, report relocation, test tiering, or historical evidence
  deletion as LoC simplification.

## Qualification matrix

| Boundary | Required result |
|---|---|
| static/reachability | deleted symbols have no live references; include graph, explicit imports, ambiguity ownership, formatting, parse/load, and `git diff --check` pass |
| exact API/evidence | public names and methods unchanged; every validation error and `inspect` tuple matches; capability/checkpoint/report/fingerprint bytes and field order match |
| LocalWorksets CPU | complete API, family, topology, workspace, alias, device, lifetime, sequence, StructArray, admission, and package-quality suite passes |
| CorePotts CPU | complete direct/LW, RNG, Hamiltonian, lifecycle, transaction, failure, settlement, checkpoint, capability, SPI, and hostile-world suite passes |
| PottsToolkit CPU | sole complete active inventory passes, including authoring, compiler, MTK/SciML, persistence, native components, and package quality |
| external witnesses | LBM, deterministic/fast springs, matrix-free FEM, z-buffer, and CorePotts integration remain exact |
| real Metal | full semantic, alias/device, lifetime, implicit-order, queued-settlement, one-final-wait, failure, replay, and fail-closed evidence passes |
| inference and code generation | every affected host/device path remains inferred and device-compilable; representative CPU/Metal code has no new dynamic dispatch, runtime policy branch, aggregate spill, or forbidden allocation |
| performance | launch/synchronization counts and warm allocations match; rerun controlled noninferiority only for an affected measured path |
| LoC | each slice and final production/test totals are net-negative; no split-only or generated-code substitution is credited |

## Reviewer contradiction ballots

| Reviewer | Final ballot | Correction contributed |
|---|---|---|
| LocalWorksets API/Julia design | SAFE in reduced scope | lowered the production claim to a conservative range; required exact inspection/error preservation; held generic waits, gates, and recursive walkers |
| JuliaGPU/backend/lifetime | SAFE immediate deletion; conditional dedup requires evidence | corrected dead LocalWorksets count to about 97; confirmed Core reachability; required inference, allocation, codegen, Metal, and exact fingerprint evidence |
| external adopter/cross-package | SAFE only after oracle and settlement carve-outs | removed double counting; vetoed shared direct/LW science and candidate ABI deletion; reduced defensible test deletion |
| chair | AUTHORIZE S0-S2 only under this matrix | selected the common zero-loss intersection; S3 and all conditional retirements remain held |

## Decision

The project has genuine internal growth, but a responsible zero-loss pass will
not erase all post-IC functionality. S0-S2 provide a concrete, net-negative
candidate without reopening architecture or sacrificing independent oracles.

Before implementation, preserve the exact current source and evidence through a
recoverable commit or complete content manifest. Then execute S0, S1, and S2 in
order. Passing this qualification matrix and a fresh final review seals only
the simplification candidate; it does not authorize another operation migration
or new LocalWorksets functionality. Either requires a separate explicit gate
and owner decision.
