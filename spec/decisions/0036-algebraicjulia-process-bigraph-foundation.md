# Decision 0036: AlgebraicJulia as the ProcessBigraphs Structural Foundation

Status: Accepted

Date: 2026-07-26

## Context

Phase 14.PB0 proved an independent `ProcessBigraphs.jl` package with typed paths, schemas, ports,
exact time, typed deltas, atomic serial commit, capability preflight, and bounded checkpoint/replay.
The next milestone must choose whether AlgebraicJulia is merely an optional representation adapter
or a required architectural dependency.

The owner requires direct use of AlgebraicJulia without an adoption experiment. The owner also
requires comprehensive independent unit and integration evidence rather than installing or
executing Vivarium or the Python Process-Bigraph runtime.

These choices affect structural authority, runtime ownership, identities, persistence, dynamic
rewriting, parity language, dependency policy, and the Phase 15--19 maturity gates. They were
resolved through the accepted 34-choice
[AlgebraicJulia owner interview](../../design/audits/process-bigraph-algebraicjulia-owner-interview.md).

## Decision

### Required AlgebraicJulia roles

1. `ACSets.jl` and `Catlab.jl` become direct `ProcessBigraphs.jl` dependencies when Phase 15
   implementation begins. Accepted compatibility ranges are explicit, and exact resolved versions
   are recorded in evidence.
2. `AlgebraicRewriting.jl` becomes a direct dependency when Phase 16 dynamic structural semantics
   begin.
3. `AlgebraicDynamics.jl` enters in Phase 17 through a weak-dependency extension for suitable
   scientific authoring and solver adapters. It is not a core runtime dependency or execution
   authority.
4. AlgebraicJulia integration is mandatory architecture, not an optional experiment, compatibility
   mirror, or disposable visualization layer.

### Canonical structural model

5. One custom ProcessBigraph ACSet schema is the canonical structural representation. It contains
   composites, nodes, stores, processes, steps, typed ports, links, containment, structural
   schemas, and stable semantic identities.
6. Structured cospans define typed open-composite boundaries and composition. Directed wiring
   diagrams are derived dataflow and visualization views. Neither view is a second canonical model.
7. Ordinary typed Julia constructors and AlgebraicJulia authoring both lower to the identical
   canonical ACSet and canonical fingerprint. Category-theory knowledge is not required for ordinary
   users.
8. Existing PB0 structural structs become ergonomic façades over the canonical ACSet during Phase
   15. After equivalence passes, no permanent parallel structural authority remains.

### Identity and compilation

9. Every semantic composite, node, store, process, step, port, and link has a stable
   ProcessBigraph identity and canonical path.
10. ACSet row numbers and traversal order are storage-local and nonsemantic. They are excluded from
    canonical ordering, fingerprints, RNG addresses, persistence identities, and scientific
    diagnostics.
11. Compilation validates and canonicalizes the authoring ACSet, freezes one immutable structural
    epoch, and produces indexed execution tables plus an exact provenance map.
12. Runtime hot paths do not traverse, match, or mutate the authoring ACSet and do not allocate
    because of AlgebraicJulia structure. They execute ProcessBigraphs-owned compiled storage.

### Runtime authority and data ownership

13. ProcessBigraphs exclusively owns exact time, imminent-event selection, snapshots, invocation
    identities, typed deltas, reconciliation, atomic commit, failure, retry, semantic RNG,
    observation, checkpointing, and replay.
14. AlgebraicJulia owns structural mathematics and validated composition. AlgebraicDynamics and
    AlgebraicRewriting cannot create a second scheduler, state authority, transaction protocol, or
    persistence format.
15. Committed numerical state and backend-resident arrays remain ProcessBigraphs state. The
    canonical ACSet is host-side placement-independent topology and metadata.
16. Every CPU/device bridge remains explicit, bounded, synchronized, and measured. AlgebraicJulia
    adoption does not weaken residency or hidden-transfer rules.

### Structural rewriting

17. ProcessBigraphs exposes typed structural operations such as add, remove, divide, move, and
    rewire. Those operations lower to AlgebraicRewriting rules; arbitrary raw rewrites are not the
    stable biological/runtime API.
18. AlgebraicRewriting may discover candidate matches. ProcessBigraphs assigns semantic match
    identities, validates preconditions, orders conflicts deterministically, and selects the
    committed match set.
19. Rewrites produce a candidate ACSet and may publish only at a settled structural barrier after
    schema, port, identity, lineage, continuation, capability, and conflict validation.
20. A committed rewrite creates a new structural epoch, canonical fingerprint, and identity map.
    Checkpoints are permitted before or after the complete structural transaction, never during
    matching or partial rewrite application.

### Persistence and public API

