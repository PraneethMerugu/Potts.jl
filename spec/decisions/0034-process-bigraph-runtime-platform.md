# Decision 0034: ProcessBigraphs.jl as the Domain-Neutral Runtime Platform

Status: Accepted architecture and roadmap policy; PB0, Phase 15.A, and Phase 15.B passed; Phase 15.C remains open

Date: 2026-07-26

Amended by
[Decision 0036](0036-algebraicjulia-process-bigraph-foundation.md): AlgebraicJulia is the mandatory
structural foundation beginning in Phase 15, and upstream Python runtimes are source authorities
but are never executed as conformance oracles. This decision's package identity, runtime authority,
Dagger boundary, migration, and release rules otherwise remain in force.

## Context

PottsToolkit and CorePotts began Phase 14 with a Potts-owned coupled executor. That work established
valuable contracts for exact clocks, deterministic ordering, semantic randomness, failure
atomicity, persistence, backend preflight, and GPU-resident computation. It did not establish a
domain-neutral runtime: the current plan, state, lifecycle, and integrator structures still require
Potts concepts.

The project goal has expanded. It now includes an independent Julia implementation of the
Process-Bigraph 2.0 runtime model with source-audited feature and semantic parity, a path toward
whole-cell development, and continued development of PottsToolkit as the flagship spatial-modeling
environment. Python declaration interchange is useful but is not the product center.

The research basis and owner decisions are recorded in:

- `design/audits/process-bigraph-runtime-parity-and-parallel-development-audit.md`; and
- `design/audits/process-bigraph-runtime-owner-interview.md`.

This decision accepts all 48 owner answers. It does not accept an implementation merely because it
resembles the upstream API or passes a subset of examples.

## Decision

### Product and parity authority (decisions 1--6)

1. The general runtime is the long-term platform. CorePotts is its flagship high-performance
   spatial-process adapter, and PottsToolkit is the biological CPM authoring environment.
   `ProcessBigraphs.jl` begins as an independently valid package under `lib/` in this monorepo.
2. Parity means feature and observable behavioral parity through idiomatic Julia APIs. Python
   spelling, Python object layout, and exact declaration interchange are not parity requirements.
3. Every parity claim names exact Process-Bigraph and Bigraph-Schema revisions. A pin advances only
   through a reviewed qualification change with refreshed fixtures.
4. Paper, code, and test discrepancies receive independently researched, versioned Julia semantic
   decisions. A differing upstream behavior may be retained only as a named compatibility mode
   with its own evidence; it cannot silently control normative Julia behavior.
5. Vivarium 1.x compatibility is outside scope. A useful feature is admitted because the pinned
   Process-Bigraph 2.0 target or a whole-cell requirement needs it, not merely because Vivarium 1.x
   contained it.
6. Development is independent of Eran Agmon. Presentation or feedback near release does not make
   Eran, Vivarium contributors, or any external party a design or release authority.

### Package and public boundaries (decisions 7--12)

7. `ProcessBigraphs.jl` begins under `lib/` with its own UUID, project, tests, documentation,
   compatibility bounds, and CI identity. Repository separation is reconsidered only after the
   first complete parity release.
8. The runtime has no domain dependency. CorePotts depends on the runtime for generic composition;
   PottsToolkit may depend on both.
9. The runtime owns paths, ports, structural schemas, hierarchical stores, processes, steps,
   deltas, update laws, logical clocks, composites, topology, scheduling, transactions, and
   executor protocols. CorePotts owns Potts laws, lattice storage, workspaces, kernels, spatial
   roles, lifecycle specialization, and algorithm identities.
10. PottsToolkit retains biological façades and lowers generic composition into
    `ProcessBigraphs.jl`; it does not create a second scheduler or state authority.
11. The runtime is not independently published until complete pinned parity and a whole-cell-style
    composite pass. Internal alpha and beta milestones are evidence states, not public releases.
12. The package name is `ProcessBigraphs.jl`. Documentation must describe it as an independent
    Julia implementation and must not imply upstream ownership or endorsement.

### Time and execution semantics (decisions 13--18)

