# LatticeFields

LatticeFields is the field compiler under LatticePDE. It lowers lattice field programs to
KernelAbstractions kernels, fuses them into launches, and steps them with explicit and
implicit field solvers, multigrid and Krylov linear solvers, and Newton iterations. Its
names are public but not exported: most users reach it through LatticePDE, which re-exports
the field algorithms and the linear solvers.

```julia
using ModelingToolkitBase, LatticePDE
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y Dc = 50.0 k = 1.0
@variables c(..)
dom = lattice_domain(t, (x, y), (64, 64); tspan = (0.0, 2.0))
@named stiff = PDESystem(D(c(t, x, y)) ~ Dc * laplacian(c(t, x, y)) - k * c(t, x, y),
    [c(0, x, y) ~ 1.0], dom, [t, x, y], [c(t, x, y)], [Dc, k])
prob = discretize(stiff, LatticeDiscretization(Grid((64, 64))))

# BackwardEuler and LatticePCG are LatticeFields objects
sol = solve(prob, BackwardEuler(; linsolve = LatticePCG()); dt = 0.5)
```

Documentation: the "Developer reference" page of the "Fields (LatticePDE)" section of
the Potts.jl docs, and its "How it works" page for the pipeline.
The docs are not hosted yet: build them with `julia --project=docs docs/make.jl` from
the repository root, then open `docs/build/index.html`.
