# P6.15m m4, re-scoped (D-225; replaces the D-222 freeze `15_openvt_entries.jl`): the
# CheckerboardCPM characterisation on page 15. Frozen (AUTONOMY §7.3) once committed by the
# coordinator; the test author writes no implementation.
#
# Maintainer (D-225): "ok we can leave checkerboard out of the submission, but keep it in the
# docs". So:
#   - the OpenVT submission stays sequential-only, exactly as P6.15l merged it: no `entries`
#     keyword, no OPENVT_ENTRIES / OPENVT_CHECKERBOARD_TOKEN, no checkerboard folder, bulk
#     file, EMAIL.md text or O1 replay; Q27 is withdrawn (never raised);
#   - page 15 keeps a "Potts.jl (checkerboard)" section and its figure slots, as a
#     characterisation of the algorithm, not as a consortium entry.
#
# Sources: spec 15 §1.3 (the characterisation; placement directly after each Potts.jl slot);
# D-008 (claims), D-218 (the spread rule), D-220 (claim-conflict thinning, own-T time mapping,
# ΔH brute-force evidence), D-221 (the 4-vs-64-colour contrast), D-223 (ΔH evidence kept),
# D-224 (T_cb calibrated on the P1b chain at the production colour count, 4 = 4), D-225.
#
# Every number is READ from the latest final checkerboard record (as
# `15_openvt_checkerboard.jl` picks it: the latest `data/15/checkerboard-<date>/` with meta
# status "final", else the latest), never hard-coded: the record is being regenerated under
# D-224, so T_cb, the cycle and the counts change.
#
# ---------------------------------------------------------------------------------------------
# What the record must provide (meta.toml [time], written by the D-224 runner)
# ---------------------------------------------------------------------------------------------
#   T_lambda2 (T_cb, MCS), T_seq (the sequential P1 record's 156), T_seq_p1b (the sequential
#   T on the same P1b chain), z (against P1), z_p1b (like with like), cycle_mcs, alpha_text
#   ("50/<cycle>"), colours_chain and colours_monolayer (Int; equal, D-224); comparison.tsv
#   (beyond = true|false per row); entry/deviations.tsv; ablation.tsv (its `colours` column:
#   the contrast arm, 64 under D-221). Optional: meta [dH_check] with `copies` (Int) and
#   `mismatches` (Int); when present, the page must quote both.
#
# ---------------------------------------------------------------------------------------------
# Page 15 (the Literate source; read, not run)
# ---------------------------------------------------------------------------------------------
# (P1) A level-3 heading naming "Potts.jl (checkerboard)" inside Results, after the level-3
#      "Deviations" heading and before "## 4. Details"; the heading carries no figure/table
#      label and no "deviation", "verdict" or "video" (the frozen page test's order picks).
#      Its section (to the next heading of level ≤ 3) does not say "pending" and names the
#      record directory, the first 8 characters of its commit and its machine (the cpu up to
#      " w/", case-insensitive).
# (P2) Not a submission: the section says the checkerboard is not part of the (consortium)
#      submission and is a characterisation ("characteris/zation") of the algorithm. It names
#      no folder token (`Potts.jl_checkerboard`), colour key (`PottsJLcheckerboard`), Q27
#      colour (0,109,44), banner, `implementations/` or `results/Potts…` path, and says
#      neither "second entry", "two entries" nor "submitted".
# (P3) The time scale, from meta [time]: T_lambda2, T_seq_p1b, T_seq, "<cycle_mcs> MCS",
#      alpha_text, z and z_p1b to two decimals; the calibration colour counts:
#      "<colours_chain> colours" on the chain and "<colours_monolayer>" on the monolayer, in one
#      paragraph that says "chain" and "monolayer".
# (P4) The comparison summary "<flagged> of <rows>" from comparison.tsv, and a deviations table
#      (header with "Ours", a "Potts.jl"/"sequential" reference column, "cause" and "Author
#      question") with one row per entry/deviations.tsv row: the first cell holds the metric id
#      and "(<case>)"; the row holds the first decimal number of `ours` and of `paper`, the
#      cause's leading clause (before ':'), and a last cell starting "not an author question",
#      "not asked" or "resolved" (and "not an author question" when the record's does).
#      Backslashes and backticks are ignored when matching.
# (P5) The cause and its evidence: "thinning", "claim", "D-008", "D-220", "not a bug", the
#      ablation's contrast arm "<max colours of ablation.tsv> colours", and the ΔH brute-force
#      check ("ΔH" and "brute force"/"brute-force", with "0 mismatches" or "no mismatch"; with
#      meta [dH_check], its copies count, digits possibly grouped by "," or a space).
# (P6) Figure slots directly after the Potts.jl slot (spec §1.3): in the "Figure 2" section the
#      record_figure call after (calibration-2026-10-05, fig2_bde.png) is (CB record,
#      fig2.png); in the "Figures 3 and 9" section (f3-f8-2026-10-08, fig3.png) is followed by
#      (CB record, fig3.png) and (f3-f8-2026-10-08, fig8.png) by (CB record, fig9.png). Those
#      two sections name "Potts.jl (checkerboard)", and the Figure 2 one T_lambda2. No other CB
#      record_figure call on the page. The page asserts the commit:
#      `record("<CB record>"; commit = "<8 hex>")`.
# (P7) Table S5 (Details): the section names "Potts.jl (checkerboard)", the CB record and
#      T_lambda2.
# (P8) The renders fig2.png, fig3.png, fig9.png are in the CB record (PNG, ≤ 10 MiB), each named
#      in a plot_*.jl script of the record.
# (P9) Page-wide: no "Q27", no "Q28" (D-219, D-225), nothing private (the package test's list,
#      the repository URL aside).
#
# ---------------------------------------------------------------------------------------------
# The submission is unchanged (D-225)
# ---------------------------------------------------------------------------------------------
# (S1, always) PottsModels defines no OPENVT_CHECKERBOARD_TOKEN or OPENVT_ENTRIES, and
#      `openvt_submission_package` takes no `entries` keyword.
# (S2, bulk tier: OPENVT_PACKAGE_BULK set, else a clean skip) The default build and the
#      `split = :email` build carry no trace of the checkerboard: no path and no text member
#      (README, CSV, TOML, EMAIL.md, scripts) that contains "checkerboard" (any case) or
#      "CheckerboardCPM"; the trees are exactly implementations/Potts.jl and results/Potts.jl
#      (and core.zip, bulk/, EMAIL.md). Byte equality with the P6.15l build is the frozen
#      `15_openvt_package.jl` / `15_openvt_d213.jl`'s job; this pins that adding the page
#      section, the renders and the plot scripts changes nothing the package reads.
using Test, TOML, Printf, PottsModels

