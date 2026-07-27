# MakiePotts v0.2 Visual and Interaction Specification

Status: Owner-approved after three visual audits

Date: 2026-07-26

## Makie behavior

- Reuse native Makie attribute names whenever meanings match.
- Inherit ordinary theme values; define only Potts-specific semantic defaults.
- Create plot primitives only. Never create axes, titles, legends, colorbars, or controls inside
  `PottsPlot`.
- Prefer `Axis` for 2D and slices and the appropriate native 3D container for true 3D.
- Preserve physical spacing, coordinate order, transformations, data limits, and ordinary axis
  overrides.
- Integrate with standard `Legend`, `Colorbar`, `DataInspector`, `save`, and `record`.

## Semantic defaults

- Biological cell type is the default encoding.
- Medium is visually neutral.
- Medium domains, finite cells, obstacles, fixed exterior, absent sites, missing values, and
  selected cells remain distinguishable.
- Categorical palettes never silently cycle. Automatic palettes expand deterministically.
- Continuous color ranges do not change frame-locally unless the user requests that behavior.
- Boundaries default to `automatic`: show thin ownership boundaries for type/property encodings and
  avoid redundant boundaries for identity encoding.
- Axes and spatial decorations remain visible by default.

## Inspection and selection

`DataInspector` reports lattice coordinates, MCS, owner category, cell ID, generation, biological
type, and encoded value when available. `inspectable=false` is respected.

The base recipe installs no selection behavior. Optional helpers attach ordinary Makie events and
expose selection as an Observable. Reference compositions use a compact generation-aware selection
summary and can link it to standard Makie plots.

## Explorer

The experimental explorer is plot-dominant and uses standard Makie Blocks. Exact saved MCS drives
the lattice and metric cursor through a shared Observable. Status and failures remain outside the
plot. Timers, tasks, and subscriptions are owned by a closable controller.
