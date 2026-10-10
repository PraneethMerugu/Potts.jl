# P6.15k (D-211 R1, D-212): the Potts.jl row of M's Figure 7 in the 9 Oct 2026 draft's grid
# form, "Tissue Snapshots with Surface Inhibition": columns 1.1×, 2×, 5×, 10×, 20× (the Table 1
# multiples), one 10⁴-cell colony per column at that multiple's T1 γ (β = 0), empty where our
# T1 is "—" (1.1× and 2×, as for every lattice framework). A render only: the colonies are this
# record's O5 files `f7/` (replicate 1 at γ = 0.1625, 0.5375, 0.7625, from `table1.tsv` and
# `runs.tsv`); no run file is touched.
#
# Style (M's grid, D-185 consortium figure): each cell a filled disc of radius radius_i at its
# centroid (R), no strokes, yellow = no inhibition, teal = surface-inhibited (`inhibited` = 1);
# the tissue outline in black, the concave hull of the centroids as metrics.cpp draws it
# (concaveman, concavity 1.5, lengthThreshold 0). The outline is a tissue outline, not a cell
# outline. All colonies share one length scale. The panels carry no number: M's label
# quantity is unstated (D-211 R5, on our open question list), so each colony's C/C_circle
# (metrics.cpp's roughness 1, `openvt_metrics(x, y, g).C_rel`) goes to fig7_grid.tsv and the
# captions instead. Column headers and the legend are figure labels outside the panels.
#
# Writes fig7_grid.png, fig7_grid.tsv (multiple parameter value file N inhibited B C_rel),
# fig7_hull.tsv (multiple j x y; the outline's vertices in order) and fig7_grid.toml (the
# figure's form). Floats are written with `string` (exact). Pinned by
# `lib/PottsModels/test/reproductions/15_openvt_d211.jl`.
#     julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/sweeps-2026-10-08/plot_f7_grid.jl
using CairoMakie, TOML
using PottsModels

const DIR = @__DIR__
const K = 7
const PARAM = "gamma"
const TITLE = "Tissue Snapshots with Surface Inhibition"
const LEGEND = ["No Inhibition", "Surface Inhibition", "Concave Hull"]
const COLOURS = (none = "#f2cf1d", inhibited = "#1b9e9a", hull = "#000000")   # M: yellow, teal, black
const MULTS = [1.1, 2.0, 5.0, 10.0, 20.0]
const COLS = ["1.1x", "2x", "5x", "10x", "20x"]
const CONCAVITY = 1.5
const LENGTH_THRESHOLD = 0.0
const PANEL_PX = 520

function tsv(path)
    ls = filter(!isempty, readlines(path))
    head = String.(split(ls[1], '\t'))
    return [Dict(zip(head, String.(split(l, '\t')))) for l in ls[2:end]]
end

# the colonies: (column, value, O5 path relative to this record); T1 "—" columns are empty
t1 = filter(r -> r["parameter"] == PARAM, tsv(joinpath(DIR, "table1.tsv")))
runs = Dict((r["sweep"], parse(Int, r["q"]), parse(Int, r["k"])) => r for r in tsv(joinpath(DIR, "runs.tsv")))
colonies = Tuple{String, Float64, String}[]
empty = String[]
for (j, m) in enumerate(MULTS)
    r = only(filter(x -> parse(Float64, x["multiple"]) == m, t1))
    if r["threshold"] == "—"
        push!(empty, COLS[j])
        continue
    end
    γ = parse(Float64, r["threshold"])
    run = runs[(PARAM, round(Int, γ * 10_000), 1)]
    push!(colonies, (COLS[j], γ, "f7/" * openvt_filename(:O5; gamma = γ, mcs = parse(Int, run["mcs"]))))
end

# the outline and C/C_circle of each colony (the consortium's metrics.cpp boundary)
data = Dict{String, Any}()
for (col, v, f) in colonies
    o = read_openvt(joinpath(DIR, f), :O5)
    hull = PottsModels.Analysis.concave_hull(zip(o.x_pos, o.y_pos); concavity = CONCAVITY,
        length_threshold = LENGTH_THRESHOLD)
    crel = openvt_metrics(o.x_pos, o.y_pos, 1 .- o.inhibited).C_rel
    data[col] = (; v, f, o, hull, crel)
