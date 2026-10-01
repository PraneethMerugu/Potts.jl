# Potts.jl

Cellular Potts models written as equations, in the style of ModelingToolkit, and solved with
SciML-style problems, solvers and solutions, on the CPU or a GPU.

```julia
using Potts, PottsModels, MakiePotts, CairoMakie

σ0, k0 = graner_glazier_state()                      # a 64-cell aggregate of two kinds
gg = GranerGlazier(; name = :gg, lattice = size(σ0)) # Graner & Glazier (1992) cell sorting
prob = PottsProblem(gg, [ownership => σ0, kind => k0], (0, 200); seed = 1)
sol = solve(prob, SequentialCPM())
pottsplot(renderframe(sol.u[end]))                    # the sorted aggregate
```

This repository holds four Julia packages:

| Package | Path | What it is |
|---|---|---|
| **Potts** | `/` | The modelling language: `@potts_model`, `PottsProblem`, layouts, components |
| **CorePotts** | `lib/CorePotts` | The numerical layer: lattices, `SequentialCPM` and `CheckerboardCPM`, solutions, ensembles, callbacks, GPU kernels |
| **PottsModels** | `lib/PottsModels` | Published models as ordinary `@potts_model` constructors, with reproductions |
| **MakiePotts** | `lib/MakiePotts` | Plotting of states and solutions with Makie |

## Install

The packages are not registered yet. With Julia 1.12:

```bash
git clone https://github.com/PraneethMerugu/Potts.jl
```

```julia
using Pkg
Pkg.develop([PackageSpec(path = "Potts.jl/lib/CorePotts"), PackageSpec(path = "Potts.jl"),
             PackageSpec(path = "Potts.jl/lib/PottsModels"), PackageSpec(path = "Potts.jl/lib/MakiePotts")])
```

GPU runs use any KernelAbstractions backend (Metal is tested): load the backend package and
pass `backend = MetalBackend()` to `solve`.

## Documentation

Build the documentation locally:

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

and open `docs/build/index.html`. It covers getting started, tutorials, the modelling
language, and the published models, each reproduced from its public constructor.

## History

This repository replaces the earlier CorePotts.jl, MakiePotts.jl and PottsModels.jl
repositories (now archived) and the previous contents of this one. Their histories stay
reachable: the old `main` is an ancestor of this branch, and every earlier branch is kept as
an `archive/*` or `legacy/*` tag in its repository.