13. Normative scheduling is imminent-event execution. At the smallest next logical event time, all
    due processes read state committed through that time. The pinned implementation's deferred
    sample-and-hold behavior may exist only as a named compatibility mode.
14. A forced partial interval receives its actual elapsed duration. A process may declare partial
    advancement unsupported and must then fail preflight or interval planning before mutation.
15. Processes due at the same logical time read one common immutable pre-commit snapshot. They
    publish only through deterministic reconciliation of typed effects.
16. Temporal `Process` and zero-time ordered or reactive `Step` remain distinct public concepts
    over shared ports, deltas, failures, capabilities, and executor machinery.
17. Undeclared workflow cycles are invalid. Fixed-point iteration, bounded iteration, and nonlinear
    solves require explicit, versioned constructs with termination and failure policies.
18. Global logical time uses normalized integer ticks and a declared time scale. Rational input
    durations are normalized during compilation. Process and kernel invocations receive an
    appropriate elapsed scalar; exact scheduling does not force rational arithmetic into device
    hot loops.

### State, ports, effects, and topology (decisions 19--24)

19. Runtime state is a versioned hierarchical store. Committed snapshots are logically immutable;
    physical leaves may use specialized mutable storage owned by the engine.
20. Structural schemas may carry optional nominal identities and independently describe element
    type, shape, units, ontology, ownership, conservation, update law, division law, persistence,
    continuation, and residency.
21. Processes and steps declare typed input and output ports wired to stable hierarchical paths.
    Place topology and link topology are distinct, inspectable views.
22. User process code publishes only typed deltas or structural requests. Optimized kernels may
    mutate engine-owned transaction buffers but never publish directly to committed state.
23. The update system consists of a small, versioned built-in algebra plus an open law-declared
    protocol. Every law declares identity, associativity, commutativity, conflict behavior,
    determinism, device support, persistence, and division behavior.
24. The first stable structural transaction set is add, remove, divide, move, and rewire. Merge,
    engulf, burst, and arbitrary rewrite remain unqualified until promoted by explicit fixtures.

### Persistence, randomness, failure, and observation (decisions 25--30)

25. Exact restart is first guaranteed at settled commit boundaries. Mid-event restart is claimed
    only when every pending work item and transaction buffer has an explicit continuation schema.
26. Semantic RNG addressing includes process identity, logical time, event identity, draw identity,
    and lineage identity. Solver-owned RNG continuation may persist, but task order, worker count,
    and completion order cannot move semantic streams.
27. Every stateful process declares a versioned continuation schema and invalidation rules.
    Serializing an arbitrary Julia process object is not a continuation contract.
28. A failed event or tick publishes no partial state. Failure returns structured diagnostics and
    supports restart from the last stable commit. External effects outside runtime ownership are
    not promised universal rollback.
29. Core owns a read-only observer protocol. Memory, SQLite, Parquet, dashboards, and other
    emitters are extensions unless separately promoted.
30. Exact same-engine/backend replay is required where the process law permits it. Executor-order
    invariance is normative. Cross-backend evidence is classified honestly as exact, numerical, or
    statistical; bitwise cross-hardware identity is not a universal promise.

### GPU, placement, and Dagger (decisions 31--36)

31. The runtime is GPU-native and capability-declared, but a valid whole-cell composite may contain
    explicit CPU processes. Each process family publishes its supported execution domains.
32. Every cross-residency projection or transfer is declared, bounded, measured, and visible during
    preflight and inspection. Hidden transfer fails before execution.
33. Dagger placement experiments may begin early. `DaggerExecutor` cannot qualify until the serial
    runnable-batch, reconciliation, commit, and structural-barrier semantics are stable.
34. Dagger task granularity is coarse: a process tick, solver call, field advance, or partition
    batch. Individual Potts attempts, lattice sites, or tiny reactions are not runtime task units.
35. Distributed execution first provides deterministic fail-stop plus settled-checkpoint recovery.
    Automatic retry is limited to work declared pure and idempotent.
