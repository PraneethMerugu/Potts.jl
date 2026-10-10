# P6.15l (ROADMAP Step 3b; D-213, D-215): the OpenVT package made easy to e-mail (Q11
# replaced), its conformance to the consortium repository's scripts (D-215), and the Q25
# wording (Q25 closed by maintainer ruling, not asked). Frozen (AUTONOMY §7.3). This file adds
# to `15_openvt_package.jl` (the unsplit package; amended for D-215 in the same freeze) and
# `15_openvt_page.jl` (page 15's layout, unchanged). Nothing here sends, uploads or contacts
# anyone: the release asset is created only with the maintainer's OK at that moment (D-213
# (b)), and the cover note is a draft the maintainer pastes (D-213 (c)).
#
# Sources: D-213 (Q25 closed: "M is followed (actual area); the released TST model divides on
# target area", rows marked "not asked (maintainer ruling: M over TST)"; Q11 replaced by
# (a)–(d)); D-215 (the audit: names, columns, the split's sides, the README/EMAIL notes, the
# framework token); spec 15 §7 at da81b245 (Q15, Q23, Q24 and Q26 open, so rows may keep
# naming them; Q25 resolved; Q19, Q20 and Q21 CLOSED, not asked, under D-213: "Potts follows
# M; this framework's departure is recorded, not queried"); D-180/D-204/D-206 (the package and its bulk
# directory); D-211/D-212 (Figs 5, 7, 8; Q26); D-214 (a second entry later, P6.15m).
#
# The framework token <FW> is P615L_FW ("Potts.jl"; D-215 (9): a parameter without spaces,
# "Potts.jl_checkerboard" for P6.15m). Nothing below spells it except through P615L_FW. The
# repository name in URLs, PraneethMerugu/Potts.jl, is the repository, not the token.
#
# ---------------------------------------------------------------------------------------------
# A. The e-mail split (D-213 (a)–(d), D-215 (7))
# ---------------------------------------------------------------------------------------------
#   r = PottsModels.openvt_submission_package(outdir; split = :email,
#           release_tag = PottsModels.OPENVT_BULK_RELEASE_TAG,
#           bulk = get(ENV, "OPENVT_PACKAGE_BULK", nothing))
# writes exactly three entries under `outdir`:
#   core.zip   ≤ P615L_CORE_MAX bytes (20 MB, D-213 (a)); it unpacks at the consortium
#              repository's root: every member is under implementations/<FW>/ or results/<FW>/
#   bulk/      flat: the files that go to a public pre-release, each < P615L_BULK_MAX, to be
#              dropped into results/<FW>/Monolayer/ and left zipped (D-215 (7))
#   EMAIL.md   the plain-text cover note
# and returns a value with `core_bytes` (= filesize of core.zip) and `bulk_bytes` (= the summed
# sizes of the files in bulk/): the "reports both sizes" of D-213 (d). It may also print them.
# The same refusals as the unsplit build hold (non-empty outdir, outdir in git, a bad bulk
# directory; nothing left behind). Any other `split` value is an `ArgumentError`. The default
# (no `split`) is the unsplit build U of `15_openvt_package.jl`: it returns `outdir` and writes
# only `implementations/` and `results/`.
#
# The split of U (same commit, same bulk directory):
#   - bulk/ holds exactly U's O1 archives, its O2 zip and its O1 manifest CSV (D-215 (7);
#     P615L_BULK_CLASSES, the package test's D-215 names), each under its U base name and
#     byte-identical to the U file results/<FW>/Monolayer/<name>: `cases + 2` files.
#   - core.zip holds every other U file at its U path, byte-identical, with no directory
#     entries: the READMEs, parameters, model source, runners, O3/O4/O5, Table 1
#     (<FW>_table1.csv), the per-run metrics, means and neighbours, A3, Table S5, the figure
#     PNGs, the closeup and the provenance (P615L_CORE_KINDS must each be present). The only
#     exception: README*.md members may differ from U (the bulk links), and README*.md members
#     not in U may be added (under the two roots).
#
# Sizes. Measured at base 21d3b544 on this Mac (2026-10-10), zipping the pre-D-215 unsplit
# tree with `zip -X -D -9` in sorted order: everything but the O1 archives 19 421 166 B (the
# audit: 19.43 MB, 2.9 % under the limit), without O2 15 641 312 B; O2 alone 3 774 476 B
# zipped; O1 manifest CSV 6 374 590 B raw; O1 archives 86 156 848 (a), 68 252 726 (b),
# 114 094 168 (e), 52 938 304 (f) B (+ the g column after D-215). Bulk ≈ 330 MB, each file
# far below 2 GB. After D-215, measured on a prototype of the post-processing (g column,
# D-215 names) and a stub split (2026-10-10, before this freeze): core.zip 13 451 156 B; bulk/
# 338 214 282 B in 6 files: O1 87 055 263 (a), 69 799 073 (b), 115 442 502 (e), 54 424 923 (f),
# O2 zip 3 774 472, O1 manifest CSV 7 718 049.
#
# Release links (placeholder pattern, chosen here). The pre-release does not exist yet. Each
# bulk zip is linked as
#     https://github.com/PraneethMerugu/Potts.jl/releases/download/<tag>/<file>
# with <tag> = the `release_tag` keyword, default `PottsModels.OPENVT_BULK_RELEASE_TAG` (a
# constant String of [A-Za-z0-9._-], e.g. "openvt-monolayer-package-<date>"; its value is the
# implementer's, so the maintainer creates the pre-release under that tag, or rebuilds with
# another). <file> = the bulk zip's file name. A core README line holds the file name, its
# sha256 (64 lower-case hex of the bulk file's bytes) and that URL. A build with another tag
# changes only README*.md members and EMAIL.md; bulk/ is byte-identical.
#
# EMAIL.md (D-213 (c)): plain text, no Markdown headings, tables, bold, HTML or [text](url)
# links. It names core.zip as attached, every bulk file as linked (file name and URL), the
# units (R, the cell radius; a cycle is 775 MCS), the open questions Q15 (Fig 5 distance unit)
# and Q26 (Fig 7/8 labels), and summarises the deviations: every non-control FAIL row id of
# the records (today V1, V2.1.1x, V3b, V4.2, V4.3, V4.5), "actual area" and "target area".
#
# D-215 (8) notes, in EMAIL.md and in the results README (unsplit, and the core's), each in one
# paragraph (or list item, or line) that holds all of its parts:
#   N1  run_metrics.sh's `seq 0 10000` drops files with MCS above 10000 (or 10 000), and our
#       precomputed measurements are complete: "run_metrics.sh", "seq 0 10000", "complete";
#   N2  the large zips may need Git LFS on the consortium repository's side: "LFS";
#   N3  lengths in R with the origin at the lattice centre: "R" and "lattice cent(re|er)";
#   N4  only R is shipped, no px: "R" and "px" and one of "only", "no", "not";
#   N5  each entry needs one line added to the framework lists the consortium's scripts
#       hard-code: "hard-coded"/"hardcoded", "framework" and "line";
#   N6  the bulk files go into results/<FW>/Monolayer/ and stay zipped: that path and "zip".
# No Q25. No e-mail addresses, no names of private individuals or titles before names, no
# hostnames, IP addresses or local paths, and nothing saying anything was sent or that
# contact was made (the package test's list P615J_FORBIDDEN, copied here as P615L_FORBIDDEN,
# plus P615L_EMAIL_FORBIDDEN). Every text member of core.zip gets the package test's list,
# and its README*.md members the cover note's list too.
#
# Determinism: two split builds give the same entries and the same bytes (core.zip, every
# bulk file, EMAIL.md). Zip entries carry a DOS time stamp: it must not come from the clock.
#
# ---------------------------------------------------------------------------------------------
# B. Q25 wording (D-213)
# ---------------------------------------------------------------------------------------------
# In page 15 (Literate comments, `# ` stripped) and in both package READMEs (unsplit and the
# core's), outside dated change-log rows (first cell YYYY-MM-DD):
#   B1  the sentence P615L_Q25 = "M is followed (actual area); the released TST model divides
#       on target area" appears (page and results README; whitespace normalised, `\*` read as
#       `*`), in a paragraph or table cell with no Q#, no "open question" and no "?";
#   B2  no "Q25", "Q19", "Q20" or "Q21" anywhere (all closed, not asked; spec 15 §7);
#   B3  any prose paragraph, and any table cell except a row's last (status) cell, that speaks
#       of the division trigger (P615L_DIVISION: division/divides on target area, target-area
#       division, "TST uses/on the target area", "division trigger", C13, max_cell_count —
#       the latter the old "Q23" note on the released TST's 1000-cell exit, which D-211
#       renumbered Q25(b)) names no Q#, says no "open question" and asks no "?";
#   B4  in every table with an "Author question" column, a row whose other cells cite TST's
#       target-area rule (P615L_TARGET_DIV), and the rows V1, V4.2, V4.3, V4.5 and C13, have
#       a status starting "not asked (maintainer ruling: M over TST)". The other rows that
#       cited the closed Q20 or Q21 (P615L_FW_KEYS: V2.1.1x and F3.4, Q20; C17, Q21, the
#       Morpheus σ) have a status starting with that prefix or with "not asked (M over the
#       framework's code)". Open questions may follow (Q23 and Q24 are still open in spec 15
#       §7; also Q15, Q26), with "our open question list". Those rows keep their reading:
#       page and results README each still have V1, V4.2, V4.3, V4.5 and C13 rows (the frozen
#       tests pin their values).
# EMAIL.md follows B2 and B3.
using Test, TOML, SHA, PottsModels

