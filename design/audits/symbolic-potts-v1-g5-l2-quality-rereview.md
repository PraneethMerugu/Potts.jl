# Symbolic Potts V1 G5-L2Q lifecycle quality rereview

Date: 2026-08-04

Branch: `codex/symbolic-potts-v1`

Reviewed HEAD: `a00060ebd419a774a6345f50b37a49e29ab495e6`

Reviewed implementation: `e22c660e41d358aad15d3e7c92db9b627ec04c96`

Implementation parent: `6a08b3361887b8b74d1d92d0d3c24c2222ce349d`

Status: complete fresh-context read-only exact-commit rereview

Verdict: **Clear — no P0, P1, P2, or P3 findings**

## 1. Verdict

The repaired candidate clears G5-L2Q. The prior sole P0 is closed: backend state-stage failure
selection now preserves the canonical state-rule offender within each request and performs one
canonical request-order reduction only after all reachable state action/effect launches. Sequential
and KernelAbstractions CPU execution expose the same complete status for the adversarial fixture,
independently of lifecycle declaration order, and failed settlement leaves all scientific state
unpublished.

The compilation and qualification costs remain material engineering costs, but the supplied
cold/warm, payload, specialization, kernel-family, structural-guard, and guarantee-ownership
evidence does not establish a remaining correctness or architecture blocker. The appropriate
follow-up is measurement, not speculative compiler work or test deletion.

This verdict stops at G5-L2Q. It does not authorize R2, G6, proof-model migration, lifecycle
language expansion, or a new compiler/backend refactor.

## 2. Exact-tree and review basis

The rereview independently inspected the implementation delta from `6a08b336` through `e22c660`,
the qualification-only handoff update at `a00060e`, the production state-stage path, the exact
regression, the Metal runner, the compilation/test-cost evidence, and the accepted stop boundary.

Before recording this review:

- `HEAD` was exactly `a00060ebd419a774a6345f50b37a49e29ab495e6`;
- `HEAD^` was exactly the implementation commit
  `e22c660e41d358aad15d3e7c92db9b627ec04c96`;
- the implementation parent was exactly
  `6a08b3361887b8b74d1d92d0d3c24c2222ce349d`;
- the worktree was clean;
- `git diff --check 6a08b336..a00060e` passed;
- the reviewed delta introduced no numbered phase artifact; and
- the sole production synchronization and host scientific-state materialization authority remained
  `lib/CorePotts/src/execution/program_settlement.jl:142-202`.

The independent focused CPU probe returned:

```text
(backend = :cpu, permutations = 2, selected = (2, 2),
 status = LifecycleStatusPayload(LifecycleStatusEvaluator, 1,
 LifecycleStageState, 11, 0xf3f7621d1ca2ea43, 0, 1,
 LifecycleDetailNonfiniteResult, 0, 0, 0))
```

The independent CorePotts package run with bounds checking enabled also passed all 223 functional
assertions and all 10 Aqua assertions. The exact-candidate recorded qualification was reused rather
than rerunning a 17-minute suite: fast 469/469; CorePotts 223 plus Aqua 10/10; and real Metal green
with scalar indexing disabled, including both canonical-failure permutations, selected counts
`(2, 2)`, and the exact state-stage nonfinite offender at anchor 1.

## 3. Prior P0 closure

### Request-local canonical state-rule selection

`LifecycleBackendControl` adds one fixed-capacity `Int32` failure-rank vector beside the existing
candidate-status vector (`lifecycle_backend_control.jl:6-20, 298-319`). The reset kernel restores
each rank to `typemax(Int32)` at the transaction boundary
(`lifecycle_backend_kernels.jl:3-17`). This is value storage; names, handles, declaration order,
descriptor counts, capacities, and rule identities do not become type parameters.

Each selected request remains one backend work item. For each reachable action/effect launch, its
state-rule loop wraps that request's status slot with the global state-rule index
(`lifecycle_commit.jl:591-631`). `_LifecycleRankedStatusSlot.setindex!` replaces a prior failure only
when the newly failing rule has a lower canonical index
(`lifecycle_backend_control.jl:115-140`). Consequently, `ResetBoth` may launch and fail before
`TransformDaughters`, but the canonical-earlier `TransformDaughters` rule still replaces it for the
same Divide request.

There is no cross-work-item race on a rank slot: one work item owns each request; only the matching
plan class acts on that request; and action kernels are enqueued in the existing ordered backend
queue. All state launches write only request-local candidate state until the reduction boundary.

### Canonical request-order selection

The fixed launch list still places `Initialize` before `ResetBoth` and `TransformDaughters`, but it
no longer assigns semantic priority to that order. The enqueue path now completes every reachable
state action/effect launch and invokes the planning-status reducer exactly once afterward
(`lifecycle_backend_enqueue.jl:249-292`). The reducer traverses
`workspace.canonical_order` and publishes the first failed request
(`lifecycle_backend_kernels.jl:327-340`) before the existing sticky failure stamp gates
finalization and publication.

