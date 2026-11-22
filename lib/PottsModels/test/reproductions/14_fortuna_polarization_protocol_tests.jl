# Reproduction 14, the polarization study of Thomas et al. (2022): the protocol in
# `lib/PottsModels/reproductions/data/14/polarization_protocol.jl` (run set, seeds, the
# analysis and the bands), on synthetic data only (no simulation):
# - the run set, seeds and cadence;
# - the stationary series of one run: warm-up cut, unwrapping, the three polarizations;
# - the whole analysis of one set on tracks with a known modified Fürth MSD whose
#   polarization is the direction of the persistent velocity: the fitted Δτ_opt is within
#   the band of the true one, ξ peaks within ×2 of Δτ_opt (Fig 4), u_∥ converges and u
#   diverges as δ → 0 (Figs 3B, 7D); negative control: a polarization that ignores the
#   motion has ξ ≈ 0 and u_∥ ≈ 0;
# - the verdict rules on hand rows, with controls that break each rule.

@testsetup module FortunaPolarizationProtocolSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using PottsModels: PottsModels
using StableRNGs: StableRNG
const DIR14 = joinpath(pkgdir(PottsModels), "reproductions", "data", "14")
include(joinpath(DIR14, "protocol.jl"))
include(joinpath(DIR14, "polarization_protocol.jl"))
const PP = FortunaPolarizationProtocol
const P14 = FortunaProtocol

