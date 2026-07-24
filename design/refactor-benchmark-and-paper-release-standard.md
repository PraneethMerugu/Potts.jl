# Refactor, Benchmark, and Paper-Release Standard

Status: Accepted engineering standard

## Purpose

This document governs the pre-release refactor from the current implementation to the accepted
Potts.jl architecture. It defines compatibility policy, phase order, correctness gates, performance
measurement, documentation timing, and paper-release completion.

## Clean-Break Policy

Breaking changes are allowed until the paper/library API is finalized. The project maintains one
architecture rather than permanent old and new paths.

Deprecated constructors, compatibility aliases, old exports, and legacy engines are removed when
their replacements are complete. An alias remains only when it is independently the best final API.

Old tests preserve scientific fixtures, invariants, and intended behavior—not obsolete call syntax.
When accepted semantics intentionally change an old result, the test is rewritten with a reference
to the governing decision and a focused regression case.

Undocumented historical behavior is investigated rather than preserved automatically. No migration
guide is required for the pre-release API.

The refactor has a feature freeze except for work required by accepted contracts, conformance,
backend qualification, or architectural validation.

## Baseline Before Replacement

Before replacing a subsystem, capture its current:

- Correctness behavior and known defects
- End-to-end and operation performance
- Host and device allocation
- Host synchronization and transfers
- Persistent, scratch, and peak memory
- Package, model, and kernel compilation latency
- Dependency, driver, OS, CPU, GPU, and thread configuration

Correctness-qualified performance comparison excludes workloads whose old behavior is scientifically
invalid. Such behavior is still recorded as engineering evidence.

The baseline commit and pinned environments are retained through version control and benchmark
artifacts. The obsolete engine is not retained in the released packages.

## Refactor Phases

The accepted phase order is:

1. Freeze correctness and performance baselines.
2. Build reference models and cross-backend conformance harnesses.
3. Introduce stable identifiers, schemas, capabilities, numerical policies, and reports.
4. Replace state, proposal, energy, tracker, and transaction interfaces.
5. Replace launch, workspace, synchronization, and backend adaptation.
6. Rebuild algorithms and lifecycle execution against the new engine.
7. Implement the accepted SciML problem, integrator, and solution behavior.
8. Rebuild PottsToolkit typed modeling and compilation; delete its legacy compiler after the first
   qualified replacement slice and caller/test migration, before broad component expansion.
9. Implement the Level 1 rule DSL over the typed API.
10. Tune performance and verify that no legacy path was restored.
11. Freeze the published-model corpus; specify and implement only the additional reusable
    capabilities it requires through reference-first, post-freeze change control.
12. Manually rebuild Learn, Examples, Published Models, Concepts and Guarantees, API documentation,
    and in-scope satellites.
13. Run paper-release qualification.

Each phase ends with one working implementation for its migrated subsystem. A temporary parallel
path is removed before the phase is complete.

PottsToolkit follows stable CorePotts protocols. The Level 2 typed modeling API is implemented before
the Level 1 DSL. GPU compilation and representative execution remain working throughout CorePotts
phases; GPU validity is not deferred to final tuning.

Temporary performance regression is allowed only on active development work and remains measured.
A subsystem is incomplete until its qualified performance is recovered or improved.

## Correctness Gates

A migrated subsystem passes, as applicable:

- Unit and interface tests
- Reference implementation comparison
- Accepted invariant tests
- CPU `Float32` and `Float64`
- GPU `Float32` on every available backend
- Allocation and synchronization checks
- Statistical validation
- Backend capability and failure tests

CPU success does not qualify a GPU backend. Release claims require hardware execution. Local work
continues on available hardware while hosted or scheduled CI supplies missing qualification.

Backend exclusions are visible and prevent a conformance claim for the excluded feature.

Randomized tests use recorded semantic seeds and emit reproduction information on failure. Testing
is tiered into deterministic per-commit cases, moderate fixed CI batteries, and large scheduled or
pre-release statistical validation.

Scientific tests use stable interfaces. Direct inspection of backend arrays is limited to execution
and storage tests.

## Code-Quality Gates

Use proportionate Julia tooling, including:

- Aqua for package hygiene and method ambiguities
- JET or equivalent inference checks on representative CPU paths
- Backend device-code inspection for critical kernels
- Steady-state allocation assertions
- JuliaFormatter with one repository style

Every stable extension function is documented and tested. Public-looking methods that are not part
of the final interface become internal.

## Benchmark Project

Benchmarks live in a dedicated pinned `benchmark/` environment, separate from ordinary tests.
Canonical workload builders are shared by correctness, performance, and external comparison where
appropriate.

### Benchmark layers

The suite measures:

- Scalar and reference operations
- Individual kernels and primitives
- Component pipelines
- One complete MCS
- Multi-MCS steady state
- Initialization and compilation latency
- Saving and observation
- Ensemble throughput
- Strong and weak scaling where applicable

### Metrics

Required metrics include:

- MCS per second
- Proposed and accepted attempts per second
- Time per site or proposal where meaningful
- Kernel launches per MCS
- Host synchronizations and host-device transfers per MCS
- Host and device allocations
- Persistent, scratch, and peak memory
- Time to first MCS
- Model and kernel compilation time
- CPU thread scaling
- GPU registers, occupancy, spills, and memory traffic for critical kernels

### Timing

Every asynchronous GPU sample uses the correct backend synchronization or event timing. Unsynchronized
GPU timing is invalid.

Cold initialization, warm initialization, first MCS, and steady state are separate benchmarks.
Steady-state expressions use prebuilt state and workspaces and do not include setup allocation.

Backends run in separate processes or CI jobs where practical. One process is not required to load
every GPU stack.

### Workloads

