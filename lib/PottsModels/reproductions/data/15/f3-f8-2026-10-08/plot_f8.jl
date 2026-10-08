# M Fig 8 layout (quantitative comparison, `G:results/metrics.tex`; spec 15 §4.0.2 F8) from this
# record's timeseries.tsv and neighbors.tsv: seven panels, (a) N, (b) r [R], (c) A [R²]
# (semilog, x 0–20, dashed bulk and dotted boundary laws), (d) C / C_circle, (e) w / r,
# (f) g (log-log, dashed g = 1, dotted 2/t from t = 2) and (g) the final neighbour-number
# histogram (p in %). Potts.jl case (a) (β = γ = 0, orange) and case (e) (β = 0.8, the Potts.jl
# colour 8,29,88; the like-for-like case of the legacy curves), 10 runs each to
# 10⁴ cells, time in 775-MCS cycles. With F3F8_G_OUT set to `consortium_on_g.jl`'s output, the
# draft Fig 8's CompuCell3D and Morpheus curves are overlaid after converting px to R (C10):
# they are legacy β = 0.8 runs in their own legacy cycles (D4), footnoted; never committed.
#     [F3F8_G_OUT=…] julia --project=docs lib/PottsModels/reproductions/data/15/f3-f8-2026-10-08/plot_f8.jl
using CairoMakie, DelimitedFiles

const DIR = @__DIR__
const GO = get(ENV, "F3F8_G_OUT", "")
const CYCLE = 775
const CELLS = 10_000
num(x) = x isa AbstractString ? (x == "nan" ? NaN : parse(Float64, x)) : Float64(x)
rgb(r, g, b) = RGBf(r / 255, g / 255, b / 255)

d, head = readdlm(joinpath(DIR, "timeseries.tsv"), '\t', Any; header = true)
col(name) = d[:, findfirst(==(name), vec(head))]
cases, seeds = string.(col("case")), Int.(col("seed"))
Q = Dict(k => (k in ("mcs", "N") ? Int.(col(k)) : num.(col(k))) for k in ("mcs", "N", "r", "A", "C", "w", "g"))
function cutser(t, cols)
    p = sortperm(t)
    j = something(findfirst(>=(CELLS), cols.N[p]), length(p))
    return merge((; t = t[p][1:j]), map(v -> v[p][1:j], cols))
end
function potts(case)
    out = []
    for s in sort(unique(seeds[cases .== case]))
        i = findall(k -> cases[k] == case && seeds[k] == s, eachindex(cases))
        push!(out, cutser(Q["mcs"][i] ./ CYCLE, (; N = Q["N"][i], r = Q["r"][i], A = Q["A"][i], C = Q["C"][i],
            w = Q["w"][i], g = Q["g"][i])))
    end
    return out
end
nb, nh = readdlm(joinpath(DIR, "neighbors.tsv"), '\t', Any; header = true)
ncol(name) = nb[:, findfirst(==(name), vec(nh))]
function nhist(case)
    i = string.(ncol("case")) .== case
    n, c = Int.(ncol("n"))[i], Int.(ncol("count"))[i]
    ks = sort(unique(n))
    tot = sum(c)
    return ks, [100 * sum(c[n .== k]) / tot for k in ks]
end

# series: (label, colour, runs, neighbour histogram, line width)
SER = Any[("Potts.jl (a): β = γ = 0, 10 runs", rgb(230, 97, 1), potts("a"), nhist("a"), 0.8),
    ("Potts.jl (e): β = 0.8, 10 runs", rgb(8, 29, 88), potts("e"), nhist("e"), 0.8)]
const LEGACY = !isempty(GO) && isfile(joinpath(GO, "legacy_morpheus.tsv"))
if LEGACY
    for (fw, name, c) in (("compucell3d", "CompuCell3D", rgb(37, 52, 148)), ("morpheus", "Morpheus", rgb(44, 127, 184)))
        g, h = readdlm(joinpath(GO, "legacy_$(fw).tsv"), '\t', Float64; header = true)
        gc(k) = g[:, findfirst(==(k), vec(h))]
        s = cutser(gc("t"), (; N = round.(Int, gc("N")), r = gc("r"), A = gc("A"), C = gc("C"), w = gc("w"), g = gc("g")))
        n, _ = readdlm(joinpath(GO, "neighbors_$(fw).csv"), ',', Float64; header = true)
        push!(SER, ("$name, legacy β = 0.8ᵃ", c, [s], (Int.(n[:, 1]), n[:, 2]), 1.6))
    end
end

mm = 72 / 25.4
s = 2.2
fig = Figure(; size = (4 * 52mm * s, 2 * 50mm * s + 14mm * s), fontsize = 8 * s,
    fonts = (; regular = "TeX Gyre Heros Makie"))
t = range(0.01, 20; length = 400)
grid = (; xgridcolor = (:black, 0.2), ygridcolor = (:black, 0.2), xgridwidth = 0.4, ygridwidth = 0.4)
function panel(pos, letter, ylabel, f; yscale = identity, xscale = identity, xl = (0, 20), yl = nothing, laws = ())
    ax = Axis(fig[pos...]; xlabel = "Time [T]", ylabel, yscale, xscale, title = "($letter)", titlealign = :left, grid...)
    for (_, c, runs, _, lw) in SER, x in runs
        y = f(x)
        k = findall(v -> isfinite(v) && (yscale === identity || v > 0) && (xscale === identity || true), y)
        xscale === identity || (k = filter(i -> x.t[i] > 0, k))
        lines!(ax, x.t[k], y[k]; color = (c, lw < 1 ? 0.6 : 1.0), linewidth = lw)
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
axg = Axis(fig[2, 3]; xlabel = "Number of neighbours n", ylabel = "p [%]", title = "(g)", titlealign = :left, grid...)
for (j, (_, c, _, (n, p), _)) in enumerate(SER)
    off = (j - (length(SER) + 1) / 2) * 0.15
    barplot!(axg, n .+ off, p; width = 0.15, gap = 0, strokewidth = 0, color = c)
end
xlims!(axg, 1.5, 9.5)
ylims!(axg, 0, 80)
elems = [[LineElement(; color = c, linewidth = 2) for (_, c, _, _, _) in SER];
    LineElement(; color = :black, linestyle = :dash); LineElement(; color = :black, linestyle = :dot)]
labs = [[l for (l, _, _, _, _) in SER]; "bulk law"; "boundary law"]
Legend(fig[2, 4], elems, labs; framevisible = false, labelsize = 7 * s, rowgap = 2, tellwidth = false)
LEGACY && Label(fig[3, 1:4], "ᵃ Draft Fig 8 lattice curves (G postprocessing/measurements_*.csv, neighbors_*.csv): " *
                            "legacy β = 0.8 runs with legacy parameter sets, t in each framework's legacy cycle " *
                            "(CompuCell3D 310 MCS, Morpheus 97 MCS; D4), lengths converted from px to R (C10). " *
                            "Potts.jl: t in 775-MCS cycles.";
    fontsize = 6.5 * s, halign = :left, tellwidth = false, justification = :left, word_wrap = true)
save(joinpath(DIR, "fig8.png"), fig; px_per_unit = 1)
println(filesize(joinpath(DIR, "fig8.png")))
