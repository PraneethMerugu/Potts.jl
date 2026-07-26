# Phase 14.1 G3-B Cell-History Substrate Evidence

Status: bounded-history substrate plus generic centroid-sampling and lagged-displacement processes
complete on sequential CPU and the portable KernelAbstractions CPU path; real-device
qualification remains G3-C

Date: 2026-07-25

Governing entry contract:
[phase-14-g3b-entry-contract-v1.toml](phase-14-g3b-entry-contract-v1.toml)

## Scope

This evidence covers the bounded cell-history substrate and the two reusable processes needed to
turn compiled unwrapped moments into a history-derived direction. It does not claim the complete
Wang model or any Metal/ROCm qualification.

`CellHistoryState` now accepts backend array families for:

- fixed-capacity history values;
- per-cell ring heads;
- per-cell fill counts; and
- generation tags.

All four arrays adapt together. A separate immutable `CellHistoryExecutionState` removes the host
declaration and semantic clock from kernel arguments while retaining the history identity and
length as compile-time parameters. Kernel-side reads return an unavailable value for stale
generations, out-of-capacity cells, and unavailable lags without throwing.

CPU sampling validates every active slot, generation, sample conversion, and semantic MCS before
writing. It then commits directly into the fixed-capacity ring with no candidate-array allocation.
This preserves synchronous failure atomicity while making a warm sample transition allocation-free.

Coupled checkpoint capture now materializes history arrays through the registered Adapt boundary,
matching existing device-aware site and field checkpoint behavior.

`CentroidHistorySample` stages one centroid per active persistent cell slot from the compiled
unwrapped moment tracker, validates the complete synchronous update, and commits into the bounded
generation-aware ring. `HistoryDisplacementDirection` reads the current and configured lagged
samples, publishes an arbitrary fixed number of component properties plus the pre-normalization
magnitude, and maps zero displacement to a zero vector. Both processes have host reference and
portable KernelAbstractions execution paths with caller-owned bounded workspaces.

The physical history representation is intentionally generic: a capacity-by-history-length matrix
whose isbits element is a fixed-size vector, plus per-slot head, fill, and generation arrays. This
replaces the earlier x/y-only SoA sketch in the entry packet. It supports 2D Wang centroids and
non-Wang 3D trajectories without adding axis-specific process types.

## Pinned source interpretation

The Wang source file
`s4_figures/Figure3/Radial/Simulation/fpp_polarity_force_Steppables.py` has SHA-256
`2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30`.

- lines 7-8 define the relaxation and switch boundaries as source MCS 120 and 210;
- lines 26-30 define normalization and explicitly preserve a zero vector;
- lines 82-90 append the current `xCOM`/`yCOM` sample before any polarity read;
- lines 93-100 activate only for source MCS greater than 120 and read Python index `[-5]`;
- lines 103-110 compute current minus that sample, retain the pre-normalization magnitude, and
  publish the normalized components.

Because the current sample is appended first, `[-5]` is four MCS intervals behind the current
sample, not five. The contract therefore uses `Lag(4)` and activates the derivation at normalized
target MCS 122 (source MCS 121).

## Wang-specific conformance

[Dedicated history tests](../../lib/CorePotts/test/test_phase14_cell_history.jl) prove:

- `SVector{2,Float32}` centroid samples;
- capacity-five ring wrap;
- the source-faithful append-current-then-`[-5]` result, equivalent to `t-4`;
- current-value and lag-four reads through both host and execution views;
- stale generation and invalid slot rejection without device exceptions;
- whole-state and execution-view adaptation;
- no host declaration field in the execution view;
- allocation-free warm sampling with caller-owned inputs;
- all-input validation before mutation; and
- invalid semantic-time rejection.

[Dedicated history-process tests](../../lib/CorePotts/test/test_phase14_history_polarity.jl)
additionally prove:

- exact unwrapped-centroid sampling on the host and portable CPU paths;
- zero-transfer KernelAbstractions CPU execution;
- exact current-minus-lag-four magnitude and normalized direction;
- deterministic failure before any output publication when the lag is unavailable;
- process read/write declarations and Adapt behavior; and
- non-Wang three-dimensional reuse of the same direction primitive;
- a non-Wang closed-boundary microassembly through the actual Potts, sample, derive, lifecycle,
  and observation scheduler; and
- completed-MCS checkpoint/restore followed by exact deterministic continuation.

## Validation

Recorded locally on Julia 1.12.6:

- dedicated device-ready bounded-history gate: 22/22 assertions passed;
- dedicated centroid/history-direction gate: 64/64 assertions passed;
- complete CorePotts suite: 3,562/3,562 assertions passed; and
- complete PottsToolkit suite: 702/702 assertions passed;
- G3-A generic authoring/lowering gate: passed;
- frozen Phase 13 API inventory: unchanged; and
- G3-B entry-contract and repository-structure checkers: passed.

## Boundary

This evidence closes the generic CPU/device-storage ABI, isolated process behavior, non-Wang
composition, and completed-MCS replay for bounded cell history and history-derived directions.
G3-B still requires the complete Wang assembly, its boundary/order matrix, the source-semantic
studies, and the whole-plan restart/resource evidence. G3-C must run the same history state and
logical operations through real Metal and ROCm kernels with device-code, residency, transfer,
allocation, restart, replay, memory, and performance evidence.
