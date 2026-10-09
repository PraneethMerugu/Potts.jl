# P6.15i (ROADMAP Phase 6, OpenVT track): the docs page "OpenVT monolayer benchmark".
# Frozen (AUTONOMY §7.3). The page is the Literate script
# `lib/PottsModels/reproductions/15_openvt_monolayer.jl`, so the existing docs hook renders it
# (`docs/make.jl` turns every script in `lib/PottsModels/reproductions/` into a "Published
# models" page under `POTTS_DOCS_PUBLISHED=true`), like reproductions 01, 09 and 10. This file
# reads the page source and the committed records only; it runs no simulation.
#
# What the page must carry (spec 15 §4.0 inventory and §1.1; D-146, D-154, D-156, D-161,
# D-168, D-172–D-175, D-185). Re-frozen under D-185 for the page layout only: the order of
# (b), where the deviations and videos sit ((d), (e)), the pending wording and the F1 colour
# row; no verdict rule, band or record-value check changed.
#
# (a) Title. The first Markdown heading is the H1 "OpenVT monolayer benchmark".
# (b) The D-185 order. Four level-2 headings, in this order: the model ("model"), a minimal
#     run ("minimal"), "Results" and "Details". The model section holds a ```julia listing of
#     `@potts_model OpenVTReferenceMonolayer`; every code line of it (comments and blank
#     lines dropped, whitespace trimmed) is a line of the model's source
#     `lib/PottsModels/src/openvt_reference.jl`, in the source's order, and the listing has
#     every `@`-macro line of the source (condensed, not paraphrased). The minimal-run
#     section runs code (a non-comment line calls `solve(`). Inside Results, level-3
#     headings in this order: Figure 2; Figure 5; Figure 1; Figures 3 and 8; Figures 6 and
#     7 with Table 1; the videos ("video"); the verdict summary ("verdict"); "Deviations".
#     Details opens a raw-HTML `<details>` before its first level-3 heading and closes it
#     (`</details>`) after its last line, and holds level-3 headings for Figure 4, Table S1,
#     Table S5 and "Differences", and a protocol ("protocol") and provenance ("provenance")
#     heading. Every item of M (Figure 1–8, Table 1, Tables S1 and S5) has a heading that
#     names it ("Figure N", "Figures N and M", "Table N", …); its section runs to the next
#     heading of the same or a higher level.
# (c) Each item is either RENDERED from a merged record or PENDING:
#     - an item's records are the directories of `reproductions/data/15/` whose
#       `provenance.toml` has its ROADMAP item: F1, F4 P6.15h; F2, S5 P6.15b; F3, F8 P6.15f;
#       F5 P6.15e; F6, T1, F7 P6.15g. Table S1 is the parameter table and has no record;
#     - RENDERED: the section names a record directory, the first 8 characters of its
#       commit, and its machine (the cpu up to " w/", or the hostname; case-insensitive),
#       all as literal text; and it shows the record's figure (the file name, which must
#       exist: F1 fig1.png, F2 fig2_bde.png, F3 fig3.png, F4 fig4.png, F5 fig5.png,
#       F8 fig8.png; for the tables and the P6.15g items any .png, .svg or .tsv of the
#       record). It does not say "pending". The record figures follow M's layout (their
#       READMEs and frozen tests pin it), so naming the file pins the layout;
#     - PENDING is allowed only for the P6.15g items while no P6.15g record is merged
#       (D-174). The section then says "pending: FULL run <state> (D-174)" (e.g. "parked" or
#       "in progress") and shows no image. When a P6.15g record lands, the same items must
#       be RENDERED, with no edit to this file.
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
#     has a `provenance.toml` (40-hex commit, an item P6.15*, a clean tree, a runner inside
#     the record directory that exists), only .tsv/.toml/.md/.jl/.png/.svg files, none over
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
using Test, TOML, SHA

