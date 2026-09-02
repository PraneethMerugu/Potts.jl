# [Wortel 2021 integration](@id wortel-2021-integration)

This serial CPU program exercises the final authoring and execution interface
for activity-coupled cell migration: site-owned activity, accepted-copy
activation, per-MCS decay, history, surface and volume constraints, contact
energy, local connectivity, observation, and exact semantic RNG addressing.

It is an integration witness, not a reproduction of the paper's full
parameter campaign or its speed-persistence claims.

## Substrate disposition

This program does not replace an applicable ModelingToolkit, Catalyst, or
MethodOfLines subsystem with a Potts-specific numerical component. Its
mechanisms are tied to CPM events and spatial identity:

| Mechanism | Owner | Reason |
|:--|:--|:--|
| volume, contact, surface, connectivity, and copy energy | Potts | These are CPM lattice and proposal semantics. |
| site activity and ownership-change clearing | Potts | Activity belongs to individual occupied lattice sites, not one continuous state per cell. |
| activation | Potts | It occurs only when an extension copy is accepted. |
| activity aging and history | Potts | They advance at the completed-MCS boundary and retain site-field history. |

A per-cell MTK ODE or Catalyst reaction network would lose the per-site
activity distribution, accepted-copy trigger, and ownership-change behavior.
MethodOfLines would instead describe an independently evolving PDE field.
Those are different models, so the final Wortel witness keeps these mechanisms
on the CPM substrate.

The complete reusable source is
[`examples/wortel_2021_serial.jl`](https://github.com/PraneethMerugu/Potts.jl/blob/main/examples/wortel_2021_serial.jl).
The strict documentation build executes that exact file:

```@example wortel_product
using Potts
program = joinpath(pkgdir(Potts), "examples", "wortel_2021_serial.jl")
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
