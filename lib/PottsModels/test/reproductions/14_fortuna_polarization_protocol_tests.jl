# Reproduction 14, the polarization study of Thomas et al. (2022): the protocol in
# `lib/PottsModels/reproductions/data/14/polarization_protocol.jl` (run set, seeds, the
# analysis and the bands), on synthetic data only (no simulation):
# - the run set, seeds and cadence;
# - the stationary series of one run: warm-up cut, unwrapping, the three polarizations;
# - the whole analysis of one set on tracks with a known modified Fürth MSD whose
#   polarization is the direction of the persistent velocity: the fitted Δτ_opt is within
#   its bootstrap band of the true one, ξ peaks within ×2 of Δτ_opt (Fig 4), u_∥ converges
#   and u diverges as δ → 0 (Figs 3B, 7D); negative control: a polarization that ignores
#   the motion has ξ ≈ 0 and u_∥ ≈ 0;
# - the Δτ band on the ideal modified Fürth process at the two gating sets' Table 2 S, P,
#   D, with the protocol's sampling: σ_ref is the spread of one fit, pairs of independent
#   fits rarely fail the band, and a reference off by ×2.5 mostly fails;
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
# `lead`. As `record_run` does, cx, cy are the cytoplasm centroid r_N + Π (V_C + V_N)/V_C,
# not r_CN = r_N + Π, so a protocol that read them as the CN track would fail.
function synthetic_run(
        rng; S, D, P, R = 15, L = 120, n = 100_001, pol = 2.0, lead = 5.0,
        mode = :velocity
    )
    a, sv, sb = exp(-1 / P), sqrt(D / (2P)), sqrt(D * S / (1 - S))
    v, x = (sv * randn(rng), sv * randn(rng)), (60.0 / R, 60.0 / R)
    rec = (
        t = collect(0:(n - 1)), nx = zeros(n), ny = zeros(n), cx = zeros(n), cy = zeros(n),
        lx = zeros(n), ly = zeros(n), Πx = zeros(n), Πy = zeros(n), vl = ones(n),
        vc = fill(3.0, n), vn = ones(n), lam_cyto = ones(n),
    )
    for k in 1:n
        e = mode === :velocity ? v ./ hypot(v...) : (c = 2π * rand(rng); (cos(c), sin(c)))
        rec.nx[k], rec.ny[k] = mod.(R .* x, L)
        rec.Πx[k], rec.Πy[k] = pol .* e
        rec.lx[k], rec.ly[k] = mod.(R .* x .+ lead .* e, L)
        f = (rec.vc[k] + rec.vn[k]) / rec.vc[k]
        rec.cx[k], rec.cy[k] = 1 .+ mod.(R .* x .+ f .* pol .* e .- 1, L)
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
        t, nx, ny = fill(5.0, n), cx = mod.(nx .+ 2.0, 20), cy = fill(5.0, n),
        lx = mod.(nx .- 3, 20), ly = fill(5.0, n),
        Πx = fill(0.5, n), Πy = fill(0.0, n), vl = [k == 1002 ? 0.0 : 1.0 for k in 1:n],
        lam_cyto = [k == 1003 ? 0.0 : 1.0 for k in 1:n],
    )
    s = PP.stationary(rec, 10, 20)
    @test s.t == 1000:1009
    @test all(k -> s.track[k + 1][1] - s.track[k][1] ≈ 0.1, 1:9)   # unwrapped, units of R
    # the CN track is r_N + Π_CN−N, not the cytoplasm centroid cx, cy
    @test all(k -> collect(s.cn_track[k] .- s.track[k]) ≈ [0.05, 0.0], 1:10)
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
    # Table 2's R = 15, φ = 0.10, λ_F = 150: S = 9.68e-3, P = 6878 MCS, D = 2.83e-4 R²/MCS;
    # 10 replicates of 40 000 MCS and 50 bootstrap resamples (the protocol's 10⁵ MCS and
    # 200 resamples would only cost time here)
    S, P, D = 9.68e-3, 6878.0, 2.83e-4
    n = 40_001
    truth = PP.A.optimal_interval(S).Δτ
    runs = [
        PP.stationary(synthetic_run(StableRNG(100 + k); S, D, P, n), 15, 120) for k in 1:10
    ]
    a = PP.analyze_set(runs; B = 50)
    r = a.row
    @test r.resolved && r.n == 10
    @test 0 < r.dtau_logsd < 0.5
    @test first(PP.dtau_ok(r.dtau, r.dtau_logsd, r.n, truth, 0.0))   # the bootstrap alone
    @test r.lag == round(Int, r.dtau * r.P)
    @test r.pi ≈ 2 / 15                                       # |Π| = 2 sites, in units of R
    @test 0.5 <= PP.argmax_delta(a.curves, :xi_CN_N) / r.dtau <= 2   # Fig 4
    @test r.xi_CN_N > 1 && r.detached == 0
    c1, c10 = (a.curves[findfirst(c -> c.lag == l, a.curves)] for l in (1, 10))
    @test (r.upar1, r.upar10) == (c1.upar, c10.upar)
    @test PP.upar_ok(r.upar1, r.upar10, r.upar_dse)                 # Fig 7D
    @test 0 < r.upar_dse < 0.1 * abs(r.upar10)
    # the CN track is the nucleus plus Π, so its u_∥ adds ⟨Π·ΔΠ⟩/δ (< 0 as Π turns)
    scale, dt = sqrt(2 * r.D * r.P / (1 - r.S)), 1 / r.P
    m = length(first(runs).t) - 10
    turn = sum(
        sum(
            q.Π.CN_N[j][1] * (q.Π.CN_N[j + 10][1] - q.Π.CN_N[j][1]) +
                q.Π.CN_N[j][2] * (q.Π.CN_N[j + 10][2] - q.Π.CN_N[j][2]) for j in 1:m
        )
            for q in runs
    ) / (length(runs) * m * scale * 10dt)
    @test turn < 0 && r.upar_cn10 ≈ r.upar10 + turn
    @test c1.u > 2 * c10.u                                          # Fig 3B
    @test abs(r.dtau_slope / truth - 1) < 0.3
    @test length(a.msd) == 200 && length(a.cloud) > 7000
    @test all(c -> abs(c.theta) <= π, a.cloud)
    # negative control: the polarization ignores the motion
    rr = [
        PP.stationary(
            synthetic_run(StableRNG(900 + k); S, D, P, n, mode = :random), 15, 120
        )
            for k in 1:10
    ]
    b = PP.analyze_set(rr; B = 2).row
    @test abs(b.xi_CN_N) < 0.05 && abs(b.upar) < 0.05 * abs(r.upar)
