# Process-Bigraph Runtime and Parallel-Roadmap Owner Interview

Status: Complete; all 48 owner decisions resolved

Date: 2026-07-26

Post-interview disposition: [Decision 0035](../../spec/decisions/0035-wang-sequential-gpu-disposition.md)
later retired assembled Wang GPU qualification and opened G4. The G3-C answer text below is retained
as the historical owner record and no longer defines the current Potts gate.

This interview follows the
[Process-Bigraph runtime parity and parallel-development audit](process-bigraph-runtime-parity-and-parallel-development-audit.md).
It determines the product, semantic, migration, and roadmap choices required before changing the
project charter, package architecture, Phase 14 exit sequence, or later phases.

The audit's technical non-regression obligations are not optional answers:

- preserve frozen Phase 13 and attested G3-B behavior;
- keep the new runtime free of Potts dependencies;
- retain a deterministic serial semantic oracle;
- keep Dagger beneath the scientific scheduler and commit protocol;
- pin every parity claim to exact upstream revisions;
- expose placement, residency, synchronization, and transfers;
- fail before mutation when a declared capability cannot execute; and
- use differential reference execution as test evidence rather than a production dependency.

Reply with selections such as `1A, 2A, 3B`. `A for all` is valid within one round. Option A is the
audit recommendation in every question. The interview should proceed one round at a time so later
answers can be refined using earlier decisions.

## Accepted owner answers

### Round 1: Product identity and parity authority

On 2026-07-26, the project owner selected:

1. **A, with monorepo incubation.** The general runtime is the long-term platform and Potts is its
   flagship spatial-modeling adapter. The runtime must first develop as an independently valid
   package under `lib/`.
2. **A.** Parity means feature and observable behavioral parity through idiomatic Julia APIs, not
   Python spelling or internal organization.
3. **A.** The first parity authority is an exact pinned Process-Bigraph and Bigraph-Schema source
   revision, advanced only through qualification.
4. **A, with independent authority.** Upstream paper/code/test discrepancies receive heavily
   researched, versioned Julia semantic decisions developed by this project. Eran Agmon is not a
   design dependency or delegated semantic authority.
5. **C.** Vivarium 1.x compatibility is outside the parity target. The runtime targets the pinned
   Process-Bigraph 2.0 baseline.
6. **C.** Development proceeds independently. The project may present the completed or
   near-release work to Eran, but it does not require his review to design or implement the runtime.

### Round 2: Package, repository, and public boundaries

7. **A, resolved by the owner's Question 1 qualification.** The runtime begins as an independently
   valid package under `lib/` in the existing monorepo. A later repository split remains a separate
   release decision.
8. **A.** `ProcessBigraphs.jl` has no domain dependency; CorePotts depends on it; PottsToolkit
   depends on both when it directly uses both contracts.
9. **A.** `ProcessBigraphs.jl` owns paths, ports, state schemas, processes, deltas, clocks, and
   composites. CorePotts owns Potts laws, storage, workspaces, kernels, spatial roles, and
   algorithms.
10. **A.** PottsToolkit retains biological façades and lowers generic composition into
    `ProcessBigraphs.jl`.
11. **C.** `ProcessBigraphs.jl` is not independently released until complete pinned parity has
    passed. It may remain an independently valid internal package throughout development.
12. **B.** The package name is `ProcessBigraphs.jl`.

### Round 3: Time, processes, steps, and scheduling

On 2026-07-26, the project owner selected A for Questions 13--18:

13. imminent-event execution is normative; due processes read state committed through their event
    time, while deferred sample-and-hold may exist only as an explicit pinned compatibility mode;
14. forced partial advancement passes actual elapsed time, and processes may reject partial
    intervals through their declared capability;
15. processes due simultaneously read one common pre-commit snapshot and publish only through
    deterministic delta reconciliation;
16. temporal `Process` and zero-time ordered/reactive `Step` remain distinct concepts over shared
    port, delta, failure, and executor machinery;
17. undeclared workflow cycles are invalid; iteration requires an explicit versioned iterative,
    fixed-point, or solver construct; and
