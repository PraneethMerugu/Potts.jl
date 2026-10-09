# D-203: reproduction 04 (foam, Jiang et al. 1999, "04b"), the pre-registered scan of a
# separate bulk shear scale κ_b. Frozen (AUTONOMY §7.3) BEFORE any scan run. Decisions:
# D-203 (this scan), D-190 (the frozen reproduction test 04_foam.jl, whose functions, foams,
# seeds pattern and τ this file reuses unchanged), D-154 (deviations), D-156 (unstated
# parameters are calibrated and labelled; heavy runs on the PC), D-157 (all heavy compute on
# the PC), D-048 (oracles and negative controls, no parity harness).
#
# ── What changes against D-190, and what does not ─────────────────────────────────────────
# D-190 used one scale κ (A-1) for both shear terms: model γ0 = κ·γ0_paper (Eq. 6) and model
# β = κ·β_paper (Eq. 7). D-203 keeps the F1 displacement form, keeps the boundary
# κ = 2.497 (the D-190 FULL record's calibration.tsv, 2.4967980904210996) for Eq. 6
# unchanged, and gives the bulk Eq. 7 term its own scale:
#     γ(y, t) = −κ_b·β_paper·(y − (L_y + 1)/2)·G(t),   G = 1 (steady),
# i.e. the model parameter `β` of `P64RShearedFoam` is κ_b·β_paper. Nothing else changes:
# lattice 256², (Periodic(), Closed()), NeighborOrder(4) contacts and proposals, J = 3,
# Γ = 1, T = 1e-6, `BoundarySiteCPM()` (DV1), T1s counted with `t1_events(...; unit = :t1)`
# on the VonNeumann(1) `cell_graph` of consecutive MCS.
#
# Does the code expose κ_b separately? At the MODEL level, yes in effect: in
# `P64RShearedFoam` (04_foam.jl) the Eq. 6 term reads only `γ0` and the Eq. 7 term only `β`,
# both free parameters in model units, so the two scales are already independent and the scan
# needs no new model parameter. The coupling is in the HARNESS: D-190's `p64r_bulk(st, βp, κ,
# …)` takes one κ, and the FULL runner and `p64r_full` pass the boundary κ (`κ.kappa`) to it,
# and the record tier asserts `beta_model ≈ κ·beta`. If this scan returns a κ_b, the re-frozen
# 04 test needs a pre-registered constant (say `P64R_KAPPA_B`, a D-entry value) passed as the
# κ argument of every `p64r_bulk` call, a `beta_model ≈ κ_b·beta` record check, and κ_b in
# calibration.tsv. This file implements none of that (D-203: the test is re-frozen only after
# a D-entry).
#
# ── The scan (pre-registered; set "kb", seed block 13) ──────────────────────────────────────
# Foams: ordered foams k = 1..5 exactly as D-190 (`p64r_foam(:ordered, k)`, prep seeds
#   `p64r_prep_seed(:ordered, k, try)`: the same foams as the D-190 FULL record). τ = 1/ū
#   over foams 1..5 (`p64r_ubar`, the D-190 A-5 τ, as `p64r_tau`). Runs use foams k = 1..3.
# Seeds: n = 3 replicates; run seed `p64r_run_seed(13, j, k)` with j the β index (1..5) and k
#   the foam. The seed does not depend on κ_b: common random numbers across the κ_b grid, so
#   the t_first(κ_b) curve of a replicate is paired along the grid. Block 13 is unused by D-190.
# β (paper units): {1e-4, 1e-3, 5e-3, 0.01, 0.05} (D-203 (a); Fig. 9's set). Model β = κ_b·β.
# κ_b grid: κ_b = κ_D190 · 2^(i/2), i = −8..14: 23 values, 0.156 … 319.6, step √2.
#   Anchored on the boundary κ so that i = 0 is the D-190 bulk setting (a harness control
#   against the D-190 record, below). Bounds, from the D-190 FULL record (ordered foams,
#   bulk.tsv set "spec", the only information used):
#   - at κ = 2.497, paper β = 0.005 (model 0.0125) gave no T1 in 2^17 paper MCS (5/5), and
#     paper β = 0.01 (model 0.025) gave t_first = 425–475 (median 455);
#   - lower bound κ_b = κ/16 = 0.156: paper β = 0.05 is model 0.0078 < 0.0125, below the
#     pinned value, so every β is slower than its target (or never yields): the grid starts
#     below both fit targets' crossings;
#   - upper bound κ_b = 128κ = 319.6: paper β = 1e-4 is model 0.032 > 0.025, above the
#     yielding value, so T1s occur at every β and β = 0.01, 0.05 are far faster than their
#     targets: the grid ends above both crossings and above the consistency onset.
#   - step √2 (41 %): narrower than the acceptance window (1.25/0.75 = 1.67), so under the
#     naive scaling t_first ∝ 1/κ_b at least one grid value falls inside each target window.
# Run: steady bulk shear (G = 1, bulk = 1, γ0 = 0) from the relaxed foam, per MCS T1 series
#   N (as `p64r_bulk`). t_first = `yield_strain((1:T)/τ, N; threshold = 1, window =
#   round(Int, 100τ))` rounded to an Int (paper MCS; exactly D-190's t_first); none → −1.
# Cap (paper MCS): 2^16 = 65 536 for β ∈ {1e-4, 1e-3}; 2^14 = 16 384 for β ≥ 5e-3; our MCS =
#   `p64r_ours(cap, τ)`. Justification: the paper's ordered first T1 is ε_y/(c·β) with
#   Fig. 11(a)'s ordered ε_y (1.13, 1.10, 1.11, 0.80, 0.43 at β = 0.001 … 0.05) and c =
#   0.0205–0.0258: β = 0.001 → 43 800–55 100 (cap 2^16 covers it by ≥ 19 %); β = 0.005 →
#   8 500–10 700 and β = 0.01 → 4 300 (2^14 = 3.8 × 4 300, far beyond the +25 % edge 5 375).
#   β = 1e-4 would need ≈ 4.4–5.5 × 10⁵ on the ordered plateau: no affordable cap reaches it,
#   so its rows are info only (it gets the 2^16 cap).
# Early stop (exact): the run stops at the first check (every w = round(Int, 100τ) of our MCS,
#   and at the cap) where `yield_strain` on the prefix finds index i with i ≤ m − w + 1. Then
#   every candidate before i has its full window inside the prefix and failed, and i's window
#   is complete, so the full-cap result is i: t_first is identical to a run to the cap
#   (oracle below). Recorded: our MCS run (`mcs_run`) and T1s up to the stop (`t1_total`).
# Jobs: 23 κ_b × 5 β × 3 replicates = 345, plus the 5 foams.
#
# ── Fit target (D-203 (b)) ──────────────────────────────────────────────────────────────────
# Spec 04 §3.2 ("Yield-strain calibration, ordered bulk shear", from 04b Figs. 4(b), 5(b),
# 11(a)): β = 0.01 → first T1 ≈ 4300 MCS; β = 0.05 → first T1 ≈ 420 MCS; ε_y ≈ c·β·t with
# c ≈ 0.020–0.026. The paper itself gives no tolerance (04b p.5826 only reads Figs. 4(b) and
# 5(b), and p.5827 says "the yield strain remains almost the same", which Fig. 11(a)
# contradicts: spec A-17 (i)). The ±25 % band is spec §3.2's own wording: "The ≈ 25%
# mismatch between the two estimates marks the limits of this calibration" (the two c
# values, 0.0258 and 0.0205, differ by 26 %).
# Rule: med_β(κ_b) = the median over the 3 replicates of t_first, with −1 read as +Inf (no
#   yield within the cap) and t_first clamped to ≥ 1 for the logarithms. A grid value meets
#   the fit iff |med_β/target_β − 1| ≤ 0.25 for BOTH β = 0.01 (4300) and β = 0.05 (420).
#
# ── Consistency check (D-203 (c)) ───────────────────────────────────────────────────────────
# "T1s occur at β ≤ 0.001, so Fig. 9's N̄ > 0." N̄ > 0 ⇔ t1_total > 0 (N̄ is t1_total over
# positive factors). Pre-registered: at β = 1e-3, t1_total > 0 within the cap in at least
# k = 2 of the n = 3 replicates. β = 1e-3 is the largest β ≤ 0.001 and the one where the
# paper's ORDERED foam yields (Fig. 11(a): ε_y = 1.13 at 0.001, the plateau); Fig. 9's own
# foams are disordered, and on the ordered plateau β = 1e-4 cannot yield within any
# affordable cap, so β = 1e-4 is recorded (info) and does not gate.
#
# ── Decision rule (D-203 (d); `p64kb_analyse` / `p64kb_decide`, pure, tested below) ────────
# Input: the scan table; it must be exactly the pre-registered grid × β × replicates (else
# ArgumentError: an incomplete table is not a result).
# 1. Grid path (checked first). P = the grid values that meet the fit (both targets) AND the
#    consistency check. If |P| = 1, return that κ_b.
# 2. Otherwise (|P| = 0 or ≥ 2), the interpolation path. For each target β:
#    - med_β along the grid must not cross the target upward (med_i < target ≤ med_{i+1}
#      anywhere → `nothing`, :non_monotone); there must be one downward crossing
#      med_i ≥ target > med_{i+1} (none → `nothing`, :not_bracketed);
#    - med_i must be finite (an Inf → finite step is a pinning cliff → `nothing`,
#      :pinning_cliff);
#    - κ̂_β = log–log linear interpolation of (κ_b, med_β) on that bracket at the target.
#    κ̂ = √(κ̂_0.01 · κ̂_0.05). The log–log interpolated med_β(κ̂) must meet BOTH targets within
#    ±25 % (bracket ends must be finite; else `nothing`, :off_target), and the consistency
#    check must hold at the largest grid value ≤ κ̂ (the conservative neighbour; else
#    `nothing`, :consistency). Then return κ̂ (an off-grid value: the D-entry, re-frozen test
#    and the 200 bulk jobs re-run validate it, D-203 (d)).
# A returned κ_b → the spec owner, then a D-entry, re-freeze, re-run (D-203). `nothing` →
# stop: the Eq. 2 form is in question, the record stays provisional, F1 hard gate (Dr Jiang).
#
# ── Harness control against the D-190 record (record tier) ─────────────────────────────────
# At i = 0 (κ_b = κ_D190) the scan repeats D-190's ordered bulk runs at β = 0.01 and 0.05
# (other seeds, same foams 1..3, same model β). D-190 record medians (ordered, set "spec",
# 5 replicates): 455 and 40 paper MCS. The scan's medians there must lie within ±25 % of them.
#
# ── Cost (estimate) ─────────────────────────────────────────────────────────────────────────
# Per (κ_b, replicate), worst case (every run to its cap): 2 × 65 536 + 3 × 16 384 = 180 224
# paper MCS = 6.2 × 10⁵ of our MCS at τ = 3.447. × 69 = 4.3 × 10⁷ our MCS. The D-190 FULL ran
# ≈ 1.35 × 10⁸ our MCS in 9.7 h on 24 PC threads ≈ 6.2 ms per MCS per thread (with heavier
# per-window analysis than here): worst case ≈ 74 thread-h ≈ 3.1 h on 24 threads. With the
# D-190 pinning pattern (model β ≲ 0.0125–0.025 never yields) about 2/3 of that runs to the
# cap: expected ≈ 2 h on 24 threads. The longest job is ≈ 2.3 × 10⁵ our MCS (≈ 25 min).
# Mac: SMOKE only (≈ 10 s of runs plus compilation).
#
# ── Tiers ───────────────────────────────────────────────────────────────────────────────────
# always: the decision rule on synthetic tables (with negative controls), the early-stop
#   oracle, the grid and cap bounds.
# SMOKE (default, gate P6.4a1 as D-190): foam 1, κ_b = κ_D190, β = 0.05, cap 300 paper MCS
#   (yields, stops early); control β = 0, cap 100 (no T1, runs to the cap); TSV round trip.
# SCAN (P64KB_SCAN=true; offline on the PC, D-157): runs the 345 jobs; with
#   P64KB_OUT=<dir> writes scan.tsv, provenance.toml and decision.toml there. Copy to
#   lib/PottsModels/reproductions/data/04/kb-scan-<date>/.
# record (always): reads the one reproductions/data/04/kb-scan-*/scan.tsv: `@test_broken`
#   until it exists; then checks completeness, τ and the harness control, recomputes the
#   decision (and compares it with decision.toml when present) and reports it. The decision
#   itself (a κ_b or `nothing`) is an outcome, not a pass/fail.
#
# scan.tsv schema (one header line, tab-separated): kappa_b, beta, beta_model, k, seed, tau,
# cap (paper MCS), mcs_run (our MCS), t_first (paper MCS, −1 none), t1_total.
using Potts, PottsModels, Test, Dates
using Statistics: mean, median

