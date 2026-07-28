# Semantic-Preserving Repository Consolidation Contract

Status: Accepted normative specification; baseline frozen, production consolidation not started

Version: 1.0.0

Date: 2026-07-28

Authority: Decision 0041, the completed semantic-preserving consolidation owner interview, the
qualified ProcessBigraphs 0.5.0 internal-beta closure, accepted Decisions 0028, 0031, 0034, and
0036--0040, the repository architecture and performance standards, and the project-owner direction
to consolidate the package family without adding or removing functionality

Companion ledger:
[`semantic-preserving-consolidation-qualification-v1.toml`](semantic-preserving-consolidation-qualification-v1.toml)

## 1. Purpose

This contract governs a repository-wide consolidation of `ProcessBigraphs`, `CorePotts`,
`PottsToolkit`, `MakiePotts`, package tests, integration tests, quality tooling, documentation, and
current specification indexes.

The result MUST preserve the qualified scientific and runtime behavior while making the living
codebase:

- more direct and DRY;
- organized by domain responsibility rather than development chronology;
- consistently named;
- easier to test, inspect, extend, and maintain;
- free of parallel production authorities; and
- free of active phase- or milestone-based naming except at explicit compatibility and historical
  evidence boundaries.

This is a semantic-preserving consolidation, not a feature phase, API redesign, numerical-method
change, scientific-scope expansion, performance optimization campaign, or public release.

The keywords MUST, MUST NOT, REQUIRED, SHOULD, SHOULD NOT, and MAY are normative.

## 2. Starting authority and measured baseline

### 2.1 Qualified baseline

The consolidation baseline is the exact ProcessBigraphs 0.5.0 unpublished internal-beta closure
recorded by:

- `design/audits/process-bigraph-phase16-closure-audit.md`;
- `design/evidence/process-bigraph-phase16i-evidence-v1.toml`;
- `spec/process-bigraph-phase16-entry-v1.toml`;
- `spec/process-bigraph-phase16-qualification-v1.toml`; and
- final CI run `30399756947` at commit
  `d2f4d40e78fb68ee20da483d9784b55d25bf6147`.

All previously accepted Potts, ProcessBigraphs, authoring, persistence, SciML, backend,
reproducibility, and published-model claim boundaries remain normative. Consolidation may change
implementation location and private spelling; it may not weaken or broaden those contracts.

### 2.2 Current structural baseline

The pre-consolidation audit observed:

- 388 tracked Julia files;
- 87 tracked Julia files with phase-based paths or filenames;
- 22 `scripts/process-bigraph-*.jl` quality scripts totaling 4,692 lines;
- 18 phase-organized ProcessBigraphs test files;
- 20 phase-named CorePotts test files;
- 40 phase-named root or integration test files;
- no phase-named active library source filenames, but approximately 108 milestone-coded source
  identifiers, messages, documentation strings, or protocol values;
- a 4,119-line ProcessBigraphs composition/structure/lowering responsibility cluster;
- a 1,463-line ProcessBigraphs logical-codec/checkpoint responsibility cluster; and
- CorePotts responsibility clusters including `continuous.jl` at 2,785 lines and
  `relationships.jl` at 2,554 lines.

These measurements identify consolidation pressure; raw line-count reduction is not itself a
conformance goal. A smaller implementation is better only when ownership and behavior become more
obvious.

### 2.3 Implementation is evidence, not authority

Existing code determines the inventory that must be reconciled, but an accidental duplicate,
unreachable path, misleading name, or historical implementation layer is not made permanent merely
because it exists.

Deleting or merging such code is permitted only after proving that:

1. it is not a distinct accepted semantic authority;
2. every consumer has a named canonical replacement;
3. applicable behavioral, persistence, fingerprint, failure, and performance evidence remains;
   and
4. the qualified claim boundary is unchanged.

## 3. Non-negotiable invariants

### 3.1 Functionality conservation

The consolidation MUST have zero unapproved functional delta.

For this contract, functionality includes:

- accepted scientific meaning and model behavior;
- supported and rejected input envelopes;
- public construction, execution, observation, persistence, and inspection behavior;
- scheduling, logical time, visibility, reconciliation, transaction, and publication semantics;
- solver and CPM ownership boundaries;
- numerical algorithms, tolerances, stopping rules, and declared replay classes;
- CPU, Metal, ROCm, extension, and residency behavior;
- deterministic traces, semantic RNG addresses, and replay;
- error types, stable error codes, and failure atomicity;
- canonical fingerprints and serialized identities;
- checkpoint encoding, decoding, restoration, and migration compatibility;
- documented capability and limitation claims; and
- applicable performance and allocation budgets.