18. global logical time is exact, preferring normalized integer ticks and a declared scale. Rational
    durations may be normalized during compilation. Process implementations receive an appropriate
    elapsed scalar, so exact scheduling does not burden GPU kernels.

The accepted Dagger boundary is: `ProcessBigraphs.jl` selects logical batches, snapshots, merge
order, commits, and structural barriers; Dagger may place and concurrently compute the already
selected batch.

### Round 4: State, ports, deltas, and topology

On 2026-07-26, the project owner selected A for Questions 19--24:

19. runtime state is a versioned hierarchical store with immutable committed snapshots and
    specialized physical storage;
20. schemas are structural with optional nominal identities and independently describe type, shape,
    units, ownership, conservation, update/division behavior, persistence, and residency;
21. processes use typed input/output ports wired through stable hierarchical paths, with distinct
    place and link topology views;
22. processes publish only typed deltas or structural requests; optimized kernels may mutate
    engine-owned transaction buffers but never committed state directly;
23. the update system is a small versioned built-in algebra plus an open law-declared protocol whose
    operators declare associativity, commutativity, identity, conflicts, device support,
    persistence, and division behavior; and
24. the first stable structural set is add, remove, divide, move, and rewire. Merge, engulf, burst,
    and general rewrites require later promotion fixtures.

### Round 5: Persistence, randomness, failure, and observation

On 2026-07-26, the project owner selected A for Questions 25--30:

25. exact restart is first guaranteed at settled commit boundaries; mid-event restart requires
    explicitly serializable pending work;
26. semantic RNG addressing uses process, logical time, event, draw, and lineage identity. Required
    solver RNG state may persist, but task order cannot move semantic streams;
27. every stateful process declares a versioned continuation schema and invalidation rules;
28. a failed event or tick publishes no partial state, returns structured diagnostics, and may
    restart from the last stable commit;
29. the core owns a read-only observer protocol while memory, SQLite, Parquet, dashboards, and
    other emitters are extensions; and
30. exact same-engine/backend replay is required where the process law permits it, executor-order
    invariance is normative, and cross-backend guarantees are honestly classified as numerical or
    statistical when exact replay is unavailable.

### Round 6: GPU, placement, and distributed execution

On 2026-07-26, the project owner selected A for Questions 31--36:

31. the runtime is GPU-native and every process declares its execution capabilities; explicit CPU
    processes remain valid in whole-cell compositions;
32. every cross-residency projection is declared, bounded, measured, and visible during preflight;
    hidden movement fails;
33. Dagger placement may be spiked early, but `DaggerExecutor` cannot qualify until serial batches
    and structural commits stabilize;
34. Dagger tasks operate at coarse process-tick, solver-call, field-advance, or partition-batch
    granularity;
35. distributed execution first provides deterministic fail-stop and checkpoint recovery; retry is
    limited to declared pure, idempotent work; and
36. the runtime core qualifies CPU plus applicable GPU microfixtures while each process family
    publishes its own backend matrix. Existing Potts Metal/ROCm requirements remain until a
    separate accepted decision revises them.

### Round 7: Scientific adapters and whole-cell semantics

On 2026-07-26, the project owner selected A for Questions 37--42:

37. every process declares whether inputs are frozen, interpolated, event-updated, or continuously
    callable during its solver interval;
38. ModelingToolkit is an optional authoring/compiler frontend that lowers to standard SciML process
    adapters and never owns runtime state or scheduling;
39. Catalyst and JumpProcesses are adapted with explicit propensity-cache invalidation and
    rescheduling contracts;
40. COBREXA/JuMP supplies FBA behind pinned optimizer settings and an explicit deterministic
    solution-selection policy such as pFBA or lexicographic objectives;
41. schemas carry units and ontology metadata while state uses canonical numeric payloads; boundary
    validation and conversion do not force unitful values into hot arrays; and
42. SBMLImporter, SBMLFBCModels, and libSBML are adapted behind an exact supported-feature matrix.

### Round 8: Parallel roadmap, migration, release, and presentation

On 2026-07-26, the project owner selected A for Questions 43--48:

43. Wang G3-C continues while `ProcessBigraphs.jl` specifications, the serial runtime, and non-Potts
    fixtures begin in isolated paths;
44. the first field-model slice may finish on the existing executor when necessary, while its
    generic adapter is co-designed but not frozen before the field evidence closes;
45. migration is a strangler process using old/new serial differential execution and
    one-slice-at-a-time cutover;
46. `ProcessBigraphs.jl` uses an internal alpha for serial static composites and an internal beta
    for dynamic hierarchy plus the Potts adapter. Its first public release requires complete pinned
    parity and a whole-cell-style composite;
47. whole-cell acceptance proceeds through a Julia biochemical/FBA composite, selected vEcoli
    slices, well-stirred Syn3A, a full vEcoli generation, and population/environment composition
    with PottsToolkit; and
48. documentation and conformance evidence are required in every phase. Development is independent,
    presentation to Eran occurs near release, and a repository split is considered only after the
    first complete parity release.

## Round 1: Product identity and parity authority

### 1. Long-term product center

- **A — General runtime with Potts as flagship adapter (recommended).** The new runtime becomes the
  general compositional platform; CorePotts is its highest-performance spatial process family and
  PottsToolkit remains the biological CPM authoring environment.
- **B — Two equal products.** PottsToolkit and the runtime remain peers with no declared long-term
  center.
- **C — Potts remains the platform.** The general runtime stays a Potts-adjacent satellite.

### 2. Meaning of parity

- **A — Feature and observable behavioral parity with Julia-native APIs (recommended).** Match
  runtime capability and tested behavior without copying Python spelling or internal organization.
- **B — Feature, behavior, and close API similarity.** Julia names and composition follow upstream
  concepts wherever practical.
- **C — Capability inspiration only.** No formal parity claim or differential gate.

### 3. First parity authority

- **A — Exact pinned Process-Bigraph and Bigraph-Schema commits (recommended).** Begin with the
  candidate 2026-07 commits from the audit and move the pin only through a qualification change.
- **B — Latest tagged releases.** Follow tags without recording exact transitive source commits.
- **C — Upstream `main`.** Continuously target the newest source.

### 4. Paper/implementation discrepancies

- **A — Versioned Julia semantic decision with compatibility fixtures (recommended).** Study the
  paper, code, tests, and Eran's guidance; choose one normative mode and preserve differing upstream
  behavior only through an explicit compatibility mode when valuable.
- **B — Current implementation wins.** Reproduce executable behavior including known quirks.
- **C — Paper wins.** Implement stated intent even when the current engine differs.

### 5. Legacy Vivarium 1.x scope

- **A — Feature-by-feature disposition (recommended).** Retain legacy behaviors only when still
  required by whole-cell applications or promised by the 2.0 architecture.
- **B — Full legacy superset.** Match current Process-Bigraph plus all Vivarium Core capabilities.
- **C — No legacy scope.** Target only the pinned 2.0 runtime.

### 6. Upstream collaboration

- **A — Early semantic review, later conformance review (recommended).** Present the goal and the
  scheduler/update ambiguity packet to Eran after the first specification, then request review again
  after executable microfixtures.
- **B — Review only after a working prototype.**
- **C — Independent development; present only near release.**

## Round 2: Package, repository, and public boundaries

### 7. Initial repository strategy

- **A — Independent package inside the current monorepo (recommended).** Give it its own UUID,
  project, tests, docs, CI, and release identity; split repositories only after beta.
- **B — Separate repository immediately.**
- **C — Keep it as an internal CorePotts module until mature.**

### 8. Dependency direction

- **A — Runtime → no domain dependency; CorePotts → runtime; PottsToolkit → both as needed
  (recommended).**
- **B — PottsToolkit supplies the adapter and CorePotts remains unaware of the runtime.**
- **C — A small shared-protocol package sits beneath both runtime and CorePotts.**

### 9. Ownership of generic semantic values

- **A — Runtime owns state/path/port/process/delta/time/composite contracts (recommended).**
  CorePotts owns Potts state, laws, kernels, workspaces, spatial roles, and algorithm identities.
