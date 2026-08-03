using PottsToolkit
using ModelingToolkitBase
using SciMLBase
using Symbolics

@parameters target = 4.0 strength = 1.0 temperature = 2.0
cell = CellKind(:cell; extinction = RetireAtZero())
medium = MediumKind(:medium)
@named smoke = PottsSystem(
    statements = StatementSet((
        Lattice((4, 4)),
        cell,
        medium,
        Volume(cell; target, strength),
        Protocol(Sweep(; temperature); name = :main),
    )),
    parameters = [target, strength, temperature],
)
executable = compile(
    complete(smoke);
    engine = SequentialEngine(),
    backend = CPUBackend(),
    scalar_type = Float32,
)
labels = zeros(Int, 4, 4)
labels[2:3, 2:3] .= 1
initial = PottsInitialState(
    ownership = LabelledCells(labels; cells = [cell], medium)
)
solution = solve(PottsProblem(executable, initial, (0, 1); seed = 1))
solution.retcode == SciMLBase.ReturnCode.Success ||
    error("tiny sequential trajectory did not complete")
