# The protocol of the Fortuna reproduction (Fortuna et al. 2020, Biophys. J. 118:2801):
# every band, seed, replicate count, lag window and run length, fixed before the runs.
# `run_full.jl` makes the record with it, `evaluate.jl` and the test file
# `test/reproductions/14_fortuna_protocol_tests.jl` check the record with it.
#
# Short qualitative tier (the `qtier` stage of run_full.jl; < 1 h on 3+ threads). The
# check names below are the labels in qtier.toml:
#
# | Check | Rule | Over |
# |---|---|---|
# | `lamellipodium_by_50` | R = 10, φ_l = 0.05, λ_F = 150, 3 replicates × 2 × 10⁴ MCS: the lamellipodium is alive at a sample ≤ MCS 50 | per replicate |
# | `polarization` | the same runs: |Π_CN−N| over MCS 5000–20000 has time mean > 1 site | per replicate |
# | `polarization_start` | |Π_CN−N| at t = 0 is 0 (the nucleus ball is concentric with the cytoplasm ball) | exact |
# | `mean_displacement` | the mean nucleus displacement over the 3 replicates > 2R | mean of 3 |
# | `confined_set` | R = 15, φ_l = 0.30, λ_F = 125 moves < 2R in 2 × 10⁴ MCS (Fig 6, confined) | mean of 3 |
# | `no_drive_control` | λ_F = 0 at the first set moves < 1/3 of its mean displacement (mechanism control) | mean of 3 |
# | `volume_window` | volumes in the first set: time mean of |V − V_target|/V_target over MCS 5000–20000 ≤ 2 % per compartment | mean of 3 |
# | `timing` | ns per copy attempt at R = 10, 15, 20 over 1000 MCS | info |
# | `c_calibration` | c = 0.1; if `volume_window` fails, the first set again at c = 0.3, then 1.0; the first passing c is the calibrated c | first pass in order |
#
# The paper does not state c. The c calibration uses the volume check only, never Figs 5–6
# or Table 2. `mean_displacement` reads the mean of 3 replicates: on synthetic tracks at the
# first set's Table 2 row, one replicate is ≤ 2R in 4.8 % of runs, the mean of 3 in
# 0.045 %.
#
# FULL tier: 68 sets (`SETS`), 10 replicates each and 30 for (15, 0.30, 160) (Fig 9): 700
# runs of 10⁵ MCS. Seed of replicate k of set i: 1_400_000_000 + 1000i + k. Recorded every
# MCS for the 36 sets of λ_F ∈ {150, 175, 200} and every 10 MCS otherwise. The row ids of
# verdicts.tsv begin with the names below.
#
# | Row | Target | Source | Band | Gating |
# |---|---|---|---|---|
# | `volumes/` | volumes at target in steady state | p.2806 | per set: replicate mean of the time mean of |ΔV|/V_t over MCS 5000–10⁵ ≤ 2 %, each compartment | 68 rows |
# | `regime_map` | Fig 6 regime map, R = 15 (`REGIME_MAP`) | Fig 6 | ≥ 16 of 20 panels match | 1 row (+ 20 info) |
# | `fig5_displacement/` | Fig 5 displacement after 10⁵ MCS (nucleus xy / R), 59 points | Fig 5 (fig5.tsv) | |ours − paper| ≤ 2 SE_paper, or ours/paper ∈ [1/2, 2] | per point |
# | `table2/` | Table 2 S, P, D, 40 rows | Table 2 (table2.tsv) | S/S_p ∈ [1/2, 2]; |P/P_p − 1| ≤ 0.5; D/D_p ∈ [1/2, 2]; a set not migrating fails as a regime mismatch | `:lsq` per row; `:paper` only on ≥ 30-replicate sets |
# | `table2/` (loose rows) | four rows whose printed 2DP/(1 − S) disagrees with S, P, D (`LOOSE_ROWS`) | Table 2 | S as `table2/`; P/P_p ∈ [1/4, 3]; D/D_p ∈ [1/4, 4] | as `table2/` |
# | `table2/` (D info row) | R = 10, φ 0.20, λ 175: D printed 3.60E−4, likely ×10 too small (`D_INFO_ROWS`) | Table 2 | S, P as `table2/`; D info | as `table2/` |
# | `persistence/` | S = 0.02 at (15, 0.30, 160), 30 replicates | p.2809; Table 2 | S ∈ [0.01, 0.04]; bootstrap SE(S) ≤ 0.005; collapse RMS ≤ 0.2 | both methods |
# | `collapse/` | collapse onto Eq 2 | Fig 7 | RMS of log m − log Eq 1(fit) ≤ 0.1 on the log lags, each migrating set | `:lsq`; `:paper` info on 10-replicate sets |
# | `dfast/` | D_fast = 0.127 R⁻² | Fig 11 | geometric mean of D_fast·R⁴ over migrating, resolved fits within ±30 % | `:lsq`; `:paper` info |
# | `wall_time` | wall time against CompuCell3D's 200 min per R = 15 run | p.2810 | — | info |
#
# Shared rules:
# - The tracked point is the nucleus center of mass in xy, periodic-unwrapped, over R. MSD
#   in R², D in R²/MCS. MSD on the whole track sampled every 50 MCS (2001 samples),
#   overlapping windows, replicates with equal weight, at `LAGS` (samples).
# - Fits: `furth_fit(50 .* (1:200), m; method)` with the default `range`, `short` and
#   `offset`, for both `:paper` and `:lsq`. The synthetic oracle below fixed the window
#   (K = 200 samples: at K = 400 `:paper`'s SD of S is 0.028 at S = 0.0212).
# - On 10-replicate sets `:lsq` gates `table2/`, `collapse/` and `dfast/`, and `:paper` is
#   info with the spread of its S over per-replicate fits; on ≥ 30-replicate sets
#   (`persistence/`) both gate. At N = 10 `:paper` puts S inside the ×2 band of `table2/`
#   on 8–12 of 16 oracle seeds, `:lsq` on 16 of 16.
# - A fit is resolved if S, P, D are finite, 0 ≤ S < 1, P > 0 and D > 0. An unresolved fit
#   fails where its method gates and is info elsewhere; it never errors.
# - Regime: a replicate is detached if `lam_cyto` = 0 at a 50-MCS sample after MCS 10 while
#   the lamellipodium is alive; a set is detachment if ≥ half its replicates detach; else
#   confined if its mean displacement < 2R (p.2807); else migrating.
#
# Record schema (TSV, one header line, tab separated):
#   sets.tsv     set R phi lambda n every L Lz regime detach disp_mean disp_se
#   runs.tsv     set rep seed R phi lambda every disp detached lam_deaths lid_touch dv_cyto
#                dv_nuc dv_lam wall_s
#   msd_runs.tsv set rep m_<lag>… (one column per lag of LAGS, R²)
#   msd.tsv      set lag_mcs msd (the replicate mean)
#   fits.tsv     set method S P D D_fast v_eff se_S excluded offset (migrating sets;
#                `excluded`: fit lags with m − offset ≤ 0, left out of the collapse; −1 if
#                unresolved)
#   oracle.tsv   method P S_true seed S D P_fit
#   scal.tsv     c cyto nucleus lam pass (the c calibration, in the order tried)
#   verdicts.tsv id kind value band result
#   deviations.tsv (optional) id ours paper cause question
#   provenance.toml (a 40-hex commit, dirty = false, julia, threads, machine, cpu, c)
# Reference transcriptions (inputs; see test/reproductions/data/14/README.md): table2.tsv
# (R phi lambda S P D, 40 rows) and fig5.tsv (R phi lambda disp se, 59 points).
module FortunaProtocol