No feature may be added, removed, generalized, narrowed, accelerated through a different algorithm,
or exposed as newly qualified under this contract.

### 3.2 One production authority

Each accepted concept MUST have one production authority. In particular, the consolidated system
MUST have:

- one author-facing semantic model;
- one canonical ProcessBigraph structural representation;
- one deterministic lowering route from semantic model to canonical structure;
- one compilation route from canonical structure to execution plan;
- one runtime route per qualified execution mode;
- one engine transaction state machine;
- one field descriptor and publication contract;
- one canonical logical-value encoding mechanism;
- one current checkpoint front door with explicitly versioned codecs;
- one validation and diagnostic vocabulary per layer; and
- one authoritative implementation for each scientific mechanism and qualified backend path.

Compatibility readers, deprecated names, independent oracles, and backend-specific kernels are not
second production authorities when they are explicitly bounded by this contract.

### 3.3 Compute ownership

ProcessBigraphs MUST continue to own when and why computation occurs. Solvers and optimized CPM
kernels MUST continue to own how their authorized heavy computation occurs.

The consolidation MUST NOT move numerical stepping, convergence, array layout, kernel, workspace,
stream, or cache authority into ProcessBigraphs. It MUST NOT move logical time, scheduling,
visibility, authorization, publication, failure, checkpoint, or replay authority into CorePotts or
a solver adapter.

### 3.4 Package boundaries

The existing dependency direction MUST remain:

```text
ProcessBigraphs <- CorePotts <- PottsToolkit
```

`MakiePotts` and optional extensions depend on the lowest appropriate public interface.
ProcessBigraphs MUST NOT acquire a CorePotts, PottsToolkit, concrete SciML algorithm, Metal, AMDGPU,
CUDA, or visualization dependency. Existing weak-extension boundaries MUST remain weak unless a
separate accepted semantic decision changes them.

### 3.5 Historical evidence

Qualified evidence content, source pins, run identifiers, hashes, frozen protocol identifiers, and
decision history MUST NOT be rewritten to look contemporary.

Historical evidence may remain under phase-named paths. It MUST be indexed as historical authority
and isolated from the living source, tests, CI vocabulary, and current package registry. A frozen
identifier such as `phase13-transition-evidence-v1` remains exact data, not a recommended current
name.

## 4. Naming contract

### 4.1 Living vocabulary

Active names MUST describe stable domain meaning rather than when they were implemented.

The following are forbidden in living source, tests, CI job names, ordinary documentation, fixture
names, and generated capability names:

- project phase or subgate numbers;
- temporary ledger identifiers;
- prototype or migration chronology;
- names such as `phase16_checkpoint`, `phase15c_plan`, `P16BMockAdapter`, or
  `test_phase16f_solver_plurality`; and
- user-facing messages such as “Phase 16 fields must be 2D or 3D.”

Names MUST instead identify the exact concept, role, or envelope, for example:

- `LOGICAL_CHECKPOINT_SCHEMA`;
- `capture_logical_checkpoint`;
- `requires_iteration_fingerprint`;
- `CoupledContractVersions`;
- `CartesianFieldMockAdapter`; and
- `test_solver_adapter_contract`.

### 4.2 Domain uses of “phase”

The ban does not apply when phase is the scientific or execution-domain concept, including MCS
phases, observation phases, protocol phases, or a `CoupledPhase`. Such uses MUST be understandable
without reference to the project roadmap.

### 4.3 Type, function, and predicate conventions

- Concrete types and semantic records MUST use nouns.
- Mutating operations MUST use verbs and the Julia `!` convention.
- Predicates SHOULD use `is`, `has`, `supports`, `requires`, or a similarly explicit relation.
- Internal helpers MUST be private and use a leading underscore when their unqualified name could
  be mistaken for supported API.
- Version numbers MUST live in schema values, fingerprints, and codec dispatch, not ordinary
  filenames or current front-door function names.
- The same concept MUST use the same noun across authoring, lowering, runtime, diagnostics,
  documentation, and tests unless a layer distinction is intentional and documented.

