# Potts.jl

Potts.jl is a ModelingToolkit-native cellular Potts stack with four explicit
package responsibilities:

| Package | Responsibility |
|:--|:--|
| `Potts` | Symbolic authoring, composition, structural compilation, native MTK coupling, and the SciML lifecycle |
| `CorePotts` | MTK-free CPM execution, identity, lifecycle, relationships, checkpoints, and CPU/GPU backend contracts |
| `LocalMath` | Backend-portable validated local connectivity, bounded conflict handling, workspace, lifetime, and inspection beneath CorePotts |
| `MakiePotts` | Visualization from public saved observations and solutions |

The public lifecycle is:

```text
PottsSystem -> PottsProblem (complete / mtkcompile)
            -> init / solve -> PottsIntegrator / PottsSolution
```

Algorithm, backend, scalar type, seed, and runtime state are late choices.
`PottsProblem` invokes the structural, idempotent `mtkcompile` boundary for an
authored model. Call `mtkcompile` yourself when you want to inspect that
boundary; it does not select a device or create a public executable artifact.

## Start here

- [Author and compose](@ref author-and-compose) introduces the symbolic model.
- [Build a custom model](@ref custom-model) combines transparent functions,
  gathered reductions, tracker projections, state, relationships, lifecycle,
  and checkpoint continuation in one executable workflow.
- [Initialize and execute](@ref initialize-and-execute) runs the model through
  the standard SciML lifecycle.
- [Native MTK components](@ref native-mtk-components) embeds global or
  generation-safe per-cell systems without copying their equations into a
  second representation.
- [Capability status](@ref capability-status) is the exact support and
  limitations table.
- [Model library](@ref model-library) explains the PottsModels ownership of
  reusable scientific factories, initializers, tutorials and model-level tests.

PottsModels' initial activity, vasculogenesis and division tutorials are bounded
API examples, not calibrated paper reproductions. Potts retains minimal
authoring and execution examples and their defending tests.

LocalMath, CorePotts, and MakiePotts publish their own package manuals; this
manual covers the high-level Potts authoring and SciML surface.