using Test: @test, @test_broken
using Potts, PottsModels
using PottsModels.Analysis: Analysis
using StableRNGs: StableRNG
using Statistics: mean, median, std
using TOML: TOML
const A = Analysis
const DATA = @__DIR__
const REFS = joinpath(pkgdir(PottsModels), "test", "reproductions", "data", "14")

# ------------------------------------------------------------------------------------------
# Constants

const DT = 50                                       # MCS per MSD sample
const TMAX = 100_000                                # run length (Figs 5–6)
const FIT_LAGS = 1:200                              # samples: Δt = 50 … 10⁴ MCS
const LOG_LAGS = unique(round.(Int, exp10.(range(0, 3; length = 60))))   # 49 distinct
const LAGS = sort(union(FIT_LAGS, LOG_LAGS))
const FIT_DT = Float64.(DT .* FIT_LAGS)
const METHODS = (:paper, :lsq)
const BOOT = (n = 1000, seed = 14_000)              # bootstrap over replicates
const VOLUME_FROM = 5000                            # volume window start (MCS)
const C_GRID = (0.1, 0.3, 1.0)                      # c calibration order
const KIND = (cytoplasm = 3, lamellipodium = 4, nucleus = 5)   # kind codes (@kinds order)
const SETS = let s = NTuple{3, Any}[]
    for φ in (0.05, 0.1, 0.2, 0.3), λ in (100, 125, 150, 175, 200)
        push!(s, (10, φ, λ))
    end
    push!(s, (10, 0.05, 75))
    for φ in (0.05, 0.1, 0.2, 0.3), λ in (100, 125, 150, 175, 200, 250)
        push!(s, (15, φ, λ))
    end
    append!(s, [(15, 0.3, 160), (15, 0.3, 165), (15, 0.3, 170)])
    for φ in (0.05, 0.1, 0.2, 0.3), λ in (100, 125, 150, 175, 200)
        push!(s, (20, φ, λ))
    end
    [(Int(R), Float64(φ), Int(λ)) for (R, φ, λ) in s]
