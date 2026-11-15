# Process-wide statistical acceptance and convergence-order helper definitions,
# evaluated once inside `Main.PottsStats` by `stats_helpers.jl`.

using Statistics: mean, std, var

# Standard normal CDF via erf approximation (Abramowitz & Stegun 7.1.26, max err 1.5e-7)
function _normcdf(z::Real)
    x = Float64(z) / sqrt(2.0)
    t = 1.0 / (1.0 + 0.3275911 * abs(x))
    y = 1.0 - (
        ((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t +
            0.254829592
    ) * t * exp(-x * x)
    erf_x = x >= 0 ? y : -y
    return 0.5 * (1.0 + erf_x)
end

# Beasley-Springer-Moro inverse standard normal CDF for p in (0, 1)
function _norminvcdf(p::Real)
    0.0 < p < 1.0 || throw(DomainError(p, "p must lie in (0, 1)"))
    p < 0.5 && return -_norminvcdf(1.0 - p)
    q = p - 0.5
    if q <= 0.42
        r = q * q
        return q * (((-25.44106049637 * r + 41.39119773534) * r - 18.61500062529) * r + 2.50662823884) /
            ((((3.13082909833 * r - 21.06224101826) * r + 23.08336743743) * r - 8.4735109309) * r + 1.0)
    end
    r = log(-log(1.0 - p))
    return 0.3374754822726147 + r * (
        0.9761690190917186 + r * (
            0.1607979714918209 +
                r * (
                0.0276438810333863 + r * (
                    0.0038405729373609 + r * (
                        0.0003951896511919 +
                            r * (0.0000321767881768 + r * (0.0000002888167364 + r * 0.0000003960315187))
                    )
                )
            )
        )
    )
end

"""
    required_n(sigma, delta; alpha = 1e-3, power = 0.9, two_sided = true) -> Int

Sample size per group for a z-test at significance `alpha` and `power` against shift `delta`.
"""
function required_n(sigma::Real, delta::Real; alpha::Real = 1.0e-3, power::Real = 0.9, two_sided::Bool = true)
    z_a = _norminvcdf(two_sided ? 1.0 - alpha / 2.0 : 1.0 - alpha)
    z_b = _norminvcdf(power)
    return ceil(Int, ((z_a + z_b) * sigma / abs(delta))^2)
end

"""
    stat_accept(xs; mu0 = 0.0, margin = nothing, sigma = nothing, alpha = 1e-3, alternative = :two_sided)

One-sample z-test (when `sigma` is provided) or normal-approx test, or TOST equivalence test
(when `margin` is provided). Returns `(; pass, pvalue, statistic, n, mean)`.
"""
function stat_accept(
        xs::AbstractVector{<:Real};
        mu0::Real = 0.0,
        margin::Union{Nothing, Real} = nothing,
        sigma::Union{Nothing, Real} = nothing,
        alpha::Real = 1.0e-3,
        alternative::Symbol = :two_sided
    )
    n = length(xs)
    n >= 2 || throw(ArgumentError("stat_accept requires at least 2 observations"))
    m = Float64(mean(xs))
    s = sigma === nothing ? Float64(std(xs)) : Float64(sigma)
    se = s / sqrt(n)
    if margin !== nothing
        z_lo = (m - (mu0 - margin)) / se
        z_hi = ((mu0 + margin) - m) / se
        p_lo = 1.0 - _normcdf(z_lo)
        p_hi = 1.0 - _normcdf(z_hi)
        pval = max(p_lo, p_hi)
        return (; pass = pval <= alpha, pvalue = pval, statistic = min(z_lo, z_hi), n, mean = m)
    end
    z = (m - mu0) / se
    pval = if alternative === :two_sided
        2.0 * (1.0 - _normcdf(abs(z)))
    elseif alternative === :greater
        1.0 - _normcdf(z)
    elseif alternative === :less
        _normcdf(z)
    else
        throw(ArgumentError("unknown alternative=$(repr(alternative))"))
    end
    return (; pass = pval <= alpha, pvalue = pval, statistic = z, n, mean = m)
end

"""
    stat_accept(xs, ys; margin = nothing, alpha = 1e-3, alternative = :greater)

Two-sample Welch z-test comparing `xs` against control `ys`, or two-sample TOST
equivalence test within `[-margin, +margin]` when `margin` is provided.
"""
function stat_accept(
        xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real};
        margin::Union{Nothing, Real} = nothing,
        alpha::Real = 1.0e-3,
        alternative::Symbol = :greater
    )
    nx, ny = length(xs), length(ys)
    (nx >= 2 && ny >= 2) || throw(ArgumentError("two-sample stat_accept requires n >= 2 per group"))
    mx, my = Float64(mean(xs)), Float64(mean(ys))
    se = sqrt(Float64(var(xs)) / nx + Float64(var(ys)) / ny)
    diff = mx - my
    if margin !== nothing
        z_lo = (diff + margin) / se
        z_hi = (margin - diff) / se
        pval = max(1.0 - _normcdf(z_lo), 1.0 - _normcdf(z_hi))
        return (; pass = pval <= alpha, pvalue = pval, statistic = min(z_lo, z_hi), n = (nx, ny), mean = (mx, my))
    end
    z = diff / se
    pval = if alternative === :two_sided
        2.0 * (1.0 - _normcdf(abs(z)))
    elseif alternative === :greater
        1.0 - _normcdf(z)
    elseif alternative === :less
        _normcdf(z)
    else
        throw(ArgumentError("unknown alternative=$(repr(alternative))"))
    end
    return (; pass = pval <= alpha, pvalue = pval, statistic = z, n = (nx, ny), mean = (mx, my))
end

include(joinpath(@__DIR__, "convergence_helpers.jl"))

export required_n, stat_accept, observed_orders, observed_order
