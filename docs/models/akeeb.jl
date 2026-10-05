# # [Leader–follower tumour invasion](@id model-akeeb)
#
# Tumours invade the surrounding tissue in several ways: as single cells, as fingers or
# as detached clusters. In many carcinomas a minority of *leader* cells, which sense and
# follow cues in the matrix, pulls a majority of *follower* cells behind it. Akeeb, Marcus
# and Jiang (2026) model a slab of followers seeded with leaders, and map how adhesion
# between the two kinds, leader motility and proliferation decide the invasion pattern.
# This page builds that model.
#
# **What you will learn**
#
# - how to declare per-cell and per-site variables, and set them in the starting state;
# - how a drive acts only on copies that involve one kind of cell;
# - how two constraints keep cells connected and alive;
# - how `@after_mcs` updates grow cells and run their clocks, and how `@divide` splits a
#   cell, with a random division time;
# - how a layout builds a slab of cells seeded with single-site leaders.
#
# The [cell sorting](@ref model-graner-glazier) and [vasculogenesis](@ref model-merks)
# pages explain the parts used here before (contacts, area constraints, drives).
#
# ## The paper
#
# - S. Akeeb, A. I. Marcus and Y. Jiang, "Clusters, fingers, and singles: A mechanical
#   landscape of tumor invasion", *PLoS Comput. Biol.* **22**, e1014747 (2026),
#   doi:[10.1371/journal.pcbi.1014747](https://doi.org/10.1371/journal.pcbi.1014747).
#
# The paper's energy, Eq. (1), is
#
# ```math
# H = \sum_{\langle i,j \rangle} J\big(\tau(\sigma_i), \tau(\sigma_j)\big)\,(1 - \delta_{\sigma_i \sigma_j})
#   + \sum_\sigma \lambda_V (V_\sigma - V_{T,\sigma})^2
#   - \sum_x \lambda\, c(x)\, \delta_{\sigma(x), \text{LC}} ,
# ```
#
# with a per-cell target volume ``V_{T,\sigma}`` and a cue ``c(x)`` that leader cells
# (LC) climb. Copies are accepted with the Metropolis rule, Eq. (2). The authors ran the
# model in CompuCell3D and published the code; where code and text differ, the model
# follows the code, and the steps below say so.

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
# 500 × 300 sites, periodic along ``x`` and closed along ``y`` (paper p. 4). Contacts
# use the 8 neighbours and copies the 4 nearest, as in the authors' CompuCell3D files.
#
# ## Step 2: cell kinds
#
# <<fragment kinds>>
#
# ## Step 3: parameters
#
# <<fragment parameters>>
#
# The values of the paper's Table 1: ``\lambda_V = 2``, ``T = 10`` and the contact
# energies medium–leader 2, medium–follower 10, leader–leader 16 and follower–follower 5.
# The leader–follower energy ``J_{LF}`` (here 2) is the paper's main scanned parameter,
# over ``[-5, 5]``; `akeeb_contacts(J_LF)` builds the table for any value. `μ` is the
# chemotaxis strength (the paper's ``\lambda``); its default is the paper's reference value
# 24. `V_max`, `clock_min` and `clock_spread` govern growth and division (Steps 8 and 9).
#
# ## Step 4: per-cell and per-site variables
#
# <<fragment variables>>
#
# Each cell carries its own target volume, a mitotic clock and a growth rate, and each
# site a value of the cue. The values after `=` are defaults; the starting state overrides
# them per cell (below). A clock of ``-1`` marks a cell that does not proliferate.
#
# ## Step 5: the energy
#
# <<fragment volume>>
#
# The domain `cells` (with no kinds listed) covers every cell, leaders and followers. The
# target is the cell's own variable `V_target`, not a parameter: the first two terms of
# Eq. (1).
#
# <<fragment contacts>>
#
# ## Step 6: the cue drive
#
# <<fragment drive>>
#
# Eq. (1)'s third term is a potential summed over leader sites. The authors' code applies
# it as CompuCell3D's default chemotaxis instead: each copy whose gaining (`new`) or losing
# (`old`) cell is a leader changes ``\Delta H`` by ``-\mu\,(c(\text{target}) - c(\text{source}))``.
# The model follows the code. With the cue ``c = y - 1`` (set in the starting state, as
# in the paper, p. 6) leaders are biased upwards, into the empty matrix.
#
# ## Step 7: constraints
#
# <<fragment constraints>>
#
# `connectivity(leader, follower)` forbids copies that would split a leader or a
# follower: the cell losing the target site must keep its neighbours of that site in one
# arc (CompuCell3D's `Connectivity` plugin, used by the authors). `no_extinction` forbids
# copies that take a cell's last site.
#
# ## Step 8: growth and clocks
#
# <<fragment growth>>
#
# `@after_mcs` updates run after every MCS. `Pre(x)` is the value before the update. Each
# cell's target volume grows by its `rate` (0.015 per MCS for followers, the paper's
# ``f_{\text{grow}}``, Table 1) until it reaches `V_max` = 20, and running clocks
# (``\ge 0``) tick.
#
# ## Step 9: division
#
# <<fragment division>>
#
# A follower with a running clock divides when its volume exceeds `V_max` (twice the
# initial target) and its clock exceeds ``75 + 50\,U``, with ``U`` a fresh uniform draw
# every MCS (`rand()`). This is the authors' code. The paper's text describes one draw per
# cycle from ``U(25, 125)``; the code's per-MCS test fires between clock 76 and 125. The
# cell is cut along a random plane, the target volume is split between the daughters
# (`Split()`), and both clocks restart at 0.
#
# ## Step 10: the sweep
#
# <<fragment sweep>>
#
# ## The whole model

