# Symbolic Potts V1 Architecture Redirection Contract

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: implementation-grade and audit-passed; implementation prohibited until explicit owner
send-off

## Authority

This contract records ARI-001 through ARI-020 from the accepted
[architecture-redirection owner interview](../design/audits/symbolic-potts-v1-architecture-redirection-owner-interview.md).
It governs the compiler and runtime correction required before Symbolic Potts V1 may be
implemented to completion.

The authority order for this branch is:

1. the [Compiler Construction Contract](symbolic-potts-v1-compiler-construction.md) for the
   compiler, descriptor, layout, spatial-planning, transaction, backend-test, and autonomous-gate
   details it explicitly freezes;
2. this architecture-redirection contract;
3. the [Autonomous Consolidation Contract](symbolic-potts-v1-consolidation.md);
4. [Symbolic Potts V1](symbolic-potts-v1.md);
5. surviving scientific specifications and accepted decisions; and
6. historical implementation notes.

This contract supersedes a lower authority only where it explicitly changes compiler openness,
CorePotts storage, execution staging, checkerboard semantics, relationship admission, portability,
test authority, implementation order, or completion. All compatible product, syntax, units,
stochastic, lifecycle, SciML, checkpoint, inspection, and clean-break requirements survive.

The words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** have the meanings defined
in [the specification index](README.md).

## Governing invariant

> CorePotts knows how to execute typed CPM programs, but it does not know which biological
> mechanisms exist.

No type, field, compiler switch, proposal-loop branch, engine branch, checkpoint branch, or
capability branch in CorePotts may be named for Wortel, Merks, focal-point plasticity, activity,
chemotaxis, elongation, or another biological mechanism.

The phase is not complete merely because the two proof models run. It is complete only when those
models run through the same externalizable contracts used by a downstream novel term.

## ARV1-001 — Phase scope

The phase MUST deliver:

- one ModelingToolkit-native `PottsSystem` authoring and composition surface;
- an honest symbolic vocabulary for Hamiltonian terms, nonequilibrium drives, constraints, and
  modifiers;
- completion into qualified scientific IR;
- lowering into typed, grouped, device-valid descriptors;
- general state, workspace, resource-access, stage, adaptation, and checkpoint contracts;
- one scalar CPU sequential engine;
- one CPU/GPU portable checkerboard engine;
- deterministic deferred relationship and lifecycle transactions required by the proof models;
- SciMLBase problem, integrator, solve, solution, remake, and symbolic-indexing behavior;
- optional ModelingToolkit, ProcessBigraphs, and Unitful integration already accepted by V1;
- an independent downstream extension conformance fixture;
- complete stochastic Wortel and Merks integration fixtures written visibly through public syntax;
  and
- removal of the monolithic and mechanism-specific V1 execution architecture.

The phase MUST NOT deliver:

- migration wrappers, deprecated aliases, compatibility modes, or a dual compiler;
- polished documentation, tutorials, or browser documentation QA;
- Lottery, tiled, or a third engine;
- Dagger execution;
- a generic entity-component runtime;
- an arbitrary user-defined execution DAG;
- unrestricted concurrent graph mutation;
- arbitrary Julia or arbitrary Symbolics compilation to a device;
- broad CPM-literature reproduction;
- cross-language or Vivarium adapters;
- efficient sequential GPU execution; or
- an evidence ledger, parity oracle, or one-time release-qualification system.

## ARV1-002 — Package and portability boundaries

PottsToolkit retains the symbolic and SciML dependency direction defined by ACV1-001. CorePotts
MUST remain free of ModelingToolkitBase, ModelingToolkit, Symbolics,
SymbolicIndexingInterface, DynamicQuantities, Unitful, ProcessBigraphs, and external equation
solvers.

CorePotts MUST use the following portability stack:

- `KernelAbstractions` for model-specific portable kernels;
- `AcceleratedKernels` for suitable bulk traversal, sorting, scans, and reductions;
- `Adapt` for recursive backend adaptation;
- `Atomix` for explicitly admitted atomic operations; and
- `StaticArrays` for measured small fixed-size local values.

