# [Wortel 2021 integration](@id wortel-2021-integration)

This serial CPU program exercises the final authoring and execution interface
for activity-coupled cell migration: site-owned activity, accepted-copy
activation, per-MCS decay, history, surface and volume constraints, contact
energy, local connectivity, observation, and exact semantic RNG addressing.

It is an integration witness, not a reproduction of the paper's full
parameter campaign or its speed-persistence claims.

The complete reusable source is
[`examples/wortel_2021_serial.jl`](https://github.com/PraneethMerugu/Potts.jl/blob/main/examples/wortel_2021_serial.jl).
The strict documentation build executes that exact file:

```@example wortel_product
using PottsToolkit
program = joinpath(pkgdir(PottsToolkit), "examples", "wortel_2021_serial.jl")
include(program)
result = Wortel2021Serial.run_wortel_2021()
final = last(result.solution)
(
    retcode=result.solution.retcode,
    mcs=final.mcs,
    occupied=final[:occupied_sites],
    activity_bounds=extrema(final[:activity]),
)
```

The model runs with `SequentialCPM()`, `CPUBackend()`, and `Float32`. Its
bounded execution does not qualify Metal, 3D, or the paper's scientific
outcomes.
