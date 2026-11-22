# [Observables: `@observed` and measurements](@id manual-observables)

## Observed quantities

`@observed name ~ expression` defines a derived quantity. It is computed when you ask for
it, from the saved states, so it costs nothing during the run. `name(cell) ~ …` makes the
scope explicit; otherwise it follows from the expression (a cell expression gives one value
per cell, a fold over cells one number).

```@example observables
using Potts
using Potts.Layouts

@potts_model Census begin
    @kinds medium dark light
    @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = 25.0, strength = 1.0)
        contacts => J[kind, neighbor_kind]
    end
    @observed begin
        ndark ~ count(true for c in cells(dark))
        mean_volume ~ mean(volume for c in cells)
        dark_area ~ sum(volume for c in cells(dark))
        oversized(cell) ~ volume > 25
    end
    @sweep Metropolis(; temperature = 10.0)
end

@named census = Census()
op = layout(Tiling((5, 5); region = (11:30, 11:30), kinds = [:dark, :light]), census)
prob = PottsProblem(census, op, (0, 50); seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 25)
(ndark = sol[:ndark], mean_volume = sol[:mean_volume], dark_area = sol[:dark_area],
 oversized = count(sol[:oversized][end]))
```

Observed quantities can use each other, the built-ins and the model's variables and
parameters. `observe(prob, x)` evaluates a quantity on the initial state, and
`observe(sol, x)` on every saved state. `x` can be the quantity itself or its name as a
`Symbol`, such as `observe(sol, :ndark)`.

## Energy

`total_energy(prob, u)` is ``H`` of a state `u` (by default the initial state). It is a
useful summary of relaxation, and a check of a model: Potts derives ``\Delta H`` from the
same terms, and the test suite verifies that they agree.

```@example observables
total_energy.(Ref(prob), sol.u)
```

## Analysis helpers

`PottsModels.Analysis` has plain-Julia functions for saved states: `centroids(σ)` of every
cell (`periodic = (true, …)` takes each cell's minimum image on periodic axes), the cell
adjacency graph `cell_graph(σ)` with `components` and `reachable`, profile helpers
`column_tops` and `trapezoid_integral`, peak finding (`find_peaks`, `peak_prominences`, `peak_widths`),
and chains of cells along a periodic axis with their relaxation curves (`chain_centroids`,
`chain_width`, `crossing_time`, `relaxation_mse`). See the [API](@ref api).

Morphology helpers work on masks, such as `σ .> 0` or the sites of one kind:

| Function | Returns |
|---|---|
| `skeletonize(mask)` | the skeleton of a 2D mask (Zhang–Suen thinning, then a pass that removes 2 × 2 blocks); its lines end about half a width short of each tip |
| `skeleton_counts(skel; min_length)` | the tips, junctions, branches (tip-to-junction edges of at least `min_length`, measured on the skeleton) and loops (independent cycles) of a skeleton; `skeleton_graph` has the nodes and edges |
| `spanning_cluster(f, σ; axis, adjacency, periodic)`, `percolates` | the sites of the clusters where `f` holds that reach both ends of `axis` |
| `pair_graph(pred, n)` | the graph of a pairwise predicate on items `1:n`; `components` of it are the clusters under its transitive closure |
| `sprout_length(mask; axis, from)`, `width_profile`, `sprout_thickness` | how far a mask reaches past a base slice, and its mean width per slice |
| `lineage(records)`, `clone_sizes` | the lineage forest of `child => parent` birth records, with each cell's founder and depth |

To record births, copy the parent's built-in serial `birth` into a cell variable at
division (`@variables mother(cell) = 0.0` and the rule `mother => birth`). The rule sets
the value in both daughters, so the parent, which keeps its `birth`, then holds the self
record `birth => birth`. Read `sol[:birth][k][c] => sol[:mother][k][c]` for the living
cells of every saved state, drop the self records, and map `mother = 0` to `nothing`.
Save at least at every MCS where the rule can fire, so that each cell is saved before its
first division. The `lineage` docstring in the [API](@ref api) has the full loop. For clone sizes alone,
a founder label in a cell variable is enough, because daughters copy it.

```@example observables
using PottsModels.Analysis: skeletonize, skeleton_counts, percolates
mask = ownership(sol.u[end]) .> 0
skeleton_counts(skeletonize(mask)), percolates(mask; axis = 1)
```

```@example observables
using PottsModels.Analysis: centroids, cell_graph, components
σ = ownership(sol.u[end])
g = cell_graph(σ)
length(centroids(σ)), length(components(g, findall(==(1), sol[:kind][end])))   # dark cells' clusters
```
