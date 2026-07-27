# ProcessBigraphs Phase 15.C Serial Internal-Alpha Plan

Status: Complete; C0--C7 implemented, independently qualified, and attested

Date: 2026-07-26

Authority:

- [Phase 15.C owner interview](process-bigraph-phase15c-serial-alpha-owner-interview.md)
- [Decision 0038](../../spec/decisions/0038-process-bigraph-serial-alpha.md)
- [Phase 15.C entry contract](../../spec/process-bigraph-phase15c-entry-v1.toml)
- [ProcessBigraphs runtime semantics](../../spec/process-bigraph-runtime-semantics.md)
- [ProcessBigraphs parity registry](../../spec/process-bigraph-parity-registry-v1.toml)

## Objective

Turn the bounded PB0 execution machinery and the passed Phase 15.A/15.B structural foundation into
a qualified immutable-topology serial internal alpha. The result must have one production serial
executor, exact multirate semantics, semantic RNG, read-only observation, typed continuation,
canonical settled checkpoints, deterministic fail-stop behavior, and a structurally independent
checked Julia oracle.

This plan is the historical implementation contract, not the evidence record. Under its two-stage
rule the implementation candidate remained version `0.3.0`, `internal_alpha = false`, and publicly
unreleased until closure. The attestation subsequently advanced the unchanged qualified runtime to
`0.4.0`, `internal_alpha = true`, with `public_release = false`.

## Non-goals

- runtime topology mutation or AlgebraicRewriting;
- Threads, Dagger, distributed placement, automated retry, or task-level fault recovery;
- Metal, ROCm, CUDA, or other device execution;
- executable residency bridges or cross-backend checkpoint import;
- CorePotts or PottsToolkit adapters and any Potts cutover;
- SciML, ModelingToolkit, Catalyst, JumpProcesses, COBREXA, SBML, or whole-cell adapters;
- Python declaration interchange or upstream Python runtime execution;
- complete pinned parity, repository separation, package publication, or public API freeze;
- fastest-runtime claims; and
- a broad rewrite of the passed Phase 15.A/15.B structure and composition implementation.

## Frozen semantic boundary

The exact feature allowlists, exclusions, fixtures, methods, and evidence fields are normative in
the entry contract. Human-readable lists in this plan must not be edited independently of that
contract.

The 15 target feature rows are:

1. `canonical-state-serialization`;
2. `temporal-process-protocol`;
3. `ordered-reactive-step-protocol`;
4. `explicit-iterative-constructs`;
5. `imminent-event-scheduler`;
6. `adaptive-deadlines`;
7. `versioned-update-algebra`;
8. `settled-boundary-checkpoint`;
9. `versioned-process-continuation`;
10. `semantic-lineage-rng`;
11. `transactional-failure`;
12. `readonly-observer-protocol`;
13. `serial-semantic-executor`;
14. `multirate-input-semantics`; and
15. `independent-julia-specification-oracle`.

The supporting rows requalified against the oracle where applicable are:

- `workflow-cycle-rejection`;
- `exact-integer-logical-time`;
- `actual-elapsed-partial-interval`;
- `same-time-common-snapshot`;
- `typed-process-deltas`;
- `deterministic-conflict-reconciliation`; and
- `atomic-event-commit`.

The passed canonical ACSet, compiled epoch, open composition, and annotated wiring rows retain
their Phase 15.A/B direct evidence. Phase 15.C tests their authoring-to-runtime equivalence without
rewriting their evidence history.

## Code-organization rule

New concerns use focused source units. Exact filenames may change during implementation review, but
the ownership boundaries may not:

| Concern | Planned source ownership | Forbidden coupling |
|---|---|---|
| Executor protocol and serial event loop | `executor.jl`, `serial_executor.jl` | ACSet traversal, oracle calls |
| Schedules, deadlines, reactive activation, iteration | `scheduling.jl`, `iteration.jl` | observer or checkpoint authority |
| Semantic RNG addresses and draws | `semantic_rng.jl` | global RNG, task-order counters |
| Typed continuation contracts | `continuations.jl` | arbitrary unvalidated runtime state |
| Observation plans and in-memory records | `observation.jl` | committed-state mutation, model RNG |
| Structured failures and transaction candidate | `transactions.jl`, existing `errors.jl` | external side-effect rollback claims |
| Logical checkpoint envelope and codec | `checkpoint.jl`, `checkpoint_codec.jl` | Julia `Serialization` authority |
| Independent oracle | `test/specification_oracle/` | production semantic implementations |
| Neutral fixtures and comparison driver | `test/phase15c/` | fixture-specific production shortcuts |

