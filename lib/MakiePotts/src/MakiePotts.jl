"""
Native Makie recipes and explicit, visualization-neutral render contracts for
Potts solutions.
"""
module MakiePotts

import Makie
import Potts
import PrecompileTools

include("errors.jl")
include("requests.jl")
include("frames.jl")
include("encodings.jl")
include("potts_saved_state.jl")
include("recipes.jl")
include("inspection.jl")
include("recording.jl")
include("explorer.jl")
include("precompile.jl")

export AbstractPottsRenderFrame, PottsRenderFrame
export RenderOwner, RenderOwnerKind, CellSite, MediumSite, ObstacleSite
export RenderCellIdentity, RenderCellMetadata, RenderGeometry, RenderProvenance
export frame_mcs, frame_size, frame_geometry, owner_at, cell_metadata
export available_channels, channel, frame_provenance
export RenderFrameConformance, render_frame_conformance
export assert_render_frame_conformance

export AbstractRenderExtent, FullDomain, OrthogonalSlice
export AbstractRenderChannelScope, SiteChannelScope, CellChannelScope, MediumChannelScope
export RenderChannelKey, RenderChannel, SiteChannelKey, CellChannelKey, MediumChannelKey
export RenderRequest, renderframe, renderframes

export AbstractPottsEncoding, CellTypeEncoding, CellIdentityEncoding, ChannelEncoding
export EncodingKind, CategoricalEncoding, ContinuousEncoding
export encoding_kind, required_channels, encoding_label, encode
export EncodedPottsFrame, LegendEntry, legend_entries

export PottsPlot, pottsplot, pottsplot!
export PottsBoundaries, pottsboundaries, pottsboundaries!
export PottsVolume, pottsvolume, pottsvolume!
export potts_theme, potts_legend
export inspection_label, record_potts

export PottsExplorer, explore_potts

end
