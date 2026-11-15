# Shared property-test helpers (TS-R2 §2, §3, §4):
# - `fp_props`: fingerprint sensitivity, invariance, checkpoint compatibility, and subprocess determinism
# - `stat_accept` / `required_n`: normal/t/TOST statistical acceptance helpers with stated α and power
# - `observed_orders` / `observed_order`: empirical convergence-order helpers
# - `tiny_oracle_sample` / `tiny_oracle_check`: tiny-lattice transition-kernel enumerator helpers
#
# Designed to be `include`d inside a ReTestItems `@testsetup` module.

using Statistics: mean, std, var
using Test: @test, @test_throws

if !isdefined(@__MODULE__, :Oracle)
    include(joinpath(@__DIR__, "..", "..", "lib", "CorePotts", "test", "oracle_core.jl"))
end

# --- Fingerprint property helpers (§2.1, §5) ---------------------------------------------

function _assert_checkpoint_refused(base_prob, mut_prob)
    integ = init(base_prob, SequentialCPM(); save_start = false)
    ck = checkpoint(integ)
    @test_throws ArgumentError init(mut_prob, SequentialCPM(); checkpoint = ck)
end

function _assert_checkpoint_accepted(base_prob, eq_prob)
    integ = init(base_prob, SequentialCPM(); save_start = false)
    ck = checkpoint(integ)
    loaded = init(eq_prob, SequentialCPM(); checkpoint = ck)
    @test loaded.state.σ == integ.state.σ
end

