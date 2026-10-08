# P6.3f (ROADMAP Phase 6, step 3): the reproduction 01 page renders the FULL record.
# Frozen (AUTONOMY §7.3; under D-146, D-153–D-156, D-161, D-172, D-183). The page is the Literate
# script `lib/PottsModels/reproductions/01_merks.jl`. This file reads the page source, the
# committed record and the frozen 01 test; it runs no simulation. The frozen 01 test
# (`test/reproductions/01_merks.jl`, D-153) is not edited: its FULL tier's rules are
# re-applied here, verbatim in substance, to the committed per-replicate record.
#
# The record (D-146) is `lib/PottsModels/reproductions/data/01/full-2026-10-08/`:
#
# (a) Provenance. `provenance.toml` has item "P6.3f"; a 40-hex `commit` that is an ancestor
#     of HEAD (checked when git is available and the clone is not shallow); `dirty = false`;
#     `frozen_test_sha256` equal to frozen.toml's entry for `reproductions/01_merks.jl` and to
#     that file's sha256 now; `hostname`, `cpu`, `julia`, an integer `threads`, `jobs = 590`,
#     and a `runner` inside the record directory that exists. Files: only .tsv, .toml, .md,
#     .jl, .png, .svg (and .jls under `snap/`), each ≤ 10 MB; no video file.
# (b) Replicates. `replicates.tsv` (tab-separated, header first) has one row per job of the
#     frozen FULL tier, 590 in all: the pre-registered seeds of the frozen test, each once,
#     with the frozen test's parameters for that seed (columns `row`, `seed`, `key` and the
#     parameter columns `arm`, `L`, `J_cc`, `ratio`, `CI`, `χcM`, `s`, `T`, `mode`), and
#     the observables the rules read: `C_t`, `share_t`, `lacunae_t`, `network_t` at the
#     frozen save times t, `anisotropy` (V-E10) and `displacement_sites` (V-C12). Floats are
#     written at full precision (shortest round-trip form).
# (c) Snapshot oracle. `snap/<key>.jls` holds the σ snapshots of at least one 2006 job
#     (V-E1, V-E5 or V-E6) and at least one 2008 job (V-C*), ≤ 4 MB in all, each the
#     runner's `serialize`d Dict{Int, Matrix{UInt16}} of σ at the job's save times. The
#     frozen test's own observable functions (its definitions, evaluated here without its
#     testsets) recompute every observable of those jobs from the snapshots, and they equal
#     the replicate rows exactly (our own code: bitwise, D-158). Opt-in: `P63F_SNAPSHOTS` = a
#     directory of every job's snapshots (kept on the PC) checks them all the same way.
# (d) Verdicts. The frozen FULL rules, applied here to `replicates.tsv`, give 37 checks
#     (P63F_CHECKS below, in the frozen test's order; the frozen V-C3 plateau `@test` is
#     reported as its low and high halves). `verdicts.tsv` has exactly these rows, in this
#     order, with columns `row`, `check`, `ours`, `rule`, `result` equal to the recomputed
#     ones. `points.tsv` has the mean compactness of every 2008 sweep point at N and at
#     N + 100 MCS (D-153 M6, reported), within 5e-5 of the recomputed means.
# (e) Videos (D-146, D-156, D-161, D-172). `videos.toml` lists ≥ 1 `[[video]]` with `file`
#     (`01_merks_full-2026-10-08_*cells*.mp4`), `tag` (a new dated pre-release
#     `reproductions-2026-10-DD…`, DD ≥ 08, which the coordinator creates and uploads to),
#     `job` (a key of `replicates.tsv`), `encoding = "CellIdentityEncoding"`,
#     `boundaries = false`, a 64-hex `sha256`, `bytes` ≤ 50 MB and
#     `final_state_matches_record = true`. The page links each as
#     `https://github.com/PraneethMerugu/Potts.jl/releases/download/<tag>/<file>`, and every
#     `01_merks_full` video URL on the page is one of them.
#
# The page:
#
# (f) FULL record chunk. Exactly one code chunk delimited by the lines
#     `## FULL record (P6.3f): begin` and `## FULL record (P6.3f): end`, before §3. It names
#     the record directory and runs no simulation (no `solve(`, `PottsProblem`, `run06`,
#     `run08`, `walk(`). Evaluated alone in a fresh module (with PottsModels, TOML, Markdown
#     and Statistics loaded) it defines
#     - `full_verdicts_md::String`, a Markdown table with columns Target, Ours, Class and
#       Result: for every check of (d) a row whose Target starts with "<row> <check>", whose
#       Ours is the check's `ours`, whose Class is "FULL record" and whose Result is the
#       recomputed PASS or FAIL;
#     - `full_deviation_rows::Vector{String}`, Markdown rows of the §3 deviations table (D-154):
#       for every FAIL check, a row whose first cell names the row id and "FAIL" (for a
#       failing V-C3 low plateau: "V-C3 low plateau" and "FAIL") and whose Ours cell
#       contains the check's `ours`, with a non-empty cause.
#     Outside the chunk, `full_verdicts_md` is shown in §5 and `full_deviation_rows` is
#     spliced into the §3 deviations table. The page names `points.tsv` (the N + 100 reading).
# (g) Deviations table (D-154, D-155, D-161). The §3 table's header has Ours, Paper, cause
#     and Author question. Its static rows keep D-161's items: 2006 target length L
#     (provisional, 50 and 60 px), V-E5/V-E6 classification time (provisional, 48 h), 2006
#     connectivity E₀, 2006 seeding, 2008 time origin, 01b Fig. 2 set-up, Field scheme,
#     ΔH arithmetic, χ(c,c), Parameter sets, 2008 seeding, Border, Copy proposal,
#     Compactness; and PARKED rows covering V-E2, V-E3, V-E4, V-E7, V-E8, V-E9, V-C6, V-C8,
#     V-C10 and V-C11. No row is about attempts per MCS; no row says "pending" or "at risk".
#     Each static row's last cell starts with "not an author question", "not asked" or the
#     page's `$(aq(` helper, whose text starts "not asked" and names "open question list".
#     The rows of `full_deviation_rows` end with "not an author question" or "not asked".
# (h) Banner and text (D-161 kept). Before §1 the page names the record directory, the first
#     8 characters of its commit and its machine (the cpu up to " w/", or the hostname;
#     case-insensitive). Nowhere does it say the full run is pending or not yet made. Units
#     still give 39 204 attempts and TST's (sizex − 2)(sizey − 2); clocks still say
#     "MCS after relaxation" and "code MCS". No private question sheet ("sheet", "PI_SHEET",
#     "author-questions") and no local reference path ("docs/references"; D-183: sources by
#     DOI or public URL only). The changelog has a row dated 2026-10-08 or later naming the
#     record directory.
# (i) Rendering (D-156, D-172). No `boundaries = true`, no `pottsboundaries`, no
#     `ChannelEncoding`; every `record_potts(` call passes `encoding = CellIdentityEncoding()`;
#     every `pottsplot` call names CellIdentityEncoding or CellTypeEncoding.
# (j) Docs. The page parses; `docs/make.jl` renders every reproductions script. Opt-in
#     (`POTTS_DOCS_BUILD=true`): the docs build succeeds and the built page has every
#     check's ours and result and every video URL.
#
# Negative controls (D-048): the recomputed rules flip on perturbed copies of the record
# (V-C3 low plateau moved into and out of its band, a V-C1 network flag flipped); the job
# check rejects a missing and a duplicated seed; the snapshot oracle rejects an edited value;
# the frozen observables are checked on a hand-built square (C = 100/81).
using Test, TOML, SHA, Serialization, Markdown
using Statistics: mean