const P615I_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const P615I_PAGE = joinpath(P615I_ROOT, "lib", "PottsModels", "reproductions", "15_openvt_monolayer.jl")
const P615I_DATA = joinpath(P615I_ROOT, "lib", "PottsModels", "reproductions", "data", "15")
const P615I_ASSETS = joinpath(P615I_ROOT, "docs", "src", "assets", "openvt_monolayer")
const P615I_SPEC = joinpath(P615I_ROOT, "docs", "design", "research", "model-specs", "15_openvt_monolayer.md")
const P615I_MAKE = joinpath(P615I_ROOT, "docs", "make.jl")
const P615I_TITLE = "OpenVT monolayer benchmark"
const P615I_PENDING = r"pending: FULL run [a-z ]+ \(D-174\)"
const P615I_MODEL_SRC = joinpath(P615I_ROOT, "lib", "PottsModels", "src", "openvt_reference.jl")
const P615I_RELEASES = "https://github.com/PraneethMerugu/Potts.jl/releases/download/"

# (label kind, label, ROADMAP item or nothing, fixed artefact or nothing), in M's order
const P615I_ITEMS = [
    ("F1", :figure, "1", "P6.15h", "fig1.png"),
    ("F2", :figure, "2", "P6.15b", "fig2_bde.png"),
    ("F3", :figure, "3", "P6.15f", "fig3.png"),
    ("F4", :figure, "4", "P6.15h", "fig4.png"),
    ("F5", :figure, "5", "P6.15e", "fig5.png"),
    ("F6", :figure, "6", "P6.15g", nothing),
    ("T1", :table, "1", "P6.15g", nothing),
    ("F7", :figure, "7", "P6.15g", nothing),
    ("F8", :figure, "8", "P6.15f", "fig8.png"),
    ("S1", :table, "S1", nothing, nothing),
    ("S5", :table, "S5", "P6.15b", nothing),
]
const P615I_PARKED_ITEM = "P6.15g"

# the six current per-cell videos (gh release view, 2026-10-08), by the sections they belong to
const P615I_VIDEOS = [
    ("reproductions-2026-10-07-openvt-f5-cells-v2", "15_openvt_f5_b_run1_seed15001_cells_v2.mp4", ("F5",)),
    ("reproductions-2026-10-07-openvt-f5-cells-v2", "15_openvt_f5_control_gamma1e-4_run1_seed15501_cells_v2.mp4", ("F5",)),
    ("reproductions-2026-10-08-openvt-f3f8", "15_openvt_f3f8_a_run1_seed15701_cells.mp4", ("F1", "F3", "F8")),
    ("reproductions-2026-10-08-openvt-f3f8", "15_openvt_f3f8_b_run1_seed15001_cells.mp4", ("F1", "F3", "F8")),
    ("reproductions-2026-10-08-openvt-f3f8", "15_openvt_f3f8_e_beta0.8_run1_seed15801_cells.mp4", ("F1", "F3", "F8")),
    ("reproductions-2026-10-08-openvt-f3f8", "15_openvt_f3f8_f_sigmaX0_run1_seed15201_cells.mp4", ("F1", "F3", "F8")),
]
const P615I_SUPERSEDED = ["reproductions-2026-10-07-openvt-f5", "reproductions-2026-10-07-openvt-f5-cells"]
const P615I_VIDEO_EXT = (".mp4", ".webm", ".mov", ".mkv", ".gif")
const P615I_RECORD_EXT = (".tsv", ".toml", ".md", ".jl", ".png", ".svg")
const P615I_G_NAMES = [r"closeup"i, r"cell_data_"i, r"relaxation_exact"i, r"^Fig1_"]

const P615I_FORBIDDEN = [
    r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i,
    r"docs/references"i, r"POTTS_REFERENCES", r"manuscript-draft"i,
    r"correspondence"i, r"\be-?mails?\b"i, r"\basked on\b"i, r"\bwe (have )?(asked|wrote|sent|contacted|emailed)\b"i,
    r"\bcontacted (the|R\.|Dr)"i, r"\banswered by\b"i, r"personal communication"i,
    r"\bletters? (to|from)\b"i, r"\bsubmitted to\b"i,
]