end
const PERSISTENCE_SET = (15, 0.3, 160)              # persistence/
replicates(set) = set == PERSISTENCE_SET ? 30 : 10
every(set) = set[3] in (150, 175, 200) ? 1 : 10
seed(i, k) = 1_400_000_000 + 1000i + k
qseed(block, k) = 1_490_000_000 + 1000block + k
dims(R, φ) = fortuna_lattice(R, φ)
set_id(s) = "R$(s[1])/φ$(s[2])/λ$(s[3])"
# regime_map: Fig 6, R = 15
const REGIME_MAP = Dict(
    (φ, λ) => (
        φ == 0.05 ? (λ <= 175 ? "migrating" : "detachment") :
            (λ == 125 ? "confined" : λ <= 200 ? "migrating" : "detachment")
    )
        for φ in (0.05, 0.1, 0.2, 0.3), λ in (125, 150, 175, 200, 250)
)
# 59 points: Fig 5 has no R = 10, φ 0.05, λ 200 marker
const FIG5_SETS = [
    (R, φ, λ) for R in (10, 15, 20) for φ in (0.05, 0.1, 0.2, 0.3)
        for λ in (100, 125, 150, 175, 200) if (R, φ, λ) != (10, 0.05, 200)
]
# Table 2 values quoted in the reproduction spec, a cross-check of table2.tsv
const TABLE2_QUOTED = Dict(
    (15, 0.1, 150) => (S = 9.68e-3, P = 6878.0, D = 2.83e-4),
    (15, 0.1, 175) => (S = 9.84e-4, P = 12546.0, D = 2.37e-3),
    (15, 0.1, 200) => (S = 3.93e-4, P = 23265.0, D = 5.66e-3),
    (15, 0.3, 160) => (S = 2.12e-2, P = 8327.0, D = 1.13e-4),
    (15, 0.3, 150) => (S = nothing, P = 11987.0, D = nothing),
    (15, 0.3, 165) => (S = nothing, P = 11507.0, D = nothing),
    (15, 0.3, 170) => (S = nothing, P = 15079.0, D = nothing),
    (15, 0.3, 175) => (S = nothing, P = 7491.0, D = nothing),
    (15, 0.3, 200) => (S = nothing, P = 10124.0, D = nothing),
    (20, 0.2, 175) => (S = nothing, P = 26853.0, D = nothing),
    (20, 0.2, 200) => (S = nothing, P = 12613.0, D = nothing),
)
const LOOSE_ROWS = ((15, 0.1, 150), (15, 0.2, 150), (15, 0.3, 160), (10, 0.2, 150))  # loose rows
const D_INFO_ROWS = ((10, 0.2, 175),)                                               # D info
gates(set, method) = method === :lsq || replicates(set) >= 30

# ------------------------------------------------------------------------------------------
# Bands, regime and fits

ratio_in(x, ref, lo, hi) = isfinite(x) && lo <= x / ref <= hi
displacement_ok(ours, paper, se) = abs(ours - paper) <= 2se || ratio_in(ours, paper, 0.5, 2.0)
function table2_ok(fit, ref; loose = false, d_info = false)
    okS = ratio_in(fit.S, ref.S, 0.5, 2.0)
    okP = loose ? ratio_in(fit.P, ref.P, 0.25, 3.0) : ratio_in(fit.P, ref.P, 0.5, 1.5)
    okD = loose ? ratio_in(fit.D, ref.D, 0.25, 4.0) : ratio_in(fit.D, ref.D, 0.5, 2.0)
    return resolved(fit) && okS && okP && (d_info || okD)
end
dfast_ok(a) = isfinite(a) && abs(a / 0.127 - 1) <= 0.3
function regime(detached::AbstractVector{Bool}, disp::AbstractVector{<:Real})
    2count(detached) >= length(detached) && return "detachment"
    return mean(disp) < 2 ? "confined" : "migrating"
end
detached(t, lam_cyto, alive) = any(i -> t[i] > 10 && alive[i] && lam_cyto[i] == 0, eachindex(t))

# `furth_fit`, with NaNs for a fit it cannot make (e.g. `:paper` with no decaying second
# derivative): the row then fails its band
function fit(Δt, m, method)
    try
        return A.furth_fit(Δt, m; method)
    catch e
        e isa ArgumentError || rethrow()
        return (; S = NaN, D = NaN, P = NaN, D_fast = NaN, D_slow = NaN, v_eff = NaN, offset = NaN, method)
    end
end
eq2(τ, S) = τ - (1 - S) * (1 - exp(-τ))
resolved(f) = all(isfinite, (f.S, f.P, f.D)) && 0 <= f.S < 1 && f.P > 0 && f.D > 0
# collapse/: RMS of log m − log Eq 1(fit); NaN for an unresolved fit
curve_rms(Δt, m, f) = resolved(f) ?
    sqrt(mean(abs2, log.(m) .- log.(A.furth_mean_squared_displacement(Δt, f.S, f.D, f.P)))) :
    NaN
# persistence/ collapse: ρ² = natural units of m − offset against Eq2(τ, S_fit), the RMS of
# the log ratio over the fit lags. Lags with m − offset ≤ 0 are left out (`:paper`'s offset
# is a noisy intercept of about ±2 m(Δt = 50)); more than COLLAPSE_DROP of them is NaN.
const COLLAPSE_BOUND = 0.2
const COLLAPSE_DROP = 10
function collapse(Δt, m, f)
    resolved(f) || return NaN
    τ, ρ2 = A.natural_units(Δt, m .- f.offset, f)
    keep = ρ2 .> 0
    count(!, keep) > COLLAPSE_DROP && return NaN
    return sqrt(mean(abs2, log.(ρ2[keep] ./ eq2.(τ[keep], f.S))))
end
collapse_ok(Δt, m, f) = collapse(Δt, m, f) <= COLLAPSE_BOUND
excluded(Δt, m, f) = resolved(f) ? count(<=(0), A.natural_units(Δt, m .- f.offset, f)[2]) : -1

