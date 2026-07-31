# Symbolic Potts V1 Execution-Control Audit

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: owner-accepted execution-control audit; requirements consolidated into CCV1-021 through
CCV1-023; no production implementation is authorized

## Owner disposition

On 2026-07-30, the owner accepted all recommendations in this audit.

Acceptance means:

- the two neutral downstream fixtures are required;
- G0 through G9 are the sole authoritative execution order;
- progressive GPU qualification and the four independent review boundaries are required;
- gate failure, architecture invalidation, owner blockers, and recovery checkpoints have distinct
  meanings;
- the older SPV1, ACV1, and ARV1 implementation lists are superseded only for ordering; and
- this is execution-control authority, not the explicit production implementation send-off.

## Purpose

This audit asks whether the accepted V1 specification can control one autonomous implementation
phase safely, especially at the compiler, checkerboard, relationship, GPU, scientific-model, and
clean-break boundaries.

It evaluates:

- which document owns implementation order;
- whether every dangerous architectural decision is tested before dependent work;
- how a failed foundational gate routes work backward;
- where independent review adds real protection;
- how implementation can retain recoverable checkpoints without creating an evidence system; and
- whether the controls remain normal for a Julia library.

The audit does not add another product phase, owner approval round, CI subsystem, compatibility
layer, documentation task, or implementation authorization.

## Executive finding

The V1 scientific and compiler specifications are strong enough for autonomous implementation.
The execution-control layer is not yet optimal.

The current highest-authority order in CCV1-022 is substantially better than the older vertical
slice plans. It correctly requires:

- semantic-test extraction before deletion;
- host analysis before runtime construction;
- an evidence-selected evaluator;
- a neutral external term before proof models;
- generic engines and relationships before biological mechanisms;
- complete old-path deletion; and
- a terminal source/API audit.

Five execution risks remain:

1. lower-authority documents still display different implementation sequences;
2. the neutral downstream term is treated as a late pass/fail event instead of a progressive
   vertical slice used from the first descriptor gate;
3. the current external term proves ordinary site-state extensibility but does not independently
   prove relationship-state/request/lifecycle extensibility;
4. GPU functional evidence arrives after too much layout and concurrency code can accumulate; and
5. the specification does not define independent reviewer boundaries, finding severity, or a
   lightweight recovery/checkpoint protocol.

The best correction is small:

- amend CCV1-021 with one neutral external relationship fixture;
- replace CCV1-022's linear list with one authoritative ten-gate dependency graph in which the
  existing external fixture is introduced early and qualified progressively;
- amend CCV1-023 with failure routing, four fresh-context read-only reviews, and recoverable Git
  checkpoints; and
- mark older implementation orders as superseded for execution ordering.

No additional statistical tests, CI jobs, evidence ledgers, or owner gates are needed.

## Audited authority

Execution authority currently resolves in this order:

1. [`spec/symbolic-potts-v1-compiler-construction.md`](../../spec/symbolic-potts-v1-compiler-construction.md);
2. [`spec/symbolic-potts-v1-architecture-redirection.md`](../../spec/symbolic-potts-v1-architecture-redirection.md);
3. [`spec/symbolic-potts-v1-consolidation.md`](../../spec/symbolic-potts-v1-consolidation.md);
4. [`spec/symbolic-potts-v1.md`](../../spec/symbolic-potts-v1.md); and
5. compatible scientific specifications and historical evidence.

CCV1-022 and CCV1-023 therefore govern autonomous implementation order, stopping, and exit. The
older sequences remain useful as requirement inventories but should not be consulted as executable
plans.

## What is already controlled well

### Compiler architecture

CCV1-001 through CCV1-013 define:

- a non-specializing indexed host graph;
- explicit fact tables and deterministic analyses;
- a public semantic/private compiler boundary;
- concrete open descriptors;
- grouping by structural strategy rather than occurrence;
- bounded evaluator selection;
- device-valid operation tags;
- typed state and reusable workspace; and
- no runtime interpreter or named-mechanism central program.

CCV1-024 adds the right implementation alarms: idempotence, algebraic metamorphisms, fixed-`G`
growth, targeted inference, allocation, access-count sentinels, RNG vectors, kernel shapes,
adaptation, downstream loading, and fresh-process package behavior.

