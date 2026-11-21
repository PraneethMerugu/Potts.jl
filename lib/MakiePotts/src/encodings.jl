"""Abstract supertype for semantic frame encodings consumed by Makie recipes."""
abstract type AbstractPottsEncoding end

"""Whether an encoding produces categorical or continuous values."""
@enum EncodingKind::UInt8 begin
    CategoricalEncoding = 0x01
    ContinuousEncoding = 0x02
end
@doc "The encoding produces semantic categories and a discrete legend." CategoricalEncoding
@doc "The encoding produces numeric values suitable for a Makie \
    `Colorbar`." ContinuousEncoding

"""
    CellTypeEncoding(; label = "Cell type")

Color cells by kind (the frame's `cell_type`). This is the default encoding of the plot
recipes.

Categorical: medium and obstacle sites take the first category, and each kind
present in the frame takes the next ones in increasing order.

# Keywords

  - `label::AbstractString = "Cell type"`: the title of the legend.

# Fields

  - `label::String`: as given.

# Examples

```jldoctest
julia> using MakiePotts

julia> encoding_label(CellTypeEncoding())
"Cell type"
```

See also [`CellIdentityEncoding`](@ref), [`encode_frame`](@ref).
"""
struct CellTypeEncoding <: AbstractPottsEncoding
    label::String
end
function CellTypeEncoding(; label::AbstractString = "Cell type")
    return CellTypeEncoding(String(label))
end

"""
    CellIdentityEncoding(; label = "Cell identity")

Color cells by identity, so that each cell has its own color.

Categorical: medium and obstacle sites take the first category, and each cell identity
(number and generation) present in the frame takes the next ones in increasing order.
The default colors depend only on the identity, so a cell keeps its color across frames.

# Keywords

  - `label::AbstractString = "Cell identity"`: the title of the legend.

# Fields

  - `label::String`: as given.

# Examples

```jldoctest
julia> using MakiePotts

julia> encoding_kind(CellIdentityEncoding()) == CategoricalEncoding
true
```

See also [`CellTypeEncoding`](@ref), [`encode_frame`](@ref).
"""
struct CellIdentityEncoding <: AbstractPottsEncoding
    label::String
end
function CellIdentityEncoding(; label::AbstractString = "Cell identity")
    return CellIdentityEncoding(String(label))
end

"""
    ChannelEncoding(key; label = nothing)

Color sites by the values of the channel with key `key`.

Continuous: a site channel colors each site, a cell channel colors the sites of each cell
and a medium channel colors the medium and obstacle sites. Sites outside the channel's
scope and `missing` values are `NaN` (drawn in the plot's `nan_color`).

# Arguments

  - `key::RenderChannelKey`: the channel. The frame must have it.

# Keywords

  - `label = nothing`: the title; `nothing` uses the channel's `label`.

# Fields

  - `key`: as given.
  - `label::Union{Nothing, String}`: as given.

# Examples

```jldoctest
julia> using MakiePotts

julia> required_channels(ChannelEncoding(SiteChannelKey(:c, Float64)))
(site channel :c::Float64,)
```

See also [`RenderChannel`](@ref), [`encode_frame`](@ref).
"""
struct ChannelEncoding{K <: RenderChannelKey} <: AbstractPottsEncoding
    key::K
    label::Union{Nothing, String}
end
function ChannelEncoding(key::RenderChannelKey; label = nothing)
    return ChannelEncoding(key, label === nothing ? nothing : String(label))
end

