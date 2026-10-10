# P6.15m m4 (ROADMAP; D-214, D-215 (9), D-218, D-220, D-221): the second OpenVT entry,
# "Potts.jl (checkerboard)", in the submission package, its e-mail split and page 15.
# Frozen (AUTONOMY §7.3) once committed by the coordinator; the test author writes no
# implementation. This file ADDS to the frozen `15_openvt_package.jl`, `15_openvt_d213.jl`,
# `15_openvt_page.jl`, `15_openvt_d211.jl` and `15_openvt_checkerboard.jl`, which stay
# unchanged and green: the generator's DEFAULT build stays the sequential-only package they
# pin (its `readdir(implementations) == ["Potts.jl"]` and its split's single-token roots).
#
# Sources: spec 15 §1.3 (two entries, placement directly after each Potts.jl slot, tokens,
# colours), §3.1 (O1–O6 formats), §4.0.1 (the email split), §4.0.2 (colours), §7 Q27;
# D-213 (the split), D-214 (the second entry; its own folder, colour, legend line, results
# folder; the email package gains it once P6.15m lands), D-215 (G conformance: O1 x,y,i,n,g,
# header R, O2/O5 names, zip stems, Table 1 CSV, token `Potts.jl_checkerboard`, colour key
# `PottsJLcheckerboard`, the checkerboard implementation folder = README + runner pointing
# to `implementations/Potts.jl/src`), D-217 (the split's API and EMAIL.md rules), D-219 (no
# Q28; no questions about how other frameworks run their benchmarks), D-220 (the entry runs
# on its own calibrated T: cycle 5·T_cb = 870 MCS, α = 50/870), D-221 (the 4-vs-64-colour
# contrast; "6 colours on the chain, 4 on the monolayer" disclosed).
#
# Tokens (constants below; nothing else spells them): <FW> = "Potts.jl" (sequential),
# <CB> = "Potts.jl_checkerboard" (folder and file token), <LABEL> = "Potts.jl (checkerboard)"
# (legend and banner text), colour key `PottsJLcheckerboard`, Q27 proposal RGB 0,109,44.
#
# ---------------------------------------------------------------------------------------------
# API required of the implementer (PottsModels; not exported)
# ---------------------------------------------------------------------------------------------
#   PottsModels.OPENVT_CHECKERBOARD_TOKEN :: String == "Potts.jl_checkerboard"
#   PottsModels.OPENVT_ENTRIES == (PottsModels.OPENVT_FRAMEWORK_TOKEN, PottsModels.OPENVT_CHECKERBOARD_TOKEN)
#   PottsModels.openvt_submission_package(outdir; bulk, allow_pending, split, release_tag,
#                                         entries = (PottsModels.OPENVT_FRAMEWORK_TOKEN,))
# `entries` lists the entries to build, by token. Accepted: exactly the sequential entry
# (the default; byte-for-byte today's package) or both entries, in either order (the
# build order is always sequential first). Anything else (the checkerboard entry alone,
# since its implementation folder points into the sequential one; an unknown token; a
# duplicate; an empty list) is an `ArgumentError` whose message contains "entries", raised
# FIRST, before the records, the bulk directory or the output directory are looked at, so
# nothing is written. Every other keyword keeps its meaning; `split = :email` composes with
# `entries`.
#
# The checkerboard entry is built from two committed records (D-146):
#   CB record  the latest `data/15/checkerboard-<YYYY-MM-DD>/` with meta status "final" (else
#              the latest), as `15_openvt_checkerboard.jl` picks it (today
#              checkerboard-2026-10-10: cases a, b, f; the λ = 2 chain calibration;
#              entry/deviations.tsv);
#   O1 record  the latest `data/15/o1cb-<YYYY-MM-DD>/` whose provenance `source` is the CB
#              record's directory name (see "The checkerboard O1 record" below).
#
# ---------------------------------------------------------------------------------------------
# Decision: m4 PRODUCES the checkerboard O1 files (a GPU replay), it does not list them as
# missing. The CB record holds no per-cell O1 files: only stop-frame summaries
# (metrics.tsv O1.*) and per-save N, r, A, C, w, g. O1 is the one output the manuscript
# itself prescribes (DATA COLLECTION, C8), and the consortium's own pipeline
# (run_metrics.sh → metrics.cpp) derives the Figure 9 measurements from it, so an entry
# without O1 cannot be processed by G's scripts and is not a submission. The cost is small:
# the CB record's GPU time for a, b, f was 141 + 367 + 358 s (provenance runs_gpu_s), plus
# frame extraction every 39 MCS; the zips are ~0.2–0.3 GB in all (the sequential a, b, f zips
# are 87, 70 and 54 MB), far below 2 GB each. The replay reruns every CB seed of a, b, f with
# the CB record's protocol on the PC's GPU (ROCm, no host-planner fallback) and must stop at
# the CB record's MCS with its N (the D-218 replay rule). O2 (Figure 5), the β/γ sweeps
# (O3, Table 1, Figures 6–8, O5), case (e), the 11+10 chain and λ = 1, 3, 5 remain NOT
# produced for this entry, as the coordinator scoped m4, and are listed as such.
#
# ---------------------------------------------------------------------------------------------
# The checkerboard O1 record: data/15/o1cb-<YYYY-MM-DD>/ (item "P6.15m"; the page test's (g)
# rules: .tsv/.csv/.toml/.md/.jl/.png/.svg only, none over 10 MiB)
# ---------------------------------------------------------------------------------------------
#   provenance.toml  item = "P6.15m"; source = the CB record's directory name; commit (40
#                    hex); dirty_tracked = false; runner = the repository path of a runner
#                    inside this directory (it exists), runner_sha256 = its sha256; julia,
#                    machine, cpu; framework = <LABEL>; folder_token = <CB>; algorithm
#                    (contains "CheckerboardCPM"); backend (AMDGPU|ROCm|ROCBackend); device
#                    (non-empty); host_planner_fallback = false (Bool); no `hostname`
#   archives.tsv     case archive members bytes sha256: exactly one row per case a, b, f,
#                    archive = <CB>_beta0.0_gamma0.0.zip (a), <CB>_No_CI_stochastic.zip (b),
#                    <CB>_No_CI_deterministic.zip (f) (D-215 (5) stems with <CB>), members =
#                    that case's manifest rows; no O2 row (O2 is not produced)
#   o1_manifest.tsv  case seed mcs file rows bytes i0 i1 i2 i3 sha256 (the o1g record's
#                    header), one row per O1 file, file = <stem>/s<seed>/potts_<case>_s<seed>_
#                    <MCS:06d>.csv; per case exactly the CB record's runs.tsv seeds; per seed
#                    exactly the MCS values of the CB record's timeseries.tsv (every save), with
#                    rows = that save's N; the largest MCS = runs.tsv's mcs and its rows =
#                    runs.tsv's N (the replay equals the characterised run); i0+…+i3 = rows,
#                    and i0 = rows (β = γ = 0: no cell is ever inhibited)
#   neighbors.tsv    case seed n count (the P6.15f record's header): the stop frame's
#                    neighbour-number histogram per run; Σ count = runs.tsv's N per seed
#   README.md        what was run and how the files relate to the bulk zips
# The bulk directory OPENVT_PACKAGE_BULK holds the three zips under their archive names
# with the pinned size and sha256 (as for the sequential zips, D-204). Inside each zip:
# members sorted by path, no directory entries, each member's bytes = the manifest's bytes
# and sha256; header x,y,i,n,g; g = 1 if i == 0 else 0; one row per live cell.
#
# ---------------------------------------------------------------------------------------------
# The two-entry package (entries = both; bulk tier)
# ---------------------------------------------------------------------------------------------
# U2 = openvt_submission_package(out; entries = (<FW>, <CB>)) writes implementations/{<FW>,
# <CB>}/ and results/{<FW>, <CB>}/ and nothing else.
#   Regression (item 4). U1 = the default build. U2's <FW> subtrees hold exactly U1's files,
#   byte-identical, except implementations/<FW>/README.md and results/<FW>/README.md, which
#   may differ (they may name the second entry): "files that list both entries".
#   implementations/<CB>/ holds exactly
#     README.md        names <LABEL>, `CheckerboardCPM`, the GPU backend (ROCm or AMDGPU), the
#                      shared model by its path `implementations/<FW>/src` (no model copy
#                      here), the cycle 870 MCS, each record's 8-hex commit and runner path
#                      `scripts/<record>/<runner>`, the MIT line
#     parameters.csv   name,value,unit: the sequential parameters.csv's names and values,
#                      except alpha = A0/870 (≈ 0.0574713), cycle_MCS = 870,
#                      T_relax_lambda2_MCS = 174 and algorithm containing "CheckerboardCPM";
#                      extra rows allowed (e.g. backend, colours)
#     scripts/<record>/<name>.jl  byte copies of the CB and O1 records' .jl files (each
#                      record's provenance runner at least; scripts that read a consortium
#                      clone, OPENVT_MONOLAYER_REPO, may be left out)
#   results/<CB>/ holds exactly (nothing else: no closeup.png, figures/, 11+10cells/, O2,
#   O3, O5, Table 1):
#     README.md
#     provenance/<record>.toml   for the CB and O1 records: the record's provenance.toml
#                                without `hostname` and `work`
#     Relaxation/11cells/width.csv and Relaxation/lambda_scan/11cells_lambda2_width.csv:
#                      `Normalized time (T),Mean Tissue width (CD),STD Tissue width (CD)`, the
#                      CB record's timeseries_11chain.tsv λ = 2 rows (t_over_T is in T_cb)
#     Relaxation/table_S5.csv    `lambda,T (MCS),MSE`, one row: 2, T_lambda2 (174), the MSE of
#                      the mean curve against the spring–dashpot reference of the sequential
#                      calibration record (`Analysis.relaxation_mse`, t_mcs ≥ 0, T = T_cb):
#                      this entry's Relaxation/T(λ = 2) row
#     Monolayer/metrics/<c>/measurements_s<seed>.csv  c = a, b, f, every runs.tsv seed:
#                      `MCS,t,N,R,A,C,w,g` with t = MCS/870, the CB record's timeseries rows
#     Monolayer/metrics/measurements_<c>_mean.csv      `MCS,t,N,R,A,C,w,g,runs` on the
#                      39-MCS saves every run reached, NaN skipped (as the sequential means)
#     Monolayer/metrics/neighbors_<c>.csv              `n,p`, pooled from the O1 record's
#                      neighbors.tsv, p in %
#     Monolayer/metrics/a/inhibition_s<seed>.csv       A3 of case (a): `MCS,t,f0,f1,f2,f3`
#                      from the O1 manifest, t = MCS/870
#     Monolayer/<stem>.zip (3)   byte copies of the bulk zips
#     Monolayer/<CB>_centroids_manifest.csv  `archive,file,rows,bytes,sha256`, the O1
#                      manifest in case then file order
#   results/<CB>/README.md:
#     - the first heading names <LABEL>; the legend text <LABEL>, the colour key
#       `PottsJLcheckerboard` and RGB 0,109,44 (Q27, "our open question list");
#     - the units: R; t in cycles of 870 MCS (5T); T(λ = 2) = 174 MCS against the sequential
#       156; α = 50/870; the record's z to two decimals. Every line naming 775 also says
#       "sequential" (the cycle is 870 wherever the sequential entry says 775);
#     - the cases and seeds (each case's seed text from the CB record's meta);
#     - a level-2 section whose heading says "not produced" that names: O2 and Figure 5;
#       O3, Figure 6 and Table 1; O5, Figure 7 and Figure 8; case (e); the 11+10 chain;
#       λ = 1, 3, 5; closeup.png and Figure 1 ("not produced for this entry", not omitted);
#     - the characterisation: "<flagged> of <rows>" from comparison.tsv; the cause: thinning
#       of conflicting accepted copies (D-008 claims), ~27 % commit, the 64-colour contrast
#       (D-221) and "6 colours on the chain, 4 on the monolayer";
#     - a deviations table (header: Ours, a sequential/Potts.jl reference column, cause,
#       Author question) with one row per entry/deviations.tsv row: first cell = the metric
#       id and "(<case>)", the row holds the first decimal of `ours` and of `paper`, the
#       cause's leading clause (before ':'), and a status starting as the record's;
#     - the D-215 (8) notes N1–N6 with <CB> (N5 names the folder <CB>, N6 the path
#       results/<CB>/Monolayer/); the MIT line;
#     - no "?", no Q19/Q20/Q21/Q25/Q28, nothing private (the package test's lists).
#
# The two-entry split S2 = openvt_submission_package(out; split = :email, entries = both):
#   core.zip ≤ 20 000 000 B; members under the four roots; every non-bulk U2 file exactly
#   once at its U2 path, byte-identical (README*.md excepted; new README*.md allowed);
#   bulk/ = U2's bulk files of both entries (the sequential cases + 2, the three <CB> zips
#   and the <CB> manifest), byte-identical, each < 2 000 000 000 B; the core's
#   results/<CB>/README.md links every <CB> bulk file by name, sha256 and release URL;
#   the return value's core_bytes and bulk_bytes are the sizes. Two builds: same bytes.
#   EMAIL.md (plain text, the D-217 rules) describes both entries: core.zip attached; every
#   bulk file of both entries named with its URL; "775 MCS" for the sequential entry and,
#   in a paragraph naming the checkerboard entry, "870 MCS", 174 and 156; the cause summary
#   (a paragraph naming the checkerboard with "thinning" or "conflicting" and "claim") and
#   the number of its deviation rows; the legend <LABEL>, `PottsJLcheckerboard`,
#   0,109,44; both folder names and both Monolayer paths (N5, N6); Q15 and Q26 as before;
#   every sequential FAIL row id. No "?" (D-219: no questions on how other frameworks
#   run their benchmarks; Q27 is offered as a proposal, not asked), no "compiler", no
#   Q19/Q20/Q21/Q25/Q28, nothing private.
#
# ---------------------------------------------------------------------------------------------
# Page 15 (always; reads the Literate source)
# ---------------------------------------------------------------------------------------------
#   - a level-3 heading naming <LABEL> in Results, after the level-3 "Deviations" heading and
#     before "## 4. Details" (so the frozen page test's order and its Deviations-section
#     rules are untouched); its section (to the next heading of level ≤ 3) names the CB
#     record directory, its 8-hex commit and machine; the time scale (174, 156, "870 MCS",
#     "50/870", z to 2 dp); the comparison summary "<flagged> of <rows>"; a deviations table
#     as in the README (the cause cell may be the leading clause only: the long text once in
#     prose); the cause text (thinning, claim, 27 %, D-008, D-220, D-221, 64 colours, "6
#     colours on the chain", "4 on the monolayer", "not a bug"); no "pending";
#   - figure slots that have data, each placed DIRECTLY after the Potts.jl slot (spec §1.3):
#     in the Figure 2 section the record_figure call after (calibration, fig2_bde.png) is
#     (CB, fig2.png); in the Figures 3 and 9 section (f3-f8, fig3.png) is followed by
#     (CB, fig3.png) and (f3-f8, fig8.png) by (CB, fig9.png); no other CB record_figure on
#     the page (no data for Figures 1, 4–8). Those sections name <LABEL>. The Table S5
#     section names <LABEL>, the CB record and 174. The page asserts the CB record's commit
#     (`record("<CB record>"; commit = "<8 hex>")`);
#   - the renders fig2.png, fig3.png and fig9.png sit in the CB record (PNG, ≤ 10 MiB), each
#     named in a plot_*.jl script of the record;
#   - no "Q28" and nothing private (the package test's list, the repository URL aside).
#
# Tiers. always: the API's shape and refusals, the O1 record, the renders, page 15.
# bulk (OPENVT_PACKAGE_BULK set; else a clean skip): the four builds (U1, U2, S2 twice), the
# archives against the O1 record, every check above. Nothing here contacts anyone.
using Test, TOML, SHA, Printf, PottsModels

