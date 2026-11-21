"""
Reference composition of native Makie Blocks. The explorer owns no rendering
semantics; its central display is an ordinary `PottsPlot`.
"""
struct PottsExplorer{F, A, P, S, I, O, D}
    figure::F
    axis::A
    plot::P
    slider::S
    frame_index::I
    slider_subscription::O
    inspector::D
    closed::Base.RefValue{Bool}
end

"""
    explore_potts(frames; title="Potts model", inspector=true, kwargs...)
    explore_potts(solution; request=RenderRequest(), kwargs...)

Build the experimental reference explorer from already materialized frames, or from the
states of `solution`: a `PottsSolution`, or `CorePotts.PottsFrames`, whose frames are read
and rendered one at a time, when the slider shows them.
Call `close(explorer)` to release its slider subscription and optional
`DataInspector`; closing is idempotent.
"""
function explore_potts(
        frames::AbstractVector{<:AbstractPottsRenderFrame{2}};
        title::AbstractString = "Potts model", inspector::Bool = true,
        encoding::AbstractPottsEncoding = CellTypeEncoding(),
        figure = (;), axis = (;), plot = (;)
    )
    isempty(frames) && throw(ArgumentError("the explorer requires at least one frame"))
    expected_geometry = frame_geometry(first(frames))
    all(frame -> frame_geometry(frame) == expected_geometry, frames) ||
        throw(ArgumentError("explorer frames must have compatible geometry"))
    return _explorer(
        i -> frames[i], eachindex(frames); title, inspector, encoding, figure, axis, plot
    )
end

function explore_potts(
        solution::CorePotts.PottsSolution;
        request::RenderRequest = RenderRequest(), kwargs...
    )
    return explore_potts(renderframes(solution, request); kwargs...)
end

function explore_potts(
        frames::CorePotts.PottsFrames;
        request::RenderRequest = RenderRequest(), kwargs...
    )
    first_frame = _first_written_frame(frames, request)
    getframe(i) = _next_written_frame(frames, request, i, first_frame)
    return _explorer(getframe, eachindex(frames.t); kwargs...)
end

# the explorer of the frames `getframe(i)`, `i` in `indices` (each built when shown)
function _explorer(
        getframe::F, indices;
        title::AbstractString = "Potts model", inspector::Bool = true,
        encoding::AbstractPottsEncoding = CellTypeEncoding(),
        figure = (;), axis = (;), plot = (;)
    ) where {F}
    fig = Makie.Figure(; figure...)
    ax = Makie.Axis(
        fig[1, 1];
        title = String(title), aspect = Makie.DataAspect(), axis...
    )
    index = Makie.Observable(first(indices))
    frame = Makie.lift(getframe, index)
    rendered = pottsplot!(ax, frame; encoding, plot...)
    slider = Makie.Slider(fig[2, 1], range = indices, startvalue = first(indices))
    subscription = Makie.on(slider.value) do value
        index[] = Int(value)
    end
    data_inspector = inspector ? Makie.DataInspector(fig) : nothing
    return PottsExplorer(
        fig, ax, rendered, slider, index,
        subscription, data_inspector, Ref(false)
    )
end

Base.showable(::MIME"text/plain", ::PottsExplorer) = true
function Base.show(io::IO, ::MIME"text/plain", explorer::PottsExplorer)
    return show(io, MIME"text/plain"(), explorer.figure)
end

Base.isopen(explorer::PottsExplorer) = !explorer.closed[]

function Base.close(explorer::PottsExplorer)
    explorer.closed[] && return explorer
    Makie.off(explorer.slider_subscription)
    explorer.inspector === nothing ||
        delete!(explorer.figure, explorer.inspector)
    explorer.closed[] = true
    return explorer
end
