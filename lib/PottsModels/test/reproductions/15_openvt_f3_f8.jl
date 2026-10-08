# P6.15f (ROADMAP Step 3b): the OpenVT monolayer benchmark's Fig 3 ("Comparing monolayer
# growth over time": deterministic case (f), stochastic case (b)) and Fig 8 (quantitative
# comparison, target V5), overlaid on the consortium data. Frozen (AUTONOMY §7.3).
# Protocols: spec 15 §4.0.1 cases (a), (b), (e), (f), §3.1 O1/O6, §3.2, §4.0.2 F8; target
# §4.1 V5 (docs/design/research/model-specs/15_openvt_monolayer.md v3.1). Spec 15 has no
# V-target for F3: the F3 rows below are the test author's, against the only Table S1 CPM
# data in G, TST's `TST_No_CI_{deterministic,stochastic}.zip` (spec §4.4). Every band, grid,
# seed, lattice and run count is the test author's (P6.15f; see the D-entry).
#
# Reference numbers from G (54f375f, read only, never in git) are frozen below as constants.
# They were computed with this file's rules (`p615f_g_tst`, `p615f_g_legacy`) on the PC
# clone (2026-10-08); the G tier recomputes them when OPENVT_MONOLAYER_REPO is set.
#
# Units. Time t in cycles, t = MCS / 775 (5T, C1; TST files too, as M and TST's README do,
# although TST's α is 50/770, C16). Lengths in R = √(A₀/π) (C10). A run's series is its saves:
# MCS 0, every 39 MCS (Q4) and the stopping MCS; per save N and the `openvt_metrics` fields
# r, A, C, w, g of the centroids (spec §3.2, the frozen D-149 port; NaN for N < 3).
#
# Rules (one series per run; ensemble = mean over the runs):
# - value at grid time τ: the last save with t ≤ τ (saves are 39 MCS apart);
# - cut: a series ends at its first save with N ≥ the stop count n_s (1000 or 10⁴), if any.
#   G's TST stochastic runs end on their last 39-MCS save before the run stopped, at N =
#   960–996 in 98 of 100 runs (audit, 2026-10-08), so the stop rules do not need a save at n_s;
# - t_s (time to n_s cells): where log₂ N crosses log₂ n_s, linear in t between the two saves
#   around the crossing, or extrapolated from the last two saves when the series ends below;
# - end: the first save with N ≥ 0.95 n_s; there the size-free r/√N and A/N (R and R² per cell);
# - grids: T_N = 0.5:1:8.5 (log₂ N), T_R = 4.5:1:8.5 (r, A; N ≥ 16), T_S = 4.5:1:8.5 (V5.1);
# - L(τ) = mean over runs of log₂ N(τ); r̄(τ), Ā(τ) = mean r, A; t̄_s; r̄_e, Ā_e = mean r/√N, A/N at the end;
# - sync(k) = share of runs with N(k + 0.5) == 2^k, k = 0:3;
# - slope = least-squares slope of L(τ) on τ ∈ T_S; offset = max over T_N of |L(τ) − τ|.
#
# | Row  | Case(s)     | Statistic                                          | Pass band                         |
# |------|-------------|----------------------------------------------------|-----------------------------------|
# | F3.1 | (f), (b)    | max over T_N of |L − L_TST|                          | ≤ 0.3 (log₂ units)                |
# | F3.2 | (f), (b)    | t̄_s / t̄_s,TST (time to 1000 cells)                  | [0.95, 1.05]                      |
# | F3.3 | (f), (b)    | max over T_R of |r̄ / r̄_TST − 1| and |r̄_e / r̄_e,TST − 1| | ≤ 0.10                         |
# | F3.4 | (f), (b)    | max over T_R of |Ā / Ā_TST − 1| and |Ā_e / Ā_e,TST − 1| | ≤ 0.20                         |
# | F3.5 | (f)         | min over k = 0:3 of sync(k) (synchronous doublings) | ≥ 0.9                             |
# | V5.1 | (a), (e)    | slope of L on T_S (doubling time = one cycle)       | [0.9, 1.1] per cycle              |
# | V5.2 | (a), (e)    | max over T_N of |L(τ) − τ| (Fig 8a bulk law 2^t)     | ≤ 1.0                             |
# | F8.1 | (a)         | g at every save (β = γ = 0: every cell grows)       | == 1                              |
# | F8.2 | (a), (e)    | min over saves with N ≥ 3 of C/(2√(πA)); min w      | ≥ 1 − 1e-9; ≥ 0                   |
# | F8.3 | (a)         | mean n of the pooled final neighbour histogram      | G lattice spread ± 0.3            |
# | F8.4 | (e)         | mean g at the last save of the cut series (N ≥ 10⁴) | G lattice spread ± 0.1 (legacy)   |
#
# Fig 3 passes iff every F3 row passes for both cases; V5 iff V5.1 and V5.2 pass for (a)
# and (e); F8 iff V5 and F8.1–F8.4 pass.
#
# Consortium references (G, frozen below): F3 rows against TST deterministic (case f) and
# stochastic (case b), 100 runs each. F8.3 against `postprocessing/neighbors_{compucell3d,
# morpheus}.csv` and F8.4 against `measurements_{compucell3d,morpheus}.csv`: the draft
# Fig 8's lattice curves, which are legacy β = 0.8 runs with legacy parameter sets (D4, Q7);
# V5 is evaluated on them as information only (their t is a legacy cycle, D4).
#
# Negative controls (D-048).
# - C1: case (b)'s protocol with type-2 inhibition γ = 1e-4 (V3b's γ → 0⁺: interior cells
#   stop growing; growth becomes boundary-limited, N ∝ t²). Pre-registered: FAILS F3.1 and
#   F3.2 against TST stochastic, and FAILS V5.1 (slope < 0.9).
# - C2: case (b)'s stochastic runs under the deterministic synchrony rule: FAIL F3.5.
#
# Protocol. `OpenVTReferenceMonolayer` at its Table S1 defaults (σ_X = 0.4, β = γ = 0), one
# disc cell at the centre (`openvt_reference_state`), `SequentialCPM(; proposal = Moore(1))`,
# closed lattice with `edge_guard(5; terminate = true)` (a run that reaches the guard fails),
# stopped at the end of the first MCS with ≥ the stop count (`stop_at_cells`).
#
# | Case    | Parameters            | Lattice | Stop  | Runs | Seeds            |
# |---------|-----------------------|---------|-------|------|------------------|
# | (f)     | σ_X = 0 (X ≡ 2)       | 400²    | 1000  | 100  | 15_200 + k       |
# | (b)     | defaults              | 400²    | 1000  | 100  | 15_000 + k (F5)  |
# | control | γ = 1e-4              | 400²    | 1000  | 20   | 15_500 + k (F5)  |
# | (a)     | defaults              | 1400²   | 10⁴   | 10   | 15_700 + k       |
# | (e)     | β = 0.8               | 1400²   | 10⁴   | 10   | 15_800 + k       |
#
# Cases (b) and control are P6.15e's protocol and seeds with a recorder added (information:
# their stopping MCS can be compared with the F5 record; not asserted). The O1 rows of a
# state (spec §3.1: x, y, i, n) come from `PottsModels.openvt_frame(u; β, γ)`, pre-registered
# here: the same live cells, order and x, y as `openvt_snapshot`, i = `openvt_inhibition_code`
# of the snapshot's a, f, and n = the number of distinct cells (medium and the cell itself
# excluded) among the Moore(1) neighbours of the cell's sites (spec §2.4), on the closed
# lattice. It takes any `u` with `u.σ`, `u.cell.volume`, `u.cell.A_star`, as the snapshot does.
#
# Tiers.
# - always: the rules on synthetic series with known answers; `openvt_frame` against a
#   brute-force oracle.
# - SMOKE (the default; well under a minute plus one model compilation): three runs on 240²
#   to t = 8.5 cycles (MCS 6591; seeds 95_101–95_103): deterministic, stochastic, and
#   deterministic with γ = 1e-4 (the control's mechanism: slope < 0.9).
# - G (OPENVT_MONOLAYER_REPO set): recompute the frozen consortium constants from G.
# - FULL record (always, cheap): reads the committed D-146 record, the one directory
#   `reproductions/data/15/f3-f8-*` (`runs.tsv`, `timeseries.tsv`, `neighbors.tsv`,
#   `verdicts.tsv`, `provenance.toml`), and recomputes every row. A failing row must be in
#   the record's `deviations.tsv` (D-154) and is then `@test_broken`; the controls must fail
#   as pre-registered. Until the record exists this testset fails on its first check.
# - FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full, offline on the PC, D-146, D-157):
#   reruns all 240 runs and requires every row and both controls.
#
# Record schema (tab-separated, one header line; floats parse as Float64, `nan` allowed):
# - runs.tsv: case, k, seed, beta, gamma, sigma_X, lattice, retcode, mcs, N
# - timeseries.tsv: case, seed, mcs, N, r, A, C, w, g (every save of every run)
# - neighbors.tsv: case, seed, n, count (final state, cases a and e)
# - verdicts.tsv: target (first token the row id), case, ours, band, result (PASS | FAIL),
#   one line per (row, case) of P615F_PAIRS and P615F_CONTROL_PAIRS
using Potts, PottsModels, Test
using Statistics: mean

