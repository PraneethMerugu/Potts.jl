# # [A growing monolayer (OpenVT benchmark)](@id model-openvt)
#
# A single cell on a dish grows, divides, and its daughters do the same, until a colony
# covers the dish. The OpenVT project (Open Virtual Tissues) uses this as a benchmark for
# comparing cell-based simulators: every framework implements the same growth and division
# rules, and the colony's cell count, area and radius are compared over time. This page
# builds the cellular Potts version, with the parameter set of the Artistoo
# implementation.
#
# **What you will learn**
#
# - how a per-cell target area grows through an `@after_mcs` rule, and how that rule
#   expresses contact inhibition;
# - how `@divide` triggers division on a size threshold, chooses the division plane and
#   resets the daughters' variables;
# - how to reserve room for new cells, and measure a population's doubling time.
#
# The [cell sorting](@ref model-graner-glazier) page explains the parts every model shares.
#
# ## The benchmark
#
# The OpenVT reference models specify the monolayer by rules rather than equations:
#
# - each cell has a target area ``V_T`` and an area constraint
#   ``\lambda (V - V_T)^2``; cell–cell and cell–medium contact energies are equal, so
#   there is no net adhesion;
# - ``V_T`` grows by ``A_0/\tau`` per MCS, so an unconstrained cell doubles its area in
#   ``\tau`` MCS;
# - a cell divides when its area reaches ``2A_0``, along a uniformly random plane, and both
#   daughters restart at ``V_T = A_0``;
# - contact inhibition (type 1): a cell grows only while its area is at least
#   ``\beta V_T``. A compressed cell, squeezed below its target by its neighbours, stops
#   growing.

# ## The paper run
#
# The finished model, built step by step below, run at the paper's size, with the paper's
# starting state, parameters and run length. It is computed outside the docs build:
#
# <<paper_run>>
#
# The rest of this page builds the model and runs it at a size that takes seconds.

using Potts, PottsModels

# ## Step 1: the lattice
#
# <<fragment lattice>>
#
# A closed 400 × 400 lattice (the Artistoo reference file uses 1100 × 1100) with Moore
# contacts and copies.
#
# ## Step 2: cell kinds
#
# <<fragment kinds>>
#
# ## Step 3: parameters
#
# <<fragment parameters>>
#
# The Artistoo parameter set: ``A_0 = 25``, ``\lambda = 20``, a doubling time
# ``\tau = 84`` MCS and ``T = 20``. Both contact energies are 20. `β = 0` switches contact
# inhibition off (the benchmark's baseline); its inhibited runs use ``\beta \approx 0.9``.
#
# ## Step 4: the target area
#
# <<fragment variables>>
#
# `V_target(cell)` is one value per cell. Its default refers to a parameter: a new cell
# starts at `A₀`.
#
# ## Step 5: the energy
#
# <<fragment area>>
#
# The area constraint pulls each cell towards its own, growing, target.
#
# <<fragment contacts>>
#
# ## Step 6: growth with contact inhibition
#
# <<fragment growth>>
#
# After every MCS each cell whose area is at least ``\beta V_T`` adds ``A_0/\tau`` to its
# target; the others keep it. `Pre(V_target)` is the value before the update, and `volume`
# the cell's current area. With `β = 0` the condition always holds.
#
# ## Step 7: division
#
# <<fragment division>>
#
# `@divide` names the cells that may divide (`cells(cell)`), the condition (`when`), the
# division plane (`along = RandomPlane()`, a uniformly random orientation through the
# cell's centre) and what the daughters' variables become: both start again at
# ``V_T = A_0``.
#
# ## Step 8: the sweep
#
# <<fragment sweep>>
#
# ## The whole model

# <<model>>

# We run it on the constructor's 400 × 400 lattice with the Artistoo parameters:

dims = (400, 400)
@named mono = GrowingMonolayer()

# ## The starting state
#
# One square cell of area ``A_0`` at the centre. A `Tiling` layer restricted to a 5 × 5
# region makes exactly one 5 × 5 box. It is the state that `openvt_monolayer_state`
# builds:

u0 = layout(Tiling((5, 5); region = (198:202, 198:202), kinds = [:cell]), dims)
u0[1].second == openvt_monolayer_state()[1].second

# ## Solving
#
# 840 MCS are ten doubling times ``\tau``. New cells need room in the state: `capacity`
# is the largest number of cells the run can hold.

prob = PottsProblem(mono, u0, (0, 840); seed = 1, capacity = 4096)
sol = solve(prob, SequentialCPM(); saveat = 0:8:840)

# ## The run as a movie
#
# All cells are of one kind, so the movie colours them by identity
# (`CellIdentityEncoding`), and zooms in on the central 180 × 180 sites, where the colony
# grows, through the `axis` limits:

