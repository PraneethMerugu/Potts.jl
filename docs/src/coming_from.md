# [Coming from CompuCell3D or Morpheus](@id coming-from)

If you have models in CompuCell3D (CC3D) or Morpheus, most of their parts have a one-line
counterpart in Potts.jl. This page lists the translations that work today. Features that
are not available yet are on the [Roadmap](@ref roadmap).

## Conventions that carry over

| Topic | Potts.jl |
|---|---|
| Neighbour orders | `NeighborOrder(k)` gives CC3D's cumulative distance shells (2D: 4, 8, 12, 20, … neighbours) |
| Contact energies | each pair of neighbouring sites is counted **once**, as in CC3D and Morpheus. Contact energies `J` convert 1:1 at the same neighbour order. Exception: Morpheus divides by its `boundaryLengthScaling`; divide a Morpheus `J` by it |
| Copy proposals | a uniform random target site and a uniform random neighbour as source, in the proposal relation (`@relations proposal = …`) |
| Monte Carlo step | one MCS is one attempt per site. A model that counts `n` attempts per site as a step needs `n` of our MCS per step |
| Acceptance | Metropolis; at `T = 0` ties are accepted with probability ½ (CC3D) |
| Temperature per kind | `temperature = Tk[kind]`, combined over source and target cells with `combine` (default `min`); the medium never contributes |

## CompuCell3D

| CC3D | Potts.jl |
|---|---|
| `<Potts>` `Dimensions`, `Boundary_x` | `@lattice Lattice((nx, ny); boundary = (Periodic(), Closed()))` |
| `<Potts>` `NeighborOrder` | `@lattice Lattice(…; neighborhood = NeighborOrder(k))` for contacts, `@relations proposal = NeighborOrder(k)` for copies |
| `<Potts>` `Temperature` / `FluctuationAmplitude` | `@sweep Metropolis(; temperature = T)`; per type `temperature = Tk[kind]`; see the note below |
| `<Potts>` `Offset` | `@sweep Metropolis(; temperature = T, offset = δ)` |
| `<Potts>` `Steps` | the time span of `PottsProblem(sys, op, (0, steps))` |
| `<Plugin Name="CellType">`, `Freeze` | `@kinds medium a b wall[frozen]` |
| `<Plugin Name="Volume">` `TargetVolume`, `LambdaVolume` | `cells(k) => λ * (volume - V₀)^2`, or per type `V₀[kind]` |
| `<Plugin Name="Surface">` | `cells(k) => λₛ * (surface - S₀)^2` |
| `<Plugin Name="Contact">` `Energy Type1 Type2` | `contacts => J[kind, kind′]` with `J[kind, kind]` |
| `<Plugin Name="ContactInternal">`, compartments | `contacts => ifelse(cluster[owner] == cluster[owner′], Jint, J[kind, kind′])`, `cluster =>` in the operating point |
| `<Plugin Name="Connectivity">` | `@constraint connectivity(k)` |
| `<Plugin Name="LengthConstraint">` (2D) | `cells(k) => λL * (major_length - L)^2` |
| `<Plugin Name="Chemotaxis">` `Lambda`, `SaturationCoef` | `@drive Chemotaxis(c; strength = λ, response = saturating(s), kinds = (k,))` |
| `ChemotactTowards` (only into medium) | `Chemotaxis(c; strength = λ, when = old == 0)` |
| `<Plugin Name="FocalPointPlasticity">` | `@relationship fpp(cell, cell) capacity = n`, `edges(fpp) => λ * (distance - L)^2`, `@link` / `@unlink` |
| `<Steppable Type="DiffusionSolverFE">` | `c(field)`, `@equations D(c) ~ Dc * Δ(c) - δ * c + …`, `field_solver = ExplicitEuler(substeps = n)` |
| `SecretionData` (inside cells of a type) | `+ s * (kind == k)` in the field equation |
| `UniformInitializer`, `BlobInitializer` | `Tiling`, `Scattered`, or your own layer (see [layouts](@ref tutorial-layouts)) |
| PIF initializer / PIF dumper | `read_piff`, `write_piff` |
| `MitosisSteppable` (`divide_cell_random_orientation`, along major/minor axis) | `@divide cells(k) when = …, along = RandomPlane()` / `major_axis()` / `principal_axis()` |
| Python steppable updating `cell.dict` | a cell variable `x(cell)` and `@after_mcs x ~ …` |
| Python steppable changing `targetVolume` | `V_target(cell)` in the volume term, updated in `@after_mcs` |
| Steppable `frequency` | `@after_mcs Every(n) …`, `@divide cells(k) Every(n) …` |
| SBML / RoadRunner ODEs per cell | a ModelingToolkit `System` in `@components cells(k) name = sys` |
| `stop_simulation` | `DiscreteCallback(cond, terminate!)` |
| Parameter scans | `remake` and `EnsembleProblem` |

