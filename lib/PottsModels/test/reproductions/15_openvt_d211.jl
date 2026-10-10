# P6.15k (ROADMAP Step 3b; D-211): page 15 and its records follow the 9 Oct 2026 OpenVT
# manuscript draft (M). Frozen (AUTONOMY §7.3). Spec 15 §1.2 lists the changes; this file
# pins R1–R4 on the records and on page 15. The package side (D-204) is in
# `15_openvt_package.jl`, the page layout (headings, items, records) in `15_openvt_page.jl`.
#
# R1  M's Fig 7 is now a grid "Tissue Snapshots with Surface Inhibition": one row per
#     framework, columns 1.1×, 2×, 5×, 10×, 20× (the T1 multiples), one 10⁴-cell colony per
#     cell at that multiple's T1 γ, empty where T1 is "—". Our row is a RENDER of the sweeps
#     record (`data/15/sweeps-2026-10-08/`, P6.15g): its O5 files `f7/` at the T1 γ values of
#     its `table1.tsv` (5×, 10×, 20×: γ = 0.1625, 0.5375, 0.7625, replicate 1); 1.1× and 2× are
#     empty (T1 "—"). New files in that record (the run files stay byte for byte):
#       plot_f7_grid.jl   the render script
#       fig7_grid.png     the Potts row in M's grid form
#       fig7_grid.tsv     one row per drawn colony (header P615K_H_GRID)
#       fig7_hull.tsv     the drawn tissue outline of each colony, vertex by vertex (P615K_H_HULL)
#       fig7_grid.toml    the figure's form (keys below)
# R2  M's new Fig 8 "Tissue Snapshots with Area Inhibition": the same grid for β at γ = 0.
#     Our row: five runs to 10⁴ cells at our T1 β values 0.625, 0.9375, 0.9875, 1.007, 1.0212
#     (`table1.tsv`), in a new record `data/15/f8beta-<date>/` (ROADMAP item "P6.15k").
#     - REPLAY (decided here). The sweeps record's runs are pure functions of their seed
#       (its README: resumable, "a run is a pure function of its seed"), and each T1 β is a
#       final bracket end with replicates k = 1…6 in `runs.tsv` (k = 1 the bisection run).
#       Replicate 1 of each point is replayed with the sweeps test's own job function
#       (`p615g_problem(1400)`, `p615g_job(prob, :beta, q, 1)`, seed 160 000 000 + 100 q + 1,
#       `SequentialCPM(; skip_interior = true, proposal = Moore(1))`, 1400², closed with
#       `edge_guard(5; terminate = true)`, stop at the end of the first MCS with ≥ 10⁴ cells,
#       cap P615G_CAP = 210 335 MCS = 20 × 13.57 cycles, the per-run cap). Checked before this
#       freeze on this Mac at base 4e8668f8: β = 0.625, k = 1 (seed 160 625 001) replayed to
#       MCS 11389 with N = 10005, the record's row exactly, in 146 s; and β = 0, k = 1 replayed
#       to the record's f7 O5 file byte for byte. So every R2 run must equal its sweeps row
#       (stop MCS, N, return code): replicate 1 is then one of the six runs behind T1's mean.
#       Replicate 1 is the colony M's rule would show: γ's Fig 7 panels are replicate 1 too.
#       No run is capped: the 20× run (β = 1.0212, k = 1) stopped at MCS 203 045 (262 cycles).
#     - O5 writer: `openvt_filename(:O5; beta, mcs)` = "Potts.jl_beta_<β>_<mcs>MCS.csv" (β as
#       `string` writes it; the γ form is unchanged), columns x_pos, y_pos, radius_i, inhibited
#       (`p615g_o5`: inhibited = i > 0; at γ = 0 that is area inhibition, a < β).
#     Record files:
#       run_f8beta.jl     the runner: evaluates this file's top-level `P615K*`/`p615k_*`
#                         definitions (as run_sweeps.jl does for its test) and runs `p615k_job`
#       provenance.toml   item "P6.15k", commit (40 hex), dirty_tracked = false, runner (in
#                         this directory), test (this file) and test_sha256, decisions ∋ "D-211",
#                         cpu, threads, julia, started/finished, wall_s; no key "work" (D-195)
#       meta.toml         replay = true, cap_mcs, cells = 10000, lattice = 1400, algorithm
#       runs.tsv          header P615K_H_RUNS, the five runs in multiple order; inhibited = the
#                         O5 count of inhibited = 1
#       f8/               the five O5 files
#       plot_f8_grid.jl, fig8_grid.png, fig8_grid.tsv, fig8_hull.tsv, fig8_grid.toml   as for R1
#       README.md
#     Checks: the run is the pre-registered job; it equals the sweeps row (replay); N ≥ 10⁴;
#     O5 rows = N; the inhibited shares s(m): s(1.1×) > 0.01 (inhibition is present; the β = 0
#     colony has none), s(1.1×) < 1 − g_e < s(2×), with g_e = 0.2973 the F3/F8 record's mean
#     growing fraction at 10⁴ cells for case (e), β = 0.8 (F8.4; 0.625 < 0.8 < 0.9375), and
#     s non-decreasing in β within 0.02 (sampling noise at 10⁴ cells is ≈ 0.005).
# R1/R2 grid files (both figures):
#   fig<k>_grid.tsv   multiple parameter value file N inhibited B C_rel: one row per drawn
#                     colony, in column order; multiple as "5x"; parameter "gamma" | "beta";
#                     file the O5 file's path in the record ("f7/…", "f8/…"); B and C_rel from
#                     the tissue outline below; floats written with Julia's `string` (exact)
#   fig<k>_hull.tsv   multiple j x y: the outline's vertices in order (j = 1…B), x, y in R
#   The tissue outline is the consortium's (G `results/postprocessing/metrics.cpp`, spec 15
#   §3.2): the concave hull of the O5 centroids by concaveman with concavity 1.5 and
#   lengthThreshold 0, i.e. `PottsModels.Analysis.concave_hull(zip(x, y); concavity = 1.5,
#   length_threshold = 0.0)`, and C_rel = C/C_circle = C/(2√(πA)) of that outline, i.e.
#   `openvt_metrics(x, y, g).C_rel` ("roughness 1" of metrics.cpp). The panels carry NO
#   numeric label: M's label quantity is unstated (D-211 R5; no candidate matched; Q24 on our
#   open question list), so C/C_circle goes in the caption or in a table under the figure,
#   named as metrics.cpp's C/C_circle, never as M's quantity.
#   fig<k>_grid.toml
#     title          M's title: "Tissue Snapshots with Surface Inhibition" | "… Area Inhibition"
#     columns        ["1.1x", "2x", "5x", "10x", "20x"]
#     empty          the columns without a colony: ["1.1x", "2x"] for Fig 7 (T1 "—"), [] for Fig 8
#     panel_label    "none"
#     measure        "C/C_circle"
#     legend         ["No Inhibition", "Surface Inhibition" | "Area Inhibition", "Concave Hull"]
#     [colours]      none, inhibited, hull: "#rrggbb". M's colours (D-185): none yellow; Fig 7
#                    inhibited teal, Fig 8 inhibited red; hull black. Both figures use the same
#                    yellow.
#     [hull]         method = "concaveman", concavity = 1.5, length_threshold = 0.0,
#                    points = "centroids"
#   fig<k>_grid.png   holds the declared colours (yellow, the inhibited colour, black) and not
#                     the other figure's inhibited colour; it is drawn large enough that cell
#                     fills keep their exact colour (≥ 300 px per panel); the script draws no text
#                     in the panels (no `text!`, `annotations!` or `annotate` call; column headers
#                     and the legend go through `Label`/`Legend` or axis titles).
# R3  M's metrics figure is Fig 9 (was Fig 8). On page 15 a line that labels Figure 8 outside
#     the Fig 8 (β grid) section must be about the β grid or say that it was the old number
#     ("formerly", "2 Oct"); dated change-log rows are history and exempt; record names
#     (f3-f8-*, fig8.png, F8.1–F8.4) stay. The page test
#     pins the headings ("Figures 3 and 9", a Figure 8 heading, a Figure 9 item).
# R4  M's Fig 5 uses one set of distance bins for every row: edges 0, 18.6, 37.2, 55.8, 74.4,
#     93 ("radii"). Our row is re-rendered on them from the case (b) O2 files (distance from
#     the initial cell's centre, in R, as before). New files in the F5 record
#     (`data/15/f5-2026-10-07/`; its run files and verdicts stay byte for byte, so V4 is
#     unchanged):
#       plot_f5_shared.jl  the render script
#       hist_shared.tsv    hist.tsv's schema and value bins (width 0.01, floor(100x + 1e-9)),
#                          distance bin j = min(5, searchsortedlast(edges, d)); rows with count > 0
#       fig5_shared.png    M's four columns for case (b) on the shared bins
#     Checks: the edges; every case's value histogram summed over distance bins equals
#     hist.tsv's (re-binning moves cells between distance bins only); the totals equal Σ N of
#     runs.tsv; bins beyond the case's largest distance are empty. Opt-in (the bulk O2 files in
#     OPENVT_PACKAGE_BULK): every case (b) count recomputed from the 100 O2 files.
# Page 15: the Fig 7 section shows fig7_grid.png, the Fig 8 section fig8_grid.png, both with
# "C/C_circle", "metrics.cpp" and each colony's C_rel to two decimals; a note that M's label
# quantity is unstated and on our open question list; the Fig 5 section shows
# fig5_shared.png and the shared edges.
#
# Tiers. always: the R1 render, the R4 render, the page (read the committed files).
# SMOKE (default; one model compilation, < 1 min): a β job through the sweeps test's job
# function on 300² to 250 cells, its O5 rows and file name, the β = 0 negative control.
# Record (always): the R2 record. FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full, on the
# PC): the five R2 runs rerun, equal to the record's rows and O5 bytes.
using Test, TOML, SHA, Printf, Potts, PottsModels
using Statistics: mean
import CairoMakie

