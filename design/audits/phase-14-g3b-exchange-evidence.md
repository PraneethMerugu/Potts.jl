# Phase 14.1 G3-B Exchange Transaction Evidence

Status: sequential CPU and portable fixed-tree KernelAbstractions reference accepted; Metal/ROCm execution remains open

Date: 2026-07-25

## Scope

This record covers the generic immediate uptake, maximum calibration, and root-plan mode substrate
required by the Wang secretome/signal exchange. It is not complete G3-B or GPU qualification.

The implementation now provides:

- generic `Uptake`, `MaximumCalibration`, and `FieldExchange` declarations;
- one plan-owned `PlanModeSchedule`, with no MCS branch inside the process;
- inactive, reset, calibrate, and publish execution modes;
- one backend-adaptable global calibration value, initialized status, and publication epoch;
- preallocated per-cell raw totals, candidate signal, status, and failing-index workspace;
- reuse of the field's two staging grids for candidate field and per-site removals;
- source-faithful Float32 site removals accumulated into Float64 by ascending cell slot and
  ascending canonical linear site;
- post-Potts volume normalization;
- calibration by a declared numerator divided by the maximum raw uptake;
- a typed declared write set spanning field, cell property, and global calibration state;
- candidate-only execution followed by one logical publication;
- structured zero-maximum and uninitialized-calibration failures;
- checkpoint payloads containing calibration value, initialized status, and publication epoch but
  no workspace; and
- zero-byte warm sequential CPU publish execution.

The portable profile now additionally provides:

- exactly one 256-lane workgroup per cell;
- ascending lane-strided canonical site visits;
- an explicitly unrolled pairwise Float32 shared-memory reduction tree;
- one explicitly unrolled fixed-tree global maximum;
- integer-only status and failing-index atomics;
- conditional field, signal, calibration, and epoch publication;
- no host scalar access or unobserved transfer; and
- explicit stable-boundary status synchronization.

The coupled phase runner recognizes a mode-bound `Exchange` invocation and executes field, cell,
and global writes against one phase candidate. Later phases cannot observe a partial exchange.

## Executed evidence

The focused Phase 14 run now passes 136 assertions in the continuous-system/field-coupling set.
The exchange assertions cover:

- exact mode boundaries at target MCS 1, 121, 122, 210, 211, 212, and 500;
- schedule gap and out-of-range rejection;
- inactive and reset behavior without field mutation;
- relative-rate and capped uptake branches;
- per-cell volume normalization;
- target-211 calibration without signal publication;
- target-212 same-MCS signal publication;
- field mass balance using Float64 observation accumulation;
- maximum calibration value and initialized status;
- publication epoch progression;
- candidate/snapshot isolation for typed cross-domain writes;
- zero-maximum and uninitialized-publish failure atomicity;
- checkpoint restore;
- Adapt-visible authoritative and workspace arrays; and
- exactly zero warmed CPU allocations.

The portable assertions additionally compare calibrate/publish results against the sequential
oracle, prove 15 ordered launches, prove zero host/device transfers before the declared boundary,
and prove zero-maximum conditional-publication failure.

The implementation preserves the earlier field, G3-A, Phase 14.0, Phase 13 API, and repository
structure gates.

## Explicitly open

G3-B still requires:

1. Metal/ROCm device-tree compilation evidence without host closures or scalar indexing;
2. stale-generation and backend/capacity failure fixtures;
3. source-runtime uptake/calibration fixtures;
4. assembled completed-MCS restart at targets 210, 211, and 212; and
5. the CC3D numerical-field source study needed to interpret exchange input equivalence.

No portable, source-semantic, or paper-reproduction claim may cite this sequential CPU record
alone.
