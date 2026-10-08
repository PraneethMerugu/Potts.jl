# [Updates: `@before_mcs`, `@after_mcs`, `@on_copy`](@id manual-updates)

Updates change state at fixed points of the simulation. They are equations: the left side
is the variable's new value, `Pre(x)` its value before the update.

| Section | When | Scope of the left side |
|---|---|---|
| `@before_mcs` | at the start of every MCS | site, field, cell, model or edge variables |
| `@after_mcs` | at the end of every MCS, after the copy attempts | site, field, cell, model or edge variables |
| `@on_copy` | after every accepted copy | `x[target]` of a site variable |

A bare variable on the left updates every site, every live cell, the model, or every link
of a relationship (see [Relationships](@ref manual-relationships)), depending on its scope.

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
  and every MCS from the problem's seed; runs are reproducible, on any backend. `randn()`
  is a standard normal number with the same contract, `randn(μ, σ)` is `μ + σ * randn()`,
  and `randn(μ, σ; lower)` is redrawn while it is `≤ lower` (a truncated normal; after 64
  draws all `≤ lower` the value is NaN and the run fails with `ReturnCode.Failure`, which
  for a bound below `μ + 2σ` does not happen in practice). Each draw depends only on the
  seed, the MCS, the cell or site and the draw's place in the model, so it is the same on
  every algorithm and thread count. Other random functions (`rand(1:6)`, `randn(3)`,
  `randexp()`, `shuffle(v)`, `Base.rand(…)` with arguments) are an error when the model is
  built: they would run once, at build time, and become constants.
- **Folds.** Updates can fold over the cells (`count(true for c in cells(k))`,
  `sum(volume for c in cells)`, `mean`, `minimum`, `maximum`, `any`, `all`), over the sites
  (`sum(x[s] for s in sites)`) and over a relation around a site (`sum(c[n] for n in
  Moore(1)(site))`).
- **Contact counts.** In cell scope (cell updates and equations, division conditions and
  rules, cell observed quantities), `count(pred for _ in contacts)` is the number of the
  cell's contact pairs (s, s′), s in the cell and s′ a neighbour of s (inside the lattice)
  owned by another cell or the medium, for which `pred` holds; `contacts(rel)` uses a
  relation declared in `@relations` instead of the contact neighbourhood. `pred` reads the
  partner's kind `kind′` (`medium` for the medium) and constants: `count(true for _ in
  contacts)` is the unweighted `surface` over the contact relation, and the free-surface
  fraction `count(kind′ == medium for _ in contacts) / count(true for _ in contacts)` is
  the share of a cell's contacts with the medium. Each count is a tracker kept exact by
  every accepted copy and every division, removal and kind change, so reading it costs
  nothing per MCS; it is not available in energies, drives or constraints.

  ```@example updates
  @potts_model Exposure begin
      @kinds medium A B
      @variables begin
          free(cell) = 0.0
          touching_b(cell) = 0.0
      end
      @lattice Lattice((30, 30); boundary = Closed(), neighborhood = Moore(1))
      @energy begin
          Volume(A, B; target = 25.0, strength = 1.0)
          contacts => 8.0 * (kind != kind′)
      end
      @after_mcs begin
          free ~ count(kind′ == medium for _ in contacts) / count(true for _ in contacts)
          touching_b ~ count(kind′ == B for _ in contacts)
      end
      @sweep Metropolis(; temperature = 8.0)
  end

  @named exposure = Exposure()
  σ = zeros(Int32, 30, 30)                          # a 4 × 4 block of 5 × 5 cells
  for (k, (a, b)) in enumerate(Iterators.product(0:3, 0:3))
      σ[5 + 5a .+ (1:5), 5 + 5b .+ (1:5)] .= k
  end
  op = [ownership => σ, kind => [isodd(k) ? :A : :B for k in 1:16]]
  u = solve(PottsProblem(exposure, op, (0, 10); seed = 1), SequentialCPM()).u[end]
  (corner = u.cell.free[1], inner = u.cell.free[6], b_contacts = u.cell.touching_b[1:4])
  ```
- **Cell quantities.** `centroid(k)` is the `k`-th centroid coordinate of a cell;
  `integral(x)` sums a site expression over the cell's sites. A fold inside `x` that does
  not read the site, such as `integral(w * mean(volume[c] for c in cells))`, is computed
  once per recomputation of the integral, not at every site: it costs what
  `integral(w) * mean(volume[c] for c in cells)` costs. Folds that draw `rand()`, and
  folds nested inside a fold that reads the site, stay per site.
- **`@on_copy`** writes the target site of an accepted copy, with the copy names `new`,
  `old`, `source`, `target`: `act[target] ~ ifelse(new != 0, max_act, 0.0)`.
  It runs inside the sweep, while `integral(x)` is refreshed only between sweeps, so an
  `integral` in an `@on_copy` right-hand side is an error at build; keep it in a cell
  variable updated `@before_mcs` (`s ~ integral(x)`) and read `s[new]`, `s[old]`.