CUDA, AMDGPU, and Metal integration MUST be package extensions. A backend extension may expose only
backend selection, allocation/adaptation, synchronization, capability discovery, and genuinely
backend-specific optimized kernels justified by measurement.

`StructArrays` MAY become a CorePotts dependency only when a checked benchmark demonstrates a
material state-layout benefit for a retained hot path. Private GPU APIs, the former custom
KernelIntrinsics fork, silent CPU fallback, and unconditional backend dependencies are forbidden.

The implementation abstraction order is:

1. an ordinary array operation;
2. an AcceleratedKernels primitive;
3. a KernelAbstractions kernel; and
4. a measured backend-specific implementation.

Skipping a higher level requires a source comment or design record naming the missing semantic or
performance capability.

## ARV1-003 — Scientific term taxonomy

Every proposal contribution MUST have exactly one honest semantic category:

1. `HamiltonianTerm` is a conservative energy contribution;
2. `ProposalDrive` is a directional or nonequilibrium contribution;
3. `ProposalConstraint` is a hard veto; or
4. `ProposalModifier` changes proposal or acceptance behavior without claiming to be energy.

`HamiltonianTerm` replaces `ProposalEnergy` in the stored V1 statement inventory; the inventory
cardinality remains 23. Historical requirements referring to the scientific meaning of
`ProposalEnergy` apply to `HamiltonianTerm`, but its old proposal-delta-first naming and semantics
are superseded.

A Hamiltonian term describes energy. Its proposal delta is the energy of the compiler-proven
affected region after the staged copy minus the energy before the staged copy. This is a discrete
local difference, not symbolic differentiation.

A directional effect MUST NOT be relabeled as Hamiltonian merely to reuse the energy accumulator.
Random draws MUST be represented by proposal generation, acceptance, or an explicit stochastic
process and MUST NOT be hidden inside a symbolic term.

Focal-point elastic energy MAY be Hamiltonian. Relationship creation, removal, maturation,
retuning, and lifecycle cleanup are processes and transactions.

These categories are orthogonal to the surviving bounded effect classes. Hamiltonian terms,
drives, constraints, and read-only modifiers ordinarily have `PureRead` proposal-evaluation
effects; accepted-copy, synchronous, and ordered-batch processes retain their respective mutation
effect classes.

## ARV1-004 — Analyzable symbolic vocabulary

The ordinary V1 expression vocabulary MAY contain:

- typed literals, parameters, and declared coefficients;
- scalar arithmetic and documented pure scalar functions;
- comparisons and typed conditional selection;
- universal source, target, site, cell, kind, generation, coordinate, and proposal references;
- declared state observations;
- bounded neighborhood and incident-relation reductions;
- declared field samples and gradients; and
- declared relationship observations.

Every operation MUST define result type and shape, unit propagation, purity, resource reads,
locality, effect bounds, engine/backend capability, canonical serialization, and lowering.

The ordinary compiler MUST reject:

- arbitrary Julia calls or closures;
- host containers or object graphs in device expressions;
- mutation;
- exceptions as device control flow;
- unbounded iteration;
- hidden random draws;
- unresolved dynamic dispatch;
- unresolved Symbolics objects; and
- an operation without a validated lowering.

Symbolics `build_function` MAY support host-only equation-system work where its public contract is
appropriate. It MUST NOT be the primary CPM term or device-kernel representation.

## ARV1-005 — Extension boundary

Built-in statements use ordinary Julia types and methods. A downstream PottsToolkit statement
family MUST enter through the versioned host-side `RegisteredStatement` boundary.

Its frozen registration MUST provide:

- schema identity, semantic version, canonical serialization, and provenance;
- symbolic traversal, result types, dimensions, shapes, and validation;
- resource access, locality, effect bounds, stages, and ordering;
- state and workspace schemas;
- engine and backend capabilities;
- construction of concrete term, process, and request descriptors;
- adaptation and checkpoint behavior;
- inspection and diagnostic rendering; and
- any registered symbolic-operation lowering it owns.

Registration ends before executable construction. A completed system freezes the registry
snapshot. Compilation and execution MUST NOT consult a registry.

