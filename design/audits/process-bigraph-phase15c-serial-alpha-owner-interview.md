# ProcessBigraphs Phase 15.C Serial-Alpha Owner Interview

Status: Complete; all 64 owner decisions resolved

Date: 2026-07-26

Authority:

- [Decision 0034](../../spec/decisions/0034-process-bigraph-runtime-platform.md)
- [Decision 0036](../../spec/decisions/0036-algebraicjulia-process-bigraph-foundation.md)
- [Decision 0037](../../spec/decisions/0037-process-bigraph-open-composition.md)
- [ProcessBigraphs runtime semantics](../../spec/process-bigraph-runtime-semantics.md)
- [ProcessBigraphs parity registry](../../spec/process-bigraph-parity-registry-v1.toml)

This interview freezes every owner choice required before Phase 15.C implementation. It does not
claim that any Phase 15.C capability had been implemented or qualified at interview time. Option A
was the recommendation for every question, and the owner selected A for all eight questions in all
eight rounds. C0--C7 subsequently passed through implementation PR #24 and closure-attestation
PR #25.

The accepted normative result is
[Decision 0038](../../spec/decisions/0038-process-bigraph-serial-alpha.md). The executable boundary
and ordering are frozen by the
[Phase 15.C plan](process-bigraph-phase15c-serial-alpha-plan.md) and machine-readable
[entry contract](../../spec/process-bigraph-phase15c-entry-v1.toml).

## Round 1: 15.C0 closure contract

1. **A.** Phase 15.C qualifies an immutable-topology serial internal alpha. Dynamic rewriting,
   parallel executors, scientific adapters, GPU execution, and public release remain later work.
2. **A.** The phase uses an explicit machine-readable registry allowlist. It neither substitutes a
   smaller convenient subset nor absorbs every pinned-parity row.
3. **A.** The required capability set is the complete serial-semantic set: scheduler, temporal
   processes, reactive steps, fixed-structure iteration, update algebra, continuations, settled
   checkpoints, semantic RNG, observers, transactional failure, serial executor, multirate input
   semantics, and independent Julia oracle.
4. **A.** Dynamic topology, AlgebraicRewriting, Threads, Dagger, device execution, SciML and
   scientific adapters, Potts cutover, upstream Python execution, and public release are hard
   exclusions.
5. **A.** Phase 15.C freezes semantic identities and observable behavior while permitting
   constructor spelling to improve before public release.
6. **A.** Targeted behavioral rows require production evidence plus independent-oracle evidence.
   Phase 15.A and 15.B structural rows retain their direct evidence unless an oracle comparison is
   semantically applicable.
7. **A.** Implementation is strictly gated:
   `15.C0 -> 15.C1 -> 15.C2 -> 15.C3 -> 15.C4 -> 15.C5 -> 15.C6 -> 15.C7`.
8. **A.** Development remains on package version `0.3.x`. A successful closure-attestation change
   advances the internal package identity to `0.4.0` without publishing it.

## Round 2: 15.C1 production serial scheduler

9. **A.** `SerialExecutor` is the explicit execution policy and `SerialRuntime` contains mutable
   execution state. Execution operations dispatch through the executor boundary.
10. **A.** The scheduler selects the minimum exact next deadline. Every process due at that time
    reads one immutable common snapshot and publishes through one atomic reconciliation.
11. **A.** An adaptive invocation may propose an exact next deadline. Validation and publication of
    that deadline are atomic with state and continuation.
12. **A.** Horizon policies are explicit `exact` and `stop_prior` choices. Exact mode supplies
    actual elapsed partial intervals only to processes declaring support and otherwise rejects
    before mutation.
13. **A.** Declared acyclic reactive layers run after a temporal batch. Only steps whose declared
    inputs changed repeat, until deterministic quiescence or a fingerprinted bound.
14. **A.** A cycle is legal only inside a named, fingerprinted iterative region with deterministic
    order and either a hard bound or declared convergence rule.
15. **A.** Exact empty-time advancement may publish an unchanged settled snapshot at the requested
    time without inventing a process event or consuming RNG.
16. **A.** Every committed batch has a canonical event record containing time, ordinal, due
    identities, step activations, iteration outcomes, and result fingerprints. Declaration and
    execution order remain nonsemantic.

## Round 3: 15.C2 semantic RNG

17. **A.** The core RNG is counter-based and addressed semantically rather than through a shared
    mutable stream or task completion order.
18. **A.** A draw address contains the model fingerprint, normalized root seed, process identity,
    logical time, event identity, lineage identity, stable draw site, and explicit draw index.
