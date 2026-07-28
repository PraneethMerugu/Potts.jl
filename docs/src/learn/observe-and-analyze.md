# [Observe and analyze](@id observe-and-analyze)

Analysis consumes declared host observations. It does not inspect private backend storage or cause
an undeclared device synchronization.

## Request the smallest sufficient dataset

The stable high-level requests include cell volume, cell type, boundary measure, named cell
properties, and lattice ownership. Combine them in `ObservationSet` and derive a snapshot policy:

```@example observe-and-analyze
analysis = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials",
    "observe_and_analyze.jl"))
(length(analysis.volume_series), length(analysis.rows),
    length(analysis.ownership_series))
```

The canonical source declares the observations in the model, retains them during execution, and
builds a cell-valued table.

## Understand the data shapes

- `CellSeries` stores generation-aware values by saved MCS.
- `SpatialSeries` stores lattice-valued frames such as ownership.
- `observation_table` joins compatible cell-valued series.

Spatial data is not flattened into a cell table. A recycled cell slot is a different biological
cell, so join on cell ID and generation.

## Snapshot policy choices

| Policy | Retained state | Use |
|:--|:--|:--|
| backend/default | Backend-resident saved state | continuation inside execution |
| `HostSnapshotPolicy()` | Complete logical host state | debugging or whole-state conversion |
| `observation_policy(set)` | Declared typed observations | production analysis |

Observation cadence, transfer cost, and retained variables belong in the run record. `observe`
cannot reconstruct a quantity that was never retained.

## Units

MCS and lattice spacing remain dimensionless until a study supplies `PhysicalScale`.
`with_units` creates a calibrated view without mutating the solution or its fingerprints. Report
the calibration method; the engine does not infer physical time.