Contrary to the former SPV1-017 and ACV1-005 wording, a conforming registered statement is not
required to lower into a built-in biological statement or mechanism. It MUST lower into the
qualified scientific IR and then into concrete descriptors satisfying this contract.

CorePotts's qualified compiler/runtime protocol MUST permit those descriptor types without editing
a central enum, concrete-family union, mechanism `isa` ladder, or mechanism switch. Arbitrary
runtime callbacks remain forbidden.

## ARV1-006 — Qualified scientific IR

Completion MUST produce immutable records that preserve the accepted identity, source,
namespacing, units, provenance, fingerprint, and diagnostic requirements.

For execution analysis, each record MUST additionally contain or derive:

- semantic category;
- normalized typed expression;
- bounded affected region or deferred-stage requirement;
- resource reads and writes;
- state and workspace requirements;
- concurrency policy requirements;
- stage entries and dependencies;
- RNG sites;
- engine/backend admissions and rejections; and
- descriptor-lowering identity.

The scientific IR is open to registered record payload types satisfying this schema. The ordinary
symbolic operation vocabulary and execution-stage taxonomy remain closed and versioned.

## ARV1-007 — Compiled descriptor and group contract

The host compiler MUST lower qualified records into immutable, concrete, backend-adaptable
descriptors. Descriptors MUST contain only device-valid values for the selected backend.

The compiler MUST group repeated compatible descriptors by operation family and execution
strategy. Repeated parameter values, coefficients, targets, cell kinds, identities, and similar
model data remain data in backend-compatible buffers; they MUST NOT become type parameters.

CorePotts MUST provide qualified generic operations equivalent to:

- state requirements;
- workspace requirements;
- resource access and footprint;
- stage participation;
- engine/backend support;
- proposal evaluation;
- effect or request emission;
- stage application;
- adaptation;
- checkpoint encoding and reconstruction; and
- inspection metadata.

Exact function and abstract-type names MAY be chosen during implementation, but the conformance
fixture and all Core engines MUST depend only on the resulting generic contracts.

An executable MUST NOT contain Symbolics expressions, units, source ASTs, registries, dictionaries,
host closures, abstractly typed descriptor collections, or mechanism-name dispatch.

## ARV1-008 — Core state and workspace

CorePotts directly owns only universal CPM invariants:

- lattice ownership and topology;
- cell identity, kind, and generation required to interpret ownership safely;
- proposal coordinates and accepted-copy bookkeeping;
- semantic RNG counters/addresses;
- settled MCS and batch position; and
- universal capacities and validity information required by the engines.

Scientific state is stored in typed auxiliary blocks or grouped slots declared by descriptors.
Scientific workspaces are similarly declared, allocated before execution, and reused.

The program, state, and workspace structures MUST recurse generically for:

- initialization;
- validation;
- backend adaptation;
- state access;
- settled-state export;
- checkpoint encode/reconstruct; and
- inspection.

Adding activity, history, fields, elongation, relationships, or a downstream state block MUST NOT
add a named field or branch to the central program, engine, or checkpoint code.

Proposal and warmed stage execution MUST NOT allocate. Whole-lattice scans, dynamic `Set` or
`Vector` construction, dense general-purpose eigensolvers, or per-MCS scratch allocation are
forbidden in a proposal hot path.

## ARV1-009 — Compilation pipeline

The corrected compilation pipeline is:

1. validate the selected engine, backend, and scalar type;
2. normalize and type the scientific expressions;
3. derive built-in resource footprints and validate registered footprint rules;
4. classify conservative, drive, constraint, modifier, process, and observation records;
5. classify structural and runtime parameters and erase validated units;
6. lower expressions and processes into concrete descriptor candidates;
7. group descriptors by type and execution strategy;
8. merge and validate state and workspace schemas;
9. validate stage ordering, boundedness, conflicts, and engine/backend capabilities;
10. plan topology, capacities, incremental trackers, buffers, and layouts;
11. assign semantic RNG stream and draw-site addresses;
12. lower equation-process and observation boundaries;
13. construct one immutable general `CompiledPottsProgram`;
14. construct inspection, capability, storage, workspace, schedule, checkpoint, and replay reports;
    and
