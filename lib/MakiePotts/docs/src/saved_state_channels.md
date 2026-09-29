# [Saved-state channels](@id saved-state-channels)

MakiePotts renders only observations that a caller actually retained. This
example runs a small Potts model, derives a site-valued observation from each
saved state, projects it into a typed render frame, and uses that channel in an
ordinary Makie plot and recording.

```@example saved_state_channels
using CairoMakie
using MakiePotts
using ModelingToolkitBase: @named
using Potts

cell = Potts.CellKind(:cell; extinction=Potts.RetireAtZero())
medium = Potts.MediumKind(:medium)
@named visual = Potts.PottsSystem(statements=Potts.StatementSet((
    Potts.Lattice((8, 6)),
    cell,
    medium,
    Potts.Volume(cell; target=9.0, strength=1.0),
    Potts.Protocol(Potts.Sweep(; temperature=2.0); name=:main),
)))

labels = zeros(Int, 8, 6)
labels[3:5, 2:4] .= 1
initial = Potts.PottsInitialState(
    ownership=Potts.LabelledCells(labels; cells=[cell], medium),
)
problem = Potts.PottsProblem(
    Potts.mtkcompile(Potts.complete(visual)), initial, (0, 0); seed=11,
)
solution = Potts.solve(
    problem,
    Potts.SequentialCPM();
    backend=Potts.CPUBackend(),
    scalar_type=Float64,
)

saved = solution[end]
activity = Float32.(saved.ownership .!= 0)
activity_key = SiteChannelKey(:activity, Float32)
frame = renderframe(solution;
    channels=(RenderChannel(activity_key, activity; label="Activity"),))

encoded = encode(frame, ChannelEncoding(activity_key))
figure, axis, plot = CairoMakie.plot(
    frame; encoding=ChannelEncoding(activity_key), boundaries=true,
)
size(encoded.values) == size(saved.ownership) && plot isa PottsPlot
```

Site channels always describe the full saved domain. For a 3D state, an
`OrthogonalSlice` projects both ownership and site channels through the same
axis/index mapping:

```julia
request = RenderRequest(extent=OrthogonalSlice(3, 4))
frame = renderframe(saved, request;
    channels=(RenderChannel(activity_key, full_3d_activity),))
```

Cell channels use `RenderCellIdentity` keys, including the cell generation;
medium channels use positive domain IDs. `renderframe` rejects stale
generations, malformed keys, duplicate channel keys, wrong value types, and
site arrays that do not match the complete saved domain.

Channels that change between saved states are explicit ordinary Julia data.
Build independent frames with `map`, then record them:

```@example saved_state_channels
frames = map(eachindex(solution)) do index
    state = solution[index]
    values = Float32.(state.ownership .!= 0)
    renderframe(state;
        channels=(RenderChannel(activity_key, values; label="Activity"),))
end

recording = tempname() * ".gif"
Main.CITelemetry.record_duration("documentation.gif_recording"; kind="recording") do
    record_potts(recording, frames; framerate=2, figure=(; size=(240, 180)))
end
isfile(recording) && filesize(recording) > 0
```

MakiePotts does not infer a missing channel and does not add a callback API to
`renderframes`; explicit `map` keeps the retained observation and its lifetime
visible.
