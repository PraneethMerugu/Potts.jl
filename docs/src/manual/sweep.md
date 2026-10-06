# [Sweep: `@sweep`](@id manual-sweep)

`@sweep` sets how copy attempts are accepted and how long an MCS lasts:

| Form | Meaning |
|---|---|
| `Metropolis(; temperature = T)` | accept if ``\Delta H \le 0``, else with probability ``e^{-\Delta H/T}`` |
| `Barker(; temperature = T)` | accept with probability ``1/(1 + e^{\Delta H/T})`` |
| `temperature = Tk[kind]` | a temperature per kind (or any cell expression); the copy uses `combine` of the source and target cells' values, and the medium never contributes |
| `combine = min` | how the two temperatures combine (default `min`); a named function or a callable struct, not an anonymous function (below) |
| `offset = ε` | shift ``\Delta H`` to ``\Delta H - \varepsilon`` in either law: Metropolis accepts if ``\Delta H \le \varepsilon``, else with probability ``e^{-(\Delta H - \varepsilon)/T}``; Barker with probability ``1/(1 + e^{(\Delta H - \varepsilon)/T})``. Morpheus's yield `Y` is `offset = -Y` |
| `mcs_duration = 0.5` | the time one MCS represents, for equations (default 1) |

`@sweep` checks three of these when the model is built, and throws an `ArgumentError` otherwise:

- `offset` must be finite. NaN and ±Inf are rejected.
- `mcs_duration` must be a positive, finite number. NaN, ±Inf, 0 and negative values are
  rejected, as are values that are not numbers and a symbolic parameter: the duration
  belongs to the sweep, not to the model's parameters, so it cannot be changed with
  `remake`. Build a new system to change it.
- `combine` must be a named function or an instance of a callable struct. An anonymous
  function (`(a, b) -> (a + b) / 2`), a closure, or a function defined inside another
  function is rejected: its compiler-generated name changes between Julia sessions, so a
  checkpoint saved in one session would not load in the next. Define the function at the
  top level, or use a callable struct to carry parameters:

```julia
amean(a, b) = (a + b) / 2                 # combine = amean

struct Mix                                # combine = Mix(0.7)
    w::Float64
end
(m::Mix)(a, b) = m.w * a + (1 - m.w) * b
```

A wrapper is checked through: `min ∘ max` is accepted, while `Base.Fix2((a, b) -> a, 1)` or a
callable struct whose field holds an anonymous function is rejected. A named function is
identified by its module path and name, not its body, so redefining it under the same name
between saving and loading a checkpoint is not detected. Functions defined in a Pluto notebook
or inside a module are identified by that module path too, so a Pluto workspace function's
checkpoint does not reload in another notebook session, and the same function defined in a
script and in a module fingerprints differently.

One MCS is as many copy attempts as there are mobile lattice sites. A paper that counts
`n` attempts per site as one step uses `n` of our MCS per paper step. At `T ≤ 0` ties are
accepted with probability ½, as in CompuCell3D.

## The order of one MCS: `@schedule`

One MCS runs its phases in this order:

| Phase | What runs |
|---|---|
| `before_mcs` | `@before_mcs` updates |
| `sweep` | the copy attempts |
| `after_mcs` | `@after_mcs` updates |
| `fields` | the field equations (`D(c) ~ …` of `c(field)`) |
| `components` | cell and model ODEs, discrete components, `@link`/`@unlink` |
| `operators` | (none yet) |
| `lifecycle` | `@divide` rules |
| `end_mcs` | history (`Pre(x, k)`), derived quantities, then callbacks and saving |

`@schedule` lists phases in another order, for models whose paper steps the field before
the cells move (`@schedule fields, sweep`):

- Listed phases run in the listed order. Each unlisted phase goes right after the last
  placed phase that precedes it in the default order (first if none), so `@schedule
  fields, sweep` runs `before_mcs, fields, sweep, after_mcs, components, …`, and a schedule
  that lists phases in their default relative order is no schedule at all, bit for bit.
- `end_mcs` is always last; `before_mcs` must precede `sweep` and `after_mcs` must follow
  it. An unknown name, a name listed twice or a broken rule is an error naming the phase.
- Every phase reads current values in any order: integrals (`integral(x)`) are refreshed
  after each phase that moves cells (the sweep, a lifecycle that divides) and after each
  update that writes their operand, before the next phase that reads them.
- The order is part of the model (its fingerprint): a checkpoint does not cross orders.
- Reordering costs nothing on any backend: `step!` is one fold over a static tuple of the
  phases. A phase that runs on the host (an `Adaptive` ODE solver) costs one device↔host
  round trip per MCS wherever the schedule puts it.

