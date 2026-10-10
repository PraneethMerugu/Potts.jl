# P6.15m m1 (ROADMAP; D-214, D-215 item 9): characterisation of the OpenVT entry
# "Potts.jl (checkerboard)", `CheckerboardCPM` on the PC's GPU (ROCm), against the CPU
# `SequentialCPM` reference (the "Potts.jl" entry). Frozen (AUTONOMY §7.3).
# Spec 15 §1.3 (the entry, its expected-difference classes and its own time scale), §3.1 O1,
# §3.2, §4.0.1 cases (b), (f); D-008 (sequential is the fidelity reference), D-029
# (CPU/GPU agreement is statistical), D-051 item 5, D-053 item 7 (claims), D-146 (offline
# records), D-048 (ordinary tests, negative controls), D-154 (deviation rows).
#
# The statistics CHARACTERISE; they do not gate the entry (D-214). What this file requires:
#  1. Runs exist: one dated record `reproductions/data/15/checkerboard-<YYYY-MM-DD>/` with
#     per-seed F3–F8 metrics and O1 summaries for both algorithms, cases (b) and (f) at least,
#     the checkerboard seeds disjoint from every sequential seed; provenance names the
#     algorithm, an AMDGPU/ROCm device, and no host-planner fallback.
#  2. A comparison row per (case, metric), recomputed here from the per-seed values.
#  3. Every row beyond the seed spread is a row of the entry's deviations table with a cause
#     from the fixed vocabulary; no "under investigation" row once the record is final (the
#     bug-chase rule: an unexplained difference is investigated before the full runs).
#  4. Negative controls: a shifted metric is flagged; a sequential-vs-sequential split is not.
#  5. Its own time scale (spec §1.3, D-214 "Spec additions"): T(λ = 2) of the checkerboard
#     chain calibration with its spread; the cycle is 5T(λ = 2) if T differs from the
#     sequential calibration under the same rule as the comparison table, else 775 MCS.
#
# ---------------------------------------------------------------------------------------------
# The rule "beyond the seed spread" (test author)
# ---------------------------------------------------------------------------------------------
# Per (case, metric): x = the sequential per-seed values (n_ref seeds), y = the checkerboard
# per-seed values (n_alt seeds), independent runs. Welch two-sample z:
#     diff = ȳ − x̄,  se = √(s²ₓ/n_ref + s²ᵧ/n_alt)  (s = sample sd, n − 1),
#     z = diff / se;  se == 0: z = 0 if diff == 0, else ±Inf (sign of diff).
#     beyond  ⇔  |z| > Z_SPREAD = 4.42.
# Why: it is the repo's convention for algorithm-against-algorithm checks, P6.4b1's ensemble
# check of BoundarySiteCPM against SequentialCPM (`acceptance/p6_4b1_boundary_site.jl`
# items 3 and 5: Welch z per check, a family false-alarm budget of 1e-3 split evenly over
# the checks, Z_FULL = 3.89 for 10 checks at 1e-4 each). Here a case has 33 metrics, cases
# (b) and (f) give 66 rows, plus the T(λ = 2) row and optional cases (a), (e): at most 100
# checks, so 1e-5 each, two-sided: Φ⁻¹(1 − 5e-6) = 4.42. Under equal laws the whole table
# raises a false deviation with probability ≤ 1e-3; with 100 seeds per arm a shift of
# about 0.63 seed sd is flagged (4.42·√(2/100)). A false row costs a bug chase, a missed
# small shift costs nothing the entry claims, so the budget errs on the quiet side. The same
# rule decides the time scale (item 5). Normal limit: n ≥ 100 per arm for (b), (f) and the
# calibration (CLT; P6.4b1 used the same with 100 runs).
#
# ---------------------------------------------------------------------------------------------
# Per-seed metrics (test author; the F3/F8 rules of `15_openvt_f3_f8.jl`, per run)
# ---------------------------------------------------------------------------------------------
# A run's series: saves (t = MCS / cycle, N, r, A, C, w, g), cut at the first save with
# N ≥ cells (1000 for b, f; 10⁴ for a, e). Metric ids (no spaces; τ printed with one decimal):
#   L@τ      log₂ N at the last save with t ≤ τ, τ ∈ 0.5:1:8.5            (F3.1)
#   r@τ, A@τ r and A there, τ ∈ 4.5:1:8.5                                  (F3.3, F3.4)
#   t_stop   time to `cells`: log₂ N crossing log₂ cells, linear in t between the two saves
#            around it, or extrapolated from the last two saves                (F3.2)
#   r_stop, A_stop   r/√N and A/N at the end save (first save with N ≥ 0.95 cells)  (F3.3/4)
#   sync@k   1 if N(k + 0.5) == 2^k else 0, k = 0:3                          (F3.5)
#   C_rel_end, w_end, g_end   C/(2√(πA)), w, g at the end save              (F8.1, F8.2)
#   O1.n_mean, O1.n_sd, O1.n6, O1.i0   of the run's last O1 frame (the stop save; D-215
#            columns x,y,i,n,g): mean and sample sd of n, share of cells with n == 6, share
#            with i == 0. Not recomputable from git (O1 files are bulk); checked for range.
# The sequential reference values are the P6.15f record's runs of the case (all its seeds,
# cycle 775); this file recomputes them from that record's timeseries.tsv. The checkerboard
# values use the record's own cycle (item 5).
#
# ---------------------------------------------------------------------------------------------
# The record (D-146 form; written by the m2/m3 runner on the PC's GPU)
# ---------------------------------------------------------------------------------------------
# reproductions/data/15/checkerboard-<YYYY-MM-DD>/ (exactly one such directory):
#   provenance.toml  item = "P6.15m"; commit, julia, machine, cpu, threads, started, finished,
#                    wall_s, runner, runner_sha256, test, test_sha256, manifest_sha256 (as the
#                    other data/15 records); and
#                    framework = P615M_LABEL, folder_token = P615M_FOLDER,
#                    algorithm (contains "CheckerboardCPM"), algorithm_reference (contains
#                    "SequentialCPM"), backend (matches AMDGPU|ROCm|ROCBackend), device (the
#                    GPU's name, non-empty), host_planner_fallback = false (Bool)
#   meta.toml        status = "provisional" | "final"; reference_record = the P6.15f record
#                    directory name (f3-f8-*); every_mcs (save cadence, ≤ 39);
#                    [cases.<c>] runs, seeds (text), cells, lattice, beta, gamma, sigma_X;
#                    [time] T_lambda2 (MCS, mean-curve crossing as in P6.15b), T_lambda2_sd
#                    (sd of the per-run crossings), T_runs, z (the item-5 z), cycle_mcs,
#                    cycle_reason (text; names 156 and says "significant" or "not significant")
#   runs.tsv         case k seed beta gamma sigma_X lattice retcode mcs N planner: one row per
#                    checkerboard run; planner = "device" for every run
#   timeseries.tsv   case seed mcs N r|R A C w g: every save of every checkerboard run (the
#                    length column may be headed `r` as in P6.15f or `R` as D-215 item 2)
#   metrics.tsv      algorithm case seed metric value: algorithm ∈ {sequential, checkerboard};
#                    every metric id above for every seed of both algorithms
#   comparison.tsv   case metric n_ref n_alt mean_ref mean_alt sd_ref sd_alt diff se z beyond:
#                    one row per (case, metric), beyond ∈ {true, false}
#   calibration.tsv  lambda seed T_run: per-run crossing times of the checkerboard chain
#                    calibration (P6.15b protocol), λ = 2 at least, 100 runs at λ = 2
#   entry/deviations.tsv   the checkerboard entry's deviations, header
#                    target case ours paper suspected_cause author_question (the P6.15f
#                    record's columns); target's first token is the metric id; `ours` holds the
#                    checkerboard mean, `paper` the sequential reference mean (first decimal
#                    numbers); suspected_cause's leading clause (before the first ':') is one
#                    or more vocabulary classes joined by " + "; author_question starts
#                    "not an author question", "not asked" or "resolved".
# The deviations table sits in `entry/` and the comparison is not called verdicts.tsv: the
# frozen page and package tests sweep data/15/*/{deviations,verdicts}.tsv into the
# sequential entry's tables, and this entry's rows do not belong there (m4 decides).
#
# ---------------------------------------------------------------------------------------------
# API required of the implementer (PottsModels; `public`, not exported, as openvt_snapshot)
# ---------------------------------------------------------------------------------------------
#     PottsModels.openvt_spread_compare(ref, alt; z = 4.42) -> NamedTuple
# `ref`, `alt`: per-seed values (AbstractVector{<:Real}), each of length ≥ 2 and all
# finite, else ArgumentError. Returns
#     (; n_ref, n_alt, mean_ref, mean_alt, sd_ref, sd_alt, diff, se, z, beyond)
# with the rule above (`z` keyword = the critical value; the returned `z` field is the
# statistic); n_* are Int, the rest Float64 except `beyond::Bool`.
#
#     PottsModels.openvt_spread_table(ref, alt; z = 4.42) -> Vector{NamedTuple}
# `ref`, `alt`: AbstractDict{String, <:AbstractVector{<:Real}} metric id => per-seed values,
# with the same key set (else ArgumentError). One row per metric, sorted by metric id:
# `merge((; metric), openvt_spread_compare(ref[metric], alt[metric]; z))`.
#
# Tiers.
# - always: the per-seed metric rules (test author) on synthetic series; the deviation and
#   time-scale checkers on synthetic tables.
# - API (always, once PottsModels defines it; marked broken until then): known answers,
#   the threshold, degenerate spreads, errors, and the negative controls on synthetic data.
# - record (always, cheap; no GPU needed): skipped until the record exists, then items 1–5.
using Test, TOML, Potts, PottsModels
using Statistics: mean, std
using StableRNGs: StableRNG

