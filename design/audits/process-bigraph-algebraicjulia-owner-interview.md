# ProcessBigraphs AlgebraicJulia and Independent-Conformance Owner Interview

Status: Complete; all 34 owner decisions resolved

Date: 2026-07-26

This interview amends the ProcessBigraphs architecture before Phase 15. It resolves mandatory
AlgebraicJulia adoption and replaces planned live Python runtime oracles with comprehensive
independent Julia conformance.

The accepted normative result is
[Decision 0036](../../spec/decisions/0036-algebraicjulia-process-bigraph-foundation.md).

## Round 1: Foundation and ownership

1. **A.** `ACSets.jl` and `Catlab.jl` become direct Phase 15 dependencies;
   `AlgebraicRewriting.jl` becomes mandatory in Phase 16; `AlgebraicDynamics.jl` becomes a later
   scientific adapter.
2. **A.** A custom ACSet schema is canonical for composites, processes, steps, ports, stores, place
   hierarchy, and link topology. Typed ProcessBigraphs constructors lower into it.
3. **A.** ProcessBigraphs exclusively owns scheduling, exact time, transactions, reconciliation,
   commit, failure, and restart. AlgebraicJulia supplies validated structure.
4. **A.** ProcessBigraphs owns immutable committed snapshots and backend-resident numerical arrays.
   ACSets hold topology and metadata and change only at structural transaction boundaries.
5. **A.** Ordinary typed Julia constructors and Catlab wiring-diagram authoring lower to the same
   canonical ACSet and fingerprint. Category theory is optional user knowledge.
6. **A.** Accepted compatibility ranges are explicit, exact versions are recorded in evidence, and
   AlgebraicJulia interactions remain behind a narrow owned boundary.

## Round 2: Topology, composition, and rewriting

7. **A.** One integrated ProcessBigraph ACSet contains composites, nodes, stores, processes, steps,
   ports, links, containment, schemas, and stable identities.
8. **A.** Structured cospans express typed open-composite composition; directed wiring diagrams are
   derived process/step dataflow and visualization views.
9. **A.** Stable ProcessBigraph identities and canonical paths are semantic. ACSet row numbers are
   storage-local and excluded from RNG, fingerprints, ordering, and persistence.
10. **A.** The canonical ACSet preserves hierarchy and compiles to an immutable flattened execution
    plan with exact structural provenance.
11. **A.** ProcessBigraphs typed structural operations lower to AlgebraicRewriting rules. Raw graph
    rewriting is not the stable public biological/runtime API.
12. **A.** AlgebraicRewriting may discover candidates; ProcessBigraphs assigns identities, validates
    preconditions, orders conflicts, and selects committed matches.
13. **A.** A rewrite may publish only at a settled structural barrier after complete validation.
14. **A.** Each structural epoch has a canonical fingerprint and identity map. Checkpoints occur
    only before or after the atomic structural transaction.

## Round 3: Independent conformance without running Vivarium

15. **A.** CI, tests, examples, and release tooling never install or execute Vivarium or
    Process-Bigraph Python.
16. **A.** Claims are source-audited feature and semantic parity, not direct runtime equivalence.
17. **A.** A small checked Julia specification oracle remains structurally independent from the
    production executor.
18. **A.** Exhaustive small-domain truth tables plus property and metamorphic tests cover paths,
    schemas, ports, topology, time, scheduling, updates, reconciliation, fingerprints, RNG,
    continuation, and failure.
19. **A.** Expected traces are hand-checkably derived from pinned source semantics, documentation,
    papers, and mathematical definitions with source locations and uncertainty records.
20. **A.** Declaration order, row numbering, hash order, task completion order, worker count, path
    aliases, and equivalent composite parenthesization are mandatory invariances.
21. **A.** Failure injection covers every pre-commit, commit, observation, and checkpoint stage and
    proves absence of partial publication.
22. **A.** Internal alpha requires non-Potts shared-state multirate, partial interval, fork/join,
    biochemical regulation, nested open-composite, conflict-heavy update, and checkpoint/replay
    integration fixtures.
23. **A.** AlgebraicJulia coverage includes schema validity, naturality, isomorphism-invariant
    fingerprints, structured-cospan composition, wiring-diagram equivalence, hierarchy compilation,
    and constructor/ACSet round trips.
24. **A.** Upstream source pins remain exact traceability authorities; advancing one versions the
    registry, renews the source audit, and refreshes affected fixtures.

## Round 4: API, migration, performance, and maturity

25. **A.** Existing typed constructors lower immediately into the canonical ACSet during Phase 15.
    After equivalence passes, no parallel structural authority remains.
26. **A.** `ACSets.jl` and `Catlab.jl` are direct dependencies; `AlgebraicRewriting.jl` becomes
    direct in Phase 16; `AlgebraicDynamics.jl` enters through a Phase 17 weak-dependency extension.
27. **A.** Public APIs accept ACSets and wiring diagrams and expose read-only canonical structure,
    while semantic mutation, compilation, execution, and persistence remain ProcessBigraphs APIs.
28. **A.** Compilation canonicalizes and freezes a structural epoch and produces indexed runtime
    tables with provenance. Hot paths do not traverse the authoring graph.
29. **A.** ProcessBigraphs owns a versioned checkpoint envelope. Raw ACSet JSON is optional
    interchange, not a checkpoint.
30. **A.** AlgebraicJulia runs during authoring, validation, compilation, inspection, and structural
    barriers, not ordinary numerical hot loops.
31. **A.** Topology is host-side placement-independent metadata; compiled numerical state may
    remain CPU- or GPU-resident with explicit measured bridges.
32. **A.** A Phase 17 AlgebraicDynamics extension lowers suitable machines and resource sharers to
    ordinary ProcessBigraphs processes and ports without owning runtime semantics.
33. **A.** Documentation teaches ordinary biological/process authoring first and an advanced
    AlgebraicJulia track second. Both produce identical canonical models.
34. **A.** Phase 15 closes static ACSet-backed serial alpha; Phase 16 closes
    AlgebraicRewriting-backed dynamic hierarchy and Potts adapter beta; later phases add scientific
    adapters and alternate executors; public release still requires complete parity and the
    whole-cell-style composite.

## Completion Statement

No question remains open. The interview authorizes a coordinated specification and roadmap
revision. It does not claim that the AlgebraicJulia dependencies, ACSet migration,
AlgebraicRewriting structural engine, independent specification oracle, or Phase 15 alpha are
already implemented.
