# the docs page "OpenVT monolayer benchmark".
# The page is the Literate script
# `lib/PottsModels/reproductions/15_openvt_monolayer.jl`, so the existing docs hook renders it
# (`docs/make.jl` turns every script in `lib/PottsModels/reproductions/` into a "Published
# models" page under `POTTS_DOCS_PUBLISHED=true`), like reproductions 01, 09 and 10. This file
# reads the page source and the committed records only; it runs no simulation.
#
# What the page must carry (spec 15 §4.0 inventory and §1.1; D-146, D-154, D-156, D-161,
# D-168, D-172–D-175, D-185). Amended under D-185 for the page layout only: the order of
# (b), where the deviations and videos sit ((d), (e)), the pending wording and the F1 colour
# row; no verdict rule, band or record-value check changed.
# Amended under D-211 (the 9 Oct 2026 draft is M) for the figure numbering and the
# record artefacts only: M's metrics figure is now Figure 9 (the F3/F8 record's `fig8.png`,
# record names unchanged), M's new Figure 8 is the β colony grid (the Fig 8 β record, pending
# until its PC run lands), Figure 7 shows the grid render `fig7_grid.png` and Figure 5 the
# shared-bin render `fig5_shared.png`. The R1–R4 content checks are in `15_openvt_manuscript_draft_tests.jl`.
#
# (a) Title. The first Markdown heading is the H1 "OpenVT monolayer benchmark".
# (b) The D-185 order. Four level-2 headings, in this order: the model ("model"), a minimal
#     run ("minimal"), "Results" and "Details". The model section holds a ``julia listing of
#     `@potts_model OpenVTReferenceMonolayer`; every code line of it (comments and blank
#     lines dropped, whitespace trimmed) is a line of the model's source
#     `lib/PottsModels/src/openvt_reference.jl`, in the source's order, and the listing has
#     every `@`-macro line of the source (condensed, not paraphrased). The minimal-run
#     section runs code (a non-comment line calls `solve(`). Inside Results, level-3
#     headings in this order: Figure 2; Figure 5; Figure 1; Figures 3 and 9; Figures 6 and
#     7 with Table 1; Figure 8 (its own heading after that one, or named in it); the videos
#     ("video"); the verdict summary ("verdict"); "Deviations".
#     Details opens a raw-HTML `<details>` before its first level-3 heading and closes it
#     (`</details>`) after its last line, and holds level-3 headings for Figure 4, Table S1,
#     Table S5 and "Differences", and a protocol ("protocol") and provenance ("provenance")
#     heading. Every item of M (Figure 1–9, Table 1, Tables S1 and S5) has a heading that
#     names it ("Figure N", "Figures N and M", "Table N", …); its section runs to the next
#     heading of the same or a higher level.
# (c) Each item is either RENDERED from a merged record or PENDING:
#     - an item's records are the directories of `reproductions/data/15/` whose
#       `provenance.toml` has the item ID given for it in `ITEMS` below: F1, F4 the F1/F4 record; F2, S5 the calibration
#       record; F3, F9 the F3/F8 record; F5 the F5 record; F6, T1, F7 the sweeps record; F8 the Fig 8 β record. Table S1 is the parameter table and has no
#       record;
#     - RENDERED: the section names a record directory, the first 8 characters of its
#       commit, and its machine (the cpu up to " w/", or the hostname; case-insensitive),
#       all as literal text; and it shows the record's figure (the file name, which must
#       exist: F1 fig1.png, F2 fig2_bde.png, F3 fig3.png, F4 fig4.png, F5 fig5_shared.png,
#       F7 fig7_grid.png, F8 fig8_grid.png, F9 fig8.png; for the tables and F6 any .png, .svg
#       or .tsv of the
#       record). It does not say "pending". The record figures follow M's layout (their
#       READMEs and reproduction tests check it), so naming the file checks the layout;
#     - PENDING is allowed only for the sweeps items while no sweeps record is merged
#       (D-174), and for F8 while no Fig 8 β record is merged (D-211). The section then says
#       "pending: FULL run <state> (D-174)" (or "(D-211)"; <state> e.g. "parked" or "in
#       progress") and shows no image. When the record lands, the same items must be
#       RENDERED, with no edit to this file.
# (d) Deviations and differences (D-154). The level-3 "Deviations" heading of Results and
#     the level-3 "Differences" heading of Details. Every Markdown table in those sections
#     (rows are lines, after an optional Literate "# ", that start and end with "|") has a
#     header with "Ours", a paper column ("Paper", "Manuscript" or "M"), "cause" and
#     "Author question". The Deviations table (the four-column table of failed and
#     provisional targets) must include, keyed by their first cell:
#     - every row of every `data/15/*/deviations.tsv`, with the first decimal number of
#       its "ours" column and, when the target says FAIL, the word FAIL;
#     - every FAIL row of every `data/15/*/verdicts.tsv` that is not a negative control
#       (case "control" or a band that says "must FAIL") or an "(all rows)" summary, with
#       the word FAIL: today V4.2, V4.3 and V4.5. Failures are not hidden;
#     - V1: case (a) reaches 10⁴ cells at 15.17 cycles against 13.57 (about 12 % slow,
#       D-173), opening beyond 10³ cells, traced to division on actual area against TST's
#       target area (C13). The row names 15.17, 13.57, a percentage of 11–12 %, 10³ (or
#       1000), "actual area", "target area" and C13, and does not say PASS;
#     - F1: the panel's colour scale, coolwarm by area with provisional limits (D-185).
#     The rows of both tables together include every C# of spec 15 §1.1 (parsed from the
#     spec; at least C1–C17). Every row's last cell (the author-question status) starts with "not an author
#     question", "not asked" or "resolved"; a row that names a question (Q#) also says "our
#     open question list".
# (e) Videos (D-146, D-168, D-172, D-173). No video is committed: no .mp4, .webm, .mov,
#     .mkv or .gif under the page's asset directory `docs/src/assets/openvt_monolayer/` or
#     under `data/15/`. Every .mp4 the page names is a release download URL of this repo
#     (`https://github.com/PraneethMerugu/Potts.jl/releases/download/reproductions-…/`), not
#     a superseded release (area colours `reproductions-2026-10-07-openvt-f5`, or the
#     pre-D-172 palette `reproductions-2026-10-07-openvt-f5-cells`), and is a per-cell render
#     ("cells" in the file name). The six current assets are named in the Results' videos
#     section.
# (f) Stills (D-156, D-172). The page code draws no outlines (no `boundaries = true`, no
#     `pottsboundaries`), uses no `ChannelEncoding` (area heat maps), and any `pottsplot`
#     comes with `CellIdentityEncoding` or `CellTypeEncoding`.
# (g) G-derived content (D-147, D-168). Figures and small statistics only: every cited record
#     has a `provenance.toml` (40-hex commit, an item label, a clean tree, a runner inside
#     the record directory that exists), only .tsv/.csv/.toml/.md/.jl/.png/.svg files, none over
#     10 MB, and no consortium file names (closeup, cell_data_, relaxation_exact, Fig1_).
#     Every file under `docs/src/assets/openvt_monolayer/` is byte-identical to a file of a
#     `data/15/` record, or is listed in that directory's `provenance.toml` as
#     `[files."<path>"]` with `record` (a `data/15/` directory) and `kind` "figure" or
#     "statistics". Opt-in (`OPENVT_MONOLAYER_REPO` = a local G clone): no cited or asset
#     file is byte-identical to a G file.
# (h) Forbidden text. No private question sheet ("sheet", "PI_SHEET", "author-questions");
#     nothing from `docs/references/` (the path, `POTTS_REFERENCES`, the manuscript file
#     name, or the name of any PDF there when the directory is present; and, when present,
#     no cited or asset file byte-identical to one there); no implied contact with authors
#     or the consortium ("correspondence", e-mail, "asked on", "we asked/wrote/sent/
#     contacted", "contacted the", "answered by", "personal communication", "letter to/from",
#     "submitted to").
# (i) Docs. The page parses as Julia; `docs/make.jl` puts it in the navigation (by name, or
#     through the reproductions loop and the "Published models" or "Paper models" section). Opt-in
#     (`POTTS_DOCS_BUILD=true`): the standing docs suite runs,
#     `POTTS_DOCS_PUBLISHED=true julia --project=docs docs/make.jl`, and the built page
#     exists, has the title and every release URL, and each image it embeds is in the build.

