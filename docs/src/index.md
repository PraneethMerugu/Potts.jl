# Potts.jl

Potts.jl simulates **cellular Potts models** (CPMs), also called Glazier–Graner–Hogeweg
models. You write a model as equations: the energy (the Hamiltonian) of a tissue, the
fields and ODEs inside and around cells, and the rules for growth, division and links. The
compiler derives everything else, including the energy change of every copy attempt, and
generates fast code for the CPU or a GPU.

Potts.jl follows the conventions of [SciML](https://sciml.ai) and
[ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/). If you have used
`ODEProblem` and `solve`, you already know the workflow. What Potts.jl takes from ModelingToolkit, and
what it does itself, is set out in [Relation to ModelingToolkit](@ref modelingtoolkit).

## The workflow at a glance

| Step | SciML / ModelingToolkit | Potts.jl |
|---|---|---|
| Write a model | `@mtkmodel`, `System` | [`@potts_model`](@ref) |
| Give initial conditions | `[x => 1.0]` operating point | `[ownership => σ, kind => kinds]`, or a [layout](@ref tutorial-layouts) |
| Build a problem | `ODEProblem(sys, op, tspan)` | `PottsProblem(sys, op, (0, 1000))` |
| Choose a solver | `Tsit5()` | `SequentialCPM()` (CPU) or `CheckerboardCPM()` (CPU or GPU) |
| Solve | `solve(prob, alg)` | `solve(prob, SequentialCPM())` |
| Read results | `sol[x]`, `sol(t)` | `sol[:volume]`, `sol[:c]`, `sol.u[end]` |
| Change parameters | `remake(prob; p = [k => 2.0])` | `remake(prob; p = [:T => 5.0])` (no recompilation) |
| Many runs | `EnsembleProblem` | `EnsembleProblem` (one compiled model, independent random streams) |

Time is counted in **Monte Carlo steps** (MCS): one MCS is one copy attempt per lattice site.

## Installation

Potts.jl needs [Julia 1.12](https://julialang.org/downloads/) or later. The packages are
not registered yet, so you install them from a clone of the repository. In a terminal:

```
git clone https://github.com/PraneethMerugu/Potts.jl
```

Then start Julia in the same folder and run:

```
using Pkg
Pkg.develop([PackageSpec(path = "Potts.jl/lib/CorePotts"), PackageSpec(path = "Potts.jl"),
             PackageSpec(path = "Potts.jl/lib/PottsModels"), PackageSpec(path = "Potts.jl/lib/MakiePotts")])
Pkg.add("CairoMakie")
```

The repository holds four packages:

| Package | What it is |
|---|---|
| **Potts** | The modelling language: `@potts_model`, `PottsProblem`, layouts, components. It re-exports CorePotts. |
| **CorePotts** | The numerical layer: lattices, solvers, solutions, ensembles, callbacks, GPU kernels. |
| **PottsModels** | Published models as ordinary `@potts_model` constructors. |
| **MakiePotts** | Plotting of states and solutions with [Makie](https://docs.makie.org). |

## A complete example

Two kinds of cells, dark and light, start mixed in an aggregate. Dark cells stick to each
other more strongly than light cells do, so the aggregate sorts: dark cells gather in the
middle and light cells surround them. This is the model of Graner & Glazier (1992), written
out with the paper's parameters (it is the same model as the shipped constructor
`GranerGlazier`), started from the paper's aggregate of 64 cells:

```@example home
using Potts, PottsModels, MakiePotts, CairoMakie

@potts_model CellSorting begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0                                          # area constraint strength
        V₀ = 40.0                                        # target area
        T = 10.0                                         # temperature
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]     # contact energies
    end
    @lattice Lattice((72, 72); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)                       # copy from any of the 8 neighbours
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end

@named sorting = CellSorting()
σ0, kinds0 = graner_glazier_state()                      # the paper's 64-cell aggregate
prob = PottsProblem(sorting, [ownership => σ0, kind => kinds0], (0, 3200); seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 50)
record_potts("home_sorting.mp4", sol; framerate = 12, title = "", figure = (; size = (420, 420)))
nothing # hide
```

```@raw html
<video src="home_sorting.mp4" controls autoplay loop muted playsinline width="420"></video>
```

The run covers 3200 MCS. The paper counts 16 copy attempts per site as one MCS, so this is
200 of the paper's MCS (the paper follows sorting to 10⁴). [Getting started](@ref
getting-started) explains every line of this example. The full run of the paper, to 10⁴
of its MCS:

```@example home
Main.paper_run("graner_glazier", "") # hide
```

## Where to go next

- **New to cellular Potts models or to Julia?** Start with [Getting started](@ref getting-started).
- **Learning to build models?** Follow the [Tutorials](@ref tutorial-energies) in order, then
  try the [Workshop](@ref workshop) exercises.
- **Looking something up?** The [Manual](@ref manual-models) has one page per part of the
  model language, and the [API](@ref api) lists every exported function.
- **Using ModelingToolkit already?** [Relation to ModelingToolkit](@ref modelingtoolkit)
  says which parts of a model are ModelingToolkit systems and which are Potts' own.
- **Coming from CompuCell3D or Morpheus?** See the [translation tables](@ref coming-from).
- **Want a published model?** The [Models](@ref models) section builds five published
  models step by step, each with a video of a full paper-scale run.

## Citing

A paper describing Potts.jl is in preparation. Until it is out, please cite the software:

```
@software{potts_jl,
  author = {Merugu, Praneeth},
  title  = {Potts.jl: cellular Potts models as equations},
  url    = {https://github.com/PraneethMerugu/Potts.jl},
  year   = {2026}
}
```

Please also cite the papers of the models you use. The cellular Potts model itself is due
to F. Graner and J. A. Glazier, *Phys. Rev. Lett.* **69**, 2013 (1992),
doi:[10.1103/PhysRevLett.69.2013](https://doi.org/10.1103/PhysRevLett.69.2013). Each
published model's docstring and model page give its references.