const P63F_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const P63F_PAGE = joinpath(P63F_ROOT, "lib", "PottsModels", "reproductions", "01_merks.jl")
const P63F_FROZEN = joinpath(P63F_ROOT, "lib", "PottsModels", "test", "reproductions", "01_merks.jl")
const P63F_FROZEN_TOML = joinpath(P63F_ROOT, "lib", "PottsModels", "test", "frozen.toml")
const P63F_RECNAME = "full-2026-10-08"
const P63F_REC = joinpath(P63F_ROOT, "lib", "PottsModels", "reproductions", "data", "01", P63F_RECNAME)
const P63F_MAKE = joinpath(P63F_ROOT, "docs", "make.jl")
const P63F_RELEASES = "https://github.com/PraneethMerugu/Potts.jl/releases/download/"
const P63F_BEGIN = "## FULL record (P6.3f): begin"
const P63F_END = "## FULL record (P6.3f): end"
const P63F_VIDEO_EXT = (".mp4", ".webm", ".mov", ".mkv", ".gif")
const P63F_RECORD_EXT = (".tsv", ".toml", ".md", ".jl", ".png", ".svg")

p63f_read(p) = isfile(p) ? read(p, String) : ""
p63f_sha(f) = bytes2hex(open(sha256, f))
function p63f_files(dir)
    out = String[]
    isdir(dir) || return out
    for (root, _, fs) in walkdir(dir), f in fs
        push!(out, joinpath(root, f))
    end
    return out
end
function p63f_tsv(path)
    isfile(path) || return Dict{String, String}[]
    lines = filter(!isempty, readlines(path))
    isempty(lines) && return Dict{String, String}[]
    head = split(lines[1], '\t')
    return [Dict(String(h) => String(v) for (h, v) in zip(head, split(l, '\t'; keepempty = true))) for l in lines[2:end]]
end
function p63f_tsv_header(path)
    isfile(path) || return String[]
    l = readline(path)
    return String.(split(l, '\t'))
end

# ---------------------------------------------------------------------------------------------
# the frozen 01 test's definitions (no testsets, no FULL block), in their own module
# ---------------------------------------------------------------------------------------------
function p63f_frozen_module()
    m = Module(:P63FFrozen01)
    Core.eval(m, :(using Potts, PottsModels, Test))
    ex = Meta.parseall(p63f_read(P63F_FROZEN))
    for e in ex.args
        e isa Expr || continue
        e.head === :if && continue
        e.head === :macrocall && e.args[1] === Symbol("@testset") && continue
        Core.eval(m, e)
    end
    return m
end

# ---------------------------------------------------------------------------------------------
# the pre-registered jobs of the frozen FULL tier: (row, seed) => parameters
# ---------------------------------------------------------------------------------------------
function p63f_jobs()
    J = Tuple{String, Int, Dict{String, Any}}[]
    for s in 1001:1010
        push!(J, ("V-E1", s, Dict{String, Any}("arm" => "standard")))
    end
    for s in 1101:1110
        push!(J, ("V-E1", s, Dict{String, Any}("arm" => "λ_L = 0")))
    end
    for (k, L) in enumerate((10.0, 20.0, 30.0, 40.0, 50.0)), i in 1:10
        push!(J, ("V-E5", 1200 + 10(k - 1) + i, Dict{String, Any}("L" => L)))
    end
    for (k, Jcc) in enumerate((20.0, 5.0, 1.0)), i in 1:10
        push!(J, ("V-E6", 1300 + 10(k - 1) + i, Dict{String, Any}("J_cc" => Jcc)))
    end
    for s in 1401:1410
        push!(J, ("V-E10", s, Dict{String, Any}("arm" => "elongated")))
    end
    for s in 1411:1420
        push!(J, ("V-E10", s, Dict{String, Any}("arm" => "round")))
    end
    for (j, r) in enumerate(0.0:0.1:1.0), i in 1:10
        push!(J, ("V-C3", 3000 + 100j + i, Dict{String, Any}("ratio" => r)))
    end
    pts4 = [(0.0, true), (20.0, true), (40.0, true), (60.0, true), (80.0, true),
        (0.0, false), (5.0, false), (10.0, false), (15.0, false), (20.0, false), (40.0, false)]
    for (k, (Jcc, ci)) in enumerate(pts4), i in 1:10
        push!(J, ("V-C4", 4000 + 100k + i, Dict{String, Any}("J_cc" => Jcc, "CI" => ci)))
    end
    pts5 = [(0.0, true), (500.0, true), (5000.0, true), (0.0, false), (5000.0, false)]
    for (k, (χ, ci)) in enumerate(pts5), i in 1:10
        push!(J, ("V-C5", 5000 + 100k + i, Dict{String, Any}("χcM" => χ, "CI" => ci)))
    end
    ss = [0.0, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15, 0.175, 0.2, 0.25]
    for (k, s) in enumerate(ss), i in 1:10
        push!(J, ("V-C7", 7000 + 100k + i, Dict{String, Any}("s" => s, "CI" => true)))
    end
    for (k, s) in enumerate((0.0, 0.1, 0.25)), i in 1:10
        push!(J, ("V-C7", 7500 + 100k + i, Dict{String, Any}("s" => s, "CI" => false)))
    end
    for (k, (T, mode)) in enumerate(((50.0, "extension_only"), (50.0, "extension_retraction"),
                                      (800.0, "extension_only"), (800.0, "extension_retraction"))), i in 1:10
        push!(J, ("V-C9", 9000 + 100k + i, Dict{String, Any}("T" => T, "mode" => mode)))
    end
    for i in 1:10
        push!(J, ("V-C12", 12_000 + i, Dict{String, Any}("CI" => true)))
        push!(J, ("V-C12", 12_100 + i, Dict{String, Any}("CI" => false)))
    end
    for i in 1:5
        push!(J, ("V-C1", 20_000 + i, Dict{String, Any}("CI" => true)))
        push!(J, ("V-C1", 20_100 + i, Dict{String, Any}("CI" => false)))
    end
    return J
