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

"""Minimum-image offset of `x` from `a` (ties at half a periodic box resolve to +)."""
@inline function min_image(l::Lattice{N}, x::NTuple{N, Int}, a::NTuple{N, Int}) where {N}
    return ntuple(Val(N)) do d
        δ = x[d] - a[d]
        n = l.dims[d]
        l.periodic[d] ? δ - n * fld(δ + cld(n, 2) - 1, n) : δ
    end
end

@inline anchor(cell, c, ::Val{N}) where {N} = ntuple(d -> Int(@inbounds cell.anchor[d, c]), Val(N))

"""
    init_moments(σ, lattice, ncell) -> (; anchor, m1, m2)

Moment trackers from scratch. Each cell is anchored at the rounded per-axis centre of its
sites (the circular mean on periodic axes), so the minimum-image offsets are valid while
the cell spans less than the whole axis about its centre.
"""
function init_moments(σ, l::Lattice{N}, ncell::Integer) where {N}
    S = zeros(N, ncell); C = zeros(N, ncell); M = zeros(N, ncell); V = zeros(Int, ncell)
    for i in 1:nsites(l)
        c = σ[i]
        c == 0 && continue
        x = coordinates(l, i)
        V[c] += 1
        for d in 1:N
            θ = 2π * (x[d] - 1) / l.dims[d]
            S[d, c] += sin(θ); C[d, c] += cos(θ); M[d, c] += x[d]
        end
    end
    anchor = ones(Int32, N, ncell)
    for c in 1:ncell, d in 1:N
        V[c] == 0 && continue
        n = l.dims[d]
        centre = l.periodic[d] ? atan(S[d, c], C[d, c]) * n / 2π + 1 : M[d, c] / V[c]
        anchor[d, c] = l.periodic[d] ? mod1(round(Int, centre), n) : round(Int, centre)
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
        @inbounds m1[d, c] += s * δ[d]
        for e in d:N
            @inbounds m2[_pair(N, d, e), c] += s * δ[d] * δ[e]
        end
    end
    return nothing
end

@inline function _recenter!(cell, l::Lattice{N}, c, V) where {N}
    V > 0 || return nothing
    shift = ntuple(d -> Int(fld(2 * @inbounds(cell.m1[d, c]) + V, 2V)), Val(N))  # round(mean)
    any(s -> abs(s) >= RECENTER, shift) || return nothing
    for d in 1:N                           # Σ(δ−s)(δ−s)ᵀ = m2 − s m1ᵀ − m1 sᵀ + V s sᵀ
        for e in d:N
            p = _pair(N, d, e)
            @inbounds cell.m2[p, c] += -shift[d] * cell.m1[e, c] - shift[e] * cell.m1[d, c] +
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
    commit_moments!(cell, lattice, prop)

Move the target site from `prop.old` to `prop.new` in the moment trackers. Call after
`commit_volume!` (re-centring uses the updated volumes).
"""
@inline function commit_moments!(cell, l::Lattice{N}, prop::Proposal{N}) where {N}
    if prop.old != 0
        _accumulate!(cell.m1, cell.m2, prop.old, min_image(l, prop.x, anchor(cell, prop.old, Val(N))), -1)
        _recenter!(cell, l, prop.old, @inbounds cell.volume[prop.old])
    end
    if prop.new != 0
        if @inbounds(cell.volume[prop.new]) == 1   # first site: anchor there
            for d in 1:N
                @inbounds cell.anchor[d, prop.new] = prop.x[d]
            end
        end
        _accumulate!(cell.m1, cell.m2, prop.new, min_image(l, prop.x, anchor(cell, prop.new, Val(N))), 1)
        _recenter!(cell, l, prop.new, @inbounds cell.volume[prop.new])
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# Queries (host or device). `T` is the float type of the result.

"""Centroid of cell `c` in lattice coordinates, wrapped into `[1, n + 1)` on periodic axes."""
@inline centroid(::Type{T}, cell, l::Lattice, c) where {T} = _centroid(T, cell, l, c, @inbounds cell.volume[c])
# … from an already-loaded volume `V` (one load for a caller that also tests `V`, e.g.
# `link_delta`'s dead-partner skip: no second, possibly racing, read of the volume)
@inline function _centroid(::Type{T}, cell, l::Lattice{N}, c, V) where {T, N}
    return ntuple(Val(N)) do d
        x = T(@inbounds cell.anchor[d, c]) + T(@inbounds cell.m1[d, c]) / T(V)
        l.periodic[d] ? mod(x - one(T), T(l.dims[d])) + one(T) : x
    end
end
centroid(cell, l::Lattice, c) = centroid(Float64, cell, l, c)

"""Centroid of cell `c` as a Cartesian position (`embed` of `centroid`; equal on square lattices)."""
@inline centroid_position(::Type{T}, cell, l::Lattice, c) where {T} = embed(l, centroid(T, cell, l, c))

"""
    centroid_shift(T, cell, lattice, c, x, s) -> NTuple{N, T}

