# the reproduction 01 page renders the FULL record.
# The page is the Literate
# script `lib/PottsModels/reproductions/01_merks.jl`. This file reads the page source, the
# committed record and the 01 reproduction test; it runs no simulation. The 01 reproduction test
# (`test/reproductions/01_merks_tests.jl`, D-153; V-C12 amended by D-200) is not edited here: its FULL tier's rules are
# re-applied here, verbatim in substance, to the committed per-replicate record.
#
# The record (D-146) is `lib/PottsModels/reproductions/data/01/full-2026-10-08/`:
#
# (a) Provenance. `provenance.toml` has the record's item ID; a 40-hex `commit` that is an ancestor
#     of HEAD (checked when git is available and the clone is not shallow); `dirty = false`;
#     `hostname`, `cpu`, `julia`, an integer `threads`, `jobs = 590`,
#     and a `runner` inside the record directory that exists. Files: only .tsv, .toml, .md,
#     .jl, .png, .svg (and .jls under `snap/`), each ≤ 10 MB; no video file.
# (b) Replicates. `replicates.tsv` (tab-separated, header first) has one row per job of the
#     FULL tier, 590 in all: the pre-registered seeds of the reproduction test, each once,
#     with the reproduction test's parameters for that seed (columns `row`, `seed`, `key` and the
#     parameter columns `arm`, `L`, `J_cc`, `ratio`, `CI`, `χcM`, `s`, `T`, `mode`), and
#     the observables the rules read: `C_t`, `share_t`, `lacunae_t`, `network_t` at the
#     pre-registered save times t, `anisotropy` (V-E10) and `displacement_sites` (V-C12). Floats are
#     written at full precision (shortest round-trip form).
# (c) Snapshot oracle. `snap/<key>.jls` holds the σ snapshots of at least one 2006 job
#     (V-E1, V-E5 or V-E6) and at least one 2008 job (V-C*), ≤ 4 MB in all, each the
#     runner's `serialize`d Dict{Int, Matrix{UInt16}} of σ at the job's save times. The
#     reproduction test's own observable functions (its definitions, evaluated here without its
#     testsets) recompute every observable of those jobs from the snapshots, and they equal
#     the replicate rows exactly (our own code: bitwise, D-158). Opt-in: `SNAPSHOTS` = a
#     directory of every job's snapshots (kept on the PC) checks them all the same way.
# (d) Verdicts. The FULL rules, applied here to `replicates.tsv`, give 37 checks
#     (CHECKS below, in the reproduction test's order; the V-C3 plateau `@test` is
#     reported as its low and high halves). `verdicts.tsv` has exactly these rows, in this
#     order, with columns `row`, `check`, `ours`, `rule`, `result` equal to the recomputed
#     ones. `points.tsv` has the mean compactness of every 2008 sweep point at N and at
#     N + 100 MCS (D-153 M6, reported), within 5e-5 of the recomputed means.
# (e) Videos (D-146, D-156, D-161, D-172). `videos.toml` lists ≥ 1 `[[video]]` with `file`
#     (`01_merks_full-2026-10-08_*cells*.mp4`), `tag` (a new dated pre-release
#     `reproductions-2026-10-DD…`, DD ≥ 08, which is created and uploaded at release),
#     `job` (a key of `replicates.tsv`), `encoding = "CellIdentityEncoding"`,
#     `boundaries = false`, a 64-hex `sha256`, `bytes` ≤ 50 MB and
#     `final_state_matches_record = true`. The page links each as
#     `https://github.com/PraneethMerugu/Potts.jl/releases/download/<tag>/<file>`, and every
#     `01_merks_full` video URL on the page is one of them.
#
# The page (D-185 layout): an intro before `# ## 1.`; §1 the model code, §2 a minimal run,
# §3 the results (key figures, the FULL videos, a verdict summary and, as the subsection
# headed `# ### … Deviations`, the deviations table); §4 a collapsed "Details" section
# (`<details>` … `</details>`) to the end of the page, with the protocol, every verdict and
# the provenance. "The deviations section" below runs from its `# ###` heading to the next
# `# ##`/`# ###` heading; "the Details section" from `# ## 4.` to the end.
#
# (f) FULL record chunk. Exactly one code chunk delimited by the lines
#     `BEGIN` and `END` (below), before the
#     deviations section. It names
#     the record directory and runs no simulation (no `solve(`, `PottsProblem`, `run06`,
#     `run08`, `walk(`). Evaluated alone in a fresh module (with PottsModels, TOML, Markdown
#     and Statistics loaded) it defines
#     - `full_verdicts_md::String`, a Markdown table with columns Target, Ours, Class and
#       Result: for every check of (d) a row whose Target starts with "<row> <check>", whose
#       Ours is the check's `ours`, whose Class is "FULL record" and whose Result is the
#       recomputed PASS or FAIL;
#     - `full_deviation_rows::Vector{String}`, Markdown rows of the deviations table (D-154):
#       for every FAIL check, a row whose first cell names the row id and "FAIL" (for a
#       failing V-C3 low plateau: "V-C3 low plateau" and "FAIL") and whose Ours cell
#       contains the check's `ours`, with a non-empty cause.
#     Outside the chunk, `full_verdicts_md` is shown in the Details section and
#     `full_deviation_rows` is spliced into the deviations section's table. The page names `points.tsv` (the N + 100 reading).
# (g) Deviations table (D-154, D-155, D-161). The deviations section's table header has Ours, Paper, cause
#     and Author question. Its static rows keep D-161's items: 2006 target length L
#     (provisional, 50 and 60 px), V-E5/V-E6 classification time (provisional, 48 h), 2006
#     connectivity E₀, 2006 seeding, 2008 time origin, 01b Fig. 2 set-up, Field scheme,
#     ΔH arithmetic, χ(c,c), Parameter sets, 2008 seeding, Border, Copy proposal,
#     Compactness; and PARKED rows covering V-E2, V-E3, V-E4, V-E7, V-E8, V-E9, V-C6, V-C8,
#     V-C10 and V-C11. One row is about attempts per MCS (D-200 item 2); no row says "pending" or "at risk".
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
# (k) Layout (D-185). The headings `# ## 1.` to `# ## 4.` appear once each, in order, the
#     fourth naming "Details"; the deviations section lies inside §3; the Details section
#     opens a `<details>` element and closes it; every `01_merks_full` video URL first
#     appears before the Details section; the page has no contact wording ("Contact:",
#     "contact us", "e-mail").
#
# Amended under D-200 (2026-10-09). Item 1: the reproduction test's V-C12 now measures displacement
# from MCS 0 (01b Fig. 6E), not MCS 100. The record gains `vc12_mcs0.tsv` (one row per V-C12
# job: `key`, `row`, `seed`, `CI`, `displacement_sites_0`, `displacement_sites_100`), read
# from the stored snapshots with no new dynamics by `vc12_mcs0.jl`, and a `[vc12_mcs0]` table
# in `provenance.toml` (decision "D-200", `new_dynamics = false`, its own 40-hex `commit`, an
# existing `script` in the record, no `hostname` or `work` key, and the amended test's
# `frozen_test_sha256` provenance field). So: in (b)
# `vc12_mcs0.tsv` covers the 20 V-C12 jobs once each, with `displacement_sites_100` equal to
# `replicates.tsv`'s `displacement_sites` exactly, and `displacement_sites_0` joins those rows;
# in (c) a V-C12 snapshot also recomputes `displacement_sites_0` from σ at MCS 0; in (d)
# V-C12's check is "displacement ratio CI / no CI (MCS 0 to 19 300)" on
# `displacement_sites_0`. Item 2: (g) now requires a deviations row on attempts per MCS (the
# paper's N = number of lattice sites, 200² = 40 000 on the 200² lattice of the 01b parameter
# files, against our 39 204, a 2 % time scale, the paper the target).
#
# Amended under D-240 (2026-10-13 paper audit). The 01 reproduction test re-targets V-C4's CI value
# at J_cc = 40 to 0.40 (was 0.3) and V-C5's CI value at χcM = 500 to 0.40 (was 0.35), both
# ± 0.1; (d) re-applies them, and the record's `verdicts.tsv` rows were re-derived from
# `replicates.tsv` with no new dynamics.
#
# Negative controls (D-048): the recomputed rules flip on perturbed copies of the record
# (V-C3 low plateau moved into and out of its band, a V-C1 network flag flipped); the job
# check rejects a missing and a duplicated seed; the snapshot oracle rejects an edited value;
# V-C12 fails when read on the old MCS-100 axis; an edited `displacement_sites_100` is caught;
# the reproduction's observables are checked on a hand-built square (C = 100/81).