# <<model>>

# We run it on the paper's 500 × 300 lattice. Every default is the paper's value:

dims = (500, 300)
@named invasion = LeaderFollowerInvasion(; lattice = dims)

# ## The starting state
#
# The paper starts from a slab of followers 21 sites high across the whole width, in
# which a quarter of all cells are leaders (p. 5). The authors' code tiles the slab with
# 3 × 3 followers, then draws random sites and turns each draw that lands on a follower
# into a new one-site leader, until leaders are a quarter of all cells. Two layout layers
# say exactly this. `Tiling` fills a region with boxes. `InsertUntil` inserts one-site
# cells into cells of the given kinds until a stop rule holds; `misses = :count` counts a
# draw that misses (lands on a leader) towards the quota, as the authors' loop does.
# `overlay` paints the layers in order:

slab = overlay(Tiling((3, 3); region = (1:500, 1:21), kinds = [:follower], partial = :clip),
    InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed = 0x5cd2609, misses = :count,
        region = (2:500, 2:20), splits = :allow))
point = layout(slab, dims)
kinds = point[2].second
count(==(:leader), kinds), count(==(:follower), kinds)

# 1169 followers, as in the authors' files, and about 382 leaders painted for 390
# counted. `splits = :allow` silences a warning: two leaders inside one follower can cut
# it in two, which the published slab also does. This layout ships as `akeeb_layout`:

point[1].second == layout(akeeb_layout(), dims)[1].second

# `akeeb_state` paints it and adds the per-cell and per-site values: half of the
# followers get a running clock, drawn from ``0, \dots, 74`` (the paper's
# proliferation fraction ``PP``, here 0.5), followers grow at 0.015 per MCS, and the cue
# is ``y - 1``:

u0 = akeeb_state()
clocks = u0[3].second           # the pairs are ownership, kind, :clock, :rate, :cue
count(>=(0), clocks) / count(==(:follower), u0[2].second)

# ## Solving
#
# The paper reports its fronts at "MCS 700". The authors' CompuCell3D runs take 701 steps
# and count from 0, so their MCS ``t`` is our state after ``t + 1`` MCS: we run 701 MCS and
# save the start and every 10th of the authors' MCS (our 1, 11, …, 701). Cells are born
# during the run, so the problem reserves room for them with `capacity`:

prob = PottsProblem(invasion, u0, (0, 701); seed = 1, capacity = 6000)
sol = solve(prob, SequentialCPM(); saveat = [0; 1:10:701])
sol.stats.lifecycle.divisions

# ## The run as a movie
#
# Leaders are red and followers green, as in the paper's Fig. 4, on a white matrix;
# `boundaries = true` outlines each cell:

using MakiePotts, CairoMakie
mkpath("akeeb") #hide
record_potts("akeeb/invasion.mp4", sol; framerate = 15, title = "Leader–follower invasion", figure = (; size = (640, 420)),
    plot = (; boundaries = true, category_palette = [:red3, :forestgreen], medium_color = :white))
nothing #hide

