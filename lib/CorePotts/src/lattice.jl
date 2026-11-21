# N-dimensional Cartesian lattices and neighborhood relations of any order.

"""
    AbstractBoundary

The supertype of the boundary condition of a lattice axis: [`Periodic`](@ref) or
[`Closed`](@ref).

See also [`Lattice`](@ref).
"""
abstract type AbstractBoundary end
"""
    Periodic()

The periodic boundary condition of a lattice axis: opposite faces are identified, so a
neighbor across a face wraps to the other side.

See also [`Closed`](@ref), [`Lattice`](@ref).
"""
struct Periodic <: AbstractBoundary end
"""
    Closed()

The closed boundary condition of a lattice axis: a site has no neighbor across the face.

A copy attempt whose source would lie across a closed face is a counted null attempt.
Contacts, surfaces and field stencils stop at the face.

See also [`Periodic`](@ref), [`Lattice`](@ref).
"""
struct Closed <: AbstractBoundary end

abstract type AbstractGeometry end
"""
    Square()

The square lattice geometry (cubic in 3D): the coordinates of a site are its position.

See also [`Hexagonal`](@ref), [`Lattice`](@ref).
"""
struct Square <: AbstractGeometry end
"""
    Hexagonal()

The hexagonal 2D lattice geometry, in axial coordinates.

Site `(q, r)` lies at the position `(q + r/2, r·√3/2)`. Its six nearest neighbors are the
offsets `(±1, 0)`, `(0, ±1)`, `(1, -1)` and `(-1, 1)`. These are a subset of `Moore(1)`, so
checkerboard coloring, periodic wrapping and the integer moment trackers work unchanged.
Periodic axes make a rhombic torus. Positions, distances, centroids, shapes and division
planes use the embedding ([`embed`](@ref)). On this geometry `Moore(k)` and
`VonNeumann(k)` resolve to `Hex(k)`.

See also [`Square`](@ref), [`Hex`](@ref), [`Lattice`](@ref).
"""
struct Hexagonal <: AbstractGeometry end

"""
    Lattice(dims; boundary = Periodic(), domain = nothing, geometry = Square())

A Cartesian lattice of `dims` sites, with a boundary per axis and an optional domain.

Sites outside the domain never change their cell number and must belong to the medium.
The domain edge is closed: [`shift`](@ref) reports a neighbor outside the domain as
outside the lattice, so contacts, surfaces, gathers, proposals and field stencils (zero
flux) all stop there.

# Arguments
- `dims::NTuple{N, Integer}`: the number of sites along each axis, all positive.

# Keywords
- `boundary = Periodic()`: one [`AbstractBoundary`](@ref) for all axes, or a tuple with
  one per axis.
- `domain = nothing`: the region of the lattice that cells may occupy. It is a `Bool`
  array of size `dims`, or a predicate of the site position `x -> …`. A predicate receives
  Cartesian positions (the [`embed`](@ref)ded coordinates on a hexagonal lattice); wrap it
  in [`OnIndices`](@ref) to receive lattice coordinates. The domain must contain at least
  one site.
- `geometry = Square()`: [`Square`](@ref) or [`Hexagonal`](@ref). A hexagonal lattice is
  2D.

# Fields
- `dims::NTuple{N, Int}`: the size along each axis (also `size(lattice)`).
- `periodic::NTuple{N, Bool}`: whether each axis is periodic.
- `mask`: `nothing`, or the domain as a `Bool` array (`true` = inside).
- `geometry`: the geometry.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((4, 3); boundary = (Periodic(), Closed()));

julia> size(l), nsites(l), l.periodic
((4, 3), 12, (true, false))

julia> d = Lattice((5, 5); domain = x -> sum(abs2, x .- 3) <= 4);

julia> count(d.mask)
13
```

See also [`relation`](@ref), [`nsites`](@ref), [`shift`](@ref).
"""
struct Lattice{N, M, G <: AbstractGeometry}
    dims::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    mask::M                       # `nothing`, or a Bool array (`true` = in the domain)
    geometry::G
end
function Lattice{N}(dims, periodic) where {N}
    return Lattice{N, Nothing, Square}(dims, periodic, nothing, Square())
end
function Lattice{N, M}(dims, periodic, mask) where {N, M}
    return Lattice{N, M, Square}(dims, periodic, mask, Square())
end

function Lattice(
        dims::NTuple{N, Integer}; boundary = Periodic(), domain = nothing,
        geometry::AbstractGeometry = Square()
    ) where {N}
    geometry isa Hexagonal && N != 2 &&
        throw(ArgumentError("hexagonal lattices are 2D, got $(N)D dims $dims; pass a \
            2-tuple for dims or use `Square()`"))
    b = boundary isa AbstractBoundary ? ntuple(_ -> boundary, N) : Tuple(boundary)
    length(b) == N || throw(ArgumentError("need $N boundaries, got $(length(b))"))
    all(>(0), dims) || throw(ArgumentError("lattice dimensions must be positive"))
    d = Int.(dims)
    mask = _domain_mask(domain, d, geometry)
    mask === nothing || any(mask) ||
        throw(ArgumentError("the domain contains no sites: widen `domain` so at least one \
            lattice site is inside"))
    return Lattice{N, typeof(mask), typeof(geometry)}(
        d, map(x -> x isa Periodic, b), mask,
        geometry
    )