# One recorded run (the columns `stationary` reads) of a modified Fürth walk, every MCS:
# AR(1) velocity plus Brownian increments of D_fast = DS/(1 − S), in units of R; the
# polarization is `pol` sites along the velocity (`mode = :velocity`) or along a fresh
# random direction each MCS (`mode = :random`), and the lamellipodium leads the nucleus by
# `lead`.
function synthetic_run(
        rng; S, D, P, R = 15, L = 120, n = 100_001, pol = 2.0, lead = 5.0,
        mode = :velocity
    )
    a, sv, sb = exp(-1 / P), sqrt(D / (2P)), sqrt(D * S / (1 - S))
    v, x = (sv * randn(rng), sv * randn(rng)), (60.0 / R, 60.0 / R)
    rec = (
        t = collect(0:(n - 1)), nx = zeros(n), ny = zeros(n), lx = zeros(n), ly = zeros(n),
        Πx = zeros(n), Πy = zeros(n), vl = ones(n), lam_cyto = ones(n),
    )
    for k in 1:n
        e = mode === :velocity ? v ./ hypot(v...) : (c = 2π * rand(rng); (cos(c), sin(c)))
        rec.nx[k], rec.ny[k] = mod.(R .* x, L)
        rec.Πx[k], rec.Πy[k] = pol .* e
        rec.lx[k], rec.ly[k] = mod.(R .* x .+ lead .* e, L)
        x = x .+ v .+ sb .* (randn(rng), randn(rng))
        v = a .* v .+ (sv * sqrt(1 - a^2)) .* (randn(rng), randn(rng))
    end
    return rec
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "Fortuna polarization protocol: the run set, seeds and cadence" setup = [
    FortunaPolarizationProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    S = PP.SETS
    @test length(S) == 36 && allunique(S) && first(S)[1] == 15
    @test Set(s[1] for s in S) == Set((10, 15, 20))
    @test Set(s[3] for s in S) == Set((150, 175, 200))
    seeds = [PP.seed(i, k) for i in eachindex(S) for k in 1:PP.REPS]
    @test allunique(seeds) && all(<(typemax(Int32)), seeds)
    # disjoint from the seeds of the Fortuna reproduction
    old = [
        P14.seed(i, k) for i in eachindex(P14.SETS) for k in 1:P14.replicates(P14.SETS[i])
    ]
    @test isempty(intersect(seeds, old))
    @test keys(PP.PAPER_DTAU) ⊆ S && PP.CLOUD_SETS ⊆ S
    @test (PP.TMAX, PP.WARMUP, PP.EVERY, PP.REPS) == (100_000, 1000, 1, 10)
    @test length(1:PP.DT:(PP.TMAX - PP.WARMUP + 1)) == 1981   # "1980 points" (p. 11)
    @test first(PP.DELTA_LAGS) == 1 && 10 in PP.DELTA_LAGS && last(PP.DELTA_LAGS) == 10_000
    @test PP.DT .* extrema(PP.FIT_LAGS) == (50, 10_000)
end

@testitem "Fortuna polarization protocol: the stationary series of one run" setup = [
    FortunaPolarizationProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    # R = 10, L = 20: the nucleus walks +1 site per MCS in x across the seam; the
    # lamellipodium sits 3 sites behind it (so across the seam at times); no lamellipodium
    # at t = 1001, and no lamellipodium–cytoplasm contact at t = 1002
    n = 1010
    t = collect(0:(n - 1))
    nx = mod.(1.0 .+ t, 20)
    rec = (
        t, nx, ny = fill(5.0, n), lx = mod.(nx .- 3, 20), ly = fill(5.0, n),
        Πx = fill(0.5, n), Πy = fill(0.0, n), vl = [k == 1002 ? 0.0 : 1.0 for k in 1:n],
        lam_cyto = [k == 1003 ? 0.0 : 1.0 for k in 1:n],
    )
    s = PP.stationary(rec, 10, 20)
    @test s.t == 1000:1009
    @test all(k -> s.track[k + 1][1] - s.track[k][1] ≈ 0.1, 1:9)   # unwrapped, units of R
    @test s.Π.CN_N[1] == (0.05, 0.0)
    @test collect(s.Π.L_N[1]) ≈ [-0.3, 0.0]                                # minimum image
    @test collect(s.Π.L_CN[1]) ≈ [-0.35, 0.0]
    @test all(isnan, s.Π.L_N[2]) && all(isnan, s.Π.L_CN[2])
    @test s.detached ≈ 1 / 10
    @test PP.stationary(rec, 10, 20; warmup = 1005).t == 1005:1009
    @test_throws ArgumentError PP.stationary(rec, 10, 20; warmup = 2000)
    sparse = map(c -> c isa Vector ? c[1:2:end] : c, rec)
    @test_throws ArgumentError PP.stationary(sparse, 10, 20)
end

@testitem "Fortuna polarization protocol: the analysis of one set on Fürth tracks" setup = [
    FortunaPolarizationProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    # Table 2's R = 15, φ = 0.10, λ_F = 150: S = 9.68e-3, P = 6878 MCS, D = 2.83e-4 R²/MCS
    S, P, D = 9.68e-3, 6878.0, 2.83e-4
    truth = PP.A.optimal_interval(S).Δτ
    runs = [
        PP.stationary(synthetic_run(StableRNG(100 + k); S, D, P), 15, 120) for k in 1:10
    ]
    a = PP.analyze_set(runs)
    r = a.row
    @test r.resolved && r.n == 10
    @test abs(r.dtau / truth - 1) < PP.DTAU_BAND
    @test r.lag == round(Int, r.dtau * r.P)
    @test r.pi ≈ 2 / 15                                       # |Π| = 2 sites, in units of R
    @test 0.5 <= PP.argmax_delta(a.curves, :xi_CN_N) / r.dtau <= 2   # Fig 4
    @test r.xi_CN_N > 1 && r.detached == 0
    c1, c10 = (a.curves[findfirst(c -> c.lag == l, a.curves)] for l in (1, 10))
    @test abs(c1.upar - c10.upar) <= PP.UPAR_BAND * abs(c10.upar)   # Fig 7D
    @test c1.u > 2 * c10.u                                          # Fig 3B
    @test abs(r.dtau_slope / truth - 1) < PP.DTAU_BAND
    @test length(a.msd) == 200 && length(a.cloud) > 19_000
    @test all(c -> abs(c.theta) <= π, a.cloud)
    # negative control: the polarization ignores the motion
    rr = [
        PP.stationary(synthetic_run(StableRNG(900 + k); S, D, P, mode = :random), 15, 120)
            for k in 1:10
    ]
    b = PP.analyze_set(rr).row
    @test abs(b.xi_CN_N) < 0.05 && abs(b.upar) < 0.05 * abs(r.upar)
end

@testitem "Fortuna polarization protocol: the verdict rules on hand rows" setup = [
    FortunaPolarizationProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    # every R = 15 set: ⟨|Π|⟩ falls with φ, u rises with ⟨|Π|⟩, ε and σθ fall with it
    function row(φ; dtau = 0.1, xi = (3.0, 1.0, 1.0))
        pi = 1 - φ
        return (;
            S = 0.01, dtau, pi, u = 2pi, eps = 1 / pi, sigma = φ,
            xi_CN_N = xi[1], xi_L_CN = xi[2], xi_L_N = xi[3],
        )
    end
    curve(dtau) = [
        (;
            lag = l, delta = l * 1.0e-4, u = 10 / sqrt(l), upar = 1.0,
            xi_CN_N = -abs(log(l * 1.0e-4 / dtau)), xi_L_CN = 0.0, xi_L_N = 0.0,
        )
            for l in PP.DELTA_LAGS
    ]
    sets = [s for s in PP.SETS if s[1] == 15]
    good() = (
        Dict(s => row(s[2]; dtau = get(PP.PAPER_DTAU, s, 0.1)) for s in sets),
        Dict(s => curve(get(PP.PAPER_DTAU, s, 0.1)) for s in sets),
    )
    rows, curves = good()
    V = Dict(v.id => v for v in PP.verdicts(rows, curves))
    gating = [v for v in values(V) if v.kind === :row]
    @test length(gating) == 2 + 2 + 6 + 2 * 12
    @test all(v -> v.ok, gating)
    @test V["trend/R15/u_vs_pi"].value == 3
    @test !haskey(V, "trend/R10/u_vs_pi")                    # missing sets give no rows
    # controls: each rule fails when its input is broken
    rows[PP.FIG4_POLARIZED] = row(0.1; dtau = 0.048 * 1.4)
    rows[PP.FIG4_WEAK] = row(0.3; dtau = 0.672, xi = (1.0, 2.0, 1.0))
    curves[PP.FIG4_POLARIZED] = curve(0.048 * 1.4 * 3)
    for λ in (150, 175)                                       # two of three curves flip
        rows[(15, 0.05, λ)] = merge(rows[(15, 0.05, λ)], (; u = 0.0, sigma = 1.0))
    end
    cs = curves[(15, 0.2, 175)]
    broken(c) = c.lag == 1 ? merge(c, (; upar = 1.2, u = 0.1)) : c
    curves[(15, 0.2, 175)] = broken.(cs)
    W = Dict(v.id => v for v in PP.verdicts(rows, curves))
    @test !W["dtau/R15/φ0.1/λ200"].ok && W["dtau/R15/φ0.3/λ150"].ok
    @test !W["xi_peak/R15/φ0.1/λ200"].ok
    @test W["xi_best/R15/φ0.1/λ200"].ok && W["xi_weak/R15/φ0.3/λ150/xi_CN_N"].ok
    @test !W["trend/R15/u_vs_pi"].ok && !W["trend/R15/u_vs_phi"].ok
    @test !W["trend/R15/sigma_vs_pi"].ok && W["trend/R15/pi_vs_phi"].ok
    @test !W["upar/R15/φ0.2/λ175"].ok && !W["udiv/R15/φ0.2/λ175"].ok
    @test W["upar/R15/φ0.2/λ150"].ok
    @test PP.kendall([1, 2, 3, 4], [4, 3, 2, 1]) == -1
    @test PP.kendall([1, 2, 3, 4], [1, 2, 3, 4]) == 1
end
