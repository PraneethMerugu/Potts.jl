# Fields of a lattice field solution (LatticePDE, LatticeFields): a Makie recipe and a
# recording wrapper. The solution types live in LatticeFields, a weak dependency: the
# extension `MakiePottsLatticeFieldsExt` adds the `field_frames` methods that read them.

"""
    FieldFrames(t, series)

The saves of one field of a lattice field solution, as the field recipe reads them: the
save times `t` and the time-first values `series` (size `(length(t), dims...)`, a
LatticeFields `FieldSeries`). `field_frames(sol, c)` builds it when LatticeFields is loaded.
"""
struct FieldFrames{TT, S <: AbstractArray}
    t::Vector{TT}
    series::S
    function FieldFrames(t::AbstractVector, series::AbstractArray)
        length(t) == size(series, 1) || throw(
            ArgumentError(
                "field frames: $(length(t)) save times but $(size(series, 1)) saves"
            )
        )
        length(t) > 0 || throw(ArgumentError("field frames: the solution has no saves"))
        ndims(series) in (3, 4) || throw(
            ArgumentError(
                "field frames: a field plot needs a 2D or 3D field; got a \
                $(ndims(series) - 1)D one"
            )
        )
        tt = collect(t)
        return new{eltype(tt), typeof(series)}(tt, series)
    end
end

"""
    field_frames(sol, c) -> FieldFrames

The saves of field `c` of a lattice field solution `sol`. The methods come with the
LatticeFields extension: for the solution of a problem from `LatticePDE.discretize` (a
field algorithm or an OrdinaryDiffEq solver) and for a LatticeFields `FieldSolution`.
"""
function field_frames end

# the grid at save `i` (a host copy)
function _field_grid(f::FieldFrames, i::Integer)
    1 <= i <= length(f.t) || throw(
        ArgumentError("field plot: save $i is outside 1:$(length(f.t))")
    )
    n = ndims(f.series) - 1
    return Array(f.series[i, ntuple(_ -> Colon(), n)...])
end
function _field_grid(f::FieldFrames, i)
    i === Makie.automatic && return _field_grid(f, length(f.t))
    throw(ArgumentError("field plot: `index` is a save number; got $(repr(i))"))
end

# the color range over every save, so the colors of a video do not drift
function _field_colorrange(f::FieldFrames, range)
    range === Makie.automatic || return range
    lo, hi = Inf, -Inf
    for i in eachindex(f.t)
        for v in _field_grid(f, i)
            isfinite(v) || continue
            lo = min(lo, Float64(v))
            hi = max(hi, Float64(v))
        end
    end
    lo > hi && return (0.0, 1.0)
    lo == hi && return (lo - 0.5, hi + 0.5)
    return (lo, hi)
end

"""
    fieldplot(sol, c; index = automatic, kwargs...)
    fieldplot!(ax, sol, c; index = automatic, kwargs...)

Plot field `c` of a lattice field solution at one save: a heatmap of a 2D field and a
volume of a 3D field. `sol` is the solution of a problem from `LatticePDE.discretize`,
solved by a field algorithm or an OrdinaryDiffEq solver, or a LatticeFields
`FieldSolution`. `c` is any key that `sol[c]` takes: the variable, `c(t, x, y)` or `:c`.
The methods come with LatticeFields: load LatticePDE (or LatticeFields) beside MakiePotts.

The axes count sites: site `(i, j)` covers `[i - 1/2, i + 1/2] × [j - 1/2, j + 1/2]`.

# Arguments

  - `sol`: the solution.
  - `c`: the field.

# Keywords

  - `index = automatic`: the save to show; `automatic` is the last save. Give an
    `Observable` to change the save after plotting ([`record_field`](@ref) does this).
  - `colorrange = automatic`: the color limits; `automatic` takes the extrema of the field
    over all saves, so the colors stay fixed when `index` changes.
  - `colormap = :viridis`, `nan_color = :transparent`, `alpha = 1.0`, `visible = true`.
  - `interpolate = false`: smooth the heatmap of a 2D field.
  - `algorithm = :mip`, `absorption = 1.0`: the volume rendering of a 3D field, as in
    Makie's `volume`.

# Returns

A `FieldPlot`. The non-mutating form returns Makie's `FigureAxisPlot`.

# Examples

```julia
using LatticePDE, MakiePotts, CairoMakie
fig, ax, plt = fieldplot(sol, c)               # the last save
i = Observable(1)
fieldplot!(Axis(fig[1, 2]), sol, c; index = i)
i[] = 5                                        # show save 5
```
"""
Makie.@recipe(FieldPlot, solution, field) do scene
    Makie.Attributes(
        index = Makie.automatic,
        colormap = :viridis,
        colorrange = Makie.automatic,
        nan_color = :transparent,
        interpolate = false,
        algorithm = :mip,
        absorption = 1.0,
        alpha = 1.0,
        visible = true
    )
