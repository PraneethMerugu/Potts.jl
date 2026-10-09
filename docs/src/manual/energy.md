# [Energy: `@energy`](@id manual-energy)

`@energy` declares the terms of the Hamiltonian ``H``. Each term is `domain => expression`.
The domain fixes what is summed over and which names the expression may use. Potts derives
the energy change ``\Delta H`` of every copy from these terms; you never write ``\Delta H``.

| Domain | Sum over | Names in scope |
|---|---|---|
| `cells(k₁, k₂, …)`, `cells` | every live cell of those kinds (all kinds) | `volume`, `surface`, `major_length`, `kind`, `id`, cell variables (`x`, or `x[c]`) |
| `contacts`, `contacts(rel)` | every unordered pair of neighbouring sites with different owners, once | `kind`, `kind′`, `owner`, `owner′`, `weight`; site and field variables as `x` and `x′`; cell variables of both sides as `y[owner]`, `y[owner′]` |
| `sites` | every lattice site | `kind`, `owner`, `position`, site and field variables |
| `edges(rel)` | every link of a relationship | `a`, `b`, `distance`, edge variables |
| `clusters(k…)` | every compartment cluster whose root cell is of kind `k` | `cluster_volume`, `cluster_surface` |

```@example energy
using Potts

@potts_model AllTerms begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 25.0
        λₛ = 0.05
        S₀ = 60.0
        λL = 0.5
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
        μ = 0.01
    end
    @variables cue(site) = 0.0
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2                  # area
        cells(dark) => λₛ * (surface - S₀)^2                       # perimeter, dark cells only
        cells(light) => λL * (major_length - 8.0)^2                # elongation of light cells
        contacts => J[kind, kind′] + 2.0 * (cue + cue′) / 2        # adhesion, modulated by a site cue
        sites => μ * position[1] * (kind == dark)                  # an external potential on dark cells
    end
    @sweep Metropolis(; temperature = 10.0)
end

@named allterms = AllTerms()
op = layout(Tiling((5, 5); region = (11:30, 11:30), kinds = [:dark, :light]), allterms)
prob = PottsProblem(allterms, op, (0, 50); seed = 1)
total_energy(prob), total_energy(prob, solve(prob, SequentialCPM()).u[end])
```

Notes:

- A contact pair is counted once (CompuCell3D's convention). An asymmetric contact
  expression is averaged with its mirror (`kind ↔ kind′`, `x ↔ x′`).
- `x′` exists only for site and field variables; the neighbouring cell's value of a cell
  variable is `y[owner′]`.
- `centroid`, `integral` and `rand()` are not allowed in energies: their change by a copy
  is not local, or not an energy. Use a drive with `displacement(c, k)` for centroid-based
  motility.
- A fold over a relation inside an energy (`volume * sum(q[n] for n in far(40))`) may read
  only values a copy does not change: static site variables, parameters, constants, `id`;
  the bare cell quantities (`volume`, cell variables) and, in contact terms, `owner`,
  `owner′`, `kind`, `kind′` are fine outside it. Its anchor must be static. Potts computes
  ``\Delta H`` only where the copy acts, so `owner[n]`, `kind[n]`, `volume[owner[n]]`, σ at
  an explicit site (`owner[40]`) or an indexed `volume[id]` is refused at `mtkcompile`;
  read the cell's own quantities bare, and use a `@drive` to react to the ownership around
  the copy.
- The library forms `Volume(kinds…; target, strength)`, `Surface(kinds…; target,
  strength)` and `Adhesion(J)` expand to the terms above.

## Compartments

Cells can form **clusters**, for example a nucleus and its cytoplasm. Give each cell a
cluster id in the operating point (`cluster => groups`, equal ids form one cluster). A
cluster is named by its lowest live member, the root. Contact terms can read
`cluster[owner] == cluster[owner′]`, and `clusters(k) => …` terms read the cluster's total
`cluster_volume` and `cluster_surface`:

```@example energy
@potts_model Compartments begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        V₀[kind] = [0.0, 48.0, 16.0]
    end
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells => (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 2.0, J[kind, kind′])
        clusters(cytoplasm) => (cluster_volume - 64.0)^2
    end
    @sweep Metropolis(; temperature = 10.0)
end

σ = zeros(Int32, 30, 30)
σ[5:12, 5:12] .= 1; σ[7:10, 7:10] .= 3              # cell 1 with nucleus 3
σ[16:23, 16:23] .= 2; σ[18:21, 18:21] .= 4          # cell 2 with nucleus 4
@named comp = Compartments()
prob = PottsProblem(comp, [ownership => σ, kind => [:cytoplasm, :cytoplasm, :nucleus, :nucleus],
                           cluster => [1, 2, 1, 2]], (0, 50))
sol = solve(prob, SequentialCPM())
sol[:cluster_volume][end]
```

`@divide clusters(k) …` divides a whole cluster; see [Lifecycle](@ref manual-lifecycle).
