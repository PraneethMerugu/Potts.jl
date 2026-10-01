# [Your first cellular Potts model](@id getting-started)

This page builds a complete simulation of **cell sorting** from scratch. You will learn:

- what a cellular Potts model is, in a few paragraphs;
- how to write a model with `@potts_model`;
- how to build an initial state, a problem and a solution;
- how to plot the result and read cell quantities such as volumes;
- how to change a parameter without recompiling, and how to run an ensemble.

No knowledge of Julia or of SciML is assumed. If you have never used Julia, read the
primer below first.

!!! tip "Julia in five minutes"
    - Run code in the Julia REPL (type `julia` in a terminal) or in a notebook. Packages are
      loaded with `using Potts`.
    - `x = 1.0` makes a variable. `[1, 2, 3]` is a vector, `[1 2; 3 4]` a 2×2 matrix (rows
      are separated by `;`). Indices start at 1: `v[1]` is the first element, `v[end]` the
      last.
    - `(60, 60)` is a tuple. `a => b` is a pair. `:dark` is a symbol, a name used as a value.
    - `f(x; k = 2)` calls `f` with the keyword argument `k`. Keywords come after `;`.
    - Functions with a `!` at the end (`solve!`, `step!`) change their argument.
    - Macros start with `@` (`@potts_model`, `@named`). They transform the code you write
      before it runs.
    - Unicode names such as `λ`, `V₀` and `kind′` are ordinary names. In the REPL type
      `\lambda` then Tab for `λ`, `V\_0` then Tab for `V₀`, and `kind\prime` then Tab for `kind′`.
    - `?solve` in the REPL shows the documentation of `solve`.

## What is a cellular Potts model?

A cellular Potts model represents a tissue on a grid of **sites** (pixels in 2D, voxels in
3D). Every site belongs to exactly one **cell**, or to the **medium** (the space around the
cells, cell number 0). A cell is the set of sites with its number, so cells have real shapes
that change over time.

Each cell has a **kind** (also called a type), such as `dark` or `light`. A model assigns an
**energy** ``H`` to every configuration of the grid. A typical ``H`` has two parts:

- a **contact** term: each pair of neighbouring sites that belong to different cells
  costs an energy ``J`` that depends on the two kinds. Low ``J`` means strong adhesion.
- an **area** (or volume) term ``\lambda (V - V_0)^2`` that keeps every cell near its
  target size ``V_0``.

The simulation repeatedly picks a random site and proposes to **copy** the cell of a
random neighbouring site into it. The copy is accepted with the Metropolis rule: always if
it lowers the energy, and with probability ``e^{-\Delta H / T}`` if it raises it by
``\Delta H``. The **temperature** ``T`` sets how much the cell membranes fluctuate. One
**Monte Carlo step** (MCS) is as many copy attempts as there are sites.

In Potts.jl you write ``H`` and the copy rules as equations. Potts.jl derives the energy
change of a copy (``\Delta H``) and generates the simulation code.

## Step 1: load the packages

```@example start
using Potts            # the modelling language and the solvers
using PottsModels      # published models and their initial states
using MakiePotts       # plotting of Potts states
using CairoMakie       # a Makie backend that draws figures and videos to files
CairoMakie.activate!(type = "png") # hide
```

## Step 2: write the model

A model is a block of **sections**, each starting with `@`. This is the cell sorting model
of Graner and Glazier (1992), with the parameters of the paper:

```@example start
@potts_model CellSorting begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice((72, 72); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end
```

Line by line:

- `@kinds medium dark light` declares the cell kinds. The **first kind is always the
  medium**.
- `@parameters` declares the numbers of the model with their default values: the
  strength `λ` and target `V₀` of the area constraint, the temperature `T`, and the
  contact energies. `J[kind, kind]` is a table indexed by two kinds, in the order of
  `@kinds`: row 2, column 3 is the dark–light energy (11). Dark–dark contacts (2) are the
  cheapest, so dark cells stick together most; contacts with the medium (16) are the most
  expensive.
- `@lattice` declares a 72×72 grid. `Periodic()` wraps the edges around.
  `Moore(1)` makes the 8 surrounding sites the neighbours of a site.
- `@relations proposal = Moore(1)` lets a copy come from any of these 8 neighbours, as in
  the paper (the default is the 4 nearest).
- `@energy` lists the terms of ``H``, each as `domain => expression`:
  - `cells(dark, light) => λ * (volume - V₀)^2` sums over every dark and light cell;
    `volume` is the number of sites of the cell.
  - `contacts => J[kind, kind′]` sums over every pair of neighbouring sites owned by
    different cells; `kind` and `kind′` are the kinds on the two sides.
- `@sweep Metropolis(; temperature = T)` sets the acceptance rule.

`@potts_model` defines a constructor function, `CellSorting`. Calling it makes the model
object. `@named` gives the model a name (here `sorting`):

```@example start
@named sorting = CellSorting()
```

Keywords change the defaults: `CellSorting(; name = :hot, T = 20.0)` is the same model
with a higher temperature.

!!! note "This model ships with Potts"
    `PottsModels` contains this model as `GranerGlazier`, with its documentation and a
    [reproduction of the paper](@ref published-models). Writing it out here shows how a
    model is built; `@named sorting = GranerGlazier()` gives the same model.

## Step 3: the initial state

The initial state says which cell owns each site and what kind each cell is. The paper
starts from a round aggregate of 64 cells, each dark or light at random.
`graner_glazier_state()` returns it as two arrays:

```@example start
σ0, kinds0 = graner_glazier_state()
size(σ0), length(kinds0)
```

