@doc """
Abstract supertype for complete Potts render frames with `N` spatial
dimensions. Downstream implementations conform through the exported accessor
protocol and [`render_frame_conformance`](@ref).
""" AbstractPottsRenderFrame

@doc """Enumeration describing the semantic owner kind of one lattice site.""" RenderOwnerKind
@doc """A lattice site owned by a finite, generation-aware cell.""" CellSite
@doc """A mutable lattice site owned by a medium domain.""" MediumSite
@doc """An immutable lattice site owned by a medium domain.""" ObstacleSite

@doc """Abstract supertype for full-domain and projected render extents.""" AbstractRenderExtent
@doc """Abstract supertype for the scope carried by a typed render-channel key.""" AbstractRenderChannelScope
@doc """Marker scope for values defined independently at every lattice site.""" SiteChannelScope
@doc """Marker scope for values keyed by generation-aware finite-cell identity.""" CellChannelScope
@doc """Marker scope for values keyed by medium-domain identity.""" MediumChannelScope
@doc """Construct a site-scoped [`RenderChannelKey`](@ref).""" SiteChannelKey
@doc """Construct a finite-cell-scoped [`RenderChannelKey`](@ref).""" CellChannelKey
@doc """Construct a medium-domain-scoped [`RenderChannelKey`](@ref).""" MediumChannelKey
@doc """Abstract supertype for open, explicitly materialized channel requests.""" AbstractChannelRequest

@doc """Abstract supertype for semantic frame encodings consumed by Makie recipes.""" AbstractPottsEncoding
@doc """Whether an encoding produces categorical or continuous values.""" EncodingKind
@doc """The encoding produces semantic categories and a discrete legend.""" CategoricalEncoding
@doc """The encoding produces numeric values suitable for a Makie `Colorbar`.""" ContinuousEncoding

@doc """Return the Monte Carlo step represented by a render frame.""" frame_mcs
@doc """Return the spatial dimensions represented by a render frame.""" frame_size
@doc """Return the physical [`RenderGeometry`](@ref) of a render frame.""" frame_geometry
@doc """Return the semantic [`RenderOwner`](@ref) at `site`.""" owner_at
@doc """
Return generation-aware metadata for a finite-cell identity or semantic cell
owner. Downstream frames implement both call forms.
""" cell_metadata
@doc """Return the typed keys of all explicitly materialized frame channels.""" available_channels
@doc """Return the materialized channel matching `key`, or throw if absent.""" channel
@doc """Return the value-like source-lineage record carried by a frame.""" frame_provenance
@doc """Throw `InvalidRenderFrameError` unless the open accessor protocol conforms.""" assert_render_frame_conformance

@doc """Return whether an encoding is categorical or continuous.""" encoding_kind
@doc """Return the typed channels that must be present for an encoding.""" required_channels
@doc """Return the human-readable label of an encoding.""" encoding_label
@doc """Materialize semantic numeric values and legend metadata from a render frame.""" encode
@doc """Return a copy of the semantic legend entries produced by an encoding.""" legend_entries

@doc """Makie recipe type for a two-dimensional frame or orthogonal slice.""" PottsPlot
@doc """Add a [`PottsPlot`](@ref) to an existing Makie scene or axis.""" pottsplot!
@doc """Makie recipe type for a composable finite-cell boundary overlay.""" PottsBoundaries
@doc """Add a [`PottsBoundaries`](@ref) overlay to an existing Makie scene or axis.""" pottsboundaries!
@doc """Experimental Makie recipe type for a true three-dimensional frame.""" PottsVolume
@doc """Add an experimental [`PottsVolume`](@ref) to an existing Makie scene.""" pottsvolume!

@doc """Return the reactive status `Observable` of a [`RerunController`](@ref).""" rerun_status
@doc """Return the last completely published result `Observable` of a [`RerunController`](@ref).""" rerun_result
@doc """Return the latest rerun failure `Observable`, or one containing `nothing`.""" rerun_error
