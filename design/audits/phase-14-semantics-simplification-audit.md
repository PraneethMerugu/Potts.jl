# Phase 14 Semantic-Architecture Simplification Audit

Status: Complete; focused owner interview unanimously accepted; no normative specification changed

Date: 2026-07-24

## Executive verdict

The concern that the Phase 14 semantic system is over-engineered is justified.

The scientific scope is not itself excessive. The six selected models genuinely require dynamic
site state, evolving fields, cell state, histories, relationships, lifecycle changes, staged
execution, observations, and explicit source timing. The problem is representational: the
provisional design promotes too many closely related implementation concepts to independent public
contracts.

The current registry contains:

- 24 provisional contracts in 12 families;
- 93 distinct named public values;
- 20 capability rows for six selected models; and
- several concepts represented independently in execution, authoring, persistence, compatibility,
  and backend-reporting layers.

Those numbers are not proof by themselves. The decisive evidence is that time, scheduling, state,
processes, lifecycle, events, and symbol identity each have two or more authoritative
representations. A feature currently tends to require coordinated changes across CorePotts
declarations, execution, authoring aliases, normalization, lowering, persistence, preflight,
compatibility reporting, and tests. That is a structural multiplication of concepts.

The recommended correction is a hybrid architecture:

1. a small internal semantic kernel with `State`, `Process`, `Plan`, `Lifecycle`, and
   `Observation`;
2. biological authoring declarations such as activity, field dynamics, and cell dynamics retained
   as ergonomic façades that lower into that kernel;
3. persistence, backend preflight, fingerprints, and compatibility evidence derived from the same
   kernel rather than separately authored; and
4. advanced continuous-system families retained as experimental extensions until a selected model
   proves that they belong in the stable Phase 14 surface.

This is a simplification of representation, not a reduction in scientific ambition. It preserves
the path to Morpheus-level semantic coverage while making later adapters—including a possible
Mermaid.jl adapter—consumers of one model IR rather than influences on the present public API.

## Scope and evidence

This audit compares:

- the [Phase 14 contract registry](../../spec/phase-14-contract-registry-v1.toml);
- the [six-model capability matrix](phase-14-model-capability-matrix-v1.toml);
- the [source records](phase-14-model-source-records-v1.toml);
- the [Morpheus compatibility matrix](phase-14-morpheus-continuous-semantics-v1.toml);
- the provisional Phase 14 specifications; and
- the Phase 14.1 prototype currently present in the worktree.

The audit does not change the portfolio, source records, Phase 13 contracts, or any model claim. It
also does not accept a replacement API. Those are owner decisions after the focused interview.
Implementation should remain paused until the interview decisions are incorporated into a revised
contract registry and specifications.

## What must not be simplified away

The following are irreducible observable guarantees. Any smaller design must preserve them
explicitly.

| Guarantee | Why it is observable |
| --- | --- |
| Exact update order | Wortel, Wang, CNV, and split field/CPM models change results when order changes. |
| Declared read, write, and snapshot boundaries | They determine whether a process observes old, partially updated, or completed state. |
| Accepted-copy atomicity | Rejected and no-op attempts must not mutate activity or other transaction-coupled state. |
| Exact source attempt budgets | `N` and `16N` attempts are distinct algorithm identities and RNG traces. |
| One authoritative global time mapping | MCS, physical time, field steps, delays, and observations must remain commensurable. |
| Deterministic conflict and priority rules | Relationship mutation, simultaneous events, and lifecycle requests require stable resolution. |
| Lifecycle and slot-generation safety | New, removed, and reused cells must never inherit stale state or relationships. |
| Complete stable-boundary continuation | Checkpoint/restart must reproduce uninterrupted execution, including histories and solver state. |
| Semantic fingerprints | Model identity must include laws, schedules, spatial roles, mappings, and versions. |
| Explicit backend preflight | Unsupported coupled mechanisms must fail before execution, never silently fall back. |
| Qualification and approximation labels | Exact, numerically qualified, approximate, partial, and rejected mappings must remain distinct. |
| Paper observables and provenance | Reproduction claims require traceable definitions, phases, transforms, and source authority. |

The simplification target is the number of ways these guarantees are expressed, not the guarantees
themselves.

## Where the provisional design multiplied concepts

