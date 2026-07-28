using PottsToolkit

medium = Medium(:medium)
cell = CellType(:cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 4, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 8,
        (cell, cell) => 2,
    ),
)
problem = PottsProblem(
    model,
    CartesianDomain((4, 4)),
    Layout(LabelledCells(UInt64[1 1 0 0; 1 1 0 0; 0 0 0 0; 0 0 0 0],
        (1 => cell,)));
    capacity = 2,
    tspan = (0, 1),
    seed = 42,
)
algorithm = SequentialCPM(temperature = 0.0f0)
report = backend_report(problem, algorithm)

@assert isvalid(model)
@assert report.qualified
result = (; model_valid = true, backend_qualified = report.qualified,
    lattice = (4, 4))
