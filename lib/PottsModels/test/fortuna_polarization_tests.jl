# The polarization analysis of Thomas et al. (2022, Physica A 587:126511) in
# PottsModels.Analysis, against oracles with a known answer:
# - the slope α (Eq 12) against a numerical derivative of the natural-units MSD (Eq 4);
# - Δτ_opt: the two values the paper prints (Fig 4: 0.048 and 0.672 at the S of Table 2
#   and of p. 10), a brute-force grid, and the α_opt law of Fig 5;
# - Δτ_opt from tracks on the paper's sampling (10 replicates, 10⁵ MCS, a 1000-MCS
#   warm-up): the Fürth fit on 50-MCS samples, and the fit-free steepest-slope estimate on
#   every-MCS samples, both recover the true Δτ_opt; negative controls at another S and on
#   purely diffusive tracks;
# - ξ, σθ, ⟨u⟩, ε and u_∥ (Eqs 13–16) on hand tracks with exact values and on tracks of the
#   anisotropic model (persistent along Π, translational noise across it) against
#   quadrature; negative control: a polarization that ignores the motion gives ξ ≈ 0.

@testsetup module FortunaPolarizationSetup
include(joinpath(@__DIR__, "shared", "common.jl"))
using PottsModels.Analysis
using StableRNGs: StableRNG
const TABLE2 = joinpath(@__DIR__, "reproductions", "data", "14", "table2.tsv")
table2_S() = [parse(Float64, split(l, '\t')[4]) for l in readlines(TABLE2)[2:end]]

# Eq 4: ⟨|Δρ|²⟩ = Δτ − (1 − S)(1 − e^{−Δτ}), in BigFloat for the numerical derivative
eq4(τ, S) = τ - (1 - S) * (1 - exp(-τ))
function slope_fd(τ, S; h = big"1e-20")
    x, s = big(τ), big(S)
    return Float64((log(eq4(x * exp(h), s)) - log(eq4(x * exp(-h), s))) / 2h)
end

# Tracks with the modified Fürth MSD (Eq 3): an exact AR(1) velocity per axis, the
# position Euler-integrated from it (the error is O(dt/P), negligible here), plus Brownian
# increments of D_fast = DS/(1 − S), sampled every `dt` MCS.
function furth_tracks(rng; S, D, P, n, dt = 1.0, ntracks = 10)
    a, sv, sb = exp(-dt / P), sqrt(D / (2P)), sqrt(D * S / (1 - S) * dt)
    out = Vector{Vector{NTuple{2, Float64}}}()
    for _ in 1:ntracks
        v = (sv * randn(rng), sv * randn(rng))
        x = (0.0, 0.0)
        tr = Vector{NTuple{2, Float64}}(undef, n)
        tr[1] = x
        for k in 2:n
            x = x .+ v .* dt .+ sb .* (randn(rng), randn(rng))
            v = a .* v .+ (sv * sqrt(1 - a^2)) .* (randn(rng), randn(rng))
            tr[k] = x
        end
        push!(out, tr)
    end
    return out
end
# The anisotropic model: speed `v` along a fixed direction φ per track, translational noise
# of diffusion constant `Dp` across it; the polarization is `p` along φ.
function aniso_tracks(rng; v, Dp, p, n, ntracks = 10)
    tracks, Πs = Vector{Vector{NTuple{2, Float64}}}(), Vector{Vector{NTuple{2, Float64}}}()
    for _ in 1:ntracks
        φ = 2π * rand(rng)
        e, e⊥ = (cos(φ), sin(φ)), (-sin(φ), cos(φ))
        x = (0.0, 0.0)
        tr = [x]
        for _ in 2:n
            x = x .+ v .* e .+ sqrt(2Dp) * randn(rng) .* e⊥
            push!(tr, x)
        end
        push!(tracks, tr)
        push!(Πs, fill(p .* e, n))
    end
    return tracks, Πs
end
# E[g(Z)], Z standard normal, by the trapezoid rule on [−10, 10]
function gauss_mean(g; m = 20_001)
    z = range(-10, 10; length = m)
    w = exp.(-z .^ 2 ./ 2) ./ sqrt(2π) .* step(z)
    return sum(w .* g.(z))