# ---------------------------------------------------------------------------------------------
# Parameters (the framework token is a parameter: D-214, D-215 item 9)
# ---------------------------------------------------------------------------------------------

const P615M_LABEL = "Potts.jl (checkerboard)"       # legend and banner text
const P615M_FOLDER = "Potts.jl_checkerboard"        # folder and file token (D-215 item 9)
const P615M_DATA = joinpath(pkgdir(PottsModels), "reproductions", "data", "15")
const P615M_PREFIX = "checkerboard-"
const P615M_Z = 4.42
const P615M_CYCLE_SEQ = 775
const P615M_T_SEQ = 156                              # sequential T(λ = 2), P6.15b record
const P615M_TN = 0.5:1.0:8.5
const P615M_TR = 4.5:1.0:8.5
const P615M_KSYNC = 0:3
const P615M_REQUIRED = ("b", "f")
# case protocols (P6.15f, spec 15 §4.0.1); the sequential seeds are the P6.15f record's
const P615M_CASES = Dict(
    "f" => (; beta = 0.0, gamma = 0.0, sigma_X = 0.0, L = 400, cells = 1000, runs = 100, seed = k -> 15_200 + k),
    "b" => (; beta = 0.0, gamma = 0.0, sigma_X = 0.4, L = 400, cells = 1000, runs = 100, seed = k -> 15_000 + k),
    "a" => (; beta = 0.0, gamma = 0.0, sigma_X = 0.4, L = 1400, cells = 10_000, runs = 10, seed = k -> 15_700 + k),
    "e" => (; beta = 0.8, gamma = 0.0, sigma_X = 0.4, L = 1400, cells = 10_000, runs = 10, seed = k -> 15_800 + k))
