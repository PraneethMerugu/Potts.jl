# Symbolic Potts V1 lifecycle language — independent review request

Status: ready for fresh-context read-only review  
Review boundary: G5-L0 specification clearance  
Implementation authorization: none

## Review purpose

Determine whether the accepted lifecycle owner decisions have been consolidated into one bounded,
implementable, compiler-neutral, GPU-complete V1-L contract without contradicting the authoritative
V1 construction specification or creating another overengineered subsystem.

The reviewer must not implement, edit production code, migrate proof models, or broaden V1. The
candidate is not authoritative until P0/P1 findings are resolved and the accepted construction spec
is amended once.

## Required reading

Read these files completely:

1. `design/audits/symbolic-potts-v1-lifecycle-language-owner-interview.md`
2. `design/audits/symbolic-potts-v1-lifecycle-language-consolidation-candidate.md`
3. `spec/symbolic-potts-v1-compiler-construction.md`
4. `spec/state-model.md`
5. `spec/lifecycle.md`
6. `spec/randomness-and-reproducibility.md`
7. `spec/decisions/0004-lifecycle-transactions.md`
8. `spec/decisions/0019-property-and-auxiliary-lifecycle-policies.md`
9. `spec/decisions/0006-reproducible-transactions.md`
10. `design/juliagpu-and-performance-programming-standard.md`

Inspect the current implementation at minimum:

- `src/statements/semantics.jl`
- `src/statements/statements.jl`
- `src/completion/completion.jl`
- `src/compiler/host/analysis.jl`
- `src/compiler/lowering/stage_plan.jl`
- `src/compiler/execution/boundary.jl`
- `lib/CorePotts/src/execution/sequential_program.jl`
- `lib/CorePotts/src/execution/stage_runtime.jl`
- `lib/CorePotts/src/execution/checkerboard_program.jl`
- `lib/CorePotts/src/program/runtime.jl`
- `lib/CorePotts/src/program/relationships.jl`
- `lib/CorePotts/src/rng/semantic.jl`
- `test/backend_conformance/g5_relationship_execution.jl`
- `test/backend_conformance/g5_surface_execution.jl`
- `benchmark/backends/metal/runtests.jl`

The reviewer may inspect additional directly relevant files. Historical documents are context, not
permission to expand the accepted construction plan.

## Accepted facts that are not open for preference voting

- V1-L has the five structural effects `CreateCell`, `RemoveCell`, `Retire`, `Transition`, and
  `Divide`; fusion and fragmentation are withdrawn.
- `LifecycleProcess` remains the public statement.
- Triggers and pure policies are symbolically open through frozen registered operations; structural
  mutation is closed.
- All admitted effects and stable built-in policies must function on one real GPU witness before
  the one final R2.
- Sequential and checkerboard CPU share one lifecycle plan; V1-L does not add sequential GPU.
- The default tests stay focused and DRY; expensive compiler/backend qualification is explicit.
- After R2 clears, work stops before G6.

The reviewer may find an accepted fact internally inconsistent or infeasible, but must demonstrate
that with a governing clause and concrete counterexample rather than substituting taste.

## Clarifications to challenge explicitly

Treat the candidate's Section 20 items as hypotheses:

1. singleton `model()` domain;
2. explicit `RetireAtZero()` versus `ForbidExtinction()` kind law;
3. exactly one structural cell effect per process;
4. immutable lifecycle before/after policy views;
5. explicit never-used/active/reusable slot status;
6. concrete frozen constructor defaults; and
7. closed device status categories and stage-owned folder layout.

For each, return one of:

- `Essential clarification` — required to implement an accepted fact;
- `Compatible implementation choice` — valid but not normative;
- `Owner question required` — materially changes scientific scope; or
- `Reject` — contradictory, unnecessary, or unimplementable.

## Required review questions

1. Is the structural algebra closed, sufficient, and free of named biological privilege?
2. Does the extinction law genuinely remove hardcoded retirement rather than move it behind a
   configurable-looking wrapper?
3. Are domains, policies, conflicts, capacity, generation, RNG, and checkpoints exact and mutually
   coherent?
4. Is there one unbypassable symbolic-to-resolved-policy/evaluator path with no live registry after
   completion?
5. Can external pure policies receive equal CPU/GPU/inference/checkpoint treatment without central
   executor edits?
6. Can the transaction be implemented on Metal with bounded workspaces, no host semantic work, and
   honest scientific publication atomicity?
7. Does any requirement force request-times-lattice work, model-identity specialization, dynamic
   dispatch, device exception, or per-MCS allocation?
8. Does the test plan prove each claim without an exhaustive Cartesian matrix, duplicate oracles,
   evidence freshness, or expensive universal CI?
9. Does the folder ownership preserve existing generic evaluator, storage, relationship, tracker,
   RNG, and checkpoint authorities rather than duplicating them?
10. Which exact authoritative clauses must change, and which historical clauses should be marked
    superseded rather than copied?

## Finding standard

Every finding must contain:

- severity `P0`, `P1`, or `P2`;
- candidate clause and governing accepted clause;
- smallest current code/spec location;
- counterexample, failing microfixture sketch, or static proof;
- scientific/compiler/GPU/developer-experience consequence;
- bounded repair; and
- earliest repair checkpoint (`G5-L0` through `G5-L5`).

Severity meanings follow the accepted construction review policy:

- `P0`: scientific corruption, data loss, nondeterministic integrity failure, or direct accepted-
  contract contradiction;
- `P1`: compiler invariant, external extensibility, GPU legality, concurrency, replay, or public
  boundary failure;
- `P2`: important clarity, maintainability, test quality, or bounded performance risk that does not
  invalidate the architecture.

Do not report speculative style preferences as blockers. Do not recommend a general rewrite
language, arbitrary callbacks, fusion/fragmentation, daughter relationship transfer, sequential
GPU, proof-model migration, a second evaluator, or a new evidence system.

## Required output

Return a review document containing:

1. verdict: `Clear`, `Clear with P2 dispositions`, or `Blocked`;
2. accepted-decision traceability audit;
3. disposition of all seven derived clarifications;
4. findings ordered by severity;
5. exact amendment map for `spec/symbolic-potts-v1-compiler-construction.md` and any conflicting
   accepted spec/decision text;
6. bounded implementation-readiness assessment for G5-L1 through G5-L5; and
7. explicit statement whether implementation may begin.

If blocked, stop after the review. If clear, do not code: hand the clearance and amendment map back
for one authoritative consolidation edit.
