# Ecosystem CI cold-compilation research

Date: 2026-09-18

## Scope and method

This audit covers LocalMath, CorePotts, Potts, PottsModels and MakiePotts on
Julia 1.12.6. It is diagnostic: no workflow or production source was changed.
Hosted logs are timing authority; local source identifies ownership and fixture
structure. The three passes were:

1. Observe every job, cache, environment, compilation phase and slow fixture.
2. Attribute repeated work to environment identity, cache scope, `Pkg.test`,
   worker isolation, workload specialization or backend compilation.
3. Test safe controls and define one-axis candidate experiments and acceptance.

Critical-path latency and total runner-minutes are separate outcomes. A cache
restore is not evidence that compiled code was reused. Fresh-depot cold evidence
remains separate from accelerated warm CI.

## Executive result

The ecosystem has three different dominant problems:

- PottsModels and MakiePotts compile nearly the same large dependency graph
  twice in one job through distinct setup/test or package/backend environments.
- Potts restores a substantial cache but still recompiles 265 dependencies,
  then spends most fixture time compiling model-specific workloads. Its current
  three CPU and two Metal shards use separate job-named cache lineages and may
  trade lower latency for much higher runner cost.
- CorePotts base import is cheap, but isolated test workers compile huge,
  overlapping operational type families. Individual useful fixtures take
  10–45 minutes. This is workload-specialization and test-topology debt, not
  download or garbage-collection cost.

LocalMath is the healthiest reference, but its package suite still spends about
seven minutes across separately compiled test workloads.

## Pass 1 — observed topology and time

