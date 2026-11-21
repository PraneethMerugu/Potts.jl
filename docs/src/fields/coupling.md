# [Coupling to a Potts model](@id fields-coupling)

A `PDESystem` from the pages before joins a Potts model with no change to its equations.
This page lists what changes when it does, and where each step is shown.

## What changes

- **The inputs.** An input such as `src(t, x, y)` is bound to the cells: a kind, a cell
  variable or a site variable. The model fills it again from the CPM state at every MCS.
- **The window.** The model steps the fields once per MCS, in its place in the sweep. The
  window is the MCS, so `dt` is not given; `mcs_duration` in `@sweep` sets its length.
- **The algorithm.** `PottsProblem(…; field_solver)` takes the field algorithms of this
  section ([Solvers](@ref fields-solvers)). `FieldGroups` gives each group its own.
- **The lattice.** The model's `@lattice` sets the grid, its spacing and its boundary.
  A field condition overrides the lattice boundary for that field
  ([Boundary conditions](@ref fields-boundaries)).

## Where it is shown

1. Couple a field to cells with `@fields`, then let the cells follow its gradient:
   [Tutorial 2: fields and chemotaxis](@ref tutorial-chemotaxis).
2. Write the coupled equations, their bindings and the solver keywords:
   [Equations and solvers](@ref manual-equations).
3. Couple a `PDESystem` as a function with `Potts.couple`, and solve the fields of a model
   with OrdinaryDiffEq: [The SciML path](@ref manual-sciml-path).
4. Give the fields of a model another discretization with `PottsProblem(…; discretization)`:
   [The fields under another discretization](@ref mtk-discretization).

`Potts.fields(model)` returns the fields of a model as a plain `PDESystem`, with each
binding written in as its CPM input. Every page of this section applies to it.
