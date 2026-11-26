# Cell geometry: exact, periodic-safe moment trackers and CompuCell3D shape descriptors.
#
# Each cell keeps an integer anchor site and integer sums over its sites of the
# minimum-image offset δ = x − anchor (ties at half a periodic box resolve to +):
#   m1[d, c] = Σ δ_d,   m2[p, c] = Σ δ_d δ_e   (p enumerates d ≤ e)
# Integer sums never drift and stay small, so float precision is only spent on the final
# division. When a cell's mean offset leaves ±RECENTER the anchor moves to the nearest
# site of the mean and the sums are shifted exactly. The tracker is valid while every cell
# spans less than half of each periodic axis.

const RECENTER = 2

npairs(N) = N * (N + 1) ÷ 2
@inline _pair(N, d, e) = (d - 1) * N - (d - 1) * (d - 2) ÷ 2 + (e - d + 1)   # d ≤ e

"""
    min_image(lattice, x, a) -> NTuple{N, Int}

Return the minimum-image offset of site `x` from site `a`.

On a periodic axis of length `n` the offset is wrapped into `(-n/2, n/2]`, so a tie at
half the axis resolves to the positive side. On a closed axis it is `x - a`.

The wrap is a single shift by `n`, so on a periodic axis `x` and `a` must be sites of the
lattice (`1 ≤ x[d], a[d] ≤ n`). For other coordinates (`|x[d] - a[d]| ≥ n`) the result can
lie outside `(-n/2, n/2]`.

# Arguments
- `lattice::Lattice{N}`: the lattice.
- `x::NTuple{N, Int}`, `a::NTuple{N, Int}`: lattice coordinates, in `1:n` on a periodic
  axis.

# Returns
- `NTuple{N, Int}`: the offset.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((10,));

julia> min_image(l, (9,), (1,)), min_image(l, (6,), (1,))
((-2,), (5,))
```
"""
@inline function min_image(l::Lattice{N}, x::NTuple{N, Int}, a::NTuple{N, Int}) where {N}
    return ntuple(d -> _wrap(x[d] - a[d], l.dims[d], l.periodic[d]), Val(N))
end

# The offset δ of two coordinates of an axis of length n (so |δ| < n), wrapped into
# (-n/2, n/2] on a periodic axis. One wrap is enough, so there is no division. A closed
# axis returns δ at once: computing the wrap there and selecting doubled the CPU site walk
# on closed lattices. The flag is the same for every work item, so the branch does not
# diverge on a device.
@inline function _wrap(δ::Int, n::Int, periodic::Bool)
    periodic || return δ
    h = δ + cld(n, 2) - 1
    return ifelse(h < 0, δ + n, ifelse(h >= n, δ - n, δ))
end

# bounds: c ≤ capacity and d ≤ N, the rows of anchor
@inline function anchor(cell, c, ::Val{N}) where {N}
    return ntuple(
        d -> Int(@inbounds cell.anchor[d, c]),
        Val(N)
    )
end

