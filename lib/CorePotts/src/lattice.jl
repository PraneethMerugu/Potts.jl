# N-dimensional Cartesian lattices and neighborhood relations of any order.

abstract type AbstractBoundary end
"""Opposite faces are identified."""
struct Periodic <: AbstractBoundary end
"""No neighbours across the face: out-of-domain directions are counted null attempts."""
struct Closed <: AbstractBoundary end

abstract type AbstractGeometry end
"""Square (cubic in 3D) lattice: site coordinates are positions."""
struct Square <: AbstractGeometry end
"""
Hexagonal 2D lattice in axial coordinates: site `(q, r)` sits at `(q + r/2, r·√3/2)`, and its
six nearest neighbours are the offsets `(±1, 0)`, `(0, ±1)`, `(1, -1)`, `(-1, 1)` — a subset of
Moore(1), so checkerboard colouring, periodic wrapping and the integer moment trackers carry
over. Periodic axes make a rhombic torus. Positions, distances, centroids, shapes and division
planes use the embedding; `Moore(k)`/`VonNeumann(k)` mean `Hex(k)` here.
"""
struct Hexagonal <: AbstractGeometry end

"""
    Lattice(dims; boundary = Periodic(), domain = nothing, geometry = Square())

A Cartesian lattice. `boundary` is one boundary for all axes or a tuple with one per axis.
`domain` restricts it to an irregular region (ROADMAP M2.1b): a `Bool` array over the
lattice or a predicate of the site position, `x -> …` (Cartesian: `embed`ded coordinates on a
hexagonal lattice; wrap it in `OnIndices` to receive lattice coordinates). Sites outside the domain never
change owner and must belong to the medium. The domain edge is closed: `shift` reports
neighbours outside it as outside the lattice, so contacts, surfaces, gathers, proposals and
field stencils (zero flux) all stop there.
"""
struct Lattice{N, M, G <: AbstractGeometry}
    dims::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    mask::M                       # `nothing`, or a Bool array (`true` = in the domain)
    geometry::G
end
Lattice{N}(dims, periodic) where {N} = Lattice{N, Nothing, Square}(dims, periodic, nothing, Square())
Lattice{N, M}(dims, periodic, mask) where {N, M} = Lattice{N, M, Square}(dims, periodic, mask, Square())

function Lattice(dims::NTuple{N, Integer}; boundary = Periodic(), domain = nothing,
        geometry::AbstractGeometry = Square()) where {N}
    geometry isa Hexagonal && N != 2 && throw(ArgumentError("hexagonal lattices are 2D"))
    b = boundary isa AbstractBoundary ? ntuple(_ -> boundary, N) : Tuple(boundary)
    length(b) == N || throw(ArgumentError("need $N boundaries, got $(length(b))"))
    all(>(0), dims) || throw(ArgumentError("lattice dimensions must be positive"))
    d = Int.(dims)
    mask = _domain_mask(domain, d, geometry)
    mask === nothing || any(mask) || throw(ArgumentError("the domain contains no sites"))
    return Lattice{N, typeof(mask), typeof(geometry)}(d, map(x -> x isa Periodic, b), mask, geometry)
end

"""
    OnIndices(f)

A domain predicate (or relation weight) that receives lattice coordinates (axial `(q, r)`
on a hexagonal lattice) instead of Cartesian positions.
"""
struct OnIndices{F}
    f::F
end

_domain_mask(::Nothing, dims, g) = nothing
function _domain_mask(m::AbstractArray{Bool}, dims, g)
    size(m) == dims || throw(ArgumentError("domain mask has size $(size(m)), lattice $dims"))
    return Array{Bool}(m)
end
_domain_mask(f, dims, g) = Bool[f(_embed(g, Tuple(x))) for x in CartesianIndices(dims)]
_domain_mask(f::OnIndices, dims, g) = Bool[f.f(Tuple(x)) for x in CartesianIndices(dims)]


# `embed` by geometry alone (for construction, before the lattice exists)
_embed(::Square, v) = v
_embed(::Hexagonal, v) = (v[1] + v[2] / 2, v[2] * sqrt(3) / 2)

Adapt.adapt_structure(to, l::Lattice{N}) where {N} =
    (m = Adapt.adapt(to, l.mask); Lattice{N, typeof(m), typeof(l.geometry)}(l.dims, l.periodic, m, l.geometry))
Base.:(==)(a::Lattice, b::Lattice) = a.dims == b.dims && a.periodic == b.periodic && a.geometry == b.geometry &&
    (a.mask === b.mask || (a.mask !== nothing && b.mask !== nothing && Array(a.mask) == Array(b.mask)))
