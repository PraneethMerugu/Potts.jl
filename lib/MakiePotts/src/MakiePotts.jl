"""
Native Makie recipes and explicit, visualization-neutral render contracts for
CorePotts simulations.
"""
module MakiePotts

import CorePotts
import Makie
import PottsToolkit
import PrecompileTools

include("errors.jl")
include("requests.jl")
include("frames.jl")
include("encodings.jl")
include("adapters.jl")
include("recipes.jl")
include("inspection.jl")
include("recording.jl")
include("explorer.jl")
include("public_api_docs.jl")
include("precompile.jl")

export AbstractPottsRenderFrame, PottsRenderFrame
export RenderOwner, RenderOwnerKind, CellSite, MediumSite, ObstacleSite
export CellIdentity, RenderCellMetadata, RenderGeometry, RenderProvenance
export frame_mcs, frame_size, frame_geometry, owner_at, cell_metadata
export available_channels, channel, frame_provenance
export RenderFrameConformance, render_frame_conformance
export assert_render_frame_conformance

export AbstractRenderExtent, FullDomain, OrthogonalSlice
export AbstractRenderChannelScope, SiteChannelScope, CellChannelScope, MediumChannelScope
export RenderChannelKey, RenderChannel, SiteChannelKey, CellChannelKey, MediumChannelKey
export AbstractChannelRequest, CellPropertyRequest, RenderRequest
export renderframe, renderframes, materialize_channel

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
export RerunController, rerun!, rerun_status, rerun_result, rerun_error

end