@testsetup module OpenVTPageSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, TOML, SHA
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const PAGE = joinpath(ROOT, "lib", "PottsModels", "reproductions", "15_openvt_monolayer.jl")
const DATA = joinpath(ROOT, "lib", "PottsModels", "reproductions", "data", "15")
const ASSETS = joinpath(ROOT, "docs", "src", "assets", "openvt_monolayer")
const SPEC = joinpath(ROOT, "docs", "design", "research", "model-specs", "15_openvt_monolayer.md")
const MAKE = joinpath(ROOT, "docs", "make.jl")
const TITLE = "OpenVT monolayer benchmark"
const PENDING = r"pending: FULL run [a-z ]+ \(D-(174|211)\)"
const MODEL_SRC = joinpath(ROOT, "lib", "PottsModels", "src", "openvt_reference.jl")
const RELEASES = "https://github.com/PraneethMerugu/Potts.jl/releases/download/"
# (label kind, label, record item ID or nothing, fixed artefact or nothing), in M's order
const ITEMS = [
    ("F1", :figure, "1", "P6.15h", "fig1.png"),
    ("F2", :figure, "2", "P6.15b", "fig2_bde.png"),
    ("F3", :figure, "3", "P6.15f", "fig3.png"),
    ("F4", :figure, "4", "P6.15h", "fig4.png"),
    ("F5", :figure, "5", "P6.15e", "fig5_shared.png"),
    ("F6", :figure, "6", "P6.15g", nothing),
    ("T1", :table, "1", "P6.15g", nothing),
    ("F7", :figure, "7", "P6.15g", "fig7_grid.png"),
    ("F8", :figure, "8", "P6.15k", "fig8_grid.png"),
    ("F9", :figure, "9", "P6.15f", "fig8.png"),
    ("S1", :table, "S1", nothing, nothing),
    ("S5", :table, "S5", "P6.15b", nothing),
]
const PARKED_ITEMS = ("P6.15g", "P6.15k")
# the six current per-cell videos (gh release view, 2026-10-08), by the sections they belong to
const VIDEOS = [
    ("reproductions-2026-10-07-openvt-f5-cells-v2", "15_openvt_f5_b_run1_seed15001_cells_v2.mp4", ("F5",)),
    ("reproductions-2026-10-07-openvt-f5-cells-v2", "15_openvt_f5_control_gamma1e-4_run1_seed15501_cells_v2.mp4", ("F5",)),
    ("reproductions-2026-10-08-openvt-f3f8", "15_openvt_f3f8_a_run1_seed15701_cells.mp4", ("F1", "F3", "F9")),
    ("reproductions-2026-10-08-openvt-f3f8", "15_openvt_f3f8_b_run1_seed15001_cells.mp4", ("F1", "F3", "F9")),
    ("reproductions-2026-10-08-openvt-f3f8", "15_openvt_f3f8_e_beta0.8_run1_seed15801_cells.mp4", ("F1", "F3", "F9")),
    ("reproductions-2026-10-08-openvt-f3f8", "15_openvt_f3f8_f_sigmaX0_run1_seed15201_cells.mp4", ("F1", "F3", "F9")),
]
const SUPERSEDED = ["reproductions-2026-10-07-openvt-f5", "reproductions-2026-10-07-openvt-f5-cells"]
const VIDEO_EXT = (".mp4", ".webm", ".mov", ".mkv", ".gif")
const RECORD_EXT = (".tsv", ".csv", ".toml", ".md", ".jl", ".png", ".svg")
const G_NAMES = [r"closeup"i, r"cell_data_"i, r"relaxation_exact"i, r"^Fig1_"]
const FORBIDDEN = [
    r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i,
    r"docs/references"i, r"POTTS_REFERENCES", r"manuscript-draft"i,
    r"correspondence"i, r"\be-?mails?\b"i, r"\basked on\b"i, r"\bwe (have )?(asked|wrote|sent|contacted|emailed)\b"i,
    r"\bcontacted (the|R\.|Dr)"i, r"\banswered by\b"i, r"personal communication"i,
    r"\bletters? (to|from)\b"i, r"\bsubmitted to\b"i,
]
# ---------------------------------------------------------------------------------------------
# reading the page
# ---------------------------------------------------------------------------------------------
openvt_page_source() = isfile(PAGE) ? read(PAGE, String) : ""
const SRC = openvt_page_source()
const LINES = split(SRC, '\n')
# Literate Markdown headings: (line index, level, text)
function headings(lines)
    hs = Tuple{Int, Int, String}[]
    for (i, l) in enumerate(lines)
        m = match(r"^# (#{1,6}) +(.*?)\s*$", l)
        m === nothing || push!(hs, (i, length(m[1]), String(m[2])))
    end
    return hs
