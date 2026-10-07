# M Fig 5 layout ("100 runs of 1000 cells"; spec 15 §3.4, §4.0.2) from this record's
# hist.tsv: one row per Potts.jl case, four columns (PDF of f with a log y axis, CDF of f,
# PDF of a, CDF of a), raw cell counts in bins of width 0.01, stacked by 5 distance bins
# from the initial cell's centre (viridis_r for f, inferno_r for a; inner bin first).
# Potts only: the consortium rows (G) are never copied into git.
#     julia --project=docs lib/PottsModels/reproductions/data/15/f5-2026-10-07/plot_f5.jl
using CairoMakie, DelimitedFiles

const DIR = @__DIR__
d, head = readdlm(joinpath(DIR, "hist.tsv"), '\t'; header = true)
col(name) = d[:, findfirst(==(name), vec(head))]
case, q, dbin, bin, cnt = string.(col("case")), string.(col("quantity")), Int.(col("dbin")), Int.(col("bin")), Int.(col("count"))
dlo, dhi = Float64.(col("d_lo_R")), Float64.(col("d_hi_R"))
const NB = 5
const NBINS = 200

function counts(c, qq)
    H = zeros(Int, NBINS, NB)
    for i in eachindex(cnt)
        (case[i] == c && q[i] == qq) && (H[bin[i] + 1, dbin[i]] += cnt[i])
    end
    return H
end
labels(c) = [let k = findfirst(i -> case[i] == c && dbin[i] == j, eachindex(cnt))
                 "$(floor(Int, dlo[k]))–$(floor(Int, dhi[k]))"
             end for j in 1:NB]

mm = 72 / 25.4
s = 2.2
fig = Figure(; size = (4 * 48mm * s, 2 * 44mm * s), fontsize = 8 * s, fonts = (; regular = "TeX Gyre Heros Makie"))
rowtitle = Dict("b" => "Potts.jl, case (b): β = γ = 0 (100 runs)", "control" => "Potts.jl, negative control: γ = 10⁻⁴ (20 runs)")
x = ((0:(NBINS - 1)) .+ 0.5) ./ 100
for (r, c) in enumerate(("b", "control"))
    for (j, (qq, cmap, xl, cum, logy)) in enumerate((("f", :viridis, "Surface Fraction (f)", false, true),
            ("f", :viridis, "Surface Fraction (f)", true, false), ("a", :inferno, "Area Fraction (a)", false, false),
            ("a", :inferno, "Area Fraction (a)", true, false)))
        H = counts(c, qq)
        cum && (H = cumsum(H; dims = 1))
        cols = reverse(cgrad(cmap, NB; categorical = true).colors)   # *_r: inner bin pale / yellow
        ax = Axis(fig[r, j]; xlabel = xl, ylabel = cum ? "Cumulative count" : "Count",
            yscale = logy ? log10 : identity, xgridcolor = (:black, 0.2), ygridcolor = (:black, 0.2),
            xgridwidth = 0.4, ygridwidth = 0.4, title = j == 1 ? rowtitle[c] : "", titlealign = :left,
            titlesize = 8 * s)
        xlims!(ax, qq == "f" ? (-0.01, 1.01) : (0.3, 1.2))
        base = zeros(NBINS)
        for k in 1:NB
            top = base .+ H[:, k]
            lo = logy ? max.(base, 0.8) : base
            keep = top .> (logy ? 0.8 : 0)
            barplot!(ax, x[keep], top[keep]; fillto = lo[keep], width = 0.01, gap = 0, strokewidth = 0,
                color = cols[k], label = labels(c)[k])
            base = top
        end
        logy && ylims!(ax, 0.8, nothing)
        j in (2, 4) && axislegend(ax, "d [R]"; position = :lt, framevisible = false, labelsize = 7 * s,
            titlesize = 7 * s, patchsize = (8, 8), rowgap = 0)
    end
end
save(joinpath(DIR, "fig5.png"), fig; px_per_unit = 1)
println(filesize(joinpath(DIR, "fig5.png")))
