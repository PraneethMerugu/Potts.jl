# Potts.jl Semantics Specification

Version: `0.3-draft`

Status: Draft

## Authority

This specification defines the observable scientific behavior of Potts.jl. A conforming
implementation may change storage layouts, kernel organization, parallel scheduling, backend
libraries, and other internal mechanisms, but it MUST preserve the applicable normative behavior
defined here.

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
- [Unresolved Questions](unresolved.md)
- [Specification-to-Conformance Evidence Index](conformance-evidence.md)
- [Decision Records](decisions/README.md)

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
- [Phase 8 Minimality Pass](../design/audits/phase-8-minimality-pass.md)
- [Phase 8 Mechanical Lifecycle Research](../design/audits/phase-8-mechanical-lifecycle-research.md)
- [JuliaGPU and Open-Protocol Community Validation](../design/audits/juliagpu-open-protocol-research.md)
- [Phase 0 Current-Code Audit](../design/audits/phase-0-current-code-audit.md)
- [Phase 0 Paper-Scope Map](../design/audits/phase-0-paper-scope-map.md)

Future documents will cover the remaining algorithm proofs, final rule-language details, and the
separately scoped evolving-field semantics required for PDE stepping, secretion, uptake, and named
operator splitting.

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
