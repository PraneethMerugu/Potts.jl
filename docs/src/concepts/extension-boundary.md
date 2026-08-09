# [Extension boundary](@id extension-boundary)

PottsToolkit has two extension seams and neither is a second modeling engine.

1. A native ModelingToolkit component remains an upstream system. The full-MTK
   extension structurally compiles it and constructs its standard SciML
   problem/integrator. PottsToolkit owns only the typed CPM coupling map,
   cadence, time conversion, lifecycle transfer policy, and capability check.
2. A new kernel-safe Potts operation uses the documented PottsToolkit
   operation/descriptor transfer API and the named `CorePotts.CompilerSPI` or
   `CorePotts.BackendSPI`. Production code must not reach private package
   fields or create a parallel scheduler, state store, RNG, or checkpoint.

GPU support requires device conformance and evidence for the exact mechanism;
CPU compilation is not device qualification. External code without reviewed
package, source, version, and environment identity is functional at most and
cannot manufacture replay evidence.

The public extension-oriented names are distinguishable from the exported
authoring API:

```@example extension_inventory
using PottsToolkit
authoring = Set(names(PottsToolkit))
extension_api = Set(names(PottsToolkit; all=false, imported=false))
(:PottsSystem in authoring, :operation_transfer in extension_api)
```