@testsetup module MerksPageSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, TOML, SHA, Serialization, Markdown
using Statistics: mean
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const PAGE = joinpath(ROOT, "lib", "PottsModels", "reproductions", "01_merks.jl")
const RECNAME = "full-2026-10-08"
const REC = joinpath(ROOT, "lib", "PottsModels", "reproductions", "data", "01", RECNAME)
const MAKE = joinpath(ROOT, "docs", "make.jl")
const RELEASES = "https://github.com/PraneethMerugu/Potts.jl/releases/download/"
const BEGIN = "## FULL record: begin"
const END = "## FULL record: end"
const VIDEO_EXT = (".mp4", ".webm", ".mov", ".mkv", ".gif")
const RECORD_EXT = (".tsv", ".toml", ".md", ".jl", ".png", ".svg")
page_read(p) = isfile(p) ? read(p, String) : ""
sha(f) = bytes2hex(open(sha256, f))
function page_files(dir)
    out = String[]
    isdir(dir) || return out
    for (root, _, fs) in walkdir(dir), f in fs
        push!(out, joinpath(root, f))
    end
    return out
end
function page_tsv(path)
    isfile(path) || return Dict{String, String}[]
    lines = filter(!isempty, readlines(path))
    isempty(lines) && return Dict{String, String}[]
    head = split(lines[1], '\t')
    return [Dict(String(h) => String(v) for (h, v) in zip(head, split(l, '\t'; keepempty = true))) for l in lines[2:end]]
end
function tsv_header(path)
    isfile(path) || return String[]
    l = readline(path)
    return String.(split(l, '\t'))
end
# ---------------------------------------------------------------------------------------------
# the 01 reproduction's definitions (shared/merks.jl), in their own module
# ---------------------------------------------------------------------------------------------
function merks_module()
    m = Module(:MerksReproduction)
    Core.eval(m, :(using Potts, PottsModels, Test))
    Base.include(m, joinpath(@__DIR__, "..", "shared", "merks.jl"))
    return m
end
# ---------------------------------------------------------------------------------------------
# the pre-registered jobs of the FULL tier: (row, seed) => parameters
# ---------------------------------------------------------------------------------------------
function page_jobs()
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
    pts4 = [
        (0.0, true), (20.0, true), (40.0, true), (60.0, true), (80.0, true),
        (0.0, false), (5.0, false), (10.0, false), (15.0, false), (20.0, false), (40.0, false),
    ]
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
    for (k, (T, mode)) in enumerate(
                (
                    (50.0, "extension_only"), (50.0, "extension_retraction"),
                    (800.0, "extension_only"), (800.0, "extension_retraction"),
                )
            ), i in 1:10
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
const JOBS = page_jobs()
# the pre-registered save times per job (the observables the rules read)
function saves(row, meta)
    row == "V-E1" && return meta["arm"] == "standard" ? [480, 1080, 1440, 2880, 5760] : [1440]
    row in ("V-E5", "V-E6") && return [5760]
    row == "V-E10" && return Int[]
    row in ("V-C3", "V-C1") && return [10_000, 10_100]
    row in ("V-C4", "V-C5", "V-C7", "V-C9") && return [5000, 5100]
    row == "V-C12" && return [100, 19_300]
    error("unknown row $row")
end
# a job is (row, seed, CI): the reproduction test reuses seeds 7601–7910 for V-C7's CI (s = 0.125–0.2)
# and no-CI (s = 0, 0.1, 0.25) arms, which differ in CI
jobkey(row, seed, meta) = (row, seed, haskey(meta, "CI") ? string(meta["CI"]) : "")
val_eq(s::AbstractString, v::Bool) = s == string(v)
val_eq(s::AbstractString, v::Real) = (x = tryparse(Float64, s); x !== nothing && x == v)
val_eq(s::AbstractString, v::AbstractString) = s == v
"""Problems with the replicate rows against the pre-registered jobs (empty when they match)."""
function job_problems(R)
    probs = String[]
    length(R) == length(JOBS) || push!(probs, "$(length(R)) rows, want $(length(JOBS))")
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
    for (row, seed, meta) in JOBS
        r = get(byk, jobkey(row, seed, meta), nothing)
        r === nothing && (push!(probs, "missing $row seed $seed"); continue)
        for (c, v) in meta
            val_eq(get(r, c, ""), v) || push!(probs, "$row seed $seed: $c = $(get(r, c, "")), want $v")
        end
        for t in saves(row, meta), c in ("C_$t", "share_$t", "lacunae_$t", "network_$t")
            v = get(r, c, "")
            ok = c == "network_$t" ? v in ("true", "false") : tryparse(Float64, v) !== nothing
            ok || push!(probs, "$row seed $seed: $c = \"$v\"")
        end
        row == "V-E10" && tryparse(Float64, get(r, "anisotropy", "")) === nothing && push!(probs, "$row seed $seed: anisotropy")
        row == "V-C12" && tryparse(Float64, get(r, "displacement_sites", "")) === nothing &&
            push!(probs, "$row seed $seed: displacement_sites")
        row == "V-C12" && tryparse(Float64, get(r, "displacement_sites_0", "")) === nothing &&
            push!(probs, "$row seed $seed: displacement_sites_0 (vc12_mcs0.tsv)")
    end
    return probs
