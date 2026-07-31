# Symbolic Potts V1 Architecture Redirection Owner Interview

Date opened: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: complete; Rounds 1 through 4 accepted

## Purpose

This interview redirects Symbolic Potts V1 around a general, portable execution architecture.
It preserves the accepted product vision and scientific semantics while preventing Wortel, Merks,
or any other named biological mechanism from becoming part of the CorePotts executor.

Accepted answers are design authority for the forthcoming consolidation specification. They do not
authorize implementation before the interview series, research consolidation, and specification
audit are complete.

## Governing principle

> CorePotts knows how to execute typed CPM programs, but it does not know which biological
> mechanisms exist.

## Round 1 — Compiler and runtime foundation

Owner response: **accept the five**

### ARI-001 — Hybrid extensibility boundary

Accepted.

- PottsToolkit's authoring, symbolic, completion, and host-side compiler layers are extensible.
- CorePotts execution is extensible through qualified typed descriptors and stage entries.
- Device execution uses a closed ordinary operation vocabulary.
- An explicitly registered lowering escape hatch may introduce external compiled descriptors after
  host-side validation.
- Symbols, symbolic expression graphs, dictionaries, closures, dynamic dispatch, and registry
  lookup do not cross the device compilation boundary.
- Extensibility is proven by a downstream fixture that adds a term without editing
  `CompiledPottsProgram`, the proposal loop, checkpoint machinery, or either engine.

### ARI-002 — Typed expression algebra and descriptor dispatch

Accepted.

- Ordinary symbolic Hamiltonian expressions lower into a small typed expression algebra and then
  into immutable concrete descriptors.
- Core execution dispatches on descriptor types rather than mechanism names.
- Symbolics-generated functions are not the primary execution representation.
- A runtime opcode interpreter is not the V1 execution representation.
- Device evaluators do not throw, allocate, or inspect host-side symbolic objects.

### ARI-003 — Fixed CPM invariants with open typed auxiliary state

Accepted.

- CorePotts directly owns universal CPM state such as the lattice, identities, topology, proposal
  coordinates, RNG counters, and acceptance bookkeeping.
- Scientific terms declare typed auxiliary state and workspace requirements.
- Compiled storage contains typed tuples or grouped slots rather than named fields for activity,
  fields, history, elongation, focal-point relationships, Wortel, or Merks.
- Checkpointing and adaptation recurse over the general state structure.
- A generic entity-component system and unrestricted arbitrary runtime blocks are outside V1.

### ARI-004 — Closed execution-stage taxonomy with open entries

Accepted.

- V1 defines a small, ordered taxonomy of execution stages with explicit scientific semantics.
- External compiled descriptors may contribute qualified entries to supported stages.
- The runtime does not contain a mechanism-name switch.
- An arbitrary user-defined phase DAG is outside V1.
- The compiler validates stage ordering, resource access, engine capabilities, and conflicts before
  execution.

### ARI-005 — Grouped specialization

Accepted.

- The compiler groups operations with the same descriptor and execution strategy.
- Julia specializes on a bounded number of operation families, not every statement occurrence or
  parameter value.
- Repeated coefficients, targets, identities, and similar model values remain backend-compatible
  data.
- The specification will include compile-time, generated-code-size, and allocation budgets that
  prevent symbolic model size from causing uncontrolled specialization.
- Per-statement tuple expansion and a non-specialized runtime interpreter are both rejected as the
  default V1 strategy.

## Round 2 — Concurrency, relationships, and portability

Owner response: **accept all recommended**

### ARI-006 — Resource-class checkerboard concurrency

Accepted.

- Checkerboard execution uses a closed set of concurrency policies selected by resource class.
- Spatial exclusion protects conflicting lattice writes.
- Exact atomics are used only for safe commutative integer effects.
- Deterministic grouped reductions are used where floating-point accumulation requires an explicit
  order.