`composition.jl` may be split behavior-preservingly into validation, mounting, initialization,
ACSet assembly, and provenance helpers if Phase 15.C work must touch it. Such a split cannot change
public behavior, fingerprints, failures, or Phase 15.B assertion totals and is not a prerequisite
for unrelated scheduler work.

## 15.C0: Entry freeze

### Work

- Record all 64 owner answers without reinterpretation.
- Accept Decision 0038.
- Freeze this plan and the machine-readable entry contract.
- Publish an entry audit mapping each choice to a decision, plan section, machine-readable field,
  later evidence, and phase exclusion.
- Add a fail-closed entry checker to Project integrity CI.
- Update the decision index, specification index, roadmap, repository architecture, package-local
  maturity text, and local registry planning metadata.
- Confirm package version `0.3.0`, `internal_alpha = false`, and no Phase 15.C runtime or oracle
  evidence claim.

### Exit

- Every entry artifact exists and cross-links correctly.
- The registry contains every target, supporting, retained, and excluded feature exactly once.
- No target is falsely labelled Phase 15.C implemented or independently qualified.
- The entry checker, platform checker, PB0 checker, Phase 15.A checker, Phase 15.B checker, package
  tests, TOML parsing, and whitespace checks pass.
- The packet merges through normal CI. Only merged `main` authorizes 15.C1.

## 15.C1: Production serial scheduler

### Representation

- Add an explicit `SerialExecutor` policy value and retain `SerialRuntime` as execution state.
- Replace the PB0-only event-loop status with a versioned serial-executor contract.
- Represent fixed and adaptive scheduling behind one validated schedule protocol.
- Represent proposed next deadlines in invocation results without allowing process-side mutation of
  runtime clocks.
- Add canonical event and activation records independent of declaration or task order.
- Represent iterative regions explicitly in the compiled plan; undeclared cycles remain invalid.

### Event transaction

For one selected time:

1. derive the canonical event identity without mutating runtime state;
2. project one common immutable snapshot for every due temporal process;
3. invoke due processes in any execution order while retaining semantic identities;
4. validate deltas, proposed deadlines, diagnostics, and continuations into an unpublished
   candidate;
5. reconcile all temporal deltas deterministically;
6. activate reactive steps from declared changed-input dependencies;
7. run acyclic layers to quiescence or the fingerprinted activation bound;
8. execute named iterative regions using their deterministic bound or convergence rule;
9. validate the complete candidate; and
10. publish one settled boundary atomically.

### Required semantics

- exact minimum-deadline selection;
- common same-time visibility;
- strictly future adaptive deadlines;
- actual elapsed duration;
- `exact` and `stop_prior` horizons;
- preflight rejection of unsupported partial advancement;
- empty exact-time advancement without a process event;
- changed-input reactive activation;
- deterministic quiescence and non-convergence failure;
- explicit bounded and convergent iteration;
- checked event-ordinal and time overflow;
- declaration-, collection-, and invocation-order invariance; and
- no ACSet or authoring-tree traversal after compilation.

### Tests

- finite deadline and horizon truth tables;
- same-time accumulator and multirate producer/consumer fixtures;
- adaptive pulse valid, past, equal, overflow, and failure cases;
- reactive DAG activation and quiescence matrices;
- iterative bounded success, convergent success, bound exhaustion, and undeclared cycle failure;
- old PB0 trace and checkpoint non-regression;
- event-record canonicalization; and
- allocation and structure-traversal guards.

### Exit

The production serial scheduler passes its direct matrix while the registry remains unqualified
until the independent oracle joins in 15.C5/15.C6.

## 15.C2: Semantic RNG

### Representation