# ---------------------------------------------------------------------------------------------
# reading the page
# ---------------------------------------------------------------------------------------------
p615i_source() = isfile(P615I_PAGE) ? read(P615I_PAGE, String) : ""
const P615I_SRC = p615i_source()
const P615I_LINES = split(P615I_SRC, '\n')

# Literate Markdown headings: (line index, level, text)
function p615i_headings(lines)
    hs = Tuple{Int, Int, String}[]
    for (i, l) in enumerate(lines)
        m = match(r"^# (#{1,6}) +(.*?)\s*$", l)
        m === nothing || push!(hs, (i, length(m[1]), String(m[2])))
    end
    return hs
end
const P615I_HEADS = p615i_headings(P615I_LINES)

# every label a heading names: [("F", "3"), ("F", "8")] for "Figures 3 and 8", ("T", "S5"), …
function p615i_labels(text)
    out = Tuple{String, String}[]
    for m in eachmatch(r"\b(Figures?|Figs?\.?|Tables?)\s*((?:S?\d+)(?:\s*(?:,|and|&)\s*S?\d+)*)", text)
        k = startswith(m[1], "T") ? "T" : "F"
        for n in eachmatch(r"S?\d+", m[2])
            push!(out, (k, String(n.match)))
        end
    end
    return out
end
p615i_label(text) = (l = p615i_labels(text); isempty(l) ? nothing : first(l))
p615i_key(kind, n) = kind === :figure ? ("F", n) : ("T", n)

# the section of heading k: its lines up to the next heading of the same or a higher level
function p615i_section(lines, heads, k)
    i, lvl, _ = heads[k]
    j = findnext(h -> h[2] <= lvl, heads, k + 1)
    stop = j === nothing ? length(lines) : heads[j][1] - 1
    return join(lines[i:stop], '\n')
end

# first heading of each item: id => (heading index in P615I_HEADS, line)
function p615i_item_heads()
    found = Dict{String, Tuple{Int, Int}}()
    for (id, kind, n, _, _) in P615I_ITEMS
        k = findfirst(h -> p615i_key(kind, n) in p615i_labels(h[3]), P615I_HEADS)
        k === nothing || (found[id] = (k, P615I_HEADS[k][1]))
    end
    return found
end
const P615I_ITEM_HEADS = p615i_item_heads()
p615i_item_section(id) = haskey(P615I_ITEM_HEADS, id) ? p615i_section(P615I_LINES, P615I_HEADS, P615I_ITEM_HEADS[id][1]) : ""

# ---------------------------------------------------------------------------------------------
# records
# ---------------------------------------------------------------------------------------------
function p615i_records()
    recs = Dict{String, Any}[]
    isdir(P615I_DATA) || return recs
    for d in sort(readdir(P615I_DATA))
        p = joinpath(P615I_DATA, d, "provenance.toml")
        isfile(p) || continue
        prov = TOML.parsefile(p)
        push!(recs, Dict{String, Any}("dir" => d, "path" => joinpath(P615I_DATA, d), "prov" => prov,
            "item" => string(get(prov, "item", ""))))
    end
    return recs
end
const P615I_RECORDS = p615i_records()
p615i_records_of(item) = item === nothing ? Dict{String, Any}[] : filter(r -> r["item"] == item, P615I_RECORDS)

function p615i_machine_names(prov)
    names = String[]
    cpu = string(get(prov, "cpu", ""))
    isempty(cpu) || push!(names, lowercase(strip(first(split(cpu, " w/")))))
    host = string(get(prov, "hostname", ""))
    isempty(host) || push!(names, lowercase(host))
    return names
end

# does `sec` render record `r` (with the artefact `art`, or any figure/table file)?
function p615i_renders(sec, r, art)
    prov = r["prov"]
    commit = string(get(prov, "commit", ""))
    length(commit) >= 8 || return false
    occursin(r["dir"], sec) || return false
    occursin(commit[1:8], sec) || return false
    any(m -> occursin(m, lowercase(sec)), p615i_machine_names(prov)) || return false
    files = readdir(r["path"])
    if art !== nothing
        return art in files && occursin(art, sec)
    end
    return any(f -> any(e -> endswith(f, e), (".png", ".svg", ".tsv")) && occursin(f, sec), files)
