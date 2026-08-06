# Decision 0031: Phase 14 Single Semantic Kernel

Status: Accepted

Current disposition: the one-semantic-authority principle remains active. Coupled scheduling,
component integration, capability profiles, and current phase placement are superseded by
[Decision 0044](0044-pre-g6-cohesion-and-mtk-hardening.md).

Date: 2026-07-24

## Context

Decision 0030 established that the six-model Phase 14 portfolio can be supported additively without
changing any frozen Phase 13 meaning. Its candidate architecture then decomposed the new scope into
24 provisional contracts and 93 named public values.

The Phase 14.1 prototype and the
[semantic-architecture simplification audit](../../design/audits/phase-14-semantics-simplification-audit.md)
showed that this decomposition created multiple authorities for the same semantic concepts:

- continuous, global, system-local, and convenience clocks;
- positional, staged, event, and multirate schedulers;
- separate state contracts for sites, cells, fields, relationships, membranes, histories, and
  delays;
- separate execution systems for accepted-copy, site, cell, field, exchange, relationship,
  continuous, event, and mapping processes;
- parallel lifecycle event, request, schedule, and timed-phase concepts; and
- repeated identity descriptions in authoring, lowering, persistence, preflight, and compatibility
  reports.

The scientific requirements remain valid. The problem is the number of authoritative
representations, not the model portfolio.

The project owner completed the
[focused semantic-architecture interview](../../design/audits/phase-14-semantics-focused-interview.md)
and selected the recommended option for all 15 decisions.

## Decision

Phase 14 will use one compiled semantic kernel with seven stable contract areas:

1. state;
2. process;
3. plan;
4. lifecycle;
5. observation;
6. spatial roles; and
7. Potts algorithm identities.

The normative architecture is defined by the
[Phase 14 Single Semantic Kernel](../phase-14-semantic-kernel.md) and machine-readable
[Phase 14 Contract Registry v2](../phase-14-contract-registry-v2.toml).

### One semantic authority

Every coupled model lowers to one canonical, inspectable representation before execution. That
representation is the sole authority for:

- state ownership and storage policy;
- process reads, writes, snapshots, laws, triggers, and atomicity;
- exact global time, ordering, cadence, stages, and conflict resolution;
- lifecycle requests and their commit boundary;
- observation timing and definitions; and
- canonical semantic identity.

Fingerprints, continuation requirements, checkpoint extension payloads, backend preflight,
compatibility reports, and inspection output are derived projections of this representation. They
are not independently authored model semantics.

### Hybrid public API

Ordinary users may author biological declarations such as activity state, field dynamics, cell
dynamics, relationship laws, or equation-style continuous systems. These declarations are façades:
they must lower completely to the same kernel and may not own a separate clock, scheduler, runtime,
identity graph, persistence scheme, or backend contract.

Equivalent façades that lower to the same canonical representation have the same scientific
fingerprint.

### One time and plan model

There is one exact global clock and one duration mapping for an MCS. Process-local solver steps,
subcycles, and convergence iterations are process policies. Positional Potts phases, staged
protocols, sampled events, observations, and multirate entries are views of one ordered plan.

### One state and process model

State is parameterized by owner domain, value schema, storage policy, initialization, lifecycle
policy, and continuation requirements. Specialized field grids, relationship graphs, membrane
storage, bounded histories, and delay buffers may have different physical representations while
implementing the same semantic state contract.

Accepted-copy updates, synchronous rules, ODE advancement, field solvers, exchange, relationship
updates, mappings, decay, and sampled events implement one process protocol. Their scientific law
families remain explicit.

### Lifecycle

Processes may emit typed lifecycle requests. One lifecycle contract validates and commits those
requests at declared plan boundaries. No independent lifecycle scheduler or clock is permitted.

### Adapters and advanced families

ModelingToolkit is an optional outer authoring adapter. Future SBML, MorpheusML, or much-later
Mermaid.jl integrations use the same adapter boundary and do not shape CorePotts execution.
Mermaid.jl remains outside Phase 14.

The stable initial scope is evidence-gated. Source-backed ODE, synchronous-rule, explicit mapping,
sampled-event, delay/history, field, and lifecycle semantics may stabilize through their registered
vertical slices. Adaptive integration, solver-located root events, DAEs, SDEs, deterministic
reaction systems, discrete jumps, and hybrid reactions remain Experimental until each has:

- a selected source model or required compatibility fixture;
- an exact observable contract;
- continuation and failure semantics;
- a CPU reference implementation; and
- conformance evidence.

### Compatibility and migration