- **B — CorePotts retains generic state/process contracts and the runtime reuses them.**
- **C — Duplicate public semantic values with conversion between packages.**

### 10. PottsToolkit authoring relationship

- **A — PottsToolkit keeps biological façades and lowers generic composition into the runtime
  (recommended).**
- **B — PottsToolkit re-exports the runtime's generic API as its primary coupled-model surface.**
- **C — PottsToolkit and the runtime expose separate model-authoring systems.**

### 11. Release identity

- **A — Independent versions from the first public alpha (recommended).** Monorepo co-location does
  not imply synchronized versions.
- **B — Lock runtime releases to PottsToolkit until 1.0.**
- **C — Do not publish the runtime separately until full parity.**

### 12. Package name

- **A — Use a neutral Julia name selected after naming research (recommended).** Describe
  Process-Bigraph parity in documentation without implying upstream ownership or certification.
- **B — Use `ProcessBigraphs.jl` directly.**
- **C — Keep a Potts-family name.**

## Round 3: Time, processes, steps, and scheduling

### 13. Normative multirate scheduler

- **A — Imminent-event execution from current committed state (recommended).** At the minimum next
  time, due processes read the state committed through that time and advance by the declared elapsed
  interval. Offer upstream deferred sample-and-hold only if application parity requires it.
- **B — Reproduce deferred sample-and-hold as the primary mode.**
- **C — Make both modes equal first-class contracts from the start.**

### 14. Forced partial final intervals

- **A — Pass actual elapsed time, with a process capability to reject partial advancement
  (recommended).**
- **B — Always pass the nominal interval, matching current upstream behavior.**
- **C — Never force partial completion; stop at the previous settled event.**

### 15. Same-time process visibility

- **A — One common pre-commit snapshot for a simultaneous batch (recommended).**
- **B — Stable sequential visibility ordered by priority and identity.**
- **C — Let the executor choose visibility when no dependency is declared.**

### 16. Processes versus steps

- **A — Retain distinct temporal processes and zero-time ordered/reactive steps (recommended),**
  implemented over shared port, delta, and commit primitives.
- **B — Represent steps as zero-duration processes with one public protocol.**
- **C — Keep workflows outside the core scheduler.**

### 17. Workflow cycles

- **A — Reject undeclared cycles; permit only an explicit versioned iterative/fixed-point construct
  (recommended).**
- **B — Break cycles by stable priority as current upstream code can do.**
- **C — Permit cycles and run until no update changes.**

### 18. Exact time representation

- **A — Exact rational or normalized integer logical time with declared unit mapping
  (recommended).**
- **B — Floating-point time plus stable tolerance and tie rules.**
- **C — User-selected time type per model without one canonical representation.**

## Round 4: State, ports, deltas, and topology

### 19. Runtime state abstraction

- **A — Versioned hierarchical store with immutable committed snapshots and specialized physical
  storage (recommended).**
- **B — Persistent immutable tree copied or structurally shared at every commit.**
- **C — Mutable hierarchical dictionary with schema validation.**

### 20. Schema policy

- **A — Structural schemas plus optional nominal identities (recommended).** Shape, type, units,
  owner, conservation, update, division, persistence, and residency metadata are independently
  inspectable.
- **B — Nominal registered schema types only.**
- **C — Structural Julia types without a runtime schema layer.**

### 21. Port and topology model

- **A — Typed input/output ports wired through stable hierarchical paths, with separate place and
  link views (recommended).**
- **B — Direct state-path read/write declarations without named ports.**
- **C — Ports exist only in external adapters; Julia processes receive state objects directly.**

### 22. Process effects

- **A — Processes return typed deltas or declared structural requests exclusively (recommended).**
  Optimized in-place kernels may operate on engine-owned transaction buffers but cannot publish
  state directly.
- **B — Permit either deltas or direct mutation as equal public modes.**
- **C — Use mutation plus read/write declarations; add deltas only for distributed execution.**

### 23. Update algebra

- **A — Small versioned built-in algebra plus an open, law-declared extension protocol
  (recommended).** Every operator declares associativity, commutativity, identity, conflict, device,
  persistence, and division behavior.
