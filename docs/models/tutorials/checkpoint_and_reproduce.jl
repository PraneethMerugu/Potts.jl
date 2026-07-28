using PottsToolkit
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (10, 10); target_volume = 12, tspan = (0, 4), seed = 33)
algorithm = SequentialCPM(temperature = 2.0f0)
uninterrupted = CorePotts.init(
    problem, algorithm; save_start = false, save_end = false)
CorePotts.step!(uninterrupted, 2)
checkpoint = CorePotts.capture_checkpoint(uninterrupted)
resumed = CorePotts.restore_checkpoint(checkpoint, problem, algorithm)
CorePotts.step!(uninterrupted, 2)
CorePotts.step!(resumed, 2)
expected = CorePotts.logical_state(uninterrupted)
observed = CorePotts.logical_state(resumed)

@assert CorePotts.lattice_storage(expected) == CorePotts.lattice_storage(observed)
@assert checkpoint.mcs == 2
result = (; checkpoint, exact_lattice_continuation = true,
    final_mcs = resumed.t)