const P615N_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const P615N_DATA = joinpath(P615N_ROOT, "lib", "PottsModels", "reproductions", "data", "15")
const P615N_PAGE = joinpath(P615N_ROOT, "lib", "PottsModels", "reproductions", "15_openvt_monolayer.jl")
const P615N_BULK_ENV = "OPENVT_PACKAGE_BULK"
const P615N_BULK = get(ENV, P615N_BULK_ENV, "")
const P615N_HAVE_BULK = !isempty(P615N_BULK) && isdir(P615N_BULK)
const P615N_CORE_MAX = 20_000_000
const P615N_BULK_MAX = 2_000_000_000
const P615N_RELEASE_BASE = "https://github.com/PraneethMerugu/Potts.jl/releases/download/"

# tokens (D-214, D-215 (9)); nothing below spells them except through these
const P615N_FW = "Potts.jl"
const P615N_CB = "Potts.jl_checkerboard"
const P615N_LABEL = "Potts.jl (checkerboard)"
const P615N_KEY = "PottsJLcheckerboard"
const P615N_RGB = r"0,\s*109,\s*44"
const P615N_BOTH = (P615N_FW, P615N_CB)

const P615N_CASES = ["a", "b", "f"]
const P615N_STEM = Dict("a" => "$(P615N_CB)_beta0.0_gamma0.0", "b" => "$(P615N_CB)_No_CI_stochastic",
    "f" => "$(P615N_CB)_No_CI_deterministic")
const P615N_SEQ_CAL = "calibration-2026-10-05"
const P615N_SEQ_F3F8 = "f3-f8-2026-10-08"
const P615N_T_SEQ = 156
const P615N_RENDERS = ["F2" => "fig2.png", "F3" => "fig3.png", "F9" => "fig9.png"]
const P615N_RECORD_EXT = (".tsv", ".csv", ".toml", ".md", ".jl", ".png", ".svg")
const P615N_H_WIDTH = "Normalized time (T),Mean Tissue width (CD),STD Tissue width (CD)"
const P615N_H_S5 = "lambda,T (MCS),MSE"
const P615N_H_MEAS = "MCS,t,N,R,A,C,w,g"
const P615N_H_O1M = ["case", "seed", "mcs", "file", "rows", "bytes", "i0", "i1", "i2", "i3", "sha256"]
const P615N_GRID = 39
const P615N_STATUS = r"^(not an author question|not asked|resolved)"i
const P615N_CLOSED_Q = r"\bQ(19|20|21|25|28)\b"

