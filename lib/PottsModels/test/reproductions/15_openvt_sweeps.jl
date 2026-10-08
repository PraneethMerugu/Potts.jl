# P6.15g (ROADMAP Step 3b): the OpenVT monolayer benchmark's inhibition sweeps. Fig 6 shows the
# time to 10⁴ cells against β (γ = 0) and against γ (β = 0). Table 1 (T1) gives the thresholds
# at 1.1, 2, 5, 10 and 20× the uninhibited time. Fig 7 shows 10⁴-cell colonies at β = 0 for the
# T1 γ values. Frozen (AUTONOMY §7.3).
# Protocol: spec 15 §4.0.1 cases (a), (c) and (d), §3.5 and §4.3. Targets: §4.1 V1, V2, V2b, V3
# and V3b (docs/design/research/model-specs/15_openvt_monolayer.md v3.3, which carries the
# P6.15g V-target audit). Every grid, seed, lattice, run count, rule and negative control below
# is the test author's (P6.15g; see the D-entry).
#
# Reference numbers from G (54f375f, read only, never in git) are frozen below as constants.
# They were computed with this file's rules (`p615g_mrule`, `p615g_g_reference`) on the PC
# clone on 2026-10-08. The G tier recomputes them when OPENVT_MONOLAYER_REPO is set.
#
# Units. A run's time t is its stopping MCS / 775: the end of the first MCS with ≥ 10⁴ live
# cells, in cycles (5T, C1). This is M's "Time to 10k (5T)". The targets are multiples of M's
# uninhibited time, τ_m = 13.57 m, for m = 1.1, 2, 5, 10, 20: 14.927, 27.14, 67.85, 135.7, 271.4
# (Table 1 caption; Fig 6 dashed lines, spec §2.3).
#
# Cap (spec §4.3, "runs past 20× are capped"). A run ends at MCS P615G_CAP = 271.4 × 775 =
# 210 335. If it has not reached 10⁴ cells by then it is capped: t = Inf, read as "> 20×".
# A run that reaches 10⁴ cells at the cap itself has t = 271.4 = τ_20, so "capped" means
# exactly t > τ_20.
#
# Point mean. A point is (sweep, q), where q is the inhibition threshold in units of 10⁻⁴
# (β = q/10⁴ in the β sweep, γ = q/10⁴ in the γ sweep). Its runs are its replicates k = 1, 2, ….
# t̄ is the mean of their t, or Inf if any replicate is capped.
#
# Sampling: the TST/Artistoo way (spec §3.5, §4.3), as a deterministic adaptive protocol
# (`p615g_protocol`) that the record tier replays.
# 1. Grid. Every point of P615G_GRID gets n₁ replicates:
#    - 10 at β = 0 (V1; C4's ≥ 10);
#    - 5 at the V2b points and at γ = 10⁻⁴ (V3b);
#    - 1 elsewhere (TST's single runs).
#    The γ sweep does not include γ = 0. That case is the β = 0 point, because β = γ = 0 is
#    one model.
# 2. Bracket. For each target (sweep, m) of P615G_TARGETS, take the first adjacent pair of
#    grid points (ascending q) with t̄(lo) ≤ τ_m < t̄(hi). The γ sweep scans only γ > 0. With
#    no such pair the threshold is "—".
# 3. Bisection, P615G_K = 2 steps. mid = (lo + hi) ÷ 2 in q units, so β and γ are rounded down
#    to 10⁻⁴. The mid gets one replicate, unless it is already sampled. Then lo := mid if
#    t̄(mid) ≤ τ_m, else hi := mid. A step is skipped when mid equals lo or hi. Each step is
#    one batch over all targets.
# 4. Final points (Artistoo's repeats; spec §4.3 "repeat 6 runs at the final points"). Both
#    ends of each final bracket are topped up to P615G_NFINAL = 6 replicates. An end that is
#    already capped (t̄ = Inf) is not topped up: it stays "> 20×".
# 5. Threshold (M's rule, §3.5): the final end whose t̄ is nearest τ_m. Ties go to lo,
#    including when both ends are Inf. Information only: a log-linear interpolation of τ_m
#    between the ends; the thresholds relative to Potts' own uninhibited time (t̄(β = 0) × m,
#    by `p615g_mrule` over the sampled table).
#
# | Row          | Statistic                                                     | Lattice spread (spec §4.1) | Pass band                 |
# |--------------|---------------------------------------------------------------|----------------------------|---------------------------|
# | V1           | t̄ at β = γ = 0 (10 replicates)                                | 13.57 × 5T                 | [12.213, 14.927] (± 10 %) |
# | V2.1.1x      | β threshold at 1.1×                                           | 0.687–0.704                | [0.667, 0.724]            |
# | V2.2x        | β threshold at 2×                                             | 0.936–0.943                | [0.916, 0.963]            |
# | V2.5x        | β threshold at 5×                                             | 0.9867–0.9916              | [0.9817, 0.9966]          |
# | V2.10x       | β threshold at 10×                                            | 1.006–1.011                | [1.001, 1.016]            |
# | V2.20x       | β threshold at 20×                                            | 1.020–1.024                | [1.015, 1.029]            |
# | V2b.<β>      | t̄(β) / reference at β = 0.8727, 0.9, 0.9334, 0.95, 1.0       | Artistoo 18.59, TST 20.40, Artistoo 25.59, TST 32.11, TST 105.76 | [0.75, 1.25] (± 25 %) |
# | V3.1.1x, V3.2x | γ threshold at 1.1× and 2×                                  | "—" (the γ → 0⁺ jump)      | "—"                       |
# | V3.5x        | γ threshold at 5×                                             | 0.076–0.12                 | [0.026, 0.17]             |
# | V3.10x       | γ threshold at 10×                                            | 0.45–0.50                  | [0.40, 0.55]              |
# | V3.20x       | γ threshold at 20×                                            | 0.715–0.76                 | [0.665, 0.81]             |
# | V3b          | t̄ at γ = 10⁻⁴ (5 replicates)                                  | 61.4–63.1 (γ ≤ 0.02)       | [61, 70]                  |
# | F7.1         | min over the T1 γ thresholds (5×, 10×, 20×) of the inhibited  | TST 0.961, 0.978, 0.990    | ≥ 0.90                    |
# |              | fraction of replicate 1's final colony (O5)                   |                            |                           |
#
# A threshold row fails when its threshold is "—". V1 is frozen as the spec states it. D-173
# measured 15.17 cycles for case (a), so V1 may fail. A failure is a D-154 deviation: it goes
# in `deviations.tsv`, and the band is not widened. The spread values come from Table 1 (M p.7,
# spec v3 log). G's TST and Artistoo rows reproduce them under p615g_mrule (constants below).
#
# Negative controls (D-048). Each is pre-registered to FAIL its row.
# - NC1 (V3b's own control, spec §4.1): γ = 0 (the β = 0 point, 10 replicates) lies outside
#   the V3b band. Without inhibition there is no γ → 0⁺ jump: t̄ ≈ 13.6, not 61–70.
# - NC2 (V2b's β resolution): the V2b statistic at a β offset of 0.05. That is Potts t̄(0.95)
#   against TST's 20.40 at 0.9, and Potts t̄(1.0) against TST's 32.11 at 0.95. Both must leave
#   [0.75, 1.25]. If the steep end of the Potts curve were flat, this control would pass.
# - NC3 (V1's discrimination): the V1 rule applied to the γ = 10⁻⁴ point (5 replicates) must
#   fail.
#
# Protocol. `OpenVTReferenceMonolayer` at its Table S1 defaults (σ_X = 0.4), with β and γ set
# per point, from one disc cell at the centre (`openvt_reference_state`). The algorithm is
# `SequentialCPM(; proposal = Moore(1))`. The lattice is closed, with
# `edge_guard(5; terminate = true)`, and a run that reaches the guard invalidates the record.
# The run stops at the end of the first MCS with ≥ 10⁴ cells (`stop_at_cells`), or at the cap.
#
# | Sweep | Fixed  | Lattice | Grid (P615G_GRID)                                                                    | Seeds                         |
# |-------|--------|---------|--------------------------------------------------------------------------------------|-------------------------------|
# | β     | γ = 0  | 1400²   | 0, 0.25, 0.5, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.8727, 0.9, 0.9334, 0.95, 0.96, 0.97, 0.98, 0.99, 1.0, 1.006, 1.01, 1.015, 1.02, 1.025, 1.03 | 160 000 000 + 100 q + k |
# | γ     | β = 0  | 1800²   | 10⁻⁴, 0.001, 0.01, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8 | 170 000 000 + 100 q + k |
#
# Lattices. Spec §4.3 has β ∈ [0, 1.03] and γ ∈ [0, 0.95]. The grid is dense at β ≥ 0.9 and
# γ ≥ 0.4, and includes γ = 10⁻⁴. γ stops at 0.8: in TST, γ ≥ 0.75 is already past 20× (278.8).
# Lattice sizes come from G's TST final snapshots (audit): the furthest centroid is 491 px at
# β = 1.02 and 602 px at γ = 0.75. Potts' (a) colony is about 10 % wider than TST's at the same
# β, and Potts' γ colonies are less compact than its uninhibited ones (the γ = 10⁻⁴ control of
# D-173 came within 33 sites of a 400² edge at 1000 cells; a 300-cell SMOKE draft hit the guard
# of 200² at 190 cells). So 1400² leaves about 150 sites at β = 1.02, and 1800² (TST: 1601²)
# leaves about 240 at γ = 0.75. The cost of a larger γ lattice is the medium sites (G9).
#
# Fig 7 (O5, spec §3.1). For each T1 γ threshold, the final state of replicate 1 is written
# as `Potts.jl_gamma_<γ>_<MCS>MCS.csv`, with `x_pos, y_pos, radius_i` in R and `inhibited =
# i > 0`. So are γ = 0 (β = 0, k = 1) and γ = 10⁻⁴ (k = 1): five panels, one per T1 entry, with
# γ = 0 and 10⁻⁴ standing in for the lattice "—" at 1.1× and 2×. This reading of M's five
# panels is [unverified].
#
# Tiers.
# - always: the rules and the protocol on synthetic sweeps with known answers (curves through
#   TST's Table 1 samples), including that the protocol resolves them within the bands;
#   replay checks; the G constants' premises.
# - SMOKE (the default; under a minute plus one model compilation): three jobs through the
#   FULL job function on 300² with a 250-cell stop. They are β = γ = 0, γ = 10⁻⁴ (the V3b
#   jump's mechanism: at least 1.3× slower), and β = 1.03 under a 1500-MCS cap (the cap path:
#   capped, t = Inf; run twice, the same). Plus the O5 rows of their final states.
# - G (OPENVT_MONOLAYER_REPO set): recompute the frozen consortium constants.
# - FULL record (always, cheap): reads the one committed D-146 record directory
#   `reproductions/data/15/sweeps-*`:
#   - `runs.tsv`, `verdicts.tsv` and `provenance.toml`;
#   - `Potts.jl_time_to_10k_vs_{beta,gamma}.csv` (O3);
#   - `f7/` (O5).
#   It replays the protocol on the recorded times, requires the record to hold exactly the
#   replayed runs, and recomputes every row. A failing row must be in the record's
#   `deviations.tsv` (D-154) and is then `@test_broken`. The controls must fail. Until the
#   record exists this testset fails on its first check.
# - FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full, offline on the PC; D-146, D-157):
#   reruns the protocol and requires every row and every control. Its cost (G9 profile,
#   P6.15g): at most 160 runs and about 11 M MCS·runs, ≈ 125 core-hours on one uncontended
#   PC thread; the jobs of a stage run in parallel with `:greedy` scheduling (D-173).
#
# Record schema (tab-separated, one header line):
# - runs.tsv: sweep (beta | gamma), q, k, seed, stage (grid | bisect | final), beta, gamma,
#   lattice, retcode (Terminated | Success), mcs, N, capped (true | false), edge_gap, wall_s
# - verdicts.tsv: target (first token the row id), ours, band, result (PASS | FAIL), one line
#   per row of P615G_ROWS and P615G_CONTROLS
# - f7/: one O5 file per Fig 7 panel (five)
using Potts, PottsModels, Test
using Statistics: mean