end
const HEADS = headings(LINES)
# every label a heading names: [("F", "3"), ("F", "8")] for "Figures 3 and 8", ("T", "S5"), …
function labels(text)
    out = Tuple{String, String}[]
    for m in eachmatch(r"\b(Figures?|Figs?\.?|Tables?)\s*((?:S?\d+)(?:\s*(?:,|and|&)\s*S?\d+)*)", text)
        k = startswith(m[1], "T") ? "T" : "F"
        for n in eachmatch(r"S?\d+", m[2])
            push!(out, (k, String(n.match)))
        end
    end
    return out
end
label(text) = (l = labels(text); isempty(l) ? nothing : first(l))
key(kind, n) = kind === :figure ? ("F", n) : ("T", n)
# the section of heading k: its lines up to the next heading of the same or a higher level
function openvt_page_section(lines, heads, k)
    i, lvl, _ = heads[k]
    j = findnext(h -> h[2] <= lvl, heads, k + 1)
    stop = j === nothing ? length(lines) : heads[j][1] - 1
    return join(lines[i:stop], '\n')
end
# first heading of each item: id => (heading index in HEADS, line)
function item_heads()
    found = Dict{String, Tuple{Int, Int}}()
    for (id, kind, n, _, _) in ITEMS
        k = findfirst(h -> key(kind, n) in labels(h[3]), HEADS)
        k === nothing || (found[id] = (k, HEADS[k][1]))
    end
    return found
