# [Runtime and orchestration boundary](@id runtime-boundary)

ProcessBigraphs and the current CorePotts execution engine are separate authorities during the
runtime transition.

## Stable documentation boundary

This manual documents behavior available through the current PottsToolkit, CorePotts, and
MakiePotts interfaces. ProcessBigraphs is an unpublished internal beta with canonical hierarchy,
open composition, serial orchestration, structural transactions, solver and field adapters,
observation, continuation, and logical checkpoint contracts documented inside its package.
Read the
[independent ProcessBigraphs manual](https://praneethmerugu.github.io/Potts.jl/ProcessBigraphs/dev/) for that
qualified boundary; its deployment is versioned separately under the
`ProcessBigraphs` documentation directory.

That internal capability is not presented here as:

- a public runtime release;
- complete upstream parity;
- a replacement for CorePotts;
- evidence that an uncut Potts path uses ProcessBigraphs.

## Coupled-runtime integration

ProcessBigraphs owns when and why coupled computation occurs. CorePotts, SciML solvers, and custom
engines retain authority over how their heavy computation executes inside each authorized
interval. The internal-beta integration includes checked structural add, remove, divide, move, and
rewire transactions, structural restart, and bounded Merks and CNV assemblies.

These capabilities do not automatically replace CorePotts execution or promote a public
ProcessBigraph API. A user-facing PottsToolkit workflow is documented only after its public
integration contract passes, while package-local capability pages record internal runtime
authority and checkpoint compatibility.

## Merge rule for this manual

ProcessBigraph integration documentation enters this structure in three places:

1. **Learn/Examples** only for admitted user workflows;
2. **Concepts and Guarantees** for hierarchy, ports, structural barriers, lifecycle, failure, and
   checkpoint semantics;
3. **API** only for names that have passed the applicable stability gate.

Every page must state its support level and avoid describing a roadmap intention as implemented
behavior. Package-local ProcessBigraphs docs remain the authority for internal adapter and runtime
extension details during incubation.