const P615G_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P615G_REPO = get(ENV, "OPENVT_MONOLAYER_REPO", "")
const P615G_DATA = joinpath(pkgdir(PottsModels), "reproductions", "data", "15")

# ---------------------------------------------------------------------------------------------
# Protocol constants (test author)
# ---------------------------------------------------------------------------------------------

const P615G_CYCLE = 775                                # MCS per cycle (5T, C1)
const P615G_T0 = 13.57                                 # M's uninhibited time (Table 1 caption)
const P615G_MULTS = (1.1, 2.0, 5.0, 10.0, 20.0)
p615g_tau(m) = round(P615G_T0 * m; digits = 4)         # 14.927, 27.14, 67.85, 135.7, 271.4
const P615G_CAP = 210_335                              # 271.4 × 775 MCS: the 20× cap
const P615G_CELLS = 10_000
const P615G_GUARD = 5
const P615G_ALG = SequentialCPM(; proposal = Moore(1))
const P615G_LATTICE = (beta = 1400, gamma = 1800)
const P615G_GRID = (
    beta = [0, 2500, 5000, 6000, 6500, 7000, 7500, 8000, 8500, 8727, 9000, 9334, 9500, 9600, 9700, 9800, 9900,
        10_000, 10_060, 10_100, 10_150, 10_200, 10_250, 10_300],
    gamma = [1, 10, 100, 500, 1000, 1500, 2000, 3000, 4000, 4500, 5000, 5500, 6000, 6500, 7000, 7500, 8000])
