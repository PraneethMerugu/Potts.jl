# The protocol of the polarization study (Thomas et al. 2022, Physica A 587:126511) on the
# Fortuna model: the run set, seeds, cadence, the analysis and every band, fixed before the
# runs. `run_polarization.jl` makes the tracks, `analyze_polarization.jl` reduces them to
# the record and its verdicts with this file, and
# `test/reproductions/14_fortuna_polarization_protocol_tests.jl` checks the rules here on
# synthetic data.
#
# Model: `FortunaMigration(; factin_source = :all_lamellipodium)` (Eq 9: the F-actin
# source on every lamellipodium site) from `fortuna_layout(R, sys; nucleus = :cube)` (p. 8:
# "a spherical cell with no lamellipodium engulfing a cubic nucleus resting over the
# substrate"; the 6³ cube of the authors' code). Every other parameter is as in the
# Fortuna reproduction (p. 8: "as in Ref. [9]"), c included: the runner takes the c that
# the Fortuna calibration chose (`--c`).
#
# Run set (p. 8): λ_F ∈ {150, 175, 200} × φ ∈ {0.05, 0.10, 0.20, 0.30} × R ∈ {10, 15, 20},
# 36 sets (`SETS`), 10 replicates of 10⁵ MCS, every MCS recorded. Seed of replicate k of
# set i: 1_420_000_000 + 1000i + k. The main text is R = 15; R = 10 and 20 are in the
# supplement, so their rows are info.
#
# Shared rules:
# - Stationary part: t ≥ 1000 MCS (p. 8: "we have waited 1000 MCS before recording").
# - Tracked point ("the cell position" ρ, Eq 13): the nucleus center of mass in xy,
#   periodic-unwrapped, over R, the point Fortuna et al. fitted S, P and D on (their S1
#   §S3; Fig 5 uses those S values). The paper does not name it. The CN track,
#   r_CN = r_N + Π_CN−N (from nx, ny, Πx, Πy; not the cx, cy columns, which are the
#   cytoplasm centroid), gives u_∥ as an info column (`upar_cn1`, `upar_cn10`),
#   because Π_CN−N contains −r_N and short-time nucleus jitter enters u_∥ on the nucleus
#   track.
# - Fit: the modified Fürth fit of the Fortuna protocol, `furth_fit(50 .* (1:200), m;
#   method = :lsq)`, m the replicate-mean MSD of the stationary track sampled every 50
#   MCS (1981 samples; "1980 points" per trajectory, p. 11). `:paper` is info.
# - Spread of Δτ_opt (`dtau_logsd`): the standard deviation of log Δτ_opt over `BOOT_B`
#   bootstrap resamples of the replicates (each resample refits the mean of its replicate
#   MSDs), seed `BOOT_SEED`.
# - Natural units (Eq 4): τ = t/P, ρ = r/√(2DP/(1 − S)) with the set's fit. Π in units of
#   R (Figs 6–7: "in units of cell radius").
# - Δτ_opt = `optimal_interval(S).Δτ` (Eq 12); its lag is round(Δτ_opt P) MCS, at least 1.
# - Polarizations (Eq 10), xy, minimum image: Π_CN−N (the `Πx`, `Πy` observables, the
#   paper's choice, p. 11), Π_L−N = r_L − r_N and Π_L−CN = Π_L−N − Π_CN−N. A sample
#   without a lamellipodium has NaN for the last two.
# - Statistics (`polarization_statistics`): every window that starts in the stationary part
#   and ends by 10⁵ MCS, pooled over the replicates. ξ uses the unsigned angle θ ∈ [0, π]
#   (so ⟨sin θ⟩ > 0), σθ the signed one. u_∥ is Eq 16 as printed, Π·u, not divided by |Π|.
# - A set has a resolved fit if S, P, D are finite, 0 < S < 1, P > 0, D > 0. A set without
#   one has no Δτ_opt: its gating rows fail and its δ curves are still written.
#
# Figures and record columns (one row per set in sets.tsv, one per set and δ in
# curves.tsv):
#
# | Figure | Plots | Record |
# |---|---|---|
# | 3A | ⟨|Δρ|²⟩ against Δτ in natural units, with Eq 4 at the fit | msd.tsv, sets.tsv S P D |
# | 3B | ⟨u⟩_δ against δ (Eq 13) | curves.tsv u |
# | 4 | ξ_β(δ) for CN−N, L−CN, L−N at (15, 0.10, 200) and (15, 0.30, 150) | curves.tsv xi_* |
# | 5 | Δτ_opt and α_opt against S (math; the tests check it) | sets.tsv dtau alpha |
# | 6A, 6B | ⟨u(Δτ_opt)⟩ and ε against ⟨|Π_CN−N|⟩/R, R = 15 | sets.tsv u eps pi |
# | 6C | ⟨u(Δτ_opt)⟩ against φ | sets.tsv |
# | 6D | u(Δτ_opt) against |Π_CN−N| per sample, (15, 0.05, 200) and (15, 0.30, 150) | clouds.tsv.gz |
# | 7A | σθ_CN−N at Δτ_opt against ⟨|Π_CN−N|⟩ (inset: θ per sample) | sets.tsv sigma, clouds |
# | 7B, 7C | ⟨|Π_CN−N|⟩ and σθ against φ | sets.tsv |
# | 7D | ⟨u_∥,CN−N⟩_δ against δ | curves.tsv upar |
# | S1–S18 | the same at R = 10 and 20 | the same files |
#
# Verdict rows (verdicts.tsv; `kind` is `row` for a gating row, `info` otherwise):
#
# | Row | Target | Source | Band |
# |---|---|---|---|
# | `dtau/R15/φ0.1/λ200` | Δτ_opt = 0.048 | Fig 4 | the Δτ band below |
# | `dtau/R15/φ0.3/λ150` | Δτ_opt = 0.672 | Fig 4 | the Δτ band below |
# | `S/R15/φ0.3/λ150` | S = 9.46e-2 | p. 10 | info |
# | `xi_peak/R15/φ0.1/λ200` | ξ_CN−N(δ) peaks near Δτ_opt | Fig 4 | argmax over δ within ×2 of Δτ_opt |
# | `xi_best/R15/φ0.1/λ200` | Π_CN−N is the strongest correlator at Δτ_opt | Fig 4 caption | ξ_CN−N > ξ_L−CN and > ξ_L−N |
# | `xi_weak/R15/φ0.3/λ150` | no definition peaks near Δτ_opt | Fig 4 | info: the three argmax / Δτ_opt |
# | `trend/R15/<name>` | the six trends of Figs 6–7 (`TRENDS`), over φ for each λ_F | Figs 6A–C, 7A–C | the sign holds on all 3 λ_F curves |
# | `upar/R15/φ…/λ…` | ⟨u_∥⟩_δ converges as δ → 0 | Fig 7D | Δ = |u_∥(1) − u_∥(10)| ≤ 0.10 |u_∥(10)|, or Δ < its replicate standard error (δ in MCS) |
# | `upar_cn/R15/φ…/λ…` | the same on the CN track | review | info: the relative change |
# | `udiv/R15/φ…/λ…` | ⟨u⟩_δ diverges as δ → 0 | Fig 3B | u(1 MCS) > u(10 MCS) |
# | `trend/R10/…`, `trend/R20/…` | the same trends | Figs S7, S14, S15 | info |
#
# A trend's sign is the sign of Kendall's τ over the four φ points of one λ_F curve. The
# spec asks for "the same monotonic trends"; the sign of τ is weaker than strict
# monotonicity (one swapped pair still passes), a deliberate relaxation (D-331).
#
# The Δτ band: pass if |log(Δτ_ours / Δτ_paper)| ≤ 1.96 √(dtau_logsd² n/(n − 1) + σ_ref²).
# The first term is our fit's spread (the bootstrap, corrected for n replicates), the
# second the paper's: σ_ref (`DTAU_REF_SD`) is the standard deviation of log Δτ_opt of one
# fit of the ideal modified Fürth process at the set's Table 2 S, P, D with this sampling
# (200 StableRNG seeds, 5001–5200): 0.187 at (15, 0.10, 200) and 0.151 at (15, 0.30, 150).
# On 200 pairs of independent ideal fits the band fails 5.5 % and 7.5 % of the time
# (0 % against the true value); a Δτ off by a factor 2 passes 16.5 % and 2 %.
#
# Record schema (TSV, one header line):
#   sets.tsv     set R phi lambda n S P D resolved dtau alpha dtau_logsd lag pi u eps
#                sigma xi_CN_N xi_L_CN xi_L_N upar upar1 upar10 upar_dse upar_cn1
#                upar_cn10 dtau_slope detached
#                (upar1, upar10: u_∥ at δ = 1 and 10 MCS; upar_dse: the standard error
#                of their difference over the replicates; upar_cn*: on the CN track)
#   curves.tsv   set lag delta u upar xi_CN_N xi_L_CN xi_L_N
#   msd.tsv      set lag msd (lag in MCS, MSD in R²)
#   clouds.tsv.gz set rep t pi u theta (the 50-MCS grid; t of the window start)
#   verdicts.tsv id kind value band result
module FortunaPolarizationProtocol

