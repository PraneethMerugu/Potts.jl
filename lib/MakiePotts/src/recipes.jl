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

function _semantic_overlay(
        frame::AbstractPottsRenderFrame{2},
        encoding::AbstractPottsEncoding, medium_color, obstacle_color
    )
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
        _categorical_colors(encoded.categories, category_palette, medium_color)
    )
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
        inspectable = false
    )
end
@doc "Makie recipe type for a composable finite-cell boundary overlay." PottsBoundaries
@doc "Add a [`PottsBoundaries`](@ref) overlay to an existing Makie scene or \
    axis." pottsboundaries!

# The recipes compute their children's inputs with `map!` on the plot's compute graph, so a
# change of any attribute (not only of the frame) reaches the children and the screen. The
# graph is lazy, so the first frame and attributes are checked at once here: a bad input
# throws its own error when the plot is made, not a wrapped one at the first draw.
function _check_first_inputs(plot; colors = true)
    frame = assert_render_frame_conformance(plot.frame[])
    colors || return nothing
    encoded = encode_frame(frame, plot.encoding[])
    _resolved_colormap(
        encoded, plot.colormap[], plot.category_palette[], plot.medium_color[]
    )
    _plot_colorrange(encoded, plot.colorrange[])
    return nothing
end

function Makie.plot!(plot::PottsBoundaries)
    _check_first_inputs(plot; colors = false)
    map!(assert_render_frame_conformance, plot, :frame, :validated_frame)
    map!(_boundary_segments, plot, :validated_frame, :segments)
    Makie.linesegments!(
        plot, plot.segments;
        color = plot.color, linewidth = plot.linewidth,
        linestyle = plot.linestyle, visible = plot.visible,
        inspectable = plot.inspectable
    )
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
        inspector_label = Makie.automatic
    )
end
@doc "Makie recipe type for a two-dimensional frame or orthogonal slice." PottsPlot
@doc "Add a [`PottsPlot`](@ref) to an existing Makie scene or axis." pottsplot!

function Makie.plot!(plot::PottsPlot)
    _check_first_inputs(plot)
    map!(assert_render_frame_conformance, plot, :frame, :validated_frame)
    map!(encode_frame, plot, [:validated_frame, :encoding], :encoded)
    map!(plot, :validated_frame, [:image_xs, :image_ys]) do frame
        extents = _image_extents(frame_geometry(frame))
        return (first(extents), last(extents))
    end
    map!(plot, :validated_frame, [:heatmap_xs, :heatmap_ys]) do frame
        edges = _heatmap_edges(frame_geometry(frame))
        return (first(edges), last(edges))
    end
    map!(item -> item.values, plot, :encoded, :encoded_values)
    map!(
        _resolved_colormap, plot,
        [:encoded, :colormap, :category_palette, :medium_color], :resolved_colormap
    )
    map!(_plot_colorrange, plot, [:encoded, :colorrange], :resolved_colorrange)
    labeler_inputs = [:inspector_label, :validated_frame, :encoding]
    map!(plot, labeler_inputs, :labeler) do custom, frame, enc
        if custom === Makie.automatic
            return (child, index, position) -> inspection_label(frame, enc, index)
        else
            return custom
        end
    end

    Makie.heatmap!(
        plot, plot.heatmap_xs, plot.heatmap_ys, plot.encoded_values;
        colormap = plot.resolved_colormap, colorrange = plot.resolved_colorrange,
        colorscale = plot.colorscale,
        nan_color = plot.nan_color, lowclip = plot.lowclip,
        highclip = plot.highclip, interpolate = plot.interpolate,
        visible = plot.visible, alpha = plot.alpha,
        inspectable = plot.inspectable, inspector_label = plot.labeler
    )

    map!(
        _semantic_overlay, plot,
        [:validated_frame, :encoding, :medium_color, :obstacle_color], :semantic_overlay
    )
    Makie.image!(
        plot, plot.image_xs, plot.image_ys, plot.semantic_overlay;
        interpolate = false, visible = plot.visible, inspectable = false
    )

    pottsboundaries!(
        plot, plot.validated_frame;
        color = plot.boundary_color, linewidth = plot.boundary_width,
        visible = plot.boundaries, inspectable = false
    )
    return plot