const P615G_V2B = [8727, 9000, 9334, 9500, 10_000]     # matched β of the V2b references
const P615G_K = 2
const P615G_NFINAL = 6
const P615G_TARGETS = [(:beta, 1.1), (:beta, 2.0), (:beta, 5.0), (:beta, 10.0), (:beta, 20.0),
    (:gamma, 5.0), (:gamma, 10.0), (:gamma, 20.0)]
p615g_n1(sweep, q) = sweep === :beta ? (q == 0 ? 10 : q in P615G_V2B ? 5 : 1) : (q == 1 ? 5 : 1)
p615g_seed(sweep, q, k) = (sweep === :beta ? 160_000_000 : 170_000_000) + 100q + k
p615g_params(sweep, q) = sweep === :beta ? (q / 10_000, 0.0) : (0.0, q / 10_000)
p615g_seed_smoke(k) = 95_400 + k

# ---------------------------------------------------------------------------------------------
# Targets: the lattice spread (spec §4.1, from Table 1) and the pass bands (test author)
# ---------------------------------------------------------------------------------------------

const P615G_V1_BAND = (0.9 * P615G_T0, 1.1 * P615G_T0)
const P615G_V2_SPREAD = Dict(1.1 => (0.687, 0.704), 2.0 => (0.936, 0.943), 5.0 => (0.9867, 0.9916),
    10.0 => (1.006, 1.011), 20.0 => (1.020, 1.024))
const P615G_V2_MARGIN = Dict(1.1 => 0.02, 2.0 => 0.02, 5.0 => 0.005, 10.0 => 0.005, 20.0 => 0.005)
const P615G_V3_SPREAD = Dict(5.0 => (0.076, 0.12), 10.0 => (0.45, 0.50), 20.0 => (0.715, 0.76))
const P615G_V3_MARGIN = 0.05
const P615G_V2B_RATIO = (0.75, 1.25)
const P615G_V3B_BAND = (61.0, 70.0)
const P615G_F7_MIN = 0.90
p615g_band(sweep, m) = sweep === :beta ?
                       (P615G_V2_SPREAD[m][1] - P615G_V2_MARGIN[m], P615G_V2_SPREAD[m][2] + P615G_V2_MARGIN[m]) :
                       (P615G_V3_SPREAD[m][1] - P615G_V3_MARGIN, P615G_V3_SPREAD[m][2] + P615G_V3_MARGIN)
p615g_mid(m) = m == 1.1 ? "1.1x" : string(Int(m), "x")
p615g_row(sweep, m) = (sweep === :beta ? "V2." : "V3.") * p615g_mid(m)

const P615G_ROWS = ["V1"; ["V2." * p615g_mid(m) for m in P615G_MULTS];
    ["V2b." * string(q / 10_000) for q in P615G_V2B]; ["V3." * p615g_mid(m) for m in P615G_MULTS]; "V3b"; "F7.1"]
const P615G_CONTROLS = ["NC1", "NC2", "NC3"]

# ---------------------------------------------------------------------------------------------
# Consortium constants from G (54f375f), computed with this file's rules on 2026-10-08:
# p615g_mrule on `results/TST/TST_time_to_10k_vs_{beta,gamma}.csv` and
# `results/Artistoo/Monolayer/time_to_10k_vs_{beta,gamma}.csv` (rows grouped by parameter
# value, mean time), and the TST final snapshots `results/TST/final_snapshot_data/*.csv`
# ---------------------------------------------------------------------------------------------

const P615G_G = (
    # thresholds at 1.1, 2, 5, 10, 20× (β) and 5, 10, 20× (γ), "—" at γ 1.1× and 2×, by M's
    # rule on the nearest run (`runs`, TST's Table 1 row) and on the nearest point mean
    # (`means`, Artistoo's row except its 1.1× β, and this file's rule); β rows are not repeated
    tst_beta = [0.7037, 0.9361, 0.9867, 1.006, 1.02], art_beta = [0.698182, 0.937665, 0.987636, 1.005947, 1.020946],
    tst_gamma_runs = [0.12, 0.5, 0.75], tst_gamma_means = [0.12, 0.5113, 0.75],
    art_gamma_runs = [0.07562, 0.45, 0.7], art_gamma_means = [0.07562, 0.450193, 0.715045],
    # V2b references (5T) at the matched β (G's 0.872727 and 0.933368 for Artistoo)
    v2b = [18.59, 20.40, 25.59, 32.11, 105.76],
    # V3b: the first γ > 0 sample of each (TST γ = 1e-4; Artistoo γ = 0.0195)
    v3b = [61.37, 63.09],
    # V1 context: TST mean over β = 0.25–0.5 (5 runs), Artistoo mean over β ≤ 0.52 (6 runs)
    plateau = [13.77, 13.856],
    # TST final snapshots (10⁴ cells): inhibited fraction at γ = 0.12, 0.5, 0.75 (F7.1 premise)
    tst_f7 = [0.961008, 0.978402, 0.990002],
    # furthest centroid from the colony centre, px (R = 3.989 px): β = 1.02 and γ = 0.75
    rmax_px = (beta = 490.83, gamma = 602.30))

# ---------------------------------------------------------------------------------------------
# The rules
# ---------------------------------------------------------------------------------------------

p615g_mean(t) = (isempty(t) && throw(ArgumentError("p615g_mean: no runs")); any(isinf, t) ? Inf : mean(t))
p615g_in(x, (lo, hi)) = lo <= x <= hi
# the sampled points of one sweep, ascending (the γ sweep scans γ > 0 only)
p615g_points(S, sweep) = sort([q for (sw, q) in keys(S) if sw === sweep])
# first adjacent pair (ascending) with t̄(lo) ≤ τ < t̄(hi), over the given points; nothing = "—"
function p615g_bracket(S, sweep, m; points = p615g_points(S, sweep))
    τ = p615g_tau(m)
    for i in 1:(length(points) - 1)
        a, b = p615g_mean(S[(sweep, points[i])]), p615g_mean(S[(sweep, points[i + 1])])
        a <= τ < b && return (points[i], points[i + 1])
    end
    return nothing