end
const P63F_JOBS = p63f_jobs()

# the frozen save times per job (the observables the rules read)
function p63f_saves(row, meta)
    row == "V-E1" && return meta["arm"] == "standard" ? [480, 1080, 1440, 2880, 5760] : [1440]
    row in ("V-E5", "V-E6") && return [5760]
    row == "V-E10" && return Int[]
    row in ("V-C3", "V-C1") && return [10_000, 10_100]
    row in ("V-C4", "V-C5", "V-C7", "V-C9") && return [5000, 5100]
    row == "V-C12" && return [100, 19_300]
    error("unknown row $row")
end

# a job is (row, seed, CI): the frozen test reuses seeds 7601–7910 for V-C7's CI (s = 0.125–0.2)
# and no-CI (s = 0, 0.1, 0.25) arms, which differ in CI
p63f_jobkey(row, seed, meta) = (row, seed, haskey(meta, "CI") ? string(meta["CI"]) : "")

p63f_val_eq(s::AbstractString, v::Bool) = s == string(v)
p63f_val_eq(s::AbstractString, v::Real) = (x = tryparse(Float64, s); x !== nothing && x == v)
p63f_val_eq(s::AbstractString, v::AbstractString) = s == v

"""Problems with the replicate rows against the pre-registered jobs (empty when they match)."""
function p63f_job_problems(R)
    probs = String[]
    length(R) == length(P63F_JOBS) || push!(probs, "$(length(R)) rows, want $(length(P63F_JOBS))")
    seen = Dict{Tuple{String, Int, String}, Int}()
    for r in R
        s = tryparse(Int, get(r, "seed", ""))
        s === nothing && (push!(probs, "row without an integer seed"); continue)
        k = (get(r, "row", ""), s, get(r, "CI", ""))
        seen[k] = get(seen, k, 0) + 1
    end
    for (k, n) in seen
        n == 1 || push!(probs, "$(k) appears $n times")
    end
    byk = Dict((r["row"], parse(Int, r["seed"]), get(r, "CI", "")) => r for r in R if tryparse(Int, get(r, "seed", "")) !== nothing)
    for (row, seed, meta) in P63F_JOBS
        r = get(byk, p63f_jobkey(row, seed, meta), nothing)
        r === nothing && (push!(probs, "missing $row seed $seed"); continue)
        for (c, v) in meta
            p63f_val_eq(get(r, c, ""), v) || push!(probs, "$row seed $seed: $c = $(get(r, c, "")), want $v")
        end
        for t in p63f_saves(row, meta), c in ("C_$t", "share_$t", "lacunae_$t", "network_$t")
            v = get(r, c, "")
            ok = c == "network_$t" ? v in ("true", "false") : tryparse(Float64, v) !== nothing
            ok || push!(probs, "$row seed $seed: $c = \"$v\"")
        end
        row == "V-E10" && tryparse(Float64, get(r, "anisotropy", "")) === nothing && push!(probs, "$row seed $seed: anisotropy")
        row == "V-C12" && tryparse(Float64, get(r, "displacement_sites", "")) === nothing &&
            push!(probs, "$row seed $seed: displacement_sites")
    end
    return probs
end

# ---------------------------------------------------------------------------------------------
# the frozen FULL rules (test/reproductions/01_merks.jl, FULL tier), on the replicate rows
# ---------------------------------------------------------------------------------------------
p63f_f(x) = string(round(x; digits = 3))
p63f_num(r, c) = parse(Float64, r[c])
p63f_flag(r, c) = r[c] == "true"
function p63f_crossing(xs, ys, level)                          # = p63d_crossing (frozen)
    for k in 1:(length(xs) - 1)
        a, b = ys[k] - level, ys[k + 1] - level
        a == 0 && return xs[k]
        a * b < 0 && return xs[k] + (xs[k + 1] - xs[k]) * a / (a - b)
    end
    return nothing
end

