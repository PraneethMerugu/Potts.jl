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
    chemotaxis_delta(c, prop, χ)

Savill–Hogeweg chemotaxis `ΔH = −χ (c[target] − c[source])` (nearest-site sampling); gate it
by kind and mode (e.g. `is_extension`) in the model.
"""
@inline chemotaxis_delta(c, prop, χ) = -χ * (@inbounds(c[prop.target]) - @inbounds(c[prop.source]))

"""
    act_mean(act, σ, ctx, site, owner; relation = ctx.act, shifted = false)

Mean activity of `owner`'s sites among `site` and its `relation` neighbours: the geometric
mean (Niculescu et al. 2015; zero if any value is zero), or with `shifted = true` the
legacy `exp(mean(log1p(a))) − 1`.
"""
@inline function act_mean(act, σ, ctx, site, owner; relation = ctx.act, shifted::Bool = false)
    T = eltype(act)
    owner == 0 && return zero(T)
    lat = ctx.lattice
    x = coordinates(lat, site)
    total = zero(T)
    n = 0
    zero_seen = false
    if @inbounds(σ[site]) == owner
        a = max(zero(T), @inbounds act[site])
        total += shifted ? log1p(a) : (a > 0 ? log(a) : zero(T))
        zero_seen |= a == 0
        n += 1
    end
    for k in 1:length(relation)
        inside, y = shift(lat, x, @inbounds relation.offsets[k])
        inside || continue
        j = linear_index(lat, y)
        @inbounds(σ[j]) == owner || continue
        a = max(zero(T), @inbounds act[j])
        total += shifted ? log1p(a) : (a > 0 ? log(a) : zero(T))
        zero_seen |= a == 0
        n += 1
    end
    n == 0 && return zero(T)
    shifted && return expm1(total / n)
    return zero_seen ? zero(T) : exp(total / n)
end

"""
    act_delta(act, σ, ctx, prop, λ, maximum; relation = ctx.act, shifted = false)

Act model drive `ΔH = −(λ/max)(GM(source, new) − GM(target, old))` for a copy by a cell
(zero when `new` is the medium); gate by kind in the model.
"""
@inline function act_delta(act, σ, ctx, prop, λ, maximum; relation = ctx.act,
        shifted::Bool = false)
    prop.new == 0 && return zero(eltype(act))
    s = act_mean(act, σ, ctx, prop.source, prop.new; relation, shifted)
    t = act_mean(act, σ, ctx, prop.target, prop.old; relation, shifted)
    return -(λ / maximum) * (s - t)
end

"""Extinction policy `ForbidExtinction`: veto a copy that would remove a cell's last site."""
@inline forbid_extinction(volume, prop) = prop.old == 0 || @inbounds(volume[prop.old]) > 1

# ---------------------------------------------------------------------------------------
# Local connectivity

"""
    locally_connected(σ, ctx, prop) -> Bool

`true` unless removing the target from its (non-medium) owner would split the owner's sites
in the target's Moore neighbourhood into more than one face-connected component. Works in
any dimension (3ᴺ − 1 ≤ 26 neighbours, bitmask flood fill); out-of-domain neighbours are
not part of the cell.
"""
@inline function locally_connected(σ, ctx, prop::Proposal{N}) where {N}
    a = prop.old
    a == 0 && return true
    lat = ctx.lattice
    M = 3^N
    mask = UInt32(0)
    for p in 0:(M - 1)
        off = _ternary_offset(p, Val(N))
        all(iszero, off) && continue
        inside, y = shift(lat, prop.x, off)
        (inside && @inbounds(σ[linear_index(lat, y)]) == a) && (mask |= UInt32(1) << p)
    end
    mask == 0 && return true                        # the target was the cell's last site here
    reached = mask & (~mask + UInt32(1))            # lowest set bit
    while true
        grown = reached
        for p in 0:(M - 1)
            (reached >> p) & 1 == 1 || continue
            grown |= _face_neighbors(p, Val(N)) & mask
        end
        grown == reached && break
        reached = grown
    end
    return reached == mask
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

const _MERKS_RING = ((-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0))

"""
    merks_connectivity(σ, ctx, prop) -> Bool

The Merks et al. (2006) local rule as implemented by legacy Potts (2D, Moore ring): allow
if the losing cell occupies one arc of the clockwise ring (≤ 2 transitions), or otherwise
if exactly two distinct cells occupy the ring. Out-of-domain ring sites count as medium
(legacy CorePotts returns owner 0 for an absent neighbour). Gate by kind in the model.
"""
@inline function merks_connectivity(σ, ctx, prop::Proposal{2})
    a = prop.old
    a <= 0 && return true
    lat = ctx.lattice
    owners = ntuple(Val(8)) do k
        o = _MERKS_RING[k]
        inside, y = shift(lat, prop.x, (Int32(o[1]), Int32(o[2])))
        inside ? @inbounds(σ[linear_index(lat, y)]) : Int32(0)
    end
    same = map(==(a), owners)
    transitions = 0
    for k in 1:8
        same[k] || continue
        transitions += 2 - Int(same[k == 1 ? 8 : k - 1]) - Int(same[k == 8 ? 1 : k + 1])
    end
    transitions <= 2 && return true
    distinct = 0
    for k in 1:8
        o = owners[k]
        o > 0 || continue
        seen = false
        for j in 1:(k - 1)
            owners[j] == o && (seen = true)
        end
        distinct += !seen
    end
    return distinct == 2
end