# the cause vocabulary: spec 15 §1.3's four expected-difference classes, plus the open state
const P615M_CAUSES = ("update order", "colour-lagged totals", "claim widening", "thinning", "under investigation")
const P615M_OPEN = "under investigation"

p615m_fmt(τ) = string(round(τ; digits = 1))
const P615M_METRICS = String[
    ["L@" * p615m_fmt(τ) for τ in P615M_TN]; ["r@" * p615m_fmt(τ) for τ in P615M_TR];
    ["A@" * p615m_fmt(τ) for τ in P615M_TR]; "t_stop"; "r_stop"; "A_stop";
    ["sync@$k" for k in P615M_KSYNC]; "C_rel_end"; "w_end"; "g_end"]
const P615M_O1 = ["O1.n_mean", "O1.n_sd", "O1.n6", "O1.i0"]
const P615M_ALL = sort([P615M_METRICS; P615M_O1])

# ---------------------------------------------------------------------------------------------
# Per-seed metric rules (test author)
# ---------------------------------------------------------------------------------------------

function p615m_series(mcs, N, r, A, C, w, g; cycle)
    p = sortperm(mcs)
    return (; t = Float64.(mcs[p]) ./ cycle, N = Int.(N[p]), r = Float64.(r[p]), A = Float64.(A[p]),
        C = Float64.(C[p]), w = Float64.(w[p]), g = Float64.(g[p]))
end
function p615m_cut(s, cells)
    j = findfirst(>=(cells), s.N)
    return j === nothing ? s : map(v -> v[1:j], s)
end
function p615m_at(s, τ)
    j = findlast(<=(τ), s.t)
    j === nothing && throw(ArgumentError("p615m_at: no save at or before t = $τ"))
    return j
end
function p615m_tcross(s, n)
    j = findfirst(>=(n), s.N)
    j == 1 && return s.t[1]
    j === nothing && (j = length(s.N))
    (j >= 2 && s.N[j] > s.N[j - 1]) || throw(ArgumentError("p615m_tcross: cannot place N = $n"))
    a, b = log2(s.N[j - 1]), log2(s.N[j])
    return s.t[j - 1] + (s.t[j] - s.t[j - 1]) * (log2(n) - a) / (b - a)
end
function p615m_end(s, n)
    j = findfirst(>=(0.95n), s.N)
    j === nothing && throw(ArgumentError("p615m_end: the series never reaches 0.95 × $n cells"))
    return j
end
# the F3–F8 metrics of one (cut) run: Dict id => value
function p615m_seed_metrics(s, cells)
    s = p615m_cut(s, cells)
    m = Dict{String, Float64}()
    for τ in P615M_TN
        m["L@" * p615m_fmt(τ)] = log2(s.N[p615m_at(s, τ)])
    end
    for τ in P615M_TR
        j = p615m_at(s, τ)
        m["r@" * p615m_fmt(τ)] = s.r[j]
        m["A@" * p615m_fmt(τ)] = s.A[j]
    end
    m["t_stop"] = p615m_tcross(s, cells)
    e = p615m_end(s, cells)
    m["r_stop"] = s.r[e] / sqrt(s.N[e])
    m["A_stop"] = s.A[e] / s.N[e]
    for k in P615M_KSYNC
        m["sync@$k"] = s.N[p615m_at(s, k + 0.5)] == 2^k ? 1.0 : 0.0
    end
    m["C_rel_end"] = s.C[e] / (2sqrt(π * s.A[e]))
    m["w_end"] = s.w[e]
    m["g_end"] = s.g[e]
    return m
end

# an ideal deterministic run (as P6.15f's): N = 2^⌊rate (t − lag)⌋ saved every 39 MCS
function p615m_ideal(; lag = 0.02, rate = 1.0, cells = 1000, cycle = P615M_CYCLE_SEQ, every = 39)
    mcs = Int[]; N = Int[]
    m = 0
    while true
        n = 2^max(0, floor(Int, rate * (m / cycle - lag)))
        push!(mcs, m); push!(N, n)
        n >= cells && break
        m += every
    end
    r = sqrt.(N .* 1.3)
    return p615m_series(mcs, N, r, π .* r .^ 2, 2π .* r .* 1.1, 0.05 .* r, ones(length(N)); cycle)
end

# ---------------------------------------------------------------------------------------------
# Checkers (test author): the deviations table and the time scale
# ---------------------------------------------------------------------------------------------

# the classes of a cause: its leading clause (before the first ':'), split on " + ", each
# with any parenthetical (a decision tag such as "(D-029)") removed; nothing if any part is
# outside the vocabulary or "under investigation" is combined with another class
function p615m_causes(s::AbstractString)
    lead = strip(first(split(s, ':'; limit = 2)))
    parts = [lowercase(strip(replace(p, r"\([^)]*\)" => ""))) for p in split(lead, " + ")]
    (isempty(parts) || any(isempty, parts)) && return String[]
    all(in(P615M_CAUSES), parts) || return String[]
    (P615M_OPEN in parts && length(parts) > 1) && return String[]
    return String.(parts)