end
const ITEM_HEADS = item_heads()
item_section(id) = haskey(ITEM_HEADS, id) ? openvt_page_section(LINES, HEADS, ITEM_HEADS[id][1]) : ""
# ---------------------------------------------------------------------------------------------
# records
# ---------------------------------------------------------------------------------------------
function records()
    recs = Dict{String, Any}[]
    isdir(DATA) || return recs
    for d in sort(readdir(DATA))
        p = joinpath(DATA, d, "provenance.toml")
        isfile(p) || continue
        prov = TOML.parsefile(p)
        push!(
            recs, Dict{String, Any}(
                "dir" => d, "path" => joinpath(DATA, d), "prov" => prov,
                "item" => string(get(prov, "item", ""))
            )
        )
    end
    return recs
end
const RECORDS = records()
records_of(item) = item === nothing ? Dict{String, Any}[] : filter(r -> r["item"] == item, RECORDS)
function machine_names(prov)
    names = String[]
    cpu = string(get(prov, "cpu", ""))
    isempty(cpu) || push!(names, lowercase(strip(first(split(cpu, " w/")))))
    host = string(get(prov, "hostname", ""))
    isempty(host) || push!(names, lowercase(host))
    return names
end
# does `sec` render record `r` (with the artefact `art`, or any figure/table file)?
function renders(sec, r, art)
    prov = r["prov"]
    commit = string(get(prov, "commit", ""))
    length(commit) >= 8 || return false
    occursin(r["dir"], sec) || return false
    occursin(commit[1:8], sec) || return false
    any(m -> occursin(m, lowercase(sec)), machine_names(prov)) || return false
    files = readdir(r["path"])
    if art !== nothing
        return art in files && occursin(art, sec)
    end
    return any(f -> any(e -> endswith(f, e), (".png", ".svg", ".tsv")) && occursin(f, sec), files)
end
# ---------------------------------------------------------------------------------------------
# Markdown tables of a section
# ---------------------------------------------------------------------------------------------
function openvt_page_tables(sec)
    tables = Vector{Vector{Vector{String}}}()
    cur = Vector{Vector{String}}()
    for l in split(sec, '\n')
        s = strip(replace(l, r"^#\s?" => ""))
        if startswith(s, "|") && endswith(s, "|") && length(s) > 1
            push!(cur, [String(strip(c)) for c in split(s[2:(end - 1)], '|')])
        else
            isempty(cur) || push!(tables, cur)
            cur = Vector{Vector{String}}()
        end
    end
    isempty(cur) || push!(tables, cur)
    return tables
end
issep(row) = all(c -> occursin(r"^:?-{3,}:?$", c), row)
function table_section(re)
    k = findfirst(h -> h[2] == 3 && occursin(re, h[3]), HEADS)
    k === nothing && return ("", Vector{Vector{Vector{String}}}())
    sec = openvt_page_section(LINES, HEADS, k)
    return (sec, openvt_page_tables(sec))
end
openvt_page_rows(tables) = [row for t in tables for row in t[3:end] if length(t) >= 3 && !issep(row)]
const DEV_SEC, DEV_TABLES = table_section(r"deviations"i)
const DIFFS_SEC, DIFFS_TABLES = table_section(r"differences"i)
const DIFF_SEC = DEV_SEC * "\n" * DIFFS_SEC
const DIFF_TABLES = [DEV_TABLES; DIFFS_TABLES]
const DEV_ROWS = openvt_page_rows(DEV_TABLES)
const DIFF_ROWS = openvt_page_rows(DIFF_TABLES)
idre(id) = Regex("(?<![A-Za-z0-9.])" * replace(id, "." => "\\.") * "(?![0-9.])")
rows_for(id; rows = DIFF_ROWS) = filter(r -> !isempty(r) && occursin(idre(id), r[1]), rows)
rowtext(r) = join(r, " | ")
function openvt_page_tsv(path)
    lines = filter(!isempty, readlines(path))
    isempty(lines) && return Dict{String, String}[]
    head = split(lines[1], '\t')
    return [Dict(String(h) => String(v) for (h, v) in zip(head, split(l, '\t'))) for l in lines[2:end]]