- Exclusive ownership protects noncommutative state.
- Relationship and lifecycle mutations use ordered deferred batches.
- The architecture does not impose a universal transaction system or reject every proposal that
  touches the same cell.
- Reproducibility means deterministic conflict resolution for a fixed program, seed, backend, and
  execution schedule. It does not require sequential and checkerboard engines to produce identical
  stochastic trajectories.

### ARI-007 — Compiler-derived and validated resource footprints

Accepted.

- The compiler derives access footprints for ordinary built-in symbolic operations.
- External descriptors provide typed access and bounded-footprint traits.
- Compilation validates footprints against the selected stage, engine, and concurrency policy.
- An unbounded or data-dependent footprint must use a qualified deferred stage or declare
  checkerboard incompatibility.
- Runtime mechanism-name lists and unvalidated arbitrary access declarations are rejected.

### ARI-008 — Snapshot relationship reads with ordered deferred mutation

Accepted.

- Proposal energy reads an immutable relationship snapshot for a checkerboard batch.
- Accepted proposals emit typed relationship requests.
- Requests are deterministically ordered, validated, and applied at a specified stage barrier.
- Sequential execution uses the same request protocol with a batch size of one where necessary.
- Relationship packages own their descriptor and request types; CorePotts owns only the general
  staged-request contract.
- Immediate concurrent graph mutation and checkerboard-wide rejection of relationship models are
  both outside the accepted V1 direction.

### ARI-009 — Layered Julia portability stack

Accepted.

- KernelAbstractions is the custom device-kernel boundary.
- AcceleratedKernels is used selectively for suitable indexed traversal, sorting, scans, and
  reductions.
- Adapt is the device-transfer boundary.
- Atomix is used for explicitly permitted atomic operations.
- StaticArrays represents small fixed-size local values where appropriate.
- StructArrays is conditional on benchmarked data-layout value rather than a baseline dependency.
- CUDA, AMDGPU, and Metal are backend extensions.
- SciMLBase remains in PottsToolkit's host-side problem and solution layer rather than the
  CorePotts kernel runtime.
- Private GPU intrinsics, the former custom KernelIntrinsics fork, and wholesale restoration of the
  previous dependency stack are rejected.

The preferred abstraction ladder is ordinary array operations, then AcceleratedKernels, then
KernelAbstractions, and only then a measured backend-specific implementation.

### ARI-010 — CPU sequential reference and portable checkerboard engine

Accepted.

- Sequential is the authoritative scalar CPU engine.
- Checkerboard is the portable throughput engine and runs on CPU arrays and supported GPU
  backends.
- Both engines consume the same compiled descriptors and general state model.
- A term may declare checkerboard incompatibility only when the accepted deferred-stage protocols
  cannot represent its semantics.
- Efficient GPU sequential execution is not a V1 promise.
- Ordinary qualification requires CPU coverage. GPU release claims are made only for individually
  qualified backends; every vendor is not required on every pull request.

## Round 3 — ModelingToolkit composition and symbolic semantics

Owner response: **accept all recommended**

### ARI-011 — Honest conservative and nonequilibrium semantic taxonomy

Accepted.

- `HamiltonianTerm` represents a conservative energy contribution.
- `ProposalDrive` represents a directional or nonequilibrium proposal contribution.
- `ProposalConstraint` represents a hard proposal veto.
- `ProposalModifier` represents an acceptance or proposal modification that does not claim to be
  energy.
- The compiler obtains a Hamiltonian term's proposal delta from the affected energy before and
  after a discrete copy; it does not symbolically differentiate the expression.
- Focal-point elastic energy may be Hamiltonian. Relationship creation, deletion, maturation, and
  retuning are relationship processes.
- Randomness belongs to explicit proposal generation, acceptance, and stochastic-process semantics,
  not hidden calls inside symbolic energy expressions.

### ARI-012 — Analyzable symbolic vocabulary

Accepted.

