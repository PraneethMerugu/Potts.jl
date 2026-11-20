# reproduction 10, Akeeb, Marcus & Jiang (2026), against
# the authors' released data. The pre-registered V-targets
# are spec 10 §5.2 as audited in §5.3 (docs/design/research/model-specs/10_akeeb_invasion.md);
# every reference value, tolerance, point, seed and run length below is copied from there.
# The tutorial page `lib/PottsModels/reproductions/10_akeeb.jl` carries the same table.
#
# Surface fixed by the coordinator (implemented in `10_akeeb_tests.jl`):
#
#   AkeebInvasion(; name, …) has the default μ = 24 (D-050 A5, confirmed by D-142).
#
#   akeeb_observables(σ::AbstractMatrix{<:Integer}, kinds::AbstractVector{Symbol}) -> NamedTuple
#   akeeb_observables(u) = akeeb_observables(u.ownership, <kinds of u's cells as :leader / :follower>)
#                                                            (PottsModels, exported)
#     The authors' metric code at one state, spec 10 §5.3.3 O1–O8, on a 2-D lattice with x
#     (first index) periodic and y (second index) closed. Cell c is σ's value c, kinds[c]
#     its kind; an id that owns no site is not a cell (counts nothing, as CC3D's empty
#     leaders, whose yCOM is 0). 1-based: the authors' row y = 1 is our y = 2.
#       O1 adjacency: two cells are neighbours iff they own von Neumann-adjacent sites
#          (x periodic). Medium is not a cell.
#       O2 main tumour M: the O1 components of the cells owning a site in row y = 2 with
#          x ∈ 1:X−1 (the authors' x range skips the last column).
#       O3 profiles: top_main(x) = largest y with σ ∈ M, top_out(x) = largest y with
#          σ ≠ 0; keep the columns where both exist, in x order; base = min of the kept
#          top_main.
#       O4 invasive = trapezoid_integral(x_kept, top_main − base), infiltrative = trapezoid_integral(x_kept,
#          top_out − base), Float64, px², not periodic.
#       O5 fingers = length(merge_peaks(find_peaks(top_main_kept; prominence = 10,
#          distance = 10, width = 5), 15)) (PottsModels.Analysis; on the kept-column array
#          index, not on x).
#       O6 singles: leaders with no O1 neighbour and yCOM > min over c ∈ M of yCOM(c).
#       O7 detached: cells ∉ M (any kind) with yCOM > min over M of yCOM.
#       O8 clusters: the O1 components outside M with ≥ 2 cells and ≥ 1 follower
#          (leader-only components never count, D17). No y condition.
#     Fields: invasive, infiltrative (Float64); singles, fingers, detached, clusters (Int);
#     cluster_leaders, cluster_followers (Vector{Int}: the leaders and followers of each
#     counted cluster, clusters ordered by their smallest cell id).
#
# Time mapping (spec 10 §5.3.2): the authors' "MCS t" is our state after t + 1 MCS. Every
# run is `SequentialCPM(; proposal = VonNeumann(1))` from `akeeb_state(; pp, seed)` with
# `capacity = 4000`, solver seed = state seed.
#
# Tiers. SMOKE runs in the PottsModels suite (about 1 min on one thread). FULL runs with
# POTTS_FULL_REPRODUCTION=true (or REPRO=full): the spec's CI tier (9 points × 10 runs) and
# its FULL tier (the PP = 0.5 slice, 121 × 10 runs, ≈ 1.7 CPU-h). Spec n is 10 per point;
# SMOKE uses fewer runs only for rows whose verdict does not depend on n (exact rows) or
# that hold with a wide margin at the smaller n (stated per row).
#
# | Row | Target (spec 10 §5.2/§5.3) | Rule / tolerance | SMOKE | FULL |
# |---|---|---|---|---|
# | V-A0 | P1 after one sweep: invasive 499.4 ± 5.3 px², infiltrative = invasive, counts 0 (B, MCS 0) | R1 | n = 10 × 1 MCS | same |
# | V-A1 (a) | 1169 followers (3 × 3 tiles, last column 2 × 3); leader inventory 390 (counted, MD-1) | exact | 10 layouts | same |
# | V-A1 (b) | leaders never divide and are never lost | exact | P1 n = 4 | P1 n = 10 |
# | V-A1 (c) | divisions by the MCS-700 snapshot 578 | \|mean − 578\| ≤ 55 | P1 n = 4 (see the row) | P1 n = 10 |
# | V-A2 | six metrics at P1–P8 (A, §5.3.4), 48 tests | R1 | — | n = 10 per point |
# | V-A3 | fingers / singles / clusters marginals over the PP = 0.5 slice | R2 | — | 1210 runs |
# | V-A4 | invasive / infiltrative marginals; order; ratios 4.25 and 8.56 | R2; strict; ±15 % | — | 1210 runs |
# | V-A5 | cluster incidence 28.3 % (N 1209), 71.5 % at λ ≥ 24 (N 330); 4.85 ± 0.24 when present | R3; R2 | — | 1210 runs |
# | V-A6 | phenotype fractions 22 / 1 / 23 / 54 % (A classified: 2950 / 143 / 2989 / 7181 of 13,263) | R3 per phenotype; READY (D-163), classifier `akeeb_phenotype` provisional (author question 1) | — | FULL record: recomputed from the committed 13,310-run sweep (`10_akeeb_tests.jl`) |
# | V-A7 | P1, P7, P9 each match their own reference | R1 (P9 adds 6) | — | n = 10 |
# | V-A8 | cluster composition, pooled (C): P1 mean size 5.79 (SD 3.75, 75), leader fraction 0.578; P2 5.56 (3.71, 143), 0.517 | R1 with clusters as units; ±0.10 | — | P1, P2 n = 10 |
# | V-A8 paper | "mean ≈ 7 cells, 60–70 % leaders, median 4 L / 3 F" | PARKED (not reproducible from the release) | — | — |
# | V-A9 | leader speed 0.4 px/MCS at λ = 20 | PARKED (undefined; no code or data) | — | — |
# | V-A10 | morphology at 0, 350, 700 per phenotype | not gating (tutorial videos) | — | — |
# | V-A11 | P1 time course at MCS 100 / 300 / 500 (B), 18 tests | R1 | — | P1 runs, snapshots |
# | V-C1 | PP = 0: no division ever, live count constant (P7) | exact | P7 n = 2 | P7 n = 10 |
# | V-C2 | λ = 0 (P8): clusters 0 in every run; singles, fingers, detached mean ≤ 1 | exact; mean ≤ 1 | P8 n = 2 (clusters) | P8 n = 10 |
# | per run | infiltrative ≥ invasive; detached ≥ singles (hold in A, B and C) | exact | every SMOKE run and save | every run and save |
#
# R1 (per point): |μ_B − μ_A| ≤ max(3·√(s_A²/n_A + s_B²/n_B), 0.10·|μ_A|, f_m), f_m = 0
# for areas, 1.0 for the counts (singles, fingers, detached, clusters).
# R2 (slice marginal): R1 with SE = SD_runs/√N on both sides.
# R3 (incidence): |p_B − p_A| ≤ max(3·√(p_A(1−p_A)/N_A + p_B(1−p_B)/N_B), 0.05).
#
# Negative controls (D-048): the state before any sweep fails V-A0 (the time mapping is
# not vacuous); P1 runs divide (V-C1's 0 is not vacuous) and have clusters (V-C2's 0 is not
# vacuous); P8 (λ = 0) fails P1's invasive reference (λ drives invasion; R1 can fail); the
# oracle lattices below are built so that each wrong reading of O1–O8 (seed row, last
# column, periodicity, Moore adjacency, follower singles, leader-only clusters, distance
# vs merge) changes a hand-derived value.
#
# The rules are checked against the authors' own independent ensembles (spec 10 §5.3.3:
# R1 on B and C against A at P1–P8 96/96; B against C over MCS 0–500 24/24; R2, R3 and the
# V-A4 order and ratios on B and C against A), and the reference constants against
# dataset A, when the released data are on disk (`docs/references` is gitignored; point
# POTTS_REFERENCES at a checkout that has it, otherwise those testsets are skipped).