# ```@raw html
# <video src="invasion.mp4" controls autoplay loop muted playsinline width="640"></video>
# ```
#
# Leaders climb out of the slab, many of them as single cells, and the growing followers
# advance behind them in fingers.
#
# ## Measuring the invasion
#
# Each saved state holds the owner array `u.σ` and each cell's kind `u.cell.kind`
# (1 leader, 2 follower). The mean height of each kind's sites shows leaders moving ahead
# of the followers:

using Statistics: mean
mean_height(u, k) = mean(I[2] for I in CartesianIndices(u.σ) if u.σ[I] > 0 && u.cell.kind[u.σ[I]] == k)
CairoMakie.activate!(type = "png")
fig = Figure(size = (520, 340))
ax = Axis(fig[1, 1]; xlabel = "MCS", ylabel = "mean height (sites)")
lines!(ax, sol.t, [mean_height(u, 1) for u in sol.u]; label = "leaders")
lines!(ax, sol.t, [mean_height(u, 2) for u in sol.u]; label = "followers")
axislegend(ax; position = :lt)
fig

# The paper measures the final front with the authors' analysis code: the areas under the
# top of the main tumour (invasive) and under the top of any cell (infiltrative), both
# above the tumour's lowest top; the fingers of the front; single leaders; detached
# cells; and clusters that contain a follower.
# `akeeb_observables` computes exactly these quantities (built from the
# `PottsModels.Analysis` tools) at a state. Here they are for this run at the authors'
# MCS 700, next to the authors' ensemble at the same point (``J_{LF} = 2``,
# ``\lambda = 24``, ``PP = 0.5``; mean ± SD of 10 runs, released data):

obs = akeeb_observables(sol.u[end])
using Markdown
reference = (invasive = "15734 ± 1362", infiltrative = "44029 ± 1669", singles = "204.5 ± 9.3",
    fingers = "12.0 ± 1.2", detached = "239.4 ± 11.1", clusters = "5.5 ± 2.3")
fmt(v) = v isa Integer ? string(v) : string(round(v; digits = 1))
Markdown.parse("""
| Measure | This run | Authors (10 runs) |
|:--|--:|--:|
""" * join(["| $m | $(fmt(getproperty(obs, m))) | $(reference[m]) |" for m in keys(reference)], "\n"))

# One run is not an ensemble: the reproduction of this paper compares ensembles of runs
# with every reference point and its tolerance.
#
# ## Differences from the paper
#
# The model follows the authors' CompuCell3D code where it differs from the text:
#
# | | Paper text | Here (the authors' code) |
# |:--|:--|:--|
# | Leader cue | a potential ``-\lambda \sum_x c(x)`` over leader sites (Eq. (1)) | CompuCell3D's per-copy chemotaxis, ``-\mu\,(c(\text{target}) - c(\text{source}))`` when a leader gains or loses the site |
# | Leaders at the start | 25% of the followers "reassigned" (p. 5) | one-site leaders inserted into followers; missed draws counted, so about 382 painted for 390 counted |
# | Division time | one draw from ``U(25, 125)`` MCS per cycle (p. 6) | a fresh test every MCS: clock ``> 75 + 50\,U`` |
# | Neighbourhoods | not stated | contacts over 8 neighbours, copies from 4 (CompuCell3D orders 2 and 1) |
# | ``y`` boundary | not stated | a closed wall (the CompuCell3D default) |
# | Connectivity | not mentioned | every cell kept in one piece (CompuCell3D `Connectivity`) |
# | Time | 700 MCS (701 CompuCell3D steps) | 701 MCS (the authors' MCS 700) |
# | Chemotaxis strength | ``\lambda = 24`` | `μ = 24`, the constructor's default |
#
# The lattice, temperature, contact energies, volume constraint, growth rate and division
# size are the paper's (Table 1). The leader–follower energy is 2 here; the paper scans
# it from −5 to 5.
#
# ## This model ships as `AkeebInvasion`
#
# PottsModels exports this model as `AkeebInvasion`; the test suite checks that it
# compiles to the same code and defaults as `LeaderFollowerInvasion` above.

@named akeeb = AkeebInvasion()

# Its start is `akeeb_state()`, used above. To scan the leader–follower energy as the
# paper does, pass a contact table with the state, for example
# `[akeeb_state(); :J => akeeb_contacts(-2.0)]`. To measure a state as the authors'
# analysis code does (invasive and infiltrative areas, fingers, singles, detached cells
# and clusters), use `akeeb_observables(u)`.

# ```@docs
# AkeebInvasion
# akeeb_state
# akeeb_layout
# akeeb_contacts
# akeeb_observables
# ```
