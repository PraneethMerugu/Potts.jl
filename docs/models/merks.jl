# # [Vasculogenesis by chemotaxis and cell elongation](@id model-merks)
#
# Endothelial cells spread on Matrigel organise themselves into a polygonal network of
# cords, the first step of blood-vessel formation (vasculogenesis). The cells secrete a
# chemoattractant and move up its gradient. Merks and coworkers (2006) found that in a
# cellular Potts model this chemotaxis alone gathers the cells into round islands, and that
# a network forms only when the cells are elongated. PottsModels ships their model, with
# the paper's parameter set, border and connectivity rule, as `Merks2006`, and the 2008
# contact-inhibited model as `Merks2008`; this page is about them. The full reproduction,
# target by target, is reproduction 01 (*Vasculogenesis*, in the Published models section).
# The second half of the page builds a simpler variant, `MerksVasculogenesis`, step by step.
#
# **What you will learn**
#
# - how to declare a diffusing field and write its reaction–diffusion equation;
# - how a *drive* adds a non-energetic bias (chemotaxis) to every copy;
# - how a shape descriptor (the cell length) enters an energy term;
# - how a constraint keeps cells in one piece, and how a structural parameter switches
#   between model variants;
# - how to choose the field solver, compare runs with a parameter changed, and record
#   them as movies, on the paper's lattice.
#
# The [cell sorting page](@ref model-graner-glazier) explains the parts every model shares
# (lattice, kinds, parameters, the area and contact energies, the sweep); here they are
# brief.
#
# ## The paper
#
# - R. M. H. Merks, S. V. Brodsky, M. S. Goligorsky, S. A. Newman and J. A. Glazier,
#   "Cell elongation is key to in silico replication of in vitro vasculogenesis and
#   subsequent remodeling", *Dev. Biol.* **289**, 44 (2006),
#   doi:[10.1016/j.ydbio.2005.10.003](https://doi.org/10.1016/j.ydbio.2005.10.003).
# - R. M. H. Merks, E. D. Perryn, A. Shirinifard and J. A. Glazier, "Contact-inhibited
#   chemotaxis in de novo and sprouting blood-vessel growth", *PLoS Comput. Biol.* **4**,
#   e1000163 (2008), doi:[10.1371/journal.pcbi.1000163](https://doi.org/10.1371/journal.pcbi.1000163).
#
# Equation numbers below are those of the 2006 paper (01a) unless marked 01b (2008). The energy is Eq. (1) plus the
# length constraint of Eq. (4):
#
# ```math
# H = \sum_{\langle i,j \rangle} J\big(\tau(\sigma_i), \tau(\sigma_j)\big)\,(1 - \delta_{\sigma_i \sigma_j})
#   + \lambda \sum_\sigma (a_\sigma - A)^2 + \lambda_L \sum_\sigma (l_\sigma - L)^2 .
# ```
#
# A copy from site ``x`` into its neighbour ``x'`` changes the energy by an extra
# chemotaxis term, Eq. (2), ``\Delta H_{\text{chemotaxis}} = \chi\,(c(x) - c(x'))``
# (``\gamma`` in the paper): copies up the gradient are favoured. The chemoattractant
# ``c`` obeys Eq. (6),
#
# ```math
# \frac{\partial c}{\partial t} = D \nabla^2 c + \alpha\,[\text{cell}] - \varepsilon\,c\,[\text{matrix}] ,
# ```
#
# secreted at rate ``\alpha`` inside cells and decaying at rate ``\varepsilon`` in the
# matrix.

