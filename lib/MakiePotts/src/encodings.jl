abstract type AbstractPottsEncoding end

@enum EncodingKind::UInt8 begin
    CategoricalEncoding = 0x01
    ContinuousEncoding = 0x02
end

"""Encode finite cells by biological cell type; this is the default."""
struct CellTypeEncoding <: AbstractPottsEncoding
    label::String
end
CellTypeEncoding(; label::AbstractString = "Cell type") =
    CellTypeEncoding(String(label))

"""Encode finite cells by generation-aware identity."""
struct CellIdentityEncoding <: AbstractPottsEncoding
    label::String
end
CellIdentityEncoding(; label::AbstractString = "Cell identity") =
    CellIdentityEncoding(String(label))

"""Encode one requested numeric channel."""
struct ChannelEncoding{K <: RenderChannelKey} <: AbstractPottsEncoding
    key::K
    label::Union{Nothing, String}
end
function ChannelEncoding(key::RenderChannelKey; label = nothing)
    return ChannelEncoding(key, label === nothing ? nothing : String(label))
end

encoding_kind(::Union{CellTypeEncoding, CellIdentityEncoding}) = CategoricalEncoding
encoding_kind(::ChannelEncoding) = ContinuousEncoding
required_channels(::Union{CellTypeEncoding, CellIdentityEncoding}) = ()
required_channels(encoding::ChannelEncoding) = (encoding.key,)
encoding_label(encoding::Union{CellTypeEncoding, CellIdentityEncoding}) = encoding.label
encoding_label(encoding::ChannelEncoding) =
    encoding.label === nothing ? String(encoding.key.name) : encoding.label

"""One semantic categorical legend entry independent of any Makie Block."""
struct LegendEntry
    value
    label::String
    color_key::UInt64
end

"""
Numerical array plus semantic mapping produced by an encoding. Styling remains
in the recipe and may therefore inherit from Makie themes.
"""
struct EncodedPottsFrame{N, A <: AbstractArray{Float64, N}, E}
    values::A
    encoding::E
    categories::Vector{LegendEntry}
    label::String
    units::Union{Nothing, String}
    finite_range::Union{Nothing, Tuple{Float64, Float64}}
end

function _cell_identity(frame, owner::RenderOwner)
    metadata = cell_metadata(frame, owner)
    return metadata.identity
end

function encode(frame::AbstractPottsRenderFrame, encoding::CellTypeEncoding)
    type_ids = UInt32[]
    for site in CartesianIndices(frame_size(frame))
        owner = owner_at(frame, site)
        owner.kind === CellSite || continue
        push!(type_ids, cell_metadata(frame, owner).cell_type)
    end
    sort!(unique!(type_ids))
    code = Dict(type_id => index + 1 for (index, type_id) in pairs(type_ids))
    values = Array{Float64}(undef, frame_size(frame))
    for site in CartesianIndices(values)
        owner = owner_at(frame, site)
        values[site] = owner.kind === CellSite ?
                       code[cell_metadata(frame, owner).cell_type] : 1.0
    end
    entries = LegendEntry[LegendEntry(:medium, "Medium", 0)]
    append!(entries, [
        LegendEntry(type_id, "Cell type $type_id", UInt64(type_id))
        for type_id in type_ids
    ])
    return EncodedPottsFrame(values, encoding, entries,
        encoding.label, nothing, nothing)
end

function encode(frame::AbstractPottsRenderFrame, encoding::CellIdentityEncoding)
    identities = CellIdentity[]
    for site in CartesianIndices(frame_size(frame))
        owner = owner_at(frame, site)
        owner.kind === CellSite || continue
        push!(identities, _cell_identity(frame, owner))
    end
    sort!(unique!(identities); by = identity -> (identity.id, identity.generation))
    code = Dict(identity => index + 1 for (index, identity) in pairs(identities))
    values = Array{Float64}(undef, frame_size(frame))
    for site in CartesianIndices(values)
        owner = owner_at(frame, site)
        values[site] = owner.kind === CellSite ?
                       code[_cell_identity(frame, owner)] : 1.0
    end
    entries = LegendEntry[LegendEntry(:medium, "Medium", 0)]
    append!(entries, [
        LegendEntry(identity,
            "Cell $(identity.id) · generation $(identity.generation)",
            (UInt64(identity.id) << 32) ⊻ identity.generation)
        for identity in identities
    ])
    return EncodedPottsFrame(values, encoding, entries,
        encoding.label, nothing, nothing)
end

function _finite_range(values)
    finite = filter(isfinite, vec(values))
    isempty(finite) && return nothing
    extrema_values = extrema(finite)
    extrema_values[1] == extrema_values[2] &&
        return (extrema_values[1] - 0.5, extrema_values[2] + 0.5)
    return extrema_values
end

function encode(frame::AbstractPottsRenderFrame, encoding::ChannelEncoding)
    item = channel(frame, encoding.key)
    values = fill(NaN, frame_size(frame))
    if encoding.key isa RenderChannelKey{SiteChannelScope}
        for site in eachindex(values, item.values)
            raw = item.values[site]
            values[site] = ismissing(raw) ? NaN : Float64(raw)
        end
    elseif encoding.key isa RenderChannelKey{CellChannelScope}
        for site in CartesianIndices(values)
            owner = owner_at(frame, site)
            owner.kind === CellSite || continue
            identity = _cell_identity(frame, owner)
            raw = get(item.values, identity, missing)
            values[site] = ismissing(raw) ? NaN : Float64(raw)
        end
    elseif encoding.key isa RenderChannelKey{MediumChannelScope}
        for site in CartesianIndices(values)
            owner = owner_at(frame, site)
            owner.kind === CellSite && continue
            raw = get(item.values, owner.id, missing)
            values[site] = ismissing(raw) ? NaN : Float64(raw)
        end
    end
    label = encoding.label === nothing ? item.label : encoding.label
    return EncodedPottsFrame(values, encoding, LegendEntry[],
        label, item.units, _finite_range(values))
end

legend_entries(encoded::EncodedPottsFrame) = copy(encoded.categories)
legend_entries(frame::AbstractPottsRenderFrame, encoding::AbstractPottsEncoding) =
    legend_entries(encode(frame, encoding))

function _hsv_rgb(h::Float64, s::Float64 = 0.62, v::Float64 = 0.88)
    sector = 6h
    i = floor(Int, sector)
    f = sector - i
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    r, g, b = if mod(i, 6) == 0
        (v, t, p)
    elseif mod(i, 6) == 1
        (q, v, p)
    elseif mod(i, 6) == 2
        (p, v, t)
    elseif mod(i, 6) == 3
        (p, q, v)
    elseif mod(i, 6) == 4
        (t, p, v)
    else
        (v, p, q)
    end
    return Makie.RGBf(r, g, b)
end

_stable_category_color(key::UInt64) =
    _hsv_rgb(mod(Float64(key) * 0.6180339887498949, 1.0))

function _categorical_colors(entries::Vector{LegendEntry}, palette, medium_color)
    isempty(entries) && return Makie.RGBf[]
    if palette === Makie.automatic
        colors = Makie.RGBf[Makie.to_color(medium_color)]
        append!(colors, [_stable_category_color(entry.color_key) for entry in entries[2:end]])
        return colors
    end
    requested = length(entries) - 1
    supplied = Makie.to_colormap(palette)
    length(supplied) >= requested || throw(ArgumentError(
        "category palette supplies $(length(supplied)) colors for $requested categories; " *
        "MakiePotts never cycles palettes silently"))
    return vcat([Makie.to_color(medium_color)], supplied[1:requested])
end
