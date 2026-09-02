# LocalMath LM-0 Semantic Closure Evidence

Date: 2026-08-20

Status: executable evidence ledger for LM-0; non-authoritative over
[`localmath-direct-cutover.md`](localmath-direct-cutover.md)

## Purpose

This ledger maps the accepted LocalMath stage, empty-result, overflow,
ordering, failure, visibility, and numerical contracts to current executable
LocalWorksets evidence before structural editing begins. It does not preserve
the current public API. The direct-cutover specification remains the sole
authority; these tests are behavioral witnesses that the replacement must
continue to satisfy through the new semantic waist.

The ledger deliberately distinguishes:

1. behavior already executable through the current one KernelAbstractions
   path;
2. current negative or baseline evidence that must be replaced rather than
   frozen; and
3. LocalMath-only evidence that cannot exist until LM-1 or LM-2 introduces
   the corresponding representation.

## CPU semantic closure matrix

| LocalMath contract | Current executable evidence | Exact fact frozen for the cutover |
|---|---|---|
| Stage-entry reads and later-stage visibility | `test_consolidation.jl`, `LW-4C2 canonical topology and automatic workspace are explicit`; `test_mechanisms.jl`, `ordered candidate stages preserve provider visibility` | A later sequence stage observes the settled earlier result; source statement order inside one operation does not create a second visibility authority. |
| Unique participation is distinct from destination coverage | `test_phase3_keyed_independent.jl`, constructor/inspection cases and `Phase 3 canonical diagnostics and no-write validation cut`; `test_generic.jl`, `LW-4B direct independent lowering` and partial multi-emission cases | Unconditional reached-source participation does not prove sparse destination coverage. Total coverage rejects missing destinations; partial coverage preserves unmatched destinations. |
| Unique semantic validation closes publication | `test_phase3_keyed_independent.jl`, `Phase 3 canonical diagnostics and no-write validation cut` | Invalid keys, duplicates, and incomplete coverage produce one exact device validation error and leave the prior output canary unchanged. |
| Identity-seeded reduction and empty identity | `test_generic.jl`, `LW-4B deterministic and fast combined laws`; `test/localworksets_witnesses/matrix_free_fem.jl` | Deterministic assembly starts from the exact identity and publishes that identity to an empty destination. |
| Existing-seeded reduction and empty preservation | `test_phase2_seeded.jl`, `Phase 2 existing seed participates exactly once and empty preserves` | The stage-entry destination participates exactly once; a destination with no contribution preserves its prior value. |
| Resolution overwrite, preservation, total tie, and empty behavior | `test_phase1_semantics.jl`, `Phase 1 fused D1 routing, rank, empty, and tie laws`; `test_expansion.jl`, resolved-preserve cases | Rank and semantic identity form the complete winner order. Empty overwrite and preserve are distinct inspected laws. |
| Successful empty collection | `test_compacted_execution.jl`, `compacted Gate B boundaries and empty results`; `test_compacted_foundation.jl`, grouped empty allocation | Empty success publishes exact count zero and, for grouped results, a valid all-one segment directory. |
| Reject-on-overflow all-or-none semantic publication | `test_compacted_execution.jl`, `compacted Gate B invalid complete no-write` | Capacity overflow, invalid groups, and duplicate canonical identities fail through one validation cut and leave every public collection leaf byte-for-byte unchanged. |
| Source and canonical collection ordering | `test_compacted_execution.jl`, `compacted Gate B four semantic rows` and multilevel deterministic merge | Source order is logical item/lane order. Canonical order is exact `(group, key, identity)` order and is invariant to the physical scan/merge strategy. |
| Deterministic reduction order | `test_phase2_seeded.jl`, `Phase 2 canonical publisher order and seeded initialization`; `test_generic.jl`, deterministic Float32 case | Canonical contribution order is item-major then local lane, uses an exact left fold, and is observably distinct from lane-major reassociation. |
| Relaxed numerical policy | `test_generic.jl`, `LW-4B deterministic and fast combined laws` | Relaxed atomic combination makes no same-run replay claim; deterministic combination reports the canonical-order guarantee separately. |
| Heterogeneous ordered current-prefix recurrence | `ordered_fold_conformance.jl`; `test_ordered_fold.jl`, `ordered-fold admission and composition` | Each event reads the accumulator produced by prior canonical events, returns bounded writes to several named components, and applies an event only after validating all of its destinations. |
| Ordered empty, halt, total order, and successful prefix | `ordered_fold_conformance.jl`; `test_ordered_fold.jl` | Zero participants reproduce the explicit initial state; halt stops only the later prefix; duplicate order identities reject; a late invalid event retains the validated staged prefix. |
| Transaction-like guarded publication is emergent | `run_localworksets_ordered_fold_success_gate` in `ordered_fold_conformance.jl`; assertions in `test_ordered_fold.jl` | A failed ordered recurrence may change private staged state, while its dependent live publication remains closed by the exact device success gate. No transaction law or rollback claim is introduced. |
| Provider failure is not rollback | `test_generic.jl`, direct-publication `post_launch_failure_visibility`; `test_runtime.jl`, injected execution/fence failure cases | Inspection reports that post-launch writes may be partially visible. Provider failure poisons the provider scope and retains required leases; it does not claim restoration. |
| One prepared workspace and no intermediate stage wait | `test_compacted_consumers.jl`; `test/localworksets_witnesses/compacted_active_fem.jl` | A finite sequence consumes produced device state without a host observation or parallel executor. |

