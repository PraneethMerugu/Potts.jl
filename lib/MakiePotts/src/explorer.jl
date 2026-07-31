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

Build the experimental reference explorer from already materialized frames.
Call `close(explorer)` to release its slider subscription and optional
`DataInspector`; closing is idempotent.
"""
function explore_potts(frames::AbstractVector{<:AbstractPottsRenderFrame{2}};
        title::AbstractString = "Potts model", inspector::Bool = true,
        encoding::AbstractPottsEncoding = CellTypeEncoding(),
        figure = (;), axis = (;), plot = (;))
    isempty(frames) && throw(ArgumentError("the explorer requires at least one frame"))
    expected_geometry = frame_geometry(first(frames))
    all(frame -> frame_geometry(frame) == expected_geometry, frames) ||
        throw(ArgumentError("explorer frames must have compatible geometry"))

    fig = Makie.Figure(; figure...)
    ax = Makie.Axis(fig[1, 1];
        title = String(title), aspect = Makie.DataAspect(), axis...)
    index = Makie.Observable(1)
    frame = Makie.lift(i -> frames[i], index)
    rendered = pottsplot!(ax, frame; encoding, plot...)
    slider = Makie.Slider(fig[2, 1], range = eachindex(frames), startvalue = 1)
    subscription = Makie.on(slider.value) do value
        index[] = Int(value)
    end
    data_inspector = inspector ? Makie.DataInspector(fig) : nothing
    return PottsExplorer(fig, ax, rendered, slider, index,
        subscription, data_inspector, Ref(false))
end

function explore_potts(solution::PottsToolkit.PottsSolution;
        request::RenderRequest = RenderRequest(), kwargs...)
    return explore_potts(renderframes(solution, request); kwargs...)
end

Base.showable(::MIME"text/plain", ::PottsExplorer) = true
Base.show(io::IO, ::MIME"text/plain", explorer::PottsExplorer) =
    show(io, MIME"text/plain"(), explorer.figure)

Base.isopen(explorer::PottsExplorer) = !explorer.closed[]

function Base.close(explorer::PottsExplorer)
    explorer.closed[] && return explorer
    Makie.off(explorer.slider_subscription)
    explorer.inspector === nothing ||
        delete!(explorer.figure, explorer.inspector)
    explorer.closed[] = true
    return explorer
end

"""
Experimental latest-request-wins rerun coordinator. The `runner` executes
outside Makie recipes and must return a complete value before publication.
Call `close(controller)` to prevent in-flight or future requests from
publishing.
"""
mutable struct RerunController{F}
    runner::F
    generation::UInt64
    status::Makie.Observable{Symbol}
    result::Makie.Observable{Any}
    error::Makie.Observable{Any}
    closed::Bool
end

function RerunController(runner::F; initial = nothing) where {F}
    return RerunController{F}(runner, 0,
        Makie.Observable(:idle), Makie.Observable{Any}(initial),
        Makie.Observable{Any}(nothing), false)
end

rerun_status(controller::RerunController) = controller.status
rerun_result(controller::RerunController) = controller.result
rerun_error(controller::RerunController) = controller.error

"""
Start a nonblocking rerun. Only the latest requested generation may publish.
Failures leave the previous complete result intact.
"""
function rerun!(controller::RerunController, args...; kwargs...)
    controller.closed && throw(ArgumentError(
        "cannot rerun a closed RerunController; construct a new controller"))
    controller.generation += 1
    generation = controller.generation
    controller.status[] = :running
    controller.error[] = nothing
    return @async begin
        try
            candidate = controller.runner(args...; kwargs...)
            if generation == controller.generation
                controller.result[] = candidate
                controller.status[] = :succeeded
            end
        catch error
            if generation == controller.generation
                controller.error[] = (error, catch_backtrace())
                controller.status[] = :failed
            end
        end
        nothing
    end
end

Base.isopen(controller::RerunController) = !controller.closed

function Base.close(controller::RerunController)
    controller.closed && return controller
    controller.generation += 1
    controller.closed = true
    controller.error[] = nothing
    controller.status[] = :closed
    return controller
end