const P615L_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const P615L_DATA = joinpath(P615L_ROOT, "lib", "PottsModels", "reproductions", "data", "15")
const P615L_PAGE = joinpath(P615L_ROOT, "lib", "PottsModels", "reproductions", "15_openvt_monolayer.jl")
const P615L_BULK_ENV = "OPENVT_PACKAGE_BULK"
const P615L_BULK = get(ENV, P615L_BULK_ENV, "")
const P615L_CORE_MAX = 20_000_000                 # bytes, D-213 (a)
const P615L_BULK_MAX = 2_000_000_000              # bytes, strictly below (GitHub asset < 2 GiB)
const P615L_RELEASE_BASE = "https://github.com/PraneethMerugu/Potts.jl/releases/download/"
const P615L_ALT_TAG = "p615l-tag-check"
const P615L_RULING = "not asked (maintainer ruling: M over TST)"
const P615L_Q25 = "M is followed (actual area); the released TST model divides on target area"
const P615L_RULED_KEYS = ["V1", "V4.2", "V4.3", "V4.5", "C13"]
const P615L_RULING_FW = "not asked (M over the framework's code)"
const P615L_FW_KEYS = ["V2.1.1x", "F3.4", "C17"]               # cited Q20 or Q21 before their closure
const P615L_CLOSED_Q = r"\bQ(19|20|21|25)\b"                     # closed, not asked (D-213; spec 15 §7)
const P615L_TARGET_DIV = r"divid\w*\s+on\s+(the\s+)?target[- ]area|division\s+on\s+(the\s+)?target[- ]area|target[- ]area\s+division|TST,?\s+(uses|on)\s+(the\s+)?target[- ]area"i
const P615L_DIVISION = Regex(P615L_TARGET_DIV.pattern * raw"|division trigger|\bC13\b|max_cell_count", "i")
const P615L_QUESTION = r"\bQ\d+\b|open question|\?"i

