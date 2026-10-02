# Proposal drives, biases and constraints (ROADMAP M2.5, M2.6).
#
# Drives are energy-like and returned by `delta_H` (divided by T in acceptance); biases add
# directly to log α through `CPMFunction(…; bias)`; constraints veto through `constraint`.
# All primitives read the pre-commit state.

"""A cell extends into the medium (`old` is medium, `new` is a cell)."""
@inline is_extension(prop) = prop.old == 0 && prop.new != 0
"""A cell retracts, leaving the medium (`old` is a cell, `new` is medium)."""
@inline is_retraction(prop) = prop.old != 0 && prop.new == 0

"""
    chemotaxis_delta(c, prop, χ; response = identity)

Chemotaxis `ΔH = −χ (r(c[target]) − r(c[source]))` with a response `r` applied to each
concentration: `identity` (linear), `saturating(s)` = `c/(s + c)`,
`saturating_linear(s)` = `c/(s c + 1)`, or any function. Gate it by kind and copy type in
the model.
"""
@inline chemotaxis_delta(c, prop, χ; response::F = identity) where {F} =
    -χ * (response(@inbounds(c[prop.target])) - response(@inbounds(c[prop.source])))

"""`saturating(s)`: the response `c -> c/(s + c)`."""
saturating(s) = c -> c / (s + c)
"""`saturating_linear(s)`: the response `c -> c/(s c + 1)`."""
saturating_linear(s) = c -> c / (s * c + 1)

"""Folds for [`neighborhood_mean`](@ref)."""
abstract type MeanFold end
"""Arithmetic mean."""
struct ArithmeticMean <: MeanFold end
"""Geometric mean, zero if any value is zero."""
struct GeometricMean <: MeanFold end
"""`exp(mean(log1p(max(x, 0)))) − 1`."""
struct Log1pGeometricMean <: MeanFold end

@inline _fold_term(::ArithmeticMean, a) = a
@inline _fold_term(::GeometricMean, a) = a > 0 ? log(a) : zero(a)
@inline _fold_term(::Log1pGeometricMean, a) = log1p(max(zero(a), a))
@inline _fold_end(::ArithmeticMean, total, n, zero_seen) = total / n
@inline _fold_end(::GeometricMean, total, n, zero_seen) = zero_seen ? zero(total) : exp(total / n)
@inline _fold_end(::Log1pGeometricMean, total, n, zero_seen) = expm1(total / n)

"""
    neighborhood_mean(x, σ, ctx, site, owner; relation, fold = GeometricMean())

Mean of `x` over `site` (if `owner` owns it) and its `relation` neighbours owned by
`owner`. Zero for the medium or an empty set. The neighbourhood-memory drive of the Act
family is `−(λ/max)(mean(source, new) − mean(target, old))`.
"""
@inline function neighborhood_mean(x, σ, ctx, site, owner; relation, fold::M = GeometricMean()) where {M <: MeanFold}
    T = eltype(x)
    owner == 0 && return zero(T)
    lat = ctx.lattice
    p = coordinates(lat, site)
    total = zero(T)
    n = 0
    zero_seen = false
    if @inbounds(σ[site]) == owner
        a = @inbounds x[site]
        total += _fold_term(fold, a)
        zero_seen |= a == 0
        n += 1
    end
    for k in 1:length(relation)
        inside, y = shift(lat, p, @inbounds relation.offsets[k])
        inside || continue
        j = linear_index(lat, y)
        @inbounds(σ[j]) == owner || continue
        a = @inbounds x[j]
        total += _fold_term(fold, a)
        zero_seen |= a == 0
        n += 1
    end
    n == 0 && return zero(T)
    return _fold_end(fold, total, n, zero_seen)
end

"""Extinction policy `ForbidExtinction`: veto a copy that would remove a cell's last site."""
@inline forbid_extinction(volume, prop) = prop.old == 0 || @inbounds(volume[prop.old]) > 1

# ---------------------------------------------------------------------------------------
# Local connectivity

"""
    local_components(σ, ctx, prop) -> Int

Number of pieces the losing cell's (`prop.old`) sites around the target would form if the
copy were accepted: face-connected components of its sites in the target's Moore
neighbourhood (3ᴺ − 1 ≤ 26 sites, bitmask flood fill), or arcs of the 6-ring on a hexagonal
lattice. Out-of-domain sites are not part of the cell. Zero for the medium, when the target
is the cell's last site, or when it is an isolated fragment. Connectivity rules are
expressions over it: `local_components == 1` (hard, exactly one piece as in CompuCell3D),
`λ * (local_components > 1)` (soft).
"""
@inline local_components(σ, ctx, prop::Proposal) = _local_components(ctx.lattice, σ, prop)

