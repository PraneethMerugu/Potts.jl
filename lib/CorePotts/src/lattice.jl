# N-dimensional Cartesian lattices and neighborhood relations of any order.

abstract type AbstractBoundary end
"""Opposite faces are identified."""
struct Periodic <: AbstractBoundary end
"""No neighbours across the face: out-of-domain directions are counted null attempts."""
struct Closed <: AbstractBoundary end

"""
    Lattice(dims; boundary = Periodic())

A Cartesian lattice. `boundary` is one boundary for all axes or a tuple with one per axis.
"""
struct Lattice{N}
    dims::NTuple{N, Int}
    periodic::NTuple{N, Bool}
end

function Lattice(dims::NTuple{N, Integer}; boundary = Periodic()) where {N}
    b = boundary isa AbstractBoundary ? ntuple(_ -> boundary, N) : Tuple(boundary)
    length(b) == N || throw(ArgumentError("need $N boundaries, got $(length(b))"))
    all(>(0), dims) || throw(ArgumentError("lattice dimensions must be positive"))
    return Lattice{N}(Int.(dims), map(x -> x isa Periodic, b))
end

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

Neighbour of `x` at `offset`. Periodic axes wrap; a closed axis yields `inside = false`.
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
    return inside, w
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
