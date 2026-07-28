using PottsToolkit
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (8, 8); target_volume = 12, tspan = (0, 1), seed = 7)
algorithm = SequentialCPM(temperature = 2.0f0)
profile = CorePotts.algorithm_guarantees(algorithm)
state = problem.u0
cell_id = only(CorePotts.active_cell_ids(state))

@assert CorePotts.finite_volume(state, cell_id) > 0
result = (; lattice_sites = prod(CorePotts.lattice_size(state)),
    occupied_sites = CorePotts.finite_volume(state, cell_id),
    temperature = algorithm.temperature,
    guarantee = profile.guarantee_label)
