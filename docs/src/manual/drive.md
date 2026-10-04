# [Drives: `@drive`](@id manual-drive)

A **drive** is a term added to ``\Delta H`` of a copy attempt that is not the change of an
energy: chemotaxis, active motility, protrusion memory. Each line is `copy => expression`,
written in the **copy scope**:

| Name | Meaning |
|---|---|
| `source`, `target` | the site copied from, and the site copied into |
| `new`, `old` | the cell gaining the target (owner of `source`), and the cell losing it |
| `kind[new]`, `kind[old]`, `kind[target]` | kinds (a site index gives the owner's kind) |
| `x[target]`, `x[new]` | a site variable at a site, a cell variable of a cell |
| `owner[s]`, `volume[owner[s]]` | the owner of a site, its volume |
| `displacement(c, k)` | how far the copy would move cell `c`'s centroid along axis `k` (`c` is `new` or `old`) |
| `local_components`, `ring_arcs`, `ring_cells`, `ring_medium` | connectivity of the losing cell around the target |
| `mcs` | the current MCS |

A drive is added with weight 1: a negative value favours the copy.

```@example drive
using Potts

@potts_model Drives begin
    @kinds medium cell
    @parameters begin
        χ = 200.0
        μ = 5.0
    end
    @variables c(site) = 0.0
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @drive begin
        Chemotaxis(c; strength = χ)                                   # up the gradient of c
        copy => -μ * (displacement(new, 1) - displacement(old, 1))    # directed motion along +x
    end
    @sweep Metropolis(; temperature = 8.0)
end

@named drives = Drives()
c0 = [x / 60 for x in 1:60, y in 1:30]                               # a fixed linear gradient
op = layout(Tiling((5, 5); region = (6:10, 13:17), kinds = [:cell]), drives)
sol = solve(PottsProblem(drives, [op; :c => c0], (0, 200); seed = 1), SequentialCPM(); saveat = 50)
[sum(x[1] for x in CartesianIndices(u.σ) if u.σ[x] == 1) / count(==(1), u.σ) for u in sol.u]   # centroid x
```

## Chemotaxis

`Chemotaxis(c; strength, response = identity, kinds = (), when = new != 0)` is the drive
`copy => -strength * (r(c[target]) - r(c[source]))`:

- `response`: `identity`, `saturating(s)` (``c/(s + c)``), `saturating_linear(s)`
  (``c/(s c + 1)``), or any function;
- `when`: the copies it acts on. The default, `new != 0`, acts when a cell gains the target
  (extensions and cell–cell copies); `true` acts on every copy, retractions included;
  `old == 0` on extensions into the medium only;
- `kinds`: only copies won by cells of these kinds.

## Folds over neighbourhoods

Expressions can fold over the sites around a site with a generator over a relation:
`sum`, `prod`, `mean`, `geomean`, `log1p_geomean`, `minimum`, `maximum`, `count`, `any`,
`all`, with an optional `if` filter. The Act model of Niculescu et al. (2015), shipped as
`WortelAct`, uses the geometric mean of the `act` values of the cell's own sites around
the source and the target:

```@example drive
@potts_model ActMemory begin
    @kinds medium cell
    @parameters begin
        λ_act = 200.0
        max_act = 20.0
    end
    @variables act(site) = 0.0
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        cells(cell) => 5.0 * (volume - 200.0)^2
        contacts => 20.0 * (kind != kind′)
    end
    act_mean(s) = geomean(act[n] for n in Moore(1; include_self = true)(s) if owner[n] == owner[s])
    @drive copy => -(λ_act / max_act) * (act_mean(source) - act_mean(target))
    @on_copy act[target] ~ ifelse(new != 0, max_act, 0.0)
    @after_mcs act ~ max(Pre(act) - 1, 0)
    @sweep Metropolis(; temperature = 20.0)
end
@named actmem = ActMemory()
op = layout(Tiling((14, 14); region = (14:27, 14:27), kinds = [:cell]), actmem)
sol = solve(PottsProblem(actmem, op, (0, 50); seed = 1), SequentialCPM())
sol[:volume][end]
```

This is a teaching version with made-up parameters; the published model with its
parameters is `WortelAct`.

!!! note "No random numbers in drives"
    `rand()` is not allowed in drives, energies and constraints: a random ``\Delta H``
    breaks detailed balance. Draw random values in updates and read the stored result.

!!! note "No `integral` in drives and constraints"
    `integral(x)`, including `integral(Pre(x))` and an `integral` inside a fold over cells
    or in the arguments of `Chemotaxis`, is not allowed in drives and constraints, and
    building such a model is an `ArgumentError`. Drives and constraints are evaluated at
    every copy attempt, where the cells change with each accepted copy, while an integral
    is refreshed only between sweeps. Keep the integral in a cell variable updated at the
    start of the MCS and read it at the copy's cells:

    ```julia
    @variables begin
        u(site) = 0.0
        s(cell) = 0.0
    end
    @before_mcs s ~ integral(u)                # the sum of u over the cell's sites
    @drive copy => -0.5 * (s[new] - s[old])
    @constraint s[new] < 100.0
    ```

    `s` holds the value at the start of the MCS; it does not follow the copies within it. A copy-scope `@sweep` temperature
    may read `integral` directly and sees the same start-of-MCS value.
