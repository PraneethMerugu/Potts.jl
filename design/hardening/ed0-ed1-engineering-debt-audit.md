# ED-0/ED-1 engineering-debt audit

Status: ED-0 and bounded ED-1 complete; ED-R0 passed on exact product commit
`da80a0ec1f6b52321973872066e02632124ec0f4`

Date: 2026-08-13

Baseline commit: `a049b464b224a47fc4a695338f54db443493d737`

Baseline tree: `079cf8ba4a84d818f138916b178b0330447c7c71`

Scope: `LocalWorksets`, `CorePotts`, and `PottsToolkit`. `MakiePotts` is not
part of this three-package pass. The sealed LW-4 product and evidence remain
historical authority; this audit does not rewrite or broaden them.

## Decision

A bounded ED-1 pass should precede substantive LW-5 migration. It should fix
confirmed interface/dispatch defects, close the two carried LocalWorksets
diagnostic findings, make the standalone package visible to ordinary CI, and
remove stale milestone language from living user surfaces. It should not
delete parity oracles, remove the legacy resolved lowering, redesign an API,
consolidate cross-package adapters, or optimize kernels speculatively.

ED-0 found **no production file, dependency, extension, or empty directory
that is safe to delete now**. Every direct dependency is referenced, every
active production source file is included, all public names have docstrings,
and the active package roots contain no empty directories. Apparent execution
duplication is currently either a qualified specialization, a domain adapter,
or a direct/reference oracle until LW-5 proves otherwise.

The highest-priority findings are correctness and process debt, not line
count:

1. four public SymbolicIndexingInterface `Colon` call shapes are actually
   ambiguous;
2. CorePotts' empty tracker recursion is actually ambiguous, and two accepted-
   copy dispatch intersections remain latent;
3. LocalWorksets has the two preserved P2 diagnostic defects;
4. LocalWorksets is absent from the repository package-test CI matrix; and
5. living README/contributor status still describes the pre-LW-4 repository.

## Baseline inventory

Physical lines are debt signals, not deletion targets.

| Package boundary | Production files | Production lines | Test files | Test lines |
|---|---:|---:|---:|---:|
| PottsToolkit root | 70 `src` + 5 extension | 24,043 + 2,196 | 44 root + 10 integration | 12,040 + 2,213 |
| CorePotts | 53 | 23,218 | 21 | 5,127 |
| LocalWorksets | 23 | 9,112 | 9 | 4,497 |

Public-surface probe on this baseline:

| Package | Exported | Public-only | Undocumented public names |
|---|---:|---:|---:|
| PottsToolkit | 272 | 76 | 0 |
| CorePotts | 1 | 37 | 0 |
| LocalWorksets | 22 | 1 | 0 |

Fresh-process, already-precompiled import observations on this Mac were:

| Package | Seconds | Julia allocations |
|---|---:|---:|
| PottsToolkit | 4.490 | 567,912,296 bytes |
| CorePotts | 0.220 | 32,816,400 bytes |
| LocalWorksets | 0.223 | 25,954,464 bytes |

These are one diagnostic observation under concurrent local measurement, not
compile-time or performance gates. ED-1 records the same probe after cleanup
and investigates a material regression; it does not optimize to these numbers.

## Package findings

### LocalWorksets

Strengths to preserve:

- zero package-owned ambiguities under the exact probe;
- 23 documented public names and a small exported lifecycle;
- standalone dependency direction with no CorePotts, PottsToolkit, MTK, SciML,
  RNG, clock, checkpoint, or solver dependency;
- vendor-neutral execution/provider source, with Metal appearing only in
  isolated reviewed qualification metadata; and
- common validation, topology, workspace, evidence, arbitration, lifetime,
  and KernelAbstractions ordering authorities already consolidated.

Bounded ED-1 debt:

- missing generic `resolved(...; maximum=...)` falls through to the legacy
  constructor and reports `legacy resolved output requires capacity`;