| Concept | Current representations | Audit finding |
| --- | --- | --- |
| Time | `ContinuousClock`, `ContinuousInterval`, `OneMCS`, `HalfMCS`, `GlobalClock`, `MCSDuration`, `SystemClock`, `SystemStep`, `EveryGlobal` | One exact global clock plus process-local stepping is sufficient. Named convenience durations need not be semantic contract types. |
| Scheduling | `MCSPlan`, phase values, `StagedProtocol`, `During`, `MultirateSchedule`, and six `Scheduled*`/timed wrappers | These are different views of one ordered plan with activation windows, cadence, priority, and boundaries. |
| State ownership | `SiteProperty`, `CellHistory`, relationship state, global/cell/field/membrane domains, `DelayState` | One state contract can carry owner domain, schema, storage, initialization, lifecycle, and continuation policy. Histories and delays are storage policies over state. |
| State evolution | Separate site, cell, field, exchange, relationship, continuous-system, event, and mapping process contracts | One process protocol can declare reads, writes, law, trigger, atomicity, stepping, and failure behavior while keeping domain-specific law values. |
| Lifecycle | `LifecyclePhase`, `LifecycleEvent`, `LifecycleRequest`, `ScheduledLifecycle`, `TimedLifecyclePhase`, `TimedLifecycleCapability` | Lifecycle is a privileged process effect with deterministic commit boundaries, not a parallel scheduler. |
| Events | Sampled/root triggers, event batches, assignments, lifecycle requests, scheduled events | An event is a triggered process. Batch ordering belongs to the plan's conflict policy. Root finding may remain an optional solver capability. |
| Identity and mapping | Component identity, authoring canonicalization, `SymbolIdentity`, `SymbolRef`, `SymbolMap`, `InputRef`, checkpoint semantic records | The compiler needs one canonical identity graph. Public references are needed only at ambiguous or cross-domain boundaries. |
| Evidence and execution | Model declarations also appear in checkpoint blocks, backend capability reports, compatibility reports, and contract records | These should be derived views over the compiled semantic model, not author-authored parallel descriptions. |

The prototype exposed the cost of these overlaps: include-order dependencies, separate clock
conversion paths, repeated canonicalization logic, and dispatch boundaries whose signatures encoded
incidental storage choices. These are useful prototype findings. They do not imply that the
scientific features are infeasible; they show that the abstraction boundary should move before the
surface is frozen.

## Recommended semantic kernel

The recommended internal model contains five first-class concepts.

### 1. State

A state declaration answers:

- who owns it: global, cell, site, field, membrane, relationship, or another registered domain;
- its value schema and invariant;
- how it initializes;
- how lifecycle creation, deletion, and slot reuse affect it;
- whether it is current state, bounded history, or delayed history; and
- what must persist at a stable boundary.

Domain-specific storage may remain specialized. A field grid and a relationship graph should not
be forced into the same physical container. They should implement the same semantic state
contract.

### 2. Process

A process declaration answers:

- what it reads and writes;
- the snapshot from which reads occur;
- the law it applies;
- whether it runs transactionally, synchronously, sequentially, or through a numerical solver;
- its trigger or cadence;
- its failure and convergence behavior; and
- whether lifecycle changes are requested.

Accepted-copy updates, site decay, ODE advancement, field evolution, source/sink exchange,
relationship retuning, algebraic rules, mappings, and triggered assignments become law families
under one process protocol. Their scientific law types remain explicit and testable.

### 3. Plan

A plan is the single authority for:

- exact global time and the duration represented by one MCS;
- positional Potts phases;
- process cadence and activation windows;
- staged protocols;
- priority and conflict resolution;
- observation points; and
- stable checkpoint boundaries.

The familiar positional MCS API should remain concise authoring sugar over this plan. A multirate
model uses the same plan with more entries, not another scheduler.

### 4. Lifecycle

Lifecycle defines valid create, divide, transform, remove, and relationship-cleanup effects and
their commit boundary. Processes may request these effects, but only the plan's lifecycle commit
point applies them. This preserves stale-slot and deterministic-order guarantees without creating a
second time system.

Lifecycle could technically be modeled entirely as a process law. It remains named in the kernel
because cell creation and deletion have cross-cutting state-initialization obligations that ordinary
writes do not.

### 5. Observation

An observation declares:

- the snapshot and phase it reads;
- its cadence;
- its transform and reduction;
- its semantic identity and provenance; and
- whether it is diagnostic, validation evidence, or a published-model output.

Observations never mutate scientific state. Paper-specific analyses can compose these primitives
without becoming CorePotts runtime concepts.

### Derived views, not additional model concepts