end
function spec_cs()
    isfile(SPEC) || return String[]
    txt = read(SPEC, String)
    a = findfirst("### 1.1", txt)
    a === nothing && return String[]
    b = findnext(r"\n## ", txt, last(a))
    sub = txt[first(a):(b === nothing ? lastindex(txt) : first(b))]
    return unique([String(m[1]) for m in eachmatch(r"^\| (C\d+) \|"m, sub)])
end
function openvt_page_files(dir)
    out = String[]
    isdir(dir) || return out
    for (root, _, fs) in walkdir(dir), f in fs
        push!(out, joinpath(root, f))
    end
    return out
end
sha(f) = bytes2hex(open(sha256, f))
# files of `candidates` byte-identical to any file under `refdir` (sizes first, then sha256)
function collisions(candidates, refdir; skip = p -> false)
    bysize = Dict{Int, Vector{String}}()
    for f in candidates
        push!(get!(bysize, filesize(f), String[]), f)
    end
    hits = String[]
    shas = Dict{String, String}()
    for (root, dirs, fs) in walkdir(refdir)
        filter!(d -> d != ".git", dirs)
        skip(root) && continue
        for f in fs
            p = joinpath(root, f)
            isfile(p) || continue
            cs = get(bysize, filesize(p), nothing)
            cs === nothing && continue
            h = sha(p)
            for c in cs
                get!(() -> sha(c), shas, c) == h && push!(hits, c)
            end
        end
    end
    return unique(hits)
end
# the record directories the page cites
const CITED = filter(r -> occursin(r["dir"], SRC), RECORDS)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "15 openvt page (a) the page exists, parses and has the title" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    # =============================================================================================
    @testset "15 openvt page (a) the page exists, parses and has the title" begin
        @test isfile(PAGE)
        parsed = isempty(SRC) ? nothing : Meta.parseall(SRC)
        bad(ex) = ex isa Expr && (ex.head in (:error, :incomplete) || any(bad, ex.args))
        @test parsed !== nothing && !bad(parsed)
        @test !isempty(HEADS) && HEADS[1][2] == 1 && startswith(HEADS[1][3], TITLE)
    end
end

@testitem "15 openvt page (b) the order: model, minimal run, results, details" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt page (b) the order: model, minimal run, results, details" begin
        h2 = [(k, h) for (k, h) in enumerate(HEADS) if h[2] == 2]
        find2(re) = findfirst(((k, h),) -> occursin(re, h[3]), h2)
        im, ir, ires, idet = find2(r"model"i), find2(r"minimal"i), find2(r"^(\d+\.\s*)?Results"i), find2(r"^(\d+\.\s*)?Details"i)
        @test all(!isnothing, (im, ir, ires, idet)) && im < ir < ires < idet
        if all(!isnothing, (im, ir, ires, idet))
            sec(i) = openvt_page_section(LINES, HEADS, h2[i][1])
            # the model: the actual @potts_model source, condensed
            msec = sec(im)
            m = match(r"```julia\n(.*?@potts_model OpenVTReferenceMonolayer.*?)```"s, replace(msec, r"(?m)^# ?" => ""))
            @test m !== nothing
            src = isfile(MODEL_SRC) ? read(MODEL_SRC, String) : ""
            a = findfirst("@potts_model OpenVTReferenceMonolayer", src)
            @test a !== nothing
            if m !== nothing && a !== nothing
                body = src[first(a):(first(findnext(r"(?m)^end\b", src, first(a))) + 2)]
                strip_line(l) = strip(replace(l, r"\s+#.*$" => ""))
                srclines = [strip_line(l) for l in split(body, '\n') if !isempty(strip_line(l)) && !startswith(strip(l), "#")]
                listing = [strip_line(l) for l in split(m[1], '\n') if !isempty(strip_line(l)) && !startswith(strip(l), "#")]
                # the listing is a subsequence of the source's lines (greedy match, in order)
                j = 0
                missing_lines = String[]
                for l in listing
                    k = findnext(==(l), srclines, j + 1)
                    k === nothing ? push!(missing_lines, l) : (j = k)
                end
                ok = isempty(missing_lines)
                ok || @info "15 openvt page: model listing lines not in the source, or out of order" missing_lines
                @test ok
                @test all(l -> l in listing, filter(l -> startswith(l, "@"), srclines))
            end
            # the minimal run runs code
            @test any(l -> !startswith(l, "#") && occursin("solve(", l), split(sec(ir), '\n'))
            # Results: the items in the D-185 order
            rk, dk = h2[ires][1], h2[idet][1]
            nextk(k) = (j = findnext(h -> h[2] <= 2, HEADS, k + 1); j === nothing ? length(HEADS) + 1 : j)
            h3(lo, hi) = [(k, HEADS[k][3]) for k in (lo + 1):(hi - 1) if HEADS[k][2] == 3]
            res3 = h3(rk, nextk(rk))
            pick(list, f) = findfirst(((k, t),) -> f(t), list)
            has(t, ids...) = all(id -> id in labels(t), ids)
            order = [
                pick(res3, t -> has(t, ("F", "2"))), pick(res3, t -> has(t, ("F", "5"))), pick(res3, t -> has(t, ("F", "1"))),
                pick(res3, t -> has(t, ("F", "3"), ("F", "9"))), pick(res3, t -> has(t, ("F", "6"), ("F", "7"), ("T", "1"))),
                pick(res3, t -> occursin(r"video"i, t)), pick(res3, t -> occursin(r"verdict"i, t)), pick(res3, t -> occursin(r"deviation"i, t)),
            ]
            @test all(!isnothing, order) && issorted(something.(order, 0); lt = <)
            # D-211: M's Figure 8 (the β grid) after Figures 6 and 7, before the videos
            f8 = pick(res3, t -> has(t, ("F", "8")))
            @test f8 !== nothing && all(!isnothing, order) && order[5] <= f8 < order[6]
            # Details: collapsed, with the rest
            det3 = h3(dk, nextk(dk))
            for f in (
                    t -> has(t, ("F", "4")), t -> has(t, ("T", "S1")), t -> has(t, ("T", "S5")), t -> occursin(r"differences"i, t),
                    t -> occursin(r"protocol"i, t), t -> occursin(r"provenance"i, t),
                )
                @test pick(det3, f) !== nothing
            end
            dsec = openvt_page_section(LINES, HEADS, dk)
            o = findfirst("<details>", dsec)
            c = findlast("</details>", dsec)
            first3 = isempty(det3) ? nothing : findfirst("# ### " * det3[1][2], dsec)
            @test o !== nothing && c !== nothing && first3 !== nothing && first(o) < first(first3)
            @test c !== nothing && isempty(strip(replace(dsec[(last(c) + 1):end], r"(?m)^#\s*```\s*$" => "", r"(?m)^#\s*$" => "")))
        end
        # every item of M is named by a heading
        for (id, _, _, _, _) in ITEMS
            has = haskey(ITEM_HEADS, id)
            has || @info "15 openvt page: no heading for $id"
            @test has
        end
    end