end
# M's rule on a bracket: the end nearest τ (ties, both Inf included, go to lo)
function p615g_threshold(S, sweep, m, br)
    br === nothing && return nothing
    τ = p615g_tau(m)
    lo, hi = br
    a, b = p615g_mean(S[(sweep, lo)]), p615g_mean(S[(sweep, hi)])
    return abs(b - τ) < abs(a - τ) ? hi : lo
end
# information: log-linear interpolation of τ between the bracket ends (NaN unless both finite)
function p615g_interp(S, sweep, m, br)
    br === nothing && return NaN
    lo, hi = br
    a, b = p615g_mean(S[(sweep, lo)]), p615g_mean(S[(sweep, hi)])
    (isfinite(a) && isfinite(b) && b > a) || return NaN
    return (lo + (hi - lo) * (log(p615g_tau(m)) - log(a)) / (log(b) - log(a))) / 10_000
end
# M's rule on a plain sample table (G, and information on Potts' own table): values v,
# mean times t (Inf allowed); nearest to τ provided min t ≤ τ < max t; ties to the lower value
function p615g_mrule(v, t, τ)
    (minimum(t) <= τ < maximum(t)) || return nothing
    best = argmin(abs.(t .- τ))
    d = abs(t[best] - τ)
    return minimum(v[j] for j in eachindex(v) if abs(t[j] - τ) == d)
end
# group repeated parameter rows: sorted unique values, mean time per value
function p615g_group(v, t)
    u = sort(unique(v))
    return u, [mean(t[j] for j in eachindex(v) if v[j] == x) for x in u]
end

# ---------------------------------------------------------------------------------------------
# The protocol (deterministic given the run times; the record tier replays it)
# ---------------------------------------------------------------------------------------------

# `exec(jobs)` runs the jobs [(sweep, q, k)] and returns their times t (cycles; Inf = capped)
function p615g_protocol(exec)
    S = Dict{Tuple{Symbol, Int}, Vector{Float64}}()
    log = Tuple{Symbol, Symbol, Int, Int}[]                         # (stage, sweep, q, k)
    function run!(jobs, stage)
        isempty(jobs) && return nothing
        t = exec(jobs)
        length(t) == length(jobs) || throw(DimensionMismatch("p615g_protocol: exec returned $(length(t)) times"))
        for ((sw, q, k), x) in zip(jobs, t)
            v = get!(S, (sw, q), Float64[])
            length(v) == k - 1 || throw(ArgumentError("p615g_protocol: replicate $k of ($sw, $q) out of order"))
            push!(v, x)
            push!(log, (stage, sw, q, k))
        end
        return nothing
    end
    # 1. grid
    run!([(sw, q, k) for sw in (:beta, :gamma) for q in P615G_GRID[sw] for k in 1:p615g_n1(sw, q)], :grid)
    # 2. brackets on the grid
    br = Dict{Tuple{Symbol, Float64}, Union{Nothing, Tuple{Int, Int}}}(tg => p615g_bracket(S, tg...) for tg in P615G_TARGETS)
    # 3. bisection
    for _ in 1:P615G_K
        mids = Dict{Tuple{Symbol, Float64}, Int}()
        jobs = Tuple{Symbol, Int, Int}[]
        for tg in P615G_TARGETS
            b = br[tg]
            b === nothing && continue
            mid = (b[1] + b[2]) ÷ 2
            (mid == b[1] || mid == b[2]) && continue
            mids[tg] = mid
            j = (tg[1], mid, 1)
            (haskey(S, (tg[1], mid)) || j in jobs) || push!(jobs, j)
        end
        run!(jobs, :bisect)
        for tg in P615G_TARGETS
            haskey(mids, tg) || continue
            lo, hi = br[tg]
            mid = mids[tg]
            br[tg] = p615g_mean(S[(tg[1], mid)]) <= p615g_tau(tg[2]) ? (mid, hi) : (lo, mid)
        end
    end
    # 4. final points: both ends to P615G_NFINAL replicates (a capped end stays as it is)
    jobs = Tuple{Symbol, Int, Int}[]
    for tg in P615G_TARGETS
        b = br[tg]
        b === nothing && continue
        for q in b
            x = S[(tg[1], q)]
            any(isinf, x) && continue
            for k in (length(x) + 1):P615G_NFINAL
                j = (tg[1], q, k)
                j in jobs || push!(jobs, j)
            end
        end
    end
    run!(jobs, :final)
    return (; S, log, br)
end

# every verdict: Dict(row => (value, ok)); `inh` maps a γ-sweep q to replicate 1's inhibited
# fraction (F7.1)
function p615g_verdicts(P, inh)
    S, br = P.S, P.br
    out = Dict{String, Tuple{Any, Bool}}()
    t0 = p615g_mean(S[(:beta, 0)])
    out["V1"] = (t0, p615g_in(t0, P615G_V1_BAND))
    for (sw, m) in P615G_TARGETS
        th = p615g_threshold(S, sw, m, br[(sw, m)])
        x = th === nothing ? NaN : th / 10_000
        out[p615g_row(sw, m)] = (x, th !== nothing && p615g_in(x, p615g_band(sw, m)))
    end
    for (q, ref) in zip(P615G_V2B, P615G_G.v2b)
        r = p615g_mean(S[(:beta, q)]) / ref
        out["V2b." * string(q / 10_000)] = (r, p615g_in(r, P615G_V2B_RATIO))
    end
    gpos = filter(>(0), p615g_points(S, :gamma))
    for m in (1.1, 2.0)
        b = p615g_bracket(S, :gamma, m; points = gpos)
        out["V3." * p615g_mid(m)] = (b === nothing ? "—" : b ./ 10_000, b === nothing)
    end
    tj = p615g_mean(S[(:gamma, 1)])
    out["V3b"] = (tj, p615g_in(tj, P615G_V3B_BAND))
    qs = [p615g_threshold(S, :gamma, m, br[(:gamma, m)]) for m in (5.0, 10.0, 20.0)]
    f7 = any(isnothing, qs) ? NaN : minimum(inh[q] for q in qs)
    out["F7.1"] = (f7, f7 >= P615G_F7_MIN)
    # controls (each must fail)
    out["NC1"] = (t0, p615g_in(t0, P615G_V3B_BAND))
    nc2 = (p615g_mean(S[(:beta, 9500)]) / P615G_G.v2b[2], p615g_mean(S[(:beta, 10_000)]) / P615G_G.v2b[4])
    out["NC2"] = (nc2, all(r -> p615g_in(r, P615G_V2B_RATIO), nc2))
    out["NC3"] = (tj, p615g_in(tj, P615G_V1_BAND))
    return out