36. Runtime core qualifies CPU and applicable GPU microfixtures. Every process family publishes its
    own backend matrix. Existing Potts CPU/Metal/ROCm requirements continue until separately
    revised; they are not imposed on every whole-cell process.

The semantic boundary is fixed:

```text
exact logical-time scheduler
    -> immutable projections and a stable runnable batch
    -> SerialExecutor | ThreadsExecutor | DaggerExecutor
    -> typed deltas and structural requests
    -> deterministic reconciliation and atomic commit
    -> structural transaction barrier
    -> observation/checkpoint
```

Executors choose physical placement and concurrent computation. They do not choose scientific
time, same-time visibility, merge order, conflict meaning, structural order, or commit boundaries.

### Scientific adapters and whole-cell semantics (decisions 37--42)

37. Every solver-backed process declares whether external inputs are frozen, interpolated,
    event-updated, or continuously callable over an interval.
38. ModelingToolkit is an optional authoring/compiler frontend that lowers to ordinary SciML
    process adapters. It does not own runtime state, topology, scheduling, or persistence.
39. Catalyst and JumpProcesses are adapted with explicit propensity-cache invalidation,
    discontinuity, rescheduling, RNG-continuation, and restart contracts.
40. COBREXA/JuMP FBA adapters pin optimizer settings and define deterministic solution selection,
    such as parsimonious FBA or lexicographic objectives. Nonunique, infeasible, unbounded,
    timeout, and solver-failure behavior is part of the contract.
41. Schemas carry units and ontology metadata while hot state uses canonical numeric payloads.
    Validation and conversion occur at declared boundaries without forcing unitful wrapper values
    into device arrays.
42. SBMLImporter, SBMLFBCModels, and libSBML are optional adapters behind exact supported-feature
    matrices. Import success never implies unsupported semantic coverage.

### Parallel development, migration, release, and presentation (decisions 43--48)

43. Potts G4 continues without changing the locked G3-B ABI while runtime specifications, the
    serial engine, and non-Potts fixtures begin in isolated package paths. Decision 0035 retires
    assembled Wang GPU qualification.
44. The first Potts field-model slice may finish on the existing executor. Its generic runtime
    adapter is co-designed but is not frozen before the field evidence closes.
45. Migration uses a strangler strategy: old/new serial differential execution, one vertical slice
    at a time, with unchanged Phase 13 and attested G3-B artifacts.
46. Internal alpha means serial static composites; internal beta means dynamic hierarchy plus the
    Potts adapter. The first public runtime release requires complete pinned parity and a
    whole-cell-style composite.
47. Whole-cell acceptance proceeds through:
    1. a Julia biochemical/FBA composite;
    2. selected vEcoli slices;
    3. a well-stirred Syn3A composite;
    4. a full vEcoli generation; and
    5. population/environment composition with PottsToolkit.
48. Every phase ships documentation and conformance evidence. Development remains independent;
    presentation to Eran occurs near release; repository separation is considered only after the
    first complete parity release.

## Normative upstream baseline

The initial parity baseline is:

- Process-Bigraph commit `305ea826191e9f897f0c6e207bc303bbc44a9eef`, package version
  `1.5.0`;
- Bigraph-Schema commit `4b208e13620e09e877af52ea07273bc9429a3a17`, package version
  `1.4.3`; and
- Process-Bigraph paper arXiv `2512.23754` as architectural intent, not automatic executable truth.

Spatio-Flux commit `6fece7bb9af8e3b374affe02f30b6b022de1d134` and vEcoli commit
`0c4bc21731b07d0d395b5e5b1d8f5afe11466626` are application references. Vivarium Core commit
`60b1570ed20bddd1229e621e670621566c0dafd3` is research context only and cannot create a Vivarium
1.x parity obligation.

The authoritative feature inventory, independent source-derived oracle requirements, and
completion states are in
`spec/process-bigraph-parity-registry-v1.toml`.

## Compatibility and evidence classes

Every observed upstream behavior and every Julia claim is classified:

- `normative_parity`: required feature and observable behavior of the pinned 2.0 target;
- `normative_julia`: independently chosen Julia behavior where upstream sources disagree;
- `compatibility_mode`: intentionally reproduced upstream behavior outside the normative Julia
  mode;