### 4.4 Public milestone-coded names

Milestone-coded exported names are observable API and cannot simply be deleted while claiming
strict compatibility. The accepted migration policy is:

1. introduce the domain-oriented name as canonical;
2. retain the historical name in one dedicated compatibility file as a deprecated alias for at
   least the remainder of the unpublished internal-beta cycle;
3. preserve behavior, type identity where applicable, fingerprints, and serialization;
4. exclude compatibility aliases from examples and primary documentation; and
5. remove an alias only through a separately accepted versioned API decision.

Compatibility aliases are spelling compatibility, not new functionality. The qualification ledger
MUST enumerate every allowed export delta; no unrelated export may enter under this exception.

### 4.5 Historical and compatibility isolation

All surviving milestone-coded source identifiers MUST be classified in one of:

- frozen evidence/protocol identity;
- compatibility alias;
- serialized legacy-format identity; or
- defect awaiting removal before closure.

An explicit allowlist MUST name the first three categories. Unclassified occurrences fail
consolidation.

## 5. Target architecture

### 5.1 Layer direction

The consolidated ProcessBigraphs dependency direction MUST be:

```text
primitives
    -> semantic model
    -> canonical structure
    -> execution plan
    -> runtime orchestration
    -> engine protocol
    -> adapter implementation
```

Authoring depends on the semantic model and public protocol, not on runtime internals. Persistence
depends on canonical logical state and declared continuation contracts, not on private solver
caches. Inspection may read every stable layer but MUST NOT become a mutation authority.

The consolidated CorePotts dependency direction MUST be:

```text
logical state
    -> scientific components
    -> algorithms and kernels
    -> coupled execution
    -> ProcessBigraphs adapters and bounded model assemblies
```

A lower layer MUST NOT import or invoke a higher layer for convenience.

### 5.2 File and directory responsibilities

Files and directories MUST be organized by domain responsibility. Exact filenames may be refined
during the current-code audit, but the resulting ownership map MUST distinguish at least:

#### ProcessBigraphs

- primitives: paths, time, schemas, canonicalization, and logical values;
- semantic declarations and author-facing models;
- static and dynamic canonical structure;
- lowering, execution plans, and provenance;
- scheduling, effects, continuations, observations, and runtime transactions;
- engine declarations, invocation protocol, managed engines, and fields;
- checkpoint models, codecs, compatibility, and migrations;
- inspection, diagrams, and serialization; and
- optional package extensions.

#### CorePotts

- logical state, topology, initialization, and lifecycle;
- scientific components and component contracts;
- proposal, acceptance, CPM algorithms, and device kernels;
- fields, continuous dynamics, relationships, observations, and persistence;
- coupled execution and protocol scheduling;
- ProcessBigraphs adapters; and
- bounded Merks and CNV model assemblies.

#### PottsToolkit and MakiePotts

- authoring declarations and lowering;
- public reports and diagnostics;
- visualization requests, encodings, frames, recipes, and explorers; and
- package extensions or backend-specific tests.

The architecture MUST NOT require nested Julia submodules merely to mirror directories. A new
submodule requires a real namespace, dependency, or extension boundary and a documented import
policy.

### 5.3 Responsibility limits

An active production file SHOULD have one dominant responsibility and MUST NOT combine unrelated
declaration, validation, execution, persistence, device, and documentation responsibilities.

An active source file exceeding 1,000 nonblank, noncomment lines requires a waiver that explains
why splitting would make semantic ownership less clear. File length alone MUST NOT motivate
artificial abstraction or indirection.

### 5.4 Include and dependency audit

Each package MUST publish a checked include-order map. The map MUST:

- be acyclic at the responsibility-layer level;
- identify extension boundaries;
- identify compatibility-only files;
- contain no include-order dependency that is absent from the documented layer graph; and
- make the package entry module a concise dependency and export index rather than an
  implementation file.

## 6. DRY and abstraction policy

### 6.1 Duplication classifications

Every nontrivial duplicate block MUST be classified as:

- accidental production duplication;
- deliberate independent oracle;
- backend-specific kernel realization;
- compatibility implementation;
- generated code;
- bounded model-specific scientific specialization; or
- false positive caused by conventional boilerplate.

Accidental production duplication MUST be eliminated. All permitted duplication MUST be recorded
with its independence or specialization rationale.

