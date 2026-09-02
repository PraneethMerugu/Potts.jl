# LM-2B execution-receipt and preparation evidence

LM-2B strengthens the sole `WorkEvent` / `run!` production path. The public
names remain unchanged until the LM-3B identity cutover.

## Runtime contract

- A provider scope is the backend, device, owner task, and its implicitly
  ordered KernelAbstractions queue.
- Every submission receives a monotonically increasing scope ordinal and one
  exact logical receipt.
- An unresolved dependency is admitted only from an earlier ordinal in the
  same scope. A settled-success dependency is admissible from any scope.
  Settled failures and unresolved cross-scope dependencies fail before
  submission.
- The provider queue supplies physical order. LocalWorksets adds no scheduler,
  task graph, native-event abstraction, backend branch, or alternate executor.
- `wait` may synchronize the cumulative provider tail, but settles and
  releases only the requested logical receipt. `waitall` groups scopes and
  reports receipt failures in argument order.
- Semantic and dependency failures are receipt-specific and cached. A provider
  failure poisons only its provider scope.

## Fixed dependency join ABI

The old tuple-shaped dependency gate no longer exists. After the program reset,
each unresolved dependency launches the same one-lane KA kernel:

```text
target execution gate + target lease
+ source execution gate + source lease
→ copy a settled failure into the target gate, or leave it open
```

The join kernel is qualified once whenever the prepared dependency capacity is
positive. Receipt identity, producer program shape, and dependency tuple arity
do not parameterize the device kernel. The physical order is:

```text
program reset → U fixed joins → relationship guards and stage phases
```

where `U` is the number of unresolved admitted dependencies. Settled-success
dependencies contribute zero joins. Canonical inspection reports the static
program count as `base_provider_launch_count`; `inspect(event)` reports `U` as
`dependency_join_count`.

Ordinary CPU tests cover arities 0, 1, 2, 4, and 17; exact counts 1, 2, 4, and
17 for unresolved inputs; zero joins for settled-success inputs; exact failure
and lease behavior; compatible prepared types and enqueue method reuse; and
bounded warm host bookkeeping below the frozen 4096-byte ceiling.

## Preparation and specialization cutover

The preparation regression was addressed by deleting specialization and
analysis authorities rather than caching a second runtime:

- `PreparedWork{Q,L,R}` specializes only on the submission schema, provider
  lane, and prepared runtime. Its semantic plan and workspace ownership root
  are cold fields and do not enter the warm type identity.
- `_StageEvaluation` contains only evaluator, fields, accesses, control, and
  source extent. Publication laws and parameter-slot metadata do not enter the
  common evaluation kernel ABI.
- Candidate publication data, Collect physical plans, and OrderedFold state are
  passed only to phases that use them.
- OrderedFold sorting, duplicate validation, and finalization receive only the
  order law. Its serial recurrence receives only the transition callable.
- `_StageProgramLowering` owns one flat callback-evidence vector. Entries and
  prepared runtime state do not duplicate it.
- One ephemeral planning dictionary memoizes the exact typed compiler analysis
  of evaluators, reductions, grouping and ordering extractors, and OrderedFold
  transitions. Admission, inferred result types, and callback-world facts all
  consume that same analysis.
- The weaker standalone evaluator `code_lowered` probe was deleted; the exact
  source-and-typed-IR analysis is the single callable-admission authority.
- Planning captures the Julia method world before analysis and seals it after
  callback facts are built. Preparation and execution revalidate facts when the
  world advances, before submission or publication.

World invalidation tests cover the Stage evaluator, a transitive evaluator
helper, Reduce operations, ordering extractors, and OrderedFold transitions.

## Physical launch authority

The four-stage synthetic program remains 21 stage-local launches plus one
unconditional program reset, or 22 base provider launches. Relationship
receipt validation is already included in each affected stage's canonical
phase tuple; it is not an extra hidden program-level count. Only unresolved
execution dependencies add the dynamic `U` joins described above.

## Qualification

- Complete ordinary LocalWorksets package suite: pass.
- Focused callback-world protocol tests: 9/9 pass.
- Real-Metal execution receipts: 13/13 pass on the fixed join path.
- Real-Metal Stage families and CPU/Metal inspection parity: 46/46 pass.
- The commands, versions, device identity, counts, and frozen source hashes for
  both current Metal packets are persisted in `lm2b-real-metal-current.toml`.
- Kaimon confirms the final structural ABIs:
  `_StageEvaluation` has fields `(evaluator, fields, accesses, control,
  source_count)`; `PreparedWork` has no callback-evidence field; and
  `_StageProgramLowering` owns `(entries, workspace, callback_facts, world)`.
- The retained packet in `lm2a/compiler-qualified-synthetic-current/` records
  the pre-stabilization source. The post-stabilization current-source
  measurements below were run in fresh Julia subprocesses through the shared
  Kaimon investigation session.

The current-source fresh-process observations are:

| stages | cold host compilation (s) | base launches | warm Julia compilation |
|---:|---:|---:|---:|
| 1 | 2.411 | 2 | 0 |
| 4 | 11.304 | 22 | 0 |
| 8 | 14.110 | 53 | 0 |
| 13 | 15.913 | 90 | 0 |
| 32 | 25.873 | 231 | 0 |

The current source passes the frozen 2.851-second one-stage and 15.047-second
four-stage ceilings. The pre-stabilization raw packet remains retained rather
than relabeled. The ordinary LocalWorksets suite passes 832/832; the current
real-Metal Stage and receipt witnesses pass 46/46 and 13/13.

The root PrecompileTools workload and the removal of fictional KA launch-event
assumptions are independent LM-2D foundation corrections. They do not alter
receipt semantics or create another execution path.
