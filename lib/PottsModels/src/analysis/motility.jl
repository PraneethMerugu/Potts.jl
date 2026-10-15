# Cell motility (P6.5c, review R16): unwrapped tracks, the mean squared displacement and the
# modified Fürth model of a persistent random walk with a fast diffusive part (Fortuna et al.
# 2020, Eq. 1–2 and the fit procedure of their S1). Plain Julia on vectors of points.

# A point: a tuple or a vector of reals.
_point_tuple(p::Tuple, ::Val{N}) where {N} = ntuple(d -> Float64(p[d]), Val(N))
_point_tuple(p::AbstractVector{<:Real}, ::Val{N}) where {N} = ntuple(d -> Float64(p[d]), Val(N))
_point_tuple(p, ::Val) = throw(ArgumentError("a point is a tuple or a vector of reals, got $(repr(p))"))

# The points of a track as `NTuple{N, Float64}`s, all of one dimension.
function _track_points(points, ::Val{N}, what) where {N}
    out = Vector{NTuple{N, Float64}}(undef, length(points))
    for (k, p) in enumerate(points)
        length(p) == N ||
            throw(ArgumentError("$what: the points have mixed dimensions ($N and $(length(p)))"))
        out[k] = _point_tuple(p, Val(N))
    end
    return out
end

"""
    unwrap_track(points, dims; periodic) -> Vector{NTuple{N, Float64}}

The track of `points` (tuples or vectors of N reals, one per sample, as
[`centroids`](@ref) returns per cell) with the jumps through periodic edges removed:
`out[1] = points[1]` and `out[k] = out[k − 1] + w(points[k] − points[k − 1])`, where `w` is
the identity on a non-periodic axis and, on a periodic axis `d`, the minimum image in
`[−dims[d]/2, dims[d]/2)` (a displacement of exactly half the period maps to `−dims[d]/2`).

`dims` holds one period per axis (the lattice size); `periodic` is one `Bool` per axis or one
`Bool` for every axis. The result is right when every true displacement between consecutive
samples is below half the period; this is not detected, so sample often enough. A `NaN`
coordinate (the centroid of a cell that owns no site) is not detected either: it propagates
to that sample and every later one on its axis.

Throws an `ArgumentError` for an empty track, points of mixed dimensions, `dims` or
`periodic` of another length than the points, and a non-positive period.
"""
function unwrap_track(points, dims; periodic)
    isempty(points) && throw(ArgumentError("unwrap_track: the track is empty"))
    N = length(first(points))
    return _unwrap_track(points, dims, periodic, Val(N))
end
function _unwrap_track(points, dims, periodic, ::Val{N}) where {N}
    length(dims) == N ||
        throw(ArgumentError("unwrap_track: `dims` has $(length(dims)) entries, the points are $(N)D"))
    per = periodic isa Bool ? ntuple(_ -> periodic, Val(N)) :
          (length(periodic) == N ? ntuple(d -> Bool(periodic[d]), Val(N)) :
           throw(ArgumentError("unwrap_track: `periodic` has $(length(periodic)) entries, the points are $(N)D")))
    L = ntuple(d -> Float64(dims[d]), Val(N))
    all(l -> l > 0, L) || throw(ArgumentError("unwrap_track: the periods must be positive, got $dims"))
    pts = _track_points(points, Val(N), "unwrap_track")
    out = similar(pts)
    out[1] = pts[1]
    for k in 2:length(pts)
        out[k] = ntuple(Val(N)) do d
            δ = pts[k][d] - pts[k - 1][d]
            out[k - 1][d] + (per[d] ? δ - L[d] * floor((δ + L[d] / 2) / L[d]) : δ)
        end
    end
    return out
end

# One track (a vector of points) or a vector of tracks.
_is_point(p) = p isa Tuple || (p isa AbstractVector && eltype(p) <: Real) ||
               (p isa AbstractVector && !isempty(p) && first(p) isa Real)

