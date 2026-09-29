# MakiePotts.jl

MakiePotts provides rendering recipes, inspection views, recording, and
interactive exploration for Potts simulations.

```@example makiepotts_quickstart
using MakiePotts

owners = fill(RenderOwner(MediumSite, 1), 3, 2)
frame = PottsRenderFrame(0, owners, RenderCellMetadata[])
frame_size(frame)
```

`renderframe(saved_state)` materializes ownership and generation-aware cell
metadata retained by a native Potts saved state. Explicit typed channels can be
attached during the same conversion; MakiePotts never reconstructs an unsaved
scientific value.
The package has one rendering boundary:

```text
PottsSavedState → renderframe → PottsRenderFrame → encode → Makie recipe
                                                    ↓
                                               record_potts
```

`PottsRenderFrame` is the canonical visualization value. Saved-state conversion
is one source adapter; downstream packages may instead implement the documented
frame accessor protocol without inheriting Potts runtime storage.

Continue with the [saved-state channel tutorial](@ref saved-state-channels) for
a complete solve-to-recording workflow.