function p63f_verdicts(R)
    V = NamedTuple{(:row, :check, :ours, :rule, :result), NTuple{5, String}}[]
    add!(row, check, ours, rule, ok) = push!(V, (; row, check, ours, rule, result = ok ? "PASS" : "FAIL"))
    sel(row; kw...) = sort(filter(r -> r["row"] == row && all(p63f_val_eq(get(r, string(k), ""), v) for (k, v) in kw), R);
        by = r -> parse(Int, r["seed"]))
    mC(rs, t) = mean(r -> p63f_num(r, "C_$t"), rs)
    # V-E1
    std_ = sel("V-E1"; arm = "standard")
    rnd = sel("V-E1"; arm = "λ_L = 0")
    n12 = count(r -> p63f_flag(r, "network_1440"), std_)
    add!("V-E1", "network at 1440 MCS (12 h)", "$n12/$(length(std_))", ">= 8/10", n12 >= 8)
    l12, l48 = mean(r -> p63f_num(r, "lacunae_1440"), std_), mean(r -> p63f_num(r, "lacunae_5760"), std_)
    add!("V-E1", "mean lacunae at 5760 vs 1440 MCS", "$(p63f_f(l48)) vs $(p63f_f(l12))", "5760 < 1440", l48 < l12)
    s48 = mean(r -> p63f_num(r, "share_5760"), std_)
    add!("V-E1", "mean share at 5760 MCS (48 h)", p63f_f(s48), ">= 0.9", s48 >= 0.9)
    s12, sr = mean(r -> p63f_num(r, "share_1440"), std_), mean(r -> p63f_num(r, "share_1440"), rnd)
    add!("V-E1", "control λ_L = 0: mean share at 1440 MCS vs standard", "$(p63f_f(sr)) vs $(p63f_f(s12))",
        "<= standard - 0.2", sr <= s12 - 0.2)
    # V-E5
    for L in (10.0, 20.0, 30.0, 40.0, 50.0)
        nnet = count(r -> p63f_flag(r, "network_5760"), sel("V-E5"; L))
        add!("V-E5", "L = $(Int(L)) px ($(Int(2L)) µm): networks at 5760 MCS", "$nnet/10",
            L <= 20 ? "islands in >= 8/10" : "networks in >= 8/10", L <= 20 ? (10 - nnet >= 8) : (nnet >= 8))
    end
    # V-E6
    for Jcc in (20.0, 5.0, 1.0)
        rs = sel("V-E6"; J_cc = Jcc)
        nnet = count(r -> p63f_flag(r, "network_5760"), rs)
        add!("V-E6", "J_cc = $(Int(Jcc)): networks at 5760 MCS", "$nnet/10", ">= 8/10", nnet >= 8)
        if Jcc == 1.0
            lj = mean(r -> p63f_num(r, "lacunae_5760"), rs)
            add!("V-E6", "J_cc = 1: mean lacunae vs V-E1 standard at 5760 MCS", "$(p63f_f(lj)) vs $(p63f_f(l48))", "<=", lj <= l48)
        end
    end
    # V-E10
    el = [p63f_num(r, "anisotropy") for r in sel("V-E10"; arm = "elongated")]
    ro = [p63f_num(r, "anisotropy") for r in sel("V-E10"; arm = "round")]
    add!("V-E10", "elongated: mean anisotropy", p63f_f(mean(el)), "> 1.2", mean(el) > 1.2)
    add!("V-E10", "round control: mean anisotropy", p63f_f(mean(ro)), "< 1.2 and < elongated", mean(ro) < 1.2 && mean(ro) < mean(el))
    # V-C2, V-C3
    ratios = collect(0.0:0.1:1.0)
    m = [mC(sel("V-C3"; ratio = x), 10_000) for x in ratios]
    add!("V-C2", "mean C at ratio 0 (CI) vs ratio 1 (no CI), 10⁴ MCS", "$(p63f_f(m[1])) vs $(p63f_f(m[end]))",
        "CI < no CI - 0.3", m[1] < m[end] - 0.3)
    low, high = mean(m[1:5]), mean(m[8:11])
    add!("V-C3", "low plateau (ratio 0–0.4)", p63f_f(low), "0.35 ± 0.07", abs(low - 0.35) <= 0.07)
    add!("V-C3", "high plateau (ratio 0.7–1)", p63f_f(high), "0.9 ± 0.07", abs(high - 0.9) <= 0.07)
    mid = p63f_crossing(ratios, m, (low + high) / 2)
    add!("V-C3", "midpoint", mid === nothing ? "none" : p63f_f(mid), "in [0.45, 0.65]", mid !== nothing && 0.45 <= mid <= 0.65)
    # V-C4
    m4(J, ci) = mC(sel("V-C4"; J_cc = J, CI = ci), 5000)
    a = (m4(20.0, true), m4(40.0, true), m4(80.0, true))
    add!("V-C4", "CI: mean C at J_cc = 20, 40, 80", join(p63f_f.(a), ", "), "0.3, 0.3, 0.85 ± 0.1",
        abs(a[1] - 0.3) <= 0.1 && abs(a[2] - 0.3) <= 0.1 && abs(a[3] - 0.85) <= 0.1)
    b = (m4(0.0, false), m4(15.0, false), m4(20.0, false), m4(40.0, false))
    add!("V-C4", "no CI: mean C at J_cc = 0, 15, 20, 40", join(p63f_f.(b), ", "), "0.35, 0.83, 0.83, 0.83 ± 0.1",
        abs(b[1] - 0.35) <= 0.1 && all(x -> abs(x - 0.83) <= 0.1, b[2:4]))
    rci, rno = m4(80.0, true) - m4(0.0, true), m4(40.0, false) - m4(0.0, false)
    add!("V-C4", "rise from the lowest to the highest J_cc (CI; no CI)", "$(p63f_f(rci)); $(p63f_f(rno))", "> 0.3 both",
        rci > 0.3 && rno > 0.3)
    # V-C5
    for ((χ, ci), want) in [((0.0, true), 0.9), ((500.0, true), 0.35), ((5000.0, true), 0.2), ((0.0, false), 0.95), ((5000.0, false), 0.7)]
        got = mC(sel("V-C5"; χcM = χ, CI = ci), 5000)
        add!("V-C5", "χcM = $(Int(χ)), $(ci ? "CI" : "no CI"): mean C", p63f_f(got), "$want ± 0.1", abs(got - want) <= 0.1)
    end
    # V-C7
    ss = [0.0, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15, 0.175, 0.2, 0.25]
    mci = [mC(sel("V-C7"; s, CI = true), 5000) for s in ss]
    mid7 = p63f_crossing(ss, mci, (mci[1] + mci[end]) / 2)
    add!("V-C7", "CI: transition midpoint in s", mid7 === nothing ? "none" : p63f_f(mid7), "in [0.07, 0.15]",
        mid7 !== nothing && 0.07 <= mid7 <= 0.15)
    for s in (0.0, 0.1, 0.25)
        got = mC(sel("V-C7"; s, CI = false), 5000)
        add!("V-C7", "no CI, s = $s: mean C", p63f_f(got), "0.95 ± 0.1", abs(got - 0.95) <= 0.1)
    end
    # V-C9
    m9(T, mode) = mC(sel("V-C9"; T, mode), 5000)
    add!("V-C9", "extension-only, T = 50: mean C", p63f_f(m9(50.0, "extension_only")), "> 0.85", m9(50.0, "extension_only") > 0.85)
    add!("V-C9", "extension-retraction, T = 50: mean C", p63f_f(m9(50.0, "extension_retraction")), "< 0.5",
        m9(50.0, "extension_retraction") < 0.5)
    e8, r8 = m9(800.0, "extension_only"), m9(800.0, "extension_retraction")
    add!("V-C9", "both modes, T = 800: mean C (ext-only; ext-retr)", "$(p63f_f(e8)); $(p63f_f(r8))", "< 0.3 both", e8 < 0.3 && r8 < 0.3)
    # V-C12
    ci12 = mean(r -> p63f_num(r, "displacement_sites"), sel("V-C12"; CI = true))
    no12 = mean(r -> p63f_num(r, "displacement_sites"), sel("V-C12"; CI = false))
    add!("V-C12", "displacement ratio CI / no CI (MCS 100 to 19 300)", p63f_f(ci12 / no12), "in [1.5, 2.5]", 1.5 <= ci12 / no12 <= 2.5)
    # V-C1
    k1 = count(r -> p63f_flag(r, "network_10000"), sel("V-C1"; CI = true))
    add!("V-C1", "CI: networks at 10⁴ MCS", "$k1/5", ">= 4/5", k1 >= 4)
    k2 = count(r -> p63f_num(r, "share_10000") < 0.5, sel("V-C1"; CI = false))
    add!("V-C1", "no CI: share < 0.5 at 10⁴ MCS", "$k2/5", ">= 4/5", k2 >= 4)
    return V
end
const P63F_NCHECKS = 37

