# Phase 14 Focused Semantic-Architecture Interview

Status: Complete; all 15 owner decisions accepted

Date: 2026-07-24

This interview follows the
[semantic-architecture simplification audit](phase-14-semantics-simplification-audit.md). It asks
only questions that require an owner preference. Technical non-regression obligations—Phase 13
stability, deterministic semantics, continuation, preflight, and honest qualification—are not
optional answers.

Implementation remains paused until these decisions are answered and recorded in the Phase 14
specifications and contract registry.

Reply with selections such as `1A, 2A, 3A, 4A, 5A`. You may also answer `A for all` within a round.
Option A is the audit recommendation in every question.

## Accepted owner answers

On 2026-07-24, the project owner selected A for Questions 1--5:

- hybrid biological façades over one inspectable semantic kernel;
- consolidation to seven stable semantic areas;
- one exact global clock with process-local solver steps;
- one ordered plan underlying positional, staged, event, and multirate authoring; and
- one owner-parameterized state contract with specialized storage implementations.

On 2026-07-24, the project owner selected A for Questions 6--10:

- one process protocol with explicit biological and numerical law families;
- `ContinuousSystem` as an authoring façade over the shared kernel, never a second runtime;
- events as triggered processes, delays as history policies, and mappings as process laws;
- lifecycle requests applied through one deterministic commit boundary; and
- evidence-gated experimental status for advanced adaptive, root, DAE, SDE, reaction, and jump
  families.

On 2026-07-24, the project owner selected A for Questions 11--15:

- ModelingToolkit and future integrations as optional outer adapters over the shared kernel;
- persistence, preflight, compatibility reports, and related evidence as derived public tooling;
- clean replacement of provisional Phase 14 spellings while preserving every Phase 13 contract;
- proving slices in the order Wortel, Wang, then one field-coupled model; and
- resuming broad implementation only after the revised registry, canonical IR, six model sketches,
  golden tests, and complete Wortel slice are accepted.

## Round 1: Architectural center

### 1. Public architecture

- **A — Hybrid façades over one kernel (recommended).** Biological declarations lower to one
  inspectable state/process/plan IR.
- **B — Minimal kernel only.** Users author generic state, process, and plan values directly.
- **C — Domain systems.** Site, cell, field, relationship, event, and continuous systems remain
  independent public semantic authorities.

### 2. Contract consolidation

- **A — Consolidate to seven stable semantic areas (recommended).** State, process, plan,
  lifecycle, observation, spatial roles, and Potts algorithms; persistence/adapters/evidence are
  derived tooling.
- **B — Moderate consolidation.** Keep separate field, relationship, event, and continuous-system
  contracts but unify clocks and schedules.
- **C — Preserve the current 24-contract registry.** Simplify only names and documentation.

### 3. Time model

- **A — One exact global clock (recommended).** One MCS-duration mapping; solver steps and
  subcycles belong to processes.
- **B — Global clock plus separate continuous-system clocks.** Explicit synchronization connects
  them.
- **C — Keep the current continuous, global, system, and convenience clock values as public
  contracts.**

### 4. Schedule model

- **A — One ordered plan (recommended).** Positional MCS phases, stages, cadence, events, and
  multirate entries are façades over one plan.
- **B — Separate simple-MCS and multirate plan types with a shared protocol.**
- **C — Keep `MCSPlan`, `StagedProtocol`, and `MultirateSchedule` as separate schedulers.**

### 5. State model

- **A — One owner-parameterized semantic state contract (recommended).** Site, cell, field,
  membrane, global, relationship, history, and delay storage may be specialized implementations.
- **B — One property contract plus separate field, relationship, history, and delay contracts.**
- **C — Preserve the current domain-specific state contracts as independent semantics.**

## Round 2: Dynamics and coupling

### 6. Process model

- **A — One process protocol with explicit law families (recommended).** Accepted-copy, site,
  cell, field, exchange, relationship, rule, mapping, and event behaviors share read/write,
  snapshot, trigger, and atomicity metadata.