const P615K_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P615K_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const P615K_DATA = joinpath(P615K_ROOT, "lib", "PottsModels", "reproductions", "data", "15")
const P615K_PAGE = joinpath(P615K_ROOT, "lib", "PottsModels", "reproductions", "15_openvt_monolayer.jl")
const P615K_SWEEPS_TEST = joinpath(@__DIR__, "15_openvt_sweeps.jl")
const P615K_BULK = get(ENV, "OPENVT_PACKAGE_BULK", "")
const P615K_SWEEPS = "sweeps-2026-10-08"
const P615K_F5 = "f5-2026-10-07"
const P615K_F3F8 = "f3-f8-2026-10-08"
const P615K_CYCLE = 775
const P615K_CELLS = 10_000
const P615K_LATTICE = 1400
const P615K_MULTS = [1.1, 2.0, 5.0, 10.0, 20.0]
const P615K_COLS = ["1.1x", "2x", "5x", "10x", "20x"]
const P615K_BETA = [0.625, 0.9375, 0.9875, 1.007, 1.0212]          # our T1 β row (table1.tsv)
const P615K_GAMMA = Union{Nothing, Float64}[nothing, nothing, 0.1625, 0.5375, 0.7625]
const P615K_EDGES = [0.0, 18.6, 37.2, 55.8, 74.4, 93.0]             # M Fig 5 shared distance bins
const P615K_CONCAVITY = 1.5                                          # metrics.cpp's concaveman call
const P615K_LENGTH_THRESHOLD = 0.0
const P615K_GE = 0.2973                                              # F3/F8 F8.4, case (e), β = 0.8
const P615K_SHARE_SLACK = 0.02
const P615K_H_RUNS = ["multiple", "beta", "q", "k", "seed", "lattice", "retcode", "mcs", "N", "capped", "edge_gap",
    "inhibited", "wall_s"]