19. **A.** Process authors request draws through the invocation context using stable named sites and
    explicit indices. Source locations and call order never define identity.
20. **A.** The core uses a pinned and versioned counter algorithm suitable for future CPU/device
    reproduction. Algorithm and address-schema versions enter fingerprints and checkpoints.
21. **A.** Core integer, bit, and uniform draws are exact. Transformed distributions and external
    solvers declare exact, numerical, or statistical replay honestly.
22. **A.** A solver-owned stateful RNG is permitted only through a declared continuation carrying
    its algorithm, version, state, replay class, and invalidation rules.
23. **A.** A failed unpublished event consumes no RNG identity. Explicit retry from the unchanged
    stable boundary receives the same addresses and values.
24. **A.** Observers cannot consume model RNG. Stochastic analysis uses a separate declared
    namespace that cannot alter model draws or simulation results.

## Round 4: 15.C3 observation and continuation

25. **A.** Observers form a declarative plan registered before execution with stable identities,
    projections, schedules, schemas, and required or optional delivery policy.
26. **A.** Observers see only immutable candidate snapshots at declared settled boundaries. They
    cannot observe in-flight deltas, partial step layers, or mutable continuation state.
27. **A.** Each observer receives only declared paths and metadata through a read-only projection.
    Mutation attempts fail deterministically.
28. **A.** Required in-memory observation records are computed and validated before publication.
    State, clocks, continuations, and records become visible together or not at all.
29. **A.** Files, databases, services, and other external effects are separate non-atomic emitters
    with explicit retry and idempotency behavior. The core does not claim external atomicity.
30. **A.** Observation choices do not alter the scientific model fingerprint. A separate runtime
    and observation fingerprint records the observation plan and policies.
31. **A.** Every stateful process, step, and observer declares a typed continuation specification
    with validation, canonical encoding, fingerprinting, restore, and invalidation rules. Arbitrary
    untracked `Any` continuation is not alpha-qualified.
32. **A.** Restore fails closed unless owner identity, continuation schema, semantic implementation
    version, schedule law, and relevant contracts match. Migration requires an explicit registered
    migration.

## Round 5: 15.C4 failure and checkpoint completion

33. **A.** A stable checkpoint includes committed state, exact time, event ordinal, process and step
    clocks, typed continuations, semantic RNG identity and version, observer positions, structural
    epoch identity, and relevant fingerprints.
34. **A.** The phase defines a deterministic, versioned logical checkpoint envelope with canonical
    encode and decode independent from Julia object serialization. Storage backends remain
    extensions.
35. **A.** The already attested checkpoint-v1 reader remains supported. New information uses a
    distinct version; no heuristic conversion or mutation of v1 is permitted.
36. **A.** Failure injection covers process invocation, result validation, reconciliation, step
    execution, continuation validation, required observation, checkpoint capture, and record
    publication.
37. **A.** A failed event exposes no candidate state, clock, continuation, RNG, observer position,
    or required record. Earlier settled commits remain valid.
38. **A.** Failures are versioned structured values containing stage, owner, time, event identity,
    last stable fingerprint, semantic cause code, and retry classification without mutable runtime
    objects.
39. **A.** The serial alpha is deterministic fail-stop and performs no silent retry. Explicit retry
    may begin from the unchanged stable boundary; automated retry remains later executor work for
    declared pure and idempotent tasks.
40. **A.** Phase 15.C supports exact compatible serial restore only. Cross-backend logical import
    and general schema migration require separate later qualification.

## Round 6: 15.C5 independent Julia oracle

41. **A.** The oracle is a test-only independent Julia module. Production `ProcessBigraphs` never
    depends on it.
42. **A.** Production and oracle may share neutral machine-readable fixtures and result schemas,
    but the oracle cannot call production scheduling, reconciliation, RNG, continuation,
    observation, checkpoint, fingerprint, or runtime implementations.
43. **A.** The oracle uses deliberately small independent records, tables, and loops optimized for
    reviewability rather than performance or production API similarity.
44. **A.** Oracle scope covers exact time, event selection, same-time visibility, partial
    intervals, adaptive deadlines, reactive steps, admitted iteration, update laws, continuations,
    semantic RNG, observers, failure atomicity, and settled restart.
45. **A.** Every oracle rule cites a pinned source location or explicit Julia decision. A
    source/code/test disagreement becomes a recorded discrepancy decision.
46. **A.** Core Phase 15.C comparisons are exact. Numerical and statistical comparisons remain for
    explicitly declared later adapters.