15. compute the executable fingerprint.

Independent safe failures SHOULD be aggregated. Diagnostics MUST identify the originating qualified
statement and model expression, not merely a descriptor or kernel type.

## ARV1-010 — Closed execution-stage taxonomy

The internal V1 stage schedule is:

```text
Initialize                                      once
for each MCS
    BeforeMCS
    for each engine batch
        BeforeBatch
        Proposal
        Resolve
        CommitAccepted
        AfterBatch
        RelationshipCommit                      accepted-copy requests
    end
    AfterMCS
    RelationshipCommit                          MCS relationship-process requests
    Lifecycle
    EquationStep
    Observe
end
```

Sequential has one proposal per engine batch. A checkerboard batch contains the compiler-selected
independent proposal set. A stage with no entries is a no-op.

An engine MAY fuse adjacent stages only when the result preserves the specified snapshots, ordering,
RNG addresses, and externally observable behavior.

External descriptors MAY contribute validated entries to supported stages. They MUST NOT create a
new stage, reorder the taxonomy, or introduce an arbitrary phase DAG. Public protocol names map
onto these anchors and do not create additional scheduling authority. This mapping supersedes the
open-ended “named protocol-stage boundaries” wording in SPV1-022.

Each stage entry declares its immutable input snapshot, outputs or requests, resource policy,
bounded work domain, and commit semantics. No object may have two scheduling owners.

## ARV1-011 — Resource and concurrency policies

Every stage access MUST resolve to one of the following closed policies:

- read-only snapshot;
- spatially exclusive write;
- exact commutative integer atomic;
- deterministic grouped reduction;
- exclusive owner;
- ordered deferred request; or
- host equation/process boundary.

The compiler derives policies and bounded footprints for built-in operations. A registered
descriptor supplies typed rules that the compiler validates against its expression, state schema,
stage, and selected engine.

An unbounded or data-dependent footprint MUST use a qualified deferred stage with a proven bounded
emission count or be rejected for checkerboard. User assertions MUST NOT override failed compiler
analysis.

Floating-point reductions that contribute to promised reproducibility MUST use a specified stable
order. Atomics are not by themselves proof of deterministic multi-resource semantics.

## ARV1-012 — Sequential engine

Sequential is the authoritative scalar CPU reference engine.

It MUST:

- use the same compiled descriptors, auxiliary state, requests, and stage semantics as
  checkerboard;
- process one proposal at a time with batch size one;
- observe accepted mutations before the next proposal where sequential semantics require it;
- use semantic addressed randomness independent of incidental host threading; and
- provide the simplest inspectable reference for exact term, tracker, request, and checkpoint
  tests.

Efficient GPU sequential execution is not a V1 requirement. Sequential is not an alternate
scientific authoring path.

## ARV1-013 — Checkerboard engine

Checkerboard is the portable throughput engine and MUST execute on CPU arrays and each claimed GPU
backend through the same general descriptor contracts.

For each batch it MUST:

1. establish the specified immutable batch snapshot;
2. generate proposals and random priorities from semantic addresses;
3. evaluate constraints, Hamiltonian deltas, drives, and modifiers;
4. resolve spatial write conflicts deterministically;
5. commit admitted lattice ownership changes;
6. apply safe integer atomic effects and deterministic grouped reductions;
7. emit exclusive-owner and deferred requests;
8. apply ordered after-batch work; and
9. publish the next settled batch snapshot.

The compiler MUST construct a finite coloring from the maximum admitted spatial read/write
footprint. It SHOULD make spatially exclusive footprints disjoint by construction. Any residual
exclusive conflict uses the canonical priority key `(priority_draw, semantic_proposal_id)`, ordered
by larger priority draw and then smaller semantic proposal identity. A proposal wins only when it
is canonical winner for every exclusively written spatial resource in its footprint.

Conflict selection MUST NOT depend on device completion order. Read-only observations, commutative
integer effects, deterministic reductions, and deferred requests do not become spatial claims
merely because two proposals reference the same cell. In particular, the implementation MUST avoid
treating every shared cell observation as an exclusive mutation claim.