- Define a versioned normalized root-seed representation.
- Define a canonical RNG address containing every field in the entry contract.
- Define stable named draw-site identities and explicit draw indices.
- Select and pin a counter-based core algorithm after a dependency, license, CPU/device-portability,
  and reference-vector review.
- Define exact bit, integer, and uniform transforms with golden vectors.
- Add a separate observer-analysis namespace.
- Add an explicit continuation wrapper for solver-owned stateful RNGs.

### Rules

- No core draw depends on mutable stream position, source line, call order, invocation order, task
  completion order, or dictionary order.
- Duplicate requests for one address return the same value.
- Distinct explicit indices and semantic sites cannot alias.
- Failed unpublished events do not advance RNG identity.
- Retry from the unchanged boundary reproduces the same draws.
- An observer cannot request a model-namespace draw.
- RNG algorithm and address-schema identities enter runtime and checkpoint fingerprints.
- Distribution replay classes are explicit and cannot be inferred from seeding alone.

### Tests

- published/reference vectors for the selected counter algorithm;
- complete address-component sensitivity;
- request-order and invocation-order metamorphic tests;
- duplicate-address identity and distinct-address separation;
- failure/retry equality;
- checkpoint/restart equality;
- observer isolation;
- root-seed normalization and rejection;
- bounded generated stochastic-branch fixtures; and
- source scans rejecting untracked `rand`/global RNG use in qualified core paths.

### Exit

The semantic RNG implementation passes direct exact vectors and invariance tests. No device or
cross-backend claim is made.

## 15.C3: Observation and continuation

### Typed continuation

- Replace alpha-qualified arbitrary continuation storage with a typed continuation specification.
- Preserve the ability to hold domain-specific values only through explicit schema, codec,
  fingerprint, validation, restore, invalidation, and migration contracts.
- Separate owner semantic version from continuation schema version.
- Validate the initial continuation at compile/initialization time and every proposed continuation
  before event publication.
- Reject restore across incompatible owner, schedule, schema, or semantic versions before creating
  a live runtime.

### Observation

- Compile a declarative observation plan before execution.
- Give each observer a stable identity, declared paths/metadata, exact schedule, output schema,
  continuation specification, and required/optional policy.
- Build immutable projection views without granting runtime or committed-store mutation authority.
- Compute and validate required in-memory records inside the event candidate.
- Publish required records atomically with the settled event.
- Keep external emitter behavior outside the core transaction and explicitly non-atomic.
- Separate model fingerprints from runtime/observation fingerprints.

### Tests

- continuation schema/version/owner truth tables;
- canonical continuation encode/decode/fingerprint;
- invalid initial and proposed continuation rejection;
- explicit migration success and unregistered migration failure;
- observer projection privacy and mutation rejection;
- observation schedule and empty-time behavior;
- required record atomicity;
- optional observer failure classification;
- observer RNG namespace isolation;
- duplicate/omission prevention across every restart cut; and
- unchanged model fingerprint under observation-plan changes.

### Exit

Every alpha-qualified stateful process, step, and observer uses a typed continuation contract, and
required in-memory observation records are transactionally integrated without external atomicity
claims.

## 15.C4: Failure and checkpoint completion

### Transactional failure

- Represent a complete unpublished event candidate.
- Validate all candidate fields before mutating `SerialRuntime`.
- Convert failures at each registered stage into versioned structured diagnostics.
- Retain the last settled boundary and exact retry identity.
- Perform no implicit retry.
- Prove that earlier successful events in one `run_until!` call remain valid when a later event
  fails.

### Checkpoint envelope

- Preserve the existing v1 reader and its attested behavior.
- Add a distinct logical envelope version for the complete Phase 15.C state.
- Define canonical encode and decode for every admitted value; unsupported continuation payloads
  fail before checkpoint creation.
- Include every required field from the entry contract.
- Separate the logical envelope from filesystems, databases, and Julia object serialization.
- Validate checksum, schema, model, plan, observation, continuation, RNG, and clock compatibility
  before returning a restored runtime.
- Qualify exact compatible serial restore only.

### Tests

