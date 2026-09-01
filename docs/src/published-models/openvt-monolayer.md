# [OpenVT monolayer workflow](@id openvt-monolayer-integration)

The removed research notebooks combined two scientific purposes: calibrating
the OpenVT 11-cell relaxation timescale and running a growing, dividing 2D
monolayer with zero cell-cell adhesion and free-surface contact inhibition.
Their implementation depended on retired CorePotts event/kernel APIs and
unsupported CUDA/ROCm selectors.

The current bounded replacement preserves that workflow as ordinary Julia. It
uses public PottsToolkit declarations for steric volume energy, zero cell-cell
adhesion, generation-safe division, and a serial trajectory; it computes the
relaxation calibration and free-surface inhibition classification explicitly.
It does not claim to reproduce the notebooks' 10,000-cell GPU campaign or
submission videos.

```@example openvt_monolayer
using PottsToolkit
program = joinpath(pkgdir(PottsToolkit), "examples", "openvt_monolayer_serial.jl")
include(program)
using .OpenVTMonolayerSerial

result = OpenVTMonolayerSerial.run_openvt_monolayer()
(result.relaxation_steps, result.inhibition, last(result.solution).mcs)
```
