# M Fig 3 layout ("Comparing monolayer growth over time"; spec 15 §4.0 F3) from this record's
# timeseries.tsv: three panels, N, r [R] and area A [R²] against time [T] (read as 775-MCS
# cycles, Q2) on 0–10 with a log y axis; one thick blue deterministic run (case (f), run 1),
# thin red stochastic runs (case (b), all 100), the dashed bulk law (N = 2^t, r = 2^{t/2},
# A = π 2^t). Every series ends at its first save with ≥ 1000 cells (the test's cut).
# With F3F8_G_OUT set to the directory `consortium_on_g.jl` wrote, a consortium row (TST No_CI:
# deterministic run 1 thick, the 100 stochastic runs thin) is drawn first; those rows are
# derived from G and are never committed.
#     [F3F8_G_OUT=…] julia --project=docs lib/PottsModels/reproductions/data/15/f3-f8-2026-10-08/plot_f3.jl
using CairoMakie, DelimitedFiles

const DIR = @__DIR__
const GO = get(ENV, "F3F8_G_OUT", "")
const CYCLE = 775
const CELLS = 1000
num(x) = x isa AbstractString ? (x == "nan" ? NaN : parse(Float64, x)) : Float64(x)

# Potts.jl series: case => [(t, N, r, A)] per seed, cut at ≥ 1000 cells
d, head = readdlm(joinpath(DIR, "timeseries.tsv"), '\t', Any; header = true)
col(name) = d[:, findfirst(==(name), vec(head))]
cases, seeds, mcs, Ns, rs, As = string.(col("case")), Int.(col("seed")), Int.(col("mcs")), Int.(col("N")),
    num.(col("r")), num.(col("A"))
function cutser(t, N, r, A)
    p = sortperm(t)
    t, N, r, A = t[p], N[p], r[p], A[p]
    j = something(findfirst(>=(CELLS), N), length(N))
    return (; t = t[1:j], N = N[1:j], r = r[1:j], A = A[1:j])
end
function potts(case)
    out = []
    for s in sort(unique(seeds[cases .== case]))
        i = findall(k -> cases[k] == case && seeds[k] == s, eachindex(cases))
        push!(out, cutser(mcs[i] ./ CYCLE, Ns[i], rs[i], As[i]))
    end
    return out
end
function tst(kind)
    g, h = readdlm(joinpath(GO, "tst_$(kind).tsv"), '\t', Any; header = true)
    c(name) = g[:, findfirst(==(name), vec(h))]
    run, t, N, r, A = Int.(c("run")), num.(c("t")), Int.(c("N")), num.(c("r")), num.(c("A"))
    return [cutser(t[run .== k], N[run .== k], r[run .== k], A[run .== k]) for k in sort(unique(run))]
end

ROWS = Any[]
if !isempty(GO) && isfile(joinpath(GO, "tst_stochastic.tsv"))
    push!(ROWS, ("TST (consortium data, TST_No_CI: deterministic run 1, 100 stochastic runs)",
        first(tst("deterministic")), tst("stochastic")))
end
push!(ROWS, ("Potts.jl: case (f) σ_X = 0, run 1 (blue); case (b), 100 runs (red)", first(potts("f")), potts("b")))

mm = 72 / 25.4
s = 2.2
blue, red = RGBf(31 / 255, 80 / 255, 200 / 255), RGBf(200 / 255, 30 / 255, 30 / 255)
fig = Figure(; size = (3 * 58mm * s, length(ROWS) * 50mm * s), fontsize = 8 * s,
    fonts = (; regular = "TeX Gyre Heros Makie"))
tt = range(0, 10; length = 200)
for (row, (title, det, sto)) in enumerate(ROWS)
    for (j, (q, lab, bulk, lims)) in enumerate(((:N, "Number of cells N", t -> 2.0^t, (1, 2000)),
            (:r, "Radius r [R]", t -> 2.0^(t / 2), (1, 50)), (:A, "Area A [R²]", t -> π * 2.0^t, (1, 5000))))
        ax = Axis(fig[row, j]; xlabel = "Time [T]", ylabel = lab, yscale = log10, xgridcolor = (:black, 0.2),
            ygridcolor = (:black, 0.2), xgridwidth = 0.4, ygridwidth = 0.4, title = j == 1 ? title : "",
            titlealign = :left, titlesize = 8 * s)
        for x in sto
            y = getfield(x, q)
            k = findall(v -> isfinite(v) && v > 0, y)
            lines!(ax, x.t[k], y[k]; color = (red, 0.35), linewidth = 0.6)
        end
        y = getfield(det, q)
        k = findall(v -> isfinite(v) && v > 0, y)
        lines!(ax, det.t[k], y[k]; color = blue, linewidth = 2.5)
        lines!(ax, tt, bulk.(tt); color = :black, linestyle = :dash, linewidth = 1)
        xlims!(ax, 0, 10.5)
        ylims!(ax, lims...)
    end
end
save(joinpath(DIR, "fig3.png"), fig; px_per_unit = 1)
println(filesize(joinpath(DIR, "fig3.png")))
