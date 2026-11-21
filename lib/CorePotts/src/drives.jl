# Proposal drives, biases and constraints.
#
# Drives are energy-like and returned by `delta_H` (divided by T in acceptance); biases add
# directly to log α through `CPMFunction(…; bias)`; constraints veto through `constraint`.
# All primitives read the pre-commit state.

"""
    is_extension(prop) -> Bool

Return `true` if the copy is an extension: a cell copies into the medium (`prop.old` is
the medium, `prop.new` is a cell).

# Arguments
- `prop`: the copy attempt, a [`Proposal`](@ref).

# Returns
- `Bool`.

See also [`is_retraction`](@ref).
"""
@inline is_extension(prop) = prop.old == 0 && prop.new != 0
"""
    is_retraction(prop) -> Bool

Return `true` if the copy is a retraction: the medium copies into a cell (`prop.old` is a
cell, `prop.new` is the medium).

# Arguments
- `prop`: the copy attempt, a [`Proposal`](@ref).

# Returns
- `Bool`.

See also [`is_extension`](@ref).
"""
@inline is_retraction(prop) = prop.old != 0 && prop.new == 0

"""
    chemotaxis_delta(c, prop, χ; response = identity)

Compute the chemotaxis energy change `ΔH = −χ (r(c[target]) − r(c[source]))`.

The response `r` is applied to each concentration. Gate the term by kind and copy type in
the model.

# Arguments
- `c`: the concentration site array.
- `prop`: the copy attempt, a [`Proposal`](@ref).
- `χ`: the chemotactic strength.

# Keywords
- `response = identity`: the response `r`: `identity` (linear),
  [`saturating(s)`](@ref saturating), [`saturating_linear(s)`](@ref saturating_linear),
  or any function.

# Returns
- The energy change.

# Examples
```jldoctest
julia> using CorePotts

julia> prop = CorePotts.Proposal{1}(1, 2, (1,), 1, Int32(0), Int32(1));

julia> chemotaxis_delta([1.0, 3.0], prop, 2.0)
4.0
```

See also [`saturating`](@ref).
"""
@inline function chemotaxis_delta(c, prop, χ; response::F = identity) where {F}
    # bounds: the proposal's target and source are sites ≤ nsites = length(c)
    return -χ * (response(@inbounds(c[prop.target])) - response(@inbounds(c[prop.source])))
end

"""
    saturating(s) -> Function

Return the saturating response `c -> c / (s + c)`.

# Arguments
- `s`: the saturation constant.

# Returns
- A function of the concentration.

# Examples
```jldoctest
julia> using CorePotts

julia> saturating(2.0)(2.0)
0.5
```

See also [`chemotaxis_delta`](@ref), [`saturating_linear`](@ref).
"""
saturating(s) = c -> c / (s + c)
"""
    saturating_linear(s) -> Function

Return the response `c -> c / (s c + 1)`.

# Arguments
- `s`: the saturation constant.

# Returns
- A function of the concentration.

# Examples
```jldoctest
julia> using CorePotts

julia> saturating_linear(1.0)(1.0)
0.5
```

See also [`chemotaxis_delta`](@ref), [`saturating`](@ref).
"""
saturating_linear(s) = c -> c / (s * c + 1)

"""
    AbstractNeighborhoodMean

The supertype of the folds of [`neighborhood_mean`](@ref): [`ArithmeticMean`](@ref),
[`GeometricMean`](@ref) and [`Log1pGeometricMean`](@ref).
"""
abstract type AbstractNeighborhoodMean end
"""
    ArithmeticMean()

The arithmetic mean, a fold of [`neighborhood_mean`](@ref).
"""
struct ArithmeticMean <: AbstractNeighborhoodMean end
"""
    GeometricMean()

The geometric mean, a fold of [`neighborhood_mean`](@ref). It is zero if any value is
zero.
"""
struct GeometricMean <: AbstractNeighborhoodMean end
"""
    Log1pGeometricMean()

The fold `exp(mean(log1p(max(x, 0)))) − 1` of [`neighborhood_mean`](@ref).
"""
struct Log1pGeometricMean <: AbstractNeighborhoodMean end

@inline _fold_term(::ArithmeticMean, a) = a
@inline _fold_term(::GeometricMean, a) = a > 0 ? log(a) : zero(a)
@inline _fold_term(::Log1pGeometricMean, a) = log1p(max(zero(a), a))
@inline _fold_end(::ArithmeticMean, total, n, zero_seen) = total / n
@inline function _fold_end(::GeometricMean, total, n, zero_seen)
    return if zero_seen
        zero(total)
    else
        exp(total / n)
    end
end
@inline _fold_end(::Log1pGeometricMean, total, n, zero_seen) = expm1(total / n)

"""
    neighborhood_mean(x, σ, ctx, site, owner; relation, fold = GeometricMean())

Compute the mean of `x` over `site` (if `owner` owns it) and its `relation` neighbors
that `owner` owns.

The result is zero for the medium or an empty set. A neighborhood-memory drive (as in
the Act model) is `−(λ / max) (mean(source, new) − mean(target, old))`.

# Arguments
- `x`: the site values.
- `σ`: the `ownership` array.
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `site`: the linear site index.
- `owner`: the cell whose sites count.

# Keywords
- `relation`: the resolved relation of the neighbors. Required.
- `fold::AbstractNeighborhoodMean = GeometricMean()`: the mean.

# Returns
- The mean, of the element type of `x`.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((3,); boundary = Closed()); ctx = (; lattice = l);

julia> r = relation(VonNeumann(), l); σ = Int32[1, 1, 2];

julia> neighborhood_mean([1.0, 4.0, 9.0], σ, ctx, 2, 1; relation = r)
2.0
```
"""
@inline function neighborhood_mean(
        x, σ, ctx, site, owner; relation,
        fold::M = GeometricMean()
    ) where {M <: AbstractNeighborhoodMean}
    T = eltype(x)
    owner == 0 && return zero(T)
    lat = ctx.lattice
    p = coordinates(lat, site)
    total = zero(T)
    n = 0
    zero_seen = false
    # bounds: site and inside neighbors have linear indices ≤ nsites
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