"""
    fp_props(make_base; variants = (), invariants = (), check_checkpoint = true,
             check_algorithms = false, subprocess_expr = nothing, project = dirname(@__DIR__))

Verify fingerprint properties for a problem family without stored literal pins:
- same-session determinism (`make_base()` built twice gives equal fingerprints)
- sensitivity: every `(label, make_mut)` in `variants` changes `prob.f.fingerprint`
  (and refuses a checkpoint from `base` when `check_checkpoint` is true)
- invariance: every `(label, make_eq)` in `invariants` preserves `prob.f.fingerprint`
  (and accepts a checkpoint from `base` when `check_checkpoint` is true)
- optional algorithm independence (`SequentialCPM` vs `CheckerboardCPM`)
- optional fresh-subprocess determinism (`subprocess_expr` prints `repr(fp)` or `string(fp)`).
"""
function fp_props(make_base;
        variants = (),
        invariants = (),
        check_checkpoint::Bool = true,
        check_algorithms::Bool = false,
        subprocess_expr::Union{Nothing, AbstractString} = nothing,
        project::AbstractString = dirname(@__DIR__))
    base = make_base()
    fp0 = base.f.fingerprint
    @test make_base().f.fingerprint == fp0

    for (label, make_mut) in variants
        @testset "sensitivity: $label" begin
            mut = make_mut()
            @test mut.f.fingerprint != fp0
            check_checkpoint && _assert_checkpoint_refused(base, mut)
        end
    end

    for (label, make_eq) in invariants
        @testset "invariance: $label" begin
            eq = make_eq()
            @test eq.f.fingerprint == fp0
            check_checkpoint && _assert_checkpoint_accepted(base, eq)
        end
    end

    if check_algorithms
        ck = checkpoint(init(base, SequentialCPM(); save_start = false))
        cb = init(base, CheckerboardCPM(); checkpoint = ck)
        @test cb.state.σ == ck.state.σ
    end

    if subprocess_expr !== nothing
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project -e $subprocess_expr`
        out = strip(read(cmd, String))
        @test parse(UInt64, out) == fp0
    end

    return (; base = fp0, sensitivity = length(variants), invariance = length(invariants))
end

# --- Statistical acceptance helpers (§3) -------------------------------------------------

# Standard normal CDF via erf approximation (Abramowitz & Stegun 7.1.26, max err 1.5e-7)
function _normcdf(z::Real)
    x = Float64(z) / sqrt(2.0)
    t = 1.0 / (1.0 + 0.3275911 * abs(x))
    y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t +
        0.254829592) * t * exp(-x * x)
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
               ((((3.13082909833 * r - 21.06224101826) * r + 23.08336743743) * r - 8.47351093090) * r + 1.0)
    end
    r = log(-log(1.0 - p))
    return 0.3374754822726147 + r * (0.9761690190917186 + r * (0.1607979714918209 +
        r * (0.0276438810333863 + r * (0.0038405729373609 + r * (0.0003951896511919 +
        r * (0.0000321767881768 + r * (0.0000002888167364 + r * 0.0000003960315187)))))))
end

"""
    required_n(sigma, delta; alpha = 1e-3, power = 0.9, two_sided = true) -> Int

Sample size per group for a z-test at significance `alpha` and `power` against shift `delta`.
"""
function required_n(sigma::Real, delta::Real; alpha::Real = 1e-3, power::Real = 0.9, two_sided::Bool = true)
    z_a = _norminvcdf(two_sided ? 1.0 - alpha / 2.0 : 1.0 - alpha)
    z_b = _norminvcdf(power)
    return ceil(Int, ((z_a + z_b) * sigma / abs(delta))^2)
end

"""
    stat_accept(xs; mu0 = 0.0, margin = nothing, sigma = nothing, alpha = 1e-3, alternative = :two_sided)

One-sample z-test (when `sigma` is provided) or normal-approx test, or TOST equivalence test
(when `margin` is provided). Returns `(; pass, pvalue, statistic, n, mean)`.
"""
function stat_accept(xs::AbstractVector{<:Real};
        mu0::Real = 0.0,
        margin::Union{Nothing, Real} = nothing,
        sigma::Union{Nothing, Real} = nothing,
        alpha::Real = 1e-3,
        alternative::Symbol = :two_sided)
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
    stat_accept(xs, ys; alpha = 1e-3, alternative = :greater)

Two-sample Welch z-test comparing `xs` against control `ys`.
"""
function stat_accept(xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real};
        alpha::Real = 1e-3,
        alternative::Symbol = :greater)
    nx, ny = length(xs), length(ys)
    (nx >= 2 && ny >= 2) || throw(ArgumentError("two-sample stat_accept requires n >= 2 per group"))
    mx, my = Float64(mean(xs)), Float64(mean(ys))
    se = sqrt(Float64(var(xs)) / nx + Float64(var(ys)) / ny)
    z = (mx - my) / se
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

# --- Convergence order helpers -----------------------------------------------------------

"""
    observed_orders(hs, errs) -> Vector{Float64}

Pairwise empirical convergence orders `log(errs[i] / errs[i+1]) / log(hs[i] / hs[i+1])`.
"""
function observed_orders(hs::AbstractVector{<:Real}, errs::AbstractVector{<:Real})
    length(hs) == length(errs) || throw(DimensionMismatch("hs and errs must have equal length"))
    length(hs) >= 2 || throw(ArgumentError("at least 2 grid levels required"))
    return [log(Float64(errs[i]) / Float64(errs[i + 1])) / log(Float64(hs[i]) / Float64(hs[i + 1]))
            for i in 1:(length(hs) - 1)]
end

"""
    observed_order(hs, errs) -> Float64

Least-squares log-log slope of `errs` against `hs`.
"""
function observed_order(hs::AbstractVector{<:Real}, errs::AbstractVector{<:Real})
    lx = log.(Float64.(hs))
    ly = log.(Float64.(errs))
    mx, my = mean(lx), mean(ly)
    return sum((lx .- mx) .* (ly .- my)) / sum((lx .- mx) .^ 2)
end

# --- Tiny-lattice transition-kernel enumerator helpers -----------------------------------

function tiny_oracle_sample(prob, alg, R::Integer)
    counts = Dict{Vector{Int8}, Int}()
    for seed in 1:R
        σ = vec(Int8.(solve(remake(prob; seed), alg; save_start = false).u[end].σ))
        counts[σ] = get(counts, σ, 0) + 1
    end
    return counts
end

function tiny_oracle_check(tiny::Oracle.Tiny, σ0::Vector{Int8}, nmcs::Integer, step, prob, alg;
        R::Integer = 40_000)
    ex = Oracle.exact(tiny, σ0, nmcs, step)
    counts = tiny_oracle_sample(prob, alg, R)
    d, noise = Oracle.tv(ex, counts, R)
    z = Oracle.chi2_z(ex, counts, R)
    return (; z, tv = d, noise, exact = ex, counts)
end