Base.hash(l::Lattice, h::UInt) = hash((l.dims, l.periodic, l.mask === nothing ? nothing : Array(l.mask), l.geometry), h)

"""
    embed(lattice, v) -> NTuple

Lattice-coordinate vector `v` (an offset, or a position) as a Cartesian vector: the identity on
square lattices, `(q + r/2, r·√3/2)` on hexagonal ones. Linear, so it maps centroids, shifts
and offsets alike.
"""
@inline embed(::Lattice{N, M, Square}, v) where {N, M} = v
@inline function embed(::Lattice{2, M, Hexagonal}, v) where {M}
    T = float(typeof(v[1]))
    return (T(v[1]) + T(v[2]) / 2, T(v[2]) * sqrt(T(3)) / 2)
end

"""Covariance (upper triangle) of lattice-coordinate data mapped by `embed`."""
@inline embed_covariance(::Lattice{N, M, Square}, C) where {N, M} = C
@inline function embed_covariance(::Lattice{2, M, Hexagonal}, C) where {M}
    a, b, d = C
    T = typeof(a)
    s = sqrt(T(3)) / 2
    return (a + b + d / 4, s * (b + d / 2), T(3) / 4 * d)
end

"""`true` if site `i` is in the lattice's domain."""
@inline in_domain(::Lattice{N, Nothing}, i) where {N} = true
@inline in_domain(l::Lattice, i) = @inbounds l.mask[i]

"""The lattice with its domain mask on the host (for host code given a device context). The
mask is static: its host copy is made once per device mask and reused (read-only)."""
host_lattice(l::Lattice) = _host_lattice(nothing, l)
# `stats` counts the mask copy (D-085), or `nothing`; the copy is cached (D-092, audit A4/H3)
_host_lattice(stats, l::Lattice{N, Nothing}) where {N} = l
_host_lattice(stats, l::Lattice) = _adapt_host_cached(stats, l)

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

`spec` with per-offset weights `weight(offset)` of the Cartesian offset (e.g.
`o -> 1 / sqrt(sum(abs2, o))` for distance-weighted contact; `OnIndices(f)` receives lattice
offsets instead). Weights are stored as `Float32`.
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

"""
    Hex(k)

Hexagonal ball of hex distance ≤ `k` (order 1 = 6 neighbours, 2 = 18, 3 = 36) on a
hexagonal lattice (axial offsets).
"""
struct Hex <: RelationSpec
    k::Int
    include_self::Bool
end
Hex(k::Integer = 1; include_self = false) = Hex(k, include_self)
_hexdist(o) = (abs(o[1]) + abs(o[2]) + abs(o[1] + o[2])) ÷ 2

# Candidates per geometry: on hexagonal lattices Moore/VonNeumann are the hex balls and
# Euclidean specs use embedded distances.
_candidates(spec, N, ::Square) = _candidates(spec, N)
_candidates(spec::Hex, N, ::Square) = throw(ArgumentError("`Hex(k)` needs a hexagonal lattice (`geometry = Hexagonal()`)"))
_candidates(spec::Union{Hex, Moore, VonNeumann}, N, ::Hexagonal) = [o for o in _box(2, spec.k) if _hexdist(o) <= spec.k]
_candidates(spec::Stencil, N, ::Hexagonal) = _candidates(spec, N)
_hexsq(o) = (x = o[1] + o[2] / 2; y = o[2] * sqrt(3) / 2; x^2 + y^2)
_candidates(spec::Ball, N, ::Hexagonal) = [o for o in _box(2, ceil(Int, 2spec.r / sqrt(3))) if _hexsq(o) <= spec.r^2 + 1e-9]
function _candidates(spec::NeighborOrder, N, ::Hexagonal)
    box = _box(2, 2spec.k)
    shells = sort!(unique(round(_hexsq(o); digits = 9) for o in box if _hexsq(o) > 0))
    cutoff = shells[spec.k] + 1e-9
    return [o for o in box if _hexsq(o) <= cutoff]
end
_ordersq(::Square, o) = _sq(o)
_ordersq(::Hexagonal, o) = round(_hexsq(o); digits = 9)
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
    w = Tuple(Float32[_weight(spec.weight, l.geometry, o) for o in offs])
    all(isfinite, w) || throw(ArgumentError("relation weights must be finite, got $w"))
    return Relation{N, length(offs), typeof(w)}(Tuple(map(o -> Int32.(o), offs)), w)
end

_weight(f, g, o) = f(_embed(g, Tuple(o)))
_weight(f::OnIndices, g, o) = f.f(Tuple(o))