- **B — Freeze the full upstream update set before alpha.**
- **C — Allow arbitrary user merge functions without algebraic metadata.**

### 24. Structural rewrite scope

- **A — Stabilize add/remove/divide/move/rewire first, then promote merge/engulf/burst/general
  rewrite through fixtures (recommended).**
- **B — Require every paper-claimed rewrite before the first beta.**
- **C — Stabilize only add/remove/divide for 1.0.**

## Round 5: Persistence, randomness, failure, and observation

### 25. Checkpoint boundary

- **A — Exact settled-commit restart first; mid-event restart only after pending work is explicitly
  serializable (recommended).**
- **B — Arbitrary mid-tick restart is required from alpha.**
- **C — Completed experiment checkpoints only; process-local continuation is optional.**

### 26. Randomness

- **A — Engine semantic RNG addressing with process/time/event/draw and lineage identity
  (recommended).** Adapters may retain solver RNG state when required, but task order must not move
  semantic streams.
- **B — Each process owns an independently seeded conventional RNG.**
- **C — Match upstream NumPy RNG behavior for parity.**

### 27. Process continuation

- **A — Every stateful process declares a versioned continuation schema and invalidation rules
  (recommended).**
- **B — Serialize the process object when possible and document exceptions.**
- **C — Restart stateful numerical processes from the last visible state.**

### 28. Failure model

- **A — Fail-stop event/tick with no published partial state, structured diagnostics, and restart
  from the last stable commit (recommended).**
- **B — Best-effort rollback of all process side effects.**
- **C — Preserve upstream exception behavior initially and harden later.**

### 29. Observation and emitters

- **A — Read-only observer protocol in core; storage emitters are extensions (recommended).**
- **B — Memory, SQLite, and Parquet emitters all belong in core.**
- **C — Observation remains PottsToolkit/SciML responsibility rather than runtime responsibility.**

### 30. Replay promise

- **A — Exact same-engine/same-backend replay where laws permit, executor-order invariance, and
  explicitly classified cross-backend numerical/statistical equivalence (recommended).**
- **B — Exact replay across CPU, GPU, threads, and distributed execution.**
- **C — Seeded statistical reproducibility only.**

## Round 6: GPU, placement, and distributed execution

### 31. GPU support policy

- **A — GPU-native runtime and capability-declared processes (recommended).** Qualify suitable
  built-ins on named devices; permit explicit CPU processes in whole-cell composites.
- **B — Every stable process must support CPU, Metal, and ROCm as in Phase 14.**
- **C — GPU support is adapter-specific and outside the runtime contract.**

### 32. Transfer policy

- **A — Every cross-residency projection is declared, bounded, measured, and visible in preflight
  (recommended); hidden movement fails.**
- **B — Allow automatic transfers below a configurable size threshold.**
- **C — Let the executor move data automatically and report transfers afterward.**

### 33. Dagger timing

- **A — Spike placement early but qualify `DaggerExecutor` only after serial batches and structural
  commits stabilize (recommended).**
- **B — Develop serial and Dagger executors together from the first runtime slice.**
- **C — Defer Dagger until feature parity is otherwise complete.**

### 34. Dagger granularity

- **A — Coarse process tick, solver call, field advance, or partition batch (recommended).**
- **B — Let each adapter select arbitrary task granularity.**
- **C — Compile the entire simulation into one long-lived Dagger streaming graph.**

### 35. Distributed failure

- **A — Deterministic fail-stop and checkpoint recovery first; bounded retry only for declared pure
  idempotent work (recommended).**
- **B — Automatic retry is required for all process tasks.**
- **C — Any worker failure terminates the experiment without runtime recovery.**

### 36. Hardware release tiers

- **A — Runtime core qualifies CPU plus available GPU microfixtures; each process family publishes
  its own backend matrix (recommended).** Preserve Metal/ROCm requirements for the current Potts
  portfolio until separately revised.
- **B — CUDA and ROCm become mandatory for runtime 1.0; Metal is secondary.**
- **C — Reuse the Potts CPU/Metal/ROCm matrix for every runtime release.**

## Round 7: Scientific adapters and whole-cell semantics