end

# ---------------------------------------------------------------------------------------------
# Markdown tables of a section
# ---------------------------------------------------------------------------------------------
function p615i_tables(sec)
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
p615i_issep(row) = all(c -> occursin(r"^:?-{3,}:?$", c), row)

function p615i_table_section(re)
    k = findfirst(h -> h[2] == 3 && occursin(re, h[3]), P615I_HEADS)
    k === nothing && return ("", Vector{Vector{Vector{String}}}())
    sec = p615i_section(P615I_LINES, P615I_HEADS, k)
    return (sec, p615i_tables(sec))
end
p615i_rows(tables) = [row for t in tables for row in t[3:end] if length(t) >= 3 && !p615i_issep(row)]
const P615I_DEV_SEC, P615I_DEV_TABLES = p615i_table_section(r"deviations"i)
const P615I_DIFFS_SEC, P615I_DIFFS_TABLES = p615i_table_section(r"differences"i)
const P615I_DIFF_SEC = P615I_DEV_SEC * "\n" * P615I_DIFFS_SEC
const P615I_DIFF_TABLES = [P615I_DEV_TABLES; P615I_DIFFS_TABLES]
const P615I_DEV_ROWS = p615i_rows(P615I_DEV_TABLES)
const P615I_DIFF_ROWS = p615i_rows(P615I_DIFF_TABLES)

p615i_idre(id) = Regex("(?<![A-Za-z0-9.])" * replace(id, "." => "\\.") * "(?![0-9.])")
p615i_rows_for(id; rows = P615I_DIFF_ROWS) = filter(r -> !isempty(r) && occursin(p615i_idre(id), r[1]), rows)
p615i_rowtext(r) = join(r, " | ")

function p615i_tsv(path)
    lines = filter(!isempty, readlines(path))
    isempty(lines) && return Dict{String, String}[]
    head = split(lines[1], '\t')
    return [Dict(String(h) => String(v) for (h, v) in zip(head, split(l, '\t'))) for l in lines[2:end]]
end

function p615i_spec_cs()
    isfile(P615I_SPEC) || return String[]
    txt = read(P615I_SPEC, String)
    a = findfirst("### 1.1", txt)
    a === nothing && return String[]
    b = findnext(r"\n## ", txt, last(a))
    sub = txt[first(a):(b === nothing ? lastindex(txt) : first(b))]
    return unique([String(m[1]) for m in eachmatch(r"^\| (C\d+) \|"m, sub)])
end

function p615i_files(dir)
    out = String[]
    isdir(dir) || return out
    for (root, _, fs) in walkdir(dir), f in fs
        push!(out, joinpath(root, f))
    end
    return out
end
p615i_sha(f) = bytes2hex(open(sha256, f))

# files of `candidates` byte-identical to any file under `refdir` (sizes first, then sha256)
function p615i_collisions(candidates, refdir; skip = p -> false)
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
            h = p615i_sha(p)
            for c in cs
                get!(() -> p615i_sha(c), shas, c) == h && push!(hits, c)
            end
        end
    end
    return unique(hits)
end

# the record directories the page cites
const P615I_CITED = filter(r -> occursin(r["dir"], P615I_SRC), P615I_RECORDS)

# =============================================================================================
@testset "P6.15i (a) the page exists, parses and has the title" begin
    @test isfile(P615I_PAGE)
    parsed = isempty(P615I_SRC) ? nothing : Meta.parseall(P615I_SRC)
    bad(ex) = ex isa Expr && (ex.head in (:error, :incomplete) || any(bad, ex.args))
    @test parsed !== nothing && !bad(parsed)
    @test !isempty(P615I_HEADS) && P615I_HEADS[1][2] == 1 && startswith(P615I_HEADS[1][3], P615I_TITLE)
end