# the package test's privacy and no-contact list, and the cover note's (15_openvt_d213.jl)
const P615N_FORBIDDEN = [
    r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i,
    r"docs/references"i, r"POTTS_REFERENCES", r"manuscript-draft"i,
    r"correspondence"i, r"\be-?mails?\b"i, r"\basked on\b"i, r"\bwe (have )?(asked|wrote|sent|contacted|emailed)\b"i,
    r"\bcontacted (the|R\.|Dr)"i, r"\banswered by\b"i, r"personal communication"i,
    r"\bletters? (to|from)\b"i, r"\bsubmitted to\b"i,
    r"praneeth"i, r"merugu"i, r"jiang"i, r"\bPI\b", r"nucbox"i, r"tailscale"i, r"100\.107\.",
    r"/Users/", r"/home/", r"/private/", r"/tmp/", r"\.claude", r"scratchpad"i,
]
const P615N_EMAIL_FORBIDDEN = [
    r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}",
    r"vetter"i, r"\b(Dr|Prof|Mr|Ms|Mrs)\.?\s+[A-Z]",
    r"\b\d{1,3}(\.\d{1,3}){3}\b", r"\.local\b"i, r"\.lan\b"i, r"\bhostname\b"i, r"localhost"i,
    r"/Volumes/", r"/var/", r"/opt/", r"/mnt/", r"~/", r"\$HOME", r"\b[A-Za-z]:\\(?=\w)", r"potts-bulk"i,
    r"\b(has|have|had|was|were|is|are)\s+(already\s+)?(been\s+)?(sent|e-?mailed|mailed|forwarded|delivered|submitted)\b"i,
    r"\bas (we )?(discussed|agreed|promised|requested)\b"i, r"\b(our|your) (previous|earlier|last) (message|mail|note|exchange|call|meeting)\b"i,
    r"\bthank(s| you) for (your|the) (reply|response|message|answer|note)\b"i, r"\bin (reply|response) to\b"i,
    r"\bfollow(ing)?[- ]up\b"i, r"\bper (your|our)\b"i,
]
# D-219: no questions to the consortium about how frameworks run their benchmarks
const P615N_NO_QUESTIONS = [r"\?", r"compiler"i, r"\b(could|would|can|do|does|did) (you|the consortium|the other frameworks)\b"i,
    r"\bplease (let us know|confirm|advise|tell)\b"i]

# ---- helpers ------------------------------------------------------------------------------------
p615n_sha(path) = bytes2hex(open(sha256, path))
p615n_tree(dir) = isdir(dir) ? sort([replace(relpath(joinpath(r, f), dir), '\\' => '/') for (r, _, fs) in walkdir(dir) for f in fs]) : String[]
function p615n_in_git(path)
    d = abspath(path)
    while true
        ispath(joinpath(d, ".git")) && return true
        p = dirname(d)
        p == d && return false
        d = p
    end
end
function p615n_tsv(path)
    ls = filter(!isempty, split(replace(read(path, String), "\r\n" => "\n"), '\n'))
    h = String.(split(ls[1], '\t'))
    return h, [Dict(zip(h, String.(split(l, '\t')))) for l in ls[2:end]]
end
function p615n_csv(path)
    ls = filter(!isempty, split(replace(read(path, String), "\r\n" => "\n"), '\n'))
    return String(ls[1]), [String.(split(l, ',')) for l in ls[2:end]]
end
p615n_f(s) = parse(Float64, strip(s))
p615n_eq(a, b; rtol = 1e-12, atol = 1e-12) = (isnan(a) && isnan(b)) || a == b ||
    (isfinite(a) && isfinite(b) && abs(a - b) <= atol + rtol * max(abs(a), abs(b)))
p615n_zip_names(z) = filter(!isempty, readlines(`unzip -Z1 $z`))
p615n_zip_read(z, m) = read(`unzip -p $z $m`)
p615n_isreadme(p) = occursin(r"^README[^/]*\.md$"i, basename(p))
p615n_dec(s) = (m = match(r"\d+\.\d+", s); m === nothing ? nothing : m.match)
p615n_q(s) = "\\Q" * s * "\\E"
# paragraphs: blank-line separated, and each list item or table row on its own
p615n_paras(t) = vcat([String.(split(q, r"\n(?=\s*(?:[-*]|\d+\.)\s|\s*\|)")) for q in split(t, r"\n\s*\n")]...)
# markdown table rows of a text (optional Literate "# "), backslashes and backticks dropped
function p615n_tables(text)
    tables = Vector{Vector{Vector{String}}}()
    cur = Vector{Vector{String}}()
    for l in split(text, '\n')
        s = strip(replace(l, r"^#\s?" => ""))
        if startswith(s, "|") && endswith(s, "|") && length(s) > 1
            push!(cur, [String(strip(replace(c, "\\" => "", "`" => ""))) for c in split(s[2:(end - 1)], '|')])
        else
            isempty(cur) || push!(tables, cur)
            cur = Vector{Vector{String}}()
        end
    end
    isempty(cur) || push!(tables, cur)
    return tables
end
p615n_issep(row) = all(c -> occursin(r"^:?-{3,}:?$", c), row)

# ---- records ------------------------------------------------------------------------------------
p615n_dirs(re) = isdir(P615N_DATA) ? sort(filter(d -> occursin(re, d) && isdir(joinpath(P615N_DATA, d)), readdir(P615N_DATA))) : String[]
function p615n_cb_record()
    dirs = p615n_dirs(r"^checkerboard-\d{4}-\d{2}-\d{2}$")
    isempty(dirs) && return nothing
    st(d) = (p = joinpath(P615N_DATA, d, "meta.toml"); isfile(p) ? string(get(TOML.parsefile(p), "status", "")) : "")
    finals = filter(d -> st(d) == "final", dirs)
    return isempty(finals) ? last(dirs) : last(finals)
end
const P615N_CBREC = p615n_cb_record()
function p615n_o1_record()
    P615N_CBREC === nothing && return nothing
    dirs = filter(p615n_dirs(r"^o1cb-\d{4}-\d{2}-\d{2}$")) do d
        p = joinpath(P615N_DATA, d, "provenance.toml")
        isfile(p) && get(TOML.parsefile(p), "source", "") == P615N_CBREC
    end
    return isempty(dirs) ? nothing : last(dirs)
end
const P615N_O1REC = p615n_o1_record()
p615n_rec(d, f...) = joinpath(P615N_DATA, d, f...)
const P615N_META = P615N_CBREC === nothing ? Dict{String, Any}() : TOML.parsefile(p615n_rec(P615N_CBREC, "meta.toml"))
const P615N_PROV = P615N_CBREC === nothing ? Dict{String, Any}() : TOML.parsefile(p615n_rec(P615N_CBREC, "provenance.toml"))
const P615N_CYCLE = Int(get(get(P615N_META, "time", Dict()), "cycle_mcs", 870))
const P615N_TCB = Int(get(get(P615N_META, "time", Dict()), "T_lambda2", 174))
const P615N_ALPHA = string(get(get(P615N_META, "time", Dict()), "alpha_text", "50/$(P615N_CYCLE)"))
const P615N_Z = Float64(get(get(P615N_META, "time", Dict()), "z", NaN))
const P615N_MACHINE = lowercase(strip(first(split(string(get(P615N_PROV, "cpu", "")), " w/"))))
const P615N_COMMIT8 = first(string(get(P615N_PROV, "commit", "")), 8)
p615n_devs() = P615N_CBREC === nothing ? Dict{String, String}[] : p615n_tsv(p615n_rec(P615N_CBREC, "entry", "deviations.tsv"))[2]
function p615n_flagged()
    P615N_CBREC === nothing && return (0, 0)
    _, rows = p615n_tsv(p615n_rec(P615N_CBREC, "comparison.tsv"))
    return (count(r -> r["beyond"] == "true", rows), length(rows))
end
# the cause's leading clause (before the first ':'), and the metric id (first token)
p615n_clause(r) = String(strip(first(split(r["suspected_cause"], ':'))))
p615n_metric(r) = String(first(split(r["target"])))

# a deviations table holds every entry/deviations.tsv row (README and page share the rule)
function p615n_dev_findings(name, text)
    bad = String[]
    tabs = filter(t -> length(t) >= 3 && p615n_issep(t[2]) &&
                       (h = lowercase(join(t[1], " | ")); occursin("ours", h) && occursin("cause", h) &&
                        occursin("author question", h) && occursin(r"potts\.jl|sequential", h)), p615n_tables(text))
    isempty(tabs) && return ["$name: no deviations table (Ours, the sequential reference, cause, Author question)"]
    rows = [r for t in tabs for r in t[3:end] if !p615n_issep(r)]
    devs = p615n_devs()
    isempty(devs) && push!(bad, "$name: the CB record has no deviation rows")
    for d in devs
        m, c = p615n_metric(d), d["case"]
        idre = Regex("(?<![A-Za-z0-9._@])" * p615n_q(m) * "(?![A-Za-z0-9._@])")
        hits = filter(r -> occursin(idre, r[1]) && occursin("($c)", r[1]), rows)
        ok = any(hits) do r
            t = join(r, " | ")
            o, p = p615n_dec(d["ours"]), p615n_dec(d["paper"])
            (o === nothing || occursin(o, t)) && (p === nothing || occursin(p, t)) &&
                occursin(p615n_clause(d), t) && occursin(P615N_STATUS, last(r)) &&
                (!startswith(d["author_question"], "not an author question") || startswith(last(r), "not an author question"))
        end
        ok || push!(bad, "$name: no row for $m ($c) with its values, cause class and status")
    end
    length(rows) >= length(devs) || push!(bad, "$name: fewer rows than deviations")
    return bad
