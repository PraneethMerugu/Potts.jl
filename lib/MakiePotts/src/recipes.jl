function _image_extents(geometry::RenderGeometry{2})
    return ntuple(Val(2)) do axis
        first = geometry.origin[axis]
        last = first + geometry.spacing[axis] * geometry.size[axis]
        (first, last)
    end
end

function _heatmap_edges(geometry::RenderGeometry{2})
    return ntuple(Val(2)) do axis
        first = geometry.origin[axis]
        last = first + geometry.spacing[axis] * geometry.size[axis]
        range(first, last; length = geometry.size[axis] + 1)
    end
end

function _semantic_overlay(frame::AbstractPottsRenderFrame{2},
        encoding::AbstractPottsEncoding, medium_color, obstacle_color)
    transparent = Makie.RGBAf(0, 0, 0, 0)
    medium = Makie.to_color(medium_color)
    obstacle = Makie.to_color(obstacle_color)
    overlay_medium = encoding isa ChannelEncoding &&
                     encoding.key isa RenderChannelKey{CellChannelScope}
    result = Matrix{Makie.RGBAf}(undef, frame_size(frame))
    for site in CartesianIndices(result)
        owner = owner_at(frame, site)
        result[site] = if owner.kind === ObstacleSite
            obstacle
        elseif overlay_medium && owner.kind === MediumSite
            medium
        else
            transparent
        end
    end
    return result
end

function _resolved_colormap(encoded, continuous_colormap, category_palette, medium_color)
    encoding_kind(encoded.encoding) === CategoricalEncoding ||
        return continuous_colormap
    return Makie.Categorical(
        _categorical_colors(encoded.categories, category_palette, medium_color))
end

function _plot_colorrange(encoded, requested)
    requested === Makie.automatic || return requested
    if encoding_kind(encoded.encoding) === CategoricalEncoding
        return (0.5, length(encoded.categories) + 0.5)
    end
    return encoded.finite_range === nothing ? (0.0, 1.0) : encoded.finite_range
end

function _boundary_segments(frame::AbstractPottsRenderFrame{2})
    geometry = frame_geometry(frame)
    nx, ny = frame_size(frame)
    dx, dy = geometry.spacing
    ox, oy = geometry.origin
    points = Makie.Point2f[]
    for j in 1:ny, i in 1:(nx - 1)
        owner_at(frame, CartesianIndex(i, j)) ==
            owner_at(frame, CartesianIndex(i + 1, j)) && continue
        x = ox + i * dx
        y0 = oy + (j - 1) * dy
        push!(points, Makie.Point2f(x, y0), Makie.Point2f(x, y0 + dy))
    end
    for j in 1:(ny - 1), i in 1:nx
        owner_at(frame, CartesianIndex(i, j)) ==
            owner_at(frame, CartesianIndex(i, j + 1)) && continue
        y = oy + j * dy
        x0 = ox + (i - 1) * dx
        push!(points, Makie.Point2f(x0, y), Makie.Point2f(x0 + dx, y))
    end
    return points
end

"""
    pottsboundaries(frame; color=:black, linewidth=1)

Composable semantic boundary overlay for a two-dimensional frame.
"""
Makie.@recipe(PottsBoundaries, frame) do scene
    Makie.Attributes(
        color = Makie.theme(scene, :linecolor; default = :black),
        linewidth = Makie.theme(scene, :linewidth; default = 1.0),
        linestyle = nothing,
        visible = true,
        inspectable = false,
    )
end

function Makie.plot!(plot::PottsBoundaries)
    segments = Makie.lift(_boundary_segments, plot.frame)
    Makie.linesegments!(plot, segments;
        color = plot.color, linewidth = plot.linewidth,
        linestyle = plot.linestyle, visible = plot.visible,
        inspectable = plot.inspectable)
    return plot
end

"""
    pottsplot(frame; encoding=CellTypeEncoding(), kwargs...)

Native Makie recipe for validated two-dimensional Potts render frames.
"""
Makie.@recipe(PottsPlot, frame) do scene
    Makie.Attributes(
        encoding = CellTypeEncoding(),
        colormap = Makie.theme(scene, :colormap; default = :viridis),
        category_palette = Makie.automatic,
        colorrange = Makie.automatic,
        colorscale = identity,
        medium_color = :gray18,
        obstacle_color = :gray45,
        nan_color = :transparent,
        lowclip = Makie.automatic,
        highclip = Makie.automatic,
        interpolate = false,
        boundaries = false,
        boundary_color = Makie.theme(scene, :linecolor; default = :black),
        boundary_width = Makie.theme(scene, :linewidth; default = 1.0),
        visible = true,
        alpha = 1.0,
        inspectable = true,
        inspector_label = Makie.automatic,
    )
end

function Makie.plot!(plot::PottsPlot)
    encoded = Makie.lift(encode, plot.frame, plot.encoding)
    coordinates = Makie.lift(_image_extents ∘ frame_geometry, plot.frame)
    image_xs = Makie.lift(first, coordinates)
    image_ys = Makie.lift(last, coordinates)
    edges = Makie.lift(_heatmap_edges ∘ frame_geometry, plot.frame)
    heatmap_xs = Makie.lift(first, edges)
    heatmap_ys = Makie.lift(last, edges)
    values = Makie.lift(item -> item.values, encoded)
    colormap = Makie.lift(
        _resolved_colormap, encoded, plot.colormap,
        plot.category_palette, plot.medium_color)
    colorrange = Makie.lift(_plot_colorrange, encoded, plot.colorrange)
    labeler = Makie.lift(plot.inspector_label, plot.frame, plot.encoding) do custom, frame, enc
        custom === Makie.automatic ?
        ((child, index, position) -> inspection_label(frame, enc, index)) : custom
    end

    Makie.heatmap!(plot, heatmap_xs, heatmap_ys, values;
        colormap, colorrange, colorscale = plot.colorscale,
        nan_color = plot.nan_color, lowclip = plot.lowclip,
        highclip = plot.highclip, interpolate = plot.interpolate,
        visible = plot.visible, alpha = plot.alpha,
        inspectable = plot.inspectable, inspector_label = labeler)

    semantic_overlay = Makie.lift(
        _semantic_overlay, plot.frame, plot.encoding,
        plot.medium_color, plot.obstacle_color)
    Makie.image!(plot, image_xs, image_ys, semantic_overlay;
        interpolate = false, visible = plot.visible, inspectable = false)

    pottsboundaries!(plot, plot.frame;
        color = plot.boundary_color, linewidth = plot.boundary_width,
        visible = plot.boundaries, inspectable = false)
    return plot
