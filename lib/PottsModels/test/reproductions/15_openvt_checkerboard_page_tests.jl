# The CheckerboardCPM characterisation on page 15 (D-225; replaces the D-222 test `15_openvt_entries.jl`).
#
# Maintainer (D-225): "ok we can leave checkerboard out of the submission, but keep it in the
# docs". So:
#   - the OpenVT submission stays sequential-only, exactly as D-215 left it: no `entries`
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
# the checkerboard test picks it (`15_openvt_checkerboard_tests.jl`): the latest `data/15/checkerboard-<date>/` with meta
# status "final", else the latest), never hard-coded: the record is being regenerated under
# D-224, so T_cb, the cycle and the counts change.
#
# ---------------------------------------------------------------------------------------------
# What the record must provide (meta.toml [time], written by the D-224 runner)
# ---------------------------------------------------------------------------------------------
#   T_lambda2 (T_cb, MCS), T_seq (the sequential P1 record's 156), T_seq_p1b (the sequential
#   T on the same P1b chain), z (against P1), z_p1b (like with like), cycle_mcs, alpha_text
#   ("50/<cycle>"), phases_chain and phases_monolayer (Int, phases per MCS; equal, D-224;
#   D-271: the lockless block checkerboard has phases, not colours); comparison.tsv
#   (beyond = true|false per row); entry/deviations.tsv (header only when no row is beyond);
#   with flagged rows also ablation.tsv (its `colours` column: the contrast arm). Optional:
#   meta [dH_check] with `copies` (Int) and `mismatches` (Int); when present, the page must
#   quote both.
#
# ---------------------------------------------------------------------------------------------
# Page 15 (the Literate source; read, not run)
# ---------------------------------------------------------------------------------------------
# (P1) A level-3 heading naming "Potts.jl (checkerboard)" inside Results, after the level-3
#      "Deviations" heading and before "## 4. Details"; the heading carries no figure/table
#      label and no "deviation", "verdict" or "video" (the page test's order picks).
#      Its section (to the next heading of level ≤ 3) does not say "pending" and names the
#      record directory, the first 8 characters of its commit and its machine (the cpu up to
#      " w/", case-insensitive).
# (P2) Not a submission: the section says the checkerboard is not part of the (consortium)
#      submission and is a characterisation ("characteris/zation") of the algorithm. It names
#      no folder token (`Potts.jl_checkerboard`), colour key (`PottsJLcheckerboard`), Q27
#      colour (0,109,44), banner, `implementations/` or `results/Potts…` path, and says
#      neither "second entry", "two entries" nor "submitted".
# (P3) The time scale, from meta [time]: T_lambda2, T_seq_p1b, T_seq, "<cycle_mcs> MCS",
#      alpha_text, z and z_p1b to two decimals; the calibration phase counts:
#      "<phases_chain> phases" on the chain and "<phases_monolayer>" on the monolayer, in one
#      paragraph that says "chain" and "monolayer".
# (P4) The comparison summary "<flagged> of <rows>" from comparison.tsv, and, when a row is
#      flagged (D-271), a deviations table
#      (header with "Ours", a "Potts.jl"/"sequential" reference column, "cause" and "Author
#      question") with one row per entry/deviations.tsv row: the first cell holds the metric id
#      and "(<case>)"; the row holds the first decimal number of `ours` and of `paper`, the
#      cause's leading clause (before ':'), and a last cell starting "not an author question",
#      "not asked" or "resolved" (and "not an author question" when the record's does).
#      Backslashes and backticks are ignored when matching.
# (P5) When a row is flagged (D-271), the cause and its evidence: "thinning", "claim", "D-008", "D-220", "not a bug", the
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
#      (and core.zip, bulk/, EMAIL.md). Byte equality with the D-215 build is checked by
#      `15_openvt_package_tests.jl` and `15_openvt_package_delivery_tests.jl`; this pins that adding the page
#      section, the renders and the plot scripts changes nothing the package reads.

@testsetup module OpenVTCheckerboardPageSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, TOML, Printf, PottsModels
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const DATA = joinpath(ROOT, "lib", "PottsModels", "reproductions", "data", "15")
const PAGE = joinpath(ROOT, "lib", "PottsModels", "reproductions", "15_openvt_monolayer.jl")
const BULK_ENV = "OPENVT_PACKAGE_BULK"
const BULK = get(ENV, BULK_ENV, "")
const LABEL = "Potts.jl (checkerboard)"
const SEQ_CAL = "calibration-2026-10-05"
const SEQ_F3F8 = "f3-f8-2026-10-08"
const RENDERS = ["fig2.png", "fig3.png", "fig9.png"]
const STATUS = r"^(not an author question|not asked|resolved)"i
const NOT_SUBMISSION = [
    r"Potts\.jl_checkerboard", r"PottsJLcheckerboard", r"0,\s*109,\s*44", r"\bbanner\b"i,
    r"implementations/", r"results/Potts"i, r"second (Potts\.jl )?entry"i, r"two (Potts\.jl )?entries"i, r"\bsubmitted\b"i,
    r"\bQ27\b", r"\bQ28\b",
]
const FORBIDDEN = [
    r"\bsheets?\b"i, r"PI_SHEET"i, r"author-questions"i,
    r"docs/references"i, r"POTTS_REFERENCES", r"manuscript-draft"i,
    r"correspondence"i, r"\be-?mails?\b"i, r"\basked on\b"i, r"\bwe (have )?(asked|wrote|sent|contacted|emailed)\b"i,
    r"\bcontacted (the|R\.|Dr)"i, r"\banswered by\b"i, r"personal communication"i,
    r"\bletters? (to|from)\b"i, r"\bsubmitted to\b"i,
    r"praneeth"i, r"merugu"i, r"jiang"i, r"\bPI\b", r"nucbox"i, r"tailscale"i, r"100\.107\.",
    r"/Users/", r"/home/", r"/private/", r"/tmp/", r"\.claude", r"scratchpad"i,
]
# ---- helpers ------------------------------------------------------------------------------------
function checkerboard_page_tsv(path)
    ls = filter(!isempty, split(replace(read(path, String), "\r\n" => "\n"), '\n'))
    h = String.(split(ls[1], '\t'))
    return [Dict(zip(h, String.(split(l, '\t')))) for l in ls[2:end]]
end
checkerboard_page_q(s) = "\\Q" * s * "\\E"
dec(s) = (m = match(r"\d+\.\d+", s); m === nothing ? nothing : m.match)
checkerboard_page_2dp(x) = @sprintf("%.2f", x)
# a number as printed in prose: plain, or grouped by "," / thin or plain space
numre(n::Integer) = Regex("(?<![0-9])" * join(collect(string(n))[1:end], "[,\\s\u2009\u202f]?") * "(?![0-9])")
function checkerboard_page_tables(text)
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
issep(row) = all(c -> occursin(r"^:?-{3,}:?$", c), row)
# paragraphs (blank-line separated; list items and table rows on their own), whitespace collapsed
paras(t) = [String(strip(replace(x, r"\s+" => " "))) for q in split(t, r"\n\s*\n") for x in split(q, r"\n(?=\s*(?:[-*]|\d+\.)\s|\s*\|)")]
# ---- the record ---------------------------------------------------------------------------------
function checkerboard_page_record()
    dirs = if isdir(DATA)
        sort(
            filter(
                d -> occursin(r"^checkerboard-\d{4}-\d{2}-\d{2}$", d) &&
                    isdir(joinpath(DATA, d)), readdir(DATA)
            )
        )
    else
        String[]
    end
    isempty(dirs) && return nothing
    st(d) = (p = joinpath(DATA, d, "meta.toml"); isfile(p) ? string(get(TOML.parsefile(p), "status", "")) : "")
    finals = filter(d -> st(d) == "final", dirs)
    return isempty(finals) ? last(dirs) : last(finals)
end
const REC = checkerboard_page_record()
rec(f...) = joinpath(DATA, something(REC, "?"), f...)
const META = REC === nothing ? Dict{String, Any}() : TOML.parsefile(rec("meta.toml"))
const PROV = REC === nothing ? Dict{String, Any}() : TOML.parsefile(rec("provenance.toml"))
const TIME = get(META, "time", Dict{String, Any}())
const TIME_KEYS = ["T_lambda2", "T_seq", "T_seq_p1b", "z", "z_p1b", "cycle_mcs", "alpha_text", "phases_chain", "phases_monolayer"]
const COMMIT8 = first(string(get(PROV, "commit", "")), 8)
const MACHINE = lowercase(strip(first(split(string(get(PROV, "cpu", "")), " w/"))))
function flagged()
    rows = isfile(rec("comparison.tsv")) ? checkerboard_page_tsv(rec("comparison.tsv")) : Dict{String, String}[]
    return (count(r -> r["beyond"] == "true", rows), length(rows))