const P615K_H_GRID = ["multiple", "parameter", "value", "file", "N", "inhibited", "B", "C_rel"]
const P615K_H_HULL = ["multiple", "j", "x", "y"]
const P615K_TITLE = Dict(7 => "Tissue Snapshots with Surface Inhibition", 8 => "Tissue Snapshots with Area Inhibition")
const P615K_LEGEND = Dict(7 => ["No Inhibition", "Surface Inhibition", "Concave Hull"],
    8 => ["No Inhibition", "Area Inhibition", "Concave Hull"])
# run files of the merged records that the renders must not touch (sha256 at base 4e8668f8)
const P615K_PINNED = Dict(
    "f5-2026-10-07/verdicts.tsv" => "ca0b6e2ec2b130e55c5e9feb776a6f116317ff7f2a9a289f661abc375b1bbd76",
    "f5-2026-10-07/runs.tsv" => "ef244efed3aecf9898057648297ae2ef3e5da91d47b0cc45fc0fba34ab1acc50",
    "f5-2026-10-07/hist.tsv" => "8389001316aba4a0144193941730a5bed829a12893120c5f9ff148a7f44674ac",
    "f5-2026-10-07/deviations.tsv" => "c18589c17273cec23628feb114a505eb078fb9ac9090c76ba1413255199c2469",
    "sweeps-2026-10-08/runs.tsv" => "aecde9535f85bd92569b3ef451c79f60ed6033e27a5fe10c2b2b56ec56ea8c7e",
    "sweeps-2026-10-08/table1.tsv" => "6c646b5644607e3ccc299066f78f23dbe9bdba31a7490be0a461c80ecb6b2de0",
    "sweeps-2026-10-08/verdicts.tsv" => "9d2718e307c6fd04209a6746a3912c97083bbc2f33d9610f105f8c44b286367e",
    "sweeps-2026-10-08/f7/Potts.jl_gamma_0.0_11462MCS.csv" => "8d7f3e2f0cc2554e07d4032268e25c38e0977285a0615510233d46e7917355d9",
    "sweeps-2026-10-08/f7/Potts.jl_gamma_0.1625_52907MCS.csv" => "775d3bf75a44284afc01b7e0751a9c237b99ab26b367fa7b04fcef413bb6dc3f",
    "sweeps-2026-10-08/f7/Potts.jl_gamma_0.5375_108081MCS.csv" => "031c5c01a259f6c26697a5fcf2d8a137c29eda48136a2780977a3396e64740ed",
    "sweeps-2026-10-08/f7/Potts.jl_gamma_0.7625_201438MCS.csv" => "a9d4cb07aaf5a8cfd0b0eb2094515c50ad4878eb00a32567f170c6a465ef7f00")

# ---- the sweeps test's job functions, loaded from its source (reused, not copied) ---------------
function p615k_defname(ex)
    ex isa Expr || return nothing
    ex.head === :const && return p615k_defname(ex.args[1])
    ex.head in (:(=), :function) || return nothing
    a = ex.args[1]
    a isa Symbol && return a
    a isa Expr && a.head === :call && return a.args[1]
    a isa Expr && a.head === :where && return a.args[1].args[1]
    return nothing
end
function p615k_sweeps_module()
    m = Module(:P615KG)
    Core.eval(m, :(using Potts, PottsModels, Test))
    Core.eval(m, :(using Statistics: mean))
    for ex in Meta.parseall(read(P615K_SWEEPS_TEST, String)).args
        n = p615k_defname(ex)
        (n isa Symbol && startswith(string(n), r"p615g_|P615G_")) || continue
        Core.eval(m, ex)
    end
    return m
end
const P615KG = p615k_sweeps_module()

# ---- the R2 job (pinned; the runner calls these) -------------------------------------------------
p615k_q(β) = round(Int, β * 10_000)
p615k_job(prob, β; kw...) = P615KG.p615g_job(prob, :beta, p615k_q(β), 1; kw...)
p615k_o5(r) = P615KG.p615g_o5(r.u; β = r.β, γ = 0.0)
p615k_o5_name(β, mcs) = openvt_filename(:O5; beta = β, mcs = mcs)
p615k_hull(x, y) = PottsModels.Analysis.concave_hull(zip(x, y); concavity = P615K_CONCAVITY,
    length_threshold = P615K_LENGTH_THRESHOLD)
p615k_crel(x, y, inhibited) = openvt_metrics(x, y, 1 .- inhibited).C_rel

# ---- readers -------------------------------------------------------------------------------------
function p615k_tsv(path)
    ls = filter(!isempty, readlines(path))
    head = String.(split(ls[1], '\t'))
    return head, [Dict(zip(head, String.(split(l, '\t')))) for l in ls[2:end]]