The standard matrix covers 2D and 3D, latency-sensitive small models, medium models, and
publication-scale throughput models. Scientific workloads include:

- Volume-only cells
- Adhesion-driven sorting
- Surface constraints
- Chemotaxis and fields
- Focal-point interactions
- Growth and division
- Death and transitions
- Dense tissue
- Sparse occupancy
- Stable auxiliary volume and surface families after their relevant laws are accepted; experimental
  length and focal-point auxiliary results remain separately labeled

Every stable algorithm family is reported separately. Exact and approximate algorithms do not share
an unlabeled leaderboard.

Workloads use fixed seeds, initial-state checksums, and model fingerprints.

### Results

Benchmark runs use warm-up, repeated samples, medians and distributions, and retain raw results. A
best-of-one measurement is not evidence.

Results are emitted in a versioned machine-readable format plus human-readable summaries. Important
commits and paper candidates retain benchmark artifacts outside normal package source growth.

Conservative/default and tuned results are separate. Tuning cost and selected parameters are
recorded. Benchmark tuning never changes scientific semantics.

## External Comparisons

External CPM software comparisons live in a separate suite. Every comparison pins software version
and records differences in model semantics, proposal normalization, precision, observation, and
output work.

Only semantically matched configurations are direct speed comparisons. Unmatched configurations are
reported with their differences and are not used for a fastest-implementation claim.

## Performance Gates

For representative release workloads:

- No workload regresses by more than 5% without accepted written justification.
- The geometric mean across core workloads does not regress.
- Critical GPU workloads should improve where legacy synchronization or allocation debt exists.
- Comparisons count only when scientific and numerical policies match.

Noisy GPU CI uses repeated confirmation and historical variance rather than failing on one sample.
The performance target remains 5% even when the decision process accounts for noise.

Compile latency, time to first MCS, steady-state throughput, and memory are independent gates. Runtime
speed does not excuse unbounded compile latency or memory growth.

Qualified core GPU workloads allocate no steady-state device or host memory and do not synchronize
the host within an MCS except at explicit observation, saving, callback, transfer, or error
boundaries.

CPU remains a first-class performance target and MAY use a separately optimized implementation
behind the same scientific contract.

## API Finalization

Existing documentation does not make an API authoritative. Provisional public names are frozen only
after representative Level 1–3 models have been written and reviewed.

Every final public extension point is documented and tested. Old exports and implementation-specific
GPU concepts are removed from ordinary modeling APIs.

The generated stable-component inventory must meet the accepted 95% Level 1 DSL-coverage target and
list every exception.

## Documentation Phase

Full documentation work begins after libraries, tests, and the Phase 13 API candidate are stable.
The selected published-model corpus is then audited adversarially before tutorial presentation work.
If the corpus exposes a missing reusable scientific mechanism, that mechanism is specified,
reference-implemented, tested, persisted, inspected, and qualified under the post-freeze policy
before documentation relies on it. Existing frozen contracts are not reopened implicitly.

Tutorials are manually rebuilt rather than mechanically rewritten. Historical scientific mistakes
are corrected. Every tutorial executes in CI, with expensive rendering separable from code and
numerical assertions.

The Documenter site follows this top-level information architecture:

1. Learn
2. Examples
3. Published Models
4. Concepts and Guarantees
5. API

Learn follows progressive disclosure:

1. Level 1 for ordinary biological modeling
2. Level 2 for typed Julia modeling
3. Level 3 for scientific extension
4. Level 4 for hardware and engine work

The initial release contains 12--15 guided tutorials and 4--6 selected published models. Simplified
literature-inspired programs remain Examples. A Published Model targets a named paper result and
must satisfy the source, manifest, fidelity, preregistration, clean-execution, and evidence
requirements in
[Published-Model Reproduction Semantics](../spec/published-model-reproduction-semantics.md).

Reusable scientific logic lives in the packages. Documentation-owned model source may assemble
components, record paper parameters and schedules, and implement paper-specific analysis, but it
does not contain a private simulator or hidden state transition.

Benchmark numbers in papers or documentation come from versioned artifacts with hardware and
software context. No exported symbol, example, conceptual page, or tutorial remains stale at
release.

## Completion Criteria

The refactor is complete only when:

- No legacy engine or DSL path remains.
- All accepted core semantics have conformance tests.
- CorePotts works independently through its final public interfaces.
- PottsToolkit Level 1 and Level 2 use the new engine.
- Genuine SciML integration passes its contract.
- CPU, AMDGPU, and Metal claims are hardware-qualified under the current backend contract.
- Correctness, performance, compilation, and memory gates pass.
- The 95% DSL-coverage target passes.
- Documentation and tutorials use only the final API.
- The selected 4--6-model portfolio passes its registered release-status validations with visible
  fidelity, deviations, backend support, and evidence links.
- Every reusable mechanism required by the portfolio has accepted semantics, sequential CPU
  reference evidence, persistence/inspection coverage, and qualification for every claimed backend.
- Publication workloads reproduce from a clean environment.
- Paper benchmarks emit archived machine-readable results.

“Mostly refactored” is not sufficient. Experimental satellite features may remain separate, and
explicitly Deferred, Experimental, or Unsupported future features do not block release when they do
not leak provisional behavior into stable interfaces, the selected published-model portfolio, or
paper claims. A selected model is not deferred or simplified without the explicit owner-approved
scope amendment required by Decision 0029.

## Primary Guidance

- [CUDA.jl benchmarking and profiling](https://cuda.juliagpu.org/dev/development/profiling/)
- [KernelAbstractions performance examples](https://juliagpu.github.io/KernelAbstractions.jl/stable/examples/performance/)
- [AcceleratedKernels cross-architecture approach](https://juliagpu.github.io/AcceleratedKernels.jl/stable/)