end

# information: interpolated thresholds and thresholds relative to Potts' own uninhibited time
function p615g_information(P)
    S, br = P.S, P.br
    t0 = p615g_mean(S[(:beta, 0)])
    rel = Dict{String, Any}()
    for sw in (:beta, :gamma)
        qs = sw === :beta ? p615g_points(S, sw) : filter(>(0), p615g_points(S, sw))
        t = [p615g_mean(S[(sw, q)]) for q in qs]
        for m in P615G_MULTS
            th = p615g_mrule(qs ./ 10_000, t, t0 * m)
            rel[(sw === :beta ? "V2." : "V3.") * p615g_mid(m)] = th === nothing ? "—" : th
        end
    end
    interp = Dict(p615g_row(tg...) => p615g_interp(S, tg..., br[tg]) for tg in P615G_TARGETS)
    return (; t0, relative = rel, interp)
end

# ---------------------------------------------------------------------------------------------
# Jobs: one run per (sweep, q, k)
# ---------------------------------------------------------------------------------------------

function p615g_problem(L; cells = P615G_CELLS, cap = P615G_CAP)
    sys = OpenVTReferenceMonolayer(; name = Symbol(:p615g_m, L), lattice = (L, L))
    return PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, cap);
        capacity = ceil(Int, 1.3cells) + 100, seed = 1)
end
function p615g_job(prob, sweep, q, k; cells = P615G_CELLS, cap = P615G_CAP)
    β, γ = p615g_params(sweep, q)
    seed = p615g_seed(sweep, q, k)
    pr = remake(prob; seed, p = [:β => β, :γ => γ, :σ_X => 0.4], tspan = (0, cap))
    sol = solve(pr, P615G_ALG; callback = Potts.CorePotts.CallbackSet(PottsModels.stop_at_cells(cells),
        PottsModels.edge_guard(P615G_GUARD; terminate = true)))
    u = sol.u[end]
    N = count(>(0), Array(u.cell.volume))
    rc = Symbol(sol.retcode)
    mcs = Int(sol.t[end])
    capped = rc === :Success && N < cells && mcs == cap
    (rc === :Terminated && N >= cells) || capped ||
        throw(ErrorException("p615g_job: ($sweep, $q, $k) ended $rc at MCS $mcs with $N cells (edge guard?)"))
    return (; sweep, q, k, seed, β, γ, retcode = rc, mcs, N, capped, t = capped ? Inf : mcs / P615G_CYCLE, u)
end
# the O5 rows of a final state (Fig 7)
function p615g_o5(u; β, γ)
    o = PottsModels.openvt_snapshot(u)
    fr = PottsModels.openvt_frame(u; β, γ)
    return (; x_pos = o.x, y_pos = o.y, radius_i = o.r, inhibited = Int.(fr.i .> 0))
end

# ---------------------------------------------------------------------------------------------
# Record readers
# ---------------------------------------------------------------------------------------------

function p615g_tsv(path)
    l = split.(readlines(path), '\t')
    return [Dict(zip(l[1], r)) for r in l[2:end]]
end
p615g_ver_id(target) = first(split(target))
p615g_rtime(r) = r["capped"] == "true" ? Inf : parse(Int, r["mcs"]) / P615G_CYCLE

# ---------------------------------------------------------------------------------------------
# always: the rules and the protocol on synthetic sweeps
# ---------------------------------------------------------------------------------------------

# synthetic curves, log-linear through TST's Table 1 samples (spec §3.5) and its γ → 0⁺ jump
const P615G_SYN = (
    beta = ([0.0, 0.7037, 0.9361, 0.9867, 1.006, 1.02, 1.031], [13.7, 14.74, 27.07, 67.54, 133.52, 275.21, 598.11]),
    gamma = ([1e-4, 0.12, 0.5, 0.75, 0.95], [61.37, 68.34, 132.14, 278.78, 566.08]))
function p615g_syn(sweep, q; shift = 0.0, scale = 1.0)
    sweep === :gamma && q == 0 && return 13.7 * scale
    x, y = P615G_SYN[sweep]
    v = q / 10_000 + shift
    v <= x[1] && return y[1] * scale
    v >= x[end] && return Inf
    i = findlast(<=(v), x)
    t = exp(log(y[i]) + (log(y[i + 1]) - log(y[i])) * (v - x[i]) / (x[i + 1] - x[i])) * scale
    return t > p615g_tau(20.0) ? Inf : t
end
p615g_syn_exec(; kw...) = jobs -> [p615g_syn(sw, q; kw...) for (sw, q, _) in jobs]