The compiled kernel should derive:

- canonical fingerprints;
- checkpoint schemas and continuation payloads;
- backend capability requirements and preflight reports;
- read/write conflict diagnostics;
- compatibility reports;
- inspection output; and
- adapter boundary metadata.

An ordinary paper-model author should not need to mention checkpoint extension blocks, backend
capability objects, compatibility profiles, or internal symbol identities.

## Contract-by-contract disposition

These dispositions are proposed interview inputs, not normative decisions.

| Current contract | Proposed disposition | Result |
| --- | --- | --- |
| `coupled-mcs-plan` | Merge into `plan` | Preserve positional phases and transaction snapshots as concise plan entries. |
| `staged-protocol` | Merge into `plan` | Stages become activation windows and scheduled bindings. |
| `continuous-clock` | Merge into `plan` | Retain exact global time and MCS duration; make process-local intervals ordinary values. |
| `spatial-roles` | Keep as a focused spatial contract | Independent proposal/contact/surface/connectivity/query/field relations are CPM-specific and already narrow. |
| `budgeted-sequential-cpm` | Keep as a separate algorithm identity | It protects the frozen `SequentialCPM` meaning and exact RNG/attempt semantics. |
| `site-property` | Merge into `state` | Site ownership is a state domain. |
| `accepted-copy-update` | Merge into `process` | Retain accepted-transaction trigger and atomic commit as a process policy. |
| `cell-history` | Merge into `state` plus `process` | History is a storage policy; sampling is a process. |
| `cell-dynamics` | Merge into `process` | Fixed/adaptive stepping are solver policies, not top-level semantic systems. |
| `field-dynamics` | Merge into `process` | Field solver and convergence behavior remain explicit law/solver metadata. |
| `field-exchange` | Merge into `process` | Secretion and uptake are coupled process laws. |
| `relationship-set` | Merge into `state` | Graph storage remains specialized but implements the state contract. |
| `relationship-dynamics` | Merge into `process` | Priority becomes plan/process conflict policy. |
| `site-dynamics` | Merge into `process` | Decay and degradation are process laws over site state. |
| `coupled-persistence` | Derive from the compiled model | Keep a versioned continuation envelope, but remove it from ordinary authoring. |
| `paper-observation` | Keep as `observation` | Fold phase/cadence into the common plan while retaining observation identity. |
| `coupled-lifecycle` | Keep as a focused kernel concept | Unify all lifecycle requests and commit timing here; remove parallel timed wrappers. |
| `continuous-state-domains` | Merge into `state` | Domains become owner descriptors; ergonomic property constructors may remain. |
| `continuous-system` | Retain as authoring sugar, not a second runtime | Lower equations, rules, reactions, and mappings to state/process/plan IR. |
| `delay-state` | Merge into `state` | Delay interpolation is a history-storage/read policy. |
| `continuous-event` | Merge into `process` plus `plan` | Triggered assignment is a process; ordering is a plan rule. |
| `multirate-schedule` | Merge into `plan` | Use one clock, one ordered schedule, and process-local solver steps. |
| `symbol-mapping` | Mostly internalize | Keep explicit public references only when crossing or disambiguating domains. |
| `continuous-model-adapter` | Move to adapter/evidence boundary | Compatibility reports remain public tooling; adapters should not enlarge the Core model kernel. |

This reduces the semantic center from 24 independently versioned contracts to seven stable areas:

1. state;
2. process;
3. plan;
4. lifecycle;
5. observation;
6. spatial roles; and
7. Potts algorithm identities.

Persistence, compatibility, adapters, inspection, and backend qualification remain important public
tooling surfaces, but they are projections of the model rather than additional authoring semantics.

## Advanced features that should remain experimental

The current `continuous-system` proposal includes DAEs, SDEs, deterministic reactions, discrete
jumps, hybrid reactions, algebraic constraints, and root-triggered events. This is a plausible
long-term compatibility envelope, but the six-model release portfolio does not currently prove that
every family belongs in the stable Phase 14.1 contract.

The recommended rule is:

- stabilize ODEs, synchronous rules, explicit mappings, histories/delays, sampled events, field
  evolution, and lifecycle requests when a selected model or mandatory Morpheus microfixture uses
  them;
- retain extension points and experimental prototypes for adaptive integration, root events, DAEs,
  SDEs, reactions, and jumps; and
- promote an advanced family only after a source-backed model, exact microfixture, continuation
  contract, failure semantics, and backend disposition exist.