- duplicate resolved semantic identities and competing independent writers
  fail closed but do not populate stable structured diagnostic fields; and
- nine living source messages/comments still describe the implementation as
  an `LW-1` profile rather than naming the actual bounded contract.

Deferred debt:

- `masked`, the named-family descriptor, flat topology, legacy workspace, and
  four-launch resolved lowering remain one compatibility unit. They may be
  removed only after the already accepted generic-parity, zero-consumer,
  CPU/Metal, launch/allocation, performance, and warned-release criteria pass.
- the private conjunctive mechanism remains required by CorePotts' two-owner
  claim and is not generalized or deleted in ED-1.

### CorePotts

Strengths to preserve:

- the package-level boundary is narrow and MTK-free;
- LocalWorksets is reached through public lifecycle values plus a deliberately
  trusted Core-owned adapter;
- direct checkerboard execution remains an independent scientific and
  performance oracle; and
- RNG, acceptance, canonical Hamiltonian folding, settlement, lifecycle,
  checkpoints, and failure authority remain outside LocalWorksets.

Bounded ED-1 debt:

- `Test.detect_ambiguities(CorePotts, Base; recursive=true)` reports 167 total
  dependency-closure intersections, of which exactly three contain a
  CorePotts-owned method;
- `_tracker_value_after` has an actual ambiguous empty-tuple call between
  `tracker_plan_runtime.jl:140` and `:174`, so an unavailable quantity can
  produce `MethodError` instead of the intended `ArgumentError`;
- two `descriptor_apply_stage!` intersections at `stage_runtime.jl:322` versus
  `:337`/`:353` are latent package-owned ambiguities and require explicit
  call-shape tests before disambiguation; and
- three living comments/reasons use G5H/LW milestone wording.

Responsibility review is required for:

- `execution/checkerboard_program.jl`: 1,506 nonblank/noncomment lines; and
- `execution/sequential_program.jl`: 1,129 nonblank/noncomment lines.

Both files contain separable responsibilities, but moving the private
LocalWorksets adapter or transaction/checkpoint code before LW-5 would churn
the exact execution boundary and its evidence without yet proving lower
downstream glue. ED-1 records a waiver and a post-pilot split map; it does not
split either file merely to satisfy a size threshold.

### PottsToolkit

Strengths to preserve:

- the public API is broad but explicitly inventoried, documented, and grouped
  around authoring, completion, structural `mtkcompile`, SciML execution,
  persistence, native components, and inspection;
- all seven direct dependencies are referenced;
- extensions own optional ModelingToolkit, MethodOfLines, Unitful, and Metal
  integration rather than loading them into the base package; and
- root tests reject retired ProcessBigraphs and old public-executable surfaces.

Bounded ED-1 debt:

- `Test.detect_ambiguities(PottsToolkit, Base; recursive=true)` reports 189
  total dependency-closure intersections, of which exactly 25 contain a
  PottsToolkit-owned method;
- four are confirmed public interface defects:
  `state_values(::PottsProblem, :)`,
  `state_values(::PottsIntegrator, :)`,
  `state_values(::PottsSolution, :)`, and
  `current_time(::PottsSolution, :)` are ambiguous with SciML/SII methods;
- the remaining 21 are generated statement-constructor intersections (4
  declaration, 7 ID-state, 6 symbolic-state, and 4 process constructors).
  A representative internal `CellKind(::StatementCore)` call resolves to the
  intended concrete constructor, so these are not all demonstrated runtime
  failures. They still require either safe disambiguation or a narrow,
  explained owner-method allowlist;
- Aqua ambiguity checking is disabled, so these defects are invisible to the
  ordinary suite;
- 38 living root/extension occurrences use G5H milestone vocabulary in
  diagnostics, comments, or internal environment-constant names; and
- `PottsToolkitModelingToolkitExt.jl` has 1,409 nonblank/noncomment lines and
  combines fingerprinting, semantic preflight, problem construction,
  serial/batched runtime, replay evidence, and lifecycle lowering.

