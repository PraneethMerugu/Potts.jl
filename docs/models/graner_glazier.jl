# # [Cell sorting by differential adhesion](@id model-graner-glazier)
#
# Mix two kinds of embryonic cells and they sort themselves out: one kind gathers into a
# core, the other wraps around it. Steinberg's differential adhesion hypothesis explains
# this with surface energies alone. Graner and Glazier (1992) put the hypothesis into a
# cellular Potts model: cells of two kinds, an area constraint and kind-dependent contact
# energies. That model is the smallest complete Potts model, so this page builds it first.
#
# **What you will learn**
#
# - how a `@potts_model` declares a lattice, cell kinds and parameters;
# - how an energy term is written as `domain => expression`, and how it maps to a term of
#   the paper's Hamiltonian;
# - how `@sweep` chooses the Metropolis dynamics;
# - how to build a starting aggregate with a layout, solve at the paper's size, record the
#   run as a movie and measure sorting;
# - where the run differs from the paper, and why.
#
# ## The paper
#
# - F. Graner and J. A. Glazier, "Simulation of biological cell sorting using a
#   two-dimensional extended Potts model", *Phys. Rev. Lett.* **69**, 2013 (1992),
#   doi:[10.1103/PhysRevLett.69.2013](https://doi.org/10.1103/PhysRevLett.69.2013).
# - J. A. Glazier and F. Graner, "Simulation of the differential adhesion driven
#   rearrangement of biological cells", *Phys. Rev. E* **47**, 2128 (1993),
#   doi:[10.1103/PhysRevE.47.2128](https://doi.org/10.1103/PhysRevE.47.2128).
#
# Every site ``i`` of a square lattice belongs to one cell ``\sigma_i``; cell 0 is the
# medium. Each cell has a kind ``\tau(\sigma)``: dark ``d``, light ``l`` or medium ``M``.
# The energy is Eq. (2) of the PRL:
#
# ```math
# H = \sum_{\langle i,j \rangle} J\big(\tau(\sigma_i), \tau(\sigma_j)\big)\,(1 - \delta_{\sigma_i \sigma_j})
#   + \lambda \sum_{\sigma} (a_\sigma - A)^2 ,
# ```
#
# a contact energy for every pair of neighbouring sites in different cells, and an area
# constraint that holds each cell's area ``a_\sigma`` near the target ``A``. The medium
# has no area constraint.
#
# We now write this model section by section. Each section is one or a few lines of a
# `@potts_model` block; the whole block is assembled and run at the end.

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
# `@structural_parameters` holds values that are fixed when the model is compiled, here
# the lattice size. `@lattice` builds a two-dimensional periodic lattice. `Moore(1)` is the
# neighbourhood used for contacts: the 8 nearest and next-nearest neighbours, as in the
# paper. `@relations proposal = Moore(1)` makes copy attempts come from the same 8
# neighbours: the paper copies from "one of the eight neighboring sites" (PRE, p. 2130).
#
# ## Step 2: cell kinds
#
# <<fragment kinds>>
#
# The first kind is always the medium. The others are cell kinds; a cell's kind decides
# which energy terms apply to it and which contact energies it pays.
#
# ## Step 3: parameters
#
# <<fragment parameters>>
#
# `λ`, `V₀` (the target area ``A``) and the temperature `T` are numbers. `J[kind, kind]`
# is a table indexed by two kinds, in the order of `@kinds`: row and column 1 are the
# medium, 2 dark and 3 light. These are the PRL's values (p. 2015):
# ``J(d,d) = 2``, ``J(d,l) = 11``, ``J(l,l) = 14`` and ``J(d,M) = J(l,M) = 16``.
#
# They obey the PRL's sorting hierarchy, Eq. (3): dark–dark contacts are the strongest
# (cheapest), the heterotypic energy is above the mean of the two homotypic ones, and
# contacts with the medium cost most. Let us check it:

J = [0 16 16; 16 2 11; 16 11 14]
J_dd, J_dl, J_ll, J_M = J[2, 2], J[2, 3], J[3, 3], J[1, 2]
J_dd < (J_dd + J_ll) / 2 < J_dl < J_ll < J_M

