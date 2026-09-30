# Learn

A tutorial on writing models is in preparation. Until then, the authoring surface is
specified in `docs/design/AUTHORING.md` in the repository: a complete model (§1), the
model blocks, energies, relations, lifecycle rules and fields, and the renames from the
earlier packages (§9).

A minimal session:

```julia
using Potts, PottsModels
@named gg = GranerGlazier()
σ0, kinds = graner_glazier_state()
prob = PottsProblem(gg, [ownership => σ0, kind => kinds], (0, 1600); seed = 1)
sol = solve(prob, SequentialCPM())
```