@testsetup module AkeebSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts, PottsModels, Test
using Statistics: mean, std
const AKEEB_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const METRICS = (:invasive, :infiltrative, :singles, :fingers, :detached, :clusters)
const FLOOR = (; invasive = 0.0, infiltrative = 0.0, singles = 1.0, fingers = 1.0, detached = 1.0, clusters = 1.0)
# ---------------------------------------------------------------------------------------------
# Pass rules (spec 10 §5.3.3)
# ---------------------------------------------------------------------------------------------
akeeb_r1(μA, sA, nA, μB, sB, nB, f) = abs(μB - μA) <= max(3 * sqrt(sA^2 / nA + sB^2 / nB), 0.1 * abs(μA), f)
akeeb_r2(μA, seA, μB, seB, f) = abs(μB - μA) <= max(3 * sqrt(seA^2 + seB^2), 0.1 * abs(μA), f)
akeeb_r3(pA, NA, pB, NB) = abs(pB - pA) <= max(3 * sqrt(pA * (1 - pA) / NA + pB * (1 - pB) / NB), 0.05)
akeeb_sd(v) = length(v) > 1 ? std(v) : 0.0
# R1 of our runs `v` (one value per run) against a reference (mean, SD, n)
akeeb_r1(ref::Tuple, v::AbstractVector, f) = akeeb_r1(ref[1], ref[2], ref[3], mean(v), akeeb_sd(v), length(v), f)
# ---------------------------------------------------------------------------------------------
# References, verbatim from spec 10 §5.3.4 (dataset A, MCS 700, n = 10; "= invasive" rows
# copy the invasive entry; "0" is 0 ± 0) and §5.2
# ---------------------------------------------------------------------------------------------

# (J_LF, λ, PP)
const POINTS = (
    P1 = (2.0, 24.0, 0.5), P2 = (2.0, 30.0, 0.5), P3 = (5.0, 30.0, 0.5), P4 = (-2.0, 15.0, 0.5),
    P5 = (5.0, 3.0, 0.5), P6 = (-2.0, 6.0, 0.5), P7 = (2.0, 24.0, 0.0), P8 = (2.0, 0.0, 0.5), P9 = (2.0, 24.0, 1.0),
)
# (mean, SD) per metric in METRICS order
const REF_A = (
    P1 = ((15734, 1362), (44029, 1669), (204.5, 9.3), (12.0, 1.2), (239.4, 11.1), (5.5, 2.3)),
    P2 = ((12903, 1185), (50860, 1827), (246.8, 9.8), (10.4, 1.3), (312.2, 14.1), (11.2, 2.7)),
    P3 = ((4771, 935), (54495, 981), (290.3, 6.7), (4.5, 1.1), (320.5, 12.2), (1.4, 1.1)),
    P4 = ((4897, 826), (4897, 826), (0, 0), (4.2, 1.5), (0, 0), (0, 0)),
    P5 = ((2707, 282), (2950, 289), (6.7, 2.4), (0.7, 0.8), (6.7, 2.4), (0, 0)),
    P6 = ((2155, 261), (2155, 261), (0, 0), (0.1, 0.3), (0, 0), (0, 0)),
    P7 = ((15319, 1873), (46006, 1286), (204.3, 7.9), (11.1, 1.4), (249.9, 16.1), (7.0, 2.1)),
    P8 = ((1963, 300), (1963, 300), (0, 0), (0, 0), (0, 0), (0, 0)),
    P9 = ((16493, 2294), (42656, 2888), (201.8, 6.4), (11.7, 1.9), (228.4, 12.5), (4.5, 1.8)),
)
const N_A = 10
# Time course at P1, dataset B, n = 10 (V-A0 at MCS 0, V-A11 at 100 / 300 / 500)
const REF_B = Dict(
    0 => ((499.4, 5.3), (499.4, 5.3), (0, 0), (0, 0), (0, 0), (0, 0)),
    100 => ((3666, 515), (3765, 499), (3.2, 1.5), (3.8, 1.1), (3.2, 1.5), (0, 0)),
    300 => ((9261, 1576), (12657, 1708), (57.7, 4.5), (9.3, 1.6), (58.8, 5.3), (0.1, 0.3)),
    500 => ((15108, 933), (28345, 1187), (139.2, 7.1), (10.8, 1.3), (148.1, 6.3), (1.4, 0.5))
)
const N_B = 10
# V-A1 (c): divisions by the MCS-700 snapshot (sample CellCount_2_24_0.5.csv: 2137 − 1559)
const DIVISIONS, DIVISIONS_TOL = 578, 55
# V-A3 / V-A4 / V-A5: PP = 0.5 slice marginals, (mean, SE)
const SLICE_SETS = (
    J_mid = k -> -1 <= k[1] <= 2, J_strong = k -> k[1] <= -2, J_weak = k -> k[1] > 2,
    λ_high = k -> k[2] >= 20, λ_low = k -> k[2] < 10, λ_24 = k -> k[2] >= 24,
)
const REF_SLICE = [
    # V-A3
    (:fingers, :J_mid, 7.2, 0.24), (:fingers, :λ_high, 9.78, 0.15), (:fingers, :J_strong, 3.99, 0.22),
    (:fingers, :J_weak, 6.08, 0.2),
    (:singles, :J_weak, 175.94, 6.6), (:singles, :J_strong, 1.46, 0.22), (:singles, :J_mid, 52.94, 3.37),
    (:clusters, :J_mid, 1.63, 0.15), (:clusters, :J_weak, 1.77, 0.16),
    # V-A4
    (:invasive, :J_strong, 5381, 206), (:invasive, :J_mid, 10301, 335), (:invasive, :J_weak, 6658, 192),
    (:invasive, :λ_high, 12173, 275), (:invasive, :λ_low, 2866, 53),
    (:infiltrative, :λ_high, 30351, 860), (:infiltrative, :λ_low, 3545, 133),
]
const RATIO = (invasive = 4.25, infiltrative = 8.56)
# λ ≥ 20 over λ < 10; ±15 %
const INCIDENCE = ((:all, 0.283, 1209), (:λ_24, 0.715, 330))
const CLUSTERS_WHEN_PRESENT = (4.85, 0.24)
# λ ≥ 24, mean ± SE
# V-A8: pooled cluster composition at MCS 700 (dataset C): mean size, per-cluster SD, clusters,
# pooled leader fraction
const REF_C = (P1 = (5.79, 3.75, 75, 0.578), P2 = (5.56, 3.71, 143, 0.517))
# the scan grid (S:37–39): J_LF ∈ −5:5, λ ∈ 0:3:30
const SLICE = [(Float64(j), Float64(l), 0.5) for j in -5:5 for l in 0:3:30]
# ---------------------------------------------------------------------------------------------
# Runs
# ---------------------------------------------------------------------------------------------