end
@doc "Makie recipe type of [`fieldplot`](@ref): a field of a lattice solution." FieldPlot
@doc "Add a [`fieldplot`](@ref) to an existing axis or scene." fieldplot!

function Makie.preferred_axis_type(::Type{<:FieldPlot}, solution, field)
    return ndims(field_frames(solution, field).series) == 4 ? Makie.LScene : Makie.Axis
end
function Makie.preferred_axis_attributes(::Type{Makie.Axis}, ::Type{<:FieldPlot})
    return (aspect = Makie.DataAspect(),)
end

function Makie.plot!(plot::FieldPlot)
    map!(field_frames, plot, [:solution, :field], :frames)
    map!(_field_grid, plot, [:frames, :index], :grid)
    map!(_field_colorrange, plot, [:frames, :colorrange], :field_colorrange)
    dims = size(plot.grid[])
    if length(dims) == 2
        Makie.heatmap!(
            plot, 1:dims[1], 1:dims[2], plot.grid;
            colormap = plot.colormap, colorrange = plot.field_colorrange,
            nan_color = plot.nan_color, interpolate = plot.interpolate, alpha = plot.alpha,
            visible = plot.visible
        )
    else
        Makie.volume!(
            plot, (0.5, dims[1] + 0.5), (0.5, dims[2] + 0.5), (0.5, dims[3] + 0.5),
            plot.grid;
            colormap = plot.colormap, colorrange = plot.field_colorrange,
            nan_color = plot.nan_color, algorithm = plot.algorithm,
            absorption = plot.absorption, visible = plot.visible
        )
    end
    return plot
end

function Makie.extract_colormap(plot::FieldPlot)
    isempty(plot.plots) && return nothing
    return Makie.extract_colormap(plot.plots[1])
end

"""
    record_field(filename, sol, c; indices = automatic, framerate = 15, kwargs...)

Write a video of field `c` of a lattice field solution `sol`: one frame per save, each a
[`fieldplot`](@ref) with a color bar and the save time as the title. The color range is
fixed over all saves. The file is written whole or not at all.

# Arguments

  - `filename`: the output file; its extension (`.mp4`, `.gif`, …) sets the format.
  - `sol`, `c`: as for [`fieldplot`](@ref).

# Keywords

  - `indices = automatic`: the saves to record, in order; `automatic` is every save.
  - `framerate = 15`: frames per second.
  - `title = "c"`: the title before the time; it defaults to the field's name.
  - `colorbar = true`: draw a color bar.
  - `figure = (;)`, `axis = (;)`, `plot = (;)`: keywords of the figure, the axis and
    the [`fieldplot`](@ref).

# Returns

`filename`.

# Examples

```julia
using LatticePDE, MakiePotts, CairoMakie
record_field("c.mp4", sol, c; framerate = 10)
```
"""
function record_field(
        filename::AbstractString, sol, field;
        indices = Makie.automatic, framerate::Real = 15,
        title::AbstractString = _field_title(field), colorbar::Bool = true,
        figure = (;), axis = (;), plot = (;)
    )
    rate = _validate_framerate(framerate)
    frames = field_frames(sol, field)
    idx = indices === Makie.automatic ? eachindex(frames.t) : indices
    isempty(idx) && throw(ArgumentError("record_field: no saves to record"))
    foreach(i -> _field_grid(frames, i), (first(idx), last(idx)))
    three = ndims(frames.series) == 4
    fig = Makie.Figure(; figure...)
    index = Makie.Observable(first(idx))
    label = Makie.lift(i -> string(title, ", t = ", _field_time(frames.t[i])), index)
    ax = if three
        Makie.Axis3(fig[1, 1]; title = label, aspect = :data, axis...)
    else
        Makie.Axis(fig[1, 1]; title = label, aspect = Makie.DataAspect(), axis...)
    end
    plt = fieldplot!(ax, sol, field; index, plot...)
    colorbar && Makie.Colorbar(fig[1, 2], plt)
    return _atomic_record(filename) do temporary
        Makie.record(fig, temporary, idx; framerate = rate) do i
            index[] = i
        end
    end
end

_field_title(field) = string(field)
_field_title(field::Symbol) = String(field)
_field_time(t::AbstractFloat) = string(round(t; sigdigits = 4))
_field_time(t) = string(t)
