# [Tutorial 2: fields and chemotaxis](@id tutorial-chemotaxis)

This tutorial adds a chemical that cells sense and secrete. In Potts.jl a chemical is a
**field**: a value at every site that obeys a partial differential equation. You write the
equation as a ModelingToolkit `PDESystem` and couple it into the model. You will learn:

- how to write a field's reaction–diffusion equation as a `PDESystem`;
- how to couple it into a model with `@fields`, and bind its inputs to the cells;
- how to choose the field solver of a problem;
- how chemotaxis biases copy attempts, with `Chemotaxis` or a written-out `@drive`;
- how to make cells secrete, and how to plot and record a field.

The models on this page are generic teaching models, not published ones.

```@example chemo
using Potts, MakiePotts, CairoMakie
using Potts.Layouts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: laplacian, lattice_domain
CairoMakie.activate!(type = "png") # hide
nothing # hide
```

## A field with a source

The model below has one cell kind and a chemical `c`. The chemical is made in a strip at
the right edge of the lattice. It diffuses and decays. The lattice is closed in x and
periodic in y:

```math
\frac{\partial c}{\partial t} = D_c \nabla^2 c + s\,[x > 75] - k c
```

First write the field equation as a `PDESystem`. `t` is the time of the model, and
`x` and `y` are the coordinates of the lattice:

```@example chemo
t = Potts.t
Dt = Differential(t)
@parameters x y
@parameters Dc = 1.0 s = 0.1 k = 0.001     # diffusion, production in the strip, decay
@variables c(..) = 0.0
C = c(t, x, y)
strip = PDESystem([Dt(C) ~ Dc * laplacian(C) + s * (x > 75) - k * C], [],
    lattice_domain(t, (x, y), (80, 40)), [t, x, y], [C], [Dc, s, k]; name = :strip)
nothing # hide
```

Then couple it into the model with `@fields`:

```@example chemo
@potts_model Gradient begin
    @kinds medium cell
    @parameters begin
        λ = 2.0
        V₀ = 25.0
        T = 8.0
        J[kind, kind] = [0 10; 10 8]
        χ = 0.0          # chemotactic strength (off for now)
    end
    @lattice Lattice((80, 40); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy begin
        cells(cell) => λ * (volume - V₀)^2
        contacts => J[kind, neighbor_kind]
    end
    @fields c = strip
    @drive Chemotaxis(c; strength = χ)
    @sweep Metropolis(; temperature = T)
end
nothing # hide
```

New pieces:

- `@variables c(..) = 0.0` declares the field `c` with initial value 0. In the equation it
  is `c(t, x, y)`, a function of time and space.
- `Dt(C)` is the time derivative and `laplacian(C)` the lattice Laplacian. A comparison such as
  `x > 75` counts as 1 or 0. The coordinates are site centers, from 0 at the low face:
  site `i` has `x = i - 0.5`, so `x > 75` holds at sites 76 to 80.
- `lattice_domain(t, (x, y), (80, 40))` gives the domain of an 80 × 40 lattice. The domain
  of a coupled `PDESystem` must be the lattice's.
- `@fields c = strip` adds the fields, parameters and conditions of `strip` to the model.
  `Dc`, `s` and `k` become model parameters, and `c = ` names the field for the lines after
  it.
- `@drive Chemotaxis(c; strength = χ)` biases copies towards higher `c` (more below).
- The periodic `y` axis is the lattice's: every field takes the lattice's boundary.

The problem must say how to integrate the field. `ExplicitEuler(substeps = 8, lower_bound = 0.0)`
takes 8 explicit Euler time steps per MCS (Monte Carlo step). It clips negative values:

```@example chemo
@named gradient = Gradient()
start = layout(Scattered(12, (5, 5); region = (8:30, 1:40), kinds = [:cell], seed = 1), gradient)
prob = PottsProblem(gradient, start, (0, 1500); field_solver = ExplicitEuler(substeps = 8, lower_bound = 0.0), seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 25)
nothing # hide
```

`Scattered` places 12 cells at random in the left part of the lattice. With `χ = 0` the
cells only diffuse. `sol[:c]` gives the field at every saved time, as a matrix. Plot its
mean over y at the end of the run:

```@example chemo
c_end = sol[:c][end]
fig = Figure(size = (600, 300))
ax = Axis(fig[1, 1]; xlabel = "x", ylabel = "c (mean over y)")
lines!(ax, 1:80, vec(sum(c_end; dims = 2)) ./ 40)
fig
```