# ## The reference model: `Merks2006`
#
# `Merks2006` is the 2006 model as the paper and the authors' code define it:
#
# - **Energy** (Eqs. 1, 4, 5): contacts over the 8 Moore neighbours, ``\lambda (a - A)^2``
#   and ``\lambda_L (l - L)^2`` for every endothelial cell, with ``l = 4\sqrt{\lambda_b/a}``
#   (`major_length`).
# - **Chemotaxis** at every copy (Eq. 2): ``-\chi\,(f(c(x')) - f(c(x)))`` with
#   ``f(c) = c/(1 + s c)``, ``\chi = 1000`` (the paper's ``\gamma``) and ``s = 0``.
# - **Connectivity** (p. 49): the soft penalty. A copy that breaks the losing cell's
#   8-site ring costs ``E_0 = 5000`` (`rule = :soft`, the default; under Metropolis this is
#   the authors' dissipation threshold). `rule = :hard` vetoes those copies instead.
# - **Border:** a frozen border cell one site thick around the lattice (`Frame(:border)`),
#   with ``J(c, B) = 100``, and the field held at ``c = 0`` on it (the authors' absorbing
#   ring).
# - **Field** (Eq. 6): ``\partial c/\partial t = D \nabla^2 c + \alpha[\text{cell}] -
#   \varepsilon c[\text{matrix}]``, stepped *before* each sweep (`@schedule fields, sweep`) with
#   15 explicit substeps of 2 s per MCS.
# - **Parameters** in lattice units (2 µm per site, 30 s per MCS): ``T = 50``,
#   ``\lambda = 50``, ``A = 100``, ``\lambda_L = 5``, ``L = 50`` px ("about 100 µm"),
#   ``D = 0.75``, ``\alpha = \varepsilon = 5.4 \cdot 10^{-3}``, ``J_{cM} = 20``, ``J_{cc} = 40``.
# - **Clocks:** one MCS is 30 s, so the paper's 48 h are 5760 MCS and 50 h are 6000 MCS.
#   The paper run below shows both.
#
# Its definition, abridged:
#
# ```julia
# @potts_model Merks2006 begin
#     @structural_parameters begin
#         lattice = (500, 500)
#         rule = :soft
#     end
#     @kinds medium endothelial border[frozen]
#     @parameters begin
#         T = 50.0; λ = 50.0; A = 100.0; λ_L = 5.0; L = 50.0; E₀ = 5000.0
#         χcM = 1000.0; χcc = 1000.0; s = 0.0; Dc = 0.75; α = 5.4e-3; ε = 5.4e-3
#         J[kind, kind] = [0.0 20.0 0.0; 20.0 40.0 100.0; 0.0 100.0 0.0]
#     end
#     @variables c(field) = 0.0
#     @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
#     @relations proposal = Moore(1)
#     @energy begin
#         cells(endothelial) => λ * (volume - A)^2 + λ_L * (major_length - L)^2
#         contacts => J[kind, kind′]
#     end
#     @drive copy => -ifelse((old == 0) | (new == 0), χcM, χcc) *
#                    (c[target] / (1 + s * c[target]) - c[source] / (1 + s * c[source]))
#     # rule = :soft: the authors' connectivity penalty
#     @drive copy => E₀ * ((kind[old] == endothelial) & !((ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))))
#     @equations D(c) ~ Dc * Δ(c) + α * (kind == endothelial) - ε * c * (kind == medium)
#     @boundary c begin
#         sites(kind == border) => Dirichlet(0.0)
#     end
#     @schedule fields, sweep
#     @sweep Metropolis(; temperature = T)
# end
# ```
#
# ## The paper run
#
# `Merks2006` with its defaults, at the paper's size: 282 cells over the central 333 × 333
# sites of 500 × 500 (`merks2006_layout()`), to 50 h. It is computed outside the docs build:
#
# <<paper_run>>
#
# ## Running `Merks2006`
#
# The same model on a 200 × 200 lattice at the paper's density (100 cells of 10 × 10 over
# the whole interior, as reproduction 01's reduced build), for 4 h, so that the page builds
# quickly. `merks2006_layout` places the cells and the one-site frozen border:

using Potts, PottsModels
using MakiePotts, CairoMakie
mkpath("merks") #hide

lat = (200, 200)
@named m6 = Merks2006(; lattice = lat)
prob06 = PottsProblem(m6, layout(merks2006_layout(; lattice = lat, n = 100, seed = 1), lat), (0, 480);
    seed = 1, field_solver = ExplicitEuler(substeps = 15))
sol06 = solve(prob06, SequentialCPM(); saveat = 0:10:480)
record_potts("merks/merks2006.mp4", sol06; framerate = 15, title = "Merks2006, 200², to 4 h",
    encoding = CellIdentityEncoding(), figure = (; size = (420, 420)), axis = (; limits = (1.5, 199.5, 1.5, 199.5)))
nothing #hide