end

"""
    OnIndices(f)

Wrap a domain predicate or a relation weight so that it receives lattice coordinates.

By default [`Lattice`](@ref)'s `domain` and [`Weighted`](@ref)'s weight receive Cartesian
positions or offsets. With `OnIndices(f)`, `f` receives the lattice coordinates instead:
the axial `(q, r)` on a hexagonal lattice. On a square lattice the two are the same.

# Arguments
- `f`: a function of a coordinate tuple.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((4, 4); geometry = Hexagonal(), domain = OnIndices(x -> x[1] <= 2));

julia> count(l.mask)
8
```

See also [`Lattice`](@ref), [`Weighted`](@ref).
"""
struct OnIndices{F}
    f::F
end

_domain_mask(::Nothing, dims, g) = nothing
function _domain_mask(m::AbstractArray{Bool}, dims, g)
    size(m) == dims ||
        throw(ArgumentError("domain mask has size $(size(m)), lattice $dims"))
    return Array{Bool}(m)
end
_domain_mask(f, dims, g) = Bool[f(_embed(g, Tuple(x))) for x in CartesianIndices(dims)]
_domain_mask(f::OnIndices, dims, g) = Bool[f.f(Tuple(x)) for x in CartesianIndices(dims)]

# `embed` by geometry alone (for construction, before the lattice exists)
_embed(::Square, v) = v
_embed(::Hexagonal, v) = (v[1] + v[2] / 2, v[2] * sqrt(3) / 2)

function Adapt.adapt_structure(to, l::Lattice{N}) where {N}
    m = Adapt.adapt(to, l.mask)
    return Lattice{N, typeof(m), typeof(l.geometry)}(l.dims, l.periodic, m, l.geometry)
end
function Base.:(==)(a::Lattice, b::Lattice)
    return a.dims == b.dims && a.periodic == b.periodic && a.geometry == b.geometry &&
        (
        a.mask === b.mask ||
            (a.mask !== nothing && b.mask !== nothing && Array(a.mask) == Array(b.mask))
    )
end
function Base.hash(l::Lattice, h::UInt)
    return hash(
        (l.dims, l.periodic, l.mask === nothing ? nothing : Array(l.mask), l.geometry), h
    )
end

"""
    embed(lattice, v) -> NTuple

Map a vector `v` in lattice coordinates (an offset or a position) to Cartesian coordinates.

On a square lattice it returns `v` unchanged. On a hexagonal lattice it returns
`(q + r/2, r·√3/2)` as floats. The map is linear, so it maps centroids, shifts and offsets
alike.

# Arguments
- `lattice::Lattice`: the lattice.
- `v`: a tuple of lattice coordinates.

# Returns
- The Cartesian coordinates, a tuple.

# Examples
```jldoctest
julia> using CorePotts

julia> embed(Lattice((4, 4); geometry = Hexagonal()), (2, 2))
(3.0, 1.7320508075688772)
```

See also [`embed_covariance`](@ref), [`centroid_position`](@ref).
"""
@inline embed(::Lattice{N, M, Square}, v) where {N, M} = v
@inline function embed(::Lattice{2, M, Hexagonal}, v) where {M}
    T = float(typeof(v[1]))
    return (T(v[1]) + T(v[2]) / 2, T(v[2]) * sqrt(T(3)) / 2)
end

"""
    embed_covariance(lattice, C) -> NTuple

Map the covariance `C` of lattice-coordinate data to the covariance of the data mapped by
[`embed`](@ref).

`C` is the upper triangle, as [`covariance`](@ref) returns it. On a square lattice it is
returned unchanged. On a hexagonal lattice, `(a, b, d) = (C_qq, C_qr, C_rr)` maps to
`(a + b + d/4, √3/2 · (b + d/2), 3d/4)`.

# Arguments
- `lattice::Lattice`: the lattice.
- `C`: the upper triangle of the covariance in lattice coordinates.

# Returns
- The upper triangle of the covariance in Cartesian coordinates.

See also [`embed`](@ref), [`covariance`](@ref).
"""
@inline embed_covariance(::Lattice{N, M, Square}, C) where {N, M} = C
@inline function embed_covariance(::Lattice{2, M, Hexagonal}, C) where {M}
    a, b, d = C
    T = typeof(a)
    s = sqrt(T(3)) / 2
    return (a + b + d / 4, s * (b + d / 2), T(3) / 4 * d)
end

"""
    in_domain(lattice, i) -> Bool

Return `true` if site `i` is in the domain of `lattice` (always `true` without a domain).

# Arguments
- `lattice::Lattice`: the lattice.
- `i`: a linear site index in `1:nsites(lattice)` (not bounds-checked).

# Returns
- `Bool`.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((3,); domain = Bool[1, 0, 1]);

julia> in_domain(l, 2)
false
```

See also [`Lattice`](@ref).
"""
@inline in_domain(::Lattice{N, Nothing}, i) where {N} = true
# bounds: i is a site index ≤ nsites = length(l.mask)
@inline in_domain(l::Lattice, i) = @inbounds l.mask[i]