end

# the D-215 (8) notes for a token
p615n_notes(fw) = [
    "N1" => p -> occursin("run_metrics.sh", p) && occursin(r"seq 0 10000", p) && occursin(r"complete"i, p),
    "N2" => p -> occursin(r"\bLFS\b", p),
    "N3" => p -> occursin(r"\bR\b", p) && occursin(r"lattice cent(re|er)"i, p),
    "N4" => p -> occursin(r"\bR\b", p) && occursin(r"\bpx\b", p) && occursin(r"\b(only|no|not)\b"i, p),
    "N5" => p -> occursin(r"hard-?coded"i, p) && occursin(r"framework"i, p) && occursin(r"\bline\b"i, p) && occursin(fw, p),
    "N6" => p -> occursin("results/$fw/Monolayer/", p) && occursin(r"zip"i, p),
]
p615n_missing_notes(t, fw) = [n for (n, f) in p615n_notes(fw) if !any(f, p615n_paras(t))]

function p615n_forbidden(text; email = false)
    s = replace(text, "PraneethMerugu/Potts.jl" => "")
    return [re.pattern for re in (email ? vcat(P615N_FORBIDDEN, P615N_EMAIL_FORBIDDEN) : P615N_FORBIDDEN) if occursin(re, s)]
end

# =============================================================================================
@testset "P6.15m m4 (0) API: the second entry's tokens and the `entries` keyword" begin
    @test isdefined(PottsModels, :OPENVT_CHECKERBOARD_TOKEN) && PottsModels.OPENVT_CHECKERBOARD_TOKEN == P615N_CB
    @test isdefined(PottsModels, :OPENVT_FRAMEWORK_TOKEN) && PottsModels.OPENVT_FRAMEWORK_TOKEN == P615N_FW
    @test isdefined(PottsModels, :OPENVT_ENTRIES) && Tuple(PottsModels.OPENVT_ENTRIES) == P615N_BOTH
    @test occursin(r"^[A-Za-z0-9._-]+$", P615N_CB)
    @test hasmethod(PottsModels.openvt_submission_package, Tuple{String}, (:entries,))
    # refusals come first: before the records, the bulk directory or the outdir are used
    for bad in ((P615N_CB,), (P615N_FW, "Potts.jl nonsense"), (P615N_FW, P615N_FW), (), ("Potts.jl (checkerboard)",))
        out = joinpath(mktempdir(), "pkg")
        msg = try
            withenv(() -> PottsModels.openvt_submission_package(out; entries = bad), P615N_BULK_ENV => nothing)
            "no error"
        catch e
            e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e))"
        end
        ok = occursin("entries", msg)
        ok || @info "P6.15m m4: entries = $(repr(bad)) not refused as required" msg
        @test ok
        @test !ispath(out) || isempty(readdir(out))
    end
end

@testset "P6.15m m4 (1) the checkerboard O1 record (GPU replay of the CB runs)" begin
    @test P615N_CBREC !== nothing
    ok = P615N_O1REC !== nothing
    ok || @info "P6.15m m4: no data/15/o1cb-<date>/ record with source = $(P615N_CBREC) (the GPU O1 replay; see the header)"
    @test ok
    if ok && P615N_CBREC !== nothing
        D = p615n_rec(P615N_O1REC)
        for f in ("provenance.toml", "archives.tsv", "o1_manifest.tsv", "neighbors.tsv", "README.md")
            @test isfile(joinpath(D, f))
        end
        @test !isfile(joinpath(D, "deviations.tsv")) && !isfile(joinpath(D, "verdicts.tsv"))
        for (root, _, fs) in walkdir(D), f in fs
            @test any(e -> endswith(lowercase(f), e), P615N_RECORD_EXT) && filesize(joinpath(root, f)) <= 10 * 2^20
        end
        prov = TOML.parsefile(joinpath(D, "provenance.toml"))
        @test get(prov, "item", "") == "P6.15m" && get(prov, "source", "") == P615N_CBREC
        @test occursin(r"^[0-9a-f]{40}$", string(get(prov, "commit", ""))) && get(prov, "dirty_tracked", true) === false
        runner = string(get(prov, "runner", ""))
        @test startswith(runner, "lib/PottsModels/reproductions/data/15/$(P615N_O1REC)/") && isfile(joinpath(P615N_ROOT, runner))
        isfile(joinpath(P615N_ROOT, runner)) && @test get(prov, "runner_sha256", "") == p615n_sha(joinpath(P615N_ROOT, runner))
        @test get(prov, "framework", "") == P615N_LABEL && get(prov, "folder_token", "") == P615N_CB
        @test occursin("CheckerboardCPM", string(get(prov, "algorithm", "")))
        @test occursin(r"AMDGPU|ROCm|ROCBackend", string(get(prov, "backend", ""))) && !isempty(string(get(prov, "device", "")))
        @test get(prov, "host_planner_fallback", true) === false
        @test !haskey(prov, "hostname")
        for k in ("julia", "machine", "cpu")
            @test !isempty(string(get(prov, k, "")))
        end
        # the CB record's runs and saves
        _, runs = p615n_tsv(p615n_rec(P615N_CBREC, "runs.tsv"))
        _, ts = p615n_tsv(p615n_rec(P615N_CBREC, "timeseries.tsv"))
        saves = Dict{Tuple{String, Int}, Dict{Int, Int}}()
        for r in ts
            get!(saves, (r["case"], parse(Int, r["seed"])), Dict{Int, Int}())[parse(Int, r["mcs"])] = parse(Int, r["N"])
        end
        # the manifest
        h, man = p615n_tsv(joinpath(D, "o1_manifest.tsv"))
        @test h == P615N_H_O1M
        @test sort(unique(r["case"] for r in man)) == P615N_CASES
        bad = String[]
        byseed = Dict{Tuple{String, Int}, Vector{Dict{String, String}}}()
        foreach(r -> push!(get!(byseed, (r["case"], parse(Int, r["seed"])), Dict{String, String}[]), r), man)
        for c in P615N_CASES
            seeds = sort([parse(Int, r["seed"]) for r in runs if r["case"] == c])
            sort([s for (cc, s) in keys(byseed) if cc == c]) == seeds || push!(bad, "($c): seeds differ from runs.tsv")
            for s in seeds
                ms = get(byseed, (c, s), Dict{String, String}[])
                got = Dict(parse(Int, r["mcs"]) => r for r in ms)
                want = get(saves, (c, s), Dict{Int, Int}())
                (length(got) == length(ms) && Set(keys(got)) == Set(keys(want))) || (push!(bad, "($c) s$s: MCS set ≠ timeseries saves"); continue)
                for (m, r) in got
                    rows = parse(Int, r["rows"])
                    rows == want[m] || push!(bad, "($c) s$s MCS $m: rows $rows ≠ N $(want[m])")
                    r["file"] == "$(P615N_STEM[c])/s$(s)/potts_$(c)_s$(s)_$(lpad(m, 6, '0')).csv" || push!(bad, "($c) s$s: name $(r["file"])")
                    i = [parse(Int, r["i$k"]) for k in 0:3]
                    (sum(i) == rows && i[1] == rows) || push!(bad, "($c) s$s MCS $m: codes $i")
                    occursin(r"^[0-9a-f]{64}$", r["sha256"]) && parse(Int, r["bytes"]) > 0 || push!(bad, "($c) s$s MCS $m: sha/bytes")
                end
                run = only(filter(r -> r["case"] == c && parse(Int, r["seed"]) == s, runs))
                mx = maximum(keys(got))
                (mx == parse(Int, run["mcs"]) && parse(Int, got[mx]["rows"]) == parse(Int, run["N"])) ||
                    push!(bad, "($c) s$s: the replay's stop ≠ runs.tsv")
            end
        end
        isempty(bad) || @info "P6.15m m4 O1 manifest" first(bad, 15)
        @test isempty(bad)
        @test issorted([r["file"] for r in man]) || issorted([(r["case"], r["file"]) for r in man])
        # archives
        _, ar = p615n_tsv(joinpath(D, "archives.tsv"))
        @test sort([r["case"] for r in ar]) == P615N_CASES
        for r in ar
            c = r["case"]
            @test haskey(P615N_STEM, c) && r["archive"] == P615N_STEM[c] * ".zip"
            @test parse(Int, r["members"]) == count(m -> m["case"] == c, man)
            @test occursin(r"^[0-9a-f]{64}$", r["sha256"]) && 0 < parse(Int, r["bytes"]) < P615N_BULK_MAX
        end
        # neighbours: the stop frame's histogram per run
        _, nb = p615n_tsv(joinpath(D, "neighbors.tsv"))
        nbad = String[]
        for r in runs
            c, s = r["case"], parse(Int, r["seed"])
            tot = sum((parse(Int, x["count"]) for x in nb if x["case"] == c && parse(Int, x["seed"]) == s); init = 0)
            tot == parse(Int, r["N"]) || push!(nbad, "($c) s$s: Σ count $tot ≠ N $(r["N"])")
        end
        @test all(x -> parse(Int, x["n"]) >= 0 && parse(Int, x["count"]) > 0, nb)
        isempty(nbad) || @info "P6.15m m4 neighbours" first(nbad, 10)
        @test isempty(nbad)
    end
