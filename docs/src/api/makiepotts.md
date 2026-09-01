# [MakiePotts API](@id makiepotts-api)

MakiePotts converts explicit saved host observations into render frames and
ordinary Makie recipes. It never advances a simulation, mutates state,
implicitly synchronizes a device, or reconstructs an unsaved channel.

| Task | Primary names |
|:--|:--|
| Materialize frames | `RenderRequest`, `renderframe`, `renderframes`, `PottsRenderFrame` |
| Select geometry | `FullDomain`, `OrthogonalSlice` |
| Request channels | `CellPropertyRequest`, `RenderChannel`, `materialize_channel` |
| Encode | `CellTypeEncoding`, `CellIdentityEncoding`, `ChannelEncoding` |
| Plot | `pottsplot`, `pottsplot!`, `pottsboundaries!`, `pottsvolume!`, `potts_legend` |
| Record | `record_potts` |

The stable boundary is the immutable render frame, not a CorePotts runtime
object. `PottsExplorer`, `explore_potts`, `RerunController`, `reexecute!`, and
the rerun-state accessors are exported experimental interfaces: they may change
within the pre-1.0 series and are not covered by the stable render-frame
contract.

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
