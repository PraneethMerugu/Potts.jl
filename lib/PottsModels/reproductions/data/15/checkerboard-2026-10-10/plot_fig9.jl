# Figure 9 for Potts.jl (checkerboard) (spec 15 §1.3, the slot after the sequential
# `f3-f8-2026-10-08/fig8.png`, M's Figure 9 metrics), from this record's timeseries.tsv and
# metrics.tsv: the sequential slot's layout, axes and laws, (a) N, (b) r [R], (c) A [R²]
# (semilog, dashed bulk and dotted boundary laws), (d) C / C_circle, (e) w / r, (f) g
# (log-log, dashed g = 1, dotted 2/t), for case (a) (β = γ = 0, orange, the sequential slot's
# case (a) colour), 10 runs to 10⁴ cells, time in this entry's own cycle (meta.toml [time]
# cycle_mcs). The sequential entry's case (a) runs (f3-f8-2026-10-08, 775-MCS cycles) are drawn
# in grey. This record keeps the O1 summary of each stop state, not the neighbour histogram, so
# panel (g) shows the per-run share of six-neighbour cells and the sd of n (metrics.tsv, both
# algorithms). Writes fig9.png.
#     julia --project=docs lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/plot_fig9.jl
using CairoMakie, DelimitedFiles, TOML

const DIR = @__DIR__
const SEQ = joinpath(DIR, "..", "f3-f8-2026-10-08")
const CYCLE = TOML.parsefile(joinpath(DIR, "meta.toml"))["time"]["cycle_mcs"]
const CYCLE_SEQ = 775
const CELLS = 10_000
num(x) = x isa AbstractString ? (x == "nan" ? NaN : parse(Float64, x)) : Float64(x)
rgb(r, g, b) = RGBf(r / 255, g / 255, b / 255)

function cutser(t, cols)
    p = sortperm(t)
    j = something(findfirst(>=(CELLS), cols.N[p]), length(p))
    return merge((; t = t[p][1:j]), map(v -> v[p][1:j], cols))
end
function series(file, cycle, case)
    d, head = readdlm(file, '\t', Any; header = true)
    col(name) = d[:, findfirst(==(name), vec(head))]
    cases, seeds = string.(col("case")), Int.(col("seed"))
    Q = Dict(k => (k in ("mcs", "N") ? Int.(col(k)) : num.(col(k))) for k in ("mcs", "N", "r", "A", "C", "w", "g"))
    out = []
    for s in sort(unique(seeds[cases .== case]))
        i = findall(k -> cases[k] == case && seeds[k] == s, eachindex(cases))
        push!(out, cutser(Q["mcs"][i] ./ cycle, (; N = Q["N"][i], r = Q["r"][i], A = Q["A"][i], C = Q["C"][i],
            w = Q["w"][i], g = Q["g"][i])))
    end
    return out
end
orange, grey = rgb(230, 97, 1), RGBf(0.45, 0.45, 0.45)
cb = series(joinpath(DIR, "timeseries.tsv"), CYCLE, "a")
sq = series(joinpath(SEQ, "timeseries.tsv"), CYCLE_SEQ, "a")
# series: (label, colour, runs, line width); the reference first, so the entry is drawn on top
SER = Any[("sequential (a), 10 runs,\n775-MCS cycles", grey, sq, 0.7),
    ("checkerboard (a), $(length(cb)) runs,\n$(CYCLE)-MCS cycles", orange, cb, 0.8)]

# per-seed O1 summaries of the stop state (case a), both algorithms
m, mh = readdlm(joinpath(DIR, "metrics.tsv"), '\t', Any; header = true)
mcol(name) = m[:, findfirst(==(name), vec(mh))]
o1(alg, metric) = Float64.(mcol("value")[(string.(mcol("algorithm")) .== alg) .& (string.(mcol("case")) .== "a") .&
                                         (string.(mcol("metric")) .== metric)])

mm = 72 / 25.4
s = 2.2
fig = Figure(; size = (4 * 52mm * s, 2 * 50mm * s), fontsize = 8 * s, fonts = (; regular = "TeX Gyre Heros Makie"))
t = range(0.01, 20; length = 400)
grid = (; xgridcolor = (:black, 0.2), ygridcolor = (:black, 0.2), xgridwidth = 0.4, ygridwidth = 0.4)
function panel(pos, letter, ylabel, f; yscale = identity, xscale = identity, xl = (0, 20), yl = nothing, laws = ())
    ax = Axis(fig[pos...]; xlabel = "Time [T]", ylabel, yscale, xscale, title = "($letter)", titlealign = :left, grid...)
    for (_, c, runs, lw) in SER, x in runs
        y = f(x)
        k = findall(v -> isfinite(v) && (yscale === identity || v > 0), y)
        xscale === identity || (k = filter(i -> x.t[i] > 0, k))
        lines!(ax, x.t[k], y[k]; color = (c, 0.6), linewidth = lw)
    end
    for (law, style) in laws
        tt = filter(v -> isfinite(law(v)) && law(v) > 0, collect(t))
        lines!(ax, tt, law.(tt); color = :black, linestyle = style, linewidth = 1)
    end
    xlims!(ax, xl...)
    yl === nothing || ylims!(ax, yl...)
    return ax
end
panel((1, 1), "a", "N", x -> Float64.(x.N); yscale = log10, yl = (1, 1e5),
    laws = ((v -> 2.0^v, :dash), (v -> π / 4 * v^2, :dot)))
panel((1, 2), "b", "r [R]", x -> x.r; yscale = log10, yl = (1, 1e3),
    laws = ((v -> 2.0^(v / 2), :dash), (v -> sqrt(π / 2) / 2 * v, :dot)))
panel((1, 3), "c", "A [R²]", x -> x.A; yscale = log10, yl = (1, 1e5),
    laws = ((v -> π * 2.0^v, :dash), (v -> (π * v / 2)^2 / 2, :dot)))
panel((1, 4), "d", "C / C_circle", x -> x.C ./ (2 .* sqrt.(π .* x.A)); yl = (1, 2))
panel((2, 1), "e", "w / r", x -> x.w ./ x.r; yl = (0, 1))
panel((2, 2), "f", "g", x -> x.g; yscale = log10, xscale = log10, xl = (1, 20), yl = (0.1, 1.05),
    laws = ((v -> 1.0, :dash), (v -> v >= 2 ? 2 / v : NaN, :dot)))
axg = Axis(fig[2, 3]; xlabel = "Share of cells with n = 6 [%]", ylabel = "sd of n",
    title = "(g)  stop state, per run", titlealign = :left, grid...)
for (alg, c) in (("sequential", grey), ("checkerboard", orange))
    scatter!(axg, 100 .* o1(alg, "O1.n6"), o1(alg, "O1.n_sd"); color = c, markersize = 6 * s, strokewidth = 0)
end
elems = [[LineElement(; color = c, linewidth = 2) for (_, c, _, _) in SER];
    LineElement(; color = :black, linestyle = :dash); LineElement(; color = :black, linestyle = :dot)]
labs = [[l for (l, _, _, _) in SER]; "bulk law"; "boundary law"]
Legend(fig[2, 4], elems, labs; framevisible = false, labelsize = 7 * s, rowgap = 2, tellwidth = false, halign = :left)
save(joinpath(DIR, "fig9.png"), fig; px_per_unit = 1)
println(filesize(joinpath(DIR, "fig9.png")))