"""
    encoding_kind(encoding) -> EncodingKind

Return whether an encoding is categorical or continuous.

# Arguments

  - `encoding`: a [`CellTypeEncoding`](@ref), [`CellIdentityEncoding`](@ref) or
    [`ChannelEncoding`](@ref).

# Returns

  - `EncodingKind`: [`CategoricalEncoding`](@ref) for the two cell encodings,
    [`ContinuousEncoding`](@ref) for `ChannelEncoding`.

# Examples

```jldoctest
julia> using MakiePotts

julia> encoding_kind(CellTypeEncoding()) == CategoricalEncoding
true
```

See also [`required_channels`](@ref).
"""
encoding_kind(::Union{CellTypeEncoding, CellIdentityEncoding}) = CategoricalEncoding
encoding_kind(::ChannelEncoding) = ContinuousEncoding
"""
    required_channels(encoding) -> Tuple

Return the keys of the channels a frame must have for `encoding`.

# Arguments

  - `encoding`: a [`CellTypeEncoding`](@ref), [`CellIdentityEncoding`](@ref) or
    [`ChannelEncoding`](@ref).

# Returns

  - `Tuple`: `()` for the two cell encodings, `(encoding.key,)` for `ChannelEncoding`.

# Examples

```jldoctest
julia> using MakiePotts

julia> required_channels(CellTypeEncoding())
()
```

See also [`encoding_kind`](@ref).
"""
required_channels(::Union{CellTypeEncoding, CellIdentityEncoding}) = ()
required_channels(encoding::ChannelEncoding) = (encoding.key,)
"""
    encoding_label(encoding) -> String

Return the title of an encoding.

# Arguments

  - `encoding`: a [`CellTypeEncoding`](@ref), [`CellIdentityEncoding`](@ref) or
    [`ChannelEncoding`](@ref).

# Returns

  - `String`: the `label` of the encoding. For a `ChannelEncoding` with no `label`, the
    name of its key.

# Examples

```jldoctest
julia> using MakiePotts

julia> encoding_label(ChannelEncoding(SiteChannelKey(:c, Float64)))
"c"
```

See also [`EncodedPottsFrame`](@ref).
"""
encoding_label(encoding::Union{CellTypeEncoding, CellIdentityEncoding}) = encoding.label
function encoding_label(encoding::ChannelEncoding)
    return encoding.label === nothing ? String(encoding.key.name) : encoding.label
end

"""
    MakiePotts.LegendEntry(value, label, color_key)

One entry of a categorical legend, independent of Makie.

`MakiePotts.LegendEntry` is public but not exported, because Makie exports a
`LegendEntry` of its own.

# Fields

  - `value`: the category: `:medium`, a kind number or a
    [`RenderCellIdentity`](@ref).
  - `label::String`: the text of the entry, for example `"Cell type 2"`.
  - `color_key::UInt64`: the key of the default color of the category; `0` for the
    medium.

See also [`legend_entries`](@ref), [`potts_legend`](@ref).
"""
struct LegendEntry
    value
    label::String
    color_key::UInt64
end

"""
    EncodedPottsFrame

The numbers that an encoding gives a frame, with the meaning of each category.

[`encode_frame`](@ref) makes it. The colors are chosen by the plot recipe, so a Makie
theme applies to them.

# Fields

  - `values::AbstractArray{Float64, N}`: one number per site. Categorical encodings give
    the category number, from 1; continuous encodings give the value or `NaN`.
  - `encoding`: the encoding.
  - `categories::Vector{MakiePotts.LegendEntry}`: one entry per category, in category
    order; empty for a continuous encoding.
  - `label::String`: the title.
  - `units::Union{Nothing, String}`: the channel units, or `nothing`.
  - `finite_range::Union{Nothing, Tuple{Float64, Float64}}`: the extrema of the finite
    values of a continuous encoding (widened by 0.5 on each side when they are equal), or
    `nothing`.

See also [`legend_entries`](@ref).
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

"""
    encode_frame(frame, encoding) -> EncodedPottsFrame

Return the numbers that `encoding` gives each site of `frame`, with the categories.

The categories of [`CellTypeEncoding`](@ref) are named `"Medium"` and `"Cell type n"`;
those of [`CellIdentityEncoding`](@ref) are named `"Medium"` and
`"Cell n · generation g"`. See [`ChannelEncoding`](@ref) for the continuous case.

# Arguments

  - `frame::AbstractPottsRenderFrame`: the frame.
  - `encoding`: the encoding. A `ChannelEncoding` throws
    `MakiePotts.MissingRenderChannelError` when `frame` has no channel with its key.

# Returns

  - [`EncodedPottsFrame`](@ref): the encoded frame.

# Examples

```jldoctest
julia> using MakiePotts

julia> c, m = RenderOwner(CellSite, 1), RenderOwner(MediumSite, 1);

julia> cell = RenderCellMetadata(RenderCellIdentity(1, 1), 3);

julia> encode_frame(PottsRenderFrame(0, [c m; c m], [cell]), CellTypeEncoding()).values
2×2 Matrix{Float64}:
 2.0  1.0
 2.0  1.0
```

