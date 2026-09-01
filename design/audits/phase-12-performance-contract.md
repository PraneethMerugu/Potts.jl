# Phase 12 Quantitative Performance Contract

Status: Accepted; interview decisions 1--20 complete

Date: 2026-07-21

This document records project-owner choices for Phase 12. It specializes the accepted benchmark and
JuliaGPU standards without changing scientific semantics. Profiling chooses implementation details;
the owner interview chooses what constitutes project success.

## Accepted performance priorities

### 1. Optimization target

Steady-state MCS throughput on paper-scale workloads is the primary optimization target. Scientific
correctness and GPU residency are inviolable. Compilation latency, first-MCS latency, and memory are
independent gates; a throughput improvement cannot compensate for failure of another gate.

### 2. Conservative and tuned results

Conservative public defaults are the primary release and paper results. Explicitly tuned results are
reported separately with every selected parameter and the tuning cost. Tuning runs outside timed
scientific execution and cannot change the selected scientific algorithm or semantic RNG identity.

### 3. Algorithm-family comparison

`SequentialCPM`, `SequentialEquilibrium`, `CheckerboardSweepCPM`, and `LotteryCPM` are reported as
separate scientific processes. Regression geometric means combine only semantically comparable
workloads within a defined algorithm/backend group. A descriptive cross-family presentation cannot
be used to crown an unlabeled fastest algorithm.

KernelIntrinsics and other implementation variants remain inside an algorithm result. Generic and
optimized variants may be compared to justify engineering complexity, but an intrinsic path is not
a fifth scientific algorithm.

### 4. Release-blocking workload scope

The required set covers all five paper families, 2D and 3D where scientifically applicable, small
latency-sensitive cases, and publication-scale throughput cases. It is a curated matrix rather than
a wasteful Cartesian product. An algorithm runs only workloads compatible with its guarantee
profile. Additional dense/sparse, lifecycle, and component-isolation cases are diagnostic unless
they exercise a unique release-critical path.

### 5. Regression acceptance

A reproducible regression greater than 5% fails unless the project owner explicitly accepts a
written justification supported by a bounded compensating improvement. A result within 5% is not an
automatic pass when the applicable geometric mean regresses consistently, memory becomes unbounded,
or cold latency deteriorates materially.

No performance trade can excuse changed scientific behavior, backend fallback, undeclared warm
allocation, transfer, or host synchronization. No accepted justification changes the meaning of a
metric or makes scientifically incomparable records comparable.

Accepted exceptions are enumerated in the machine-readable
[`phase-12-accepted-regressions.toml`](phase-12-accepted-regressions.toml) ledger. An unlisted
regression is not accepted, and each ledger entry must preserve the raw failing comparison rather
than weakening a threshold.

## Accepted hardware and measurement policy

### 6. Authoritative CPU systems

The Metal runner's ARM64 CPU and the ROCm runner's x86_64 CPU are the two controlled authoritative
CPU-performance systems. GitHub-hosted x86_64 remains diagnostic validation rather than benchmark
authority because its hardware allocation and noise are not controlled. Records include CPU model,
memory, operating system, power mode, and available thermal information.

### 7. CPU thread configurations

Authoritative results include one Julia thread and a pinned physical-core configuration. One-thread
results provide the stable sequential reference; the physical-core configuration represents maximum
qualified CPU throughput. A `1, 2, 4, ...` physical-core series diagnoses scaling where applicable.
SMT is excluded from headline results unless measurements demonstrate a consistent benefit.

An algorithm that is scientifically sequential remains sequential. Increasing the Julia thread count
does not authorize a different scientific algorithm or parallel transaction rule.

### 8. Precision

`Float32` is the primary cross-backend performance precision for CPU, Metal, and ROCm. CPU also
qualifies `Float64` correctness and reports separate `Float64` performance. GPU `Float64` is optional
and backend-labeled. Unsupported precision is reported as unsupported; it is never silently
downgraded or compared with a different precision.

### 9. Repetition

Smoke runs are diagnostic. A regression decision requires at least three fresh-process full runs,
each with at least ten synchronized steady samples. Paper candidates require at least five
independent full runs. Baseline and candidate execute on the same runner in a close time window, and
noisy-hardware failure requires confirmation rather than a single adverse observation.

Release evidence uses a counterbalanced paired schedule: each fresh-process pair runs the immutable
baseline and immutable candidate consecutively, and the first subject alternates by pair. The paired
process identity records subject, pair index, and ordinal. Separate subject-only workflows remain
useful for cold and precompile tiers, but their warm ratios are diagnostic when host drift can be
observed; they cannot overrule balanced paired warm evidence.

Raw samples and process-level summaries are retained. Combining many samples from one process does
not misrepresent them as independent process repetitions.

### 10. Cold-latency tiers

Cold performance is reported in three independent tiers:

1. isolated environment setup and precompilation, excluding network download time;
2. fresh-process package import and first model construction, normalization, binding, and lowering
   with an existing compiled cache; and
3. first backend kernel compilation and first synchronized MCS.

Warm throughput begins only after compilation, initialization, and declared warmup complete. The
three tiers cannot be collapsed into one ambiguous startup measurement.

