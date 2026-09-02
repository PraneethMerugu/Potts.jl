# This deliberately uses only the public compiled-model flow. Keeping the
# complete construction-through-solve workload in one ordinary function gives
# PrecompileTools one compiled latest-world entry boundary for all KA CPU work.
function _potts_precompile_workload()
    cell = CellKind(:precompile_cell; extinction = RetireAtZero())
    medium = MediumKind(:precompile_medium)
    system = PottsSystem(
        name = :PottsPrecompileWorkload,
        statements = StatementSet((
            Lattice((3, 3)),
            cell,
            medium,
            Volume(cell; target = 1.0, strength = 1.0),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
    )
    scheduled = mtkcompile(system)
    labels = zeros(Int, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
    )
    solve(
        PottsProblem(scheduled, initial, (0, 1); seed = 1),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    return nothing
end

PrecompileTools.@compile_workload begin
    _potts_precompile_workload()
end