end
# ---------------------------------------------------------------------------------------------
# the FULL rules (test/reproductions/01_merks_tests.jl, FULL tier), on the replicate rows
# ---------------------------------------------------------------------------------------------
page_f(x) = string(round(x; digits = 3))
num(r, c) = parse(Float64, r[c])
flag(r, c) = r[c] == "true"
function page_crossing(xs, ys, level)                          # = crossing (frozen)
    for k in 1:(length(xs) - 1)
        a, b = ys[k] - level, ys[k + 1] - level
        a == 0 && return xs[k]
        a * b < 0 && return xs[k] + (xs[k + 1] - xs[k]) * a / (a - b)
    end
    return nothing
end
function page_verdicts(R)
    V = NamedTuple{(:row, :check, :ours, :rule, :result), NTuple{5, String}}[]
    add!(row, check, ours, rule, ok) = push!(V, (; row, check, ours, rule, result = ok ? "PASS" : "FAIL"))
    sel(row; kw...) = sort(
        filter(r -> r["row"] == row && all(val_eq(get(r, string(k), ""), v) for (k, v) in kw), R);
        by = r -> parse(Int, r["seed"])
    )
    mC(rs, t) = mean(r -> num(r, "C_$t"), rs)
    # V-E1
    std_ = sel("V-E1"; arm = "standard")
    rnd = sel("V-E1"; arm = "λ_L = 0")
    n12 = count(r -> flag(r, "network_1440"), std_)
    add!("V-E1", "network at 1440 MCS (12 h)", "$n12/$(length(std_))", ">= 8/10", n12 >= 8)
    l12, l48 = mean(r -> num(r, "lacunae_1440"), std_), mean(r -> num(r, "lacunae_5760"), std_)
    add!("V-E1", "mean lacunae at 5760 vs 1440 MCS", "$(page_f(l48)) vs $(page_f(l12))", "5760 < 1440", l48 < l12)
    s48 = mean(r -> num(r, "share_5760"), std_)
    add!("V-E1", "mean share at 5760 MCS (48 h)", page_f(s48), ">= 0.9", s48 >= 0.9)
    s12, sr = mean(r -> num(r, "share_1440"), std_), mean(r -> num(r, "share_1440"), rnd)
    add!(
        "V-E1", "control λ_L = 0: mean share at 1440 MCS vs standard", "$(page_f(sr)) vs $(page_f(s12))",
        "<= standard - 0.2", sr <= s12 - 0.2
    )
    # V-E5
    for L in (10.0, 20.0, 30.0, 40.0, 50.0)
        nnet = count(r -> flag(r, "network_5760"), sel("V-E5"; L))
        add!(
            "V-E5", "L = $(Int(L)) px ($(Int(2L)) µm): networks at 5760 MCS", "$nnet/10",
            L <= 20 ? "islands in >= 8/10" : "networks in >= 8/10", L <= 20 ? (10 - nnet >= 8) : (nnet >= 8)
        )
    end
    # V-E6
    for Jcc in (20.0, 5.0, 1.0)
        rs = sel("V-E6"; J_cc = Jcc)
        nnet = count(r -> flag(r, "network_5760"), rs)
        add!("V-E6", "J_cc = $(Int(Jcc)): networks at 5760 MCS", "$nnet/10", ">= 8/10", nnet >= 8)
        if Jcc == 1.0
            lj = mean(r -> num(r, "lacunae_5760"), rs)
            add!("V-E6", "J_cc = 1: mean lacunae vs V-E1 standard at 5760 MCS", "$(page_f(lj)) vs $(page_f(l48))", "<=", lj <= l48)
        end
    end
    # V-E10
    el = [num(r, "anisotropy") for r in sel("V-E10"; arm = "elongated")]
    ro = [num(r, "anisotropy") for r in sel("V-E10"; arm = "round")]
    add!("V-E10", "elongated: mean anisotropy", page_f(mean(el)), "> 1.2", mean(el) > 1.2)
    add!("V-E10", "round control: mean anisotropy", page_f(mean(ro)), "< 1.2 and < elongated", mean(ro) < 1.2 && mean(ro) < mean(el))
    # V-C2, V-C3
    ratios = collect(0.0:0.1:1.0)
    m = [mC(sel("V-C3"; ratio = x), 10_000) for x in ratios]
    add!(
        "V-C2", "mean C at ratio 0 (CI) vs ratio 1 (no CI), 10⁴ MCS", "$(page_f(m[1])) vs $(page_f(m[end]))",
        "CI < no CI - 0.3", m[1] < m[end] - 0.3
    )
    low, high = mean(m[1:5]), mean(m[8:11])
    add!("V-C3", "low plateau (ratio 0–0.4)", page_f(low), "0.35 ± 0.07", abs(low - 0.35) <= 0.07)
    add!("V-C3", "high plateau (ratio 0.7–1)", page_f(high), "0.9 ± 0.07", abs(high - 0.9) <= 0.07)
    mid = page_crossing(ratios, m, (low + high) / 2)
    add!("V-C3", "midpoint", mid === nothing ? "none" : page_f(mid), "in [0.45, 0.65]", mid !== nothing && 0.45 <= mid <= 0.65)
    # V-C4
    m4(J, ci) = mC(sel("V-C4"; J_cc = J, CI = ci), 5000)
    a = (m4(20.0, true), m4(40.0, true), m4(80.0, true))
    add!(
        "V-C4", "CI: mean C at J_cc = 20, 40, 80", join(page_f.(a), ", "), "0.3, 0.4, 0.85 ± 0.1",
        abs(a[1] - 0.3) <= 0.1 && abs(a[2] - 0.4) <= 0.1 && abs(a[3] - 0.85) <= 0.1
    )
    b = (m4(0.0, false), m4(15.0, false), m4(20.0, false), m4(40.0, false))
    add!(
        "V-C4", "no CI: mean C at J_cc = 0, 15, 20, 40", join(page_f.(b), ", "), "0.35, 0.83, 0.83, 0.83 ± 0.1",
        abs(b[1] - 0.35) <= 0.1 && all(x -> abs(x - 0.83) <= 0.1, b[2:4])
    )
    rci, rno = m4(80.0, true) - m4(0.0, true), m4(40.0, false) - m4(0.0, false)
    add!(
        "V-C4", "rise from the lowest to the highest J_cc (CI; no CI)", "$(page_f(rci)); $(page_f(rno))", "> 0.3 both",
        rci > 0.3 && rno > 0.3
    )
    # V-C5
    for ((χ, ci), want) in [((0.0, true), 0.9), ((500.0, true), 0.4), ((5000.0, true), 0.2), ((0.0, false), 0.95), ((5000.0, false), 0.7)]
        got = mC(sel("V-C5"; χcM = χ, CI = ci), 5000)
        add!("V-C5", "χcM = $(Int(χ)), $(ci ? "CI" : "no CI"): mean C", page_f(got), "$want ± 0.1", abs(got - want) <= 0.1)
    end
    # V-C7
    ss = [0.0, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15, 0.175, 0.2, 0.25]
    mci = [mC(sel("V-C7"; s, CI = true), 5000) for s in ss]
    mid7 = page_crossing(ss, mci, (mci[1] + mci[end]) / 2)
    add!(
        "V-C7", "CI: transition midpoint in s", mid7 === nothing ? "none" : page_f(mid7), "in [0.07, 0.15]",
        mid7 !== nothing && 0.07 <= mid7 <= 0.15
    )
    for s in (0.0, 0.1, 0.25)
        got = mC(sel("V-C7"; s, CI = false), 5000)
        add!("V-C7", "no CI, s = $s: mean C", page_f(got), "0.95 ± 0.1", abs(got - 0.95) <= 0.1)
    end
    # V-C9
    m9(T, mode) = mC(sel("V-C9"; T, mode), 5000)
    add!("V-C9", "extension-only, T = 50: mean C", page_f(m9(50.0, "extension_only")), "> 0.85", m9(50.0, "extension_only") > 0.85)
    add!(
        "V-C9", "extension-retraction, T = 50: mean C", page_f(m9(50.0, "extension_retraction")), "< 0.5",
        m9(50.0, "extension_retraction") < 0.5
    )
    e8, r8 = m9(800.0, "extension_only"), m9(800.0, "extension_retraction")
    add!("V-C9", "both modes, T = 800: mean C (ext-only; ext-retr)", "$(page_f(e8)); $(page_f(r8))", "< 0.3 both", e8 < 0.3 && r8 < 0.3)
    # V-C12 (D-200 item 1: from MCS 0, as 01b Fig. 6E; was MCS 100)
    ci12 = mean(r -> num(r, "displacement_sites_0"), sel("V-C12"; CI = true))
    no12 = mean(r -> num(r, "displacement_sites_0"), sel("V-C12"; CI = false))
    add!("V-C12", "displacement ratio CI / no CI (MCS 0 to 19 300)", page_f(ci12 / no12), "in [1.5, 2.5]", 1.5 <= ci12 / no12 <= 2.5)
    # V-C1
    k1 = count(r -> flag(r, "network_10000"), sel("V-C1"; CI = true))
    add!("V-C1", "CI: networks at 10⁴ MCS", "$k1/5", ">= 4/5", k1 >= 4)
    k2 = count(r -> num(r, "share_10000") < 0.5, sel("V-C1"; CI = false))
    add!("V-C1", "no CI: share < 0.5 at 10⁴ MCS", "$k2/5", ">= 4/5", k2 >= 4)
    return V