"""
    host_lattice(lattice) -> Lattice

Return `lattice` with its domain mask on the host, for host code that holds a device
context.

A lattice without a mask, or with a host mask, is returned as it is. A device mask is
copied once and the copy is reused while the device array lives. The copy is shared, so
host code must not write it.

# Arguments
- `lattice::Lattice`: the lattice, possibly with a device mask.

# Returns
- A `Lattice` whose mask is a host array or `nothing`.

See also [`to_host`](@ref).
"""
host_lattice(l::Lattice) = host_lattice(nothing, l)
# `stats` counts the mask copy (D-085), or `nothing`; the copy is cached (D-092, audit
# A4/H3)
"""
    host_lattice(stats, lattice) -> Lattice

Return `lattice` with its domain mask on the host, and count the copy in `stats`.

As [`host_lattice`](@ref)`(lattice)`, but the one copy of a device mask is counted as a
device-to-host transfer in the run statistics `stats`.

# Arguments
- `stats`: the run statistics that count transfers, or `nothing`.
- `lattice::Lattice`: the lattice.

# Returns
- A `Lattice` whose mask is a host array or `nothing`.
"""
host_lattice(stats, l::Lattice{N, Nothing}) where {N} = l
host_lattice(stats, l::Lattice) = _adapt_host_cached(stats, l)

Base.ndims(::Lattice{N}) where {N} = N
"""
    nsites(lattice) -> Int

Return the number of sites of `lattice`, `prod(size(lattice))`.

Sites outside the domain are counted.

# Arguments
- `lattice::Lattice`: the lattice.

# Returns
- `Int`: the site count.

# Examples
```jldoctest
julia> using CorePotts

julia> nsites(Lattice((10, 20)))
200
```
"""
nsites(l::Lattice) = prod(l.dims)
Base.size(l::Lattice) = l.dims

"""
    linear_index(lattice, x) -> Int

Return the 1-based, column-major linear index of the site with lattice coordinates `x`.

# Arguments
- `lattice::Lattice{N}`: the lattice.
- `x::NTuple{N, Int}`: 1-based lattice coordinates, inside the lattice (not checked).

# Returns
- `Int`: the linear site index.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.linear_index(Lattice((4, 3)), (2, 3))
10
```

See also [`coordinates`](@ref).
"""
@inline function linear_index(l::Lattice{N}, x::NTuple{N, Int}) where {N}
    i = 0
    stride = 1
    for d in 1:N
        i += (x[d] - 1) * stride
        stride *= l.dims[d]
    end
    return i + 1
end

"""
    coordinates(lattice, i) -> NTuple{N, Int}

Return the 1-based lattice coordinates of the site with linear index `i`.

The inverse of [`linear_index`](@ref).

# Arguments
- `lattice::Lattice{N}`: the lattice.
- `i::Int`: a linear site index in `1:nsites(lattice)`.

# Returns
- `NTuple{N, Int}`: the coordinates.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.coordinates(Lattice((4, 3)), 10)
(2, 3)
```

See also [`linear_index`](@ref).
"""
@inline function coordinates(l::Lattice{N}, i::Int) where {N}
    # Stride of axis d is prod(dims[1:d-1]); no captured mutable state (it would be boxed).
    return ntuple(Val(N)) do d
        stride = prod(ntuple(e -> e < d ? l.dims[e] : 1, Val(N)))
        rem(div(i - 1, stride), l.dims[d]) + 1
    end
end

"""
    shift(lattice, x, offset) -> (inside::Bool, y)

Return the neighbor of site `x` at `offset`, and whether the pair interacts.

A periodic axis wraps `y`. On a closed axis, `y` is clamped to the face and `inside` is
`false`. `inside` is also `false` when `x` or `y` lies outside the domain, so a pair
interacts only when both sites are in the domain.

# Arguments
- `lattice::Lattice{N}`: the lattice.
- `x::NTuple{N, Int}`: the site's coordinates.
- `offset::NTuple{N, Int32}`: the offset, for example from a relation.

# Returns
- `(inside, y)`: `inside::Bool`, and the neighbor's coordinates `y::NTuple{N, Int}`.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((4, 4); boundary = (Periodic(), Closed()));

julia> CorePotts.shift(l, (1, 1), (Int32(-1), Int32(0)))
(true, (4, 1))

julia> CorePotts.shift(l, (1, 1), (Int32(0), Int32(-1)))
(false, (1, 1))
```

See also [`neighbor_index`](@ref).
"""
@inline function shift(l::Lattice{N}, x::NTuple{N, Int}, off::NTuple{N, Int32}) where {N}
    # No captured mutable state in the closure (it would be boxed).
    y = ntuple(d -> x[d] + Int(off[d]), Val(N))
    inside = all(ntuple(d -> l.periodic[d] || 1 <= y[d] <= l.dims[d], Val(N)))
    w = ntuple(Val(N)) do d
        n = l.dims[d]
        v = y[d]
        ifelse(
            v < 1, ifelse(l.periodic[d], v + n, 1), ifelse(
                v > n, ifelse(
                    l.periodic[d], v -
                        n, n
                ), v
            )
        )
    end
    return inside && _in_domain(l.mask, l, x, w), w