@testset "P6.15i (b) the D-185 order: model, minimal run, results, details" begin
    h2 = [(k, h) for (k, h) in enumerate(P615I_HEADS) if h[2] == 2]
    find2(re) = findfirst(((k, h),) -> occursin(re, h[3]), h2)
    im, ir, ires, idet = find2(r"model"i), find2(r"minimal"i), find2(r"^(\d+\.\s*)?Results"i), find2(r"^(\d+\.\s*)?Details"i)
    @test all(!isnothing, (im, ir, ires, idet)) && im < ir < ires < idet
    if all(!isnothing, (im, ir, ires, idet))
        sec(i) = p615i_section(P615I_LINES, P615I_HEADS, h2[i][1])
        # the model: the actual @potts_model source, condensed
        msec = sec(im)
        m = match(r"```julia\n(.*?@potts_model OpenVTReferenceMonolayer.*?)```"s, replace(msec, r"(?m)^# ?" => ""))
        @test m !== nothing
        src = isfile(P615I_MODEL_SRC) ? read(P615I_MODEL_SRC, String) : ""
        a = findfirst("@potts_model OpenVTReferenceMonolayer", src)
        @test a !== nothing
        if m !== nothing && a !== nothing
            body = src[first(a):first(findnext(r"(?m)^end\b", src, first(a)))+2]
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
            ok || @info "P6.15i: model listing lines not in the source, or out of order" missing_lines
            @test ok
            @test all(l -> l in listing, filter(l -> startswith(l, "@"), srclines))
        end
        # the minimal run runs code
        @test any(l -> !startswith(l, "#") && occursin("solve(", l), split(sec(ir), '\n'))
        # Results: the items in the D-185 order
        rk, dk = h2[ires][1], h2[idet][1]
        nextk(k) = (j = findnext(h -> h[2] <= 2, P615I_HEADS, k + 1); j === nothing ? length(P615I_HEADS) + 1 : j)
        h3(lo, hi) = [(k, P615I_HEADS[k][3]) for k in (lo + 1):(hi - 1) if P615I_HEADS[k][2] == 3]
        res3 = h3(rk, nextk(rk))
        pick(list, f) = findfirst(((k, t),) -> f(t), list)
        has(t, ids...) = all(id -> id in p615i_labels(t), ids)
        order = [pick(res3, t -> has(t, ("F", "2"))), pick(res3, t -> has(t, ("F", "5"))), pick(res3, t -> has(t, ("F", "1"))),
            pick(res3, t -> has(t, ("F", "3"), ("F", "8"))), pick(res3, t -> has(t, ("F", "6"), ("F", "7"), ("T", "1"))),
            pick(res3, t -> occursin(r"video"i, t)), pick(res3, t -> occursin(r"verdict"i, t)), pick(res3, t -> occursin(r"deviation"i, t))]
        @test all(!isnothing, order) && issorted(something.(order, 0); lt = <)
        # Details: collapsed, with the rest
        det3 = h3(dk, nextk(dk))
        for f in (t -> has(t, ("F", "4")), t -> has(t, ("T", "S1")), t -> has(t, ("T", "S5")), t -> occursin(r"differences"i, t),
            t -> occursin(r"protocol"i, t), t -> occursin(r"provenance"i, t))
            @test pick(det3, f) !== nothing
        end
        dsec = p615i_section(P615I_LINES, P615I_HEADS, dk)
        o = findfirst("<details>", dsec)
        c = findlast("</details>", dsec)
        first3 = isempty(det3) ? nothing : findfirst("# ### " * det3[1][2], dsec)
        @test o !== nothing && c !== nothing && first3 !== nothing && first(o) < first(first3)
        @test c !== nothing && isempty(strip(replace(dsec[(last(c) + 1):end], r"(?m)^#\s*```\s*$" => "", r"(?m)^#\s*$" => "")))
    end
    # every item of M is named by a heading
    for (id, _, _, _, _) in P615I_ITEMS
        has = haskey(P615I_ITEM_HEADS, id)
        has || @info "P6.15i: no heading for $id"
        @test has
    end
