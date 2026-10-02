# [Updates: `@before_mcs`, `@after_mcs`, `@on_copy`](@id manual-updates)

Updates change state at fixed points of the simulation. They are equations: the left side
is the variable's new value, `Pre(x)` its value before the update.

| Section | When | Scope of the left side |
|---|---|---|
| `@before_mcs` | at the start of every MCS | site, field, cell or model variables |
| `@after_mcs` | at the end of every MCS, after the copy attempts | site, field, cell or model variables |
| `@on_copy` | after every accepted copy | `x[target]` of a site variable |

A bare variable on the left updates every site, every live cell, or the model, depending
on its scope.

```@example updates
using Potts

@potts_model Clocks begin
    @kinds medium cell
    @variables begin
        age(cell) = 0.0
        hits(site) = 0.0
        ticks(model) = 0.0
        lagged(model) = 0.0
        noise(cell) = 0.0
        mean_hits(cell) = 0.0
    end
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @on_copy hits[target] += 1                         # count accepted copies per site
    @after_mcs begin
        age ~ Pre(age) + 1
        lagged ~ Pre(ticks, 3)                         # ticks, three MCS ago
        noise ~ rand()                                  # a fresh uniform number per cell
        mean_hits ~ integral(hits) / volume             # mean over the cell's sites
    end
    @after_mcs Every(5) ticks += 1                      # every 5 MCS
    @sweep Metropolis(; temperature = 8.0)
end

@named clocks = Clocks()
op = layout(Tiling((5, 5); region = (6:25, 6:25), spacing = 1, kinds = [:cell]), clocks)
sol = solve(PottsProblem(clocks, op, (0, 20); seed = 1), SequentialCPM(); saveat = 1)
(ticks = sol[:ticks], lagged = sol[:lagged], age = sol[:age][end][1])
```

## Rules

- **Compound assignments.** `x += e` means `x ~ Pre(x) + e`; also `-=`, `*=`, `/=`.
- **One equation per variable** in a phase: two updates of the same variable are an error
  that suggests `+=`. In an extension, an update of a variable replaces the base's.
- **Cadence.** `@after_mcs Every(n) …` runs at the MCS where `mcs % n == 0` (MCS are numbered
  from 0).
- **Lags.** `Pre(x, k)` is the value of a site, field or model variable at the end of the
  MCS `k` before the current one (`k` ≥ 1). Lags of cell variables are not supported (chain
  `Pre` through an extra variable instead).
- **Randomness.** `rand()` is a uniform number in (0, 1), drawn fresh for every cell or site
  and every MCS from the problem's seed; runs are reproducible, on any backend.
- **Folds.** Updates can fold over the cells (`count(true for c in cells(k))`,
  `sum(volume for c in cells)`, `mean`, `minimum`, `maximum`, `any`, `all`), over the sites
  (`sum(x[s] for s in sites)`) and over a relation around a site (`sum(c[n] for n in
  Moore(1)(site))`).
- **Cell quantities.** `centroid(k)` is the `k`-th centroid coordinate of a cell;
  `integral(x)` sums a site expression over the cell's sites.
- **`@on_copy`** writes the target site of an accepted copy, with the copy names `new`,
  `old`, `source`, `target`: `act[target] ~ ifelse(new != 0, max_act, 0.0)`.