### 6.2 Extraction rule

A helper or abstraction SHOULD be introduced when it:

- gives one stable concept one implementation;
- centralizes an invariant that would otherwise drift;
- supports at least three genuine consumers; or
- preserves an important two-consumer boundary such as codec validation or transaction failure.

An abstraction MUST NOT be introduced solely to reduce line count, make two syntactically similar
but semantically different operations share a name, or anticipate unrequested future backends.

### 6.3 Canonical mechanisms

The consolidation MUST specifically audit and converge:

- all semantic/canonical/runtime fingerprint builders;
- canonical byte encoding and integrity hashing;
- validation report and error construction;
- engine staging, completion, validation, publication, and discard;
- field boundary, sampling, deposition, exchange, and accounting validation;
- checkpoint envelope validation and legacy conversion;
- structural request validation, conflict selection, and publication;
- authoring handle and origin-map resolution;
- CorePotts host/portable process dispatch;
- model fixture construction; and
- repeated CI/spec integrity helper code.

### 6.4 Independent evidence exception

DRY does not override evidence independence.

The following MUST NOT share decisive implementation logic with the production path they validate:

- the checked ProcessBigraph specification oracle;
- analytic or manufactured numerical oracles;
- the independent custom solver adapter;
- production-versus-reference transition comparisons;
- CPU-versus-device qualification where independent realization is part of the claim; and
- source-audit comparators.

Shared literal parsing, test reporting, or neutral fixture data is permitted only when it cannot
make both sides produce the same wrong answer.

## 7. Test consolidation

### 7.1 Domain organization

Active tests MUST be organized by contract domain rather than project phase. At minimum,
ProcessBigraphs tests MUST distinguish:

- primitives and canonical values;
- schemas and stores;
- authoring and validation;
- static composition and algebraic laws;
- dynamic structural transactions;
- scheduling and runtime transactions;
- observations and continuations;
- engine protocol and field operations;
- SciML and independent adapter conformance;
- checkpoint and migration behavior;
- bounded Merks and CNV assemblies; and
- independent specification oracle.

CorePotts tests MUST distinguish state, topology, initialization, scientific components,
algorithms, coupled execution, fields, relationships, persistence, ProcessBigraphs adapters,
bounded models, and backend/device qualification.

Root and integration tests MUST distinguish package-local API tests from actual package-boundary
and evidence-archive tests.

### 7.2 Fixture ownership

Each reusable scenario MUST have one fixture authority at the lowest appropriate test layer.
Fixture helpers MUST describe their scientific or contract purpose, not the phase that introduced
them.

Production packages MUST NOT acquire test-only constructors, mock adapters, or expected-value
tables to make tests DRY.

### 7.3 Contract suites

Where multiple implementations claim one protocol, tests SHOULD define one contract suite and run
it against each implementation. Candidate examples include:

- engine adapters;
- field operations;
- continuation codecs;
- checkpoint stores;
- CPU and qualified device execution;
- authoring and direct canonical construction equivalence; and
- current and legacy checkpoint decoding.

Implementation-specific tests remain REQUIRED for specialized failure behavior, backend
constraints, and numerical evidence.

### 7.4 Coverage preservation

Consolidation may change test-file count and assertion count. It MUST NOT reduce the accepted
behavioral coverage matrix.

Before deleting, merging, or replacing a test, the implementation MUST map its covered:

- semantic requirement;
- happy path;
- negative path;
- failure stage;
- restart cut;
- backend envelope;
- replay class;
- oracle;
- model claim; and
- evidence consumer.

The post-consolidation matrix MUST show every baseline obligation mapped to a surviving test or
immutable historical artifact.

### 7.5 Test quality

Tests MUST:

- assert behavior and stable diagnostics rather than private line-by-line implementation shape;
- avoid unexplained global mutable setup;
- use deterministic seeds and semantic identities;
- minimize compilation duplication through shared neutral fixtures where independence permits;
- keep package tests executable independently;
- keep integration shards semantically meaningful; and
- retain Aqua, clean-install, documentation, serialization, performance, and restart coverage.

## 8. Quality tooling and CI

### 8.1 Stable current-state checker

The active ProcessBigraph quality stack MUST converge from phase-specific lifecycle scripts into a
small stable current-state checker system.

The recommended living responsibilities are:

- architecture and package boundaries;
- current semantic/API contracts;
- evidence and historical-artifact integrity;
- documentation and generated pages;
- performance budgets; and
- one root runner used by CI.

There may be at most six active ProcessBigraph quality entrypoints, with one ordinary CI
entrypoint.

### 8.2 Declarative validation

Current-state names, export inventories, dependency rules, supported envelopes, evidence paths,
compatibility exceptions, and qualification rows SHOULD be data in versioned registries rather
than repeated string tests across scripts.

Checker code MUST provide reusable typed or structured operations for:

- required files;
- SHA-256 and Git identity;
- TOML schema validation;
- allowed state vocabularies;
- export and dependency inventories;
- artifact/reference integrity;
- documentation phrases or generated-page equality;
- allowed historical-name occurrences; and
- actionable aggregated diagnostics.

### 8.3 Historical checker disposition

Historical phase checkers MAY be retained in an archive when needed to reproduce an attestation.
They MUST NOT:

- remain active CI authorities for current source through accumulating lifecycle branches;
- be imported by production packages;
- govern future status transitions;
- force current files to preserve obsolete organization; or
- be silently deleted when an evidence manifest claims them by hash.

The archive index MUST distinguish executable reproduction tools from immutable source records.

### 8.4 CI names and gates

Living CI names MUST describe durable obligations, not roadmap stages. The final gate set MUST
include:

- project integrity;
- independent packages;
- cross-package integration;
- independent scientific or specification oracle;
- documentation and examples;
- performance and allocation budgets;
- CPU architecture matrix;
- applicable real-device qualification;
- exact-head evidence; and
- one required aggregate.

The consolidation MUST NOT reduce platform coverage or turn a previously mandatory job optional.

## 9. API, identity, and persistence compatibility

### 9.1 Public API inventory

Before implementation, each package MUST record:

- exported names;
- public qualified-only names used by tests, examples, or sibling packages;
- signatures and return-type families for stable operations;
- extension-owned methods;
- documented constructors and defaults;
- error types and stable diagnostic codes; and
- compatibility-only names.

The final inventory MUST differ only by explicitly accepted naming aliases or renames. A new
capability, constructor family, backend claim, or semantic option is forbidden.

### 9.2 Layered identity

Equivalent inputs before and after consolidation MUST preserve every identity whose contract does
not explicitly depend on private source spelling, including:

- semantic model fingerprints;
- canonical-structure fingerprints;
- declaration and adapter fingerprints;
- execution-plan fingerprints;
- problem fingerprints;
- structural epoch and lineage identities;
- observation and continuation fingerprints;
- runtime fingerprints;
- checkpoint fingerprints; and
- evidence and source identities that claim exact preservation.

If a private internal name currently leaks into a semantic identity, the implementation MUST
either preserve its encoded value through a stable identity constant or obtain a separate accepted
versioned migration decision. It may not silently change.

### 9.3 Checkpoint compatibility

The consolidation MUST retain:

- byte-identical encoding for the current canonical checkpoint formats unless a separate versioned
  format decision is accepted;
- decoding and validation of every retained supported legacy format;
- exact restoration for exact-replay envelopes;
- declared numerical or statistical behavior for weaker replay classes;
- non-destructive CorePotts-to-ProcessBigraph conversion; and
- the distinction between logical state, typed continuation, reconstructible cache, diagnostic
  state, and unsupported opaque state.

Legacy format code MUST be isolated from the current front door but remain testable.

### 9.4 Errors and diagnostics

Stable error types and diagnostic codes MUST remain. User-facing text SHOULD be rewritten to remove
development chronology, provided tests and documentation bind to stable codes and the new text is
more domain-specific.

Changing a stable code, failure stage, exception type, or atomicity boundary is a semantic change
and is forbidden here.

## 10. Migration order

The consolidation MUST proceed through independently reviewable passes in the following order.
These are named gates, not future product phases.

### 10.1 Baseline freeze

Produce:

- exact-head source and environment identity;
- public and qualified-name inventories;
- behavioral coverage matrix;
- fingerprint and serialization fixtures;
- package dependency graph;
- active include graph;
- duplicate-code classification;
- performance/allocation baseline; and
- source-impact map for real-device evidence.

No implementation movement may precede this gate.