end

@testset "P6.15i (c) each item rendered from its record, or pending (D-174)" begin
    # the merged records the page builds on today (D-148, D-168, D-173, D-175)
    for item in ("P6.15b", "P6.15e", "P6.15f", "P6.15h")
        @test !isempty(p615i_records_of(item))
    end
    for (id, _, _, item, art) in P615I_ITEMS
        sec = p615i_item_section(id)
        recs = p615i_records_of(item)
        if item === nothing
            @test !isempty(sec) && !occursin(r"pending"i, sec)
        elseif isempty(recs)
            # only the parked sweeps may be pending
            @test item == P615I_PARKED_ITEM
            @test occursin(P615I_PENDING, sec)
            @test !occursin(r"\.(png|svg)\b"i, sec)
        else
            ok = any(r -> p615i_renders(sec, r, art), recs)
            ok || @info "P6.15i: $id does not render a $item record (dir, commit, machine, $(something(art, "a figure or table file")))"
            @test ok
            @test !isempty(sec) && !occursin(r"pending"i, sec)
        end
    end
end

@testset "P6.15i (d) deviations and differences tables: spec 15 §1.1 and every deviation (D-154)" begin
    @test !isempty(P615I_DEV_TABLES) && !isempty(P615I_DIFFS_TABLES)
    for t in P615I_DIFF_TABLES
        h = lowercase(join(t[1], " | "))
        @test length(t) >= 3 && p615i_issep(t[2])
        @test occursin("ours", h) && occursin("cause", h) && occursin("author question", h) &&
              occursin(r"paper|manuscript|\bm\b", h)
    end
    # every §1.1 conflict
    cs = p615i_spec_cs()
    @test all(c -> c in cs, ["C$k" for k in 1:17])
    for c in cs
        ok = !isempty(p615i_rows_for(c))
        ok || @info "P6.15i: no differences row for $c"
        @test ok
    end
    # every recorded deviation
    devs = [(r, d) for r in P615I_RECORDS for d in (isfile(joinpath(r["path"], "deviations.tsv")) ?
                                                   p615i_tsv(joinpath(r["path"], "deviations.tsv")) : Dict{String, String}[])]
    @test length(devs) >= 3
    for (r, d) in devs
        id = String(first(split(d["target"])))
        rows = p615i_rows_for(id; rows = P615I_DEV_ROWS)
        num = match(r"\d+\.\d+", get(d, "ours", ""))
        ok = any(rows) do row
            t = p615i_rowtext(row)
            (num === nothing || occursin(num.match, t)) && (!occursin("FAIL", d["target"]) || occursin("FAIL", t))
        end
        ok || @info "P6.15i: deviation $id of $(r["dir"]) is not a row (with its value and verdict)"
        @test ok
    end
    # every non-control FAIL of every verdict table
    fails = String[]
    for r in P615I_RECORDS
        f = joinpath(r["path"], "verdicts.tsv")
        isfile(f) || continue
        for v in p615i_tsv(f)
            get(v, "result", "") == "FAIL" || continue
            get(v, "case", "") == "control" && continue
            occursin("must FAIL", get(v, "band", "") * get(v, "tolerance", "")) && continue
            occursin("(all rows)", v["target"]) && continue
            push!(fails, String(first(split(v["target"]))))
        end
    end
    @test Set(["V4.2", "V4.3", "V4.5"]) ⊆ Set(fails)
    for id in unique(fails)
        ok = any(row -> occursin("FAIL", p615i_rowtext(row)), p615i_rows_for(id; rows = P615I_DEV_ROWS))
        ok || @info "P6.15i: failing target $id is not a FAIL row"
        @test ok
    end
    # V1: slow growth beyond 10³ cells, actual against target area (D-173)
    v1 = p615i_rowtext.(p615i_rows_for("V1"; rows = P615I_DEV_ROWS))
    @test any(v1) do t
        occursin("15.17", t) && occursin("13.57", t) && occursin(r"1[12](\.\d)?\s?%", t) &&
            occursin(r"10³|10\^3|1000", t) && occursin(r"actual area"i, t) && occursin(r"target area"i, t) &&
            occursin(p615i_idre("C13"), t) && !occursin("PASS", t)
    end
    # F1: coolwarm by area, the scale limits provisional (D-185)
    @test any(t -> occursin(r"coolwarm"i, t) && occursin(r"area"i, t) && occursin(r"provisional"i, t),
        p615i_rowtext.(p615i_rows_for("F1"; rows = P615I_DEV_ROWS)))
    # author-question status
    for row in P615I_DIFF_ROWS
        s = lowercase(last(row))
        ok = occursin(r"^(not an author question|not asked|resolved)", s) &&
             (!occursin(r"\bq\d+\b", s) || occursin("our open question list", s))
        ok || @info "P6.15i: bad author-question status: $(last(row))"
        @test ok
    end