Checkerboard has explicitly batch-synchronous kinetics. It is not required to reproduce a
sequential trajectory. The selected coloring, batch structure, neighborhood safety radius, and
proposal multiplicity are compiled structural choices reported by inspection and included in the
executable/replay identity.

No unsupported term may silently fall back to host or sequential execution.

## ARV1-014 — Relationships and lifecycle

Checkerboard proposal evaluation reads an immutable relationship snapshot for its batch.
Relationship mutation occurs through bounded typed requests with canonical identities.

Accepted proposals MAY emit relationship requests. Requests MUST be:

1. bounded;
2. deterministically ordered or grouped;
3. duplicate/conflict resolved by the declared policy;
4. checked for capacity, maximum degree, endpoint generation, endpoint kind, and lifecycle;
5. applied as one validated transaction; and
6. published at the specified `RelationshipCommit` boundary.

Sequential uses the same request protocol with a batch size of one when immediate sequential
visibility is scientifically required.

Lifecycle mutations use the same ordered-deferred principle and publish only at the declared
lifecycle boundary. Immediate arbitrary graph mutation inside a parallel proposal kernel is
forbidden.

This clause supersedes the requirement that the initial focal fixture be sequential-only.
Focal-point plasticity is checkerboard-admissible through snapshot energy reads and ordered deferred
relationship requests. Its checkerboard kinetics MUST be specified and tested as batch-synchronous.

## ARV1-015 — ModelingToolkit, equation, and ProcessBigraphs composition

`PottsSystem` MUST implement the accepted public ModelingToolkitBase system behavior without
translating lattice sites or copy proposals into an ODE system.

PottsToolkit owns:

```text
PottsSystem -> PottsExecutable -> PottsProblem -> PottsIntegrator -> PottsSolution
```

SciMLBase owns the public conventions for problem construction, `init`, `step!`, `solve`,
`solve!`, `remake`, callbacks where admitted, return codes, timeseries behavior, and symbolic
indexing.

A tightly coupled compatible external equation system enters through an `EquationProcess`. The
host compiler partitions equation execution from CPM descriptors and creates the coupled
integrator. An external solver MUST NOT be invoked from a device proposal kernel.

The optional ProcessBigraphs extension derives a CPM process with typed ports, explicit state
exchange, integer-MCS advancement, atomic publication, failure propagation, and checkpoint
behavior. ProcessBigraphs owns multiscale orchestration; CorePotts has no ProcessBigraph dependency.

Future Vivarium interoperability belongs at the ProcessBigraphs component boundary and is outside
this phase.

## ARV1-016 — Stochastic, replay, checkpoint, and inspection contract

All accepted semantic RNG addressing survives. “Deterministic checkerboard” means deterministic
conflict and reduction resolution for a fixed completed system, executable configuration, seed,
replica, backend support level, and schedule. It does not mean deterministic biology or
cross-engine trajectory identity.

Same-engine exact replay is a support-level claim and MUST name the backend/configuration scope.
Cross-engine and cross-backend equality is required only where an explicit lower-level arithmetic
contract promises it.

Checkpointing operates only on settled stage boundaries admitted by the existing checkpoint
contract. It recursively encodes universal state and descriptor-declared auxiliary state. It MUST
NOT contain live workspaces, kernels, symbolic objects, registries, or host closures.

Inspection MUST expose:

- normalized scientific expressions and semantic categories;
- descriptor groups and group cardinalities;
- state and workspace schemas;
- resource footprints and concurrency policies;
- stage schedule and fused stages;
- engine/backend admissions and reasons;
- structural checkerboard choices;
- RNG sites and replay scope; and
- checkpoint participation.

## ARV1-017 — Specialization and performance budgets

Let `N` be statement occurrences and `G` the number of distinct descriptor-group execution
strategies.

The implementation MUST satisfy these machine-independent budgets:

- host normalization, validation, grouping, and data construction are at most linearithmic in `N`
  absent an explicitly documented global sort;