# ------------------------------------------------------------------------------------------
# The S-resolution oracle: OU + Brownian tracks at Fortuna's sampling
#
# Exact AR(1) velocity per axis plus Brownian increments, sample step 50 MCS, 2001 samples
# (10⁵ MCS), N = 30 tracks, at the persistence row (S = 0.0212, P = 8327, D = 1.13e-4
# R²/MCS) and at P = 11987; controls S = 0 (both P) and S = 0.1. Seeds StableRNG(1:16),
# common to every configuration. Measured at K = 200, N = 30, 16 seeds (median |ΔS|, SD):
#   S 0.0212, P 8327: paper 0.0015, 0.0032; lsq 0.0023, 0.0030
#   S 0.0212, P 11987: paper 0.0027, 0.0039; lsq 0.0025, 0.0035
#   S 0.1, P 8327: median S paper 0.1124, lsq 0.1018
# Both methods pass (median |ΔS| ≤ 0.005, SD ≤ 0.005, S = 0 median |S| ≤ 0.01), so N = 30
# gives SE(S) ≈ 0.003 ≪ 0.02 at the persistence set. The collapse bound 0.2 was calibrated
# on 40 ideal synthetics: `:paper` 1 of 40 false failures with the ρ² ≤ 0 lags left out,
# `:lsq` 0.

const ORACLE_D = 1.13e-4
const ORACLE_CONFIGS = (
    (S = 0.0212, P = 8327.0), (S = 0.0212, P = 11987.0), (S = 0.0, P = 8327.0),
    (S = 0.0, P = 11987.0), (S = 0.1, P = 8327.0),
)
const N_ORACLE = 30

function ou_tracks(rng; S, D, P, δ = Float64(DT), n = TMAX ÷ DT + 1, ntracks = N_ORACLE)
    Df = D * S / (1 - S)
    a = exp(-δ / P)
    sv = sqrt(D / (2P))
    sb = sqrt(Df * δ)
    out = Vector{Vector{NTuple{2, Float64}}}()
    for _ in 1:ntracks
        v = (sv * randn(rng), sv * randn(rng))
        x = (0.0, 0.0)
        tr = Vector{NTuple{2, Float64}}(undef, n)
        tr[1] = x
        for k in 2:n
            x = x .+ v .* δ .+ sb .* (randn(rng), randn(rng))
            v = a .* v .+ (sv * sqrt(1 - a^2)) .* (randn(rng), randn(rng))
            tr[k] = x
        end
        push!(out, tr)
    end
    return out
end
function brownian_tracks(rng; D, δ = Float64(DT), n = TMAX ÷ DT + 1, ntracks = N_ORACLE)
    sb = sqrt(D * δ)
    walk() = accumulate((x, _) -> x .+ sb .* (randn(rng), randn(rng)), 2:n; init = (0.0, 0.0))
    return [[(0.0, 0.0); walk()] for _ in 1:ntracks]
end
replicate_msds(tracks) = permutedims(
    reduce(hcat, [A.mean_squared_displacement(t; lags = FIT_LAGS) for t in tracks])
)

# the calibration rows: (method, P, S_true, seed, S, D, P_fit)
function oracle_rows()
    rows = NamedTuple[]
    for cf in ORACLE_CONFIGS, sd in 1:16
        tr = ou_tracks(StableRNG(sd); S = cf.S, D = ORACLE_D, P = cf.P)
        m = A.mean_squared_displacement(tr; lags = FIT_LAGS)
        for method in METHODS
            f = fit(FIT_DT, m, method)
            push!(rows, (; method, P = cf.P, S_true = cf.S, seed = sd, S = f.S, D = f.D, P_fit = f.P))
        end
    end
    return rows
end
const ORACLE = Ref{Any}(nothing)
oracle() = something(ORACLE[], (ORACLE[] = oracle_rows(); ORACLE[]))
select_S(rows, method, S, P) = [r.S for r in rows if r.method === method && r.S_true == S && r.P == P]
function method_passes(rows, method)
    ok = true
    for P in (8327.0, 11987.0)
        s = select_S(rows, method, 0.0212, P)
        ok &= median(abs.(s .- 0.0212)) <= 0.005 && std(s) <= 0.005
        ok &= median(abs.(select_S(rows, method, 0.0, P))) <= 0.01
    end
    return ok
end

# bootstrap SE(S) over replicates; `reps` is replicates × fit lags
function bootstrap_se(reps::AbstractMatrix, method)
    rows = [reps[k, :] for k in axes(reps, 1)]
    n = length(rows)
    rng = StableRNG(BOOT.seed)
    S = [fit(FIT_DT, mean(rows[rand(rng, 1:n, n)]), method).S for _ in 1:BOOT.n]
    ok = filter(isfinite, S)
    return length(ok) > 1 ? std(ok) : NaN
end

"""
The whole persistence verdict for one method from the replicate MSDs at the fit lags (`reps`,
replicates × fit lags): a resolved fit, S ∈ [0.01, 0.04], bootstrap SE(S) ≤ 0.005 and the
collapse. It has no P or D band.
"""
function persistence_verdict(reps::AbstractMatrix, method)
    m = vec(mean(reps; dims = 1))
    f = fit(FIT_DT, m, method)
    se = resolved(f) ? bootstrap_se(reps, method) : NaN
    rms = collapse(FIT_DT, m, f)
    okS = resolved(f) && 0.01 <= f.S <= 0.04
    return (; f, se, rms, okS, ok = okS && se <= 0.005 && rms <= COLLAPSE_BOUND)