# The frozen D-190 test provides the model, foams, τ and run helpers (`p64r_*`). In
# runtests.jl it is included first (sorted order, same module); standalone, include it here.
isdefined(@__MODULE__, :p64r_ordered) || include(joinpath(@__DIR__, "04_foam.jl"))

# ---------------------------------------------------------------------------------------------
# Constants (pre-registered)
# ---------------------------------------------------------------------------------------------

const P64KB_SCAN = get(ENV, "P64KB_SCAN", "false") == "true"
const P64KB_OUT = get(ENV, "P64KB_OUT", "")
const P64KB_KAPPA_D190 = 2.4967980904210996            # boundary κ (D-190 record calibration.tsv)
const P64KB_GRID_I = collect(-8:14)
const P64KB_GRID = P64KB_KAPPA_D190 .* 2.0 .^ (P64KB_GRID_I ./ 2)   # 0.156 … 319.6, step √2
const P64KB_BETAS = [1e-4, 1e-3, 5e-3, 0.01, 0.05]
const P64KB_CAP = Dict(1e-4 => 2^16, 1e-3 => 2^16, 5e-3 => 2^14, 0.01 => 2^14, 0.05 => 2^14)   # paper MCS
const P64KB_N, P64KB_K = 3, 2                           # replicates; consistency needs ≥ K of N
const P64KB_TAU_FOAMS = 5                               # τ over ordered foams 1..5 (D-190)
const P64KB_TARGETS = (0.01 => 4300.0, 0.05 => 420.0)   # spec §3.2, paper MCS
const P64KB_TOL = 0.25                                  # spec §3.2's ≈ 25 % calibration limit
const P64KB_CONS_BETA = 1e-3
const P64KB_BLOCK = 13
const P64KB_D190_MED = (0.01 => 455.0, 0.05 => 40.0)    # D-190 record, ordered "spec" medians
const P64KB_SMOKE_CAP, P64KB_SMOKE_CAP0 = 300, 100
const P64KB_COLS = ["kappa_b" => Float64, "beta" => Float64, "beta_model" => Float64, "k" => Int, "seed" => Int,
    "tau" => Float64, "cap" => Int, "mcs_run" => Int, "t_first" => Int, "t1_total" => Float64]

