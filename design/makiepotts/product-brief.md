# MakiePotts v0.2 Product Brief

Status: Owner-approved implementation scope

Date: 2026-07-26

## Product direction

MakiePotts is a native Makie extension package, not a visualization application beside Makie.
Its priorities are:

1. publication figures and animations;
2. composition in custom Makie figures and dashboards;
3. parameter-driven reruns; and
4. general solution exploration.

The stable center is a backend-neutral render-frame and recipe contract. Recording is a limited
convenience over `Makie.record`. Explorer and rerun controllers are experimental reference
compositions of ordinary Makie recipes, Blocks, Observables, and SciML problem transformations.

## Product laws

- Every rendered value originates from an explicit host snapshot or declared observation boundary.
- Plot conversion never solves, mutates simulation state, synchronizes a backend, transfers device
  data, or computes an unsaved observable.
- Static, reactive, interactive, and recorded output use the same recipe.
- Makie owns figures, axes, themes, transformations, legends, colorbars, inspection, saving,
  recording, and backend selection.
- MakiePotts owns Potts-specific semantic frames, encodings, source adapters, and optional
  convenience composition.
- Scientific identity is generation-aware; reusable storage slots are never biological identity.
- The package uses documented Makie extension APIs and introduces no backend-specific public
  semantics.

## Stability

- Stable: render frames, render requests, channels, encodings, source adapters, 2D/slice recipes,
  boundaries, and inspection.
- Limited: recording convenience.
- Experimental: true-3D volume rendering, explorer, and rerun controller.

The deferred pre-freeze implementation receives no compatibility shim. Familiar names are retained
only where their new meaning remains coherent.