# ```@raw html
# <video src="merks2006.mp4" controls autoplay loop muted playsinline width="420"></video>
# ```
#
# Each cell has its own colour; the frozen border is cropped from the view.
#
# ```@docs
# Merks2006
# merks2006_layout
# merks_layout
# ```
#
# ## The 2008 model: `Merks2008`
#
# Merks et al. (2008) drop the length constraint and make chemotaxis contact-inhibited:
# it acts only at cell–matrix interfaces (``\chi(c, M) = 500``, ``\chi(c, c) = 0``), which
# turns a dispersed population into a network and a compact cluster into sprouts. Its
# other changes: contacts and copies over the 20 neighbours of `NeighborOrder(4)` (first to
# fourth order), a two-site frozen border, smaller cells (``A = 50``, ``\lambda = 25``),
# ``\alpha = \varepsilon = 0.03``, and no field for the first ``t_\text{relax} = 100`` MCS
# (the authors' relaxation). Its time origin is the authors' loop counter, which includes
# those 100 MCS; reproduction 01 reports both clocks. `mode = :extension_only` gives the
# extension-only chemotaxis of 01b Eq. 4. The sprouting start is `merks2008_sprout()`: one
# Eden blob divided into 128 cells on 202 × 202. Here it runs 600 MCS (500 after relaxation):

@named m8 = Merks2008()
prob08 = PottsProblem(m8, layout(merks2008_sprout(; seed = 1), (202, 202)), (0, 600);
    seed = 1, field_solver = ExplicitEuler(substeps = 15))
sol08 = solve(prob08, SequentialCPM(); saveat = 0:10:600)
record_potts("merks/merks2008.mp4", sol08; framerate = 15, title = "Merks2008 sprout, 600 MCS",
    encoding = CellIdentityEncoding(), figure = (; size = (420, 420)), axis = (; limits = (2.5, 200.5, 2.5, 200.5)))
nothing #hide