- generated evaluator and kernel specialization count is proportional to `G`, not `N`;
- repeating one descriptor family with different numerical values does not deepen a per-statement
  tuple type or create one evaluator method instance per occurrence;
- generated device code contains no runtime opcode interpreter or mechanism-name switch;
- warmed proposal, resolve, commit, and declared process kernels allocate zero host heap memory;
- reusable runtime workspace allocation is independent of MCS count; and
- per-proposal tracker updates are bounded by the declared local footprint rather than lattice
  size or total relationship count.

Compilation benchmarks MUST report latency and generated-code growth for increasing `N` at fixed
`G` and increasing `G`. These reports are regression tools, not hard wall-clock PR gates.

Representative hot-path benchmarks MUST report allocations, synchronization, host/device transfer,
and warm execution separately. A backend claim requires evidence that no hidden host fallback or
per-stage transfer occurs.

## ARV1-018 — Recovery and source disposition

Implementation proceeds surgically on the current branch. It preserves valid V1 authoring,
completion, SciML, syntax, stochastic, and test work and replaces the incorrect execution
architecture.

A read-only temporary clone of `main` MAY be used to understand:

- KernelAbstractions kernels;
- Adapt boundaries;
- explicit reusable workspaces;
- staged checkerboard candidate/claim/evaluate/commit structure;
- incremental volume, boundary, moment, centroid, field, history, and relationship trackers;
- backend extension organization; and
- useful warm-allocation and device-validity tests.

The clone MUST NOT be imported, called, linked, copied wholesale, used to generate expected
outputs, or retained as an oracle/evidence artifact.

The implementation MUST NOT restore:

- coupled authoring or paper-specific CorePotts assemblies;
- Lottery or tiled engines;
- the former custom KernelIntrinsics fork or private GPU APIs;
- obsolete event/dependency APIs;
- incidental host waits or transfers;
- single-lane relationship application presented as scalable;
- one universal launch size;
- broad CorePotts exports; or
- historical evidence and parity machinery.

The current monolithic V1 executor MUST be removed after its general replacement passes the
applicable tests. No old and new execution authority may coexist at phase exit.

## ARV1-019 — Test authority and ordinary CI

The test authority is layered:

- exact unit tests for expressions, lowering, local energy differences, acceptance, trackers,
  request ordering, checkpoint reconstruction, and other exact contracts;
- deterministic same-engine replay within its claimed scope;
- property tests for locality, conservation, connectivity, generations, relationships, and state
  consistency;
- statistical tests for stochastic scientific behavior;
- analytic or independently calculated small fixtures;
- checkerboard tests against specified batch semantics;
- cross-engine tests only at the exact, invariant, or statistical level promised by the relevant
  contract;
- device compilation and backend smoke tests; and
- a downstream external-module conformance fixture.

Scientifically equivalent tests from `main` MUST be retained or rewritten against V1. Tests that
exist only for migration, a removed engine, historical expected-output archives, legacy parity, or
evidence freshness MUST remain removed.

The downstream fixture MUST define outside CorePotts:

- a novel Hamiltonian term;
- at least one auxiliary state block;
- required workspace;
- symbolic lowering;
- resource and stage capabilities;
- adaptation and checkpoint participation; and
- execution on CPU sequential and CPU checkerboard.

It MUST compile for every GPU backend claimed by the affected descriptor protocol. CorePotts source
MUST remain unchanged by the fixture.

CCV1-021 of the
[Compiler Construction Contract](symbolic-potts-v1-compiler-construction.md) extends this
authority with a second neutral downstream relationship-state/request/lifecycle fixture. Both are
required before proof-model lowering.

Wortel and Merks fixtures MUST contain the full public model assembly, stochastic problem, initial
layout, parameters, and observations. They MUST test bounded end-to-end behavior, replay/divergence,
scientific invariants, and appropriate statistical behavior. They are not semantic oracles.

Ordinary required CI contains package loading, supported Julia versions, package and integration
tests, CPU sequential/checkerboard, downstream conformance, Aqua/ExplicitImports where retained,
and source/dependency audits. It MUST NOT fail because hardware evidence is missing or stale.