# The PRE (Sec. II) reads the same table as three surface tensions, the extra cost of
# a heterotypic boundary over the homotypic ones:

γ_dl = J_dl - (J_dd + J_ll) / 2
γ_lM = J_M - J_ll / 2
γ_dM = J_M - J_dd / 2
(; γ_dl, γ_lM, γ_dM)

# ``\gamma_{dl} > 0``, so the kinds separate. ``\gamma_{dM} > \gamma_{lM} + \gamma_{dl}``,
# so a light layer between the dark cells and the medium lowers the energy: light cells
# engulf dark ones.
#
# ## Step 4: the area constraint
#
# <<fragment area>>
#
# Energy terms are `domain => expression` pairs inside an `@energy` block. The domain
# `cells(dark, light)` sums the expression over every dark and light cell, so the medium
# is exempt, as in the paper. `volume` is the built-in cell size (the area in 2D). This
# is the second term of Eq. (2): ``\lambda \sum_\sigma (a_\sigma - A)^2``.
#
# ## Step 5: the contact energy
#
# <<fragment contacts>>
#
# The domain `contacts` sums over pairs of neighbouring sites (in the lattice's `Moore(1)`
# neighbourhood) that belong to different cells: the factor
# ``(1 - \delta_{\sigma_i \sigma_j})`` of Eq. (2). `kind` is the kind of one site's cell
# and `kind′` that of its neighbour's, so `J[kind, kind′]` is
# ``J(\tau(\sigma_i), \tau(\sigma_j))``.
#
# You never write the energy *change* of a copy: the compiler derives ``\Delta H`` from
# ``H``.
#
# ## Step 6: the sweep
#
# <<fragment sweep>>
#
# A copy attempt picks a random site and a random neighbour, and proposes to copy the
# neighbour's cell into the site. `Metropolis` accepts it with probability 1 when
# ``\Delta H \le 0`` and ``e^{-\Delta H / T}`` otherwise (PRE Eq. (3)). One Monte Carlo
# step (MCS) is as many attempts as the lattice has sites. The paper's MCS is 16 times
# longer (PRL, p. 2014), so one paper MCS is 16 of ours.
#
# ## The whole model
#
# Put together, the sections make one `@potts_model`:

# <<model>>

# `CellSorting` is now a constructor; keywords override structural parameters and
# parameter defaults. All parameters keep the paper's values. Only the lattice is chosen
# here, to fit the starting aggregate. The paper run at the top of this page uses the
# paper's 1000 cells; here we use 200, so that the page builds in seconds.
#
# ## The starting state
#
# A starting state names the owner of every site and the kind of every cell. *Layouts*
# build one from layers. The paper starts from a compact aggregate of "about 1000 cells"
# (PRE, p. 2129) of area about 40, with the kinds assigned at random. The `Voronoi` layout
# divides a region into one cell per generator point; here the region is a disk
# (`Circle`), the generators are `n` random sites of it (`RandomPoints`), and 30 Lloyd
# steps (`lloyd = 30`) move each generator to its cell's centroid, so the cells are compact
# and of about equal area. Its `kinds` are cycled over the randomly placed cells, so dark
# and light are mixed at random, in equal numbers. A disk of area ``n \times 40`` sites,
# with a 10-site margin of medium on every side, sets the lattice:

n = 200
radius = sqrt(40n / π)
side = 2ceil(Int, radius) + 1 + 2 * 10
@named sorting = CellSorting(; lattice = (side, side))
disk = Circle(Point((side + 1) / 2, (side + 1) / 2), radius)     # centred on the lattice
u0 = layout(Voronoi(RandomPoints(n; region = disk, seed = 1); region = disk, lloyd = 30, kinds = [:dark, :light]), sorting)
first(u0[2].second, 6)

# `layout` returns an operating point, `[ownership => σ, kind => kinds]`, the same form a
# hand-made state would have. Passing the model (rather than a size) lets the layout use
# its lattice. Other layers (`Tiling`, `Scattered`, `InsertUntil`, combined with `overlay`)
# appear on the other model pages.
#
# ## Solving
#
# A `PottsProblem` joins the model, the starting state and the time span (in MCS);
# `solve` runs it. 1600 MCS are 100 paper MCS (the paper runs to ``10^4``); `saveat`
# keeps 51 states for the movie and the measurement:

prob = PottsProblem(sorting, u0, (0, 1600); seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 0:32:1600)

# ## The run as a movie
#
# MakiePotts draws saved states, one colour per kind (dark cells blue, light cells green,
# medium black); `boundaries = true` outlines each cell. `record_potts` writes the whole
# solution as a movie:

using MakiePotts, CairoMakie
mkpath("graner_glazier") #hide
record_potts("graner_glazier/sorting.mp4", sol; framerate = 10, title = "Cell sorting, 200 cells",
    figure = (; size = (400, 400)), plot = (; boundaries = true))
nothing #hide

# ```@raw html
# <video src="sorting.mp4" controls autoplay loop muted playsinline width="420"></video>
# ```
#
# Same-kind clusters form and merge, and light cells collect at the medium: the start of
# the engulfment the PRL describes. (A single saved state is drawn with
# `pottsplot(renderframe(sol.u[k]))`.)
#
# ## Measuring sorting
#
# The paper measures sorting by the share of cell–cell boundary that is heterotypic
# (dark–light). Each saved state `u` holds the owner array `u.σ`, and `u.cell.kind` gives
# each cell's kind (1 dark, 2 light). We count every Moore bond once, through the periodic
# edges:

function heterotypic_fraction(u)
    σ, k = u.σ, u.cell.kind
    nx, ny = size(σ)
    hetero = homo = 0
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a, b = σ[x, y], σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        (a == b || a == 0 || b == 0) && continue
        k[a] == k[b] ? (homo += 1) : (hetero += 1)
    end
    return hetero / (hetero + homo)
end
CairoMakie.activate!(type = "png")
paper_t = sol.t[2:end] ./ 16                       # in paper MCS
lines(paper_t, heterotypic_fraction.(sol.u[2:end]);
    axis = (xscale = log10, xlabel = "time (paper MCS)", ylabel = "heterotypic boundary fraction"))

# The fraction falls about linearly in the logarithm of time, the slow coarsening the
# papers report (PRL Fig. 2, PRE Fig. 13).
#
# ## Differences from the paper
#
# | | Paper | Here |
# |:--|:--|:--|
# | Time unit | 1 MCS = 16 copy attempts per site (PRL p. 2014) | 1 MCS = 1 attempt per site; times above are converted to paper MCS |
# | Run length | to ``10^4`` paper MCS | 100 paper MCS on this page, to keep the docs build short |
# | Cells | about 1000 | 200 on this page (1000 in the paper run above) |
# | Starting aggregate | relaxed as one kind for 400 paper MCS before the kinds are assigned (PRE §II D3) | Voronoi cells of mean area 40, not relaxed |
# | Boundary | not stated | periodic, with a 10-site medium margin on this short run (60 in the paper run and by default in `graner_glazier_aggregate`) |
# | Measurement | on a copy annealed for 2 paper MCS at ``T = 0`` (PRE p. 2134) | on the raw states |
# | Target area per kind | one value, except the cavity run (PRE Fig. 28) | one `V₀`; a per-kind table `V₀[kind]` gives the cavity run's targets |
#
# Every energy, parameter, neighbourhood and the temperature are the paper's.
#
# ## This model ships as `GranerGlazier`
#
# PottsModels exports this model as `GranerGlazier`. It is the same `@potts_model`: the
# test suite checks that it compiles to the same code, with the same defaults, as
# `CellSorting` above.

@named gg = GranerGlazier(; lattice = (side, side))

# Its starting states are `graner_glazier_aggregate(n)`, the aggregate built above but with
# a 60-site medium margin by default (a long run drifts, and a 10-site margin lets it reach
# the lattice edge and its periodic image; pass `margin` for a short run), and
# `graner_glazier_state()`, 64 cells made by the PRE's relaxation recipe on the default
# 72 × 72 lattice.

# ```@docs
# GranerGlazier
# graner_glazier_aggregate
# graner_glazier_state
# ```
#
# ## Reproduction
#
# A full reproduction page, which runs `GranerGlazier` against the papers' figures (the
# sorting time course, the engulfment end state, partial sorting and a negative control),
# is in preparation.