end
p615k_f(s) = parse(Float64, s)
p615k_sha(p) = bytes2hex(open(sha256, p))
p615k_dirs(prefix) = isdir(P615K_DATA) ? sort(filter(d -> startswith(d, prefix) && isdir(joinpath(P615K_DATA, d)),
    readdir(P615K_DATA))) : String[]
function p615k_table1()
    _, rows = p615k_tsv(joinpath(P615K_DATA, P615K_SWEEPS, "table1.tsv"))
    return rows
end
function p615k_sweep_runs()
    _, rows = p615k_tsv(joinpath(P615K_DATA, P615K_SWEEPS, "runs.tsv"))
    return Dict((r["sweep"], parse(Int, r["q"]), parse(Int, r["k"])) => r for r in rows)
end
p615k_rtime(r) = r["capped"] == "true" ? Inf : parse(Int, r["mcs"]) / P615K_CYCLE
# hex "#rrggbb" -> (r, g, b) in 0:255
function p615k_rgb(s)
    m = match(r"^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$", string(s))
    m === nothing && return nothing
    return Tuple(parse(Int, m[i]; base = 16) for i in 1:3)
end
p615k_yellow(c) = c !== nothing && c[1] >= 200 && c[2] >= 180 && c[3] <= 100
p615k_teal(c) = c !== nothing && c[2] >= c[1] + 40 && c[3] >= c[1] + 40 && abs(c[2] - c[3]) <= 60 && max(c[2], c[3]) <= 210
p615k_red(c) = c !== nothing && c[1] >= 180 && c[2] <= 120 && c[3] <= 130 && c[1] >= c[2] + 80
p615k_black(c) = c !== nothing && max(c...) <= 40

# pixels of a PNG within `tol` (per channel, 0:255) of each colour, and near-black pixels
function p615k_png_counts(path, colours; tol = 16)
    img = CairoMakie.Makie.FileIO.load(path)
    C = CairoMakie.Makie.Colors
    counts = zeros(Int, length(colours))
    black = 0
    for p in img
        C.alpha(p) < 0.5 && continue
        v = (round(Int, 255 * Float64(C.red(p))), round(Int, 255 * Float64(C.green(p))), round(Int, 255 * Float64(C.blue(p))))
        for (k, c) in enumerate(colours)
            maximum(abs.(v .- c)) <= tol && (counts[k] += 1)
        end
        max(v...) <= 40 && (black += 1)
    end
    return counts, black, length(img)
end

# the colonies a grid must draw: (column, parameter, value, O5 path relative to the record)
function p615k_fig7_expected()
    t1 = filter(r -> r["parameter"] == "gamma", p615k_table1())
    runs = p615k_sweep_runs()
    out = Tuple{String, String, Float64, String}[]
    for (j, m) in enumerate(P615K_MULTS)
        r = only(filter(x -> p615k_f(x["multiple"]) == m, t1))
        r["threshold"] == "—" && continue
        γ = p615k_f(r["threshold"])
        run = runs[("gamma", p615k_q(γ), 1)]
        push!(out, (P615K_COLS[j], "gamma", γ, "f7/Potts.jl_gamma_$(γ)_$(run["mcs"])MCS.csv"))
    end
    return out
end
function p615k_fig7_empty()
    t1 = filter(r -> r["parameter"] == "gamma", p615k_table1())
    return [P615K_COLS[j] for (j, m) in enumerate(P615K_MULTS) if only(filter(x -> p615k_f(x["multiple"]) == m, t1))["threshold"] == "—"]
end