end

@testset "P6.15m m4 (2) the checkerboard renders for page 15" begin
    @test P615N_CBREC !== nothing
    if P615N_CBREC !== nothing
        D = p615n_rec(P615N_CBREC)
        scripts = filter(f -> startswith(f, "plot_") && endswith(f, ".jl"), readdir(D))
        for (_, f) in P615N_RENDERS
            p = joinpath(D, f)
            ok = isfile(p) && filesize(p) <= 10 * 2^20 && read(p, 8) == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
            ok || @info "P6.15m m4: the render $f is missing from $(P615N_CBREC) (or not a PNG)"
            @test ok
            @test any(s -> occursin(f, read(joinpath(D, s), String)), scripts)
        end
    end
end

# ---- page 15 ----------------------------------------------------------------------------------
const P615N_SRC = isfile(P615N_PAGE) ? read(P615N_PAGE, String) : ""
const P615N_LINES = split(P615N_SRC, '\n')
const P615N_HEADS = [(i, length(m[1]), String(m[2])) for (i, l) in enumerate(P615N_LINES)
                     for m in (match(r"^# (#{1,6}) +(.*?)\s*$", l),) if m !== nothing]
function p615n_section(k)
    i, lvl, _ = P615N_HEADS[k]
    j = findnext(h -> h[2] <= lvl, P615N_HEADS, k + 1)
    return join(P615N_LINES[i:(j === nothing ? length(P615N_LINES) : P615N_HEADS[j][1] - 1)], '\n')
end
p615n_head(f) = findfirst(f, P615N_HEADS)
p615n_calls(sec) = [(String(m[1]), String(m[2])) for m in eachmatch(r"record_figure\(\s*\"([^\"]+)\"\s*,\s*\"([^\"]+)\"", sec)]
p615n_prose(sec) = replace(join([replace(l, r"^#\s?" => "") for l in split(sec, '\n') if startswith(l, "#")], '\n'), "\\" => "")
# the call after the Potts.jl slot (dir, file) is the CB slot (CB record, cbfile)
function p615n_after(calls, seq, cbfile)
    i = findfirst(==(seq), calls)
    return i !== nothing && i < length(calls) && calls[i + 1] == (something(P615N_CBREC, "?"), cbfile)
end

@testset "P6.15m m4 (3) page 15: the Potts.jl (checkerboard) section" begin
    @test !isempty(P615N_SRC) && P615N_CBREC !== nothing
    kdev = p615n_head(h -> h[2] == 3 && occursin(r"^Deviations"i, h[3]))
    kdet = p615n_head(h -> h[2] == 2 && occursin(r"^(\d+\.\s*)?Details"i, h[3]))
    kcb = p615n_head(h -> h[2] == 3 && occursin(P615N_LABEL, h[3]))
    @test kcb !== nothing
    @test kdev !== nothing && kdet !== nothing && kcb !== nothing && kdev < kcb < kdet
    sec = kcb === nothing ? "" : p615n_section(kcb)
    prose = p615n_prose(sec)
    if kcb !== nothing && P615N_CBREC !== nothing
        h = P615N_HEADS[kcb][3]
        @test !occursin(r"deviation|verdict|video|Figures?\s*\d|Tables?\s*S?\d"i, h)     # the frozen order picks
        @test !occursin(r"pending"i, sec)
        # the record: directory, commit, machine
        @test occursin(P615N_CBREC, sec) && length(P615N_COMMIT8) == 8 && occursin(P615N_COMMIT8, sec)
        @test !isempty(P615N_MACHINE) && occursin(P615N_MACHINE, lowercase(sec))
        # the time scale (D-220)
        for s in (string(P615N_TCB), string(P615N_T_SEQ), "$(P615N_CYCLE) MCS", P615N_ALPHA, @sprintf("%.2f", P615N_Z))
            ok = occursin(s, prose)
            ok || @info "P6.15m m4 page: the checkerboard section lacks" s
            @test ok
        end
        # the comparison summary
        nf, nt = p615n_flagged()
        @test nt > 0 && occursin("$nf of $nt", prose)
        # the deviations table
        f = p615n_dev_findings("page 15", sec)
        isempty(f) || @info "P6.15m m4 page deviations" first(f, 10)
        @test isempty(f)
        # the cause text (D-008, D-220, D-221)
        for re in (r"thinning"i, r"claim"i, r"27\s?%", r"D-008", r"D-220", r"D-221", r"64 colours"i,
            r"6 colours on the chain"i, r"4 on the monolayer"i, r"not a bug"i)
            ok = occursin(re, prose)
            ok || @info "P6.15m m4 page: the cause text lacks" re
            @test ok
        end
    end
    # figure slots that have data, directly after the Potts.jl slot (spec §1.3)
    k2 = p615n_head(h -> h[2] == 3 && occursin(r"^Figure 2\b", h[3]))
    k39 = p615n_head(h -> h[2] == 3 && occursin(r"Figures 3 and 9", h[3]))
    @test k2 !== nothing && k39 !== nothing
    if k2 !== nothing && k39 !== nothing
        s2, s39 = p615n_section(k2), p615n_section(k39)
        @test p615n_after(p615n_calls(s2), (P615N_SEQ_CAL, "fig2_bde.png"), "fig2.png")
        @test p615n_after(p615n_calls(s39), (P615N_SEQ_F3F8, "fig3.png"), "fig3.png")
        @test p615n_after(p615n_calls(s39), (P615N_SEQ_F3F8, "fig8.png"), "fig9.png")
        @test occursin(P615N_LABEL, s2) && occursin(P615N_LABEL, s39)
        @test occursin(string(P615N_TCB), s2)
    end
    allcb = filter(c -> c[1] == something(P615N_CBREC, "?"), p615n_calls(P615N_SRC))
    @test sort(allcb) == sort([(something(P615N_CBREC, "?"), f) for (_, f) in P615N_RENDERS])
    for (_, f) in P615N_RENDERS
        @test P615N_CBREC !== nothing && isfile(p615n_rec(P615N_CBREC, f))
    end
    # Table S5: this entry's T(λ = 2) row
    ks5 = p615n_head(h -> h[2] == 3 && occursin(r"Table S5"i, h[3]))
    @test ks5 !== nothing && kdet !== nothing && ks5 > kdet
    if ks5 !== nothing
        s5 = p615n_section(ks5)
        @test occursin(P615N_LABEL, s5) && occursin(something(P615N_CBREC, "?"), s5) && occursin(string(P615N_TCB), s5)
    end
    # the page asserts the record's commit
    @test P615N_CBREC !== nothing &&
          occursin(Regex("record\\(\\s*\"" * p615n_q(P615N_CBREC) * "\"\\s*;\\s*commit\\s*=\\s*\"" * P615N_COMMIT8 * "\"\\s*\\)"), P615N_SRC)
    # no Q28 (D-219), nothing private
    @test !occursin(P615N_CLOSED_Q, P615N_SRC)
    bad = p615n_forbidden(P615N_SRC)
    isempty(bad) || @info "P6.15m m4 page: forbidden text" bad
    @test isempty(bad)
end

# ---- the bulk tier: builds -------------------------------------------------------------------------
const P615N_OUT = mktempdir()
const P615N_U1 = joinpath(P615N_OUT, "u1")
const P615N_U2 = joinpath(P615N_OUT, "u2")
const P615N_S2A = joinpath(P615N_OUT, "s2a")
const P615N_S2B = joinpath(P615N_OUT, "s2b")
const P615N_RET = Dict{String, Any}()
const P615N_ERR = Dict{String, Any}()
function p615n_build(which)
    haskey(P615N_RET, which) && return true
    haskey(P615N_ERR, which) && return false
    try
        P615N_RET[which] = withenv(P615N_BULK_ENV => P615N_BULK) do
            which == "u1" ? PottsModels.openvt_submission_package(P615N_U1) :
            which == "u2" ? PottsModels.openvt_submission_package(P615N_U2; entries = P615N_BOTH) :
            which == "s2a" ? PottsModels.openvt_submission_package(P615N_S2A; split = :email, entries = P615N_BOTH) :
            (p615n_build("s2a"); sleep(1.1); PottsModels.openvt_submission_package(P615N_S2B; split = :email, entries = reverse(P615N_BOTH)))
        end
        return true
    catch e
        P615N_ERR[which] = e
        @info "P6.15m m4: the $(which) build failed" exception = (e, catch_backtrace())
        return false
    end
end
p615n_bulkfiles(s) = (d = joinpath(s, "bulk"); isdir(d) ? sort(readdir(d)) : String[])
p615n_url(f) = P615N_RELEASE_BASE * string(PottsModels.OPENVT_BULK_RELEASE_TAG) * "/" * f
p615n_cbres(f...) = joinpath(P615N_U2, "results", P615N_CB, f...)
p615n_cbimpl(f...) = joinpath(P615N_U2, "implementations", P615N_CB, f...)
const P615N_BULK_O1 = [P615N_STEM[c] * ".zip" for c in P615N_CASES]
const P615N_CB_MANIFEST = "$(P615N_CB)_centroids_manifest.csv"

