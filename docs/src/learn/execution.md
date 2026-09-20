# [Initialize and execute](@id initialize-and-execute)

`PottsProblem` combines a model, immutable initialization recipe, integer MCS
span, parameter values, and semantic RNG identity. It completes and
structurally schedules an authored model immediately; an already scheduled
model passes through unchanged. Algorithm, backend, scalar type, save policy,
callbacks, and native solve profiles are selected at `init` or `solve`.

```@example execution
using Potts
using SciMLBase
using Symbolics
using ModelingToolkitBase: @parameters

@parameters target = 4.0 strength = 1.0 temperature = 2.0
cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
system = PottsSystem(
    name=:execution_example,
    statements=StatementSet((
        Lattice((4, 4); boundary=Periodic()),
        cell,
        medium,
        Volume(cell; target, strength),
        Protocol(Sweep(; temperature); name=:main),
        Observation(:occupied, occupancy(cell, :lattice)),
    )),
    parameters=[target, strength, temperature],
)

labels = zeros(Int, 4, 4)
labels[2:3, 2:3] .= 1
initial = PottsInitialState(
    ownership=LabelledCells(labels; cells=[cell], medium),
)
problem = PottsProblem(
    system,
    initial,
    (0, 2);
    p=(target=>4.0, strength=>1.0, temperature=>2.0),
    seed=0x5a17,
)
solution = solve(
    problem,
    SequentialCPM();
    backend=CPUBackend(),
    scalar_type=Float64,
    save_everystep=true,
    observables=(:occupied,),
)

(solution.retcode, solution.t, last(solution)[:occupied])
```

`failure_report(integrator)` and `failure_report(solution)` return the exact
failure object already retained by the corresponding execution result, or
`nothing` after success:

```@example execution
failure_report(solution)
```

Querying an integrator is passive. It reports only its most recently settled
state and never waits for pending work, synchronizes a device, or changes the
integrator. When a report is present, `showerror` preserves its source-aware
diagnostic context:

```julia
report = failure_report(integrator)
report === nothing || showerror(stderr, report)
```

`SequentialCPM()` is the serial semantic reference.
`CheckerboardSweepCPM()` is a distinct colored parallel schedule, not an
acceleration mode for the sequential algorithm. `CPUBackend()` is available
for both. `MetalBackend()` is admitted only for the exact checkerboard
`Float32` profile in [Capability status](@ref capability-status).

A sweep's positive attempt budget is declared with
`Sweep(; attempts=AttemptsPerSite(16), temperature=...)`. Both public
algorithms execute the declared number of copy attempts per mutable site
before the MCS boundary and its after-step cell events. Keep the attempt
budget in the model when translating a published MCS definition; changing it
changes the stochastic trajectory as well as the work per MCS.

`CheckerboardSweepCPM()` currently admits at most 255 rounds per mutable site
because each round occupies one addressed-RNG subround; `SequentialCPM()` does
not have that checkerboard limit. An unsupported budget is rejected during
initialization, before execution.

For interactive control, call `init`, then `step!` or `solve!`. A failed step
does not publish partial CPM, lifecycle, relationship, or native-component
state. `terminate!` stops at the last settled boundary.
