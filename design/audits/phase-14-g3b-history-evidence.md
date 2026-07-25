# Phase 14.1 G3-B Cell-History Substrate Evidence

Status: first G3-B implementation increment complete on sequential CPU; device qualification
remains G3-C

Date: 2026-07-25

Governing entry contract:
[phase-14-g3b-entry-contract-v1.toml](phase-14-g3b-entry-contract-v1.toml)

## Scope

This increment replaces the host-container assumption in the provisional bounded cell-history
substrate. It does not claim the complete Wang model or any Metal/ROCm qualification.

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

## Validation

Recorded locally on Julia 1.12.6:

- dedicated device-ready bounded-history gate: 22/22 assertions passed;
- complete CorePotts suite: 3,045/3,045 assertions passed; and
- complete PottsToolkit suite: 702/702 assertions passed;
- G3-A generic authoring/lowering gate: passed;
- frozen Phase 13 API inventory: unchanged; and
- G3-B entry-contract and repository-structure checkers: passed.

## Boundary

This evidence closes only the generic CPU/device-storage ABI for bounded cell history. G3-B still
requires the field, exchange, intracellular, relationship, alignment/force, observation, complete
Wang assembly, source-runtime oracles, and restart matrix. G3-C must run the same history state and
logical operations through real Metal and ROCm kernels with device-code, residency, transfer,
allocation, restart, replay, memory, and performance evidence.