47. **A.** Generated tests use recorded seeds, bounded model sizes, deterministic reproduction and
    shrinking, and retained minimal counterexamples.
48. **A.** CI rejects forbidden oracle imports and calls and runs mutation-sensitivity fixtures
    proving detection of perturbed scheduler, update, RNG, failure, and checkpoint behavior.

## Round 7: 15.C6 qualification matrix

49. **A.** The exact target allowlist is:
    `canonical-state-serialization`, `temporal-process-protocol`,
    `ordered-reactive-step-protocol`, `explicit-iterative-constructs`,
    `imminent-event-scheduler`, `adaptive-deadlines`, `versioned-update-algebra`,
    `settled-boundary-checkpoint`, `versioned-process-continuation`,
    `semantic-lineage-rng`, `transactional-failure`, `readonly-observer-protocol`,
    `serial-semantic-executor`, `multirate-input-semantics`, and
    `independent-julia-specification-oracle`. Supporting implemented semantics receive
    independent-oracle evidence where applicable.
50. **A.** Qualification uses small orthogonal non-Potts fixtures: same-time accumulator, multirate
    producer/consumer, adaptive pulse, reactive DAG, iterative region, stochastic branch,
    open-composite fork/join, and observation/failure/restart workflow.
51. **A.** Ordinary typed, direct ACSet, n-ary composition, pairwise grouping, structured-cospan,
    and annotated-wiring authoring must converge on equivalent canonical models, plans, oracle
    inputs, and traces where applicable.
52. **A.** Required methods are finite truth tables, unit tests, production/oracle differential
    tests, property tests, metamorphic invariance, mutation sensitivity, failure injection, and
    checkpoint/restart.
53. **A.** Bounded invariance covers declaration and ACSet order, composition grouping, process
    invocation order, dictionary order, RNG request order, restart boundary, observer selection,
    and retry attempt.
54. **A.** Every reachable settled boundary in every bounded fixture is a restart cut. Resumed and
    uninterrupted state, clocks, continuations, RNG, observation, failure, and remaining traces
    must match.
55. **A.** Qualification enforces no runtime ACSet traversal, structure-dependent hot-path
    allocation, hidden transfer, or asymptotic regression. Measurements are recorded without a
    fastest-runtime claim.
56. **A.** A dedicated required checker, independent-oracle lane, package lane, machine-readable
    evidence manifest, exact assertion counts, source locations, and commit/tree provenance are
    mandatory.

## Round 8: 15.C7 internal-alpha closure

57. **A.** Internal alpha is an all-or-nothing gate. No targeted partial row, missing oracle
    comparison, untested restart cut, failure stage, checker, package test, or required CI result
    may be waived.
58. **A.** Registry promotion preserves PB0, Phase 15.A, and Phase 15.B evidence history and adds
    explicit Phase 15.C implementation and independent-oracle status.
59. **A.** Closure is two-stage. The implementation PR produces and passes a CI-generated candidate
    artifact. A second closure-attestation PR records the exact implementation merge commit,
    qualified head and tree, CI run, assertion totals, and limitations. Phase 15.C closes only
    after the attestation passes and merges.
60. **A.** The package advances from `0.3.x` to internal `0.4.0` only in the successful
    closure-attestation PR and is not published.
61. **A.** Internal-alpha documentation covers ordinary authoring, process authoring, scheduling,
    RNG, observation, continuation, failure, checkpoint, oracle, limitations, and advanced
    AlgebraicJulia use through checked examples.
62. **A.** New scheduler, RNG, observation, checkpoint-codec, and oracle capabilities use focused
    modules. Oversized internals may be decomposed only behavior-preservingly behind the complete
    regression matrix; there is no broad rewrite.
63. **A.** Implementation and attestation PRs receive no CI bypass. Every applicable job and the
    aggregate `Required` gate must pass before squash merge.
64. **A.** The final claim is only a qualified immutable-topology serial internal alpha with
    independent Julia-oracle evidence. Public release, complete parity, dynamic rewriting, Potts
    cutover, adapters, Threads, Dagger, GPU execution, and whole-cell qualification remain open.

## Completion statement

All owner choices required to plan Phase 15.C are resolved. This interview authorizes
specification, planning, entry-enforcement, and later gated implementation work. It does not
authorize weakening the allowlist, substituting direct evidence for the independent oracle,
executing an upstream Python runtime, or claiming that Phase 15.C has begun implementation before
the entry packet passes. That entry packet and the complete implementation/attestation sequence
have since passed; the interview remains the owner-choice authority rather than current status.