@testset "P6.15g rules and protocol on synthetic sweeps" begin
    @test [p615g_tau(m) for m in P615G_MULTS] == [14.927, 27.14, 67.85, 135.7, 271.4]
    @test P615G_CAP == round(Int, p615g_tau(20.0) * P615G_CYCLE)
    @test p615g_seed(:beta, 0, 1) == 160_000_001 && p615g_seed(:gamma, 1, 5) == 170_000_105
    @test p615g_params(:beta, 9334) == (0.9334, 0.0) && p615g_params(:gamma, 1) == (0.0, 1e-4)
    # every seed of every possible point is distinct across sweeps
    @test p615g_seed(:beta, 10_300, P615G_NFINAL + 10) < p615g_seed(:gamma, 0, 1)
    @test all(issorted, P615G_GRID) && all(in(P615G_GRID.beta), P615G_V2B) && 1 in P615G_GRID.gamma
    @test p615g_mean([1.0, 3.0]) == 2 && p615g_mean([1.0, Inf]) == Inf
    @test p615g_band(:beta, 5.0) == (0.9817, 0.9966) && p615g_band(:gamma, 10.0) == (0.4, 0.55)
    # the rules on a hand table
    S = Dict((:beta, 0) => [10.0], (:beta, 1) => [14.0], (:beta, 2) => [16.0], (:beta, 3) => [Inf])
    @test p615g_bracket(S, :beta, 1.1) == (1, 2) && p615g_threshold(S, :beta, 1.1, (1, 2)) == 1   # |14 − 14.927| < |16 − 14.927|
    @test p615g_bracket(S, :beta, 20.0) == (2, 3) && p615g_threshold(S, :beta, 20.0, (2, 3)) == 2
    @test p615g_threshold(Dict((:beta, 1) => [Inf], (:beta, 2) => [Inf]), :beta, 20.0, (1, 2)) == 1   # tie → lo
    @test p615g_bracket(Dict((:beta, 0) => [15.0], (:beta, 1) => [16.0]), :beta, 1.1) === nothing  # "—"
    @test p615g_mrule([0.1, 0.2, 0.3], [10.0, 20.0, 30.0], 24.0) == 0.2
    @test p615g_mrule([0.1, 0.2], [10.0, 30.0], 20.0) == 0.1                                       # tie → lower
    @test p615g_mrule([0.1, 0.2], [30.0, 40.0], 20.0) === nothing
    @test p615g_group([0.5, 0.4, 0.5], [1.0, 2.0, 3.0]) == ([0.4, 0.5], [2.0, 2.0])

    # the protocol on the TST-shaped curves
    P = p615g_protocol(p615g_syn_exec())
    @test p615g_protocol(p615g_syn_exec()).log == P.log                                            # deterministic
    @test count(e -> e[1] === :grid, P.log) ==
          sum(p615g_n1(sw, q) for sw in (:beta, :gamma) for q in P615G_GRID[sw])
    @test count(e -> e[1] === :bisect, P.log) <= P615G_K * length(P615G_TARGETS)
    @test all(e -> e[4] <= P615G_NFINAL || (e[2], e[3]) == (:beta, 0), P.log)
    for tg in P615G_TARGETS
        b = P.br[tg]
        @test b !== nothing
        x = [P.S[(tg[1], q)] for q in b]
        @test all(v -> length(v) >= P615G_NFINAL || any(isinf, v), x)                               # final points
    end
    p615g_inh(P, f) = Dict(q => f for q in p615g_points(P.S, :gamma))
    ver = p615g_verdicts(P, p615g_inh(P, 0.97))
    @test sort(collect(keys(ver))) == sort([P615G_ROWS; P615G_CONTROLS])
    # the design resolves TST's own curve inside every band (the protocol's premise) …
    for r in P615G_ROWS
        r == "V1" && continue                                     # 13.7 ∈ band, checked below
        r in ("V2b.0.8727", "V2b.0.9334") && continue             # Artistoo references, not TST's curve
        @test ver[r][2]
    end
    @test ver["V1"][2] && ver["V3.1.1x"] == ("—", true) && ver["V3.2x"] == ("—", true)
    # … the controls fail on it …
    @test !ver["NC1"][2] && !ver["NC2"][2] && !ver["NC3"][2]
    # … and the bisection sharpens the grid: the 5× β threshold lies within 0.002 of TST's 0.9867
    @test abs(ver["V2.5x"][1] - 0.9867) < 0.002 && abs(ver["V2.10x"][1] - 1.006) < 0.002

    # each row can fail on its own
    Ps = p615g_protocol(p615g_syn_exec(; scale = 1.118))                                         # D-173's 15.17 / 13.57
    slow = p615g_verdicts(Ps, p615g_inh(Ps, 0.97))
    @test !slow["V1"][2] && !slow["V2.1.1x"][2] && slow["V2.1.1x"][1] === NaN                      # "—": no crossing at 14.927
    Pd = p615g_protocol(p615g_syn_exec(; shift = 0.02))                                          # curve 0.02 to the left
    shifted = p615g_verdicts(Pd, p615g_inh(Pd, 0.97))
    @test !shifted["V2.5x"][2] && !shifted["V2.10x"][2] && !shifted["V2.20x"][2] && shifted["V1"][2]
    @test !p615g_verdicts(P, p615g_inh(P, 0.5))["F7.1"][2]
    # a capped end is not topped up, and the 20× threshold is the finite end
    q20 = P.br[(:beta, 20.0)]
    @test any(isinf, P.S[(:beta, q20[2])]) && length(P.S[(:beta, q20[2])]) < P615G_NFINAL
    @test p615g_threshold(P.S, :beta, 20.0, q20) == q20[1]
    # information
    info = p615g_information(P)
    @test info.t0 == 13.7 && info.relative["V3.1.1x"] == "—" && isfinite(info.interp["V2.5x"])

    # replay: a record holding exactly the protocol's runs replays to the same log; an extra
    # or a missing run is detected
    times = Dict((e[2], e[3], e[4]) => p615g_syn(e[2], e[3]) for e in P.log)
    lookup = jobs -> [times[j] for j in jobs]
    R = p615g_protocol(lookup)
    @test Set((e[2], e[3], e[4]) for e in R.log) == Set(keys(times)) && R.log == P.log
    missing_one = copy(times)
    delete!(missing_one, (P.log[end][2], P.log[end][3], P.log[end][4]))
    @test_throws KeyError p615g_protocol(jobs -> [missing_one[j] for j in jobs])

    # the G constants have the rules' form, and G's own samples pass the bands (audit premises)
    @test length(P615G_G.tst_beta) == length(P615G_G.art_beta) == 5 && length(P615G_G.v2b) == length(P615G_V2B)
    for (j, m) in enumerate(P615G_MULTS)
        @test p615g_in(P615G_G.tst_beta[j], p615g_band(:beta, m)) && p615g_in(P615G_G.art_beta[j], p615g_band(:beta, m))
    end
    for (j, m) in enumerate((5.0, 10.0, 20.0)), k in (:tst_gamma_runs, :tst_gamma_means, :art_gamma_runs, :art_gamma_means)
        @test p615g_in(P615G_G[k][j], p615g_band(:gamma, m))
    end
    @test all(x -> p615g_in(x, P615G_V3B_BAND), P615G_G.v3b) && all(x -> p615g_in(x, P615G_V1_BAND), P615G_G.plateau)
    @test all(>=(P615G_F7_MIN), P615G_G.tst_f7)
    @test 1.1 * P615G_G.rmax_px.beta + P615G_GUARD + 10 < P615G_LATTICE.beta / 2
    @test 1.1 * P615G_G.rmax_px.gamma + P615G_GUARD + 10 < P615G_LATTICE.gamma / 2
end

# ---------------------------------------------------------------------------------------------
# SMOKE: three jobs through the FULL job function on 200², 300-cell stop
# ---------------------------------------------------------------------------------------------

