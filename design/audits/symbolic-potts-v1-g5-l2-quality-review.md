# Symbolic Potts V1 G5-L2Q lifecycle quality review

Date: 2026-08-03

Branch: `codex/symbolic-potts-v1`

Reviewed candidate: `63a3c4e58d3fb5f15fd596a6248bc8729e0c5b00`

Reviewed parent: `101bd4d6dcd9fa14075956c399aa701cfa018658`

Status: complete fresh-context read-only exact-commit review

Verdict: **Blocked — one P0 finding**

## 1. Verdict

The exact candidate does not clear G5-L2Q. One reproducible backend semantic error remains:
state-stage failures are selected across reachable action/effect launches by kernel launch order,
not by the accepted canonical request order. The sequential authority and the shared
KernelAbstractions CPU path can therefore expose different qualified failure sources, action
identities, and anchors for the same transaction.

The previous P1 scalar whole-domain/request-by-site evaluator-scan finding is cleared. The bounded
compilation and test-cost evidence does not support another P0 or P1 finding. There are no P2 or P3
findings requiring disposition in this review.

The candidate must return to the state-stage status-reduction boundary, add the exact regression
specified below, rerun the affected focused/Core tests and explicit Metal lifecycle qualification,
and receive a fresh exact-commit rereview. Work must stop before R2, G6, proof-model migration, or
another lifecycle-language expansion.

## 2. Review basis and exact-tree checks

The review treated the implementation claims and the prior finding as hypotheses. It independently
inspected the amended G5-L2Q gate, the compiler-construction contract, the asynchronous settlement
and lifecycle mask-pipeline decisions, the production execution path, backend-neutral conformance
bodies, CPU and Metal profiles, and the bounded compilation/test-cost handoff.

Before this review result was recorded:

- `HEAD` was exactly `63a3c4e58d3fb5f15fd596a6248bc8729e0c5b00`;
- its parent was exactly `101bd4d6dcd9fa14075956c399aa701cfa018658`;
- the worktree was clean;
- `git diff --check HEAD^ HEAD` passed;
- the case-insensitive production/test phase-label inventory was clean;
- no G6 or proof-model work was present; and
- the sole production `KernelAbstractions.synchronize` and device-to-host materialization authority
  remained `lib/CorePotts/src/execution/program_settlement.jl`.

The reported exact-candidate evidence was green before the independent counterexample:

- fast CPU profile: 426/426 assertions;
- CorePotts package tests and Aqua checks;
- complete real Metal qualification with `Metal.allowscalar(false)`; and
- full Metal wall time: 668.15 seconds.

Passing suites do not override the reproducible canonical-failure counterexample below.

## 3. Sole finding

### P0-01 — state failure selection follows action/effect launch order

#### Governing invariant

The accepted lifecycle mask-pipeline contract requires request-local failures to reduce by
canonical request order, never by kernel launch order. Sequential and backend execution consume one
scientific plan and must expose the same exact device-sized offender status. The host cannot
reinterpret or choose a different offender at settlement.

#### Production evidence

The sequential authority stages state by traversing selected requests in
`workspace.canonical_order` and stops on the first failed request:

- `lib/CorePotts/src/execution/lifecycle_validation.jl:247-269`.

The repaired backend correctly assigns one selected request to each KernelAbstractions work item
and gives each request a private candidate-status slot:

- `lib/CorePotts/src/execution/lifecycle_backend_kernels.jl:415-445`.

However, host orchestration traverses the fixed state-action list from `Initialize` through
`TransformDaughters` and `RedrawDaughters`, then traverses reachable structural effects. After each
reachable action/effect pair it immediately reduces candidate status and stamps the sticky global
state-stage failure:

- action order: `lib/CorePotts/src/execution/lifecycle_backend_enqueue.jl:249-261`;
- reachable action/effect launch: `lib/CorePotts/src/execution/lifecycle_backend_enqueue.jl:264-288`;
- per-pair reduction and stamp: `lib/CorePotts/src/execution/lifecycle_backend_enqueue.jl:289-290`.

The reducer itself traverses canonical requests, but it runs before later action/effect pairs have
executed:

- `lib/CorePotts/src/execution/lifecycle_backend_kernels.jl:325-339`.

Once that reduction publishes one candidate failure into the global workspace status, sticky
backend gating prevents a canonical-earlier request belonging to a later action/effect pair from
executing. Canonical traversal inside each pair therefore cannot establish canonical ordering
across pairs.

