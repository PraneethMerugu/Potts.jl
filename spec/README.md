# Potts.jl and ProcessBigraphs.jl Semantics Specification

Version: `0.5-draft`

Status: Draft

## Authority

This specification defines the observable scientific behavior of Potts.jl and the domain-neutral
runtime contracts of the internally incubated `ProcessBigraphs.jl`. A conforming implementation
may change storage layouts, kernel organization, parallel scheduling, backend libraries, and other
internal mechanisms, but it MUST preserve the applicable normative behavior defined here.

The specification is authoritative over implementation comments, tutorials, examples, and
historical behavior. Until a section is marked `Accepted`, existing code MUST NOT be assumed to
define the intended semantics.

## Normative Language

The words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are normative:

- **MUST** and **MUST NOT** define conformance requirements.
- **SHOULD** and **SHOULD NOT** define expected behavior from which an implementation may depart
  only for a documented reason.
- **MAY** identifies permitted behavior.

Each document or section has one of these statuses:

- **Accepted**: approved project semantics.
- **Provisional**: current direction requiring validation or derivation.
- **Under Investigation**: no semantic decision has been accepted.
- **Experimental**: deliberately excluded from compatibility guarantees.

Semantic status is independent of implementation maturity. Conformance evidence uses these
implementation labels:

- **Specified**: the observable contract is written, but no package implementation is claimed.
- **Reference implemented**: the ordinary sequential CPU implementation exercises the contract.
- **Production implemented**: at least one optimized execution path implements the contract.
- **Backend qualified**: the named backend has passed its required correctness, statistical,
  device-code, allocation, synchronization, and performance evidence.
- **Deferred**: implementation is intentionally assigned to a later roadmap phase.

An `Accepted` rule can therefore still be only `Specified`. Conversely, historical working code is
not conforming merely because it runs. Documents and release claims MUST state semantic status and
implementation maturity separately.

## Scope

This specification covers:

- The independent ProcessBigraphs runtime boundary and pinned parity contract
- Hierarchical runtime state, ports, processes, steps, deltas, clocks, commits, and executors
- The lattice, cells, cell types, media, and per-cell state
- Monte Carlo time and copy-attempt semantics
- Energy, proposal, acceptance, and tracker contracts
- Cell lifecycle events
- Algorithmic guarantees and normalized time
- Randomness and reproducibility
- Observation, saving, and checkpoint semantics
- Cross-backend numerical and statistical expectations
- The user-visible SciML and PottsToolkit behavior

Implementation techniques such as KernelAbstractions kernels, AcceleratedKernels operations,
StructArrays storage, StaticArrays lowering, KernelIntrinsics, generated functions, and backend
workarounds belong in design documents. They become semantic only when they affect observable
behavior.

## Documents

- [Project Charter](project-charter.md)
- [Glossary](glossary.md)
- [State Model](state-model.md)
- [Time and Monte Carlo Steps](time-and-mcs.md)
- [Auxiliary Constraints and Mechanical State](auxiliary-state-semantics.md)
- [Lifecycle](lifecycle.md)
- [Randomness and Reproducibility](randomness-and-reproducibility.md)
- [Snapshots, Checkpoints, Restore, and Logical Storage](persistence.md)
- [Energy, Proposals, Acceptance, and Trackers](energy-proposals-and-trackers.md)
- [Topology and Spatial Relations](topology-and-spatial-relations.md)
- [Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md)
- [PottsToolkit Rule and Model Semantics](pottstoolkit-rule-and-model-semantics.md)
- [PottsToolkit Authoring, Composition, and API Semantics](pottstoolkit-authoring-composition-and-api-semantics.md)
- [CorePotts Public Scientific and Execution Interfaces](corepotts-public-interface-semantics.md)
- [Sequential Reference Engine](reference-engine-semantics.md)
- [SciML Problem, Integrator, Solution, and Ensemble Semantics](sciml-interface-semantics.md)
- [Numerical and Cross-Backend Semantics](numerical-and-cross-backend-semantics.md)
- [Transition-Kernel Verification and Algorithm Characterization](transition-kernel-verification.md)
- [Published-Model Reproduction Semantics](published-model-reproduction-semantics.md)
- [Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md)
- [Phase 14 Contract Registry v2](phase-14-contract-registry-v2.toml)
- [Process-Bigraph Runtime Semantics](process-bigraph-runtime-semantics.md)
- [Process-Bigraph Parity Registry v1](process-bigraph-parity-registry-v1.toml)
- [Unresolved Questions](unresolved.md)
- [Specification-to-Conformance Evidence Index](conformance-evidence.md)
- [Decision Records](decisions/README.md)

