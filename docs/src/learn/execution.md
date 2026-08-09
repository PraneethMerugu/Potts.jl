# [Initialize and execute](@id initialize-and-execute)

`PottsProblem` combines a scheduled system, immutable initialization recipe,
integer MCS span, parameter values, and semantic RNG identity. Algorithm,
backend, scalar type, save policy, callbacks, and native solve profiles are
selected at `init` or `solve`.

```@example execution
using PottsToolkit
using SciMLBase
using Symbolics
using ModelingToolkitBase: @parameters

@parameters target = 4.0 strength = 1.0 temperature = 2.0
cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
scheduled = mtkcompile(PottsSystem(
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
))

labels = zeros(Int, 4, 4)
labels[2:3, 2:3] .= 1
initial = PottsInitialState(
    ownership=LabelledCells(labels; cells=[cell], medium),
)
problem = PottsProblem(
    scheduled,
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

`SequentialCPM()` is the serial semantic reference.
`CheckerboardSweepCPM()` is a distinct colored parallel schedule, not an
acceleration mode for the sequential algorithm. `CPUBackend()` is available
for both. `MetalBackend()` is admitted only for the exact checkerboard
`Float32` profile in [Capability status](@ref capability-status).

For interactive control, call `init`, then `step!` or `solve!`. A failed step
does not publish partial CPM, lifecycle, relationship, or native-component
state. `terminate!` stops at the last settled boundary.