ModelingToolkit should remain an optional authoring adapter that lowers into the same process IR.
SBML, Morpheus import, and any much-later Mermaid.jl work should use the adapter boundary. None
should define Phase 14's internal execution model.

## Model coverage under the smaller design

| Model | Source-record ID | Kernel expression |
| --- | --- | --- |
| Graner--Glazier sorting | `graner-glazier-1992-sorting` | CPM state and components, explicit spatial roles, `BudgetedSequentialCPM(16N)`, positional plan, boundary observations. |
| Mombach 3D sorting | `mombach-1995-3d-sorting` | CPM state/components, 3D spatial roles, source attempt budget, temperature stages, boundary observations. |
| Merks vasculogenesis | `merks-2006-vasculogenesis` | Field state, field-evolution process, secretion/chemotaxis process laws, Potts phase, exact split plan, lacuna/branch observations. |
| Wortel Act-CPM | `wortel-2021-act-cpm` | Site-owned activity state, accepted-copy process, per-MCS decay process, neighborhood-read law, burn-in/measurement plan, track observations. |
| Shirinifard CNV | `shirinifard-2012-cnv` | Field/site/relationship states, subcycled field and exchange processes, degradable-structure processes, lifecycle requests and commit, staged plan, ensemble observations. |
| Wang tumor migration | `wang-2025-collective-tumor-migration` | Cell state and bounded histories, ODE/rule processes, field exchange, relationship state/processes, staged relax/switch plan, timed observations. |
| Morpheus compatibility fixtures | `morpheus-continuous-semantics-v1` | Global/cell/field state, ODE/rule/mapping processes, history/delay policies, sampled triggers, lifecycle requests, and one multirate plan. |

No selected mechanism is lost. The smaller kernel changes where it is represented.

## Competing architectures

Scores are provisional, from 1 (poor) to 5 (strong).

| Criterion | A. Minimal kernel only | B. Domain-specific public systems | C. Hybrid façades over one kernel |
| --- | ---: | ---: | ---: |
| Ordinary biological model readability | 2 | 5 | 5 |
| Number of authoritative concepts | 5 | 2 | 4 |
| Exact execution semantics | 5 | 4 | 5 |
| Persistence and preflight derivation | 5 | 2 | 5 |
| Morpheus/MTK adapter path | 5 | 3 | 5 |
| Ease of adding a mechanism | 4 | 2 | 4 |
| Risk of a generic mini-language | 2 | 4 | 4 |
| Risk of parallel runtimes | 5 | 1 | 4 |
| Total | 33 | 23 | 36 |

### A. Minimal kernel only

Users author `State`, `Process`, and `Plan` directly. This has the smallest conceptual core but would
make common biological models verbose and compiler-like.

### B. Domain-specific public systems

Site, cell, field, relationship, event, lifecycle, and continuous systems remain independently
authored and executed. This reads naturally at first but preserves the current duplication and
makes cross-domain coupling costly.

### C. Hybrid façades over one kernel — recommended

Users may write `Act`, field dynamics, cell dynamics, or relationship declarations at the
biological level. Each lowers to one inspectable kernel before execution. There is one scheduler,
one identity graph, one conflict validator, one persistence derivation, and one backend preflight.

The critical constraint is that a façade may add vocabulary, but not a second semantic authority.

## Complexity budgets for the revised design

The following budgets are proposed as enforceable review gates:

1. Exactly one authoritative representation each for global time, scheduling, read/write sets,
   snapshots, and semantic identity.
2. Every stable distinction must change an observable trace, validity condition, persistence
   obligation, or qualification claim. Otherwise it is a convenience value or implementation
   detail.
3. A new process family should implement the process protocol and tests. Fingerprints,
   continuation requirements, inspection, conflict validation, and preflight should derive from its
   metadata rather than require parallel handwritten cases.
4. A simple paper model should use biological declarations and a short plan. It should never author
   checkpoint records, backend requirement objects, adapter profiles, or compatibility levels.
5. No stable contract with no selected-model or required compatibility-fixture source should enter
   Phase 14.1 merely for anticipated completeness.
6. All public façades must lower to an inspectable canonical form, and two equivalent façades must
   produce the same semantic fingerprint.
7. Each Phase 14.1 vertical slice must prove declaration, lowering, CPU-reference execution,
   backend-resident Metal/ROCm execution, inspection, persistence, restart, preflight, residency,
   transfer/allocation bounds, and model microfixtures before another abstraction family is
   expanded.
