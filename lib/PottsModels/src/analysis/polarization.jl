# Polarization and mean velocity of a migrating cell (Thomas et al. 2022, Physica A 587:
# 126511): the log-log slope of the modified Fürth MSD and the interval that maximizes it
# (Eq. 12), the mean velocity over a finite interval (Eq. 13), the velocity-polarization
# correlation index (Eq. 14), the relative speed error (Eq. 15) and the speed parallel to
# the polarization (Eq. 16). Plain Julia on vectors of 2D points.

"""
    furth_exponent(Δτ, S) -> Float64

Return the log-log slope `α = d log⟨|Δρ|²⟩ / d log Δτ` of the modified Fürth MSD in
natural units (Thomas et al. 2022, Eq. 12):

    α(Δτ) = Δτ (1 − (1 − S) e^{−Δτ}) / (Δτ − (1 − S)(1 − e^{−Δτ}))

`α` runs from 1 (fast diffusion, `Δτ ≪ S`) through a maximum near `S ≤ Δτ ≤ 1` back to 1
(slow diffusion, `Δτ ≫ 1`). The terms are computed with `expm1`, so small `Δτ` keeps its
precision.

# Arguments
- `Δτ`: the interval in natural units (`Δt/P`), positive.
- `S`: the weight of the fast part, `0 ≤ S < 1`.

Throws an `ArgumentError` unless `Δτ > 0` and `0 ≤ S < 1`.

# Returns
- `Float64`: the slope.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> isapprox(furth_exponent(1.0e-6, 0.0), 2; rtol = 1.0e-6)
true
```

See also [`optimal_interval`](@ref), [`max_slope_interval`](@ref).
"""
function furth_exponent(Δτ::Real, S::Real)
    Δτ > 0 || throw(ArgumentError("furth_exponent: Δτ must be positive, got $Δτ"))
    0 <= S < 1 || throw(ArgumentError("furth_exponent: S must satisfy 0 ≤ S < 1, got $S"))
    return _alpha(Float64(Δτ), Float64(S))
end
# 1 − (1 − S)e^{−x} = S e^{−x} − expm1(−x); x − (1 − S)(1 − e^{−x}) = S x + (1 − S) g(x),
# g(x) = x + expm1(−x) (the series below 1e-4, as `_furth_g`)
function _alpha(x, S)
    g = x < 1.0e-4 ? x^2 / 2 - x^3 / 6 + x^4 / 24 : x + expm1(-x)
    return x * (S * exp(-x) - expm1(-x)) / (S * x + (1 - S) * g)
end

"""
    optimal_interval(S) -> (; Δτ, α)

Return the interval `Δτ_opt` that maximizes the slope [`furth_exponent`](@ref) at `S`, and
the maximum `α_opt` (Thomas et al. 2022, Eq. 12 and Fig. 5).

Thomas et al. take `Δτ_opt` as the interval at which the polarization best predicts the
displacement. Their power-law fits over the S values of Fortuna et al. (2020) are
`Δτ_opt ≈ 1.932 S^0.455` and `α_opt ≈ 2.022 − 1.115 S^0.397`.

The maximum is found on `log Δτ`: a 400-point grid on `[S/100, 100]`, then golden section
on the bracket of the best grid point to a relative `1e-12`.

# Arguments
- `S`: the weight of the fast part, `0 < S < 1`. At `S = 0` the slope falls from 2 for all
  `Δτ > 0`, so it has no interior maximum.

Throws an `ArgumentError` unless `0 < S < 1`.

# Returns
- `NamedTuple`: `(; Δτ, α)`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> isapprox(optimal_interval(0.01).Δτ, 1.932 * 0.01^0.455; rtol = 0.03)
true
```

See also [`furth_exponent`](@ref), [`furth_fit`](@ref).
"""
function optimal_interval(S::Real)
    0 < S < 1 || throw(ArgumentError("optimal_interval: S must satisfy 0 < S < 1, got $S"))
    s = Float64(S)
    f(y) = _alpha(exp(y), s)
    lo, hi = log(s / 100), log(100.0)
    K = 400
    grid = [lo + (hi - lo) * (k - 1) / (K - 1) for k in 1:K]
    kb = argmax(map(f, grid))
    a, b = grid[max(kb - 1, 1)], grid[min(kb + 1, K)]
    φ = (sqrt(5) - 1) / 2
    x1, x2 = b - φ * (b - a), a + φ * (b - a)
    f1, f2 = f(x1), f(x2)
    while b - a > 1.0e-12
        if f1 >= f2
            b, x2, f2 = x2, x1, f1
            x1 = b - φ * (b - a)
            f1 = f(x1)
        else
            a, x1, f1 = x1, x2, f2
            x2 = a + φ * (b - a)
            f2 = f(x2)
        end
    end
    y = (a + b) / 2
    return (; Δτ = exp(y), α = f(y))