end
p615m_first_decimal(s) = (m = match(r"\d+\.\d+(?:[eE][-+]?\d+)?", s); m === nothing ? nothing : parse(Float64, m.match))
p615m_close(x, y) = x !== nothing && isapprox(x, y; rtol = 1e-2, atol = 1e-3)

# problems with a deviations table against a comparison table (both: vectors of Dict or
# NamedTuple rows with string-keyed access via `p615m_get`); `final` forbids open causes.
# Returns a list of messages; empty means the table explains every flagged row.
p615m_get(r::AbstractDict, k) = r[String(k)]
p615m_get(r::NamedTuple, k) = getfield(r, Symbol(k))
function p615m_deviation_problems(cmp, devs; final::Bool)
    bad = String[]
    flagged = Set((string(p615m_get(r, :case)), string(p615m_get(r, :metric))) for r in cmp if p615m_get(r, :beyond) == true)
    seen = Set{Tuple{String, String}}()
    for d in devs
        id = String(first(split(p615m_get(d, :target))))
        key = (string(p615m_get(d, :case)), id)
        key in seen && push!(bad, "duplicate row $key")
        push!(seen, key)
        key in flagged || (push!(bad, "row $key is not beyond the spread"); continue)
        c = only(r for r in cmp if (string(p615m_get(r, :case)), string(p615m_get(r, :metric))) == key)
        p615m_close(p615m_first_decimal(p615m_get(d, :ours)), Float64(p615m_get(c, :mean_alt))) ||
            push!(bad, "row $key: ours does not give the checkerboard mean")
        p615m_close(p615m_first_decimal(p615m_get(d, :paper)), Float64(p615m_get(c, :mean_ref))) ||
            push!(bad, "row $key: paper does not give the sequential mean")
        cs = p615m_causes(p615m_get(d, :suspected_cause))
        isempty(cs) && push!(bad, "row $key: cause outside the vocabulary")
        (final && P615M_OPEN in cs) && push!(bad, "row $key: under investigation in a final record")
        occursin(r"^(not an author question|not asked|resolved)"i, p615m_get(d, :author_question)) ||
            push!(bad, "row $key: author_question")
    end
    for key in setdiff(flagged, seen)
        push!(bad, "flagged $key has no deviation row")
    end
    return bad
end

# the cycle the time-scale rule demands from the item-5 comparison
p615m_cycle(beyond::Bool, T_lambda2) = beyond ? 5 * T_lambda2 : P615M_CYCLE_SEQ

@testset "P6.15m rules: per-seed metrics, causes, deviations, time scale" begin
    s = p615m_ideal()
    m = p615m_seed_metrics(s, 1000)
    @test sort(collect(keys(m))) == sort(P615M_METRICS) && length(P615M_ALL) == 33
    @test [m["L@" * p615m_fmt(τ)] for τ in P615M_TN] == collect(0.0:8.0)
    @test all(m["sync@$k"] == 1 for k in P615M_KSYNC)
    @test 10.05 < m["t_stop"] < 10.07 && m["r_stop"] ≈ sqrt(1.3) && m["A_stop"] ≈ 1.3π
    @test m["C_rel_end"] ≈ 1.1 && m["g_end"] == 1 && m["w_end"] ≈ 0.05 * sqrt(1024 * 1.3)
    @test p615m_fmt(4.5) == "4.5" && "L@0.5" in P615M_METRICS && "A@8.5" in P615M_METRICS
    # a late run desynchronises and stops later; the cycle scales time
    late = p615m_seed_metrics(p615m_ideal(; lag = 0.6), 1000)
    @test late["sync@0"] == 1 && late["sync@1"] == 0 && late["t_stop"] > m["t_stop"] + 0.5
    @test p615m_seed_metrics(p615m_series(round.(Int, s.t .* 775), s.N, s.r, s.A, s.C, s.w, s.g; cycle = 900),
        1000)["t_stop"] ≈ m["t_stop"] * 775 / 900
    @test_throws ArgumentError p615m_end(p615m_ideal(; cells = 100), 1000)
    # causes
    @test p615m_causes("update order") == ["update order"]
    @test p615m_causes("Colour-lagged totals (D-029): area read one colour late") == ["colour-lagged totals"]
    @test p615m_causes("claim widening + thinning (D-051): measured …") == ["claim widening", "thinning"]
    @test p615m_causes("under investigation: chasing") == ["under investigation"]
    @test isempty(p615m_causes("update order + under investigation"))
    @test isempty(p615m_causes("GPU rounding"))
    @test isempty(p615m_causes(""))
    @test isempty(p615m_causes("noise"))
    # the deviation checker on a synthetic table
    cmp = [(; case = "b", metric = "t_stop", mean_ref = 10.36, mean_alt = 10.81, beyond = true),
        (; case = "b", metric = "L@4.5", mean_ref = 4.157, mean_alt = 4.160, beyond = false),
        (; case = "f", metric = "O1.n6", mean_ref = 0.41, mean_alt = 0.47, beyond = true)]
    row(case, id, ours, paper, cause; q = "not asked") =
        Dict("target" => "$id beyond seed spread", "case" => case, "ours" => ours, "paper" => paper,
            "suspected_cause" => cause, "author_question" => q)
    good = [row("b", "t_stop", "10.81 cycles (100 seeds, sd 0.31)", "10.36 cycles (sd 0.29)", "update order: …"),
        row("f", "O1.n6", "0.470 (sd 0.02)", "0.410 (sd 0.02)", "claim widening + thinning: …")]
    @test isempty(p615m_deviation_problems(cmp, good; final = true))
    @test length(p615m_deviation_problems(cmp, good[1:1]; final = false)) == 1                  # a flag unexplained
    @test !isempty(p615m_deviation_problems(cmp, [good; row("b", "L@4.5", "4.160", "4.157", "update order")]; final = false))
    @test !isempty(p615m_deviation_problems(cmp, [good[1]; row("f", "O1.n6", "0.470", "0.410", "GPU noise")]; final = false))
    @test !isempty(p615m_deviation_problems(cmp, [good[1]; row("f", "O1.n6", "0.520", "0.410", "thinning")]; final = false))
    @test !isempty(p615m_deviation_problems(cmp, [good[1]; row("f", "O1.n6", "0.470", "0.410", "thinning"; q = "ask")]; final = false))
    @test !isempty(p615m_deviation_problems(cmp, [good; good[1]]; final = false))                 # duplicate
    open = [good[1]; row("f", "O1.n6", "0.470", "0.410", "under investigation: …")]
    @test isempty(p615m_deviation_problems(cmp, open; final = false))                             # provisional: allowed
    @test !isempty(p615m_deviation_problems(cmp, open; final = true))                             # the bug-chase rule
    # the time-scale rule
    @test p615m_cycle(false, 160) == 775 && p615m_cycle(true, 170) == 850
