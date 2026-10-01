"""Abstract supertype for full-domain and projected render extents."""
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

"""Abstract supertype for the scope carried by a typed render-channel key."""
abstract type AbstractRenderChannelScope end
"""Marker scope for values defined independently at every lattice site."""
struct SiteChannelScope <: AbstractRenderChannelScope end
"""Marker scope for values keyed by generation-aware finite-cell identity."""
struct CellChannelScope <: AbstractRenderChannelScope end
"""Marker scope for values keyed by medium-domain identity."""
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
"""Construct a site-scoped [`RenderChannelKey`](@ref)."""
SiteChannelKey(name::Symbol, ::Type{T} = Any) where {T} =
    RenderChannelKey(SiteChannelScope(), name, T)
"""Construct a finite-cell-scoped [`RenderChannelKey`](@ref)."""
CellChannelKey(name::Symbol, ::Type{T} = Any) where {T} =
    RenderChannelKey(CellChannelScope(), name, T)
"""Construct a medium-domain-scoped [`RenderChannelKey`](@ref)."""
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

"""
    RenderRequest(; extent=FullDomain(), include_cell_metadata=true)

Select the spatial extent and metadata retained when converting a native Potts
saved state. Scientific channels are never reconstructed from saved state;
callers may pass explicit [`RenderChannel`](@ref) values to [`renderframe`](@ref).
"""
struct RenderRequest{E <: AbstractRenderExtent}
    extent::E
    include_cell_metadata::Bool
end

function RenderRequest(; extent::AbstractRenderExtent = FullDomain(),
        include_cell_metadata::Bool = true)
    return RenderRequest(extent, include_cell_metadata)
end