# the 2008 sweep points: (row, point label, selector, N)
function p63f_points()
    P = Tuple{String, String, Dict{String, Any}, Int}[]
    for x in collect(0.0:0.1:1.0)
        push!(P, ("V-C3", "ratio $x", Dict{String, Any}("ratio" => x), 10_000))
    end
    for (J, ci) in [(0.0, true), (20.0, true), (40.0, true), (60.0, true), (80.0, true),
        (0.0, false), (5.0, false), (10.0, false), (15.0, false), (20.0, false), (40.0, false)]
        push!(P, ("V-C4", "J_cc $J, CI $ci", Dict{String, Any}("J_cc" => J, "CI" => ci), 5000))
    end
    for (χ, ci) in [(0.0, true), (500.0, true), (5000.0, true), (0.0, false), (5000.0, false)]
        push!(P, ("V-C5", "χcM $χ, CI $ci", Dict{String, Any}("χcM" => χ, "CI" => ci), 5000))
    end
    for s in [0.0, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15, 0.175, 0.2, 0.25]
        push!(P, ("V-C7", "s $s, CI true", Dict{String, Any}("s" => s, "CI" => true), 5000))
    end
    for s in (0.0, 0.1, 0.25)
        push!(P, ("V-C7", "s $s, CI false", Dict{String, Any}("s" => s, "CI" => false), 5000))
    end
    for (T, mode) in ((50.0, "extension_only"), (50.0, "extension_retraction"), (800.0, "extension_only"), (800.0, "extension_retraction"))
        push!(P, ("V-C9", "T $T, $mode", Dict{String, Any}("T" => T, "mode" => mode), 5000))
    end
    return P
end

# ---------------------------------------------------------------------------------------------
# snapshot oracle
# ---------------------------------------------------------------------------------------------
# call a frozen definition in the latest world (the module is built at run time)
p63f_fz(F, name, args...) = Base.invokelatest(Base.invokelatest(getglobal, F, name), args...)

"""Mismatches between a job's snapshot (recomputed with the frozen observables) and its row."""
function p63f_snapshot_problems(F, snapfile, row)
    probs = String[]
    snap = deserialize(snapfile)
    res = Dict(Int(t) => Int32.(σ) for (t, σ) in snap)
    for (t, σ) in sort(collect(res); by = first)
        nw = p63f_fz(F, :p63d_network, σ)
        want = Dict("C_$t" => p63f_fz(F, :p63d_compactness, σ), "share_$t" => Float64(nw.share),
            "lacunae_$t" => Float64(nw.lacunae))
        for (c, v) in want
            got = tryparse(Float64, get(row, c, ""))
            got == v || push!(probs, "$(basename(snapfile)): $c = $(get(row, c, "")), recomputed $v")
        end
        get(row, "network_$t", "") == string(p63f_fz(F, :p63d_isnetwork, nw)) ||
            push!(probs, "$(basename(snapfile)): network_$t")
    end
    if get(row, "row", "") == "V-C12"
        d = p63f_fz(F, :p63d_displacement, res[100], res[19_300])
        tryparse(Float64, get(row, "displacement_sites", "")) == d || push!(probs, "$(basename(snapfile)): displacement_sites")
    end
    return probs
end

# ---------------------------------------------------------------------------------------------
# the page
# ---------------------------------------------------------------------------------------------
const P63F_SRC = p63f_read(P63F_PAGE)
const P63F_LINES = split(P63F_SRC, '\n')
p63f_heading_line(re) = findfirst(l -> occursin(re, l), P63F_LINES)
const P63F_H1 = p63f_heading_line(r"^# ## 1\.")
const P63F_H3 = p63f_heading_line(r"^# ## 3\.")
const P63F_H4 = p63f_heading_line(r"^# ## 4\.")
const P63F_H5 = p63f_heading_line(r"^# ## 5\.")
const P63F_H6 = p63f_heading_line(r"^# ## 6\.")
p63f_lines(a, b) = (a === nothing || b === nothing) ? "" : join(P63F_LINES[a:(b - 1)], '\n')
const P63F_BEGINS = findall(l -> strip(l) == P63F_BEGIN, P63F_LINES)
const P63F_ENDS = findall(l -> strip(l) == P63F_END, P63F_LINES)
const P63F_CHUNK = (length(P63F_BEGINS) == 1 && length(P63F_ENDS) == 1 && P63F_BEGINS[1] < P63F_ENDS[1]) ?
                   join(P63F_LINES[(P63F_BEGINS[1] + 1):(P63F_ENDS[1] - 1)], '\n') : ""
const P63F_OUTSIDE = isempty(P63F_CHUNK) ? P63F_SRC :
                     join([P63F_LINES[1:(P63F_BEGINS[1] - 1)]; P63F_LINES[(P63F_ENDS[1] + 1):end]], '\n')

function p63f_md_rows(text)
    rows = Vector{Vector{String}}()
    for l in split(text, '\n')
        s = strip(replace(l, r"^#\s?" => ""))
        (startswith(s, "|") && endswith(s, "|") && length(s) > 1) || continue
        push!(rows, [String(strip(c)) for c in split(s[2:(end - 1)], '|')])
    end
    return rows
end
p63f_issep(row) = all(c -> occursin(r"^:?-{3,}:?$", c), row)

"""Evaluate the page's FULL record chunk alone: (full_verdicts_md, full_deviation_rows) or nothing."""
function p63f_eval_chunk()
    isempty(P63F_CHUNK) && return nothing
    m = Module(:P63FChunk01)
    Core.eval(m, :(using PottsModels, TOML, Markdown, Statistics))
    for e in Meta.parseall(P63F_CHUNK).args
        e isa LineNumberNode && continue
        Core.eval(m, e)
    end
    (Base.invokelatest(isdefined, m, :full_verdicts_md) && Base.invokelatest(isdefined, m, :full_deviation_rows)) || return nothing
    return (Base.invokelatest(getglobal, m, :full_verdicts_md), Base.invokelatest(getglobal, m, :full_deviation_rows))
end

# ids covered by a deviations row's first cell (ranges like V-E2–V-E4 included)
function p63f_ids(cell)
    ids = String[]
    for mt in eachmatch(r"V-([EC])(\d+)(?:\s*[–-]\s*V-\1(\d+))?", cell)
        a = parse(Int, mt[2])
        b = mt[3] === nothing ? a : parse(Int, mt[3])
        append!(ids, ["V-$(mt[1])$k" for k in a:b])
    end
    return ids
end

# =============================================================================================
const P63F_PROV = isfile(joinpath(P63F_REC, "provenance.toml")) ? TOML.parsefile(joinpath(P63F_REC, "provenance.toml")) : Dict{String, Any}()
const P63F_R = p63f_tsv(joinpath(P63F_REC, "replicates.tsv"))

