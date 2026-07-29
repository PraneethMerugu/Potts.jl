using PottsToolkit

# Compose contact, volume, shape, and connectivity without a reference wrapper.
medium = Medium(:Medium)
cell = CellType(:ShapeCell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 8, strength = 2)),
    Elongation(cell => (target = 2, strength = 4)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 10,
        (cell, cell) => 4,
    ),
    PreserveConnectivity(),
)
labels = zeros(UInt64, 12, 12)
labels[3:6, 3:4] .= 1
labels[8:11, 9:10] .= 2
problem = PottsProblem(
    model,
    CartesianDomain((12, 12)),
    Layout(LabelledCells(labels, (1 => cell, 2 => cell)));
    capacity = 4,
    tspan = (0, 1),
    seed = 5,
)

@assert isvalid(model)
@assert backend_report(problem, SequentialCPM()).qualified
result = (; model, problem, declarations = length(model.declarations),
    capabilities = capabilities(model))