**Temperature in detail.** See [Sweep](@ref manual-sweep) for runnable examples.

- `FluctuationAmplitudeFunctionName` `Min` / `Max` / `ArithmeticAverage` is
  `combine = min` / `max` / `amean`, with `amean(a, b) = (a + b) / 2` defined at the top
  level (`combine` must be a named function or a callable struct, not `(a, b) -> …`; see
  [Sweep](@ref manual-sweep)). `combine` receives two numbers, so
  `mean` from Statistics does not work (it expects a collection). As in CC3D, the medium
  never contributes: a copy between a cell and the medium uses the cell's value.
- A per-cell `fluctAmpl`, where −1 means "use the type's value", is a cell variable:
  `temperature = ifelse(T_cell >= 0, T_cell, Tk[kind])`.
- `Anneal = n` (the temperature set to 0 for `n` more MCS after `Steps`) is a second solve
  at ``T = 0``, `remake(prob; u0 = sol.u[end], tspan = (steps, steps + n), p = [:T => 0.0])`,
  or a [callback](@ref manual-callbacks) that sets `integ.ps[:T] = 0.0` at `t == steps`.
- The default temperature is 0 in CC3D XML but 10 in PyCoreSpecs. Check which one the model
  relied on.

## Morpheus

| Morpheus | Potts.jl |
|---|---|
| `Lattice class="square"/"hexagonal"/"cubic"`, `Size`, `BoundaryConditions` | `@lattice Lattice(dims; geometry = Hexagonal(), boundary = …)` |
| `Neighborhood Order` (contacts, `ShapeSurface`) | `neighborhood = NeighborOrder(k)`; on hexagonal lattices order 2 is `NeighborOrder(2)` (12 neighbours) |
| `Domain` (circle, image) | `@lattice Lattice(…; domain = x -> …)` or a `Bool` mask |
| `CellType class="biological"` / `"medium"` | `@kinds medium a b`; the medium comes first |
| `VolumeConstraint target strength` | `cells(k) => strength * (volume - target)^2` |
| `SurfaceConstraint mode="surface"` | `cells(k) => strength * (surface - target)^2` |
| `CPM Interaction Contact type1 type2 value` | `contacts => J[kind, kind′]` (divide by `boundaryLengthScaling`) |
| `MetropolisKinetics temperature` | `@sweep Metropolis(; temperature = T)` |
| `MetropolisKinetics yield = Y` | `@sweep Metropolis(; temperature = T, offset = -Y)` |
| `MonteCarloSampler MCSDuration` | `@sweep Metropolis(; …, mcs_duration = Δt)` |
| `MCS Neighborhood` (copy neighbourhood) | `@relations proposal = …` |
| `Property` (cell scope) | `@variables x(cell) = x₀` |
| `Field` with `Diffusion rate` | `c(field)` with `D(c) ~ rate * Δ(c) + …` |
| `System` with `DiffEqn` (cell scope) | `@equations D(x) ~ …` for a cell variable, or a `System` in `@components` |
| `System` with `Rule` / `Equation` | `@after_mcs x ~ …` |
| `Event` with `Condition` | an `ifelse` in an update, or a `DiscreteCallback` |
| `Chemotaxis field strength` | `@drive Chemotaxis(c; strength = …)` |
| `Chemotaxis` with `saturation` | `Chemotaxis(c; strength, response = saturating_linear(s))` |
| `Protrusion` (Act model) | a site variable with `@on_copy`, `@after_mcs` and a geometric-mean drive (see [Drives](@ref manual-drive) and `WortelAct`) |
| `Haptotaxis` | `@drive copy => -μ * (a[target] - a[source])` for a site variable `a` |
| `CellDivision Condition, division-plane` | `@divide cells(k) when = …, along = …` |
| `ConnectivityConstraint` | `@constraint connectivity(k)` |
| `FreezeMotion` | a `[frozen]` kind, or a constraint on `kind[old]` |
| `MechanicalLink` | `@relationship` with `edges(…)`, `@link`, `@unlink` |
| `InitRectangle`, `InitCircle` (random) | `Tiling`, `Scattered`, `InsertUntil` |
| `rand_uni(a, b)` in rules | `a + (b - a) * rand()` |
| `ParamSweep` | `remake` and `EnsembleProblem` |
| `Logger`, `Gnuplotter` | `sol[:x]`, `saveat`, MakiePotts |
