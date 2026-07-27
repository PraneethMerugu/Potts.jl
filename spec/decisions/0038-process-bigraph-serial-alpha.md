# Decision 0038: ProcessBigraphs Phase 15.C Serial Internal Alpha

Status: Accepted pre-implementation architecture; Phase 15.C runtime implementation not started

Date: 2026-07-26

## Context

Phase 14.PB0 established a bounded domain-neutral serial foundation. Phase 15.A replaced its
provisional authoring structure with one canonical ProcessBigraph ACSet and an immutable indexed
execution plan. Phase 15.B added arbitrary-depth immutable open composition, real structured
cospans, and a lossless annotated wiring view. Those slices pass direct evidence, but they do not
establish the complete serial runtime or its independent conformance oracle.

The remaining Phase 15 work is semantically coupled. Scheduler publication determines RNG event
identity, observer boundaries, continuation advancement, failure rollback, and checkpoint
contents. Implementing these concerns independently without one closure contract could create
multiple authorities or circular conformance evidence.

The project owner resolved all 64 questions in the
[Phase 15.C owner interview](../../design/audits/process-bigraph-phase15c-serial-alpha-owner-interview.md)
by accepting the recommended option. This record converts those answers into one normative
pre-implementation decision. The exact allowlist, exclusions, fixtures, ordering, and evidence
shape are machine-readable in
[`process-bigraph-phase15c-entry-v1.toml`](../process-bigraph-phase15c-entry-v1.toml).

## Decision

### Scope and maturity

Phase 15.C qualifies an immutable-topology serial internal alpha. It is not a public release or a
complete Process-Bigraph parity claim. The phase implements only the allowlisted serial semantics
and requalifies their applicable supporting invariants against an independent Julia oracle.

The following remain outside Phase 15.C:

- runtime structural add, remove, divide, move, and rewire;
- `AlgebraicRewriting.jl` and dynamic structural epochs;
- Threads, Dagger, distributed execution, and automated retry;
- GPU/device execution and cross-residency transfer execution;
- SciML, ModelingToolkit, Catalyst, JumpProcesses, COBREXA, SBML, and other scientific adapters;
- the CorePotts adapter and any Potts runtime cutover;
- whole-cell qualification, Python interchange, public package registration, and public release;
- Vivarium, Process-Bigraph Python, or Bigraph-Schema Python installation or execution.

Semantic identities and observable behavior become alpha-stable. Constructor spelling may still
improve before public release.

### Runtime and scheduler authority

`SerialExecutor` is the execution policy. `SerialRuntime` contains mutable execution state.
ProcessBigraphs remains the sole authority for logical time, batch selection, committed state,
continuations, RNG identity, observation, failure, checkpoint, and replay.

At each event the scheduler:

1. chooses the minimum exact due deadline;
2. selects every process due at that deadline;
3. gives each due process the same immutable pre-commit snapshot;
4. validates all deltas, proposed deadlines, continuations, and required observation records;
5. deterministically reconciles the batch;
6. runs the declared reactive plan to deterministic quiescence;
7. publishes state, clocks, continuations, RNG/event position, and required records atomically; and
8. emits one canonical event record.

An adaptive deadline is a proposed transactional result. It must be exact, strictly future,
representable, and valid under the process contract before publication.

Exact horizon advancement supplies actual elapsed partial intervals only to processes declaring
partial support. Otherwise it rejects before mutation. `stop_prior` is the explicit alternative.
Empty exact-time advancement may publish an unchanged settled snapshot without creating a process
event or consuming RNG.

Reactive steps execute in a statically declared acyclic dependency plan. A step repeats only when
one of its declared inputs changes. Execution stops at quiescence or a fingerprinted activation
bound. Cyclic work is legal only inside a named iterative region with deterministic ordering and a
fingerprinted hard bound or convergence rule. Undeclared cycles remain invalid.

### Semantic RNG

Core randomness is counter-based and is addressed by:

- model fingerprint;
- normalized root seed;
- process identity;
- exact logical time;
- event identity;
- lineage identity;
- stable named draw site; and
- explicit draw index.

Source line, call order, task order, and device allocation are nonsemantic. The counter algorithm
and address schema are versioned and fingerprinted. Core bits, integers, and uniforms are exact.
Other distributions and solver-owned RNGs declare an honest replay class. A solver-owned mutable
RNG is valid only inside a typed, versioned, checkpointed continuation. Failed unpublished events
consume no semantic RNG identity. Observer randomness occupies a separate namespace and cannot
alter model draws.

### Observation and continuation

Observation is a declarative pre-execution plan of stable observer identities, read-only
projections, schedules, output schemas, and required or optional policy. Observers see only
declared projections of immutable candidate snapshots at settled boundaries.

Required in-memory records participate in event validation and atomic publication. External files,
databases, services, and dashboards are separate emitters with explicit idempotency and retry
contracts; the serial core does not claim atomic external side effects.

Observers do not change the scientific model fingerprint. The runtime/observation fingerprint
does include observation identities, schemas, schedules, and policies.

Every stateful process, step, and observer owns a typed continuation specification with:

- stable owner and schema identity;
- semantic implementation version;
- canonical encode and decode;
- validation and fingerprint rules;
- restore requirements;
- invalidation rules; and
- explicit migrations when supported.

Arbitrary untracked continuation values cannot qualify for internal alpha.

### Failure and checkpoint

The serial executor is deterministic fail-stop. It performs no implicit retry. A failed event
publishes no candidate state, clock, continuation, RNG/event position, observer position, or
required record. Earlier settled events remain committed, and explicit retry from the unchanged
settled boundary receives the same semantic RNG addresses.

Structured failures carry a versioned semantic code, stage, owner, logical time, event identity,
last stable fingerprint, cause classification, and retry classification. Mutable runtime objects
are not diagnostic payloads.

A Phase 15.C checkpoint is a canonical, deterministic, versioned logical envelope independent of
Julia object serialization. It contains:

- committed state and exact logical time;
- event ordinal and canonical event position;
- process and step clocks;
- typed process, step, and observer continuations;
- semantic RNG algorithm, address schema, root identity, and required solver RNG state;
- observation positions required to prevent duplicates or omissions;
- structural epoch and compiled-plan compatibility identities; and
- model, runtime, observation, continuation, and checkpoint fingerprints.

The already attested v1 reader remains supported. New contents use a distinct version. Phase 15.C
qualifies exact compatible serial restore only; cross-backend import and general migration remain
later work.

### Independent Julia specification oracle

The checked oracle is a test-only Julia module. Production code cannot depend on it. The oracle
uses deliberately simple independent records and algorithms and may share only neutral
machine-readable fixture inputs and result schemas with the production driver.

The oracle must not call or import production implementations of scheduling, reconciliation,
update laws, RNG, continuation, observation, checkpoint, fingerprinting, or runtime execution.
Every oracle rule cites a pinned source location or an explicit Julia semantic decision.

Core comparisons are exact. Generated cases are bounded and reproducible and retain minimal
counterexamples. CI statically enforces the dependency boundary and runs mutation-sensitivity
fixtures showing that the oracle detects perturbed scheduler, update, RNG, failure, and checkpoint
behavior.

### Qualification and closure

Qualification uses the exact target and supporting allowlists in the entry contract. Required
evidence includes:

- finite truth tables;
- focused unit tests;
- production/oracle differential tests;
- property and metamorphic invariance tests;
- mutation-sensitivity tests;
- failure injection at every publication stage;
- restart from every reachable settled boundary in bounded fixtures;
- all supported authoring-form equivalence where applicable;
- no runtime ACSet traversal, hidden transfer, or structure-dependent hot-path allocation;
- package-independent clean installation and testing; and
- a dedicated Phase 15.C checker, oracle CI lane, machine-readable evidence, and aggregate
  `Required` passage.

Closure is all-or-nothing and uses two pull requests:

1. the implementation PR passes the full matrix and produces a CI-generated candidate artifact
   naming its exact head commit, tree, run, assertions, and environment; then
2. the closure-attestation PR records the implementation merge commit, qualified head/tree, CI
   run, exact totals, limitations, and registry promotions.

Only the closure-attestation PR may set `internal_alpha = true` and advance the internal package
identity from `0.3.x` to `0.4.0`. It does not publish the package.

## Consequences

- Phase 15.C has one explicit semantic and evidence boundary rather than a collection of loosely
  related features.
- Scheduler, RNG, observation, failure, and checkpoint identities cannot drift independently.
- Direct Phase 15.A/B structural evidence remains historically intact.
- The independent oracle cannot become a wrapper around production code.
- The two-stage closure avoids a self-referential or pre-squash-only provenance record.
- New capabilities must use focused modules; existing large internals may be decomposed only
  behavior-preservingly behind the complete regression matrix.
- Later executors and adapters inherit the serial time, visibility, commit, failure, RNG, and
  checkpoint semantics rather than redefining them.

## Rejected alternatives

- Treating the PB0 microfixture runner as a qualified serial executor.
- Closing internal alpha without adaptive deadlines, iteration, multirate input behavior, semantic
  RNG, observers, typed continuations, or portable logical checkpoints.
- A mutable global RNG, implicit draw counters, or task-order-dependent streams.
- Arbitrary callbacks with runtime mutation authority.
- Julia object serialization as the canonical checkpoint format.
- Silent automatic retry or partially published failed events.
- An oracle that reuses production semantic helpers.
- Live upstream Python execution as the conformance oracle.
- One large whole-cell or Potts fixture in place of orthogonal domain-neutral fixtures.
- Expanding Phase 15.C into dynamic structure, adapters, Dagger, GPU, or public release.
- Recording only a pre-merge commit as final runtime provenance.

## Required conformance evidence

Before Phase 15.C implementation may begin, the owner interview, this decision, the implementation
plan, entry contract, entry audit, roadmap references, and entry checker must agree and pass.

Before internal alpha may close, every requirement in the entry contract and implementation plan
must have exact production and independent evidence as applicable, both closure PRs must pass all
required CI, and the final registry and documentation must retain every later-phase exclusion.