# ```@raw html
# <video src="merks2008.mp4" controls autoplay loop muted playsinline width="420"></video>
# ```
#
# ```@docs
# Merks2008
# merks2008_sprout
# merks2008_denovo
# ```
#
# ## Variant: `MerksVasculogenesis`, built step by step
#
# `MerksVasculogenesis` is a simpler, legacy form of the 2006 model, kept as a documented
# variant because it builds in fewer ingredients. It is **not** the paper's model. Its
# deviations from the paper:
#
# - connectivity is a hard veto (`rule = :local`), not the soft ``E_0`` penalty;
# - no frozen border: the closed lattice walls cost nothing (paper: ``J(c, B) = 100``);
# - the field has a zero-flux boundary (the authors' code holds ``c = 0`` on the border);
# - the field is stepped after the sweep, not before it, and is clipped at 0;
# - its 2008 switch (`contact_inhibited = true`) keeps 8 Moore neighbours, the 2006 cell
#   size and no saturation (`Merks2008` uses 20 neighbours and the 2008 set).
#
# The parameters are the 2006 set. The rest of this section builds it.
#
# ### Step 1: the lattice and the variant switch
#
# <<fragment lattice>>
#
# The lattice is closed (no wrap-around), with Moore contacts (the paper's 8 neighbours)
# and copies (from the authors' code). The paper's border differs; see the table at the
# end.
# `contact_inhibited` is a second structural parameter: it selects one of two chemotaxis
# rules in Step 6, when the model is constructed.
#
# ### Step 2: cell kinds
#
# <<fragment kinds>>
#
# One cell kind, the endothelial cells, in a medium that stands for the matrix.
#
# ### Step 3: parameters
#
# <<fragment parameters>>
#
# The defaults are the paper's values in lattice units (2 µm per site, 30 s per MCS):
# ``T = 50``, ``\chi = 1000``, cell–cell ``J = 40``, cell–matrix ``J = 20``,
# ``D = 0.75``, ``\alpha = \varepsilon = 5.4 \cdot 10^{-3}``, target area `V₀` ``= 100``
# with `λ` ``= 50``, and target length `L` ``= 50`` (the paper's "about 100 µm") with
# `λ_L` ``= 5``. `Dc`, `σc` and `δc` are ``D``, ``\alpha`` and ``\varepsilon``. The 2008
# contact-inhibited runs used smaller cells (target area 50); pass such values as keywords.
#
# ### Step 4: the chemoattractant field
#
# <<fragment field>>
#
# A variable's *scope* is written in its signature. `c(field)` is a value at every lattice
# site that is advanced by a differential equation (Step 7); it starts at 0. Other scopes
# are `x(site)` (a value per site updated by rules), `x(cell)` (one value per cell) and
# `x(model)` (one value for the whole model).
#
# ### Step 5: the energy
#
# <<fragment shape>>
#
# The area term is the one of cell sorting. The length term uses the built-in shape
# descriptor `major_length`: the paper's cell length ``l = 4\sqrt{\lambda_b / a}``, with
# ``\lambda_b`` the largest eigenvalue of the cell's inertia tensor (Eq. (5)). The
# compiler keeps the cell's moments up to date, so the term costs a few operations per copy.
#
# <<fragment contacts>>
#
# ### Step 6: the chemotaxis drive
#
# <<fragment drive>>
#
# A *drive* adds a term to ``\Delta H`` of every copy without being part of ``H``.
# Chemotaxis is one: it biases copies but stores no energy. In a copy, `source` is the site
# copied from and `target` the site copied into, so `-χ * (c[target] - c[source])` is
# Eq. (2): negative, hence favoured, when the cell extends up the gradient.
#
# The `if` is evaluated when the model is constructed. With `contact_inhibited = true` the
# drive acts only when a cell extends into the medium (`old == 0`: the target belonged to
# the medium; `new` is the cell that gains it). That is the contact-inhibited,
# extension-only rule of the 2008 paper (its Eq. (4), here without the saturation of the
# response), with which cells form sprouts.
#
# ### Step 7: the field equation
#
# <<fragment equation>>
#
# `@equations` takes ModelingToolkit-style equations. `D(c)` is the time derivative,
# `Δ(c)` the lattice Laplacian, and `(kind == endothelial)` is 1 at sites owned by an
# endothelial cell and 0 elsewhere: this is Eq. (6) term by term. The equation is solved
# after every MCS. How is chosen when the problem is built (below), not in the model.
#
# ### Step 8: connectivity
#
# <<fragment constraint>>
#
# A constraint vetoes copies. The paper penalises copies that would split a cell
# (an energy threshold above 2000, p. 49); here such copies are forbidden outright. The
# `:local` rule decides from the 8 neighbours of the target site whether the losing cell
# stays in one piece.
#
# ### Step 9: the sweep
#
# <<fragment sweep>>
#
# Metropolis at ``T = 50``. The paper adds a dissipation threshold ``E_0`` to the
# acceptance rule (Eq. (3)) but gives no value; the model uses plain Metropolis.
#
# ### The whole model

# <<model>>

# Here we use 200 × 200 at the paper's cell density, so that the page builds in seconds:

@named vasc = Vasculogenesis(; lattice = (200, 200))

# ### The starting state
#
# The paper scatters 282 cells at random over the central 333 × 333 sites of its lattice
# (Fig. 4). `merks_state` builds this start: square cells of 10 × 10 sites (the target
# area; the paper does not state the initial cell shape) at random, non-overlapping positions with gaps of at least one site.
# Scaled to our lattice, 45 cells over the central 133 × 133 sites keep the paper's
# density:

u0 = merks_state(; lattice = (200, 200), region = (133, 133), n = 45)
length(u0[2].second)

# The same kind of start is one `Scattered` layer of the layout vocabulary, for example
# `layout(Scattered(45, (10, 10); kinds = [:endothelial], region = (34:166, 34:166), seed = 1), vasc)`.

# ### Solving
#
# A model with a field needs a *field solver*, chosen when the problem is built. The paper
# integrates the field with 15 explicit Euler steps per MCS (2 s each); `substeps = 15`
# does the same, and `lower = 0.0` clips the concentration at zero. One MCS is 30 s, so
# 1000 MCS are about 8 hours (paper: 50 hours; here: 1000 MCS, to keep the build short):

prob = PottsProblem(vasc, u0, (0, 1000); seed = 1, field_solver = ExplicitEuler(substeps = 15, lower = 0.0))
sol = solve(prob, SequentialCPM(); saveat = 0:10:1000)

# The paper's central claim is that elongation makes the network. `remake` builds the same
# problem with a parameter changed, without compiling again; with `λ_L = 0` the cells stay
# round:

round_cells = solve(remake(prob; p = [:λ_L => 0.0]), SequentialCPM(); saveat = 0:10:1000)

# ### The runs as movies
#
# `record_potts` writes a solution as a movie; each cell has its own colour.

record_potts("merks/elongated.mp4", sol; framerate = 15, title = "elongated cells (λ_L = 5)",
    encoding = CellIdentityEncoding(), figure = (; size = (400, 400)))
record_potts("merks/round.mp4", round_cells; framerate = 15, title = "round cells (λ_L = 0)",
    encoding = CellIdentityEncoding(), figure = (; size = (400, 400)))
nothing #hide

# ```@raw html
# <video src="elongated.mp4" controls autoplay loop muted playsinline width="380"></video>
# <video src="round.mp4" controls autoplay loop muted playsinline width="380"></video>
# ```
#
# Elongated cells join into branched cords, the start of a network; round cells gather
# into compact islands (the paper's Fig. 6 makes this comparison). With only 45 cells the
# small network coarsens if run much longer; the paper run at the top (`Merks2006`) shows
# the full-size network over 50 hours. `sol[:c]` reads the chemoattractant at every saved time (symbolic
# indexing, as in ModelingToolkit); at the end it follows the network:

CairoMakie.activate!(type = "png")
heatmap(sol[:c][end]; axis = (title = "chemoattractant c, MCS $(sol.t[end])", aspect = DataAspect()))

# ### Measuring elongation
#
# `sol[:major_length]` is the length of every cell at every saved time. The cells start
# as 10 × 10 squares (length about 11.5) and stretch towards `L = 50` when `λ_L > 0`:

using Statistics: mean
mean_length(s) = [mean(l) for l in s[:major_length]]
fig = Figure(size = (520, 340))
ax = Axis(fig[1, 1]; xlabel = "MCS", ylabel = "mean cell length (sites)")
lines!(ax, sol.t, mean_length(sol); label = "λ_L = 5")
lines!(ax, round_cells.t, mean_length(round_cells); label = "λ_L = 0")
axislegend(ax; position = :rc)
fig

# ### Differences from the paper
#
# | | Paper (2006) | Here |
# |:--|:--|:--|
# | Lattice | 500 × 500, 282 cells over the central 333 × 333 sites | 200 × 200 on this page, 45 cells over the central 133 × 133 sites (same density) |
# | Run length | 50 h (6000 MCS) | 1000 MCS (8.3 h) on this page, to keep the docs build short |
# | Cell size | ``A = 100``, ``\lambda = 50``, length "about 100 µm" (``L = 50``), ``\lambda_L = 5``; the authors' parameter file `longcells.par` uses ``L = 60`` | the same, with `L = 50` from the paper text (pass `L = 60.0` for the parameter file's value) |
# | Initial cells | shape not stated | 10 × 10 squares |
# | Lattice border | frozen border cells with ``J = 100`` against cells | closed walls that cost nothing |
# | Field at the border | the authors' code holds ``c = 0`` on an absorbing border ring | zero flux |
# | Contact-inhibited variant (2008) | 20 neighbours for contacts and copies (the authors' parameter files) | `contact_inhibited = true` keeps the 8 Moore neighbours |
# | Acceptance | Metropolis with a dissipation threshold ``E_0`` (Eq. (3)), value not given | plain Metropolis |
# | Connectivity | an energy penalty above 2000 (p. 49) | a hard veto |
# | Field integration | 15 explicit substeps per MCS (p. 49) | the same, `ExplicitEuler(substeps = 15)`, clipped at 0 |
#
# The cell size, contact energies, temperature, chemotaxis strength, the field
# integration, the diffusion, secretion and decay rates inside the lattice, the 2006 model's neighbourhoods and the cell density
# are the paper's.
#
# ### This variant ships as `MerksVasculogenesis`
#
# PottsModels exports this model as `MerksVasculogenesis`; the test suite checks that it
# compiles to the same code and defaults as `Vasculogenesis` above, in both variants.

@named merks = MerksVasculogenesis()

# Its start is `merks_state()`: the paper's 282 cells on the 500 × 500 lattice.

# ```@docs
# MerksVasculogenesis
# merks_state
# ```