const P615P_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const P615P_DATA = joinpath(P615P_ROOT, "lib", "PottsModels", "reproductions", "data", "15")
const P615P_PAGE = joinpath(P615P_ROOT, "lib", "PottsModels", "reproductions", "15_openvt_monolayer.jl")
const P615P_BULK_ENV = "OPENVT_PACKAGE_BULK"
const P615P_BULK = get(ENV, P615P_BULK_ENV, "")
const P615P_LABEL = "Potts.jl (checkerboard)"
const P615P_SEQ_CAL = "calibration-2026-10-05"
const P615P_SEQ_F3F8 = "f3-f8-2026-10-08"
const P615P_RENDERS = ["fig2.png", "fig3.png", "fig9.png"]
const P615P_STATUS = r"^(not an author question|not asked|resolved)"i
const P615P_NOT_SUBMISSION = [r"Potts\.jl_checkerboard", r"PottsJLcheckerboard", r"0,\s*109,\s*44", r"\bbanner\b"i,
    r"implementations/", r"results/Potts"i, r"second (Potts\.jl )?entry"i, r"two (Potts\.jl )?entries"i, r"\bsubmitted\b"i,
    r"\bQ27\b", r"\bQ28\b"]
const P615P_FORBIDDEN = [
    r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i,
    r"docs/references"i, r"POTTS_REFERENCES", r"manuscript-draft"i,
    r"correspondence"i, r"\be-?mails?\b"i, r"\basked on\b"i, r"\bwe (have )?(asked|wrote|sent|contacted|emailed)\b"i,
    r"\bcontacted (the|R\.|Dr)"i, r"\banswered by\b"i, r"personal communication"i,
    r"\bletters? (to|from)\b"i, r"\bsubmitted to\b"i,
    r"praneeth"i, r"merugu"i, r"jiang"i, r"\bPI\b", r"nucbox"i, r"tailscale"i, r"100\.107\.",
    r"/Users/", r"/home/", r"/private/", r"/tmp/", r"\.claude", r"scratchpad"i,
]