end

@testitem "Fortuna polarization protocol: the Δτ band on the ideal Fürth process" setup = [
    FortunaPolarizationProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    using Statistics: std
    # the gating sets' Table 2 S, P (MCS), D (R²/MCS); 10 tracks of 1981 samples every
    # 50 MCS, as the protocol samples them
    table2 = Dict(
        PP.FIG4_POLARIZED => (3.93e-4, 23265.0, 5.66e-3),
        PP.FIG4_WEAK => (9.46e-2, 11987.0, 2.59e-5),
    )
    function draw(seed, (S, P, D); B)
        tr = P14.ou_tracks(StableRNG(seed); S, D, P, n = 1981, ntracks = PP.REPS)
        msds = [PP.A.mean_squared_displacement(t; lags = PP.FIT_LAGS) for t in tr]
        return PP.dtau_fit(msds, PP.FIT_LAGS; B, seed = seed + 1)
    end
    for (s, (S, P, D)) in table2
        truth = PP.A.optimal_interval(S).Δτ
        # σ_ref is the spread of log Δτ_opt of one fit (its standard error here is ≈ 10 %)
        one = [draw(5000 + k, (S, P, D); B = 0).o.Δτ for k in 1:60]
        @test isapprox(std(log.(one)), PP.DTAU_REF_SD[s]; rtol = 0.25)
        # pairs of independent fits: "ours" with a 30-resample bootstrap, the "paper" one
        # fit; the expected failure rate is 5.5 % (polarized) and 7.5 % (weak), so
        # 4 or more failures of 12 has a probability of about 1 %
        fail, fail_truth, fail_off = 0, 0, 0
        K = 12
        for k in 1:K
            ours = draw(7000 + 10k, (S, P, D); B = 30)
            paper = draw(8000 + 10k, (S, P, D); B = 0).o.Δτ
            sd = PP.DTAU_REF_SD[s]
            band(ref) = first(PP.dtau_ok(ours.o.Δτ, ours.logsd, PP.REPS, ref, sd))
            fail += !band(paper)
            fail_truth += !band(truth)
            fail_off += !band(2.5 * truth)                 # negative control
        end
        @test fail <= 3 && fail_truth <= 1
        @test fail_off >= K - 2
    end
end

@testitem "Fortuna polarization protocol: the verdict rules on hand rows" setup = [
    FortunaPolarizationProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    # every R = 15 set: ⟨|Π|⟩ falls with φ, u rises with ⟨|Π|⟩, ε and σθ fall with it
    function row(φ; dtau = 0.1, logsd = 0.05, xi = (3.0, 1.0, 1.0), upar = (1.0, 1.0, 0.01))
        pi = 1 - φ
        return (;
            n = 10, S = 0.01, dtau, dtau_logsd = logsd, pi, u = 2pi, eps = 1 / pi,
            sigma = φ, xi_CN_N = xi[1], xi_L_CN = xi[2], xi_L_N = xi[3], upar1 = upar[1],
            upar10 = upar[2], upar_dse = upar[3], upar_cn1 = 1.0, upar_cn10 = 2.0,
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
    cn = V["upar_cn/R15/φ0.2/λ175"]
    @test cn.kind === :info && cn.value ≈ 0.5
    @test !haskey(V, "trend/R10/u_vs_pi")                    # missing sets give no rows
    # controls: each rule fails when its input is broken
    rows[PP.FIG4_POLARIZED] = row(0.1; dtau = 0.048 * 2, xi = (1.0, 2.0, 1.0))
    rows[PP.FIG4_WEAK] = row(0.3; dtau = 0.672 * 2, logsd = 0.4)   # a wide bootstrap
    curves[PP.FIG4_POLARIZED] = curve(0.048 * 2 * 3)
    # one of three curves flips: u and σθ at λ_F = 150, ε at λ_F = 175
    rows[(15, 0.05, 150)] = merge(rows[(15, 0.05, 150)], (; u = 0.0, sigma = 1.0))
    rows[(15, 0.05, 175)] = merge(rows[(15, 0.05, 175)], (; eps = 10.0))
    # u_∥: a 20 % change beyond its standard error fails; within it, or 10 %, passes
    rows[(15, 0.2, 175)] = row(0.2; upar = (1.2, 1.0, 0.05))
    rows[(15, 0.2, 150)] = row(0.2; upar = (1.2, 1.0, 0.3))
    rows[(15, 0.2, 200)] = row(0.2; upar = (0.03, 0.01, 0.05))
    rows[(15, 0.1, 150)] = row(0.1; upar = (1.09, 1.0, 0.0))
    cs = curves[(15, 0.2, 175)]
    curves[(15, 0.2, 175)] = [c.lag == 1 ? merge(c, (; u = 0.1)) : c for c in cs]
    W = Dict(v.id => v for v in PP.verdicts(rows, curves))
    @test !W["dtau/R15/φ0.1/λ200"].ok && W["dtau/R15/φ0.3/λ150"].ok
    @test !W["xi_peak/R15/φ0.1/λ200"].ok && !W["xi_best/R15/φ0.1/λ200"].ok
    @test W["xi_weak/R15/φ0.3/λ150/xi_CN_N"].ok
    @test W["trend/R15/u_vs_pi"].value == 2
    for name in (:u_vs_pi, :u_vs_phi, :sigma_vs_pi, :sigma_vs_phi, :eps_vs_pi)
        @test !W["trend/R15/$name"].ok
    end
    @test W["trend/R15/pi_vs_phi"].ok
    @test !W["upar/R15/φ0.2/λ175"].ok && !W["udiv/R15/φ0.2/λ175"].ok
    @test W["upar/R15/φ0.2/λ150"].ok && W["upar/R15/φ0.2/λ200"].ok
    @test W["upar/R15/φ0.1/λ150"].ok
    # a non-finite gating value gives a FAIL row, never a dropped one
    rows, curves = good()
    rows[PP.FIG4_POLARIZED] = merge(rows[PP.FIG4_POLARIZED], (; dtau = NaN, xi_CN_N = NaN))
    rows[(15, 0.2, 175)] = merge(rows[(15, 0.2, 175)], (; upar10 = NaN))
    rows[(15, 0.3, 200)] = merge(rows[(15, 0.3, 200)], (; u = NaN))
    cs = curves[(15, 0.2, 150)]
    curves[(15, 0.2, 150)] = [c.lag == 10 ? merge(c, (; u = NaN)) : c for c in cs]
    N = Dict(v.id => v for v in PP.verdicts(rows, curves))
    @test count(v -> v.kind === :row, values(N)) == length(gating)
    for id in (
            "dtau/R15/φ0.1/λ200", "xi_peak/R15/φ0.1/λ200", "xi_best/R15/φ0.1/λ200",
            "upar/R15/φ0.2/λ175", "trend/R15/u_vs_pi", "udiv/R15/φ0.2/λ150",
        )
        @test !N[id].ok
    end
    @test !PP.upar_ok(1.0, NaN, 1.0) && !PP.upar_ok(NaN, 1.0, 1.0)
    @test PP.kendall([1, 2, 3, 4], [4, 3, 2, 1]) == -1
    @test PP.kendall([1, 2, 3, 4], [1, 2, 3, 4]) == 1
end