end

# a pair interacts only if both sites are in the domain (symmetric, so brute-force sums
# over all sites agree with per-copy deltas)
"""`true` if `x + off` stays within the lattice faces (ignoring the domain mask)."""
@inline function _within_faces(l::Lattice{N}, x, off) where {N}
    return all(ntuple(d -> l.periodic[d] || 1 <= x[d] + Int(off[d]) <= l.dims[d], Val(N)))
end
@inline _in_domain(::Nothing, l, x, w) = true
# bounds: x and w are lattice sites (shifted inside), so ≤ nsites = length(m)
@inline function _in_domain(m, l, x, w)
    return @inbounds(m[linear_index(l, x)]) &&
        @inbounds(m[linear_index(l, w)])
end

# ---------------------------------------------------------------------------------------
# Relations

"""
A resolved neighborhood: `K` offsets in canonical order (by squared length, then
lexicographic) and optional per-offset weights (`Float32`, device-safe; `nothing` = all 1).
"""
struct Relation{N, K, W <: Union{Nothing, NTuple{K, Float32}}}
    offsets::NTuple{K, NTuple{N, Int32}}
    weights::W
end
Relation{N, K}(offsets) where {N, K} = Relation{N, K, Nothing}(offsets, nothing)
Base.length(::Relation{N, K}) where {N, K} = K

"""
    weight(relation, k)

Return the weight of offset `k` of a resolved relation.

An unweighted relation returns `Int32(1)`, so sums over it stay integers. A
[`Weighted`](@ref) relation returns its `Float32` weight.

# Arguments
- `relation`: a relation from [`relation`](@ref).
- `k`: the offset number, in `1:length(relation)` (not bounds-checked).

# Returns
- `Int32(1)` or a `Float32`.

See also [`relation`](@ref), [`Weighted`](@ref).
"""
@inline weight(::Relation{N, K, Nothing}, k) where {N, K} = Int32(1)
# bounds: k ≤ K = length(r.weights), one weight per offset
@inline weight(r::Relation, k) = @inbounds r.weights[k]
"""
    radius(relation) -> Int

Return the largest Chebyshev length `maximum(abs, o)` over the offsets `o` of `relation`.

# Arguments
- `relation`: a relation from [`relation`](@ref).

# Returns
- `Int`: the radius, `0` for a relation with no offsets.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.radius(relation(VonNeumann(2), Lattice((10, 10))))
2
```

See also [`interior`](@ref).
"""
radius(r::Relation) = maximum(o -> maximum(abs, o; init = 0), r.offsets; init = 0)

"""
    interior(lattice, x, relation) -> Bool

Return `true` when every neighbor of site `x` under `relation` lies inside the lattice
without wrapping.

That holds when `x` is more than [`radius`](@ref)`(relation)` sites from every face. A
lattice with a domain mask always returns `false`, since the mask must be checked per
pair.

# Arguments
- `lattice::Lattice{N}`: the lattice.
- `x`: the site's coordinates.
- `relation`: a relation from [`relation`](@ref).

# Returns
- `Bool`.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((5, 5)); r = relation(Moore(), l);

julia> CorePotts.interior(l, (3, 3), r), CorePotts.interior(l, (1, 3), r)
(true, false)
```

See also [`neighbor_index`](@ref).
"""
@inline function interior(l::Lattice{N, Nothing}, x, rel::Relation{N, K}) where {N, K}
    # bounds: k ≤ K offsets of rel, each with N components
    r = foldl(
        max,
        ntuple(
            k -> foldl(max, ntuple(d -> abs(Int(@inbounds rel.offsets[k][d])), Val(N))),
            Val(K)
        )
    )
    return all(ntuple(d -> r < x[d] <= l.dims[d] - r, Val(N)))
end
@inline interior(l::Lattice, x, rel) = false

"""
    neighbor_index(lattice, x, t, relation, k, interior) -> (inside::Bool, index::Int)

Return the linear index of neighbor `k` of site `t` under `relation`.

When `interior` is `true`, the index is `t` plus the offset's linear stride, with no wrap
arithmetic. Pass `true` only when [`interior`](@ref) holds for `x`. Otherwise it calls
[`shift`](@ref) and [`linear_index`](@ref), and returns `(false, t)` when the pair does
not interact.

# Arguments
- `lattice::Lattice{N}`: the lattice.
- `x`: the coordinates of site `t`.
- `t::Int`: the linear index of the site.
- `relation`: a relation from [`relation`](@ref).
- `k`: the offset number, in `1:length(relation)`.
- `interior::Bool`: whether the fast path applies.

# Returns
- `(inside, index)`: whether the pair interacts, and the neighbor's linear index (`t`
  when it does not).

See also [`shift`](@ref), [`interior`](@ref).
"""
@inline function neighbor_index(
        l::Lattice{N}, x, t::Int, rel::Relation{N}, k, inner::Bool
    ) where {N}
    # bounds: k ≤ length(rel), an offset of the relation
    inner && return true, t + _linear_offset(l, @inbounds rel.offsets[k])
    inside, y = shift(l, x, @inbounds rel.offsets[k])
    return inside, inside ? linear_index(l, y) : t