Every Phase 13 API, fingerprint, checkpoint, RNG identity, algorithm meaning, and qualification
claim remains protected.

The Phase 14 registry v1 and its public spellings were explicitly Provisional and receive no
compatibility commitment. They remain historical design evidence. Implementations may cleanly
replace them while preserving applicable scientific traces and golden fixtures.

### Proving order and implementation gate

Broad Phase 14.1 implementation remains paused. The proving order is:

1. Wortel Act-CPM;
2. Wang collective tumor migration; and
3. one field-coupled model, selected between Merks vasculogenesis and Shirinifard CNV according to
   the first closed solver/source gate.

Implementation may resume only after:

- registry v2 and this decision pass the architecture checker;
- the canonical kernel is specified;
- all six selected models have complete lowering sketches;
- existing Phase 14 prototype behavior used by those sketches has golden traces;
- Phase 13 non-regression checks pass; and
- the Wortel vertical slice has an accepted implementation plan and executable conformance gate.

The complete Wortel implementation is the gate for expanding beyond its slice, not a prerequisite
for writing the kernel infrastructure that the slice requires.

## Relationship to Earlier Decisions

This decision supersedes the architectural decomposition and named candidate surface in
[Decision 0030](0030-phase-14-coupled-dynamics-and-freeze-impact.md). It preserves Decision 0030's
additive D10 classification, Phase 13 freeze protections, completed-MCS stable checkpoint boundary,
CPU-reference requirement, honest backend reporting, and Mermaid.jl exclusion.

[Decision 0029](0029-phase-14-model-driven-capability-and-documentation-policy.md) continues to
govern the selected-model portfolio, fidelity policy, and documentation program.

Decision 0043 retires the later orchestration-package experiment. This decision remains
authoritative for surviving Phase 14 Potts semantics; each accepted cutover must prove serial
equivalence and retire the prior execution
authority for that slice.

## Consequences

- The semantic center contains seven contract areas rather than 24 independently versioned
  contracts.
- Domain-specific vocabulary can remain pleasant without creating parallel runtimes.
- A new process law supplies one metadata record from which conflict checks, fingerprints,
  continuation obligations, preflight, and inspection are derived.
- Persistence and compatibility tooling remain public and testable but are not model-authoring
  languages.
- Morpheus semantic parity is measured construct by construct against the kernel, not by mirroring
  Morpheus's internal object hierarchy.
- ModelingToolkit integration remains optional and cannot become the runtime state owner.
- Provisional prototype code may be retained as temporary façade or law implementations,
  internalized, or removed.
- The revised architecture must be validated vertically before breadth-first capability growth
  resumes.

## Alternatives Considered

### Generic kernel as the only user API

This minimizes concepts but makes ordinary biological models read like compiler IR. It was rejected
as the sole authoring surface.

### Independent domain runtimes

Separate cell, field, event, relationship, and continuous runtimes initially look natural, but
duplicate time, scheduling, persistence, and coupling semantics. This was rejected.

### Preserve registry v1 and improve documentation

The overlap is structural rather than terminological. Renaming the 24 contracts would not remove
parallel authorities.

### Stabilize the full Morpheus/SBML formalism envelope immediately

This would freeze speculative DAE, SDE, root-event, reaction, and jump semantics before the selected
models prove their necessity. Extension points are retained, but those families remain
Experimental.

### Preserve provisional Phase 14 spellings through deprecation

No released compatibility promise exists, and preserving the prototype surface would force the
complexity that this decision resolves. Phase 13 remains fully protected.

## Required Conformance Evidence

- Registry v2 contains exactly the seven accepted contract areas.
- Every non-existing/non-paper-specific capability row maps to a registry v2 contract or to the
  explicitly derived adapter/tooling boundary.
- Every Morpheus semantic requirement maps to registry v2 contracts or the adapter boundary.
- All six selected models have an unambiguous state/process/plan/lifecycle/observation lowering
  sketch.
- There is exactly one canonical identity for time, schedule order, read/write sets, snapshots, and
  state/process references.
- Equivalent façade and direct-kernel models normalize identically.
- Persistence, preflight, inspection, and compatibility reports derive from the normalized model.
- Uncoupled Phase 13 normalization, fingerprints, checkpoints, RNG traces, and results remain
  unchanged.
- Wortel accepted/rejected/no-op copy, decay order, observation, and restart fixtures pass before
  the next vertical slice opens.
- Wang then proves history, continuous state, relationships, staging, and multirate coupling.
- A field model then proves field evolution, exchange, splitting, continuation, and failure
  semantics.