8. Phase 13 behavior, fingerprints, checkpoints, RNG identities, and algorithm meanings remain
   unchanged for uncoupled models.

These are architecture budgets rather than arbitrary limits on exported names. A library can expose
many helpful law constructors without multiplying semantic authorities.

## Migration from the current prototype

The work already completed should be treated as design evidence, not discarded wholesale.

1. Freeze new prototype surface growth.
2. Define the compact internal state/process/plan IR and its canonical identity.
3. Convert current Phase 14 types into temporary lowering façades or internal law/storage values.
4. Make fingerprints, checkpoint requirements, preflight, and compatibility reports derive from
   the compiled IR.
5. Port the existing focused fixtures as golden semantic traces.
6. Build one full CPU vertical slice—recommended Wortel because it exercises accepted-copy
   atomicity, site state, decay, scheduling, observation, and restart without a PDE solver—then
   close that exact slice on real Metal and ROCm.
7. Build Wang and one field slice in turn to pressure-test multirate and cross-domain coupling,
   closing each on CPU, Metal, and ROCm before opening the next.
8. Delete, internalize, or mark experimental any provisional type that adds no distinct observable
   semantics.
9. Only then revise the stable registry and resume breadth-first Phase 14.1 work.

Because all Phase 14 contracts are explicitly provisional, this cleanup does not require preserving
their current public spelling. Phase 13 compatibility remains mandatory.

### Measured prototype migration gate

After Decision 0031 was accepted, the frozen Phase 13 API checker measured the paused registry v1
prototype rather than accepting it implicitly. Relative to the owner-frozen inventory, the
prototype currently adds 284 CorePotts exports and 152 PottsToolkit exports. The policy's automatic
documentation rules would even classify a small subset as stable despite the provisional design.

The correct response is not to regenerate the frozen inventory. Before the Wortel slice opens, the
implementation migration must:

1. remove or internalize registry v1-only exports;
2. retain a biological value only when registry v2 deliberately identifies it as a façade;
3. replace the v1 family-version report with a seven-area or registry-derived report;
4. prove direct-kernel and retained-façade normalization identity; and
5. make the unchanged Phase 13 API inventory checker pass.

This is now an executable architecture gate, not an aesthetic cleanup suggestion.

## Non-regression and acceptance evidence

The simplification is successful only if all of the following pass:

- unchanged Phase 13 public API, fingerprints, checkpoints, RNG traces, and qualified results;
- exact attempt-count and transaction fixtures;
- accepted/rejected/no-op copy truth tables;
- old-versus-new golden traces for every already-built Phase 14 microfixture;
- restart from every allowed completed-MCS boundary;
- deterministic simultaneous-process and lifecycle conflict fixtures;
- equivalent authoring façades producing identical canonical IR and fingerprints;
- backend rejection before mutation for every unsupported mechanism;
- one complete Wortel vertical slice;
- one Wang multirate/history/relationship slice;
- one Merks or CNV field-splitting slice; and
- Morpheus ODE, rule, delay, mapper, event, and field microfixtures expressed without a second
  runtime.

Passing unit tests alone is not enough. The model sketches must also demonstrate that the smaller
API is readable and that every source order maps to one unambiguous plan.

## Findings that do not require an owner decision

The following should be treated as technical conclusions:

- Phase 13 contracts must not change.
- There must be one compiled semantic authority.
- Persistence and preflight should derive from that authority.
- Independent clocks and schedulers must not coexist.
- Accepted-copy and lifecycle atomicity remain explicit.
- Compatibility status must remain honest and evidence-backed.
- Mermaid.jl is not in Phase 14 scope.
- Current Phase 14 contracts remain provisional until the simplification is accepted and verified.

## Owner decisions required

The owner must decide:

- whether to adopt the recommended hybrid architecture;
- how aggressively to collapse the 24 provisional contracts;
- whether advanced continuous-system families remain experimental;
- how much symbol mapping is visible to ordinary authors;
- whether adapters remain outside the semantic kernel;
- whether the provisional Phase 14 API has any compatibility commitment; and
- which vertical slices gate renewed implementation.

Those choices are isolated in the
[Phase 14 focused semantic-architecture interview](phase-14-semantics-focused-interview.md). On
2026-07-24, the project owner selected the recommended option for all 15 decisions. The next
authorized architecture step is to record that result in a decision and coherently replace the
provisional registry and specifications before broad implementation resumes.
