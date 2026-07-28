using PottsToolkit
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

@assert exact_lattice
@assert resumed.t == uninterrupted.t == 6
result = (; problem, algorithm, checkpoint, exact_lattice,
    resumed_mcs = resumed.t)