const P615F_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P615F_REPO = get(ENV, "OPENVT_MONOLAYER_REPO", "")
const P615F_DATA = joinpath(pkgdir(PottsModels), "reproductions", "data", "15")

# ---------------------------------------------------------------------------------------------
# Protocol constants (test author)
# ---------------------------------------------------------------------------------------------

const P615F_CYCLE = 775                              # MCS per cycle (5T, C1)
const P615F_EVERY = 39                               # save cadence (Q4)
const P615F_TN = 0.5:1.0:8.5
const P615F_TR = 4.5:1.0:8.5
const P615F_TS = 4.5:1.0:8.5
const P615F_KSYNC = 0:3
const P615F_GAMMA_CTL = 1e-4
const P615F_CASES = (
    f = (; beta = 0.0, gamma = 0.0, sigma_X = 0.0, L = 400, cells = 1000, runs = 100, seed = k -> 15_200 + k),
    b = (; beta = 0.0, gamma = 0.0, sigma_X = 0.4, L = 400, cells = 1000, runs = 100, seed = k -> 15_000 + k),
    control = (; beta = 0.0, gamma = P615F_GAMMA_CTL, sigma_X = 0.4, L = 400, cells = 1000, runs = 20,
        seed = k -> 15_500 + k),
    a = (; beta = 0.0, gamma = 0.0, sigma_X = 0.4, L = 1400, cells = 10_000, runs = 10, seed = k -> 15_700 + k),
    e = (; beta = 0.8, gamma = 0.0, sigma_X = 0.4, L = 1400, cells = 10_000, runs = 10, seed = k -> 15_800 + k))
const P615F_ALG = SequentialCPM(; proposal = Moore(1))
const P615F_GUARD = 5
p615f_seed_smoke(k) = 95_100 + k

# the (row, case) pairs that must pass, and the control pairs that must fail
const P615F_PAIRS = [("F3.1", "f"), ("F3.2", "f"), ("F3.3", "f"), ("F3.4", "f"), ("F3.5", "f"),
    ("F3.1", "b"), ("F3.2", "b"), ("F3.3", "b"), ("F3.4", "b"),
    ("V5.1", "a"), ("V5.2", "a"), ("V5.1", "e"), ("V5.2", "e"),
    ("F8.1", "a"), ("F8.2", "a"), ("F8.2", "e"), ("F8.3", "a"), ("F8.4", "e")]
