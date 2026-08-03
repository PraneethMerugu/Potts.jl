# G5-L2Q Sequential Lifecycle Quality Gate

Date: 2026-08-02

Branch: `codex/symbolic-potts-v1`

Placement: after G5-L2 and before G5-L3

Status: owner-requested gate design; execution waits for a complete G5-L2 candidate

## Purpose

G5-L2 adds the first complete production lifecycle transaction runtime. That is the dangerous
point at which a correct sequential implementation can accidentally become a second compiler,
a mechanism-specific executor, or a body of duplicated mutation logic that checkerboard and GPU
work later reproduce.

`G5-L2Q` is one bounded, fresh-context, read-only quality review of the exact clean G5-L2
checkpoint. It has three mandatory lenses:

1. code quality;
2. architectural quality; and
3. production and test DRYness.

The reviewer returns one severity-ranked report and one gate verdict. This is not a new product
phase, a documentation gate, a performance campaign, or a replacement for R2. G5-L3 cannot begin
until G5-L2Q clears.

## Governing question

> Is the complete sequential lifecycle implementation a clean, single-authority realization of
> the accepted transaction architecture that can be shared by checkerboard and device execution,
> without duplicating semantics or privileging biological mechanisms?

## Entry conditions

The gate may start only when all of the following are true:

- G5-L1 remains green and its compiler/runtime stop boundary has not been bypassed;
- all five accepted lifecycle effects execute through the sequential CPU reference;
- snapshot-relative planning, filtering, conflict resolution, capacity preflight, staged commit,
  publication, status translation, tracker repair, relationship consequences, and checkpoint
  reconstruction are implemented for the accepted G5-L2 scope;
- one frozen `max_cells` value sizes all cell identity/state/transaction storage before execution;
  the sequential path never resizes, and exhaustion returns `CellCapacityFailure` without partial
  publication;
- the focused lifecycle compiler and sequential transaction suites pass;
- the ordinary package suite passes on the exact candidate, or every unrelated failure is
  reproduced and explicitly classified before review;
- `git diff --check` passes and the worktree is clean; and
- the handoff names the exact candidate commit and the G5-L1 base commit.

An incomplete implementation is returned to G5-L2 rather than reviewed speculatively.

## Required reviewer inputs

The reviewer receives:

- CCV1-027 and the accepted lifecycle-language decisions;
- the G5-L1 checkpoint `eadd4ca` and exact G5-L2 candidate;
- the candidate diff and source tree;
- focused test commands and their measured wall times;
- the ordinary package-test result; and
- a short implementation claim map naming the owner of normalization, analysis, transaction IR,
  planning, conflict resolution, commit, publication, status translation, and reconstruction.

Implementation claims are hypotheses to challenge, not evidence to accept.

## Lens A — architectural quality

The review MUST answer each question with code evidence.

1. Is there exactly one production route from a completed lifecycle statement and frozen callable
   closure to transaction IR, sequential evaluation, a validated plan, and staged publication?
2. Does the runtime consume compiler-owned qualified identities, analyzed policies, bounds,
   capabilities, and footprints rather than rediscovering them from symbolic names or statement
   syntax?
3. Are immutable pre-lifecycle snapshots, request emission, validation/filtering, conflict
   selection, allocation, policy evaluation, commit, invariant validation, and publication visibly
   separate responsibilities with one owner each?
4. Does CorePotts execute generic structural descriptors and policies without branches for Wortel,
   Merks, focal-point plasticity, Act, or another biological mechanism?
5. Are the five closed lifecycle effects expressed around reusable structural primitives, with
   effect-specific dispatch only where the accepted structural algebra truly differs?
6. Do external registered trigger, placement, partition, and state-transform operations receive
   the same frozen resolution, ABI validation, inference, diagnostics, and sequential execution as
   package operations without central executor edits?
7. Are qualified statement/resource identities authoritative after surface capture, with names,
   IDs, generations, slots, capacities, occurrences, and priorities remaining value-level?