p64kb_seed(j, k) = p64r_run_seed(P64KB_BLOCK, j, k)

# ---------------------------------------------------------------------------------------------
# Decision rule (pure)
# ---------------------------------------------------------------------------------------------

"""t_first as a number for medians and logs: −1 (no yield within the cap) → Inf; ≥ 1."""
p64kb_tval(t) = t < 0 ? Inf : max(Float64(t), 1.0)
"""Within the ±tol band of the target (Inf never is)."""
p64kb_within(t, target; tol = P64KB_TOL) = isfinite(t) && abs(t / target - 1) <= tol + 1e-12

"""(t, n1) arrays [κ_b index, β index, replicate] from table rows; the table must be exactly
the grid × betas × seeds (no row missing, duplicated or off the design)."""
function p64kb_cube(rows; grid = P64KB_GRID, betas = P64KB_BETAS, seeds = 1:P64KB_N)
    t = fill(NaN, length(grid), length(betas), length(seeds))
    n1 = fill(NaN, size(t))
    for r in rows
        i = findfirst(g -> isapprox(g, Float64(r["kappa_b"]); rtol = 1e-9), grid)
        j = findfirst(b -> isapprox(b, Float64(r["beta"]); rtol = 1e-9), betas)
        k = findfirst(==(Int(r["k"])), seeds)
        (i === nothing || j === nothing || k === nothing) &&
            throw(ArgumentError("p64kb: row off the design (κ_b = $(r["kappa_b"]), β = $(r["beta"]), k = $(r["k"]))"))
        isnan(t[i, j, k]) || throw(ArgumentError("p64kb: duplicate row (κ_b = $(grid[i]), β = $(betas[j]), k = $(r["k"]))"))
        t[i, j, k] = p64kb_tval(r["t_first"])
        n1[i, j, k] = Float64(r["t1_total"])
    end
    any(isnan, t) && throw(ArgumentError("p64kb: incomplete table ($(count(isnan, t)) of $(length(t)) rows missing)"))
    return t, n1