const P615F_CONTROL_PAIRS = [("F3.1", "control"), ("F3.2", "control"), ("V5.1", "control"), ("F3.5", "b")]

# ---------------------------------------------------------------------------------------------
# Consortium constants from G (54f375f), computed with this file's rules on 2026-10-08
# (p615f_g_tst on TST_No_CI_{deterministic,stochastic}.zip; p615f_g_legacy on
# postprocessing/{measurements,neighbors}_{compucell3d,morpheus}.csv)
# ---------------------------------------------------------------------------------------------

# TST deterministic: all 100 runs identical, N = 2^k from MCS 780k (target-area division
# every 770 MCS, C13, C16), 1024 cells at MCS 7761. TST stochastic: t_s 9.58–10.89 per run.
const P615F_TST = (
    f = (; L = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
        r = [3.816867, 5.70509, 8.458899, 12.37904, 17.45748], A = [39.2308, 96.4274, 220.3375, 479.2536, 957.8109],
        t_stop = 10.01247, r_stop = 0.9265458, A_stop = 2.701978, sync = [1.0, 1.0, 1.0, 1.0], slope = 1.0,
        offset = 0.5),
    b = (; L = [0.09, 1.07209, 2.050304, 3.113616, 4.111189, 5.155918, 6.182014, 7.188097, 8.162223],
        r = [3.927976, 5.910564, 8.795155, 12.92483, 18.32561], A = [42.18473, 104.51, 243.0626, 530.5249, 1068.292],
        t_stop = 10.23546, r_stop = 1.057312, A_stop = 3.521652, sync = [0.91, 0.62, 0.42, 0.17], slope = 1.013425,
        offset = 0.4496963))
# draft Fig 8 lattice curves (CompuCell3D, Morpheus; legacy β = 0.8, D4): mean neighbour
# number of `neighbors_*.csv`; g at the first row with N ≥ 10⁴ of `measurements_*.csv`
const P615F_LEGACY = (; nmean = [5.841774, 6.480024], g_stop = [0.498702, 0.349797])

# Pass bands (test author)
const P615F_BAND = (logN = 0.3, t_stop = (0.95, 1.05), r = 0.10, A = 0.20, sync = 0.9,
    slope = (0.9, 1.1), offset = 1.0,
    nmean = (minimum(P615F_LEGACY.nmean) - 0.3, maximum(P615F_LEGACY.nmean) + 0.3),
    g_stop = (minimum(P615F_LEGACY.g_stop) - 0.1, maximum(P615F_LEGACY.g_stop) + 0.1))

# ---------------------------------------------------------------------------------------------
# The rules
# ---------------------------------------------------------------------------------------------

# a run's series: saves in time order
function p615f_series(t, N; r = fill(NaN, length(t)), A = fill(NaN, length(t)), C = fill(NaN, length(t)),
        w = fill(NaN, length(t)), g = fill(NaN, length(t)))
    p = sortperm(t)
    return (; t = Float64.(t[p]), N = Int.(N[p]), r = Float64.(r[p]), A = Float64.(A[p]), C = Float64.(C[p]),
        w = Float64.(w[p]), g = Float64.(g[p]))
end
# cut a series at its first save with N ≥ cells (unchanged if it never gets there)
function p615f_cut(s, cells)
    j = findfirst(>=(cells), s.N)
    return j === nothing ? s : map(v -> v[1:j], s)
end
# the time log₂ N crosses log₂ n: interpolated between saves, or extrapolated from the last two
function p615f_tcross(s, n)
    j = findfirst(>=(n), s.N)
    j == 1 && return s.t[1]
    j === nothing && (j = length(s.N))
    (j >= 2 && s.N[j] > s.N[j - 1]) || throw(ArgumentError("p615f_tcross: cannot place N = $n"))
    a, b = log2(s.N[j - 1]), log2(s.N[j])
    return s.t[j - 1] + (s.t[j] - s.t[j - 1]) * (log2(n) - a) / (b - a)
end
# the end save: the first with N ≥ 0.95 n
function p615f_end(s, n)
    j = findfirst(>=(0.95n), s.N)
    j === nothing && throw(ArgumentError("p615f_end: the series never reaches 0.95 × $n cells"))
    return j
end
# index of the value at grid time τ: the last save with t ≤ τ
function p615f_at(s, τ)
    j = findlast(<=(τ), s.t)
    j === nothing && throw(ArgumentError("p615f_at: no save at or before t = $τ"))
    return j
end
# the indices the rules read (for G, where metrics are computed only there)
p615f_reads(s, n) = sort(unique([[p615f_at(s, τ) for τ in P615F_TN]; [p615f_at(s, τ) for τ in P615F_TR]; p615f_end(s, n)]))
p615f_slope(x, y) = (xm = mean(x); ym = mean(y); sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm))

# the ensemble statistics of a set of cut series with stop count n
function p615f_stats(runs, n)
    isempty(runs) && throw(ArgumentError("p615f_stats: no runs"))
    L = [mean(log2(s.N[p615f_at(s, τ)]) for s in runs) for τ in P615F_TN]
    at(f, τ) = mean(getfield(s, f)[p615f_at(s, τ)] for s in runs)
    e = [p615f_end(s, n) for s in runs]
    LS = [mean(log2(s.N[p615f_at(s, τ)]) for s in runs) for τ in P615F_TS]
    return (; L, r = [at(:r, τ) for τ in P615F_TR], A = [at(:A, τ) for τ in P615F_TR],
        t_stop = mean(p615f_tcross(s, n) for s in runs),
        r_stop = mean(s.r[j] / sqrt(s.N[j]) for (s, j) in zip(runs, e)),
        A_stop = mean(s.A[j] / s.N[j] for (s, j) in zip(runs, e)),
        sync = [count(s -> s.N[p615f_at(s, k + 0.5)] == 2^k, runs) / length(runs) for k in P615F_KSYNC],
        slope = p615f_slope(collect(P615F_TS), LS), offset = maximum(abs.(L .- collect(P615F_TN))))