using MakiePotts, CairoMakie
mkpath("openvt") #hide
record_potts("openvt/monolayer.mp4", sol; framerate = 15, title = "Growing monolayer",
    encoding = CellIdentityEncoding(), figure = (; size = (440, 440)), axis = (; limits = (110, 290, 110, 290)))
nothing #hide

# ```@raw html
# <video src="monolayer.mp4" controls autoplay loop muted playsinline width="440"></video>
# ```
#
# ## Measuring growth
#
# The benchmark's first observable is the number of cells. `sol[:volume]` gives every
# cell's area at every saved time (zero for slots not yet used), so the live cells are
# those with a positive area. If every cell grew freely, the count would double every
# ``\tau`` MCS; the dashed line is ``2^{t/\tau}``:

ncells = [count(>(0), v) for v in sol[:volume]]
CairoMakie.activate!(type = "png")
fig = Figure(size = (520, 340))
ax = Axis(fig[1, 1]; xlabel = "MCS", ylabel = "cells", yscale = log2)
lines!(ax, sol.t, ncells; label = "simulation")
lines!(ax, sol.t, 2 .^ (sol.t ./ 84); linestyle = :dash, label = "2^(t/τ)")
axislegend(ax; position = :lt)
fig

# The doubling time fitted over the second half of the run:

half = sol.t .>= 420
tm = sum(sol.t[half]) / count(half)
slope = sum((sol.t[half] .- tm) .* log2.(ncells[half])) / sum(abs2, sol.t[half] .- tm)
1 / slope

# It is somewhat longer than ``\tau = 84``: a cell's area lags its growing target, and
# a cell divides only when its area itself reaches ``2A_0``.
#
# ## The benchmark's colony metrics
#
# The benchmark measures each saved colony with the consortium's `metrics.cpp`: the tissue
# boundary is a concave hull of the cell centroids, and from it come the mean radius `r`,
# the area `A`, the perimeter `C`, the boundary roughness `w`, and the ratios
# `C_rel = C/(2√(πA))` and `w_rel = w/r`. `openvt_metrics` ports that program, built on the
# general primitive `PottsModels.Analysis.concave_hull`. Its output line is identical to
# `metrics.cpp` built with `-ffp-contract=off` on the consortium's 25 parameter-plane
# colonies and on fuzzed tie-free clouds. It departs from the reference on purpose in two
# places where the reference's boundary depends on luck: the Graham order of points
# collinear with the pivot, and an R-tree search that can miss candidates next to
# near-parallel edges (spec defects D12 and D13). In both, the port's boundary is the
# correct hull. The benchmark's unit of length is the cell radius ``R = \sqrt{A_0/\pi}``,
# with the origin at the lattice centre. Ids of cells that have vanished have `NaN`
# centroids, so they are dropped first:

using PottsModels.Analysis: centroids, concave_hull
R = sqrt(25 / π)
cs = filter(c -> !isnan(c[1]), centroids(sol.u[end].σ))
x = [(c[1] - 200) / R for c in cs]
y = [(c[2] - 200) / R for c in cs]
m = openvt_metrics(x, y, ones(Int, length(cs)))   # β = 0: every cell grows

# `openvt_metrics_line(m)` is what `metrics.cpp` prints, and `write_openvt` writes the
# benchmark's files: here the O6 metrics series, one row per save:

print(openvt_metrics_line(m))
io = IOBuffer()
write_openvt(io, :O6, (t = [840 / 84], metrics = [m]))   # t in cycles of τ = 84 MCS
print(String(take!(io)))

# The boundary itself, over the centroids:

b = concave_hull(zip(x, y); concavity = 1.5)
fig = Figure(size = (420, 420))
ax = Axis(fig[1, 1]; aspect = DataAspect(), xlabel = "x / R", ylabel = "y / R")
scatter!(ax, x, y; markersize = 4, color = :gray)
lines!(ax, [first.(b); b[1][1]], [last.(b); b[1][2]]; color = :crimson)
fig

# For an inhibited run, `openvt_inhibition_code` classifies each cell and
# `openvt_inhibition_fractions` gives the shares of the four codes; `read_openvt` reads any
# of the files back and `openvt_filename` names them as the benchmark expects.

# ## Differences from the benchmark
#
# | | Artistoo reference file | Here |
# |:--|:--|:--|
# | Lattice | 1100 × 1100 | 400 × 400 (constructor default); enough while the colony stays clear of the walls, not for the benchmark's 10⁴ cells |
# | Division size | random, ``N(2, 0.4) \cdot A_0`` | exactly ``2A_0``, as in the benchmark's written baseline specification |
#
# The energies, growth law, division plane and parameters are the Artistoo set. This page
# runs the uninhibited baseline (`β = 0`) for ten doubling times; the benchmark also runs
# contact-inhibited colonies (`β ≈ 0.9`).
#
# ## This model ships as `OpenVTGrowingMonolayer`
#
# PottsModels exports this model as `OpenVTGrowingMonolayer`; the test suite checks that
# it compiles to the same code and defaults as `GrowingMonolayer` above.