"""
    msd(tracks; lags = 1:(n − 1)) -> Vector{Float64}

The mean squared displacement at each lag ℓ of `lags` (in samples): for one track
`x₁ … xₙ` (a vector of points, tuples or vectors of reals),

    MSD(ℓ) = (1/(n − ℓ)) Σ_{i=1}^{n−ℓ} |x_{i+ℓ} − x_i|²

over overlapping windows, with the squares of all components summed. For a vector of
tracks of one length `n`, the mean of their MSDs with equal weights. Times are `ℓ·Δt`,
where `Δt` is the sampling interval: pass the unwrapped tracks of [`unwrap_track`](@ref),
projected onto the axes of interest (the xy plane for a cell crawling on a substrate). It
costs O(n·|lags|) per track, so the default lags cost O(n²): pass `lags` for a long track
(a 10⁵-sample track takes about 5 s with every lag; `lags = 1:1000` or a logarithmic set is
far cheaper). A track of one sample has no lag, so its MSD is `Float64[]`. `NaN` points are
not detected: they propagate to every lag whose windows contain them.

Throws an `ArgumentError` for a lag outside `1:(n − 1)`, tracks of unequal lengths, no
track, and points of mixed dimensions.
"""
function msd(tracks; lags = nothing)
    isempty(tracks) && throw(ArgumentError("msd: no track"))
    trs = _is_point(first(tracks)) ? [tracks] : collect(tracks)
    any(isempty, trs) && throw(ArgumentError("msd: a track is empty"))
    n = length(first(trs))
    all(t -> length(t) == n, trs) ||
        throw(ArgumentError("msd: the tracks have unequal lengths $(unique(length.(trs)))"))
    ls = lags === nothing ? (1:(n - 1)) : lags
    for l in ls
        1 <= l < n || throw(ArgumentError("msd: lag $l is outside 1:$(n - 1) (the tracks have $n samples)"))
    end
    N = length(first(first(trs)))
    return _msd(trs, collect(Int, ls), Val(N))
end
function _msd(trs, ls::Vector{Int}, ::Val{N}) where {N}
    out = zeros(length(ls))
    for t in trs
        x = _track_points(t, Val(N), "msd")
        n = length(x)
        for (j, l) in enumerate(ls)
            s = 0.0
            for i in 1:(n - l)
                s += sum(abs2, x[i + l] .- x[i])
            end
            out[j] += s / (n - l)
        end
    end
    return out ./ length(trs)
end

# g(Δt; P) = Δt − P(1 − e^{−Δt/P}) = P(x + expm1(−x)), x = Δt/P. For small x the sum
# cancels (it is ≈ x²/2), so below x = 1e-4 the series x²/2 − x³/6 + x⁴/24 is used (its
# truncation error is below x³/60 relative, < 2e-14).
function _furth_g(t, P)
    x = t / P
    return x < 1e-4 ? P * (x^2 / 2 - x^3 / 6 + x^4 / 24) : P * (x + expm1(-x))
end

function _furth_params(S, D, P, what)
    (0 <= S < 1) || throw(ArgumentError("$what: S must satisfy 0 ≤ S < 1, got $S"))
    D >= 0 || throw(ArgumentError("$what: D must be non-negative, got $D"))
    P > 0 || throw(ArgumentError("$what: P must be positive, got $P"))
    return nothing
end

"""
    furth_msd(Δt; S, D, P)

The modified Fürth MSD (Fortuna et al. 2020, Eq. 1) at the times `Δt`, elementwise:

    MSD(Δt) = 2D (Δt − P (1 − e^{−Δt/P})) + (2DS/(1 − S)) Δt

`D` is the diffusion constant of the persistent part, `P` its persistence time and `S`
(`0 ≤ S < 1`) the weight of the fast, uncorrelated part, whose diffusion constant is
`D_fast = DS/(1 − S)`. Throws an `ArgumentError` unless `0 ≤ S < 1`, `D ≥ 0` and `P > 0`.
"""
function furth_msd(Δt; S, D, P)
    _furth_params(S, D, P, "furth_msd")
    return [2D * _furth_g(t, P) + 2D * S / (1 - S) * t for t in Δt]
end

"""
    natural_units(Δt, m, fit) -> (τ, ρ²)

The times and MSDs `m` in the natural units of Eq. 2 of Fortuna et al. (2020): `τ = Δt/P`
and `ρ² = m/(2DP/(1 − S))`, so that the model reads `ρ² = τ − (1 − S)(1 − e^{−τ})`. `fit` is
any object with fields `S`, `D` and `P`, such as a [`furth_fit`](@ref) result.
"""
function natural_units(Δt, m, fit)
    length(Δt) == length(m) ||
        throw(ArgumentError("natural_units: Δt has $(length(Δt)) values, m $(length(m))"))
    S, D, P = fit.S, fit.D, fit.P
    scale = 2D * P / (1 - S)
    return [t / P for t in Δt], [x / scale for x in m]
