# PottsModels

PottsModels holds published cellular Potts models as ordinary `@potts_model` constructors,
with their initial states, analysis functions (`PottsModels.Analysis`) and reproductions of
the papers' figures.

```julia
using Potts, PottsModels

σ0, k0 = graner_glazier_state()                      # a 64-cell aggregate of two kinds
gg = GranerGlazier(; name = :gg, lattice = size(σ0)) # Graner & Glazier (1992) cell sorting
prob = PottsProblem(gg, [ownership => σ0, kind => k0], (0, 200); seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 2)
```

Documentation: the "Paper models" section of the Potts.jl docs, one page per model.
The docs are not hosted yet: build them with `julia --project=docs docs/make.jl` from
the repository root, then open `docs/build/index.html`.