8. Does the transaction IR contain only immutable, concrete, backend-adaptable data and callable
   values required by the model, with no live-registry lookup, host closure, symbolic tree, or
   arbitrary callback in execution?
9. Are cell, ownership, state, relationship, tracker, RNG, and checkpoint changes published by one
   atomic transaction authority rather than independent subsystems that can partially commit?
10. Can G5-L3 reuse the transaction IR and semantic planning/commit contracts without copying the
    sequential scientific rules, while G5-L2 avoids speculative checkerboard or GPU machinery?
11. Does folder and module ownership make compiler stages and runtime responsibilities legible,
    with no lifecycle catch-all file or dependency cycle becoming the de facto architecture?
12. Has G5-L2 remained inside CCV1-027, without new lifecycle vocabulary, proof-model migration,
    G6 APIs, or device claims?
13. Are library and test filenames, modules, types, functions, constants, fields, fixtures,
    diagnostics, testsets, and inspection objects free of implementation-phase labels such as
    `G5`, `L2`, `R2`, or a numbered `Phase`? Phase labels belong only to specifications, audits,
    archived evidence, and development history; they must not leak into executable source or test
    vocabulary.

## Lens B — code quality

The review MUST inspect production code, not infer quality from passing tests alone.

1. Are warm transaction paths concretely inferred, bounded, and free of accidental allocation,
   dynamic dispatch, abstract containers, exception-driven control flow, and scalar global scans?
2. Do constructors and lowering make invalid transaction IR states unrepresentable where
   practical, with remaining runtime validation explicit and deterministic?
3. Are functions and types cohesive enough that their invariants can be stated locally, without
   arbitrary line-count limits or abstraction-for-abstraction's-sake?
4. Are public, package-public, and private boundaries intentional, with no reliance on non-public
   dependency APIs, method piracy, compiler-name heuristics, or unowned extension hooks?
5. Does status production have one bounded device/engine representation and one host translation,
   with stable diagnostics and no alternate exception semantics?
6. Are resource ownership, aliasing, mutation, synchronization, and lifecycle of reusable
   workspaces explicit?
7. Are canonical ordering and equality rules implemented once and independent of declaration,
   tuple, grouping, allocation, and launch order?
8. Are comments and names used to preserve non-obvious invariants and scientific meaning rather
   than narrate syntax or conceal unclear ownership?
9. Do package-quality checks, explicit imports, ambiguity checks, and relevant lint-like structural
   tests pass without suppressing legitimate findings?
10. Is sequential code written as the reference execution of shared semantics rather than as a
    disposable special case that later engines must reinterpret?

## Lens C — semantic and test DRYness

DRYness means one authority per rule and the cheapest test owner per failure signal. Similar syntax
or an intentionally independent oracle is not automatically duplication.

The review MUST:

- trace snapshot construction, request canonicalization, filtering, conflict selection, capacity
  preflight, ID/generation allocation, state policies, relationship consequences, tracker repair,
  invariant checks, publication, status translation, RNG addressing, and checkpoint
  reconstruction to exactly one production owner each;
- identify any second production evaluator, planner, mutation path, recomputation path, or
  hand-coded effect branch that can disagree with the canonical authority;
- verify that inspection and diagnostics consume analyzed or lowered facts rather than rebuilding
  executable semantics;
- distinguish shared helpers from abstractions that erase important phase or ownership boundaries;
- produce a guarantee-to-test ownership map for compiler admission, each lifecycle effect,
  snapshot semantics, conflict and capacity behavior, failure atomicity, state/relationship/tracker
  recomputation, replay/checkpoint, external operations, inference, allocation, and specialization;
- identify repeated `complete`, `compile`, `init`, transaction, checkpoint, and replica work that
  protects no distinct boundary or independent oracle;
- share immutable fixtures and backend-neutral conformance bodies where safe, without introducing
  order dependence or mutable global test state; and
- preserve independent recomputation and scientific oracles even when their intentional semantic
  duplication costs more than a production-derived assertion.

The reviewer MUST recommend the smallest standard-Julia partition that retains all accepted
signals:

1. a focused G5-L1/L2 inner loop;
2. ordinary `Pkg.test()` integration coverage; and
3. explicitly requested later qualification for optimized IR, scale growth, statistics, and real
   GPU backends.

No freshness file, stored pass artifact, renewed evidence hash, or second test framework may be
introduced.

## Mandatory probes

The gate reuses production tests and small adversarial fixtures. At minimum it MUST establish:

1. all five effects use the same request-to-publication pipeline;
2. one downstream module's lifecycle operations execute without editing the central compiler or
   executor, and a late registry change cannot alter an already completed model;
3. declaration permutation cannot change deduplication, filtering, conflict winners, allocation,
   RNG addresses, state, relationships, trackers, or status;
4. an inadmissible higher-priority request cannot suppress a valid competitor;
5. capacity, generation, evaluator, footprint, and invariant failures expose no partial state;
6. ownership, state, relationships, trackers, and generations match independent recomputation
   after accepted create, remove, transition, divide, and retire transactions;
7. checkpoint restoration reproduces uninterrupted sequential continuation;
8. the steady-state bounded transaction path has an explicit inference and allocation witness;
9. repeated value-level statements and capacities do not create unjustified structural
   specialization; and
10. inspection and diagnostics report the same qualified transaction facts the executor consumes.
11. a case-insensitive inventory of `src/`, `lib/CorePotts/src/`, `test/`, and
    `lib/CorePotts/test/` filenames and declared identifiers contains no milestone/phase label; any
    textual occurrence in executable source or tests is inspected and removed unless it describes
    an external scientific term rather than the development process.

The capacity probe MUST cover an exact-fit batch and a one-slot-overflow batch, prove that no CPU
or GPU-facing storage grows after initialization, and prove that the overflow status is translated
only after the prior published state remains bitwise unchanged.

These probes SHOULD share fixtures with the existing G5-L1/L2 suites. The reviewer reruns the
focused gate and independently inspects decisive IR/inference evidence. A second complete package
run is not required merely for ceremony when the exact candidate's ordinary suite already passed.

## Severity and clearance

- **P0:** scientific-semantic error, loss of atomicity/replay, unsafe mutation, or an invalid
  lifecycle result that can be published.
- **P1:** second production authority; mechanism-specific core branch; live-registry or symbolic
  execution bypass; unbounded or uninferred warm path; architecture that requires duplicating
  semantics in G5-L3; ambiguous ownership at a mutation/publication boundary; missing practical
  focused test path; or repeated expensive test execution with no distinct guarantee.
- **P2:** localized organization, naming, encapsulation, low-cost duplication, or missing focused
  assertion that does not currently threaten semantic authority.
- **P3:** optional polish with no correctness, extensibility, performance, or maintenance impact.

G5-L2Q clears only with:

- zero P0 findings;
- zero P1 findings;
- every P2 assigned a bounded disposition and earliest owning checkpoint;
- an explicit `Clear` verdict for all three lenses; and
- confirmation that the candidate contains no G5-L3, G5-L4, G6, or proof-model work.

A blocker returns implementation to the earliest owning G5-L1 or G5-L2 boundary. Repairs receive
focused regression tests and one fresh review of the repaired exact commit. They do not trigger a
new interview or broader specification cycle unless the repair requires changing an accepted
semantic decision.

Clearance authorizes G5-L3 only. It does not clear R2, authorize GPU claims, open G6, or permit
Wortel/Merks migration.

## Anti-expansion rules

G5-L2Q MUST NOT require:

- checkerboard correctness, GPU execution, vendor hardware, or long performance benchmarks;
- polished documentation, migration wrappers, compatibility aliases, or proof models;
- arbitrary coverage percentages, file-size limits, type-count limits, or style-only rewrites;
- a general transaction/query/effect language beyond CCV1-027;
- replacing clear finite dispatch with a speculative abstraction;
- deleting independent oracles to make tests look DRY;
- rerunning the complete suite multiple times without a changed failure surface; or
- an evidence ledger, freshness policy, or new CI service.

The gate exists to make the next engine reuse a trustworthy architecture, not to enlarge V1.