end

@testset "P6.15i (e) videos are release assets, per cell, current" begin
    kv = findfirst(h -> h[2] == 3 && occursin(r"video"i, h[3]), P615I_HEADS)
    @test kv !== nothing
    vsec = kv === nothing ? "" : p615i_section(P615I_LINES, P615I_HEADS, kv)
    for (tag, name, _) in P615I_VIDEOS
        url = P615I_RELEASES * tag * "/" * name
        ok = occursin(url, vsec)
        ok || @info "P6.15i: $name is not linked in the videos section"
        @test ok
    end
    mp4 = [m.match for m in eachmatch(r"[^\s\"'()<>\[\]`]*\.mp4", P615I_SRC)]
    @test length(mp4) >= length(P615I_VIDEOS)
    for u in mp4
        m = match(Regex("^" * replace(P615I_RELEASES, "." => "\\.") * "(reproductions-[^/]+)/([^/]+)\$"), u)
        ok = m !== nothing && !(m[1] in P615I_SUPERSEDED) && occursin("cells", m[2])
        ok || @info "P6.15i: video reference not allowed: $u"
        @test ok
    end
    committed = filter(f -> any(e -> endswith(lowercase(f), e), P615I_VIDEO_EXT),
        [p615i_files(P615I_ASSETS); p615i_files(P615I_DATA)])
    @test isempty(committed)
end

@testset "P6.15i (f) stills: per-cell colours, no outlines (D-156, D-172)" begin
    @test !isempty(P615I_SRC)
    @test !occursin(r"boundaries\s*=\s*true", P615I_SRC)
    @test !occursin("pottsboundaries", P615I_SRC)
    @test !occursin("ChannelEncoding", P615I_SRC)
    @test !occursin("pottsplot", P615I_SRC) || occursin(r"CellIdentityEncoding|CellTypeEncoding", P615I_SRC)
end

@testset "P6.15i (g) G-derived content: figures and small statistics, with provenance" begin
    @test !isempty(P615I_CITED)
    for r in P615I_CITED
        prov = r["prov"]
        @test occursin(r"^[0-9a-f]{40}$", string(get(prov, "commit", "")))
        @test startswith(r["item"], "P6.15")
        @test get(prov, "dirty_tracked", true) === false
        runner = string(get(prov, "runner", ""))
        @test startswith(runner, "lib/PottsModels/reproductions/data/15/" * r["dir"] * "/") && isfile(joinpath(P615I_ROOT, runner))
        for f in p615i_files(r["path"])
            b = basename(f)
            ok = any(e -> endswith(lowercase(b), e), P615I_RECORD_EXT) && filesize(f) <= 10 * 2^20 &&
                 !any(p -> occursin(p, b), P615I_G_NAMES)
            ok || @info "P6.15i: not a figure or small statistic: $f"
            @test ok
        end
    end
    # the page's own assets
    recfiles = Set(p615i_sha(f) for r in P615I_RECORDS for f in p615i_files(r["path"]))
    manifest = joinpath(P615I_ASSETS, "provenance.toml")
    listed = isfile(manifest) ? get(TOML.parsefile(manifest), "files", Dict{String, Any}()) : Dict{String, Any}()
    for f in p615i_files(P615I_ASSETS)
        f == manifest && continue
        rel = relpath(f, P615I_ASSETS)
        e = get(listed, rel, nothing)
        ok = p615i_sha(f) in recfiles ||
             (e isa AbstractDict && isdir(joinpath(P615I_DATA, string(get(e, "record", "")))) && !isempty(string(get(e, "record", ""))) &&
              get(e, "kind", "") in ("figure", "statistics"))
        ok = ok && !any(p -> occursin(p, basename(f)), P615I_G_NAMES)
        ok || @info "P6.15i: page asset without provenance: $rel"
        @test ok
    end
    g = get(ENV, "OPENVT_MONOLAYER_REPO", "")
    if isdir(g)
        cands = [p615i_files(P615I_ASSETS); (f for r in P615I_CITED for f in p615i_files(r["path"]))...]
        @test isempty(p615i_collisions(cands, g))
    else
        @info "P6.15i: OPENVT_MONOLAYER_REPO not set; the byte check against G is skipped"
    end