See also [`legend_entries`](@ref).
"""
function encode_frame(frame::AbstractPottsRenderFrame, encoding::CellTypeEncoding)
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
        values[site] = if owner.kind === CellSite
            code[cell_metadata(frame, owner).cell_type]
        else
            1.0
        end
    end
    entries = LegendEntry[LegendEntry(:medium, "Medium", 0)]
    append!(
        entries, [
            LegendEntry(type_id, "Cell type $type_id", UInt64(type_id))
                for type_id in type_ids
        ]
    )
    return EncodedPottsFrame(
        values, encoding, entries,
        encoding.label, nothing, nothing
    )
end

function encode_frame(frame::AbstractPottsRenderFrame, encoding::CellIdentityEncoding)
    identities = RenderCellIdentity[]
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
        values[site] = if owner.kind === CellSite
            code[_cell_identity(frame, owner)]
        else
            1.0
        end
    end
    entries = LegendEntry[LegendEntry(:medium, "Medium", 0)]
    append!(
        entries, [
            LegendEntry(
                identity,
                "Cell $(identity.id) · generation $(identity.generation)",
                (UInt64(identity.id) << 32) ⊻ identity.generation
            )
                for identity in identities
        ]
    )
    return EncodedPottsFrame(
        values, encoding, entries,
        encoding.label, nothing, nothing
    )
end

function _finite_range(values)
    finite = filter(isfinite, vec(values))
    isempty(finite) && return nothing
    extrema_values = extrema(finite)
    extrema_values[1] == extrema_values[2] &&
        return (extrema_values[1] - 0.5, extrema_values[2] + 0.5)
    return extrema_values
end

function encode_frame(frame::AbstractPottsRenderFrame, encoding::ChannelEncoding)
    item = frame_channel(frame, encoding.key)
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
    return EncodedPottsFrame(
        values, encoding, LegendEntry[],
        label, item.units, _finite_range(values)
    )
end

"""
    legend_entries(encoded::EncodedPottsFrame) -> Vector{MakiePotts.LegendEntry}
    legend_entries(frame, encoding) -> Vector{MakiePotts.LegendEntry}

Return a copy of the categories of an encoded frame, or of `encode_frame(frame, encoding)`.

# Arguments

  - `encoded::EncodedPottsFrame`: the encoded frame.
  - `frame::AbstractPottsRenderFrame`, `encoding::AbstractPottsEncoding`: as for
    [`encode_frame`](@ref).

# Returns

  - `Vector{MakiePotts.LegendEntry}`: the categories; empty for a continuous encoding.

# Examples

```jldoctest
julia> using MakiePotts

julia> c, m = RenderOwner(CellSite, 1), RenderOwner(MediumSite, 1);

julia> cell = RenderCellMetadata(RenderCellIdentity(1, 1), 3);

julia> frame = PottsRenderFrame(0, [c m; c m], [cell]);

julia> [e.label for e in legend_entries(frame, CellTypeEncoding())]
2-element Vector{String}:
 "Medium"
 "Cell type 3"
```

See also [`potts_legend`](@ref).
"""
legend_entries(encoded::EncodedPottsFrame) = copy(encoded.categories)
function legend_entries(frame::AbstractPottsRenderFrame, encoding::AbstractPottsEncoding)
    return legend_entries(encode_frame(frame, encoding))
end

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

# splitmix64 finalizer (Steele, Lea & Flood 2014): a fixed bijection of UInt64, so colours
# never depend on Julia's `hash`, the session or the frame.
function _splitmix64(x::UInt64)
    x += 0x9e3779b97f4a7c15
    x = (x ⊻ (x >> 30)) * 0xbf58476d1ce4e5b9
    x = (x ⊻ (x >> 27)) * 0x94d049bb133111eb
    return x ⊻ (x >> 31)
end

# Small keys (cell types) take golden-ratio hues, which stay well spaced for the first few
# categories. Keys from 2^32 up (generation-aware cell identities, `id << 32 ⊻ generation`)
# would alias under that formula (frac(2^32 φ⁻¹) ≈ 0.497, and Float64 loses the low bits),
# so they are scrambled with splitmix64 and the top 53 bits become the hue (D-172).
function _stable_category_color(key::UInt64)
    key < UInt64(1) << 32 && return _hsv_rgb(mod(Float64(key) * 0.6180339887498949, 1.0))
    return _hsv_rgb(Float64(_splitmix64(key) >> 11) * 2.0^-53)
end

function _categorical_colors(entries::Vector{LegendEntry}, palette, medium_color)
    isempty(entries) && return Makie.RGBf[]
    if palette === Makie.automatic
        colors = Makie.RGBf[Makie.to_color(medium_color)]
        append!(
            colors, [
                _stable_category_color(entry.color_key)
                    for entry in entries[2:end]
            ]
        )
        return colors
    end
    requested = length(entries) - 1
    supplied = Makie.to_colormap(palette)
    length(supplied) >= requested || throw(
        ArgumentError(
            "category palette supplies $(length(supplied)) colors for $requested " *
                "categories; MakiePotts never cycles palettes silently"
        )
    )
    return vcat([Makie.to_color(medium_color)], supplied[1:requested])
end