# the framework token (D-214, D-215 (9)); see the header
const P615L_FW = "Potts.jl"
# a pattern with {FW} standing for the escaped framework token
p615l_re(pat) = Regex(replace(pat, "{FW}" => "\\Q" * P615L_FW * "\\E"))
const P615L_RES_README = "results/$(P615L_FW)/README.md"
const P615L_IMPL_README = "implementations/$(P615L_FW)/README.md"

# the bulk classes (D-215 (5), (3), (7); the package test's names; paths relative to outdir)
const P615L_MONO = "results/$(P615L_FW)/Monolayer/"
const P615L_O1_RE = p615l_re(raw"^results/{FW}/Monolayer/{FW}_(beta[0-9.]+_gamma[0-9.]+|No_CI_[a-z]+|case_[a-z]+)\.zip$")
const P615L_O2_RE = p615l_re(raw"^results/{FW}/Monolayer/{FW}_5T_MonolayerGrowth_1000_Data\.zip$")
const P615L_O1M_RE = p615l_re(raw"^results/{FW}/Monolayer/{FW}_centroids_manifest\.csv$")
const P615L_BULK_CLASSES = [P615L_O1_RE, P615L_O2_RE, P615L_O1M_RE]
# kinds the core must hold (D-213 (a)), by the package test's existing paths
const P615L_CORE_KINDS = [
    "README (implementations)" => p615l_re(raw"^implementations/{FW}/README\.md$"),
    "README (results)" => p615l_re(raw"^results/{FW}/README\.md$"),
    "parameters" => p615l_re(raw"^implementations/{FW}/parameters\.csv$"),
    "model source" => p615l_re(raw"^implementations/{FW}/src/openvt_reference\.jl$"),
    "runners" => p615l_re(raw"^implementations/{FW}/scripts/[^/]+/[^/]+\.jl$"),
    "O3 (Table 1, Fig 6)" => p615l_re(raw"^results/{FW}/Monolayer/{FW}_time_to_10k_vs_(beta|gamma)\.csv$"),
    "O4 relaxation" => p615l_re(raw"^results/{FW}/Relaxation/.+_?width\.csv$"),
    "Table S5" => p615l_re(raw"^results/{FW}/Relaxation/table_S5\.csv$"),
    "O5" => p615l_re(raw"^results/{FW}/Monolayer/final_snapshot_data/{FW}_beta_[0-9.eE+-]+_gamma_[0-9.eE+-]+_\d+MCS\.csv$"),
    "Table 1" => p615l_re(raw"^results/{FW}/Monolayer/{FW}_table1\.csv$"),
    "per-run metrics" => p615l_re(raw"^results/{FW}/Monolayer/metrics/[a-z]+/measurements_s\d+\.csv$"),
    "means" => p615l_re(raw"^results/{FW}/Monolayer/metrics/measurements_[a-z]+_mean\.csv$"),
    "neighbours" => p615l_re(raw"^results/{FW}/Monolayer/metrics/neighbors_[a-z]+\.csv$"),
    "A3" => p615l_re(raw"^results/{FW}/Monolayer/metrics/[a-z]+/inhibition_s\d+\.csv$"),
    "figures" => p615l_re(raw"^results/{FW}/figures/fig[578]\.png$"),
    "closeup" => p615l_re(raw"^results/{FW}/closeup\.png$"),
    "provenance" => p615l_re(raw"^results/{FW}/provenance/[^/]+\.toml$"),
]
# the D-215 (8) notes: name => (predicate on one paragraph)
const P615L_NOTES = [
    "N1 run_metrics.sh truncation; ours complete" =>
        p -> occursin("run_metrics.sh", p) && occursin(r"seq 0 10000", p) && occursin(r"complete"i, p),
    "N2 LFS" => p -> occursin(r"\bLFS\b", p),
    "N3 R, origin at the lattice centre" => p -> occursin(r"\bR\b", p) && occursin(r"lattice cent(re|er)"i, p),
    "N4 only R, no px" => p -> occursin(r"\bR\b", p) && occursin(r"\bpx\b", p) && occursin(r"\b(only|no|not)\b"i, p),
    "N5 one line in the hard-coded framework lists" =>
        p -> occursin(r"hard-?coded"i, p) && occursin(r"framework"i, p) && occursin(r"\bline\b"i, p),
    "N6 bulk into results/<FW>/Monolayer/, zipped" => p -> occursin(P615L_MONO, p) && occursin(r"zip"i, p),
]
# paragraphs: blank-line separated, and each list item or table row on its own
p615l_paras(t) = vcat([String.(split(q, r"\n(?=\s*(?:[-*]|\d+\.)\s|\s*\|)")) for q in split(t, r"\n\s*\n")]...)
p615l_missing_notes(t) = [n for (n, f) in P615L_NOTES if !any(f, p615l_paras(t))]