end

"""κ where the log–log line through (κ1, m1), (κ2, m2) reaches m (m1 ≥ m > m2, finite)."""
p64kb_interp(κ1, m1, κ2, m2, m) = exp(log(κ1) + (log(m) - log(m1)) * (log(κ2) - log(κ1)) / (log(m2) - log(m1)))
"""med at κ by log–log interpolation along the grid; Inf if a bracket end is Inf."""
function p64kb_at(grid, med, κ)
    j = findlast(g -> g <= κ * (1 + 1e-12), grid)
    (j === nothing || (j == length(grid) && !isapprox(grid[j], κ; rtol = 1e-12))) && return Inf
    isapprox(grid[j], κ; rtol = 1e-12) && return med[j]
    (isfinite(med[j]) && isfinite(med[j + 1])) || return Inf
    return exp(log(med[j]) + (log(κ) - log(grid[j])) * (log(med[j + 1]) - log(med[j])) / (log(grid[j + 1]) - log(grid[j])))
end

"""The D-203 decision on a scan table: (kappa_b = Float64 or nothing, path, reason, khat,
med, cons, fit, P). See the header for the rule."""
function p64kb_analyse(rows; grid = P64KB_GRID, betas = P64KB_BETAS, seeds = 1:P64KB_N, k_req = P64KB_K,
        targets = P64KB_TARGETS, tol = P64KB_TOL, cons_beta = P64KB_CONS_BETA)
    t, n1 = p64kb_cube(rows; grid, betas, seeds)
    jb(β) = findfirst(b -> isapprox(b, β; rtol = 1e-9), betas)
    ng = length(grid)
    med = [median(t[i, j, :]) for i in 1:ng, j in eachindex(betas)]
    cons = [count(>(0), n1[i, jb(cons_beta), :]) >= k_req for i in 1:ng]
    fit = [all(p64kb_within(med[i, jb(β)], tg; tol) for (β, tg) in targets) for i in 1:ng]
    P = findall(fit .& cons)
    out(κ, path, reason, khat) = (; kappa_b = κ, path, reason, khat, med, cons, fit, P)
    length(P) == 1 && return out(grid[only(P)], :grid, :ok, Float64[])
    khat = Float64[]
    for (β, tg) in targets
        m = med[:, jb(β)]
        any(i -> m[i] < tg && m[i + 1] >= tg, 1:(ng - 1)) && return out(nothing, :interp, :non_monotone, khat)
        d = findfirst(i -> m[i] >= tg && m[i + 1] < tg, 1:(ng - 1))
        d === nothing && return out(nothing, :interp, :not_bracketed, khat)
        isfinite(m[d]) || return out(nothing, :interp, :pinning_cliff, khat)
        push!(khat, p64kb_interp(grid[d], m[d], grid[d + 1], m[d + 1], tg))
    end
    κ̂ = exp(mean(log, khat))
    all(p64kb_within(p64kb_at(grid, med[:, jb(β)], κ̂), tg; tol) for (β, tg) in targets) ||
        return out(nothing, :interp, :off_target, khat)
    cons[findlast(g -> g <= κ̂ * (1 + 1e-12), grid)] || return out(nothing, :interp, :consistency, khat)
    return out(κ̂, :interp, :ok, khat)