The extension receives a responsibility review in ED-1. A physical split is
permitted only if it is a pure include-boundary change with exact extension-
load, MTK retention, native runtime, checkpoint, and applicable Metal checks.
It is not required merely to reduce line count.

## Repository and tooling findings

| Finding | Evidence | ED-1 disposition |
|---|---|---|
| LocalWorksets missing from CI | `.github/workflows/ci.yml` lists PottsToolkit, CorePotts, and MakiePotts only | Add the standalone `lib/LocalWorksets` `Pkg.test` row. |
| Contributor guide says three suites | `CONTRIBUTING.md` omits LocalWorksets and still describes the manual as a future G5H-5 deliverable | Correct commands and current state. |
| Root README is stale | says LW-R1/extraction authorized although LW-R2 is sealed | Correct to frozen LW-4/LW-R2 and LW-5 authorized after ED-R0. |
| User architecture omits LocalWorksets | root docs list PottsToolkit/CorePotts/MakiePotts only | Add the internal execution layer without presenting it as scientific authoring. |
| Package-quality policy is uneven | root and Core disable Aqua ambiguities; LocalWorksets separately proves zero | Add owner-filtered ambiguity tests and explicit dispositions. |
| Explicit-import checks are uneven | PottsToolkit runs ExplicitImports; CorePotts and LocalWorksets do not | Add package-local checks, then make only mechanical import changes required to pass. |
| No selected formatter | LW-4Q names Runic as intended conventional work, but repository has no formatter job or policy | Select one formatter and check touched files first; do not mass-reformat production during ED-1. |
| No dead dependency/file result | all direct dependencies referenced; all active source included; no empty active directories | Record zero deletion rather than manufacture cleanup. |

CompatHelper, TagBot, multi-version CI, JET, and external CUDA/ROCm hardware
jobs remain conventional future infrastructure. ED-1 may document them but
does not add unavailable infrastructure or claim untested backends.

## ED-1 implementation matrix

The order is deliberate: repair actual interface defects first, establish the
quality checks that would have caught them, then reconcile living repository
surfaces. Each row is independently reviewable.

| ID | Bounded operation | Required evidence |
|---|---|---|
| ED1-01 | Fix LocalWorksets' missing-`maximum` generic resolved diagnostic without changing the accepted constructor API or legacy behavior. | Constructor tests distinguish missing generic maximum, malformed generic declaration, and malformed legacy capacity/key type. |
| ED1-02 | Populate `stage=:plan`, stable contract, port, and useful expected/actual facts for duplicate resolved identities and competing independent writers. | Exact `LocalWorkValidationError` field assertions; rejection remains prelaunch, unpoisoned, and output-preserving on CPU and a bounded real-Metal witness. |
| ED1-03 | Disambiguate CorePotts empty tracker recursion and the two accepted-copy dispatch intersections without broad fallback methods. | Direct `which`/call-shape regression, unavailable-quantity error contract, accepted-copy site/relationship tests, full CorePotts suite. |
| ED1-04 | Add explicit SII `Colon` behavior for problem, integrator, and solution consistent with upstream semantics. | All four formerly ambiguous signatures dispatch; SII lifecycle, saving, settlement, and solution tests cover values and time. |
| ED1-05 | Resolve or narrowly justify the 21 statement-constructor intersections. Do not change public constructor spellings or `with_source`/symbolic mapping behavior. | All statement families construct from IDs/symbolics, retain source mapping, and pass an owner-method ambiguity budget containing no unexplained entry. |
| ED1-06 | Make owner-filtered ambiguity checks ordinary package quality: target zero in LocalWorksets, zero in CorePotts, and zero or a reviewed exact constructor allowlist in PottsToolkit. | Fresh-process ambiguity probes run after dependencies load; hostile LocalWorksets method-table tests remain isolated and last. |
| ED1-07 | Add ExplicitImports to CorePotts and LocalWorksets test environments and correct only proven import hygiene findings. | Standalone package tests and package dependency checks pass; no dependency is removed based on name counting alone. |
| ED1-08 | Add LocalWorksets to the CI package matrix and contributor commands. Reconcile root README and architecture status with sealed LW-R2. | Workflow syntax/read review; all four package commands are copy-pastable; docs build remains strict. |
| ED1-09 | Replace milestone-coded user diagnostics with domain/capability language. Rename private milestone constants only when no serialized, fingerprint, checkpoint, capability-suite, or evidence identity changes. | Source scan; exact error tests updated; fingerprint/checkpoint/capability results unchanged. Stable versioned symbols and historical evidence remain exact. |
| ED1-10 | Perform responsibility reviews for the three files above. Split only a cohesive include unit whose ownership and test invalidation are explicit; otherwise record a waiver through the LW-5 pilot. | Before/after responsibility map, include-order test, no new cross-package private reach, affected package/integration/Metal checks. |
| ED1-11 | Select a formatter policy for new/touched code and add a check mode. | No repository-wide mechanical rewrite; formatter version and command documented; touched-file check passes. |
| ED1-12 | Record post-cleanup source/test/public/ambiguity/import metrics and the same diagnostic import probe. | Machine commands and exact commit/tree recorded; no arbitrary LOC or latency threshold. |

