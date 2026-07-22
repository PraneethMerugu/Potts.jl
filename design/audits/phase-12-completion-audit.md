# Phase 12 performance recovery and backend qualification completion audit

Status: Core recovery merged; Phase 12.CPU closure addendum pending

Date: 2026-07-22

## Scope and retained implementation

Phase 12 qualified the Phase 11 execution path on CPU ARM64, CPU x86_64, Metal, and ROCm under
Julia 1.12.6. Its objective was a measured recovery, not speculative specialization: retain only
changes with scientific, residency, and real-hardware evidence.

The fixed historical Phase 11 baseline is `7eae976b77ac5095979db12db463387656f9d58c`. The retained
startup mechanism is `cb5fc8fdfb68c38e6433bc84622ee3c2ee63cc1e`; the immediate comparison parent is
`d0eac8319eebd5c24de94bcdf1dc9f1e78b73606`; and the final scientific candidate is
`91394ba4dafc8ad0ddd41781114fb5c4378a1683`.

Two mechanisms are retained:

1. a CPU-only representative `PrecompileTools` workload for the four public algorithm families;
2. deferral of Checkerboard attempt-accounting aggregation to explicit
   `current_mcs_report` observation.

The second change is confined to `checkerboard.jl` and the Checkerboard report dispatch. It removes
one unrequested report launch per ordinary Checkerboard MCS, preserves the existing report kernel,
and launches it only at the declared observation boundary. Lottery and both sequential algorithms
are not changed by the candidate source diff.

No new AcceleratedKernels primitive, KernelIntrinsics specialization, runtime autotuning, or
backend-specific scientific path was retained. Existing KernelAbstractions algorithms remain the
only scientific execution paths.

## Measurement contract and raw evidence

The accepted [Phase 12 performance contract](phase-12-performance-contract.md) controls identity,
hardware, precision, synchronized timing, residency, cold/warm separation, and accepted
regressions. All result records retain the immutable implementation commit, harness tree digest,
hardware identity, semantic workload fingerprints, independent process identifier, and raw sample
arrays.

Early subject-only controls exposed large apparent movements in algorithms absent from the candidate
diff. They are preserved as diagnostic records, not silently discarded. The release warm evidence
therefore uses a counterbalanced paired schedule: immutable baseline and candidate processes run
consecutively, with first subject alternating by pair. `benchmark/paired_repeat.jl` and the paired
workflow record subject, pair, and ordinal in every process identifier. The comparison module now
also validates that schedule and retains pair-level ratios in its output; it does not weaken any
release threshold.

## Correctness, residency, and native execution

All commands below target Julia 1.12.6.

| Gate | Evidence | Result |
|---|---|---:|
| Benchmark comparison contract | local `benchmark/test/runtests.jl` | 50 / 50 pass |
| CorePotts suite | final candidate local qualification | 2,990 pass; 1 intentional broken; 0 fail |
| PottsToolkit suite | final candidate local qualification | 635 / 635 pass |
| Documentation | [29886808132](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29886808132) | pass |
| Package, integration, ARM64, x86_64 CI | [29886808118](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29886808118) | pass |
| Metal and ROCm scientific qualification | [29886808113](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29886808113) | pass |

Warm qualified regions retain zero device allocation, zero undeclared host-to-device transfer, and
zero undeclared host synchronization. Declared lifecycle observation and explicit report observation
remain separately recorded boundaries.

ROCm native evidence from [29876566494](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29876566494)
contains nonempty GCN output and a nonempty `rocprofv3` trace for every algorithm. Native-code sizes
are 2,565,272 bytes for Checkerboard, 2,973,480 for Lottery, 1,289,858 for Sequential, and
1,370,239 for SequentialEquilibrium; the Perfetto trace is 3,403,564 bytes. Metal native evidence
from [29878843742](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29878843742) contains
nonempty AIR and chronological profiles for every algorithm: Checkerboard 1,052,257 bytes and 75
command buffers over five MCS; Lottery 1,162,727 bytes and 210 command buffers; Sequential 671,310
bytes and five command buffers; SequentialEquilibrium 675,244 bytes and five command buffers.

## Cold and precompile tradeoff

The owner-approved [accepted-regressions ledger](phase-12-accepted-regressions.toml) retains the
raw cold/precompile records and bounds. The representative precompile workload increases total
precompile by at most 11.6% and isolated cache size by at most 14.3%, while complete fresh-process
time-to-first-MCS improves on every qualified backend and algorithm. This exception is limited to
that startup mechanism; it does not accept a warm-runtime, scientific, residency, transfer,
synchronization, or GPU-kernel-precompile regression.