end

# ---------------------------------------------------------------------------------------------
# API (implementer): openvt_spread_compare / openvt_spread_table
# ---------------------------------------------------------------------------------------------

p615m_var(x) = sum(abs2, x .- mean(x)) / (length(x) - 1)
const P615M_API = isdefined(PottsModels, :openvt_spread_compare) && isdefined(PottsModels, :openvt_spread_table)

# a table of 33 metrics with `n` seeds per arm, every metric from one law, from `rng`
p615m_draws(rng, n; shift = Dict{String, Float64}()) =
    Dict(k => randn(rng, n) .* (1 + i / 10) .+ 3i .+ get(shift, k, 0.0) for (i, k) in enumerate(P615M_ALL))

@testset "P6.15m API: the spread rule on synthetic data, and the negative controls" begin
    if !P615M_API
        @info "P6.15m: PottsModels.openvt_spread_compare / openvt_spread_table not defined yet (m2)"
        @test_broken P615M_API
    else
        C, T = PottsModels.openvt_spread_compare, PottsModels.openvt_spread_table
        # known answers
        r = C([1.0, 2.0, 3.0, 4.0], [2.0, 3.0, 4.0, 5.0])
        @test keys(r) == (:n_ref, :n_alt, :mean_ref, :mean_alt, :sd_ref, :sd_alt, :diff, :se, :z, :beyond)
        @test r.n_ref == 4 && r.n_alt == 4 && r.n_ref isa Int
        @test r.mean_ref == 2.5 && r.mean_alt == 3.5 && r.diff == 1.0
        @test r.sd_ref ≈ std([1.0, 2.0, 3.0, 4.0]) && r.sd_alt ≈ r.sd_ref
        @test r.se ≈ sqrt(2 * p615m_var([1.0, 2.0, 3.0, 4.0]) / 4) && r.z ≈ 1 / r.se && r.beyond === false
        @test C([2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0]).z ≈ -r.z                  # sign: alt − ref
        # unequal sizes: Welch, not pooled
        r2 = C([0.0, 2.0], [1.0, 1.0, 4.0, 4.0, 5.0])
        @test r2.se ≈ sqrt(2.0 / 2 + p615m_var([1.0, 1.0, 4.0, 4.0, 5.0]) / 5)
        # the threshold: default 4.42, and the keyword
        x = collect(1.0:10.0)
        se = sqrt(2 * p615m_var(x) / 10)
        @test !C(x, x .+ 4.41se).beyond && C(x, x .+ 4.43se).beyond
        @test !C(x, x .- 4.41se).beyond && C(x, x .- 4.43se).beyond
        @test C(x, x .+ 3.0se; z = 2.0).beyond && !C(x, x .+ 3.0se; z = 4.0).beyond
        # degenerate spreads
        @test C(fill(1.0, 5), fill(1.0, 5)).z == 0 && !C(fill(1.0, 5), fill(1.0, 5)).beyond
        d = C(fill(1.0, 5), fill(1.1, 5))
        @test d.se == 0 && d.z == Inf && d.beyond
        @test C(fill(1.0, 5), fill(0.9, 5)).z == -Inf
        # errors
        @test_throws ArgumentError C([1.0], [1.0, 2.0])
        @test_throws ArgumentError C([1.0, NaN], [1.0, 2.0])
        @test_throws ArgumentError C([1.0, 2.0], [Inf, 2.0])
        @test_throws ArgumentError T(Dict("a" => [1.0, 2.0]), Dict("b" => [1.0, 2.0]))
        # the table: one row per metric, sorted, each the compare of its values
        a = Dict("t_stop" => [1.0, 2.0, 3.0], "L@0.5" => [0.0, 0.0, 1.0])
        b = Dict("t_stop" => [9.0, 9.1, 9.2], "L@0.5" => [0.0, 1.0, 0.0])
        tab = T(a, b)
        @test [t.metric for t in tab] == ["L@0.5", "t_stop"]
        @test tab[2] == merge((; metric = "t_stop"), C(a["t_stop"], b["t_stop"]))
        @test [t.beyond for t in tab] == [false, true]
        @test [t.beyond for t in T(a, b; z = 100.0)] == [false, false]
        # negative control 1: a deliberately shifted metric is flagged, and only it
        rng = StableRNG(214_001)
        ref = p615m_draws(rng, 100)
        shifted = p615m_draws(rng, 100; shift = Dict("t_stop" => 1.0 * (1 + findfirst(==("t_stop"), P615M_ALL) / 10)))
        tab = T(ref, shifted)
        @test length(tab) == 33
        @test [t.metric for t in tab if t.beyond] == ["t_stop"]
        @test only(t for t in tab if t.metric == "t_stop").z > 5
        # negative control 2: a split of one law (sequential against sequential) flags nothing,
        # over 20 independent splits (660 checks; expected false flags 0.0066)
        rng = StableRNG(214_002)
        nflag = sum(count(t -> t.beyond, T(p615m_draws(rng, 100), p615m_draws(rng, 100))) for _ in 1:20)
        @test nflag == 0
        # and on the per-seed metrics of synthetic runs: the same law split in two flags
        # nothing; time miscounted by 1.1× flags t_stop
        rng = StableRNG(214_003)
        runs = [p615m_seed_metrics(p615m_ideal(; lag = 0.02 + 0.3rand(rng)), 1000) for _ in 1:40]
        tbl(rs) = Dict(k => [m[k] for m in rs] for k in P615M_METRICS)
        @test !any(t -> t.beyond, T(tbl(runs[1:2:end]), tbl(runs[2:2:end])))
        rng = StableRNG(214_004)
        reread(s) = p615m_series(round.(Int, s.t .* 775), s.N, s.r, s.A, s.C, s.w, s.g; cycle = 775 / 1.1)
        mis = [p615m_seed_metrics(reread(p615m_ideal(; lag = 0.02 + 0.3rand(rng))), 1000) for _ in 1:20]
        @test only(t for t in T(tbl(runs[1:2:end]), tbl(mis)) if t.metric == "t_stop").beyond
    end