end
const NCHECKS = 37
# the 2008 sweep points: (row, point label, selector, N)
function page_points()
    P = Tuple{String, String, Dict{String, Any}, Int}[]
    for x in collect(0.0:0.1:1.0)
        push!(P, ("V-C3", "ratio $x", Dict{String, Any}("ratio" => x), 10_000))
    end
    for (J, ci) in [
            (0.0, true), (20.0, true), (40.0, true), (60.0, true), (80.0, true),
            (0.0, false), (5.0, false), (10.0, false), (15.0, false), (20.0, false), (40.0, false),
        ]
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
# call a reproduction definition in the latest world (the module is built at run time)
call_latest(F, name, args...) = Base.invokelatest(Base.invokelatest(getglobal, F, name), args...)
"""Mismatches between a job's snapshot (recomputed with the reproduction's observables) and its row."""
function snapshot_problems(F, snapfile, row)
    probs = String[]
    snap = deserialize(snapfile)
    res = Dict(Int(t) => Int32.(σ) for (t, σ) in snap)
    for (t, σ) in sort(collect(res); by = first)
        nw = call_latest(F, :merks_network, σ)
        want = Dict(
            "C_$t" => call_latest(F, :merks_compactness, σ), "share_$t" => Float64(nw.share),
            "lacunae_$t" => Float64(nw.lacunae)
        )
        for (c, v) in want
            got = tryparse(Float64, get(row, c, ""))
            got == v || push!(probs, "$(basename(snapfile)): $c = $(get(row, c, "")), recomputed $v")
        end
        get(row, "network_$t", "") == string(call_latest(F, :isnetwork, nw)) ||
            push!(probs, "$(basename(snapfile)): network_$t")
    end
    if get(row, "row", "") == "V-C12"
        d = call_latest(F, :merks_displacement, res[100], res[19_300])
        tryparse(Float64, get(row, "displacement_sites", "")) == d || push!(probs, "$(basename(snapfile)): displacement_sites")
        d0 = haskey(res, 0) ? call_latest(F, :merks_displacement, res[0], res[19_300]) : nothing
        tryparse(Float64, get(row, "displacement_sites_0", "")) == d0 || push!(probs, "$(basename(snapfile)): displacement_sites_0")
    end
    return probs
end
# ---------------------------------------------------------------------------------------------
# the page
# ---------------------------------------------------------------------------------------------
const SRC = page_read(PAGE)
const LINES = split(SRC, '\n')
heading_line(re) = findfirst(l -> occursin(re, l), LINES)
const PAGE_H1 = heading_line(r"^# ## 1\.")
const PAGE_H2 = heading_line(r"^# ## 2\.")
const PAGE_H3 = heading_line(r"^# ## 3\.")
const PAGE_H4 = heading_line(r"^# ## 4\.")
# D-185 layout: the deviations section (a `# ###` subsection of §3, to the next heading) and
# the Details section (§4, to the end of the page)
const HDEV = heading_line(r"^# ### .*[Dd]eviations")
const HDEV_END = HDEV === nothing ? nothing :
    let k = findfirst(l -> occursin(r"^# ###? ", l), LINES[(HDEV + 1):end])
        k === nothing ? length(LINES) + 1 : HDEV + k
