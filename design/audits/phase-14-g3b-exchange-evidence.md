# Phase 14.1 G3-B Exchange Transaction Evidence

Status: sequential CPU transaction accepted; portable fixed-tree execution remains open

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

The coupled phase runner recognizes a mode-bound `Exchange` invocation and executes field, cell,
and global writes against one phase candidate. Later phases cannot observe a partial exchange.

## Executed evidence

The focused Phase 14 run passes 104 assertions in the continuous-system/field-coupling set.
Relative to the previous 35-assertion field checkpoint, 69 additional assertions cover:

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

The implementation preserves the earlier field, G3-A, Phase 14.0, Phase 13 API, and repository
structure gates.

## Explicitly open

G3-B still requires:

1. portable width-256 per-cell and fixed global-maximum reduction kernels;
2. backend-native integer status/failing-index propagation and conditional publication;
3. Metal/ROCm device-tree compilation evidence without host closures or scalar indexing;
4. stale generation and backend/capacity failure fixtures;
5. source-runtime uptake/calibration fixtures;
6. assembled completed-MCS restart at targets 210, 211, and 212; and
7. the CC3D numerical field oracle needed to interpret exchange input equivalence.

No portable or foreign-runtime numerical claim may cite this sequential CPU record alone.