using Potts, PottsModels
using PottsModels.Analysis: Analysis
using StableRNGs: StableRNG
using Statistics: mean, std
const A = Analysis

# ------------------------------------------------------------------------------------------
# Constants

const TMAX = 100_000                                 # run length (p. 8)
const WARMUP = 1000                                  # MCS before the stationary part (p. 8)
const EVERY = 1                                      # MCS per recorded sample (p. 7)
const REPS = 10                                      # replicates per set (p. 8)
const DT = 50                                        # MCS per MSD sample (the Fürth fit)
const FIT_LAGS = 1:200                               # samples: 50 … 10⁴ MCS
const DELTA_LAGS = unique(round.(Int, exp10.(range(0, 4; length = 41))))   # δ grid, MCS
const BETAS = (:CN_N, :L_CN, :L_N)
const SETS = [
    (R, φ, λ) for R in (15, 10, 20) for φ in (0.05, 0.1, 0.2, 0.3) for λ in (150, 175, 200)
]
seed(i, k) = 1_420_000_000 + 1000i + k
set_id(s) = "R$(s[1])/φ$(s[2])/λ$(s[3])"
const FIG4_POLARIZED = (15, 0.1, 200)
const FIG4_WEAK = (15, 0.3, 150)
const PAPER_DTAU = Dict(FIG4_POLARIZED => 0.048, FIG4_WEAK => 0.672)   # Fig 4 caption
const PAPER_S_WEAK = 9.46e-2                                           # p. 10
const DTAU_REF_SD = Dict(FIG4_POLARIZED => 0.187, FIG4_WEAK => 0.151)   # the Δτ band
const BOOT_B = 200                                   # bootstrap resamples of Δτ_opt
const BOOT_SEED = 1_420_999_000
const UPAR_BAND = 0.1
const UPAR_SE_MULT = 1.0                             # the u_∥ band's SE multiplier (P6)
const CLOUD_SETS = ((15, 0.05, 200), (15, 0.3, 150))                   # Fig 6D, 7A inset
# name => (x column, y column, expected sign of Kendall's τ)
const TRENDS = (
    u_vs_pi = (:pi, :u, 1), eps_vs_pi = (:pi, :eps, -1), u_vs_phi = (:phi, :u, -1),
    sigma_vs_pi = (:pi, :sigma, -1), pi_vs_phi = (:phi, :pi, -1),
    sigma_vs_phi = (:phi, :sigma, 1),
)