end
page_lines(a, b) = (a === nothing || b === nothing) ? "" : join(LINES[a:(b - 1)], '\n')
const DEV = page_lines(HDEV, HDEV_END)
const DETAILS = page_lines(PAGE_H4, length(LINES) + 1)
const BEGINS = findall(l -> strip(l) == BEGIN, LINES)
const ENDS = findall(l -> strip(l) == END, LINES)
const CHUNK = (length(BEGINS) == 1 && length(ENDS) == 1 && BEGINS[1] < ENDS[1]) ?
    join(LINES[(BEGINS[1] + 1):(ENDS[1] - 1)], '\n') : ""
const OUTSIDE = isempty(CHUNK) ? SRC :
    join([LINES[1:(BEGINS[1] - 1)]; LINES[(ENDS[1] + 1):end]], '\n')
function md_rows(text)
    rows = Vector{Vector{String}}()
    for l in split(text, '\n')
        s = strip(replace(l, r"^#\s?" => ""))
        (startswith(s, "|") && endswith(s, "|") && length(s) > 1) || continue
        push!(rows, [String(strip(c)) for c in split(s[2:(end - 1)], '|')])
    end
    return rows
end
issep(row) = all(c -> occursin(r"^:?-{3,}:?$", c), row)
"""Evaluate the page's FULL record chunk alone: (full_verdicts_md, full_deviation_rows) or nothing."""
function eval_chunk()
    isempty(CHUNK) && return nothing
    m = Module(:Chunk01)
    Core.eval(m, :(using PottsModels, TOML, Markdown, Statistics))
    for e in Meta.parseall(CHUNK).args
        e isa LineNumberNode && continue
        Core.eval(m, e)
    end
    (Base.invokelatest(isdefined, m, :full_verdicts_md) && Base.invokelatest(isdefined, m, :full_deviation_rows)) || return nothing
    return (Base.invokelatest(getglobal, m, :full_verdicts_md), Base.invokelatest(getglobal, m, :full_deviation_rows))
end
# ids covered by a deviations row's first cell (ranges like V-E2–V-E4 included)
function page_ids(cell)
    ids = String[]
    for mt in eachmatch(r"V-([EC])(\d+)(?:\s*[–-]\s*V-\1(\d+))?", cell)
        a = parse(Int, mt[2])
        b = mt[3] === nothing ? a : parse(Int, mt[3])
        append!(ids, ["V-$(mt[1])$k" for k in a:b])
    end
    return ids
end
# =============================================================================================
const PROV = isfile(joinpath(REC, "provenance.toml")) ? TOML.parsefile(joinpath(REC, "provenance.toml")) : Dict{String, Any}()
const PAGE_R0 = page_tsv(joinpath(REC, "replicates.tsv"))
const VC12 = page_tsv(joinpath(REC, "vc12_mcs0.tsv"))
"""Problems with `vc12_mcs0.tsv` against the replicate rows (empty when they match)."""
function vc12_problems(R, V)
    probs = String[]
    jobs = [r for r in R if get(r, "row", "") == "V-C12"]
    length(V) == length(jobs) == 20 || push!(probs, "$(length(V)) vc12_mcs0 rows for $(length(jobs)) V-C12 jobs, want 20")
    allunique(get(v, "key", "") for v in V) || push!(probs, "duplicate key in vc12_mcs0.tsv")
    byk = Dict(get(r, "key", "") => r for r in jobs)
    for v in V
        r = get(byk, get(v, "key", ""), nothing)
        r === nothing && (push!(probs, "vc12_mcs0 key $(get(v, "key", "")) is not a V-C12 job"); continue)
        for c in ("row", "seed", "CI")
            get(v, c, "") == get(r, c, "") || push!(probs, "$(v["key"]): $c")
        end
        a, b = tryparse(Float64, get(v, "displacement_sites_100", "")), tryparse(Float64, get(r, "displacement_sites", ""))
        (a !== nothing && a == b) || push!(probs, "$(v["key"]): displacement_sites_100 differs from replicates.tsv")
        tryparse(Float64, get(v, "displacement_sites_0", "")) === nothing && push!(probs, "$(v["key"]): displacement_sites_0")
    end
    return probs
end
"""The replicate rows with each V-C12 row's `displacement_sites_0` joined from `vc12_mcs0.tsv`."""
function with_vc12(R, V)
    byk = Dict(get(v, "key", "") => v for v in V)
    return [
        get(r, "row", "") == "V-C12" && haskey(byk, get(r, "key", "")) && haskey(byk[r["key"]], "displacement_sites_0") ?
            merge(r, Dict("displacement_sites_0" => byk[r["key"]]["displacement_sites_0"])) : r for r in R
    ]
end
const PAGE_R = with_vc12(PAGE_R0, VC12)
const PAGE_V = isempty(job_problems(PAGE_R)) ? page_verdicts(PAGE_R) : nothing
const VIDEOS = let f = joinpath(REC, "videos.toml")
    isfile(f) ? get(TOML.parsefile(f), "video", Any[]) : Any[]
end
const CHUNK_OUT = try
    eval_chunk()
catch e
    @info "01 merks page: the FULL record chunk does not evaluate" exception = e
    nothing
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "01 merks page (a) the FULL record and its provenance" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (a) the FULL record and its provenance" begin
        @test isdir(REC)
        prov = PROV
        commit = string(get(prov, "commit", ""))
        @test get(prov, "item", "") == "P6.3f"
        @test occursin(r"^[0-9a-f]{40}$", commit)
        @test get(prov, "dirty", true) === false
        # the launch ran the D-153 pre-registration and the D-200 amendment (V-C12 from MCS 0) the D-200
        # provenance.toml's `frozen_test_sha256` records which revision of `01_merks_tests.jl` produced
        # the run record (provenance metadata only).
        amend = get(prov, "vc12_mcs0", Dict{String, Any}())
        @test get(amend, "decision", "") == "D-200"
        @test get(amend, "new_dynamics", true) === false
        @test get(amend, "dirty", true) === false
        @test occursin(r"^[0-9a-f]{40}$", string(get(amend, "commit", "")))
        ascript = string(get(amend, "script", ""))
        @test startswith(ascript, "lib/PottsModels/reproductions/data/01/$RECNAME/") && isfile(joinpath(ROOT, ascript))
        @test !haskey(amend, "hostname") && !haskey(amend, "work")             # D-183, D-195
        for k in ("hostname", "cpu", "julia")
            @test !isempty(string(get(prov, k, "")))
        end
        @test get(prov, "threads", nothing) isa Integer
        @test get(prov, "jobs", 0) == 590
        runner = string(get(prov, "runner", ""))
        @test startswith(runner, "lib/PottsModels/reproductions/data/01/$RECNAME/") && isfile(joinpath(ROOT, runner))
        # the producing commit is in our history
        git(args...) = try
            readchomp(Cmd(`git $args`; dir = ROOT))
        catch
            nothing
        end
        shallow = git("rev-parse", "--is-shallow-repository")
        if shallow == "false" && length(commit) == 40
            @test success(Cmd(`git merge-base --is-ancestor $commit HEAD`; dir = ROOT))
            acommit = string(get(amend, "commit", ""))
            length(acommit) == 40 && @test success(Cmd(`git merge-base --is-ancestor $acommit HEAD`; dir = ROOT))
        else
            @info "01 merks page: git unavailable or shallow clone; the producing-commit ancestry check is skipped"
        end
        # only small statistics, figures and code; snapshots only under snap/; no video
        files = page_files(REC)
        @test !isempty(files)
        for f in files
            rel = relpath(f, REC)
            ok = filesize(f) <= 10 * 2^20 &&
                (any(e -> endswith(lowercase(f), e), RECORD_EXT) || (startswith(rel, "snap" * Base.Filesystem.path_separator) && endswith(f, ".jls")))
            ok || @info "01 merks page: not allowed in the record: $rel"
            @test ok
        end
        @test !any(f -> any(e -> endswith(lowercase(f), e), VIDEO_EXT), page_files(dirname(REC)))
    end