### Checkerboard and relationship semantics

CCV1-015 through CCV1-018 define a closed footprint algebra, deterministic realized-domain
coloring, local trackers, bounded requests, canonical conflict resolution, staged verification,
and atomic publication. The specification does not rely on device completion order.

### Scientific confidence

CCV1-025 and CCV1-026 now prefer exact finite-state, analytic, property, and metamorphic tests over
sampling. They bound the proof-model statistical surface to one primary endpoint per model.

### GPU and package scope

CCV1-020 correctly distinguishes interface, compilation, functional, replay, and performance
support. It requires one functional GPU witness through a shared backend-agnostic suite and leaves
the multi-vendor matrix outside ordinary PR CI.

Julia's package manager runs package tests in a fresh Julia process and supports extensions as
separately precompilable conditional modules. KernelAbstractions launches asynchronously, so the
existing requirement to synchronize before observation is necessary. Adapt's structure/storage
separation supports the specification's synthetic-adaptor and real-device tests.

### Scope restraint

The branch still excludes migration, wrappers, documentation, browser QA, Dagger, a third engine,
cross-language execution, and broad literature reproduction. Those exclusions are important
execution controls, not missing work.

## Findings

### EC-001 — Multiple visible implementation orders create avoidable ambiguity

Severity: high

ACV1-021 starts with a public system skeleton and reaches Wortel/Merks before the final CorePotts
extraction. ARV1-020 is architecture-first but redirects PottsToolkit after engines and
relationships. CCV1-022 adds the host graph, evaluator qualification, and downstream fixture.

Normative precedence resolves the conflict, but an autonomous implementer can still mistakenly use
the older lists as parallel obligations or reorder mechanism work to match them.

Recommendation:

- CCV1-022 becomes the sole executable gate graph.
- ACV1-021, ARV1-020, and SPV1-032 remain requirement history and are explicitly superseded only
  for implementation ordering.
- The specification index links the execution-control audit beside the compiler contract.

### EC-002 — The external site term arrives too late as a construction tool

Severity: high

CCV1-021 correctly requires `ExternalWeightedSiteTerm` to pass before proof models. CCV1-022,
however, presents its pass after sequential, checkerboard, trackers, relationships, lifecycle, and
checkpoint construction.

The fixture should be authored as soon as the public registration and descriptor boundary exists,
then qualified progressively:

1. completion/analysis/lowering;
2. grouping and fixed-`G` behavior;
3. sequential CPU execution;
4. checkerboard CPU execution;
5. adaptation/checkpoint/replay; and
6. the functional GPU witness.

This makes the fixture a running architectural probe. A compiler or executor special case becomes
visible immediately rather than after several subsystems have accumulated.

### EC-003 — Relationship extensibility lacks an independent downstream proof

Severity: high

`ExternalWeightedSiteTerm` exercises an external statement, operation, Hamiltonian descriptor,
per-site auxiliary state, workspace, adaptation, checkpoint, and both engines. It does not prove
that an external module can add relationship state, incident access, bounded accepted-copy
requests, lifecycle requests, or payload behavior without a central edit.

Focal-point plasticity cannot supply that proof because it is an accepted proof model and could
quietly shape the relationship runtime.

Recommendation:

Add a test-only `ExternalBoundedPairTerm` or equivalent neutral downstream fixture outside
CorePotts. It should contain:

- typed undirected relationship state with one scalar payload;
- an independently calculable pair contribution that does not use focal distance mechanics;
- bounded incident access;
- at most one accepted-copy create or update request;
- one bounded lifecycle remove request;
- capacity, degree, generation, duplicate, conflict, and canonical-order behavior;
- adaptation and logical checkpoint reconstruction;
- sequential and checkerboard capability rules; and
- functional execution on the selected GPU witness for every relationship kernel family claimed
  `Functional`.

It must require zero edits to CorePotts central program, engines, proposal loop, relationship
commit machinery, descriptor unions, or mechanism switches. It is a compiler/runtime conformance
fixture, not a new user-facing model or literature mechanism.

### EC-004 — GPU evidence should be staged earlier

Severity: high