# the package test's privacy and no-contact list (15_openvt_package.jl, P615J_FORBIDDEN)
const P615L_FORBIDDEN = [
    r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i,
    r"docs/references"i, r"POTTS_REFERENCES", r"manuscript-draft"i,
    r"correspondence"i, r"\be-?mails?\b"i, r"\basked on\b"i, r"\bwe (have )?(asked|wrote|sent|contacted|emailed)\b"i,
    r"\bcontacted (the|R\.|Dr)"i, r"\banswered by\b"i, r"personal communication"i,
    r"\bletters? (to|from)\b"i, r"\bsubmitted to\b"i,
    r"praneeth"i, r"merugu"i, r"jiang"i, r"\bPI\b", r"nucbox"i, r"tailscale"i, r"100\.107\.",
    r"/Users/", r"/home/", r"/private/", r"/tmp/", r"\.claude", r"scratchpad"i,
]
# more for the cover note and the core: addresses, people, machines, paths, implied contact
const P615L_EMAIL_FORBIDDEN = [
    r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}",   # e-mail addresses
    r"vetter"i, r"\b(Dr|Prof|Mr|Ms|Mrs)\.?\s+[A-Z]",                        # people
    r"\b\d{1,3}(\.\d{1,3}){3}\b", r"\.local\b"i, r"\.lan\b"i, r"\bhostname\b"i, r"localhost"i,
    r"/Volumes/", r"/var/", r"/opt/", r"/mnt/", r"~/", r"\$HOME", r"\b[A-Za-z]:\\(?=\w)", r"potts-bulk"i,
    r"\b(has|have|had|was|were|is|are)\s+(already\s+)?(been\s+)?(sent|e-?mailed|mailed|forwarded|delivered|submitted)\b"i,
    r"\bas (we )?(discussed|agreed|promised|requested)\b"i, r"\b(our|your) (previous|earlier|last) (message|mail|note|exchange|call|meeting)\b"i,
    r"\bthank(s| you) for (your|the) (reply|response|message|answer|note)\b"i, r"\bin (reply|response) to\b"i,
    r"\bfollow(ing)?[- ]up\b"i, r"\bper (your|our)\b"i,
]

# ---- helpers ------------------------------------------------------------------------------------
p615l_tree(dir) = sort([replace(relpath(joinpath(r, f), dir), '\\' => '/') for (r, _, fs) in walkdir(dir) for f in fs])
p615l_sha(path) = bytes2hex(open(sha256, path))
function p615l_in_git(path)
    d = abspath(path)
    while true
        ispath(joinpath(d, ".git")) && return true
        p = dirname(d)
        p == d && return false
        d = p
    end
end
p615l_zip_names(z) = filter(!isempty, readlines(`unzip -Z1 $z`))
p615l_zip_read(z, m) = read(`unzip -p $z $m`)
p615l_isreadme(p) = occursin(r"^README[^/]*\.md$"i, basename(p))
p615l_tsv(path) = (ls = filter(!isempty, split(read(path, String), '\n'));
                   h = split(ls[1], '\t'); [Dict(zip(h, split(l, '\t'))) for l in ls[2:end]])
function p615l_records()
    recs = Dict{String, String}()
    for d in sort(readdir(P615L_DATA))
        p = joinpath(P615L_DATA, d, "provenance.toml")
        isfile(p) && (recs[get(TOML.parsefile(p), "item", "")] = d)
    end
    return recs
end
const P615L_RECS = p615l_records()

# the non-control FAIL row ids of the records (as the package test's deviations check)
function p615l_fail_keys()
    keys_ = String[]
    for d in readdir(P615L_DATA)
        p = joinpath(P615L_DATA, d, "deviations.tsv")
        isfile(p) && append!(keys_, [String(split(r["target"])[1]) for r in p615l_tsv(p) if occursin("FAIL", r["target"])])
        p = joinpath(P615L_DATA, d, "verdicts.tsv")
        isfile(p) || continue
        for r in p615l_tsv(p)
            get(r, "result", "") == "FAIL" || continue
            get(r, "case", "") == "control" && continue
            occursin(r"must FAIL"i, get(r, "band", "")) && continue
            occursin("(all rows)", r["target"]) && continue
            push!(keys_, String(split(r["target"])[1]))
        end
    end
    return sort(unique(keys_))
