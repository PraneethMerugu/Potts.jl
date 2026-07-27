# Process-Bigraph Runtime Parity and Parallel-Development Audit

> Post-audit architecture note: [Decision 0036](../../spec/decisions/0036-algebraicjulia-process-bigraph-foundation.md)
> supersedes recommendations below to execute the upstream Python runtime. Exact upstream commits
> remain source-audit authorities, while conformance uses a structurally independent Julia oracle,
> source-located derivations, and comprehensive unit/integration evidence. AlgebraicJulia is the
> required structural foundation beginning in Phase 15.

Status: Pre-interview research complete; no roadmap or contract decision is changed by this audit

Date: 2026-07-26

Post-audit disposition: [Decision 0035](../../spec/decisions/0035-wang-sequential-gpu-disposition.md)
retired assembled Wang GPU qualification and opened G4. References below to concurrent or pending
G3-C work preserve the factual planning context at the time of this research; they are not current
gates. Decisions 0034 and 0036--0038 subsequently froze the runtime architecture, and
ProcessBigraphs Phase 15.C has since qualified the immutable-topology serial internal alpha. The
research recommendations below remain historical input rather than current implementation status.

## Purpose

This audit evaluates a new project goal:

> Develop an independent Julia implementation of the Vivarium 2.0 / Process-Bigraph runtime with
> feature and behavioral parity, suitable for future whole-cell development, while continuing
> PottsToolkit and CorePotts development in parallel.

Python document interchange is not the primary objective. It may remain a later adapter. The
primary objective is runtime function, scientific semantics, model capability, and whole-cell
workflow parity.

The audit does not authorize implementation, extraction, package creation, or roadmap revision.
Those actions require the focused owner interview recorded in
[process-bigraph-runtime-owner-interview.md](process-bigraph-runtime-owner-interview.md).

## Research basis

Three independent audits covered:

1. the current Process-Bigraph, Bigraph-Schema, Vivarium Core, Spatio-Flux, and vEcoli sources;
2. the local PottsToolkit/CorePotts implementation, specifications, evidence, package boundaries,
   and CI; and
3. Dagger, SciML, ModelingToolkit, Catalyst, JumpProcesses, COBREXA, SBML, units, GPU execution,
   and whole-cell reference-model options.

### Candidate upstream pins

The first parity baseline should use exact commits rather than a floating branch or package range.
The audit recommends these candidate pins, subject to owner acceptance:

| Source | Candidate revision | Role |
|---|---|---|
| [Process-Bigraph](https://github.com/vivarium-collective/process-bigraph/tree/305ea826191e9f897f0c6e207bc303bbc44a9eef) | `305ea826191e9f897f0c6e207bc303bbc44a9eef`, package version 1.5.0 | Executable runtime baseline |
| [Bigraph-Schema](https://github.com/vivarium-collective/bigraph-schema/tree/4b208e13620e09e877af52ea07273bc9429a3a17) | `4b208e13620e09e877af52ea07273bc9429a3a17`, package version 1.4.3 | Type, state, apply, divide, and serialization baseline |
| [Process-Bigraph paper](https://arxiv.org/abs/2512.23754) | arXiv 2512.23754 | Architectural intent and formal description |
| [Vivarium Core](https://github.com/vivarium-collective/vivarium-core/tree/60b1570ed20bddd1229e621e670621566c0dafd3) | `60b1570ed20bddd1229e621e670621566c0dafd3`, v1.6.5 | Legacy capability cross-check |
| [Spatio-Flux](https://github.com/vivarium-collective/spatio-flux/tree/6fece7bb9af8e3b374affe02f30b6b022de1d134) | `6fece7bb9af8e3b374affe02f30b6b022de1d134`, v1.4.0 | Multiscale application reference |
| [vEcoli](https://github.com/vivarium-collective/vEcoli/tree/0c4bc21731b07d0d395b5e5b1d8f5afe11466626) | `0c4bc21731b07d0d395b5e5b1d8f5afe11466626`, v0.1.0 | Whole-cell acceptance reference |

The paper is not automatically executable truth. Every parity result must name the two runtime
source revisions and classify the observed behavior as documented, tested, incidental, a known
upstream discrepancy, or an intentional Julia improvement.

## Executive findings

1. **Parallel development is feasible.** A new domain-neutral package can develop in the current
   monorepo while G3-C continues on the locked G3-B ABI.
2. **The current coupled directory is not an extractable general runtime.** It contains strong
   concepts inside a Potts-owned executor. Moving it wholesale would preserve the wrong dependency.
3. **The new runtime must be independently implemented around typed hierarchical stores, ports,
   deltas, exact logical time, deterministic commits, and structural transactions.**
4. **CorePotts should become the flagship spatial-process adapter.** Process-Bigraph runtime code
   must not depend on CorePotts or PottsToolkit.
5. **A deterministic serial executor must remain the semantic oracle.** Dagger is an optional coarse
   executor beneath it, not the time, conflict, or commit authority.
6. **A whole-cell engine can be GPU-native without requiring every process to execute on a GPU.**
   FBA, some stiff/adaptive solvers, and external tools will remain CPU processes. Placement,
   residency, transfers, and support must be explicit and fail closed.
7. **The Julia solver ecosystem is not the main bottleneck.** SciML, Catalyst, JumpProcesses,
   COBREXA, and SBML tooling should be adapted. The hard work is scheduler semantics, update
   algebra, dynamic hierarchy, process invalidation, replay, and mixed-device state ownership.
8. **The upstream runtime contains consequential semantic ambiguities.** “Parity” cannot be defined
   until the interview resolves them.

## Local baseline and inconsistency

G3-B is attested complete in commit `a82b0c4`. The authoritative
[closure ledger](phase-14-g3b-closure-ledger-v1.toml) records `overall_status = "passed"`.

Several documents still describe G3-B as current or open, including:

- [the roadmap](../refactor-roadmap.md);
- [the Phase 14 semantic kernel](../../spec/phase-14-semantic-kernel.md); and
- [the GPU-native implementation plan](phase-14-gpu-native-implementation-plan.md).

The eventual roadmap revision must first correct this factual baseline: G3-B is complete and G3-C
is the next Potts qualification gate.

## Upstream semantic ambiguities

### Imminent-event versus deferred sample-and-hold execution

The paper describes an imminent-event scheduler: advance to the minimum next event and invoke the
processes due at that time using current shared state.

The pinned implementation can compute a future update when a process front is first due, retain the
deferred result, and commit it at its future event time. An interval-two process may therefore
compute from time zero even when another process changes shared state at time one. The relevant
implementation is
[`Composite._run_inner`](https://github.com/vivarium-collective/process-bigraph/blob/305ea826191e9f897f0c6e207bc303bbc44a9eef/process_bigraph/composite.py#L2370)
and
[`run_process`](https://github.com/vivarium-collective/process-bigraph/blob/305ea826191e9f897f0c6e207bc303bbc44a9eef/process_bigraph/composite.py#L2491).

This is not a minor implementation detail. It changes coupled trajectories.

### Partial final intervals

`force_complete` trims the future event time to the requested end, but the handler can still receive
the original nominal process interval rather than the actual elapsed interval. The Julia runtime
must explicitly choose nominal, elapsed, rejected-partial, or process-selected behavior.

### Workflow cycles

The paper says workflow cycles are disallowed. The current implementation can break a cycle by
selecting the highest-priority remaining step. The parity contract must decide whether cycles are
invalid, supported through a defined fixed-point/priority rule, or preserved only in a compatibility
mode.

### Noncommutative update order

Current update behavior includes last-writer and absorbing operations whose result can depend on
declaration or dispatch order. Julia must expose a versioned conflict algebra rather than copy an
incidental dictionary traversal.

### Claimed versus implemented structural rewrites

The paper discusses broad rewrite families. The current generic runtime most clearly implements
add, remove, and divide. Move, merge, engulf, burst, arbitrary rewrite, and rewire support require a
feature-by-feature evidence classification.

## Feature and function parity map

### Core runtime parity

The following capabilities belong in the domain-neutral runtime:

- hierarchical typed stores and stable typed paths;
- schema realization, validation, defaults, metadata, and canonical serialization;
- temporal processes, zero-time ordered steps, and recursive composites;
- explicit input/output ports, topology wiring, external interfaces, and bridges;
- exact logical time, process deadlines, adaptive next-time selection, priorities, and stable ties;
- immutable read projections and typed process deltas;
- deterministic batch reconciliation, conflict reporting, and atomic commit;
- configurable type-directed update operators;
- ordered-step dependency layers, silent inputs, fork/join, and cycle policy;
- structural add, remove, divide, move, rewire, and selected broader graph rewrites;
- process creation, reconfiguration, retirement, and daughter reconstruction;
- checkpoint/replay of state, graph, clocks, RNG, process continuation, and emitter position;
- observers, emitters, inspection, diagnostics, and structured failures;
- process capability, placement, residency, transfer, and backend declarations;
- a deterministic serial executor plus executor-equivalence protocols.

### Whole-cell workflow parity

The runtime and adapters must eventually support:

- requester → allocator → evolver ordered workflows;
- shared process instances across workflow stages;
- bulk and unique-molecule state families;
- custom update and daughter-division laws;
- lineage-stable stochastic streams;
- nested cell composites;
- cell division and fresh daughter process construction;
- multigeneration simulations;
- metabolism, transcription, translation, regulation, replication, allocation, division, and
  observation processes;
- multiscale composition of ODE, jump, FBA, Boolean, spatial, and agent processes.

### Optional ecosystem parity

These capabilities should not block the semantic runtime:

- exact Python/JSON declaration interchange;
- REST, Ray, EC2, Python multiprocessing, and Nextflow backends;
- SQLite and Parquet emitter packages;
- dashboards, discovery metadata, and `bigraph-viz`;
- package auto-discovery;
- formal Milner bigraph calculi and their specialized encodings.

They may receive later packages or compatibility modes.

### Legacy Vivarium 1.x

Legacy Composer dictionaries, Deriver names, topology views, `_parallel`, condition paths, database
emitter configuration, private-state APIs, and schema override spellings are not automatically
normative.

Legacy move/insert/delete/divide behavior, configurable updaters/dividers, conditions, and
hierarchical topology operations require explicit disposition because some are clearer in Vivarium
1.x than in the current 2.0 implementation.

## What the current Potts code contributes

The following concepts are valuable seeds:

- typed state and process metadata in
  [semantic_kernel.jl](../../lib/CorePotts/src/coupled/semantic_kernel.jl);
- exact rational clocks and deterministic time/priority/identity ordering in
  [multirate.jl](../../lib/CorePotts/src/coupled/multirate.jl);
- same-time read/write conflict validation;
- canonical semantic encoding and checkpoint blocks in
  [persistence.jl](../../lib/CorePotts/src/coupled/persistence.jl);
- typed fragment requirements, exports, privacy, substitution, and backend propagation in
  [models.jl](../../src/authoring/models.jl);
- semantic RNG, failure atomicity, backend preflight, device adaptation, and extensive conformance
  discipline.

These should be re-expressed through domain-neutral runtime values and adapters, with golden
equivalence evidence. They should not simply be moved.

## Potts assumptions that must not enter the runtime

The present implementation:

- requires a Potts entry and lifecycle in `PlanSpec`;
- makes `SemanticModel` own spatial roles and a Potts algorithm;
- requires `PottsAttempts → LifecyclePhase → ObservationPhase` in `MCSPlan`;
- requires one scheduled Potts process in multirate mode;
- stores a fixed `CoupledState` tuple rather than a hierarchical store;
- makes `CoupledIntegrator` own a Potts integrator and MCS counter;
- exposes logical Potts state directly to process execution;
- derives portable execution capability from the Potts plan;
- embeds the frozen Potts checkpoint in coupled checkpoints; and
- mutates deep-copied candidate state rather than returning first-class typed deltas.

`ModelFragment` is also compile-time authoring hierarchy that is erased during lowering. It can
inspire a composite façade but is not a runtime place/link graph.

## Recommended package and dependency direction

The provisional package name is used only to make the dependency clear:

```text
ProcessBigraphs.jl
    ↑
CorePotts
    ↑
PottsToolkit

PottsToolkit ─────────→ ProcessBigraphs.jl
```

`PottsToolkit` may depend on both packages when it directly uses both APIs. The runtime must have no
Potts dependency.

The new package should initially live under `lib/` in this monorepo with its own UUID, project,
tests, documentation, compatibility bounds, CI lane, and release identity. A repository split is a
later beta-or-release decision.

## Parallel workstreams

### Workstream A — Potts scientific closure

Continue through the existing CorePotts path:

1. Wang G3-C Metal/ROCm qualification on the locked G3-B ABI;
2. the general field-model CPU/Metal/ROCm slice;
3. specifically Potts-owned published-model capabilities; and
4. Potts documentation and reproduction evidence.

G3-C may repair backend plumbing. It may not silently change G3-B storage semantics, ordering, RNG
addressing, launch topology, or publication boundaries.

### Workstream B — Domain-neutral runtime

Begin without altering CorePotts:

1. typed paths, schemas, hierarchical stores, and ports;
2. typed deltas and update/conflict algebra;
3. exact time and a deterministic serial executor;
4. steps, dependencies, barriers, and composite topology;
5. checkpoint, fingerprint, observation, and failure protocols;
6. structural transactions;
7. a multirate biochemical fixture; and
8. a dynamically nested non-Potts fixture.

### Workstream C — Adapter and equivalence bridge

Join A and B only through bounded bridge work:

1. adapt CorePotts state and execution as runtime processes;
2. lower PottsToolkit composition into the generic graph;
3. run old and new serial paths as differential oracles;
4. prove unchanged Phase 13 artifacts;
5. prove Wortel, Wang, and field-model state/order equivalence;
6. cut over one vertical slice at a time; and
7. retain readers for already-attested checkpoint formats.

This is a strangler migration, not a flag-day rewrite.

### Workstream D — Julia scientific adapters

Develop package extensions after the core process contract is testable:

- SciML/OrdinaryDiffEq for adaptive ODE integration;
- ModelingToolkit as authoring/compilation, not runtime state;
- Catalyst and JumpProcesses for reaction, SSA, and hybrid processes;
- COBREXA/JuMP for FBA;
- SBMLImporter/SBMLFBCModels/libSBML for standards import and validation;
- Dagger only after the serial semantic batches are normative.

## Sequencing gates

Can begin immediately:

- parity audit and pinned oracles;
- package and semantic specifications;
- paths, ports, schemas, deltas, exact time, and the serial executor;
- non-Potts microfixtures;
- canonical encoding and package CI scaffolding.

Must wait for G3-C before final GPU ownership or cutover:

- portable executor ownership;
- device graph/state adaptation;
- status publication and synchronization accounting;
- Wang GPU claims through the new runtime.

Must wait for the field-model slice before freezing:

- generic field/PDE adapter contracts;
- stencil and boundary-condition capability taxonomies;
- field continuation codecs;
- field convergence and split semantics.

Should be co-designed rather than implemented twice:

- lifecycle request queues;
- sampled events and delays;
- relationship/degradation dynamics;
- hierarchical structural rewrites.

## Dagger and executor architecture

Dagger supplies task placement and data movement, not scientific meaning:

```text
logical-time scheduler
    → immutable state projection
    → stable runnable batch
        → SerialExecutor | ThreadsExecutor | DaggerExecutor
    → typed deltas
    → deterministic reconcile and commit
    → structural transaction barrier
    → emit/checkpoint
```

Dagger should receive coarse process ticks or solver calls, never individual Potts attempts,
lattice sites, or tiny reactions. Compute and result scopes must be explicit. An undeclared
automatic transfer is an error.

## Whole-cell build-versus-adapt boundary

Build:

- runtime state, ports, paths, clocks, scheduling, deltas, conflict algebra, structural
  transactions, persistence, RNG, placement, failure, and observation semantics.

Adapt:

- SciML integrators;
- ModelingToolkit compilation;
- Catalyst and JumpProcesses;
- COBREXA/JuMP;
- SBML parsers and validators;
- Dagger execution.

Important adapter obligations include:

- external-state invalidation and reinitialization for ODE and jump solvers;
- propensity-cache reset after coupled state changes;
- explicit input behavior during a solver interval;
- FBA optimizer, tolerance, infeasibility, timeout, warm-start, and solution-selection policy;
- unit and ontology metadata without forcing unitful scalars into hot device arrays.

## GPU policy finding

The runtime should be GPU-generic and residency-aware. Each process and state leaf declares:

- supported execution domains;
- current residency;
- allowed projections and transfers;
- synchronization and status-publication boundaries;
- numerical/replay guarantee.

Potts and appropriate field/reaction kernels may require complete device residency. CPU-only FBA or
solver processes remain valid when the composition declares and measures their exchanges. Small
explicit scalar transfers may be allowed by policy; hidden or large implicit transfers must fail
preflight.

This requires revisiting the Phase 14 rule that every stable process qualifies on Metal and ROCm.
That rule remains valid for the selected Phase 14 Potts capabilities until superseded. It is not a
viable universal rule for a whole-cell process ecosystem.

## Differential-oracle suite

Before large applications, compare the Julia serial engine with the pinned Python runtime on:

1. interval-one and interval-two processes sharing state;
2. a forced partial final interval;
3. same-time numeric, overwrite, map, array, add/remove, and divide conflicts in reversed orders;
4. fork/join steps, silent inputs, wildcard inputs, same-layer writes, and a priority cycle;
5. dynamic add, execute, rewire, divide, daughter reconstruction, and remove;
6. nested composite bridges;
7. typed daughter partitioning and lineage RNG;
8. settled-boundary checkpoint and replay;
9. requester → allocator → evolver;
10. a short seeded vEcoli slice;
11. a Spatio-Flux coupled fixture; and
12. failure during invoke, reconcile, apply, structural commit, and emission.

The first four are scheduler/update specification fixtures. The rest validate application fitness.

## Whole-cell qualification ladder

1. Runtime microfixtures.
2. Catalyst gene-expression jump + OrdinaryDiffEq regulation + COBREXA E. coli core FBA.
3. Representative vEcoli processes with differential traces.
4. A well-stirred JCVI-syn3A CME/ODE composition.
5. Historical Karr/Covert *M. genitalium* semantic coverage.
6. Full vEcoli generation, then population/environment composition with PottsToolkit.

The engine program and construction of a scientifically complete whole-cell model are different
commitments. The latter remains a longer scientific program.

## Production qualification obligations

The eventual runtime requires:

- serial golden semantics and randomized update-algebra tests;
- stable ties, exact time, and adaptive-boundary tests;
- serial/threads/Dagger executor equivalence;
- checkpoint/restart at every supported commit boundary;
- failure injection and dynamic-topology fuzzing;
- RNG invariance under task order and worker-count changes;
- residency and hidden-transfer tracing;
- declared CPU/GPU numerical or statistical equivalence;
- external-solver invalidation fixtures;
- jump propensity-reset fixtures;
- FBA nonunique, infeasible, unbounded, timeout, and solver-failure fixtures;
- applicable SBML conformance cases;
- long-run leak/output-volume tests; and
- compile-latency, memory, and throughput budgets.

## Conclusions carried into the interview

The following are audit conclusions rather than owner preference questions:

- build the domain-neutral semantics rather than delegate them to Dagger or SciML;
- retain a serial semantic oracle;
- make process execution return declared effects or deltas to an engine-owned commit;
- keep the runtime free of Potts dependencies;
- preserve frozen Phase 13 and attested G3-B behavior through adapters and golden evidence;
- do not claim parity against an unpinned upstream;
- use external Python execution as a test oracle, not a production dependency;
- expose all placement and transfers;
- do not promise that arbitrary whole-cell processes are GPU-executable; and
- do not copy undocumented upstream quirks without an explicit compatibility decision.

The owner interview must decide product identity, baseline, scheduler mode, update semantics,
structural scope, GPU tiers, migration timing, release gates, upstream collaboration, and the first
whole-cell acceptance workloads.