end
# the oracle of the anisotropic model at lag ℓ: the displacement is vℓ along Π plus
# N(0, 2Dp ℓ) across it
function aniso_oracle(; v, Dp, p, ℓ)
    s = sqrt(2Dp * ℓ) / (v * ℓ)
    θ(z) = atan(s * z)
    sp(z) = sqrt(v^2 + 2Dp * z^2 / ℓ)
    u = gauss_mean(sp)
    return (;
        u, ε = sqrt(v^2 + 2Dp / ℓ - u^2) / u,
        ξ = gauss_mean(z -> cos(θ(z))) / gauss_mean(z -> abs(sin(θ(z)))),
        σθ = sqrt(gauss_mean(z -> θ(z)^2)), u_parallel = p * v,
    )
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "Fortuna polarization analysis: the MSD slope (Eq 12)" setup = [
    FortunaPolarizationSetup,
] tags = [:pottsmodels, :core] begin
    for S in (0.0, 1.0e-4, 0.01, 0.1, 0.4), τ in (1.0e-5, 1.0e-3, 0.05, 0.5, 3.0, 30.0)
        @test furth_exponent(τ, S) ≈ slope_fd(τ, S) rtol = 1.0e-9
    end
    # the limits: 2 (ballistic) at S = 0 and small Δτ, 1 (diffusive) at Δτ ≪ S and Δτ ≫ 1
    @test furth_exponent(1.0e-8, 0.0) ≈ 2 rtol = 1.0e-6
    @test furth_exponent(1.0e-8, 0.1) ≈ 1 rtol = 1.0e-5
    @test furth_exponent(1.0e4, 0.1) ≈ 1 rtol = 1.0e-3
    @test_throws ArgumentError furth_exponent(0.0, 0.1)
    @test_throws ArgumentError furth_exponent(1.0, 1.0)
end

@testitem "Fortuna polarization analysis: the optimal interval" setup = [
    FortunaPolarizationSetup,
] tags = [:pottsmodels, :core] begin
    # Fig 4 prints Δτ_opt = 0.048 at R = 15, φ = 0.10, λ_F = 200 (Table 2 of Fortuna et al.:
    # S = 3.93e-4) and 0.672 at φ = 0.30, λ_F = 150 (p. 10: S = 9.46e-2); the band is one
    # unit of the last printed digit (we get 0.04817 and 0.67253)
    @test abs(optimal_interval(3.93e-4).Δτ - 0.048) < 1.0e-3
    @test abs(optimal_interval(9.46e-2).Δτ - 0.672) < 1.0e-3
    # negative control: the neighbor row (λ_F = 175, S = 9.84e-4) is far outside the band
    @test abs(optimal_interval(9.84e-4).Δτ - 0.048) > 0.02
    # a brute-force grid on log Δτ agrees, and the slope is flat at the maximum
    for S in (1.0e-4, 3.0e-3, 0.05, 0.3)
        o = optimal_interval(S)
        τs = exp.(range(log(S / 100), log(100.0); length = 200_001))
        k = argmax([furth_exponent(τ, S) for τ in τs])
        @test o.Δτ ≈ τs[k] rtol = 1.0e-3
        @test o.α ≈ furth_exponent(τs[k], S) rtol = 1.0e-9
        @test o.α ≈ furth_exponent(o.Δτ, S)
        @test abs(slope_fd(o.Δτ * 1.0001, S) - o.α) < 1.0e-7
        # p. 7 says "a maximum for S ≤ Δτ ≤ 1", which fails for S ≳ 0.25 (Δτ_opt(0.3) ≈
        # 1.12); 1.2 covers the S of this loop
        @test S <= o.Δτ <= 1.2
    end
    # Fig 5 at the S values of Table 2: the α_opt law holds within 3 % (spec band; 1 % in
    # fact). The Δτ_opt law holds within 20 % (16 % at S = 1.09e-4, the smallest), while
    # the two printed values above hold to 1e-3
    S = table2_S()
    o = optimal_interval.(S)
    @test all(k -> abs(o[k].α / (2.022 - 1.115 * S[k]^0.397) - 1) < 0.03, eachindex(S))
    @test all(k -> abs(o[k].Δτ / (1.932 * S[k]^0.455) - 1) < 0.2, eachindex(S))
    # The 16 %: the Δτ_opt law is a least-squares fit of a·S^b in linear space over these S,
    # which weights the large Δτ. Our refit gives a = 1.948, b = 0.4575 (R² = 0.9993)
    # against the printed 1.932, 0.455: a within 1.5 %, b within 0.005. Control: a fit in
    # log space gives b ≈ 0.479, outside the band.
    y = [x.Δτ for x in o]
    afit(b) = sum(y .* S .^ b) / sum(S .^ (2b))              # the best a for a given b
    sse(b) = sum(abs2, y .- afit(b) .* S .^ b)
    bs = range(0.3, 0.6; length = 30_001)
    b = bs[argmin(sse.(bs))]
    @test abs(afit(b) / 1.932 - 1) < 0.015 && abs(b - 0.455) < 0.005
    @test 1 - sse(b) / sum(abs2, y .- sum(y) / length(y)) > 0.999
    X = log.(S)
    blog = sum((X .- sum(X) / length(X)) .* log.(y)) / sum(abs2, X .- sum(X) / length(X))
    @test abs(blog - 0.455) > 0.005
    @test_throws ArgumentError optimal_interval(0.0)   # S = 0: no interior maximum
    @test_throws ArgumentError optimal_interval(1.0)
