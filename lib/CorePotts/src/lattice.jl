# N-dimensional Cartesian lattices and neighborhood relations of any order.

abstract type AbstractBoundary end
"""Opposite faces are identified."""
struct Periodic <: AbstractBoundary end
"""No neighbours across the face: out-of-domain directions are counted null attempts."""
struct Closed <: AbstractBoundary end

"""
    Lattice(dims; boundary = Periodic(), domain = nothing)

A Cartesian lattice. `boundary` is one boundary for all axes or a tuple with one per axis.
`domain` restricts it to an irregular region (ROADMAP M2.1b): a `Bool` array over the
lattice or a predicate of the site coordinates, `x -> …`. Sites outside the domain never
change owner and must belong to the medium. The domain edge is closed: `shift` reports
neighbours outside it as outside the lattice, so contacts, surfaces, gathers, proposals and
field stencils (zero flux) all stop there.
"""
struct Lattice{N, M}
    dims::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    mask::M                       # `nothing`, or a Bool array (`true` = in the domain)
end
Lattice{N}(dims, periodic) where {N} = Lattice{N, Nothing}(dims, periodic, nothing)

function Lattice(dims::NTuple{N, Integer}; boundary = Periodic(), domain = nothing) where {N}
    b = boundary isa AbstractBoundary ? ntuple(_ -> boundary, N) : Tuple(boundary)
    length(b) == N || throw(ArgumentError("need $N boundaries, got $(length(b))"))
    all(>(0), dims) || throw(ArgumentError("lattice dimensions must be positive"))
    d = Int.(dims)
    mask = _domain_mask(domain, d)
    mask === nothing || any(mask) || throw(ArgumentError("the domain contains no sites"))
    return Lattice{N, typeof(mask)}(d, map(x -> x isa Periodic, b), mask)
end

_domain_mask(::Nothing, dims) = nothing
function _domain_mask(m::AbstractArray{Bool}, dims)
    size(m) == dims || throw(ArgumentError("domain mask has size $(size(m)), lattice $dims"))
    return Array{Bool}(m)
end
_domain_mask(f, dims) = Bool[f(Tuple(x)) for x in CartesianIndices(dims)]

Adapt.adapt_structure(to, l::Lattice{N}) where {N} =
    (m = Adapt.adapt(to, l.mask); Lattice{N, typeof(m)}(l.dims, l.periodic, m))
Base.:(==)(a::Lattice, b::Lattice) = a.dims == b.dims && a.periodic == b.periodic &&
    (a.mask === b.mask || (a.mask !== nothing && b.mask !== nothing && Array(a.mask) == Array(b.mask)))
Base.hash(l::Lattice, h::UInt) = hash((l.dims, l.periodic, l.mask === nothing ? nothing : Array(l.mask)), h)

"""`true` if site `i` is in the lattice's domain."""
@inline in_domain(::Lattice{N, Nothing}, i) where {N} = true
@inline in_domain(l::Lattice, i) = @inbounds l.mask[i]

"""The lattice with its domain mask on the host (for host code given a device context)."""
host_lattice(l::Lattice{N, Nothing}) where {N} = l
host_lattice(l::Lattice) = Adapt.adapt(Array, l)

Base.ndims(::Lattice{N}) where {N} = N
nsites(l::Lattice) = prod(l.dims)
Base.size(l::Lattice) = l.dims

@inline function linear_index(l::Lattice{N}, x::NTuple{N, Int}) where {N}
    i = 0
    stride = 1
    for d in 1:N
        i += (x[d] - 1) * stride
        stride *= l.dims[d]
    end
    return i + 1
end

@inline function coordinates(l::Lattice{N}, i::Int) where {N}
    # Stride of axis d is prod(dims[1:d-1]); no captured mutable state (it would be boxed).
    return ntuple(Val(N)) do d
        stride = prod(ntuple(e -> e < d ? l.dims[e] : 1, Val(N)))
        rem(div(i - 1, stride), l.dims[d]) + 1
    end
end

"""
    shift(lattice, x, offset) -> (inside::Bool, y)

Neighbour of `x` at `offset`. Periodic axes wrap; a closed axis yields `inside = false`, as
does a pair with either site outside the lattice domain.
"""
@inline function shift(l::Lattice{N}, x::NTuple{N, Int}, off::NTuple{N, Int32}) where {N}
    # No captured mutable state in the closure (it would be boxed).
    y = ntuple(d -> x[d] + Int(off[d]), Val(N))
    inside = all(ntuple(d -> l.periodic[d] || 1 <= y[d] <= l.dims[d], Val(N)))
    w = ntuple(Val(N)) do d
        n = l.dims[d]
        v = y[d]
        ifelse(v < 1, ifelse(l.periodic[d], v + n, 1), ifelse(v > n, ifelse(l.periodic[d], v - n, n), v))
    end
    return inside && _in_domain(l.mask, l, x, w), w
end
# a pair interacts only if both sites are in the domain (symmetric, so brute-force sums
# over all sites agree with per-copy deltas)
"""`true` if `x + off` stays within the lattice faces (ignoring the domain mask)."""
@inline _within_faces(l::Lattice{N}, x, off) where {N} =
    all(ntuple(d -> l.periodic[d] || 1 <= x[d] + Int(off[d]) <= l.dims[d], Val(N)))
@inline _in_domain(::Nothing, l, x, w) = true
@inline _in_domain(m, l, x, w) = @inbounds(m[linear_index(l, x)]) && @inbounds(m[linear_index(l, w)])

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