# every check of one grid figure k ∈ (7, 8) in record directory D
function p615k_check_grid(D, k, expected, empty)
    stem = "fig$(k)_grid"
    for f in ("plot_$(k == 7 ? "f7" : "f8")_grid.jl", "$(stem).png", "$(stem).tsv", "fig$(k)_hull.tsv", "$(stem).toml")
        @test isfile(joinpath(D, f))
    end
    all(f -> isfile(joinpath(D, f)), ("$(stem).png", "$(stem).tsv", "fig$(k)_hull.tsv", "$(stem).toml")) || return nothing
    # the form
    meta = TOML.parsefile(joinpath(D, "$(stem).toml"))
    @test get(meta, "title", "") == P615K_TITLE[k]
    @test get(meta, "columns", nothing) == P615K_COLS
    @test get(meta, "empty", nothing) == empty
    @test get(meta, "panel_label", "") == "none"
    @test get(meta, "measure", "") == "C/C_circle"
    @test get(meta, "legend", nothing) == P615K_LEGEND[k]
    hull = get(meta, "hull", Dict{String, Any}())
    @test get(hull, "method", "") == "concaveman" && get(hull, "concavity", NaN) == P615K_CONCAVITY &&
          get(hull, "length_threshold", NaN) == P615K_LENGTH_THRESHOLD && get(hull, "points", "") == "centroids"
    col = get(meta, "colours", Dict{String, Any}())
    none, inh, hc = p615k_rgb(get(col, "none", "")), p615k_rgb(get(col, "inhibited", "")), p615k_rgb(get(col, "hull", ""))
    @test p615k_yellow(none)
    @test k == 7 ? p615k_teal(inh) : p615k_red(inh)
    @test p615k_black(hc)
    # the colonies: one row per expected colony, in column order; B and C_rel of the
    # consortium's outline recomputed from the O5 centroids; the outline vertex by vertex
    _, rows = p615k_tsv(joinpath(D, "$(stem).tsv"))
    _, hrows = p615k_tsv(joinpath(D, "fig$(k)_hull.tsv"))
    @test first(p615k_tsv(joinpath(D, "$(stem).tsv"))) == P615K_H_GRID
    @test first(p615k_tsv(joinpath(D, "fig$(k)_hull.tsv"))) == P615K_H_HULL
    @test [(r["multiple"], r["parameter"], p615k_f(r["value"]), r["file"]) for r in rows] == expected
    @test isempty(intersect(empty, [r["multiple"] for r in rows]))
    for r in rows
        f = joinpath(D, r["file"])
        isfile(f) || (@test isfile(f); continue)
        o5 = read_openvt(f, :O5)
        x, y, inhibited = o5.x_pos, o5.y_pos, o5.inhibited
        @test parse(Int, r["N"]) == length(x) && parse(Int, r["inhibited"]) == count(==(1), inhibited)
        h = p615k_hull(x, y)
        @test parse(Int, r["B"]) == length(h)
        crel = p615k_crel(x, y, inhibited)
        @test isapprox(p615k_f(r["C_rel"]), crel; rtol = 1e-12) && crel >= 1
        hv = sort(filter(v -> v["multiple"] == r["multiple"], hrows); by = v -> parse(Int, v["j"]))
        @test [parse(Int, v["j"]) for v in hv] == 1:length(h)
        @test length(hv) == length(h) && all(p615k_f(v["x"]) == p[1] && p615k_f(v["y"]) == p[2] for (v, p) in zip(hv, h))
    end
    @test Set(v["multiple"] for v in hrows) == Set(r["multiple"] for r in rows)
    # the picture: M's colours present, the other figure's inhibited colour absent
    other = k == 7 ? (217, 95, 105) : (44, 123, 140)            # a representative red / teal
    if none !== nothing && inh !== nothing
        (cn, ci, co), black, npx = p615k_png_counts(joinpath(D, "$(stem).png"), [none, inh, other])
        @info "P6.15k fig$(k)_grid.png" none = cn inhibited = ci other = co black npx
        @test cn >= 50 && ci >= 500 && black >= 200
        @test co <= max(20, npx ÷ 10_000)
    end
    # no text in the panels: the script draws none
    src = read(joinpath(D, "plot_$(k == 7 ? "f7" : "f8")_grid.jl"), String)
    @test !occursin(r"\btext!?\s*\(|\bannotations!?\s*\(|\bannotate"i, src)
    return nothing
end

# a hist.tsv-schema table's value histogram of case c, quantity q, summed over distance bins
function p615k_marg(rows, c, q)
    d = Dict{Int, Int}()
    for r in rows
        (r["case"] == c && r["quantity"] == q) || continue
        b = parse(Int, r["bin"])
        d[b] = get(d, b, 0) + parse(Int, r["count"])
    end
    return d
end

# =================================================================================================
@testset "P6.15k R1: the Fig 7 grid, rendered from the sweeps record" begin
    D = joinpath(P615K_DATA, P615K_SWEEPS)
    @test isdir(D)
    # the run files are untouched (a render only)
    for (rel, h) in P615K_PINNED
        startswith(rel, P615K_SWEEPS) && @test isfile(joinpath(P615K_DATA, rel)) && p615k_sha(joinpath(P615K_DATA, rel)) == h
    end
    exp = p615k_fig7_expected()
    # the premise: T1 γ at 5×, 10×, 20× and "—" at 1.1×, 2× (D-211 R1)
    @test [e[3] for e in exp] == filter(!isnothing, P615K_GAMMA)
    @test p615k_fig7_empty() == ["1.1x", "2x"]
    @test all(e -> isfile(joinpath(D, e[4])), exp)
    p615k_check_grid(D, 7, exp, ["1.1x", "2x"])
end

@testset "P6.15k R4: the Fig 5 row on M's shared distance bins" begin
    D = joinpath(P615K_DATA, P615K_F5)
    for (rel, h) in P615K_PINNED
        startswith(rel, P615K_F5) && @test isfile(joinpath(P615K_DATA, rel)) && p615k_sha(joinpath(P615K_DATA, rel)) == h
    end
    for f in ("hist_shared.tsv", "fig5_shared.png", "plot_f5_shared.jl")
        @test isfile(joinpath(D, f))
    end
    if isfile(joinpath(D, "hist_shared.tsv"))
        hh, old = p615k_tsv(joinpath(D, "hist.tsv"))
        sh, new = p615k_tsv(joinpath(D, "hist_shared.tsv"))
        @test sh == hh
        _, runs = p615k_tsv(joinpath(D, "runs.tsv"))
        cases = sort(unique(r["case"] for r in new))
        @test "b" in cases && issubset(cases, unique(r["case"] for r in old))
        for r in new
            j = parse(Int, r["dbin"])
            @test 1 <= j <= 5 && p615k_f(r["d_lo_R"]) == P615K_EDGES[j] && p615k_f(r["d_hi_R"]) == P615K_EDGES[j + 1]
            @test parse(Int, r["count"]) > 0 && r["quantity"] in ("f", "a")
        end
        for c in cases, q in ("f", "a")
            # the value histogram, summed over distance bins, is hist.tsv's
            @test p615k_marg(new, c, q) == p615k_marg(old, c, q)
            n = sum(parse(Int, r["N"]) for r in runs if r["case"] == c)
            @test sum(values(p615k_marg(new, c, q))) == n
            # bins beyond the case's furthest cell are empty
            dmax = maximum(p615k_f(r["d_max_R"]) for r in runs if r["case"] == c)
            @test all(r -> !(r["case"] == c && P615K_EDGES[parse(Int, r["dbin"])] > dmax), new)
        end
        # premise: case (b) reaches past 37.2 R but not 55.8 R, so three bins are filled
        @test sort(unique(parse(Int, r["dbin"]) for r in new if r["case"] == "b")) == [1, 2, 3]
        # opt-in: every case (b) count from the 100 O2 files (x, y from the lattice centre)
        o2 = joinpath(P615K_BULK, "Potts.jl_5T_MonolayerGrowth_1000_Data")
        if !isempty(P615K_BULK) && isdir(o2)
            want = Dict{Tuple{String, Int, Int}, Int}()
            for k in 1:100
                l = readlines(joinpath(o2, "cell_data_no_inhibition_$(k).csv"))
                @test l[1] == "x,y,r,f,a"
                for s in l[2:end]
                    v = parse.(Float64, split(s, ','))
                    j = min(5, searchsortedlast(P615K_EDGES, hypot(v[1], v[2])))
                    for (q, x) in (("f", v[4]), ("a", v[5]))
                        key = (q, j, floor(Int, 100x + 1e-9))
                        want[key] = get(want, key, 0) + 1
                    end
                end
            end
            got = Dict((r["quantity"], parse(Int, r["dbin"]), parse(Int, r["bin"])) => parse(Int, r["count"]) for r in new
                       if r["case"] == "b")
            @test got == want
        else
            @info "P6.15k R4: OPENVT_PACKAGE_BULK not set; the O2 recount is skipped"
        end
    end
    p = joinpath(D, "fig5_shared.png")
    isfile(p) && @test size(CairoMakie.Makie.FileIO.load(p), 1) > 100