end
"""The chosen κ_b, or `nothing` (stop: the F1 gate)."""
p64kb_decide(rows; kw...) = p64kb_analyse(rows; kw...).kappa_b

# ---------------------------------------------------------------------------------------------
# Early stop (pure) and the run
# ---------------------------------------------------------------------------------------------

"""After m of our MCS (N = the per-MCS T1 series so far): (done, tf). done once the
prefix's yield index i has a complete window (i ≤ m − w + 1), or at the cap (final);
tf = i/τ (paper MCS), or nothing."""
function p64kb_settled(N, τ, w; final = false)
    m = length(N)
    i = P64R_AN.yield_strain(collect(1.0:m), N; threshold = 1, window = w)
    i === nothing && return (done = final, tf = nothing)
    i = round(Int, i)
    return (done = final || i <= m - w + 1, tf = i / τ)
end
"""The stopping loop on a given series (checks every w MCS and at the cap): (tf, m)."""
function p64kb_online(N, τ, w)
    T = length(N)
    for m in 1:T
        (m % w == 0 || m == T) || continue
        d = p64kb_settled(view(N, 1:m), τ, w; final = m == T)
        d.done && return (tf = d.tf, m)
    end
end

"""One scan run: steady bulk shear at model β = βm from state st, cap `cap` paper MCS."""
function p64kb_run(st, βm, cap, seed, τ)
    lat = p64r_lat(size(st.σ))
    T = p64r_ours(cap, τ)
    w = round(Int, 100τ)
    integ = init(p64r_problem(st, T; shear = true, β = βm, bulk = true, seed), P64R_ALG)
    g = P64R_AN.cell_graph(st.σ, lat)
    N = zeros(T)
    for m in 1:T
        step!(integ)
        g2 = P64R_AN.cell_graph(integ.u.σ, lat)
        N[m] = P64R_AN.t1_events(g, g2; unit = :t1)
        g = g2
        (m % w == 0 || m == T) || continue
        d = p64kb_settled(view(N, 1:m), τ, w; final = m == T)
        d.done && return (t_first = d.tf === nothing ? -1 : round(Int, d.tf), mcs_run = m, t1_total = sum(view(N, 1:m)))
    end
end

function p64kb_write(dir, rows)
    mkpath(dir)
    open(joinpath(dir, "scan.tsv"), "w") do io
        println(io, join(first.(P64KB_COLS), '\t'))
        for r in rows
            println(io, join((string(r[c]) for (c, _) in P64KB_COLS), '\t'))
        end
    end
end
function p64kb_read(file)
    ls = readlines(file)
    h = split(ls[1], '\t')
    h == first.(P64KB_COLS) || throw(ArgumentError("p64kb: scan.tsv header $(h)"))
    return [Dict{String, Any}(c => parse(T, v) for ((c, T), v) in zip(P64KB_COLS, split(l, '\t'))) for l in ls[2:end] if !isempty(l)]
end

# ---------------------------------------------------------------------------------------------
# always: the rule on synthetic tables, the early-stop oracle, the design
# ---------------------------------------------------------------------------------------------

"""A synthetic complete table: t(κ, β, k) and n1(κ, β, k)."""
p64kb_synth(tf, n1; grid = P64KB_GRID) = [Dict{String, Any}("kappa_b" => κ, "beta" => β, "k" => k, "t_first" => tf(κ, β, k),
    "t1_total" => n1(κ, β, k)) for κ in grid for β in P64KB_BETAS for k in 1:P64KB_N]
"""t ∝ 1/κ_b through the targets at κ01 (β = 0.01) and κ05 (β = 0.05); others ∝ 1/(κβ)."""
p64kb_pow(κ01, κ05; cap = 2^16) = (κ, β, k) -> begin
    t = β == 0.01 ? 4300κ01 / κ : β == 0.05 ? 420κ05 / κ : 43κ01 / (κ * β)
    t > cap ? -1 : round(Int, t)
end
p64kb_cons(κc; who = 1:P64KB_N) = (κ, β, k) -> (β >= 1e-3 && κ >= κc * (1 - 1e-12) && k in who) ? 3.0 : 0.0

@testset "04 κ_b scan: the design" begin
    @test length(P64KB_GRID) == 23 && P64KB_GRID[9] == P64KB_KAPPA_D190 && issorted(P64KB_GRID)
    @test all(r -> r ≈ √2, P64KB_GRID[2:end] ./ P64KB_GRID[1:(end - 1)])
    @test P64KB_GRID[1] * 0.05 < 0.0125 && P64KB_GRID[end] * 1e-4 > 0.025      # bracket (header)
    @test √2 < (1 + P64KB_TOL) / (1 - P64KB_TOL)                               # step narrower than the window
    @test P64KB_CAP[1e-3] >= 1.13 / (0.0205 * 1e-3) && P64KB_CAP[0.01] >= 1.25 * 4300 && P64KB_CAP[5e-3] >= 1.10 / (0.0205 * 5e-3)
    @test sort(collect(keys(P64KB_CAP))) == P64KB_BETAS && P64KB_K <= P64KB_N
    seeds = [p64kb_seed(j, k) for j in eachindex(P64KB_BETAS) for k in 1:P64KB_N]
    @test allunique(seeds) && !any(s -> s in seeds, [p64r_run_seed(b, i, k) for b in 1:12 for i in 0:200 for k in 1:10])