end
@inline function _linear_offset(l::Lattice{N}, o::NTuple{N, Int32}) where {N}
    return foldl(
        +, ntuple(
            d -> Int(o[d]) *
                prod(ntuple(e -> e < d ? l.dims[e] : 1, Val(N))), Val(N)
        )
    )
end

"""
    AbstractRelationSpec

The supertype of a relation's specification: a neighborhood or stencil before
[`relation`](@ref) binds it to a lattice.

The subtypes are [`Moore`](@ref), [`VonNeumann`](@ref), [`NeighborOrder`](@ref),
[`EuclideanBall`](@ref), [`Hex`](@ref), [`Stencil`](@ref) and [`Weighted`](@ref).
"""
abstract type AbstractRelationSpec end

"""
    Moore(k = 1; include_self = false)

The Chebyshev ball: all offsets `o` with `maximum(abs, o) ≤ k`.

Order 1 has 8 offsets in 2D and 26 in 3D. On a hexagonal lattice it resolves to `Hex(k)`.

# Arguments
- `k::Integer = 1`: the order.

# Keywords
- `include_self = false`: whether to include the zero offset.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((10, 10));

julia> length(relation(Moore(), l)), length(relation(Moore(2), l))
(8, 24)
```

See also [`VonNeumann`](@ref), [`relation`](@ref).
"""
struct Moore <: AbstractRelationSpec
    k::Int
    include_self::Bool
end
Moore(k::Integer = 1; include_self = false) = Moore(k, include_self)

"""
    VonNeumann(k = 1; include_self = false)

The Manhattan ball: all offsets `o` with `sum(abs, o) ≤ k`.

Order 1 has 4 offsets in 2D and 6 in 3D. On a hexagonal lattice it resolves to `Hex(k)`.

# Arguments
- `k::Integer = 1`: the order.

# Keywords
- `include_self = false`: whether to include the zero offset.

# Examples
```jldoctest
julia> using CorePotts

julia> length(relation(VonNeumann(), Lattice((10, 10, 10))))
6
```

See also [`Moore`](@ref), [`relation`](@ref).
"""
struct VonNeumann <: AbstractRelationSpec
    k::Int
    include_self::Bool
end
VonNeumann(k::Integer = 1; include_self = false) = VonNeumann(k, include_self)

"""
    NeighborOrder(k = 1; include_self = false)

All offsets in the first `k` distinct Euclidean distance shells, as CompuCell3D's
`NeighborOrder`.

The shells are cumulative. The offset counts are 4, 8, 12, 20, 24 and 28 in 2D, and 6, 18,
26, 32, 56 and 80 in 3D, for `k = 1, …, 6`. On a hexagonal lattice the shells are those of
the embedded distances.

# Arguments
- `k::Integer = 1`: the number of shells.

# Keywords
- `include_self = false`: whether to include the zero offset.

# Examples
```jldoctest
julia> using CorePotts

julia> length(relation(NeighborOrder(4), Lattice((10, 10))))
20
```

See also [`Moore`](@ref), [`relation`](@ref).
"""
struct NeighborOrder <: AbstractRelationSpec
    k::Int
    include_self::Bool
end
NeighborOrder(k::Integer = 1; include_self = false) = NeighborOrder(k, include_self)

"""
    EuclideanBall(r; include_self = false)

The Euclidean ball: all offsets `o` with `‖o‖ ≤ r`, in lattice units.

On a hexagonal lattice the length is that of the embedded offset.

# Arguments
- `r::Real`: the radius.

# Keywords
- `include_self = false`: whether to include the zero offset.

# Examples
```jldoctest
julia> using CorePotts

julia> length(relation(EuclideanBall(2), Lattice((10, 10))))
12
```

See also [`NeighborOrder`](@ref), [`relation`](@ref).
"""
struct EuclideanBall <: AbstractRelationSpec
    r::Float64
    include_self::Bool
end
EuclideanBall(r::Real; include_self = false) = EuclideanBall(r, include_self)

"""
    Weighted(spec, weight)

The relation `spec` with a weight on each offset.

`weight(o)` receives the Cartesian offset `o`, for example `o -> 1 / sqrt(sum(abs2, o))`
for distance-weighted contact. Wrap it in [`OnIndices`](@ref) to receive lattice offsets.
The weights are stored as `Float32` and must be finite.

# Arguments
- `spec::AbstractRelationSpec`: the offsets.
- `weight`: a function from an offset to a real weight.

# Examples
```jldoctest
julia> using CorePotts

julia> r = relation(Weighted(Moore(), o -> 1 / sqrt(sum(abs2, o))), Lattice((10, 10)));

julia> CorePotts.weight(r, 1), CorePotts.weight(r, 8)
(1.0f0, 0.70710677f0)
```

See also [`relation`](@ref), [`weight`](@ref).
"""
struct Weighted{S <: AbstractRelationSpec, F} <: AbstractRelationSpec
    spec::S
    weight::F