`σ0` is the 72×72 matrix of cell numbers (0 for the medium), and `kinds0` the kind of each
cell (1 = dark, 2 = light, in the order of `@kinds` after the medium). The pairs
`ownership => σ0` and `kind => kinds0` form the **operating point**, as in ModelingToolkit.
You can also build initial states from simple pieces with layouts; the
[layouts tutorial](@ref tutorial-layouts) shows how.

## Step 4: build the problem

A `PottsProblem` combines the model, the initial state and the time span (in MCS):

```@example start
prob = PottsProblem(sorting, [ownership => σ0, kind => kinds0], (0, 3200); seed = 1)
nothing # hide
```

Building the problem compiles the model, so the first problem of a session takes a few
seconds. `seed` fixes the random numbers: the same seed gives the same run.

!!! note "Time units"
    One of our MCS is one copy attempt per site. Graner and Glazier count 16 attempts per
    site as one MCS, so 3200 of our MCS are 200 of the paper's. The paper follows the
    sorting to 10⁴ of its MCS; here we stop early to keep the page fast.

## Step 5: solve

```@example start
sol = solve(prob, SequentialCPM(); saveat = 50)
```

`SequentialCPM()` is the standard algorithm: one copy attempt after another, as in the
original model. `saveat = 50` saves the state every 50 MCS (the first and last states
are always saved). `sol.t` holds the saved times and `sol.u` the saved states:

```@example start
sol.t[1:5]
```

## Step 6: watch the run

`record_potts` turns the saved states into a video, one frame per saved state:

```@example start
record_potts("getting_started_sorting.mp4", sol; framerate = 12, title = "", plot = (; boundaries = true), figure = (; size = (420, 420)))
nothing # hide
```

```@raw html
<video src="../getting_started_sorting.mp4" controls autoplay loop muted playsinline width="420"></video>
```

The dark cells (blue) gather into a growing cluster and the light cells (green) cover
them. For a single picture, `renderframe` turns one saved state into a frame and `pottsplot`
draws it: `pottsplot(renderframe(sol.u[end]))`.

Our run stops at 200 of the paper's MCS. This is the same model run as long as in the
paper (10⁴ of its MCS), made offline:

```@example start
Main.paper_run("graner_glazier", "../") # hide
```

## Step 7: read cell quantities

Every quantity of the model can be read from the solution by name, as with
ModelingToolkit's symbolic indexing. `sol[:volume]` gives, for each saved time, the
volume of every cell:

```@example start
volumes = sol[:volume]
volumes[end][1:8]       # the volumes of cells 1 to 8 at the last saved time
```

The kinds work the same way:

```@example start
kinds = sol[:kind][end]
kinds[1:8]              # 1 = dark, 2 = light
```

The results are ordinary Julia arrays, so any Julia code can analyse them. For example,
the mean volume of the dark cells at the last saved time:

```@example start
using Statistics: mean
mean(volumes[end][kinds .== 1])
```

A saved state also holds the raw arrays: `u.σ` is the matrix of cell numbers and `u.cell`
the per-cell arrays. This function counts the dark–light contacts between neighbouring
sites, a measure of how mixed the aggregate is:

```@example start
function mixed_contacts(u)
    σ, k = u.σ, u.cell.kind
    n = 0
    for x in CartesianIndices(σ), step in ((1, 0), (0, 1))
        y = CartesianIndex(mod1.(Tuple(x) .+ step, size(σ)))   # neighbour, wrapping around
        a, b = σ[x], σ[y]
        n += (a != 0 && b != 0 && k[a] != k[b])
    end
    return n
end
mixed = mixed_contacts.(sol.u)
fig = Figure(size = (600, 300))
ax = Axis(fig[1, 1]; xlabel = "MCS", ylabel = "dark–light contacts")
lines!(ax, sol.t, mixed)
fig
```

The count falls as the cells sort. `total_energy` computes ``H`` of any state; it falls too:

```@example start
total_energy(prob, sol.u[1]), total_energy(prob, sol.u[end])
```

## Step 8: change a parameter

`remake` changes parameters without recompiling. Here we change one entry of the paper's
table: the dark–light energy goes from 11 to 8, the mean of the dark–dark (2) and
light–light (14) energies. Then a mixed boundary costs the same as a sorted one, and the
aggregate stays mixed:

```@example start
J_neutral = [0 16 16; 16 2 8; 16 8 14]      # paper: J(dark, light) = 11; here: 8
prob_neutral = remake(prob; p = [:J => J_neutral])
sol_neutral = solve(prob_neutral, SequentialCPM(); saveat = 50)
lines!(ax, sol_neutral.t, mixed_contacts.(sol_neutral.u); label = "J(dark, light) = 8")
fig
```

## Step 9: an ensemble

A cellular Potts model is random, so one run is one sample. An `EnsembleProblem` runs many
replicates with independent random streams. `output_func` keeps only what you need from each
run, here the number of mixed contacts at the end:

```@example start
ensemble = EnsembleProblem(prob; output_func = (sol, i) -> (mixed_contacts(sol.u[end]), false))
results = solve(ensemble, SequentialCPM(); trajectories = 4)
results.u
```

The runs use all the threads Julia was started with (`julia --threads=auto`). Replicate
`i` is reproducible on its own: it equals `solve(remake(prob; replica = i), SequentialCPM())`.

## What you learned

- A model is a `@potts_model` block: kinds, parameters, a lattice, energy terms and a sweep.
- `PottsProblem` compiles the model with an initial state; `solve` runs it.
- `record_potts` makes a video; `sol[:name]` reads any model quantity; `sol.u` holds the
  saved states.
- `remake` changes parameters cheaply; `EnsembleProblem` runs replicates.

Next, the [first tutorial](@ref tutorial-energies) looks at the energy in more detail.
