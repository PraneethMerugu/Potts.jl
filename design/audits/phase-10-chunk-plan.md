# Phase 10 PottsToolkit Typed API and Compiler Chunk Plan

Status: Complete execution record

Date: 2026-07-20

Inputs:

- [Decision 0026](../../spec/decisions/0026-phase-10-typed-api-and-compiler.md)
- [Current-code and gap audit](phase-10-current-code-and-gap-audit.md)
- [Replacement-slice evidence](phase-10-replacement-slice-evidence.md)
- [Refactor roadmap](../refactor-roadmap.md)

## Completion Rule

Phase 10 is complete only when the replacement Level 2 API is PottsToolkit's sole semantic path,
all required public components and the five reference workloads are expressible and executable,
CorePotts lowering uses only public dispatch, CPU/Metal/ROCm gates pass, legacy is deleted, and
performance is preserved or improved.

Passing a vertical slice is the legacy-deletion trigger, not Phase 10 completion.

## Implementation Checkpoint — 2026-07-20

- Chunks 10.0–10.7 are complete under the [completion audit](phase-10-completion-audit.md).
- PottsToolkit's historical compiler, macros, event kernels, blanket CorePotts re-export, and
  obsolete runtime dependencies are deleted; the hard containment gate passes.
- The Level 2 implementation covers immutable identities, bindings, laws, properties, fragments,
  lifecycle rules, reports, fingerprints, public lowering, typed layouts, all required component
  families, direct downstream CorePotts components, and one CorePotts/SciML problem.
- PottsToolkit passes 129 tests. CorePotts passes 2,983 tests plus one intentional broken research
  case. Integration, package, CPU, Metal, ROCm, documentation, and integrity CI passed for the
  schema `2.0.0` implementation/evidence head `a75e376`.
- All five required reference families have public constructors, stable smoke fixtures,
  paper-scalable configurations, literature scope, parameter interpretation, invariants, and
  declared ensemble observables.
- Benchmark schema `2.0.0` now persists all eight reference configurations, actual proposal
  accounting, MCS/s, resident memory, allocations, launches, transfers, observation boundaries,
  checkpoint cost, provenance, and the matched direct-Core comparison. CPU, real Metal, and real
  ROCm pass authoritative CI; both GPU artifacts were downloaded and independently validated.

## Chunk 10.0 — Contract Baseline, Audit, and Freeze

Deliverables:

- accept Decision 0026 and update authoritative specifications;
- capture the current source/test/dependency/caller inventory;
- record the Julia 1.12.6 270-test baseline;
- retain the existing SHA/signature containment gate over all historical source and consumers;
- forbid new production references to legacy names outside its manifest;
- create this requirement-to-chunk ledger.

Exit gate:

- new replacement files can be added without changing frozen historical files;
- every accepted Phase 10 deliverable has an owning chunk;
- no existing caller is assumed to be final merely because it passes.

## Chunk 10.1 — Public CorePotts Lowering Seams

Deliverables:

- define public proposal-evaluation dispatch for energy, drive, constraint, modifier, and mechanical
  components, replacing built-in-specific private fold hooks as the extension boundary;
- define stable component semantic/fingerprint metadata and capability reporting;
- ensure `ScientificComponentSet` accepts downstream public extensions by ordinary Julia methods;
- add an external test module defining a miniature energy and proving host reference, CPU, Metal,
  and ROCm compilation/execution without editing a central component switch;
- expose any required public lifecycle/property-effect lowering seam; no PottsToolkit kernel may be
  introduced.

Exit gate:

- the external component uses only exported/public CorePotts methods;
- unknown effects fail preflight;
- built-ins and the external component share the same hot fold with concrete inference;
- existing Phase 6–9 CPU and backend conformance remains green.

## Chunk 10.2 — Immutable Level 2 Semantic Values

Deliverables:

- implement namespace-capable `CellType`, `Medium`, property declarations, typed bindings,
  `PairwiseLaw`, component values, fragments, phases, and `PottsToolkit.PottsModel`;
- implement one explicit real-number policy with visible `Float32` default and no hidden narrowing;
- implement persistent `add`, `remove`, `replace`, compose, and `remake` operations;
- enforce order-independent identity, duplicate rejection, explicit missing/default behavior, and
  explicit merges;