end
checkerboard_page_devs() = isfile(rec("entry", "deviations.tsv")) ? checkerboard_page_tsv(rec("entry", "deviations.tsv")) : Dict{String, String}[]
function maxcolours()
    if isfile(rec("ablation.tsv"))
        return maximum(parse(Int, r["colours"]) for r in checkerboard_page_tsv(rec("ablation.tsv")))
    else
        return nothing
    end
end
clause(r) = String(strip(first(split(r["suspected_cause"], ':'))))
function dev_findings(text)
    bad = String[]
    tabs = filter(
        t -> length(t) >= 3 && issep(t[2]) &&
            (
            h = lowercase(join(t[1], " | ")); occursin("ours", h) && occursin("cause", h) &&
                occursin("author question", h) && occursin(r"potts\.jl|sequential", h)
        ), checkerboard_page_tables(text)
    )
    isempty(tabs) && return ["no deviations table (Ours, the sequential reference, cause, Author question)"]
    rows = [r for t in tabs for r in t[3:end] if !issep(r)]
    devs = checkerboard_page_devs()
    isempty(devs) && push!(bad, "the record has no deviation rows")
    for d in devs
        m, c = String(first(split(d["target"]))), d["case"]
        idre = Regex("(?<![A-Za-z0-9._@])" * checkerboard_page_q(m) * "(?![A-Za-z0-9._@])")
        ok = any(filter(r -> occursin(idre, r[1]) && occursin("($c)", r[1]), rows)) do r
            t = join(r, " | ")
            o, p = dec(d["ours"]), dec(d["paper"])
            (o === nothing || occursin(o, t)) && (p === nothing || occursin(p, t)) && occursin(clause(d), t) &&
                occursin(STATUS, last(r)) &&
                (!startswith(d["author_question"], "not an author question") || startswith(last(r), "not an author question"))
        end
        ok || push!(bad, "no row for $m ($c) with its values, cause class and status")
    end
    return bad
end
# ---- the page -------------------------------------------------------------------------------------
const SRC = isfile(PAGE) ? read(PAGE, String) : ""
const LINES = split(SRC, '\n')
const HEADS = [
    (i, length(m[1]), String(m[2])) for (i, l) in enumerate(LINES)
        for m in (match(r"^# (#{1,6}) +(.*?)\s*$", l),) if m !== nothing
]
function checkerboard_page_section(k)
    i, lvl, _ = HEADS[k]
    j = findnext(h -> h[2] <= lvl, HEADS, k + 1)
    return join(LINES[i:(j === nothing ? length(LINES) : HEADS[j][1] - 1)], '\n')
end
head(f) = findfirst(f, HEADS)
checkerboard_page_calls(sec) = [(String(m[1]), String(m[2])) for m in eachmatch(r"record_figure\(\s*\"([^\"]+)\"\s*,\s*\"([^\"]+)\"", sec)]
checkerboard_page_prose(sec) = replace(join([replace(l, r"^#\s?" => "") for l in split(sec, '\n') if startswith(l, "#")], '\n'), "\\" => "")
function after(calls, seq, file)
    i = findfirst(==(seq), calls)
    return i !== nothing && i < length(calls) && calls[i + 1] == (something(REC, "?"), file)
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "15 openvt checkerboard page (R) the record provides the page's numbers" setup = [OpenVTCheckerboardPageSetup] tags = [:pottsmodels, :reproductions] begin
    # =============================================================================================
    @testset "15 openvt checkerboard page (R) the record provides the page's numbers" begin
        @test REC !== nothing
        for k in TIME_KEYS
            ok = haskey(TIME, k)
            ok || @info "15 openvt checkerboard page: meta.toml [time] of $(REC) lacks $k (the re-run at the production color count writes it)"
            @test ok
        end
        @test get(TIME, "phases_chain", -1) == get(TIME, "phases_monolayer", -2)            # D-224
        @test get(TIME, "alpha_text", "") == "50/$(get(TIME, "cycle_mcs", "?"))"
        nf, nt = flagged()
        @test nt > 0
        @test isfile(rec("entry", "deviations.tsv"))
        nf > 0 && @test !isempty(checkerboard_page_devs()) && maxcolours() !== nothing   # flagged rows need causes
        dh = get(META, "dH_check", nothing)
        dh === nothing || @test get(dh, "copies", 0) isa Integer && get(dh, "mismatches", -1) isa Integer
    end