end

"""
    Stencil(offsets)

A relation with explicit offsets.

Each offset is an iterable of integers, with one entry per lattice axis. A zero offset is
kept if it is given.

# Arguments
- `offsets`: an iterable of offsets, for example `[(1, 0), (-1, 0)]`.

# Fields
- `offsets::Vector{Vector{Int}}`: the offsets.

# Examples
```jldoctest
julia> using CorePotts

julia> length(relation(Stencil([(1, 0), (-1, 0)]), Lattice((10, 10))))
2
```

See also [`relation`](@ref).
"""
struct Stencil <: AbstractRelationSpec
    offsets::Vector{Vector{Int}}
    Stencil(offsets) = new([collect(Int, o) for o in offsets])
end

_box(N, R) = vec([Tuple(c) for c in CartesianIndices(ntuple(_ -> (-R):R, N))])
_sq(o) = sum(abs2, o)

function _candidates(spec::Moore, N)
    return [o for o in _box(N, spec.k)]
end
_candidates(spec::VonNeumann, N) = [o for o in _box(N, spec.k) if sum(abs, o) <= spec.k]
function _candidates(spec::EuclideanBall, N)
    return [o for o in _box(N, floor(Int, spec.r)) if _sq(o) <= spec.r^2]
end
function _candidates(spec::NeighborOrder, N)
    box = _box(N, spec.k)
    shells = sort!(unique(_sq(o) for o in box if _sq(o) > 0))
    cutoff = shells[spec.k]
    return [o for o in box if _sq(o) <= cutoff]
end
function _candidates(spec::Stencil, N)
    all(o -> length(o) == N, spec.offsets) ||
        throw(ArgumentError("stencil offsets must have $N components"))
    return [Tuple(o) for o in spec.offsets]
end
_include_self(spec::Stencil) = any(o -> all(iszero, o), spec.offsets)

"""
    Hex(k = 1; include_self = false)

The hexagonal ball: all axial offsets of hex distance `≤ k`, on a hexagonal lattice.

Order 1 has 6 offsets, order 2 has 18 and order 3 has 36. A square lattice throws an
`ArgumentError`.

# Arguments
- `k::Integer = 1`: the order.

# Keywords
- `include_self = false`: whether to include the zero offset.

# Examples
```jldoctest
julia> using CorePotts

julia> length(relation(Hex(2), Lattice((10, 10); geometry = Hexagonal())))
18
```

See also [`Hexagonal`](@ref), [`relation`](@ref).
"""
struct Hex <: AbstractRelationSpec
    k::Int
    include_self::Bool
end
Hex(k::Integer = 1; include_self = false) = Hex(k, include_self)
_hexdist(o) = (abs(o[1]) + abs(o[2]) + abs(o[1] + o[2])) ÷ 2

# Candidates per geometry: on hexagonal lattices Moore/VonNeumann are the hex balls and
# Euclidean specs use embedded distances.
_candidates(spec, N, ::Square) = _candidates(spec, N)
function _candidates(spec::Hex, N, ::Square)
    throw(ArgumentError("`Hex(k)` needs a hexagonal lattice (`geometry = Hexagonal()`)"))
end
function _candidates(spec::Union{Hex, Moore, VonNeumann}, N, ::Hexagonal)
    return [o for o in _box(2, spec.k) if _hexdist(o) <= spec.k]
end
_candidates(spec::Stencil, N, ::Hexagonal) = _candidates(spec, N)
_hexsq(o) = (x = o[1] + o[2] / 2; y = o[2] * sqrt(3) / 2; x^2 + y^2)
function _candidates(spec::EuclideanBall, N, ::Hexagonal)
    return [
        o for o in _box(2, ceil(Int, 2spec.r / sqrt(3)))
            if _hexsq(o) <= spec.r^2 + 1.0e-9
    ]
end
function _candidates(spec::NeighborOrder, N, ::Hexagonal)
    box = _box(2, 2spec.k)
    shells = sort!(unique(round(_hexsq(o); digits = 9) for o in box if _hexsq(o) > 0))
    cutoff = shells[spec.k] + 1.0e-9
    return [o for o in box if _hexsq(o) <= cutoff]
end
_ordersq(::Square, o) = _sq(o)
_ordersq(::Hexagonal, o) = round(_hexsq(o); digits = 9)
_include_self(spec) = spec.include_self