"""Weight of the `k`-th offset (`Int32(1)` when unweighted, so counts stay integers)."""
@inline weight(::Relation{N, K, Nothing}, k) where {N, K} = Int32(1)
@inline weight(r::Relation, k) = @inbounds r.weights[k]
radius(r::Relation) = maximum(o -> maximum(abs, o; init = 0), r.offsets; init = 0)

abstract type RelationSpec end

"""Chebyshev ball: all offsets with `maximum(abs, o) ≤ k` (order 1 = 8 in 2D, 26 in 3D)."""
struct Moore <: RelationSpec
    k::Int
    include_self::Bool
end
Moore(k::Integer = 1; include_self = false) = Moore(k, include_self)

"""Manhattan ball: all offsets with `sum(abs, o) ≤ k` (order 1 = 4 in 2D, 6 in 3D)."""
struct VonNeumann <: RelationSpec
    k::Int
    include_self::Bool
end
VonNeumann(k::Integer = 1; include_self = false) = VonNeumann(k, include_self)

"""
    NeighborOrder(k)

All offsets in the first `k` distinct Euclidean distance shells, cumulative (CompuCell3D
`NeighborOrder`; counts 4, 8, 12, 20, 24, 28 in 2D and 6, 18, 26, 32, 56, 80 in 3D).
"""
struct NeighborOrder <: RelationSpec
    k::Int
    include_self::Bool
end
NeighborOrder(k::Integer = 1; include_self = false) = NeighborOrder(k, include_self)

"""Euclidean ball: all offsets with `‖o‖ ≤ r` (lattice units)."""
struct Ball <: RelationSpec
    r::Float64
    include_self::Bool
end
Ball(r::Real; include_self = false) = Ball(r, include_self)

"""
    Weighted(spec, weight)

`spec` with per-offset weights `weight(offset::NTuple{N,Int})` (e.g. `o -> 1 / sqrt(sum(abs2, o))`
for distance-weighted contact). Weights are stored as `Float32`.
"""
struct Weighted{S <: RelationSpec, F} <: RelationSpec
    spec::S
    weight::F
end

"""Explicit offsets."""
struct Stencil <: RelationSpec
    offsets::Vector{Vector{Int}}
    Stencil(offsets) = new([collect(Int, o) for o in offsets])
end

_box(N, R) = vec([Tuple(c) for c in CartesianIndices(ntuple(_ -> (-R):R, N))])
_sq(o) = sum(abs2, o)

function _candidates(spec::Moore, N)
    return [o for o in _box(N, spec.k)]
end
_candidates(spec::VonNeumann, N) = [o for o in _box(N, spec.k) if sum(abs, o) <= spec.k]
_candidates(spec::Ball, N) = [o for o in _box(N, floor(Int, spec.r)) if _sq(o) <= spec.r^2]
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
_include_self(spec) = spec.include_self

"""
    relation(spec, lattice) -> Relation

Resolve a neighborhood for `lattice`. Offsets are canonically ordered. Stencils that alias
under a small periodic axis (two offsets reaching the same site, or an offset reaching
the origin) are rejected.
"""
function relation(spec::RelationSpec, l::Lattice{N}) where {N}
    offs = _offsets(spec, l)
    return Relation{N, length(offs)}(Tuple(map(o -> Int32.(o), offs)))
end
function relation(spec::Weighted, l::Lattice{N}) where {N}
    offs = _offsets(spec.spec, l)
    w = Tuple(Float32[spec.weight(o) for o in offs])
    all(isfinite, w) || throw(ArgumentError("relation weights must be finite, got $w"))
    return Relation{N, length(offs), typeof(w)}(Tuple(map(o -> Int32.(o), offs)), w)
end

function _offsets(spec::RelationSpec, l::Lattice{N}) where {N}
    offs = unique(_candidates(spec, N))
    filter!(o -> _include_self(spec) || !all(iszero, o), offs)
    sort!(offs; by = o -> (_sq(o), o))
    _check_aliasing(offs, l)
    return offs
end
relation(r::Relation, ::Lattice) = r
has_origin(r::Relation) = any(o -> all(iszero, o), r.offsets)

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
# Mobility: frozen sites (walls, obstacles, fixed owners) are neither copy targets nor
# sources and are not counted in N; they still count in contact energies.

"""Every site may change owner (the default; no per-attempt cost)."""
struct AllMobile end

"""Sites with `frozen[i] = true` never change owner and never donate; `sites` lists the rest."""
struct MaskMobility{M, S}
    frozen::M
    sites::S
    n::Int
end
Adapt.@adapt_structure MaskMobility

function mobility(frozen::Union{Nothing, AbstractArray{Bool}}, l::Lattice)
    frozen === nothing && return AllMobile()
    size(frozen) == l.dims || throw(ArgumentError("frozen mask has size $(size(frozen)), lattice $(l.dims)"))
    sites = Int32[i for i in 1:nsites(l) if !frozen[i]]
    isempty(sites) && throw(ArgumentError("every site is frozen"))
    return MaskMobility(Array{Bool}(frozen), sites, length(sites))
end

@inline is_mobile(::AllMobile, i) = true
@inline is_mobile(m::MaskMobility, i) = !@inbounds(m.frozen[i])
nmobile(::AllMobile, l::Lattice) = nsites(l)
nmobile(m::MaskMobility, l::Lattice) = m.n
@inline mobile_site(::AllMobile, j) = j
@inline mobile_site(m::MaskMobility, j) = Int(@inbounds m.sites[j])