end
# ---------------------------------------------------------------------------------------------
# The record (D-146; no GPU needed to check it)
# ---------------------------------------------------------------------------------------------

function p615m_tsv(path)
    l = split.(filter(!isempty, readlines(path)), '\t')
    return [Dict(String(k) => String(v) for (k, v) in zip(l[1], r)) for r in l[2:end]]
end
p615m_header(path) = String.(split(first(readlines(path)), '\t'))
p615m_f64(x) = lowercase(x) == "nan" ? NaN : parse(Float64, x)
# per-run series of one case from a timeseries table (r or R column)
function p615m_record_series(ts, case; cycle)
    rows = [r for r in ts if r["case"] == case]
    rc = isempty(rows) ? "r" : (haskey(first(rows), "R") ? "R" : "r")
    out = Dict{Int, Any}()
    for seed in unique(parse(Int, r["seed"]) for r in rows)
        rr = [r for r in rows if parse(Int, r["seed"]) == seed]
        F(k) = [p615m_f64(r[k]) for r in rr]
        out[seed] = p615m_series(F("mcs"), [parse(Int, r["N"]) for r in rr], F(rc), F("A"), F("C"), F("w"), F("g"); cycle)
    end
    return out
end
# metrics.tsv as Dict (algorithm, case) => Dict(metric => Dict(seed => value))
function p615m_metric_table(rows)
    out = Dict{Tuple{String, String}, Dict{String, Dict{Int, Float64}}}()
    for r in rows
        d = get!(get!(out, (r["algorithm"], r["case"]), Dict{String, Dict{Int, Float64}}()), r["metric"], Dict{Int, Float64}())
        d[parse(Int, r["seed"])] = p615m_f64(r["value"])
    end
    return out
end
p615m_vals(d) = [d[k] for k in sort(collect(keys(d)))]
# every sequential seed in any committed data/15 record (runs.tsv and crossings.tsv)
function p615m_sequential_seeds(dirs)
    s = Set{Int}()
    for d in dirs, f in ("runs.tsv", "crossings.tsv")
        p = joinpath(P615M_DATA, d, f)
        isfile(p) || continue
        for r in p615m_tsv(p)
            haskey(r, "seed") && push!(s, parse(Int, r["seed"]))
        end
    end
    return union!(s, 95_101:95_103)                      # the P6.15f SMOKE seeds
end

