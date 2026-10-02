# [Sweep: `@sweep`](@id manual-sweep)

`@sweep` sets how copy attempts are accepted and how long an MCS lasts:

| Form | Meaning |
|---|---|
| `Metropolis(; temperature = T)` | accept if ``\Delta H \le 0``, else with probability ``e^{-\Delta H/T}`` |
| `Barker(; temperature = T)` | accept with probability ``1/(1 + e^{\Delta H/T})`` |
| `temperature = Tk[kind]` | a temperature per kind (or any cell expression); the copy uses `combine` of the source and target cells' values, and the medium never contributes |
| `combine = min` | how the two temperatures combine (default `min`) |
| `offset = ε` | accept if ``\Delta H \le \varepsilon``, else ``e^{-(\Delta H - \varepsilon)/T}``; Morpheus's yield `Y` is `offset = -Y` |
| `mcs_duration = 0.5` | the time one MCS represents, for equations (default 1) |

One MCS is as many copy attempts as there are mobile lattice sites. A paper that counts
`n` attempts per site as one step uses `n` of our MCS per paper step. At `T ≤ 0` ties are
accepted with probability ½, as in CompuCell3D.

```@example sweep
using Potts

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
