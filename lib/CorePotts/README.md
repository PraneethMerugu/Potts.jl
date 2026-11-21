# CorePotts

CorePotts is the numerical layer of Potts.jl: lattices, the cellular Potts state,
`SequentialCPM` and `CheckerboardCPM`, problems, integrators, solutions, ensembles,
callbacks, checkpoints and the GPU kernels. Potts generates the functions that CorePotts
runs; models are written with Potts' `@potts_model`. Potts re-exports CorePotts.

```julia
using CorePotts

u = CPMState(Int32[0 1; 1 2], (kind = Int32[1, 2], volume = [2, 1]))
ownership(u)   # the cell number of each site; 0 is the medium
volumes(u)     # [2, 1]
```

Documentation: the Potts.jl docs, in particular the page "Problems, solvers and solutions"
of the Manual. The docs are not hosted yet: build them with
`julia --project=docs docs/make.jl` from the repository root, then open
`docs/build/index.html`.
