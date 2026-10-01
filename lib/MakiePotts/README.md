# MakiePotts

> **Development disclosure:** Substantial portions of this pre-release codebase,
> tests, and documentation were developed with generative-AI assistance and
> remain subject to maintainer review.

MakiePotts v0.3 turns explicit Potts observations into native Makie recipes.

```julia
using MakiePotts
using CairoMakie

owners = fill(RenderOwner(MediumSite, 1), 3, 2)
frame = PottsRenderFrame(0, owners, RenderCellMetadata[])
fig, axis, plot = plot(frame; boundaries = true)
potts_legend(fig[1, 2], plot)
```

The stable API centers on:

- validated `PottsRenderFrame` snapshots that defensively own their inputs;
- data-only spatial `RenderRequest` values and explicit typed render channels;
- open encoding and frame-accessor protocols;
- `PottsPlot` for 2D domains and orthogonal 3D slices;
- normal Makie composition, themes, `Observable`s, `DataInspector`, `Legend`,
  `Colorbar`, `save`, and `record`.

`renderframe` is deliberately explicit. It never transfers backend state or
reconstructs an observation that was not retained. Native `PottsSavedState`
values contain ownership and cell metadata; retained site, cell, or medium data
can be attached as typed channels:

```julia
signal = SiteChannelKey(:signal, Float32)
frame = renderframe(saved_state;
    channels = (RenderChannel(signal, retained_signal),))
```

Site arrays describe the complete saved domain and follow the same full-domain
or orthogonal-slice projection as ownership. Cell and medium channels remain
identity-keyed dictionaries. No scientific channel is inferred.

`PottsVolume` and `PottsExplorer` are experimental. The
frame, request, channel, encoding, 2D recipe, boundary, inspection, and limited
recording contracts are release-candidate behavior for the v0.3 line.

`record_potts` validates inputs and replaces its destination only after a
successful temporary recording. Experimental explorers are explicitly closable
with `close`.

The ordinary package and backend tests exercise an unrelated downstream frame
implementation and custom encoding extensions,
CairoMakie/GLMakie/WGLMakie, tolerant visual regression, allocation
measurements, strict documentation, and a clean install-to-PNG workflow.
