# LatticePDE

LatticePDE puts a ModelingToolkit `PDESystem` on a lattice and solves it with SciML's
`solve`. `discretize` returns an ordinary `ODEProblem` (rates) or `DiscreteProblem` (maps).
The lattice's own field algorithms step it, and so does any OrdinaryDiffEq solver, on the
CPU or a GPU. Potts.jl uses it for the fields of a cellular Potts model.

```julia
using ModelingToolkitBase, LatticePDE
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y Dc = 1.0 k = 0.1
@variables c(..)
eq = D(c(t, x, y)) ~ Dc * laplacian(c(t, x, y)) - k * c(t, x, y)
ic = [c(0, x, y) ~ exp(-((x - 32)^2 + (y - 32)^2) / 20)]
dom = lattice_domain(t, (x, y), (64, 64); tspan = (0.0, 20.0))
@named spot = PDESystem(eq, ic, dom, [t, x, y], [c(t, x, y)], [Dc, k])

prob = discretize(spot, LatticeDiscretization(Grid((64, 64))))
sol = solve(prob, ExplicitEuler(); dt = 1.0, saveat = 1.0)
sum(sol[c][end])   # 8.3327...
```

Documentation: the "Fields (LatticePDE)" section of the Potts.jl docs, starting at its
"Getting started" page. The docs are not hosted yet: build them with
`julia --project=docs docs/make.jl` from the repository root, then open
`docs/build/index.html`.