end
p615f_relmax(x, y) = maximum(abs.(x ./ y .- 1))
p615f_in(x, (lo, hi)) = lo <= x <= hi
# F3 rows of one case against its TST reference; `ours.sync` is read by F3.5
function p615f_f3(ours, ref)
    B = P615F_BAND
    v = (; F3_1 = maximum(abs.(ours.L .- ref.L)), F3_2 = ours.t_stop / ref.t_stop,
        F3_3 = p615f_relmax([ours.r; ours.r_stop], [ref.r; ref.r_stop]),
        F3_4 = p615f_relmax([ours.A; ours.A_stop], [ref.A; ref.A_stop]), F3_5 = minimum(ours.sync))
    ok = (; F3_1 = v.F3_1 <= B.logN, F3_2 = p615f_in(v.F3_2, B.t_stop), F3_3 = v.F3_3 <= B.r,
        F3_4 = v.F3_4 <= B.A, F3_5 = v.F3_5 >= B.sync)
    return (; v, ok)
end
function p615f_v5(st)
    v = (; V5_1 = st.slope, V5_2 = st.offset)
    return (; v, ok = (; V5_1 = p615f_in(st.slope, P615F_BAND.slope), V5_2 = st.offset <= P615F_BAND.offset))
end
# F8.1: g == 1 at every save; F8.2: isoperimetric C ≥ 2√(πA) and w ≥ 0 at every save with N ≥ 3
p615f_f81(runs) = minimum(minimum(s.g) for s in runs)
function p615f_f82(runs)
    c = minimum(minimum(s.C[j] / (2sqrt(π * s.A[j])) for j in eachindex(s.N) if s.N[j] >= 3) for s in runs)
    w = minimum(minimum(s.w[j] for j in eachindex(s.N) if s.N[j] >= 3) for s in runs)
    return (; C_rel = c, w, ok = c >= 1 - 1e-9 && w >= 0)
end
# F8.3: the mean of a neighbour histogram (counts or percentages) over n
p615f_nmean(n, p) = sum(n .* p) / sum(p)
# F8.4: mean g at the stop
p615f_gstop(runs) = mean(s.g[end] for s in runs)

# ---------------------------------------------------------------------------------------------
# Runs: one case, with a recorder (saves at MCS 0, every 39 MCS and the stop)
# ---------------------------------------------------------------------------------------------

function p615f_row(u, t; beta, gamma)
    o = PottsModels.openvt_snapshot(u)
    i = [openvt_inhibition_code(o.a[j], o.f[j]; β = beta, γ = gamma) for j in eachindex(o.a)]
    m = openvt_metrics(o.x, o.y, Float64.(i .== 0))
    return (; mcs = Int(t), N = length(o.x), m.r, m.A, m.C, m.w, m.g)
end
function p615f_problem(L, cells)
    sys = OpenVTReferenceMonolayer(; name = Symbol(:p615f_m, L), lattice = (L, L))
    return PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 100_000);
        capacity = ceil(Int, 1.3cells) + 100, seed = 1)
end
function p615f_run(prob, seed, c; cells = c.cells, tmax = nothing)
    rec = NamedTuple[]
    record(integ) = push!(rec, p615f_row(integ.u, integ.t; c.beta, c.gamma))
    cb_rec = Potts.DiscreteCallback((u, t, integ) -> t % P615F_EVERY == 0 || count(>(0), u.cell.volume) >= cells,
        record; initialize = (cb, u, t, integ) -> record(integ), save_positions = (false, false))
    p = [:β => c.beta, :γ => c.gamma, :σ_X => c.sigma_X]
    pr = tmax === nothing ? remake(prob; seed, p) : remake(prob; seed, p, tspan = (0, tmax))
    sol = solve(pr, P615F_ALG; callback = Potts.CorePotts.CallbackSet(cb_rec, PottsModels.stop_at_cells(cells),
        PottsModels.edge_guard(P615F_GUARD; terminate = true)))
    s = p615f_series([r.mcs / P615F_CYCLE for r in rec], [r.N for r in rec]; r = [r.r for r in rec],
        A = [r.A for r in rec], C = [r.C for r in rec], w = [r.w for r in rec], g = [r.g for r in rec])
    return (; retcode = Symbol(sol.retcode), mcs = sol.t[end], series = s, u = sol.u[end])
end
function p615f_runs(prob, seeds, c; kw...)
    out = Vector{Any}(undef, length(seeds))
    Threads.@threads :dynamic for j in eachindex(seeds)
        out[j] = p615f_run(prob, seeds[j], c; kw...)
    end
    return out
end

# ---------------------------------------------------------------------------------------------
# G readers (OPENVT_MONOLAYER_REPO; read only, unpacked into a temporary directory)
# ---------------------------------------------------------------------------------------------

# TST No_CI: 100 run directories of `cell_data_no_inhibition_<MCS>.csv` (x_pos, y_pos, … in
# R; spec §4.4). N for every save; metrics where the rules read them; cut at 1000 cells.
function p615f_g_tst(G, kind)
    zip = joinpath(G, "results", "TST", "TST_No_CI_$(kind).zip")
    d = mktempdir()
    run(`unzip -q -o $zip -d $d`)
    runs = []
    for (root, _, files) in walkdir(d)
        occursin("__MACOSX", root) && continue
        fs = filter(f -> startswith(f, "cell_data_no_inhibition_") && endswith(f, ".csv"), files)
        isempty(fs) && continue
        mcs = [parse(Int, f[(length("cell_data_no_inhibition_") + 1):(end - 4)]) for f in fs]
        p = sortperm(mcs)
        fs, mcs = fs[p], mcs[p]
        rows(f) = filter(!isempty ∘ strip, readlines(joinpath(root, f)))[2:end]
        N = [length(rows(f)) for f in fs]
        s = p615f_cut(p615f_series(mcs ./ P615F_CYCLE, N), 1000)
        r, A, C, w, g = (fill(NaN, length(s.t)) for _ in 1:5)
        for j in p615f_reads(s, 1000)
            xy = [parse.(Float64, split(l, ',')[1:2]) for l in rows(fs[j])]
            m = openvt_metrics(first.(xy), last.(xy), ones(length(xy)))
            r[j], A[j], C[j], w[j], g[j] = m.r, m.A, m.C, m.w, m.g
        end
        push!(runs, (; s.t, s.N, r, A, C, w, g))
    end
    return runs