# ---- helpers ------------------------------------------------------------------------------------
function p615p_tsv(path)
    ls = filter(!isempty, split(replace(read(path, String), "\r\n" => "\n"), '\n'))
    h = String.(split(ls[1], '\t'))
    return [Dict(zip(h, String.(split(l, '\t')))) for l in ls[2:end]]
end
p615p_q(s) = "\\Q" * s * "\\E"
p615p_dec(s) = (m = match(r"\d+\.\d+", s); m === nothing ? nothing : m.match)
p615p_2dp(x) = @sprintf("%.2f", x)
# a number as printed in prose: plain, or grouped by "," / thin or plain space
p615p_numre(n::Integer) = Regex("(?<![0-9])" * join(collect(string(n))[1:end], "[,\\s\u2009\u202f]?") * "(?![0-9])")
function p615p_tables(text)
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
p615p_issep(row) = all(c -> occursin(r"^:?-{3,}:?$", c), row)
# paragraphs (blank-line separated; list items and table rows on their own), whitespace collapsed
p615p_paras(t) = [String(strip(replace(x, r"\s+" => " "))) for q in split(t, r"\n\s*\n") for x in split(q, r"\n(?=\s*(?:[-*]|\d+\.)\s|\s*\|)")]

# ---- the record ---------------------------------------------------------------------------------
function p615p_record()
    dirs = isdir(P615P_DATA) ? sort(filter(d -> occursin(r"^checkerboard-\d{4}-\d{2}-\d{2}$", d) &&
                                                isdir(joinpath(P615P_DATA, d)), readdir(P615P_DATA))) : String[]
    isempty(dirs) && return nothing
    st(d) = (p = joinpath(P615P_DATA, d, "meta.toml"); isfile(p) ? string(get(TOML.parsefile(p), "status", "")) : "")
    finals = filter(d -> st(d) == "final", dirs)
    return isempty(finals) ? last(dirs) : last(finals)
end
const P615P_REC = p615p_record()
p615p_rec(f...) = joinpath(P615P_DATA, something(P615P_REC, "?"), f...)
const P615P_META = P615P_REC === nothing ? Dict{String, Any}() : TOML.parsefile(p615p_rec("meta.toml"))
const P615P_PROV = P615P_REC === nothing ? Dict{String, Any}() : TOML.parsefile(p615p_rec("provenance.toml"))
const P615P_TIME = get(P615P_META, "time", Dict{String, Any}())
const P615P_TIME_KEYS = ["T_lambda2", "T_seq", "T_seq_p1b", "z", "z_p1b", "cycle_mcs", "alpha_text", "colours_chain", "colours_monolayer"]
const P615P_COMMIT8 = first(string(get(P615P_PROV, "commit", "")), 8)
const P615P_MACHINE = lowercase(strip(first(split(string(get(P615P_PROV, "cpu", "")), " w/"))))
p615p_flagged() = (rows = isfile(p615p_rec("comparison.tsv")) ? p615p_tsv(p615p_rec("comparison.tsv")) : Dict{String, String}[];
                   (count(r -> r["beyond"] == "true", rows), length(rows)))
p615p_devs() = isfile(p615p_rec("entry", "deviations.tsv")) ? p615p_tsv(p615p_rec("entry", "deviations.tsv")) : Dict{String, String}[]
p615p_maxcolours() = isfile(p615p_rec("ablation.tsv")) ?
                     maximum(parse(Int, r["colours"]) for r in p615p_tsv(p615p_rec("ablation.tsv"))) : nothing
p615p_clause(r) = String(strip(first(split(r["suspected_cause"], ':'))))

