# [Lifecycle: division and death](@id manual-lifecycle)

## Division: `@divide`

A division rule reads `@divide cells(k₁, k₂, …) [Every(n)] when = condition, along = plane,
x => rule, …`:

| Part | Meaning |
|---|---|
| `cells(k…)` | the kinds that divide by this rule (`cells`: every kind) |
| `Every(n)` or `every = n` | check the rule only at MCS where `mcs % n == 0` (default: every MCS) |
| `when` | a cell-scope condition: `volume`, cell variables, component variables, `mcs`, `rand()` |
| `along` | the division plane: `RandomPlane()` (uniformly random), `principal_axis()` (across the long axis, the default), `major_axis()`, or a fixed normal `(1.0, 0.0)` |
| `x => value` | set `x` in both daughters (an expression of the parent's state) |
| `x => Split()` | halve the parent's `x` between the daughters |

Rules run at the end of the MCS. The daughter takes a new cell number and its sites are
on one side of the plane through the centroid; state without a rule is copied. Several
rules are tried in order and the first that fires for a cell wins. A problem reserves
`capacity` cell slots (by default twice the initial cells plus 64); pass a larger
`capacity` for long growth runs. When the slots run out, divisions wait and a warning says
so.

```@example lifecycle
using Potts

@potts_model Divider begin
    @kinds medium cell
    @parameters V₀ = 25.0
    @variables begin
        mass(cell) = 1.0
        clock(cell) = 0.0
    end
    @lattice Lattice((40, 40); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cell) => 2.0 * (volume - V₀ * (1 + clock / 50))^2
        contacts => 8.0 * (kind != kind′)
    end
    @after_mcs clock += 1
    @divide cells(cell) Every(5) when = (clock >= 50) && (rand() < 0.5), along = principal_axis(),
        clock => 0.0, mass => Split()
    @sweep Metropolis(; temperature = 8.0)
end

@named divider = Divider()
op = layout(Tiling((5, 5); region = (16:25, 16:25), kinds = [:cell]), divider)
sol = solve(PottsProblem(divider, op, (0, 200); seed = 1, capacity = 64), SequentialCPM())
alive = sol[:volume][end] .> 0
(cells = count(alive), divisions = sol.stats.lifecycle.divisions, total_mass = sum(sol[:mass][end][alive]))
```

The total mass stays 4: `Split()` conserves it.

## Clusters

With compartments (see [Energy](@ref manual-energy)), `@divide clusters(k) when = …` divides
a whole cluster when its root (lowest live member, of kind `k`) meets the condition; every
member is split by the same plane, and the daughters form a new cluster. A kind divides
either by `cells(…)` or by `clusters(…)` rules, not both.

## Death

A cell dies when it loses its last site. There is no separate death statement: write the
rule that empties the cell. The usual way is to set its target volume to zero:

```@example lifecycle
@potts_model Apoptosis begin
    @kinds medium cell
    @variables begin
        V_target(cell) = 25.0
        doomed(cell) = 0.0
    end
    @lattice Lattice((40, 40); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cell) => 2.0 * (volume - V_target)^2
        contacts => 8.0 * (kind != kind′)
    end
    @after_mcs begin
        doomed ~ ifelse((Pre(doomed) > 0) || ((mcs == 20) && (id <= 2)), 1.0, 0.0)
        V_target ~ ifelse(doomed > 0, 0.0, 25.0)
    end
    @sweep Metropolis(; temperature = 8.0)
end

@named apoptosis = Apoptosis()
op = layout(Tiling((5, 5); region = (16:25, 16:25), kinds = [:cell]), apoptosis)
sol = solve(PottsProblem(apoptosis, op, (0, 100); seed = 1), SequentialCPM(); saveat = 20)
[count(>(0), v) for v in sol[:volume]]
```

Cells 1 and 2 are doomed at MCS 20 and gone soon after. A dead cell keeps its number, with
volume 0, and drops out of energies, folds and plots. `@constraint no_extinction` forbids
the copies that would empty a cell, for models in which cells must not die.