# Pre-registered seeds: point Pk, run i → 10_000k + i; V-A0 → 10_000·10 + i; slice point j
# (SLICE order) → 1_000_000 + 100j + i
akeeb_seed(k::Int, i::Int) = 10_000k + i
const SAVES = [1, 101, 301, 501, 701]
const ALG = SequentialCPM(; proposal = VonNeumann(1))
const BASE = PottsProblem(AkeebInvasion(; name = :akeeb), akeeb_state(; seed = 1), (0, 701); capacity = 4000, seed = 1)
# One record per run: observables at each save (authors' t ↦ our t + 1), the lifecycle
# division count, and the V-A1 (b) / V-C1 bookkeeping.
function akeeb_run(point, seeds; tmax = 701, saves = SAVES)
    jlf, μ, pp = point
    prob_func(q, ctx) = (
        s = seeds[ctx.sim_id];
        remake(
            q; u0 = akeeb_state(; pp, seed = s), p = [:μ => μ, :J => akeeb_contacts(jlf)], seed = s,
            tspan = (0, tmax)
        )
    )
    ens = solve(
        EnsembleProblem(BASE; prob_func), ALG, EnsembleThreads();
        trajectories = length(seeds), saveat = saves
    )
    return map(enumerate(ens.u)) do (i, sol)
        kinds0 = layout(akeeb_layout(; seed = seeds[i]), (500, 300))[2].second
        u0, u1 = sol.u[findfirst(==(0), sol.t)], sol.u[end]
        L = findall(==(:leader), kinds0)
        lc = u0.cell.kind[first(L)]                         # the leader kind's code
        alive1 = falses(length(u1.cell.kind))
        for c in u1.ownership
            c > 0 && (alive1[c] = true)
        end
        (;
            obs = Dict(Int(t) - 1 => akeeb_observables(sol.u[findfirst(==(t), sol.t)]) for t in saves),
            divisions = sol.stats.lifecycle.divisions,
            live0 = length(unique(filter(>(0), vec(u0.ownership)))), live1 = count(alive1), ncells0 = length(kinds0),
            leaders_same_code = all(c -> u0.cell.kind[c] == lc, L),
            leaders_alive = all(c -> alive1[c], L),
            leader_cells1 = count(c -> alive1[c] && u1.cell.kind[c] == lc, eachindex(alive1)), painted = length(L),
        )
    end
end
akeeb_values(runs, t, m) = [Float64(getproperty(r.obs[t], m)) for r in runs]
function akeeb_invariants(runs)
    return all(r -> all(o -> o.infiltrative >= o.invasive && o.detached >= o.singles, values(r.obs)), runs)
end
# ---------------------------------------------------------------------------------------------
# akeeb_observables against hand-built lattices (independent oracle, spec 10 §5.3.3 O1–O8)
# ---------------------------------------------------------------------------------------------

# A lattice from a picture: rows top (y = Y) to bottom (y = 1), σ[x, y].
akeeb_lattice(rows) = (Y = length(rows); [rows[Y - y + 1][x] for x in eachindex(rows[1]), y in 1:Y])
const AKEEB_SMOKE = AKEEB_FULL ? nothing :
    (
        P1 = akeeb_run(POINTS.P1, akeeb_seed.(1, 1:4)), P7 = akeeb_run(POINTS.P7, akeeb_seed.(7, 1:2)),
        P8 = akeeb_run(POINTS.P8, akeeb_seed.(8, 1:2)),
    )