end

@testitem "Fortuna polarization analysis: Δτ_opt from tracks, paper's sampling" setup = [
    FortunaPolarizationSetup,
] tags = [:pottsmodels, :core] begin
    # Table 2's R = 15, φ = 0.10, λ_F = 150: S = 9.68e-3, P = 6878 MCS, D = 2.83e-4. Ten
    # replicates of 10⁵ MCS after a 1000-MCS warm-up: 99001 samples, every MCS.
    S, P, D = 9.68e-3, 6878.0, 2.83e-4
    truth = optimal_interval(S).Δτ                    # 0.232: 1594 MCS
    lags = unique(round.(Int, exp10.(range(0, 4.5; length = 60))))
    fit_lags = 1:200
    for seed in 1:3
        tr = furth_tracks(StableRNG(seed); S, D, P, n = 99_001)
        # the Fürth fit on 50-MCS samples (lags 50 … 10⁴ MCS), then Eq 12 at the fitted S
        m50 = mean_squared_displacement([t[1:50:end] for t in tr]; lags = fit_lags)
        f = furth_fit(50.0 .* fit_lags, m50; method = :lsq)
        @test abs(optimal_interval(f.S).Δτ / truth - 1) < 0.3
        # the steepest log-log slope of the every-MCS MSD, without a fit
        m = mean_squared_displacement(tr; lags)
        ms = max_slope_interval(lags, m)
        @test abs(ms.Δt / P / truth - 1) < 0.1
        @test abs(ms.α - optimal_interval(S).α) < 0.05
    end
    # negative controls: tracks at S = 0.1 give a Δτ_opt far from this one; purely
    # diffusive tracks have no ballistic stretch (α_max near 1, not 1.85)
    tr = furth_tracks(StableRNG(1); S = 0.1, D, P, n = 99_001)
    m50 = mean_squared_displacement([t[1:50:end] for t in tr]; lags = fit_lags)
    f = furth_fit(50.0 .* fit_lags, m50; method = :lsq)
    @test optimal_interval(f.S).Δτ / truth > 2
    bt = furth_tracks(StableRNG(1); S = 1 - 1.0e-9, D, P, n = 99_001)
    @test max_slope_interval(lags, mean_squared_displacement(bt; lags)).α < 1.3
    @test_throws ArgumentError max_slope_interval([1.0, 2.0], [1.0, 2.0])
    @test_throws ArgumentError max_slope_interval([1.0, 2.0, 3.0], [1.0, 0.0, 2.0])
end