- `application_required`: required for the accepted whole-cell ladder even when not decisive for
  pinned runtime parity;
- `optional_ecosystem`: valuable integration that cannot block semantic parity;
- `excluded_legacy`: Vivarium 1.x-only behavior outside scope; or
- `deferred_rewrite`: advertised or useful structural behavior not yet promoted.

No feature may be labeled complete without its registered semantic specification, implementation,
independent source-derived Julia oracle fixtures, conformance evidence, documentation, persistence
disposition, failure behavior, and applicable backend evidence. Per Decision 0036, upstream Python
runtimes are never installed or executed by CI, tests, examples, attestations, or release tooling.

## Migration constraints

The runtime must be implemented independently around domain-neutral values. The current
`CorePotts/src/coupled/` tree is source evidence, not a package to move wholesale.

During migration:

- frozen Phase 13 behavior and artifacts remain unchanged;
- the attested G3-B result remains unchanged;
- G4 may repair backend plumbing without changing the locked G3-B semantic ABI;
- current checkpoint readers remain supported for attested formats;
- CorePotts and runtime paths are compared through serial golden fixtures;
- Wortel, Wang, and field-model state/order equivalence is required before their cutover; and
- no model uses two simultaneous state, scheduler, lifecycle, or persistence authorities.

## Consequences

- PottsToolkit and the general runtime can progress concurrently without freezing an unproven field
  abstraction or blocking G4.
- The serial executor remains the durable alternate-executor equivalence reference; the checked
  Julia specification oracle is structurally independent, and Dagger is replaceable infrastructure.
- GPU-native means explicit residency and qualified device processes, not a false requirement that
  every whole-cell method execute on every GPU family.
- Typed deltas and structural transactions make deterministic parallelism, replay, and dynamic
  hierarchy testable.
- The no-public-release gate is deliberately stricter than normal package incubation.
- Full whole-cell construction remains a scientific program beyond merely implementing the runtime.

## Rejected alternatives

### Extract the current Potts coupled executor

Rejected because its plan, state, lifecycle, checkpoint, and integrator authority are Potts-owned.

### Let Dagger define the runtime

Rejected because task dependency and placement do not define logical time, typed update meaning,
same-time visibility, dynamic topology, or deterministic commit.

### Make ModelingToolkit the runtime graph

Rejected because ModelingToolkit is an authoring and symbolic compilation system, not the owner of
hierarchical runtime state, structural transactions, or multirate commit semantics.

### Require universal GPU execution

Rejected because whole-cell compositions include solver and optimization processes for which CPU
execution may be the qualified path. Hidden movement remains prohibited.

### Reproduce every Vivarium version

Rejected. Vivarium 1.x is explicitly outside scope, and unpinned moving-target parity is not
falsifiable.

### Publish an incomplete compatibility alpha

Rejected by the owner. Internal milestones remain available, but the independent public package
waits for complete pinned parity and a whole-cell-style acceptance composite.

## Required conformance evidence

Before the first public release:

- every required registry feature is `qualified`;
- all normative scheduler, update, topology, continuation, failure, and replay fixtures pass;
- the independent Julia specification oracle passes its source-located derivations, finite truth
  tables, property, metamorphic, invariance, failure, and restart suites;
- canonical ACSet, structured-cospan, wiring-diagram, compiled-epoch, and
  AlgebraicRewriting conformance passes;
- the serial implementation passes randomized update-algebra and dynamic-topology tests;
- applicable Serial/Threads/Dagger executor equivalence passes;
- every claimed placement and residency path proves absence of hidden transfer;
- process-family backend matrices and numerical/replay classifications are published;
- old/new Potts differential gates pass for every migrated slice;
- the required whole-cell-style composite passes its scientific, restart, and failure gates;
- complete user, adapter-author, executor-author, and conformance documentation exists; and
- no public claim implies Vivarium 1.x support, exact Python interchange, live upstream-runtime
  equivalence, or upstream endorsement.
