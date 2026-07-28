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
field_run = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials",
    "fields_and_chemotaxis.jl"))
(field_run.report.qualified, field_run.completed_mcs, field_run.retcode)
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