Qualification record: this gate is qualified by
[`semantic-preserving-consolidation-baseline-freeze.md`](../design/audits/semantic-preserving-consolidation-baseline-freeze.md)
and the exact
[`baseline-freeze-v1.toml`](../design/evidence/consolidation-baseline/baseline-freeze-v1.toml)
attestation. The production baseline remains commit
`d2f4d40e78fb68ee20da483d9784b55d25bf6147`; no production consolidation occurred while
qualifying the gate.

### 10.2 Naming and archive boundary

Establish:

- canonical domain vocabulary;
- old-to-new naming map;
- compatibility-alias policy;
- historical evidence index;
- legacy protocol-name allowlist; and
- rules that distinguish runtime `phase` concepts from project milestones.

Rename active test and tooling organization before changing scientific implementation.

### 10.3 Test and quality harness

Create the domain-organized test hierarchy, shared neutral fixtures, contract suites, coverage
matrix, current-state checker library, and stable CI names.

At the end of this gate, old and new test organization MUST exercise the same implementation and
produce equivalent results. Historical checkers may be retired from active CI only after their
current obligations are represented by the new checker and immutable evidence verification.

### 10.4 ProcessBigraphs structure

Consolidate ProcessBigraphs in this dependency order:

1. primitives and canonical logical values;
2. semantic declarations and canonical structure;
3. lowering, compilation, identity, and provenance;
4. scheduling, runtime transactions, observations, and continuations;
5. engine and field protocol implementation;
6. persistence and legacy codecs; and
7. authoring, inspection, and documentation.

Each pull request or commit group MUST be either a structure-only move or a named deduplication
with an equivalence proof. Broad simultaneous rewrites are forbidden.

### 10.5 CorePotts and adapters

Consolidate CorePotts after the ProcessBigraphs protocol boundaries are stable:

1. logical state and persistence;
2. components and scientific contracts;
3. algorithms and backend kernels;
4. dynamic state, continuous fields, and relationships;
5. coupled execution;
6. ProcessBigraphs adapters; and
7. bounded Merks and CNV assemblies.

PottsToolkit and MakiePotts follow their lowest changed dependency. No package may maintain a
second compatibility implementation after its consumers migrate.

### 10.6 Reconciliation and requalification

The final gate MUST:

- run all independent package and integration suites;
- rerun semantic, numerical, restart, failure, and persistence matrices;
- compare baseline and consolidated fingerprints, bytes, traces, and model observations;
- rerun authoring and runtime performance budgets;
- rerun trusted hardware qualification for every exact-source evidence claim whose source or
  transitive qualified implementation changed;
- rebuild documentation and examples;
- produce an exact-head consolidation evidence manifest; and
- attest the complete functional-delta inventory.

Roadmap redesign may begin only after this gate closes.

## 11. Hardware and performance evidence

### 11.1 Source-addressed hardware evidence

Moving, splitting, or editing source covered by exact-source CPU, Metal, or ROCm evidence
invalidates that source identity even when behavior is intended to remain equal.

The baseline freeze MUST compute an impact map from changed files to qualified hardware claims.
Every invalidated claim MUST be rerun on the applicable trusted hardware at the final exact head.
An assertion that a change was “only refactoring” is not hardware evidence.

### 11.2 Performance preservation

The consolidation MUST preserve all existing frozen performance and allocation budgets. It MUST
also report:

- package load and precompile time;
- authoring construction, validation, lowering, compilation, initialization, and warm execution;
- runtime steady-state time and allocations;
- field/CPM publication allocation;
- device warm allocation and hidden transfer checks; and
- test-suite wall time by domain.

A performance improvement is acceptable when it follows mechanically from removed duplication or
indirection and changes no algorithm or semantics. It MUST NOT be promoted as new functional scope.
A regression requires repair or an explicitly accepted budget decision outside this contract.

## 12. Documentation and claim reconciliation

Living documentation MUST describe:

- the domain architecture;
- authoring, lowering, execution, adapter, and persistence boundaries;
- the current public and compatibility APIs;
- supported backends and envelopes;
- bounded Merks and CNV claims;
- known limitations; and
- the distinction between historical evidence and current contracts.

Primary docs MUST NOT teach project phases. Historical audits MAY explain them.

Generated capability pages MUST derive from current domain registries. The roadmap MUST describe
consolidation by named gates rather than creating another numbered implementation phase.

No documentation change may broaden claims beyond the qualified baseline.