## Real-GPU evidence

The current qualified real-device path is Metal through KernelAbstractions.
`benchmark/backends/metal/runtests.jl` exercises:

- source-order, canonical-order, halt, invalid-prefix, and success-gated
  ordered recurrence;
- identity- and existing-seeded deterministic reductions;
- fixed and runtime-keyed unique publication, including incomplete coverage;
- resolved overwrite/preserve and named multi-port publication;
- stable grouped deterministic publication;
- compacted multi-port success and semantic rejection;
- injected device failure and shared failure-scope behavior; and
- warm packed execution through the single KernelAbstractions provider.

`benchmark/backends/metal/lw4_check.jl` is the narrower ordered-fold and
failure-gate diagnostic. It proves the current recurrence ABI on a
scalar-disabled real GPU and is suitable for quick pre-cutover qualification.

These witnesses freeze semantics, not the current implicit lane-tail event
model.

The final LM-0 real-device results, including the exact distinction between a
preparation-local publication-validation failure and shared-scope provider
poisoning, are recorded in
[`metal-semantic-final.toml`](../design/evidence/localmath/lm0/metal-semantic-final.toml).

## Evidence that must not be misclassified as LM-0 completion

### Exact per-submission receipts

Current `WorkEvent` values describe an implicitly ordered cumulative provider
tail, and `wait` synchronizes that tail. This is useful baseline and failure
lifetime evidence, but it does **not** yet satisfy the accepted LocalMath
`ExecutionReceipt` dependency and settlement contract.

LM-2B must add focused CPU and real-GPU tests proving:

- every `execute!` returns one exact logical submission receipt;
- an unresolved same-scope downstream submission consumes an earlier receipt
  without a host wait by relying on KA implicit ordering;
- settled-success receipts are admitted across scopes, while unresolved
  cross-scope dependencies reject until the caller explicitly waits;
- waiting may physically synchronize the cumulative provider tail while
  resolving and releasing only the requested logical receipt;
- settled scope ordinals and `waitall` grouping prevent redundant provider
  synchronizations;
- semantic failure gates dependent publication on device;
- dependency/backend/device mismatches reject before launch; and
- neither `execute!` nor dependency consumption hides synchronization.

The cumulative lane-tail tests remain provider-truth evidence and are extended
with exact logical dependency, settlement, failure, and lifetime witnesses.
They do not imply selective provider completion or a second scheduler.

### Runtime relation freshness

Current topology epochs do not yet represent the accepted split between
`schema_epoch` and `content_generation`.

LM-1 must add focused CPU and real-GPU tests proving:

- advancing packed content generation within planned capacity does not rebuild
  or invalidate a plan;
- a schema epoch, representation, ownership, capacity, or physical binding
  change invalidates the prepared relation proof before launch;
- a warm validation receipt pairs the exact content generation with the event
  that established it;
- a stale receipt cannot authorize dependent publication; and
- no `ProgramRelationshipState` conversion occurs during validation,
  execution, settlement, or lifecycle processing.

### LocalMath syntax equivalence

Current `@localwork` tests establish the evaluator and execution semantics but
cannot establish the new syntax. LM-3 must prove that `@localmath` and the
programmatic constructors produce the same semantic signature, bindings,
workspace, phases, launches, numerical evidence, and device result for each
row in the CPU closure matrix. The old grammar is deleted in that same atomic
boundary.

## Verification commands

Complete CPU package evidence:

```sh
julia --project=lib/LocalWorksets -e 'using Pkg; Pkg.test()'
```

Focused real-Metal ordered/failure evidence:

```sh
julia --startup-file=no --threads=1 --project=benchmark/backends/metal \
    --compiled-modules=existing --compile=yes --optimize=2 \
    benchmark/backends/metal/lw4_check.jl
```

Complete qualified Metal evidence:

```sh
julia --startup-file=no --threads=1 --project=benchmark/backends/metal \
    --compiled-modules=existing --compile=yes --optimize=2 \
    benchmark/backends/metal/runtests.jl
```

LM-0 does not require inventing duplicate tests around already exact evidence.
It requires carrying this matrix forward, adding the three missing
LocalMath-only suites at their representation boundaries, and deleting the
superseded tests with their obsolete authorities.
