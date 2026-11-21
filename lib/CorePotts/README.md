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

Documentation: the [Potts.jl docs](../../docs/src/index.md), in particular
[Problems, solvers and solutions](../../docs/src/manual/problems.md). Build them as the
[root README](../../README.md) shows.