end

# ------------------------------------------------------------------------------------------
# Runs: the problem, the basic recorder and its reductions

const SYSTEMS = Dict{Any, Any}()
system(R, φ) = get!(
    () -> FortunaMigration(; name = :fortuna, lattice = dims(R, φ)), SYSTEMS, dims(R, φ)
)
# build `sys` and `layout` on the calling task (the cache is a plain Dict)
function problem(R, φ, λ; c = 0.1, seed, T, sys = system(R, φ), layout = fortuna_layout(R, sys))
    op = [layout; :R => Float64(R); :φ_l => Float64(φ); :λ_F => Float64(λ); :c => Float64(c)]
    return PottsProblem(sys, op, (0, T); seed, field_solver = ExplicitEuler(substeps = 1))
end
kind_volume(vol, kd, k) = sum((vol[c] for c in eachindex(vol) if vol[c] > 0 && kd[c] == k); init = 0)

"""
    record(prob; T, every) -> NamedTuple of vectors

Step one run and sample it every `every` MCS from t = 0: t, the nucleus centroid in x and y
(sites), Πx, Πy, lam_cyto, the three compartment volumes, the lamellipodium alive flag and
lam_births. `record.jl` has the full recorder of the FULL runs.
"""
function record(prob; T, every)
    integ = init(
        prob, SequentialCPM(); save_everystep = false, save_start = false, save_end = false
    )
    rec = (
        t = Int[], nx = Float64[], ny = Float64[], Πx = Float64[], Πy = Float64[],
        lam_cyto = Float64[], vc = Float64[], vn = Float64[], vl = Float64[], alive = Bool[],
        births = Float64[],
    )
    function sample!(t, u)
        kd, vol = cell_kinds(u), volumes(u)
        push!(rec.t, t)
        for o in (:nx, :ny, :Πx, :Πy, :lam_cyto)
            push!(getfield(rec, o), observe(prob, o, u)[1])
        end
        push!(rec.vc, kind_volume(vol, kd, KIND.cytoplasm))
        push!(rec.vn, kind_volume(vol, kd, KIND.nucleus))
        push!(rec.vl, kind_volume(vol, kd, KIND.lamellipodium))
        push!(rec.alive, rec.vl[end] > 0)
        push!(rec.births, observe(prob, :lam_births, u)[1])
        return nothing
    end
    sample!(0, prob.u0)
    for t in 1:T
        step!(integ)
        t % every == 0 && sample!(t, integ.u)
    end
    return rec
end
# the nucleus displacement (sites) from the unwrapped xy track
function displacement(rec, L)
    tr = A.unwrap_track(collect(zip(rec.nx, rec.ny)), (L, L), true)
    return sqrt(sum(abs2, tr[end] .- tr[1]))
end
# the time mean of |V − V_t|/V_t over t ≥ from, per compartment (targets fixed)
function volume_errors(rec, R, φ; from = VOLUME_FROM)
    V = 4 / 3 * π * R^3
    w = findall(>=(from), rec.t)
    rel(v, vt) = mean(abs.(v[w] .- vt) ./ vt)
    return (
        cyto = rel(rec.vc, (1 - 0.15 - φ) * V), nucleus = rel(rec.vn, 0.15 * V),
        lam = rel(rec.vl, φ * V),
    )