end

# ---- SMOKE: the β job and the O5 writer -----------------------------------------------------------
if !P615K_FULL
    @testset "P6.15k SMOKE: a β job through the sweeps job function, its O5 rows" begin
        prob = P615KG.p615g_problem(300; cells = 250, cap = 20_000)
        r = p615k_job(prob, 0.9375; cells = 250, cap = 20_000)
        free = P615KG.p615g_job(prob, :beta, 0, 1; cells = 250, cap = 20_000)
        @info "P6.15k SMOKE" r.mcs r.N free.mcs free.N
        @test r.seed == 160_937_501 && r.β == 0.9375 && r.γ == 0.0
        @test r.retcode === :Terminated && r.N >= 250 && !r.capped
        o = p615k_o5(r)
        @test length(o.x_pos) == r.N && all(in((0, 1)), o.inhibited)
        @test all(<=(1), PottsModels.openvt_frame(r.u; β = r.β, γ = 0.0).i)   # γ = 0: area inhibition only
        @test count(==(1), o.inhibited) > 0                                   # inhibition is present …
        @test all(==(0), p615k_o5((; u = free.u, β = 0.0)).inhibited)         # … and absent at β = 0
        tmp = mktempdir()
        f = joinpath(tmp, "Potts.jl_beta_0.9375_$(r.mcs)MCS.csv")
        write_openvt(f, :O5, o)
        back = read_openvt(f, :O5)
        @test back.inhibited == o.inhibited && length(back.x_pos) == r.N
        @test startswith(read(f, String), "x_pos,y_pos,radius_i,inhibited\n")
        h = p615k_hull(o.x_pos, o.y_pos)
        @test length(h) >= 3 && p615k_crel(o.x_pos, o.y_pos, o.inhibited) >= 1
        # same seed, same run (the replay premise)
        again = p615k_job(prob, 0.9375; cells = 250, cap = 20_000)
        @test again.mcs == r.mcs && Array(again.u.σ) == Array(r.u.σ)
    end
end

@testset "P6.15k O5 file names for β (the writer)" begin
    @test p615k_o5_name(0.9375, 20771) == "Potts.jl_beta_0.9375_20771MCS.csv"
    @test p615k_o5_name(1.0212, 203045) == "Potts.jl_beta_1.0212_203045MCS.csv"
    @test openvt_filename(:O5; gamma = 0.1625, mcs = 52907) == "Potts.jl_gamma_0.1625_52907MCS.csv"   # unchanged
end