## Paired warm throughput evidence

The first paired release matrix used four baseline/candidate pairs on each authoritative system:

| System | Run | Pairs | Result |
|---|---:|---:|---|
| CPU ARM64, `Float32`, one thread | [29886816669](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29886816669) | 4 | all workloads within 5%; strict raw GM diagnostic flags `SequentialEquilibrium` +0.065% |
| CPU x86_64, `Float32`, one thread | [29886829600](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29886829600) | 4 | all workloads within 5%; strict raw GM diagnostic flags Lottery +0.096% |
| Metal, `Float32` | [29886840525](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29886840525) | 4 | Checkerboard strongly improves; Lottery monolayer is +6.41%, requiring confirmation |
| ROCm, `Float32` | [29886850222](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29886850222) | 4 | all workloads within 5%; strict raw GMs for unchanged sequential paths are <= +0.17% |

The Metal anomaly was rerun under the same immutable pair protocol with five fresh pairs:

| System | Run | Pairs | Confirmation result |
|---|---:|---:|---|
| Metal, `Float32` | [29888615690](https://github.com/PraneethMerugu/Potts.jl/actions/runs/29888615690) | 5 | prior Lottery monolayer result is +1.19%; a different latency-scale Lottery workload is +7.04% |

The >5% Lottery result does not reproduce in the same workload. Pair-level raw ratios instead show
large, sign-changing latency-scale Lottery variation—for example the confirmation has individual
ratios from 0.57 to 2.19 across distinct Lottery workloads/pairs—while Checkerboard improvements
are present across every pair and workload. This is a confirmed measurement-noise pattern, not a
candidate-caused regression: the candidate contains no Lottery code change, the affected workload
changes between independent paired schedules, and no same-workload >5% regression repeats.

The literal comparator intentionally still marks its raw summaries as failures whenever an algorithm
geometric mean exceeds exactly 1.0. Those raw failures are retained. They are not treated as a
scientific or release regression here because they are sub-threshold, have no reproducible affected
workload, and belong to algorithm paths unchanged by the candidate. The paired schedule, raw pair
ratios, confirmation run, and source-diff scope are all preserved so this conclusion remains
auditable. A later candidate with a repeatable >5% workload regression, a consistent paired
algorithm regression, or a changed unaffected path fails the contract rather than inheriting this
decision.

Checkerboard is the only affected path and improves on every qualified backend. The four-pair
geometric-mean candidate/baseline steady-time ratios are 0.973 (ARM64), 0.962 (x86_64), 0.502
(Metal), and 0.043 (ROCm). The five-pair Metal confirmation independently reports 0.490.

## External-comparison boundary and remaining opportunities

The [external comparison crosswalk](phase-12-external-comparison-crosswalk.md) pins the Phase 15
paper-scope mappings for CompuCell3D, Morpheus, and Artistoo. It prevents unmatched models from
supporting a performance claim; final cross-library paper experiments remain Phase 15 work, outside
the internal Phase 12 release gate.

The remaining opportunity is recorded rather than folded into this phase: Phase 12.5 evaluates the
separately named tiled Checkerboard engine under its own statistical, semantic, native-profile, and
paper-scale contract.

## Closure checklist

- [x] Versioned benchmark schema and immutable baseline/candidate identity.
- [x] Independent cold, first-use, and warm timing tiers with accepted startup ledger.
- [x] Repeated real ARM64, x86_64, Metal, and ROCm evidence.
- [x] Counterbalanced paired warm evidence and a required Metal confirmation.
- [x] Scientific correctness, semantic accounting, residency, and native GPU evidence.
- [x] Raw failures, raw samples, and pair-level ratios retained rather than threshold edits.
- [x] Exact candidate CI, GPU validation, and documentation green.
- [x] Run the same release gates on the final audit/comparator PR head and merge it in
  [PR #12](https://github.com/PraneethMerugu/Potts.jl/pull/12) as
  `ac68b366ba33eb9edb3e87bb3a0073db445c32e6`.

This audit closes the merged core recovery work. The subsequently separated Phase 12.CPU addendum
must still qualify the accepted physical-core scaling matrix and record its own completion audit
before Phase 12.5 implementation begins.
