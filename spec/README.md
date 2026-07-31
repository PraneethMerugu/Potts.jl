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
- [Symbolic Potts V1](symbolic-potts-v1.md)
- [Symbolic Potts V1 Autonomous Consolidation Contract](symbolic-potts-v1-consolidation.md)
- [Symbolic Potts V1 Architecture Redirection Contract](symbolic-potts-v1-architecture-redirection.md)
- [Symbolic Potts V1 Compiler Construction Contract](symbolic-potts-v1-compiler-construction.md)
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
- [Phase 16 Engine, Field, Structural, and Adapter Semantics](phase-16-engine-field-structural-and-adapter-semantics.md)
- [ProcessBigraphs High-Level Authoring Semantics](process-bigraph-high-level-authoring-semantics.md)
- [Phase 16 Entry Contract](process-bigraph-phase16-entry-v1.toml)
- [Phase 16 Qualification Ledger](process-bigraph-phase16-qualification-v1.toml)
- [Phase 16 Backend Matrix](process-bigraph-phase16-backend-matrix-v1.toml)
- [Phase 16 Migration Registry](process-bigraph-phase16-migration-registry-v1.toml)
- [Phase 16 Model Scope](process-bigraph-phase16-model-scope-v1.toml)
- [Phase 16 API Contract](process-bigraph-phase16-api-v1.toml)
- [Semantic-Preserving Repository Consolidation Contract](semantic-preserving-consolidation-contract.md)
- [Semantic-Preserving Consolidation Qualification Ledger](semantic-preserving-consolidation-qualification-v1.toml)
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

- [Symbolic Potts V1 Round 3 Research](../design/audits/symbolic-potts-v1-round-3-research.md)
- [Symbolic Potts V1 Round 4 Research](../design/audits/symbolic-potts-v1-round-4-research.md)
- [Symbolic Potts V1 Consolidation Research](../design/audits/symbolic-potts-v1-consolidation-research.md)
- [Symbolic Potts V1 MTK and ProcessBigraphs Integration Research](../design/audits/symbolic-potts-v1-mtk-processbigraph-integration-research.md)
- [Symbolic Potts V1 Consolidation Owner Interview](../design/audits/symbolic-potts-v1-consolidation-owner-interview.md)
- [Symbolic Potts V1 Consolidation Readiness Audit](../design/audits/symbolic-potts-v1-consolidation-audit.md)
- [Symbolic Potts V1 Architecture Redirection Owner Interview](../design/audits/symbolic-potts-v1-architecture-redirection-owner-interview.md)
- [Symbolic Potts V1 Architecture Redirection Specification Audit](../design/audits/symbolic-potts-v1-architecture-redirection-spec-audit.md)
- [Symbolic Potts V1 Compiler Capability and Construction Audit](../design/audits/symbolic-potts-v1-compiler-capability-and-construction-audit.md)
- [Symbolic Potts V1 Compiler Consolidation Owner Interview](../design/audits/symbolic-potts-v1-compiler-consolidation-owner-interview.md)
- [Symbolic Potts V1 Quick Confidence-Test Research](../design/audits/symbolic-potts-v1-quick-confidence-test-research.md)
- [Symbolic Potts V1 Execution-Control Audit](../design/audits/symbolic-potts-v1-execution-control-audit.md)
- [Symbolic Potts V1 Implementation Control](../design/audits/symbolic-potts-v1-implementation-control.md)
- [Symbolic Potts V1 Compiler Construction Specification Audit](../design/audits/symbolic-potts-v1-compiler-construction-spec-audit.md)
- [ProcessBigraphs Phase 16 Owner Interview](../design/audits/process-bigraph-phase16-owner-interview.md)
- [Decision 0039: Phase 16 Compute Ownership and Scope](decisions/0039-phase-16-compute-ownership-and-scope.md)
- [ProcessBigraphs Phase 16.HC High-Level Authoring Owner Interview](../design/audits/process-bigraph-phase16hc-high-level-authoring-owner-interview.md)
- [Decision 0040: ProcessBigraphs High-Level Authoring and Phase 16.HC](decisions/0040-process-bigraph-high-level-authoring.md)
- [Semantic-Preserving Consolidation Owner Interview](../design/audits/semantic-preserving-consolidation-owner-interview.md)
- [Decision 0041: Semantic-Preserving Repository Consolidation](decisions/0041-semantic-preserving-repository-consolidation.md)
- [Semantic-Preserving Consolidation Baseline Freeze](../design/audits/semantic-preserving-consolidation-baseline-freeze.md)
- [ProcessBigraphs Phase 16.HC Qualification Audit](../design/audits/process-bigraph-phase16hc-high-level-authoring-audit.md)
- [ProcessBigraphs Phase 16.HC Evidence](../design/evidence/process-bigraph-phase16hc-evidence-v1.toml)
- [ProcessBigraphs Phase 16 Implementation Plan](../design/audits/process-bigraph-phase16-implementation-plan.md)
- [ProcessBigraphs Phase 16 Entry Audit](../design/audits/process-bigraph-phase16-entry-audit.md)
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
- [AlgebraicJulia and Independent-Conformance Owner Interview](../design/audits/process-bigraph-algebraicjulia-owner-interview.md)
- [Decision 0036: AlgebraicJulia as the ProcessBigraphs Structural Foundation](decisions/0036-algebraicjulia-process-bigraph-foundation.md)
- [ProcessBigraphs Phase 15.B Open-Composition Owner Interview](../design/audits/process-bigraph-phase15b-open-composition-owner-interview.md)
- [Decision 0037: ProcessBigraphs Open-Composition Semantics](decisions/0037-process-bigraph-open-composition.md)
- [ProcessBigraphs Phase 15.B Open-Composition Plan](../design/audits/process-bigraph-phase15b-open-composition-plan.md)
- [ProcessBigraphs Phase 15.B Open-Composition Audit](../design/audits/process-bigraph-phase15b-open-composition-audit.md)
- [ProcessBigraphs Phase 15.B Evidence](../design/evidence/process-bigraph-phase15b-evidence-v1.toml)
- [ProcessBigraphs Phase 15.C Serial-Alpha Owner Interview](../design/audits/process-bigraph-phase15c-serial-alpha-owner-interview.md)
- [Decision 0038: ProcessBigraphs Phase 15.C Serial Internal Alpha](decisions/0038-process-bigraph-serial-alpha.md)
- [ProcessBigraphs Phase 15.C Serial-Alpha Plan](../design/audits/process-bigraph-phase15c-serial-alpha-plan.md)
- [ProcessBigraphs Phase 15.C Entry Contract](process-bigraph-phase15c-entry-v1.toml)
- [ProcessBigraphs Phase 15.C Qualification Ledger](process-bigraph-phase15c-qualification-v1.toml)
- [ProcessBigraphs Phase 15.C Entry Audit](../design/audits/process-bigraph-phase15c-entry-audit.md)
- [ProcessBigraphs Phase 15.C Closure Audit](../design/audits/process-bigraph-phase15c-closure-audit.md)
- [ProcessBigraphs Phase 15.C Documentation Consistency Audit](../design/audits/process-bigraph-phase15c-documentation-consistency-audit.md)
- [ProcessBigraphs Phase 15.C Evidence](../design/evidence/process-bigraph-phase15c-evidence-v1.toml)
- [ProcessBigraphs PB0 Implementation Audit](../design/audits/process-bigraph-pb0-implementation-audit.md)
- [ProcessBigraphs PB0 Evidence](../design/evidence/process-bigraph-pb0-evidence-v1.toml)
- [ProcessBigraphs Phase 15.A Canonical-Structure Audit](../design/audits/process-bigraph-phase15a-canonical-structure-audit.md)
- [ProcessBigraphs Phase 15.A Evidence](../design/evidence/process-bigraph-phase15a-evidence-v1.toml)
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