end

Makie.plottype(::AbstractPottsRenderFrame{2}) = PottsPlot
Makie.convert_arguments(::Type{<:PottsPlot},
    frame::AbstractPottsRenderFrame{2}) = (frame,)
Makie.used_attributes(::Type{<:PottsPlot},
    ::AbstractPottsRenderFrame{2}) = ()
Makie.preferred_axis_type(::Type{<:PottsPlot}) = Makie.Axis
Makie.preferred_axis_type(::AbstractPottsRenderFrame{2}) = Makie.Axis
Makie.preferred_axis_attributes(::Type{Makie.Axis},
    ::Type{<:PottsPlot}) = (aspect = Makie.DataAspect(),)

function Makie.data_limits(plot::PottsPlot)
    geometry = frame_geometry(plot.frame[])
    return Makie.Rect3d(
        Makie.Point3d(geometry.origin[1], geometry.origin[2], 0),
        Makie.Vec3d(geometry.size[1] * geometry.spacing[1],
            geometry.size[2] * geometry.spacing[2], 0))
end

Makie.boundingbox(plot::PottsPlot, ::Symbol = :data) =
    Makie.apply_transform_and_model(plot, Makie.data_limits(plot))

function Makie.extract_colormap(plot::PottsPlot)
    isempty(plot.plots) && return nothing
    return Makie.extract_colormap(plot.plots[1])
end

"""A compact theme fragment suitable for `with_theme` or `set_theme!`."""
function potts_theme(; medium_color = :gray18, obstacle_color = :gray45,
        boundary_color = :black, boundary_width = 1.0, kwargs...)
    return Makie.Theme(
        PottsPlot = (
            medium_color = medium_color,
            obstacle_color = obstacle_color,
            boundary_color = boundary_color,
            boundary_width = boundary_width,
        );
        kwargs...)
end

function _legend_elements(encoded, palette, medium_color)
    colors = _categorical_colors(encoded.categories, palette, medium_color)
    elements = [Makie.PolyElement(color = color) for color in colors]
    labels = [entry.label for entry in encoded.categories]
    return elements, labels
end

"""
    potts_legend(position, plot; title=nothing, kwargs...)

Construct a native Makie `Legend` for a categorical `PottsPlot`.
"""
function potts_legend(position, plot::PottsPlot; title = nothing, kwargs...)
    encoded = encode(plot.frame[], plot.encoding[])
    encoding_kind(encoded.encoding) === CategoricalEncoding ||
        throw(ArgumentError("continuous Potts encodings use `Colorbar(position, plot)`"))
    elements, labels = _legend_elements(
        encoded, plot.category_palette[], plot.medium_color[])
    if any(site -> owner_at(plot.frame[], site).kind === ObstacleSite,
            CartesianIndices(frame_size(plot.frame[])))
        push!(elements, Makie.PolyElement(color = plot.obstacle_color[]))
        push!(labels, "Obstacle")
    end
    resolved_title = title === nothing ? encoded.label : title
    return Makie.Legend(position, elements, labels, resolved_title; kwargs...)
end

"""
Experimental true-three-dimensional volume recipe. Orthogonal slices should use
the stable `PottsPlot` recipe.
"""
Makie.@recipe(PottsVolume, frame) do scene
    Makie.Attributes(
        encoding = CellTypeEncoding(),
        colormap = Makie.theme(scene, :colormap; default = :viridis),
        category_palette = Makie.automatic,
        colorrange = Makie.automatic,
        medium_color = :gray18,
        nan_color = :transparent,
        algorithm = :mip,
        absorption = 1.0,
        visible = true,
    )
end

function Makie.plot!(plot::PottsVolume)
    encoded = Makie.lift(encode, plot.frame, plot.encoding)
    values = Makie.lift(item -> item.values, encoded)
    colormap = Makie.lift(
        _resolved_colormap, encoded, plot.colormap,
        plot.category_palette, plot.medium_color)
    colorrange = Makie.lift(_plot_colorrange, encoded, plot.colorrange)
    Makie.volume!(plot, values;
        colormap, colorrange, nan_color = plot.nan_color,
        algorithm = plot.algorithm, absorption = plot.absorption,
        visible = plot.visible)
    return plot
end

Makie.plottype(::AbstractPottsRenderFrame{3}) = PottsVolume
Makie.convert_arguments(::Type{<:PottsVolume},
    frame::AbstractPottsRenderFrame{3}) = (frame,)
Makie.used_attributes(::Type{<:PottsVolume},
    ::AbstractPottsRenderFrame{3}) = ()
Makie.preferred_axis_type(::Type{<:PottsVolume}) = Makie.LScene
Makie.preferred_axis_type(::AbstractPottsRenderFrame{3}) = Makie.LScene

function Makie.extract_colormap(plot::PottsVolume)
    isempty(plot.plots) && return nothing
    return Makie.extract_colormap(plot.plots[1])
end