end
volumes_ok(dvs) = all(k -> mean(getfield(d, k) for d in dvs) <= 0.02, (:cyto, :nucleus, :lam))
function threaded_map(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads :dynamic for i in eachindex(xs)
        out[i] = f(xs[i])
    end
    return out
end
function qruns(R, φ, λ, c, block; T = 20_000, n = 3)
    sys = system(R, φ)
    layout = fortuna_layout(R, sys)
    return threaded_map(
        k -> record(problem(R, φ, λ; c, seed = qseed(block, k), T, sys, layout); T, every = 10),
        1:n
    )
end

# ------------------------------------------------------------------------------------------
# The short qualitative tier: each function returns its checks (label => pass) and numbers

"""The c calibration and the first set's checks at R = 10, φ_l = 0.05, λ_F = 150."""
function qtier_calibration(; T = 20_000)
    scal = NamedTuple[]
    chosen, runs = nothing, nothing
    for (j, c) in enumerate(C_GRID)
        rs = qruns(10, 0.05, 150, c, j; T)
        dvs = [volume_errors(r, 10, 0.05) for r in rs]
        pass = volumes_ok(dvs)
        push!(
            scal, (;
                c, cyto = mean(d.cyto for d in dvs), nucleus = mean(d.nucleus for d in dvs),
                lam = mean(d.lam for d in dvs), pass,
            )
        )
        if pass
            chosen, runs = c, rs
            break
        end
    end
    checks = Pair{String, Bool}["c_calibration: a c passes volume_window" => chosen !== nothing]
    chosen === nothing && return (; checks, scal, c = NaN, first_set_disp = NaN)
    L = dims(10, 0.05)[1]
    for (k, r) in enumerate(runs)
        i = findfirst(r.alive)
        Π = hypot.(r.Πx, r.Πy)
        w = findall(t -> VOLUME_FROM <= t <= T, r.t)
        push!(checks, "lamellipodium_by_50, replicate $k" => (i !== nothing && r.t[i] <= 50))
        push!(checks, "polarization_start, replicate $k" => isapprox(Π[1], 0; atol = 1.0e-9))
        push!(checks, "polarization, replicate $k" => mean(Π[w]) > 1)
    end
    d = [displacement(r, L) for r in runs]
    push!(checks, "mean_displacement" => mean(d) > 20)
    return (; checks, scal, c = chosen, first_set_disp = mean(d))
end
"""`confined_set` (Fig 6) and `no_drive_control` (λ_F = 0) at the calibrated `c`."""
function qtier_controls(c, first_set_disp; T = 20_000)
    d3 = [displacement(r, dims(15, 0.3)[1]) for r in qruns(15, 0.3, 125, c, 11; T)]
    d4 = [displacement(r, dims(10, 0.05)[1]) for r in qruns(10, 0.05, 0, c, 12; T)]
    checks = [
        "confined_set" => mean(d3) < 30,
        "no_drive_control" => (isfinite(first_set_disp) && mean(d4) < first_set_disp / 3),
    ]
    return (; checks, confined_disp = mean(d3), no_drive_disp = mean(d4))
end
"""`timing`: ns per copy attempt at R = 10, 15, 20 (info)."""
function qtier_timing(c)
    out = Dict{String, Float64}()
    for R in (10, 15, 20)
        prob = problem(R, 0.05, 150; c, seed = qseed(20, R), T = 1000)
        solve(
            problem(R, 0.05, 150; c, seed = qseed(20, R), T = 10), SequentialCPM();
            save_everystep = false
        )
        t = @elapsed solve(prob, SequentialCPM(); save_everystep = false, save_start = false)
        out[string(R)] = 1.0e9 * t / (1000 * prod(dims(R, 0.05)))
    end
    return out
end

# ------------------------------------------------------------------------------------------
# The FULL record: recompute every row

read_tsv(path) = (
    ls = readlines(path); h = split(ls[1], '\t');
    [Dict(zip(h, split(l, '\t'))) for l in ls[2:end] if !isempty(l)]
)
pf(x) = parse(Float64, x)
pi_(x) = parse(Int, x)
set_key(r) = (pi_(r["R"]), pf(r["phi"]), pi_(r["lambda"]))

const RECORD_FILES = (
    "README.md", "provenance.toml", "run_full.jl", "record.jl", "evaluate.jl", "sets.tsv",
    "runs.tsv", "msd_runs.tsv", "msd.tsv", "fits.tsv", "oracle.tsv", "scal.tsv",
    "verdicts.tsv", "job_walls.tsv",
)

# msd_runs.tsv as set => (replicates × lags), rows in replicate order
function msd_runs(D)
    rows = read_tsv(joinpath(D, "msd_runs.tsv"))
    out = Dict{Int, Matrix{Float64}}()
    for i in eachindex(SETS)
        rs = sort(filter(r -> pi_(r["set"]) == i, rows); by = r -> pi_(r["rep"]))
        out[i] = [pf(r["m_$l"]) for r in rs, l in LAGS]
    end
    return out
end
# the spread of S over per-replicate fits (`:paper` info rows)
function replicate_spread(mr, i, method, fitix)
    S = [fit(FIT_DT, mr[i][k, fitix], method).S for k in axes(mr[i], 1)]
    ok = filter(x -> isfinite(x) && 0 <= x < 1, S)
    return (
        n = length(S), resolved = length(ok), median_S = isempty(ok) ? NaN : median(ok),
        sd_S = length(ok) > 1 ? std(ok) : NaN,
    )
end

"""
    verdicts(D, refs = REFS) -> (rows, derived)

Recompute every verdict of the record in `D`. `rows` are `(id, kind, value, band, ok)` with
kind `:row` (gating) or `:info`; `derived` holds the regimes, displacements, ensemble MSDs
and fits.
"""
function verdicts(D, refs = REFS)
    V = NamedTuple[]
    add!(id, kind, value, band, ok) = push!(V, (; id, kind, value, band, ok))
    runs = read_tsv(joinpath(D, "runs.tsv"))
    byset = Dict(i => filter(r -> pi_(r["set"]) == i, runs) for i in eachindex(SETS))
    reg = Dict{Int, String}()
    disp = Dict{Int, Float64}()
    for (i, s) in enumerate(SETS)
        rs = byset[i]
        d = [pf(r["disp"]) for r in rs]
        reg[i] = regime([r["detached"] == "1" for r in rs], d)
        disp[i] = mean(d)
        dv = [mean(pf(r[k]) for r in rs) for k in ("dv_cyto", "dv_nuc", "dv_lam")]
        add!("volumes/" * set_id(s), :row, dv, "≤ 0.02 each", all(<=(0.02), dv))
    end
    add!("lid", :info, count(r -> r["lid_touch"] == "1", runs), "runs whose lamellipodium touches z = Lz − 1", true)
    add!("deaths", :info, sum(r -> pi_(r["lam_deaths"]), runs), "lamellipodium deaths, all runs", true)
    hits = 0
    for ((φ, λ), want) in sort(collect(REGIME_MAP))
        got = reg[findfirst(==((15, φ, λ)), SETS)]
        hits += got == want
        add!("regime_map/φ$(φ)/λ$(λ)", :info, got, want, got == want)
    end
    add!("regime_map", :row, hits, "≥ 16 of 20", hits >= 16)
    mr = msd_runs(D)
    ens = Dict(i => vec(mean(mr[i]; dims = 1)) for i in eachindex(SETS))
    fitix = [findfirst(==(l), LAGS) for l in FIT_LAGS]
    logix = [findfirst(==(l), LAGS) for l in LOG_LAGS]
    fits = Dict{Tuple{Int, Symbol}, Any}()
    for i in eachindex(SETS), method in METHODS
        reg[i] == "migrating" || continue
        fits[(i, method)] = fit(FIT_DT, ens[i][fitix], method)
    end
    for r in read_tsv(joinpath(refs, "fig5.tsv"))
        k = set_key(r)
        i = findfirst(==(k), SETS)
        add!(
            "fig5_displacement/" * set_id(k), :row, disp[i], "paper $(r["disp"]) ± 2·$(r["se"]) or ×2",
            displacement_ok(disp[i], pf(r["disp"]), pf(r["se"]))
        )
    end
    kind_of(s, method) = gates(s, method) ? :row : :info
    for r in read_tsv(joinpath(refs, "table2.tsv")), method in METHODS
        k = set_key(r)
        i = findfirst(==(k), SETS)
        ref = (S = pf(r["S"]), P = pf(r["P"]), D = pf(r["D"]))
        id = "table2/" * set_id(k) * "/$method"
        if reg[i] != "migrating"
            add!(id, kind_of(k, method), "regime mismatch: $(reg[i])", "migrating", false)
            continue
        end
        f = fits[(i, method)]
        loose, d_info = k in LOOSE_ROWS, k in D_INFO_ROWS
        band = "S, D ×2; P ±50 %" * (loose ? " (P ×[1/4, 3], D ×4)" : "") *
            (d_info ? " (D info only)" : "")
        value = resolved(f) ? (S = f.S, P = f.P, D = f.D) : "not resolved: S = $(f.S), P = $(f.P)"
        gates(k, method) ||
            (value = (; fit = value, replicates = replicate_spread(mr, i, method, fitix)))
        add!(id, kind_of(k, method), value, band, table2_ok(f, ref; loose, d_info))
    end
    i6 = findfirst(==(PERSISTENCE_SET), SETS)
    for method in METHODS
        id = "persistence/$method"
        if reg[i6] != "migrating"
            add!(id, :row, "regime mismatch: $(reg[i6])", "migrating", false)
            continue
        end
        b = persistence_verdict(mr[i6][:, fitix], method)
        add!(
            id, :row, (S = b.f.S, b.se, collapse = b.rms),
            "S ∈ [0.01, 0.04], SE ≤ 0.005, collapse RMS ≤ $(COLLAPSE_BOUND)", b.ok
        )
    end
    logdt = Float64.(DT .* LOG_LAGS)
    for method in METHODS
        pre = Float64[]
        for (i, s) in enumerate(SETS)
            haskey(fits, (i, method)) || continue
            f = fits[(i, method)]
            rms = curve_rms(logdt, ens[i][logix], f)
            add!(
                "collapse/" * set_id(s) * "/$method", kind_of(s, method),
                isnan(rms) ? "not resolved" : rms, "≤ 0.1", rms <= 0.1
            )
            resolved(f) && f.D_fast > 0 && push!(pre, f.D_fast * s[1]^4)
        end
        a = isempty(pre) ? NaN : exp(mean(log.(pre)))
        add!("dfast/$method", method === :lsq ? :row : :info, a, "0.127 ± 30 %", dfast_ok(a))
    end
    w15 = [pf(r["wall_s"]) / 60 for r in runs if r["R"] == "15"]
    add!("wall_time", :info, isempty(w15) ? NaN : mean(w15), "CompuCell3D 200 min", true)
    detach = Dict(i => count(r -> r["detached"] == "1", byset[i]) for i in eachindex(SETS))
    disp_se = Dict(
        i => (d = [pf(r["disp"]) for r in byset[i]]; std(d) / sqrt(length(d)))
            for i in eachindex(SETS)
    )
    return V, (; regime = reg, disp, detach, disp_se, ens, fits)
end

# gating rows pass, or fail with a deviations.tsv entry (`@test_broken`); a deviation that
# names no failing gating row is stale and fails
function check_verdicts(V, devs)
    for v in V
        v.kind === :info && continue
        if v.ok
            @test v.ok
        elseif any(d -> d["id"] == v.id, devs)
            @test_broken v.ok
        else
            @error "Fortuna record: row failed" v.id v.value v.band
            @test v.ok
        end
    end
    for d in devs
        i = findfirst(v -> v.id == d["id"], V)
        stale = i === nothing || V[i].kind !== :row || V[i].ok
        stale && @error "Fortuna record: stale deviations.tsv row" d["id"]
        @test !stale
    end
    return nothing
end

"""
    check_record(D; refs = REFS)

Every record check on the directory `D`: the files, provenance, the order of the c calibration, the run
set, seeds and cadence, the oracle, the recomputed regimes, MSDs and fits, and every
verdict. Runs `@test`s; call it inside a testset.
"""
function check_record(D; refs = REFS)
    for f in RECORD_FILES
        @test isfile(joinpath(D, f))
    end
    prov = TOML.parsefile(joinpath(D, "provenance.toml"))
    @test all(k -> haskey(prov, k), ("commit", "dirty", "julia", "threads", "machine", "cpu", "c"))
    @test occursin(r"^[0-9a-f]{40}$", string(get(prov, "commit", ""))) &&
        get(prov, "dirty", true) === false
    sc = read_tsv(joinpath(D, "scal.tsv"))
    cs = [pf(r["c"]) for r in sc]
    @test !isempty(cs) && cs == collect(C_GRID[1:length(cs)])
    @test [r["pass"] for r in sc] == [fill("0", length(cs) - 1); "1"]
    @test all(r -> (r["pass"] == "1") == all(k -> pf(r[k]) <= 0.02, ("cyto", "nucleus", "lam")), sc)
    @test prov["c"] == last(cs)
    sets = read_tsv(joinpath(D, "sets.tsv"))
    @test length(sets) == length(SETS)
    for (i, s) in enumerate(SETS)
        r = only(filter(r -> pi_(r["set"]) == i, sets))
        @test set_key(r) == s
        @test pi_(r["n"]) == replicates(s) && pi_(r["every"]) == every(s)
        @test (pi_(r["L"]), pi_(r["L"]), pi_(r["Lz"])) == dims(s[1], s[2])
    end
    runs = read_tsv(joinpath(D, "runs.tsv"))
    @test sort([(pi_(r["set"]), pi_(r["rep"])) for r in runs]) ==
        sort([(i, k) for (i, s) in enumerate(SETS) for k in 1:replicates(s)])
    @test all(r -> pi_(r["seed"]) == seed(pi_(r["set"]), pi_(r["rep"])), runs)
    @test all(r -> set_key(r) == SETS[pi_(r["set"])], runs)
    @test all(r -> pi_(r["every"]) == every(SETS[pi_(r["set"])]), runs)
    orc = read_tsv(joinpath(D, "oracle.tsv"))
    mine = oracle()
    @test length(orc) == length(mine)
    for r in orc
        m = only(
            filter(
                x -> string(x.method) == r["method"] && x.P == pf(r["P"]) &&
                    x.S_true == pf(r["S_true"]) && x.seed == pi_(r["seed"]), mine
            )
        )
        @test isequal(pf(r["S"]), m.S) || isapprox(pf(r["S"]), m.S; rtol = 1.0e-9)
    end
    V, R = verdicts(D, refs)
    for r in sets
        i = pi_(r["set"])
        @test r["regime"] == R.regime[i]
        @test pi_(r["detach"]) == R.detach[i]
        @test pf(r["disp_mean"]) ≈ R.disp[i] rtol = 1.0e-6
        @test pf(r["disp_se"]) ≈ R.disp_se[i] rtol = 1.0e-6
    end
    for r in read_tsv(joinpath(D, "msd.tsv"))
        i = pi_(r["set"])
        j = findfirst(==(pi_(r["lag_mcs"]) ÷ DT), LAGS)
        @test pf(r["msd"]) ≈ R.ens[i][j] rtol = 1.0e-6
    end
    fitix = [findfirst(==(l), LAGS) for l in FIT_LAGS]
    fits = read_tsv(joinpath(D, "fits.tsv"))
    @test length(fits) == length(R.fits)
    for r in fits
        i = pi_(r["set"])
        f = R.fits[(i, Symbol(r["method"]))]
        for k in ("S", "P", "D")
            @test isequal(pf(r[k]), getfield(f, Symbol(k))) ||
                isapprox(pf(r[k]), getfield(f, Symbol(k)); rtol = 1.0e-6)
        end
        @test pi_(r["excluded"]) == excluded(FIT_DT, R.ens[i][fitix], f)
    end
    nrows(prefix) = count(v -> startswith(v.id, prefix), V)
    @test (nrows("volumes/"), nrows("fig5_displacement/"), nrows("table2/")) ==
        (length(SETS), 59, 80)
    dev_f = joinpath(D, "deviations.tsv")
    devs = isfile(dev_f) ? read_tsv(dev_f) : Dict{String, String}[]
    check_verdicts(V, devs)
    vt = read_tsv(joinpath(D, "verdicts.tsv"))
    gating = [v.id for v in V if v.kind === :row]
    @test Set(r["id"] for r in vt) == Set(gating) && length(vt) == length(gating)
    for v in V
        v.kind === :info && continue
        rr = filter(r -> r["id"] == v.id, vt)
        @test length(rr) == 1 && rr[1]["result"] == (v.ok ? "PASS" : "FAIL")
    end
    return nothing
end

# the record directory under reproductions/data/14 (`full-YYYY-MM-DD`), if any
full_records() = filter(
    d -> occursin(r"^full-\d{4}-\d{2}-\d{2}$", d) && isdir(joinpath(DATA, d)), readdir(DATA)
)

end