if !P615G_FULL
    @testset "P6.15g SMOKE: uninhibited, γ = 1e-4 and a capped β = 1.03 job" begin
        prob = p615g_problem(300; cells = 250, cap = 20_000)
        free = p615g_job(prob, :beta, 0, 1; cells = 250, cap = 20_000)
        jump = p615g_job(prob, :gamma, 1, 1; cells = 250, cap = 20_000)
        cap = p615g_job(prob, :beta, 10_300, 1; cells = 250, cap = 1500)
        @info "P6.15g SMOKE" free.t jump.t cap.mcs cap.N
        @test free.retcode === :Terminated && free.N >= 250 && !free.capped && free.t == free.mcs / P615G_CYCLE
        @test free.seed == 160_000_001 && jump.seed == 170_000_101
        @test jump.retcode === :Terminated && jump.N >= 250
        @test jump.t >= 1.3 * free.t                         # the γ → 0⁺ jump's mechanism
        @test cap.capped && cap.t == Inf && cap.mcs == 1500 && cap.N < 250 && cap.retcode === :Success
        # same seed, same run
        again = p615g_job(prob, :beta, 10_300, 1; cells = 250, cap = 1500)
        @test again.N == cap.N && Array(again.u.σ) == Array(cap.u.σ)
        # O5 rows: the uninhibited colony grows everywhere; γ = 1e-4 arrests the interior
        o_free = p615g_o5(free.u; β = 0.0, γ = 0.0)
        o_jump = p615g_o5(jump.u; β = 0.0, γ = 1e-4)
        @test length(o_free.x_pos) == free.N && all(==(0), o_free.inhibited)
        @test 0.3 < mean(o_jump.inhibited) < 1
        io = IOBuffer()
        write_openvt(io, :O5, o_jump)
        @test startswith(String(take!(io)), "x_pos,y_pos,radius_i,inhibited\n")
    end
end

# ---------------------------------------------------------------------------------------------
# G: recompute the frozen consortium constants
# ---------------------------------------------------------------------------------------------

function p615g_csv(path)
    l = split.(filter(!isempty ∘ strip, readlines(path)), ',')
    v = [parse(Float64, r[1]) for r in l[2:end]]
    t = [parse(Float64, r[3]) for r in l[2:end]]
    keep = isfinite.(t)                                        # TST's "nan" rows were not run
    return v[keep], t[keep]
end
function p615g_g_reference(G)
    R = joinpath(G, "results")
    th(v, t, ms) = [p615g_mrule(p615g_group(v, t)..., p615g_tau(m)) for m in ms]       # nearest point mean
    thr(v, t, ms) = [p615g_mrule(v, t, p615g_tau(m)) for m in ms]                     # nearest run
    tb = p615g_csv(joinpath(R, "TST", "TST_time_to_10k_vs_beta.csv"))
    tg = p615g_csv(joinpath(R, "TST", "TST_time_to_10k_vs_gamma.csv"))
    ab = p615g_csv(joinpath(R, "Artistoo", "Monolayer", "time_to_10k_vs_beta.csv"))
    ag = p615g_csv(joinpath(R, "Artistoo", "Monolayer", "time_to_10k_vs_gamma.csv"))
    at(v, t, x) = only(t[j] for j in eachindex(v) if v[j] == x)
    v2b = [at(ab..., 0.872727), at(tb..., 0.9), at(ab..., 0.933368), at(tb..., 0.95), at(tb..., 1.0)]
    plateau = [mean(tb[2][j] for j in eachindex(tb[1]) if 0.25 <= tb[1][j] <= 0.5),
        mean(ab[2][j] for j in eachindex(ab[1]) if ab[1][j] <= 0.52)]
    snap = joinpath(R, "TST", "final_snapshot_data")
    function snapshot(name)
        rows = [parse.(Float64, split(l, ',')) for l in readlines(joinpath(snap, name))[2:end] if !isempty(strip(l))]
        x, y = first.(rows), getindex.(rows, 2)
        cx, cy = mean(x), mean(y)
        return (; inh = mean(r[4] for r in rows), rmax = maximum(hypot.(x .- cx, y .- cy)) * sqrt(50 / π))
    end
    f7 = [snapshot("TST_beta_0.0_gamma_$(g)_$(m)MCS.csv") for (g, m) in (("0.12", 52965), ("0.5", 103309), ("0.75", 216055))]
    b102 = snapshot("TST_beta_1.02_gamma_0_213287MCS.csv")
    dash = [p615g_mrule(p615g_group(v, t)..., p615g_tau(m)) for (v, t) in (tg, ag) for m in (1.1, 2.0)]
    G3 = (5.0, 10.0, 20.0)
    return (; tst_beta = th(tb..., P615G_MULTS), art_beta = th(ab..., P615G_MULTS),
        beta_runs = (thr(tb..., P615G_MULTS), thr(ab..., P615G_MULTS)),
        tst_gamma_runs = thr(tg..., G3), tst_gamma_means = th(tg..., G3),
        art_gamma_runs = thr(ag..., G3), art_gamma_means = th(ag..., G3), v2b,
        v3b = [minimum(tg[2]), at(ag..., 0.0195)], plateau, tst_f7 = [s.inh for s in f7],
        rmax_px = (beta = b102.rmax, gamma = f7[3].rmax), dash)
end

@testset "P6.15g G: consortium constants from the TST and Artistoo sweeps" begin
    if isempty(P615G_REPO) || !isdir(joinpath(P615G_REPO, "results"))
        @test_skip "OPENVT_MONOLAYER_REPO not set"
    else
        g = p615g_g_reference(P615G_REPO)
        @info "P6.15g G" g
        for k in (:tst_beta, :art_beta, :tst_gamma_runs, :tst_gamma_means, :art_gamma_runs, :art_gamma_means, :v2b, :v3b)
            @test isapprox(g[k], P615G_G[k]; rtol = 1e-6)
        end
        @test g.beta_runs == (g.tst_beta, g.art_beta)          # no repeated β rows: both rules agree
        @test isapprox(g.plateau, P615G_G.plateau; atol = 0.005)
        @test isapprox(g.tst_f7, P615G_G.tst_f7; atol = 1e-6)
        @test isapprox(g.rmax_px.beta, P615G_G.rmax_px.beta; atol = 0.01) &&
              isapprox(g.rmax_px.gamma, P615G_G.rmax_px.gamma; atol = 0.01)
        @test all(isnothing, g.dash)                           # lattice γ rows: "—" at 1.1× and 2×
    end
end

# ---------------------------------------------------------------------------------------------
# FULL record (D-146): replay the protocol on the recorded times and recompute every row
# ---------------------------------------------------------------------------------------------