- one injected failure at every registered publication stage;
- unchanged stable fingerprints and event positions after failure;
- retry equality for state, RNG, continuation, observations, and trace;
- v1 reader retention;
- new-envelope golden bytes and decode/encode identity;
- corruption, truncation, unknown version, mismatched model/plan/observer/RNG/continuation failures;
- every reachable settled-boundary restart for bounded fixtures;
- observer duplicate/omission checks;
- no Julia `Serialization` authority; and
- storage-extension absence does not weaken logical checkpoint evidence.

### Exit

All failure stages are atomic at the event boundary, every bounded settled boundary restarts
exactly, the v1 reader remains passing, and the new logical checkpoint format is canonical.

## 15.C5: Independent Julia specification oracle

### Boundary

The oracle lives under `lib/ProcessBigraphs/test/specification_oracle/`. Its semantic module:

- does not import `ProcessBigraphs`;
- uses only the allowed roots in the entry contract;
- owns independent time, schedule, update, RNG, continuation, observer, failure, and checkpoint
  records and algorithms;
- accepts neutral fixture records rather than production runtime objects; and
- returns a neutral result record compared by a separate driver.

The comparison driver may invoke production and oracle entry points, but neither implementation may
call the other. Shared neutral fixture/result schemas contain data only and no semantic helper.

### Derivation ledger

For every oracle rule record:

- rule identity and version;
- pinned source repository, commit, file, and line or test identity;
- applicable paper section;
- Julia decision when upstream authorities disagree;
- finite truth table or derivation;
- fixture and assertion identities; and
- known limitation.

No floating documentation or live upstream runtime result is evidence.

### Oracle matrix

- exact imminent-event selection and same-time snapshots;
- partial horizons and adaptive deadlines;
- reactive activation, quiescence, and iteration;
- all admitted update laws and conflict outcomes;
- typed continuation advancement and invalidation;
- semantic RNG vectors and address behavior;
- observer schedules and required-record publication;
- every structured failure stage; and
- checkpoint capture, integrity, restore, and remaining trace.

### Anti-circularity

- Static checks reject forbidden imports and production call names.
- File dependency checks ensure production sources do not include test/oracle paths.
- Mutation fixtures deliberately perturb scheduler selection, update ordering, RNG addressing,
  failure publication, and checkpoint fields. Every registered mutant must be killed.
- An oracle mismatch stops qualification; the oracle is not automatically updated to match
  production. Resolution requires a source/decision audit.

### Exit

The oracle passes its independent unit tests, boundary checker, source-location ledger, and all
registered mutation-sensitivity fixtures before production/oracle parity may be claimed.

## 15.C6: Qualification matrix

### Orthogonal fixtures

Use all eight fixtures defined in the entry contract. Each fixture has one primary semantic purpose
and minimal secondary behavior. A large integrated model cannot replace any fixture.

### Cross-product policy

Not every mathematical cross-product is useful, but every required interaction is registered
before execution. The qualification manifest must enumerate:

- feature rows exercised by each fixture;
- direct, truth-table, property, metamorphic, mutation, failure, and restart assertion totals;
- authoring paths applicable to the fixture;
- exact event and restart cuts;
- bounded generated-case seeds and size limits;
- expected model, plan, initial-state, trace, RNG, observation, and checkpoint fingerprints; and
- exclusions with reasons.

Missing combinations fail the checker rather than silently reducing the matrix.

### Authoring convergence

The open-composite fork/join fixture is built through ordinary typed construction, direct ACSet,
n-ary composition, pairwise grouping, structured cospan, and annotated wiring. Applicable outputs
must match exactly:

- canonical model;
- structural and model fingerprints;
- compiled plan and provenance;
- neutral oracle fixture;
- initialized state;
- event and observation traces;
- RNG addresses and values; and
- checkpoint/restart results.

### Invariance and restart

Exercise every invariance dimension in the entry contract. For each bounded fixture, enumerate
every reachable settled boundary and compare uninterrupted and resumed remaining execution
exactly. Failure fixtures additionally retry explicitly from the unchanged boundary.

### Performance guardrails