end
# the draft Fig 8 lattice curves (legacy, D4): t is the file's legacy cycle
function p615f_g_legacy(G, fw)
    pp = joinpath(G, "results", "postprocessing")
    l = split.(readlines(joinpath(pp, "measurements_$(fw).csv")), ',')
    col(name) = findfirst(==(name), l[1])
    num(r, name) = parse(Float64, r[col(name)])
    t = [num(r, "t") for r in l[2:end]]
    N = [round(Int, num(r, "N")) for r in l[2:end]]
    g = [num(r, "g") for r in l[2:end]]
    s = p615f_series(t, N; g)
    nb = split.(readlines(joinpath(pp, "neighbors_$(fw).csv")), ',')[2:end]
    n = [parse(Int, r[1]) for r in nb]
    p = [parse(Float64, r[2]) for r in nb]
    return (; series = s, nmean = p615f_nmean(n, p), g_stop = p615f_cut(s, 10_000).g[end])
end
# the frozen constants' form
function p615f_g_reference(G)
    tst = (; f = p615f_stats(p615f_g_tst(G, "deterministic"), 1000), b = p615f_stats(p615f_g_tst(G, "stochastic"), 1000))
    leg = [p615f_g_legacy(G, fw) for fw in ("compucell3d", "morpheus")]
    return tst, (; nmean = [x.nmean for x in leg], g_stop = [x.g_stop for x in leg]), leg
end

# ---------------------------------------------------------------------------------------------
# Record readers
# ---------------------------------------------------------------------------------------------

function p615f_tsv(path)
    l = split.(readlines(path), '\t')
    return [Dict(zip(l[1], r)) for r in l[2:end]]
end
p615f_f64(x) = x == "nan" ? NaN : parse(Float64, x)
function p615f_record_series(ts, case)
    rows = [r for r in ts if r["case"] == case]
    out = Dict{Int, Any}()
    for seed in unique(parse(Int, r["seed"]) for r in rows)
        rr = [r for r in rows if parse(Int, r["seed"]) == seed]
        F(k) = [p615f_f64(r[k]) for r in rr]
        out[seed] = p615f_series(F("mcs") ./ P615F_CYCLE, [parse(Int, r["N"]) for r in rr]; r = F("r"), A = F("A"),
            C = F("C"), w = F("w"), g = F("g"))
    end
    return out
end
p615f_ver_id(target) = first(split(target))

# every verdict of an evaluated record or rerun: Dict((row, case) => (value, ok))
function p615f_verdicts(S, nb_a)
    out = Dict{Tuple{String, String}, Tuple{Any, Bool}}()
    for (case, ref) in (("f", P615F_TST.f), ("b", P615F_TST.b), ("control", P615F_TST.b))
        r = p615f_f3(p615f_stats(S[case], 1000), ref)
        for (k, id) in zip(keys(r.v), ("F3.1", "F3.2", "F3.3", "F3.4", "F3.5"))
            out[(id, case)] = (r.v[k], r.ok[k])
        end
    end
    for case in ("a", "e", "control")
        r = p615f_v5(p615f_stats(S[case], case == "control" ? 1000 : 10_000))
        out[("V5.1", case)] = (r.v.V5_1, r.ok.V5_1)
        out[("V5.2", case)] = (r.v.V5_2, r.ok.V5_2)
    end
    g1 = p615f_f81(S["a"])
    out[("F8.1", "a")] = (g1, g1 == 1)
    for case in ("a", "e")
        r = p615f_f82(S[case])
        out[("F8.2", case)] = ((r.C_rel, r.w), r.ok)
    end
    nm = p615f_nmean(nb_a.n, nb_a.count)
    out[("F8.3", "a")] = (nm, p615f_in(nm, P615F_BAND.nmean))
    gs = p615f_gstop(S["e"])
    out[("F8.4", "e")] = (gs, p615f_in(gs, P615F_BAND.g_stop))
    return out
end

# ---------------------------------------------------------------------------------------------
# always: the rules on synthetic series
# ---------------------------------------------------------------------------------------------

# an ideal deterministic run: N = 2^⌊t − 0.02⌋ saved every 39 MCS to `cells`
function p615f_ideal(; lag = 0.02, rate = 1.0, cells = 1000)
    t = Float64[]; N = Int[]
    m = 0
    while true
        τ = m / P615F_CYCLE
        n = 2^max(0, floor(Int, rate * (τ - lag)))
        push!(t, τ); push!(N, n)
        n >= cells && break
        m += P615F_EVERY
    end
    r = sqrt.(N .* 1.3)
    return p615f_series(t, N; r, A = π .* r .^ 2, C = 2π .* r .* 1.1, w = 0.05 .* r, g = ones(length(t)))
end