This directly repairs the prior counterexample: a later canonical Create/Initialize failure can no
longer prevent the earlier canonical Divide/TransformDaughters failure from executing and winning.
The repair does not add host polling, synchronization, fallback, another evaluator, or another
scientific executor, and it preserves the previously narrowed state-kernel launch payload.

## 4. Exact regression adequacy

The regression in `test/backend_conformance/lifecycle_execution.jl:76-310` covers the accepted
counterexample without weakening existing coverage:

1. One Divide request contains a canonical-earlier failing `TransformDaughters` rule and a
   later-rule failing `ResetBoth` rule. The launch list runs `ResetBoth` first.
2. One nonconflicting Create request fails through the earlier-launched `InitializeFrom` action.
   Both requests are selected in one MCS.
3. Sequential and KernelAbstractions executions compare their complete
   `LifecycleStatusPayload` values, not merely status classes. This includes code, MCS, stage,
   source, action identity, anchor, detail, and all capacity fields.
4. The Divide request's retained rank must equal its descriptor's first state-rule offset, proving
   the within-request offender is canonical rather than first-launched.
5. Both lifecycle declaration permutations must have the same complete-program type, exact status,
   and selected count `(2, 2)`.
6. Before/after snapshots prove unchanged ownership, cell kinds, generations, trackers, relationship
   activity/endpoints/generations/payload/degrees/incidence, and every descriptor-state bank for
   both sequential failure and backend settlement.
7. Settlement proves submitted/drained MCS 1, committed/materialized MCS 0, and a typed evaluator
   failure.

The same backend-neutral body is called from the fast and ordinary CPU suites. The Metal runner
sets `Metal.allowscalar(false)` before including it and calls it with `Metal.MtlArray` and
`Metal.mtlconvert` (`benchmark/backends/metal/runtests.jl:1-4, 69-74`). The recorded exact-candidate
Metal result therefore qualifies real device execution rather than a scalar fallback.

## 5. Compilation and test-cost disposition

### Essential and satisfied

- The canonical state-stage repair is local to request status/rank and the post-launch reduction.
- The exact sequential/KA CPU adversarial regression is present and independently green.
- The same regression is part of the real-Metal qualification with scalar indexing disabled.
- Affected fast/Core/Metal qualifications are recorded green.
- The narrowed state-kernel payload and existing structural guards remain intact.

### Measurement-only

- The real Metal process increased from 668.15 seconds to 1,035.94 seconds. Its 46.59-second source
  precompile and the new distinct cold fixture explain only part of that delta; no per-fixture
  instrumentation supports attributing the remainder to a specialization cross-product.
- A per-kernel Metal compilation/cache-family inventory is the next useful evidence if qualification
  latency remains unacceptable.
- Further per-action evaluator-bank slicing should be compared against the current reduced payload
  on the broad and minimal fixtures before implementation.
- Immutable completed/compiled fixture sharing may be timed, while mutable integrators, workspaces,
  and registries remain independently initialized.
- Complete-state arguments on the remaining 11 lifecycle and 9 checkerboard kernels warrant work
  only after a kernel-specific ABI or compile-time regression is measured.

### Explicitly deferred or rejected

- No speculative `@static`, generated-function, function-barrier, or compiler annotation.
- No whole-program payload rewrite without a measured kernel-specific regression.
- No removal of inference, allocation, specialization, extensibility, replay, atomicity, checkpoint,
  CPU, or real-GPU guarantees.
- No ordinary-CI timing threshold and no substitution of a smoke test for the explicit Metal
  qualification.

The underlying evidence supports this classification. Warm completion is 8.6-11.2 ms, warm
lowering 41.5-84.5 ms, warm initialization 0.041-0.098 ms, warm Metal enqueue 2.94 ms, and warm
Metal synchronization/execution 0.682 ms. The combined optimized typed IR is 15,252 bytes versus
13,420 bytes for volume-only (1.137x), while the reduced representative state launch type is 1,003
characters versus 6,405 for the former whole state. Structural guards already prove names,
declaration order, capacities, slots, parameter-only changes, and homogeneous 1/32/1,024 growth do
not create new complete-program or kernel-family types. Reachability masks bound the broad fixture
to 12 admitted effect/action pairs and one division variant.

The guarantee-to-test map also shows why raw duration is not grounds for deletion: focused tests own
inference, allocation, canonical failure, atomicity, checkpoint, replay, surface/tracker semantics,
and structural growth, while the retained expensive owners independently cover external extension,
public integration, and real-GPU correctness/no fallback.

## 6. Stop boundary

This document records a **Clear** G5-L2Q exact-commit rereview and closes the prior sole P0. It makes
no code or test change and authorizes no follow-on implementation.

Work must stop before R2, G6, proof-model migration, Wortel/Merks/focal-point/Act reconstruction,
new lifecycle vocabulary or effects, a duplicate evaluator/executor, host fallback or polling,
per-stage synchronization, speculative payload/compiler refactoring, test deletion, or timing
thresholds. Owner review remains required before any later gate or handoff.