function p615g_check(ver, devs; broken_ok)
    for row in P615G_ROWS
        haskey(ver, row) || (@test haskey(ver, row); continue)
        ok = ver[row][2]
        if ok
            @test ok
        elseif broken_ok
            # a failing row is a D-154 deviation: it must be in the record's table
            @test any(d -> p615g_ver_id(d["target"]) == row, devs)
            @test_broken ok
        else
            @test ok
        end
    end
    for c in P615G_CONTROLS
        @test !ver[c][2]                                     # the controls fail
    end
end

@testset "P6.15g FULL record: V1, V2, V2b, V3, V3b, F7 and the controls" begin
    dirs = isdir(P615G_DATA) ? filter(d -> startswith(d, "sweeps-") && isdir(joinpath(P615G_DATA, d)), readdir(P615G_DATA)) :
           String[]
    length(dirs) == 1 || @info "P6.15g: no record yet (expected exactly one reproductions/data/15/sweeps-* directory)" dirs
    @test length(dirs) == 1
    if length(dirs) == 1
        D = joinpath(P615G_DATA, only(dirs))
        for f in ("runs.tsv", "verdicts.tsv", "provenance.toml", "Potts.jl_time_to_10k_vs_beta.csv",
            "Potts.jl_time_to_10k_vs_gamma.csv")
            @test isfile(joinpath(D, f))
        end
        runs = p615g_tsv(joinpath(D, "runs.tsv"))
        rec = Dict{Tuple{Symbol, Int, Int}, Dict{String, String}}()
        for r in runs
            sw, q, k = Symbol(r["sweep"]), parse(Int, r["q"]), parse(Int, r["k"])
            @test !haskey(rec, (sw, q, k))
            rec[(sw, q, k)] = r
            # each run is the pre-registered job
            β, γ = p615g_params(sw, q)
            @test parse(Int, r["seed"]) == p615g_seed(sw, q, k)
            @test parse(Float64, r["beta"]) == β && parse(Float64, r["gamma"]) == γ
            @test parse(Int, r["lattice"]) == P615G_LATTICE[sw]
            m, N = parse(Int, r["mcs"]), parse(Int, r["N"])
            if r["capped"] == "true"
                @test r["retcode"] == "Success" && m == P615G_CAP && N < P615G_CELLS
            else
                @test r["retcode"] == "Terminated" && N >= P615G_CELLS && m <= P615G_CAP
            end
            @test parse(Int, r["edge_gap"]) >= P615G_GUARD
        end
        # replay: the record holds exactly the protocol's runs, with its stage labels
        P = p615g_protocol(jobs -> [p615g_rtime(rec[j]) for j in jobs])
        @test Set((e[2], e[3], e[4]) for e in P.log) == Set(keys(rec))
        @test all(e -> rec[(e[2], e[3], e[4])]["stage"] == string(e[1]), P.log)
        # O3 tables: one row per run of each sweep, the same MCS (NaN when capped)
        for sw in (:beta, :gamma)
            o3 = read_openvt(joinpath(D, "Potts.jl_time_to_10k_vs_$(sw).csv"), :O3)
            mine = sort([(q / 10_000, rec[(s, q, k)]["capped"] == "true" ? NaN : parse(Float64, rec[(s, q, k)]["mcs"]))
                         for (s, q, k) in keys(rec) if s === sw]; by = x -> (x[1], isnan(x[2]) ? Inf : x[2]))
            got = sort(collect(zip(o3[sw], o3.mcs)); by = x -> (x[1], isnan(x[2]) ? Inf : x[2]))
            @test length(got) == length(mine) && all(((a, b),) -> a[1] == b[1] && isequal(a[2], b[2]), zip(got, mine))
        end
        # Fig 7 panels: γ = 0, γ = 1e-4 and the three T1 γ thresholds, replicate 1
        qs = Int[p615g_threshold(P.S, :gamma, m, P.br[(:gamma, m)]) for m in (5.0, 10.0, 20.0)
                 if P.br[(:gamma, m)] !== nothing]
        inh = Dict{Int, Float64}()
        f7 = joinpath(D, "f7")
        for (sw, q) in [(:beta, 0); (:gamma, 1); [(:gamma, q) for q in qs]]
            r = rec[(sw, q, 1)]
            γs = sw === :beta ? 0.0 : q / 10_000
            f = joinpath(f7, "Potts.jl_gamma_$(γs)_$(r["mcs"])MCS.csv")
            @test isfile(f)
            isfile(f) || continue
            o5 = read_openvt(f, :O5)
            @test length(o5.x_pos) == parse(Int, r["N"])
            sw === :gamma && (inh[q] = mean(o5.inhibited))
            sw === :beta && @test all(==(0), o5.inhibited)
        end
        for q in qs
            haskey(inh, q) || (inh[q] = NaN)
        end
        ver = p615g_verdicts(P, inh)
        info = p615g_information(P)
        @info "P6.15g record" Dict(k => v[1] for (k, v) in ver) info
        dev_f = joinpath(D, "deviations.tsv")
        devs = isfile(dev_f) ? p615g_tsv(dev_f) : Dict{String, String}[]
        p615g_check(ver, devs; broken_ok = true)
        # the committed verdicts agree with this recomputation
        vt = p615g_tsv(joinpath(D, "verdicts.tsv"))
        for row in [P615G_ROWS; P615G_CONTROLS]
            rr = [r for r in vt if p615g_ver_id(r["target"]) == row]
            @test length(rr) == 1 && only(rr)["result"] == (ver[row][2] ? "PASS" : "FAIL")
        end
    end
end

# ---------------------------------------------------------------------------------------------
# FULL: rerun the protocol (offline, on the PC; D-146, D-157)
# ---------------------------------------------------------------------------------------------

if P615G_FULL
    @testset "P6.15g FULL: the sweeps, rerun" begin
        probs = Dict(sw => p615g_problem(P615G_LATTICE[sw]) for sw in (:beta, :gamma))
        inh = Dict{Int, Float64}()
        lk = ReentrantLock()
        function exec(jobs)
            out = Vector{Float64}(undef, length(jobs))
            Threads.@threads :greedy for j in eachindex(jobs)
                sw, q, k = jobs[j]
                r = p615g_job(probs[sw], sw, q, k)
                out[j] = r.t
                if sw === :gamma && k == 1
                    f = mean(p615g_o5(r.u; β = r.β, γ = r.γ).inhibited)
                    lock(() -> (inh[q] = f), lk)
                end
            end
            return out
        end
        P = p615g_protocol(exec)
        ver = p615g_verdicts(P, inh)
        @info "P6.15g FULL" Dict(k => v[1] for (k, v) in ver) p615g_information(P)
        p615g_check(ver, Dict{String, String}[]; broken_ok = false)
    end
end
