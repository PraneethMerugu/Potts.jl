"""Abstract supertype for full-domain and projected render extents."""
abstract type AbstractRenderExtent end

"""Request the full two- or three-dimensional ownership domain."""
struct FullDomain <: AbstractRenderExtent end

"""
    OrthogonalSlice(axis, index)

Request the two-dimensional slice of a 3D source at `index` along array axis `axis`.

The slice keeps the other two axes in their order and records them in the frame geometry
(`source_axes`). [`renderframe`](@ref) throws an `ArgumentError` for a slice of a 2D
source and a `BoundsError` for an `index` past the end of the axis.

# Arguments

  - `axis::Integer`: the fixed axis, 1, 2 or 3. Throws an `ArgumentError` otherwise.
  - `index::Integer`: the position along `axis`, positive. Throws an `ArgumentError`
    otherwise.

# Examples

```jldoctest
julia> using MakiePotts

julia> OrthogonalSlice(3, 10).axis
3
```

See also [`FullDomain`](@ref), [`RenderRequest`](@ref).
"""
struct OrthogonalSlice <: AbstractRenderExtent
    axis::Int
    index::Int

    function OrthogonalSlice(axis::Integer, index::Integer)
        1 <= axis <= 3 || throw(ArgumentError("slice axis must be 1, 2, or 3"))
        index > 0 || throw(ArgumentError("slice index must be positive"))
        return new(Int(axis), Int(index))
    end
end

"""Abstract supertype for the scope carried by a typed render-channel key."""
abstract type AbstractRenderChannelScope end
"""Marker scope for values defined independently at every lattice site."""
struct SiteChannelScope <: AbstractRenderChannelScope end
"""Marker scope for values keyed by generation-aware finite-cell identity."""
struct CellChannelScope <: AbstractRenderChannelScope end
"""Marker scope for values keyed by medium-domain identity."""
struct MediumChannelScope <: AbstractRenderChannelScope end

"""
    RenderChannelKey{S, T}(name)
    RenderChannelKey(scope, name, T)

A typed key for a render channel: its scope `S`, its value type `T` and its name.

Two keys are equal when scope, value type and name are equal. A frame holds at most one
channel per key. [`SiteChannelKey`](@ref), [`CellChannelKey`](@ref) and
[`MediumChannelKey`](@ref) make keys of each scope.

# Arguments

  - `scope::AbstractRenderChannelScope`: [`SiteChannelScope`](@ref)`()`,
    [`CellChannelScope`](@ref)`()` or [`MediumChannelScope`](@ref)`()`.
  - `name::Symbol`: the channel name, also the default plot title of the channel.
  - `T::Type`: the type of every value of the channel (`missing` is also allowed).

# Examples

```jldoctest
julia> using MakiePotts

julia> key = RenderChannelKey(CellChannelScope(), :area, Float64);

julia> key == CellChannelKey(:area, Float64)
true
```

See also [`RenderChannel`](@ref).
"""
struct RenderChannelKey{S <: AbstractRenderChannelScope, T}
    name::Symbol
end

function RenderChannelKey(::S, name::Symbol, ::Type{T}) where {
        S <: AbstractRenderChannelScope, T,
    }
    return RenderChannelKey{S, T}(name)
end
"""
    SiteChannelKey(name, T = Any) -> RenderChannelKey

Return the key of a site channel: one value per lattice site.

# Arguments

  - `name::Symbol`: the channel name.
  - `T::Type`: the value type.

# Returns

  - `RenderChannelKey{SiteChannelScope, T}`: the key.

# Examples

```jldoctest
julia> using MakiePotts

julia> SiteChannelKey(:c, Float64)
site channel :c::Float64
```

See also [`CellChannelKey`](@ref), [`MediumChannelKey`](@ref).
"""
function SiteChannelKey(name::Symbol, ::Type{T} = Any) where {T}
    return RenderChannelKey(SiteChannelScope(), name, T)