"""
    init_moments(σ, lattice, ncell) -> (; anchor, m1, m2)

Compute the moment trackers of every cell from scratch.

Each cell keeps an integer anchor site and integer sums over its sites of the
minimum-image offset `δ = x − anchor`: `m1[d, c] = Σ δ_d` and `m2[p, c] = Σ δ_d δ_e`, with
`p` running over the pairs `d ≤ e`. Integer sums do not drift. Each anchor starts at the
rounded per-axis center of the cell's sites (the circular mean on a periodic axis). The
trackers stay valid while every cell spans less than half of each periodic axis.

# Arguments
- `σ`: the `ownership` array, on the host.
- `lattice::Lattice{N}`: the lattice.
- `ncell::Integer`: the number of cell slots.

# Returns
- A `NamedTuple` `(; anchor, m1, m2)`: `anchor::Matrix{Int32}` (`N × ncell`),
  `m1::Matrix{Int64}` (`N × ncell`) and `m2::Matrix{Int64}` (`N(N+1)/2 × ncell`). Merge it
  with the volumes into `st.cell`.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((10, 10); boundary = Closed()); σ = zeros(Int32, 10, 10);

julia> σ[3:6, 4:5] .= 1; cell = merge((; volume = Int32[8]), init_moments(σ, l, 1));

julia> centroid(cell, l, 1)
(4.5, 4.5)
```

See also [`commit_moments!`](@ref), [`centroid`](@ref), [`covariance`](@ref).
"""
function init_moments(σ, l::Lattice{N}, ncell::Integer) where {N}
    S = zeros(N, ncell)
    C = zeros(N, ncell)
    M = zeros(N, ncell)
    V = zeros(Int, ncell)
    for i in 1:nsites(l)
        c = σ[i]
        c == 0 && continue
        x = coordinates(l, i)
        V[c] += 1
        for d in 1:N
            θ = 2π * (x[d] - 1) / l.dims[d]
            S[d, c] += sin(θ)
            C[d, c] += cos(θ)
            M[d, c] += x[d]
        end
    end
    anchor = ones(Int32, N, ncell)
    for c in 1:ncell, d in 1:N
        V[c] == 0 && continue
        n = l.dims[d]
        center = l.periodic[d] ? atan(S[d, c], C[d, c]) * n / 2π + 1 : M[d, c] / V[c]
        anchor[d, c] = l.periodic[d] ? mod1(round(Int, center), n) : round(Int, center)
    end
    m1 = zeros(Int64, N, ncell)
    m2 = zeros(Int64, npairs(N), ncell)
    for i in 1:nsites(l)
        c = σ[i]
        c == 0 && continue
        a = ntuple(d -> Int(anchor[d, c]), N)
        _accumulate!(m1, m2, c, min_image(l, coordinates(l, i), a), 1)
    end
    cell = (; anchor, m1, m2)
    for c in 1:ncell
        _recenter!(cell, l, c, V[c])
    end
    return cell
end

@inline function _accumulate!(m1, m2, c, δ::NTuple{N, Int}, s::Int) where {N}
    for d in 1:N
        # bounds: c ≤ capacity; d, e ≤ N index the N rows of m1 and npairs(N) of m2
        @inbounds m1[d, c] += s * δ[d]
        for e in d:N
            @inbounds m2[_pair(N, d, e), c] += s * δ[d] * δ[e]
        end
    end
    return nothing
end

@inline function _recenter!(cell, l::Lattice{N}, c, V) where {N}
    V > 0 || return nothing
    # round(mean)
    shift = ntuple(d -> Int(fld(2 * @inbounds(cell.m1[d, c]) + V, 2V)), Val(N))
    any(s -> abs(s) >= RECENTER, shift) || return nothing
    for d in 1:N                           # Σ(δ−s)(δ−s)ᵀ = m2 − s m1ᵀ − m1 sᵀ + V s sᵀ
        for e in d:N
            p = _pair(N, d, e)
            @inbounds cell.m2[p, c] += -shift[d] * cell.m1[e, c] -
                shift[e] * cell.m1[d, c] +
                V * shift[d] * shift[e]
        end
    end
    for d in 1:N
        @inbounds cell.m1[d, c] -= V * shift[d]
        a = @inbounds(cell.anchor[d, c]) + shift[d]
        n = l.dims[d]
        @inbounds cell.anchor[d, c] = l.periodic[d] ? mod1(a, n) : a
    end
    return nothing
end

"""
    commit_moments!(cell, ctx, prop) -> nothing
    commit_moments!(cell, lattice, prop) -> nothing

Move the target site of an accepted copy from the losing to the gaining cell in the moment
trackers.

Call it after [`commit_volume!`](@ref), because re-centering reads the updated volumes. A
cell's anchor moves to the nearest site of its mean when the mean offset reaches 2 sites,
and the sums shift exactly. A cell that gains its first site is anchored there.

In a `commit!`, pass the context `ctx`. On the lockless checkerboard the sums then move by
atomic adds and the anchors re-center once per MCS, since another copy of the cell may be
in flight. The `lattice` form re-centers at every copy.

# Arguments
- `cell`: the cell columns, with `volume`, `anchor`, `m1` and `m2` (`st.cell`).
- `ctx::NamedTuple`: the copy-step context.
- `lattice::Lattice{N}`: the lattice.
- `prop::Proposal{N}`: the accepted copy.

# Returns
- `nothing`.

See also [`init_moments`](@ref).
"""
@inline function commit_moments!(cell, l::Lattice{N}, prop::Proposal{N}) where {N}
    if prop.old != 0
        _accumulate!(
            cell.m1, cell.m2, prop.old,
            min_image(l, prop.x, anchor(cell, prop.old, Val(N))), -1
        )
        _recenter!(cell, l, prop.old, @inbounds cell.volume[prop.old])
    end
    if prop.new != 0
        if @inbounds(cell.volume[prop.new]) == 1   # first site: anchor there
            for d in 1:N
                @inbounds cell.anchor[d, prop.new] = prop.x[d]
            end
        end
        _accumulate!(
            cell.m1, cell.m2, prop.new,
            min_image(l, prop.x, anchor(cell, prop.new, Val(N))), 1
        )
        _recenter!(cell, l, prop.new, @inbounds cell.volume[prop.new])
    end
    return nothing
