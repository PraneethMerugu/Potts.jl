# Fields of a lattice field solution (LatticePDE, LatticeFields): a Makie recipe and a
# recording wrapper. The solution types and their reads come from LatticeFields.

"""
    FieldFrames(t, series; centers = nothing)

The saves of one field of a lattice field solution, as the field recipe reads them: the
save times `t`, the time-first values `series` (size `(length(t), dims...)`, a
LatticeFields `FieldSeries`) and the coordinates of the site centers on each axis
(`centers`, one vector per axis of length `dims[k]`, or `nothing` to count sites).
`field_frames(sol, c)` builds it.
"""
struct FieldFrames{TT, S <: AbstractArray, C}
    t::Vector{TT}
    series::S
    centers::C
    function FieldFrames(t::AbstractVector, series::AbstractArray; centers = nothing)
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
        dims = size(series)[2:end]
        cs = centers === nothing ? ntuple(k -> 1:dims[k], length(dims)) : Tuple(centers)
        length(cs) == length(dims) && all(k -> length(cs[k]) == dims[k], eachindex(dims)) ||
            throw(
            ArgumentError(
                "field frames: the centers have lengths $(map(length, cs)); the grid \
                    is $(join(dims, "×"))"
            )
        )
        tt = collect(t)
        return new{eltype(tt), typeof(series), typeof(cs)}(tt, series, cs)
    end
end

"""
    field_frames(sol, c) -> FieldFrames

The saves of field `c` of a lattice field solution `sol`: the solution of a problem from
`LatticePDE.discretize` (a field algorithm or an OrdinaryDiffEq solver) or a LatticeFields
`FieldSolution`. The centers are the system's coordinates when the solution has them
(`sol[x]`), else the site counts `1:n`.
"""
function field_frames(sol::Union{FieldSolution, LatticeSolution}, field)
    series = field_series(sol, field)
    dims = size(series)[2:end]
    return FieldFrames(sol.t, series; centers = _field_centers(site_centers(sol), dims))
end

# the centers of a grid of size `dims` from the lattice's site centers: the centers
# themselves, the node centers of a coarse grid (a node covers a block of `k` sites), or the
# site counts when the solution has no coordinates
_field_centers(::Nothing, dims) = nothing
function _field_centers(sites::Tuple, dims)
    length(sites) == length(dims) || return nothing
    return ntuple(length(dims)) do k
        r, n = sites[k], dims[k]
        length(r) == n && return collect(Float64, r)
        (n > 0 && length(r) % n == 0 && length(r) > 1) || return collect(Float64, 1:n)
        h = (last(r) - first(r)) / (length(r) - 1)
        b = length(r) ÷ n
        return [first(r) - h / 2 + (j - 1 / 2) * b * h for j in 1:n]
    end
end

# the save number `i`, checked
function _field_save(f::FieldFrames, i::Integer)
    1 <= i <= length(f.t) || throw(
        ArgumentError("field plot: save $i is outside 1:$(length(f.t))")
    )
    return Int(i)
end
function _field_save(f::FieldFrames, i)
    i === Makie.automatic && return length(f.t)
    throw(ArgumentError("field plot: `index` is a save number; got $(repr(i))"))
end

# the grid at save `i` (a host copy)
function _field_grid(f::FieldFrames, i)
    n = ndims(f.series) - 1
    return Array(f.series[_field_save(f, i), ntuple(_ -> Colon(), n)...])
end

# the plotted extent of each axis: the outer faces of the end sites
function _field_extent(c::AbstractVector)
    length(c) == 1 && return (first(c) - 0.5, first(c) + 0.5)
    lo = first(c) - (c[2] - c[1]) / 2
    hi = last(c) + (c[end] - c[end - 1]) / 2
    return (Float64(lo), Float64(hi))
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

The axes show the system's coordinates: each cell of the heatmap is centered at its site
center (`sol[x]`), and a coarse field's cell covers its block. A solution with no
coordinates counts sites instead, with site `i` centered at `i`. The axes and the grid size
follow the data: a new `solution` of another size redraws them (a 2D plot stays 2D).

# Arguments

  - `sol`: the solution.
  - `c`: the field.

# Keywords

  - `index = automatic`: the save to show; `automatic` is the last save. Give an
    `Observable` to change the save after plotting ([`record_field`](@ref) does this).
  - `colorrange = automatic`: the color limits; `automatic` takes the extrema of the field
    over all saves, so the colors stay fixed when `index` changes.
  - `colormap = :viridis`, `nan_color = :transparent`, `alpha = 1.0`, `visible = true`.
    `alpha` sets the opacity of the heatmap and of the volume.
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
    # the axes follow the data: centers in 2D, extents in 3D
    map!(f -> f.centers[1], plot, :frames, :xs)
    map!(f -> f.centers[2], plot, :frames, :ys)
    if ndims(plot.grid[]) == 2
        Makie.heatmap!(
            plot, plot.xs, plot.ys, plot.grid;
            colormap = plot.colormap, colorrange = plot.field_colorrange,
            nan_color = plot.nan_color, interpolate = plot.interpolate, alpha = plot.alpha,
            visible = plot.visible
        )
    else
        map!(f -> _field_extent(f.centers[1]), plot, :frames, :xextent)
        map!(f -> _field_extent(f.centers[2]), plot, :frames, :yextent)
        map!(f -> _field_extent(f.centers[3]), plot, :frames, :zextent)
        Makie.volume!(
            plot, plot.xextent, plot.yextent, plot.zextent, plot.grid;
            colormap = plot.colormap, colorrange = plot.field_colorrange,
            nan_color = plot.nan_color, algorithm = plot.algorithm,
            absorption = plot.absorption, alpha = plot.alpha, visible = plot.visible
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
    foreach(i -> _field_save(frames, i), idx)
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