end

"""
    furth_fit(Δt, m; method = :paper, range = nothing, short = nothing, offset = true)
        -> (; S, D, P, D_fast, D_slow, v_eff, offset, method)

Fit the modified Fürth model ([`furth_msd`](@ref)) to an MSD `m` at the times `Δt`
(positive, strictly increasing, at least 4 of them). The derived fields are
`D_fast = DS/(1 − S)`, `D_slow = D + D_fast = D/(1 − S)` and the effective speed
`v_eff = √(D/P)/(1 − S)`; `offset` is the fitted constant (the localisation error), 0 when
`offset = false`. Both methods are deterministic.

- `method = :paper` (the default) is the procedure of Fortuna et al.'s S1. `Δt` must be
  uniformly spaced (step `h`). The second differences `dᵢ = (m_{i+1} − 2mᵢ + m_{i−1})/h²` at
  the interior times (those in `range = (lo, hi)`, default all) that are positive are fitted
  by ordinary least squares to `log dᵢ = c₀ + c₁Δtᵢ`, the logarithm of Eq. 1's second
  derivative `(2D/P)e^{−Δt/P}`, which gives `P = −1/c₁` and `D = e^{c₀}P/2`. The residual
  `m − furth_msd(Δt; S = 0, D, P)` at the short times (`short = (lo, hi)`, default `Δt ≤ P`,
  or the first two times when fewer than two qualify) is then fitted by the line
  `2D_fast·Δt + offset`, and `S = D_fast/(D_fast + D)`. `D_fast` is not clamped, so noise
  can make it, and `S`, negative. With fewer than 3 positive second differences, or a
  non-decaying fit (`c₁ ≥ 0`), it throws: the data do not resolve a persistence (a purely
  diffusive or a ballistic MSD), and `method = :lsq` is the cross-check.
- `method = :lsq` minimizes the relative squared error `Σ((model − m)/m)²` of Eq. 1 (plus a
  free `offset`) over `D`, `D_fast ≥ 0` and `P`: for fixed `P` the model is linear in
  `a = 2D` and `b = 2D_fast`, solved exactly under `a, b ≥ 0`; `P` runs over a 200-point
  logarithmic grid on `[Δt₁/10, 100·Δt_end]`, refined by golden section to a relative
  `1e-10` (ties go to the smaller `P`). `D_slow` is `(a + b)/2` directly, which stays exact as
  `S → 1`; `S = b/(a + b)` (`NaN` when both vanish). It needs `m > 0`. On a purely diffusive
  MSD only `D_slow` is identifiable. A fitted `P` at either end of the grid (`Δt₁/10` or
  `100·Δt_end`) means the persistence is not resolved by the data (a purely diffusive or a
  ballistic MSD): read `D_slow` or `v_eff`, not `P`, `D` or `S`.

Throws an `ArgumentError` for fewer than 4 points, `Δt` and `m` of different lengths,
non-finite values, a `Δt` that is not positive and strictly increasing, an unknown
`method`, and the method-specific conditions above.
"""
function furth_fit(Δt, m; method::Symbol = :paper, range = nothing, short = nothing, offset::Bool = true)
    t = collect(Float64, Δt)
    y = collect(Float64, m)
    length(t) == length(y) || throw(ArgumentError("furth_fit: Δt has $(length(t)) values, m $(length(y))"))
    length(t) >= 4 || throw(ArgumentError("furth_fit: at least 4 points are needed, got $(length(t))"))
    (all(isfinite, t) && all(isfinite, y)) || throw(ArgumentError("furth_fit: Δt and m must be finite"))
    (t[1] > 0 && all(i -> t[i + 1] > t[i], 1:(length(t) - 1))) ||
        throw(ArgumentError("furth_fit: Δt must be positive and strictly increasing"))
    method === :paper && return _furth_paper(t, y, range, short, offset)
    method === :lsq && return _furth_lsq(t, y, offset)
    throw(ArgumentError("furth_fit: method must be :paper or :lsq, got $(repr(method))"))
end

function _furth_result(S, D, P, Df, Ds, c, method)
    return (; S, D, P, D_fast = Df, D_slow = Ds, v_eff = sqrt(D / P) / (1 - S), offset = c, method)
end