- Ordinary symbolic expressions use a documented vocabulary of pure scalar operations, parameter
  lookup, universal proposal and lattice references, declared state observations, bounded
  neighborhood reductions, and qualified field or relationship observations.
- Expressions normalize into a scientific typed IR before lowering into grouped concrete
  descriptors.
- External symbolic operations require a host-side lowering with explicit resource, locality,
  device, and stage capabilities.
- Arbitrary Julia calls, closures, mutation, exceptions, and hidden random draws are rejected
  inside symbolic energy expressions.
- Arbitrary Symbolics-to-kernel compilation and a named-mechanism-only expression surface are both
  rejected.

### ARI-013 — Genuine ModelingToolkit integration with a numerical boundary

Accepted.

- `PottsSystem` participates through public ModelingToolkitBase system interfaces for symbolic
  unknowns, parameters, equations, observed quantities, events, hierarchy, namespacing,
  composition, extension, completion, transformation, and inspection where semantically valid.
- PottsToolkit owns the lifecycle from `PottsSystem` through `PottsExecutable`, `PottsProblem`,
  integrator, and `PottsSolution`.
- Problem construction, solving, remake, callbacks, and symbolic indexing follow SciMLBase
  conventions.
- A CPM is not translated into an ODE system, and CorePotts does not acquire ModelingToolkit
  dependencies.

### ARI-014 — Two explicit scales of coupled composition

Accepted.

- Tightly coupled compatible equation systems enter `PottsSystem` through a scheduled
  `EquationProcess`.
- The host compiler partitions equation-system execution from CPM descriptors and constructs the
  coupled integrator.
- External solver invocation does not occur inside an individual device copy-attempt kernel.
- Broader multiscale orchestration uses the optional PottsToolkit–ProcessBigraphs extension with
  typed ports, explicit state exchange, time advancement, and structural events.
- Future Vivarium interoperability belongs at the ProcessBigraphs component boundary.
- CorePotts does not become a general coupled-solver runtime, and ProcessBigraphs is not imposed on
  tightly coupled inner-loop field equations.

### ARI-015 — Host-side semantic plugins producing typed descriptors

Accepted.

- `RegisteredStatement` is the deliberate extension point for non-core scientific statement
  families.
- Registration provides semantic identity and version, completion and validation, symbolic
  lowering, state and workspace schemas, descriptor construction, resource footprints, stages,
  engine/backend capabilities, adaptation, checkpointing, inspection, and diagnostic rendering.
- Registration and validation finish before runtime compilation. Executables contain concrete
  descriptors rather than callbacks or registry references.
- Public macros are thin source-capture and readability tools over ordinary semantic constructors.
- Models remain inspectable Julia values, and inspection exposes source expansion, normalized
  statements, inferred resources, and compiled groups.
- Wortel and Merks are complete inline model definitions and demanding integration fixtures, not
  privileged compiler cases.

## Round 4 — Consolidation and autonomous implementation

Owner response: **accept all**

### ARI-016 — Surgical redirection on the current branch

Accepted.

- Preserve accepted public syntax, lifecycle, valid scientific semantics, relevant tests, the
  two-engine decision, and the clean removal of obsolete public APIs.
- Replace the monolithic V1 program, named biological program fields, mechanism switches, serial
  checkerboard implementation, proposal-time lattice scans, and hot-path dynamic allocation.
- Selectively recover portable kernels, adaptation, workspaces, staged checkerboard execution,
  incremental trackers, backend extensions, and allocation discipline from the previous engine.
- A read-only temporary clone of `main` may support algorithm and test understanding. It is not
  imported, invoked, linked, or treated as an executable oracle.

### ARI-017 — Layered semantic test authority

Accepted.

- Exact unit tests govern normalization, lowering, energy deltas, acceptance calculations,
  incremental trackers, request ordering, checkpoint reconstruction, and other exact contracts.
