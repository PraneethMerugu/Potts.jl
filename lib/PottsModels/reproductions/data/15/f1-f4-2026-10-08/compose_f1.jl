# P6.15h (optional, information only): M Fig 1 ("Overview of participating frameworks";
# G:results/introduction.tex:50-92) with the Potts.jl panel added. The ten consortium
# closeups are read from a local clone of the consortium repository G (54f375f) at
# OPENVT_MONOLAYER_REPO; the composite is written to OPENVT_F1_OUT (default ./f1-composite)
# and is NOT committed: it contains G images (D-146, D-175).
#
# Layout as in the .tex: 45 mm square panels 4 mm apart, a 5 mm banner 1 mm above each in
# the framework colour (`G:results/colors.tex`), the name in bold white (black for
# TinyDEM), each image drawn into the square as `\includegraphics[width=\w, height=\w]`
# does. The Potts.jl panel (banner RGB(8,29,88), Q18 proposal) joins the lattice frameworks
# after Artistoo; its block is rebuilt from window.tsv (owners and generations; the
# identity colours depend only on them, D-172), so no rerun is needed.
#
#     OPENVT_MONOLAYER_REPO=~/openvt/monolayergrowth julia --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/f1-f4-2026-10-08/compose_f1.jl
using Potts, PottsModels, CairoMakie, MakiePotts

const DIR = @__DIR__
const G = get(ENV, "OPENVT_MONOLAYER_REPO", "")
isempty(G) && error("set OPENVT_MONOLAYER_REPO to a local clone of the consortium repository")
const OUT = get(ENV, "OPENVT_F1_OUT", joinpath(pwd(), "f1-composite"))
mkpath(OUT)

rgb(r, g, b) = RGBf(r / 255, g / 255, b / 255)
# (name, image under G:results, banner colour, label colour); the .tex's order, Potts.jl after Artistoo
const PANELS = [
    ("CompuCell3D", "CompuCell3D/closeup.png", rgb(37, 52, 148), :white),
    ("Morpheus", "Morpheus/Fig1_Morpheus.png", rgb(44, 127, 184), :white),
    ("TST", "TST/closeup.png", rgb(65, 182, 196), :white),
    ("Artistoo", "Artistoo/closeup.png", rgb(161, 218, 180), :white),
    ("Potts.jl", nothing, rgb(8, 29, 88), :white),
    ("Chaste (VM)", "Chaste_Vertex/Chaste_VM.png", rgb(0, 0, 0), :white),
    ("Chaste (VT)", "Chaste_VT_Linear/Chaste_VT.png", rgb(96, 96, 96), :white),
    ("PolyHoop", "polyhoop/closeup.png", rgb(192, 192, 192), :white),
    ("PhysiCell", "PhysiCell/closeup_improved.png", rgb(189, 0, 38), :white),
    ("Chaste (OS)", "Chaste_OS_Quad/Chaste_OS.png", rgb(240, 59, 32), :white),
    ("TinyDEM", "tinydem/closeup.png", rgb(254, 204, 92), :black),
]

# the Potts.jl block from window.tsv
rows = [split(l, '\t') for l in readlines(joinpath(DIR, "window.tsv"))[2:end]]
xs = [parse(Int, r[1]) for r in rows]; ys = [parse(Int, r[2]) for r in rows]
x0, y0 = minimum(xs) - 1, minimum(ys) - 1
W = maximum(xs) - x0
owners = Matrix{RenderOwner}(undef, W, W)
gens = Dict{Int, Int}()
for r in rows
    x, y, o, g = parse.(Int, r)
    owners[x - x0, y - y0] = o == 0 ? RenderOwner(MediumSite, 1) : RenderOwner(CellSite, o)
    o == 0 || (gens[o] = g)
end
cells = [RenderCellMetadata(RenderCellIdentity(id, gens[id]), 1) for id in sort!(collect(keys(gens)))]
block = PottsRenderFrame(0, owners, cells; geometry = RenderGeometry((W, W); origin = (x0, y0)))

mm = 10                                    # px per mm
w, xs_mm, bh, ysb = 45, 4, 5, 1
ncol = 6
fig = Figure(; size = (ncol * (w + xs_mm) * mm + 40, 2 * (w + bh + ysb + xs_mm) * mm + 40), backgroundcolor = :white)
for (k, (name, path, colour, labelcolour)) in enumerate(PANELS)
    row, col = fldmod1(k, ncol)
    gl = fig[row, col] = GridLayout()
    Box(gl[1, 1]; width = w * mm, height = bh * mm, color = colour, strokevisible = false)
    Label(gl[1, 1], name; color = labelcolour, font = :bold, fontsize = 26, tellwidth = false, tellheight = false)
    ax = Axis(gl[2, 1]; width = w * mm, height = w * mm, spinewidth = 0.5)
    hidedecorations!(ax)
    if path === nothing
        pottsplot!(ax, block; encoding = CellIdentityEncoding(), medium_color = :white, boundaries = false)
        limits!(ax, x0, x0 + W, y0, y0 + W)
    else
        img = load(joinpath(G, "results", path))
        image!(ax, rotr90(img))
        limits!(ax, 0, size(img, 2), 0, size(img, 1))
    end
    rowgap!(gl, 1, ysb * mm)
end
colgap!(fig.layout, xs_mm * mm)
rowgap!(fig.layout, xs_mm * mm)
path = joinpath(OUT, "fig1_composite.png")
save(path, fig; px_per_unit = 1)
println(path)