end

@testitem "15 openvt checkerboard page (P1–P5) page 15: the Potts.jl (checkerboard) section" setup = [OpenVTCheckerboardPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt checkerboard page (P1–P5) page 15: the Potts.jl (checkerboard) section" begin
        @test !isempty(SRC) && REC !== nothing
        kdev = head(h -> h[2] == 3 && occursin(r"^Deviations"i, h[3]))
        kdet = head(h -> h[2] == 2 && occursin(r"^(\d+\.\s*)?Details"i, h[3]))
        kcb = head(h -> h[2] == 3 && occursin(LABEL, h[3]))
        @test kcb !== nothing
        @test kdev !== nothing && kdet !== nothing && kcb !== nothing && kdev < kcb < kdet
        if kcb !== nothing && REC !== nothing
            sec = checkerboard_page_section(kcb)
            prose = checkerboard_page_prose(sec)
            flat = replace(prose, r"\s+" => " ")          # line breaks of the Literate comments do not matter
            h = HEADS[kcb][3]
            # (P1)
            @test !occursin(r"deviation|verdict|video|Figures?\s*\d|Tables?\s*S?\d"i, h)
            @test !occursin(r"pending"i, sec)
            @test occursin(REC, sec) && length(COMMIT8) == 8 && occursin(COMMIT8, sec)
            @test !isempty(MACHINE) && occursin(MACHINE, lowercase(flat))
            # (P2) a characterisation, not a submission
            @test any(p -> occursin(r"\bnot\b[^.]{0,60}\bsubmission"i, p), paras(prose))
            @test occursin(r"characteri[sz]ation"i, flat)
            bad = [re.pattern for re in NOT_SUBMISSION if occursin(re, sec)]
            isempty(bad) || @info "15 openvt checkerboard page: submission wording in the checkerboard section" bad
            @test isempty(bad)
            # (P3) the time scale and the colour counts, from the record
            t = TIME
            if all(k -> haskey(t, k), TIME_KEYS)
                for s in (
                        string(t["T_lambda2"]), string(t["T_seq_p1b"]), string(t["T_seq"]), "$(t["cycle_mcs"]) MCS",
                        string(t["alpha_text"]), checkerboard_page_2dp(t["z"]), checkerboard_page_2dp(t["z_p1b"]),
                    )
                    ok = occursin(s, flat)
                    ok || @info "15 openvt checkerboard page: the checkerboard section lacks" s
                    @test ok
                end
                cc, cm = t["phases_chain"], t["phases_monolayer"]
                @test any(
                    p -> occursin(r"chain"i, p) && occursin(r"monolayer"i, p) && occursin(Regex("\\b$cc phases"), p) &&
                        occursin(Regex("\\b$cm\\b"), p), paras(prose)
                )
            end
            # (P4) the comparison summary and the deviations table
            nf, nt = flagged()
            @test nt > 0 && occursin("$nf of $nt", flat)
            if nf > 0                                    # (P4, P5) only with flagged rows (D-271)
                f = dev_findings(sec)
                isempty(f) || @info "15 openvt checkerboard page deviations" first(f, 10)
                @test isempty(f)
                for re in (
                        r"thinning"i, r"claim"i, r"not a bug"i, r"ΔH", r"brute[- ]force"i,
                        r"\b0 mismatches\b|\bno mismatch"i,
                    )
                    ok = occursin(re, flat)
                    ok || @info "15 openvt checkerboard page: the cause text lacks" re
                    @test ok
                end
                mc = maxcolours()
                @test mc !== nothing && occursin("$mc colors", flat)
            end
            dh = get(META, "dH_check", nothing)
            dh === nothing || @test occursin(numre(dh["copies"]), flat) && occursin(Regex("\\b$(dh["mismatches"]) mismatch"), flat)
        end
    end
end

@testitem "15 openvt checkerboard page (P6–P9) page 15: figure slots, Table S5, renders, wording" setup = [OpenVTCheckerboardPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt checkerboard page (P6–P9) page 15: figure slots, Table S5, renders, wording" begin
        @test REC !== nothing
        k2 = head(h -> h[2] == 3 && occursin(r"^Figure 2\b", h[3]))
        k39 = head(h -> h[2] == 3 && occursin(r"Figures 3 and 9", h[3]))
        @test k2 !== nothing && k39 !== nothing
        if k2 !== nothing && k39 !== nothing
            s2, s39 = checkerboard_page_section(k2), checkerboard_page_section(k39)
            @test after(checkerboard_page_calls(s2), (SEQ_CAL, "fig2_bde.png"), "fig2.png")
            @test after(checkerboard_page_calls(s39), (SEQ_F3F8, "fig3.png"), "fig3.png")
            @test after(checkerboard_page_calls(s39), (SEQ_F3F8, "fig8.png"), "fig9.png")
            @test occursin(LABEL, s2) && occursin(LABEL, s39)
            @test haskey(TIME, "T_lambda2") && occursin(string(TIME["T_lambda2"]), s2)
            for s in (s2, s39)
                @test !any(re -> occursin(re, s), NOT_SUBMISSION)
            end
        end
        allcb = filter(c -> c[1] == something(REC, "?"), checkerboard_page_calls(SRC))
        @test sort(allcb) == sort([(something(REC, "?"), f) for f in RENDERS])
        @test REC !== nothing &&
            occursin(Regex("record\\(\\s*\"" * checkerboard_page_q(REC) * "\"\\s*;\\s*commit\\s*=\\s*\"" * COMMIT8 * "\"\\s*\\)"), SRC)
        # (P7)
        kdet = head(h -> h[2] == 2 && occursin(r"^(\d+\.\s*)?Details"i, h[3]))
        ks5 = head(h -> h[2] == 3 && occursin(r"Table S5"i, h[3]))
        @test ks5 !== nothing && kdet !== nothing && ks5 > kdet
        if ks5 !== nothing
            s5 = checkerboard_page_section(ks5)
            @test occursin(LABEL, s5) && occursin(something(REC, "?"), s5) &&
                haskey(TIME, "T_lambda2") && occursin(string(TIME["T_lambda2"]), s5)
        end
        # (P8)
        if REC !== nothing
            scripts = filter(f -> startswith(f, "plot_") && endswith(f, ".jl"), readdir(rec()))
            for f in RENDERS
                p = rec(f)
                ok = isfile(p) && filesize(p) <= 10 * 2^20 && read(p, 8) == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
                ok || @info "15 openvt checkerboard page: the render $f is missing from $(REC) (or not a PNG)"
                @test ok
                @test any(s -> occursin(f, read(rec(s), String)), scripts)
            end
        end
        # (P9)
        @test !occursin(r"\bQ2[78]\b", SRC)
        bad = [re.pattern for re in FORBIDDEN if occursin(re, replace(SRC, "PraneethMerugu/Potts.jl" => ""))]
        isempty(bad) || @info "15 openvt checkerboard page: forbidden text" bad
        @test isempty(bad)
    end
end

@testitem "15 openvt checkerboard page (S1) the submission API is unchanged" setup = [OpenVTCheckerboardPageSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt checkerboard page (S1) the submission API is unchanged" begin
        @test !isdefined(PottsModels, :OPENVT_CHECKERBOARD_TOKEN)
        @test !isdefined(PottsModels, :OPENVT_ENTRIES)
        @test !hasmethod(PottsModels.openvt_submission_package, Tuple{String}, (:entries,))
    end
end

@testitem "15 openvt checkerboard page (S2) the package carries no checkerboard (bulk tier)" setup = [OpenVTCheckerboardPageSetup] tags = [:pottsmodels, :reproductions] begin
    if isempty(BULK) || !isdir(BULK)
        @testset "15 openvt checkerboard page (S2) the package carries no checkerboard (bulk tier)" begin
            @info "15 openvt checkerboard page: $(BULK_ENV) not set; the package check is skipped"
            @test_skip "15 openvt checkerboard page (S2) needs $(BULK_ENV)"
        end
    else
        @testset "15 openvt checkerboard page (S2) the package carries no checkerboard" begin
            out = mktempdir()
            U, S = joinpath(out, "u"), joinpath(out, "s")
            trace(s) = occursin(r"checkerboard"i, s) || occursin("CheckerboardCPM", s)
            textext = (".md", ".csv", ".toml", ".jl", ".txt")
            try
                withenv(BULK_ENV => BULK) do
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
                isempty(bad) || @info "15 openvt checkerboard page: checkerboard traces in the submission" first(bad, 10)
                @test isempty(bad)
            finally
                rm(out; recursive = true, force = true)
            end
        end
    end
end