end

Makie.plottype(::AbstractPottsRenderFrame{2}) = PottsPlot
function Makie.convert_arguments(
        ::Type{<:PottsPlot},
        frame::AbstractPottsRenderFrame{2}
    )
    return (frame,)
end
function Makie.used_attributes(
        ::Type{<:PottsPlot},
        ::AbstractPottsRenderFrame{2}
    )
    return ()
end
Makie.preferred_axis_type(::Type{<:PottsPlot}) = Makie.Axis
Makie.preferred_axis_type(::AbstractPottsRenderFrame{2}) = Makie.Axis
function Makie.preferred_axis_attributes(
        ::Type{Makie.Axis},
        ::Type{<:PottsPlot}
    )
    return (aspect = Makie.DataAspect(),)
end

function Makie.data_limits(plot::PottsPlot)
    geometry = frame_geometry(plot.frame[])
    return Makie.Rect3d(
        Makie.Point3d(geometry.origin[1], geometry.origin[2], 0),
        Makie.Vec3d(
            geometry.size[1] * geometry.spacing[1],
            geometry.size[2] * geometry.spacing[2], 0
        )
    )
end

function Makie.boundingbox(plot::PottsPlot, ::Symbol = :data)
    return Makie.apply_transform_and_model(plot, Makie.data_limits(plot))
end

function Makie.extract_colormap(plot::PottsPlot)
    isempty(plot.plots) && return nothing
    return Makie.extract_colormap(plot.plots[1])
end

"""A compact theme fragment suitable for `with_theme` or `set_theme!`."""
function potts_theme(;
        medium_color = :gray18, obstacle_color = :gray45,
        boundary_color = :black, boundary_width = 1.0, kwargs...
    )
    return Makie.Theme(
        PottsPlot = (
            medium_color = medium_color,
            obstacle_color = obstacle_color,
            boundary_color = boundary_color,
            boundary_width = boundary_width,
        );
        kwargs...
    )
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
    encoded = encode_frame(plot.frame[], plot.encoding[])
    encoding_kind(encoded.encoding) === CategoricalEncoding ||
        throw(ArgumentError("continuous Potts encodings use `Colorbar(position, plot)`"))
    elements, labels = _legend_elements(
        encoded, plot.category_palette[], plot.medium_color[]
    )
    if any(
            site -> owner_at(plot.frame[], site).kind === ObstacleSite,
            CartesianIndices(frame_size(plot.frame[]))
        )
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
        visible = true
    )
end
@doc "Makie recipe type for a true three-dimensional frame." PottsVolume
@doc "Add a [`PottsVolume`](@ref) to an existing Makie scene." pottsvolume!

function Makie.plot!(plot::PottsVolume)
    _check_first_inputs(plot)
    map!(assert_render_frame_conformance, plot, :frame, :validated_frame)
    map!(encode_frame, plot, [:validated_frame, :encoding], :encoded)
    map!(item -> item.values, plot, :encoded, :encoded_values)
    map!(
        _resolved_colormap, plot,
        [:encoded, :colormap, :category_palette, :medium_color], :resolved_colormap
    )
    map!(_plot_colorrange, plot, [:encoded, :colorrange], :resolved_colorrange)
    Makie.volume!(
        plot, plot.encoded_values;
        colormap = plot.resolved_colormap, colorrange = plot.resolved_colorrange,
        nan_color = plot.nan_color,
        algorithm = plot.algorithm, absorption = plot.absorption,
        visible = plot.visible
    )
    return plot
end

Makie.plottype(::AbstractPottsRenderFrame{3}) = PottsVolume
function Makie.convert_arguments(
        ::Type{<:PottsVolume},
        frame::AbstractPottsRenderFrame{3}
    )
    return (frame,)
end
function Makie.used_attributes(
        ::Type{<:PottsVolume},
        ::AbstractPottsRenderFrame{3}
    )
    return ()
end
Makie.preferred_axis_type(::Type{<:PottsVolume}) = Makie.LScene
Makie.preferred_axis_type(::AbstractPottsRenderFrame{3}) = Makie.LScene

function Makie.extract_colormap(plot::PottsVolume)
    isempty(plot.plots) && return nothing
    return Makie.extract_colormap(plot.plots[1])
end