if !P615N_HAVE_BULK
    @testset "P6.15m m4 (4–9) builds (bulk tier)" begin
        @info "P6.15m m4: $(P615N_BULK_ENV) not set; the package builds are skipped"
        @test_skip "P6.15m m4 builds need $(P615N_BULK_ENV)"
    end
else

@testset "P6.15m m4 (4) inputs: the bulk directory holds the checkerboard zips" begin
    @test !p615n_in_git(P615N_BULK)
    @test Sys.which("unzip") !== nothing
    @test P615N_O1REC !== nothing
    if P615N_O1REC !== nothing
        _, ar = p615n_tsv(p615n_rec(P615N_O1REC, "archives.tsv"))
        for r in ar
            p = joinpath(P615N_BULK, r["archive"])
            ok = isfile(p) && string(filesize(p)) == r["bytes"] && p615n_sha(p) == r["sha256"]
            ok || @info "P6.15m m4: the bulk directory lacks $(r["archive"]) with the O1 record's sha256"
            @test ok
        end
    end
end

@testset "P6.15m m4 (5) two entries: layout and no regression of the sequential entry" begin
    @test p615n_build("u1") && p615n_build("u2")
    @test get(P615N_RET, "u2", nothing) == P615N_U2
    @test sort(readdir(P615N_U2)) == ["implementations", "results"]
    for d in ("implementations", "results")
        @test isdir(joinpath(P615N_U2, d)) && sort(readdir(joinpath(P615N_U2, d))) == sort(collect(P615N_BOTH))
    end
    t1 = p615n_tree(P615N_U1)
    t2s = filter(p -> startswith(p, "implementations/$(P615N_FW)/") || startswith(p, "results/$(P615N_FW)/"), p615n_tree(P615N_U2))
    @test !isempty(t1) && t2s == t1
    lists_both = ("implementations/$(P615N_FW)/README.md", "results/$(P615N_FW)/README.md")
    changed_files = [p for p in intersect(t1, t2s) if !(p in lists_both) && read(joinpath(P615N_U1, p)) != read(joinpath(P615N_U2, p))]
    isempty(changed_files) || @info "P6.15m m4: sequential files changed by the second entry" first(changed_files, 10)
    @test isempty(changed_files)
end

@testset "P6.15m m4 (6) implementations/<CB>: README, runner, parameters; the shared model" begin
    @test p615n_build("u2") && P615N_O1REC !== nothing && P615N_CBREC !== nothing
    tree = p615n_tree(p615n_cbimpl())
    @test "README.md" in tree && "parameters.csv" in tree
    @test !any(p -> startswith(p, "src/"), tree)                         # the model is shared
    recs = filter(!isnothing, [P615N_CBREC, P615N_O1REC])
    for p in tree
        p in ("README.md", "parameters.csv") && continue
        m = match(r"^scripts/([^/]+)/([^/]+\.jl)$", p)
        ok = m !== nothing && m[1] in recs && isfile(p615n_rec(m[1], m[2])) &&
             read(p615n_cbimpl(p)) == read(p615n_rec(m[1], m[2]))
        ok || @info "P6.15m m4: not a byte copy of a record script: implementations/$(P615N_CB)/$p"
        @test ok
    end
    readme = isfile(p615n_cbimpl("README.md")) ? read(p615n_cbimpl("README.md"), String) : ""
    for r in recs
        prov = TOML.parsefile(p615n_rec(r, "provenance.toml"))
        rn = basename(prov["runner"])
        @test "scripts/$r/$rn" in tree
        @test occursin("scripts/$r/$rn", readme) && occursin(first(prov["commit"], 8), readme)
    end
    @test occursin(P615N_LABEL, readme) && occursin("CheckerboardCPM", readme) && occursin(r"ROCm|AMDGPU", readme)
    @test occursin("implementations/$(P615N_FW)/src", readme)
    @test occursin("$(P615N_CYCLE) MCS", readme) && occursin(r"\bMIT\b", readme)
    @test isempty(p615n_forbidden(readme; email = true)) && !occursin(P615N_CLOSED_Q, readme)
    # parameters.csv: the sequential values, with this entry's time unit and algorithm
    ps = joinpath(P615N_U2, "implementations", P615N_FW, "parameters.csv")
    pc = p615n_cbimpl("parameters.csv")
    @test isfile(ps) && isfile(pc)
    if isfile(ps) && isfile(pc)
        hs, rs = p615n_csv(ps)
        hc, rc = p615n_csv(pc)
        @test hs == hc == "name,value,unit"
        S = Dict(r[1] => r[2] for r in rs)
        C = Dict(r[1] => r[2] for r in rc)
        @test issubset(keys(S), keys(C))
        changed = ("alpha", "cycle_MCS", "T_relax_lambda2_MCS", "algorithm")
        for (k, v) in S
            k in changed && continue
            @test get(C, k, nothing) == v
        end
        a0 = p615n_f(S["A0"])
        @test p615n_eq(p615n_f(get(C, "alpha", "NaN")), a0 / P615N_CYCLE; rtol = 1e-12)
        @test p615n_f(get(C, "cycle_MCS", "NaN")) == P615N_CYCLE && p615n_f(get(C, "T_relax_lambda2_MCS", "NaN")) == P615N_TCB
        @test occursin("CheckerboardCPM", get(C, "algorithm", ""))
        @test P615N_CYCLE == 5 * P615N_TCB                                 # D-220: cycle = 5 T_cb
    end
end