@testset "P6.15m record: $(P615M_LABEL) against SequentialCPM" begin
    all_dirs = isdir(P615M_DATA) ? sort(filter(d -> isdir(joinpath(P615M_DATA, d)), readdir(P615M_DATA))) : String[]
    dirs = filter(d -> occursin(Regex("^" * P615M_PREFIX * raw"\d{4}-\d{2}-\d{2}$"), d), all_dirs)
    if isempty(dirs)
        @info "P6.15m: no characterisation record yet (reproductions/data/15/$(P615M_PREFIX)<date>/; m3)"
        @test_skip "P6.15m record (m3: FULL runs on the PC's GPU)"
    else
        @test length(dirs) == 1
        @test P615M_API                                     # the record is checked with the API
        D = joinpath(P615M_DATA, last(dirs))
        for f in ("provenance.toml", "meta.toml", "runs.tsv", "timeseries.tsv", "metrics.tsv", "comparison.tsv",
            "calibration.tsv", joinpath("entry", "deviations.tsv"))
            @test isfile(joinpath(D, f))
        end
        # not swept into the sequential entry's tables (frozen page and package tests)
        @test !isfile(joinpath(D, "deviations.tsv")) && !isfile(joinpath(D, "verdicts.tsv"))
        prov = TOML.parsefile(joinpath(D, "provenance.toml"))
        meta = TOML.parsefile(joinpath(D, "meta.toml"))

        # (1) provenance: algorithm, backend, no host-planner fallback, the tokens
        @test get(prov, "item", "") == "P6.15m"
        @test get(prov, "framework", "") == P615M_LABEL
        @test get(prov, "folder_token", "") == P615M_FOLDER && occursin(r"^[A-Za-z0-9._-]+$", P615M_FOLDER)
        @test occursin("CheckerboardCPM", get(prov, "algorithm", ""))
        @test occursin("SequentialCPM", get(prov, "algorithm_reference", ""))
        @test occursin(r"AMDGPU|ROCm|ROCBackend"i, get(prov, "backend", ""))
        @test !isempty(strip(string(get(prov, "device", ""))))
        @test get(prov, "host_planner_fallback", true) === false
        for k in ("commit", "julia", "machine", "threads", "wall_s", "runner", "runner_sha256", "test", "test_sha256",
            "manifest_sha256")
            @test haskey(prov, k)
        end
        @test get(meta, "status", "") in ("provisional", "final")
        final = get(meta, "status", "") == "final"
        ref_dir = get(meta, "reference_record", "")
        @test startswith(ref_dir, "f3-f8-") && isdir(joinpath(P615M_DATA, ref_dir))
        every = get(meta, "every_mcs", 0)
        @test 1 <= every <= 39

        # (5) the time scale: T(λ = 2) with its spread, the cycle and why
        tm = get(meta, "time", Dict{String, Any}())
        cal = p615m_tsv(joinpath(D, "calibration.tsv"))
        Tcb = [p615m_f64(r["T_run"]) for r in cal if r["lambda"] == "2"]
        seqcal = filter(d -> startswith(d, "calibration-"), all_dirs)
        Tseq = isempty(seqcal) ? Float64[] :
               [p615m_f64(r["T_run"]) for r in p615m_tsv(joinpath(P615M_DATA, last(seqcal), "crossings.tsv")) if r["lambda"] == "2"]
        @test length(Tcb) == 100 && length(Tseq) == 100
        @test haskey(tm, "T_lambda2") && haskey(tm, "T_lambda2_sd") && get(tm, "T_runs", 0) == length(Tcb)
        @test isapprox(get(tm, "T_lambda2_sd", NaN), std(Tcb); rtol = 1e-6)
        tz = PottsModels.openvt_spread_compare(Tseq, Tcb)
        @test isapprox(get(tm, "z", NaN), tz.z; rtol = 1e-6)
        @test get(tm, "cycle_mcs", 0) == p615m_cycle(tz.beyond, get(tm, "T_lambda2", 0))
        why = string(get(tm, "cycle_reason", ""))
        @test occursin(string(P615M_T_SEQ), why) && occursin(tz.beyond ? r"(?<!not )significant"i : r"not significant"i, why)
        cycle = get(tm, "cycle_mcs", P615M_CYCLE_SEQ)
        # the calibration's seeds are its own
        seen = p615m_sequential_seeds(filter(!=(last(dirs)), all_dirs))
        @test isempty(intersect(seen, [parse(Int, r["seed"]) for r in cal]))

        # (1) runs: the cases, protocol, seeds, device planner
        cases = sort(collect(keys(get(meta, "cases", Dict()))))
        @test all(c -> c in cases, P615M_REQUIRED) && all(c -> haskey(P615M_CASES, c), cases)
        runs = p615m_tsv(joinpath(D, "runs.tsv"))
        ts = p615m_tsv(joinpath(D, "timeseries.tsv"))
        @test "r" in p615m_header(joinpath(D, "timeseries.tsv")) || "R" in p615m_header(joinpath(D, "timeseries.tsv"))
        cbseeds = [parse(Int, r["seed"]) for r in runs]
        @test allunique(cbseeds) && isempty(intersect(seen, cbseeds))
        @test all(r -> r["planner"] == "device", runs)
        ref_runs = p615m_tsv(joinpath(P615M_DATA, ref_dir, "runs.tsv"))
        ref_ts = p615m_tsv(joinpath(P615M_DATA, ref_dir, "timeseries.tsv"))
        M = p615m_metric_table(p615m_tsv(joinpath(D, "metrics.tsv")))
        cmp = p615m_tsv(joinpath(D, "comparison.tsv"))
        @test p615m_header(joinpath(D, "comparison.tsv")) ==
              ["case", "metric", "n_ref", "n_alt", "mean_ref", "mean_alt", "sd_ref", "sd_alt", "diff", "se", "z", "beyond"]
        for c in cases
            P = P615M_CASES[c]
            rr = [r for r in runs if r["case"] == c]
            @test length(rr) == P.runs
            @test all(r -> parse(Float64, r["beta"]) == P.beta && parse(Float64, r["gamma"]) == P.gamma &&
                           parse(Float64, r["sigma_X"]) == P.sigma_X && parse(Int, r["lattice"]) == P.L &&
                           r["retcode"] == "Terminated" && parse(Int, r["N"]) >= P.cells, rr)
            # the checkerboard series: saves at 0, every `every` MCS and the stop
            ser = p615m_record_series(ts, c; cycle)
            @test sort(collect(keys(ser))) == sort([parse(Int, r["seed"]) for r in rr])
            for r in rr
                s = ser[parse(Int, r["seed"])]
                mm = round.(Int, s.t .* cycle)
                @test mm[1] == 0 && mm[end] == parse(Int, r["mcs"]) && s.N[end] == parse(Int, r["N"])
                @test all(diff(mm[1:(end - 1)]) .== every) && all(diff(mm) .> 0)
            end
            # per-seed metrics: both algorithms, every metric, every seed; the F3–F8 ones
            # recomputed (checkerboard from this record, sequential from the P6.15f record)
            seqseeds = [P.seed(k) for k in 1:P.runs]
            @test sort([parse(Int, r["seed"]) for r in ref_runs if r["case"] == c]) == seqseeds
            refser = p615m_record_series(ref_ts, c; cycle = P615M_CYCLE_SEQ)
            for (alg, sers, seeds) in (("sequential", refser, seqseeds), ("checkerboard", ser, sort(collect(keys(ser)))))
                T = get(M, (alg, c), Dict{String, Dict{Int, Float64}}())
                @test sort(collect(keys(T))) == P615M_ALL
                all(k -> haskey(T, k) && sort(collect(keys(T[k]))) == seeds, P615M_ALL) || (@test false; continue)
                bad = 0
                for sd in seeds
                    m = p615m_seed_metrics(sers[sd], P.cells)
                    for k in P615M_METRICS
                        isapprox(T[k][sd], m[k]; rtol = 1e-9, atol = 1e-12) || (bad += 1)
                    end
                    # O1 summaries: in range, and consistent with the stop state
                    o = [T[k][sd] for k in P615M_O1]
                    (4 < o[1] < 8 && 0 < o[2] < 4 && 0 <= o[3] <= 1 && 0 <= o[4] <= 1) || (bad += 1)
                    (P.beta == 0 && P.gamma == 0 && o[4] != 1) && (bad += 1)
                end
                bad == 0 || @info "P6.15m: $bad per-seed values of ($alg, $c) disagree with the recomputation"
                @test bad == 0
            end
            # (2) the comparison rows, recomputed with the API
            Tr, Ta = M[("sequential", c)], M[("checkerboard", c)]
            want = PottsModels.openvt_spread_table(Dict(k => p615m_vals(Tr[k]) for k in P615M_ALL),
                Dict(k => p615m_vals(Ta[k]) for k in P615M_ALL))
            got = [r for r in cmp if r["case"] == c]
            @test sort([r["metric"] for r in got]) == P615M_ALL
            for w in want
                g = only(r for r in got if r["metric"] == w.metric)
                @test parse(Int, g["n_ref"]) == w.n_ref && parse(Int, g["n_alt"]) == w.n_alt
                for k in ("mean_ref", "mean_alt", "sd_ref", "sd_alt", "diff", "se", "z")
                    @test isapprox(p615m_f64(g[k]), getfield(w, Symbol(k)); rtol = 1e-6, atol = 1e-12) ||
                          (isinf(getfield(w, Symbol(k))) && p615m_f64(g[k]) == getfield(w, Symbol(k)))
                end
                @test g["beyond"] == string(w.beyond)
            end
            # (4) negative controls on the record: a split of the sequential seeds (odd k
            # against even k) flags nothing; the sequential runs read with time miscounted by
            # 1.1× (cycle 775/1.1) flag t_stop
            odd = Dict(k => [Tr[k][P.seed(i)] for i in 1:2:P.runs] for k in P615M_ALL)
            even = Dict(k => [Tr[k][P.seed(i)] for i in 2:2:P.runs] for k in P615M_ALL)
            halves = PottsModels.openvt_spread_table(odd, even)
            flagged = [t.metric for t in halves if t.beyond]
            isempty(flagged) || @info "P6.15m: the sequential split flags" c flagged
            @test isempty(flagged)
            mis = p615m_record_series(ref_ts, c; cycle = P615M_CYCLE_SEQ / 1.1)
            tmis = [p615m_seed_metrics(mis[P.seed(i)], P.cells)["t_stop"] for i in 2:2:P.runs]
            @test PottsModels.openvt_spread_compare(odd["t_stop"], tmis).beyond
        end
        @test sort(unique(r["case"] for r in cmp)) == cases

        # (3) deviations: every row beyond the spread explained, from the vocabulary
        devf = joinpath(D, "entry", "deviations.tsv")
        if isfile(devf)
            @test p615m_header(devf) == ["target", "case", "ours", "paper", "suspected_cause", "author_question"]
            cmpb = [merge(r, Dict("beyond" => r["beyond"] == "true", "mean_ref" => p615m_f64(r["mean_ref"]),
                "mean_alt" => p615m_f64(r["mean_alt"]))) for r in cmp]
            probs = p615m_deviation_problems(cmpb, p615m_tsv(devf); final)
            isempty(probs) || @info "P6.15m deviations" probs
            @test isempty(probs)
            nflag = count(r -> r["beyond"] == "true", cmp)
            nopen = count(d -> P615M_OPEN in p615m_causes(d["suspected_cause"]), p615m_tsv(devf))
            @info "P6.15m: $nflag of $(length(cmp)) comparison rows beyond the spread; $nopen under investigation" final
        end
    end
end