#### Reproduced counterexample

A fresh adversarial fixture selected two nonconflicting requests at the same MCS. Both failed in
`LifecycleStageState` with `LifecycleDetailNonfiniteResult`:

1. the canonical-first request was a `Divide` whose `TransformDaughters` evaluator was nonfinite;
2. the canonical-later request was a `CreateCell` whose `InitializeFrom` evaluator was nonfinite.

The exact outputs were:

| Authority | Qualified source | Action identity | Anchor | Selected semantic request |
|---|---:|---:|---:|---|
| sequential reference | 9 | `0xea46ec706dc4f5b7` | 1 | canonical-first `Divide` / `TransformDaughters` |
| KernelAbstractions CPU | 8 | `0x562f8f432defaea3` | 3 | canonical-later `CreateCell` / `InitializeFrom` |

The scientific bank remained unpublished in both executions, but the public failure status and
failure report named different scientific offenders. This is a scientific-semantic backend
divergence, not a diagnostic-polish issue, and is P0 under the G5-L2Q severity rules.

#### Required repair boundary

Preserve the one-request-per-work-item repair and the narrowed state-launch payload. Restore one
canonical cross-action/effect failure authority before stamping sticky global status. An acceptable
repair may defer global reduction until every reachable state action/effect launch has produced
request-local status, or retain enough bounded per-request rank to reproduce canonical request and
state-rule ordering. It must not:

- make launch order a semantic priority;
- replace the sequential authority with the backend's current order;
- add host polling, synchronization, or fallback;
- add another evaluator or state executor; or
- weaken exact source/action/anchor attribution.

The repair must also ensure that multiple failing rules within one request preserve the same
canonical state-rule offender as the sequential authority rather than merely moving the
cross-request mismatch.

## 4. Prior P1 disposition

The previous P1 finding was a serial whole-domain scan, repeated per selected request and evaluator,
inside a one-work-item state kernel. It is **cleared** on this candidate:

- `_stage_lifecycle_state_backend_kernel!` maps one request to each global work item;
- candidate failure status is request-local before deterministic reduction;
- `planned_site_request` gives creation ownership lookup constant-time site membership;
- planned cell volume reads the incrementally staged volume tracker;
- planned moments/center/elongation read staged volume and moment trackers; and
- planned surface starts from the authoritative qualified surface tracker and applies only bounded
  request-local directed-edge deltas.

The relevant implementation is in:

- `lib/CorePotts/src/execution/lifecycle_workspace.jl`;
- `lib/CorePotts/src/execution/lifecycle_backend_control.jl`;
- `lib/CorePotts/src/execution/lifecycle_backend_kernels.jl`;
- `lib/CorePotts/src/execution/lifecycle_commit.jl`; and
- `lib/CorePotts/src/execution/lifecycle_context.jl`.

The combined CPU/Metal planned-tracker fixture proves exact parent/daughter results of `10.0f0` and
`20.0f0` for a single state evaluator containing volume, surface, and elongation. The broad
state-policy fixture remains separate and continues to cover the closed state-action families.

## 5. Compilation and specialization disposition

The required bounded handoff separates package/precompile, completion, lowering, initialization,
backend adaptation, first kernel compilation, first synchronization, warm enqueue/execution, and
fixture repetition. Those measurements do not support another gate blocker.

### Host/compiler measurements

For the volume, surface, elongation, and combined planned-tracker fixtures:

- warm completion: 8.6-11.2 ms;
- warm compile/lower: 41.5-84.5 ms;
- warm initialization: 0.041-0.098 ms; and
- repeated optimized `code_typed` inspection: approximately 0.8-0.9 ms.

The combined optimized state-stage IR is 15,252 bytes versus 13,420 bytes for volume alone, a
1.137x ratio rather than a volume-by-surface-by-elongation Cartesian product.

### Payload and evaluator-bank structure

The narrowed state payload reduces the representative concrete runtime type description from 6,405
to 1,003 characters, approximately 6.4x. It removes checkerboard claims, candidates,
dispositions, reports, stage buffers, and complete workspace state from this kernel.

