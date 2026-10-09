# M Fig 6 layout (`G:results/time_to_10k.tex`; spec 15 §3.5, §4.0.2 F6) from this record's
# runs.tsv, points.tsv and table1.tsv: (a) time to 10⁴ cells [5T] against β at γ = 0, (b) against
# γ at β = 0, log y on [10¹, 10³], with M's dashed lines at 13.57 × {1.1, 2, 5, 10, 20}.
# Potts.jl: every run (small dots), the point means (line and markers; a point with a capped
# replicate has t̄ = Inf and is drawn as an open triangle at the top, "> 20×") and the T1
# thresholds (rings at (threshold, τ_m)). Consortium content is only the frozen constants of
# the test (no G file is read): TST's and Artistoo's Table 1 thresholds at τ_m and the V2b
# references at their β. In panel (b) the γ = 0 point is the β = 0 point (one model).
#     [P615G_OUT=<record dir>] julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/sweeps-2026-10-08/plot_f6.jl
using CairoMakie

const DIR = abspath(expanduser(get(ENV, "P615G_OUT", @__DIR__)))
const T0 = 13.57
const MULTS = (1.1, 2.0, 5.0, 10.0, 20.0)
tau(m) = round(T0 * m; digits = 4)
const TOP = 900.0                                   # where capped means are drawn (> 20×)
# the frozen test's G constants (P615G_G), restated
const TST = (beta = [0.7037, 0.9361, 0.9867, 1.006, 1.02], gamma = [0.12, 0.5, 0.75])
const ART = (beta = [0.698182, 0.937665, 0.987636, 1.005947, 1.020946], gamma = [0.07562, 0.450193, 0.715045])
const V2B = (beta = [0.8727, 0.9, 0.9334, 0.95, 1.0], t = [18.59, 20.40, 25.59, 32.11, 105.76],
    src = [:art, :tst, :art, :tst, :tst])

function tsv(path)
    l = split.(readlines(path), '\t')
    return [Dict(zip(l[1], r)) for r in l[2:end]]
end
num(s) = s == "Inf" ? Inf : s == "NaN" || s == "—" || isempty(s) ? NaN : parse(Float64, s)
runs = tsv(joinpath(DIR, "runs.tsv"))
points = tsv(joinpath(DIR, "points.tsv"))
t1 = tsv(joinpath(DIR, "table1.tsv"))

blue, orange, purple = RGBf(0x1f / 255, 0x5b / 255, 0xd1 / 255), RGBf(0xe0 / 255, 0x7b / 255, 0), RGBf(0x8e / 255, 0x44 / 255, 0xad / 255)
mm = 72 / 25.4
s = 2.2
fig = Figure(; size = (2 * 72mm * s, 62mm * s), fontsize = 8 * s, fonts = (; regular = "TeX Gyre Heros Makie"))
const AX = Axis[]
for (j, sw) in enumerate(("beta", "gamma"))
    sym = sw == "beta" ? "β" : "γ"
    ax = Axis(fig[1, j]; xlabel = sw == "beta" ? "β" : "γ", ylabel = "Time to 10⁴ cells (5T)", yscale = log10,
        title = sw == "beta" ? "(a) γ = 0" : "(b) β = 0", titlealign = :left, xgridcolor = (:black, 0.12),
        ygridcolor = (:black, 0.12), yticks = ([10, 30, 100, 300, 1000], ["10¹", "30", "10²", "300", "10³"]))
    for m in MULTS
        hlines!(ax, [tau(m)]; color = (:black, 0.55), linestyle = :dash, linewidth = 1)
        text!(ax, sw == "beta" ? 0.02 : 0.83, tau(m); text = "$(m == 1.1 ? "1.1" : string(Int(m)))×",
            align = (sw == "beta" ? :left : :right, :bottom), fontsize = 7 * s, color = (:black, 0.7),
            space = :data)
    end
    # every run
    rs = filter(r -> r["sweep"] == sw, runs)
    sw == "gamma" && append!(rs, filter(r -> r["sweep"] == "beta" && r["q"] == "0", runs))
    x = [parse(Int, r["q"]) / 10_000 for r in rs]
    y = [r["capped"] == "true" ? TOP : parse(Int, r["mcs"]) / 775 for r in rs]
    scatter!(ax, x, y; color = (blue, 0.35), markersize = 4 * s, strokewidth = 0)
    # point means
    ps = filter(p -> p["sweep"] == sw, points)
    sw == "gamma" && pushfirst!(ps, only(filter(p -> p["sweep"] == "beta" && p["q"] == "0", points)))
    px = [parse(Float64, p["value"]) for p in ps]
    pt = [num(p["t_mean_cycles"]) for p in ps]
    fin = isfinite.(pt)
    lines!(ax, px[fin], pt[fin]; color = blue, linewidth = 1.5 * s / 2, label = "Potts.jl (point means)")
    scatter!(ax, px[fin], pt[fin]; color = blue, markersize = 6 * s, strokecolor = :white, strokewidth = 0.8)
    any(.!fin) && scatter!(ax, px[.!fin], fill(TOP, count(.!fin)); marker = :utriangle, color = :white,
        strokecolor = blue, strokewidth = 1.2, markersize = 7 * s)
    any(.!fin) && text!(ax, minimum(px[.!fin]), TOP; text = "> 20× (capped)", align = (:right, :center),
        offset = (-6, 0), fontsize = 7 * s, color = (:black, 0.7))
    # T1 thresholds
    rows = filter(r -> r["parameter"] == sw && r["band"] != "—", t1)
    th = [num(r["threshold"]) for r in rows]
    ta = [parse(Float64, r["tau_cycles"]) for r in rows]
    ok = isfinite.(th)
    scatter!(ax, th[ok], ta[ok]; marker = :circle, color = :transparent, strokecolor = blue, strokewidth = 1.6,
        markersize = 11 * s, label = "Potts.jl T1 threshold")
    ms = sw == "beta" ? collect(MULTS) : [5.0, 10.0, 20.0]
    scatter!(ax, TST[Symbol(sw)], tau.(ms); marker = :diamond, color = orange, markersize = 7 * s, strokewidth = 0,
        label = "TST T1 threshold")
    scatter!(ax, ART[Symbol(sw)], tau.(ms); marker = :xcross, color = purple, markersize = 7 * s, strokewidth = 0,
        label = "Artistoo T1 threshold")
    if sw == "beta"
        k = V2B.src .=== :tst
        scatter!(ax, V2B.beta[k], V2B.t[k]; marker = :rect, color = orange, markersize = 5 * s, label = "TST, V2b reference")
        scatter!(ax, V2B.beta[.!k], V2B.t[.!k]; marker = :rect, color = purple, markersize = 5 * s,
            label = "Artistoo, V2b reference")
        xlims!(ax, -0.02, 1.05)
    else
        xlims!(ax, -0.02, 0.85)
    end
    ylims!(ax, 10, 1200)
    push!(AX, ax)
end
Legend(fig[1, 3], AX[1]; framevisible = false, labelsize = 7 * s, merge = true)
save(joinpath(DIR, "fig6.png"), fig; px_per_unit = 1)
println(filesize(joinpath(DIR, "fig6.png")))
