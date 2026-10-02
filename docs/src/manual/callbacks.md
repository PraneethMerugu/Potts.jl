# [Callbacks](@id manual-callbacks)

Callbacks run your own code during a solve, as in SciML. A `DiscreteCallback(condition,
affect!)` checks `condition(u, t, integrator)` after every MCS and, when it is true, calls
`affect!(integrator)`. Inside `affect!` use the integrator's setters:

- `integrator.ps[:λ] = v` changes a parameter from the next MCS;
- `integrator[:x] = v` writes a declared variable;
- `terminate!(integrator)` stops the run;
- after writing `integrator.state` directly (for example cell kinds), call
  `u_modified!(integrator, true)` so that frozen sites are recomputed.

`CallbackSet(cb₁, cb₂)` combines callbacks; pass them with `solve(…; callback = …)`.

```@example callbacks
using Potts

@potts_model Quench begin
    @kinds medium cell
    @parameters T = 15.0
    @variables tagged(cell) = 0.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @sweep Metropolis(; temperature = T)
end

@named quench = Quench()
op = layout(Tiling((5, 5); region = (6:25, 6:25), spacing = 1, kinds = [:cell]), quench)
prob = PottsProblem(quench, op, (0, 200); seed = 1)

cool = DiscreteCallback((u, t, integ) -> t == 50, integ -> (integ.ps[:T] = 1.0))
tag = DiscreteCallback((u, t, integ) -> t == 60, integ -> (integ[:tagged] = 1.0))
stop = DiscreteCallback((u, t, integ) -> t == 120, terminate!)
sol = solve(prob, SequentialCPM(); callback = CallbackSet(cool, tag, stop), saveat = 40)
sol.t, sol.retcode, sol[:tagged][end][1]
```

The run stopped at MCS 120 with return code `Terminated`. The `condition` sees `t` (the
MCS just completed) and `u`, a view of the state; keep conditions cheap, since they run
after every MCS.
