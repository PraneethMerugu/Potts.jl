# Figure 2 b for Potts.jl (checkerboard) (spec 15 §1.3, the slot after the sequential
# `fig2_bde.png`): the 11-chain relaxation at λ = 2 under CheckerboardCPM on the P1b chain
# (D-224), from this record's timeseries_11chain.tsv. Left: time in this entry's own T (the
# axes of the sequential panel b); right: the same curves in MCS, with the sequential λ = 2
# curve of the calibration record (`calibration-2026-10-05/timeseries_11chain.tsv`, grey) and
# both crossings of 9 CD. Dashed: the spring–dashpot reference of the calibration record.
# T and the cycle are read from meta.toml [time]. Writes fig2.png.
#     julia --project=docs lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/plot_fig2.jl
using CairoMakie, DelimitedFiles, TOML

const DIR = @__DIR__
const SEQ = joinpath(DIR, "..", "calibration-2026-10-05")
readtsv(f) = (d = readdlm(f, '\t'; header = true); (d[1], vec(d[2])))
col(d, name) = Float64.(d[1][:, findfirst(==(name), d[2])])

tm = TOML.parsefile(joinpath(DIR, "meta.toml"))["time"]
Tcb, Tseq = tm["T_lambda2"], tm["T_seq"]
cb = readtsv(joinpath(DIR, "timeseries_11chain.tsv"))
sq = readtsv(joinpath(SEQ, "timeseries_11chain.tsv"))
ref = readtsv(joinpath(SEQ, "reference.tsv"))
kcb = col(cb, "lambda") .== 2.0
ksq = col(sq, "lambda") .== 2.0
tcb, mcb, sdcb = col(cb, "t_mcs")[kcb], col(cb, "w11_mean")[kcb], col(cb, "w11_sd")[kcb]
tsq, msq, sdsq = col(sq, "t_mcs")[ksq], col(sq, "w11_mean")[ksq], col(sq, "w11_sd")[ksq]

red = "#ff725c"                       # the λ = 2 colour of the sequential panel b
grey = (:grey35, 0.9)
mm = 72 / 25.4
fig = Figure(; size = (2 * 52mm, 52mm) .* 2.2, fontsize = 9 * 2.2 / 1.6)

function guides!(ax; x = 1.0)
    hlines!(ax, [9.0]; color = (:grey, 0.5), linewidth = 0.8)
    vlines!(ax, x; color = (:grey, 0.5), linewidth = 0.8)
    hlines!(ax, [10.0]; color = :black, linestyle = :dot, linewidth = 1.6)
end

ax1 = Axis(fig[1, 1]; xlabel = "Time (T)", ylabel = "Tissue width w₁₁ (CD)",
    title = "b  11-chain, λ = 2, T = $Tcb MCS", titlealign = :left, limits = (0, 5, 5, 10.25))
guides!(ax1)
let s = tcb ./ Tcb, k = (tcb ./ Tcb .>= 0) .& (tcb ./ Tcb .<= 5)
    band!(ax1, s[k], mcb[k] .- sdcb[k], mcb[k] .+ sdcb[k]; color = (red, 0.18))
    lines!(ax1, s[k], mcb[k]; color = red, linewidth = 1.8, label = "Potts.jl (checkerboard)")
end
lines!(ax1, col(ref, "t_over_T"), col(ref, "w"); color = :black, linestyle = :dash, linewidth = 1.0,
    label = "spring–dashpot")
axislegend(ax1; position = :rb, framevisible = false, labelsize = 9, rowgap = 0, patchsize = (14, 8))

ax2 = Axis(fig[1, 2]; xlabel = "Time (MCS after the release)", ylabel = "Tissue width w₁₁ (CD)",
    title = "the same, in MCS", titlealign = :left, limits = (0, 1085, 5, 10.25))
guides!(ax2; x = [Tseq, Tcb])
let k = tsq .>= 0
    band!(ax2, tsq[k], msq[k] .- sdsq[k], msq[k] .+ sdsq[k]; color = (:grey, 0.15))
    lines!(ax2, tsq[k], msq[k]; color = grey, linewidth = 1.4, label = "Potts.jl (sequential), T = $Tseq")
end
let k = tcb .>= 0
    band!(ax2, tcb[k], mcb[k] .- sdcb[k], mcb[k] .+ sdcb[k]; color = (red, 0.18))
    lines!(ax2, tcb[k], mcb[k]; color = red, linewidth = 1.8, label = "Potts.jl (checkerboard), T = $Tcb")
end
axislegend(ax2; position = :rb, framevisible = false, labelsize = 9, rowgap = 0, patchsize = (14, 8))

save(joinpath(DIR, "fig2.png"), fig; px_per_unit = 1)
println(filesize(joinpath(DIR, "fig2.png")))