@testset "P6.15f rules: series, grid values, stop, statistics, verdicts" begin
    s = p615f_series([0.1, 0.0, 0.2], [2, 1, 3])
    @test s.t == [0.0, 0.1, 0.2] && s.N == [1, 2, 3]
    @test p615f_at(s, 0.15) == 2 && p615f_at(s, 0.1) == 2 && p615f_at(s, 5.0) == 3
    @test_throws ArgumentError p615f_at(s, -0.1)
    @test p615f_cut(s, 2).N == [1, 2] && p615f_cut(s, 4) === s
    @test p615f_tcross(s, 2) == 0.1 && p615f_tcross(s, 1) == 0.0
    @test p615f_tcross(p615f_series([0.0, 1.0], [1, 4]), 2) ≈ 0.5                 # log-linear
    @test p615f_tcross(p615f_series([0.0, 1.0], [2, 4]), 8) ≈ 2.0                 # extrapolated
    @test_throws ArgumentError p615f_tcross(p615f_series([0.0, 1.0], [4, 4]), 8)
    @test p615f_end(s, 3) == 3 && p615f_end(p615f_series([0.0, 1.0], [96, 200]), 100) == 1
    @test_throws ArgumentError p615f_end(s, 4)
    @test p615f_slope([1.0, 2.0, 3.0], [2.0, 4.0, 6.0]) ≈ 2
    # an ideal deterministic ensemble: log₂ N(k + 0.5) = k, synchronous, slope 1, offset 0.5
    runs = [p615f_cut(p615f_ideal(), 1000) for _ in 1:3]
    st = p615f_stats(runs, 1000)
    @test st.L ≈ collect(0:8) && st.sync == ones(4) && st.slope ≈ 1 && st.offset ≈ 0.5
    @test runs[1].N[end] == 1024 && st.t_stop < runs[1].t[end] && 10.05 < st.t_stop < 10.07
    @test st.r_stop ≈ sqrt(1.3) && st.A_stop ≈ 1.3π
    @test p615f_v5(st).ok == (; V5_1 = true, V5_2 = true)
    r = p615f_f3(st, st)
    @test all(values(r.ok)) && r.v.F3_1 == 0 && r.v.F3_2 == 1
    # each row can fail on its own
    slow = p615f_stats([p615f_cut(p615f_ideal(; rate = 0.8), 1000)], 1000)
    @test !p615f_v5(slow).ok.V5_1 && isapprox(slow.slope, 0.7; atol = 1e-12)         # L = 3, 4, 5, 5, 6 on T_S
    late = p615f_stats([p615f_cut(p615f_ideal(; lag = 1.6), 1000)], 1000)
    @test p615f_v5(late).ok.V5_1 && !p615f_v5(late).ok.V5_2       # parallel to 2^t but 2 cycles late
    @test !p615f_f3(late, st).ok.F3_1 && !p615f_f3(late, st).ok.F3_2
    big = merge(st, (; r = st.r .* 1.15, r_stop = st.r_stop))
    @test !p615f_f3(big, st).ok.F3_3 && p615f_f3(big, st).ok.F3_4
    @test !p615f_f3(merge(st, (; A_stop = st.A_stop * 1.25)), st).ok.F3_4
    @test !p615f_f3(merge(st, (; sync = [1.0, 0.95, 0.85, 1.0])), st).ok.F3_5
    @test p615f_f3(merge(st, (; t_stop = st.t_stop * 1.049)), st).ok.F3_2
    @test !p615f_f3(merge(st, (; t_stop = st.t_stop * 1.051)), st).ok.F3_2
    # F8 rules
    @test p615f_f81(runs) == 1 && p615f_f82(runs).ok && p615f_f82(runs).C_rel ≈ 1.1
    bad = merge(runs[1], (; C = runs[1].C ./ 1.2))                  # C below the circle's
    @test !p615f_f82([bad]).ok
    @test p615f_nmean([5, 6, 7], [25.0, 50.0, 25.0]) ≈ 6
    @test p615f_gstop(runs) == 1
    # the consortium constants have the rules' form, and the bands derive from them
    @test length(P615F_TST.f.L) == length(P615F_TN) == length(P615F_TST.b.L)
    @test length(P615F_TST.f.r) == length(P615F_TR) && length(P615F_TST.f.sync) == 4
    @test P615F_BAND.nmean[1] < 6 < P615F_BAND.nmean[2] && 0 < P615F_BAND.g_stop[1] < P615F_BAND.g_stop[2] < 1
    # the audit's premises: TST passes its own F3 rows and V5; the legacy lattice curves are
    # in the band they define
    @test all(values(p615f_f3(P615F_TST.f, P615F_TST.f).ok))
    @test p615f_v5(P615F_TST.f).ok == (; V5_1 = true, V5_2 = true)
    @test p615f_v5(P615F_TST.b).ok == (; V5_1 = true, V5_2 = true)
    @test minimum(P615F_TST.b.sync) < P615F_BAND.sync                # control C2 holds on TST
end

# a hand-built state with known O1 rows (duck-typed as openvt_snapshot accepts)
function p615f_frame_fixture()
    σ = zeros(Int32, 12, 10)
    σ[2:4, 2:4] .= 1          # cell 1
    σ[5:7, 2:4] .= 2          # cell 2: right of 1 (face contact)
    σ[8:9, 5:6] .= 3          # cell 3: diagonal-only contact with 2 at (7,4)-(8,5)
    σ[2:4, 5:7] .= 4          # cell 4: above 1, diagonal to 2 at (4,5)-(5,4)
    σ[11:12, 9:10] .= 5       # cell 5: isolated, at the lattice corner
    vol = Float64[count(==(c), σ) for c in 1:6]                     # id 6: dead (volume 0)
    A = [9.0, 12.0, 4.0, 10.0, 4.0, 50.0]
    return (; σ, cell = (; volume = vol, A_star = A))
end
# brute-force n: distinct other cells among the Moore(1) neighbours of the cell's sites
function p615f_n_oracle(σ, c)
    s = Set{Int}()
    for I in CartesianIndices(σ)
        σ[I] == c || continue
        for d in CartesianIndices((-1:1, -1:1))
            J = I + d
            checkbounds(Bool, σ, J) || continue
            q = σ[J]
            (q != 0 && q != c) && push!(s, q)
        end
    end
    return length(s)