## 13. Qualification and evidence

### 13.1 Ledger

Every required row in
[`semantic-preserving-consolidation-qualification-v1.toml`](semantic-preserving-consolidation-qualification-v1.toml)
MUST be `qualified` before closure.

Passing package tests alone is insufficient. Closure requires structural, behavioral, identity,
persistence, performance, documentation, platform, and evidence proof.

### 13.2 Exact-head protocol

Final qualification MUST record:

- exact commit and tree;
- base and merge-base identity;
- dependency-resolution inputs;
- clean-tree status;
- public and compatibility API deltas;
- source and test inventory deltas;
- behavioral coverage reconciliation;
- fingerprint, serialization, trace, and model comparisons;
- performance reports;
- CPU and applicable hardware runs;
- all CI job identifiers and conclusions;
- remaining compatibility aliases and their disposition; and
- explicit confirmation that no new feature or claim entered.

### 13.3 Closure states

Allowed implementation states are:

- `draft_contract`;
- `accepted_not_started`;
- `baseline_frozen`;
- `naming_and_archive_qualified`;
- `test_and_quality_harness_qualified`;
- `process_bigraphs_qualified`;
- `core_and_frontends_qualified`;
- `reconciliation_candidate`; and
- `consolidation_qualified`.

No intermediate state is a public release or a new scientific qualification.

The planned final ProcessBigraphs attestation version is `0.5.1`. Canonical domain names plus
retained compatibility aliases are backward-compatible additions within the Julia package
manager's nonzero pre-1.0 minor-version convention. If any required naming migration cannot
preserve the `0.5.0` public behavior, type identity, fingerprint, or serialization contract,
implementation MUST stop and obtain a separate breaking-change decision before targeting `0.6.0`.

## 14. Explicit exclusions

The consolidation MUST NOT implement or newly qualify:

- broad AlgebraicDynamics integration;
- arbitrary ODE, DAE, biochemical, FBA, or SBML ecosystems;
- Dagger or distributed execution;
- CUDA;
- multi-GPU execution;
- universal solver or callback support;
- new lattice geometries;
- new scientific mechanisms or published models;
- full Merks or CNV publication analyses;
- whole-cell-style acceptance;
- a new macro DSL;
- new automatic wiring or implicit scheduling;
- a new checkpoint format;
- a new numerical algorithm or default;
- a public ProcessBigraphs release; or
- any redesigned future roadmap phase.

Discoveries may be recorded for later roadmap design but MUST NOT be implemented under this
contract.

## 15. Accepted owner decisions

The project owner accepted all ten interview recommendations:

1. consolidation is repository-wide and proceeds dependency-first;
2. living API uses canonical domain names while historical exported names remain compatibility
   aliases for the unpublished internal-beta cycle;
3. frozen phase-named evidence and protocol identities remain immutable and indexed;
4. at most six active ProcessBigraph quality entrypoints remain, with one ordinary CI runner;
5. 1,000 nonblank, noncomment lines triggers responsibility review rather than mechanical
   splitting;
6. independent oracles, adapters, reference implementations, and qualified backend kernels remain
   separate where shared decisive logic would weaken evidence;
7. every invalidated exact-source CPU, Metal, or ROCm claim is rerun;
8. only enumerated spelling compatibility may alter the API inventory, with no functional
   addition or removal;
9. successful backward-compatible consolidation targets ProcessBigraphs `0.5.1`, while any
   unavoidable incompatibility stops work for a separate `0.6.0` decision; and
10. later-roadmap redesign begins only after exact-head consolidation qualification.

The complete rationale and answers are recorded in
`design/audits/semantic-preserving-consolidation-owner-interview.md`.

## 16. Exit condition

Consolidation is complete only when:

1. every qualification row is `qualified`;
2. the living source, tests, CI, and documentation use domain-oriented names;
3. every remaining milestone-coded occurrence is allowlisted historical or compatibility data;
4. each accepted concept has one production authority;
5. all baseline behavior, identity, persistence, failure, model, backend, and performance
   obligations are reconciled;
6. applicable trusted hardware evidence is exact-head;
7. final CI is green on a clean exact head;
8. ProcessBigraphs remains unpublished and its claim boundary is unchanged; and
9. a closure audit demonstrates zero unapproved functional delta.

Only then may the project redesign the remaining roadmap from the consolidated codebase.
