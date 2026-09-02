using Potts
using ModelingToolkitBase
using SciMLBase
using Symbolics

@parameters target = 4.0 strength = 1.0 temperature = 2.0
cell = CellKind(:cell; extinction = RetireAtZero())
medium = MediumKind(:medium)
@mtkcompile smoke = PottsSystem(
    statements = StatementSet((
        Lattice((4, 4)),
        cell,
        medium,
        Volume(cell; target, strength),
        Protocol(Sweep(; temperature); name = :main),
    )),
    parameters = [target, strength, temperature],
)

labels = zeros(Int32, 4, 4)
labels[2:3, 2:3] .= 1
initial = PottsInitialState(
    ownership = LabelledCells(labels; cells = [cell], medium)
)
problem = PottsProblem(
    smoke,
    initial,
    (0, 1);
    p = (target => 4.0, strength => 1.0, temperature => 2.0),
    seed = 1,
)
solution = solve(
    problem,
    SequentialCPM();
    backend = CPUBackend(),
    scalar_type = Float32,
)
solution.retcode == SciMLBase.ReturnCode.Success ||
    error("tiny scheduled sequential trajectory did not complete")
last(solution).mcs == 1 || error("platform smoke stopped before one MCS")