The state payload still carries the completed model's full lifecycle evaluator storage. The broad
fixture has 43 evaluator slots, 36 state rules, 11 state actions, 12 reachable action/effect pairs,
and one division variant. Reachability masks enqueue only those 12 pairs and the one admitted
division variant. Existing structural tests establish that names, capacities, slots, declaration
order, and homogeneous occurrence growth remain value-level.

The current measurements do not show an unacceptable action-by-effect-by-evaluator generated-code
cross-product. Further evaluator-bank slicing is therefore measurement-only and is not required by
this review. If latency remains material after P0-01 is repaired, the next evidence is a per-kernel
Metal compilation/cache-family inventory, not speculative annotations or a whole-program payload
rewrite.

### Real Metal measurements

For the already-precompiled minimal combined fixture with scalar device indexing disabled:

- first completion: 13.337 s;
- cold CPU setup/compile, initialization, adaptation: 27.570 s;
- first enqueue including Metal kernel compilation: 22.232 s;
- first synchronization/completed execution: 3.13 ms;
- repeated setup: 0.190 s;
- warm enqueue: 2.94 ms; and
- warm synchronization/completed execution: 0.682 ms.

These numbers identify cold Julia/backend compilation rather than warm scientific execution as the
dominant cost. No ordinary-CI timing threshold is warranted.

## 6. Test-cost and guarantee ownership disposition

The measured 426-assertion fast CPU profile took 377.5 seconds. Its principal owners were:

| Owner | Time | Distinct guarantee |
|---|---:|---|
| descriptor boundary | 19.87 s | external lowering, handles, adapted storage |
| checkerboard conformance | 30.69 s | CPU backend semantics and launch boundaries |
| relationship conformance | 32.50 s | packed relationships and backend equality |
| surface conformance | 16.18 s | generic surface tracking and recomputation |
| lifecycle settlement | 51.08 s | enqueue/settlement, exact failure MCS, consumers, allocation |
| compiler adversarial boundaries | 134.02 s | unbypassable evaluation, ownership and extension rejection |
| lifecycle compiler | 76.56 s | closed taxonomy, diagnostics, reachability and specialization |
| checkpoint continuation | 16.49 s | replay and compatibility rejection |

The compiler-heavy fixtures mostly construct distinct invalid or adversarial programs; their cost
does not establish repeated expensive execution without a distinct guarantee. The 668.15-second
Metal suite is an explicitly requested backend qualification profile covering checkerboard,
surface, settlement, sticky capacity failure, public SciML execution, every admitted policy family,
external operations, conflict behavior, and no scalar fallback. It is not an everyday CI profile.

No test should be deleted to repair P0-01. Safe cost work remains limited to measured immutable
completed/compiled fixture sharing while independently initializing mutable runtime state. The
optimized-IR scale stress remains in the explicit specialization qualification script.

## 7. Required regression and qualification

Before a repaired candidate can be rereviewed, it must add one focused two-failure fixture that:

1. creates two nonconflicting selected requests in one lifecycle boundary;
2. places the canonical-first failure in a later state action/effect launch than the
   canonical-later failure;
3. proves sequential and KernelAbstractions CPU status equality for code, exact MCS, stage,
   qualified source, action identity, anchor, detail, and capacity fields;
4. proves the previously published ownership, kinds, generations, trackers, relationships, and
   descriptor state remain unchanged;
5. proves declaration permutation cannot change the selected offender; and
6. runs the same canonical-status rule on real Metal with `Metal.allowscalar(false)`.

The repair then reruns only the affected focused fast/Core tests and the explicit Metal lifecycle
qualification. It does not require repeating unrelated compile-time experiments or creating a new
evidence system.

## 8. Stop boundary

This review records a **Blocked** G5-L2Q verdict only. It authorizes correction of P0-01 at the
existing state-stage request-local status and canonical-reduction boundary, its focused regression,
and the required CPU/Metal requalification.

It does **not** authorize:

- R2 or a whole-boundary rereview;
- G6 work;
- proof-model migration;
- Wortel, Merks, focal-point, or Act reconstruction;
- new lifecycle vocabulary or structural effects;
- a second evaluator or duplicate executor;
- host fallback, polling, or per-stage synchronization;
- speculative evaluator-bank or whole-program payload refactoring;
- deletion of scientific, failure, settlement, extensibility, inference, allocation, checkpoint,
  replay, CPU, or Metal guarantees; or
- timing thresholds in ordinary CI.

After the bounded repair and exact-commit rereview, work must again stop for owner review before any
later handoff.
