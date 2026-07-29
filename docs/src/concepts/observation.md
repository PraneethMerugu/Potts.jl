# [Observation boundary](@id observation-boundary)

Observation is explicit because device synchronization, data transfer, and retention can change
both performance and what analyses are possible.

## Snapshot policies

CorePotts provides three policy levels:

| Policy | Retains | Typical use |
|:--|:--|:--|
| Backend/default snapshot policy | Backend-resident saved state | Continuation inside the execution environment |
| `HostSnapshotPolicy` | Complete logical host snapshots | Debugging and analyses requiring full state |
| `ObservableSnapshotPolicy` | Only declared scientific observables | Production analysis and visualization |

PottsToolkit's `observation_policy(ObservationSet(...))` constructs the third form from typed
requests.

## Typed observations

The stable high-level observation set includes:

- `CellVolume`;
- `CellTypeObservable`;
- `CellBoundaryMeasure`;
- `CellPropertyValues`;
- `LatticeOwnership`.

Cell-valued requests produce generation-aware `CellSeries`. Ownership produces a `SpatialSeries`
with logical owners and cell metadata. `observation_table` joins compatible cell-valued series;
spatial series remain spatial.

## No hidden reads

`observe` reads values that the solution explicitly retained. It does not reconstruct an
undeclared quantity from private storage or silently synchronize a device. Request required data
before running.

The same rule applies to MakiePotts. `renderframe` and `renderframes` convert complete host snapshots
or declared host observations. Plot recipes consume `PottsRenderFrame`; they do not receive a live
integrator.

## Identity

Finite-cell slots can be retired and reused. Every longitudinal cell observation therefore carries
both `CellID` and `CellGeneration`. Joining by slot or integer ID alone can merge distinct
biological cells.

## Units

Lattice coordinates and MCS are dimensionless simulation values. `PhysicalScale` records an
explicit spatial/temporal calibration, and `with_units` presents a calibrated view. Calibration is
metadata supplied by the study; the engine does not infer physical time.