# ------------------------------------------------------------------------------------------
# The problem

system(R, φ) = FortunaMigration(;
    name = :fortuna, lattice = fortuna_lattice(R, φ), factin_source = :all_lamellipodium,
)
start(R, sys) = fortuna_layout(R, sys; nucleus = :cube)
function problem(R, φ, λ; c, seed, T = TMAX, sys = system(R, φ), layout = start(R, sys))
    op = [layout; :R => Float64(R); :φ_l => Float64(φ); :λ_F => Float64(λ); :c => Float64(c)]
    return PottsProblem(sys, op, (0, T); seed, field_solver = ExplicitEuler(substeps = 1))
end

# ------------------------------------------------------------------------------------------
# One run: the stationary series

minimum_image(d, L) = d - L * round(d / L)

"""
    stationary(rec, R, L; warmup = WARMUP) -> (; t, track, Π, detached)

The stationary part of one recorded run (`t ≥ warmup`, every MCS): the nucleus track and
the CN track (`cn_track`) in units of R (xy, unwrapped) and the three polarizations in
units of R. The CN track is r_N + Π_CN−N. `rec` has the columns t, nx, ny, lx, ly, Πx,
Πy, vl and lam_cyto.
`detached` is the fraction of samples with a lamellipodium but no lamellipodium–cytoplasm
contact.
"""
function stationary(rec, R, L; warmup = WARMUP)
    w = findall(>=(warmup), rec.t)
    isempty(w) && throw(ArgumentError("stationary: no sample at t ≥ $warmup"))
    t = rec.t[w]
    all(==(EVERY), diff(t)) || throw(ArgumentError("stationary: the samples are not every MCS"))
    unwrap(x, y) = [p ./ R for p in A.unwrap_track(collect(zip(x[w], y[w])), (L, L), true)]
    track = unwrap(rec.nx, rec.ny)
    cn_track = unwrap(rec.nx .+ rec.Πx, rec.ny .+ rec.Πy)       # r_CN = r_N + Π_CN−N
    cn = [(x, y) ./ R for (x, y) in zip(rec.Πx[w], rec.Πy[w])]
    ln = map(w) do j
        rec.vl[j] > 0 || return (NaN, NaN)
        return (minimum_image(rec.lx[j] - rec.nx[j], L), minimum_image(rec.ly[j] - rec.ny[j], L)) ./ R
    end
    lcn = [a .- b for (a, b) in zip(ln, cn)]
    detached = count(j -> rec.vl[j] > 0 && rec.lam_cyto[j] == 0, w) / length(w)
    return (; t, track, cn_track, Π = (CN_N = cn, L_CN = lcn, L_N = ln), detached)