# ---------------------------------------------------------------------------------------------
# FULL-record rows (D-156; recomputed under `10_akeeb_tests.jl`, D-163): V-A6 and the full-sweep
# form of V-A7 need the 13,310-run sweep, so they bind in the committed record. The test
# recomputes both verdicts from the committed per-run `sweep.tsv` (spec 10 §5.3.3 R3; |r| <
# 0.05) and checks that `verdicts_sweep.tsv` reports the same values and verdicts, so a
# hand-edited verdict or a hand-edited phenotype column fails. Cheap: two TSVs are read,
# nothing is run
# ---------------------------------------------------------------------------------------------
const DIR = joinpath(pkgdir(PottsModels), "reproductions", "data", "10", "full-2026-10-07")
const PHEN = (:none, :single, :bulk, :multimodal)
const PHEN_TEXT = (none = "No invasion", single = "Single-cell", bulk = "Bulk", multimodal = "Multimodal")
# Dataset A classified by the area-equality classifier (D-163: rebuilt exactly from the
# authors' `invasion_metrics.csv`; 13,263 classified, 42 unclassified of 13,305). The record's
# paper column prints only A's percentages and N, so the counts are cited here and checked
# against that column below
const A_COUNT = (none = 2950, single = 143, bulk = 2989, multimodal = 7181)
const A_UNCLASSIFIED = 42
akeeb_cor(x, y) = (dx = x .- mean(x); dy = y .- mean(y); sum(dx .* dy) / sqrt(sum(abs2, dx) * sum(abs2, dy)))
# V-A6 and V-A7 from per-run columns: PP, the six metrics (NamedTuple of vectors) and the
# phenotype per run
function verdicts(PP, met, phen)
    NA = sum(values(A_COUNT))
    NB = count(!=(:unclassified), phen)
    pB = NamedTuple{PHEN}(Tuple(count(==(ph), phen) / NB for ph in PHEN))
    pass6 = NamedTuple{PHEN}(Tuple(akeeb_r3(A_COUNT[ph] / NA, NA, pB[ph], NB) for ph in PHEN))
    r = NamedTuple{METRICS}(Tuple(akeeb_cor(PP, met[m]) for m in METRICS))
    pass7 = map(x -> abs(x) < 0.05, r)
    return (; NB, unclassified = count(==(:unclassified), phen), pB, pass6, r, pass7)
end
# the recomputed values agree with the record's "ours" column to its printed digits (half a
# unit of the last digit: 2 decimals for the percentages, 3 for r) and give its verdicts
near(x, printed) = (
    d = something(findfirst('.', printed), lastindex(printed)); digs = length(printed) - d;
    abs(x - parse(Float64, printed)) <= 0.5 * 10.0^-digs + 1.0e-9
)
function agrees(v, rows)
    rec(t) = only(r for r in rows if r["target"] == t)
    ok = true
    for ph in PHEN
        r = rec("V-A6 $(PHEN_TEXT[ph]) fraction")
        m = match(r"^([0-9.]+) % \(N = ([0-9]+)\)", r["ours"])
        ok &= m !== nothing && near(100 * v.pB[ph], m[1]) && parse(Int, m[2]) == v.NB
        ok &= r["result"] == (v.pass6[ph] ? "PASS" : "FAIL")
    end
    m = match(r"^([0-9]+) / ([0-9]+) ", rec("V-A6 unclassified (dropped before the fractions)")["ours"])
    ok &= m !== nothing && parse(Int, m[1]) == v.unclassified && parse(Int, m[2]) == v.NB + v.unclassified
    for k in METRICS
        r = rec("V-A7 r(PP, $k), full sweep")
        ok &= near(v.r[k], r["ours"]) && r["result"] == (v.pass7[k] ? "PASS" : "FAIL")
    end
    return ok
end
# ---------------------------------------------------------------------------------------------
# The rules and constants against the authors' released data (spec 10 §5.3.3 self-check)
# ---------------------------------------------------------------------------------------------
const DATA = joinpath(
    get(ENV, "POTTS_REFERENCES", joinpath(@__DIR__, "..", "..", "..", "..", "docs", "references")),
    "codebases", "10_Akeeb2026_Leader_Follower_Invasion_Model", "Data"
)
# rows of a CSV as (J_LF, λ, PP) => the six metrics, skipping rows with empty metrics;
# `cols` names the key and metric columns of that file
function akeeb_csv(path, cols)
    lines = readlines(path)
    head = split(lines[1], ',')
    idx = [findfirst(==(c), head) for c in cols]
    out = Pair{NTuple{3, Float64}, NTuple{6, Float64}}[]
    for l in lines[2:end]
        f = split(l, ',')
        any(isempty, f[idx]) && continue
        v = parse.(Float64, f[idx])
        push!(out, (v[1], v[2], v[3]) => Tuple(v[4:9]))
    end
    return out