end

@testset "P6.15f O1 rows: openvt_frame against an oracle" begin
    u = p615f_frame_fixture()
    o = PottsModels.openvt_snapshot(u)
    fr = PottsModels.openvt_frame(u; β = 0.95, γ = 0.3)
    @test keys(fr) == (:x, :y, :i, :n)
    @test length(fr.x) == 5                                         # live cells only
    @test fr.x == o.x && fr.y == o.y
    @test fr.n == [p615f_n_oracle(u.σ, c) for c in 1:5] == [2, 3, 1, 2, 0]
    @test fr.i == [openvt_inhibition_code(o.a[j], o.f[j]; β = 0.95, γ = 0.3) for j in 1:5]
    @test fr.i[2] in (1, 3) && fr.i[5] in (0, 1)                     # a = 9/12 < 0.95; isolated: f = 1
    @test all(in(0:3), fr.i)
    # at β = γ = 0 every cell grows
    @test PottsModels.openvt_frame(u; β = 0.0, γ = 0.0).i == zeros(Int, 5)
    # the O1 writer takes it as is
    io = IOBuffer()
    write_openvt(io, :O1, fr)
    @test startswith(String(take!(io)), "x,y,i,n\n")
end

# ---------------------------------------------------------------------------------------------
# SMOKE: three runs on 240² to t = 8.5 cycles
# ---------------------------------------------------------------------------------------------

const P615F_SMOKE_TMAX = 169 * P615F_EVERY                       # 6591 MCS ≥ 8.5 cycles

if !P615F_FULL
    const P615F_SMOKE = Dict{String, Any}()
    @testset "P6.15f SMOKE: deterministic, stochastic and γ control to 8.5 cycles" begin
        prob = p615f_problem(240, 2000)
        det = merge(P615F_CASES.f, (; L = 240))
        sto = merge(P615F_CASES.b, (; L = 240))
        ctl = merge(P615F_CASES.f, (; gamma = P615F_GAMMA_CTL, L = 240))
        for (name, c, k) in (("f", det, 1), ("b", sto, 2), ("control", ctl, 3))
            P615F_SMOKE[name] = p615f_run(prob, p615f_seed_smoke(k), c; cells = 2000, tmax = P615F_SMOKE_TMAX)
        end
        for (name, r) in P615F_SMOKE
            s = r.series
            @test r.retcode === :Success                               # reached tmax, not the guard
            @test s.t[1] == 0 && s.N[1] == 1 && round(Int, s.t[end] * P615F_CYCLE) == P615F_SMOKE_TMAX
            @test all(diff(round.(Int, s.t .* P615F_CYCLE)) .== P615F_EVERY)
            @test issorted(s.N)
            j3 = findall(>=(3), s.N)
            @test all(isfinite, s.r[j3]) && all(isfinite, s.A[j3])
            @test p615f_f82([s]).ok
        end
        sd, ss, sc = (P615F_SMOKE[k].series for k in ("f", "b", "control"))
        @test all(==(1), sd.g) && all(==(1), ss.g)                     # β = γ = 0
        @test minimum(sc.g) < 1                                        # γ = 1e-4 arrests interior cells
        std, stc = p615f_stats([sd], 200), p615f_stats([sc], 50)
        @info "P6.15f SMOKE" std.L std.sync std.slope stc.L stc.slope p615f_stats([ss], 100).L
        @test std.sync == ones(4)                                      # synchronous doublings, X ≡ 2
        @test p615f_v5(std).ok == (; V5_1 = true, V5_2 = true)
        # the control's mechanism: boundary-limited growth bends log₂ N below the bulk law
        @test !p615f_v5(stc).ok.V5_1 && stc.slope < 0.9
        @test sc.N[end] < sd.N[end]
    end
    @testset "P6.15f SMOKE: O1 rows of the SMOKE states" begin
        for (name, r) in P615F_SMOKE
            c = name == "control" ? (β = 0.0, γ = P615F_GAMMA_CTL) : (β = 0.0, γ = 0.0)
            fr = PottsModels.openvt_frame(r.u; c...)
            o = PottsModels.openvt_snapshot(r.u)
            @test fr.x == o.x && fr.y == o.y && length(fr.n) == r.series.N[end]
            @test all(>=(0), fr.n) && maximum(fr.n) <= 20
            @test 4 < mean(fr.n) < 8
            name == "control" ? (@test any(==(2), fr.i)) : (@test all(==(0), fr.i))
        end
    end
end

# ---------------------------------------------------------------------------------------------
# G: recompute the frozen consortium constants
# ---------------------------------------------------------------------------------------------

@testset "P6.15f G: consortium constants from TST No_CI and the draft Fig 8 files" begin
    if isempty(P615F_REPO) || !isdir(joinpath(P615F_REPO, "results"))
        @test_skip "OPENVT_MONOLAYER_REPO not set"
    else
        tst, leg, legs = p615f_g_reference(P615F_REPO)
        for case in (:f, :b), k in keys(P615F_TST.f)
            @test isapprox(tst[case][k], P615F_TST[case][k]; rtol = 1e-5)
        end
        @test isapprox(leg.nmean, P615F_LEGACY.nmean; rtol = 1e-5)
        @test isapprox(leg.g_stop, P615F_LEGACY.g_stop; rtol = 1e-5)
        # information: V5 on the legacy curves (legacy cycles, D4)
        for (fw, x) in zip(("compucell3d", "morpheus"), legs)
            st = p615f_stats([p615f_cut(x.series, 10_000)], 10_000)
            @info "P6.15f G legacy V5 (information)" fw st.slope st.offset p615f_v5(st).ok
        end
    end
end

# ---------------------------------------------------------------------------------------------
# FULL record (D-146): recompute every row from the committed record
# ---------------------------------------------------------------------------------------------

