# Current examples

`custom_model.jl` is the complete Potts authoring/continuation tutorial. Run it
after preparing the examples environment with the selected ecosystem checkouts:

```sh
julia --project=examples examples/custom_model.jl
```

Complete activity-migration, field-coupled vasculogenesis and monolayer-division
factories, tutorials and scientific tests now belong to the sibling
`PottsModels.jl` package. Its `docs/src/index.md` introduces the library and its
`tutorials/` directory contains the executable callers. Potts does not retain
duplicate implementations or forwarding execution functions.

The initial library models are bounded CPU examples, not calibrated paper
reproductions. Historical notebooks and design records are not current model
implementations.