end
const COLS_A = [
    "Contact Energy", "Chemotaxis Lambda", "Proliferative Probability", "Invasive Area",
    "Infiltrative Area", "Singles", "Fingers", "Detached Cells", "Clusters",
]
const COLS_B = [
    "Adhesion Energy", "Migration Coefficient", "Proliferative Probability", "Invasive Area",
    "Infiltrative Area", "Single Defects", "Fingers", "Detached Cells", "Clusters",
]
const COLS_C = [
    "Contact Energy", "Chemotaxis Lambda", "Proliferative Probability", "Invasive Area",
    "Infiltrative Area", "Single Defects", "Fingers", "Detached Cells", "Clusters",
]
akeeb_at(rows, k, j) = [v[j] for (kk, v) in rows if kk == k]
# `x` matches the printed reference `ref` to one unit of its last printed digit (0 to 3
# decimals, read off the value). One unit, not half, since `10_akeeb_tests.jl` was written; the P9 slip it
# absorbed (2889 printed for 2888.46) is corrected under D-152
akeeb_printed(x, ref) = (
    d = findfirst(d -> round(ref; digits = d) == ref, 0:3) - 1;
    abs(x - ref) <= 10.0^-d * (1 + 1.0e-6)
)
akeeb_stats(v) = (mean(v), akeeb_sd(v), length(v))
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "10 akeeb: akeeb_observables on a hand-built lattice (O1, O2, O6–O8)" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "10 akeeb: akeeb_observables on a hand-built lattice (O1, O2, O6–O8)" begin
        # 12 × 8, x periodic, y closed. F follower, L leader; id 6 owns no site (an empty slot).
        #   1 F (2:5, 1:2)   2 L (3,3)   3 F (8,1)   4 F (12,2)   5 L (7,6)   7 F (9:10,5)
        #   8 L (11,5)   9 L (1,7)   10 L (12,7)   11 F (5,6)   12 F (5,7)   13 L (6,3)
        σ = akeeb_lattice(
            [
                #1   2  3  4   5  6  7  8  9  10  11  12     x
                [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],      # y 8
                [9, 0, 0, 0, 12, 0, 0, 0, 0, 0, 0, 10],    # y 7
                [0, 0, 0, 0, 11, 0, 5, 0, 0, 0, 0, 0],     # y 6
                [0, 0, 0, 0, 0, 0, 0, 0, 7, 7, 8, 0],      # y 5
                [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],      # y 4
                [0, 0, 2, 0, 0, 13, 0, 0, 0, 0, 0, 0],     # y 3
                [0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 4],      # y 2
                [0, 1, 1, 1, 1, 0, 0, 3, 0, 0, 0, 0],      # y 1
            ]
        )
        F, L = :follower, :leader
        kinds = [F, L, F, F, L, L, F, L, L, L, F, F, L]
        @test size(σ) == (12, 8) && σ[12, 2] == 4 && σ[8, 1] == 3 && σ[6, 3] == 13
        o = akeeb_observables(σ, kinds)
        # O1 edges (von Neumann, x periodic): 1–2 (3,2)-(3,3); 7–8 (10,5)-(11,5); 9–10 through the
        # wrap (1,7)-(12,7); 11–12 (5,6)-(5,7). 13 at (6,3) touches 1 at (5,2) only diagonally.
        # O2 seeds: row y = 2, x ∈ 1:11: cell 1 only (4 sits at x = 12, the excluded last column;
        # 3 owns only a y = 1 site). M = {1, 2}.
        # yCOM: 1 → 1.5, 2 → 3, 3 → 1, 4 → 2, 5 → 6, 7 → 5, 8 → 5, 9 → 7, 10 → 7, 11 → 6,
        # 12 → 7, 13 → 3; min over M = 1.5.
        # O6 singles: leaders with no neighbour above 1.5: 5 and 13 (6 owns no site).
        #   Moore adjacency would put 13 in M (1); no x wrap would add 9 and 10 (4); counting
        #   followers would add 4 (3).
        @test o.singles == 2
        # O7 detached: outside M, yCOM > 1.5: 4, 5, 7, 8, 9, 10, 11, 12, 13 (not 3: yCOM 1).
        #   Seeding x = 12 too would put 4 in M (8).
        @test o.detached == 9
        # O8: components outside M: {3} {4} {5} {7,8} {9,10} {11,12} {13}; ≥ 2 cells with a
        # follower: {7,8} (1 L, 1 F) and {11,12} (0 L, 2 F); the leader pair {9,10} never counts.
        @test o.clusters == 2
        @test o.cluster_leaders == [1, 0] && o.cluster_followers == [1, 2]
        # O3/O4: top_main = 2, 3, 2, 2 at x = 2:5 (0 elsewhere); top_out = 7, 2, 3, 2, 7, 3, 6,
        # 1, 5, 5, 5, 7. Kept x = 2:5, base 2: invasive trapezoid_integral([0,1,0,0]) = 1.0, infiltrative
        # trapezoid_integral([0,1,0,5]) = 0.5 + 0.5 + 2.5 = 3.5. Seeding row y = 1 instead would put 3 in M
        # and keep x = 8: base 1, invasive 5.5.
        @test o.invasive === 1.0 && o.infiltrative === 3.5
        @test o.fingers == 0
        @test o.infiltrative >= o.invasive && o.detached >= o.singles
    end
end

@testitem "10 akeeb: akeeb_observables profiles, areas and fingers (O3–O5)" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "10 akeeb: akeeb_observables profiles, areas and fingers (O3–O5)" begin
        # 80 × 30. Cell 1 (follower) fills each column x from y = 1 to h(x); cell 2 (follower)
        # owns (75, 20) and (76, 20). h = 3 except:
        #   A, B, C: h = 18 − 2|x − c| for |x − c| ≤ 7 at c = 10, 30, 44 (B and C meet at x = 37: 4)
        #   D: h = 9 − 2|x − 60| for |x − 60| ≤ 2 (prominence 6 < 10)
        #   E: h(70) = 18, a one-column spike (width at half prominence 1 < 5)
        h = fill(3, 80)
        for c in (10, 30, 44), x in (c - 7):(c + 7)
            h[x] = max(h[x], 18 - 2abs(x - c))
        end
        for x in 58:62
            h[x] = max(h[x], 9 - 2abs(x - 60))
        end
        h[70] = 18
        σ = zeros(Int, 80, 30)
        for x in 1:80
            σ[x, 1:h[x]] .= 1
        end
        σ[75:76, 20] .= 2
        o = akeeb_observables(σ, [:follower, :follower])
        # O5 on the 80 kept columns: local maxima 10, 30, 44, 60, 70; distance 10 removes none
        # (60–70 is exactly 10); prominence 15, 15, 15, 6, 15 removes 60; widths at 10.5 are
        # 7.5, 7.5, 7.5 and 1 (70 removed). Merge (gap 15): keep 10, 30 (20 > 15), drop 44
        # (14 ≤ 15). Fingers 2 (merge first would also give 2; prominence first, 3 at gap 0).
        @test PottsModels.Analysis.find_peaks(h; prominence = 10, distance = 10, width = 5) == [10, 30, 44]
        @test o.fingers == 2
        # O4, base 3: Σ(h − 3) = A 113 + (B ∪ C) 225 + D 18 + E 15 = 371 (zero at both ends, so
        # trapezoid_integral is the sum); top_out − top_main is 17 at x = 75, 76: + 34.
        @test o.invasive === 371.0 && o.infiltrative === 405.0
        # cell 2: outside M, yCOM 20 above M's yCOM; one cell, so no cluster; a follower, so
        # not a single
        @test o.detached == 1 && o.singles == 0 && o.clusters == 0
        @test isempty(o.cluster_leaders) && isempty(o.cluster_followers)
    end
end

@testitem "10 akeeb: akeeb_observables on the published start (before any sweep)" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "10 akeeb: akeeb_observables on the published start (before any sweep)" begin
        # The slab top is flat at y = 21 and every leader sits inside it: areas 0, counts 0.
        # This is V-A0's negative control: a run measured before its first sweep gives 0.
        op = akeeb_state(; seed = 3)
        σ, kinds = op[1].second, op[2].second
        o = akeeb_observables(σ, kinds)
        @test o.invasive == 0 && o.infiltrative == 0
        @test (o.singles, o.fingers, o.detached, o.clusters) == (0, 0, 0, 0)
        prob = remake(BASE; u0 = op)
        @test akeeb_observables(prob.u0) == o                  # the state method reads the same kinds
    end