Decisions 0034 and 0036 establish `ProcessBigraphs.jl` as an independent package under `lib/`, with
source-audited feature and semantic parity against exact pinned Process-Bigraph 2.0 sources. One
custom ProcessBigraph ACSet is the accepted canonical structural foundation, with structured
cospans for open composition, derived wiring diagrams, and ProcessBigraphs-owned compiled runtime
plans. Its checked Julia specification oracle is independent from production execution; the
deterministic serial executor is the equivalence reference for Dagger and device executors, which
cannot redefine time, visibility, reconciliation, or commit order. Phase 14.PB0 now passes
as a bounded foundation: the independent package and 11 direct registry rows are implemented and
locally tested. Phase 15.A also passes as a bounded canonical-structure slice: ACSets and Catlab are
direct bounded dependencies, typed and direct ACSet authoring share one canonical model, and the
runtime consumes an immutable indexed plan rather than traversing the authoring ACSet. The two
corresponding registry rows are implemented. Phase 15.B now passes immutable open composition and
the annotated wiring view with direct evidence.
Decision 0038 and the completed 64-choice owner interview freeze Phase 15.C as an
immutable-topology serial internal-alpha gate. Its exact 15 target rows, seven supporting
oracle-requalification rows, four retained structural rows, exclusions, fixtures, strict C0--C7
order, independent-oracle boundary, and two-stage attested closure are machine-readable in the
Phase 15.C entry contract. C0--C7 now pass: implementation PR #24 passed Required CI, the
independent stdlib-only oracle and complete qualification matrix passed, and its squash-merge tree
exactly matches the qualified tree. The metadata-only attestation promotes ProcessBigraphs to
`0.4.0` with `internal_alpha = true` and `public_release = false`. GPU execution, parallel
executors, dynamic structure, adapters, the Potts cutover, complete parity, and public release
remain explicitly open. CI and release tooling do not execute the upstream Python runtimes. See
the [closure audit](../design/audits/process-bigraph-phase15c-closure-audit.md) and
[evidence manifest](../design/evidence/process-bigraph-phase15c-evidence-v1.toml).