# bounds: prop.old is a cell id ≤ capacity = length(volume)
"""
    forbid_extinction(volume, prop) -> Bool

Return `false` for a copy that would remove a cell's last site: the extinction policy
`ForbidExtinction`.

# Arguments
- `volume`: the volume tracker.
- `prop`: the copy attempt, a [`Proposal`](@ref).

# Returns
- `Bool`: `true` if the copy is allowed.
"""
@inline forbid_extinction(volume, prop) = prop.old == 0 || @inbounds(volume[prop.old]) > 1

# ---------------------------------------------------------------------------------------
# Local connectivity

"""
    local_components(σ, ctx, prop) -> Int

Count the pieces that the losing cell's sites around the target would form if the copy
were accepted.

The pieces are the face-connected components of the cell's sites on the target's
neighbor shell (see [`shell_offsets`](@ref)): runs of the 8-ring in 2D, a bit-dilation
flood fill over the 26 sites in 3D, or arcs of the 6-ring on a hexagonal lattice.
Out-of-domain sites are not part of the cell. The result is zero for the medium, when the
target is the cell's last site, or when it is an isolated fragment. Connectivity rules
are expressions over it: `local_components == 1` (hard, exactly one piece) or
`λ * (local_components > 1)` (soft).

# Arguments
- `σ`: the `ownership` array, or a `ShellRead`.
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.

# Returns
- `Int`: the number of pieces.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((3, 3); boundary = Closed()); ctx = (; lattice = l);

julia> σ = Int32[1 0 1; 0 1 0; 0 0 0];   # the target (2, 2) joins two corners

julia> prop = CorePotts.Proposal{2}(5, 2, (2, 2), 1, Int32(1), Int32(0));

julia> local_components(σ, ctx, prop), locally_connected(σ, ctx, prop)
(2, false)
```

See also [`locally_connected`](@ref), [`ring_arcs`](@ref).
"""
@inline function local_components(σ, ctx, prop::Proposal)
    return prop.old == 0 ? 0 : Int(_old_pieces(read_shell(σ, ctx, prop), ctx.lattice, prop))
end

"""
    locally_connected(σ, ctx, prop) -> Bool

Return `true` if the losing cell stays exactly one local piece:
`prop.old == 0 || local_components(σ, ctx, prop) == 1`.

Zero pieces (the cell's last site, an isolated fragment) is rejected like two.

# Arguments
- `σ`: the `ownership` array, or a `ShellRead`.
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.

# Returns
- `Bool`.

See also [`local_components`](@ref).
"""
@inline function locally_connected(σ, ctx, prop::Proposal)
    return prop.old == 0 ||
        local_components(σ, ctx, prop) == 1
end

"""
    ring_arcs(σ, ctx, prop) -> Int

Count the pieces of the losing cell's sites on the target's neighbor shell, two shell
sites joined when they are face neighbors.

The pieces are the maximal runs (arcs) of the 8-ring on a square lattice and of the
6-ring on a hexagonal one, and the face-connected pieces of the 26-site shell on a cubic
lattice. It equals [`local_components`](@ref) on every geometry. The result is zero for
the medium. Out-of-domain sites are not part of the cell; periodic axes wrap. The shell
is fixed, whatever the model's neighborhood.

# Arguments
- `σ`: the `ownership` array, or a `ShellRead`.
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.

# Returns
- `Int`: the number of pieces.

See also [`ring_cells`](@ref), [`ring_medium`](@ref).
"""
@inline ring_arcs(σ, ctx, prop::Proposal) = local_components(σ, ctx, prop)

"""
    ring_cells(σ, ctx, prop) -> Int

Count the distinct cells on the target's neighbor shell, the medium excluded.

# Arguments
- `σ`: the `ownership` array, or a `ShellRead`.
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.

# Returns
- `Int`: the number of distinct cells.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((3, 3); boundary = Closed()); ctx = (; lattice = l);

julia> σ = Int32[1 0 2; 0 1 0; 0 0 3];

julia> prop = CorePotts.Proposal{2}(5, 2, (2, 2), 1, Int32(1), Int32(0));

julia> ring_cells(σ, ctx, prop), ring_medium(σ, ctx, prop)
(3, 5)
```

See also [`ring_arcs`](@ref), [`ring_medium`](@ref).
"""
@inline function ring_cells(
        σ, ctx,
        prop::Proposal
    )
    return _distinct_cells(read_shell(σ, ctx, prop).owners)
end

"""
    ring_medium(σ, ctx, prop) -> Int

Count the medium sites on the target's neighbor shell.

Out-of-domain sites (off a closed face, or outside a domain mask) are not medium. On a
periodic axis the shell wraps.

# Arguments
- `σ`: the `ownership` array, or a `ShellRead`.
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.

# Returns
- `Int`: the number of medium sites.

See also [`ring_arcs`](@ref), [`ring_cells`](@ref).
"""
@inline ring_medium(σ, ctx, prop::Proposal) = _count_medium(read_shell(σ, ctx, prop).owners)

# The 6 hex neighbours in angular order (axial offsets at 0°, 60°, …, 300°).
const _HEX_RING = ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1))
# The 26 sites of the cubic Moore shell (ternary order, the origin left out).
const _CUBIC_SHELL = Tuple(
    (i, j, k) for k in -1:1 for j in -1:1
        for i in -1:1 if (i, j, k) != (0, 0, 0)
)

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