end

@testitem "10 akeeb: default μ = 24" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    # ---------------------------------------------------------------------------------------------
    # SMOKE (binding in the suite)
    # ---------------------------------------------------------------------------------------------
    @testset "10 akeeb: default μ = 24" begin
        prob = PottsProblem(
            AkeebInvasion(; name = :akeeb_default, lattice = (99, 60)), akeeb_state(; lattice = (99, 60)),
            (0, 1); capacity = 1000
        )
        @test getp(prob, :μ)(prob) == 24.0
    end
end

@testitem "10 akeeb: V-A1 (a) the published layout (exact)" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "10 akeeb: V-A1 (a) the published layout (exact)" begin
        for s in akeeb_seed.(1, 1:10)
            point, report = layout(akeeb_layout(; seed = s), (500, 300); report = true)
            σ, kinds = point[1].second, point[2].second
            t = only(r for r in report if r.type === :InsertUntil)
            F = findall(==(:follower), kinds)
            @test length(F) == 1169 && kinds[1:1169] == fill(:follower, 1169)
            # 3 × 3 tiles: every follower's sites lie in one tile [3a+1 : 3a+3] × [3b+1 : 3b+3],
            # the last tile column being x = 499:500; the slab fills 500 × 21 exactly
            tile = Dict{Int, Set{Tuple{Int, Int}}}()
            for I in CartesianIndices(σ)
                c = σ[I]
                c in 1:1169 && push!(get!(tile, c, Set{Tuple{Int, Int}}()), ((I[1] - 1) ÷ 3, (I[2] - 1) ÷ 3))
            end
            @test all(c -> length(tile[c]) == 1, F)
            @test sort!([first(only(tile[c])) for c in F if last(only(tile[c])) == 0]) == collect(0:166)
            @test all(>(0), σ[:, 1:21]) && all(==(0), σ[:, 22:end])
            # leaders: one site each, inside x 2:500, y 2:20; the inventory counts 390 at the last
            # hit, so 390 ≤ counted ≤ 390 + misses (MD-1: 390, occasionally 391 or 392)
            @test t.painted == count(==(:leader), kinds) == length(kinds) - 1169
            @test t.painted + t.misses == t.counted && 390 <= t.counted <= 390 + t.misses
            @test all(I -> σ[I] <= 1169 || (2 <= I[1] <= 500 && 2 <= I[2] <= 20), CartesianIndices(σ))
            @test all(c -> count(==(c), σ) == 1, 1170:length(kinds))
        end
    end
end

@testitem "10 akeeb: V-A0 one-sweep front (R1, n = 10 × 1 MCS)" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "10 akeeb: V-A0 one-sweep front (R1, n = 10 × 1 MCS)" begin
        runs = akeeb_run(POINTS.P1, akeeb_seed.(10, 1:10); tmax = 1, saves = [1])
        for (m, ref) in zip(METRICS, REF_B[0])
            @test akeeb_r1((ref..., N_B), akeeb_values(runs, 0, m), FLOOR[m])
        end
        @test akeeb_invariants(runs)
        # negative control: the state before the first sweep (invasive 0) fails the same rule
        before = map(akeeb_seed.(10, 1:10)) do s
            op = akeeb_state(; seed = s)
            Float64(akeeb_observables(op[1].second, op[2].second).invasive)
        end
        @test all(iszero, before)
        @test !akeeb_r1((REF_B[0][1]..., N_B), before, 0.0)
    end
end