# ---- the R2 record ---------------------------------------------------------------------------------
@testset "P6.15k R2 record: the Fig 8 β colonies (data/15/f8beta-*)" begin
    # premises from the merged records
    t1 = filter(r -> r["parameter"] == "beta", p615k_table1())
    @test [p615k_f(r["multiple"]) for r in t1] == P615K_MULTS
    @test [p615k_f(r["threshold"]) for r in t1] == P615K_BETA
    runs = p615k_sweep_runs()
    for (j, β) in enumerate(P615K_BETA)
        q = p615k_q(β)
        sr = runs[("beta", q, 1)]
        @test sr["retcode"] == "Terminated" && sr["capped"] == "false" && parse(Int, sr["N"]) >= P615K_CELLS
        # agreement with table1.tsv: replicate 1 is one of the six runs behind the reported end
        reps = [runs[("beta", q, kk)] for kk in 1:6 if haskey(runs, ("beta", q, kk))]
        @test length(reps) == 6
        row = t1[j]
        tend = p615k_f(p615k_f(row["threshold"]) == p615k_f(row["bracket_lo"]) ? row["t_lo"] : row["t_hi"])
        tm = P615KG.p615g_mean(p615k_rtime.(reps))
        @test isinf(tm) ? tend == Inf : abs(tend - tm) <= 0.0005 + 1e-9
    end
    _, v3 = p615k_tsv(joinpath(P615K_DATA, P615K_F3F8, "verdicts.tsv"))
    @test p615k_f(only(r["ours"] for r in v3 if startswith(r["target"], "F8.4") && r["case"] == "e")) == P615K_GE

    dirs = p615k_dirs("f8beta-")
    length(dirs) == 1 || @info "P6.15k: no R2 record yet (expected exactly one data/15/f8beta-* directory)" dirs
    @test length(dirs) == 1
    if length(dirs) == 1
        D = joinpath(P615K_DATA, only(dirs))
        @test occursin(r"^f8beta-\d{4}-\d{2}-\d{2}$", only(dirs))
        for f in ("README.md", "provenance.toml", "meta.toml", "runs.tsv")
            @test isfile(joinpath(D, f))
        end
        prov = isfile(joinpath(D, "provenance.toml")) ? TOML.parsefile(joinpath(D, "provenance.toml")) : Dict{String, Any}()
        @test get(prov, "item", "") == "P6.15k"
        @test occursin(r"^[0-9a-f]{40}$", string(get(prov, "commit", "")))
        @test get(prov, "dirty_tracked", true) === false
        runner = string(get(prov, "runner", ""))
        @test startswith(runner, "lib/PottsModels/reproductions/data/15/$(only(dirs))/") && isfile(joinpath(P615K_ROOT, runner))
        @test get(prov, "test", "") == "lib/PottsModels/test/reproductions/15_openvt_d211.jl"
        @test occursin(r"^[0-9a-f]{64}$", string(get(prov, "test_sha256", "")))
        @test "D-211" in get(prov, "decisions", String[])
        @test !haskey(prov, "work")
        meta = isfile(joinpath(D, "meta.toml")) ? TOML.parsefile(joinpath(D, "meta.toml")) : Dict{String, Any}()
        @test get(meta, "replay", false) === true
        @test get(meta, "cap_mcs", 0) == P615KG.P615G_CAP && get(meta, "cells", 0) == P615K_CELLS &&
              get(meta, "lattice", 0) == P615K_LATTICE
        @test occursin("skip_interior = true", string(get(meta, "algorithm", "")))

        head, rr = isfile(joinpath(D, "runs.tsv")) ? p615k_tsv(joinpath(D, "runs.tsv")) : (String[], Dict{String, String}[])
        @test head == P615K_H_RUNS
        @test [get(r, "multiple", "") for r in rr] == string.(P615K_MULTS)
        o5dir = joinpath(D, "f8")
        names = isdir(o5dir) ? sort(readdir(o5dir)) : String[]
        expected = Tuple{String, String, Float64, String}[]
        shares = Float64[]
        for (j, r) in enumerate(rr)
            j <= 5 || break
            β = P615K_BETA[j]
            q = p615k_q(β)
            # the pre-registered job
            @test p615k_f(r["beta"]) == β && parse(Int, r["q"]) == q && parse(Int, r["k"]) == 1
            @test parse(Int, r["seed"]) == P615KG.p615g_seed(:beta, q, 1)
            @test parse(Int, r["lattice"]) == P615K_LATTICE
            mcs, N = parse(Int, r["mcs"]), parse(Int, r["N"])
            @test r["retcode"] == "Terminated" && r["capped"] == "false" && N >= P615K_CELLS && mcs <= P615KG.P615G_CAP
            @test parse(Int, r["edge_gap"]) >= P615KG.P615G_GUARD
            # the replay: the sweeps record's replicate 1, exactly
            sr = runs[("beta", q, 1)]
            @test mcs == parse(Int, sr["mcs"]) && N == parse(Int, sr["N"]) && r["retcode"] == sr["retcode"]
            # so the run is one of the six replicates behind table1.tsv's reported end (premise above)
            # the O5 file
            name = "Potts.jl_beta_$(β)_$(mcs)MCS.csv"
            push!(expected, (P615K_COLS[j], "beta", β, "f8/" * name))
            f = joinpath(o5dir, name)
            @test isfile(f)
            if isfile(f)
                o5 = read_openvt(f, :O5)
                @test length(o5.x_pos) == N && all(in((0, 1)), o5.inhibited)
                @test all(isfinite, o5.x_pos) && all(isfinite, o5.y_pos)
                @test count(==(1), o5.inhibited) == parse(Int, r["inhibited"])
                push!(shares, mean(o5.inhibited))
            end
        end
        @test names == sort([basename(e[4]) for e in expected])
        # inhibition shares (area inhibition, a < β): present at 1.1×, below / above case (e)'s
        # share at β = 0.8, non-decreasing in β
        @info "P6.15k R2 inhibited shares" shares
        @test length(shares) == 5
        if length(shares) == 5
            @test shares[1] > 0.01
            @test shares[1] < 1 - P615K_GE < shares[2]
            @test all(shares[j + 1] >= shares[j] - P615K_SHARE_SLACK for j in 1:4)
        end
        # the grid
        p615k_check_grid(D, 8, expected, String[])
    end
end

# ---- FULL: rerun the five R2 runs (offline, on the PC) ---------------------------------------------
if P615K_FULL
    @testset "P6.15k FULL: the five β runs, rerun" begin
        dirs = p615k_dirs("f8beta-")
        @test length(dirs) == 1
        D = length(dirs) == 1 ? joinpath(P615K_DATA, only(dirs)) : ""
        prob = P615KG.p615g_problem(P615K_LATTICE)
        res = Vector{Any}(undef, length(P615K_BETA))
        Threads.@threads :greedy for j in eachindex(P615K_BETA)
            res[j] = p615k_job(prob, P615K_BETA[j])
        end
        runs = p615k_sweep_runs()
        for (j, r) in enumerate(res)
            sr = runs[("beta", p615k_q(P615K_BETA[j]), 1)]
            @test r.mcs == parse(Int, sr["mcs"]) && r.N == parse(Int, sr["N"])
            io = IOBuffer()
            write_openvt(io, :O5, p615k_o5(r))
            f = joinpath(D, "f8", "Potts.jl_beta_$(P615K_BETA[j])_$(r.mcs)MCS.csv")
            @test isfile(f) && take!(io) == read(f)
        end
    end