end

# `commit_moments!` from a copy function: on the lockless checkerboard (`ctx.lockless`) the
# sums move by atomic adds and the anchors re-center once per MCS (`recenter_kernel!`),
# since a re-centering rewrites a cell's sums and another copy of the cell may be in flight
@inline function commit_moments!(cell, ctx::NamedTuple, prop::Proposal)
    if _lockless(ctx)
        return _commit_moments_atomic!(cell, ctx.lattice, prop)
    else
        return commit_moments!(cell, ctx.lattice, prop)
    end
end

@inline function _commit_moments_atomic!(cell, l::Lattice{N}, prop::Proposal{N}) where {N}
    if prop.old != 0
        _accumulate_atomic!(
            cell.m1, cell.m2, prop.old,
            min_image(l, prop.x, anchor(cell, prop.old, Val(N))), -1
        )
    end
    if prop.new != 0
        if @inbounds(cell.volume[prop.new]) == 1   # first site: anchor there
            for d in 1:N
                @inbounds cell.anchor[d, prop.new] = prop.x[d]
            end
        end
        _accumulate_atomic!(
            cell.m1, cell.m2, prop.new,
            min_image(l, prop.x, anchor(cell, prop.new, Val(N))), 1
        )
    end
    return nothing
end

@inline function _accumulate_atomic!(m1, m2, c, δ::NTuple{N, Int}, s::Int) where {N}
    for d in 1:N
        Atomix.@atomic m1[d, c] += convert(eltype(m1), s * δ[d])
        for e in d:N
            Atomix.@atomic m2[_pair(N, d, e), c] += convert(eltype(m2), s * δ[d] * δ[e])
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# Queries (host or device). `T` is the float type of the result.

# bounds: c is a cell id ≤ capacity (callers pass ids from σ or a proposal)
"""
    centroid(T, cell, lattice, c) -> NTuple{N, T}
    centroid(cell, lattice, c) -> NTuple{N, Float64}

Return the centroid of cell `c` in lattice coordinates.

On a periodic axis of length `n` the centroid is wrapped into `[1, n + 1)`. The cell must
not be empty.

# Arguments
- `T`: the float type of the result (`Float64` when left out).
- `cell`: the cell columns, with `volume`, `anchor` and `m1`.
- `lattice::Lattice`: the lattice.
- `c`: the cell number, in `1:capacity`.

# Returns
- `NTuple{N, T}`: the centroid.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((10, 10)); σ = zeros(Int32, 10, 10); σ[[1, 10], 1] .= 1;

julia> cell = merge((; volume = Int32[2]), init_moments(σ, l, 1));

julia> centroid(Float32, cell, l, 1)
(10.5f0, 1.0f0)
```

See also [`centroid_position`](@ref), [`init_moments`](@ref).
"""
@inline function centroid(::Type{T}, cell, l::Lattice, c) where {T}
    return _centroid(
        T, cell, l, c, @inbounds cell.volume[c]
    )
end
# … from an already-loaded volume `V` (one load for a caller that also tests `V`, e.g.
# `link_delta`'s dead-partner skip: no second, possibly racing, read of the volume)
@inline function _centroid(::Type{T}, cell, l::Lattice{N}, c, V) where {T, N}
    return ntuple(Val(N)) do d
        # bounds: c ≤ capacity; d ≤ N, the rows of anchor and m1
        x = T(@inbounds cell.anchor[d, c]) + T(@inbounds cell.m1[d, c]) / T(V)
        l.periodic[d] ? mod(x - one(T), T(l.dims[d])) + one(T) : x
    end