function p615p_dev_findings(text)
    bad = String[]
    tabs = filter(t -> length(t) >= 3 && p615p_issep(t[2]) &&
                       (h = lowercase(join(t[1], " | ")); occursin("ours", h) && occursin("cause", h) &&
                        occursin("author question", h) && occursin(r"potts\.jl|sequential", h)), p615p_tables(text))
    isempty(tabs) && return ["no deviations table (Ours, the sequential reference, cause, Author question)"]
    rows = [r for t in tabs for r in t[3:end] if !p615p_issep(r)]
    devs = p615p_devs()
    isempty(devs) && push!(bad, "the record has no deviation rows")
    for d in devs
        m, c = String(first(split(d["target"]))), d["case"]
        idre = Regex("(?<![A-Za-z0-9._@])" * p615p_q(m) * "(?![A-Za-z0-9._@])")
        ok = any(filter(r -> occursin(idre, r[1]) && occursin("($c)", r[1]), rows)) do r
            t = join(r, " | ")
            o, p = p615p_dec(d["ours"]), p615p_dec(d["paper"])
            (o === nothing || occursin(o, t)) && (p === nothing || occursin(p, t)) && occursin(p615p_clause(d), t) &&
                occursin(P615P_STATUS, last(r)) &&
                (!startswith(d["author_question"], "not an author question") || startswith(last(r), "not an author question"))
        end
        ok || push!(bad, "no row for $m ($c) with its values, cause class and status")
    end
    return bad
end

# ---- the page -------------------------------------------------------------------------------------
const P615P_SRC = isfile(P615P_PAGE) ? read(P615P_PAGE, String) : ""
const P615P_LINES = split(P615P_SRC, '\n')
const P615P_HEADS = [(i, length(m[1]), String(m[2])) for (i, l) in enumerate(P615P_LINES)
                     for m in (match(r"^# (#{1,6}) +(.*?)\s*$", l),) if m !== nothing]
function p615p_section(k)
    i, lvl, _ = P615P_HEADS[k]
    j = findnext(h -> h[2] <= lvl, P615P_HEADS, k + 1)
    return join(P615P_LINES[i:(j === nothing ? length(P615P_LINES) : P615P_HEADS[j][1] - 1)], '\n')
end
p615p_head(f) = findfirst(f, P615P_HEADS)
p615p_calls(sec) = [(String(m[1]), String(m[2])) for m in eachmatch(r"record_figure\(\s*\"([^\"]+)\"\s*,\s*\"([^\"]+)\"", sec)]
p615p_prose(sec) = replace(join([replace(l, r"^#\s?" => "") for l in split(sec, '\n') if startswith(l, "#")], '\n'), "\\" => "")
function p615p_after(calls, seq, file)
    i = findfirst(==(seq), calls)
    return i !== nothing && i < length(calls) && calls[i + 1] == (something(P615P_REC, "?"), file)
end

# =============================================================================================
@testset "P6.15m m4 (R) the record provides the page's numbers (D-224)" begin
    @test P615P_REC !== nothing
    for k in P615P_TIME_KEYS
        ok = haskey(P615P_TIME, k)
        ok || @info "P6.15m m4: meta.toml [time] of $(P615P_REC) lacks $k (the D-224 re-run writes it)"
        @test ok
    end
    @test get(P615P_TIME, "colours_chain", -1) == get(P615P_TIME, "colours_monolayer", -2)          # D-224
    @test get(P615P_TIME, "alpha_text", "") == "50/$(get(P615P_TIME, "cycle_mcs", "?"))"
    nf, nt = p615p_flagged()
    @test nt > 0
    @test !isempty(p615p_devs()) && p615p_maxcolours() !== nothing
    dh = get(P615P_META, "dH_check", nothing)
    dh === nothing || @test get(dh, "copies", 0) isa Integer && get(dh, "mismatches", -1) isa Integer
end

