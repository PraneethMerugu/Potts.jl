# LW-5C bounded adoption matrix

Status: **PASSED AND FROZEN AS A BOUNDED NON-DEFAULT CANDIDATE**

Date: 2026-08-14

Authority:

- [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md);
- [LW-5A adoption-and-consolidation amendment](lw5a-adoption-consolidation-amendment.md);
- [LW-5B4O freeze review](lw5b4o-review.md); and
- [LocalWorksets V1 contract](../../spec/localworksets-v1.md).

## Frozen entry hold

LW-5C starts from the exact LW-5B4O-R candidate. Its qualified entry hashes
remain:

| Surface | Frozen SHA-256 |
|---|---|
| `lib/LocalWorksets/src` | `bc2f1a66f6499b90da4503a2e7590e1dc359b1ecd34130df2a5cfc040649c4bf` |
| `lib/CorePotts/src` | `97f1d8b88de73cb865a24590d7921680c349b1db00c18f05d7a83294a80f42b0` |
| LocalWorksets tests | `55bc71385481a032b821afce7d969fce624c8d2e5d5f5795243a215553188b72` |
| CorePotts tests | `822f23236263c462ae0ed7c611bbc9db53d2864586f57e51b7ae3cae82dc7509` |
| benchmark/Metal environment | `08e84b163a4bed8ba5696aa1b8a5812155801e494e00930d88e73a32e3a0c893` |

The direct checkerboard-kernel source remains the reference oracle. Its
entry and current SHA-256 is
`4c4f48bccc4afd10a292ecdaebc03e0f9260b385a9cd6ad84f4197d552e003f8`.

## Bounded adoption decision

LW-5C adopts only the two already-qualified proposal-local families:

1. K02 checkerboard candidate generation; and
2. K03 proposal-local descriptor evaluation and acceptance disposition.

They are one ordered `LocalWorksets.sequence` because K03 consumes the exact
K02 record, both have the same item domain, and the direct path already relies
on KernelAbstractions program order between their launches. The sequence has
two launches, no barrier, one validated submission per color, and no
algorithmic workspace. It is a production candidate, not the public/default
engine; LW-R3 retains authority over default promotion.

CorePotts continues to own the color/attempt loop, immutable scalar color,
semantic RNG addresses, descriptor schedule, canonical Hamiltonian fold,
acceptance law, expected-failure status, conjunctive claims, accepted-copy
transaction, commit, counters, lifecycle indexing, bank publication,
settlement, checkpoint identity and cross-mechanism rejection.

## Implementation and test matrix

| Requirement | Production authority | Implementation | Required evidence |
|---|---|---|---|
| One typed K02 record | CorePotts proposal ABI | `_CheckerboardProposalRead`, no-copy `StructArray` projection, `_CheckerboardProposalInputOperation` | component identity, exact candidate/RNG parity, CPU/Metal compilation |
| K03 read contract | fixed CorePotts proposal-science ABI, validated against descriptor `ResourceAccess` | `_proposal_resource_manifest` validates read-only descriptors for inspection; one logical `proposal` read replaces five leaf bindings; the full fixed science ABI is bound honestly rather than claiming per-resource projection | inspection names the fixed ABI and validated resource manifest; real registered external-Hamiltonian fixture |
| Canonical fold | CorePotts descriptor plan | `_validate_proposal_descriptor_identity` binds the compiler/capability fingerprint and source table; `_fold_scheduled_proposal_contributions` checks each scheduled `source_handle` before its sequential fold | same-count reorder/source-table rejection, exact disposition, nonfinite failure and source-order tests |
| Ordered execution | KernelAbstractions implicit ordering | `LocalWorksets.sequence(candidate_work, proposal_work)` | two launches, zero intermediate waits, one final grouped wait |
| Topology ownership | compiled checkerboard/descriptor plans | complete logical checkerboard epoch plus descriptor fingerprint/source-schedule epoch | stale site/color/conflict/proposal-offset and reordered-descriptor rejection before launch |
| Storage and aliasing | LocalWorksets central preparation | proposal record excludes writable disposition component | exact backend/type/shape/stride/access/alias inspection and rejection |
| Queue lifetime | LocalWorksets leases; CorePotts MCS capacity | one sequence event per color and bank | twelve queued MCSs, prelaunch exhaustion, complete tail drain |
| Checkpoint identity | CorePotts | `corepotts_checkerboard_localworksets_adoption_v1` | exact continuation and direct/adopted mismatch rejection |
| Scientific failure | CorePotts | unchanged acceptance-status/publication cut | direct/adopted expected-failure parity and no LocalWorksets poison |
| Backend portability | vendor-neutral CorePotts/LocalWorksets source | KernelAbstractions, Adapt, StructArrays, StaticArrays | source audit; CPU and qualified real Metal only |
| Inspection | LocalWorksets plus Core derivation record | stage declaration, plan, preparation, lowering, capability and launch facts | `inspect` links both semantic stages to the ordered plan |
| Performance | frozen paired protocol | direct versus adopted complete ten-MCS batches | 128x128, 10 warm, 50 paired samples, bootstrap upper95 <= 1.05 |