## Protected and deferred work

ED-1 must not:

- change `localwork -> plan -> prepare -> run!`, output semantics, topology
  ownership, workspace/lifetime contracts, KernelAbstractions implicit
  ordering, or backend qualification;
- remove the legacy LocalWorksets resolved unit before its accepted removal
  criteria and a warned release;
- delete or default-promote CorePotts' direct or LocalWorksets checkerboard
  paths;
- move RNG, Metropolis acceptance, canonical Hamiltonian folding, clocks,
  lifecycle transactions, settlement, checkpoints, or solver behavior into
  LocalWorksets;
- consolidate independent scientific or performance oracles with production;
- redesign PottsToolkit authoring, MTK/SciML integration, or public operation
  terms;
- reopen the deferred MethodOfLines input-field issue;
- add a new execution family, backend claim, scheduler, pool, macro DSL, or
  public compiler representation; or
- perform performance optimization without a measured affected path.

Legacy-lowering removal, checkerboard/transaction source consolidation,
cross-package adapter consolidation, public API reduction, and kernel
optimization wait for the first LW-5 pilot's adapter-size, clarity,
inspection, allocation, launch, and CPU/Metal evidence.

## ED-1 implementation result

The bounded candidate closes every matrix row without changing the accepted
architecture, lifecycle, output-family algebra, or public surface.

| ID | Result |
|---|---|
| ED1-01 | The generic resolved constructor now reports its missing `maximum` directly; legacy-capacity and malformed-generic paths remain distinct. |
| ED1-02 | Duplicate semantic identities and competing independent writers now expose stable planning-stage contracts, ports, expected/actual facts, and corrective hints. CPU and real-Metal witnesses prove prelaunch rejection and preserved device output. |
| ED1-03 | Exact private methods remove the empty-tracker and accepted-copy intersections. The public tracker error and accepted site/relationship behavior remain unchanged. |
| ED1-04 | Exact `Colon` methods implement the four intended SII call shapes and lifecycle tests assert their values. |
| ED1-05 | Public statement spellings now use explicit per-family constructors backed by private shared helpers. ID, symbolic, source-mapping, and traversal behavior remains covered. |
| ED1-06 | All three package suites require zero package-owned ambiguities. |
| ED1-07 | CorePotts and LocalWorksets now run ExplicitImports with exact reviewed private-access boundaries; stale imports were removed. |
| ED1-08 | CI, contributor commands, user architecture, strict docs, and living status now include the standalone LocalWorksets package and exact qualified environments. |
| ED1-09 | User-facing milestone diagnostics were replaced by domain/capability language. Private `_G5H3_*` and `_G5H4_*` evidence names remain because renaming them would churn trusted environment and fingerprint identities for no user benefit. |
| ED1-10 | The responsibility review below records bounded waivers through the first LW-5 pilot. No unearned file split was made. |
| ED1-11 | Runic 1.7.0 is documented for incremental touched-file checks; the candidate passes `git-runic --diff HEAD` without a repository-wide rewrite. |
| ED1-12 | Exact before/after metrics and qualification commands are recorded in the ED-R0 evidence record. |

