# Potts and ProcessBigraphs Development and Release Roadmap

Status: Working execution roadmap derived from accepted specifications and engineering standards

## Execution Status

| Phase | Status | Evidence |
| --- | --- | --- |
| Phase 0: Scope Freeze and Current-Code Audit | Complete | [Current-code audit](audits/phase-0-current-code-audit.md), [paper-scope map](audits/phase-0-paper-scope-map.md) |
| Phase 1: Correctness and Performance Baselines | Complete | [Baseline evidence](audits/phase-1-baseline-evidence.md), [GitHub and JuliaGPU governance](github-and-ci-governance.md), protected `main`, pinned benchmark harness, and immutable attested release |
| Phase 2: Repository Structural Migration | Complete | [Structural migration audit](audits/phase-2-structural-migration.md) and [PR #8](https://github.com/PraneethMerugu/Potts.jl/pull/8) |
| Phase 3: Reference Semantics and Conformance Foundation | Complete | [Conformance-foundation audit](audits/phase-3-conformance-foundation-audit.md), [specification-to-test evidence index](../spec/conformance-evidence.md), and integration `conformance` shard |
| Phase 4: Core State and Scientific Protocols | Complete | [Phase 4 chunk plan](audits/phase-4-chunk-plan.md), [runtime migration audit](audits/phase-4-runtime-migration-audit.md), and sequential reference vertical slice |
| Phase 5: Execution, RNG, Workspaces, and Backends | Complete | [Phase 5 completion audit](audits/phase-5-completion-audit.md), CPU/Metal/ROCm qualification, and Decision 0013 |
| Phase 6: Scientific Inner Loop | Complete | Typed component folds, staged transactions, CPU/Metal/ROCm Phase 6 qualification, and tracker reconciliation |
| Phase 7: Algorithms and Normalized MCS | Complete | [Phase 7 completion audit](audits/phase-7-completion-audit.md); production algorithms and stable volume/surface mechanics pass CPU, Metal, and ROCm |
| Phase 8: Lifecycle, Initialization, and Persistence | Complete | [Phase 8 completion audit](audits/phase-8-completion-audit.md); open lifecycle and initialization protocols, exact persistence, and CPU/Metal/ROCm qualification |
| Phase 9: SciML Integration | Complete | [Phase 9 completion audit](audits/phase-9-completion-audit.md); SciML semantics and CPU/Metal/ROCm qualification pass authoritative CI |
| Phase 10: PottsToolkit Typed API and Compiler | Complete | [Phase 10 completion audit](audits/phase-10-completion-audit.md); sole Level 2 semantic path, legacy deletion, reference workloads, schema `2.0.0` Metal/ROCm artifacts, and exact-head authoritative CI |
| Phase 11: PottsToolkit Level 1 DSL | Complete | [Phase 11 completion audit](audits/phase-11-completion-audit.md); exact-head package-family, integration, documentation, x86_64/ARM64 CPU, real-Metal, and real-ROCm CI is green |
| Phase 12: Performance Recovery and Backend Qualification | Complete | Core recovery [completion audit](audits/phase-12-completion-audit.md), [CPU completion audit](audits/phase-12-cpu-completion-audit.md), and [external comparison crosswalk](audits/phase-12-external-comparison-crosswalk.md) |
| Phase 12.5: Tiled Checkerboard Engine and Sultan-Class Study | Complete; experimental disposition | [Completion audit](audits/phase-12-5-completion-audit.md), [accepted contract](audits/phase-12-5-tiled-checkerboard-contract.md), and [chunk plan](audits/phase-12-5-chunk-plan.md) |
| Phase 13: Algorithmic Conformance and API Freeze | Complete | [Completion audit](audits/phase-13-completion-audit.md), [approved owner freeze packet](audits/phase-13-owner-freeze-packet.md), [accepted transition-kernel contract](../spec/transition-kernel-verification.md), and [entry policy](../spec/decisions/0028-phase-13-entry-and-freeze-policy.md) |
| Phase 14: Model-Driven Capability Completion, Documentation, and Runtime Foundation | Phase 14.0 complete; Wortel CPU/Metal/ROCm G2 passed; Wang G3-A and attested sequential-CPU G3-B complete; assembled Wang GPU qualification retired by Decision 0035; G4 is the current Potts gate; ProcessBigraphs PB0 bounded foundation passed | [Phase 14.0 completion audit](audits/phase-14-0-corpus-and-requirements-audit.md), [G3-B closure ledger](audits/phase-14-g3b-closure-ledger-v1.toml), [G3-B attested evidence](evidence/phase-14/g3b-closure/manifest-v1.toml), [GPU-native implementation plan](audits/phase-14-gpu-native-implementation-plan.md), [Decision 0035](../spec/decisions/0035-wang-sequential-gpu-disposition.md), [runtime parity audit](audits/process-bigraph-runtime-parity-and-parallel-development-audit.md), [PB0 implementation audit](audits/process-bigraph-pb0-implementation-audit.md), [PB0 evidence](evidence/process-bigraph-pb0-evidence-v1.toml), [Decision 0034](../spec/decisions/0034-process-bigraph-runtime-platform.md), and [registry v2](../spec/phase-14-contract-registry-v2.toml) |
| Phase 15: Potts Paper/Release Qualification and ProcessBigraphs Internal Alpha | Not started; runtime foundations may enter before Potts Phase 14 closes where the join rules permit | Two independent product gates: Potts consumes the frozen Phase 14 portfolio; ProcessBigraphs closes serial static composites without a public release |
| Phase 16: Dynamic Hierarchy and Potts Adapter Internal Beta | Not started | Begins after the serial runtime contracts needed by the first adapter slice stabilize |
| Phase 17: Scientific Process Ecosystem and Whole-Cell-Style Composite | Not started | Begins after internal beta adapter and continuation boundaries pass |
| Phase 18: Dagger and Heterogeneous Execution | Not started | Qualification begins only after serial runnable-batch, reconciliation, commit, and structural-barrier semantics stabilize |
| Phase 19: Pinned Parity Closure and First Public ProcessBigraphs Release | Not started | Public release is forbidden until complete pinned parity and the whole-cell-style acceptance composite pass |
| Phase 20: Whole-Cell Development Program | Not started | Scientific program beyond runtime parity: full-generation and population/environment compositions |

## Objective

This roadmap coordinates two products: the paper-quality `PottsToolkit`/`CorePotts` ecosystem and
the independently identified `ProcessBigraphs.jl` runtime incubated under `lib/`. It sequences
semantic decisions, reference evidence, repository migration, engine and adapter work, API
construction, optimization, documentation, paper qualification, pinned Process-Bigraph 2.0 parity,
and a staged whole-cell program so correctness and performance remain measurable throughout.

The destination is the accepted architecture, not an intermediate compatibility layer. Potts and
runtime workstreams may advance concurrently and may reach their named product gates independently.
A shared phase is complete only when each workstream assigned to it passes its exit gate. A
quarantined path may be reassigned only when its future owning exit gate is named explicitly and new
consumers are prohibited.

## Governing Rules

1. Accepted specifications govern observable behavior; existing code is evidence, not authority.
2. Scientific meaning is established in reference code and conformance tests before optimized
   implementation.
3. GPU validity is maintained throughout engine work and is not postponed to final optimization.
4. Structure-only moves are separated from scientific rewrites whenever practical.
5. Package code and tests precede full documentation and tutorial migration.
6. Performance is measured from the beginning; optimization follows profiling and preserves the
   accepted contract.
7. Breaking changes are allowed until the paper API freeze. After the freeze, incompatible API or
   frozen-contract changes require the explicit versioned release decision and invalidation policy
   in Decision 0028; additive Phase 14 work follows Decision 0029.
8. One migrated subsystem has one implementation. Temporary comparison code lives in test,
   benchmark, or archival baselines rather than the released package.
9. Scientific invariants and taxonomies may be closed, but scientific families and execution
   mechanisms remain open Julia protocols under the
   [Open Protocol and Extensibility Standard](open-protocol-and-extensibility-standard.md).
10. `ProcessBigraphs.jl` owns domain-neutral paths, ports, schemas, stores, processes, steps, deltas,
    clocks, composites, scheduling, reconciliation, and commits. CorePotts owns Potts laws,
    spatial storage, workspaces, kernels, lifecycle specializations, and algorithms.
11. The deterministic serial runtime defines scientific execution. Dagger and other executors may
    place and compute already selected batches but do not define logical time, same-time visibility,
    conflict meaning, merge order, structural order, or commit boundaries.
12. Documentation, conformance evidence, failure behavior, persistence disposition, and applicable
    backend evidence are deliverables of every runtime phase rather than final cleanup.
13. Potts release qualification and ProcessBigraphs release qualification are separate gates. The
    Potts paper release does not wait for runtime parity, and `ProcessBigraphs.jl` MUST NOT be
    publicly released before complete pinned parity and a whole-cell-style composite pass.

## Scope Classification

### Required for the paper refactor

- Cartesian 2D and 3D domains
- Finite cells, one conceptual medium, fixed owners, and obstacles
- Accepted topology roles, spatial queries, fields, surface measures, and connectivity
- Conventional sequential CPM plus every algorithm family claimed in the paper
- Normalized MCS accounting
- Volume, surface, contact, chemotaxis, focal-point, and other paper components
- Growth, division, type transition, death, extinction, and deterministic lifecycle transactions
- Semantically addressed RNG and reproducibility reports
- CPU, AMDGPU, and Metal qualification for claimed features; CUDA is deferred by Decision 0013
- CorePotts Level 3 and Level 4 interfaces
- PottsToolkit Level 2 typed modeling and Level 1 DSL
- SciML problem, integrator, solution, callback, saving, observation, remake, and ensemble behavior
- Snapshots, checkpoints, initialization, paper workloads, and archived benchmark evidence
- A biology-first Documenter manual with 12--15 guided tutorials and a clear Learn, Examples,
  Published Models, Concepts and Guarantees, and API progression
- A release portfolio of 4--6 paper-faithful published models, including flagship work associated
  with Glazier, Wortel, and Jiang, under the
  [published-model reproduction contract](../spec/published-model-reproduction-semantics.md)
- The reusable modeling primitives required by that preregistered portfolio, potentially including
  separately configurable spatial and execution roles, evolving fields, accepted-copy site state,
  general per-cell dynamics, dynamic relationships, degradable structures, staged protocols, and
  research observables

### Deferred without blocking the paper release

- Scientific mechanisms not required by the selected 4--6-model release portfolio
- Hexagonal, rhombic-dodecahedral, irregular, and graph-lattice engines
- Crofton surface estimators
- Validated CC3D, Morpheus, and Artistoo compatibility presets
- Additional query operators, arbitrary custom boundaries, and unclaimed satellite features

Deferred features MUST NOT leak provisional semantics into stable constructors, defaults, reports,
or extension interfaces. A placeholder type or generic protocol is allowed only when it is already
the simplest final design for required features.

### Required for ProcessBigraphs parity and whole-cell progression

- An exact pinned Process-Bigraph 2.0 and Bigraph-Schema authority plus a versioned feature and
  observable-behavior parity registry
- Typed hierarchical stores, stable paths, typed input/output ports, place/link topology, immutable
  committed snapshots, typed deltas, and law-declared update reconciliation
- Exact logical time, imminent-event scheduling, distinct temporal processes and zero-time steps,
  deterministic same-time batches, explicit iterative constructs, and atomic commits
- Structural add, remove, divide, move, and rewire transactions; broader rewrites remain separately
  promoted capabilities
- Settled-boundary exact restart, versioned process continuation, lineage-stable semantic RNG,
  structured failure, and read-only observation
- Capability-declared CPU/GPU execution, explicit residency and transfer, a serial semantic oracle,
  and executor-equivalence contracts
- CorePotts as the flagship spatial-process adapter and PottsToolkit lowering through a strangler
  migration with old/new serial differential evidence
- SciML, ModelingToolkit, Catalyst, JumpProcesses, COBREXA/JuMP, units/ontology, and SBML adapters
  behind explicit semantic and supported-feature contracts
- A whole-cell acceptance ladder from a Julia biochemical/FBA composite through selected vEcoli
  slices, well-stirred Syn3A, a full vEcoli generation, and population/environment composition with
  PottsToolkit

Exact Python declaration interchange, Vivarium 1.x compatibility, upstream API spelling, REST/Ray/
EC2/Nextflow backends, dashboards, and package auto-discovery are not parity requirements unless a
later accepted decision promotes a specific capability.

## Decision Gates

Open questions are resolved immediately before the first phase that needs them. They do not block
unrelated earlier work.

| Gate | Required decision or evidence | Blocks |
| --- | --- | --- |
| D1 | Paper algorithm inventory and guarantee profile for sequential, checkerboard, lottery, and intrinsic families | Algorithm replacement |
| D2 | Philox qualification and exact portable transforms for every distribution used by required features | RNG engine freeze |
| D3 | Conservative versus nonconservative classification of required field couplings | Energy/component freeze |
| D4 | Snapshot, exact checkpoint, backend-independent import, storage equivalence, and schema/RNG provenance — resolved by Decision 0022 | Persistence and SciML saving |
| D5 | Coordinates, rasterization, random placement, periodic placement, and initialization finalization — resolved by Decisions 0021 and 0024 | Initialization replacement |
| D6 | Extension registration, semantic fingerprints, cache invalidation, and expert escape-hatch contract — resolved by Decisions 0017 and 0026 | Compiler/API freeze |
| D7 | Final Level 1 model declarations, fragments, phase spelling, and displays; principal Level 2 model/problem names are resolved by Decision 0026 | PottsToolkit API candidate |
| D8 | Published-model portfolio, fidelity vocabulary, documentation information architecture, and post-freeze policy — resolved at the policy level by Decision 0029; exact papers, target results, source revisions, and licenses are pinned per model in Phase 14.0 | Phase 14.1 capability implementation |
| D9 | Observable semantics and update ordering for every missing capability through the single state/process/plan/lifecycle/observation kernel, focused spatial/algorithm contracts, and derived adapter evidence | Each corresponding Phase 14.1 vertical slice |
| D10 | Compatibility and evidence-invalidation assessment for every post-freeze addition; any incompatible frozen-contract change requires an explicit versioned release decision under Decision 0028 | Public API or contract change |
| D11 | Preregistered per-model validation targets, tolerances, ensemble sizes, stopping rules, source baselines, and fidelity limits | Final Phase 14.3 reproduction runs |
| D12 | GPU-native promotion profile, portable precision, residency boundaries, real-hardware Metal/ROCm evidence, and explicit deferred-backend policy — resolved by Decision 0032 | Stable promotion of every new Phase 14 execution capability |
| D13 | Generic hierarchical authoring, named typed fragment requirements/exports, one explicit root plan, paper-specific API exclusion, and direct-versus-fragment identity — resolved by Decision 0033 | Wang and later complex-model authoring implementation |
| D14 | Product identity, pinned Process-Bigraph 2.0 authority, parity meaning, package/dependency boundary, independent development, and no-public-release rule — resolved by Decision 0034 | ProcessBigraphs specification and package incubation |
| D15 | Versioned runtime semantics for stores, ports, deltas, update laws, exact time, processes, steps, commits, topology, persistence, failure, RNG, observation, and capability declarations | Internal serial alpha |
| D16 | Per-slice CorePotts adapter ownership, checkpoint compatibility, old/new differential fixtures, cutover, and rollback/invalidation policy | Each strangler-migration slice and internal beta |
| D17 | Stable serial runnable batches, reconciliation, structural barriers, placement/residency declarations, executor-order invariance, and failure/retry policy | Qualified Threads and Dagger executors |
| D18 | Complete pinned parity registry, whole-cell-style acceptance result, documentation, production evidence, and presentation/repository disposition | First public ProcessBigraphs release |

Every gate produces an accepted specification update or decision record plus its required evidence.
Implementation convenience MUST NOT decide a gate implicitly.

## Phase Overview

```text
0. Scope and audit
       |
1. Baselines and harnesses
       |
2. Repository structure
       |
3. Reference semantics and conformance foundation
       |
4. Core state and scientific protocols
       |
5. Execution, RNG, workspaces, and backend layer
       |
6. Topology, components, proposals, and trackers
       |
7. Algorithms and normalized MCS
       |
8. Lifecycle, initialization, and persistence
       |
9. SciML integration
       |
10. PottsToolkit typed API and compiler
       |
11. PottsToolkit Level 1 DSL
       |
12. Performance recovery and backend qualification
       |
13. API freeze and full conformance
       |
14. Model-driven capability completion, documentation, and runtime foundation
       |
  14.0 corpus, source, and requirements audit
       |
  14.1 reusable scientific capabilities and conformance
       |\
       | \ ProcessBigraphs specification, registry, package scaffold,
       |    serial primitives, non-Potts fixtures, and internal docs/CI
       |
  14.2 Learn and Examples
       |
  14.3 Published Models
       |
  14.4 full manual and satellites
       |
15. Potts paper/release qualification || ProcessBigraphs internal alpha
       |
16. Dynamic hierarchy and Potts adapter internal beta
       |
17. Scientific process ecosystem and whole-cell-style composite
       |
18. Dagger and heterogeneous execution
       |
19. Complete pinned parity and first public ProcessBigraphs release
       |
20. Whole-cell development program
```

Phases are ordered by architectural dependency, but the Potts, runtime, adapter, and evidence/docs
workstreams form a fork/join program rather than one blocking queue. Work MAY proceed in parallel
when its own inputs are stable. A later workstream MUST NOT freeze an interface whose prerequisite
gate has not passed, and a join MUST name the exact evidence required from both sides.

## Phase 0: Scope Freeze and Current-Code Audit

### Deliverables

- Freeze additions unrelated to the accepted refactor, conformance, or paper qualification.
- Produce an inventory of packages, exported names, extensions, algorithms, components, trackers,
  lifecycle operations, kernels, synchronization sites, atomics, generated functions, and direct
  low-level dependency calls.
- Classify every current feature as required, deferred, experimental, replaced, or removed.
- Map required current behavior to an accepted specification or an explicit investigation.
- Inventory documentation/tutorial workloads that must later be migrated.
- Record the exact current dependency resolution, Julia version, drivers, devices, OS, compiler
  settings, and repository revision.
- Establish issue or checklist identifiers for phases, decision gates, and conformance evidence.

### Exit gate

- No required implementation area is unowned by a roadmap phase.
- No historical behavior is labeled stable merely because it exists.
- Deferred and removed features are visible and cannot enter paper claims accidentally.

## Phase 1: Correctness and Performance Baselines

### Deliverables

- Preserve the current implementation revision as the comparison baseline without retaining its
  engine in the final source tree.
- Create the pinned `benchmark/` project and machine-readable result schema.
- Define canonical 2D and 3D workloads covering small latency, medium, and publication-scale cases.
- Record initialization, first-MCS, warm steady-state, memory, allocation, synchronization,
  transfer, compilation, and kernel metrics.
- Capture CPU results and hardware-backed results for every locally or remotely available GPU.
- Establish minimal reference models and initial-state checksums.
- Record known scientific defects separately from valid baseline behavior.
- Add repeatable commands that emit provenance and raw measurements without modifying package code.

### Exit gate

- A clean checkout of the baseline revision can reproduce the correctness and performance captures.
- Every performance comparison can distinguish setup, compilation, first MCS, and steady state.
- Invalid historical behavior is not used as a correctness-qualified performance target.

## Phase 2: Repository Structural Migration

### Deliverables

- Move `PottsToolkit` to the repository root while preserving its UUID.
- Remove the `Potts` umbrella package and its re-export behavior.
- Retain `CorePotts`, `MakiePotts`, and `NeuralPotts` as independent packages under `lib/`.
- Enforce the accepted dependency direction and remove unnecessary low-level dependencies from
  `PottsToolkit`.
- Establish package-local test ownership, `integration/`, `benchmark/`, and `paper/` environments.
- Apply the accepted manifest policy and complete compatibility bounds for the frozen dependency
  set.
- Ignore generated documentation, media, data stores, profiler traces, and benchmark results.
- Rewrite CI paths and setup scripts for the new package locations.
- Move files into the accepted responsibility-oriented source directories without redesigning
  their behavior in the same changeset.

### Exit gate

- Each package loads and tests independently from a clean environment.
- Cross-package integration tests run from their own environment.
- CPU and one available real-GPU smoke workload execute through the structurally moved code.
- No released package depends on an upward layer or satellite.
- There is no root `Potts` runtime package and no duplicated test ownership.

## Phase 3: Reference Semantics and Conformance Foundation

### Deliverables

- Build small, clear CPU reference implementations for proposal probabilities, local energy
  changes, acceptance, tracker updates, lifecycle transactions, and normalized attempt accounting.
- Implement canonical state snapshots and logical comparison helpers independent of physical array
  layout.
- Create reusable invariant tests for ownership, IDs, capacity, properties, topology, trackers, and
  transaction atomicity.
- Define statistical test procedures, sample sizes, tolerances, failure reports, and tiering.
- Parameterize conformance cases over numeric policy, algorithm, dimension, and backend.
- Add semantic seed, model fingerprint, initial checksum, backend report, and reproduction command
  to randomized test failures.
- Create the specification-to-test evidence index.

### Exit gate

- A new implementation can be evaluated without inspecting the old engine's internals.
- Reference and conformance layers do not import GPU implementation details.
- All accepted state, time, topology, numerical, and transaction invariants have executable homes,
  even when some optimized implementations remain pending.

## Phase 4: Core State and Scientific Protocols

Execution chunks: [Phase 4 chunk plan](audits/phase-4-chunk-plan.md).

### Deliverables

- Implement stable owner, cell, cell-type, medium-domain, property, component, relation, event, and
  algorithm identifiers.
- Implement immutable schemas, descriptors, requirements, capabilities, and numerical policies.
- Replace current state storage with a logical interface that permits backend-specific physical
  layouts without exposing them publicly.
- Implement fixed capacity, deterministic slot reuse, exact integer state, and initialization
  finalization invariants.
- Establish public state accessors and ordinary Julia multiple-dispatch protocols for components,
  proposals, trackers, events, topology, and algorithms.
- Add conformance helpers for third-party scientific extensions.
- Implement the accepted sequential CPU reference vertical slice over the logical state.
- Compile one public PottsToolkit volume-plus-contact model spelling to that reference path.
- Record remaining legacy execution dependencies without exposing them as the new public contract.

### Exit gate

- CorePotts can construct and inspect a valid CPU state solely through final protocols.
- Stable extension examples pass conformance without depending on PottsToolkit.
- Public types do not encode a particular GPU backend or mutable compilation cache.
- A complete normalized MCS runs through the reference engine with deterministic replay, exact
  attempt accounting, local-delta checks, extinction handling, and invariant validation.
- One PottsToolkit model compiles to and executes through that CorePotts path.
- Representative public calls are type-stable and allocation behavior is characterized; reference
  allocations are recorded without being treated as production performance acceptance.

## Phase 5: Execution, RNG, Workspaces, and Backends

### Required gate

Complete D2 before freezing the RNG engine and distribution interface.

### Deliverables

- Introduce explicit execution plans, persistent state, reusable workspaces, launch policy,
  synchronization policy, transactions, and backend capability reports.
- Replace the obsolete KernelAbstractions dependency/event wrapper with ordering valid for the
  supported KA API.
- Implement semantically addressed counter-based randomness with named streams and contract
  versioning.
- Qualify raw RNG bits and every required distribution on CPU, AMDGPU, and Metal.
- Centralize Adapt-based movement and ensure adapted state contains device-valid values only.
- Remove migrated legacy state types, exports, and direct field contracts as their production
  consumers move to compiled execution state.
- Inventory and specify every atomic operation, overflow rule, memory-ordering need, contention
  behavior, and reproducibility class.
- Move scratch allocation out of steady-state paths and expose required memory in reports.
- Instrument launches, allocations, host synchronization, and transfers.
- Implement explicit failure before launch for unsupported capability/backend combinations.

### Exit gate

- A backend-neutral execution plan can be adapted and launched on CPU and available GPUs.
- RNG known-answer vectors and semantic-address tests pass across claimed backends.
- Qualified steady-state primitives allocate no host or device memory.
- There is no incidental host synchronization in a qualified internal execution path.
- Device-code checks show no invalid dynamic dispatch or host-only values in representative kernels.

## Phase 6: Topology, Components, Proposals, and Trackers

### Required gate

Complete D3 for every required field coupling before freezing its scientific category.

### Deliverables

- Implement compiled Cartesian domain, proposal, energy, surface, connectivity, query, field, and
  conflict relations as distinct roles.
- Implement canonical offsets, periodic realization, weights, owner domains, obstacles, and 2D/3D
  measures.
- Implement required energy, constraint, drive, and kinetic-modifier component categories.
- Implement neighbor-site proposals, forward/reverse proposal probabilities, conventional and
  Metropolis-Hastings acceptance, and zero-temperature behavior.
- Implement derived trackers as transactional cached state with reference recomputation.
- Implement surface, contact, spatial-query, field-sampling, chemotaxis, and focal-point contracts.
- Establish generic implementations first, then isolated measured specialization using
  AcceleratedKernels, KernelIntrinsics, Atomix, or backend extensions where justified.
- Remove every migrated legacy dependency from the compiled scientific path. Freeze the historical
  algorithm stack as an explicitly inventoried Phase 7 quarantine; do not add consumers to it.

### Exit gate

- Local delta calculations match full reference recomputation.
- Forward/reverse proposal and acceptance fixtures pass.
- Tracker caches match recomputation after accepted, rejected, lifecycle, and boundary cases.
- Required 2D/3D cases pass CPU `Float32`/`Float64` and available-GPU `Float32` conformance.
- Surface and field reports expose the exact measure, relation, boundary, and coupling semantics.
- The compiled scientific component/evaluation/transaction path has no dependency on quarantined
  penalties, samplers, topology structures, tracker paths, or closures.

## Phase 7: Algorithms and Normalized MCS

Current implementation status and requirement-level evidence live in the
[Phase 7 completion audit](audits/phase-7-completion-audit.md). The three-backend exit gate is
complete. Broader performance comparison belongs to Phase 12, family-specific lifecycle
distributions belong to Phase 8, and no equilibrium or sequential-kinetic equivalence is inferred
for processes whose guarantee profile explicitly does not claim it.

### Required gate

Complete D1 for every algorithm intended for implementation or a paper claim. Complete the
augmented/mechanical law and normalized-time contract for every volume or surface auxiliary family
intended for stable support; auxiliary state is not deferred around the algorithm architecture.

### Deliverables

- Implement the conventional sequential reference algorithm first.
- Keep the historical penalty, sampler, topology, tracker, and kernel stack quarantined and prohibit
  new consumers. PottsToolkit's production compiler, events, persistence paths, docs, and tutorials
  still depend on that engine, so deleting it before their migration would strand the repository.
  Delete the stack atomically with the PottsToolkit production-compiler migration in Phases 10-11;
  no compatibility layer is required before the paper API freeze.
- Implement `SequentialCPM`, `SequentialEquilibrium`, `CheckerboardSweepCPM`, and `LotteryCPM` as
  separately named scientific processes with explicit guarantee profiles. Use `Approximate` in a
  name only for a deliberate relaxation of a named contract; qualify every use of `exact` by the
  particular guarantee.
- Make `SequentialCPM` the backend-independent no-algorithm default. GPU selection emits one
  informational message and never silently changes the scientific algorithm.
- Make every public step advance exactly one normalized MCS.
- Make lottery algorithms derive activation and internal rounds from qualified compiled topology,
  with one activated attempt per mutable site in expectation. Activated no-ops and dynamic conflict
  losers consume their budget; evolving contention does not trigger compensating work.
- Randomize residual-round placement and any semantically meaningful round order; validate per-site
  activation, boundary classes, waiting times, and spatial correlation rather than only global `N`.
- Implement checkerboard as the explicitly distinct once-per-site `CheckerboardSweepCPM` process.
- Update time-dependent quantities between internal sub-rounds at their accepted rate without
  exposing sweeps as public time.
- Integrate first-class mechanical state through the same component, semantic RNG, conflict,
  backend, snapshot, and lifecycle protocols. Remove the invalid historical HST terminology; require
  fluctuating volume pressure and surface tension for the paper and keep length and focal auxiliary
  families experimental until independently qualified.
- Implement conflict handling, acceptance, tracker commits, and RNG addressing without scheduling
  races.
- Prove or statistically characterize checkerboard, lottery, and intrinsic behavior before naming
  equilibrium, kinetic, or equivalence guarantees.
- Report internal rounds, attempts, acceptances, conflicts, and guarantee profile.

### Exit gate

- Attempt accounting equals the normalized MCS contract for every algorithm.
- Same-run reproducibility passes at each algorithm's accepted guarantee level.
- Statistical reference batteries pass for every stable algorithm and required workload.
- Deliberately approximate algorithms are visibly named and cannot silently replace the sequential
  reference default.
- No algorithm relies on a public `sweeps_per_step` or `active_fraction` control.
- Stable volume and surface auxiliary families pass their claimed marginal or mechanical law,
  normalized-time, RNG, transaction, and CPU/Metal/ROCm evidence without incidental host sync.
- The SHA-frozen production inventory, ordered consumer-signature inventory, and clean
  replacement-path scan pass in required CI independently of pull-request history. No new package,
  test, benchmark, tutorial, example, fallback, or production call edge is added against the
  quarantined engine; final removal is owned by the explicit PottsToolkit compiler-migration gate.

## Phase 8: Lifecycle, Initialization, and Persistence

Implementation followed the completed
[Phase 8 chunk plan](audits/phase-8-chunk-plan.md). Authoritative CPU/Metal/ROCm and repository-CI
closure evidence is in the
[Phase 8 completion audit](audits/phase-8-completion-audit.md).

### Required gates

Complete D4 and D5 before freezing persistence or initialization APIs.
Resolve every P0 finding in the
[open-protocol audit](audits/open-protocol-audit.md) before freezing or implementing its owning
lifecycle or initialization interface.
Apply the [Phase 8 minimality pass](audits/phase-8-minimality-pass.md): only scientific invariants,
paper-required built-ins, minimal extension seams, and their evidence receive Phase 8 production
code.

### Deliverables

- Implement deterministic event detection, ordering, conflict resolution, validation, and atomic
  commit once at the integer-MCS lifecycle boundary after the complete proposal and mechanics MCS.
  Internal checkerboard and lottery rounds are not lifecycle time.
- Implement growth, division, inheritance, transition, death, extinction, retirement, capacity
  failure, fragmentation policy, and optional connectivity constraint.
- Implement schedules, triggers, resolvers, effects, division geometry, property lifecycle,
  auxiliary lifecycle, initialization, and persistence as open Julia protocols with required
  built-ins rather than closed behavioral enums or central `isa` switches.
- Make the property schema the only lifecycle-policy authority. Use separate typed policies for
  division, transition, and retirement; derived families declare recomputation, and auxiliary
  families own their operation-specific scientific laws without generic clone/reset fallbacks.
- Lower flexible lifecycle authoring values into concrete device descriptors. All triggers at a
  boundary read one `PreLifecycleSnapshot`; effect planning, explicit permutation-invariant conflict
  resolution, validation, and atomic commit remain distinct phases.
- Qualify binary division with compact descendant-region labels through an open geometry protocol;
  do not encode the public partition contract as a permanently binary Boolean.
- Keep lifecycle detection, planning, and commit device-resident where supported, with explicit
  bounded error reporting rather than hidden host polling.
- Implement public coordinate, rasterization, placement, and initialization semantics.
- Use one minimal layout claim-emission protocol with stable provisional identities, order-independent
  overlap resolution, generic deterministic finalization, and explicit host-finalized or
  device-native capability. Add device-native built-ins only where construction benchmarks justify
  them.
- Replace ambiguous random layout behavior with uniform site seeding and bounded sequential rejection
  placement. Qualify periodic minimum-image rasterization, self-alias rejection, atomic placement
  failure, and exact semantic RNG addressing.
- Implement logical snapshots, exact continuation checkpoints, backend-independent restart where
  promised, schema fingerprints, RNG continuation, and provenance.
- Define and test equivalent logical storage through memory and required HDF5/Zarr extensions.
- Capture stable checkpoints only at finalized MCS boundaries. Persist canonical scientific state
  and semantic counters, reconstruct replaceable caches/workspaces, require compatible fingerprints
  for exact resume, and expose changed-profile restoration as explicit logical import.
- Complete family-specific auxiliary initialization, division, transition, death, extinction, and
  retirement laws for the stable fluctuating pressure and tension families. Unsupported
  combinations fail rather than applying a generic reset or clone policy.
- Implement constitutive reset as the default mechanical division law; expose intensive preservation
  and independent stationary redraw explicitly. Preserve compatible state through growth,
  transition, and shrink death; clear on removal, immediate death, extinction, and retirement.

### Explicitly deferred from Phase 8

- Dynamic-link event targets and focal-link creation, breakage, inheritance, or persistence.
- General conflict-resolver composition, nonbinary division, exotic-geometry catalogs, lineage
  graphs, arbitrary imperative host lifecycle callbacks, and universal equilibrium-auxiliary
  machinery.
- A universal initialization source/rasterizer/placer hierarchy, arbitrary image-format loaders,
  multiple production medium domains, and mandatory GPU kernels for every custom layout.
- Remote checkpoint stores, automatic environment installation, a universal artifact framework,
  every future storage format, and unproven cross-backend bitwise continuation.

### Exit gate

- Lifecycle transaction tests pass under contention, full capacity, invalid plans, fragmentation,
  and all required backends.
- Checkpoint continuation meets the advertised exactness profile.
- Backend-independent restart and storage-equivalence fixtures pass where claimed.
- In-memory, HDF5, and Zarr records reconstruct one canonical logical checkpoint; incomplete or
  corrupt writes never load or appear complete.
- Initialization is reproducible under its semantic seed and finalizes every required invariant.
- Layout and emission-order permutations preserve canonical ownership and runtime IDs; rejected or
  empty provisional entities allocate neither slots nor property-initialization RNG identities.
- Site-seed distribution and rejection-placement retry/failure tests pass; periodic 2D/3D shapes
  preserve canonical volume without clipping or self-aliasing.
- No required lifecycle path introduces incidental per-event host synchronization.
- One combined downstream fixture adds a non-built-in GPU-valid division geometry, property
  lifecycle policy, schedule/effect, derived observable, and initialization source without modifying
  CorePotts.
- Missing, explicitly unsupported, incompatible, and ambiguous property policies fail before
  execution; multi-property failures prove atomic rollback and derived-state repair.
- Stable pressure/tension fixtures qualify constitutive reset, preservation, addressed redraw,
  transition continuity, death clearing, and generation-safe reuse on CPU, Metal, and ROCm.
- Conflict fixtures are invariant under declaration order, tuple layout, compiler batching,
  workgroup size, and launch decomposition; launch scheduling and atomic arrival never define
  biological priority.

## Phase 9: SciML Integration

Pre-interview evidence:

- [Phase 9 current-code and gap audit](audits/phase-9-current-code-and-gap-audit.md)
- [Phase 9 SciML and JuliaGPU research audit](audits/phase-9-sciml-and-gpu-research.md)
- [Phase 9 implementation chunk plan](audits/phase-9-chunk-plan.md)
- [Accepted Phase 9 interface decision](../spec/decisions/0025-phase-9-sciml-and-gpu-interface.md)
- [Phase 9 legacy evacuation](audits/phase-9-legacy-evacuation.md)
- [Phase 9 completion audit](audits/phase-9-completion-audit.md)

### Required gate

Resolve the algorithm, proposal, backend-capability, RNG-namespace, and compiled-component P1
findings in the [open-protocol audit](audits/open-protocol-audit.md) before declaring the Level 3 API
candidate. Evacuate the historical `PottsProblem`, `PottsIntegrator`, and `PottsSolution` bindings
to internal legacy names before the replacement receives those names. Capture direct-engine
structural and timing baselines before changing the authoritative call path.

### Deliverables

- Implement final model/problem ownership and `PottsProblem` construction.
- Implement `init`, `solve!`, `solve`, integer-MCS `step!`, stopping, return codes, and mutation rules.
- Implement `remake`, distinct scientific/structural fingerprints, and an explicit trajectory-free
  compilation cache with correct reuse and invalidation.
- Implement MCS-boundary saving, observations, callbacks, snapshots, and checkpoints.
- Implement `PottsSolution` indexing, interpolation restrictions, metadata, display, and provenance.
- Implement SciML ensembles with `EnsembleSeedDerivationV1`, independent semantic seeds, backend
  selection, output functions, bounded reruns, and structured failure handling.
- Implement applicable symbolic indexing through typed handles; reject generic AD through `solve`
  and unsafe live-integrator or device-workspace serialization.
- Ensure qualified device observations remain resident and host observations synchronize only at
  declared boundaries.
- Establish the layered JuliaGPU benchmark suite and qualify Julia 1.12.6 CPU, Metal, and ROCm paths
  in 2D and 3D. Keep CUDA and evolving PDE-field execution explicitly deferred.

### Exit gate

- `solve(prob)` is behaviorally equivalent to `solve!(init(prob))`.
- SciMLBase interface tests and Potts-specific conformance tests pass.
- Saving, callbacks, displays, and ensemble execution introduce no hidden observation points.
- Remake and checkpoint tests prove correct cache, RNG, and workspace invalidation or reuse.
- A warm unobserved SciML MCS adds zero launches, synchronization, transfers, device allocations,
  state copies, or RNG draws over the direct engine.
- The Phase 9.0 legacy-containment/open-protocol gate and every gate in the
  [chunk plan](audits/phase-9-chunk-plan.md) pass on their applicable backends.
- Dedicated-runner baselines show no unexplained supported-workload regression greater than 5%.

## Phase 10: PottsToolkit Typed API and Compiler

### Required gate

The non-surface-syntax portions of D6 are complete through Decisions 0017 and 0026. Level 1 spelling
remains under D7 and does not block Level 2 implementation.

### Execution order and legacy-containment gate

1. Freeze the historical PottsToolkit compiler immediately and reject new production consumers.
2. Inventory its capabilities, callers, tests, examples, and dependencies in a migration ledger.
3. Build one end-to-end replacement vertical slice covering model/problem construction,
   normalization, validation, reference evaluation, public CorePotts lowering, one interaction,
   one HST-compatible constraint, one property transaction, one stochastic rule, one lifecycle
   operation, inspection, and CPU/Metal/ROCm execution.
4. Require reference agreement, GPU residency, actionable diagnostics, and no material warm-MCS
   performance regression for that slice.
5. Migrate remaining library code and package/integration tests, then delete the closure-first,
   MLStyle, dictionary/`Any`, `LegacyPottsProblem`, and private-CorePotts path in one explicit gate.
6. Expand component coverage and the five reference workloads only through the replacement path.

Legacy deletion therefore occurs after the first proven replacement slice and before broad Phase 10
expansion, not at the Phase 10 or paper-release tail.

### Deliverables

- Implement immutable Level 2 model, domain, cell, medium, property, component, rule, phase, and
  problem builders using ordinary Julia functions and structs.
- Implement namespaced fragments, binding, override rules, provenance, and order-independent
  declarations outside explicit phases.
- Introduce source-located typed semantic IR, host reference evaluation, staged validation, effect
  analysis, dependency analysis, and simultaneous property transactions.
- Lower normalized IR into concrete CorePotts descriptors and callable structs.
- Implement stable semantic fingerprints, compilation reports, source maps, and invalidation.
- Bound specialization and replace unnecessary generated functions with ordinary implementations.
- Prove the zero-compiler-switch rule with downstream Level 2 and direct CorePotts extensions;
  require registration only for Level 1 spelling, semantic serialization, or compatibility names.
- Establish canonical `show`, inspection, semantic serialization, and diagnostic behavior.
- Implement the five reference-model categories as ordinary Level 2 compositions: single-cell
  migration, prescribed-gradient chemotaxis, monolayer growth, differential-adhesion sorting, and
  elongation-driven angiogenesis. This is reference-model coverage, not OpenVT schema or bigraph
  compatibility.
- Remove closure-first and MLStyle-dependent prototype paths at the legacy-containment gate above;
  do not retain a compatibility compiler after conformance parity.

### Exit gate

- Representative models can be written entirely through the Level 2 API.
- Host reference evaluation and compiled CPU/GPU evaluation agree under the applicable numerical
  contract.
- Invalid models fail before backend launch with source-located, actionable diagnostics.
- Construction, lowering, compilation/first-use, allocations, and warm execution are measured;
  real-device compiler acceptance and zero warm device allocation pass. Quantitative native-code,
  register, spill, and occupancy budgets are frozen and enforced in Phase 12 with backend-native
  profilers rather than guessed through a nonexistent portable KernelAbstractions counter.
- CorePotts remains directly usable without PottsToolkit IR.
- A conforming Level 3 component lowers through PottsToolkit Level 2 without a central concrete-type
  switch or a mandatory runtime registry.
- Level 2 is the sole PottsToolkit semantic path; all five reference workloads are expressible, no
  production source or test depends on the historical compiler, and CPU/Metal/ROCm residency gates
  pass.

## Phase 11: PottsToolkit Level 1 DSL

### Required gates

Complete D6 and D7 before declaring the public API candidate.

### Deliverables

- Implement thin, hygienic macros over the complete programmatic builder interface.
- Implement the accepted closed Julia-first rule subset and reject unknown syntax.
- Preserve source locations, semantic RNG identities, query meanings, effects, phases, and
  simultaneous commit behavior through lowering.
- Implement final model declaration, fragment, binding, rule, phase, interpolation, and display
  spelling.
- Add optional units only as solution post-processing and analysis metadata. Unit handling must not
  enter model normalization, fingerprints, RNG, CorePotts lowering, or GPU stepping.
- Generate the stable-component inventory and measure DSL coverage.
- Provide explicit Level 2/3 escape routes for the components not representable at Level 1.
- Exercise representative ordinary, advanced, and extension models before freezing names.

### Exit gate

- At least 95% of stable components have a natural Level 1 spelling.
- Level 1 and equivalent Level 2 models normalize to the same semantic fingerprint.
- Macro expansion contains no engine execution and diagnostics identify user source.
- The complete API candidate has no legacy aliases, constructors, or duplicate modeling paths.
- The Phase 10 legacy-deletion gate remains intact: Level 1 adds only syntax over the replacement
  Level 2 path and cannot restore aliases, duplicate compilers, quarantined penalties, samplers,
  trackers, kernels, or the historical HST implementation.

## Phase 12: Performance Recovery and Backend Qualification

### Deliverables

- Profile canonical end-to-end workloads and identify actual launch, synchronization, memory,
  reduction, atomic, layout, register, occupancy, and compilation bottlenecks.
- Qualify AcceleratedKernels primitives and reusable scratch behavior before adoption.
- Isolate KernelIntrinsics use behind generic fallbacks and equivalence tests.
- Tune operation-specific workgroups and layouts rather than impose one universal configuration.
- Add separately optimized CPU implementations where evidence justifies them under the same
  scientific contract.
- Run the full benchmark matrix in separate backend processes with synchronized timing.
- Compare against the frozen baseline and retain raw, versioned results.
- Run semantically matched external comparisons separately from internal regression gates.

### Exit gate

- No representative core workload regresses by more than 5% without accepted written justification.
- The geometric mean across core workloads does not regress.
- Qualified steady-state GPU workloads allocate no memory and introduce no internal host wait.
- Compilation latency, first-MCS latency, memory, and steady-state throughput pass independent gates.
- CPU, AMDGPU, and Metal claims are backed by real hardware results rather than compilation
  alone.

## Phase 12.5: Tiled Checkerboard Engine and Sultan-Class Study

Phase 12.5 is a roadmap-level phase, distinct from the internal work packages in the Phase 12 chunk
plan. It begins only after Phase 12 closes and must resolve before Phase 13 freezes the public API.

Phase 12.5 is complete with `TiledCheckerboardCPM` retained as an explicitly experimental research
algorithm. Its negative performance result, qualified implementation boundary, and future
promotion requirements are recorded in the
[Phase 12.5 completion audit](audits/phase-12-5-completion-audit.md).

### Deliverables

- Reconstruct the published Sultan et al. model and measurement conditions wherever the paper
  specifies them, recording every irreducible ambiguity rather than inventing an exact match.
- Define and implement the separately named `TiledCheckerboardCPM` algorithm with deterministic
  sub-round snapshots, exact reconciled public boundaries, expected-proposal-budget MCS
  normalization, and schedule-independent counter RNG identities.
- Execute proposals sequentially within each tile and concurrently across nonconflicting active
  tiles, with topology-derived halos and validated tile-switching policies.
- Provide an open tiled-component protocol for dependency radius, snapshot-visible cell state,
  scratch requirements, device-callable energy contributions, and deterministic reconciliation.
- Qualify volume, surface/perimeter, adhesion, prescribed-field chemotaxis, directional motility,
  Act-like history, and first-class HST-compatible state where applicable.
- Provide semantically identical shared-memory and device-global storage strategies, full 2D and 3D
  execution, and CPU, Metal, and ROCm qualification through KernelAbstractions with measured
  backend-specific specialization.
- Add a normal PottsToolkit spelling, expert configuration, provenance, documentation, benchmark
  fixtures, statistical validation, native profiles, and repeated paper-scale measurements.
- Decide from predeclared evidence whether to promote, retain experimentally, or reject the engine.

### Exit gate

- Exact state/accounting invariants and the predeclared statistical-equivalence battery pass.
- Repeated runs reproduce trajectories on the same backend and agree statistically across qualified
  backends.
- Unobserved stepping remains GPU-resident, allocation-free, transfer-free, and free of host
  synchronization; observation is an explicit boundary and does not alter the stochastic schedule.
- The engine improves at least two representative paper-scale GPU workloads by 2x over
  `CheckerboardSweepCPM`, improves the supported GPU matrix geometric mean, and does not obtain speed
  by weakening physics, precision, or MCS normalization.
- Existing algorithms retain their semantics and pass the accepted Phase 12 regression budgets.
- Comparisons with Sultan et al. distinguish matched absolute throughput from speedup ratios against
  different serial baselines; unmatched hardware or semantics are labeled descriptive.
- CPU, Metal, and ROCm have repeated correctness, performance, memory, compilation, and native-code
  evidence on the exact completion revision.
- `TiledCheckerboardCPM` is explicitly promoted, marked experimental, or rejected before Phase 13.

## Phase 13: Algorithmic Conformance, API Freeze, and Full Conformance

Phase 12.CPU, the remaining Phase 12 closure gate, and Phase 12.5 are complete. Phase 12.5 enters
this phase with `TiledCheckerboardCPM` retained as an explicitly experimental research algorithm.
Phase 13 keeps it out of automatic selection, the stable performance surface, and paper claims. Its
current name and configuration are not frozen as stable API; any future promotion requires a new
scientific, portability, and performance qualification decision. The accepted algorithmic work is
detailed in the
[transition-kernel contract](../spec/transition-kernel-verification.md) and
[Phase 13 chunk plan](audits/phase-13-transition-kernel-chunk-plan.md).

### Deliverables

- Implement an independent finite-state oracle for primitive proposal, internal-round, and complete
  normalized-MCS transition kernels without reusing optimized proposal, delta, conflict, or commit
  code.
- Verify the declared sequential process and characterize the production checkerboard scheduler in
  lifted scheduler state without assuming kinetic, detailed-balance, or stationary equivalence.
- Assign checkerboard an evidence-supported guarantee label using transition support, total
  variation, stationarity, probability currents, relaxation, and observable drift/diffusion.
- Qualify applicable empirical transition rows on CPU, Metal, and ROCm through independent replicas
  and corroborate tiny-state findings with realistic-scale ensembles.
- Archive machine-readable matrices, raw counts, thresholds, parameter grids, analysis programs,
  provenance, and paper-figure inputs.
- Review every export, extension point, constructor, report, display, and error type.
- Mark the final stable, experimental, and internal surfaces explicitly.
- Run Aqua, ambiguity checks, representative JET/inference checks, allocation assertions, device
  code inspection, doctest candidates, and clean-environment installation tests.
- Run deterministic, moderate statistical, and large scheduled/pre-release conformance tiers.
- Complete the specification-to-test evidence index and close every required decision gate.
- Remove every remaining legacy path, stale dependency, unqualified claim, and provisional behavior
  from the stable surface.
- Freeze the RNG, IR, checkpoint, model-fingerprint, and result-schema contract versions used by the
  paper release.

### Exit gate

- Sequential execution passes its applicable independent reference obligations.
- Checkerboard has a scoped evidence-supported guarantee rather than an inherited equivalence claim.
- CPU, Metal, and ROCm pass applicable empirical transition tests, and realistic-model claims have
  larger-ensemble corroboration.
- All accepted core semantics have conformance evidence.
- Every required public extension function is documented by its contract and tested.
- Clean environments can install, load, test, and exercise each package independently.
- No stable API depends on a deferred feature or undocumented historical behavior.
- The project owner explicitly approves the paper API freeze.

After this gate, incompatible API changes require an explicit release decision. Before this gate,
compatibility shims remain unnecessary.

## Phase 14: Model-Driven Capability Completion, Documentation, and Runtime Foundation

Phase 14 is governed by
[Decision 0029](../spec/decisions/0029-phase-14-model-driven-capability-and-documentation-policy.md)
and the [Published-Model Reproduction Semantics](../spec/published-model-reproduction-semantics.md).
Its parallel ProcessBigraphs foundation is governed by
[Decision 0034](../spec/decisions/0034-process-bigraph-runtime-platform.md), the
[runtime parity audit](audits/process-bigraph-runtime-parity-and-parallel-development-audit.md),
and the [completed owner interview](audits/process-bigraph-runtime-owner-interview.md).
It does not reopen Phase 13 indiscriminately. Existing frozen contracts remain frozen; additive
capabilities are admitted only through accepted semantics, sequential CPU reference use, version
impact review, conformance, persistence, inspection, and the claimed backend evidence.

Phase 14 has four parallel workstreams:

- **Potts scientific closure:** preserve the locked G3-B sequential CPU reference, close G4 on
  CPU/Metal/ROCm, then close the remaining portfolio-owned capability rows.
- **Runtime foundation:** specify and begin the independent domain-neutral package without moving
  the Potts-owned coupled executor wholesale.
- **Adapter and join design:** record differential fixtures and ownership boundaries without
  cutting over a model or freezing a field adapter before its source Potts evidence passes.
- **Evidence and documentation:** preserve Potts release evidence while creating independent
  runtime specifications, internal documentation, registries, and CI identities.

These workstreams may advance independently. A Potts claim never proves runtime parity, and an
internal runtime milestone never weakens a Potts backend or paper gate.

The five Phase 10 reference workloads and Phase 13 realistic-model battery remain valid compiler and
algorithm evidence. They are not evidence that the published biological models below have already
been reproduced.

### Phase 14.0: Corpus, Sources, and Adversarial Requirements Audit

#### Deliverables

- Select and freeze a 4--6-model release portfolio. It MUST include at least one flagship model
  associated with each of Glazier, Wortel, and Jiang. The initial target set contains:
  - a foundational Glazier--Graner differential-adhesion/cell-sorting model;
  - a Wortel cell-migration/Act-CPM model;
  - a Jiang collective-tumor-migration model; and
  - a Glazier--Jiang angiogenesis model.
- Pin the exact papers, figures or tables, supplements, source-simulator revisions, datasets,
  licenses, and permitted assets. Record an authority order and every conflict or unavailable input.
- Create one versioned model record per selected paper with domain, topology, all spatial roles,
  parameters and units, initialization, attempt budget, algorithm, update schedule, field splitting,
  lifecycle behavior, seeds, replicates, observations, analyses, and target results.
- Build a model-to-capability requirements matrix that classifies every requirement as:
  - already supported and conforming;
  - expressible through an existing stable extension protocol;
  - requiring an additive reusable CorePotts or PottsToolkit capability;
  - requiring an incompatible frozen-contract decision; or
  - paper-specific assembly or analysis that belongs with the reusable model source.
- Audit at minimum the known pressure points: independent proposal/contact/surface/query relations;
  source-specific MCS attempt budgets; accepted-copy site history; evolving reaction--diffusion
  fields, secretion, uptake, and named splitting; vector cell state and history; dynamic focal or
  relationship graphs; degradable structures; staged protocols; and paper-defined observables.
- Maintain a separate Morpheus model-semantic compatibility matrix for global/per-cell/field/
  membrane systems, differential equations, synchronous rules, assignments, functions, delays,
  events, multirate clocks, typed mappers/reporters, lifecycle requests, and external-system
  adapters. Product-level GUI, XML editing, plotting, and job-management parity is not required.
- Give each missing semantic family an owner, specification/decision dependency, conformance plan,
  persistence impact, API layer, backend claim, and implementation chunk. Unknowns remain explicit;
  implementation convenience MUST NOT settle them.

#### Exit gate

- D8 is complete for the exact portfolio, and every selected result has a source record and named
  validation target.
- Every paper mechanism and execution detail is mapped; no required behavior is hidden in a page,
  private simulator, or unowned “model glue” category.
- Every proposed change to a Phase 13 contract is classified as additive or incompatible. An
  incompatible change has an explicit D10 release decision before implementation.
- The release portfolio can change only through an owner-approved scope amendment recording the
  scientific and release-claim impact.

#### Completion evidence

Phase 14.0 complete as of 2026-07-24. The
[completion audit](audits/phase-14-0-corpus-and-requirements-audit.md) freezes six versioned source
records and named validation targets; the
[source-closure registry](audits/phase-14-source-closure-v1.toml) records exact transcriptions or
bounded sensitivity plans plus license dispositions; the
[D9 work-item registry](audits/phase-14-d9-work-items-v1.toml) owns every missing semantic family;
and [Decision 0030](../spec/decisions/0030-phase-14-coupled-dynamics-and-freeze-impact.md) accepts
the additive D10 assessment. Individual Phase 14.1 D9 contracts remain Provisional until their
prototype and conformance gates pass. The
[semantic simplification audit](audits/phase-14-semantics-simplification-audit.md) found that the
requirements remain sound but the candidate surface has overlapping semantic authorities.
The [focused owner interview](audits/phase-14-semantics-focused-interview.md) accepted all 15
recommended decisions. [Decision 0031](../spec/decisions/0031-phase-14-single-semantic-kernel.md)
and [registry v2](../spec/phase-14-contract-registry-v2.toml) therefore replace the 24-contract
candidate decomposition with one seven-area semantic kernel. The architecture checks and Wortel
CPU-reference vertical slice now pass. [Decision 0032](../spec/decisions/0032-phase-14-gpu-native-promotion.md)
and the [GPU-native implementation plan](audits/phase-14-gpu-native-implementation-plan.md) require
backend-resident Metal and ROCm qualification for every stable Phase 14 execution capability.
Wortel GPU closure passed on real Metal and ROCm on 2026-07-25. Wang G3-A and the revision-7 G3-B
sequential CPU reference passed; the authoritative
[closure ledger](audits/phase-14-g3b-closure-ledger-v1.toml) records `overall_status = "passed"` and
the [attested manifest](evidence/phase-14/g3b-closure/manifest-v1.toml) records the exact tested
commit and evidence tree. [Decision 0035](../spec/decisions/0035-wang-sequential-gpu-disposition.md)
retires assembled Wang Metal/ROCm qualification because the unchanged paper-faithful sequential
algorithm is not a suitable GPU release gate. G4 is current and qualifies the reusable field
substrate on CPU, Metal, and ROCm without creating an assembled Wang GPU claim.
The [generic authoring simplification audit](audits/phase-14-generic-authoring-simplification-audit.md)
and [Decision 0033](../spec/decisions/0033-phase-14-generic-hierarchical-authoring.md) additionally
require complex models to compose through generic nested `ModelFragment` values with named typed
requirements and exports plus one explicit root plan. Paper-specific builders cannot substitute for
this generic fixture.

### Phase 14.1: Modeling Primitives and Conformance

#### Deliverables

- Implement every required capability through the single state/process/plan/lifecycle/observation
  kernel. Spatial roles and Potts algorithm identities remain focused contracts. No façade may own
  a second clock, scheduler, runtime, persistence scheme, or identity graph.
- Extend the existing `ModelFragment` boundary for named typed requirements and exports, nested
  generic composition, private declaration enforcement, and direct-versus-fragment canonical
  identity. Retain flat Phase 13 construction and add no paper-specific core constructors.
- Derive fingerprints, continuation/checkpoint requirements, preflight, inspection, and
  compatibility reports from the canonical kernel rather than authoring parallel descriptions.
- Keep equation-style `ContinuousSystem` declarations as façades that lower completely to the
  kernel. Qualify sampled events separately; adaptive, root, DAE, SDE, reaction, and jump families
  remain Experimental until their source-backed promotion gates pass.
- Implement the smallest reusable capability justified by the corpus in CorePotts or PottsToolkit.
  Paper-specific parameters and analysis remain in model source; reusable scientific behavior does
  not.
- Prove each slice first through an ordinary sequential CPU reference path and then through
  backend-resident Metal and ROCm execution before opening the next slice: Wortel, then Wang, then
  one field model. Add PottsToolkit Level 2 and natural Level 1 façades only when they normalize
  identically to the direct kernel spelling.
- Extend semantic manifests, fingerprints, reports, persistence, restart, SciML observation and
  saving, capability preflight, and backend adaptation without silently changing frozen meanings.
- Add exact, invariant, randomized reference, lifecycle, restart, and statistical conformance as
  applicable. All simulation state, dynamic fields, relationships, queues, and auxiliary state
  MUST remain backend-resident during GPU execution. Hidden scalar host loops, host fallback,
  per-MCS transfers, and steady-state allocation cannot qualify.
- Require CPU reference support plus real-hardware Metal and ROCm evidence for every stable or
  release Phase 14 execution capability. Unsupported backend pairs may remain Experimental, but
  cannot be promoted as part of the stable portfolio and cannot inherit a Phase 13 claim.
- Use the portable GPU qualification profile (`Float32` where floating-point state is involved);
  retain CPU `Float64` paper-fidelity studies as a separate evidence profile. Host work is limited
  to pre-launch authoring/lowering and explicit observation, checkpoint, snapshot, and analysis
  boundaries with bounded, measured transfers.
- Measure compilation, allocation, synchronization, transfer, memory, and steady-state performance
  for the completed vertical slices. Optimize only after reference agreement.

#### Exit gate

- Every mechanism required by the selected portfolio lowers to the one public, inspectable Potts
  canonical kernel without private storage access or a parallel Potts authority. ProcessBigraphs
  migration occurs only through the separately gated adapter path.
- The stable kernel subset passes the registered Morpheus time-scale, ODE, synchronous-rule,
  delay, sampled-event, mapper, field-coupling, and lifecycle microfixtures with derived
  construct-level compatibility reports.
- Every new stable contract is Accepted, versioned, reference implemented, mapped to conformance
  evidence, and covered by the D10 compatibility assessment.
- Checkpoint/restart reproduces dynamic fields, site state, per-cell state, relationships,
  staged-protocol position, semantic time, and RNG continuation wherever present.
- Every stable Phase 14 execution capability has sequential CPU reference evidence and
  corresponding real-hardware Metal and ROCm evidence. Unsupported combinations remain
  Experimental and fail before execution with actionable diagnostics.
- GPU qualification demonstrates backend residency, absence of hidden host fallback and per-MCS
  transfers, bounded declared synchronization, deterministic replay or stated statistical
  equivalence, checkpoint/restart, and measured allocation, transfer, and steady-state performance.
- Existing Phase 12 correctness-qualified performance gates still pass; adding a model capability
  does not excuse a regression in models that do not use it.
- The selected models reach complete bounded smoke runs before documentation presentation work
  begins.

### Phase 14.PB0: Parallel ProcessBigraphs Foundation

This workstream begins after attested G3-B and proceeds concurrently with G4 and the existing
Phase 14 documentation/model work. It does not replace the Potts Phase 14.1 kernel and does not
require a CorePotts dependency cutover.

**Status:** Passed as a bounded foundation on 2026-07-26. The independent package, direct
microfixtures, implementation audit, and machine-readable evidence pass. This does not claim the
Phase 15 internal alpha, pinned Python-oracle parity, GPU or parallel executors, dynamic structure,
the Potts adapter, or a public release.

#### Deliverables

- Freeze the initial Process-Bigraph and Bigraph-Schema commits and create a machine-readable parity
  registry covering every required feature, authority classification, fixture, evidence state,
  persistence/failure disposition, documentation obligation, and backend claim.
- Specify typed hierarchical stores, stable paths, schemas, ports, processes, steps, typed deltas,
  update/conflict laws, exact normalized-integer logical time, deterministic batches, reconciliation,
  atomic commit, structural requests, continuation, observation, failure, and capability declarations.
- Establish `lib/ProcessBigraphs/` as an independently valid internal package with its own identity,
  project, source, tests, internal documentation, compatibility declarations, and CI lane.
- Implement only independently testable serial foundations whose semantics are already accepted:
  paths, schemas, ports, store projections, delta values, exact time, canonical encoding, and
  non-Potts microfixtures.
- Record the future CorePotts adapter boundary, old/new serial differential plan, checkpoint-reader
  obligations, and one-slice-at-a-time cutover rules without importing Potts dependencies into the
  runtime.
- Permit early Dagger placement experiments only as disposable measurements. No `DaggerExecutor`
  support or parity claim is admitted in this workstream.

#### Join and non-freeze gate

- G4 may repair backend plumbing but MUST NOT change G3-B storage semantics, ordering, RNG
  addressing, publication boundaries, or attested checkpoint behavior.
- Final portable-executor ownership and device graph/state adaptation use focused G4 evidence; no
  Wang-through-runtime GPU claim is planned.
- Generic field/PDE adapter contracts, stencil/boundary taxonomies, field continuation codecs, and
  convergence/splitting semantics remain unfrozen until G4 closes.
- Lifecycle queues, sampled events/delays, relationship/degradation dynamics, and hierarchical
  structural rewrites are co-designed once, not independently stabilized in two runtimes.
- The foundation gate passes when the pinned registry and runtime specifications are internally
  consistent, the package scaffold is independently testable, serial primitive microfixtures pass,
  and no runtime or public-release claim exceeds that evidence.

### Phase 14.2: Learn and Examples

#### Deliverables

- Rebuild the manual as one Documenter site organized as Learn, Examples, Published Models,
  Concepts and Guarantees, and API.
- Create 12--15 guided tutorials for the primary audience of biologists and new CPM users. Progress
  through Beginner, Model Builder, Research Workflows, and Advanced Extensions, using 2D before 3D
  and CPU-portable defaults with explicit GPU callouts.
- Teach model construction, initialization, adhesion and constraints, fields and chemotaxis,
  algorithms and guarantees, reproducibility, lifecycle, observation, analysis, persistence,
  performance/backends, extensions, and a complete research workflow.
- Build Examples as focused, original, citable programs. Paper-inspired simplifications are labeled
  Inspired Example and remain separate from Published Models.
- Keep reusable Julia sources separate from prose and execute their numerical assertions in pull-
  request CI. Separate expensive animation, dashboards, and large data generation from fast checks.
- Rewrite or cite content and retain only licensed assets. Add a contribution template requiring
  provenance, scientific scope, support, validation, runtime, and maintenance ownership.

#### Exit gate

- The guided sequence is coherent from first simulation through reproducible research and advanced
  extension, with no prerequisite taught only after its first use.
- Every fast tutorial and example executes from the clean documentation environment on the final
  API, and all expensive outputs have reproducible commands and artifact identities.
- No Inspired Example is presented as a reproduction, and every literature-derived choice has
  visible provenance.

### Phase 14.3: Published Models

#### Deliverables

- Implement the selected 4--6 published models as reusable Julia model programs backed only by
  accepted library behavior and explicit paper-specific assembly and analysis.
- For every model, reproduce a named paper figure, table, statistic, or described result as closely
  as the pinned source permits. Report mechanistic, execution, parameter, output, and result
  fidelity separately.
- Materialize every consequential default in a machine-readable model manifest, including spatial
  roles, attempt budget, update schedule, parameters, initialization checksum, semantic seeds,
  algorithm, precision, backend, replicates, observables, and analysis version.
- Complete D11 before final runs. Preserve exploratory runs separately; final tolerances, sample
  sizes, stopping rules, exclusions, and source baselines cannot be changed after results are seen
  without a new study version.
- Use Quantitative Reproduction as the release target whenever the source exposes a quantitative
  endpoint. Use Qualitative Reproduction only for an intrinsically qualitative or irreducibly
  underspecified target, never as a post-failure downgrade.
- Record deviations and sensitivity analyses for consequential ambiguities. Obtain collaborator
  review for the Glazier, Wortel, and Jiang flagships and apply `Author Reviewed` only when the
  recorded scope and result were actually reviewed. An unavailable collaborator requires the
  recorded owner-approved exception in Decision 0029; review attempts and the missing badge remain
  visible.
- Archive raw results, manifests, environments, source records, analysis programs, output
  checksums, figures, and animations through content-addressed artifacts or a release archive.

#### Exit gate

- Every selected model passes its preregistered release-status target from a clean pinned
  environment and exposes retrievable evidence.
- Every page links to its reusable source, manifest, validation plan, raw evidence, generated
  outputs, deviations, backend limitations, and author-review status.
- Each Glazier-, Wortel-, and Jiang-associated flagship has collaborator review or the explicit
  owner-approved unavailable-reviewer exception.
- No simplified or failed model is silently substituted, removed, or described as reproduced. Any
  portfolio or target-status change has the required owner-approved scope amendment.

### Phase 14.4: Full Manual and Satellites

#### Deliverables

- Complete Concepts and Guarantees plus Level 1 through Level 4 API progression, with every stable
  export documented and every experimental/internal surface visibly separated.
- State algorithm guarantees, backend support, precision, synchronization/observation boundaries,
  reproducibility, and evidence level wherever a result could otherwise be misinterpreted.
- Replace tracked generated documentation and large media with reproducible artifact references;
  retain only small licensed source assets.
- Migrate MakiePotts against frozen observation and solution APIs, with no hidden observation,
  synchronization, transfer, or stochastic-schedule change.
- Restore or redesign only NeuralPotts capabilities that have explicit Phase 14 scope and
  conformance; keep the remainder Experimental without constraining CorePotts or PottsToolkit.
- Validate all navigation, cross-references, doctests, source links, artifact retrieval, clean
  builds, and deployment configuration.

#### Exit gate

- Every documentation page uses the final API and passes its applicable clean-build or executable
  check.
- No generated `docs/build` product or unlicensed/irreproducible large output is tracked.
- Published-model statuses and support claims agree with their manifests and archived evidence.
- MakiePotts introduces no hidden synchronization beyond requested observation boundaries.
- All Potts Phase 14.0--14.4 gates and the separately evidenced Phase 14.PB0 foundation gate pass;
  completing prose alone cannot close the shared Phase 14 program.

## Phase 15: Potts Paper/Release Qualification and ProcessBigraphs Internal Alpha

The Phase 12.5 tiled engine is excluded from fastest-engine and production-backend claims. Phase 15
may report its negative/experimental result or reproduce its research measurements, but must not
use it as release evidence without a separately accepted promotion gate. Phase 15 consumes the
frozen Phase 14 corpus, manifests, validation plans, capability versions, and evidence statuses. It
qualifies the Potts paper release; it does not repair model semantics or choose easier validation
targets after observing results.

In parallel, ProcessBigraphs advances from Phase 14.PB0 foundations to an internal serial alpha.
The Potts release gate and runtime-alpha gate are independent. Potts may release when its gate
passes even if runtime parity is incomplete. Internal alpha is not permission to publish
`ProcessBigraphs.jl`.

### Potts workstream deliverables

- Freeze the paper Project and Manifest, experiment configurations, semantic seeds, model
  fingerprints, initial checksums, published-model manifests, capability contract versions, and
  analysis programs.
- Re-run bounded publication and published-model workloads on recorded CPU and claimed GPU systems;
  verify the checksums and provenance of archived full ensembles.
- Archive raw conformance, benchmark, profiler, environment, and hardware reports.
- Produce paper figures and tables only from archived machine-readable results.
- Re-run clean-install, checkpoint/restart, documentation, tutorial, and backend smoke tests from
  release candidates.
- Audit paper claims against exact versus approximate algorithms and semantically matched external
  comparisons. Audit every published-model claim against its fidelity dimensions, registered
  validation plan, deviations, and actual evidence status.
- Tag package versions and archive the reproducibility bundle only after every release gate passes.

### Potts release gate

- Publication workloads reproduce from a clean environment.
- CPU, AMDGPU, and Metal claims have current real-hardware evidence.
- Paper tables and figures trace to archived raw results and code.
- Every selected published model retains its Phase 14 release status under the release candidate,
  or the release stops for an explicit scope and claim amendment.
- Documentation, packages, manifests, and paper describe the same frozen API and semantics.
- No legacy engine or DSL path remains.

### Runtime workstream deliverables

- Complete the versioned hierarchical store, immutable committed snapshots, typed paths and ports,
  structural schemas, process and step declarations, exact logical ticks, typed deltas, built-in
  update algebra, and deterministic serial reconciliation/commit.
- Implement imminent-event multirate scheduling, actual elapsed partial intervals, common
  pre-commit same-time snapshots, declared cycle rejection, and explicit iterative constructs.
- Guarantee failure atomicity and exact restart at settled commit boundaries. Stateful processes
  declare versioned continuation and invalidation schemas.
- Add semantic RNG addressing by process, logical time, event, draw, and lineage identity, plus a
  read-only observer protocol and canonical runtime fingerprints.
- Prove the runtime independently with non-Potts static-composite, multirate biochemical, update-law,
  failure-injection, and checkpoint/replay fixtures.

### Adapter and join workstream

- Map CorePotts state, processes, plans, observations, persistence, backend capabilities, and
  PottsToolkit fragments to runtime contracts without moving the existing coupled tree wholesale.
- Prepare old/new serial differential fixtures and checkpoint compatibility readers. No Potts model
  cuts over until its Phase 16 slice gate passes.
- Use G4 evidence to settle GPU ownership and field-adapter questions left deliberately unfrozen in
  Phase 14.PB0.

### Evidence and documentation workstream

- Maintain package-local internal user, process-author, semantic, persistence, failure, and
  extension documentation for every implemented alpha capability.
- Bind every parity-registry feature touched by alpha to its exact upstream authority, Julia
  decision, executable fixture, status, and limitation.
- Run an independent clean package test and CI lane; Potts tests do not count as runtime evidence.

### Internal-alpha gate

- Serial static composites and the admitted multirate fixtures pass exact time, same-time visibility,
  update-order, failure atomicity, settled-restart, semantic RNG, and executor-order-independent
  serial evidence.
- No required state mutation bypasses typed deltas or engine-owned transaction buffers.
- Unsupported placement, continuation, update law, or process capability fails before mutation.
- The parity registry labels only proven alpha rows accordingly; complete parity and public release
  remain explicitly unclaimed.

## Phase 16: Dynamic Hierarchy and Potts Adapter Internal Beta

### Potts workstream

- Preserve every frozen Phase 13, G3-B, G4, published-model, backend, and paper-release claim
  while adapter work proceeds.
- Continue Potts-owned performance, documentation, published-model maintenance, and scientific
  capability work through the stable Potts interfaces.

### Runtime workstream

- Implement recursive composites, place/link topology, ordered step DAGs, fork/join barriers,
  explicit fixed-point/iteration constructs, and structural add, remove, divide, move, and rewire.
- Add versioned structural transactions, daughter reconstruction, lineage RNG, dynamic process
  creation/retirement, continuation invalidation, and exact settled-boundary structural restart.
- Fuzz update algebra and dynamic topology, inject failure during invoke/reconcile/apply/structural
  commit/emission, and prove that failed events publish no partial state.

### Adapter and join workstream

- Make CorePotts the flagship spatial-process adapter and lower PottsToolkit generic composition
  into ProcessBigraphs without adding a second model, scheduler, lifecycle, or persistence authority.
- Cut over one vertical slice at a time through old/new serial differential execution. At minimum,
  preserve Phase 13, Wortel, Wang, and the first field-model state, order, observation, RNG,
  continuation, and failure behavior before retiring each corresponding old path.
- Retain readers for every already-attested checkpoint format and version every new continuation
  envelope. A migrated model may never use both authorities simultaneously.

### Evidence and documentation workstream

- Document hierarchy, ports, structural requests, lifecycle, adapter authoring, cutover status,
  checkpoint compatibility, failure behavior, and per-process backend capabilities.
- Add package-local dynamic fixtures and cross-package adapter conformance lanes. Potts regression
  evidence and runtime conformance remain separately attributable.

### Internal-beta gate

- Dynamic hierarchy and all first-stable structural transactions pass serial conformance,
  deterministic replay, continuation, failure injection, and topology fuzzing.
- At least one CorePotts vertical slice and its PottsToolkit façade pass old/new differential
  execution and use only the runtime authority after cutover.
- Phase 13 and attested G3-B artifacts remain unchanged, and no reverse Potts dependency enters the
  runtime.

## Phase 17: Scientific Process Ecosystem and Whole-Cell-Style Composite

### Potts workstream

- Maintain the released Potts scientific portfolio and expose runtime-backed composition only where
  the corresponding adapter slice is stable and documented.
- Prepare population/environment spatial interfaces without making them prerequisites of the first
  whole-cell-style composite.

### Runtime and scientific-adapter workstream

- Add SciML ODE/DAE integration with explicit frozen, interpolated, event-updated, or continuously
  callable interval inputs and versioned solver continuation/invalidation.
- Use ModelingToolkit only as optional authoring/compilation lowering to ordinary SciML processes.
- Adapt Catalyst and JumpProcesses with propensity-cache invalidation, discontinuity, rescheduling,
  RNG, and restart contracts.
- Adapt COBREXA/JuMP with pinned optimizer settings, deterministic FBA solution selection, and
  explicit nonunique/infeasible/unbounded/timeout/failure behavior.
- Carry canonical numeric payloads plus schema units and ontology metadata, and adapt
  SBMLImporter/SBMLFBCModels/libSBML behind exact supported-feature matrices.

### Acceptance and evidence workstream

- Compose a Julia gene-expression/reaction process, regulation ODE, and E. coli core FBA process
  under one multirate runtime and qualify its state exchange, restart, failure, and provenance.
- Advance selected pinned vEcoli slices through differential traces after the Julia biochemical/FBA
  composite passes.
- Publish process-family backend matrices. Explicit CPU-only processes are valid; hidden residency
  movement is not.
- Complete user, adapter-author, solver-invalidation, units, standards-import, and whole-cell
  composition documentation for the admitted scope.

### Whole-cell-style gate

- The Julia biochemical/FBA composite passes scientific, ordering, continuation, failure,
  observation, and reproducibility acceptance from a clean environment.
- Selected vEcoli slice deviations are classified against pinned sources rather than silently
  normalized away.
- This gate satisfies the required whole-cell-style acceptance workload for a future public runtime
  release, but does not substitute for complete pinned parity.

## Phase 18: Dagger and Heterogeneous Execution

This phase qualifies physical execution only after the serial runnable-batch, reconciliation,
commit, and structural-barrier semantics from Phases 15 and 16 are stable.

### Runtime and executor workstream

- Implement `ThreadsExecutor` and optional `DaggerExecutor` beneath the logical scheduler. Tasks are
  coarse process ticks, solver calls, field advances, or partition batches, never individual Potts
  attempts, lattice sites, or tiny reactions.
- Make placement, residency, projections, transfers, synchronization, and result scopes explicit,
  bounded, measured, inspectable, and preflighted.
- Provide deterministic fail-stop and settled-checkpoint recovery. Retry only work declared pure
  and idempotent.
- Prove semantic RNG and committed results invariant to task completion order and worker count where
  the declared numerical law permits it.

### Potts, whole-cell, and evidence workstream

- Qualify applicable CorePotts and field process batches without weakening their CPU/Metal/ROCm
  matrices or permitting hidden host fallback.
- Advance the acceptance ladder to a well-stirred Syn3A composition when its scientific inputs and
  validation targets are pinned.
- Record serial/threads/Dagger equivalence, placement decisions, transfers, failures, recovery,
  memory, compilation, and throughput in machine-readable evidence.
- Complete executor-author, deployment, diagnostics, placement, recovery, and performance
  documentation.

### Exit gate

- Serial, Threads, and Dagger executions produce the same committed semantic result or the exact
  preregistered numerical/statistical equivalence class.
- No undeclared transfer, synchronization, fallback, or retry occurs.
- Worker failure recovers from the last settled checkpoint without partial publication.
- Dagger remains replaceable infrastructure and owns no scientific scheduling or commit rule.

## Phase 19: Pinned Parity Closure and First Public ProcessBigraphs Release

### Deliverables

- Close every required row in the pinned Process-Bigraph 2.0 parity registry with a versioned Julia
  semantic decision, implementation, executable oracle, persistence/failure disposition,
  documentation, and applicable backend evidence.
- Complete scheduler/update differential fixtures, randomized update-algebra tests,
  dynamic-topology fuzzing, checkpoint/replay, failure injection, executor equivalence, external
  solver invalidation, jump rescheduling, FBA failure matrices, applicable SBML cases, and long-run
  leak/output-volume tests.
- Freeze runtime API, schema, checkpoint, continuation, fingerprint, capability, parity-registry,
  and evidence versions only after complete qualification.
- Produce complete user, process-author, adapter-author, executor-author, conformance, operations,
  and limitation documentation.
- Present the near-release work to Eran Agmon as an independent Julia implementation. External
  feedback is informative, not a design or release authority.

### Public-release gate

- Every mandatory parity-registry row is qualified against the exact pinned Process-Bigraph and
  Bigraph-Schema revisions.
- The Phase 17 whole-cell-style composite and all applicable Phase 18 executor-equivalence gates
  still pass under the release candidate.
- No claim implies Vivarium 1.x support, exact Python interchange, upstream ownership, or
  endorsement.
- `ProcessBigraphs.jl` MUST NOT be published, tagged as a public compatibility release, or split
  into a separate repository before this gate passes.
- A repository split may be considered only after the first complete-parity release.

## Phase 20: Whole-Cell Development Program

This phase is a scientific modeling program beyond runtime parity, not a hidden condition for
claiming that the pinned runtime has already been implemented.

### Deliverables and ladder

1. Extend the selected vEcoli slices to one complete, validated vEcoli generation.
2. Qualify multigeneration division, daughter reconstruction, allocation, metabolism,
   transcription, translation, regulation, replication, observation, and lineage behavior.
3. Compose cell populations with explicit environments and PottsToolkit spatial processes.
4. Add model-specific scientific validation, datasets, calibration, provenance, performance, and
   collaboration review without redefining runtime semantics around one whole-cell model.
5. Continue well-stirred Syn3A and historical whole-cell semantic coverage where their source and
   validation contracts justify promotion.

### Exit discipline

- Runtime conformance, scientific-model validity, and application performance remain separate
  evidence classes.
- Each whole-cell model has pinned sources, explicit supported mechanisms, versioned parameters,
  registered validation targets, restart/failure evidence, and honest backend limitations.
- Population/environment coupling uses the same generic runtime and adapter contracts; it introduces
  no Potts- or paper-specific branch into ProcessBigraphs.

## Continuous Validation Matrix

The minimum validation run grows with the implementation:

| Change class | Required validation |
| --- | --- |
| Specification or decision | Consistency review, affected evidence mapping, decision record |
| Repository or dependency | Independent load/test, clean instantiate, extension load, smoke workload |
| State or scientific protocol | Unit, invariant, reference comparison, inference check |
| Evolving field, site, auxiliary, or relationship state | Update-order and snapshot fixtures, lifecycle, exact restart, semantic RNG, residency and synchronization checks |
| Kernel or execution | CPU plus available GPU, allocation, synchronization, device code, benchmark |
| RNG or algorithm | Known-answer, schedule identity, reproducibility profile, statistical battery |
| Lifecycle or persistence | Transaction faults, capacity, continuation, corruption/failure cases |
| DSL/compiler | Parser/IR round trip, reference evaluator, diagnostics, cache identity, device compile |
| SciML | Interface behavior, saving/callback boundaries, remake, ensemble, failure codes |
| Performance optimization | Full applicable conformance plus before/after raw measurements |
| Documentation/tutorial | Executable assertions, clean environment, generated-output check |
| Published model | Pinned source and license record, manifest validation, registered result test, clean reproduction, evidence and output checksums |
| Runtime store, port, delta, clock, or update law | Schema/path round trip, immutable-snapshot fixture, algebraic law/property tests, conflict truth table, canonical encoding |
| Runtime scheduler or commit | Exact-time and stable-tie fixtures, same-time visibility, partial interval, failure atomicity, settled restart, randomized serial oracle |
| Structural topology | Add/remove/divide/move/rewire truth tables, lineage RNG, continuation, dynamic-topology fuzzing, failure injection |
| Potts/runtime adapter | Old/new serial differential execution, frozen-artifact non-regression, checkpoint reader, one-authority assertion, backend matrix |
| Scientific adapter | External-input policy, cache invalidation/reinitialization, continuation, solver failure, units, supported-feature matrix |
| Executor or placement | Serial equivalence, worker-count/task-order invariance, declared residency/transfer, fail-stop recovery, performance and memory |
| Parity claim | Exact upstream pins, registry row, semantic classification, independent oracle, docs, persistence/failure/backend disposition |
| Whole-cell application | Pinned model/source, process coverage, registered validation, lineage/restart/failure, provenance, backend and deviation report |

No performance result excuses a conformance failure. No CPU result qualifies a GPU backend.

## Phase Tracking

Each phase is tracked with:

- `Not started`, `In progress`, `Blocked`, or `Complete`
- Independent Potts, runtime, adapter/join, and evidence/docs workstream statuses where applicable
- The governing specification and decision gates
- A short list of concrete deliverables
- The baseline and candidate revision identifiers
- Commands and environments used for validation
- Links to machine-readable conformance and benchmark artifacts
- Known exclusions and their effect on claims

Only one phase SHOULD own a structural concept at a time. A phase MAY have several active work
streams, but the roadmap MUST make their shared interface boundary explicit.

## Initial Critical Path

The first executable sequence is:

1. Complete Phase 0 inventory and paper-scope classification.
2. Create the baseline benchmark/result infrastructure and capture Phase 1 evidence.
3. Perform the Phase 2 repository migration without broad semantic rewrites.
4. Build Phase 3 reference and conformance foundations.
5. Resolve D2 while implementing Phase 4 state and protocols.
6. Begin the new execution layer only after Phase 4 interfaces are executable.

The refactor MUST NOT begin by rewriting the DSL, tuning individual kernels, or reorganizing every
source file at once. Those actions depend on interfaces and evidence established earlier in this
critical path.

## Current Fork/Join Critical Path

Phases 0--13, Phase 14.0, Wortel G2, Wang G3-A, attested Wang G3-B, and the bounded
ProcessBigraphs PB0 foundation are complete. The remaining work proceeds on independent gates:

```text
Potts scientific path                         ProcessBigraphs runtime path
----------------------                        ----------------------------
G4 field CPU/Metal/ROCm                       PB0 bounded foundation [passed]
        |                                                   |
bounded portfolio smokes                      Phase 15 serial internal alpha
        |                                                   |
14.2 Learn/Examples                                         |
14.3 Published Models                                       |
14.4 Manual/Satellites                                      |
        |                                                   |
        +---------------- Phase 15 independent gates -------+
        |                                                   |
Potts paper/release gate                         serial static-composite alpha
                                                            |
                                           Phase 16 dynamic hierarchy + Potts adapter
                                                            |
                                           Phase 17 scientific adapters + whole-cell style
                                                            |
                                           Phase 18 Dagger/heterogeneous qualification
                                                            |
                                           Phase 19 complete parity/public release
                                                            |
                                           Phase 20 whole-cell scientific program
```

The executable sequence and join rules are:

1. **Complete:** retain the Decision 0031/0033 Potts kernel, Wortel G2, Wang G3-A, and attested G3-B
   as frozen evidence. The G3-B
   [closure ledger](audits/phase-14-g3b-closure-ledger-v1.toml) and
   [manifest](evidence/phase-14/g3b-closure/manifest-v1.toml) are the factual CPU baseline.
2. **Current Potts gate:** close G4 by qualifying the reusable field substrate on sequential CPU,
   real Metal, and real ROCm. G3-B semantics, RNG, ordering, storage ABI, publication,
   continuation, and evidence identity may not change.
3. **Complete parallel runtime gate:** the ProcessBigraphs authority and parity registry are frozen,
   and the independent package plus bounded domain-neutral primitives and non-Potts fixtures pass
   PB0. No CorePotts dependency or public runtime release was introduced; Phase 15 internal alpha
   remains a separate gate.
4. **Potts join:** Decision 0035 has opened G4 after the passed G3-B CPU reference. Only after G4
   passes may the generic field adapter freeze.
5. **Phase 14 presentation path:** close required capability rows and bounded model smokes, then
   complete Learn/Examples, preregistered published-model studies, the full manual, and satellites.
6. **Phase 15 independent gates:** qualify the Potts paper release from frozen Phase 14 evidence
   while closing ProcessBigraphs serial internal alpha. Failure of one does not rewrite or weaken
   the other.
7. **Phase 16 adapter join:** after serial runtime contracts and the relevant Potts evidence are
   stable, cut over one CorePotts slice at a time through old/new differential execution. No model
   may have two runtime authorities.
8. **Phases 17--18:** add scientific adapters and the whole-cell-style composite before qualifying
   Dagger. Dagger placement experiments may occur earlier, but qualification waits for stable serial
   batches, reconciliation, commits, and structural barriers.
9. **Phase 19 release join:** publish ProcessBigraphs only when every mandatory pinned-parity row,
   the whole-cell-style composite, applicable executor equivalence, production evidence, and
   complete documentation pass. Presentation to Eran occurs near this gate; repository separation
   is considered only afterward.
10. **Phase 20:** treat full-generation and spatial population whole-cell work as a separately
    validated scientific program built on the released runtime.

## Completion Definition

The roadmap is complete only when every required phase and workstream exit gate passes. “Mostly
refactored” does not qualify. Potts paper release, ProcessBigraphs pinned-parity release, and
whole-cell scientific validity are distinct claims with distinct evidence. Explicitly deferred or
experimental features do not block a given claim when they remain outside its stable APIs, selected
portfolio, parity registry, and publication language. A selected Potts model changes only through
the Decision 0029 amendment process; a required runtime parity feature changes only through an
explicit revision of the pinned authority, parity registry, and Decision 0034 evidence.

This roadmap is maintained as execution evidence. If implementation reveals that a phase boundary
is wrong, the roadmap MAY be revised, but accepted semantics and scientific guarantees require the
normal specification decision process.
