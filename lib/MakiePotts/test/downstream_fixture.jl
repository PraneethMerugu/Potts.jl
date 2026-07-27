module DownstreamFixture

using MakiePotts
import CorePotts
import MakiePotts: available_channels, cell_metadata, channel, encode
import MakiePotts: encoding_kind, encoding_label, frame_geometry, frame_mcs
import MakiePotts: frame_provenance, frame_size, materialize_channel
import MakiePotts: owner_at, required_channels

const SIGNAL_KEY = SiteChannelKey(:foreign_signal, Float64)

"""
Downstream-style frame whose dictionaries and column names deliberately do not
match the canonical `PottsRenderFrame` layout.
"""
struct ColumnarFrame <: AbstractPottsRenderFrame{2}
    stamp::Int
    shape::NTuple{2, Int}
    spatial::RenderGeometry{2, Float64}
    site_records::Dict{CartesianIndex{2}, RenderOwner}
    identity_records::Dict{CellIdentity, RenderCellMetadata}
    owner_records::Dict{UInt32, RenderCellMetadata}
    stream_records::Dict{Any, Any}
    lineage::RenderProvenance
end

frame_mcs(frame::ColumnarFrame) = frame.stamp
frame_size(frame::ColumnarFrame) = frame.shape
frame_geometry(frame::ColumnarFrame) = frame.spatial
owner_at(frame::ColumnarFrame, site) = frame.site_records[site]
cell_metadata(frame::ColumnarFrame, identity::CellIdentity) =
    frame.identity_records[identity]
cell_metadata(frame::ColumnarFrame, owner::RenderOwner) =
    frame.owner_records[owner.id]
available_channels(frame::ColumnarFrame) = Tuple(keys(frame.stream_records))
channel(frame::ColumnarFrame, key::RenderChannelKey) = frame.stream_records[key]
frame_provenance(frame::ColumnarFrame) = frame.lineage

function columnar_frame(phase::Integer = 0)
    shape = (4, 3)
    spatial = RenderGeometry(shape;
        spacing = (0.75, 1.25), origin = (-1.5, 2.0))
    first_identity = CellIdentity(11, 4)
    second_identity = CellIdentity(29, 8)
    first_metadata = RenderCellMetadata(first_identity, 2; label = "Alpha")
    second_metadata = RenderCellMetadata(second_identity, 5; label = "Beta")
    owners = RenderOwner[
        RenderOwner(MediumSite, 1) RenderOwner(CellSite, 11) RenderOwner(CellSite, 11);
        RenderOwner(CellSite, 29) RenderOwner(CellSite, 11) RenderOwner(CellSite, 11);
        RenderOwner(CellSite, 29) RenderOwner(CellSite, 29) RenderOwner(ObstacleSite, 2);
        RenderOwner(MediumSite, 1) RenderOwner(CellSite, 29) RenderOwner(ObstacleSite, 2);
    ]
    phase == 0 || reverse!(owners; dims = 2)
    site_records = Dict(site => owners[site] for site in CartesianIndices(shape))
    identity_records = Dict(
        first_identity => first_metadata,
        second_identity => second_metadata,
    )
    owner_records = Dict(
        first_identity.id => first_metadata,
        second_identity.id => second_metadata,
    )
    values = [
        phase + 0.0 phase + 0.2 phase + 0.4;
        phase + 0.1 phase + 0.3 phase + 0.5;
        phase + 0.2 phase + 0.4 NaN;
        phase + 0.3 phase + 0.5 NaN;
    ]
    stream_records = Dict{Any, Any}(
        SIGNAL_KEY => RenderChannel(
            SIGNAL_KEY, values; label = "Foreign signal", units = "a.u."),
    )
    lineage = RenderProvenance(
        :downstream_fixture, ColumnarFrame, :host, RenderRequest())
    return ColumnarFrame(Int(phase), shape, spatial, site_records,
        identity_records, owner_records, stream_records, lineage)
end

"""Custom request supplied by a downstream package."""
struct CheckerboardRequest <: AbstractChannelRequest
    key::typeof(SIGNAL_KEY)
end
CheckerboardRequest() = CheckerboardRequest(SIGNAL_KEY)

function materialize_channel(state::CorePotts.LogicalPottsState, cells,
        request::CheckerboardRequest)
    dims = CorePotts.lattice_size(state)
    values = Array{Float64}(undef, dims)
    for site in CartesianIndices(values)
        values[site] = isodd(sum(Tuple(site))) ? 0.25 : 0.75
    end
    return RenderChannel(request.key, values;
        label = "Checkerboard", units = "fraction")
end

"""Custom continuous encoding supplied by a downstream package."""
struct RootSignalEncoding <: AbstractPottsEncoding
    key::typeof(SIGNAL_KEY)
end
RootSignalEncoding() = RootSignalEncoding(SIGNAL_KEY)

encoding_kind(::RootSignalEncoding) = ContinuousEncoding
required_channels(encoding::RootSignalEncoding) = (encoding.key,)
encoding_label(::RootSignalEncoding) = "Square-root signal"

function encode(frame::AbstractPottsRenderFrame, encoding::RootSignalEncoding)
    source = channel(frame, encoding.key)
    values = map(source.values) do value
        ismissing(value) || !isfinite(value) ? NaN : sqrt(Float64(value))
    end
    finite = filter(isfinite, vec(values))
    limits = if isempty(finite)
        nothing
    else
        lower, upper = extrema(finite)
        lower == upper ? (lower - 0.5, upper + 0.5) : (lower, upper)
    end
    return EncodedPottsFrame(values, encoding, LegendEntry[],
        encoding_label(encoding), source.units, limits)
end

end