@testitem "Fortuna polarization analysis: ξ, σθ, ⟨u⟩, ε and u_∥ on hand tracks" setup = [
    FortunaPolarizationSetup,
] tags = [:pottsmodels, :core] begin
    # Π = (2, 0); the steps alternate at +θ₀ and −θ₀ with speeds 1 and 3
    θ0 = π / 6
    up, down = (cos(θ0), sin(θ0)), 3.0 .* (cos(θ0), -sin(θ0))
    steps = [isodd(k) ? up : down for k in 1:10]
    tr = accumulate((x, d) -> x .+ d, steps; init = (0.0, 0.0))
    tr = [(0.0, 0.0); tr]
    Π = fill((2.0, 0.0), 11)
    s = polarization_statistics(Π, tr, 1; dt = 0.5)
    @test s.n == 10 && s.n_angles == 10
    @test s.u ≈ 4                                     # speeds 2 and 6 at δ = 0.5
    @test s.ε ≈ sqrt(40 / 9) / 4                      # std of five 2s and five 6s
    @test s.ξ ≈ cot(θ0)
    @test s.σθ ≈ θ0 * sqrt(10 / 9)
    @test s.u_parallel ≈ 2 * 4 * cos(θ0)              # Eq 16 as printed: Π · u
    @test polarization_statistics(Π, tr, 1; dt = 0.5, unit = true).u_parallel ≈ 4cos(θ0)
    @test mean_velocity(tr, 2; dt = 0.5)[1] == tr[3] ./ 1.0
    # two replicates pool their windows
    s2 = polarization_statistics([Π, Π], [tr, tr], 1; dt = 0.5)
    @test s2.n == 20 && s2.u ≈ 4 && s2.ξ ≈ cot(θ0)
    # a window with Π = 0 has no angle but keeps its speed
    Π0 = copy(Π)
    Π0[1] = (0.0, 0.0)
    @test polarization_statistics(Π0, tr, 1).n_angles == 9
    # a NaN polarization (an absent compartment) keeps only the speed
    ΠN = copy(Π)
    ΠN[1] = (NaN, NaN)
    sN = polarization_statistics(ΠN, tr, 1; dt = 0.5)
    @test sN.u ≈ 4 && sN.n_angles == 9 && isfinite(sN.u_parallel) && isfinite(sN.ξ)
    @test_throws ArgumentError polarization_statistics(Π[1:10], tr, 1)
    @test_throws ArgumentError polarization_statistics([Π, Π], [tr], 1)
    @test_throws ArgumentError mean_velocity(tr, 11)
    @test_throws ArgumentError mean_velocity([(0.0, 0.0, 0.0), (1.0, 0.0, 0.0)], 1)
end

@testitem "Fortuna polarization analysis: the anisotropic model and quadrature" setup = [
    FortunaPolarizationSetup,
] tags = [:pottsmodels, :core] begin
    v, Dp, p = 0.01, 0.005, 3.0
    tracks, Πs = aniso_tracks(StableRNG(7); v, Dp, p, n = 20_001)
    for ℓ in (1, 10, 100)
        s = polarization_statistics(Πs, tracks, ℓ)
        o = aniso_oracle(; v, Dp, p, ℓ)
        @test s.u ≈ o.u rtol = 0.02
        @test s.ε ≈ o.ε rtol = 0.03
        @test s.ξ ≈ o.ξ rtol = 0.05
        @test s.σθ ≈ o.σθ rtol = 0.02
        # the noise is across Π, so Π · u is p·v at every δ, to rounding
        @test s.u_parallel ≈ o.u_parallel rtol = 1.0e-9
    end
    # Fig 3B and Fig 7D: ⟨u⟩ diverges as δ → 0 while ⟨u_∥⟩ does not
    a, b = (polarization_statistics(Πs, tracks, ℓ) for ℓ in (1, 100))
    @test a.u / b.u > 5
    @test a.u_parallel ≈ b.u_parallel rtol = 1.0e-9
    # negative control: a polarization that ignores the motion (a fresh random direction
    # each sample) gives ξ ≈ 0 and ⟨u_∥⟩ ≈ 0
    rng = StableRNG(8)
    Πr = [[p .* (cos(φ), sin(φ)) for φ in 2π .* rand(rng, length(t))] for t in tracks]
    r = polarization_statistics(Πr, tracks, 100)
    @test abs(r.ξ) < 0.05
    @test abs(r.u_parallel) < 0.05 * p * v
end
