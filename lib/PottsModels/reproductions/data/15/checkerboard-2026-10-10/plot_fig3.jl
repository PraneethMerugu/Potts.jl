# Figure 3 for Potts.jl (checkerboard) (spec 15 §1.3, the slot after the sequential
# `f3-f8-2026-10-08/fig3.png`), from this record's timeseries.tsv: the sequential slot's
# layout and colours (N, r [R] and A [R²] against time [T], log y; case (f) σ_X = 0 run 1
# thick blue, the 100 runs of case (b) thin red, the dashed bulk law), time in this entry's
# own cycle (meta.toml [time] cycle_mcs, D-220, D-224). The sequential entry's case (f) run 1
# (f3-f8-2026-10-08, 775-MCS cycles) is drawn in grey for reference. Every series ends at its
# first save with ≥ 1000 cells. Writes fig3.png.
#     julia --project=docs lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/plot_fig3.jl
using CairoMakie, DelimitedFiles, TOML

const DIR = @__DIR__
const SEQ = joinpath(DIR, "..", "f3-f8-2026-10-08")
const CYCLE = TOML.parsefile(joinpath(DIR, "meta.toml"))["time"]["cycle_mcs"]
const CYCLE_SEQ = 775
const CELLS = 1000
num(x) = x isa AbstractString ? (x == "nan" ? NaN : parse(Float64, x)) : Float64(x)

function cutser(t, N, r, A)
    p = sortperm(t)
    t, N, r, A = t[p], N[p], r[p], A[p]
    j = something(findfirst(>=(CELLS), N), length(N))
    return (; t = t[1:j], N = N[1:j], r = r[1:j], A = A[1:j])
end
function series(file, cycle)
    d, head = readdlm(file, '\t', Any; header = true)
    col(name) = d[:, findfirst(==(name), vec(head))]
    cases, seeds, mcs = string.(col("case")), Int.(col("seed")), Int.(col("mcs"))
    Ns, rs, As = Int.(col("N")), num.(col("r")), num.(col("A"))
    return function (case)
        out = []
        for s in sort(unique(seeds[cases .== case]))
            i = findall(k -> cases[k] == case && seeds[k] == s, eachindex(cases))
            push!(out, cutser(mcs[i] ./ cycle, Ns[i], rs[i], As[i]))
        end
        return out
    end
end
cb = series(joinpath(DIR, "timeseries.tsv"), CYCLE)
sq = series(joinpath(SEQ, "timeseries.tsv"), CYCLE_SEQ)
det, sto, det_seq = first(cb("f")), cb("b"), first(sq("f"))

mm = 72 / 25.4
s = 2.2
blue, red = RGBf(31 / 255, 80 / 255, 200 / 255), RGBf(200 / 255, 30 / 255, 30 / 255)
fig = Figure(; size = (3 * 58mm * s, 50mm * s), fontsize = 8 * s, fonts = (; regular = "TeX Gyre Heros Makie"))
tt = range(0, 10; length = 200)
title = "Potts.jl (checkerboard), $(CYCLE)-MCS cycles: case (f) σ_X = 0, run 1 (blue); case (b), $(length(sto)) runs (red).\n" *
        "Grey: Potts.jl (sequential), case (f) run 1, 775-MCS cycles"
for (j, (q, lab, bulk, lims)) in enumerate(((:N, "Number of cells N", t -> 2.0^t, (1, 2000)),
        (:r, "Radius r [R]", t -> 2.0^(t / 2), (1, 50)), (:A, "Area A [R²]", t -> π * 2.0^t, (1, 5000))))
    ax = Axis(fig[1, j]; xlabel = "Time [T]", ylabel = lab, yscale = log10, xgridcolor = (:black, 0.2),
        ygridcolor = (:black, 0.2), xgridwidth = 0.4, ygridwidth = 0.4, title = "")
    for x in sto
        y = getfield(x, q)
        k = findall(v -> isfinite(v) && v > 0, y)
        lines!(ax, x.t[k], y[k]; color = (red, 0.35), linewidth = 0.6)
    end
    for (x, c, lw) in ((det_seq, (:grey35, 0.8), 1.6), (det, blue, 2.5))
        y = getfield(x, q)
        k = findall(v -> isfinite(v) && v > 0, y)
        lines!(ax, x.t[k], y[k]; color = c, linewidth = lw)
    end
    lines!(ax, tt, bulk.(tt); color = :black, linestyle = :dash, linewidth = 1)
    xlims!(ax, 0, 10.5)
    ylims!(ax, lims...)
end
Label(fig[0, 1:3], title; halign = :left, justification = :left, fontsize = 8 * s, font = :bold)
save(joinpath(DIR, "fig3.png"), fig; px_per_unit = 1)
println(filesize(joinpath(DIR, "fig3.png")))
