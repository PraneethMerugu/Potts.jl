# [FAQ and common errors](@id faq)

## Questions

**Why is the first run of a session slow?**
Julia compiles code the first time it runs, and `PottsProblem` generates and compiles code
for your model. The first problem of a session takes tens of seconds; later problems of the
same model, `remake`, and new solves take a fraction of a second. Keep one Julia session open
while you work (the REPL, a notebook, or VS Code).

**How long is a Monte Carlo step in real time?**
One MCS is one copy attempt per site. Its biological duration depends on the model and is
fixed by calibration. Fields and ODEs advance by `mcs_duration` per MCS (default 1), set in
`@sweep`.

**Are runs reproducible?**
Yes. The same problem with the same `seed` gives the same run on the same machine and
algorithm, and ensembles give every trajectory its own reproducible stream (`replica`).
`SequentialCPM` and `CheckerboardCPM` sample the same model with different dynamics, so
their runs differ.

**Why does my cell disappear?**
A cell disappears when it loses its last site. Common causes: a weak area constraint
(`λ` too small for the contact energies), a high temperature, or a target volume of zero.
`@constraint no_extinction` prevents it.

**Why do my cells stick to the edges of the lattice?**
A closed boundary has no neighbours, so a cell at the edge pays no contact energy there.
Use a periodic boundary, a `Frame` of a frozen wall kind with a high contact energy, or start
the cells away from the edges.

**Why is `sol[:surface]` (or another built-in) an error?**
Potts tracks only the quantities the model uses. Add a term that uses it (its strength can be
a parameter set to 0), or compute it from the saved states.

**How do I read results into a DataFrame or a CSV file?**
`sol[:volume]`, `sol[:kind]` and `sol.t` are plain vectors; build a table from them with
DataFrames.jl, or write them with DelimitedFiles.

**Can I use units?**
Yes: declare them as metadata (`λ = 1.0, [unit = u"J"]`) and load DynamicQuantities; the
model is then checked for dimensional consistency when it is compiled.

## Common errors

| Message (abridged) | Cause and fix |
|---|---|
| `model X has no @lattice` / `has no @sweep` | add the section (an `@extend`ed model inherits them) |
| `` `a` is reserved `` | `a` and `b` are the cells of a link; rename the kind or parameter (e.g. `a₀`) |
| `` … has the name of a built-in `` | `volume`, `kind`, `target`, `mcs`, … are built in; choose another name |
| `` model `X` has the field `c`, so `PottsProblem` needs `field_solver = …` `` | pass `PottsProblem(…; field_solver = ExplicitEuler(substeps = n, lower = 0.0))` |
| `` `@sweep` no longer takes `field_solver` `` | solvers are problem keywords: `PottsProblem(sys, op, tspan; field_solver = …)` |
| `` primes exist only for site/field variables `` | `x′` is the other side of a contact pair, for site and field variables; for a cell variable write `x[owner′]` |
| `` `volume` is not available in a drive `` | drives are in the copy scope: write `volume[new]`, `volume[old]` or `volume[owner[target]]` |
| an error naming `rand()` in an energy, drive or constraint | draw the random number in an update and store it in a variable |
| `Scattered: could not place box …` | too many boxes for the region: use fewer, smaller boxes, a smaller `gap` or a larger region |
| `layout: later layers split cell …` (warning) | an overlay cut a cell into pieces; change the layers, or pass `splits = :allow` to the cutting layer |
| `lifecycle: all N cell slots are in use; divisions are deferred` (warning) | pass a larger `capacity` to `PottsProblem` |
| `SequentialCPM runs on the host` | use `CheckerboardCPM()` with a GPU backend |
| a field with huge positive and negative values | the explicit field step is unstable: increase `substeps` in `ExplicitEuler` |
| `Constructor for type "X" was extended … refers to Makie.X` (warning) | your model's name clashes with a Makie name (`Toggle`, `Axis`, …); rename the model |
