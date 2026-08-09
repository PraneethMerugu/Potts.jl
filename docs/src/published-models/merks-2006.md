# [Merks 2006 integration](@id merks-2006-integration)

This serial CPU program exercises the final field-coupled interface for
vasculogenesis mechanisms: a secreted/diffusing/decaying lattice field,
chemotaxis, volume constraint, local connectivity, fixed split order, and
field observation.

It is an integration witness, not a reproduction of the paper's network,
lacuna, branch, or remodeling statistics. Those remain G7 scientific work.

## Substrate disposition

The model boundary is deliberate:

| Mechanism | Owner | Reason |
|:--|:--|:--|
| ownership, volume, chemotaxis, connectivity, and copy scheduling | PottsToolkit | These are CPM lattice and proposal semantics. |
| diffusion, decay, and secretion | bounded `DiscreteFieldEuler()` policy | Diffusion and decay are equation-defined, but secretion is recomputed from the staged, moving endothelial occupancy after each MCS. |

MethodOfLines is the preferred upstream PDE substrate when its checked adapter
can express the complete coupling. The currently qualified
`MethodOfLinesComponent` is output-only: it can publish one discretized field
to a `FieldState`, but it cannot receive the staged cell-occupancy field that
drives Merks secretion. Replacing this program with that adapter would require
a fixed secretion mask or no secretion, either of which changes the modeled
mechanism. Catalyst can own reaction kinetics, but it does not supply this
moving CPM-occupancy/PDE boundary. The narrow built-in stencil is therefore
retained here until a separately qualified native field-input adapter exists.

Within every native symbolic component, MTK retains equations, hierarchy, and
connections; PottsToolkit owns only the explicit typed CPM/state boundary,
cadence, and atomic publication.

The complete reusable source is
[`examples/merks_2006_serial.jl`](https://github.com/PraneethMerugu/Potts.jl/blob/main/examples/merks_2006_serial.jl).
The strict documentation build executes that exact file:

```@example merks_product
using PottsToolkit
program = joinpath(pkgdir(PottsToolkit), "examples", "merks_2006_serial.jl")
include(program)
result = Merks2006Serial.run_merks_2006()
final = last(result.solution)
(
    retcode=result.solution.retcode,
    mcs=final.mcs,
    field_shape=size(final[:concentration]),
    field_total=sum(final[:concentration]),
)
```

This program deliberately uses the named `DiscreteFieldEuler()` policy. It
does not imply a generic PDE-solver claim; the separate checked MethodOfLines
row is documented in [Fields, batching, and ensembles](@ref
fields-batching-ensembles).