@named openvt = OpenVTGrowingMonolayer()

# Its start is `openvt_monolayer_state()`. Contact inhibition is a parameter, so the
# benchmark's inhibited runs start from `[openvt_monolayer_state(); :β => 0.9]`.

# ```@docs
# OpenVTGrowingMonolayer
# openvt_monolayer_state
# openvt_metrics
# openvt_metrics_line
# openvt_neighbor_histogram
# openvt_inhibition_code
# openvt_inhibition_fractions
# write_openvt
# read_openvt
# openvt_filename
# ```

# ## The manuscript's reference set (Table S1)
#
# The benchmark manuscript fixes the parameters every framework uses (its Table S1), and
# some rules differ from the 2024 Artistoo file above. PottsModels ships that model as
# `OpenVTReferenceMonolayer`; `OpenVTGrowingMonolayer` stays the documented 2024 variant.
#
# | | `OpenVTGrowingMonolayer` (2024 Artistoo set) | `OpenVTReferenceMonolayer` (Table S1) |
# |:--|:--|:--|
# | Contact energies ``J_{cc}`` / ``J_{cm}`` | 20 / 20 | 20 / 10 |
# | ``\lambda``, ``A^*(0)`` | 20, 25 | 2, 50 |
# | Growth | ``A_0/\tau`` per MCS | ``\alpha = 50/775`` per MCS: a cycle of 775 MCS |
# | Division size | exactly ``2A_0`` | ``X_i A^*(0)``, ``X_i \sim N(2, 0.4)`` redrawn while ``\le 0``, drawn by each daughter at birth |
# | Daughters' target | reset to ``A_0`` | half the mother's ``A^*`` |
# | Contact inhibition | type 1 (``V \ge \beta V_T``) | type 1 (``A_i/A^*_i \ge \beta``) and type 2 (free-surface fraction ``f_i \ge \gamma``) |
# | Initial cell | a 5 × 5 square | a disc of radius ``R = \sqrt{A^*(0)/\pi}`` (52 sites) |
# | Lattice | 400 × 400 | 1400 × 1400, closed, with an edge guard |
#
# Two rules use DSL forms of their own. The free-surface fraction is a contact count, kept
# exact by every copy (see [Updates](@ref manual-updates)):
#
# ```julia
# f ~ count(kind′ == medium for _ in contacts) / count(true for _ in contacts)
# ```
#
# and the division threshold is a truncated normal draw, made separately by each daughter
# (see [Lifecycle](@ref manual-lifecycle)):
#
# ```julia
# @divide cells(cell) when = volume >= X * A₀, along = RandomPlane(), A_star => Split(),
#     X => randn(μ_X, σ_X; lower = 0.0)
# ```
#
# Three cell cycles on a 120 × 120 lattice, with the run stopped if a cell comes within
# 5 sites of the edge (`PottsModels.edge_guard`) and at 64 cells
# (`PottsModels.stop_at_cells`):

@named ref = OpenVTReferenceMonolayer(; lattice = (120, 120))
prob_ref = PottsProblem(ref, openvt_reference_state(; lattice = (120, 120)), (0, 3 * 775); seed = 1, capacity = 256)
guards = CallbackSet(PottsModels.edge_guard(5; terminate = true), PottsModels.stop_at_cells(64))
sol_ref = solve(prob_ref, SequentialCPM(); saveat = 0:15:(3 * 775), callback = guards)
(retcode = sol_ref.retcode, cells = count(>(0), sol_ref.u[end].cell.volume))

# The colony, coloured by cell:

record_potts("openvt/reference.mp4", sol_ref; framerate = 15, title = "Table S1 monolayer",
    encoding = CellIdentityEncoding(), figure = (; size = (440, 440)), axis = (; limits = (20, 100, 20, 100)))
nothing #hide

# ```@raw html
# <video src="reference.mp4" controls autoplay loop muted playsinline width="440"></video>
# ```
#
# The O2 rows of the benchmark (centroid, radius, free-surface fraction and area fraction,
# lengths in units of ``R``) for the last state:

snap = PottsModels.openvt_snapshot(sol_ref.u[end])
(n = length(snap.x), mean_f = sum(snap.f) / length(snap.f), mean_a = sum(snap.a) / length(snap.a))

# ```@docs
# OpenVTReferenceMonolayer
# openvt_reference_state
# ```
