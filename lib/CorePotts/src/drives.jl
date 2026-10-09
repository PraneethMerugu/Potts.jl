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
neighbourhood (3ᴺ − 1 ≤ 26 sites: runs of the 8-ring in 2D, a bit-dilation flood fill in
3D), or arcs of the 6-ring on a hexagonal lattice. Out-of-domain sites are not part of the
cell. Zero for the medium, when the target is the cell's last site, or when it is an
isolated fragment. Connectivity rules are expressions over it: `local_components == 1`
(hard, exactly one piece as in CompuCell3D), `λ * (local_components > 1)` (soft).
"""
@inline local_components(σ, ctx, prop::Proposal) =
    prop.old == 0 ? 0 : Int(_old_pieces(read_shell(σ, ctx, prop), ctx.lattice, prop))

"""
`locally_connected(σ, ctx, prop)`: the losing cell stays exactly one local piece,
`prop.old == 0 || local_components(σ, ctx, prop) == 1`. Zero pieces (the cell's last
site, an isolated fragment) is rejected like two.
"""
@inline locally_connected(σ, ctx, prop::Proposal) = prop.old == 0 || local_components(σ, ctx, prop) == 1

"""
    ring_arcs(σ, ctx, prop) -> Int

Pieces of the losing cell's (`prop.old`) sites on the target's neighbour shell, two shell
sites joined when they are lattice face neighbours: the maximal runs (arcs) of the 8-ring
on a square 2D lattice and of the 6-ring on a hexagonal one; the face-connected pieces of
the 26-site Moore shell on a cubic 3D lattice. It equals [`local_components`](@ref) on every
geometry. Zero for the medium. Out-of-domain sites are not the cell; periodic axes wrap.
The shell is fixed, whatever the model's neighbourhood.
"""
@inline ring_arcs(σ, ctx, prop::Proposal) = local_components(σ, ctx, prop)

"""
    ring_cells(σ, ctx, prop) -> Int

Number of distinct cells (medium excluded) on the target's neighbour shell (see
[`ring_arcs`](@ref)).
"""
@inline ring_cells(σ, ctx, prop::Proposal) = _distinct_cells(read_shell(σ, ctx, prop).owners)

"""
    ring_medium(σ, ctx, prop) -> Int

Number of medium sites on the target's neighbour shell (see [`ring_arcs`](@ref)).
Out-of-domain sites (a closed face, outside a domain mask) are not medium; on a periodic
axis the shell wraps.
"""
@inline ring_medium(σ, ctx, prop::Proposal) = _count_medium(read_shell(σ, ctx, prop).owners)

# The 6 hex neighbours in angular order (axial offsets at 0°, 60°, …, 300°).
const _HEX_RING = ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1))
# The 26 sites of the cubic Moore shell (ternary order, the origin left out).
const _CUBIC_SHELL = Tuple((i, j, k) for k in -1:1 for j in -1:1 for i in -1:1 if (i, j, k) != (0, 0, 0))

# face pieces of the losing cell's shell positions (σ may be a `ShellRead`; `shell.jl`)
@inline function _old_pieces(s, lat, prop)
    r = _ring_bits(lat)
    return _pieces(_mask1(s.owners, prop.old, r), false, r, _shell_tables(lat))
end

@inline function _count_medium(owners::NTuple{K}) where {K}
    n = 0
    for k in 1:K
        n += owners[k] == 0
    end
    return n
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
