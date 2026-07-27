abstract type AbstractRenderExtent end

"""Request the full two- or three-dimensional ownership domain."""
struct FullDomain <: AbstractRenderExtent end

"""
    OrthogonalSlice(axis, index)

Request a two-dimensional slice by fixing one 3D array axis at `index`.
"""
struct OrthogonalSlice <: AbstractRenderExtent
    axis::Int
    index::Int

    function OrthogonalSlice(axis::Integer, index::Integer)
        1 <= axis <= 3 || throw(ArgumentError("slice axis must be 1, 2, or 3"))
        index > 0 || throw(ArgumentError("slice index must be positive"))
        new(Int(axis), Int(index))
    end
end

abstract type AbstractRenderChannelScope end
struct SiteChannelScope <: AbstractRenderChannelScope end
struct CellChannelScope <: AbstractRenderChannelScope end
struct MediumChannelScope <: AbstractRenderChannelScope end

"""
A typed semantic key for render data. The scope and value type are part of the
key's type, while `name` provides stable human-readable identity.
"""
struct RenderChannelKey{S <: AbstractRenderChannelScope, T}
    name::Symbol
end

RenderChannelKey(::S, name::Symbol, ::Type{T}) where {S <: AbstractRenderChannelScope, T} =
    RenderChannelKey{S, T}(name)
SiteChannelKey(name::Symbol, ::Type{T} = Any) where {T} =
    RenderChannelKey(SiteChannelScope(), name, T)
CellChannelKey(name::Symbol, ::Type{T} = Any) where {T} =
    RenderChannelKey(CellChannelScope(), name, T)
MediumChannelKey(name::Symbol, ::Type{T} = Any) where {T} =
    RenderChannelKey(MediumChannelScope(), name, T)

function Base.show(io::IO, key::RenderChannelKey{S, T}) where {S, T}
    scope = S === SiteChannelScope ? "site" :
            S === CellChannelScope ? "cell" : "medium"
    print(io, scope, " channel :", key.name, "::", T)
end

"""
One explicitly materialized channel. `values` is an array for site channels, a
generation-aware identity-keyed dictionary for cell channels, or a positive
medium-domain-ID-keyed dictionary for medium channels.
"""
struct RenderChannel{K <: RenderChannelKey, V}
    key::K
    values::V
    label::String
    units::Union{Nothing, String}
end

function RenderChannel(key::RenderChannelKey, values;
        label::AbstractString = String(key.name), units = nothing)
    normalized_units = units === nothing ? nothing : String(units)
    return RenderChannel(key, values, String(label), normalized_units)
end

abstract type AbstractChannelRequest end

"""
Request one finite-cell property by its frozen CorePotts property key.
"""
struct CellPropertyRequest{T} <: AbstractChannelRequest
    key::RenderChannelKey{CellChannelScope, T}
    property::Symbol
    label::String
    units::Union{Nothing, String}
end

function CellPropertyRequest(property::Symbol, ::Type{T} = Float64;
        name::Symbol = property, label::AbstractString = String(name),
        units = nothing) where {T}
    normalized_units = units === nothing ? nothing : String(units)
    return CellPropertyRequest(
        CellChannelKey(name, T), property, String(label), normalized_units)
end

"""
    RenderRequest(; extent=FullDomain(), channels=(), include_cell_metadata=true)

Immutable, visualization-free declaration of the data required by a render
frame. Styling belongs to encodings and Makie attributes.
"""
struct RenderRequest{E <: AbstractRenderExtent, C <: Tuple}
    extent::E
    channels::C
    include_cell_metadata::Bool
end

function RenderRequest(; extent::AbstractRenderExtent = FullDomain(),
        channels::Tuple = (), include_cell_metadata::Bool = true)
    all(channel -> channel isa AbstractChannelRequest, channels) ||
        throw(ArgumentError("every requested channel must be an AbstractChannelRequest"))
    keys = map(channel -> channel.key, channels)
    length(unique(keys)) == length(keys) ||
        throw(ArgumentError("requested render-channel keys must be unique"))
    return RenderRequest(extent, channels, include_cell_metadata)
end

"""Open channel-adapter protocol extended by source integrations."""
function materialize_channel end
