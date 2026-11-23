# [Kinds: `@kinds`](@id manual-kinds)

`@kinds` lists the cell kinds (cell types) of a model, for example
`@kinds medium dark light wall[frozen]`.

- The **first kind is the medium**: the space around the cells, owner number 0. It has no
  volume or cell state.
- Inside the model each kind name is its number: `medium` is 0, `dark` 1, `light` 2, … So
  `kind == dark` tests a kind, and `cells(dark, light)` selects kinds.
- Kind-indexed tables (`J[kind, kind]`, `V₀[kind]`) are indexed in this order, medium
  first. Write their entries by kind name, `J[dark, light] = 11`, so that the order does
  not matter (see [Tables by kind name](@ref manual-parameters)).
- In operating points, kinds are given by name (`kind => [:dark, :light]`) or number
  (`kind => [1, 2]`). Saved states store numbers (`sol[:kind]`); `kind_names` reads them
  as names (below).

## Kinds in results

`sol[:kind]` gives the kind number of every cell, one vector per saved state, as for every
cell variable. [`kind_names`](@ref) gives the names: `kind_names(sol)` is the list of
kinds in number order, medium first, and `kind_names(sol, k)` names the kind numbers `k`
(a number, an array, or an array of arrays such as `sol[:kind]`):

```julia
kind_names(sol)                   # [:medium, :dark, :light]
kind_names(sol, sol[:kind][end])  # [:dark, :light, :dark, …]
count(==(:dark), kind_names(sol, sol[:kind][end]))
```

`kind_names` takes a model, a compiled model, a problem, an integrator or a solution. For a
categorical vector, with every kind as a level even when no cell has it, use
CategoricalArrays:

```julia
using CategoricalArrays
categorical(kind_names(sol, sol[:kind][end]); levels = kind_names(sol))
```

## Kind classes

A line `name = (kind, …)` in `@kinds` names a set of kinds, a *kind class*. A class may list
kinds and earlier classes (flattened in order), may sit anywhere among the kinds, and does
not change kind numbers:

```julia
@kinds begin
    medium
    fluid
    matrix
    ecm = (fluid, matrix)
    tip
    stalk
    endothelial = (tip, stalk)
    sprouting = (endothelial, matrix)    # (tip, stalk, matrix)
end
```

The one-line form works too: `@kinds medium fluid matrix tip stalk endothelial = (tip, stalk)`.

A class goes wherever a list of kinds does, alone or mixed with kinds:

```julia
@energy begin
    cells(endothelial) => 2.0 * (volume - 16)^2
    Surface(ecm; target = 40.0, strength = 0.1)
    contacts => J[kind, neighbor_kind] + 3.0 * (kind ∈ endothelial) * (neighbor_kind ∈ ecm)
end
@drive Chemotaxis(V; strength = 1.5, kinds = endothelial)
@constraint connectivity(endothelial)
@observed n_ec ~ count(true for c in cells(endothelial))
@divide cells(endothelial) when = volume >= 30
```

`kind[x] ∈ g` tests membership of a symbolic kind (`kind`, `neighbor_kind`, `kind[new]`,
`kind[old]`, `kind[c]`, `kind[n]`), and `kind[x] ∉ g` its negation. In `@equations` (cell
and model equations, which are ModelingToolkit equations) and in a binding of `@fields`, write
the term `ismember(kind, g)` instead; there `∈` is an error that shows this form, because
ModelingToolkit gives `∈` another meaning (`kind ∈ Set(…)` is `false` before any term exists). It is the same as
writing the comparisons out, `(kind[x] == tip) || (kind[x] == stalk)`: the generated code
compares against constant kind numbers, allocates nothing and runs on every backend. A model
written with classes is the same model, with the same generated code, as one with the
comparisons spelled out.

Some things a class is not:

- **Not a kind.** A cell has one kind, so operating points and layouts take kinds
  (`kind => [:tip, :stalk]`, `Tiling(…; kinds = [:tip])`, `InsertUntil(:tip; into =
  [:stalk])`), never a class name. `kind == endothelial` is an error too: write
  `kind ∈ endothelial`.
- **Not an index.** Kind tables are indexed by kind (`J[kind, neighbor_kind]`); `J[endothelial,
  neighbor_kind]` is an error. Gate the term instead: `J[kind, neighbor_kind] * (kind ∈ endothelial)`.
- **Not the medium.** The medium is not a cell kind and cannot be a member; write
  `kind[x] == medium || kind[x] ∈ g`.

An empty class, a kind listed twice (also through a nested class), a member that is not a
kind or an earlier class, and a class named like another declaration are errors when the
model is built. A model extending another (`@extend endothelial = base = Base()`) can use the
base's classes; it may restate a base class with the same members in the same order, but not otherwise.
Classes are stored on the model as [`Potts.KindClass`](@ref) values.

## Frozen kinds

A kind marked `[frozen]` never moves: its sites never change owner and never copy into
neighbors. Use it for walls, obstacles and substrates. The medium cannot be frozen.

```@example kinds
using Potts, MakiePotts, CairoMakie
using Potts.Layouts
CairoMakie.activate!(type = "png") # hide

@potts_model Obstacles begin
    @kinds medium cell pillar[frozen]
    @parameters J[kind, kind] = [0 12 20; 12 6 20; 20 20 0]
    @lattice Lattice((50, 50); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        Adhesion(J)
    end
    @sweep Metropolis(; temperature = 10.0)
end

@named obstacles = Obstacles()
op = layout(overlay(Tiling((5, 5); spacing = 2, kinds = [:cell]),
                    Tiling((4, 4); spacing = 10, region = (5:46, 5:46), kinds = [:pillar])), obstacles)
sol = solve(PottsProblem(obstacles, op, (0, 100); seed = 1), SequentialCPM(); save_everystep = false)
fig = Figure(size = (320, 320))
ax = Axis(fig[1, 1]; aspect = DataAspect())
hidedecorations!(ax)
pottsplot!(ax, renderframe(sol))
fig
```

`renderframe(sol)` draws the last state with frozen sites as obstacles. Whether a site is
frozen follows its owner's kind: a cell whose kind changes to a frozen kind (by a
callback, say) stops moving from the next MCS.