end

"""
    max_slope_interval(Δt, m) -> (; Δt, α)

Return the time of the steepest log-log slope of an MSD curve `m`, and that slope: the
"faster but less precise" estimate of the optimal interval that Thomas et al. (2022, Sec.
4) give for experiments, which needs no fit.

The slope at the interior time `tᵢ` is the centered difference
`(log m_{i+1} − log m_{i−1}) / (log t_{i+1} − log t_{i−1})`. Pass the times in laboratory
units to get `Δt` in the same units; divide by a fitted `P` for natural units.

# Arguments
- `Δt`: the times, positive and strictly increasing, at least 3 of them.
- `m`: the MSD, positive, as many values as `Δt`.

Throws an `ArgumentError` for fewer than 3 points, lengths that differ, or times or MSD
values that are not positive (or times not increasing).

# Returns
- `NamedTuple`: `(; Δt, α)`.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> max_slope_interval([1.0, 2.0, 4.0, 8.0], [1.0, 4.0, 8.0, 16.0]).Δt
2.0
```

See also [`optimal_interval`](@ref), [`mean_squared_displacement`](@ref).
"""
function max_slope_interval(Δt, m)
    t, y = collect(Float64, Δt), collect(Float64, m)
    length(t) == length(y) ||
        throw(
        ArgumentError("max_slope_interval: Δt has $(length(t)) values, m $(length(y))")
    )
    length(t) >= 3 ||
        throw(ArgumentError("max_slope_interval: at least 3 points are needed"))
    (t[1] > 0 && all(i -> t[i + 1] > t[i], 1:(length(t) - 1))) ||
        throw(
        ArgumentError("max_slope_interval: Δt must be positive and strictly increasing")
    )
    all(>(0), y) || throw(ArgumentError("max_slope_interval: m must be positive"))
    s = [
        (log(y[i + 1]) - log(y[i - 1])) / (log(t[i + 1]) - log(t[i - 1]))
            for i in 2:(length(t) - 1)
    ]
    k = argmax(s)
    return (; Δt = t[k + 1], α = s[k])
end

# One series of 2D points, or a vector of series.
_series(x) = _is_point(first(x)) ? [x] : collect(x)
function _points2(x, what)
    isempty(x) && throw(ArgumentError("$what: a series is empty"))
    length(first(x)) == 2 ||
        throw(ArgumentError("$what: the points must be 2D (projected on the substrate)"))
    return _track_points(x, Val(2), what)
end

"""
    mean_velocity(track, lag; dt = 1.0) -> Vector{NTuple{2, Float64}}

Return the mean velocities `u(τ, δ) = (ρ(τ + δ) − ρ(τ))/δ` of a track over the interval
`δ = lag·dt`, at every start `τ` that has a sample `lag` later (Thomas et al. 2022, Eq.
13). The windows overlap. The mean speed is the norm of each vector.

# Arguments
- `track`: a vector of 2D points (unwrapped, projected on the substrate).
- `lag::Integer`: the interval in samples, in `1:(n − 1)`.

# Keywords
- `dt = 1.0`: the time between samples (pass `Δt/P` for natural units).

Throws an `ArgumentError` for a lag outside `1:(n − 1)` or points that are not 2D.

# Returns
- `Vector{NTuple{2, Float64}}`: `n − lag` velocities.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> mean_velocity([(0.0, 0.0), (1.0, 0.0), (3.0, 0.0)], 2; dt = 0.5)
1-element Vector{Tuple{Float64, Float64}}:
 (3.0, 0.0)
```

See also [`polarization_statistics`](@ref).
"""
function mean_velocity(track, lag::Integer; dt::Real = 1.0)
    x = _points2(track, "mean_velocity")
    1 <= lag < length(x) ||
        throw(ArgumentError("mean_velocity: lag $lag is outside 1:$(length(x) - 1)"))
    δ = lag * Float64(dt)
    return [(x[k + lag] .- x[k]) ./ δ for k in 1:(length(x) - lag)]
end