!!! note "How many substeps"
    An explicit time step is stable only if it is short enough for the diffusion
    coefficient and the reaction rate. Without `substeps`, `ExplicitEuler()` chooses the
    count itself from the current parameters. It takes the smallest `n` with
    ``\frac{\Delta t}{n}\left(D \sum_d 4/h_d^2 + k\right) \le 1.8``. Here ``k`` bounds
    the reaction's ``|\partial f/\partial c|`` (`k` for `- k * c`, also with a 0/1 input
    such as `- k * c * secreting`). The margin below the stability limit 2 damps
    lattice-scale noise.

    A number, as here, is a minimum: if the automatic count is larger, it wins. If the
    reaction is not linear in the field (`- k * c^2`), its rate is not counted and the
    problem warns. In that case, give `substeps` with room to spare. A field that blows up
    to huge positive and negative values is the sign of too few substeps.

## Chemotaxis

`Chemotaxis(c; strength = χ)` adds a term to the energy change ``\Delta H`` of a copy from
source site `source` into target site `target`:

```math
\Delta H_\text{chem} = -\chi\,\big(c(\text{target}) - c(\text{source})\big)
```

It adds this term only when the gaining cell is a cell, not the medium. So a cell that
extends up the gradient lowers its energy. Switch chemotaxis on with `remake`:

```@example chemo
prob_chemo = remake(prob; p = [:χ => 300.0])
sol_chemo = solve(prob_chemo, SequentialCPM(); saveat = 25)
record_potts("chemotaxis_gradient.mp4", sol_chemo; framerate = 12, title = "", figure = (; size = (600, 330)))
nothing # hide
```

```@raw html
<video src="../chemotaxis_gradient.mp4" controls autoplay loop muted playsinline width="600"></video>
```

The cells crawl towards the source at the right. The mean x-coordinate of their sites
shows it. `sol[:position]` is not needed, because the saved states hold the cell numbers:

```@example chemo
mean_x(u) = sum(x[1] for x in CartesianIndices(ownership(u)) if ownership(u)[x] != 0) / count(!=(0), ownership(u))
fig = Figure(size = (600, 300))
ax = Axis(fig[1, 1]; xlabel = "MCS", ylabel = "mean x of the cells")
lines!(ax, sol.t, mean_x.(sol.u); label = "χ = 0")
lines!(ax, sol_chemo.t, mean_x.(sol_chemo.u); label = "χ = 300")
axislegend(ax; position = :lt)
fig
```

### Writing the drive out

`Chemotaxis` is a one-liner for a `@drive` statement. A drive is a term added to
``\Delta H`` of a copy attempt. You write it with the names of the copy:

- `source` and `target`, the sites;
- `new`, the cell gaining the target;
- `old`, the cell losing it.

Print the model to see what `Chemotaxis(c; strength = χ)` expands to:

```@example chemo
gradient
```

The printout is Potts's internal form of the model. `LatticePDE.value_at(c(t), target(t))` is
the field at the target site, and `LatticePDE.value_at(J, kind(t), neighbor_kind(t))` is the
table entry. In the notation of `@potts_model` the drive line reads
`copy => ifelse(new != 0, -χ * (c[target] - c[source]), 0.0)`. Here is the same model
with that line in place of `Chemotaxis`:

```@example chemo
@potts_model GradientByHand begin
    @kinds medium cell
    @parameters begin
        λ = 2.0
        V₀ = 25.0
        T = 8.0
        J[kind, kind] = [0 10; 10 8]
        χ = 300.0
    end
    @lattice Lattice((80, 40); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy begin
        cells(cell) => λ * (volume - V₀)^2
        contacts => J[kind, neighbor_kind]
    end
    @fields c = strip
    @drive copy => ifelse(new != 0, -χ * (c[target] - c[source]), 0.0)
    @sweep Metropolis(; temperature = T)
end

@named by_hand = GradientByHand()
function short(sys)
    start = layout(Scattered(12, (5, 5); region = (8:30, 1:40), kinds = [:cell], seed = 1), sys)
    prob = PottsProblem(sys, start, (0, 100); field_solver = ExplicitEuler(substeps = 8, lower_bound = 0.0), seed = 1)
    return solve(remake(prob; p = [:χ => 300.0]), SequentialCPM(); save_everystep = false)
end
ownership(short(by_hand).u[end]) == ownership(short(gradient).u[end])
```

The result is `true`. With the same seed both runs make the same copies, so the drive is
the same. The written-out rule is open to change: for example, `kind[new] == leader`
would restrict it to one kind. `Chemotaxis` has keywords for the common variants:

- `kinds = (leader,)`;
- `when = old == 0` (extensions into the medium only);
- `response = saturating(s)` (``c/(s + c)``, a receptor that saturates).

## Cells that secrete

When the cells make the chemical themselves, chemotaxis pulls them together. Every site
owned by a cell now produces `c`. The `PDESystem` cannot see the cells. It reads an
**input field** instead, here `secreting`, a 0/1 value at every site:

```@example chemo
@parameters Dc = 1.0 s = 0.05 k = 0.005
@variables secreting(..)::Bool [input = true]
secretion = PDESystem([Dt(C) ~ Dc * laplacian(C) + s * secreting(t, x, y) - k * C], [],
    lattice_domain(t, (x, y), (80, 80)), [t, x, y], [C, secreting(t, x, y)], [Dc, s, k]; name = :secretion)
nothing # hide
```

`@fields` binds the input to an expression of the cells, `secreting => kind == cell`. Potts
fills it at every site once per MCS, before the field steps:

```@example chemo
@potts_model Aggregation begin
    @kinds medium cell
    @parameters begin
        λ = 2.0
        V₀ = 25.0
        T = 8.0
        J[kind, kind] = [0 10; 10 8]
        χ = 1000.0
    end
    @lattice Lattice((80, 80); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(cell) => λ * (volume - V₀)^2
        contacts => J[kind, neighbor_kind]
    end
    @fields c = secretion (secreting => kind == cell)
    @drive Chemotaxis(c; strength = χ)
    @sweep Metropolis(; temperature = T)
end

@named aggregation = Aggregation()
start = layout(Scattered(60, (5, 5); kinds = [:cell], seed = 1, gap = 2), aggregation)
prob = PottsProblem(aggregation, start, (0, 2000); field_solver = ExplicitEuler(substeps = 8, lower_bound = 0.0), seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 30)
nothing # hide
```

To show the field, follow these steps:

1. Attach the field to each frame as a **channel**.
2. Color the frame by that channel.
3. Draw the cells on top as a translucent fill, with an ordinary Makie `heatmap!` over
   the same axis. Cells are never outlined in these docs.

```@example chemo
key = SiteChannelKey(:c, Float64)
frames = [renderframe(u; mcs = t, channels = (RenderChannel(key, c; label = "c"),))
          for (u, t, c) in zip(sol.u, sol.t, sol[:c])]
cellfill(u) = [c != 0 ? 1.0 : NaN for c in Array(ownership(u))]      # cell sites; NaN is transparent
nx, ny = frame_size(frames[1])
ox, oy = frame_geometry(frames[1]).origin
k = Observable(1)
fig = Figure(size = (420, 420))
ax = Axis(fig[1, 1]; aspect = DataAspect())
hidedecorations!(ax)
pottsplot!(ax, @lift(frames[$k]); encoding = ChannelEncoding(key))
heatmap!(ax, ox .+ (0:nx), oy .+ (0:ny), @lift(cellfill(sol.u[$k])); colormap = [(:white, 0.35), (:white, 0.35)],
    colorrange = (0, 1), nan_color = :transparent)
record(fig, "chemotaxis_aggregation.mp4", eachindex(frames); framerate = 12) do i
    k[] = i
end
nothing # hide
```

```@raw html
<video src="../chemotaxis_aggregation.mp4" controls autoplay loop muted playsinline width="420"></video>
```

Cells that happen to be close raise the chemical between them. They pull each other into
clusters, and the clusters grow by collecting more cells.

!!! details "Advanced: other bindings and several fields"
    A binding takes any expression of the site:

    - `kind == cell` selects sites by owner kind;
    - `volume[owner]` reads the volume of the cell that owns the site (a numeric input,
      declared without `::Bool`);
    - a kind-indexed parameter gives each kind its own coefficient: bind a numeric input
      to the table, `dk => δ[kind]`, and write `- dk * c` in the equation for a decay per
      kind;
    - a fold over the neighbors, such as `any(kind[n] == cell for n in VonNeumann(1)(site))`.

    One `PDESystem` can hold several fields that read each other. `@fields c, u = sys (…)`
    names them all.

    Every field takes the problem's `field_solver` (default `ExplicitEuler()`, the
    automatic substep count). To give a field its own scheme, add an entry of
    `solvers = [:c => ExplicitEuler(...)]`. See
    [Equations and solvers](@ref manual-equations).

## What you learned

- A `PDESystem` on `lattice_domain(…)` gives a field's PDE with `laplacian`.
- `@fields c = sys (input => expression)` couples it into a model and binds its inputs to
  the cells.
- `PottsProblem(…; field_solver = ExplicitEuler(substeps = n, lower_bound = 0.0))` integrates it.
- `Chemotaxis(c; strength)` or `@drive copy => …` biases copies along the field.
- Fields can be recorded as videos through render-frame channels.

**See also:** the published vasculogenesis model [`Merks2006`](@ref model-merks), in which endothelial cells secrete a chemoattractant and form networks.

Next, [Tutorial 3](@ref tutorial-growth) makes cells grow, divide and die.