"""
`locally_connected(σ, ctx, prop)`: the losing cell stays exactly one local piece,
`prop.old == 0 || local_components(σ, ctx, prop) == 1`. Zero pieces (the cell's last
site, an isolated fragment) is rejected like two.
"""
@inline locally_connected(σ, ctx, prop::Proposal) = prop.old == 0 || local_components(σ, ctx, prop) == 1

"""
    ring_arcs(σ, ctx, prop) -> Int

Maximal runs of the losing cell's sites around the target's neighbour ring (the 8-ring on
a square 2D lattice, the 6-ring on a hexagonal one; out-of-domain sites count as medium).
"""
@inline ring_arcs(σ, ctx, prop::Proposal{2}) = prop.old == 0 ? 0 : _arcs(map(==(prop.old), _ring_owners(ctx.lattice, σ, prop.x)))

"""
    ring_cells(σ, ctx, prop) -> Int

Number of distinct cells (medium excluded) on the target's neighbour ring (see
[`ring_arcs`](@ref)).
"""
@inline ring_cells(σ, ctx, prop::Proposal{2}) = _distinct_cells(_ring_owners(ctx.lattice, σ, prop.x))

# The 6 hex neighbours in angular order (axial offsets at 0°, 60°, …, 300°).
const _HEX_RING = ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1))
# The 8 square neighbours in clockwise order.
const _MOORE_RING = ((-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0))

@inline _ring_owners(lat::Lattice{2, M, Hexagonal}, σ, x) where {M} = _owners(lat, σ, x, _HEX_RING)
@inline _ring_owners(lat::Lattice{2}, σ, x) = _owners(lat, σ, x, _MOORE_RING)
@inline _owners(lat, σ, x, ring::NTuple{K}) where {K} = ntuple(Val(K)) do k
    o = ring[k]
    inside, y = shift(lat, x, (Int32(o[1]), Int32(o[2])))
    inside ? @inbounds(σ[linear_index(lat, y)]) : Int32(0)
end

# Number of maximal runs of `true` in a cyclic tuple (0 if none, 1 if all).
@inline function _arcs(same::NTuple{K, Bool}) where {K}
    n = 0
    for k in 1:K
        n += same[k] & !same[k == 1 ? K : k - 1]
    end
    return (n == 0 && same[1]) ? 1 : n
end

@inline function _distinct_cells(owners::NTuple{K}) where {K}
    distinct = 0
    for k in 1:K
        o = owners[k]
        o > 0 || continue
        seen = false
        for j in 1:(k - 1)
            owners[j] == o && (seen = true)
        end
        distinct += !seen
    end
    return distinct
end

# Hexagonal: consecutive sites of the 6-ring are mutually adjacent, so the pieces are arcs.
@inline function _local_components(lat::Lattice{2, M, Hexagonal}, σ, prop::Proposal{2}) where {M}
    prop.old == 0 && return 0
    return _arcs(map(==(prop.old), _owners(lat, σ, prop.x, _HEX_RING)))
end

@inline function _local_components(lat::Lattice{N}, σ, prop::Proposal{N}) where {N}
    a = prop.old
    a == 0 && return 0
    M = 3^N
    mask = UInt32(0)
    for p in 0:(M - 1)
        off = _ternary_offset(p, Val(N))
        all(iszero, off) && continue
        inside, y = shift(lat, prop.x, off)
        (inside && @inbounds(σ[linear_index(lat, y)]) == a) && (mask |= UInt32(1) << p)
    end
    n = 0
    while mask != 0                                 # peel off one component at a time
        reached = mask & (~mask + UInt32(1))        # lowest set bit
        while true
            grown = reached
            for p in 0:(M - 1)
                (reached >> p) & 1 == 1 || continue
                grown |= _face_neighbors(p, Val(N)) & mask
            end
            grown == reached && break
            reached = grown
        end
        mask &= ~reached
        n += 1
    end
    return n
end

@inline _ternary_offset(p, ::Val{N}) where {N} =
    ntuple(d -> Int32(rem(div(p, 3^(d - 1)), 3) - 1), Val(N))

@inline function _face_neighbors(p, ::Val{N}) where {N}
    m = UInt32(0)
    center = (3^N - 1) ÷ 2
    for d in 1:N
        digit = rem(div(p, 3^(d - 1)), 3)
        digit > 0 && (q = p - 3^(d - 1); q != center && (m |= UInt32(1) << q))
        digit < 2 && (q = p + 3^(d - 1); q != center && (m |= UInt32(1) << q))
    end
    return m
end