end
centroid(cell, l::Lattice, c) = centroid(Float64, cell, l, c)

"""
    centroid_position(T, cell, lattice, c) -> NTuple{N, T}

Return the centroid of cell `c` as a Cartesian position: [`embed`](@ref) of
[`centroid`](@ref).

On a square lattice it equals the centroid.

# Arguments
- `T`: the float type of the result.
- `cell`: the cell columns, with `volume`, `anchor` and `m1`.
- `lattice::Lattice`: the lattice.
- `c`: the cell number.

# Returns
- `NTuple{N, T}`: the position.

See also [`centroid`](@ref), [`embed`](@ref).
"""
@inline function centroid_position(::Type{T}, cell, l::Lattice, c) where {T}
    return embed(
        l,
        centroid(T, cell, l, c)
    )
end

"""
    centroid_shift(T, cell, lattice, c, x, s) -> NTuple{N, T}

Return the displacement of the centroid of cell `c` if site `x` is added (`s = +1`) or
removed (`s = -1`), without changing the trackers.

Drives use it as the centroid change of a copy. A copy that would leave the cell empty
returns zeros. For a cell with no sites that gains `x`, it returns the minimum-image offset
of `x` from the cell's stored anchor.

# Arguments
- `T`: the float type of the result.
- `cell`: the cell columns, with `volume`, `anchor` and `m1`.
- `lattice::Lattice{N}`: the lattice.
- `c`: the cell number.
- `x::NTuple{N, Int}`: the site's coordinates.
- `s::Int`: `+1` to add the site, `-1` to remove it.

# Returns
- `NTuple{N, T}`: the displacement, in lattice coordinates.

See also [`centroid`](@ref), [`chemotaxis_delta`](@ref).
"""
@inline function centroid_shift(
        ::Type{T}, cell, l::Lattice{N}, c, x::NTuple{N, Int},
        s::Int
    ) where {T, N}
    # bounds: c is a cell id ≤ capacity; k ≤ N rows (and pairs) of the moments
    V = Int(@inbounds cell.volume[c])
    V + s <= 0 && return ntuple(_ -> zero(T), Val(N))
    δ = min_image(l, x, anchor(cell, c, Val(N)))
    return ntuple(Val(N)) do d
        m = @inbounds cell.m1[d, c]
        V == 0 ? T(δ[d]) : T(m + s * δ[d]) / T(V + s) - T(m) / T(V)
    end
end

"""
    covariance(T, cell, c, Val(N)) -> NTuple{N(N+1)/2, T}

Return the covariance of the site coordinates of cell `c`, as its upper triangle.

The entries are in row order over the pairs `d ≤ e`: `(xx, xy, yy)` in 2D, and
`(xx, xy, xz, yy, yz, zz)` in 3D. The coordinates are lattice coordinates; use
[`embed_covariance`](@ref) for Cartesian ones on a hexagonal lattice.

# Arguments
- `T`: the float type of the result.
- `cell`: the cell columns, with `volume`, `m1` and `m2`.
- `c`: the cell number; the cell must not be empty.
- `Val(N)`: the lattice dimension.

# Returns
- The upper triangle, a tuple of `T`.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((10, 10); boundary = Closed()); σ = zeros(Int32, 10, 10);

julia> σ[3:6, 4:5] .= 1; cell = merge((; volume = Int32[8]), init_moments(σ, l, 1));

julia> covariance(Float64, cell, 1, Val(2))
(1.25, 0.0, 0.25)
```

See also [`principal_moments`](@ref), [`cell_shape`](@ref).
"""
@inline function covariance(::Type{T}, cell, c, ::Val{N}) where {T, N}
    # bounds: c is a cell id ≤ capacity; p ≤ npairs(N) rows of m2
    V = T(@inbounds cell.volume[c])
    return ntuple(Val(npairs(N))) do p
        d, e = _unpair(N, p)
        T(@inbounds cell.m2[p, c]) / V -
            T(@inbounds cell.m1[d, c]) * T(@inbounds cell.m1[e, c]) / V^2
    end