```@example sweep
using Potts

@potts_model FieldFirst begin
    @kinds medium cell
    @variables c(field) = 0.0
    @lattice Lattice((20, 20); neighborhood = Moore(1))
    @energy Volume(cell; target = 16.0, strength = 1.0)
    @drive copy => -5.0 * (c[target] - c[source])
    @equations D(c) ~ 0.2 * Δ(c) + 0.1 * (kind == cell) - 0.05 * c
    @schedule fields, sweep
    @sweep Metropolis(; temperature = 4.0)
end

@named ff = FieldFirst()
σ = zeros(Int32, 20, 20); σ[8:11, 8:11] .= 1
sol = solve(PottsProblem(ff, [ownership => σ, kind => [:cell]], (0, 10); field_solver = ExplicitEuler(substeps = 2)),
    SequentialCPM())
sol.retcode
```

## Choosing an acceptance law

Without an offset, Metropolis and Barker both satisfy detailed balance, so they have the same equilibrium. Only
the dynamics differ:

- Barker accepts a neutral copy (``\Delta H = 0``) with probability ½; Metropolis accepts
  all of them. For every ``\Delta H``, Barker accepts with at most the probability of
  Metropolis (Peskun, 1973), so Metropolis mixes faster.
- Fluctuations, diffusion and sorting therefore run slower per MCS under Barker. MCS times
  from a paper are comparable only under the same law: for a reproduction, use the paper's
  law. With integer contact energies ``\Delta H = 0`` is common, so the difference shows in
  practice.
- At ``T \le 0`` the two laws coincide: both accept ``\Delta H < 0`` and half the ties
  (with an offset, ``\Delta H < \varepsilon`` and half of ``\Delta H = \varepsilon``).
- Barker's acceptance is smooth in ``\Delta H``, which matters for gradient-based methods
  through the stochastic dynamics (e.g. StochasticAD.jl). This is a research direction, not a
  feature of Potts.jl.

The `acceptance` keyword of the algorithm overrides the model's law, so one problem runs
under both:

```@example sweep
using Potts

@potts_model Sorting begin
    @kinds medium dark light
    @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = 25.0, strength = 1.0)
        Adhesion(J)
    end
    @sweep Metropolis(; temperature = 10.0)
end

@named sorting = Sorting()
op = layout(Tiling((5, 5); region = (11:30, 11:30), spacing = 0, kinds = [:dark, :light]), sorting)
prob = PottsProblem(sorting, op, (0, 50); seed = 1)
ratio(law) = (sol = solve(prob, SequentialCPM(; acceptance = law)); sol.stats.accepted / sol.stats.attempts)
(metropolis = ratio(Metropolis()), barker = ratio(Barker()))
```

## A temperature per kind

A kind table gives each kind its own temperature; `combine = max` lets the hotter cell of a
copy set the temperature.

```@example sweep
@potts_model TwoTemperatures begin
    @kinds medium calm busy
    @parameters Tk[kind] = [0.0, 2.0, 20.0]
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        Volume(calm, busy; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @sweep Metropolis(; temperature = Tk[kind], combine = max)
end

@named twotemps = TwoTemperatures()
op = layout(Tiling((5, 5); region = (11:30, 11:30), spacing = 2, kinds = [:calm, :busy]), twotemps)
prob = PottsProblem(twotemps, op, (0, 50); seed = 1)
sol = solve(prob, SequentialCPM())
sol.stats.accepted / sol.stats.attempts                     # the fraction of accepted attempts
```

`sol.stats` counts the MCS, attempts and accepted copies of a run.

## A temperature per cell

A temperature can also be a cell variable, so it changes during a run. Here mature cells
freeze from MCS 25 on: their `T_cell` drops to 0, while stem cells keep `T_cell = -1`,
which means "use the kind's value". This is CompuCell3D's per-cell fluctuation amplitude,
where −1 means "use the type's value":
`temperature = ifelse(T_cell >= 0, T_cell, Tk[kind])`.

```@example sweep
@potts_model Freezing begin
    @kinds medium stem mature
    @parameters Tk[kind] = [0.0, 10.0, 10.0]
    @variables T_cell(cell) = -1.0
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @energy begin
        Volume(stem, mature; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @after_mcs T_cell ~ ifelse(kind == mature && mcs >= 25, 0.0, T_cell)
    @sweep Metropolis(; temperature = ifelse(T_cell >= 0, T_cell, Tk[kind]))
end

@named freezing = Freezing()
op = layout(Tiling((5, 5); region = (11:30, 11:30), spacing = 2, kinds = [:stem, :mature]), freezing)
sol = solve(PottsProblem(freezing, op, (0, 50); seed = 1), SequentialCPM())
(start = sol[:T_cell][1], finish = sol[:T_cell][end])
```

With the default `combine = min`, every copy that involves a frozen cell runs at ``T = 0``.