"""
    relation(spec, lattice) -> Relation

Resolve the relation specification `spec` into the offsets it has on `lattice`.

The offsets are sorted by squared length, then lexicographically. A relation that aliases
under a small periodic axis throws an `ArgumentError`: two offsets that reach the same
site, or a nonzero offset that wraps onto the site itself. A resolved relation is returned
as it is.

# Arguments
- `spec`: an [`AbstractRelationSpec`](@ref), or an already resolved relation.
- `lattice::Lattice`: the lattice.

# Returns
- A `Relation` with the offsets as `Int32` tuples, and `Float32` weights for a
  [`Weighted`](@ref) spec. `length` gives the offset count.

# Examples
```jldoctest
julia> using CorePotts

julia> r = relation(VonNeumann(), Lattice((10, 10)));

julia> length(r), r.offsets[1]
(4, (-1, 0))
```

See also [`Moore`](@ref), [`VonNeumann`](@ref), [`weight`](@ref).
"""
function relation(spec::AbstractRelationSpec, l::Lattice{N}) where {N}
    offs = _offsets(spec, l)
    return Relation{N, length(offs)}(Tuple(map(o -> Int32.(o), offs)))
end
function relation(spec::Weighted, l::Lattice{N}) where {N}
    offs = _offsets(spec.spec, l)
    w = Tuple(Float32[_weight(spec.weight, l.geometry, o) for o in offs])
    all(isfinite, w) || throw(ArgumentError("relation weights must be finite, got $w"))
    return Relation{N, length(offs), typeof(w)}(Tuple(map(o -> Int32.(o), offs)), w)
end

_weight(f, g, o) = f(_embed(g, Tuple(o)))
_weight(f::OnIndices, g, o) = f.f(Tuple(o))

function _offsets(spec::AbstractRelationSpec, l::Lattice{N}) where {N}
    offs = unique(_candidates(spec, N, l.geometry))
    filter!(o -> _include_self(spec) || !all(iszero, o), offs)
    sort!(offs; by = o -> (_ordersq(l.geometry, o), o))
    _check_aliasing(offs, l)
    return offs
end
relation(r::Relation, ::Lattice) = r
"""
    has_origin(relation) -> Bool

Return `true` if `relation` contains the zero offset, so a site is its own neighbor.

# Arguments
- `relation`: a relation from [`relation`](@ref).

# Returns
- `Bool`.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.has_origin(relation(Moore(; include_self = true), Lattice((5, 5))))
true
```
"""
has_origin(r::Relation) = any(o -> all(iszero, o), r.offsets)

"""
    is_symmetric(relation) -> Bool

Return `true` if the negation of every offset is also in `relation`, with the same
weight.

A symmetric relation counts each pair of sites from both sides.

# Arguments
- `relation`: a relation from [`relation`](@ref).

# Returns
- `Bool`.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.is_symmetric(relation(Stencil([(1, 0)]), Lattice((5, 5))))
false
```
"""
function is_symmetric(r::Relation)
    for (k, o) in enumerate(r.offsets)
        j = findfirst(==(map(-, o)), r.offsets)
        j === nothing && return false
        r.weights === nothing || r.weights[j] == r.weights[k] || return false
    end
    return true
end

function _check_aliasing(offs, l::Lattice{N}) where {N}
    wrap(o) = ntuple(d -> l.periodic[d] ? mod(o[d], l.dims[d]) : o[d], N)
    seen = Dict{NTuple{N, Int}, NTuple{N, Int}}()
    for o in offs
        w = wrap(o)
        !all(iszero, o) && all(iszero, w) &&
            throw(ArgumentError("offset $o wraps onto the origin on lattice $(l.dims)"))
        haskey(seen, w) &&
            throw(ArgumentError("offsets $(seen[w]) and $o alias on lattice $(l.dims)"))
        seen[w] = o
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# Site lists and site counts (D-253): `Int32` up to 2³¹ − 1 sites, `Int64` above. The width
# is part of the array types, chosen once from the site count, so a lattice that fits keeps
# the Int32 arrays and their code exactly; there is no per-site branch.
const _FORCE_WIDE_SITES = Ref(false)    # tests: the Int64 width on a small lattice
function site_index_type(nsite::Integer)
    return (_FORCE_WIDE_SITES[] || nsite > typemax(Int32)) ? Int64 : Int32
end
# Whether the backend's kernels have 64-bit atomics, which the Int64 mask counters and the
# `@convert` scratch need. Metal's do not (its extension says so): there, a lattice above
# 2³¹ − 1 sites whose mask follows the state, or with an `@convert` pass, is refused at
# `init` (`_mobility_scratch`, `_check_convert_atomics`).
_atomic64(backend) = true

# ---------------------------------------------------------------------------------------
# Mobility: frozen sites (walls, obstacles, fixed owners) are neither copy targets nor
# sources and are not counted in N; they still count in contact energies.

"""
    AllMobile()

The default mobility: every site may change its cell number, at no cost per copy attempt.

See also [`MaskMobility`](@ref), [`is_mobile`](@ref).
"""
struct AllMobile end

"""
    MaskMobility(frozen, sites)

The mobility of a run with frozen sites: a site with `frozen[i] = true` is never a target
or a source of a copy.

Frozen sites still count in contact energies. On the host, `sites` lists the mobile sites:
[`SequentialCPM`](@ref) draws its targets from it, and the mobile count is
`length(sites)`. Its element type is `Int32`, or `Int64` above 2³¹ − 1 sites. On a device
`sites` is `nothing`: [`CheckerboardCPM`](@ref) reads only `frozen`, and the integrator
keeps the mobile count on the host. A refresh ([`refresh_frozen!`](@ref), `reinit!`)
rewrites both arrays in place, so the integrator's context stays valid.

# Fields
- `frozen`: a `Bool` array of the lattice's size.
- `sites`: the linear indices of the mobile sites, or `nothing` on a device.

See also [`AllMobile`](@ref), [`is_mobile`](@ref), [`frozen_sites`](@ref).
"""
struct MaskMobility{M, S}
    frozen::M
    sites::S
