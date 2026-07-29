# [Adhesion and mechanics](@id adhesion-and-mechanics)

Mechanics in PottsToolkit is composed from explicit terms. A term being available does not imply
that every combination or algorithm has the same scientific qualification.

## Contact energy

`Adhesion` lowers a complete symmetric pairwise contact law. Include every admitted medium and cell
type pair. Missing entries fail validation instead of receiving a hidden default.

Lower contact energy favors an interface relative to a higher-energy alternative; it is not a
literal molecular binding energy without study-specific calibration.

## Shape constraints

- `Volume` penalizes deviation from target lattice-site count.
- `Surface` penalizes a declared boundary measure.
- `Elongation` uses the supported major-axis RMS shape measure.
- `PreserveConnectivity` rejects copy attempts that would fragment a finite cell.

Fluctuating variants add explicit mechanical noise and state rather than overloading algorithm
temperature.

```@example adhesion-and-mechanics
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

(isvalid(result.model), result.declarations, result.capabilities)
```

The canonical source composes adhesion, volume, elongation, and connectivity for two sparse
endothelial cells. The example name describes the mechanism; it does not claim a validated
angiogenesis reproduction.

## Parameter discipline

Change one interpretation at a time. Volume target, volume strength, contact energy, elongation
target, elongation strength, connectivity, algorithm, and temperature all affect behavior
differently. Record the normalized model fingerprint and exact algorithm when comparing runs.

For a publishable shape claim, define a quantitative statistic—such as aspect-ratio distribution,
network connectivity, or interface length—plus burn-in, replicates, and uncertainty. A visually
plausible frame is not that evidence.
