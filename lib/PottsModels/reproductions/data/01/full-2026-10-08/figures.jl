# P6.3f: the record's figures, from points.tsv (2008 sweeps) and verdicts.tsv. Not frozen.
# usage: julia --project=lib/PottsModels/test figures.jl <recorddir>
using CairoMakie
const REC = abspath(ARGS[1])
function tsv(file)
    lines = filter(!isempty, readlines(joinpath(REC, file)))
    head = split(lines[1], '\t')
    return [Dict(String(h) => String(v) for (h, v) in zip(head, split(l, '\t'; keepempty = true))) for l in lines[2:end]]
end
P = tsv("points.tsv")
num(p, c) = parse(Float64, p[c])
lastnum(s) = parse(Float64, match(r"(-?[0-9.]+)\s*$", s)[1])

fig = Figure(; size = (1100, 700))
panels = [
    ("V-C3", "χcc / χcM", p -> true, p -> lastnum(p["point"]), "Fig. 5 (10⁴ MCS)"),
    ("V-C4", "J(c,c)", p -> occursin("CI true", p["point"]), p -> parse(Float64, match(r"J_cc ([0-9.]+)", p["point"])[1]), "Fig. 7, CI"),
    ("V-C4", "J(c,c)", p -> occursin("CI false", p["point"]), p -> parse(Float64, match(r"J_cc ([0-9.]+)", p["point"])[1]), "Fig. 7, no CI"),
    ("V-C5", "χ(c,M)", p -> occursin("CI true", p["point"]), p -> parse(Float64, match(r"χcM ([0-9.]+)", p["point"])[1]), "Fig. 8, CI"),
    ("V-C7", "s", p -> occursin("CI true", p["point"]), p -> parse(Float64, match(r"s ([0-9.]+)", p["point"])[1]), "Fig. 9, CI"),
]
for (k, (row, xl, keep, xof, ttl)) in enumerate(panels)
    pts = filter(p -> p["row"] == row && keep(p), P)
    ax = Axis(fig[fldmod1(k, 3)...]; xlabel = xl, ylabel = "compactness C", title = "$row: 01b $ttl", limits = (nothing, (0, 1.1)))
    x = xof.(pts)
    o = sortperm(x)
    scatterlines!(ax, x[o], num.(pts, "mean_C_N")[o]; color = :black, label = "code MCS N (binding)")
    scatterlines!(ax, x[o], num.(pts, "mean_C_N+100")[o]; color = :red3, label = "N MCS after relaxation")
    k == 1 && axislegend(ax; position = :lt)
end
pts9 = filter(p -> p["row"] == "V-C9", P)
ax = Axis(fig[2, 3]; ylabel = "compactness C", title = "V-C9: 01b Fig. 11 (T, mode)", xticks = (1:length(pts9), replace.(getindex.(pts9, "point"), "extension_" => "", "T " => "")),
    xticklabelrotation = 0.4, limits = (nothing, (0, 1.1)))
scatter!(ax, 1:length(pts9), num.(pts9, "mean_C_N"); color = :black)
scatter!(ax, 1:length(pts9), num.(pts9, "mean_C_N+100"); color = :red3, marker = :utriangle)
save(joinpath(REC, "sweeps_2008.png"), fig)
println("wrote ", joinpath(REC, "sweeps_2008.png"))