CCV1-008 already requires available-GPU compilation during evaluator selection, which is good.
CCV1-022 does not make the staged device boundary visible in its implementation order.

The recommended sequence is:

1. compile the evaluator candidates and concrete launch arguments during evaluator selection;
2. obtain a minimal functional GPU execution with the external site term immediately after generic
   checkerboard/adaptation works;
3. qualify the neutral relationship fixture after generic transactions exist; and
4. run every final kernel family and proof-model GPU test required by the claimed `Functional`
   surface at terminal qualification.

This does not create four GPU support claims. It creates one progressively strengthened witness and
prevents device-illegal layout or dispatch choices from surviving until the end.

### EC-005 — Reviewer independence is not specified

Severity: high

The current contracts require audits but do not prevent the implementation author from reviewing
the same assumptions embedded in both code and tests.

The efficient alternative is four read-only, fresh-context reviews at dangerous boundaries, not a
review after every gate:

| Review | Boundary | Independent scope |
|---|---|---|
| R1 compiler | after host IR, descriptor grouping, and evaluator selection | host/device separation, inference, specialization, diagnostics, external lowering |
| R2 execution | after checkerboard, GPU site witness, and neutral relationship fixture | footprints, deterministic commit, transaction atomicity, adaptation, no fallback |
| R3 science | after focal, Wortel, and Merks reconstruction, before deletion | source-qualified equations, stage order, exact microfixtures, statistical calibration |
| R4 terminal | after deletion and ordinary QA | public black-box flow, stale/private APIs, package loading, scope, phase-exit completeness |

Reviewers should receive the authoritative specifications and current diff, but not the
implementer's informal reasoning. They should be different fresh-context agents where available,
must remain read-only, and must cite a normative clause plus concrete code/test evidence for every
blocking finding.

### EC-006 — Gate failure and owner stopping need a sharper distinction

Severity: medium

CCV1-023 correctly says ordinary test failure is not an owner blocker. The phrase “stopping when a
foundational gate fails” can nevertheless be misunderstood as stopping the autonomous phase.

Three outcomes should be distinguished:

1. `GateFailure`: dependent work pauses; implementation repairs the earliest violated abstraction
   autonomously.
2. `ArchitectureInvalidation`: work returns to an earlier checkpoint because a central invariant
   such as fixed-`G`, no fallback, or zero-Core-edit extensibility failed.
3. `OwnerBlocker`: only the existing CCV1-023 contradictions, absent public upstream seam, failed
   evaluator set, impossible external boundary, unavailable functional GPU environment, or
   uncovered material product/scientific choice.

A failed gate never authorizes a local biological special case, weaker checkerboard semantics,
private upstream coupling, host fallback, or a reduced support claim that contradicts the accepted
product.

### EC-007 — Recovery checkpoints are implicit

Severity: medium

The clean break deletes substantial old code. The specification requires test extraction before
deletion but does not define recoverable implementation boundaries.

Recommendation:

- create one intentional Git checkpoint commit at each reviewer boundary and before broad legacy
  deletion;
- keep commits semantically coherent and independently testable;
- record the gate ID and tests run in the commit message or one living implementation-control
  audit;
- never use destructive reset as the ordinary failure response; and
- preserve the read-only `main` clone only for algorithm and test-intent inspection.

This is ordinary branch hygiene, not an evidence ledger. There is no freshness timestamp, renewed
attestation, generated archive, or duplicated CI authority.

### EC-008 — Integration should have an early spine and a final full pass

Severity: medium

CCV1-022 places full SciML/ModelingToolkit/ProcessBigraphs integration after proof-model
reconstruction. The proof models are supposed to demonstrate the public compiler/runtime flow, so
the minimal public spine should be established earlier.

Before proof models:

- one neutral system must complete, compile, construct a problem, initialize, step, solve, index,
  remake, checkpoint, restore, and cross the optional extension boundaries through public APIs.

After proof models:

- the full ModelingToolkit, ModelingToolkitStandardLibrary, Unitful, ProcessBigraphs, MakiePotts,
  fresh-process, and platform matrix runs.

This avoids discovering a foundational public-lifecycle mismatch after the models are complete.

## Recommended authoritative gate graph