Centroid displacement of cell `c` if site `x` is added (`s = +1`) or removed (`s = -1`):
`δcentroid` for drives.
"""
@inline function centroid_shift(::Type{T}, cell, l::Lattice{N}, c, x::NTuple{N, Int},
        s::Int) where {T, N}
    V = Int(@inbounds cell.volume[c])
    V + s <= 0 && return ntuple(_ -> zero(T), Val(N))
    δ = min_image(l, x, anchor(cell, c, Val(N)))
    return ntuple(Val(N)) do d
        m = @inbounds cell.m1[d, c]
        V == 0 ? T(δ[d]) : T(m + s * δ[d]) / T(V + s) - T(m) / T(V)
    end
end

"""Covariance of cell `c`'s site coordinates, as the `npairs(N)` upper-triangle entries."""
@inline function covariance(::Type{T}, cell, c, ::Val{N}) where {T, N}
    V = T(@inbounds cell.volume[c])
    return ntuple(Val(npairs(N))) do p
        d, e = _unpair(N, p)
        T(@inbounds cell.m2[p, c]) / V - T(@inbounds cell.m1[d, c]) * T(@inbounds cell.m1[e, c]) / V^2
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

"""Eigenvalues of a symmetric 2×2 or 3×3 matrix given by its upper triangle, descending."""
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
    shape(T, cell, lattice, c)

CompuCell3D shape descriptors of cell `c` from the covariance eigenvalues `λ₁ ≥ λ₂ (≥ λ₃)`:

- 2D: `major_length = 4√λ₁`, `minor_length = 4√λ₂` (full axes of the equivalent uniform
  ellipse), `eccentricity = √(1 − λ₂/λ₁)`, `orientation` = angle of the major axis to x.
- 3D: `semiaxes = √(5λᵢ)` (uniform ellipsoid), `major_length = 2√(5λ₁)`,
  `minor_length = 2√(5λ₃)`, `eccentricity = √(1 − λ₃/λ₁)`.
- `elongation = major_length / minor_length`.
"""
@inline function shape(::Type{T}, cell, l::Lattice{2}, c) where {T}
    C = embed_covariance(l, covariance(T, cell, c, Val(2)))
    λ1, λ2 = principal_moments(C)
    λ2 = max(λ2, zero(T))
    major, minor = 4sqrt(λ1), 4sqrt(λ2)
    orientation = atan(2C[2], C[1] - C[3]) / 2
    return (; major_length = major, minor_length = minor, elongation = major / minor,
        eccentricity = λ1 > 0 ? sqrt(1 - λ2 / λ1) : zero(T), orientation)
end
@inline function shape(::Type{T}, cell, l::Lattice{3}, c) where {T}
    λ = map(v -> max(v, zero(T)), principal_moments(covariance(T, cell, c, Val(3))))
    semiaxes = map(v -> sqrt(5v), λ)
    major, minor = 2semiaxes[1], 2semiaxes[3]
    return (; major_length = major, minor_length = minor, semiaxes,
        elongation = major / minor, eccentricity = λ[1] > 0 ? sqrt(1 - λ[3] / λ[1]) : zero(T))
end
shape(cell, l::Lattice, c) = shape(Float64, cell, l, c)

# Major length from the covariance upper triangle (square-lattice axes), as in `shape`
@inline _major_length(l::Lattice{2}, C::NTuple{3, T}) where {T} =
    4sqrt(max(first(principal_moments(embed_covariance(l, C))), zero(T)))
@inline _major_length(::Lattice{3}, C::NTuple{6, T}) where {T} =
    2sqrt(5max(first(principal_moments(C)), zero(T)))

"""
    major_length(T, cell, lattice, c)

`shape(T, cell, lattice, c).major_length` alone: `4√λ₁` of the covariance in 2D (Merks et
al. 2006, Eq. 5: `4√(λ_max(I)/a)`), `2√(5λ₁)` in 3D. Zero for an empty cell.
"""
@inline function major_length(::Type{T}, cell, l::Lattice{N}, c) where {T, N}
    @inbounds(cell.volume[c]) > 0 || return zero(T)
    return _major_length(l, covariance(T, cell, c, Val(N)))
end

"""
    major_length_after(T, cell, lattice, c, x, s)

[`major_length`](@ref) of cell `c` if site `x` is added (`s = +1`) or removed (`s = -1`),
from the moment sums without committing: the ΔH of a length constraint.
"""
@inline function major_length_after(::Type{T}, cell, l::Lattice{N}, c, x::NTuple{N, Int},
        s::Int) where {T, N}
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