| Package/profile | Hosted observation | Dominant cost |
| --- | --- | --- |
| LocalMath package | [run 35287855268](https://github.com/PraneethMerugu/LocalMath.jl/actions/runs/35287855268): package step 8m00; cache restore about 2s; suite 7m15 | Per-test workload compilation |
| LocalMath Metal | Recent successful runs about 10–12m | Host and portable-KA/backend workload compilation |
| CorePotts package | [run 34719105353](https://github.com/PraneethMerugu/CorePotts.jl/actions/runs/34719105353): package step 131m37; suite 131m22 | Operational specialization repeated across workers |
| CorePotts Metal | [run 34889776585](https://github.com/PraneethMerugu/CorePotts.jl/actions/runs/34889776585): 76 dependencies/210s before long witnesses | Fixture plus GPU workload compilation |
| Potts package | [run 35262079778](https://github.com/PraneethMerugu/Potts.jl/actions/runs/35262079778): restored 395 MB in about 11s, then 265 dependencies/1180s and about 40m47 tests | Ineffective compiled-cache reuse plus fixture JIT |
| Potts macOS smoke | A current run precompiled 265 dependencies/1082s for a 20.86s witness | Environment precompile dominates smoke |
| PottsModels | [run 34295766126](https://github.com/PraneethMerugu/PottsModels.jl/actions/runs/34295766126): 40m30 total; setup 13m36; test 21m21; docs 4m49 | Same 244 dependencies compile for 808s and again for 978s |
| MakiePotts Ubuntu | [run 34296101494](https://github.com/PraneethMerugu/MakiePotts.jl/actions/runs/34296101494): 41m52 | 461 dependencies/1058s, then backend graph 495 dependencies/1002s |
| MakiePotts macOS | Same run: 11m32; warm cache still compiled 48 dependencies/955s | Backend environment compilation |

Adjacent Potts main and PR runs repeated the 265-dependency precompile despite
nominal cache hits. Cache transfer is therefore not the main cost.

## Slow-fixture registry

These are useful behavioral/scientific witnesses. Their presence here does not
authorize deleting or weakening them. Each needs cold standalone, post-import,
same-process repeat and warm-depot fresh-process attribution.

The reproducible listing cutoff is 50 seconds wall time in the cited hosted
run; shorter fixtures remain in the machine-readable artifact.

### Potts

| Fixture | Wall time | Reported compilation share |
| --- | ---: | ---: |
| `test_scientific_activity_field_witnesses` | 1036.9s | 93.23% |
| `test_scientific_relationship_witnesses` | 592.8s | 98.15% |
| `test_external_compiler_spi` | 431.0s | 96.97% |
| `test_relationship_host_transactions` | 410.1s | 86.76% |
| `test_scientific_operation_spi` | 388.9s | 93.09% |
| `test_system_contract` | 319.2s | 98.37% |
| `test_sciml_problem_and_indexing` | 256.2s | 96.44% |
| `test_lifecycle_public_policies` | 202.8s | 94.01% |
| `test_custom_model` | 123.9s | 90.49% |
| `test_scientific_reference_witnesses` | 123.9s | 88.79% |
| `test_lifecycle_public_trajectories` | 121.9s | 94.58% |
| `test_lifecycle_public_contracts` | 83.1s | 96.48% |
| `test_lifecycle_public_arbitration` | 72.9s | 94.44% |
| `test_initial_problem_remake` | 60.7s | 86.91% |
| `test_source_traversal_authority` | 60.2s | 92.42% |
| `test_fresh_process` | 54.5s | 0.57% |

The shared [test setup](../test/setup.jl) eagerly loads the symbolic/SciML
stack in every ParallelTestRunner worker. This is a causal hypothesis to test,
not yet a deletion recommendation.

### CorePotts

| Fixture | Wall time |
| --- | ---: |
| `site_tracker_lifecycle` | 2721.5s |
| `compiled_program_checkerboard_oracles` | 1237.0s |
| `lifecycle_numeric_conversion` | 879.7s |
| `lifecycle_value_conversion` | 771.5s |
| `source_aware_trackers` | 708.2s |
| `site_minimum` | 685.1s |
| `lifecycle_rule_composition` | 673.9s |
| `lifecycle_receipts` | 569.9s |
| `scheduled_source_sums` | 542.5s |

Several allocate 19–99 GB with only 0.4–1.6% GC time, consistent with massive
compiled workloads rather than GC domination. Core's runner injects common
compiled-program fixtures into each worker. The lifecycle receipt retry search
also tries up to 128 seeds × 8 MCS and must be timed separately even though it
is not yet proven to be the primary compile owner.

### LocalMath

| Fixture | Wall time |
| --- | ---: |
| `test_localmath_authoring` | 127.8s |
| `test_keyed_reduce_stage` | 56.4s |
| `test_storage_authoring` | 48.3s |
| `test_ordered_fold_stage_execution` | 44.9s |
| `test_semantic_oracles` | 40.0s |
| `test_reduction_control` | 38.2s |
| `test_unique_stage` | 33.0s |

### PottsModels and executable text

- `bounded model factories`: 255.7s. It runs first, replay, different-seed and
  reused trajectories for every model and needs per-factory/per-mode timing.
- Documenter's aggregate `ExpandTemplates` phase spent 199.9s and contains the
  executable Wortel, Merks and OpenVT tutorial pages. Current logs cannot assign
  that aggregate to a page or prove the tutorials own all of it, so the phase
  and its three candidate pages remain grouped until page-level instrumentation.

### MakiePotts and executable text

| Fixture | Wall time |
| --- | ---: |
| Validated semantic frames | 66.6s |
| Recipe interoperability | 49.2s |
| Aqua/package quality | 44.0s |
| Fresh-process load order | 26.9s |
| Downstream conformance journey | 20.1s |

Documenter's aggregate `ExpandTemplates` phase spent 84.7s and contains the
executable pages. The log cannot assign that total to them. The saved-state
channels page includes GIF generation and is the first candidate to time
separately; the index/API pages and native recipe example remain grouped until
measured.

## Pass 2 — observations and causal hypotheses

1. `julia-actions/cache` defaults to workflow/job/OS families. Compatible jobs
   therefore do not automatically share compiled lineage, while each shard can
   accumulate a large independent depot.
2. A restored cache often contains sources and artifacts but fails to reuse the
   relevant `Pkg.test` package images. Potts is the decisive example: a 395 MB
   hit followed by 1180 seconds compiling 265 dependencies.
3. `Pkg.test` constructs an isolated test configuration and uses test compile
   flags. The PottsModels double wave demonstrates duplication in that workflow;
   whether the same mechanism explains other packages remains a source-backed
   hypothesis for the Pass-3 A/B matrix.
4. PottsModels explicitly prepares and auto-precompiles a temporary developer
   environment, then `Pkg.test` recompiles the same 244 dependencies.
5. MakiePotts compiles separate temporary package-test and backend environments,
   each containing nearly the complete Makie/SciML closure.
6. CorePotts rewrites LocalMath from the checked-in manifest path to
   `deps/LocalMath` in each job. The path mismatch is observed; its causal share
   of invalidation/recompilation is not yet established.
7. ParallelTestRunner isolation creates fresh worker processes. The hosted
   fixture tables demonstrate high compilation shares, but the amount caused by
   duplicated versus genuinely distinct JIT families awaits the one/two-worker
   and grouping controls. More shards are therefore a risk, not yet a verdict.
8. CPU, Metal-extension, docs, replay and broad compatibility environments are
   not universally interchangeable. Cache sharing is allowed only after their
   compile identities are demonstrated compatible.

## Pass 3 — controls and candidate experiments

A safe local overlay experiment found LocalMath dependency/package precompile at
about 17 seconds and warm import at 0.48 seconds; warm CorePotts import was about
0.50 seconds. It reused dependency sources/artifacts, so it is not a fresh-depot
claim, but it demonstrates that base import is orders of magnitude smaller than
Core's hosted test workload.

Every candidate must run this one-axis matrix at least three times:

1. Exact SHA with a fresh depot.
2. Packages/artifacts-only fallback, no compiled cache.
3. Exact compiled-cache restore.
4. Temporary `Pkg.test` environment versus stable test environment.
5. `Pkg.test` versus direct include under a test-equivalent prepared profile.
6. One versus two workers; one job versus current shards.
7. Suites grouped by shared compilation family versus current grouping.
8. Source-only, test-only, docs-only, manifest and sibling-SHA changes.
9. Fixture cold standalone, after shared imports, second same-process invocation
   and warm-depot fresh process.
10. GPU host precompile, `using Metal`, first portable-KA family, subsequent
    family, execution and synchronization measured separately.

Use `JULIA_DEBUG=loading` in research/nightly to capture stale-cache causes.
Record exact source tuple, resolved manifest hash, preferences, CPU target,
runner image, cache key/hit/size, depot inventory, per-fixture init/compile/science
time, allocations/RSS and subprocess use.

## Ranked correction program

### P0 — remove demonstrated duplicate work

1. PottsModels: disable automatic precompile during developer setup and let the
   isolated test configuration compile once, or demonstrate a test-equivalent
   prepared environment that `Pkg.test` actually reuses.
2. MakiePotts: test one stable Ubuntu CI environment spanning package and
   backend dependencies against the current two full compilation waves. Keep an
   ordinary isolated `Pkg.test` lane on main/nightly if PR tests use direct
   includes.
3. Potts: compare the current three CPU/two Metal shards with one prepared
   compatible environment and compilation-family-aware grouping. Accept only a
   design that improves both PR latency and total runner-minutes.
4. CorePotts: trace the top five fixtures with SnoopCompile/trace-compile and
   group tests that share operational type families within fewer workers. Do
   not split the suite further until duplicate JIT is measured.

### P1 — stable environments and useful telemetry

1. Add threshold-free machine-readable phase and fixture timing artifacts to
   every package. Keep slow-fixture history by name, semantics, compile share,
   allocations and RSS.
2. Establish stable environment layout and sibling checkout paths. Avoid
   rewriting manifests in every job. Exact committed manifests remain reserved
   for replay/stronger claims; broad compatibility environments remain broad.
3. Separate a reusable registry/package/artifact base from compiled-profile
   caches. A compiled profile includes OS, architecture, Julia, resolved graph,
   preferences and CPU target, with sibling/source identity only where Julia's
   validity requires it. Test ordered restore prefixes rather than creating an
   isolated cache for every commit; record hit quality, save time, size,
   eviction and quota churn. Keep Metal and exact replay separate.
4. Instrument PottsModels per factory/trajectory and each tutorial. Instrument
   MakiePotts executable pages, especially GIF generation.

### P2 — schedule evidence at the right cadence

1. PR: focused owner tests, one complete Linux package lane, narrow macOS smoke,
   affected portable-Metal witnesses and changed docs.
2. Main/merge: complete CPU/macOS/Metal, integration, replay, docs, quality and
   downstream canaries.
3. Scheduled: fresh-depot cold compilation, full compiler-family matrix,
   compatibility, complete model corpus and performance trends.
4. Move expensive Aqua/ambiguity, fresh load-order, complete backend/visual and
   recording evidence only after confirming a cheaper PR witness protects the
   same change class. Coverage is rescheduled, never silently removed.

Fork PRs restore trusted caches read-only. Only trusted main jobs may publish
reusable compiled artifacts. Never execute untrusted PR code through
`pull_request_target`. No project-owned kernel cache, serialized backend
pipeline or cache-dependent correctness is introduced.

## Acceptance

- One dependency-precompile wave per compatible profile.
- An identical warm graph recompiles only changed package paths and legitimate
  extension families.
- Repeated hosted A/Bs should pursue roughly 50% lower Potts/Core PR critical
  paths without increasing total runner-minutes or weakening science/Metal
  authority; this is a study goal, not a fixed timing gate.
- PottsModels near 15 minutes and MakiePotts Ubuntu near 20 minutes are plausible
  first candidate ranges inferred from removed duplicate waves, reviewed over
  repeated hosted runs rather than enforced as machine-dependent thresholds.
- Slow text and code fixtures remain individually visible, not buried in a
  documentation or package total.
- Fresh-depot results remain explicit compiler-health evidence; cache reuse is
  infrastructure only.

## Delivery ownership

Implement each package correction in that package's ordinary CI owner. Share a
reusable ecosystem workflow/composite action only after at least two packages
demonstrate the same stable setup law. Do not add this diagnostic work to the
feature PR count unless implementation proves a separately owned repository
change that cannot fit an existing CI/performance owner.