end

# ------------------------------------------------------------------------------------------
# One set: fit, natural units, statistics

function fit(Δt, m, method)
    try
        return A.furth_fit(Δt, m; method)
    catch e
        e isa ArgumentError || rethrow()
        return (; S = NaN, D = NaN, P = NaN, method)
    end
end
resolved(f) = all(isfinite, (f.S, f.P, f.D)) && 0 < f.S < 1 && f.P > 0 && f.D > 0
const NAN_STATS = (; u = NaN, ε = NaN, ξ = NaN, σθ = NaN, u_parallel = NaN, n = 0, n_angles = 0)
function stats(Π, tracks, lag, dt)
    lag < length(first(tracks)) || return NAN_STATS
    return A.polarization_statistics(Π, tracks, lag; dt)
end

"""
    dtau_fit(msds, lags; B = BOOT_B, seed = BOOT_SEED) -> (; f, o, logsd)

The fit of the mean of the replicate MSDs `msds` (one vector per replicate, at `lags`
samples of `DT` MCS), its optimal interval `o` and `logsd`, the standard deviation of
log Δτ_opt over `B` bootstrap resamples of the replicates (NaN without a resolved fit or
with fewer than 2 replicates).
"""
function dtau_fit(msds, lags; B = BOOT_B, seed = BOOT_SEED)
    nofit = fit(Float64[], Float64[], :lsq)
    length(lags) >= 4 || return (; f = nofit, o = (; Δτ = NaN, α = NaN), logsd = NaN)
    f = fit(DT .* lags, mean(msds), :lsq)
    resolved(f) || return (; f, o = (; Δτ = NaN, α = NaN), logsd = NaN)
    o = A.optimal_interval(f.S)
    k = length(msds)
    k >= 2 || return (; f, o, logsd = NaN)
    rng = StableRNG(seed)
    v = Float64[]
    for _ in 1:B
        fb = fit(DT .* lags, mean(msds[rand(rng, 1:k, k)]), :lsq)
        resolved(fb) && push!(v, log(A.optimal_interval(fb.S).Δτ))
    end
    return (; f, o, logsd = length(v) >= 2 ? std(v) : NaN)
end

"""
    dtau_ok(d, logsd, n, ref, ref_sd) -> (ok, half_width)

The Δτ band: `|log(d/ref)| ≤ 1.96 √(logsd² n/(n − 1) + ref_sd²)`.
"""
function dtau_ok(d, logsd, n, ref, ref_sd)
    h = 1.96 * sqrt(logsd^2 * n / (n - 1) + ref_sd^2)
    return (isfinite(d) && d > 0 && isfinite(h) && abs(log(d / ref)) <= h, h)
end

"""
    upar_ok(a, b, se) -> Bool

The u_∥ convergence band: `|a − b| ≤ UPAR_BAND |b|` or `|a − b| < UPAR_SE_MULT se`.
Non-finite inputs fail.
"""
upar_ok(a, b, se) = isfinite(a) && isfinite(b) &&
    (abs(a - b) <= UPAR_BAND * abs(b) || (isfinite(se) && abs(a - b) < UPAR_SE_MULT * se))