@testset "P6.3f (a) the FULL record and its provenance" begin
    @test isdir(P63F_REC)
    prov = P63F_PROV
    commit = string(get(prov, "commit", ""))
    @test get(prov, "item", "") == "P6.3f"
    @test occursin(r"^[0-9a-f]{40}$", commit)
    @test get(prov, "dirty", true) === false
    frozen = isfile(P63F_FROZEN_TOML) ? TOML.parsefile(P63F_FROZEN_TOML)["file"] : Any[]
    entry = findfirst(f -> f["path"] == "reproductions/01_merks.jl", frozen)
    @test entry !== nothing
    if entry !== nothing
        @test get(prov, "frozen_test_sha256", "") == frozen[entry]["sha256"] == p63f_sha(P63F_FROZEN)
    end
    for k in ("hostname", "cpu", "julia")
        @test !isempty(string(get(prov, k, "")))
    end
    @test get(prov, "threads", nothing) isa Integer
    @test get(prov, "jobs", 0) == 590
    runner = string(get(prov, "runner", ""))
    @test startswith(runner, "lib/PottsModels/reproductions/data/01/$P63F_RECNAME/") && isfile(joinpath(P63F_ROOT, runner))
    # the producing commit is in our history
    git(args...) = try
        readchomp(Cmd(`git $args`; dir = P63F_ROOT))
    catch
        nothing
    end
    shallow = git("rev-parse", "--is-shallow-repository")
    if shallow == "false" && length(commit) == 40
        @test success(Cmd(`git merge-base --is-ancestor $commit HEAD`; dir = P63F_ROOT))
    else
        @info "P6.3f: git unavailable or shallow clone; the producing-commit ancestry check is skipped"
    end
    # only small statistics, figures and code; snapshots only under snap/; no video
    files = p63f_files(P63F_REC)
    @test !isempty(files)
    for f in files
        rel = relpath(f, P63F_REC)
        ok = filesize(f) <= 10 * 2^20 &&
             (any(e -> endswith(lowercase(f), e), P63F_RECORD_EXT) || (startswith(rel, "snap" * Base.Filesystem.path_separator) && endswith(f, ".jls")))
        ok || @info "P6.3f: not allowed in the record: $rel"
        @test ok
    end
    @test !any(f -> any(e -> endswith(lowercase(f), e), P63F_VIDEO_EXT), p63f_files(dirname(P63F_REC)))
end

@testset "P6.3f (b) replicates: every pre-registered job, once, with its parameters" begin
    @test length(P63F_JOBS) == 590 && allunique(p63f_jobkey(j...) for j in P63F_JOBS)
    probs = p63f_job_problems(P63F_R)
    isempty(probs) || @info "P6.3f: replicate problems" probs[1:min(end, 20)]
    @test isempty(probs)
    # negative controls: a missing and a duplicated seed are caught
    if length(P63F_R) >= 2
        @test !isempty(p63f_job_problems(P63F_R[2:end]))
        @test !isempty(p63f_job_problems([P63F_R[1:(end - 1)]; [P63F_R[1]]]))
    end
end

@testset "P6.3f (c) snapshot oracle: the frozen observables recompute the rows" begin
    F = p63f_frozen_module()
    # the frozen definitions loaded: a filled 10 × 10 square on a framed 20² gives C = 100/81
    σ = zeros(Int32, 20, 20); σ[[1, 20], :] .= 1; σ[:, [1, 20]] .= 1; σ[5:14, 5:14] .= 2
    @test p63f_fz(F, :p63d_compactness, σ) ≈ 100 / 81
    byk = Dict(get(r, "key", "") => r for r in P63F_R)
    snaps = filter(f -> endswith(f, ".jls"), p63f_files(joinpath(P63F_REC, "snap")))
    keys_ = [splitext(basename(f))[1] for f in snaps]
    rows_ = [get(get(byk, k, Dict{String, String}()), "row", "") for k in keys_]
    @test any(in(("V-E1", "V-E5", "V-E6")), rows_)
    @test any(startswith("V-C"), rows_)
    @test sum(filesize, snaps; init = 0) <= 4 * 2^20
    for (f, k) in zip(snaps, keys_)
        @test haskey(byk, k)
        haskey(byk, k) || continue
        probs = p63f_snapshot_problems(F, f, byk[k])
        isempty(probs) || @info "P6.3f: snapshot mismatch" probs
        @test isempty(probs)
    end
    # negative control: an edited value is caught
    if !isempty(snaps) && haskey(byk, keys_[1])
        r = copy(byk[keys_[1]])
        c = first(filter(k -> startswith(k, "C_") && !isempty(r[k]), collect(keys(r))))
        r[c] = string(parse(Float64, r[c]) + 1e-9)
        @test !isempty(p63f_snapshot_problems(F, snaps[1], r))
    end
    # opt-in: every job's snapshots (kept on the PC)
    alld = get(ENV, "P63F_SNAPSHOTS", "")
    if isdir(alld)
        all_snaps = filter(f -> endswith(f, ".jls"), p63f_files(alld))
        @test length(all_snaps) == count(j -> j[1] != "V-E10", P63F_JOBS)
        for f in all_snaps
            k = splitext(basename(f))[1]
            @test haskey(byk, k) && isempty(p63f_snapshot_problems(F, f, byk[k]))
        end
    else
        @info "P6.3f: P63F_SNAPSHOTS not set; only the committed snapshots are checked"
    end
end

const P63F_V = isempty(p63f_job_problems(P63F_R)) ? p63f_verdicts(P63F_R) : nothing

