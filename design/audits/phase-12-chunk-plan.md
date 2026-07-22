# Phase 12 Performance Recovery and Backend Qualification Chunk Plan

Status: In progress

Date: 2026-07-21

Branch: `codex/phase-12-performance`

## Objective

Recover or improve performance after the semantics-first refactor, qualify the final execution path
on CPU, Metal, and ROCm, and retain enough raw evidence to support the paper without changing the
accepted scientific contract.

Each optimization is a small measured experiment: establish a baseline, identify an end-to-end
bottleneck, change one mechanism, rerun correctness and performance evidence, and either retain or
revert the change. Microbenchmark improvement alone does not justify engine complexity.

## 12.0: Measurement contract and entry baseline

- Complete the focused owner interview in rounds of five questions.
- Define required, diagnostic, experimental, and external-comparison workload sets.
- Introduce a new versioned Phase 12 result schema without mutating historical schemas.
- Add comparison tooling for compatibility, independent metric gates, raw distributions,
  per-workload ratios, geometric means, and accepted-regression records.
- Isolate cold package/model/kernel measurements in fresh subprocesses.
- Capture untouched merged Phase 11 CPU x86_64, CPU ARM64, Metal, and ROCm records.

Exit: the same immutable baseline can be independently retrieved and evaluated, and an incompatible
candidate is rejected rather than numerically compared.

## 12.1: End-to-end bottleneck audit

- Profile each required scientific workload before extracting microbenchmarks.
- Attribute time to authoring, compilation, initialization, proposal generation, component
  evaluation, conflict handling, commit, lifecycle, tracking, reduction, and observation.
- Record launches, synchronization, transfers, allocations, persistent/scratch/peak memory, and
  actual proposal accounting.
- Capture backend-native resource evidence for critical kernels where supported.
- Rank bottlenecks independently for CPU, Metal, and ROCm.

Exit: every proposed optimization cites a measured end-to-end bottleneck and a reproducible capture.

## 12.2: Host compilation and first-use latency

- Measure package load, precompile, first import, model construction, normalization, problem binding,
  lowering, initialization, kernel compilation, and first MCS independently.
- Reduce accidental specialization, inference failures, repeated semantic traversals, and invalidation
  only where measurements identify them.
- Add representative precompile workloads when their saved latency justifies package-image growth.
- Measure Level 1 and equivalent Level 2 construction separately from their shared runtime.

Exit: compile and first-use gates pass independently; warm throughput cannot hide a cold regression.

## 12.3: Portable GPU execution recovery

- Tune operation-specific KernelAbstractions workgroups and layouts per qualified backend.
- Audit launch granularity, memory access, atomics, reductions, scans, sorting, and reusable scratch.
- Qualify any AcceleratedKernels primitive on CPU, Metal, and ROCm before engine adoption.
- Preserve zero warm allocation, device-to-host transfer, and undeclared host synchronization.
- Reject fusion or static specialization that improves one timing by causing unacceptable register,
  occupancy, code-size, or compilation costs.

Exit: portable GPU paths pass scientific equivalence, residency, native-resource, and regression
gates on real Metal and ROCm hardware.

## 12.4: Intrinsic specialization

- Identify only portable kernels whose measured atomic or subgroup cost warrants an intrinsic path.
- Route external KernelIntrinsics use through one internal CorePotts operation boundary.
- Retain a generic KernelAbstractions implementation and capability-controlled selection.
- Test partial groups, divergence, subgroup widths, equivalence, semantic RNG identity, and fallback.
- Retain an intrinsic implementation only when it gives a material end-to-end benefit without an
  unacceptable compile, register, occupancy, or code-size cost.

Exit: intrinsics remain an internal implementation variant and never become a scientific algorithm
or sole implementation.

## 12.CPU: CPU specialization and scaling

- Treat merged Phase 12 commit `ac68b366ba33eb9edb3e87bb3a0073db445c32e6` as the immediate
  regression baseline while retaining `7eae976b77ac5095979db12db463387656f9d58c` as the fixed Phase
  11 recovery baseline.
- Profile x86_64 and ARM64 separately.
- Measure one-thread latency and the accepted `1, 2, 4, ..., physical cores` scaling matrix on the
  authoritative runners. Scientifically sequential algorithms remain one-thread references; extra
  Julia threads cannot change their transition process.
- Add CPU-specific iteration, vectorization, reduction, or grain policies only behind the same
  scientific protocol.
- Compare conservative and tuned CPU configurations separately.
- Require fixed-configuration replay, semantic-RNG identity, exact accounting, and statistical
  agreement across qualified thread configurations before retaining a parallel CPU policy.
- Retain raw profiles and repeated paired records for `Float32`; separately qualify CPU `Float64`
  correctness and performance under the accepted Phase 12 contract.

Exit: CPU remains a first-class engine target, with no representative regression over the accepted
baseline and no GPU-shaped implementation retained where a justified CPU method is better. A
standalone Phase 12.CPU completion audit records either the retained specialization or the
evidence-backed decision that the existing path is the qualified implementation.

## 12.Close: Full regression and paper-comparison qualification

- Run repeated full matrices in separate CPU, Metal, and ROCm processes.
- Apply independent compilation, first-MCS, memory, residency, and steady-throughput gates.
- Require no unaccepted workload regression over 5% and no geometric-mean core regression.
- Retain raw versioned records, summaries, profiles, environment manifests, and accepted
  justifications outside normal source growth.
- Run semantically matched external comparisons in a separate suite and label unmatched results.
- Record remaining optimization opportunities without extending the phase after its gates pass.

Exit: every Phase 12 roadmap gate has current real-hardware evidence and a completion audit. Phase 13
may then freeze the measured API and contract versions.

## Validation after every retained optimization

- affected unit and integration tests;
- algorithm accounting and statistical reference tests;
- model-fingerprint and semantic RNG invariance;
- generic/optimized equivalence where applicable;
- backend device compilation and execution;
- warm allocation, transfer, and synchronization assertions; and
- the affected baseline comparison, followed by the full matrix at chunk closure.