@testset "P6.15m m4 (P1–P5) page 15: the Potts.jl (checkerboard) section" begin
    @test !isempty(P615P_SRC) && P615P_REC !== nothing
    kdev = p615p_head(h -> h[2] == 3 && occursin(r"^Deviations"i, h[3]))
    kdet = p615p_head(h -> h[2] == 2 && occursin(r"^(\d+\.\s*)?Details"i, h[3]))
    kcb = p615p_head(h -> h[2] == 3 && occursin(P615P_LABEL, h[3]))
    @test kcb !== nothing
    @test kdev !== nothing && kdet !== nothing && kcb !== nothing && kdev < kcb < kdet
    if kcb !== nothing && P615P_REC !== nothing
        sec = p615p_section(kcb)
        prose = p615p_prose(sec)
        flat = replace(prose, r"\s+" => " ")          # line breaks of the Literate comments do not matter
        h = P615P_HEADS[kcb][3]
        # (P1)
        @test !occursin(r"deviation|verdict|video|Figures?\s*\d|Tables?\s*S?\d"i, h)
        @test !occursin(r"pending"i, sec)
        @test occursin(P615P_REC, sec) && length(P615P_COMMIT8) == 8 && occursin(P615P_COMMIT8, sec)
        @test !isempty(P615P_MACHINE) && occursin(P615P_MACHINE, lowercase(flat))
        # (P2) a characterisation, not a submission
        @test any(p -> occursin(r"\bnot\b[^.]{0,60}\bsubmission"i, p), p615p_paras(prose))
        @test occursin(r"characteri[sz]ation"i, flat)
        bad = [re.pattern for re in P615P_NOT_SUBMISSION if occursin(re, sec)]
        isempty(bad) || @info "P6.15m m4 page: submission wording in the checkerboard section" bad
        @test isempty(bad)
        # (P3) the time scale and the colour counts, from the record
        t = P615P_TIME
        if all(k -> haskey(t, k), P615P_TIME_KEYS)
            for s in (string(t["T_lambda2"]), string(t["T_seq_p1b"]), string(t["T_seq"]), "$(t["cycle_mcs"]) MCS",
                string(t["alpha_text"]), p615p_2dp(t["z"]), p615p_2dp(t["z_p1b"]))
                ok = occursin(s, flat)
                ok || @info "P6.15m m4 page: the checkerboard section lacks" s
                @test ok
            end
            cc, cm = t["colours_chain"], t["colours_monolayer"]
            @test any(p -> occursin(r"chain"i, p) && occursin(r"monolayer"i, p) && occursin(Regex("\\b$cc colou?rs"), p) &&
                           occursin(Regex("\\b$cm\\b"), p), p615p_paras(prose))
        end
        # (P4) the comparison summary and the deviations table
        nf, nt = p615p_flagged()
        @test nt > 0 && occursin("$nf of $nt", flat)
        f = p615p_dev_findings(sec)
        isempty(f) || @info "P6.15m m4 page deviations" first(f, 10)
        @test isempty(f)
        # (P5) the cause and the evidence
        for re in (r"thinning"i, r"claim"i, r"D-008", r"D-220", r"not a bug"i, r"ΔH", r"brute[- ]force"i,
            r"\b0 mismatches\b|\bno mismatch"i)
            ok = occursin(re, flat)
            ok || @info "P6.15m m4 page: the cause text lacks" re
            @test ok
        end
        mc = p615p_maxcolours()
        @test mc !== nothing && occursin(Regex("$mc colou?rs"), flat)
        dh = get(P615P_META, "dH_check", nothing)
        dh === nothing || @test occursin(p615p_numre(dh["copies"]), flat) && occursin(Regex("\\b$(dh["mismatches"]) mismatch"), flat)
    end
end