"""
    analyze_set(runs; B = BOOT_B) -> NamedTuple

Reduce the stationary series of one set's replicates (`stationary` outputs, equal lengths)
to its sets.tsv row, its δ curves, its MSD and its per-sample cloud. `B` is the number of
bootstrap resamples of Δτ_opt.
"""
function analyze_set(runs; B = BOOT_B)
    n = length(first(runs).t)
    all(r -> length(r.t) == n, runs) || throw(ArgumentError("analyze_set: unequal run lengths"))
    g = 1:DT:n                                        # the 50-MCS grid
    lags = filter(<(length(g)), FIT_LAGS)
    msds = isempty(lags) ? [Float64[] for _ in runs] :
        [A.mean_squared_displacement(r.track[g]; lags) for r in runs]
    m = mean(msds)
    (; f, o, logsd) = dtau_fit(msds, lags; B)
    ok = resolved(f)
    lag = ok ? max(1, round(Int, o.Δτ * f.P)) : 0
    scale = ok ? sqrt(2 * f.D * f.P / (1 - f.S)) : 1.0
    dt = ok ? 1 / f.P : 1.0                           # natural units (τ per MCS) if resolved
    ρ = [[p ./ scale for p in r.track] for r in runs]
    ρcn = [[p ./ scale for p in r.cn_track] for r in runs]
    Π(β) = [getfield(r.Π, β) for r in runs]
    # u_∥ at δ = 1 and 10 MCS: pooled, per replicate (the standard error of the change),
    # and on the CN track (info)
    upar(l, tr = ρ) = stats(Π(:CN_N), tr, l, dt).u_parallel
    dk = [
        stats([r.Π.CN_N], [p], 1, dt).u_parallel - stats([r.Π.CN_N], [p], 10, dt).u_parallel
            for (r, p) in zip(runs, ρ)
    ]
    upar_dse = length(dk) >= 2 ? std(dk) / sqrt(length(dk)) : NaN
    at = Dict(β => (ok ? stats(Π(β), ρ, lag, dt) : NAN_STATS) for β in BETAS)
    curves = map(filter(<(n), DELTA_LAGS)) do l
        s = Dict(β => stats(Π(β), ρ, l, dt) for β in BETAS)
        (;
            lag = l, delta = l * dt, u = s[:CN_N].u, upar = s[:CN_N].u_parallel,
            xi_CN_N = s[:CN_N].ξ, xi_L_CN = s[:L_CN].ξ, xi_L_N = s[:L_N].ξ,
        )
    end
    # the fit-free estimate (info): the steepest slope of the every-MCS MSD
    ml = filter(<(n), DELTA_LAGS)
    slope = if ok && length(ml) >= 3
        A.max_slope_interval(ml, A.mean_squared_displacement([r.track for r in runs]; lags = ml)).Δt / f.P
    else
        NaN
    end
    cloud = NamedTuple[]
    if ok && lag < n
        for (k, r) in enumerate(runs)
            for j in g
                j + lag <= n || break
                p = r.Π.CN_N[j]
                u = (ρ[k][j + lag] .- ρ[k][j]) ./ (lag * dt)
                θ = atan(p[1] * u[2] - p[2] * u[1], p[1] * u[1] + p[2] * u[2])
                push!(cloud, (; rep = k, t = r.t[j], pi = hypot(p...), u = hypot(u...), theta = θ))
            end
        end
    end
    pimean = sum(sum(hypot(p...) for p in r.Π.CN_N) for r in runs) / (n * length(runs))
    s = at[:CN_N]
    row = (;
        n = length(runs), S = f.S, P = f.P, D = f.D, resolved = ok, dtau = o.Δτ, alpha = o.α,
        dtau_logsd = logsd, lag, pi = pimean, u = s.u, eps = s.ε, sigma = s.σθ,
        xi_CN_N = s.ξ, xi_L_CN = at[:L_CN].ξ, xi_L_N = at[:L_N].ξ, upar = s.u_parallel,
        upar1 = upar(1), upar10 = upar(10), upar_dse, upar_cn1 = upar(1, ρcn),
        upar_cn10 = upar(10, ρcn), dtau_slope = slope,
        detached = sum(r.detached for r in runs) / length(runs),
    )
    msd = [(; lag = DT * l, msd = mk) for (l, mk) in zip(lags, m)]
    return (; row, curves, msd, cloud)
end

# ------------------------------------------------------------------------------------------
# Verdicts

