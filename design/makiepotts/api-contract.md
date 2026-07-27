# MakiePotts v0.2 API Contract

Status: Owner-approved implementation contract

Date: 2026-07-26

## Frame boundary

`AbstractPottsRenderFrame{N}` is the open recipe boundary.
`PottsRenderFrame{N}` is MakiePotts' canonical validated implementation. Frames contain semantic
ownership, geometry, generation-aware cell metadata, explicitly requested channels, and
provenance. They do not contain visual styling or precolored pixels.

The stable interface is accessor-based:

```julia
frame_mcs(frame)
frame_size(frame)
frame_geometry(frame)
owner_at(frame, site)
cell_metadata(frame, identity_or_cell_owner)
available_channels(frame)
channel(frame, key)
frame_provenance(frame)
```

Physical field layout and private caches are not part of the contract.
`PottsRenderFrame` owns defensive copies of its input arrays and dictionaries
and is treated as a logically immutable snapshot. Julia does not mechanically
hide concrete struct fields, so callers extend and consume the accessor
protocol rather than relying on read-only backing storage.

## Requests and conversion

`RenderRequest` is immutable and data-only. It declares ownership, cell metadata, requested
channels, and `FullDomain()` or `OrthogonalSlice(axis, index)` extent. It contains no color, theme,
or layout preferences.

`renderframe(source, request)` is explicit. Recipe conversion may invoke it only when conversion is
host-local, deterministic, and free of undeclared materialization. Device snapshots and live
integrators are never implicitly materialized.

`plot(frame)` selects `PottsPlot`. CorePotts states and solutions use `pottsplot` when generic
`plot` interpretation would be ambiguous. Extensions implement ordinary Julia methods; there is no
runtime registry and no type piracy.

## Frozen-API additions

CorePotts adds stable accessors for problem geometry, a solution's originating problem, and saved
snapshot MCS, residency, and explicitly retained host state. PottsToolkit adds
visualization-neutral ownership/spatial observation values with accessor-based traversal. Neither
addition changes frozen execution, RNG, checkpoint, algorithm, or solution semantics.

## Recipes

`PottsPlot` owns 2D frames and orthogonal slices. `PottsVolume` is a separate experimental true-3D
recipe. Common boundaries may be a child of `PottsPlot`; independently useful semantic overlays
remain composable recipes. Existing Makie recipes are used directly for ordinary fields, contours,
surfaces, arrows, and time series.

Encodings form an open protocol declaring required channels, categorical or continuous meaning,
value extraction, missing-value policy, legend/colorbar metadata, stable identity, and display
label. The central recipe does not switch over a closed encoding list.

## Reactive contract

Frames and compatible attributes accept Observables. Child plots are created once and updated
through Makie's reactive pipeline. A published frame is complete and valid. Expensive conversion
finishes before an Observable is updated. Failed conversion leaves the previous valid frame
visible.