These are checkpoints inside one autonomous phase, not separate phases, owner approvals, releases,
or CI workflows.

### G0 — Authority and recovery baseline

Required outcome:

- surviving semantic tests and source-disposition inventory are frozen;
- current dirty-worktree ownership is recorded and unrelated user changes are preserved;
- the specification state has an intentional checkpoint commit;
- old `main` is available read-only only if needed; and
- no production implementation predates explicit owner send-off.

Reviewer: none.

Failure routing: repair inventory/specification mechanically; ask the owner only for a material
unresolved requirement.

### G1 — Host compiler facts

Required outcome:

- frozen source graph, normalized DAG, analyzed facts, diagnostics, and verifiers pass;
- completion/normalization idempotence and provenance tests pass;
- no private ModelingToolkit/Symbolics representation becomes authority; and
- both neutral external fixtures reach analyzed descriptor candidates through public registration.

Reviewer: none; R1 occurs after G2.

Failure routing: return to graph, analysis, schema, or diagnostic construction.

### G2 — Descriptor, grouping, evaluator, state, and workspace boundary

Required outcome:

- descriptor grouping, layouts, handles, state, workspace, adaptation schema, and inspection pass;
- evaluator candidates are measured and one decision is recorded;
- fixed-`G`, expression-growth, inference, device-compilation, and algebra tests pass;
- the external site fixture reaches a complete executable plan; and
- evaluator/device argument compile probes succeed on the available GPU witness.

Reviewer: R1 compiler review.

Failure routing: do not begin runtime or mechanism work; repair the earliest compiler boundary. If
every evaluator candidate fails, invoke the existing owner blocker.

Checkpoint: intentional compiler-boundary commit after R1 blocking findings are cleared.

### G3 — Sequential reference and finite transition authority

Required outcome:

- generic sequential CPU execution uses only descriptor protocols;
- the external site fixture runs through public problem/solve/checkpoint flow;
- finite transition matrices, local/global deltas, rejection atomicity, tracker rebuild, RNG,
  access-count, inference, and allocation gates pass; and
- the minimal SciML/public lifecycle spine works.

Reviewer: none.

Failure routing: distinguish compiler-plan defects from runtime defects and return to G1/G2 when
the plan is wrong.

### G4 — Checkerboard and first functional GPU witness

Required outcome:

- realized coloring, footprint verification, priorities, claims, reductions, and deterministic
  commit pass;
- external site fixture runs on checkerboard CPU;
- kernel boundary/workgroup, adaptation, no-fallback, and deterministic CPU/GPU differential
  fixtures pass; and
- the selected GPU backend reaches `Functional` for the generic site/state/workspace surface.

Reviewer: R2 waits until the relationship surface is added in G5.

Failure routing: return to G2 for device-illegal representation or G4 for kernel/schedule defects.
Do not proceed with a host fallback.

### G5 — Generic trackers, relationships, lifecycle, and checkpoint

Required outcome:

- neutral external relationship fixture passes sequential CPU and checkerboard CPU;
- relationship energy/access is incident-local;
- bounded requests, canonical conflict handling, capacity, degree, generation, rollback,
  lifecycle, checkpoint, and permutation properties pass;
- applicable relationship kernel families execute on the functional GPU witness; and
- neither neutral fixture requires a CorePotts mechanism edit.

Reviewer: R2 execution/concurrency/GPU review.

Failure routing: repair footprint, transaction, state-block, incident-index, or adaptation
protocols. Do not begin focal or other proof-model work.

Checkpoint: intentional execution-boundary commit after R2 blocking findings are cleared.

### G6 — Public integration spine

Required outcome:

- public system/executable/problem/integrator/solution/checkpoint/SII flow is complete;
- namespacing, composition, units, parameters, equations, observations, remake, and extension
  load order pass on neutral fixtures; and
- ProcessBigraphs crosses only the accepted public protocol.

Reviewer: none.

Failure routing: return to the owning public/compiler/runtime boundary. Private upstream coupling is
an owner blocker only when no public seam exists.

### G7 — Proof-model reconstruction and scientific qualification

Required outcome:

- focal, Wortel, and Merks are built only through the generic compiler and public lifecycle;
- exact paper/source-qualified microfixtures pass before their bounded statistics;
- statistical thresholds use separate calibration and frozen validation seeds;
- one primary statistic per model passes; and
- adding any proof model produces no CorePotts mechanism branch or new executor category.

Reviewer: R3 scientific review.

Failure routing: a generic failure returns to G1–G6. A paper/source mismatch is repaired
autonomously when the accepted behavior is unambiguous; two materially different accepted
behaviors invoke the existing owner blocker.

Checkpoint: intentional scientific-boundary commit after R3 blocking findings are cleared.

### G8 — Clean break and complete integration

Required outcome:

- named-mechanism, obsolete engine, compatibility, oracle, old checkpoint, and superseded paths are
  removed only after replacement authority passes;
- all packages load without forbidden dependencies or broad re-exports;
- the complete in-scope integration and platform matrix passes; and
- stale-name, Aqua, ExplicitImports, fresh-process, allocation, specialization, and source audits
  pass.

Reviewer: none.

Failure routing: restore or repair from the pre-deletion checkpoint without reviving dual runtime
authority.

Checkpoint: intentional clean-break commit.

### G9 — Terminal qualification

Required outcome:

- all CCV1-023 phase-exit conditions pass;
- all shared backend-agnostic functional tests pass on the selected witness;
- full ordinary Julia CI is green without freshness or documentation gates;
- one public black-box authoring-through-solution run passes in a fresh process;
- final audit records source disposition, public surface, scientific coverage, performance limits,
  backend support level, and deferred documentation; and
- implementation completion is reported without merging or publishing.

Reviewer: R4 fresh-context terminal review.

Failure routing: reopen the earliest owning gate. A terminal review is not permission to patch over
an earlier invariant.

Checkpoint: final implementation commit only after R4 blocking findings are cleared.

## Reviewer contract

### Independence

A reviewer:

- did not author the slice under review;
- receives the accepted specifications, gate definition, diff, and test commands;
- does not receive informal implementation rationale as authority;
- reads production and test code;
- remains read-only; and
- reports findings without expanding V1 scope.

### Finding classes

| Class | Meaning | Disposition |
|---|---|---|
| P0 | scientific corruption, data loss, nondeterministic integrity failure, or direct contradiction | blocks the gate and returns to the owning abstraction |
| P1 | compiler invariant, extensibility, GPU legality, concurrency, replay, or public-boundary failure | blocks the gate and returns to the owning abstraction |
| P2 | localized correctness, diagnostics, tests, maintainability, or package-quality defect within accepted scope | fixed autonomously before G9 |
| P3 | optional improvement, style, or future-scope suggestion | recorded only if useful; never blocks V1 |

Every P0–P2 finding must cite:

- the exact normative clause;
- the smallest relevant code location;
- a reproducer, failing test, or static proof;
- the violated invariant; and
- the earliest gate that owns the repair.

A reviewer cannot turn a preference into a requirement, demand a deferred product, or weaken an
accepted invariant. A genuine uncovered scientific/product choice is escalated through CCV1-023.

## Failure-routing rules

| Symptom | Return to |
|---|---|
| missing/incorrect compiler fact or provenance | G1 |
| `G` grows with repeated occurrences, evaluator/device arguments are abstract | G2 |
| local delta/transition/RNG semantics wrong | G1–G3 according to first wrong artifact |
| access becomes whole-lattice/whole-graph | G2 or G5 |
| checkerboard outcome depends on device completion or proposal order | G4 |
| device-invalid layout, host fallback, scalar indexing | G2 or G4 |
| relationship mutation is unbounded, noncanonical, or partially published | G5 |
| public MTK/SciML/extension lifecycle fails | G6 |
| proof model needs a CorePotts special case | G1, G2, or G5 |
| paper/source truth table disagrees with implementation | G7 |
| old and new runtime authorities coexist | G8 |
| final black-box/package failure | earliest owning gate, never only G9 |

## Architecture-invalidating alarms

Dependent mechanism work must stop immediately and return to an earlier gate if:

- a named biological field, branch, enum, union, or switch enters CorePotts;
- repeated occurrences create per-occurrence evaluator/kernel specializations;
- a local hot path scans unrelated lattice or relationship state;
- the evaluator needs runtime opcode dispatch or an abstract device call;
- a checkerboard winner depends on execution completion order;
- relationship requests cannot be bounded before launch;
- a rejected or failed transaction partially publishes;
- the external site or relationship fixture requires a central CorePotts edit;
- GPU execution uses host fallback or scalar indexing;
- a scientific expectation is calculated by calling the production mechanism under test; or
- obsolete runtime authority is deleted before its independent replacement passes.

These are autonomous repair events, not reasons to weaken the specification.

## Lightweight implementation-control record

One living
`design/audits/symbolic-potts-v1-implementation-control.md` should be created only after explicit
implementation send-off. It should contain:

- gate state: `pending`, `in_progress`, `passed`, or `reopened`;
- exact tests or static checks that establish the gate;
- the intentional checkpoint commit;
- unresolved P2 findings;
- reviewer result where required; and
- the earliest gate reopened by a later regression.

It must not contain:

- freshness deadlines;
- renewed attestations;
- copied CI logs;
- expected-output archives;
- hardware ledgers;
- hashes that require manual renewal;
- duplicate vendor suites; or
- a second definition of scientific semantics.

At G9 it becomes input to the final implementation audit and may then remain historical.

## Official engineering basis

The execution controls are consistent with:

- [Julia package testing and extension behavior](https://pkgdocs.julialang.org/dev/creating-packages/);
- [KernelAbstractions launch and synchronization semantics](https://juliagpu.github.io/KernelAbstractions.jl/stable/quickstart/);
- [Adapt structure/storage adaptation](https://github.com/JuliaGPU/Adapt.jl); and
- [SciMLStyle package, downstream, and GPU guidance](https://docs.sciml.ai/SciMLStyle/).

## Alternatives considered

### Review every gate

Rejected. It creates context switching and encourages reviewers to relitigate private
implementation details. Four dangerous-boundary reviews provide better independence per unit cost.

### Review only at the end

Rejected. Host/device, specialization, and relationship mistakes would already be embedded in the
proof models and deletion work.

### Use Wortel or focal as the extensibility proof

Rejected. A built-in proof model cannot demonstrate downstream extensibility and can shape the
executor around itself.

### Use the old `main` runtime as an oracle

Rejected. It would preserve old bugs and architecture, conflict with the clean break, and recreate
parity infrastructure.

### Add a gate-specific CI workflow and evidence artifact

Rejected. Ordinary `Pkg.test`, focused integration entry points, local GPU qualification, and
intentional commits are sufficient.

### Require browser QA

Rejected for this branch. User documentation is excluded; the correct terminal experience test is
fresh-process black-box Julia API QA. Browser QA belongs to the later documentation phase.

### Develop proof models in parallel with the compiler

Rejected before G5. Their semantics may inform fixtures and tests, but production lowering before
the external site and relationship boundaries pass would cement the mechanisms into architecture.
After G5, proof-model reconstruction may proceed in parallel where files and semantic dependencies
do not overlap.

## Normative consolidation

The accepted consolidation makes four focused specification edits:

1. CCV1-021 includes the neutral external relationship fixture;
2. CCV1-022 defines G0–G9 and progressive external/GPU qualification;
3. CCV1-023 defines gate-failure versus owner-blocker routing, reviewer boundaries, finding
   classes, and checkpoint requirements; and
4. ACV1-021, ARV1-020, and SPV1-032 are superseded only for execution ordering.

CCV1-024 through CCV1-026 remain unchanged. Their test authority is already sufficient.

## Audit conclusion

The current V1 specification is implementation-grade, but its safest autonomous execution path is
not merely “follow the fourteen steps.” The compiler, external extension boundary, GPU legality,
relationship language, and scientific fixtures must progressively prove one another before broad
deletion.

With the four focused amendments above, the phase would have:

- one authoritative gate graph;
- two neutral downstream extensibility proofs;
- early device-risk discovery;
- four independent read-only reviews;
- explicit autonomous failure routing;
- recoverable checkpoints;
- one living control record rather than an evidence system; and
- no additional owner oversight between send-off and completion.

That is the strongest hedge available without turning V1 into the kind of CI and qualification
bureaucracy this consolidation was designed to remove.