end

# text units: prose paragraphs and table rows (cells), dated change-log rows dropped. For a
# Literate page, comment lines lose their "# " and code lines separate paragraphs.
p615l_norm(s) = replace(replace(String(s), "\\*" => "*", "\\_" => "_"), r"\s+" => " ") |> strip |> String
function p615l_units(text; literate = false)
    paras, rows, cur = String[], Vector{Vector{String}}(), String[]
    flush() = (isempty(cur) || push!(paras, p615l_norm(join(cur, ' '))); empty!(cur))
    tbreak() = (isempty(rows) || isempty(last(rows)) || push!(rows, String[]))    # a table ends
    for raw in split(text, '\n')
        l = raw
        if literate
            m = match(r"^\s*#(?: (.*)|)$", l)
            m === nothing && (flush(); tbreak(); continue)
            l = something(m.captures[1], "")
        end
        s = strip(l)
        if isempty(s)
            flush(); tbreak()
        elseif startswith(s, "|") && endswith(s, "|")
            flush()
            occursin(r"^\|[\s:|-]+\|$", s) && continue
            cells = String.(p615l_norm.(split(strip(s, '|'), '|')))
            occursin(r"^\d{4}-\d{2}-\d{2}$", cells[1]) && continue        # dated change-log row
            push!(rows, cells)
        else
            tbreak()
            push!(cur, String(s))
        end
    end
    flush()
    return paras, rows                     # rows: table rows, an empty row between tables
end
# tables with an "Author question" column: their data rows
function p615l_status_rows(text; literate = false)
    _, rows = p615l_units(text; literate)
    out, intable = Vector{Vector{String}}(), false
    for r in rows
        if isempty(r)
            intable = false
        elseif any(c -> occursin(r"^Author question"i, c), r)
            intable = true
        elseif intable && length(r) >= 3
            push!(out, r)
        end
    end
    return out
end
p615l_key(cells, key) = occursin(Regex("^\\Q" * key * "\\E(?![0-9A-Za-z.])"), cells[1])

# B1–B4 on one text; returns a list of findings (empty = pass)
function p615l_q25_findings(name, text; literate = false, need_sentence = true, need_rows = true)
    bad = String[]
    paras, rows = p615l_units(text; literate)
    units = vcat(paras, [c for r in rows if length(r) > 1 for c in r[1:(end - 1)]])
    # B1
    if need_sentence
        hits = filter(u -> occursin(P615L_Q25, u), units)
        isempty(hits) && push!(bad, "$name: B1 sentence missing")
        any(u -> occursin(P615L_QUESTION, u), hits) && push!(bad, "$name: B1 sentence carries a question")
    end
    # B2 (status cells included)
    for u in vcat(paras, [c for r in rows for c in r])
        m = match(P615L_CLOSED_Q, u)
        m === nothing || push!(bad, "$name: B2 names $(m.match): " * first(u, 100))
    end
    # B3
    for u in units
        occursin(P615L_DIVISION, u) && occursin(P615L_QUESTION, u) &&
            push!(bad, "$name: B3 " * first(u, 160))
    end
    # B4
    srows = p615l_status_rows(text; literate)
    for r in srows
        ruled = any(k -> p615l_key(r, k), P615L_RULED_KEYS) || any(c -> occursin(P615L_TARGET_DIV, c), r[1:(end - 1)])
        ruled && !startswith(r[end], P615L_RULING) && push!(bad, "$name: B4 status of $(first(r[1], 40)): $(first(r[end], 60))")
        fw = !ruled && any(k -> p615l_key(r, k), P615L_FW_KEYS)
        fw && !(startswith(r[end], P615L_RULING) || startswith(r[end], P615L_RULING_FW)) &&
            push!(bad, "$name: B4 status of $(first(r[1], 40)): $(first(r[end], 60))")
    end
    if need_rows
        for k in P615L_RULED_KEYS
            any(r -> p615l_key(r, k), srows) || push!(bad, "$name: B4 no $k row")
        end
    end
    return bad
end

# ---- builds ---------------------------------------------------------------------------------------
const P615L_OUT = mktempdir()
const P615L_U = joinpath(P615L_OUT, "unsplit")
const P615L_S1 = joinpath(P615L_OUT, "split1")
const P615L_S2 = joinpath(P615L_OUT, "split2")
const P615L_S3 = joinpath(P615L_OUT, "split_tag")
const P615L_RET = Dict{String, Any}()
const P615L_ERR = Dict{String, Any}()
p615l_withbulk(f) = withenv(f, P615L_BULK_ENV => (isempty(P615L_BULK) ? nothing : P615L_BULK))
function p615l_build(which)
    haskey(P615L_RET, which) && return true
    haskey(P615L_ERR, which) && return false
    try
        P615L_RET[which] = p615l_withbulk() do
            if which == "unsplit"
                PottsModels.openvt_submission_package(P615L_U)
            elseif which == "split1"
                PottsModels.openvt_submission_package(P615L_S1; split = :email)
            elseif which == "split2"
                p615l_build("split1"); sleep(1.1)            # a clock tick between the two builds
                PottsModels.openvt_submission_package(P615L_S2; split = :email)
            else
                PottsModels.openvt_submission_package(P615L_S3; split = :email, release_tag = P615L_ALT_TAG)
            end
        end
        return true
    catch e
        P615L_ERR[which] = e
        @info "P6.15l: the $(which) build failed" exception = (e, catch_backtrace())
        return false
    end