## Consolidation ledger

| Measure | Frozen direct/B4O baseline | LW-5C candidate |
|---|---|---|
| Executing K02/K03 wrappers | two direct KA wrappers | no direct wrapper selected in the adopted arm; two centrally lowered stages |
| Per-color preparation/call sites | direct candidate call plus direct evaluator call | one `_run_core_localwork_phase!` sequence submission |
| Logical proposal bindings into K03 | five separately named arrays | one typed `proposal` record plus `science` |
| Physical proposal authority | seven authoritative arrays plus shared StructArray record | same arrays; six-component read record excludes writable disposition |
| Launches per color | two | two |
| Intermediate waits | zero | zero |
| Algorithmic workspace | zero for these two stages | zero |
| Topology transfers | zero on the qualified fixed topology | zero |
| Direct oracle | selected production path at entry | retained reference path; default promotion remains an LW-R3 decision |
| Loaded historical pilots | B0/B2/B3/B4 test and executable scaffolding loaded beside the candidate | obsolete pilot bridge/runtime/checkpoint/settlement methods and regular Metal probes removed; frozen review records remain evidence |
| Core adapter/test footprint | 215-line duplicated lifecycle adapter, 346-line B4 bridge, 1,026-line B2/B3/LW-5C bridge, 1,819-line regular vertical test | 149-line shared lifecycle adapter, 93-line selected K02 operation, 605-line selected K02→K03 sequence, 342-line regular vertical test |

The matched consolidation removes 740 loaded production lines and 1,477
regular-test lines while retaining the separate direct oracle and the
qualified conjunctive LocalWorksets mechanism. The fixed proposal-science ABI
is an explicit narrow contract; LW-5C no longer claims that `ResourceAccess`
mechanically constructs a per-descriptor device view.

The matched delta does not hide the absolute integration footprint. The
remaining shared projection, typed proposal ABI, descriptor/topology checks,
and non-default capability/checkpoint/settlement branches are reviewed by
responsibility. Default promotion is conditional on LW-R3 merging or deleting
the temporary parallel lifecycle rather than keeping two permanent engines.

## Ordered stop audit for later families

The roadmap permits stopping after any family and forbids skipping a failed
hold. LW-5C therefore records these pre-migration dispositions rather than
silently broadening the implementation:

| Next row/family | Hold result | Disposition |
|---|---|---|
| K01 clear | B0 proved representability but a LocalWork adapter remains larger than the single direct clear wrapper and deletes no scientific machinery | stop; retain direct |
| K09 gated state copy | direct cleanup removed two self-copy passes; K09-R1 then proved the supported CPU relationship unit cannot satisfy current LocalWorksets storage admission and found no net deletion unit | K09-R1 sealed corrected direct execution; K09-2/K09-3 rejected |
| L01 gated lifecycle control | bank choice, due clock, explicit workgroup selection and transaction placement dominate the mechanism | stop; retain Core orchestration |
| K08 counters | the one-thread report is coupled to exact disposition/counter meaning; no launch or workspace nonregression proof exists | not opened |
| T01/T02/K07 tracker contributions | dynamic owner keys and commit atomicity remain inseparable from the accepted ownership transaction; floating modes also require a separate deterministic/fast qualification | not opened |
| C03/K06/C06 accepted-copy effects | current portable checkerboard oracle is CPU-only for these mixed site/relationship effects | closed by missing real-Metal oracle |
| L03 lifecycle request emission | requires its own bounded heterogeneous-emission mechanism hold and external-operation proof | not opened |
| K04/K05/L07 conflict resolution | K05 remains qualified evidence; complete lifecycle footprints and transaction validation are not represented by independent keyed winners | not opened |

This stop is not a claim that the later rows are impossible. It is the
required refusal to add mechanisms or domain adapters without their own
deletion unit, unrelated consumers and CPU/Metal evidence.

## Exit evidence

LW-5C closed against exact final hashes with all required evidence attached:

- focused program tests and direct/adopted parity;
- complete LocalWorksets and CorePotts suites;
- complete root PottsToolkit suite;
- persistent real-Metal LW-5C probe and complete qualified Metal suite;
- frozen CPU and Metal paired performance reports;
- source audit for vendor branches, synchronization and domain leakage;
- checkpoint continuation and mismatch rejection;
- allocation, launch, wait, transfer, workspace and compile-cache ledgers;
- a [post-migration review](lw5c-review.md) with P0=0, P1=0 and an owned P2
  ledger; and
- control/roadmap updates that leave LW-5D, LW-R3 and G6 closed.