@testset "P6.15m m4 (7) results/<CB>: every file, equal to the records" begin
    @test p615n_build("u2") && P615N_O1REC !== nothing && P615N_CBREC !== nothing
    if P615N_O1REC !== nothing && P615N_CBREC !== nothing
        _, runs = p615n_tsv(p615n_rec(P615N_CBREC, "runs.tsv"))
        seeds(c) = sort([parse(Int, r["seed"]) for r in runs if r["case"] == c])
        want = Set{String}(["README.md", "Relaxation/11cells/width.csv", "Relaxation/lambda_scan/11cells_lambda2_width.csv",
            "Relaxation/table_S5.csv", "Monolayer/$(P615N_CB_MANIFEST)",
            ("provenance/$r.toml" for r in (P615N_CBREC, P615N_O1REC))...,
            ("Monolayer/$z" for z in P615N_BULK_O1)...])
        for c in P615N_CASES
            push!(want, "Monolayer/metrics/measurements_$(c)_mean.csv", "Monolayer/metrics/neighbors_$(c).csv")
            foreach(s -> push!(want, "Monolayer/metrics/$c/measurements_s$(s).csv"), seeds(c))
        end
        foreach(s -> push!(want, "Monolayer/metrics/a/inhibition_s$(s).csv"), seeds("a"))
        got = Set(p615n_tree(p615n_cbres()))
        extra, miss = setdiff(got, want), setdiff(want, got)
        isempty(extra) || @info "P6.15m m4: results/$(P615N_CB) files not allowed" first(collect(extra), 10)
        isempty(miss) || @info "P6.15m m4: results/$(P615N_CB) files missing" first(collect(miss), 10)
        @test isempty(extra) && isempty(miss)
        # provenance without the host
        for r in (P615N_CBREC, P615N_O1REC)
            p = p615n_cbres("provenance", "$r.toml")
            isfile(p) || continue
            orig = TOML.parsefile(p615n_rec(r, "provenance.toml"))
            delete!(orig, "hostname"); delete!(orig, "work")
            @test TOML.parsefile(p) == orig
        end
        # Relaxation (O4, the T(λ = 2) row)
        _, r11 = p615n_tsv(p615n_rec(P615N_CBREC, "timeseries_11chain.tsv"))
        l2 = filter(r -> p615n_f(r["lambda"]) == 2, r11)
        for p in ("Relaxation/11cells/width.csv", "Relaxation/lambda_scan/11cells_lambda2_width.csv")
            isfile(p615n_cbres(p)) || continue
            h, g = p615n_csv(p615n_cbres(p))
            @test h == P615N_H_WIDTH && length(g) == length(l2)
            @test length(g) == length(l2) && all(all(p615n_eq(p615n_f(x[j]), p615n_f(r[c])) for (j, c) in
                enumerate(("t_over_T", "w11_mean", "w11_sd"))) for (x, r) in zip(g, l2))
        end
        if isfile(p615n_cbres("Relaxation", "table_S5.csv"))
            h, g = p615n_csv(p615n_cbres("Relaxation", "table_S5.csv"))
            _, ref = p615n_tsv(p615n_rec(P615N_SEQ_CAL, "reference.tsv"))
            post = filter(r -> p615n_f(r["t_mcs"]) >= 0, l2)
            mse = PottsModels.Analysis.relaxation_mse([p615n_f(r["t_mcs"]) for r in post], [p615n_f(r["w11_mean"]) for r in post],
                P615N_TCB, [p615n_f(r["t_over_T"]) for r in ref], [p615n_f(r["w"]) for r in ref])
            @test h == P615N_H_S5 && length(g) == 1
            @test length(g) == 1 && g[1][1] == "2" && parse(Int, g[1][2]) == P615N_TCB && p615n_eq(p615n_f(g[1][3]), mse; rtol = 1e-9)
        end
        # O6 per run and the means (t in 870-MCS cycles)
        _, ts = p615n_tsv(p615n_rec(P615N_CBREC, "timeseries.tsv"))
        rl = "R" in keys(first(ts)) ? "R" : "r"
        tsrun = Dict{Tuple{String, Int}, Vector{Dict{String, String}}}()
        foreach(r -> push!(get!(tsrun, (r["case"], parse(Int, r["seed"])), Dict{String, String}[]), r), ts)
        bad = String[]
        for c in P615N_CASES
            byrun = Dict{Int, Dict{Int, Vector{Float64}}}()
            for s in seeds(c)
                rows = sort(get(tsrun, (c, s), Dict{String, String}[]); by = r -> parse(Int, r["mcs"]))
                byrun[s] = Dict(parse(Int, r["mcs"]) => [p615n_f(r[k]) for k in ("N", rl, "A", "C", "w", "g")] for r in rows)
                p = p615n_cbres("Monolayer", "metrics", c, "measurements_s$(s).csv")
                isfile(p) || (push!(bad, "$c s$s missing"); continue)
                h, g = p615n_csv(p)
                h == P615N_H_MEAS || push!(bad, "$c s$s header $h")
                length(g) == length(rows) || (push!(bad, "$c s$s rows"); continue)
                for (x, r) in zip(g, rows)
                    m = parse(Int, r["mcs"])
                    ok = parse(Int, x[1]) == m && p615n_eq(p615n_f(x[2]), m / P615N_CYCLE) &&
                         all(p615n_eq(p615n_f(x[2 + j]), byrun[s][m][j]) for j in 1:6)
                    ok || (push!(bad, "$c s$s MCS $m"); break)
                end
            end
            p = p615n_cbres("Monolayer", "metrics", "measurements_$(c)_mean.csv")
            isfile(p) || continue
            h, g = p615n_csv(p)
            h == P615N_H_MEAS * ",runs" || push!(bad, "$c mean header")
            grid = sort(collect(reduce(intersect, [Set(m for m in keys(v) if m % P615N_GRID == 0) for v in values(byrun)])))
            [parse(Int, x[1]) for x in g] == grid || (push!(bad, "$c mean grid"); continue)
            for (x, m) in zip(g, grid)
                for j in 1:6
                    v = filter(!isnan, [byrun[s][m][j] for s in keys(byrun)])
                    p615n_eq(p615n_f(x[2 + j]), isempty(v) ? NaN : sum(v) / length(v); rtol = 1e-9) || push!(bad, "$c mean MCS $m col $j")
                end
                parse(Int, x[end]) == length(byrun) || push!(bad, "$c mean runs")
            end
        end
        isempty(bad) || @info "P6.15m m4 metrics" first(bad, 10)
        @test isempty(bad)
        # neighbours (O1 record) and A3 (O1 manifest)
        _, nb = p615n_tsv(p615n_rec(P615N_O1REC, "neighbors.tsv"))
        for c in P615N_CASES
            p = p615n_cbres("Monolayer", "metrics", "neighbors_$(c).csv")
            isfile(p) || continue
            cnt = Dict{Int, Float64}()
            for r in nb
                r["case"] == c && (cnt[parse(Int, r["n"])] = get(cnt, parse(Int, r["n"]), 0.0) + p615n_f(r["count"]))
            end
            tot = sum(values(cnt))
            h, g = p615n_csv(p)
            @test h == "n,p"
            @test [parse(Int, x[1]) for x in g] == sort([n for (n, v) in cnt if v > 0])
            @test all(p615n_eq(p615n_f(x[2]), 100 * cnt[parse(Int, x[1])] / tot; rtol = 1e-9) for x in g)
        end
        _, man = p615n_tsv(p615n_rec(P615N_O1REC, "o1_manifest.tsv"))
        for s in seeds("a")
            p = p615n_cbres("Monolayer", "metrics", "a", "inhibition_s$(s).csv")
            isfile(p) || continue
            rows = sort(filter(r -> r["case"] == "a" && parse(Int, r["seed"]) == s, man); by = r -> parse(Int, r["mcs"]))
            h, g = p615n_csv(p)
            @test h == "MCS,t,f0,f1,f2,f3" && length(g) == length(rows)
            @test all(parse(Int, x[1]) == parse(Int, r["mcs"]) && p615n_eq(p615n_f(x[2]), parse(Int, r["mcs"]) / P615N_CYCLE) &&
                      all(p615n_eq(p615n_f(x[2 + k]), parse(Int, r["i$(k - 1)"]) / parse(Int, r["rows"])) for k in 1:4)
                      for (x, r) in zip(g, rows))
        end
        # the O1 archives and the manifest CSV
        mp = p615n_cbres("Monolayer", P615N_CB_MANIFEST)
        if isfile(mp)
            h, g = p615n_csv(mp)
            @test h == "archive,file,rows,bytes,sha256"
            want_rows = [[P615N_STEM[c] * ".zip", r["file"], r["rows"], r["bytes"], r["sha256"]]
                         for c in P615N_CASES for r in sort(filter(r -> r["case"] == c, man); by = r -> r["file"])]
            @test g == want_rows
        end
        _, ar = p615n_tsv(p615n_rec(P615N_O1REC, "archives.tsv"))
        zbad = String[]
        for r in ar
            z = p615n_cbres("Monolayer", r["archive"])
            isfile(z) || (push!(zbad, "$(r["archive"]) missing"); continue)
            p615n_sha(z) == r["sha256"] || push!(zbad, "$(r["archive"]) sha256")
            mem = p615n_zip_names(z)
            mc = sort(filter(m -> m["case"] == r["case"], man); by = m -> m["file"])
            mem == [m["file"] for m in mc] || (push!(zbad, "$(r["archive"]) members"); continue)
            # every member of the first seed, and the stop frame of every seed
            byfile = Dict(m["file"] => m for m in mc)
            s1 = minimum(parse(Int, m["seed"]) for m in mc)
            stops = Dict{Int, String}()
            for m in mc
                s = parse(Int, m["seed"])
                (!haskey(stops, s) || parse(Int, byfile[stops[s]]["mcs"]) < parse(Int, m["mcs"])) && (stops[s] = m["file"])
            end
            check = unique([[m["file"] for m in mc if parse(Int, m["seed"]) == s1]; collect(values(stops))])
            for f in check
                b = p615n_zip_read(z, f)
                e = byfile[f]
                (length(b) == parse(Int, e["bytes"]) && bytes2hex(sha256(b)) == e["sha256"]) || (push!(zbad, "$f bytes"); continue)
                ls = filter(!isempty, split(String(b), '\n'))
                ls[1] == "x,y,i,n,g" || push!(zbad, "$f header")
                length(ls) - 1 == parse(Int, e["rows"]) || push!(zbad, "$f rows")
                for l in ls[2:end]
                    v = split(l, ',')
                    (length(v) == 5 && parse(Int, v[4]) >= 0 && parse(Int, v[5]) == (parse(Int, v[3]) == 0 ? 1 : 0)) || (push!(zbad, "$f row $l"); break)
                end
                if f in values(stops)                                   # the neighbours oracle
                    s = parse(Int, e["seed"])
                    hist = Dict{Int, Int}()
                    foreach(l -> (n = parse(Int, split(l, ',')[4]); hist[n] = get(hist, n, 0) + 1), ls[2:end])
                    rec = Dict(parse(Int, x["n"]) => parse(Int, x["count"]) for x in nb if x["case"] == r["case"] && parse(Int, x["seed"]) == s)
                    hist == rec || push!(zbad, "$f: neighbors.tsv ≠ the stop frame")
                end
            end
            @test read(z) == read(joinpath(P615N_BULK, r["archive"]))
        end
        isempty(zbad) || @info "P6.15m m4 archives" first(zbad, 10)
        @test isempty(zbad)
    end
end

