# # [A sheared two-dimensional foam](@id model-foam)
#
# A dry foam is a packing of gas bubbles separated by thin walls. Jiang, Swart, Saxena,
# Asipauskas and Glazier (1999) modelled it as a cellular Potts model: one cell per bubble,
# a wall energy, an area constraint, and a shear term that favours copies along x. Shear is
# applied either at the boundary rows only or across the whole foam (bulk shear). Under
# slow shear the foam first stores energy in its walls like an elastic solid. Then bubbles
# swap neighbours (T1 events), often several at once, and the stored energy drops; the
# foam flows. PottsModels ships the model as `ShearedFoam`, and this page runs it.
#
# The comparison with the paper's figures is the foam reproduction page (reproduction 04),
# which takes this page's place in the published documentation; it is listed on
# [Paper models: status](@ref paper-status). That reproduction is provisional while a
# question to the paper's authors is open.
#
# - Y. Jiang, P. J. Swart, A. Saxena, M. Asipauskas and J. A. Glazier, "Hysteresis and
#   avalanches in two-dimensional foam rheology simulations", *Phys. Rev. E* **59**, 5819
#   (1999), doi:[10.1103/PhysRevE.59.5819](https://doi.org/10.1103/PhysRevE.59.5819).
#
# ## Running it
#
# An ordered foam of 48 bubbles of 16² sites on a 128 × 96 lattice, periodic in x with
# closed walls in y. It starts as a brick wall (`sheared_foam_state`), is shaken for 10 MCS
# at T = 3 and relaxed for 300 MCS at T → 0⁺, and is then sheared at the boundary: the top
# row is pushed +x and the bottom row −x for 4000 MCS. Copies are proposed at wall sites
# only (`skip_interior = true`), as in the paper.

using Potts, PottsModels
using MakiePotts, CairoMakie
mkpath("foam") #hide

L = (128, 96)
@named foam = ShearedFoam(; lattice = L, ytop = Float64(L[2]), ymid = (L[2] + 1) / 2)
alg = SequentialCPM(; skip_interior = true)
start = sheared_foam_state(; lattice = L)
prob = PottsProblem(foam, start, (0, 10); seed = 1)
shaken = solve(remake(prob; p = [:T => 3.0]), alg).u[end]
relaxed = solve(remake(prob; u0 = [ownership => Array(shaken.σ); start[2:3]], tspan = (0, 300)), alg).u[end]
sheared = solve(remake(prob; u0 = [ownership => Array(relaxed.σ); start[2:3]], p = [:γ0 => 36.0], tspan = (0, 4000)),
    alg; saveat = 0:20:4000)
nothing #hide

# The run, one colour per bubble:

record_potts("foam/boundary_shear.mp4", sheared; framerate = 20, title = "boundary shear",
    encoding = CellIdentityEncoding(), plot = (; boundaries = false), figure = (; size = (520, 420)))
nothing #hide

# ```@raw html
# <video src="boundary_shear.mp4" controls autoplay loop muted playsinline width="520"></video>
# ```
#
# The stored energy (the number of unlike neighbour pairs, relative to the start) rises while
# the foam deforms and drops when bubbles swap neighbours; the second panel counts the T1
# events.

using PottsModels.Analysis: stored_energy, cell_graph, t1_events
CairoMakie.activate!(type = "png")
lat = Lattice(L; boundary = (Periodic(), Closed()))
φ = [stored_energy(Array(u.σ), lat) for u in sheared.u]
graphs = [cell_graph(Array(u.σ), lat) for u in sheared.u]
t1 = cumsum([0.0; [t1_events(graphs[i], graphs[i + 1]; unit = :t1) for i in 1:(length(graphs) - 1)]])
fig = Figure(size = (720, 260))
lines(fig[1, 1], sheared.t, φ ./ φ[1]; axis = (; xlabel = "MCS", ylabel = "stored energy / start"))
lines(fig[1, 2], sheared.t, t1; axis = (; xlabel = "MCS", ylabel = "T1 events (cumulative)"))
fig

# ```@raw html
# <details><summary>The model, bulk shear and the reference (click to open)</summary>
# ```
#
# ### The model
#
# `ShearedFoam` in `PottsModels`, without its docstring:
#
# ```julia
# @potts_model ShearedFoam begin
#     @structural_parameters begin
#         lattice = (256, 256)
#     end
#     @kinds medium bubble                     # a dry foam: no site is medium
#     @parameters begin
#         J = 3.0                              # wall energy per unlike neighbour pair
#         Γ = 1.0                              # area constraint
#         T = 1.0e-6                           # T → 0⁺
#         γ0 = 0.0                             # boundary shear
#         β = 0.0                              # bulk shear
#         bulk = 0.0                           # 1: bulk shear, else boundary shear
#         periodic = 0.0                       # 1: sin(ω mcs), else steady
#         ω = 2π / 4000
#         ytop = 256.0                         # the top row
#         ymid = 128.5                         # the mid-plane
#     end
#     @variables begin
#         A(cell) = 256.0                      # target area, 16²
#     end
#     @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
#     @relations proposal = NeighborOrder(4)
#     @energy begin
#         contacts => J
#         cells(bubble) => Γ * (volume - A)^2
#     end
#     @drive copy => ifelse(periodic > 0.5, sin(ω * mcs), 1.0) *
#                    ifelse(bulk > 0.5, -β * (position[target][2] - ymid),
#         γ0 * (ifelse(position[target][2] < 1.5, 1.0, 0.0) - ifelse(position[target][2] > ytop - 0.5, 1.0, 0.0))) *
#                    direction[1]
#     @sweep Metropolis(; temperature = T)
# end
# ```
#
# The energy is a wall energy `J` over the 20 neighbours up to the fourth shell and an area
# constraint per bubble. The drive adds, for a copy from a source site into a target site,
# a bias proportional to the x displacement `direction[1]`: on the two boundary rows only
# (`γ0`), or growing linearly with the distance from the mid-plane (`β`, `bulk = 1`),
# steady or oscillating (`periodic = 1`).
#
# ### Bulk shear
#
# The same foam with the whole height sheared (`bulk = 1`), for 1500 MCS:

bulk = solve(remake(prob; u0 = [ownership => Array(relaxed.σ); start[2:3]], p = [:β => 0.2, :bulk => 1.0],
        tspan = (0, 1500)), alg; saveat = 0:20:1500)
record_potts("foam/bulk_shear.mp4", bulk; framerate = 20, title = "bulk shear",
    encoding = CellIdentityEncoding(), plot = (; boundaries = false), figure = (; size = (520, 420)))
nothing #hide

# ```@raw html
# <video src="bulk_shear.mp4" controls loop muted playsinline width="520"></video>
# ```
#
# ### Reference
#
# ```@docs
# ShearedFoam
# sheared_foam_state
# ```
#
# ```@raw html
# </details>
# ```