end
@inline function _unpair(N, p)
    d = 1
    while p > N - d + 1
        p -= N - d + 1
        d += 1
    end
    return d, d + p - 1
end

"""
    principal_moments(C) -> NTuple

Return the eigenvalues of a symmetric 2 × 2 or 3 × 3 matrix, in descending order.

# Arguments
- `C`: the upper triangle, `(a, b, d)` for `[a b; b d]` or `(a, b, c, d, e, f)` for
  `[a b c; b d e; c e f]`, as [`covariance`](@ref) returns it.

# Returns
- The eigenvalues, a 2-tuple or a 3-tuple.

# Examples
```jldoctest
julia> using CorePotts

julia> principal_moments((2.0, 0.0, 1.0))
(2.0, 1.0)
```

See also [`covariance`](@ref), [`cell_shape`](@ref).
"""
@inline function principal_moments(C::NTuple{3, T}) where {T}
    a, b, d = C                                   # [a b; b d]
    m = (a + d) / 2
    r = sqrt(((a - d) / 2)^2 + b^2)
    return (m + r, m - r)
end
@inline function principal_moments(C::NTuple{6, T}) where {T}
    a, b, c, d, e, f = C                          # [a b c; b d e; c e f]
    p1 = b^2 + c^2 + e^2
    q = (a + d + f) / 3
    p1 <= eps(T) * max(abs(a), abs(d), abs(f), one(T))^2 &&
        return _sort3(a, d, f)
    p2 = (a - q)^2 + (d - q)^2 + (f - q)^2 + 2p1
    p = sqrt(p2 / 6)
    B = ((a - q) / p, b / p, c / p, (d - q) / p, e / p, (f - q) / p)
    detB = B[1] * (B[4] * B[6] - B[5]^2) - B[2] * (B[2] * B[6] - B[5] * B[3]) +
        B[3] * (B[2] * B[5] - B[4] * B[3])
    φ = acos(clamp(detB / 2, -one(T), one(T))) / 3
    λ1 = q + 2p * cos(φ)
    λ3 = q + 2p * cos(φ + 2T(π) / 3)
    return (λ1, 3q - λ1 - λ3, λ3)
end
@inline function _sort3(a, b, c)
    a < b && ((a, b) = (b, a))
    b < c && ((b, c) = (c, b))
    a < b && ((a, b) = (b, a))
    return (a, b, c)
end

"""
    cell_shape(T, cell, lattice, c) -> NamedTuple
    cell_shape(cell, lattice, c) -> NamedTuple

Return CompuCell3D's shape descriptors of cell `c`, from the eigenvalues `λ₁ ≥ λ₂ (≥ λ₃)`
of its covariance.

- 2D: `major_length = 4√λ₁` and `minor_length = 4√λ₂`, the full axes of the uniform
  ellipse with that covariance. `eccentricity = √(1 − λ₂/λ₁)`, and `orientation` is the
  angle of the major axis to the x axis, in radians. The covariance is in Cartesian
  coordinates ([`embed_covariance`](@ref)).
- 3D: `semiaxes = √(5λᵢ)` (the uniform ellipsoid), `major_length = 2√(5λ₁)`,
  `minor_length = 2√(5λ₃)` and `eccentricity = √(1 − λ₃/λ₁)`.
- Both: `elongation = major_length / minor_length`.

Negative eigenvalues from rounding are clamped to 0. `eccentricity` is 0 when `λ₁ = 0`.

# Arguments
- `T`: the float type of the result (`Float64` when left out).
- `cell`: the cell columns, with `volume`, `m1` and `m2`.
- `lattice::Lattice`: a 2D or 3D lattice.
- `c`: the cell number; the cell must not be empty.

# Returns
- 2D: `(; major_length, minor_length, elongation, eccentricity, orientation)`.
- 3D: `(; major_length, minor_length, semiaxes, elongation, eccentricity)`.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((10, 10); boundary = Closed()); σ = zeros(Int32, 10, 10);

julia> σ[3:6, 4:5] .= 1; cell = merge((; volume = Int32[8]), init_moments(σ, l, 1));

julia> s = cell_shape(cell, l, 1); s.minor_length, s.orientation
(2.0, 0.0)
```

See also [`major_length`](@ref), [`covariance`](@ref).
"""
@inline function cell_shape(::Type{T}, cell, l::Lattice{2}, c) where {T}
    C = embed_covariance(l, covariance(T, cell, c, Val(2)))
    λ1, λ2 = principal_moments(C)
    λ2 = max(λ2, zero(T))
    major, minor = 4sqrt(λ1), 4sqrt(λ2)
    orientation = atan(2C[2], C[1] - C[3]) / 2
    return (;
        major_length = major, minor_length = minor, elongation = major / minor,
        eccentricity = λ1 > 0 ? sqrt(1 - λ2 / λ1) : zero(T), orientation,
    )
