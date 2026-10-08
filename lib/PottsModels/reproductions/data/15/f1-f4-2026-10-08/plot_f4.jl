# P6.15h: OpenVT Fig 4 (lattice panel; G:results/free_surface.tex:31-110) from the 7 × 7
# configuration transcribed into the frozen test `15_openvt_f1_f4.jl` (D-175). The test's
# `p615h_fig4` is evaluated from its source, so this script cannot drift from it. Writes
# fig4.png (cell i, the drawn figure) and fig4_cells.png (cells i, i−1, i+1, i+2: each
# cell's own pairs and fᵢ, the G1 count of `openvt_snapshot`), and prints the counts.
#
#     julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/f1-f4-2026-10-08/plot_f4.jl
using Potts, PottsModels, CairoMakie, MakiePotts

const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f1_f4.jl")
for ex in Meta.parseall(read(TEST, String)).args
    ex isa Expr && ex.head === :function && ex.args[1] isa Expr && ex.args[1].args[1] === :p615h_fig4 || continue
    Core.eval(@__MODULE__, ex)
end

σ = p615h_fig4()
n = Int(maximum(σ))
u = (; σ, cell = (; volume = Float64[count(==(c), σ) for c in 1:n], A_star = fill(50.0, n)))
f = PottsModels.openvt_snapshot(u).f
println("f = ", f, "  (cell i: 13/38 = ", 13 / 38, ")")
f[1] == 13 / 38 || error("fᵢ ≠ 13/38")

save(joinpath(DIR, "fig4.png"), PottsModels.openvt_f4_figure(σ, 1); px_per_unit = 2)

# the four cells side by side (labels i, i−1, i+1, i+2 as in the .tex)
names = ["cell i", "cell i−1", "cell i+1", "cell i+2"]
fig = Figure(; size = (4 * 420, 500), backgroundcolor = :white)
for c in 1:n
    img = Makie.colorbuffer(PottsModels.openvt_f4_figure(σ, c); px_per_unit = 1)
    ax = Axis(fig[1, c]; aspect = DataAspect(), title = names[c], titlesize = 20)
    hidedecorations!(ax); hidespines!(ax)
    image!(ax, rotr90(img))
end
save(joinpath(DIR, "fig4_cells.png"), fig; px_per_unit = 1)
println("wrote fig4.png and fig4_cells.png to ", DIR)