end

@testset "P6.15i (h) forbidden text: no private sheet, no docs/references, no contact" begin
    @test !isempty(P615I_SRC)
    for re in P615I_FORBIDDEN
        hit = match(re, P615I_SRC)
        hit === nothing || @info "P6.15i: forbidden text on the page: $(hit.match)"
        @test hit === nothing
    end
    refs = get(ENV, "POTTS_REFERENCES", joinpath(P615I_ROOT, "docs", "references"))
    if isdir(refs)
        names = unique(basename(f) for f in p615i_files(refs) if endswith(lowercase(f), ".pdf") && length(splitext(basename(f))[1]) >= 8)
        hits = filter(n -> occursin(n, P615I_SRC) || occursin(splitext(n)[1], P615I_SRC), names)
        isempty(hits) || @info "P6.15i: docs/references file names on the page: $hits"
        @test isempty(hits)
        cands = [p615i_files(P615I_ASSETS); (f for r in P615I_CITED for f in p615i_files(r["path"]))...]
        @test isempty(p615i_collisions(cands, refs))
    else
        @info "P6.15i: docs/references not present; its name and byte checks are skipped"
    end
end

@testset "P6.15i (i) in the docs navigation; builds with Documenter (opt-in)" begin
    make = isfile(P615I_MAKE) ? read(P615I_MAKE, String) : ""
    by_name = occursin("15_openvt_monolayer", make)
    by_loop = occursin(r"readdir\(REPRODUCTIONS\)", make) && occursin("Literate.markdown(joinpath(REPRODUCTIONS", make) &&
              (occursin("\"Published models\"", make) || occursin("\"Paper models\"", make))
    @test by_name || by_loop
    @test dirname(P615I_PAGE) == joinpath(P615I_ROOT, "lib", "PottsModels", "reproductions") && isfile(P615I_PAGE)
    if get(ENV, "POTTS_DOCS_BUILD", "false") == "true"
        cmd = addenv(`$(Base.julia_cmd()) --project=docs docs/make.jl`, "POTTS_DOCS_PUBLISHED" => "true")
        @test success(pipeline(Cmd(cmd; dir = P615I_ROOT); stdout = stdout, stderr = stderr))
        built = joinpath(P615I_ROOT, "docs", "build", "published", "15_openvt_monolayer", "index.html")
        @test isfile(built)
        html = isfile(built) ? read(built, String) : ""
        @test occursin(P615I_TITLE, html)
        for (tag, name, _) in P615I_VIDEOS
            @test occursin(P615I_RELEASES * tag * "/" * name, html)
        end
        for m in eachmatch(r"<img[^>]*\ssrc=\"([^\"]+)\"", html)
            src = m[1]
            startswith(src, "data:") && continue
            @test isfile(normpath(joinpath(dirname(built), src)))
        end
    else
        @info "P6.15i: POTTS_DOCS_BUILD not set; the Documenter build is skipped"
    end
end