"""
    polarization_statistics(Π, tracks, lag; dt = 1.0, unit = false)
        -> (; u, ε, ξ, σθ, u_parallel, n, n_angles)

Return the statistics of Thomas et al. (2022) that compare a polarization vector with the
mean velocity over the interval `δ = lag·dt`, pooled over every start `τ` and every
replicate:

- `u`: the mean speed `⟨|u(τ, δ)|⟩` (Eq. 13).
- `ε`: the relative speed error `σ_speed/⟨u⟩` (Eq. 15), `σ_speed` the standard deviation
  of `|u(τ, δ)|` (with the `n − 1` denominator).
- `ξ`: the velocity-polarization correlation index `⟨cos θ⟩/⟨sin θ⟩` (Eq. 14), with `θ`
  the unsigned angle in `[0, π]` between `Π(τ)` and `u(τ, δ)`, so `sin θ ≥ 0`: `ξ` is 0
  when they are always orthogonal and grows without bound when they are always parallel.
- `σθ`: the standard deviation of the signed angle `θ ∈ (−π, π]` (from `Π` to `u`), whose
  mean is near 0 for a symmetric spread.
- `u_parallel`: the mean of `Π(τ) · u(τ, δ)` (Eq. 16 as printed, not divided by `|Π|`),
  or of `Π̂(τ) · u(τ, δ)` with `unit = true`.

`Π[k]` is the polarization at the start of the window that begins at sample `k`. A
window whose `Π` or displacement is the zero vector has no angle; it is left out of `ξ`
and `σθ` (`n_angles` counts the rest). A window whose `Π` is not finite (a NaN marks an
absent compartment) counts only in `u` and `ε`; so does one with `Π = 0` when `unit = true`.

# Arguments
- `Π`: the polarization series (2D vectors), one per track: a series or a vector of them.
- `tracks`: the tracks (2D points, unwrapped), as many samples as their `Π` series.
- `lag::Integer`: the interval in samples.

# Keywords
- `dt = 1.0`: the time between samples (pass `Δt/P` for natural units).
- `unit::Bool = false`: divide `Π` by its norm in `u_parallel` (as Dal-Castel et al. do).

Throws an `ArgumentError` when the numbers of series or of samples differ, for a lag
outside `1:(n − 1)`, and for points that are not 2D.

# Returns
- `NamedTuple`: `(; u, ε, ξ, σθ, u_parallel, n, n_angles)`, `n` the number of windows.

# Examples
```jldoctest
julia> using PottsModels.Analysis

julia> track = [(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)];

julia> s = polarization_statistics(fill((1.0, 0.0), 3), track, 1);

julia> (s.u ≈ √2, s.ξ ≈ 1, s.σθ ≈ π / 4 * √2)
(true, true, true)
```

See also [`mean_velocity`](@ref), [`optimal_interval`](@ref).
"""
function polarization_statistics(
        Π, tracks, lag::Integer; dt::Real = 1.0, unit::Bool = false
    )
    what = "polarization_statistics"
    (isempty(Π) || isempty(tracks)) && throw(ArgumentError("$what: no series"))
    Ps, Ts = _series(Π), _series(tracks)
    length(Ps) == length(Ts) ||
        throw(
        ArgumentError("$what: $(length(Ps)) polarization series for $(length(Ts)) tracks")
    )
    speeds, par, signed, unsigned = Float64[], Float64[], Float64[], Float64[]
    for (p, tr) in zip(Ps, Ts)
        P = _points2(p, what)
        length(P) == length(tr) ||
            throw(ArgumentError("$what: a polarization series has $(length(P)) samples, \
                its track $(length(tr))"))
        u = mean_velocity(tr, lag; dt)
        for k in eachindex(u)
            a, v = P[k], u[k]
            push!(speeds, hypot(v...))
            na = hypot(a...)
            (isfinite(na) && !(unit && na == 0)) || continue
            push!(par, (a[1] * v[1] + a[2] * v[2]) / (unit ? na : 1.0))
            (na > 0 && hypot(v...) > 0) || continue
            θ = atan(a[1] * v[2] - a[2] * v[1], a[1] * v[1] + a[2] * v[2])
            push!(signed, θ)
            push!(unsigned, abs(θ))
        end
    end
    mean_(x) = sum(x) / length(x)
    std_(x) = sqrt(sum(abs2, x .- mean_(x)) / (length(x) - 1))
    um = mean_(speeds)
    return (;
        u = um, ε = std_(speeds) / um,
        ξ = mean_(cos.(unsigned)) / mean_(sin.(unsigned)), σθ = std_(signed),
        u_parallel = mean_(par), n = length(speeds), n_angles = length(signed),
    )
end