# Ordinary least squares of y on x (a line; through the origin when `intercept = false`):
# (slope, intercept).
function _ols_line(x, y, intercept::Bool)
    if !intercept
        return sum(x .* y) / sum(abs2, x), 0.0
    end
    mx, my = sum(x) / length(x), sum(y) / length(y)
    slope = sum((x .- mx) .* (y .- my)) / sum(abs2, x .- mx)
    return slope, my - slope * mx
end

# The indices of the times in the window `w = (lo, hi)`.
_time_window(w, t) = findall(x -> first(w) <= x <= last(w), t)

function _furth_paper(t, y, range, short, offset)
    n = length(t)
    h = t[2] - t[1]
    all(i -> abs((t[i + 1] - t[i]) - h) <= 1e-9 * h, 1:(n - 1)) ||
        throw(ArgumentError("furth_fit: method = :paper needs uniformly spaced Δt (use method = :lsq)"))
    inner = 2:(n - 1)
    range === nothing || (inner = filter(in(_time_window(range, t)), inner))
    keep = [i for i in inner if (y[i + 1] - 2y[i] + y[i - 1]) / h^2 > 0]
    nores() = throw(ArgumentError("furth_fit: no decaying second derivative (persistence not resolved); " *
                                  "try method = :lsq"))
    length(keep) >= 3 || nores()
    d = [(y[i + 1] - 2y[i] + y[i - 1]) / h^2 for i in keep]
    c1, c0 = _ols_line(t[keep], log.(d), true)
    c1 < 0 || nores()
    P = -1 / c1
    D = exp(c0) * P / 2
    idx = if short === nothing
        s = findall(<=(P), t)
        length(s) >= 2 ? s : [1, 2]
    else
        s = _time_window(short, t)
        length(s) >= 2 || throw(ArgumentError("furth_fit: `short` = $short holds fewer than 2 times"))
        s
    end
    r = [y[i] - 2D * _furth_g(t[i], P) for i in idx]
    slope, c = _ols_line(t[idx], r, offset)
    Df = slope / 2
    S = Df / (Df + D)
    return _furth_result(S, D, P, Df, D + Df, c, :paper)
end

# For fixed P: the relative-error least squares of m ≈ a·g + b·Δt (+ c) under a, b ≥ 0,
# by enumerating the active sets. Returns (cost, a, b, c).
function _furth_linear(t, y, P, offset)
    n = length(t)
    cols = (map(x -> _furth_g(x, P), t) ./ y, t ./ y, 1 ./ y)
    best = (Inf, 0.0, 0.0, 0.0)
    for free_a in (true, false), free_b in (true, false)
        use = [free_a, free_b, offset]
        k = findall(use)
        coef = zeros(3)
        if isempty(k)
            cost = Float64(n)
        else
            A = hcat((cols[j] for j in k)...)
            x = qr(A) \ ones(n)
            coef[k] = x
            (coef[1] >= 0 && coef[2] >= 0) || continue
            res = A * x .- 1
            cost = sum(abs2, res)
        end
        cost < best[1] && (best = (cost, coef[1], coef[2], coef[3]))
    end
    return best
end

function _furth_lsq(t, y, offset)
    all(>(0), y) || throw(ArgumentError("furth_fit: method = :lsq weights by 1/m, so m must be positive"))
    lo, hi = log(t[1] / 10), log(100 * t[end])
    K = 200
    grid = [lo + (hi - lo) * (k - 1) / (K - 1) for k in 1:K]
    f(x) = _furth_linear(t, y, exp(x), offset)[1]
    costs = map(f, grid)
    kb = argmin(costs)                           # the first minimum: ties to the smaller P
    a, b = grid[max(kb - 1, 1)], grid[min(kb + 1, K)]
    φ = (sqrt(5) - 1) / 2
    x1, x2 = b - φ * (b - a), a + φ * (b - a)
    f1, f2 = f(x1), f(x2)
    while b - a > 1e-10
        if f1 <= f2                              # ties: keep the smaller P
            b, x2, f2 = x2, x1, f1
            x1 = b - φ * (b - a)
            f1 = f(x1)
        else
            a, x1, f1 = x1, x2, f2
            x2 = a + φ * (b - a)
            f2 = f(x2)
        end
    end
    xm = (a + b) / 2
    x = f(xm) <= costs[kb] ? xm : grid[kb]
    P = exp(x)
    _, A, B, c = _furth_linear(t, y, P, offset)
    D, Df, Ds = A / 2, B / 2, (A + B) / 2
    S = A + B == 0 ? NaN : B / (A + B)
    return _furth_result(S, D, P, Df, Ds, c, :lsq)
end