end
open(joinpath(DIR, "fig$(K)_grid.tsv"), "w") do io
    println(io, join(("multiple", "parameter", "value", "file", "N", "inhibited", "B", "C_rel"), '\t'))
    for (col, _, _) in colonies
        d = data[col]
        println(io, join((col, PARAM, string(d.v), d.f, length(d.o.x_pos), count(==(1), d.o.inhibited), length(d.hull),
            string(d.crel)), '\t'))
    end
end
open(joinpath(DIR, "fig$(K)_hull.tsv"), "w") do io
    println(io, join(("multiple", "j", "x", "y"), '\t'))
    for (col, _, _) in colonies, (j, p) in enumerate(data[col].hull)
        println(io, join((col, j, string(p[1]), string(p[2])), '\t'))
    end
end
open(joinpath(DIR, "fig$(K)_grid.toml"), "w") do io
    TOML.print(io, Dict("title" => TITLE, "columns" => COLS, "empty" => empty, "panel_label" => "none",
        "measure" => "C/C_circle", "legend" => LEGEND, "parameter" => PARAM,
        "colours" => Dict(String(k) => v for (k, v) in pairs(COLOURS)),
        "hull" => Dict("method" => "concaveman", "concavity" => CONCAVITY, "length_threshold" => LENGTH_THRESHOLD,
            "points" => "centroids"),
        "panel_px" => PANEL_PX, "source" => "f7/ (O5), replicate 1 at the T1 values of table1.tsv"); sorted = true)
end

# one length scale for every colony: the largest half-extent about a colony's centre
centre(o) = (sum(o.x_pos) / length(o.x_pos), sum(o.y_pos) / length(o.y_pos))
ext = maximum(maximum(max(abs(x - centre(d.o)[1]), abs(y - centre(d.o)[2])) + r for (x, y, r) in
                      zip(d.o.x_pos, d.o.y_pos, d.o.radius_i)) for d in values(data)) * 1.03

none, inh, hc = to_color(COLOURS.none), to_color(COLOURS.inhibited), to_color(COLOURS.hull)
fig = Figure(; size = (length(COLS) * PANEL_PX + 140, PANEL_PX + 170), fontsize = 22, backgroundcolor = :white)
Label(fig[1, 1:(length(COLS) + 1)], TITLE; fontsize = 28, font = :bold)
Label(fig[3, 1], "Potts.jl"; rotation = pi / 2, fontsize = 24, tellheight = false)
for (j, col) in enumerate(COLS)
    Label(fig[2, j + 1], replace(col, "x" => "×"); fontsize = 24, tellwidth = false)
    ax = Axis(fig[3, j + 1]; aspect = 1, width = PANEL_PX, height = PANEL_PX, backgroundcolor = :white)
    hidedecorations!(ax); hidespines!(ax)
    limits!(ax, -ext, ext, -ext, ext)
    haskey(data, col) || continue
    d = data[col]
    cx, cy = centre(d.o)
    for (flag, c) in ((0, none), (1, inh))
        k = d.o.inhibited .== flag
        any(k) || continue
        scatter!(ax, d.o.x_pos[k] .- cx, d.o.y_pos[k] .- cy; markersize = 2 .* d.o.radius_i[k], markerspace = :data,
            color = c, strokewidth = 0)
    end
    hx = [p[1] - cx for p in d.hull]
    hy = [p[2] - cy for p in d.hull]
    lines!(ax, [hx; hx[1]], [hy; hy[1]]; color = hc, linewidth = 2.5)
end
Legend(fig[4, 1:(length(COLS) + 1)],
    [MarkerElement(; marker = :circle, color = none, markersize = 22), MarkerElement(; marker = :circle, color = inh, markersize = 22),
        LineElement(; color = hc, linewidth = 3)],
    LEGEND; orientation = :horizontal, framevisible = false, labelsize = 22)
colgap!(fig.layout, 8)
rowgap!(fig.layout, 8)
save(joinpath(DIR, "fig$(K)_grid.png"), fig; px_per_unit = 1)
for (col, _, _) in colonies
    println(col, ": N = ", length(data[col].o.x_pos), ", B = ", length(data[col].hull), ", C/C_circle = ", round(data[col].crel; digits = 4))
end
println("fig$(K)_grid.png ", filesize(joinpath(DIR, "fig$(K)_grid.png")))