@testitem "10 akeeb SMOKE: V-A1 (b, c), V-C1, V-C2, invariants and controls" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    if !AKEEB_FULL
        @testset "10 akeeb SMOKE: V-A1 (b, c), V-C1, V-C2, invariants and controls" begin
            (; P1, P7, P8) = AKEEB_SMOKE
            # V-A1 (b): leaders never divide (no new leader-kind cell) and are never lost (a
            # cell that loses its last site cannot regain one, so alive at 701 is alive at every
            # MCS); divisions = live cells at the end − at the start (spec), = the lifecycle count
            for r in P1
                @test r.leaders_same_code && r.leaders_alive && r.leader_cells1 == r.painted
                @test r.live0 == r.ncells0 && r.live1 - r.live0 == r.divisions
            end
            # V-A1 (c), with the n = 10 band at n = 4: our ensemble gives 585.8 ± 18.7 divisions
            # per run (D-093, 80 seeds), so the band [523, 633] is ≥ 5.0 SE of a four-run mean
            # from either edge
            @test abs(mean(r -> r.divisions, P1) - DIVISIONS) <= DIVISIONS_TOL
            # V-C1 (exact): no division, live count constant; control: every P1 run divides
            @test all(r -> r.divisions == 0 && r.live1 == r.live0, P7)
            @test all(r -> r.divisions > 0, P1)
            # V-C2 (exact): no cluster at λ = 0; control: P1 runs do form clusters
            @test all(r -> r.obs[700].clusters == 0, P8)
            @test any(r -> r.obs[700].clusters > 0, P1)
            # λ drives invasion: P8's invasive area fails P1's reference under R1
            @test !akeeb_r1((REF_A.P1[1]..., N_A), akeeb_values(P8, 700, :invasive), 0.0)
            @test akeeb_invariants(P1) && akeeb_invariants(P7) && akeeb_invariants(P8)
        end
    end
    # ---------------------------------------------------------------------------------------------
    # FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full)
    # ---------------------------------------------------------------------------------------------
    if AKEEB_FULL
        const RUNS = Dict(name => akeeb_run(pt, akeeb_seed.(k, 1:10)) for (k, (name, pt)) in enumerate(pairs(POINTS)))

        @testset "10 akeeb FULL: V-A1, V-C1, V-C2 and invariants" begin
            P1, P7, P8 = RUNS[:P1], RUNS[:P7], RUNS[:P8]
            for r in P1
                @test r.leaders_same_code && r.leaders_alive && r.leader_cells1 == r.painted
                @test r.live0 == r.ncells0 && r.live1 - r.live0 == r.divisions
            end
            @test abs(mean(r -> r.divisions, P1) - DIVISIONS) <= DIVISIONS_TOL
            @test all(r -> r.divisions == 0 && r.live1 == r.live0, P7)
            @test all(r -> r.divisions > 0, P1)
            @test all(r -> r.obs[700].clusters == 0, P8)
            @test any(r -> r.obs[700].clusters > 0, P1)
            for m in (:singles, :fingers, :detached)
                @test mean(akeeb_values(P8, 700, m)) <= 1
            end
            @test !akeeb_r1((REF_A.P1[1]..., N_A), akeeb_values(P8, 700, :invasive), 0.0)
            @test all(akeeb_invariants, values(RUNS))
        end

        @testset "10 akeeb FULL: V-A2 / V-A7 per-point means (R1) $name" for name in keys(POINTS)
            runs = RUNS[name]
            for (m, ref) in zip(METRICS, REF_A[name])
                @test akeeb_r1((ref..., N_A), akeeb_values(runs, 700, m), FLOOR[m])
            end
        end

        @testset "10 akeeb FULL: V-A11 time course at P1 (R1), MCS $t" for t in (100, 300, 500)
            for (m, ref) in zip(METRICS, REF_B[t])
                @test akeeb_r1((ref..., N_B), akeeb_values(RUNS[:P1], t, m), FLOOR[m])
            end
        end

        @testset "10 akeeb FULL: V-A8 cluster composition $name" for name in (:P1, :P2)
            μA, sA, nA, fA = REF_C[name]
            os = [r.obs[700] for r in RUNS[name]]
            sizes = Float64[l + f for o in os for (l, f) in zip(o.cluster_leaders, o.cluster_followers)]
            @test length(sizes) >= 2
            @test akeeb_r1(μA, sA, nA, mean(sizes), std(sizes), length(sizes), 0.0)
            @test abs(sum(o -> sum(o.cluster_leaders), os) / sum(sizes) - fA) <= 0.1
        end

        const SLICE_RUNS = [
            (k = pt, runs = akeeb_run(pt, [1_000_000 + 100j + i for i in 1:10]; saves = [701]))
                for (j, pt) in enumerate(SLICE)
        ]
        marginal(m, set) = [
            Float64(getproperty(r.obs[700], m)) for s in SLICE_RUNS
                if set === :all || SLICE_SETS[set](s.k) for r in s.runs
        ]

        @testset "10 akeeb FULL: V-A3 / V-A4 slice marginals (R2)" begin
            @test length(SLICE_RUNS) == 121
            for (m, set, μA, seA) in REF_SLICE
                v = marginal(m, set)
                @test akeeb_r2(μA, seA, mean(v), std(v) / sqrt(length(v)), FLOOR[m])
            end
            invasive_mean(set) = mean(marginal(:invasive, set))
            @test invasive_mean(:J_mid) > invasive_mean(:J_weak) > invasive_mean(:J_strong)    # strict order
            for m in (:invasive, :infiltrative)
                r = mean(marginal(m, :λ_high)) / mean(marginal(m, :λ_low))
                @test abs(r / RATIO[m] - 1) <= 0.15
            end
        end

        @testset "10 akeeb FULL: V-A5 cluster incidence (R3) and size when present (R2)" begin
            for (set, pA, NA) in INCIDENCE
                v = marginal(:clusters, set)
                @test akeeb_r3(pA, NA, count(>=(1), v) / length(v), length(v))
            end
            present = filter(>=(1), marginal(:clusters, :λ_24))
            @test akeeb_r2(CLUSTERS_WHEN_PRESENT..., mean(present), std(present) / sqrt(length(present)), 1.0)
        end
    end
end

@testitem "10 akeeb: parked V-targets" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    # ---------------------------------------------------------------------------------------------
    # PARKED rows (spec 10 §5.3.5): recorded, not tested
    # ---------------------------------------------------------------------------------------------
    @testset "10 akeeb: parked V-targets" begin
        @test_skip "V-A8 paper cluster values: mean ≈ 7 cells, 60–70 % leaders, median 4 L / 3 F (author question 8)" == ""
        @test_skip "V-A9 leader speed 0.4 px/MCS at λ = 20 (undefined; author question 6)" == ""
    end
end

@testitem "FULL record: V-A6 (provisional classifier) and full-sweep V-A7, recomputed" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "FULL record: V-A6 (provisional classifier) and full-sweep V-A7, recomputed" begin
        vfile, sfile = joinpath(DIR, "verdicts_sweep.tsv"), joinpath(DIR, "sweep.tsv")
        @test isfile(vfile) && isfile(sfile)
        l = split.(readlines(vfile), '\t')
        rows = [Dict(zip(l[1], r)) for r in l[2:end]]
        @test count(r -> startswith(r["target"], "V-A6") && r["class"] == "FULL", rows) == 4
        @test count(r -> startswith(r["target"], "V-A7") && r["class"] == "FULL", rows) == 6

        s = split.(readlines(sfile), '\t')
        head, runs = s[1], s[2:end]
        col(c) = (j = findfirst(==(c), head); [r[j] for r in runs])
        num(c) = parse.(Float64, col(c))
        @test length(runs) == 13_310 && all(==("Success"), col("retcode"))
        PP = num("PP")
        met = NamedTuple{METRICS}(Tuple(num(string(m)) for m in METRICS))
        phen = Symbol.(col("phenotype"))
        # the phenotype column is the classifier's output on the committed metrics
        obs = [NamedTuple{METRICS}(Tuple(met[m][k] for m in METRICS)) for k in eachindex(phen)]
        @test akeeb_phenotype.(obs) == phen

        # A's cited counts are the record's A percentages and N
        NA = sum(values(A_COUNT))
        @test NA == 13_263 && NA + A_UNCLASSIFIED == 13_305
        for ph in PHEN
            m = match(
                r"A ([0-9.]+) % \(N = ([0-9]+)\)",
                only(r["paper"] for r in rows if r["target"] == "V-A6 $(PHEN_TEXT[ph]) fraction")
            )
            @test m !== nothing && near(100 * A_COUNT[ph] / NA, m[1]) && parse(Int, m[2]) == NA
        end

        v = verdicts(PP, met, phen)
        @test (v.NB, v.unclassified) == (13_268, 42)
        for ph in PHEN
            @test v.pass6[ph]                              # V-A6: R3 per phenotype
        end
        for k in METRICS
            @test v.pass7[k]                               # V-A7: |r(PP, metric)| < 0.05
        end
        @test agrees(v, rows)

        # negative controls (D-048): perturbed copies of the sweep must fail
        shift(phen, from, to, n) = (q = copy(phen); q[findall(==(from), q)[1:n]] .= to; q)
        # one run moved from Multimodal to No invasion: R3 still passes, but the record disagrees
        v1 = verdicts(PP, met, shift(phen, :multimodal, :none, 1))
        @test all(values(v1.pass6)) && !agrees(v1, rows)
        @test akeeb_phenotype.(obs) != shift(phen, :multimodal, :none, 1)   # and the classifier check catches it
        # 800 runs moved (6 points of No invasion): R3 fails on No invasion, so R3 can fail
        v800 = verdicts(PP, met, shift(phen, :multimodal, :none, 800))
        @test !v800.pass6.none && !agrees(v800, rows)
        # invasive made to depend on PP (+0.2 SD per SD of PP): V-A7 fails
        α = 0.2 * std(met.invasive) / std(PP)
        vr = verdicts(PP, merge(met, (; invasive = met.invasive .+ α .* PP)), phen)
        @test !vr.pass7.invasive && all(vr.pass7[k] for k in METRICS if k !== :invasive) && !agrees(vr, rows)
    end