end
"""
    CellChannelKey(name, T = Any) -> RenderChannelKey

Return the key of a cell channel: one value per cell, keyed by
[`RenderCellIdentity`](@ref).

# Arguments

  - `name::Symbol`: the channel name.
  - `T::Type`: the value type.

# Returns

  - `RenderChannelKey{CellChannelScope, T}`: the key.

# Examples

```jldoctest
julia> using MakiePotts

julia> CellChannelKey(:volume, Int)
cell channel :volume::Int64
```

See also [`SiteChannelKey`](@ref), [`MediumChannelKey`](@ref).
"""
function CellChannelKey(name::Symbol, ::Type{T} = Any) where {T}
    return RenderChannelKey(CellChannelScope(), name, T)
end
"""
    MediumChannelKey(name, T = Any) -> RenderChannelKey

Return the key of a medium channel: one value per medium, keyed by its positive number.

# Arguments

  - `name::Symbol`: the channel name.
  - `T::Type`: the value type.

# Returns

  - `RenderChannelKey{MediumChannelScope, T}`: the key.

# Examples

```jldoctest
julia> using MakiePotts

julia> MediumChannelKey(:c, Float64)
medium channel :c::Float64
```

See also [`SiteChannelKey`](@ref), [`CellChannelKey`](@ref).
"""
function MediumChannelKey(name::Symbol, ::Type{T} = Any) where {T}
    return RenderChannelKey(MediumChannelScope(), name, T)
end

function Base.show(io::IO, key::RenderChannelKey{S, T}) where {S, T}
    scope = if S <: SiteChannelScope
        "site"
    elseif S <: CellChannelScope
        "cell"
    else
        "medium"
    end
    return print(io, scope, " channel :", key.name, "::", T)
end

"""
    RenderChannel(key, values; label = String(key.name), units = nothing)

One channel of render data: values for each site, cell or medium, with a title and units.

The constructor does not check `values`. A frame checks them when it is built
([`PottsRenderFrame`](@ref) throws `MakiePotts.InvalidRenderFrameError`) and keeps a copy.

# Arguments

  - `key::RenderChannelKey`: the key. Its scope sets the form of `values`.
  - `values`: an array of the frame's size for a site channel; a dictionary from
    [`RenderCellIdentity`](@ref) for a cell channel; a dictionary from the positive medium
    number for a medium channel. Each value is of the key's value type or `missing`.

# Keywords

  - `label::AbstractString = String(key.name)`: the title of the channel in plots.
  - `units = nothing`: the units string, or `nothing`.

# Fields

  - `key`, `values`: as given.
  - `label::String`: the title.
  - `units::Union{Nothing, String}`: the units.

# Examples

```jldoctest
julia> using MakiePotts

julia> RenderChannel(SiteChannelKey(:c, Float64), zeros(2, 2); units = "mM").units
"mM"
```

See also [`ChannelEncoding`](@ref), [`renderframe`](@ref).
"""
struct RenderChannel{K <: RenderChannelKey, V}
    key::K
    values::V
    label::String
    units::Union{Nothing, String}
end

function RenderChannel(
        key::RenderChannelKey, values;
        label::AbstractString = String(key.name), units = nothing
    )
    normalized_units = units === nothing ? nothing : String(units)
    return RenderChannel(key, values, String(label), normalized_units)
end

"""
    RenderRequest(; extent = FullDomain(), include_cell_metadata = true)

Select what [`renderframe`](@ref) keeps of a saved state: the extent and the cell metadata.

`renderframe` reads only the ownership, the cell kinds and generations, and the obstacles
of a state. It computes no channels; pass them as [`RenderChannel`](@ref) values.

# Keywords

  - `extent::AbstractRenderExtent = FullDomain()`: [`FullDomain`](@ref)`()` or an
    [`OrthogonalSlice`](@ref).
  - `include_cell_metadata::Bool = true`: keep the metadata of each live cell. With
    `false`, `renderframe` throws an `ArgumentError` when the extent holds a cell site.

# Fields

  - `extent`, `include_cell_metadata`: as given.

# Examples

```jldoctest
julia> using MakiePotts

julia> RenderRequest(; extent = OrthogonalSlice(3, 1)).extent
OrthogonalSlice(3, 1)
```

See also [`renderframes`](@ref).
"""
struct RenderRequest{E <: AbstractRenderExtent}
    extent::E
    include_cell_metadata::Bool
end

function RenderRequest(;
        extent::AbstractRenderExtent = FullDomain(),
        include_cell_metadata::Bool = true
    )
    return RenderRequest(extent, include_cell_metadata)
end
