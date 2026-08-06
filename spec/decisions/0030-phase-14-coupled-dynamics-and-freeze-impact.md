# Decision 0030: Phase 14 Coupled Dynamics and Freeze Impact

Status: Accepted for Phase 14.0 architecture and D10 classification; governed D9 contracts remain
Provisional until their Phase 14.1 evidence gates pass; architectural decomposition superseded by
Decision 0031

Current disposition: coupled scheduling and integration architecture are further superseded by
[Decision 0044](0044-pre-g6-cohesion-and-mtk-hardening.md). Compatible scientific requirements and
source analysis remain historical input to G5H.

Date: 2026-07-24

Supersession note: [Decision 0031](0031-phase-14-single-semantic-kernel.md) replaces this record's
24-contract decomposition with one seven-area semantic kernel. The additive D10 assessment, Phase
13 freeze protections, completed-MCS stable boundary, and scope exclusions in this record remain
accepted.

## Context

The selected Phase 14 model corpus requires accepted-copy site state, evolving fields, continuous
cell state, dynamic relationships, degradable structures, state-dependent lifecycle, source attempt
budgets, staged protocols, and paper observations. The owner additionally requires Morpheus
model-semantic compatibility for global/per-cell/field/membrane systems, rules, events, delays,
multirate schedules, and cross-domain mappings. Phase 13 froze the existing runtime, public API,
algorithm, fingerprint, checkpoint, result, and evidence meanings.

D9 requires observable semantics and update ordering for each new family. D10 requires an explicit
assessment of whether those additions invalidate a frozen meaning.

## Decision

Accept the public identities, architectural boundaries, and additive D10 classification registered
in [Phase 14 Contract Registry v1](../phase-14-contract-registry-v1.toml). Individual D9 contracts
remain Provisional until their source gate, reference prototype, conformance, persistence, and
backend evidence passes. Acceptance of this decision is not an implementation claim.

The architecture uses:

- one existing `PottsModel`/`PottsProblem`/`PottsIntegrator`/`PottsSolution` runtime;
- the existing PottsToolkit `Phase` identity inside one explicit `MCSPlan`;
- one immutable snapshot and atomic commit per ordinary phase;
- the existing algorithm-specific transaction law inside `PottsAttempts`;
- exactly one final lifecycle and one observation phase in an ordinary positional plan;
- existing `CellProperty` for fixed-shape per-cell continuous state;
- additive `SiteProperty`, `CellHistory`, `RelationshipSet`, `GlobalProperty`,
  `MembraneProperty`, and `DelayState` state;
- additive typed processes for accepted-copy, site, cell, field, exchange, and relationship dynamics;
- one general `ContinuousSystem` contract for differential equations, synchronous rules,
  assignments, functions, DAEs, stochastic laws, deterministic reactions, discrete/hybrid jump
  processes, and events;
- an opt-in `MultirateSchedule` that maps global, MCS, and system-local clocks, retains one Potts
  attempt stage per MCS, and may schedule additional typed lifecycle boundaries;
- qualified `SymbolRef`/`SymbolMap` identities and cross-domain reductions;
- optional ModelingToolkit, MethodOfLines, SBML, and future MorpheusML adapters through PottsToolkit
  extensions with construct-level compatibility reports;
- a separate `BudgetedSequentialCPM` algorithm for source budgets other than the frozen reference
  definition;
- integer public MCS with explicitly mapped global and process-local continuous clocks; and
- a versioned `CoupledCheckpoint` envelope containing an unchanged `CanonicalCheckpoint` v1.

The completed-MCS boundary remains the only stable checkpoint boundary. Required observation failure
is fatal; only explicitly non-scientific `BestEffortTelemetry` may be nonfatal.

Mermaid.jl integration is explicitly outside Phase 14.0 and the accepted Phase 14.1 scope. A later
optional external-orchestration extension may use stable public state and stepping boundaries, but
this decision adds no Mermaid dependency, wrapper, test, runtime behavior, or delivery commitment.

## D10 Assessment

Every registered Phase 14 change is additive as specified:

- omitted Phase 14 declarations retain the exact Phase 13 normalized model and fingerprint;
- `SequentialCPM` v1 remains exactly `N` sequential attempts per MCS;
- fixed `FocalPointSpringHamiltonian` v1 remains immutable;
- existing sampled fields retain their descriptor and immutable-snapshot meaning;
- the accepted lifecycle category order, common snapshot, and transaction laws remain;
- ordinary lifecycle remains at the completed-MCS boundary; additional timed lifecycle boundaries
  exist only under the new multirate contract and reuse the accepted transaction laws;
- SciML integer-MCS stepping, callbacks, saving, and result meanings remain;
- `CanonicalCheckpoint` v1 type, bytes, checksum, storage payload, restore, and import remain;
- existing RNG namespaces and contract identities are not renumbered;
- no unqualified Metal or ROCm support is inherited by a new capability; and
- Phase 13 evidence remains valid for models that do not opt into new declarations.

Any implementation that cannot satisfy one of these statements is incompatible and must stop for a
separate versioned D10 decision before merge.

## Source Versus Architecture

The reusable architecture does not choose unknown paper behavior. The
[source-closure records](../../design/audits/phase-14-source-closure-v1.toml) separate pinned source
transcriptions from paper-only sensitivity envelopes. Merks solver/splitting, paper-only sorting
execution details, foreign-runtime ordering, missing ensemble seeds, and Graner--Glazier annealing
disposition constrain the corresponding reproduction claim but do not reopen the reusable
execution architecture.

## Consequences

- Phase 14.1 can be implemented as vertical capability slices after the applicable source and
  acceptance gates close.
- CPU sequential reference behavior is mandatory for every stable capability.
- GPU support remains explicitly unsupported or unclaimed until real-hardware qualification.
- Dynamic state and processes become part of model fingerprints, manifests, inspection, persistence,
  and restart.
- ModelingToolkit is a lowering path rather than a second runtime or scientific identity authority.
- Morpheus compatibility is a construct-by-construct evidence claim, not an XML/GUI resemblance
  claim.
- Paper observations use versioned schemas and evidence labels; tutorials do not confer validation.

## Alternatives Considered

- a separate coupled problem/integrator hierarchy;
- an unrestricted mutable callback system;
- making ModelingToolkit the simulation owner or a CorePotts dependency;
- changing `SequentialCPM` to accept a multiplier;
- mutating fixed focal-point storage into a dynamic graph;
- adding fields to `CanonicalCheckpoint` v1;
- checkpointing partial MCS phases; and
- forcing all sampled source events into solver root-finding events;
- runtime lexical symbol lookup or one mutable symbol dictionary;
- silently falling back to host execution for unsupported GPU phases.

These alternatives either duplicate the runtime, hide scientific order, or invalidate frozen
contracts.

## Required Conformance Evidence

- every acceptance item in the contract registry;
- byte-identical uncoupled normalization, fingerprint, checkpoint, and storage fixtures;
- one complete CPU reference vertical slice for each additive capability family;
- exact failure, invariant, lifecycle, persistence, and restart fixtures;
- optional-extension loading without ModelingToolkit or storage packages in CorePotts;
- pinned Morpheus time-scale, ODE, synchronous-rule, delay, event, mapping, field, and lifecycle
  microfixtures plus construct-level compatibility reports;
- source-simulator microfixtures for the first proving model in each slice; and
- owner approval of this D10 architecture and freeze-impact assessment, recorded by the completed
  Phase 14 interview and the instruction to finish Phase 14.0; and
- separate later acceptance of each governed D9 specification only after its registered Phase 14.1
  implementation and conformance evidence passes.