## Accepted baseline and optimization policy

### 11. Baseline hierarchy

The untouched merged Phase 11 head `7eae976` is the fixed Phase 12 performance-recovery baseline and
is captured under the new Phase 12 schema. Each retained optimization is also compared with its
immediate parent to expose local regressions.

The immutable pre-refactor release remains historical engineering evidence. It enters a direct speed
comparison only for a workload whose scientific semantics, proposal normalization, numerical policy,
precision, observation work, and hardware configuration are established as comparable.

### 12. Memory and residency budgets

Qualified warm execution has zero device allocations, zero engine-attributable host allocations,
zero undeclared host waits, and zero undeclared device-to-host transfers. Persistent, scratch,
lifecycle, and peak memory are reported separately. A reproducible memory increase greater than 5%
requires explicit written acceptance. Every paper-scale workload must fit on the least-memory
qualified device within its backend contract.

Observation, checkpoint, saving, callback, declared lifecycle observation, and error-readback
boundaries remain separately measured rather than hidden as engine work.

### 13. Backend-native resource evidence

Registers, occupancy, spills, local memory, and native code size have no fabricated universal
cross-backend threshold. Critical kernels retain the metrics each backend can authoritatively
provide, establish kernel-specific baselines, and reject meaningful deterioration when it harms
end-to-end performance. Register use is never inferred from occupancy, and an unavailable metric is
reported as unavailable.

### 14. Tuning scope

The paper release uses measured static policies selected by operation, backend, architecture class,
dimension, and data class. Every selected policy is recorded in the result. The architecture remains
open to later finite, cached autotuning, but Phase 12 does not add runtime search and cache
invalidation unless static policies demonstrably cannot pass the accepted gates.

Tuning policy cannot change the scientific algorithm, semantic RNG identity, or normalized MCS.

### 15. Required layout/value foundations and optional specializations

KernelAbstractions remains the default language for portable domain-specific kernels.
The owner-authorized LW-5B4O amendment makes StructArrays and StaticArrays
always-loaded direct dependencies with concrete base-package integrations in
CorePotts and LocalWorksets. This supersedes their former optional dependency
classification. It does not make every StructArrays layout or StaticArrays
specialization mandatory: each physical representation remains bounded by
semantic equivalence, specialization, compilation, allocation and qualified
CPU/GPU evidence.

AcceleratedKernels primitives, KernelIntrinsics specializations, particular
StructArrays layouts, particular StaticArrays values, and other performance
mechanisms are selected for a hot path only after the relevant cost and
representation are characterized. Adoption requires qualified CPU/Metal/ROCm
behavior where applicable, generic fallbacks, and equivalence evidence.

A mechanism normally demonstrates a material end-to-end benefit after accounting for compilation,
registers, memory, and complexity. It may instead be retained for material correctness or code
simplification when it causes no performance regression. A microbenchmark improvement or desire to
advertise a dependency is insufficient.

## Accepted external-comparison and completion policy

### 16. External systems and models

Pinned versions of CompuCell3D, Morpheus, and Artistoo are the external CPM comparison targets. The
separate external suite attempts the same five paper reference families in each system where they are
genuinely expressible. A missing or semantically different feature is labeled incomparable rather
than silently approximated.

External comparison support does not require stable PottsToolkit compatibility presets during Phase
12. Conversions and fixtures may remain benchmark-owned until their semantics and public value pass
the later API-freeze gate.

### 17. Fastest-implementation claims

The paper does not make an unqualified "fastest CPM in the world" claim. A supported claim identifies
the semantically matched workload, algorithm class, precision, hardware configuration, compared
implementations, and excluded output work. Appropriate wording is:

> Potts.jl achieved the highest measured steady-state throughput among the compared implementations
> for this semantically matched workload, algorithm class, precision, and hardware configuration.

Multiple bounded claims are permitted when each has retained evidence.

### 18. External timing boundaries

External records separate setup, compilation or JIT, initialization, first MCS, warm MCS,
observation, and saving wherever the simulator exposes those boundaries. Headline throughput compares
equivalent warm scientific execution with matched observation and output work. Potts.jl compute-only
timing is not compared with rendering or disk output in another simulator.

### 19. Relationship to the Phase 12 gate

Internal baseline recovery, scientific correctness, and three-backend qualification determine Phase
12 completion. External results determine which comparative paper claims are allowed. An external
system outperforming Potts.jl blocks the corresponding fastest claim and creates a documented
optimization target; it does not invalidate an otherwise qualified release.

### 20. Stop condition

Phase 12 ends when every internal quantitative gate passes, CPU/Metal/ROCm have repeated real-hardware
evidence, no unexplained critical bottleneck remains, preliminary external comparisons are
semantically validated, and every retained optimization has correctness and fallback evidence.

Remaining bounded opportunities are recorded rather than extending the phase for diminishing
single-workload gains. Phase 15 reruns pinned external and publication matrices for the paper.

## Contract closure

All project-owner decisions required to implement the Phase 12 measurement and optimization system
are accepted. Later measurements may select implementations but cannot weaken this contract without
an explicit owner decision and recorded amendment.