- inspect runtime dependency paths for ACSet/cospan/wiring traversal;
- measure allocations against fixture size and reject structure-dependent hot-path growth;
- reject hidden device transfer or scalar fallback paths even though device execution is excluded;
- record compile and event throughput for regression tracking; and
- make no external or fastest-runtime performance claim.

### CI

The implementation PR adds:

- a dedicated Phase 15.C closure checker;
- a separate independent-oracle job or clearly isolated required lane;
- the unchanged independent package job;
- candidate evidence generation and artifact upload;
- oracle-boundary and mutation-sensitivity enforcement; and
- dependencies from the aggregate `Required` job.

### Exit

Every target row has the required implementation and oracle evidence, every supporting row has its
applicable oracle requalification, all retained direct evidence passes, and every excluded row
remains unclaimed.

## 15.C7: Two-stage closure

### Stage 1: implementation PR

The implementation PR:

- contains the complete runtime, oracle, tests, checked docs, closure checker, and CI lane;
- keeps package version `0.3.x`, `internal_alpha = false`, and final registry promotion pending;
- passes every applicable CI job and aggregate `Required`;
- produces a machine-readable candidate artifact from CI containing all required fields;
- is squash-merged without bypass; and
- yields a known implementation merge commit and tree.

### Stage 2: closure-attestation PR

The attestation PR:

- records the implementation merge commit and tree;
- records the exact qualified implementation head, identical tree, PR, CI run, and artifact digest;
- commits exact assertion, fixture, mutation, failure-stage, restart-cut, and guardrail totals;
- adds the final Phase 15.C evidence manifest and closure audit;
- promotes only the allowlisted registry rows with their exact evidence class;
- preserves Phase 15.A/B direct evidence history;
- sets `internal_alpha = true`;
- changes the internal package version to `0.4.0`;
- updates all maturity and limitation documentation;
- keeps `public_release = false` and every exclusion explicit;
- passes all applicable CI and aggregate `Required`; and
- is squash-merged without bypass.

The attestation manifest names the implementation merge commit, not the unknowable attestation
squash commit. The GitHub attestation PR and its CI run provide the audit trail for the final
metadata-only closure change, avoiding self-reference.

### Exit

Merged `main` passes the complete checker and package matrix from a clean checkout, the registry
claims exactly the attested serial internal alpha, and no required work remains inside Phase 15.C.

## Test-file plan

The implementation may refine filenames, but it must retain one discoverable owner per matrix:

- `test/phase15c/test_serial_scheduler.jl`;
- `test/phase15c/test_adaptive_and_iteration.jl`;
- `test/phase15c/test_semantic_rng.jl`;
- `test/phase15c/test_observation_continuation.jl`;
- `test/phase15c/test_failure_checkpoint.jl`;
- `test/phase15c/test_authoring_equivalence.jl`;
- `test/phase15c/test_oracle_differential.jl`;
- `test/phase15c/test_properties_metamorphic.jl`;
- `test/phase15c/test_restart_matrix.jl`;
- `test/specification_oracle/runtests.jl`; and
- `test/specification_oracle/derivations.toml`.

The existing PB0, Phase 15.A, Phase 15.B, and Aqua suites remain required.

## Evidence accounting

Assertion totals are counted by stable assertion identity, not console summary alone. The candidate
artifact and final attestation must reconcile:

- target and supporting features;
- fixture IDs;
- truth-table rows;
- unit and differential assertions;
- property/metamorphic generated cases and seeds;
- registered and killed mutants;
- injected failure stages;
- restart boundaries;
- authoring-form comparisons;
- dependency and source-location checks;
- allocation/performance guardrails; and
- complete CI job identities.

The closure checker recomputes or validates totals from machine-readable ledgers. A manually typed
total without a ledger is not closure evidence.

## Implementation start rule

No Phase 15.C runtime source, oracle, fixture, registry promotion, or closure evidence may be
implemented on the authority of an unmerged draft of this packet. Implementation begins at 15.C1
only after the complete 15.C0 packet is merged to `main` and the entry checker passes from that
merged tree.

Disposition: the 15.C0 entry packet merged as PR #23, implementation PR #24 passed C1--C6 and
Required CI, and closure-attestation PR #25 completed C7. The rule is retained to document the
provenance discipline used by the completed phase.