end

@testitem "15 openvt page (c) each item rendered from its record, or pending" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt page (c) each item rendered from its record, or pending" begin
        # the merged records the page builds on today (D-148, D-168, D-173, D-175)
        for item in ("P6.15b", "P6.15e", "P6.15f", "P6.15h")
            @test !isempty(records_of(item))
        end
        for (id, _, _, item, art) in ITEMS
            sec = item_section(id)
            recs = records_of(item)
            if item === nothing
                @test !isempty(sec) && !occursin(r"pending"i, sec)
            elseif isempty(recs)
                # only the parked sweeps (D-174) and the β grid (D-211) may be pending
                @test item in PARKED_ITEMS
                @test occursin(PENDING, sec)
                @test !occursin(r"\.(png|svg)\b"i, sec)
            else
                ok = any(r -> renders(sec, r, art), recs)
                ok || @info "15 openvt page: $id does not render a $item record (dir, commit, machine, $(something(art, "a figure or table file")))"
                @test ok
                @test !isempty(sec) && !occursin(r"pending"i, sec)
            end
        end
    end
end

@testitem "15 openvt page (d) deviations and differences tables: spec 15 §1.1 and every deviation" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt page (d) deviations and differences tables: spec 15 §1.1 and every deviation" begin
        @test !isempty(DEV_TABLES) && !isempty(DIFFS_TABLES)
        for t in DIFF_TABLES
            h = lowercase(join(t[1], " | "))
            @test length(t) >= 3 && issep(t[2])
            @test occursin("ours", h) && occursin("cause", h) && occursin("author question", h) &&
                occursin(r"paper|manuscript|\bm\b", h)
        end
        # every §1.1 conflict
        cs = spec_cs()
        @test all(c -> c in cs, ["C$k" for k in 1:17])
        for c in cs
            ok = !isempty(rows_for(c))
            ok || @info "15 openvt page: no differences row for $c"
            @test ok
        end
        # every recorded deviation
        devs = [
            (r, d) for r in RECORDS for d in (
                    isfile(joinpath(r["path"], "deviations.tsv")) ?
                    openvt_page_tsv(joinpath(r["path"], "deviations.tsv")) : Dict{String, String}[]
                )
        ]
        @test length(devs) >= 3
        for (r, d) in devs
            id = String(first(split(d["target"])))
            rows = rows_for(id; rows = DEV_ROWS)
            num = match(r"\d+\.\d+", get(d, "ours", ""))
            ok = any(rows) do row
                t = rowtext(row)
                (num === nothing || occursin(num.match, t)) && (!occursin("FAIL", d["target"]) || occursin("FAIL", t))
            end
            ok || @info "15 openvt page: deviation $id of $(r["dir"]) is not a row (with its value and verdict)"
            @test ok
        end
        # every non-control FAIL of every verdict table
        fails = String[]
        for r in RECORDS
            f = joinpath(r["path"], "verdicts.tsv")
            isfile(f) || continue
            for v in openvt_page_tsv(f)
                get(v, "result", "") == "FAIL" || continue
                get(v, "case", "") == "control" && continue
                occursin("must FAIL", get(v, "band", "") * get(v, "tolerance", "")) && continue
                occursin("(all rows)", v["target"]) && continue
                push!(fails, String(first(split(v["target"]))))
            end
        end
        @test Set(["V4.2", "V4.3", "V4.5"]) ⊆ Set(fails)
        for id in unique(fails)
            ok = any(row -> occursin("FAIL", rowtext(row)), rows_for(id; rows = DEV_ROWS))
            ok || @info "15 openvt page: failing target $id is not a FAIL row"
            @test ok
        end
        # V1: slow growth beyond 10³ cells, actual against target area (D-173)
        v1 = rowtext.(rows_for("V1"; rows = DEV_ROWS))
        @test any(v1) do t
            occursin("15.17", t) && occursin("13.57", t) && occursin(r"1[12](\.\d)?\s?%", t) &&
                occursin(r"10³|10\^3|1000", t) && occursin(r"actual area"i, t) && occursin(r"target area"i, t) &&
                occursin(idre("C13"), t) && !occursin("PASS", t)
        end
        # F1: coolwarm by area, the scale limits provisional (D-185)
        @test any(
            t -> occursin(r"coolwarm"i, t) && occursin(r"area"i, t) && occursin(r"provisional"i, t),
            rowtext.(rows_for("F1"; rows = DEV_ROWS))
        )
        # author-question status
        for row in DIFF_ROWS
            s = lowercase(last(row))
            ok = occursin(r"^(not an author question|not asked|resolved)", s) &&
                (!occursin(r"\bq\d+\b", s) || occursin("our open question list", s))
            ok || @info "15 openvt page: bad author-question status: $(last(row))"
            @test ok
        end
    end
