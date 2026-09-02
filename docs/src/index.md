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
PottsSystem -> complete / mtkcompile -> PottsProblem
            -> init / solve -> PottsIntegrator / PottsSolution
```

Algorithm, backend, scalar type, seed, and runtime state are late choices.
`mtkcompile` is structural and does not select a device or create a public
executable artifact.

## Start here

- [Author and compose](@ref author-and-compose) introduces the symbolic model.
- [Initialize and execute](@ref initialize-and-execute) runs the model through
  the standard SciML lifecycle.
- [Native MTK components](@ref native-mtk-components) embeds global or
  generation-safe per-cell systems without copying their equations into a
  second representation.
- [Capability status](@ref capability-status) is the exact support and
  limitations table.
- [Wortel 2021](@ref wortel-2021-integration) and [Merks 2006](@ref
  merks-2006-integration) execute complete final-interface integration
  programs during this documentation build.
- [OpenVT monolayer](@ref openvt-monolayer-integration) replaces the retired
  research notebooks with a bounded 11-cell calibration, zero-adhesion
  monolayer, free-surface inhibition classification, and lifecycle recipe.

The published-model programs are API and integration witnesses. They do not
claim paper-source scientific qualification reserved for future scientific
review.

LocalMath, CorePotts, and MakiePotts publish their own package manuals; this
manual covers the high-level Potts authoring and SciML surface.