@testset "P6.15m m4 (P6–P9) page 15: figure slots, Table S5, renders, wording" begin
    @test P615P_REC !== nothing
    k2 = p615p_head(h -> h[2] == 3 && occursin(r"^Figure 2\b", h[3]))
    k39 = p615p_head(h -> h[2] == 3 && occursin(r"Figures 3 and 9", h[3]))
    @test k2 !== nothing && k39 !== nothing
    if k2 !== nothing && k39 !== nothing
        s2, s39 = p615p_section(k2), p615p_section(k39)
        @test p615p_after(p615p_calls(s2), (P615P_SEQ_CAL, "fig2_bde.png"), "fig2.png")
        @test p615p_after(p615p_calls(s39), (P615P_SEQ_F3F8, "fig3.png"), "fig3.png")
        @test p615p_after(p615p_calls(s39), (P615P_SEQ_F3F8, "fig8.png"), "fig9.png")
        @test occursin(P615P_LABEL, s2) && occursin(P615P_LABEL, s39)
        @test haskey(P615P_TIME, "T_lambda2") && occursin(string(P615P_TIME["T_lambda2"]), s2)
        for s in (s2, s39)
            @test !any(re -> occursin(re, s), P615P_NOT_SUBMISSION)
        end
    end
    allcb = filter(c -> c[1] == something(P615P_REC, "?"), p615p_calls(P615P_SRC))
    @test sort(allcb) == sort([(something(P615P_REC, "?"), f) for f in P615P_RENDERS])
    @test P615P_REC !== nothing &&
          occursin(Regex("record\\(\\s*\"" * p615p_q(P615P_REC) * "\"\\s*;\\s*commit\\s*=\\s*\"" * P615P_COMMIT8 * "\"\\s*\\)"), P615P_SRC)
    # (P7)
    kdet = p615p_head(h -> h[2] == 2 && occursin(r"^(\d+\.\s*)?Details"i, h[3]))
    ks5 = p615p_head(h -> h[2] == 3 && occursin(r"Table S5"i, h[3]))
    @test ks5 !== nothing && kdet !== nothing && ks5 > kdet
    if ks5 !== nothing
        s5 = p615p_section(ks5)
        @test occursin(P615P_LABEL, s5) && occursin(something(P615P_REC, "?"), s5) &&
              haskey(P615P_TIME, "T_lambda2") && occursin(string(P615P_TIME["T_lambda2"]), s5)
    end
    # (P8)
    if P615P_REC !== nothing
        scripts = filter(f -> startswith(f, "plot_") && endswith(f, ".jl"), readdir(p615p_rec()))
        for f in P615P_RENDERS
            p = p615p_rec(f)
            ok = isfile(p) && filesize(p) <= 10 * 2^20 && read(p, 8) == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
            ok || @info "P6.15m m4: the render $f is missing from $(P615P_REC) (or not a PNG)"
            @test ok
            @test any(s -> occursin(f, read(p615p_rec(s), String)), scripts)
        end
    end
    # (P9)
    @test !occursin(r"\bQ2[78]\b", P615P_SRC)
    bad = [re.pattern for re in P615P_FORBIDDEN if occursin(re, replace(P615P_SRC, "PraneethMerugu/Potts.jl" => ""))]
    isempty(bad) || @info "P6.15m m4 page: forbidden text" bad
    @test isempty(bad)
end

@testset "P6.15m m4 (S1) the submission API is unchanged (D-225)" begin
    @test !isdefined(PottsModels, :OPENVT_CHECKERBOARD_TOKEN)
    @test !isdefined(PottsModels, :OPENVT_ENTRIES)
    @test !hasmethod(PottsModels.openvt_submission_package, Tuple{String}, (:entries,))
end

if isempty(P615P_BULK) || !isdir(P615P_BULK)
    @testset "P6.15m m4 (S2) the package carries no checkerboard (bulk tier)" begin
        @info "P6.15m m4: $(P615P_BULK_ENV) not set; the package check is skipped"
        @test_skip "P6.15m m4 (S2) needs $(P615P_BULK_ENV)"
    end
else
    @testset "P6.15m m4 (S2) the package carries no checkerboard (D-225)" begin
        out = mktempdir()
        U, S = joinpath(out, "u"), joinpath(out, "s")
        trace(s) = occursin(r"checkerboard"i, s) || occursin("CheckerboardCPM", s)
        textext = (".md", ".csv", ".toml", ".jl", ".txt")
        try
            withenv(P615P_BULK_ENV => P615P_BULK) do
                PottsModels.openvt_submission_package(U)
                PottsModels.openvt_submission_package(S; split = :email)
            end
            @test sort(readdir(joinpath(U, "implementations"))) == ["Potts.jl"] && sort(readdir(joinpath(U, "results"))) == ["Potts.jl"]
            bad = String[]
            for (root, _, fs) in walkdir(U), f in fs
                p = joinpath(root, f)
                rel = relpath(p, U)
                trace(rel) && push!(bad, rel)
                any(e -> endswith(f, e), textext) && trace(read(p, String)) && push!(bad, "$rel (text)")
            end
            @test sort(readdir(S)) == ["EMAIL.md", "bulk", "core.zip"]
            trace(read(joinpath(S, "EMAIL.md"), String)) && push!(bad, "EMAIL.md")
            append!(bad, filter(trace, readdir(joinpath(S, "bulk"))))
            for m in filter(!isempty, readlines(`unzip -Z1 $(joinpath(S, "core.zip"))`))
                trace(m) && push!(bad, "core.zip:$m")
                any(e -> endswith(m, e), textext) && trace(String(read(`unzip -p $(joinpath(S, "core.zip")) $m`))) &&
                    push!(bad, "core.zip:$m (text)")
            end
            isempty(bad) || @info "P6.15m m4: checkerboard traces in the submission" first(bad, 10)
            @test isempty(bad)
        finally
            rm(out; recursive = true, force = true)
        end
    end
end