- Same-engine replay is deterministic for a fixed seed, backend, schedule, and compiler
  configuration where the backend support level promises it.
- Property tests govern locality, conservation, connectivity, relationship integrity, and state
  consistency.
- Statistical tests govern stochastic scientific behavior.
- Analytic or independently calculated fixtures govern suitable small models.
- Checkerboard is tested against its specified batch semantics.
- Cross-engine equality is required only where the specification promises it; other comparisons
  are statistical or invariant-based.
- A downstream conformance fixture proves external term, state, adaptation, checkpoint, and
  execution extensibility without CorePotts edits.
- Scientifically equivalent tests from `main` are preserved or rewritten. Removed compatibility,
  engine, archive, oracle, and evidence-bureaucracy tests remain removed.
- Wortel and Merks are integration fixtures, not semantic oracles.

### ARI-018 — Standard Julia-library qualification

Accepted.

- Ordinary pull-request CI covers package loading, unit and integration tests, supported Julia
  versions, CPU engines, source-quality checks, and downstream extension conformance.
- Performance-sensitive tests cover hot-loop allocation budgets, forbidden dynamic device objects,
  bounded compilation growth, tracker consistency, and representative benchmarks.
- Large performance runs, statistical campaigns, and GPU vendor matrices are manual, scheduled, or
  release-oriented rather than ordinary pull-request gates.
- Missing or stale hardware evidence does not fail an ordinary code change.
- Backend support claims require backend-specific compile-and-run qualification.
- No replacement evidence-oracle system is introduced.

### ARI-019 — Architecture plus Wortel and Merks as the V1 proof

Accepted.

V1 includes the typed scientific and compiled IR, grouped descriptors, general
state/workspace/resource contracts, CPU sequential and portable checkerboard engines, required
deferred requests, ModelingToolkitBase and SciMLBase integration, the selective JuliaGPU stack, an
external-module conformance fixture, scientifically complete Wortel and Merks fixtures, sufficient
lowering inspection, and removal of the incorrect monolithic executor.

V1 excludes migrations, deprecated aliases, wrappers, dual paths, polished documentation,
tutorials, Lottery, tiled execution, Dagger, universal concurrent graph mutation, arbitrary
execution DAGs, arbitrary Julia-to-device compilation, broad literature reproduction, Vivarium
adapters, efficient sequential GPU execution, and a new evidence-oracle system.

### ARI-020 — One autonomous architecture-first implementation phase

Accepted.

After the normative consolidation specification is accepted and audited, implementation proceeds
without additional owner interviews through internal architecture gates:

1. freeze semantic and test authority;
2. establish dependencies, backend extensions, and portable state conventions;
3. implement descriptor, resource, workspace, and stage contracts;
4. implement the CPU sequential reference;
5. implement staged portable checkerboard execution;
6. implement deferred relationship and lifecycle requests;
7. redirect PottsToolkit lowering and ModelingToolkit integration;
8. lower the general mechanisms required by Wortel and Merks;
9. add the independent downstream extension fixture;
10. reconstruct Wortel and Merks without CorePotts edits;
11. remove superseded execution scaffolding;
12. run functional, stochastic, allocation, compilation-growth, and available-backend gates; and
13. audit the final diff against every accepted normative clause.

A failed gate returns implementation to the earliest violated abstraction instead of authorizing a
special case.

The terminal architectural test is that a separate module defines a novel Hamiltonian term with
auxiliary state, lowers it into a typed descriptor, adapts and checkpoints it, and executes it on
sequential and checkerboard engines without modifying CorePotts's program container, proposal
loop, engines, or checkpoint machinery. Wortel and Merks running is necessary but not sufficient.

## Interview closure

All owner decisions required for architecture-redirection consolidation are accepted. The next
authorized work is specification consolidation and contradiction audit. Implementation remains
unauthorized until that specification is complete, audited, and explicitly sent off by the owner.