@testset "P6.15m m4 (8) results/<CB>/README.md" begin
    @test p615n_build("u2") && P615N_CBREC !== nothing
    p = p615n_cbres("README.md")
    t = isfile(p) ? read(p, String) : ""
    @test !isempty(t)
    if !isempty(t) && P615N_CBREC !== nothing
        h1 = match(r"^#\s+(.*)$"m, t)
        @test h1 !== nothing && occursin(P615N_LABEL, h1[1])
        @test occursin(P615N_KEY, t) && occursin(P615N_RGB, t) && occursin(r"\bQ27\b", t) && occursin("our open question list", t)
        # units and the time scale
        @test occursin(r"\bR\b", t) && occursin("$(P615N_CYCLE) MCS", t) && occursin("5T", t)
        for s in (string(P615N_TCB), string(P615N_T_SEQ), P615N_ALPHA, @sprintf("%.2f", P615N_Z))
            @test occursin(s, t)
        end
        @test all(l -> !occursin("775", l) || occursin(r"sequential"i, l), split(t, '\n'))
        for c in P615N_CASES
            @test occursin(string(P615N_META["cases"][c]["seeds"]), t)
        end
        # not produced for this entry
        k = findfirst(r"^##\s+[^\n]*not produced[^\n]*$"mi, t)
        @test k !== nothing
        if k !== nothing
            rest = t[last(k):end]
            e = findfirst(r"\n##\s"m, rest)
            np = e === nothing ? rest : rest[1:first(e)]
            for re in (r"\bO2\b", r"Figure 5", r"\bO3\b", r"Figure 6", r"Table 1", r"\bO5\b", r"Figure 7", r"Figure 8",
                r"case \(e\)", r"11\+10", r"λ\s*=\s*1,\s*3,?\s*(and\s*)?5", r"closeup\.png", r"Figure 1\b")
                ok = occursin(re, np)
                ok || @info "P6.15m m4 README: the not-produced section lacks" re
                @test ok
            end
        end
        # the characterisation and its cause
        nf, nt = p615n_flagged()
        @test occursin("$nf of $nt", t)
        for re in (r"thinning"i, r"claim"i, r"27\s?%", r"64 colours"i, r"6 colours on the chain"i, r"4 on the monolayer"i)
            @test occursin(re, t)
        end
        f = p615n_dev_findings("results/$(P615N_CB)/README.md", t)
        isempty(f) || @info "P6.15m m4 README deviations" first(f, 10)
        @test isempty(f)
        # D-215 (8) notes, licence, wording
        miss = p615n_missing_notes(t, P615N_CB)
        isempty(miss) || @info "P6.15m m4 README lacks" miss
        @test isempty(miss)
        @test occursin(r"\bMIT\b", t)
        @test !occursin(P615N_CLOSED_Q, t) && !occursin("?", replace(t, r"https?://\S+" => ""))
        bad = p615n_forbidden(t; email = true)
        isempty(bad) || @info "P6.15m m4 README forbidden" bad
        @test isempty(bad)
    end
end

@testset "P6.15m m4 (9) the two-entry e-mail split" begin
    @test p615n_build("u2") && p615n_build("s2a") && p615n_build("s2b")
    S = P615N_S2A
    @test isdir(S) && sort(readdir(S)) == ["EMAIL.md", "bulk", "core.zip"]
    core = joinpath(S, "core.zip")
    @test isfile(core) && filesize(core) <= P615N_CORE_MAX
    isfile(core) && @info "P6.15m m4 core.zip (two entries)" bytes = filesize(core)
    U = p615n_tree(P615N_U2)
    isbulk(u) = any(fw -> startswith(u, "results/$fw/Monolayer/") && !occursin('/', u[(length("results/$fw/Monolayer/") + 1):end]) &&
                         (occursin(Regex("^" * p615n_q(fw) * raw"_(beta[0-9.]+_gamma[0-9.]+|No_CI_[a-z]+)\.zip$"), basename(u)) ||
                          basename(u) in ("$(fw)_5T_MonolayerGrowth_1000_Data.zip", "$(fw)_centroids_manifest.csv")), P615N_BOTH)
    ub = filter(isbulk, U)
    bf = p615n_bulkfiles(S)
    @test sort(bf) == sort(basename.(ub))
    @test count(u -> startswith(u, "results/$(P615N_CB)/"), ub) == length(P615N_BULK_O1) + 1
    @test all(f -> f in bf, [P615N_BULK_O1; P615N_CB_MANIFEST])
    for f in bf
        u = only(filter(x -> basename(x) == f, ub))
        @test read(joinpath(S, "bulk", f)) == read(joinpath(P615N_U2, u)) && filesize(joinpath(S, "bulk", f)) < P615N_BULK_MAX
    end
    @info "P6.15m m4 bulk/ (two entries)" sizes = [f => filesize(joinpath(S, "bulk", f)) for f in bf]
    r = get(P615N_RET, "s2a", nothing)
    @test r !== nothing && hasproperty(r, :core_bytes) && hasproperty(r, :bulk_bytes)
    if r !== nothing && hasproperty(r, :core_bytes) && isfile(core)
        @test r.core_bytes == filesize(core) && r.bulk_bytes == sum(f -> filesize(joinpath(S, "bulk", f)), bf; init = 0)
    end
    # core: every non-bulk U2 file exactly once, byte-identical (README*.md excepted)
    mem = isfile(core) ? p615n_zip_names(core) : String[]
    @test !isempty(mem) && allunique(mem) && !any(m -> endswith(m, "/"), mem)
    roots = ["implementations/$fw/" for fw in P615N_BOTH] ∪ ["results/$fw/" for fw in P615N_BOTH]
    @test all(m -> any(x -> startswith(m, x), roots), mem)
    @test isempty(filter(m -> !(m in U) && !p615n_isreadme(m), mem))
    @test Set(m for m in mem if m in U) == Set(filter(!isbulk, U))
    db = [m for m in mem if m in U && !p615n_isreadme(m) && p615n_zip_read(core, m) != read(joinpath(P615N_U2, m))]
    isempty(db) || @info "P6.15m m4 core members differing from the unsplit build" first(db, 10)
    @test isempty(db)
    # the checkerboard README in the core links its bulk files
    cr = "results/$(P615N_CB)/README.md"
    @test cr in mem
    if cr in mem
        ls = split(String(p615n_zip_read(core, cr)), '\n')
        for f in [P615N_BULK_O1; P615N_CB_MANIFEST]
            sha = isfile(joinpath(S, "bulk", f)) ? p615n_sha(joinpath(S, "bulk", f)) : "?"
            @test any(l -> occursin(f, l) && occursin(sha, l) && occursin(p615n_url(f), l), ls)
        end
    end
    # determinism (the second build passes the entries in the other order)
    t1, t2 = p615n_tree(P615N_S2A), p615n_tree(P615N_S2B)
    @test !isempty(t1) && t1 == t2
    @test all(f -> read(joinpath(P615N_S2A, f)) == read(joinpath(P615N_S2B, f)), intersect(t1, t2))
    # core text: nothing private
    tb = String[]
    for m in mem
        any(e -> endswith(m, e), (".md", ".csv", ".toml", ".jl", ".txt")) || continue
        startswith(m, "results/$(P615N_CB)/") || startswith(m, "implementations/$(P615N_CB)/") || continue
        s = String(p615n_zip_read(core, m))
        append!(tb, ["$m: $b" for b in p615n_forbidden(s; email = p615n_isreadme(m))])
        occursin(P615N_OUT, s) && push!(tb, "$m: outdir")
        occursin(P615N_ROOT, s) && push!(tb, "$m: checkout path")
    end
    isempty(tb) || @info "P6.15m m4 core forbidden text" first(tb, 10)
    @test isempty(tb)
end

@testset "P6.15m m4 (10) EMAIL.md describes both entries" begin
    @test p615n_build("s2a")
    p = joinpath(P615N_S2A, "EMAIL.md")
    t = isfile(p) ? read(p, String) : ""
    @test !isempty(t)
    paras = p615n_paras(t)
    for re in (r"^\s*#{1,6}\s"m, r"^\s*\|.*\|\s*$"m, r"\*\*", r"<[A-Za-z/][^>]*>", r"\]\(")
        @test !occursin(re, t)                                             # plain text
    end
    @test occursin("core.zip", t) && occursin(r"attach"i, t)
    for f in p615n_bulkfiles(P615N_S2A)
        @test occursin(f, t) && occursin(p615n_url(f), t)
    end
    @test occursin(r"\bR\b", t) && occursin(r"radius"i, t) && occursin(r"775\s*MCS", t)
    @test occursin(P615N_LABEL, t) && occursin(P615N_KEY, t) && occursin(P615N_RGB, t)
    @test any(q -> occursin(r"checkerboard"i, q) && occursin("$(P615N_CYCLE) MCS", q) && occursin(string(P615N_TCB), q) &&
                   occursin(string(P615N_T_SEQ), q), paras)
    @test any(q -> occursin(r"checkerboard"i, q) && occursin(r"thinning|conflicting"i, q) && occursin(r"claim"i, q), paras)
    nd = length(p615n_devs())
    @test nd > 0 && any(q -> occursin(r"checkerboard"i, q) && occursin(Regex("\\b$nd\\b"), q), paras)
    @test any(q -> occursin(r"\bQ15\b", q) && occursin(r"Fig(ures?|s|\.)?\s*5"i, q), paras)
    @test any(q -> occursin(r"\bQ26\b", q) && occursin(r"Fig(ures?|s|\.)?\s*7"i, q), paras)
    @test occursin(r"actual area"i, t) && occursin(r"target area"i, t)
    for fw in P615N_BOTH
        miss = p615n_missing_notes(replace(t, '`' => ""), fw)
        filter!(n -> n in ("N5", "N6"), miss)                             # N1–N4 as in 15_openvt_d213.jl
        isempty(miss) || @info "P6.15m m4 EMAIL.md lacks for $fw" miss
        @test isempty(miss)
    end
    @test !occursin(P615N_CLOSED_Q, t)
    bad = [re.pattern for re in P615N_NO_QUESTIONS if occursin(re, replace(t, r"https?://\S+" => ""))]
    append!(bad, p615n_forbidden(t; email = true))
    isempty(bad) || @info "P6.15m m4 EMAIL.md forbidden" bad
    @test isempty(bad)
    @test !occursin(P615N_OUT, t) && !occursin(P615N_ROOT, t)
end

end  # bulk tier

# free the builds' disk space (several GB)
rm(P615N_OUT; recursive = true, force = true)