end

@testset "04 κ_b scan: decision rule on synthetic tables" begin
    g = P64KB_GRID
    @test p64kb_within(5375, 4300) && !p64kb_within(5376, 4300) && p64kb_within(3225, 4300) && !p64kb_within(3224, 4300)
    @test !p64kb_within(Inf, 4300) && p64kb_tval(-1) == Inf && p64kb_tval(0) == 1.0
    # (1) both targets met at one grid value; consistency from below it → that grid value
    A = p64kb_analyse(p64kb_synth(p64kb_pow(g[12], g[12]), p64kb_cons(g[10])))
    @test A.kappa_b == g[12] && A.path === :grid && A.P == [12]
    # (2) off-grid optimum (two grid values pass) → interpolation, recovers κ*
    κs = sqrt(g[12] * g[13])
    A = p64kb_analyse(p64kb_synth(p64kb_pow(κs, κs), p64kb_cons(g[10])))
    @test length(A.P) == 2 && A.path === :interp && A.reason === :ok && isapprox(A.kappa_b, κs; rtol = 1e-3)
    # (3) robust to one replicate never yielding; to row order
    t1 = p64kb_pow(g[12], g[12])
    rows = p64kb_synth((κ, β, k) -> k == 3 ? -1 : t1(κ, β, k), p64kb_cons(g[10]))
    @test p64kb_decide(rows) == g[12]
    @test p64kb_decide(reverse(rows)) == g[12] && p64kb_decide(rows[sortperm([hash(r["kappa_b"] * r["k"]) for r in rows])]) == g[12]
    # negative controls → nothing
    # (N1) the two targets want κ_b a factor 4 apart (the expected F1 shape)
    A = p64kb_analyse(p64kb_synth(p64kb_pow(g[12], g[8]), p64kb_cons(g[1])))
    @test A.kappa_b === nothing && A.reason === :off_target && isempty(A.P)
    # (N2) consistency fails: β = 1e-3 has no T1 at or below the fitted κ_b
    A = p64kb_analyse(p64kb_synth(p64kb_pow(g[12], g[12]), p64kb_cons(g[14])))
    @test A.kappa_b === nothing && A.reason === :consistency
    # (N3) k of n: 2 of 3 replicates suffice, 1 does not
    @test p64kb_decide(p64kb_synth(p64kb_pow(g[12], g[12]), p64kb_cons(g[10]; who = 1:2))) == g[12]
    @test p64kb_decide(p64kb_synth(p64kb_pow(g[12], g[12]), p64kb_cons(g[10]; who = 1:1))) === nothing
    # (N4) a pinning cliff: no yield below model β = 0.02, fast above
    A = p64kb_analyse(p64kb_synth((κ, β, k) -> κ * β >= 0.02 ? 100 : -1, p64kb_cons(g[1])))
    @test A.kappa_b === nothing && A.reason === :pinning_cliff
    # (N5) not bracketed: the optimum lies above, or below, the grid
    @test p64kb_analyse(p64kb_synth(p64kb_pow(1000.0, 1000.0; cap = 10^9), p64kb_cons(g[1]))).reason === :not_bracketed
    @test p64kb_analyse(p64kb_synth(p64kb_pow(0.01, 0.01), p64kb_cons(g[1]))).reason === :not_bracketed
    # (N6) non-monotone in κ_b (an upward crossing) → nothing on the interpolation path; the
    # grid path is checked first, so one passing grid value still decides
    ts = p64kb_pow(κs, κs)
    A = p64kb_analyse(p64kb_synth((κ, β, k) -> κ ≈ g[16] ? 10^5 : ts(κ, β, k), p64kb_cons(g[10])))
    @test A.kappa_b === nothing && A.reason === :non_monotone && A.path === :interp
    @test p64kb_decide(p64kb_synth((κ, β, k) -> κ ≈ g[16] ? 10^5 : t1(κ, β, k), p64kb_cons(g[10]))) == g[12]
    # (N7) no table is not a result: missing, duplicated or off-design rows throw
    rows = p64kb_synth(t1, p64kb_cons(g[10]))
    @test_throws ArgumentError p64kb_decide(rows[2:end])
    @test_throws ArgumentError p64kb_decide([rows; rows[1:1]])
    @test_throws ArgumentError p64kb_decide([rows[2:end]; Dict{String, Any}(rows[1]..., "kappa_b" => 2.5)])
    @test_throws ArgumentError p64kb_decide([rows[2:end]; Dict{String, Any}(rows[1]..., "beta" => 0.02)])
    # interpolation and lookup oracles
    @test p64kb_interp(1.0, 100.0, 4.0, 25.0, 50.0) ≈ 2.0
    @test p64kb_at([1.0, 4.0], [100.0, 25.0], 2.0) ≈ 50.0 && p64kb_at([1.0, 4.0], [Inf, 25.0], 2.0) == Inf
