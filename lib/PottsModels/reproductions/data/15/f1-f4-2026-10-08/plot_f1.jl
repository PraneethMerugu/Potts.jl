# The Potts.jl panel of OpenVT Fig 1 in the consortium style (D-185): cells coloured by area
# with `coolwarm`, scaled to the panel's own cell-area min–max, thin black pixel-edge
# boundaries between unlike ids, a white medium. Rebuilt from this record's `window.tsv` (the
# 64 × 64 block: owners and generations) and `window_cells.tsv` (each block cell's area in the
# full state, written by `run_f1_areas.jl`), so cells cut by the window keep their full area
# and no rerun is needed. Writes:
#
# - fig1.png: the panel with the Potts.jl banner (`openvt_f1_figure(block; areas)`);
# - fig1_panel.png: the bare panel (`banner = false`), the consortium's `closeup.png` (P6.15j,
#   D-180 amendment);
# - fig1_colony.png, only when F1_STATE names the full state serialized by `run_f1_areas.jl`
#   (outside git): the whole 10⁴-cell colony in the same style, the panel's block shaded.
#
#     [F1_STATE=<path>] julia --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/f1-f4-2026-10-08/plot_f1.jl
using Potts, PottsModels, CairoMakie, MakiePotts, Serialization

const DIR = @__DIR__

rows = [split(l, '\t') for l in readlines(joinpath(DIR, "window.tsv"))[2:end]]
xs = [parse(Int, r[1]) for r in rows]
ys = [parse(Int, r[2]) for r in rows]
x0, y0 = minimum(xs) - 1, minimum(ys) - 1
W = maximum(xs) - x0
(W == maximum(ys) - y0 && length(rows) == W^2) || error("window.tsv is not a full square block")
owners = Matrix{RenderOwner}(undef, W, W)
gens = Dict{Int, Int}()
for r in rows
    x, y, o, g = parse.(Int, r)
    owners[x - x0, y - y0] = o == 0 ? RenderOwner(MediumSite, 1) : RenderOwner(CellSite, o)
    o == 0 || (gens[o] = g)
end
cells = [RenderCellMetadata(RenderCellIdentity(id, gens[id]), 1) for id in sort!(collect(keys(gens)))]
block = PottsRenderFrame(0, owners, cells; geometry = RenderGeometry((W, W); origin = (x0, y0)))

# the full-state areas of the block's cells
crows = [split(l, '\t') for l in readlines(joinpath(DIR, "window_cells.tsv"))]
col = Dict(String(h) => i for (i, h) in enumerate(crows[1]))
areas = Dict(parse(Int, r[col["id"]]) => parse(Int, r[col["area"]]) for r in crows[2:end])
Set(keys(areas)) == Set(keys(gens)) || error("window_cells.tsv does not list exactly the block's cells")
all(r -> parse(Int, r[col["generation"]]) == gens[parse(Int, r[col["id"]])], crows[2:end]) ||
    error("window_cells.tsv's generations differ from window.tsv's")

save(joinpath(DIR, "fig1.png"), PottsModels.openvt_f1_figure(block; window = W, areas); px_per_unit = 2)
save(joinpath(DIR, "fig1_panel.png"), PottsModels.openvt_f1_figure(block; window = W, banner = false, areas); px_per_unit = 2)
println(joinpath(DIR, "fig1.png"), "\n", joinpath(DIR, "fig1_panel.png"))

state = get(ENV, "F1_STATE", "")
if !isempty(state)
    s = deserialize(state)
    σ = s.σ
    all(((x, y),) -> σ[x, y] == (owners[x - x0, y - y0].kind === CellSite ? owners[x - x0, y - y0].id : 0),
        zip(xs, ys)) || error("F1_STATE's ownership differs from window.tsv")
    live = findall(>(0), s.volume)
    fo = [x == 0 ? RenderOwner(MediumSite, 1) : RenderOwner(CellSite, x) for x in σ]
    fc = [RenderCellMetadata(RenderCellIdentity(c, s.generation[c]), 1) for c in live]
    frame = PottsRenderFrame(s.mcs, fo, fc)
    occ = findall(!=(0), σ)
    lo = minimum(occ); hi = maximum(occ)
    pad = 20
    lim = (max(1, min(lo[1], lo[2]) - pad) - 1, min(size(σ, 1), max(hi[1], hi[2]) + pad))
    cfig = Figure(; size = (1200, 1200), backgroundcolor = :white)
    cax = Axis(cfig[1, 1]; aspect = DataAspect(), title = "case (a) run 1, seed 15701: MCS $(s.mcs), N = $(length(live)); F1 window $(W)²")
    hidedecorations!(cax); hidespines!(cax)
    PottsModels.openvt_colony_panel!(cax, frame; colour = :area, linewidth = 0.3)
    poly!(cax, Rect2f(x0, y0, W, W); color = (:black, 0.25), strokewidth = 0)
    limits!(cax, lim..., lim...)
    save(joinpath(DIR, "fig1_colony.png"), cfig; px_per_unit = 1.5)
    println(joinpath(DIR, "fig1_colony.png"))
end