- accept direct conforming Level 3 CorePotts components without registration;
- keep model size and identities out of unbounded top-level type parameters.

Exit gate:

- constructors and composition are immutable and type-stable;
- no semantic field is `Any`, dictionary-backed, order-prioritized, or Unitful;
- equivalent declaration orders normalize equally;
- downstream components compose without PottsToolkit source edits.

## Chunk 10.3 — Normalization, Validation, Provenance, and Reports

Deliverables:

- implement one typed immutable normalized model;
- implement local, normalization, problem, and backend validation stages with structured errors;
- derive requirements, effects, dependency order, conflicts, schedules, and simultaneous property
  transactions;
- preserve namespaces, fragments, source locations, defaults, replacements, and lowering paths;
- implement `validate`, `normalize`, `explain`, dependency/provenance/backend reports, compact and
  `text/plain` display;
- implement semantic and execution fingerprints with canonical stable contributions and correct
  invalidation;
- distinguish semantic manifests, checkpoints, and opt-in reconstructable serialization.

Exit gate:

- invalid models fail before CorePotts problem construction or backend launch;
- source and declaration order do not affect semantic identity;
- conveniences expose their entire expansion;
- inspection performs no compilation or backend allocation.

## Chunk 10.4 — Qualified Replacement Vertical Slice

The slice deliberately crosses every architectural boundary before broad migration.

Deliverables:

- `PottsToolkit.PottsModel` with one medium and at least one finite cell type;
- deterministic 2D and 3D domain/layout lowering through public initialization claims;
- one quadratic volume constraint and one pairwise adhesion law;
- one first-class fluctuating-volume mechanical/HST component;
- one typed stochastic property transaction and one lifecycle operation;
- public lowering to `CorePotts.PottsModel` and the single Phase 9 `PottsProblem`;
- host reference evaluation and CPU, Metal, and ROCm execution;
- complete reports, fingerprints, RNG identity, and problem `remake` behavior;
- compile-time, allocation, memory, warm-MCS, transfer, synchronization, and launch measurements.

Exit gate:

- reference and optimized results satisfy exact/numerical/statistical contracts;
- warm GPU MCS stays resident with no scalar indexing, hidden transfer, host fallback, device
  allocation, or additional synchronization;
- steady-state performance is not materially worse than the matched Phase 9 direct-engine path;
- every CorePotts interaction is public.

## Legacy-Deletion Gate

Immediately after Chunk 10.4 passes:

1. migrate all root library callers and package/integration tests through the capability ledger;
2. remove frozen entries as their consumers disappear;
3. delete `PottsSystem`, historical components/layout context, `compile_component`, legacy events,
   `reference_integrator`, the MLStyle macro path, and the temporary engine re-export surface;
4. remove MLStyle, Reexport, KernelAbstractions, Adapt, Random, and any other root dependency no
   longer justified;
5. run package, integration, project-integrity, and legacy-containment gates;
6. prove that no production source or root test references `Legacy*`, old penalties/samplers,
   private CorePotts names, or deleted PottsToolkit modules.

No compatibility aliases or parallel compiler survive this gate.

## Chunk 10.5 — Required Component and Rule Coverage

Deliverables:

- ordinary and fluctuating/HST volume and boundary components;
- unordered pairwise contact/adhesion;
- prescribed fields and chemotaxis modes;
- connectivity and focal-point components where applicable;
- typed property rules, schedules, growth, division, transition, shrink death, and immediate death;
- 2D/3D declarations and backend capabilities for every first-party component;
- a new scientific elongation/major-axis family sufficient for the angiogenesis workload, built
  from public moment and auxiliary-state protocols rather than the quarantined HST length penalty;
- direct Level 3 component composition and explicit non-portable reporting where applicable.

Exit gate:

- each component has constructor, validation, reference, lowering, lifecycle, report, fingerprint,
  CPU, Metal, and ROCm evidence;
- unsupported dimension/backend combinations fail preflight;
- no component introduces a central concrete-type compiler switch.

## Chunk 10.6 — Five Reference Workloads

Implement as ordinary reusable Level 2 compositions with no runtime special case:

1. single-cell persistent or biased migration;
2. chemotaxis in fixed linear, half-normal, and exponential gradients;
3. monolayer growth from one cell with growth, division, and repulsion;
4. two-population differential-adhesion sorting;
5. elongation-driven angiogenesis.

Deliverables:

- public constructors returning Level 2 models/problems;
- fixed small conformance fixtures and paper-scalable configurations;
- literature/source provenance and parameter interpretation;
- reference invariants and statistical observables;
- CPU, Metal, and ROCm compilation and runnable smoke evidence.

This is OpenVT reference-model coverage only. External schema compatibility is excluded.

Exit gate:

- every workload normalizes, reports, fingerprints, lowers, initializes, and executes through only
  public replacement APIs;
- model-specific code contains no engine branch or private storage access.

## Chunk 10.7 — API, Benchmark, and Completion Qualification

Deliverables:

- curated exports and removal of blanket CorePotts re-export;
- Julia-style names, constructors, displays, diagnostics, and executable component documentation;
- benchmark lanes separating construction, normalization, lowering, compilation, and warm MCS;
- MCS/s, proposals/s, allocation, memory, transfer, synchronization, observation, and checkpoint
  evidence on CPU, Metal, and ROCm; retain explicit compiler-resource status and never fabricate a
  portable register count where KernelAbstractions exposes none;
- root package and cross-package conformance, ambiguity, inference, stale-dependency, project
  integrity, legacy absence, and documentation API checks;
- Phase 10 completion audit mapping every Decision 0026 and roadmap requirement to direct evidence.

Backend-native register, spill, occupancy, and native-code-size capture remains mandatory in Phase
12 after the target devices and budgets are frozen. Phase 10 requires successful real-device
compilation, rejection of dynamic device invocation, zero warm device allocation, and an explicit
machine-readable statement of the quantitative profiler boundary.

Exit gate:

- all required evidence is green at the same commit;
- no released package source contains a duplicate PottsToolkit semantic/compiler path;
- Phase 11 can add only syntax and solution post-processing over the complete Level 2 foundation.

## Capability Ledger

| Capability | Historical owner | Replacement owner | Chunk |
| --- | --- | --- | --- |
| Cell/medium names | `CellType(is_background)` | typed `CellType` and `Medium` | 10.2 |
| Model composition | `PottsSystem` | immutable `PottsModel` and fragments | 10.2–10.3 |
| Volume/contact | component dictionaries and `compile_component` | typed components and public CorePotts lowering | 10.4 |
| HST volume/surface | legacy penalties | scientific mechanical components | 10.4–10.5 |
| Surface/chemotaxis/focal/connectivity | legacy wrappers or direct penalties | scientific Level 2 components/direct Level 3 composition | 10.5 |
| Elongation | quarantined `HSTLengthPenalty` | new scientific moment/auxiliary component | 10.5 |
| Initial layouts | mutable `LayoutContext` | public initialization claims | 10.4 |
| Property schema | `Dict{Symbol,Any}` merge | typed CorePotts `PropertySchema` expansion | 10.2–10.4 |
| Rules | MLStyle closure rewrite | typed Level 2 rule/effect values | 10.3–10.5 |
| Events | private PottsToolkit kernels | public lifecycle protocols | 10.4–10.5 |
| RNG | task RNG and numeric offsets | semantic RNG identity | 10.3–10.6 |
| Problem | `LegacyPottsProblem` bridge | one CorePotts/SciML `PottsProblem` | 10.4 |
| Extension | central method plus `isa` | ordinary public dispatch | 10.1–10.2 |
| Reports/fingerprints | absent or engine-only | normalized semantic and execution reports | 10.3 |
| Reference examples | legacy `TestProblems` | five public Level 2 workloads | 10.6 |
| GPU execution | legacy private kernels | CorePotts qualified execution only | 10.1, 10.4–10.7 |

## Required Validation Commands

Commands are refined as files land, but Phase 10 cannot close without:

- Julia 1.12.6 root package tests;
- CorePotts package tests;
- integration conformance shards;
- legacy containment and project integrity scripts;
- CPU x86_64 and ARM64 lanes;
- real Metal and ROCm device lanes with scalar indexing disabled;
- matched direct-CorePotts versus Level 2 structural/performance counters;
- documentation API and executable-example checks;
- a clean worktree and authoritative CI at the completion commit.