end

@testset "04 κ_b scan: early stop equals the full-cap yield_strain" begin
    τ, w = 3.447, round(Int, 100 * 3.447)
    full(N) = (r = P64R_AN.yield_strain(collect(1:length(N)) ./ τ, N; threshold = 1, window = w);
        r === nothing ? -1 : round(Int, r))
    early(N) = (o = p64kb_online(N, τ, w); o.tf === nothing ? -1 : round(Int, o.tf))
    for s in 1:200
        T = 2000 + 37s
        N = zeros(T)
        for _ in 1:(s % 7)
            N[mod1(7919s * (length(N) ÷ 3 + 1) + 13 * count(>(0), N), T)] = 0.5         # isolated half-T1s
        end
        s % 3 == 0 && (N[mod1(104729s, T)] = 1.0)
        s % 5 == 0 && (N[T - 3] = 0.5; N[T] = 0.5)                                    # a yield in the truncated tail
        @test early(N) == full(N)
    end
    N = zeros(3000)
    N[500] = 0.5
    N[500 + w - 1] = 0.5                                     # completes exactly at the window's end
    @test early(N) == full(N) == round(Int, 500 / τ)
    o = p64kb_online(N, τ, w)
    @test o.m < 3000 && o.m >= 500 + w - 1                   # stopped early, after the window closed
    N[100] = 0.5                                             # an earlier lone half-T1 does not yield
    @test early(N) == full(N) == round(Int, 500 / τ)
    @test early(zeros(1000)) == -1 && p64kb_online(zeros(1000), τ, w).m == 1000
end

# ---------------------------------------------------------------------------------------------
# SMOKE (Mac): the harness on one κ_b, one β, a short cap (gate P6.4a1, as D-190)
# ---------------------------------------------------------------------------------------------

if !P64KB_SCAN
    @testset "04 κ_b scan SMOKE: one κ_b, one β, short cap" begin
        if !P64R_SHEAR_READY
            @test_broken P64R_SHEAR_READY
        else
            p64r_template(false, P64R_L)
            p64r_template(true, P64R_L)
            st, row = p64r_foam(:ordered, 1)
            τ = 1 / row["ubar"]
            @test 2.5 < τ < 4.5
            r = p64kb_run(st, P64KB_KAPPA_D190 * 0.05, P64KB_SMOKE_CAP, p64kb_seed(5, 1), τ)
            @info "04 κ_b SMOKE" τ r.t_first r.mcs_run r.t1_total
            @test 0 <= r.t_first <= P64KB_SMOKE_CAP && r.t1_total > 0
            @test r.mcs_run < p64r_ours(P64KB_SMOKE_CAP, τ)                           # stopped early
            # control: no drive → no T1, runs to the cap
            r0 = p64kb_run(st, 0.0, P64KB_SMOKE_CAP0, p64kb_seed(5, 1), τ)
            @test r0.t_first == -1 && r0.t1_total == 0 && r0.mcs_run == p64r_ours(P64KB_SMOKE_CAP0, τ)
            # the scan.tsv round trip
            rows = [Dict{String, Any}("kappa_b" => P64KB_KAPPA_D190, "beta" => β, "beta_model" => P64KB_KAPPA_D190 * β,
                "k" => 1, "seed" => p64kb_seed(5, 1), "tau" => τ, "cap" => c, "mcs_run" => x.mcs_run,
                "t_first" => x.t_first, "t1_total" => x.t1_total) for (β, c, x) in ((0.05, P64KB_SMOKE_CAP, r), (0.0, P64KB_SMOKE_CAP0, r0))]
            mktempdir() do d
                p64kb_write(d, rows)
                @test p64kb_read(joinpath(d, "scan.tsv")) == rows
            end
        end
    end
end

# ---------------------------------------------------------------------------------------------
# SCAN (PC, P64KB_SCAN=true)
# ---------------------------------------------------------------------------------------------

function p64kb_scan()
    p64r_template(false, P64R_L)
    p64r_template(true, P64R_L)
    foams = p64r_tmap(k -> p64r_foam(:ordered, k), 1:P64KB_TAU_FOAMS)
    τ = 1 / mean(row["ubar"] for (_, row) in foams)
    jobs = [(κ, j, β, k) for κ in P64KB_GRID for (j, β) in enumerate(P64KB_BETAS) for k in 1:P64KB_N]
    sort!(jobs; by = ((κ, j, β, k),) -> -P64KB_CAP[β])                 # long caps first
    rows = p64r_tmap(jobs) do (κ, j, β, k)
        r = p64kb_run(foams[k][1], κ * β, P64KB_CAP[β], p64kb_seed(j, k), τ)
        Dict{String, Any}("kappa_b" => κ, "beta" => β, "beta_model" => κ * β, "k" => k, "seed" => p64kb_seed(j, k),
            "tau" => τ, "cap" => P64KB_CAP[β], "mcs_run" => r.mcs_run, "t_first" => r.t_first, "t1_total" => r.t1_total)
    end
    sort!(rows; by = r -> (r["kappa_b"], r["beta"], r["k"]))
    return rows, τ, foams
