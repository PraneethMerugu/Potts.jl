# P6.15h / P6.15j (D-180 amendment): the bare Potts.jl panel of OpenVT Fig 1, the
# consortium's `results/<framework>/closeup.png`: fig1.png's 64 × 64 block, colours and
# scale, without the banner (the .tex adds it) and with no cell outlines (D-156). Rebuilt
# from this record's window.tsv (owners and generations; the identity colours depend only on
# them, D-172), so no rerun is needed. Writes fig1_panel.png; with the banner the same
# block gives fig1.png, which the script checks first.
#     julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/f1-f4-2026-10-08/plot_f1_bare.jl
using Potts, PottsModels, CairoMakie, MakiePotts

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

# the block reproduces the committed panel
check = joinpath(tempdir(), "fig1_check.png")
save(check, PottsModels.openvt_f1_figure(block; window = W); px_per_unit = 2)
read(check) == read(joinpath(DIR, "fig1.png")) || error("the window.tsv block does not reproduce fig1.png")
rm(check)

path = joinpath(DIR, "fig1_panel.png")
save(path, PottsModels.openvt_f1_figure(block; window = W, banner = false); px_per_unit = 2)
println(path)
