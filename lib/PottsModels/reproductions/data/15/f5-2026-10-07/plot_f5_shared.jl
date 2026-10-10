# P6.15k (D-211 R4, D-212): the Potts.jl case (b) row of M's Figure 5 on the 9 Oct 2026 draft's
# shared distance bins. M now draws every framework on one set of bins, edges 0, 18.6, 37.2,
# 55.8, 74.4 and 93 "radii" (one legend for all rows), instead of each row's own 5 equal bins.
# A re-render only: the counts come from the 100 case (b) O2 files at 1000 cells
# (`Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv`, x, y in R from the
# lattice centre = the initial cell's centre, as in hist.tsv), which live in the bulk directory
# outside git (OPENVT_PACKAGE_BULK, D-204; their sha256s are pinned by the O1 record's
# o2_manifest.tsv). The run files and verdicts of this record (runs.tsv, hist.tsv,
# verdicts.tsv, deviations.tsv) are not touched: V4 judges the distributions, not the display
# bins, so it is unchanged.
#
# Writes hist_shared.tsv (hist.tsv's schema: case quantity dbin d_lo_R d_hi_R bin x_lo count;
# value bins of width 0.01, floor(100x + 1e-9); distance bin j = min(5, searchsortedlast(edges,
# d)), so cells beyond 93 R would join bin 5; rows with count > 0) and fig5_shared.png (M's
# four columns: PDF of f with a log y axis, CDF of f, PDF of a, CDF of a; stacked by distance
# bin, viridis_r for f and inferno_r for a, inner bin first; the a panels on 0–1.0, as M draws
# them). Distances are binned in R from the lattice centre; M's axis appears to be ≈ 2× ours
# (its unit is ≈ 0.5 R by a cross-check on the consortium's TST data), so the unit comparison
# is provisional and on our open question list. Only case (b) has per-cell files;
# the γ = 10⁻⁴ control kept none, so it stays on its own bins in fig5.png.
#     OPENVT_PACKAGE_BULK=<bulk dir> julia --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/f5-2026-10-07/plot_f5_shared.jl
using CairoMakie

const DIR = @__DIR__
const BULK = get(ENV, "OPENVT_PACKAGE_BULK", "")
const O2 = joinpath(BULK, "Potts.jl_5T_MonolayerGrowth_1000_Data")
isdir(O2) || error("set OPENVT_PACKAGE_BULK to the bulk directory holding Potts.jl_5T_MonolayerGrowth_1000_Data/")
const EDGES = [0.0, 18.6, 37.2, 55.8, 74.4, 93.0]     # M Fig 5 (9 Oct 2026), "radii"; applied in R (provisional)
const NB = length(EDGES) - 1
const NBINS = 200
const RUNS = 100

bin(x) = floor(Int, 100x + 1e-9)
dbin(d) = min(NB, searchsortedlast(EDGES, d))

# counts[q][value bin + 1, distance bin]
H = Dict(q => zeros(Int, NBINS, NB) for q in ("f", "a"))
ncells = 0
for k in 1:RUNS
    ls = readlines(joinpath(O2, "cell_data_no_inhibition_$(k).csv"))
    ls[1] == "x,y,r,f,a" || error("cell_data_no_inhibition_$(k).csv: unexpected header $(ls[1])")
    for l in ls[2:end]
        isempty(l) && continue
        v = parse.(Float64, split(l, ','))
        j = dbin(hypot(v[1], v[2]))
        for (q, x) in (("f", v[4]), ("a", v[5]))
            b = bin(x)
            0 <= b < NBINS || error("value $x outside [0, 2)")
            H[q][b + 1, j] += 1
        end
        global ncells += 1
    end
end
open(joinpath(DIR, "hist_shared.tsv"), "w") do io
    println(io, join(("case", "quantity", "dbin", "d_lo_R", "d_hi_R", "bin", "x_lo", "count"), '\t'))
    for q in ("f", "a"), j in 1:NB, b in 1:NBINS
        c = H[q][b, j]
        c > 0 && println(io, join(("b", q, j, string(EDGES[j]), string(EDGES[j + 1]), b - 1, (b - 1) / 100, c), '\t'))
    end
end

# the figure
labels = ["$(EDGES[j])–$(EDGES[j + 1])" for j in 1:NB]
mm = 72 / 25.4
s = 2.2
fig = Figure(; size = (5.0 * 48mm * s, 52mm * s), fontsize = 8 * s, backgroundcolor = :white)
x = ((0:(NBINS - 1)) .+ 0.5) ./ 100
for (j, (qq, cmap, xl, cum, logy)) in enumerate((("f", :viridis, "Surface Fraction (f)", false, true),
        ("f", :viridis, "Surface Fraction (f)", true, false), ("a", :inferno, "Area Fraction (a)", false, false),
        ("a", :inferno, "Area Fraction (a)", true, false)))
    h = cum ? cumsum(H[qq]; dims = 1) : H[qq]
    cols = reverse(cgrad(cmap, NB; categorical = true).colors)   # *_r: inner bin pale / yellow
    ax = Axis(fig[1, j]; xlabel = xl, ylabel = cum ? "Cumulative count" : "Count", yscale = logy ? log10 : identity,
        xgridcolor = (:black, 0.2), ygridcolor = (:black, 0.2), xgridwidth = 0.4, ygridwidth = 0.4,
        title = j == 1 ? "Potts.jl, case (b): β = γ = 0 ($(RUNS) runs, shared bins)" : "", titlealign = :left,
        titlesize = 8 * s)
    xlims!(ax, qq == "f" ? (-0.01, 1.01) : (0.0, 1.0))
    base = zeros(NBINS)
    handles = Any[]
    for k in 1:NB
        top = base .+ h[:, k]
        lo = logy ? max.(base, 0.8) : base
        keep = top .> (logy ? 0.8 : 0) .&& h[:, k] .> 0
        any(keep) && barplot!(ax, x[keep], top[keep]; fillto = lo[keep], width = 0.01, gap = 0, strokewidth = 0,
            color = cols[k])
        push!(handles, PolyElement(; color = cols[k]))
        base = top
    end
    logy && ylims!(ax, 0.8, nothing)
    j in (2, 4) && Legend(fig[1, 4 + j ÷ 2], handles, labels, "d [R, provisional] ($qq)"; framevisible = false, labelsize = 7 * s,
        titlesize = 7 * s, patchsize = (8, 8), rowgap = 0, tellheight = false)
end
save(joinpath(DIR, "fig5_shared.png"), fig; px_per_unit = 1)
println("cells ", ncells, "; per distance bin ", vec(sum(H["f"]; dims = 1)), "; fig5_shared.png ",
    filesize(joinpath(DIR, "fig5_shared.png")))