@testset "P6.3f (d) verdicts: the frozen FULL rules applied to the record" begin
    @test P63F_V !== nothing
    if P63F_V !== nothing
        @test length(P63F_V) == P63F_NCHECKS
        @info "P6.3f: FULL verdicts recomputed from replicates.tsv" P63F_V
        vt = p63f_tsv(joinpath(P63F_REC, "verdicts.tsv"))
        @test p63f_tsv_header(joinpath(P63F_REC, "verdicts.tsv"))[1:5] == ["row", "check", "ours", "rule", "result"]
        @test length(vt) == length(P63F_V)
        for (k, v) in enumerate(P63F_V)
            t = k <= length(vt) ? vt[k] : Dict{String, String}()
            ok = all(get(t, string(c), nothing) == getfield(v, c) for c in (:row, :check, :ours, :rule, :result))
            ok || @info "P6.3f: verdicts.tsv row $k differs" want = v got = t
            @test ok
        end
        # negative controls: the rules move with the data
        lowpass(R, x) = [r["row"] == "V-C3" && parse(Float64, r["ratio"]) <= 0.4 ?
                         merge(r, Dict("C_10000" => string(x))) : r for r in R]
        vlow(R) = only(filter(v -> v.check == "low plateau (ratio 0–0.4)", p63f_verdicts(R))).result
        @test vlow(lowpass(P63F_R, 0.35)) == "PASS"
        @test vlow(lowpass(P63F_R, 0.55)) == "FAIL"
        flip = [r["row"] == "V-C1" && r["CI"] == "true" ? merge(r, Dict("network_10000" => "false")) : r for r in P63F_R]
        @test only(filter(v -> v.check == "CI: networks at 10⁴ MCS", p63f_verdicts(flip))).result == "FAIL"
    end
    # both clocks for the 2008 sweeps (D-153 M6)
    pt = p63f_tsv(joinpath(P63F_REC, "points.tsv"))
    P = p63f_points()
    @test length(pt) >= length(P)
    for (row, label, meta, N) in P
        rs = filter(r -> r["row"] == row && all(p63f_val_eq(get(r, c, ""), v) for (c, v) in meta), P63F_R)
        t = findfirst(x -> get(x, "row", "") == row && get(x, "point", "") == label, pt)
        @test t !== nothing && length(rs) == 10
        (t === nothing || length(rs) != 10) && continue
        for (col, tt) in (("mean_C_N", N), ("mean_C_N+100", N + 100))
            got = tryparse(Float64, get(pt[t], col, ""))
            @test got !== nothing && abs(got - mean(r -> p63f_num(r, "C_$tt"), rs)) <= 5e-5
        end
    end
end

const P63F_VIDEOS = let f = joinpath(P63F_REC, "videos.toml")
    isfile(f) ? get(TOML.parsefile(f), "video", Any[]) : Any[]
end

@testset "P6.3f (e) videos: per-cell release assets of record replicates" begin
    @test !isempty(P63F_VIDEOS)
    keys_ = Set(get(r, "key", "") for r in P63F_R)
    for v in P63F_VIDEOS
        file, tag = string(get(v, "file", "")), string(get(v, "tag", ""))
        @test occursin(Regex("^01_merks_full-2026-10-08_.*cells.*\\.mp4\$"), file)
        mt = match(r"^reproductions-2026-10-(\d\d)", tag)
        @test mt !== nothing && parse(Int, mt[1]) >= 8
        @test string(get(v, "job", "")) in keys_
        @test get(v, "encoding", "") == "CellIdentityEncoding"
        @test get(v, "boundaries", true) === false
        @test occursin(r"^[0-9a-f]{64}$", string(get(v, "sha256", "")))
        @test 0 < get(v, "bytes", 0) <= 50 * 2^20
        @test get(v, "final_state_matches_record", false) === true
        @test occursin(P63F_RELEASES * tag * "/" * file, P63F_SRC)
    end
    listed = Set(P63F_RELEASES * string(get(v, "tag", "")) * "/" * string(get(v, "file", "")) for v in P63F_VIDEOS)
    for mt in eachmatch(r"https://github\.com/[^\s\"'()<>\[\]`]*01_merks_full[^\s\"'()<>\[\]`]*\.mp4", P63F_SRC)
        ok = mt.match in listed
        ok || @info "P6.3f: page video not in videos.toml: $(mt.match)"
        @test ok
    end
end

const P63F_CHUNK_OUT = try
    p63f_eval_chunk()
catch e
    @info "P6.3f: the FULL record chunk does not evaluate" exception = e
    nothing
end

@testset "P6.3f (f) the page renders the record (its FULL record chunk)" begin
    @test length(P63F_BEGINS) == 1 && length(P63F_ENDS) == 1 && !isempty(P63F_CHUNK)
    @test P63F_H3 !== nothing && !isempty(P63F_BEGINS) && P63F_BEGINS[1] < P63F_H3
    @test occursin(P63F_RECNAME, P63F_CHUNK)
    @test !occursin(r"\bsolve\(|PottsProblem|\brun0[68]\(|\bwalk\(", P63F_CHUNK)
    @test P63F_CHUNK_OUT !== nothing
    vmd, devrows = P63F_CHUNK_OUT === nothing ? ("", String[]) : P63F_CHUNK_OUT
    @test vmd isa AbstractString && devrows isa AbstractVector{<:AbstractString}
    # the verdict table
    rows = p63f_md_rows(vmd)
    @test length(rows) >= 3 && p63f_issep(rows[2])
    head = isempty(rows) ? String[] : lowercase.(rows[1])
    col(name) = findfirst(h -> occursin(name, h), head)
    ct, co, cc, cr = col("target"), col("ours"), col("class"), col("result")
    @test all(!isnothing, (ct, co, cc, cr))
    if P63F_V !== nothing && all(!isnothing, (ct, co, cc, cr))
        body = rows[3:end]
        for v in P63F_V
            ok = any(r -> length(r) == length(head) && startswith(r[ct], "$(v.row) $(v.check)") && r[co] == v.ours &&
                     r[cc] == "FULL record" && r[cr] == v.result, body)
            ok || @info "P6.3f: no page verdict row for $(v.row) $(v.check) = $(v.ours) $(v.result)"
            @test ok
        end
    end
    # the deviation rows for every FAIL
    drows = [p63f_md_rows(r) for r in devrows]
    @test all(d -> length(d) == 1, drows)
    drows = [only(d) for d in drows if length(d) == 1]
    for d in drows
        @test length(d) == 5
        length(d) == 5 || continue
        @test !isempty(d[4]) && d[4] ∉ ("—", "-")
        @test occursin(r"^(not an author question|not asked)", lowercase(d[5]))
    end
    if P63F_V !== nothing
        for v in filter(v -> v.result == "FAIL", P63F_V)
            key = v.row == "V-C3" && startswith(v.check, "low plateau") ? "V-C3 low plateau" : v.row
            ok = any(d -> length(d) == 5 && occursin(key, d[1]) && occursin("FAIL", d[1]) && occursin(v.ours, d[2]), drows)
            ok || @info "P6.3f: failing check without a deviations row: $(v.row) $(v.check) = $(v.ours)"
            @test ok
        end
    end
    # shown on the page
    s3, s5 = p63f_lines(P63F_H3, P63F_H4), p63f_lines(P63F_H5, P63F_H6)
    @test occursin("full_deviation_rows", s3)
    @test occursin("full_verdicts_md", s5) && occursin("Markdown.parse", s5)
    @test occursin("points.tsv", P63F_SRC)
end

