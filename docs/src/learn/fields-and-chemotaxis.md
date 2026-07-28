# [Fields and chemotaxis](@id fields-and-chemotaxis)

Fields are declared separately from their realized arrays. This lets one chemotaxis model run
against different gradients without changing the biological declaration.

## Declare a field

A `Field` specifies placement, boundary behavior, and interpolation:

```julia
gradient = Field(
    :chemo_gradient;
    placement = CellCentered(),
    boundary = NoFlux(),
    interpolation = Multilinear(),
)
```

Prescribed arrays are bound when constructing `PottsProblem`. Dynamic field systems have separate
clock, solver, exchange, and backend requirements.

## Declare chemotactic work

`Chemotaxis` binds a field to cell-type sensitivity. The response law and extension/retraction mode
are explicit. Chemotactic work is not folded into a contact-energy table.

```@example fields-and-chemotaxis
using PottsToolkit
import CorePotts

# Declare field semantics once, then bind experiment-specific values.
medium = Medium(:Medium)
cell = CellType(:MigratingCell)
gradient = Field(
    :chemo_gradient;
    placement = CellCentered(),
    boundary = NoFlux(),
    interpolation = Multilinear(),
)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 12, strength = 2)),
    gradient,
    Chemotaxis(gradient, cell => 4),
)
values = repeat(reshape(range(0.0f0, 1.0f0; length = 12), :, 1), 1, 12)
mask = falses(12, 12)
mask[5:7, 5:8] .= true
problem = PottsProblem(
    model,
    CartesianDomain((12, 12)),
    Layout(Place(cell, mask; identity = 1));
    fields = (gradient => values,),
    capacity = 2,
    tspan = (0, 2),
    seed = 21,
)
algorithm = SequentialCPM(temperature = 2.0f0)
report = backend_report(problem, algorithm)
solution = CorePotts.solve(problem, algorithm)

@assert report.qualified
@assert solution.stats.completed_mcs == 2
result = (; problem, report, completed_mcs = solution.stats.completed_mcs,
    retcode = solution.retcode)

(result.report.qualified, result.completed_mcs, result.retcode)
```

The fast source verifies construction and execution. [Follow the Gradient](@ref
chemotaxis-example) adds a centroid-displacement statistic with enough declared copy attempts to
observe directed motion.

## Interpret carefully

Sensitivity changes the strength of field-coupled work. It does not change field steepness.
Changing from extension-only to reciprocal or retraction behavior changes the mechanism. State
which response, mode, field profile, interpolation, boundaries, algorithm, and temperature were
used.

“Chemotaxis” here names an implemented directional mechanism. A claim about a biological assay or
cell type requires a separately admitted model and evidence.