"""Kendall's τ (the plain pair count, no tie correction) of `x` against `y`."""
function kendall(x, y)
    s, npair = 0, 0
    for i in eachindex(x), j in eachindex(x)
        j > i || continue
        npair += 1
        s += Int(sign((x[i] - x[j]) * (y[i] - y[j])))
    end
    return s / npair
end
argmax_delta(curves, col) = let v = [getfield(c, col) for c in curves], ok = findall(isfinite, v)
    isempty(ok) ? NaN : curves[ok[argmax(v[ok])]].delta
end

"""
    verdicts(rows, curves) -> Vector of (; id, kind, value, band, ok)

The verdict rows of the table above. `rows` maps a set (R, φ, λ) to its sets.tsv row;
`curves` maps a set to its δ curves. A set that is missing (a trial) gives no rows.
"""
function verdicts(rows, curves)
    V = NamedTuple[]
    add!(id, kind, value, band, ok) = push!(V, (; id, kind, value, band, ok))
    for (s, ref) in PAPER_DTAU
        haskey(rows, s) || continue
        r = rows[s]
        ok, h = dtau_ok(r.dtau, r.dtau_logsd, r.n, ref, DTAU_REF_SD[s])
        band = "$(ref) × exp(±$(round(h; digits = 3)))"
        add!("dtau/" * set_id(s), :row, r.dtau, band, ok)
    end
    if haskey(rows, FIG4_WEAK)
        S = rows[FIG4_WEAK].S
        add!("S/" * set_id(FIG4_WEAK), :info, S, "$(PAPER_S_WEAK) (info)", true)
    end
    if haskey(rows, FIG4_POLARIZED)
        r = rows[FIG4_POLARIZED]
        pk = argmax_delta(curves[FIG4_POLARIZED], :xi_CN_N)
        add!(
            "xi_peak/" * set_id(FIG4_POLARIZED), :row, pk / r.dtau, "∈ [1/2, 2]",
            isfinite(pk / r.dtau) && 0.5 <= pk / r.dtau <= 2
        )
        add!(
            "xi_best/" * set_id(FIG4_POLARIZED), :row, r.xi_CN_N - max(r.xi_L_CN, r.xi_L_N),
            "> 0", r.xi_CN_N > r.xi_L_CN && r.xi_CN_N > r.xi_L_N
        )
    end
    if haskey(rows, FIG4_WEAK)
        r = rows[FIG4_WEAK]
        for col in (:xi_CN_N, :xi_L_CN, :xi_L_N)
            pk = argmax_delta(curves[FIG4_WEAK], col)
            add!(
                "xi_weak/" * set_id(FIG4_WEAK) * "/" * string(col), :info, pk / r.dtau,
                "info: argmax/Δτ_opt", true
            )
        end
    end
    for R in (15, 10, 20), (name, (xc, yc, sg)) in pairs(TRENDS)
        good, total = 0, 0
        for λ in (150, 175, 200)
            ss = [(R, φ, λ) for φ in (0.05, 0.1, 0.2, 0.3)]
            all(s -> haskey(rows, s), ss) || continue
            x = [xc === :phi ? s[2] : getfield(rows[s], xc) for s in ss]
            y = [getfield(rows[s], yc) for s in ss]
            all(isfinite, x) && all(isfinite, y) || (total += 1; continue)
            total += 1
            good += sign(kendall(x, y)) == sg
        end
        total == 0 && continue
        add!("trend/R$R/$name", R == 15 ? :row : :info, good, "all 3 λ_F curves", good == 3)
    end
    for (s, r) in rows
        s[1] == 15 || continue
        rel = abs(r.upar1 - r.upar10) / abs(r.upar10)
        add!(
            "upar/" * set_id(s), :row, rel, "≤ 0.10, or Δ < $(UPAR_SE_MULT) SE = $(round(r.upar_dse; sigdigits = 3))",
            upar_ok(r.upar1, r.upar10, r.upar_dse)
        )
        rc = abs(r.upar_cn1 - r.upar_cn10) / abs(r.upar_cn10)
        add!("upar_cn/" * set_id(s), :info, rc, "info: CN track", true)
    end
    for (s, cs) in curves
        s[1] == 15 || continue
        c1 = findfirst(c -> c.lag == 1, cs)
        c10 = findfirst(c -> c.lag == 10, cs)
        (c1 === nothing || c10 === nothing) && continue
        a, b = cs[c1], cs[c10]
        add!("udiv/" * set_id(s), :row, a.u / b.u, "> 1", a.u > b.u)
    end
    return sort(V; by = v -> v.id)
end

end