@testset "P6.3f (g) deviations table: D-161 rows, provisional defaults, parked targets" begin
    s3 = p63f_lines(P63F_H3, P63F_H4)
    rows = p63f_md_rows(s3)
    @test !isempty(rows)
    isempty(rows) && (rows = [String[""]])
    h = lowercase(join(rows[1], " | "))
    @test occursin("ours", h) && occursin("paper", h) && occursin("cause", h) && occursin("author question", h)
    body = [r for r in rows[2:end] if !p63f_issep(r)]
    first_cells = [r[1] for r in body]
    has(re) = any(c -> occursin(re, c), first_cells)
    @test any(c -> occursin("target length L", c) && occursin("provisional", c), first_cells)
    @test any(r -> occursin("target length L", r[1]) && occursin("50", join(r, "|")) && occursin("60", join(r, "|")), body)
    @test any(c -> occursin("classification time", c) && occursin("provisional", c), first_cells)
    @test any(r -> occursin("classification time", r[1]) && occursin("48 h", join(r, "|")), body)
    for key in ("2006 connectivity E₀", "2006 seeding", "2008 time origin", "01b Fig. 2 set-up", "Field scheme",
                "ΔH arithmetic", "χ(c,c)", "Parameter sets", "2008 seeding", "Border", "Copy proposal", "Compactness")
        ok = has(key)
        ok || @info "P6.3f: deviations row missing: $key"
        @test ok
    end
    parked = Set(id for c in first_cells if occursin("PARKED", c) for id in p63f_ids(c))
    for id in ("V-E2", "V-E3", "V-E4", "V-E7", "V-E8", "V-E9", "V-C6", "V-C8", "V-C10", "V-C11")
        ok = id in parked
        ok || @info "P6.3f: parked target without a row: $id"
        @test ok
    end
    @test !has(r"attempts"i)
    @test !any(r -> occursin(r"pending|at risk"i, join(r, "|")), body)
    for r in body
        s = last(r)
        ok = occursin(r"^(not an author question|not asked)"i, s) || startswith(s, "\$(aq(")
        ok || @info "P6.3f: bad author-question status: $s"
        @test ok
    end
    aqdef = match(r"aq\(item\)\s*=\s*\"([^\"]*)\"", P63F_SRC)
    @test aqdef !== nothing && startswith(aqdef[1], "not asked") && occursin("open question list", aqdef[1])
end

@testset "P6.3f (h) banner and text (D-161 kept)" begin
    head = P63F_H1 === nothing ? "" : join(P63F_LINES[1:(P63F_H1 - 1)], '\n')
    commit = string(get(P63F_PROV, "commit", ""))
    @test occursin(P63F_RECNAME, head)
    @test length(commit) >= 8 && occursin(commit[1:8], head)
    names = String[]
    cpu = string(get(P63F_PROV, "cpu", ""))
    isempty(cpu) || push!(names, lowercase(strip(first(split(cpu, " w/")))))
    host = string(get(P63F_PROV, "hostname", ""))
    isempty(host) || push!(names, lowercase(host))
    @test any(n -> occursin(n, lowercase(head)), names)
    for re in (r"pending (the )?full run"i, r"no full run has been made"i, r"full-run outputs[^.]*pending"i)
        @test !occursin(re, P63F_SRC)
    end
    @test occursin("39 204", P63F_SRC) && occursin("(sizex − 2)(sizey − 2)", P63F_SRC)
    @test occursin("MCS after relaxation", P63F_SRC) && occursin("code MCS", P63F_SRC)
    for re in (r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i, r"docs/references"i)
        @test !occursin(re, P63F_SRC)
    end
    log = filter(r -> length(r) >= 2 && occursin(r"^\d{4}-\d\d-\d\d$", r[1]), p63f_md_rows(P63F_SRC))
    @test any(r -> r[1] >= "2026-10-08" && occursin(P63F_RECNAME, join(r, "|")), log)
end

@testset "P6.3f (i) rendering: per-cell colours, no outlines (D-156, D-172)" begin
    @test !isempty(P63F_SRC)
    @test !occursin(r"boundaries\s*=\s*true", P63F_SRC)
    @test !occursin("pottsboundaries", P63F_SRC)
    @test !occursin("ChannelEncoding", P63F_SRC)
    # each call's text: from the name to its closing parenthesis
    function calls(name)
        out = String[]
        for mt in eachmatch(Regex("\\b" * name * "\\("), P63F_OUTSIDE)
            i, depth = mt.offset + length(name), 0
            j = i
            while j <= lastindex(P63F_OUTSIDE)
                c = P63F_OUTSIDE[j]
                c == '(' && (depth += 1)
                c == ')' && (depth -= 1; depth == 0 && break)
                j = nextind(P63F_OUTSIDE, j)
            end
            push!(out, P63F_OUTSIDE[mt.offset:min(j, lastindex(P63F_OUTSIDE))])
        end
        return out
    end
    rp = calls("record_potts")
    @test !isempty(rp)
    for c in rp
        ok = occursin(r"encoding\s*=\s*CellIdentityEncoding\(\)", c)
        ok || @info "P6.3f: record_potts without per-cell colours: $(first(c, 120))"
        @test ok
    end
    for c in calls("pottsplot")
        @test occursin(r"CellIdentityEncoding|CellTypeEncoding", c)
    end
end

@testset "P6.3f (j) the page parses and is rendered by the docs (build opt-in)" begin
    parsed = isempty(P63F_SRC) ? nothing : Meta.parseall(P63F_SRC)
    bad(ex) = ex isa Expr && (ex.head in (:error, :incomplete) || any(bad, ex.args))
    @test parsed !== nothing && !bad(parsed)
    make = p63f_read(P63F_MAKE)
    @test occursin(r"readdir\(REPRODUCTIONS\)", make) && occursin("Literate.markdown(joinpath(REPRODUCTIONS", make)
    if get(ENV, "POTTS_DOCS_BUILD", "false") == "true"
        cmd = addenv(`$(Base.julia_cmd()) --project=docs docs/make.jl`, "POTTS_DOCS_PUBLISHED" => "true")
        @test success(pipeline(Cmd(cmd; dir = P63F_ROOT); stdout = stdout, stderr = stderr))
        built = joinpath(P63F_ROOT, "docs", "build", "published", "01_merks", "index.html")
        @test isfile(built)
        html = p63f_read(built)
        if P63F_V !== nothing
            for v in P63F_V
                @test occursin(v.ours, html)
            end
        end
        for v in P63F_VIDEOS
            @test occursin(P63F_RELEASES * string(get(v, "tag", "")) * "/" * string(get(v, "file", "")), html)
        end
    else
        @info "P6.3f: POTTS_DOCS_BUILD not set; the Documenter build is skipped"
    end
end