end

@testitem "15 openvt page (e) videos are release assets, per cell, current" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt page (e) videos are release assets, per cell, current" begin
        kv = findfirst(h -> h[2] == 3 && occursin(r"video"i, h[3]), HEADS)
        @test kv !== nothing
        vsec = kv === nothing ? "" : openvt_page_section(LINES, HEADS, kv)
        for (tag, name, _) in VIDEOS
            url = RELEASES * tag * "/" * name
            ok = occursin(url, vsec)
            ok || @info "15 openvt page: $name is not linked in the videos section"
            @test ok
        end
        mp4 = [m.match for m in eachmatch(r"[^\s\"'()<>\[\]`]*\.mp4", SRC)]
        @test length(mp4) >= length(VIDEOS)
        for u in mp4
            m = match(Regex("^" * replace(RELEASES, "." => "\\.") * "(reproductions-[^/]+)/([^/]+)\$"), u)
            ok = m !== nothing && !(m[1] in SUPERSEDED) && occursin("cells", m[2])
            ok || @info "15 openvt page: video reference not allowed: $u"
            @test ok
        end
        committed = filter(
            f -> any(e -> endswith(lowercase(f), e), VIDEO_EXT),
            [openvt_page_files(ASSETS); openvt_page_files(DATA)]
        )
        @test isempty(committed)
    end
end

@testitem "15 openvt page (f) stills: per-cell colours, no outlines" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt page (f) stills: per-cell colours, no outlines" begin
        @test !isempty(SRC)
        @test !occursin(r"boundaries\s*=\s*true", SRC)
        @test !occursin("pottsboundaries", SRC)
        @test !occursin("ChannelEncoding", SRC)
        @test !occursin("pottsplot", SRC) || occursin(r"CellIdentityEncoding|CellTypeEncoding", SRC)
    end
end