function _offsets(spec::RelationSpec, l::Lattice{N}) where {N}
    offs = unique(_candidates(spec, N, l.geometry))
    filter!(o -> _include_self(spec) || !all(iszero, o), offs)
    sort!(offs; by = o -> (_ordersq(l.geometry, o), o))
    _check_aliasing(offs, l)
    return offs
end
relation(r::Relation, ::Lattice) = r
has_origin(r::Relation) = any(o -> all(iszero, o), r.offsets)

"""Whether every offset's negation is in `r` with the same weight (a symmetric pair relation)."""
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
# Mobility: frozen sites (walls, obstacles, fixed owners) are neither copy targets nor
# sources and are not counted in N; they still count in contact energies.

"""Every site may change owner (the default; no per-attempt cost)."""
struct AllMobile end

"""
Sites with `frozen[i] = true` never change owner and never donate. On the host, `sites`
lists the mobile sites (SequentialCPM draws its targets from them; the count is
`length(sites)`). On a device `sites` is `nothing`: CheckerboardCPM reads only `frozen`, and
the integrator keeps the mobile count on the host. A refresh (`refresh_frozen!`, `reinit!`)
rewrites both in place, so the integrator's context stays valid.
"""
struct MaskMobility{M, S}
    frozen::M
    sites::S
end
Adapt.@adapt_structure MaskMobility

function mobility(frozen::Union{Nothing, AbstractArray{Bool}}, l::Lattice)
    frozen === nothing && return AllMobile()
    size(frozen) == l.dims || throw(ArgumentError("frozen mask has size $(size(frozen)), lattice $(l.dims)"))
    any(!, frozen) || throw(ArgumentError("every site is frozen"))     # at construction only
    sites = Int32[]
    _mobile_sites!(sites, frozen)
    return MaskMobility(Array{Bool}(frozen), sites)
end

# The mobility in the integrator's context: on a device, the mask alone (see `MaskMobility`).
_backend_mobility(backend, m::AllMobile) = m
_backend_mobility(::KernelAbstractions.CPU, m::MaskMobility) = m
_backend_mobility(backend, m::MaskMobility) = MaskMobility(_to_backend(backend, m.frozen), nothing)

# `sites` ← the mobile sites of a host mask, in place. The first `resize!` grows the list to
# the full site count once (later calls stay within that capacity and do not allocate). A
# run may freeze every site: the list is then empty and an MCS makes no attempt.
function _mobile_sites!(sites::Vector{Int32}, frozen)
    resize!(sites, length(frozen))
    j = 0
    @inbounds for i in eachindex(IndexLinear(), frozen)
        frozen[i] && continue
        j += 1
        sites[j] = i
    end
    resize!(sites, j)
    return sites
end

# Overwrite a mask mobility from a host mask (the custom-rule fallback of `refresh_frozen!`).
# `stats` counts the host→device copy (D-085), or `nothing`.
function _set_mobility!(stats, m::MaskMobility, frozen::AbstractArray{Bool})
    _copy!(stats, m.frozen, frozen isa Array{Bool} ? frozen : Array{Bool}(frozen))
    m.sites === nothing || _mobile_sites!(m.sites, frozen)
    return nothing
end
_set_mobility!(stats, m, frozen) = throw(ArgumentError(
    "the frozen mask changed from $(frozen === nothing ? "a mask to none" : "none to a mask"); use `remake` and `init`"))

# The standard rule, one work item per site: a site is frozen when it lies outside the
# lattice domain or its owner's kind is one of `kinds`. Counts, in `counter`, the change of
# the mobile count (entry 2) and the number of sites that changed (entry 3); entry 1 is the
# lifecycle's event count, read in the same transfer.
@inline function _frozen_body!(i, frozen, counter, σ, kind, kinds, lat)
    s = @inbounds σ[i]
    f = !in_domain(lat, i) || (s != 0 && _in_kinds(@inbounds(kind[s]), kinds))
    if f != @inbounds(frozen[i])
        @inbounds frozen[i] = f
        Atomix.@atomic counter[2] += f ? Int32(-1) : Int32(1)
        Atomix.@atomic counter[3] += Int32(1)
    end
    return nothing
end
@inline _in_kinds(k, kinds::Tuple) = any(==(k), kinds)

@inline is_mobile(::AllMobile, i) = true
@inline is_mobile(m::MaskMobility, i) = !@inbounds(m.frozen[i])
nmobile(::AllMobile, l::Lattice) = nsites(l)
nmobile(m::MaskMobility{<:Any, <:AbstractVector}, l::Lattice) = length(m.sites)
@inline mobile_site(::AllMobile, j) = j
@inline mobile_site(m::MaskMobility, j) = Int(@inbounds m.sites[j])
