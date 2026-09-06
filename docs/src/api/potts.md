# [Potts API](@id potts-api)

The exported API is organized by lifecycle rather than implementation files.

| Task | Primary names |
|:--|:--|
| Author and compose | `PottsSystem`, `StatementSet`, `@statements`, `@named`, `compose`, `extend`, `flatten`, `complete`, `mtkcompile` |
| Declare domains and state | `Lattice`, `CellKind`, `MediumKind`, `SpatialRelation`, `SiteState`, `CellState`, `MediumState`, `ModelState`, `FieldState`, `HistoryState`, `RelationshipState` |
| Declare behavior | `HamiltonianTerm`, `ProposalDrive`, `ProposalConstraint`, `ProposalModifier`, `Synchronous`, `AcceptedCopy`, `LifecycleProcess`, `RelationshipProcess`, `DiscreteFieldEuler`, `Observation`, `Protocol` |
| Author custom terms | `ProposalContext`, `SiteBinding`, `CellBinding`, `ContactBinding`, `RelationshipBinding`, `anchor_value`, `gather` |
| Initialize | `PottsInitialState`, `LabelledCells`, `OwnershipLayout`, `CellPlacement`, `MediumPlacement`, `RandomSitePlacement` |
| Execute | `PottsProblem`, `SequentialCPM`, `CheckerboardSweepCPM`, `CPUBackend`, `MetalBackend`, `init`, `solve`, `step!`, `solve!`, `terminate!`, `remake` |
| Persist and inspect | `checkpoint`, `PottsCheckpoint`, `inspect`, `StateSchema`, `Observations`, `Capabilities`, `ReplayContract`, `runtime_statistics` |
| Native coupling | `NativeComponent`, `NativeInput`, `NativeOutput`, `NativeFieldOutput`, `MethodOfLinesComponent`, `NativeOperatingPoint`, `NativeSolveProfile`, `SerialNativeExecution`, `BatchedNativeExecution`, `MetalNativeExecution` |
| Dynamic identity | `CellIdentity`, `relationship_transaction!`, `CreateCell`, `RemoveCell`, `Transition`, `Divide`, `Retire`, `Create`, `Remove`, `Retune` |

The exact inventory is executable and rejects additions or retired aliases in
the package test suite. A public compiler artifact, early engine selection,
and unpublished compatibility spellings are intentionally absent.

```@example potts_inventory
using Potts
visible_names = names(Potts; all=false, imported=false)
exported = Set(filter(name -> Base.isexported(Potts, name), visible_names))
public_names = Set(filter(name -> Base.ispublic(Potts, name), visible_names))
required = Set((
    :PottsSystem,
    :mtkcompile,
    :PottsProblem,
    :SequentialCPM,
    :CheckerboardSweepCPM,
    :checkpoint,
    :NativeComponent,
    :MethodOfLinesComponent,
))
retired = Set((
    :PottsModel,
    :PottsExecutable,
    :SequentialEngine,
    :CheckerboardEngine,
    :EquationProcess,
    :ExplicitDiffusion,
    :CUDABackend,
    :ROCmBackend,
))
(issubset(required, exported), isempty(intersect(retired, public_names)))
```

Unexported but `public` names form the supported extension and inspection SPI;
they are not additional authoring constructors. See [Extension boundary](@ref
extension-boundary).

## Reference

```@autodocs
Modules = [Potts]
Private = false
```