The following Phase 14 documents are superseded design and prototype evidence. They are not
independent semantic authorities:

- [Coupled Dynamics and ModelingToolkit API](phase-14-coupled-dynamics-api.md)
- [Coupled Execution and MCS Plan](phase-14-coupled-execution-semantics.md)
- [Dynamic State Ownership](phase-14-dynamic-state-semantics.md)
- [Spatial Roles and Source Attempts](phase-14-spatial-and-attempt-semantics.md)
- [Cell and Field Dynamics](phase-14-cell-and-field-dynamics-semantics.md)
- [Continuous Systems and Morpheus Compatibility](phase-14-continuous-systems-and-morpheus-compatibility.md)
- [Relationships and Coupled Lifecycle](phase-14-relationship-and-lifecycle-semantics.md)
- [Coupled Persistence and Paper Observation](phase-14-coupled-persistence-and-observation-semantics.md)
- [Contract Registry v1](phase-14-contract-registry-v1.toml)

Engineering realization is described separately in:

- [Open Protocol and Extensibility Standard](../design/open-protocol-and-extensibility-standard.md)
- [Metaprogramming and Compiler Architecture Standard](../design/metaprogramming-and-compiler-architecture.md)
- [JuliaGPU and Performance Programming Standard](../design/juliagpu-and-performance-programming-standard.md)
- [Refactor, Benchmark, and Paper-Release Standard](../design/refactor-benchmark-and-paper-release-standard.md)
- [Repository Architecture Standard](../design/repository-architecture-standard.md)
- [Paper-Release Refactor Roadmap](../design/refactor-roadmap.md)

Refactor execution evidence:

- [Open-Protocol Audit](../design/audits/open-protocol-audit.md)
- [Phase 9 Current-Code and Gap Audit](../design/audits/phase-9-current-code-and-gap-audit.md)
- [Phase 9 SciML and JuliaGPU Research](../design/audits/phase-9-sciml-and-gpu-research.md)
- [Phase 9 Implementation Chunk Plan](../design/audits/phase-9-chunk-plan.md)
- [Phase 9 Legacy Final-Name Evacuation](../design/audits/phase-9-legacy-evacuation.md)
- [Phase 9 Completion Audit](../design/audits/phase-9-completion-audit.md)
- [Phase 10 Typed API and Compiler Decision](decisions/0026-phase-10-typed-api-and-compiler.md)
- [Phase 10 Current-Code and Gap Audit](../design/audits/phase-10-current-code-and-gap-audit.md)
- [Phase 10 Implementation Chunk Plan](../design/audits/phase-10-chunk-plan.md)
- [Phase 10 Completion Audit](../design/audits/phase-10-completion-audit.md)
- [Phase 13 Algorithmic Conformance and API Freeze Plan](../design/audits/phase-13-transition-kernel-chunk-plan.md)
- [Phase 14 Model-Driven Capability and Documentation Decision](decisions/0029-phase-14-model-driven-capability-and-documentation-policy.md)
- [Phase 14.0 Completion Audit](../design/audits/phase-14-0-corpus-and-requirements-audit.md)
- [Phase 14 Source Closure and Sensitivity Envelopes](../design/audits/phase-14-source-closure-v1.toml)
- [Phase 14 D9 Work-Item Registry](../design/audits/phase-14-d9-work-items-v1.toml)
- [Phase 14 Semantic-Architecture Simplification Audit](../design/audits/phase-14-semantics-simplification-audit.md)
- [Phase 14 Focused Semantic-Architecture Interview](../design/audits/phase-14-semantics-focused-interview.md)
- [Phase 14 Generic Authoring Simplification Audit](../design/audits/phase-14-generic-authoring-simplification-audit.md)
- [Phase 14 GPU-Native Implementation and Qualification Plan](../design/audits/phase-14-gpu-native-implementation-plan.md)
- [Process-Bigraph Runtime Parity and Parallel-Development Audit](../design/audits/process-bigraph-runtime-parity-and-parallel-development-audit.md)
- [Process-Bigraph Runtime Owner Interview](../design/audits/process-bigraph-runtime-owner-interview.md)
- [Phase 8 Minimality Pass](../design/audits/phase-8-minimality-pass.md)
- [Phase 8 Mechanical Lifecycle Research](../design/audits/phase-8-mechanical-lifecycle-research.md)
- [JuliaGPU and Open-Protocol Community Validation](../design/audits/juliagpu-open-protocol-research.md)
- [Phase 0 Current-Code Audit](../design/audits/phase-0-current-code-audit.md)
- [Phase 0 Paper-Scope Map](../design/audits/phase-0-paper-scope-map.md)