Large statistical campaigns, performance matrices, and GPU-vendor matrices are manual, scheduled,
or release-level. Each advertised backend support level requires its own compile-and-run
qualification. Documentation and browser QA are absent because documentation is outside this
branch.

## ARV1-020 — Autonomous implementation order and stopping rule

For implementation ordering only, this clause is superseded by G0 through G9 in CCV1-022 of the
[Compiler Construction Contract](symbolic-potts-v1-compiler-construction.md). Its architecture
requirements, autonomous-repair rule, owner-blocker boundary, and exit requirements survive.

After explicit owner send-off, one autonomous phase proceeds through these internal gates:

1. freeze the surviving semantic and test-authority inventory;
2. establish CorePotts dependencies, backend extensions, and portable-state conventions;
3. implement descriptor, group, state, workspace, resource, and stage contracts;
4. implement the CPU sequential reference;
5. implement staged KernelAbstractions checkerboard execution;
6. implement ordered deferred relationship and lifecycle requests;
7. redirect PottsToolkit expression lowering, grouping, and ModelingToolkit integration;
8. add and pass the independent downstream extension fixture;
9. lower the general mechanisms required by focal, Wortel, and Merks;
10. reconstruct and pass Wortel and Merks without CorePotts edits;
11. remove the superseded monolithic executor and scaffolding;
12. run functional, stochastic, allocation, specialization-growth, integration, and
    available-backend gates; and
13. audit the final diff against every surviving SPV1, ACV1, and ARV1 clause.

These are internal gates, not separate owner approvals. Work MAY move between adjacent gates to
preserve a coherent implementation. A failure sends work back to the earliest violated abstraction
and does not authorize a mechanism special case.

Implementation continues autonomously for internal representation choices, refactors, test-exposed
defects, source moves, portable upstream API substitutions, optimization, and changed extraction
order consistent with this contract.

Implementation MUST stop only if:

- two scientifically different behaviors remain consistent with the accepted specifications;
- a required public upstream capability is absent and only private coupling could satisfy it;
- satisfying the phase requires crossing a forbidden dependency boundary;
- a proof model requires an unbounded effect not representable by the accepted deferred protocol;
- a required feature needs compatibility, documentation, a third engine, Dagger, Vivarium, or
  another excluded product; or
- the terminal external-extension test cannot be met without changing the accepted product
  boundary.

An implementation difficulty, failed test, long run, missing optimization, or unavailable optional
GPU vendor after one functional portable GPU witness qualifies is not by itself an owner blocker.
Inability to obtain the functional witness required by the Compiler Construction Contract is a
phase-exit blocker.

## ARV1-021 — Phase exit

The phase is implementation-complete only when:

1. every surviving normative requirement has a test or justified static inspection;
2. a novel downstream Hamiltonian term with auxiliary state adapts, checkpoints, and executes on
   both engines and the required functional GPU witness without CorePotts edits;
3. `CompiledPottsProgram`, the proposal loop, engines, and checkpoint machinery contain no named
   biological mechanism;
4. repeated same-family terms satisfy the specialization budgets;
5. proposal and warmed-stage paths satisfy the allocation and locality budgets;
6. sequential and checkerboard satisfy their distinct specified stochastic semantics;
7. relationship and lifecycle transactions satisfy boundedness, ordering, integrity, and rollback
   tests;
8. Wortel and Merks run stochastically through complete visible public V1 definitions;
9. claimed CPU and available GPU support levels pass their required gates with no fallback, and
   every GPU semantic/conformance test uses the shared backend-agnostic harness;
10. ModelingToolkit, SciMLBase, ProcessBigraphs, Unitful, MakiePotts, and package boundaries pass
    their in-scope integration tests;
11. obsolete monolithic, compatibility, removed-engine, oracle, and evidence authorities are gone;
12. ordinary CI is green without evidence-freshness or documentation gates; and
13. a final audit records source disposition, public surface, scientific coverage, performance
    limits, backend support levels, and explicitly deferred documentation.

Implementation completion does not authorize a merge that knowingly breaks living documentation.
Documentation repair and browser QA remain a separate owner-authorized phase.
