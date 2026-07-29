using PottsToolkit
using MakiePotts
import CorePotts

# Build the checkpoint example from the same public declarations users author.
medium = Medium(:Medium)
cell = CellType(:Cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 16, strength = 2)),
)
mask = falses(12, 12)
mask[5:8, 5:8] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 6),
    seed = 101,
)

# Branch at MCS 3, then advance the original and restored integrators equally.
algorithm = SequentialCPM(temperature = 2.0f0)
uninterrupted = CorePotts.init(
    problem,
    algorithm;
    save_start = false,
    save_end = false,
)
CorePotts.step!(uninterrupted, 3)
checkpoint = CorePotts.capture_checkpoint(uninterrupted)
resumed = CorePotts.restore_checkpoint(checkpoint, problem, algorithm)
CorePotts.step!(uninterrupted, 3)
CorePotts.step!(resumed, 3)

# Compare logical state exactly; matching pictures alone would be too weak.
expected = CorePotts.logical_state(uninterrupted)
observed = CorePotts.logical_state(resumed)
exact_lattice = CorePotts.lattice_storage(expected) ==
    CorePotts.lattice_storage(observed)
uninterrupted_frame = renderframe(expected, problem; mcs = uninterrupted.t)
resumed_frame = renderframe(observed, problem; mcs = resumed.t)

@assert exact_lattice
@assert resumed.t == uninterrupted.t == 6
@assert frame_mcs(uninterrupted_frame) == frame_mcs(resumed_frame) == 6
result = (; problem, algorithm, checkpoint, exact_lattice,
    resumed_mcs = resumed.t, uninterrupted_frame, resumed_frame)