end
@inline function cell_shape(::Type{T}, cell, l::Lattice{3}, c) where {T}
    λ = map(v -> max(v, zero(T)), principal_moments(covariance(T, cell, c, Val(3))))
    semiaxes = map(v -> sqrt(5v), λ)
    major, minor = 2semiaxes[1], 2semiaxes[3]
    return (;
        major_length = major, minor_length = minor, semiaxes,
        elongation = major / minor, eccentricity = if λ[1] > 0
            sqrt(1 - λ[3] / λ[1])
        else
            zero(T)
        end,
    )
end
cell_shape(cell, l::Lattice, c) = cell_shape(Float64, cell, l, c)

# Major length from the covariance upper triangle (square-lattice axes), as in `shape`
@inline function _major_length(l::Lattice{2}, C::NTuple{3, T}) where {T}
    return 4sqrt(max(first(principal_moments(embed_covariance(l, C))), zero(T)))
end
@inline function _major_length(::Lattice{3}, C::NTuple{6, T}) where {T}
    return 2sqrt(5max(first(principal_moments(C)), zero(T)))
end

"""
    major_length(T, cell, lattice, c) -> T

Return the major length of cell `c`: `cell_shape(T, cell, lattice, c).major_length`
alone.

It is `4√λ₁` of the covariance in 2D and `2√(5λ₁)` in 3D, with `λ₁` its largest
eigenvalue. An empty cell returns zero.

# Arguments
- `T`: the float type of the result.
- `cell`: the cell columns, with `volume`, `m1` and `m2`.
- `lattice::Lattice`: a 2D or 3D lattice.
- `c`: the cell number.

# Returns
- `T`: the major length, in lattice units.

See also [`major_length_after`](@ref), [`cell_shape`](@ref).
"""
@inline function major_length(::Type{T}, cell, l::Lattice{N}, c) where {T, N}
    # bounds: c is a cell id ≤ capacity
    @inbounds(cell.volume[c]) > 0 || return zero(T)
    return _major_length(l, covariance(T, cell, c, Val(N)))
end

"""
    major_length_after(T, cell, lattice, c, x, s) -> T

Return the [`major_length`](@ref) of cell `c` if site `x` is added (`s = +1`) or removed
(`s = -1`), without changing the trackers.

A length constraint computes its energy change from it. A copy that would leave the cell
empty returns zero.

# Arguments
- `T`: the float type of the result.
- `cell`: the cell columns, with `volume`, `anchor`, `m1` and `m2`.
- `lattice::Lattice{N}`: a 2D or 3D lattice.
- `c`: the cell number.
- `x::NTuple{N, Int}`: the site's coordinates.
- `s::Int`: `+1` to add the site, `-1` to remove it.

# Returns
- `T`: the major length after the change.

See also [`major_length`](@ref).
"""
@inline function major_length_after(
        ::Type{T}, cell, l::Lattice{N}, c, x::NTuple{N, Int},
        s::Int
    ) where {T, N}
    # bounds: c is a cell id ≤ capacity; the moment rows as in centroid_shift
    V = Int(@inbounds cell.volume[c]) + s
    V > 0 || return zero(T)
    δ = V == 1 && s > 0 ? ntuple(_ -> 0, Val(N)) : min_image(l, x, anchor(cell, c, Val(N)))
    m1 = ntuple(d -> T(@inbounds(cell.m1[d, c]) + s * δ[d]), Val(N))
    C = ntuple(Val(npairs(N))) do p
        d, e = _unpair(N, p)
        (T(@inbounds(cell.m2[p, c]) + s * δ[d] * δ[e])) / T(V) - m1[d] * m1[e] / T(V)^2
    end
    return _major_length(l, C)
end