21. ProcessBigraphs owns a versioned checkpoint envelope containing semantic identities, canonical
    structure and schema fingerprints, committed state, exact time, scheduler and process
    continuation, semantic RNG, observer continuation, structural epoch, and integrity hashes.
22. Raw ACSet or wiring-diagram serialization is optional structural interchange and inspection.
    It is not a runtime checkpoint or continuation contract.
23. Public APIs may accept ACSets and wiring diagrams and expose read-only canonical structure.
    Semantic mutation, compilation, execution, structural commit, and persistence go through
    ProcessBigraphs APIs.
24. Documentation teaches ordinary process/biological authoring first and offers an advanced
    AlgebraicJulia track. Both paths produce the same canonical model.

### Independent conformance without upstream execution

25. CI, tests, examples, attestations, and release tooling do not install or execute Vivarium,
    Process-Bigraph Python, or Bigraph-Schema Python.
26. Exact upstream commits remain pinned source and traceability authorities. Advancing a pin
    requires a registry version change, renewed source audit, and refreshed affected fixtures.
27. Claims use **source-audited feature and semantic parity**. The project does not claim direct
    upstream-runtime equivalence when it deliberately does not execute the upstream runtime.
28. A small checked Julia specification oracle, structurally independent from the production
    executor, computes expected schedules, updates, commits, failures, and traces.
29. Every parity row requires source-located, hand-checkable fixtures or mathematical derivations,
    exhaustive small-domain truth tables where finite, property and metamorphic tests, failure and
    persistence evidence, documentation, and applicable backend evidence.
30. Declaration order, ACSet row numbering, hash-table order, task completion order, worker count,
    path aliases, and equivalent composite parenthesization are nonsemantic and receive randomized
    invariance tests.
31. Failure injection covers projection, invocation, matching, reconciliation, update application,
    structural validation, commit, observation, and checkpoint formation. No failed boundary may
    expose partial committed state or topology.
32. Internal-alpha integration evidence uses non-Potts shared-state multirate, partial-interval,
    fork/join, biochemical regulation, nested open-composite, conflict-heavy update, and
    checkpoint/replay fixtures.
33. AlgebraicJulia conformance covers ACSet schema validity, naturality, isomorphism-invariant
    fingerprints, structured-cospan composition, wiring-diagram equivalence, hierarchy compilation,
    and exact constructor/ACSet round trips.

### Maturity

34. Phase 15 closes the static ACSet-backed serial internal alpha. Phase 16 closes
    AlgebraicRewriting-backed dynamic hierarchy and the Potts adapter internal beta. Later phases
    add AlgebraicDynamics/scientific adapters and alternate executors. Public release still requires
    complete registered parity and the whole-cell-style composite.

This decision amends Decision 0034 wherever that decision requires pinned Python runtime execution
or leaves the AlgebraicJulia structural foundation optional. Decision 0034 continues to govern the
independent package identity, serial semantic authority, Dagger boundary, migration, whole-cell
ladder, and no-public-partial-parity rule.

## Consequences

- Phase 15 includes a real canonical-structure migration, not just additional scheduler features.
- The PB0 behavioral evidence remains valid, but its structural structs are provisional façades
  until they lower through the accepted ACSet schema.
- Catlab or ACSet internal ordering can never leak into simulation meaning.
- The hot numerical data plane remains independent of AlgebraicJulia graph traversal.
- The project can substantiate comprehensive independent semantic compatibility without a Python
  runtime dependency, but must not describe that evidence as live differential equivalence.
- Dynamic structure waits for AlgebraicRewriting-backed Phase 16 transactions rather than being
  improvised in the Phase 15 static alpha.

## Rejected Alternatives

- Optional or experimental AlgebraicJulia integration.
- Two permanent canonical structural models.
- AlgebraicDynamics as scheduler or checkpoint authority.
- Live ACSet mutation during process invocation.
- ACSet row numbers as semantic identities.
- Direct serialization of arbitrary Catlab objects as runtime checkpoints.
- Installing or executing the upstream Python runtime as a test oracle.
- Claiming direct upstream-runtime equivalence without running that runtime.
- Publishing after the static internal alpha.

## Required Evidence

- dependency and compatibility records for every admitted AlgebraicJulia package;
- canonical ProcessBigraph ACSet schema and schema-version tests;
- typed-constructor, ACSet, structured-cospan, and wiring-diagram round-trip identity;
- row-renumbering, isomorphism, declaration-order, and parenthesization invariance;
- compiled-plan provenance and absence of ACSet traversal/allocation in steady-state execution;
- independent Julia specification-oracle truth tables;
- source-located golden fixtures and uncertainty records;
- exhaustive/property/metamorphic/fuzz/failure/restart integration evidence;
- fail-closed absence of Python runtime execution from CI and release tooling; and
- unchanged PB0 behavior and package independence during the Phase 15 migration.