end
Adapt.@adapt_structure MaskMobility

function mobility(frozen::Union{Nothing, AbstractArray{Bool}}, l::Lattice)
    frozen === nothing && return AllMobile()
    size(frozen) == l.dims ||
        throw(ArgumentError("frozen mask has size $(size(frozen)), lattice $(l.dims)"))
    any(!, frozen) ||
        # at construction only
        throw(ArgumentError("every site is frozen: clear at least one entry in `frozen` \
            or use `constraint = frozen_dynamics` to keep all sites fixed"))
    sites = site_index_type(length(frozen))[]
    _mobile_sites!(sites, frozen)
    return MaskMobility(Array{Bool}(frozen), sites)
end

# The mobility in the integrator's context: on a device, the mask alone (see
# `MaskMobility`).
_backend_mobility(backend, m::AllMobile) = m
_backend_mobility(::KernelAbstractions.CPU, m::MaskMobility) = m
function _backend_mobility(backend, m::MaskMobility)
    return MaskMobility(_to_backend(backend, m.frozen), nothing)
end

# `sites` ← the mobile sites of a host mask, in place. The first `resize!` grows the list to
# the full site count once (later calls stay within that capacity and do not allocate). A
# run may freeze every site: the list is then empty and an MCS makes no attempt.
function _mobile_sites!(sites::Union{Vector{Int32}, Vector{Int64}}, frozen)
    resize!(sites, length(frozen))
    j = 0
    # bounds: i ∈ eachindex(frozen); j ≤ i ≤ length(sites) after the resize!
    @inbounds for i in eachindex(IndexLinear(), frozen)
        frozen[i] && continue
        j += 1
        sites[j] = i
    end
    resize!(sites, j)
    return sites
end

# Overwrite a mask mobility from a host mask (the custom-rule fallback of
# `refresh_frozen!`). `stats` counts the host→device copy (D-085), or `nothing`.
function _set_mobility!(stats, m::MaskMobility, frozen::AbstractArray{Bool})
    counted_copy!(stats, m.frozen, frozen isa Array{Bool} ? frozen : Array{Bool}(frozen))
    m.sites === nothing || _mobile_sites!(m.sites, frozen)
    return nothing
end
function _set_mobility!(stats, m, frozen)
    throw(
        ArgumentError(
            "the frozen mask changed \
                from $(frozen === nothing ? "a mask to none" : "none to a mask"); use \
                    `remake` and `init`"
        )
    )
end

# The standard rule, one work item per site: a site is frozen when it lies outside the
# lattice domain or its owner's kind is one of `kinds`. Counts, in `counter`, the change of
# the mobile count (entry 2) and the number of sites that changed (entry 3); entry 1 is the
# lifecycle's event count, read in the same transfer. The counter has the site lists' width
# (`site_index_type`), so neither count wraps on any lattice.
@inline function _frozen_body!(i, frozen, counter, σ, kind, kinds, lat)
    # bounds: i ≤ nsites = length(σ) = length(frozen); owners s ≤ capacity
    s = @inbounds σ[i]
    f = !in_domain(lat, i) || (s != 0 && _in_kinds(@inbounds(kind[s]), kinds))
    if f != @inbounds(frozen[i])
        @inbounds frozen[i] = f
        Atomix.@atomic counter[2] += f ? -one(eltype(counter)) : one(eltype(counter))
        Atomix.@atomic counter[3] += one(eltype(counter))
    end
    return nothing
end
@inline _in_kinds(k, kinds::Tuple) = any(==(k), kinds)

"""
    is_mobile(mobility, i) -> Bool

Return `true` if site `i` may change its cell number under `mobility`.

# Arguments
- `mobility`: [`AllMobile`](@ref) or [`MaskMobility`](@ref).
- `i`: a linear site index (not bounds-checked).

# Returns
- `Bool`: `true` for every site under `AllMobile`, `!frozen[i]` under `MaskMobility`.

See also [`MaskMobility`](@ref).
"""
@inline is_mobile(::AllMobile, i) = true
# bounds: i is a site index ≤ nsites = length(m.frozen)
@inline is_mobile(m::MaskMobility, i) = !@inbounds(m.frozen[i])
nmobile(::AllMobile, l::Lattice) = nsites(l)
nmobile(m::MaskMobility{<:Any, <:AbstractVector}, l::Lattice) = length(m.sites)
@inline mobile_site(::AllMobile, j) = j
# bounds: j ≤ nmobile(m) = length(m.sites) (the sweep draws j in that range)
@inline mobile_site(m::MaskMobility, j) = Int(@inbounds m.sites[j])