end

if P64KB_SCAN
    @testset "04 κ_b SCAN (D-203)" begin
        @test P64R_SHEAR_READY
        if P64R_SHEAR_READY
            t0 = time()
            rows, τ, foams = p64kb_scan()
            @test length(rows) == length(P64KB_GRID) * length(P64KB_BETAS) * P64KB_N
            A = p64kb_analyse(rows)
            @info "04 κ_b scan decision" A.kappa_b A.path A.reason A.khat A.P τ
            if !isempty(P64KB_OUT)
                p64kb_write(P64KB_OUT, rows)
                commit = try
                    readchomp(`git -C $(@__DIR__) rev-parse HEAD`)
                catch
                    "unknown"
                end
                dirty = try
                    !isempty(readchomp(`git -C $(@__DIR__) status --porcelain`))
                catch
                    true
                end
                open(joinpath(P64KB_OUT, "provenance.toml"), "w") do io
                    println(io, "decision = \"D-203\"\nfrozen_test = \"lib/PottsModels/test/reproductions/04_foam_kb_scan.jl\"")
                    println(io, "commit = \"$commit\"\ndirty = $dirty\njulia = \"$(VERSION)\"\nthreads = $(Threads.nthreads())")
                    println(io, "machine = \"$(gethostname()); $(Sys.cpu_info()[1].model)\"\nwall_s = $(time() - t0)")
                    println(io, "tau = $τ\nfoam_seeds = $(repr([r["seed"] for (_, r) in foams]))\nfinished = \"$(now())\"")
                end
                open(joinpath(P64KB_OUT, "decision.toml"), "w") do io
                    println(io, "kappa_b = $(A.kappa_b === nothing ? "\"nothing\"" : A.kappa_b)")
                    println(io, "path = \"$(A.path)\"\nreason = \"$(A.reason)\"\nkhat = $(repr(A.khat))")
                end
                @info "04 κ_b scan written" P64KB_OUT wall = time() - t0
            end
        end
    end
end

# ---------------------------------------------------------------------------------------------
# record: reproductions/data/04/kb-scan-<date>/scan.tsv
# ---------------------------------------------------------------------------------------------

@testset "04 κ_b scan record: reproductions/data/04/kb-scan-*" begin
    dirs = isdir(P64R_DATA) ? filter(d -> occursin(r"^kb-scan-\d{4}-\d{2}-\d{2}$", d) &&
                                          isfile(joinpath(P64R_DATA, d, "scan.tsv")), readdir(P64R_DATA)) : String[]
    if isempty(dirs)
        @test_broken !isempty(dirs)                                            # pending the PC scan (D-203)
    else
        @test length(dirs) == 1
        D = joinpath(P64R_DATA, last(sort(dirs)))
        rows = p64kb_read(joinpath(D, "scan.tsv"))
        @test length(rows) == length(P64KB_GRID) * length(P64KB_BETAS) * P64KB_N
        @test all(r -> r["seed"] == p64kb_seed(findfirst(≈(r["beta"]), P64KB_BETAS), r["k"]), rows)
        @test all(r -> r["cap"] == P64KB_CAP[P64KB_BETAS[findfirst(≈(r["beta"]), P64KB_BETAS)]], rows)
        @test all(r -> r["beta_model"] ≈ r["kappa_b"] * r["beta"], rows)
        τ = rows[1]["tau"]
        @test all(r -> r["tau"] == τ, rows) && 2.5 < τ < 4.5
        @test all(r -> r["t_first"] == -1 ? r["mcs_run"] == p64r_ours(r["cap"], τ) : r["mcs_run"] <= p64r_ours(r["cap"], τ), rows)
        @test all(r -> r["t_first"] == -1 || r["t1_total"] > 0, rows)
        # harness control: at κ_b = κ_D190 the D-190 record's ordered medians are reproduced
        A = p64kb_analyse(rows)
        for (β, m190) in P64KB_D190_MED
            m = A.med[9, findfirst(≈(β), P64KB_BETAS)]
            @info "04 κ_b control at κ_D190" β m m190
            @test p64kb_within(m, m190)
        end
        @info "04 κ_b scan decision (D-203)" A.kappa_b A.path A.reason A.khat A.P
        @test A.kappa_b === nothing || P64KB_GRID[1] <= A.kappa_b <= P64KB_GRID[end]
        dec = joinpath(D, "decision.toml")
        if isfile(dec)
            d = Dict(split(l, " = "; limit = 2) for l in readlines(dec) if occursin(" = ", l))
            @test d["kappa_b"] == (A.kappa_b === nothing ? "\"nothing\"" : string(A.kappa_b))
            @test d["reason"] == "\"$(A.reason)\""
        end
    end
end