end

@testitem "10 akeeb: rules and references against the authors' ensembles A, B, C" setup = [AkeebSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "10 akeeb: rules and references against the authors' ensembles A, B, C" begin
        if !isdir(DATA)
            @test_skip isdir(DATA)
        else
            A = akeeb_csv(joinpath(DATA, "invasion_metrics.csv"), COLS_A)
            B(t) = akeeb_csv(joinpath(DATA, "Invasion_Metrics_By_MCS", "invasion_metrics_$(t)_mcs.csv"), COLS_B)
            C(t) = akeeb_csv(
                joinpath(DATA, "NEW", "Invasion_Metrics_By_MCS", "invasion_metrics_at_$(t)_mcs.csv"),
                COLS_C
            )
            @test length(A) == 13_305
            # the recorded constants are dataset A / B as printed in the spec (rounded)
            for name in keys(POINTS), (j, ref) in enumerate(REF_A[name])
                v = akeeb_at(A, POINTS[name], j)
                @test length(v) == N_A
                @test akeeb_printed(mean(v), ref[1]) && akeeb_printed(akeeb_sd(v), ref[2])
            end
            for t in (0, 100, 300, 500), (j, ref) in enumerate(REF_B[t])
                v = akeeb_at(B(t), POINTS.P1, j)
                @test length(v) == N_B && akeeb_printed(mean(v), ref[1]) && akeeb_printed(akeeb_sd(v), ref[2])
            end
            # R1 passes B and C against A at P1–P8 (96 / 96) ...
            B700, C700 = B(700), C(700)
            names8 = (:P1, :P2, :P3, :P4, :P5, :P6, :P7, :P8)
            @test all(
                akeeb_r1(akeeb_stats(akeeb_at(A, POINTS[n], j)), akeeb_at(D, POINTS[n], j), FLOOR[m])
                    for D in (B700, C700) for n in names8 for (j, m) in enumerate(METRICS)
            )
            # ... and B against C over the time course (24 / 24)
            @test all(
                akeeb_r1(
                    akeeb_stats(akeeb_at(B(t), POINTS.P1, j)), akeeb_at(C(t), POINTS.P1, j),
                    FLOOR[m]
                ) for t in (0, 100, 300, 500) for (j, m) in enumerate(METRICS)
            )
            # but R1 is not vacuous: B's P1 fails A's P8 on invasive area
            @test !akeeb_r1(akeeb_stats(akeeb_at(A, POINTS.P8, 1)), akeeb_at(B700, POINTS.P1, 1), 0.0)
            # slice marginals: the constants are A's, and R2, R3, the order and the ratios pass B and C
            jm = Dict(m => j for (j, m) in enumerate(METRICS))
            marg(D, m, set) = [v[jm[m]] for (k, v) in D if k[3] == 0.5 && (set === :all || SLICE_SETS[set](k))]
            for (m, set, μA, seA) in REF_SLICE
                v = marg(A, m, set)
                @test akeeb_printed(mean(v), μA) && akeeb_printed(std(v) / sqrt(length(v)), seA)
                for D in (B700, C700)
                    w = marg(D, m, set)
                    @test akeeb_r2(μA, seA, mean(w), std(w) / sqrt(length(w)), FLOOR[m])
                end
            end
            for D in (A, B700, C700)
                @test mean(marg(D, :invasive, :J_mid)) > mean(marg(D, :invasive, :J_weak)) > mean(marg(D, :invasive, :J_strong))
                for m in (:invasive, :infiltrative)
                    @test abs(mean(marg(D, m, :λ_high)) / mean(marg(D, m, :λ_low)) / RATIO[m] - 1) <= 0.15
                end
                for (set, pA, NA) in INCIDENCE
                    v = marg(D, :clusters, set)
                    @test akeeb_r3(pA, NA, count(>=(1), v) / length(v), length(v))
                    if D === A
                        @test length(v) == NA && abs(count(>=(1), v) / length(v) - pA) <= 0.0005
                    end
                end
                present = filter(>=(1), marg(D, :clusters, :λ_24))
                @test akeeb_r2(CLUSTERS_WHEN_PRESENT..., mean(present), std(present) / sqrt(length(present)), 1.0)
            end
            # V-A8 constants from dataset C's per-cluster table
            rows = split.(readlines(joinpath(DATA, "NEW", "cluster_data.csv"))[2:end], ',')
            for name in (:P1, :P2)
                k = POINTS[name]
                cl = [
                    r for r in rows if (parse(Float64, r[1]), parse(Float64, r[2]), parse(Float64, r[3])) == k &&
                        parse(Int, r[8]) > 0
                ]
                sizes = [parse(Int, r[8]) for r in cl]
                μA, sA, nA, fA = REF_C[name]
                @test length(sizes) == nA && akeeb_printed(mean(sizes), μA) && akeeb_printed(std(sizes), sA)
                @test akeeb_printed(sum(r -> parse(Int, r[6]), cl) / sum(sizes), fA)
            end
        end
    end
end