- **B — A common protocol but separate public execution subsystems per domain.**
- **C — Keep each current dynamics contract independent.**

### 7. Continuous-system API

- **A — Authoring façade over the common kernel (recommended).** Equation-style systems lower to
  state/process/plan and never create a second runtime.
- **B — Separate continuous runtime synchronized to Potts through a coupling layer.**
- **C — Remove the equation-style API and support only hand-authored process laws.**

### 8. Events, delays, and mappings

- **A — Process/state policies (recommended).** Events are triggered processes, delays are history
  reads, and mappings are explicit process laws; only ambiguous cross-domain references are public.
- **B — Keep events as a separate subsystem; merge only delays and mappings.**
- **C — Keep all three as independent top-level semantic systems.**

### 9. Lifecycle coupling

- **A — Requests plus one commit boundary (recommended).** Processes request lifecycle effects;
  the plan applies them through one lifecycle contract.
- **B — Lifecycle is an ordinary process family with no privileged kernel concept.**
- **C — Preserve lifecycle events, requests, scheduled lifecycle, and timed lifecycle as separate
  public concepts.**

### 10. Advanced continuous families

- **A — Evidence-gated experimental scope (recommended).** Stabilize only source-backed ODE, rule,
  mapping, sampled-event, delay, and field needs; keep adaptive/root/DAE/SDE/reaction/jump families
  experimental until proven.
- **B — Stabilize the full current family now to target broad Morpheus/SBML parity.**
- **C — Remove all advanced-family extension points until after the six models ship.**

## Round 3: Boundaries, migration, and restart gate

### 11. ModelingToolkit and external adapters

- **A — Optional outer adapters (recommended).** ModelingToolkit lowers into the kernel; future
  Morpheus, SBML, or Mermaid.jl adapters use the same boundary and do not shape Core execution.
- **B — ModelingToolkit types become first-class Core semantic values.**
- **C — Defer all adapter interfaces, including ModelingToolkit, until after the paper release.**

### 12. Persistence, preflight, and compatibility reports

- **A — Derived public tooling (recommended).** Users can inspect the reports, but ordinary model
  declarations never author parallel checkpoint/backend/compatibility descriptions.
- **B — Derived by default with public manual override hooks.**
- **C — Preserve independent author-authored contracts for maximum explicitness.**

### 13. Provisional API compatibility

- **A — Clean replacement is allowed (recommended).** Preserve all Phase 13 contracts and
  scientific traces, but make no compatibility promise for uncommitted provisional Phase 14
  spellings.
- **B — Provide one deprecation cycle for every current provisional Phase 14 public value.**
- **C — Treat the current provisional Phase 14 surface as compatibility-frozen.**

### 14. First proving slices

- **A — Wortel, then Wang, then one field model (recommended).** This grows from transaction/site
  semantics to multirate coupling and finally PDE/splitting complexity.
- **B — Implement a generic Morpheus compatibility suite before any paper slice.**
- **C — Build all capability families breadth-first, then assemble models.**

### 15. Gate for resuming broad implementation

- **A — Architecture and vertical-slice gate (recommended).** Resume only after the revised
  registry, canonical IR sketch, lowering examples for all six models, golden tests, and a complete
  Wortel slice are accepted.
- **B — Resume after revised specifications and unit tests; full vertical slices can follow.**
- **C — Resume immediately and simplify incrementally during implementation.**

## What happens after the answers

All answers are accepted. They must next be recorded in a new architecture decision. The Phase 14
specifications, registry, work items, and roadmap must then be revised as one coherent change. Only
after the resulting contract checker and golden fixtures pass should Phase 14.1 implementation
resume.

Post-interview refinement: Decision 0032 preserves the selected Wortel → Wang → field order but
requires each stable slice to close on CPU, Metal, and ROCm before the next slice opens. The
completed Wortel CPU reference therefore does not by itself open Wang.
