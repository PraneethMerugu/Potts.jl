# Fig 2b/2d/2e layout (spec 15 §4.0.2 F2, M `relaxation.tex`) from this record's TSVs; Potts
# only (the consortium curves, G, are never copied into git).
#     julia --project=docs lib/PottsModels/reproductions/data/15/calibration-2026-10-05/plot_calibration.jl
using CairoMakie, DelimitedFiles

const DIR = @__DIR__
readtsv(f) = (d = readdlm(joinpath(DIR, f), '\t'; header = true); (d[1], vec(d[2])))
col(d, name) = Float64.(d[1][:, findfirst(==(name), d[2])])

ts11 = readtsv("timeseries_11chain.tsv")
ts21 = readtsv("timeseries_21chain.tsv")
ref = readtsv("reference.tsv")
λs = col(ts11, "lambda")
s11, m11, sd11 = col(ts11, "t_over_T"), col(ts11, "w11_mean"), col(ts11, "w11_sd")
s21 = col(ts21, "t_over_T")

colors = Dict(1.0 => "#4269d0", 2.0 => "#ff725c", 3.0 => "#3ca951", 5.0 => "#a463f2")
mm = 72 / 25.4
fig = Figure(; size = (3 * 52mm, 52mm) .* 2.2, fontsize = 9 * 2.2 / 1.6)

function guides!(ax; at = nothing)
    hlines!(ax, [9.0]; color = (:grey, 0.5), linewidth = 0.8)
    vlines!(ax, [1.0]; color = (:grey, 0.5), linewidth = 0.8)
    at === nothing || hlines!(ax, [at]; color = :black, linestyle = :dot, linewidth = 1.6)
end

ax_b = Axis(fig[1, 1]; xlabel = "Time (T)", ylabel = "Tissue width w₁₁ (CD)", title = "b  11-chain",
    titlealign = :left, limits = (0, 5, 5, 10.25))
guides!(ax_b; at = 10.0)
let k = (λs .== 2.0) .& (s11 .>= 0) .& (s11 .<= 5)
    band!(ax_b, s11[k], m11[k] .- sd11[k], m11[k] .+ sd11[k]; color = (colors[2.0], 0.18))
end
for λ in (1.0, 2.0, 3.0, 5.0)
    k = (λs .== λ) .& (s11 .>= 0) .& (s11 .<= 5)
    lines!(ax_b, s11[k], m11[k]; color = colors[λ], linewidth = λ == 2 ? 1.8 : 1.0,
        label = "Potts.jl λ = $(Int(λ))")
end
lines!(ax_b, col(ref, "t_over_T"), col(ref, "w"); color = :black, linestyle = :dash, linewidth = 1.0,
    label = "spring–dashpot")
axislegend(ax_b; position = :rb, framevisible = false, labelsize = 9, rowgap = 0, patchsize = (14, 8))
ins = Axis(fig[1, 1]; width = Relative(0.4), height = Relative(0.36), halign = 0.92, valign = 0.62,
    limits = (0.95, 1.05, 8.95, 9.05), xticks = [0.95, 1.0, 1.05], yticks = [8.95, 9.0, 9.05],
    xticklabelsize = 7, yticklabelsize = 7, backgroundcolor = :white)
guides!(ins)
for λ in (1.0, 2.0, 3.0, 5.0)
    k = (λs .== λ) .& (s11 .>= 0.9) .& (s11 .<= 1.1)
    lines!(ins, s11[k], m11[k]; color = colors[λ], linewidth = λ == 2 ? 1.8 : 1.0)
end
lines!(ins, col(ref, "t_over_T"), col(ref, "w"); color = :black, linestyle = :dash, linewidth = 1.0)

k21 = (s21 .>= 0) .& (s21 .<= 10)
for (j, (name, ylab, lim, at, title)) in enumerate((
        ("w21", "Total tissue width w₂₁ (CD)", (14, 20.3), 20.0, "d  21-chain, λ = 2 (T from b)"),
        ("inner_w11", "Width of inner cells w₁₁ (CD)", (5, 10.25), 10.0, "e  inner 11 cells")))
    ax = Axis(fig[1, j + 1]; xlabel = "Time (T)", ylabel = ylab, title, titlealign = :left,
        limits = (0, 10, lim...))
    hlines!(ax, [at]; color = :black, linestyle = :dot, linewidth = 1.6)
    m, sd = col(ts21, name * "_mean")[k21], col(ts21, name * "_sd")[k21]
    band!(ax, s21[k21], m .- sd, m .+ sd; color = (colors[2.0], 0.18))
    lines!(ax, s21[k21], m; color = colors[2.0], linewidth = 1.8, label = "Potts.jl (mean ± SD, 100 runs)")
    j == 1 && axislegend(ax; position = :rb, framevisible = false, labelsize = 9)
end
save(joinpath(DIR, "fig2_bde.png"), fig; px_per_unit = 1)
println(filesize(joinpath(DIR, "fig2_bde.png")))