end
p615l_tag() = isdefined(PottsModels, :OPENVT_BULK_RELEASE_TAG) ? PottsModels.OPENVT_BULK_RELEASE_TAG : nothing
p615l_bulkfiles(s) = (d = joinpath(s, "bulk"); isdir(d) ? sort(readdir(d)) : String[])
p615l_url(tag, f) = P615L_RELEASE_BASE * "$(tag)/$(f)"

@testset "P6.15l (A0) inputs" begin
    @test !isempty(P615L_BULK) && isdir(P615L_BULK) && !p615l_in_git(P615L_BULK)
    @test Sys.which("unzip") !== nothing
    @test haskey(P615L_RECS, "P6.15g") && isfile(joinpath(P615L_DATA, P615L_RECS["P6.15g"], "table1.tsv"))
    tag = p615l_tag()
    @test tag isa String && occursin(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", tag) && tag != P615L_ALT_TAG
end

@testset "P6.15l (A1) the unsplit default is unchanged; split refusals" begin
    @test p615l_build("unsplit")
    @test get(P615L_RET, "unsplit", nothing) == P615L_U
    @test isdir(P615L_U) && sort(readdir(P615L_U)) == ["implementations", "results"]
    # an unknown split is refused
    out = joinpath(mktempdir(), "pkg")
    @test_throws ArgumentError p615l_withbulk(() -> PottsModels.openvt_submission_package(out; split = :p615l_nonsense))
    @test !ispath(out) || isempty(readdir(out))
    # the split build keeps the unsplit refusals: a non-empty outdir, no bulk directory
    full = mktempdir(); write(joinpath(full, "stale.txt"), "x")
    @test_throws ArgumentError p615l_withbulk(() -> PottsModels.openvt_submission_package(full; split = :email))
    @test readdir(full) == ["stale.txt"]
    out2 = joinpath(mktempdir(), "pkg")
    threw = try
        withenv(() -> PottsModels.openvt_submission_package(out2; split = :email), P615L_BULK_ENV => nothing)
        false
    catch e
        e isa ArgumentError
    end
    @test threw
    @test !ispath(out2) || isempty(readdir(out2))
end

@testset "P6.15l (A2) split = :email: layout, sizes, the reported sizes" begin
    @test p615l_build("split1")
    @test isdir(P615L_S1) && sort(readdir(P615L_S1)) == ["EMAIL.md", "bulk", "core.zip"]
    core = joinpath(P615L_S1, "core.zip")
    @test isfile(core)
    isfile(core) && @info "P6.15l core.zip" bytes = filesize(core)
    @test isfile(core) && filesize(core) <= P615L_CORE_MAX
    bf = p615l_bulkfiles(P615L_S1)
    @test !isempty(bf) && all(f -> isfile(joinpath(P615L_S1, "bulk", f)), bf)          # flat
    for f in bf
        @test filesize(joinpath(P615L_S1, "bulk", f)) < P615L_BULK_MAX
    end
    @info "P6.15l bulk/" sizes = [f => filesize(joinpath(P615L_S1, "bulk", f)) for f in bf]
    r = get(P615L_RET, "split1", nothing)
    @test r !== nothing && hasproperty(r, :core_bytes) && hasproperty(r, :bulk_bytes)
    if r !== nothing && hasproperty(r, :core_bytes) && hasproperty(r, :bulk_bytes) && isfile(core)
        @test r.core_bytes == filesize(core)
        @test r.bulk_bytes == sum(f -> filesize(joinpath(P615L_S1, "bulk", f)), bf; init = 0)
    end
end

@testset "P6.15l (A3) deterministic: same bytes twice" begin
    @test p615l_build("split1") && p615l_build("split2")
    if isdir(P615L_S1) && isdir(P615L_S2)
        t1, t2 = p615l_tree(P615L_S1), p615l_tree(P615L_S2)
        @test t1 == t2
        for f in intersect(t1, t2)
            @test read(joinpath(P615L_S1, f)) == read(joinpath(P615L_S2, f))
        end
    end
end

@testset "P6.15l (A4) core.zip and bulk/ cover the unsplit package exactly once (D-215 (7))" begin
    @test p615l_build("unsplit") && p615l_build("split1")
    U = isdir(P615L_U) ? p615l_tree(P615L_U) : String[]
    core = joinpath(P615L_S1, "core.zip")
    @test !isempty(U) && isfile(core)
    mem = (isempty(U) || !isfile(core)) ? String[] : p615l_zip_names(core)
    @test !isempty(mem)
    if !isempty(mem)
        @test allunique(mem) && !any(m -> endswith(m, "/"), mem)
        # unpacks at the consortium repository's root
        roots = ("implementations/$(P615L_FW)/", "results/$(P615L_FW)/")
        @test all(m -> any(r -> startswith(m, r), roots), mem)
        # members are U paths with U's bytes, README*.md excepted
        extra = filter(m -> !(m in U) && !p615l_isreadme(m), mem)
        @test isempty(extra)
        isempty(extra) || @info "P6.15l core members not in the unsplit package" first(extra, 10)
        diffbytes = String[]
        for m in mem
            (m in U && !p615l_isreadme(m)) || continue
            p615l_zip_read(core, m) == read(joinpath(P615L_U, m)) || push!(diffbytes, m)
        end
        @test isempty(diffbytes)
        # bulk/: exactly U's bulk-class files, by base name, byte-identical; cases + 2 files
        isbulk(u) = any(re -> occursin(re, u), P615L_BULK_CLASSES)
        ub = filter(isbulk, U)
        @test all(u -> startswith(u, P615L_MONO) && !occursin('/', u[(length(P615L_MONO) + 1):end]), ub)
        o1 = filter(u -> occursin(P615L_O1_RE, u), U)
        @test !isempty(o1) && count(u -> occursin(P615L_O2_RE, u), U) == 1 && count(u -> occursin(P615L_O1M_RE, u), U) == 1
        bf = p615l_bulkfiles(P615L_S1)
        @test sort(bf) == sort(basename.(ub))
        @test length(bf) == length(o1) + 2
        for f in bf
            u = P615L_MONO * f
            @test u in ub && read(joinpath(P615L_S1, "bulk", f)) == read(joinpath(P615L_U, u))
        end
        # every U file exactly once: core (at its U path) or bulk
        incore = Set(m for m in mem if m in U)
        @test incore == Set(filter(!isbulk, U))
        @test isempty(intersect(incore, Set(ub)))
        # D-213 (a)'s kinds are in the core
        for (kind, re) in P615L_CORE_KINDS
            ok = any(m -> occursin(re, m), mem)
            ok || @info "P6.15l core lacks" kind
            @test ok
        end
    end
end

# the core's README*.md texts
p615l_core_readmes(s) = (z = joinpath(s, "core.zip"); isfile(z) ?
                         [m => String(p615l_zip_read(z, m)) for m in p615l_zip_names(z) if p615l_isreadme(m)] : Pair{String, String}[])

@testset "P6.15l (A5) core README: bulk links (placeholder pattern), D-215 notes; another tag" begin
    @test p615l_build("split1")
    tag = p615l_tag()
    rd = p615l_core_readmes(P615L_S1)
    @test !isempty(rd)
    lines = [l for (_, t) in rd for l in split(t, '\n')]
    bf = p615l_bulkfiles(P615L_S1)
    @test !isempty(bf)
    for f in bf
        sha = p615l_sha(joinpath(P615L_S1, "bulk", f))
        ok = tag isa String && any(l -> occursin(f, l) && occursin(sha, l) && occursin(p615l_url(tag, f), l), lines)
        ok || @info "P6.15l: no README line with the name, sha256 and URL of" f
        @test ok
    end
    # D-215 (8) notes in the core's results README
    rr = [t for (m, t) in rd if m == P615L_RES_README]
    @test length(rr) == 1
    miss = length(rr) == 1 ? p615l_missing_notes(only(rr)) : first.(P615L_NOTES)
    isempty(miss) || @info "P6.15l core results README lacks" miss
    @test isempty(miss)
    # another tag: only README*.md members and EMAIL.md change; bulk/ byte-identical
    @test p615l_build("split_tag")
    if isdir(P615L_S3) && isdir(P615L_S1)
        @test p615l_bulkfiles(P615L_S3) == bf
        @test all(f -> read(joinpath(P615L_S3, "bulk", f)) == read(joinpath(P615L_S1, "bulk", f)), bf)
        z1, z3 = joinpath(P615L_S1, "core.zip"), joinpath(P615L_S3, "core.zip")
        if isfile(z1) && isfile(z3)
            m1, m3 = p615l_zip_names(z1), p615l_zip_names(z3)
            @test m1 == m3
            @test all(m -> p615l_isreadme(m) || p615l_zip_read(z1, m) == p615l_zip_read(z3, m), m1)
        end
        l3 = [l for (_, t) in p615l_core_readmes(P615L_S3) for l in split(t, '\n')]
        @test all(f -> any(l -> occursin(p615l_url(P615L_ALT_TAG, f), l), l3), bf)
        tag isa String && @test !any(l -> occursin(P615L_RELEASE_BASE * tag * "/", l), l3)
        e3 = joinpath(P615L_S3, "EMAIL.md")
        @test isfile(e3) && all(f -> occursin(p615l_url(P615L_ALT_TAG, f), read(e3, String)), bf)
    end
end

@testset "P6.15l (A6) EMAIL.md: a plain-text draft cover note" begin
    @test p615l_build("split1")
    p = joinpath(P615L_S1, "EMAIL.md")
    txt = isfile(p) ? read(p, String) : ""
    @test !isempty(txt)
    tag = p615l_tag()
    # plain text
    for re in (r"^\s*#{1,6}\s"m, r"^\s*\|.*\|\s*$"m, r"\*\*", r"<[A-Za-z/][^>]*>", r"\]\(")
        @test !occursin(re, txt)
    end
    # attached and linked
    @test occursin("core.zip", txt) && occursin(r"attach"i, txt)
    for f in p615l_bulkfiles(P615L_S1)
        @test occursin(f, txt) && tag isa String && occursin(p615l_url(tag, f), txt)
    end
    # units
    @test occursin(r"\bR\b", txt) && occursin(r"radius"i, txt)
    @test occursin(r"775\s*MCS", txt) && occursin(r"\bcycles?\b"i, txt)
    # the open questions Q15 (Fig 5 distance unit) and Q26 (Fig 7/8 labels); not Q25
    paras = split(txt, r"\n\s*\n")
    @test any(q -> occursin(r"\bQ15\b", q) && occursin(r"Fig(ures?|s|\.)?\s*5"i, q) && occursin(r"unit"i, q), paras)
    @test any(q -> occursin(r"\bQ26\b", q) && occursin(r"Fig(ures?|s|\.)?\s*7"i, q) && occursin(r"label"i, q), paras)
    # the deviations
    keys_ = p615l_fail_keys()
    @test !isempty(keys_)
    for k in keys_
        ok = occursin(Regex("(?<![0-9A-Za-z.])\\Q" * k * "\\E(?![0-9A-Za-z])"), txt)
        ok || @info "P6.15l EMAIL.md lacks the deviation" k
        @test ok
    end
    @test occursin(r"actual area"i, txt) && occursin(r"target area"i, txt)
    # D-215 (8) notes
    miss = p615l_missing_notes(txt)
    isempty(miss) || @info "P6.15l EMAIL.md lacks" miss
    @test isempty(miss)
    # B2, B3
    @test isempty(p615l_q25_findings("EMAIL.md", txt; need_sentence = false, need_rows = false))
    # nothing private, nothing implying contact
    s = replace(txt, "PraneethMerugu/Potts.jl" => "")
    bad = [re.pattern for re in vcat(P615L_FORBIDDEN, P615L_EMAIL_FORBIDDEN) if occursin(re, s)]
    isempty(bad) || @info "P6.15l EMAIL.md forbidden text" bad
    @test isempty(bad)
    occursin(P615L_OUT, txt) && @test false
    occursin(P615L_ROOT, txt) && @test false
end

@testset "P6.15l (A7) core.zip text: nothing private, nothing implying contact" begin
    @test p615l_build("split1")
    z = joinpath(P615L_S1, "core.zip")
    @test isfile(z)
    bad = String[]
    for m in (isfile(z) ? p615l_zip_names(z) : String[])
        any(e -> endswith(m, e), (".md", ".csv", ".toml", ".jl", ".txt")) || continue
        s = replace(String(p615l_zip_read(z, m)), "PraneethMerugu/Potts.jl" => "")
        # every text member: the package test's list; the generated READMEs also the cover
        # note's list (the runners are byte copies of the records and may name a hostname
        # call or a home-relative default, as in the unsplit package)
        for re in (p615l_isreadme(m) ? vcat(P615L_FORBIDDEN, P615L_EMAIL_FORBIDDEN) : P615L_FORBIDDEN)
            occursin(re, s) && push!(bad, "$m: $(re.pattern)")
        end
        occursin(P615L_OUT, s) && push!(bad, "$m: outdir")
        occursin(P615L_ROOT, s) && push!(bad, "$m: checkout path")
    end
    isempty(bad) || @info "P6.15l core forbidden text" first(bad, 20)
    @test isempty(bad)
end

@testset "P6.15l (B) Q25 wording (D-213) on page 15 and the package READMEs; D-215 notes" begin
    page = read(P615L_PAGE, String)
    f = p615l_q25_findings("page 15", page; literate = true)
    isempty(f) || @info "P6.15l page 15" f
    @test isempty(f)
    @test p615l_build("unsplit")
    for (rel, sentence) in ((P615L_RES_README, true), (P615L_IMPL_README, false))
        p = joinpath(P615L_U, rel)
        @test isfile(p)
        isfile(p) || continue
        f = p615l_q25_findings(rel, read(p, String); need_sentence = sentence, need_rows = sentence)
        isempty(f) || @info "P6.15l $rel" f
        @test isempty(f)
        if sentence                                  # D-215 (8) notes in the unsplit results README
            miss = p615l_missing_notes(read(p, String))
            isempty(miss) || @info "P6.15l $rel lacks" miss
            @test isempty(miss)
        end
    end
    # the core's READMEs too (the results README carries the sentence and the rows)
    @test p615l_build("split1")
    rd = p615l_core_readmes(P615L_S1)
    @test !isempty(rd)
    for (m, t) in rd
        full = m == P615L_RES_README
        f = p615l_q25_findings("core.zip:$m", t; need_sentence = full, need_rows = full)
        isempty(f) || @info "P6.15l core.zip:$m" f
        @test isempty(f)
    end
end