### Responsibility review

`CorePotts/src/execution/checkerboard_program.jl` owns five related regions:
checkerboard types and adaptation, the trusted LocalWorksets adapter,
workspace construction/adaptation, accepted-stage orchestration, and the
direct/LocalWorksets execution alternatives. These responsibilities are
large but presently share trusted world-age, include-order, launch-count, and
parity evidence. Splitting now would be movement without a demonstrated
ownership or maintenance gain. After the LW-5 pilot, candidate cohesive units
are state/adaptation, LocalWorksets adaptation, and execution orchestration,
but only if adapter-size and inspection evidence justifies them.

`CorePotts/src/execution/sequential_program.jl` contains the transaction
protocol, LocalWorksets candidacy/capability/checkpoint integration, and
enqueue/settle/public orchestration. Their ordering is part of lifecycle and
checkpoint correctness. They remain together through the pilot; a later split
may isolate transaction authority, a bounded adoption adapter, and program
lifecycle if doing so actually reduces downstream glue.

`PottsToolkitModelingToolkitExt.jl` contains canonical fingerprint/preflight,
serial runtime, batched runtime, and native lifecycle lowering. ED-1 changed
only diagnostics. A physical split would invalidate extension-load and native
stack evidence without changing ownership or safety. The next material change
may introduce pure include boundaries for those four regions, provided exact
load-order, MTK retention, native runtime, checkpoint, integration, and
applicable Metal checks are rerun.

These are explicit waivers, not findings hidden by a size threshold. No new
cross-package private reach was introduced. The first LW-5 pilot remains the
decision point because it supplies the missing evidence: whether real domain
operations and adapters become materially smaller and clearer.

## Invalidation and ED-R0

The sealed LW-4 bundle remains valid for its exact product commit. ED-1 creates
a new candidate and does not edit that artifact or retroactively relabel it.

Documentation, CI, formatter configuration, and review-record changes require
their direct checks but no product rerun. A source or test change reruns the
affected standalone package and root/integration boundary. LocalWorksets,
CorePotts execution, native extension, or Metal-extension changes receive a
bounded real-Metal semantic check. Performance runs occur only if an affected
measured path changes; pure diagnostics, dispatch disambiguation, file moves,
or comments do not automatically trigger 1,000-pair benchmarking.

ED-R0 requires:

1. every ED1 row closed, deferred with an explicit owner/reason, or rejected;
2. LocalWorksets, CorePotts, and PottsToolkit full package tests;
3. the behavioral integration suite and strict documentation build;
4. owner-filtered ambiguity and ExplicitImports results;
5. targeted SII, tracker, accepted-copy, topology-diagnostic, checkpoint, RNG,
   continuation, failure, poisoning, and extension-load tests;
6. focused CPU witnesses and affected real-Metal semantic checks;
7. no performance/allocation regression on any path actually changed;
8. before/after footprint, public-surface, dependency, ambiguity, and import
   metrics;
9. confirmation that direct/reference oracles and sealed LW-4 evidence are
   unchanged; and
10. one focused engineering review with P0=0, P1=0 and every P2 assigned.

ED-R0 is not another architecture committee or release freeze. Once it passes,
LW-5 begins with its representability inventory and one pilot migration. The
deeper consolidation decision follows that pilot's evidence.

ED-R0 passed. See the [exact qualification and review record](edr0-engineering-debt-review.md).