end

@testitem "01 merks page (b) replicates: every pre-registered job, once, with its parameters" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (b) replicates: every pre-registered job, once, with its parameters" begin
        @test length(JOBS) == 590 && allunique(jobkey(j...) for j in JOBS)
        probs = job_problems(PAGE_R)
        isempty(probs) || @info "01 merks page: replicate problems" probs[1:min(end, 20)]
        @test isempty(probs)
        # negative controls: a missing and a duplicated seed are caught
        if length(PAGE_R) >= 2
            @test !isempty(job_problems(PAGE_R[2:end]))
            @test !isempty(job_problems([PAGE_R[1:(end - 1)]; [PAGE_R[1]]]))
        end
        # D-200: the MCS-0 table is tied to the record's V-C12 jobs
        @test tsv_header(joinpath(REC, "vc12_mcs0.tsv"))[1:6] ==
            ["key", "row", "seed", "CI", "displacement_sites_0", "displacement_sites_100"]
        vprobs = vc12_problems(PAGE_R0, VC12)
        isempty(vprobs) || @info "01 merks page: vc12_mcs0.tsv problems" vprobs
        @test isempty(vprobs)
        if !isempty(VC12)
            bad = [
                k == 1 ? merge(v, Dict("displacement_sites_100" => string(parse(Float64, v["displacement_sites_100"]) + 1.0e-9))) : v
                    for (k, v) in enumerate(VC12)
            ]
            @test !isempty(vc12_problems(PAGE_R0, bad))
            @test !isempty(vc12_problems(PAGE_R0, VC12[2:end]))
        end
    end
end

@testitem "01 merks page (c) snapshot oracle: the reproduction's observables recompute the rows" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (c) snapshot oracle: the reproduction's observables recompute the rows" begin
        F = merks_module()
        # the reproduction's definitions loaded: a filled 10 × 10 square on a framed 20² gives C = 100/81
        σ = zeros(Int32, 20, 20); σ[[1, 20], :] .= 1; σ[:, [1, 20]] .= 1; σ[5:14, 5:14] .= 2
        @test call_latest(F, :merks_compactness, σ) ≈ 100 / 81
        byk = Dict(get(r, "key", "") => r for r in PAGE_R)
        snaps = filter(f -> endswith(f, ".jls"), page_files(joinpath(REC, "snap")))
        keys_ = [splitext(basename(f))[1] for f in snaps]
        rows_ = [get(get(byk, k, Dict{String, String}()), "row", "") for k in keys_]
        @test any(in(("V-E1", "V-E5", "V-E6")), rows_)
        @test any(startswith("V-C"), rows_)
        @test sum(filesize, snaps; init = 0) <= 4 * 2^20
        for (f, k) in zip(snaps, keys_)
            @test haskey(byk, k)
            haskey(byk, k) || continue
            probs = snapshot_problems(F, f, byk[k])
            isempty(probs) || @info "01 merks page: snapshot mismatch" probs
            @test isempty(probs)
        end
        # negative control: an edited value is caught
        if !isempty(snaps) && haskey(byk, keys_[1])
            r = copy(byk[keys_[1]])
            c = first(filter(k -> startswith(k, "C_") && !isempty(r[k]), collect(keys(r))))
            r[c] = string(parse(Float64, r[c]) + 1.0e-9)
            @test !isempty(snapshot_problems(F, snaps[1], r))
        end
        # opt-in: every job's snapshots (kept on the PC)
        alld = get(ENV, "SNAPSHOTS", "")
        if isdir(alld)
            all_snaps = filter(f -> endswith(f, ".jls"), page_files(alld))
            @test length(all_snaps) == count(j -> j[1] != "V-E10", JOBS)
            for f in all_snaps
                k = splitext(basename(f))[1]
                @test haskey(byk, k) && isempty(snapshot_problems(F, f, byk[k]))
            end
        else
            @info "01 merks page: SNAPSHOTS not set; only the committed snapshots are checked"
        end
    end
end

@testitem "01 merks page (d) verdicts: the FULL rules applied to the record" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (d) verdicts: the FULL rules applied to the record" begin
        @test PAGE_V !== nothing
        if PAGE_V !== nothing
            @test length(PAGE_V) == NCHECKS
            @info "01 merks page: FULL verdicts recomputed from replicates.tsv" PAGE_V
            vt = page_tsv(joinpath(REC, "verdicts.tsv"))
            @test tsv_header(joinpath(REC, "verdicts.tsv"))[1:5] == ["row", "check", "ours", "rule", "result"]
            @test length(vt) == length(PAGE_V)
            for (k, v) in enumerate(PAGE_V)
                t = k <= length(vt) ? vt[k] : Dict{String, String}()
                ok = all(get(t, string(c), nothing) == getfield(v, c) for c in (:row, :check, :ours, :rule, :result))
                ok || @info "01 merks page: verdicts.tsv row $k differs" want = v got = t
                @test ok
            end
            # negative controls: the rules move with the data
            lowpass(R, x) = [
                r["row"] == "V-C3" && parse(Float64, r["ratio"]) <= 0.4 ?
                    merge(r, Dict("C_10000" => string(x))) : r for r in R
            ]
            vlow(R) = only(filter(v -> v.check == "low plateau (ratio 0–0.4)", page_verdicts(R))).result
            @test vlow(lowpass(PAGE_R, 0.35)) == "PASS"
            @test vlow(lowpass(PAGE_R, 0.55)) == "FAIL"
            # V-C12 on the old MCS-100 axis fails (D-184's 1.26), on the paper's MCS-0 axis it does not
            old12 = [r["row"] == "V-C12" ? merge(r, Dict("displacement_sites_0" => r["displacement_sites"])) : r for r in PAGE_R]
            v12(R) = only(filter(v -> v.row == "V-C12", page_verdicts(R)))
            @test v12(old12).result == "FAIL" && v12(old12).ours == "1.26"
            flip = [r["row"] == "V-C1" && r["CI"] == "true" ? merge(r, Dict("network_10000" => "false")) : r for r in PAGE_R]
            @test only(filter(v -> v.check == "CI: networks at 10⁴ MCS", page_verdicts(flip))).result == "FAIL"
        end
        # both clocks for the 2008 sweeps (D-153 M6)
        pt = page_tsv(joinpath(REC, "points.tsv"))
        P = page_points()
        @test length(pt) >= length(P)
        for (row, label, meta, N) in P
            rs = filter(r -> r["row"] == row && all(val_eq(get(r, c, ""), v) for (c, v) in meta), PAGE_R)
            t = findfirst(x -> get(x, "row", "") == row && get(x, "point", "") == label, pt)
            @test t !== nothing && length(rs) == 10
            (t === nothing || length(rs) != 10) && continue
            for (col, tt) in (("mean_C_N", N), ("mean_C_N+100", N + 100))
                got = tryparse(Float64, get(pt[t], col, ""))
                @test got !== nothing && abs(got - mean(r -> num(r, "C_$tt"), rs)) <= 5.0e-5
            end
        end
    end
