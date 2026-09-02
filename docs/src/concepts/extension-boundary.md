# [Extension boundary](@id extension-boundary)

Potts has several deliberately narrow extension seams. None is a second
modeling engine or a general plugin registry.

1. A native ModelingToolkit component remains an upstream system. The full-MTK
   extension structurally compiles it and constructs its standard SciML
   problem/integrator. Potts owns only the typed CPM coupling map,
   cadence, time conversion, lifecycle transfer policy, and capability check.
2. A new kernel-safe Potts operation uses the documented Potts
   operation/descriptor transfer API and the smallest necessary part of
   `CorePotts.CompilerSPI`.
3. A backend or transactional runtime extension uses the smallest necessary
   part of `CorePotts.BackendSPI`.
4. Reusable local connectivity and conflict handling uses LocalMath' own
   declaration, preparation, and extension protocols. Domain physics, clocks,
   RNG, transaction semantics, and checkpoints stay above LocalMath.

Choose the seam by responsibility:

| Extension author | Supported surface | Must not own |
| --- | --- | --- |
| Scientific model author | exported Potts authoring API | compiler IR, backend admission |
| Potts operation or term package | Potts transfer API and the required `CompilerSPI` bindings | runtime queues, device evidence, checkpoints |
| Runtime or backend package | required `BackendSPI` bindings | compiler IR, scientific semantics, self-issued support claims |
| Local-work mechanism package | LocalMath public extension protocol | Potts acceptance, RNG, clocks, lifecycle commits |
| ModelingToolkit integration | Julia package extensions and public MTK/SciML interfaces | either CorePotts SPI unless it also implements one of the roles above |

The two CorePotts SPI modules are flat, explicit facades over CorePotts-owned
bindings. They do not wrap or duplicate those implementations, and their public
name sets are disjoint. Keeping the facades explicit makes imports, ownership,
and compatibility review visible to Julia tooling. Nested role modules or a
registration framework would add ceremony without improving dispatch or
separation. Every new SPI binding must identify its owner, a concrete external
consumer, and a contract test; otherwise it remains private.

Production code must not reach private package fields, mix the two SPI roles,
or create a parallel scheduler, state store, RNG, or checkpoint.

GPU support requires device conformance for the exact mechanism; CPU
compilation is not device support. External code may provide functional
execution, but exact replay additionally requires a matching package, source,
version, and environment identity.

The public extension-oriented names are distinguishable from the exported
authoring API:

```@example extension_inventory
using Potts
visible_names = names(Potts; all=false, imported=false)
exported = Set(filter(name -> Base.isexported(Potts, name), visible_names))
public_names = Set(filter(name -> Base.ispublic(Potts, name), visible_names))
extension_api = setdiff(public_names, exported)
(:PottsSystem in exported, :operation_transfer in extension_api)
```
