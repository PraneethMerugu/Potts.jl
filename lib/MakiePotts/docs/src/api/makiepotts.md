# [MakiePotts API](@id makiepotts-api)

MakiePotts converts explicit saved host observations into render frames and
ordinary Makie recipes. It never advances a simulation, mutates state,
implicitly synchronizes a device, or reconstructs an unsaved channel.

| Task | Primary names |
|:--|:--|
| Materialize frames | `RenderRequest`, `renderframe`, `renderframes`, `PottsRenderFrame` |
| Select geometry | `FullDomain`, `OrthogonalSlice` |
| Represent retained channels | `RenderChannel`, `SiteChannelKey`, `CellChannelKey`, `MediumChannelKey` |
| Encode | `CellTypeEncoding`, `CellIdentityEncoding`, `ChannelEncoding` |
| Plot | `pottsplot`, `pottsplot!`, `pottsboundaries!`, `pottsvolume!`, `potts_legend` |
| Record | `record_potts` |

The stable boundary is the immutable render frame, not a Potts runtime object.
`PottsExplorer` and `explore_potts` are exported experimental
interfaces: they may change within the pre-1.0 series and are not covered by
the stable render-frame contract.

The native `PottsSavedState` adapter materializes ownership and cell metadata.
A saved state does not carry arbitrary retained observations, so callers attach
such data explicitly:

```julia
renderframe(saved_state, request;
    channels=(RenderChannel(channel_key, retained_values),))
```

Site-channel arrays must cover the complete saved domain and are projected by
the same `FullDomain` or `OrthogonalSlice` mapping as ownership. Cell and medium
channels remain generation-aware or domain-ID-keyed dictionaries. Each returned
frame defensively owns its projected data.

```text
saved state → validated frame → semantic encoding → Makie plot or recording
```

Validation occurs at frame construction and again through the open accessor
protocol before rendering. Plot recipes consume only that protocol; they do not
reach back into simulation state.

```@example makie_boundary
using MakiePotts
required = (
    :PottsRenderFrame,
    :RenderRequest,
    :renderframe,
    :CellTypeEncoding,
    :pottsplot,
)
all(name -> isdefined(MakiePotts, name), required)
```

## Reference

```@autodocs
Modules = [MakiePotts]
Private = false
```