@testitem "15 openvt page (g) G-derived content: figures and small statistics, with provenance" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt page (g) G-derived content: figures and small statistics, with provenance" begin
        @test !isempty(CITED)
        for r in CITED
            prov = r["prov"]
            @test occursin(r"^[0-9a-f]{40}$", string(get(prov, "commit", "")))
            @test startswith(r["item"], "P6.15")
            @test get(prov, "dirty_tracked", true) === false
            runner = string(get(prov, "runner", ""))
            @test startswith(runner, "lib/PottsModels/reproductions/data/15/" * r["dir"] * "/") && isfile(joinpath(ROOT, runner))
            for f in openvt_page_files(r["path"])
                b = basename(f)
                ok = any(e -> endswith(lowercase(b), e), RECORD_EXT) && filesize(f) <= 10 * 2^20 &&
                    !any(p -> occursin(p, b), G_NAMES)
                ok || @info "15 openvt page: not a figure or small statistic: $f"
                @test ok
            end
        end
        # the page's own assets
        recfiles = Set(sha(f) for r in RECORDS for f in openvt_page_files(r["path"]))
        manifest = joinpath(ASSETS, "provenance.toml")
        listed = isfile(manifest) ? get(TOML.parsefile(manifest), "files", Dict{String, Any}()) : Dict{String, Any}()
        for f in openvt_page_files(ASSETS)
            f == manifest && continue
            rel = relpath(f, ASSETS)
            e = get(listed, rel, nothing)
            ok = sha(f) in recfiles ||
                (
                e isa AbstractDict && isdir(joinpath(DATA, string(get(e, "record", "")))) && !isempty(string(get(e, "record", ""))) &&
                    get(e, "kind", "") in ("figure", "statistics")
            )
            ok = ok && !any(p -> occursin(p, basename(f)), G_NAMES)
            ok || @info "15 openvt page: page asset without provenance: $rel"
            @test ok
        end
        g = get(ENV, "OPENVT_MONOLAYER_REPO", "")
        if isdir(g)
            cands = [openvt_page_files(ASSETS); (f for r in CITED for f in openvt_page_files(r["path"]))...]
            @test isempty(collisions(cands, g))
        else
            @info "15 openvt page: OPENVT_MONOLAYER_REPO not set; the byte check against G is skipped"
        end
    end
end

@testitem "15 openvt page (h) forbidden text: no private sheet, no docs/references, no contact" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt page (h) forbidden text: no private sheet, no docs/references, no contact" begin
        @test !isempty(SRC)
        for re in FORBIDDEN
            hit = match(re, SRC)
            hit === nothing || @info "15 openvt page: forbidden text on the page: $(hit.match)"
            @test hit === nothing
        end
        refs = get(ENV, "POTTS_REFERENCES", joinpath(ROOT, "docs", "references"))
        if isdir(refs)
            names = unique(basename(f) for f in openvt_page_files(refs) if endswith(lowercase(f), ".pdf") && length(splitext(basename(f))[1]) >= 8)
            hits = filter(n -> occursin(n, SRC) || occursin(splitext(n)[1], SRC), names)
            isempty(hits) || @info "15 openvt page: docs/references file names on the page: $hits"
            @test isempty(hits)
            cands = [openvt_page_files(ASSETS); (f for r in CITED for f in openvt_page_files(r["path"]))...]
            @test isempty(collisions(cands, refs))
        else
            @info "15 openvt page: docs/references not present; its name and byte checks are skipped"
        end
    end
end

@testitem "15 openvt page (i) in the docs navigation; builds with Documenter (opt-in)" setup = [OpenVTPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt page (i) in the docs navigation; builds with Documenter (opt-in)" begin
        make = isfile(MAKE) ? read(MAKE, String) : ""
        by_name = occursin("15_openvt_monolayer", make)
        by_loop = occursin(r"readdir\(REPRODUCTIONS\)", make) && occursin("Literate.markdown(joinpath(REPRODUCTIONS", make) &&
            (occursin("\"Published models\"", make) || occursin("\"Paper models\"", make))
        @test by_name || by_loop
        @test dirname(PAGE) == joinpath(ROOT, "lib", "PottsModels", "reproductions") && isfile(PAGE)
        if get(ENV, "POTTS_DOCS_BUILD", "false") == "true"
            cmd = addenv(`$(Base.julia_cmd()) --project=docs docs/make.jl`, "POTTS_DOCS_PUBLISHED" => "true")
            @test success(pipeline(Cmd(cmd; dir = ROOT); stdout = stdout, stderr = stderr))
            built = joinpath(ROOT, "docs", "build", "published", "15_openvt_monolayer", "index.html")
            @test isfile(built)
            html = isfile(built) ? read(built, String) : ""
            @test occursin(TITLE, html)
            for (tag, name, _) in VIDEOS
                @test occursin(RELEASES * tag * "/" * name, html)
            end
            for m in eachmatch(r"<img[^>]*\ssrc=\"([^\"]+)\"", html)
                src = m[1]
                startswith(src, "data:") && continue
                @test isfile(normpath(joinpath(dirname(built), src)))
            end
        else
            @info "15 openvt page: POTTS_DOCS_BUILD not set; the Documenter build is skipped"
        end
    end
end