end

@testitem "01 merks page (e) videos: per-cell release assets of record replicates" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (e) videos: per-cell release assets of record replicates" begin
        @test !isempty(VIDEOS)
        keys_ = Set(get(r, "key", "") for r in PAGE_R)
        for v in VIDEOS
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
            @test occursin(RELEASES * tag * "/" * file, SRC)
        end
        listed = Set(RELEASES * string(get(v, "tag", "")) * "/" * string(get(v, "file", "")) for v in VIDEOS)
        for mt in eachmatch(r"https://github\.com/[^\s\"'()<>\[\]`]*01_merks_full[^\s\"'()<>\[\]`]*\.mp4", SRC)
            ok = mt.match in listed
            ok || @info "01 merks page: page video not in videos.toml: $(mt.match)"
            @test ok
        end
    end
end

@testitem "01 merks page (f) the page renders the record (its FULL record chunk)" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (f) the page renders the record (its FULL record chunk)" begin
        @test length(BEGINS) == 1 && length(ENDS) == 1 && !isempty(CHUNK)
        @test HDEV !== nothing && !isempty(BEGINS) && BEGINS[1] < HDEV
        @test occursin(RECNAME, CHUNK)
        @test !occursin(r"\bsolve\(|PottsProblem|\brun0[68]\(|\bwalk\(", CHUNK)
        @test CHUNK_OUT !== nothing
        vmd, devrows = CHUNK_OUT === nothing ? ("", String[]) : CHUNK_OUT
        @test vmd isa AbstractString && devrows isa AbstractVector{<:AbstractString}
        # the verdict table
        rows = md_rows(vmd)
        @test length(rows) >= 3 && issep(rows[2])
        head = isempty(rows) ? String[] : lowercase.(rows[1])
        col(name) = findfirst(h -> occursin(name, h), head)
        ct, co, cc, cr = col("target"), col("ours"), col("class"), col("result")
        @test all(!isnothing, (ct, co, cc, cr))
        if PAGE_V !== nothing && all(!isnothing, (ct, co, cc, cr))
            body = rows[3:end]
            for v in PAGE_V
                ok = any(
                    r -> length(r) == length(head) && startswith(r[ct], "$(v.row) $(v.check)") && r[co] == v.ours &&
                        r[cc] == "FULL record" && r[cr] == v.result, body
                )
                ok || @info "01 merks page: no page verdict row for $(v.row) $(v.check) = $(v.ours) $(v.result)"
                @test ok
            end
        end
        # the deviation rows for every FAIL
        drows = [md_rows(r) for r in devrows]
        @test all(d -> length(d) == 1, drows)
        drows = [only(d) for d in drows if length(d) == 1]
        for d in drows
            @test length(d) == 5
            length(d) == 5 || continue
            @test !isempty(d[4]) && d[4] ∉ ("—", "-")
            @test occursin(r"^(not an author question|not asked)", lowercase(d[5]))
        end
        if PAGE_V !== nothing
            for v in filter(v -> v.result == "FAIL", PAGE_V)
                key = v.row == "V-C3" && startswith(v.check, "low plateau") ? "V-C3 low plateau" : v.row
                ok = any(d -> length(d) == 5 && occursin(key, d[1]) && occursin("FAIL", d[1]) && occursin(v.ours, d[2]), drows)
                ok || @info "01 merks page: failing check without a deviations row: $(v.row) $(v.check) = $(v.ours)"
                @test ok
            end
        end
        # shown on the page
        @test occursin("full_deviation_rows", DEV)
        @test occursin("full_verdicts_md", DETAILS) && occursin("Markdown.parse", DETAILS)
        @test occursin("points.tsv", SRC)
    end
end

@testitem "01 merks page (g) deviations table: rows, provisional defaults, parked targets" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (g) deviations table: rows, provisional defaults, parked targets" begin
        rows = md_rows(DEV)
        @test !isempty(rows)
        isempty(rows) && (rows = [String[""]])
        h = lowercase(join(rows[1], " | "))
        @test occursin("ours", h) && occursin("paper", h) && occursin("cause", h) && occursin("author question", h)
        body = [r for r in rows[2:end] if !issep(r)]
        first_cells = [r[1] for r in body]
        has(re) = any(c -> occursin(re, c), first_cells)
        @test any(c -> occursin("target length L", c) && occursin("provisional", c), first_cells)
        @test any(r -> occursin("target length L", r[1]) && occursin("50", join(r, "|")) && occursin("60", join(r, "|")), body)
        @test any(c -> occursin("classification time", c) && occursin("provisional", c), first_cells)
        @test any(r -> occursin("classification time", r[1]) && occursin("48 h", join(r, "|")), body)
        for key in (
                "2006 connectivity E₀", "2006 seeding", "2008 time origin", "01b Fig. 2 set-up", "Field scheme",
                "ΔH arithmetic", "χ(c,c)", "Parameter sets", "2008 seeding", "Border", "Copy proposal", "Compactness",
            )
            ok = has(key)
            ok || @info "01 merks page: deviations row missing: $key"
            @test ok
        end
        parked = Set(id for c in first_cells if occursin("PARKED", c) for id in page_ids(c))
        for id in ("V-E2", "V-E3", "V-E4", "V-E7", "V-E8", "V-E9", "V-C6", "V-C8", "V-C10", "V-C11")
            ok = id in parked
            ok || @info "01 merks page: parked target without a row: $id"
            @test ok
        end
        # D-200 item 2: attempts per MCS is a deviation (the target is the paper's N = number of
        # lattice sites, 200² on the lattice of the 01b parameter files)
        att = filter(r -> occursin(r"attempts"i, r[1]), body)
        @test length(att) == 1
        if length(att) == 1
            t = join(att[1], "|")
            @test occursin("39 204", t) && occursin("40 000", t) && occursin("2 %", t) && occursin("The paper is the target", t)
        end
        @test !any(r -> occursin(r"pending|at risk"i, join(r, "|")), body)
        for r in body
            s = last(r)
            ok = occursin(r"^(not an author question|not asked)"i, s) || startswith(s, "\$(aq(")
            ok || @info "01 merks page: bad author-question status: $s"
            @test ok
        end
        aqdef = match(r"aq\(item\)\s*=\s*\"([^\"]*)\"", SRC)
        @test aqdef !== nothing && startswith(aqdef[1], "not asked") && occursin("open question list", aqdef[1])
    end