Phase 14.0 froze the published-model requirements and registered Provisional D9 contracts for
evolving fields, accepted-copy site state, general continuous state, dynamic relationship graphs,
degradable structures, staged protocols, events, mappings, and research observables. Each contract
still follows the normal prototype, conformance, persistence, and backend change process before
acceptance or implementation claims. Decision 0031 and the completed focused interview consolidate
those requirements into registry v2's seven-area kernel. Decision 0032 requires every stable
Phase 14 execution capability to pass a sequential CPU reference and backend-resident,
real-hardware Metal and ROCm qualification. Decision 0033 requires complex models to use the same
generic hierarchical `ModelFragment` composition, named typed requirements/exports, and one
explicit root plan; paper-specific builders cannot substitute for that API evidence. The
[Wortel Act-CPM vertical slice](../design/audits/phase-14-wortel-vertical-slice-evidence.md)
passes on CPU, Metal, and ROCm. Wang G3-A and its sequential CPU G3-B gate are complete; the
authoritative [G3-B closure ledger](../design/audits/phase-14-g3b-closure-ledger-v1.toml) records
`overall_status = "passed"`. Its exact
[source/runtime execution order](../design/audits/phase-14-wang-order-audit.md), revision-7
[G3-B entry packet](../design/audits/phase-14-g3b-entry-packet.md) and
[closure specification audit](../design/audits/phase-14-g3b-closure-spec-audit.md) additionally
freeze source MCS `0:499` to normalized target MCS `1:500`, atomic field/exchange publication,
completed-MCS-only restart, and deterministic reduction/device-readiness gates. The seven contracts
remain Provisional outside proven scope. Registry v1 spellings remain internal historical
prototypes and are not compatibility commitments.

Decision 0034 establishes `ProcessBigraphs.jl` as an independent package under `lib/`, with
feature and observable-behavior parity against exact pinned Process-Bigraph 2.0 sources. Its
deterministic serial executor is the semantic oracle; Dagger and device executors may run selected
work but cannot redefine time, visibility, reconciliation, or commit order. G3-C remains the next
Potts gate while runtime specification and isolated non-Potts implementation may proceed in
parallel.

## Conformance Principle

A semantic rule is not complete until it can be connected to one or more of:

- A mathematical definition
- A minimal reference example
- A state invariant
- A conformance test
- A statistical validation procedure

The long-term criterion is that a new engine can be implemented without copying an existing engine
and then validated against the shared conformance suite.

## Change Process

1. Document current implementation behavior and relevant literature.
2. Identify conflicts between code, documentation, and intended science.
3. Record the proposed semantic decision and its consequences.
4. Obtain project approval.
5. Update this specification and add a decision record.
6. Add or update conformance tests.
7. Migrate implementations only after the semantic contract is accepted.

Changes to accepted semantics MUST update the specification version and include a migration impact
assessment.
