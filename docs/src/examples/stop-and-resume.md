# [Stop and Resume](@id stop-and-resume)

This example proves exact same-contract continuation rather than merely demonstrating that a file
can be read.

```@example stop-and-resume
using PottsToolkit
using MakiePotts
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (12, 12); target_volume = 16, tspan = (0, 6), seed = 101)
algorithm = SequentialCPM(temperature = 2.0f0)
uninterrupted = CorePotts.init(
    problem, algorithm; save_start = false, save_end = false)
CorePotts.step!(uninterrupted, 3)
checkpoint = CorePotts.capture_checkpoint(uninterrupted)
resumed = CorePotts.restore_checkpoint(checkpoint, problem, algorithm)
CorePotts.step!(uninterrupted, 3)
CorePotts.step!(resumed, 3)
expected = CorePotts.logical_state(uninterrupted)
observed = CorePotts.logical_state(resumed)
exact_lattice = CorePotts.lattice_storage(expected) ==
    CorePotts.lattice_storage(observed)
frame = renderframe(observed, problem; mcs = resumed.t)

@assert exact_lattice
@assert resumed.t == uninterrupted.t == 6
@assert frame_mcs(frame) == 6
result = (; problem, algorithm, checkpoint, exact_lattice,
    resumed_mcs = resumed.t, frame)

(result.checkpoint.mcs, result.resumed_mcs, result.exact_lattice)
```

```@example stop-and-resume
using CairoMakie

figure, axis, potts_plot = plot(
    result.frame;
    axis = (; title = "Exactly resumed state at MCS $(result.resumed_mcs)"),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
figure
```

The source advances three MCS, captures a canonical checkpoint, restores it against the same
problem and algorithm, advances both branches three more MCS, and requires exact lattice equality.

`restore_checkpoint` is the exact-continuation operation. `import_checkpoint` is an explicit new
run with a compatibility report and weaker guarantee. Never replace restore with import silently.

Teaching inspiration: restart-oriented complete projects in the
[CC3D reference manual](https://compucell3dreferencemanual.readthedocs.io/en/latest/). The source
uses Potts.jl's own canonical checkpoint contract.