function p615f_check(ver, devs; broken_ok)
    for pair in P615F_PAIRS
        haskey(ver, pair) || (@test haskey(ver, pair); continue)
        v, ok = ver[pair]
        if ok
            @test ok
        elseif broken_ok
            # a failing row is a D-154 deviation: it must be in the record's table
            @test any(d -> p615f_ver_id(d["target"]) == pair[1] && d["case"] == pair[2], devs)
            @test_broken ok
        else
            @test ok
        end
    end
    for pair in P615F_CONTROL_PAIRS
        @test !ver[pair][2]                                            # the controls fail
    end
    @test ver[("V5.1", "control")][1] < P615F_BAND.slope[1]
    @test ver[("F3.2", "control")][1] > P615F_BAND.t_stop[2]
end

@testset "P6.15f FULL record: F3 (cases f, b), F8 / V5 (cases a, e) and the controls" begin
    dirs = isdir(P615F_DATA) ? filter(d -> startswith(d, "f3-f8-") && isdir(joinpath(P615F_DATA, d)), readdir(P615F_DATA)) :
           String[]
    length(dirs) == 1 || @info "P6.15f: no record yet (expected exactly one reproductions/data/15/f3-f8-* directory)" dirs
    @test length(dirs) == 1
    if length(dirs) == 1
        D = joinpath(P615F_DATA, only(dirs))
        for f in ("runs.tsv", "timeseries.tsv", "neighbors.tsv", "verdicts.tsv", "provenance.toml")
            @test isfile(joinpath(D, f))
        end
        runs = p615f_tsv(joinpath(D, "runs.tsv"))
        ts = p615f_tsv(joinpath(D, "timeseries.tsv"))
        nb = p615f_tsv(joinpath(D, "neighbors.tsv"))
        S = Dict{String, Any}()
        for (case, c) in pairs(P615F_CASES)
            cs = string(case)
            rr = [r for r in runs if r["case"] == cs]
            # the record is the pre-registered protocol
            @test sort([parse(Int, r["seed"]) for r in rr]) == [c.seed(k) for k in 1:c.runs]
            @test all(r -> parse(Float64, r["beta"]) == c.beta && parse(Float64, r["gamma"]) == c.gamma &&
                           parse(Float64, r["sigma_X"]) == c.sigma_X && parse(Int, r["lattice"]) == c.L, rr)
            @test all(r -> r["retcode"] == "Terminated" && parse(Int, r["N"]) >= c.cells, rr)
            ser = p615f_record_series(ts, cs)
            @test sort(collect(keys(ser))) == sort([c.seed(k) for k in 1:c.runs])
            for r in rr
                s = ser[parse(Int, r["seed"])]
                m = round.(Int, s.t .* P615F_CYCLE)
                # saves at 0, every 39 MCS, and the stop (the record's last save)
                @test m[1] == 0 && m[end] == parse(Int, r["mcs"]) && s.N[end] == parse(Int, r["N"])
                @test all(x -> x % P615F_EVERY == 0, m[1:(end - 1)]) && all(diff(m) .> 0)
                @test all(diff(m[1:(end - 1)]) .== P615F_EVERY)
            end
            S[cs] = [p615f_cut(s, c.cells) for s in values(ser)]
        end
        na = [r for r in nb if r["case"] == "a"]
        @test sort(unique(parse(Int, r["seed"]) for r in na)) == [P615F_CASES.a.seed(k) for k in 1:P615F_CASES.a.runs]
        nn = sort(unique(parse(Int, r["n"]) for r in na))
        nb_a = (; n = nn, count = [sum(parse(Int, r["count"]) for r in na if parse(Int, r["n"]) == n) for n in nn])
        # the neighbour histogram holds every final cell of case (a) once
        @test sum(nb_a.count) == sum(parse(Int, r["N"]) for r in runs if r["case"] == "a")
        ver = p615f_verdicts(S, nb_a)
        @info "P6.15f record" Dict(k => v[1] for (k, v) in ver)
        dev_f = joinpath(D, "deviations.tsv")
        devs = isfile(dev_f) ? p615f_tsv(dev_f) : Dict{String, String}[]
        p615f_check(ver, devs; broken_ok = true)
        # the committed verdicts agree with this recomputation
        vt = p615f_tsv(joinpath(D, "verdicts.tsv"))
        for pair in [P615F_PAIRS; P615F_CONTROL_PAIRS]
            rr = [r for r in vt if p615f_ver_id(r["target"]) == pair[1] && r["case"] == pair[2]]
            @test length(rr) == 1 && only(rr)["result"] == (ver[pair][2] ? "PASS" : "FAIL")
        end
    end
end

# ---------------------------------------------------------------------------------------------
# FULL: rerun the 240 runs (offline, on the PC; D-146, D-157)
# ---------------------------------------------------------------------------------------------

if P615F_FULL
    @testset "P6.15f FULL: F3, F8 / V5 and the controls, rerun" begin
        S = Dict{String, Any}()
        nb_a = nothing
        for (case, c) in pairs(P615F_CASES)
            prob = p615f_problem(c.L, c.cells)
            out = p615f_runs(prob, [c.seed(k) for k in 1:c.runs], c)
            @test all(r -> r.retcode === :Terminated && r.series.N[end] >= c.cells, out)
            S[string(case)] = [p615f_cut(r.series, c.cells) for r in out]
            if case === :a
                n = reduce(vcat, [PottsModels.openvt_frame(r.u; β = c.beta, γ = c.gamma).n for r in out])
                nn = sort(unique(n))
                nb_a = (; n = nn, count = [count(==(k), n) for k in nn])
            end
        end
        ver = p615f_verdicts(S, nb_a)
        @info "P6.15f FULL" Dict(k => v[1] for (k, v) in ver)
        p615f_check(ver, Dict{String, String}[]; broken_ok = false)
    end
end