### 37. Inputs during a solver interval

- **A — Every process declares frozen, interpolated, event-updated, or callable input semantics
  (recommended).**
- **B — Inputs are frozen over each process interval by default without declaration.**
- **C — Adapters decide and document input behavior independently.**

### 38. ModelingToolkit role

- **A — Optional authoring/compiler frontend lowering to SciML process adapters (recommended).**
- **B — ModelingToolkit systems are first-class runtime graph nodes.**
- **C — Defer ModelingToolkit until after parity.**

### 39. Reaction and jump processes

- **A — Adapt Catalyst/JumpProcesses with explicit propensity-cache invalidation and rescheduling
  contracts (recommended).**
- **B — Implement a small native SSA runtime before adapting SciML.**
- **C — Restrict the first whole-cell program to deterministic reactions.**

### 40. FBA policy

- **A — Adapt COBREXA/JuMP with a pinned optimizer/settings contract and explicit deterministic
  solution-selection mode such as pFBA or lexicographic objectives (recommended).**
- **B — Permit any optimizer and accept any optimal flux solution.**
- **C — Defer FBA until after full process-runtime parity.**

### 41. Units and biological metadata

- **A — Units and ontology metadata in schemas with canonical numeric payloads (recommended).**
  Validate and convert at boundaries; do not force unitful scalar types into hot arrays.
- **B — Use unitful values throughout runtime state.**
- **C — Treat units as documentation only until whole-cell porting.**

### 42. Standards import

- **A — Adapt SBMLImporter/SBMLFBCModels/libSBML behind an explicit support matrix
  (recommended).**
- **B — Implement only the SBML features needed by the first flagship.**
- **C — Defer standards import; port models directly to Julia.**

## Round 8: Parallel roadmap, migration, release, and review

### 43. Immediate parallel start

- **A — Continue G3-C while beginning runtime specification, serial core, and non-Potts fixtures in
  isolated paths (recommended).**
- **B — Finish G3-C before creating runtime code.**
- **C — Pause G3-C and prioritize the runtime.**

### 44. First field-model slice

- **A — Allow it to finish on the existing executor if necessary, while co-designing but not
  freezing the generic field adapter (recommended).**
- **B — Require the field model to be the first new-runtime Potts cutover.**
- **C — Complete and freeze the field API in CorePotts before runtime work uses it.**

### 45. Migration strategy

- **A — Strangler migration with old/new serial differential execution and one-slice-at-a-time
  cutover (recommended).**
- **B — One planned flag-day replacement after the new serial runtime passes generic tests.**
- **C — Keep both runtimes indefinitely as supported alternatives.**

### 46. First public milestones

- **A — Alpha: serial static composites; beta: dynamic hierarchy plus Potts adapter; 1.0: pinned
  parity matrix and whole-cell-style composite (recommended).**
- **B — Publish nothing until full parity and Dagger qualification.**
- **C — Publish a scheduler-only alpha before state/topology semantics stabilize.**

### 47. Whole-cell acceptance ladder

- **A — Julia biochemical/FBA composite → selected vEcoli slices → well-stirred Syn3A → full vEcoli
  generation → population/spatial composition (recommended).**
- **B — Port vEcoli end to end immediately after the serial runtime.**
- **C — Use only independent Julia models; do not port Vivarium applications.**

### 48. Documentation, review, and repository split

- **A — Documentation and conformance evidence are required in every phase; ask Eran for semantic
  review before implementation freeze; split repositories only after beta (recommended).**
- **B — Consolidate documentation and external review near 1.0; keep the monorepo permanently.**
- **C — Split repositories immediately and let each package document independently.**

## Required post-interview work

All rounds are answered. The following work remains:

1. record accepted choices and unresolved external questions;
2. resolve upstream semantic ambiguities through independent source studies and versioned decisions;
3. revise the project charter and repository architecture;
4. create a versioned runtime semantic specification and parity registry;
5. redesign the remaining roadmap into parallel Potts, runtime, adapter, and evidence workstreams;
6. correct stale G3-B status text;
7. add contract checkers before implementation; and
8. begin only the workstreams admitted by the revised gates.