Decision 0035 retires assembled Wang GPU qualification because the paper-faithful sequential
algorithm is not an appropriate GPU promotion target. Decision 0039 absorbs the still-open G4
CPU/Metal/ROCm reusable-field obligation into Phase 16.C. The accepted 481-choice Phase 16
interview additionally freezes the solver-neutral field protocol, dynamic hierarchy, CorePotts
strangler adapter, CPU SciML/custom proof adapters, and bounded runnable Merks/CNV scope.
ProcessBigraphs owns when and why computation occurs; optimized solver and CPM kernels own how the
heavy computation occurs. Phase 16 is qualified as unpublished ProcessBigraphs `0.5.0` internal
beta. All 38 rows pass, including the engine/field boundary, dynamic orchestration transactions,
CorePotts native-field cutover, typed domain requests, V3 logical checkpoint, non-destructive
legacy conversions, bounded runnable Merks/CNV assemblies, ordinary Julia authoring,
deterministic lowering, complete origin mapping, controlled raw-IR migration, and stage-separated
performance guardrails. Phase 16.C retains trusted exact-source CPU, Metal, and ROCm artifacts;
Phase 16.I retains the admitted candidate, complete performance report, evidence manifest, and
closure audit. The Phase 16.HC obligations and claim boundary are normative in the
[high-level authoring specification](process-bigraph-high-level-authoring-semantics.md) and
content-addressed in its [qualification evidence](../design/evidence/process-bigraph-phase16hc-evidence-v1.toml). The
[16.F solver-integration consolidation](../design/audits/process-bigraph-phase16f-solver-integration-consolidation-research.md)
classified rebased commit `e0fd0b3` as an unqualified prototype. The resulting
[qualified solver-plurality audit](../design/audits/process-bigraph-phase16f-solver-plurality-audit.md)
records rebased commit `6cd20d9`: a real injected SciML algorithm, standard solver interfaces, an
external-style independent custom fixture, numerical replay by default, analytic/convergence
evidence, and a bounded adapter-author API. The
[qualified Merks audit](../design/audits/process-bigraph-phase16g-merks-audit.md) records commit
`e9ce80b`: one ProcessBigraphs-owned schedule around native, real-SciML, and independent field
adapters plus the CorePotts CPM kernel, without claiming the paper's full Figure 5 analysis.
The [qualified CNV audit](../design/audits/process-bigraph-phase16h-cnv-audit.md) records the
source-bounded scenario-38/simulation-902 assembly: a generated 40×40×35 startup, four
solver-injectable fields, a CorePotts CPM phase, lifecycle and degradation fixtures, and
restart/rollback evidence without a publication-analysis claim.

The accepted
[semantic-preserving repository consolidation contract](semantic-preserving-consolidation-contract.md)
remains the historical main-branch baseline. On `codex/symbolic-potts-v1`, conflicting
authoring/compiler/API requirements are superseded by
[Symbolic Potts V1](symbolic-potts-v1.md) and its
[autonomous consolidation contract](symbolic-potts-v1-consolidation.md). The historical
consolidation contract is
governed by the completed
[owner interview](../design/audits/semantic-preserving-consolidation-owner-interview.md) and
[Decision 0041](decisions/0041-semantic-preserving-repository-consolidation.md).
It freezes the qualified ProcessBigraphs 0.5.0 internal-beta head as the behavioral baseline,
requires one production authority per concept, replaces living milestone terminology with domain
vocabulary, consolidates tests and quality tooling without weakening independent oracles,
preserves API/identity/persistence/backend claims, and forbids new functionality. The
[37-row qualification ledger](semantic-preserving-consolidation-qualification-v1.toml) separates
baseline, naming, architecture, deduplication, test/tooling, package, and exact-head reconciliation
evidence. All 37 rows are now qualified. The
[baseline freeze](../design/audits/semantic-preserving-consolidation-baseline-freeze.md) remains
the behavioral authority, while the
[closure audit](../design/audits/semantic-preserving-consolidation-closure.md) and
[exact-head evidence](../design/evidence/consolidation-qualified/exact-head-v1.toml) record the
qualified `0.5.1` internal-beta candidate, exact CPU and trusted-hardware runs, platform
installation smokes, performance results, API disposition, and zero-functional-delta attestation.
Repository consolidation is closed; later roadmap redesign remains a separate decision.

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
