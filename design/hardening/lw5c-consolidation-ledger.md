# LW-5C consolidation ledger

Status: **IMPLEMENTATION CONSOLIDATED; EXACT REVIEW PASSED**

Date: 2026-08-14

## Selected product

LW-5C selects one bounded CorePotts integration: K02 candidate generation and
K03 proposal evaluation execute as one ordered `LocalWorksets.sequence`.
The sequence uses KernelAbstractions implicit ordering, two launches per
color, no intermediate wait and one cumulative completion scope.

## Removed live alternatives

The frozen B0/B2/B3/B4 documents remain historical evidence. Their obsolete
loaded executable candidates do not remain coequal with LW-5C:

- isolated proposal-evaluation bridge and its private B3 runtime;
- B3 capability, replay, checkpoint, queue and settlement dispatch;
- standalone B4 candidate-generation bridge and execution wrapper;
- B0/B2/B3/B4 regular real-Metal probes; and
- B0/B4 regular test-support modules and the B4 parity runner.

The direct K02/K03 kernels remain only as the required scientific and
performance oracle. The qualified conjunctive LocalWorksets claim mechanism
also remains because it is a distinct reusable mechanism, not a superseded
proposal-stage pilot.

## Earned abstractions

- `_prepare_core_localwork` now owns the common topology → plan → prepare
  lifecycle for both single work and sequences.
- `_CheckerboardProposalInputOperation` is the sole K02 operation adapter.
- `_SequencedProposalEvaluationOperation` is the sole K03 operation adapter.
- `_LocalWorksetsProposalStagesExecution` represents the ordered stages
  directly; it no longer impersonates candidate execution followed by a
  no-op proposal executor.
- the no-copy `StructArray` proposal record is the single K02/K03 ABI;
  writable disposition is excluded from the read record.
- one fixed `corepotts_checkerboard_proposal_science_v1` ABI is named
  honestly. `ResourceAccess` validates and inspects descriptor requirements;
  it does not pretend to synthesize a per-resource device view.

## Complexity change

| Surface | Before remediation | Consolidated candidate |
|---|---:|---:|
| Core LocalWork lifecycle adapter | 215 | 149 |
| candidate-generation bridge | 346 | 93 |
| proposal bridge / selected stages | 1,026 | 605 |
| regular Core LocalWorksets vertical test | 1,819 | 342 |
| total above | 3,406 | 1,189 |

This is a 2,217-line reduction on the directly compared surfaces: 740 loaded
production lines and 1,477 regular-test lines. The final cleanup removed four
uncalled helpers from the lifecycle adapter, checkerboard projection, and
proposal-record units. Line reduction is not the admission argument: the
retained code has one selected consumer, one direct oracle, explicit
ownership, and the full safety/performance evidence.

The table is a matched before/after delta, not an absolute adapter-footprint
claim. The retained checkerboard projection, typed proposal ABI, and temporary
non-default capability/checkpoint/settlement branches are accounted separately
for review. LW-R3 must merge or delete the temporary parallel lifecycle before
any default promotion; it may not leave direct and adopted engines permanently
coequal.

## Descriptor and topology closure

Preparation now requires the compiler-owned host `DescriptorExecutionPlan`.
It checks the complete capability descriptor digest and source table, derives
the canonical schedule, and incorporates descriptor fingerprint plus schedule
into the prepared topology epoch. The generated canonical fold also checks
each scheduled descriptor's `source_handle` before evaluation.

Tests reject same-count group reorder, same-count foreign source table, and
stale sites, color offsets, conflict displacements and proposal offsets.

## Stop ruling

No later family is opened by this result. K01, K09/L01, K08, tracker
contributions, accepted-copy effects, lifecycle emission and conflict
families retain the dispositions in the adoption matrix. A later family still
requires its own deletion unit, unrelated consumer evidence and CPU/Metal
hold.