end

# ---- page 15 ------------------------------------------------------------------------------------
const P615K_SRC = isfile(P615K_PAGE) ? read(P615K_PAGE, String) : ""
const P615K_LINES = split(P615K_SRC, '\n')
# labels a text names: ("F", "3"), ("F", "9") for "Figures 3 and 9" or "Figure 3/9"
function p615k_labels(text)
    out = Tuple{String, String}[]
    for m in eachmatch(r"\b(Figures?|Figs?\.?|Tables?)\s*((?:S?\d+)(?:\s*(?:,|and|&|/|–)\s*S?\d+)*)", text)
        k = startswith(m[1], "T") ? "T" : "F"
        for n in eachmatch(r"S?\d+", m[2])
            push!(out, (k, String(n.match)))
        end
    end
    return out
end
const P615K_HEADS = [(i, length(m[1]), String(m[2])) for (i, l) in enumerate(P615K_LINES)
                     for m in (match(r"^# (#{1,6}) +(.*?)\s*$", l),) if m !== nothing]
# the lines of the first level-3 heading naming `label`, up to the next heading of level ≤ 3
function p615k_section(label)
    k = findfirst(h -> h[2] == 3 && label in p615k_labels(h[3]), P615K_HEADS)
    k === nothing && return 0:-1
    j = findnext(h -> h[2] <= 3, P615K_HEADS, k + 1)
    return P615K_HEADS[k][1]:(j === nothing ? length(P615K_LINES) : P615K_HEADS[j][1] - 1)
end
p615k_text(rng) = join(P615K_LINES[rng], '\n')
const P615K_CCIRCLE = r"C\s*/\s*C_?\{?circle\}?|C/C<sub>circle</sub>"

@testset "P6.15k page 15: Fig 7 and Fig 8 grids, C/C_circle, the label note (R1, R2)" begin
    @test !isempty(P615K_SRC)
    for k in (7, 8)
        sec = p615k_text(p615k_section(("F", string(k))))
        @test !isempty(sec)
        @test occursin("fig$(k)_grid.png", sec)
        @test occursin(P615K_CCIRCLE, sec) && occursin("metrics.cpp", sec)
        @test occursin(r"concave"i, sec) && occursin(r"yellow"i, sec) && occursin(k == 7 ? r"teal"i : r"\bred\b"i, sec)
        # each colony's C/C_circle to two decimals, from the record
        dirs = k == 7 ? [P615K_SWEEPS] : p615k_dirs("f8beta-")
        if length(dirs) == 1 && isfile(joinpath(P615K_DATA, only(dirs), "fig$(k)_grid.tsv"))
            _, rows = p615k_tsv(joinpath(P615K_DATA, only(dirs), "fig$(k)_grid.tsv"))
            @test !isempty(rows)
            for r in rows
                @test occursin(@sprintf("%.2f", p615k_f(r["C_rel"])), sec)
            end
        else
            @test false                                      # the grid table is not there yet
        end
    end
    # the note: M's label quantity is unstated and on our open question list (D-211 R5)
    grids = p615k_text(p615k_section(("F", "7"))) * "\n" * p615k_text(p615k_section(("F", "8")))
    paras = split(replace(grids, r"(?m)^# ?" => ""), r"\n\s*\n")
    @test any(p -> occursin(r"label"i, p) && occursin(r"unstated|not stated"i, p) && occursin("our open question list", p), paras)
end

@testset "P6.15k page 15: Fig 5 on the shared bins (R4) and the metrics figure as Fig 9 (R3)" begin
    sec5 = p615k_text(p615k_section(("F", "5")))
    @test occursin("fig5_shared.png", sec5)
    @test all(e -> occursin(e, sec5), ("18.6", "37.2", "55.8", "74.4", "93"))
    # R3: the metrics figure is Figure 9; the heading that names Figure 3 names 9, not 8
    h3 = [h for h in P615K_HEADS if h[2] == 3 && ("F", "3") in p615k_labels(h[3])]
    @test length(h3) == 1 && ("F", "9") in p615k_labels(only(h3)[3]) && !(("F", "8") in p615k_labels(only(h3)[3]))
    # every other line that labels Figure 8 is about the β grid, or names the old number;
    # dated rows of the page's change log (history) are exempt
    f8 = p615k_section(("F", "8"))
    bad = String[]
    for (i, l) in enumerate(P615K_LINES)
        i in f8 && continue
        occursin(r"^#\s*\|\s*\d{4}-\d{2}-\d{2}\s*\|", l) && continue
        ("F", "8") in p615k_labels(l) || continue
        occursin(r"β|beta|area[- ]inhibit|formerly|2 Oct"i, l) || push!(bad, strip(l))
    end
    isempty(bad) || @info "P6.15k: lines that still call the metrics figure Figure 8" bad
    @test isempty(bad)
    # the metrics figure's own section shows the F3/F8 record's fig8.png
    @test occursin("fig8.png", p615k_text(p615k_section(("F", "9"))))
end