end

@testitem "01 merks page (h) banner and text" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (h) banner and text" begin
        head = PAGE_H1 === nothing ? "" : join(LINES[1:(PAGE_H1 - 1)], '\n')
        commit = string(get(PROV, "commit", ""))
        @test occursin(RECNAME, head)
        @test length(commit) >= 8 && occursin(commit[1:8], head)
        names = String[]
        cpu = string(get(PROV, "cpu", ""))
        isempty(cpu) || push!(names, lowercase(strip(first(split(cpu, " w/")))))
        host = string(get(PROV, "hostname", ""))
        isempty(host) || push!(names, lowercase(host))
        @test any(n -> occursin(n, lowercase(head)), names)
        for re in (r"pending (the )?full run"i, r"no full run has been made"i, r"full-run outputs[^.]*pending"i)
            @test !occursin(re, SRC)
        end
        @test occursin("39 204", SRC) && occursin("(sizex − 2)(sizey − 2)", SRC)
        @test occursin("MCS after relaxation", SRC) && occursin("code MCS", SRC)
        for re in (r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i, r"docs/references"i)
            @test !occursin(re, SRC)
        end
        log = filter(r -> length(r) >= 2 && occursin(r"^\d{4}-\d\d-\d\d$", r[1]), md_rows(SRC))
        @test any(r -> r[1] >= "2026-10-08" && occursin(RECNAME, join(r, "|")), log)
    end
end

@testitem "01 merks page (i) rendering: per-cell colours, no outlines" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (i) rendering: per-cell colours, no outlines" begin
        @test !isempty(SRC)
        @test !occursin(r"boundaries\s*=\s*true", SRC)
        @test !occursin("pottsboundaries", SRC)
        @test !occursin("ChannelEncoding", SRC)
        # each call's text: from the name to its closing parenthesis
        function calls(name)
            out = String[]
            for mt in eachmatch(Regex("\\b" * name * "\\("), OUTSIDE)
                i, depth = mt.offset + length(name), 0
                j = i
                while j <= lastindex(OUTSIDE)
                    c = OUTSIDE[j]
                    c == '(' && (depth += 1)
                    c == ')' && (depth -= 1; depth == 0 && break)
                    j = nextind(OUTSIDE, j)
                end
                push!(out, OUTSIDE[mt.offset:min(j, lastindex(OUTSIDE))])
            end
            return out
        end
        rp = calls("record_potts")
        @test !isempty(rp)
        for c in rp
            ok = occursin(r"encoding\s*=\s*CellIdentityEncoding\(\)", c)
            ok || @info "01 merks page: record_potts without per-cell colours: $(first(c, 120))"
            @test ok
        end
        for c in calls("pottsplot")
            @test occursin(r"CellIdentityEncoding|CellTypeEncoding", c)
        end
    end
end

@testitem "01 merks page (j) the page parses and is rendered by the docs (build opt-in)" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (j) the page parses and is rendered by the docs (build opt-in)" begin
        parsed = isempty(SRC) ? nothing : Meta.parseall(SRC)
        bad(ex) = ex isa Expr && (ex.head in (:error, :incomplete) || any(bad, ex.args))
        @test parsed !== nothing && !bad(parsed)
        make = page_read(MAKE)
        @test occursin(r"readdir\(REPRODUCTIONS\)", make) && occursin("Literate.markdown(joinpath(REPRODUCTIONS", make)
        if get(ENV, "POTTS_DOCS_BUILD", "false") == "true"
            cmd = addenv(`$(Base.julia_cmd()) --project=docs docs/make.jl`, "POTTS_DOCS_PUBLISHED" => "true")
            @test success(pipeline(Cmd(cmd; dir = ROOT); stdout = stdout, stderr = stderr))
            built = joinpath(ROOT, "docs", "build", "published", "01_merks", "index.html")
            @test isfile(built)
            html = page_read(built)
            if PAGE_V !== nothing
                for v in PAGE_V
                    @test occursin(v.ours, html)
                end
            end
            for v in VIDEOS
                @test occursin(RELEASES * string(get(v, "tag", "")) * "/" * string(get(v, "file", "")), html)
            end
        else
            @info "01 merks page: POTTS_DOCS_BUILD not set; the Documenter build is skipped"
        end
    end
end

@testitem "01 merks page (k) layout: intro, model, minimal run, results, collapsed Details" setup = [MerksPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "01 merks page (k) layout: intro, model, minimal run, results, collapsed Details" begin
        hs = [PAGE_H1, PAGE_H2, PAGE_H3, PAGE_H4]
        @test all(!isnothing, hs)
        all(!isnothing, hs) && @test issorted(hs) && allunique(hs)
        for k in 1:4
            @test count(l -> startswith(l, "# ## $(k)."), LINES) == 1
        end
        @test PAGE_H4 !== nothing && occursin("Details", LINES[PAGE_H4])
        @test HDEV !== nothing && PAGE_H3 !== nothing && PAGE_H4 !== nothing &&
            PAGE_H3 < HDEV && HDEV_END <= PAGE_H4
        @test occursin("<details>", DETAILS) && occursin("</details>", DETAILS)
        o, c = findfirst("<details>", DETAILS), findlast("</details>", DETAILS)
        @test o !== nothing && c !== nothing && first(o) < first(c)
        before = PAGE_H4 === nothing ? "" : page_lines(1, PAGE_H4)
        for v in VIDEOS
            @test occursin(RELEASES * string(get(v, "tag", "")) * "/" * string(get(v, "file", "")), before)
        end
        for re in (r"\bContact:"i, r"contact us"i, r"\be-?mail\b"i)
            @test !occursin(re, SRC)
        end
    end
end
