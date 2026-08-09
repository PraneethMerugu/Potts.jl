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
object. The explorer and rerun controller remain experimental and are not
promoted by their export status.

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
