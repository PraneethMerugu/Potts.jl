# CorePotts Public Scientific and Execution Interfaces

Status: Accepted architectural and API semantics

Current disposition: superseded in part by the
[G5H Hardening Contract](symbolic-potts-v1-hardening.md). Compatible scientific protocols survive,
but the old breadth, exact public names, algorithm inventory, and maturity claims do not prevent
G5H from narrowing CorePotts into an explicit runtime, compiler SPI, and backend SPI boundary.

## Purpose

This document defines the public Julia interfaces for using and extending CorePotts directly. It
governs scientific components, state access, proposals, trackers, observables, events, algorithms,
topologies, backend specialization, workspaces, validation, and conformance.

CorePotts is independently usable. Direct CorePotts programs do not construct PottsToolkit
authoring IR. They remain governed by the scientific contracts in this specification suite.

The API follows ordinary Julia design: immutable structs, small functions, multiple dispatch,
callable typed values, package extensions, and concise displays. Abstract types communicate genuine
scientific categories; methods and tests establish conformance.

## Scientific Categories

CorePotts defines meaningful category abstractions conceptually equivalent to:

- `AbstractEnergy`
- `AbstractTracker`
- `AbstractEvent`
- `AbstractAlgorithm`
- `AbstractTopology`

The final exported names may preserve compatible existing names where clear. CorePotts does not
require every object to subtype one universal `AbstractComponent`. Relations, schedules,
distributions, capabilities, effects, and other reusable values MAY implement functions without a
shared abstract supertype.

Subtyping communicates category only. It does not prove that required behavior exists.

## Ordinary Julia Extension

Scientific configuration is stored in ordinary immutable parametric structs:

```julia
struct VolumeConstraint{T} <: AbstractEnergy
    strength::T
end
```

Extensions import and add methods to documented CorePotts functions:

```julia
import CorePotts: energy_change, required_properties
```

Behavior is not assembled from dictionaries of callbacks or `Function`-typed fields. A callable is
stored parametrically when needed:

```julia
struct CustomLaw{F}
    f::F
end
```

Concrete immutable closures are permitted when they satisfy the applicable inference, effect,
portability, serialization, and capability requirements.

Every required extension function is documented and public. Internal underscored helpers are not
extension contracts.

## Open Protocol Boundary

Scientific invariants and semantic category taxonomies MAY define closed, versioned sets.
Scientific family membership and execution mechanisms MUST remain open Julia protocols unless an
accepted specification explicitly requires exhaustiveness.

A finite built-in inventory does not define the complete extension surface. A downstream package
MUST be able to add a conforming scientific family member through owned types and documented public
methods without editing a central CorePotts enum, method-signature `Union`, `isa` ladder, or runtime
registry. Closed local result tags remain valid when they are not required of every implementation
of a broader protocol.

Host-level openness does not permit dynamic device dispatch. Model compilation lowers accepted
scientific values into concrete, bounded, device-valid descriptors and operations. GPU-capable
extensions specialize through ordinary dispatch on their concrete compiled types and satisfy the
same allocation, synchronization, effect, RNG, and conformance contracts as built-ins.

Direct Level 3 execution does not require registration. PottsToolkit MAY require versioned
registration for Level 1 spelling, semantic serialization, compatibility translation, or other
boundaries that genuinely require durable names.

Every stable protocol MUST include a downstream-style conformance fixture demonstrating that a
non-built-in implementation works through public interfaces without a CorePotts source edit. A
device-capable protocol fixture MUST compile and run on every backend it claims.

## Stable Scientific Identity

Every stable scientific component declares:

- Stable semantic identity
- Semantic version
- Scientific category
- Required and provided state
- Reads, writes, and effects
- Numerical and RNG behavior
- Backend and dimensional capabilities
- Reference and conformance support
- Provenance and serialization support

The stable identity is independent of the Julia concrete type name. Renaming a type does not by
itself change scientific meaning. Diagnostics and reports include both the stable identity and Julia
type so dispatch problems remain understandable.

## Requirements and Capabilities

Components describe requirements through ordinary functions returning typed immutable values,
conceptually including:

```julia
required_properties(component)
required_observables(component)
required_relations(component)
capabilities(component)
scientific_access(component)
```

Requirements do not use unstructured symbol lists when typed descriptions can carry ownership,
units, precision, lifecycle behavior, and identity.

Capabilities are ordinary values such as an atomic operation requirement, supported dimensions, or
numerical feature. Dictionaries of backend-name booleans are not the stable interface.

Essential category methods have no misleading empty fallback. Empty defaults are provided only for
genuinely optional requirement categories. Public validation reports incomplete interfaces before
problem initialization.

Incidental `hasmethod` discovery does not define scientific support. Explicit declarations and
conformance evidence do.

`scientific_access` is the conservative deterministic-parallel trait. The default is
`UnsupportedScientificAccess`; an extension opts in with `SnapshotScientificAccess`, declaring
every static spatial relation whose simultaneous recipient writes could interact, whether it reads
mutable cell-wide state, and whether proposal-private workspace is required. Parallel algorithm
compilation unions those relations with the proposal and maintained-tracker relations, colors the
realized finite graph, and derives remaining cell-wide conflicts from proposal owner identities.
An undeclared component is rejected rather than silently scheduled under an incomplete conflict
relation.

Direct Level 3 use does not require a global component registry. Julia dispatch provides direct
extension. PottsToolkit maintains a versioned registry only where Level 1 naming, DSL parsing,
normalization, or semantic serialization requires it.

## State Access

Scientific extensions use small public access functions rather than depending on concrete state
field paths. Representative access is conceptually:

```julia
owner_at(state, site)
cell_type(state, cell)
property(state, volume, cell)
```

These accessors are allocation-free and inline in hot code. They preserve freedom to change
structure-of-arrays layout, compiled indices, backend storage, and tracker implementation.

Typed semantic identifiers remain visible at the scientific interface. Raw backend arrays, dense
property offsets, and mutable workspace fields belong to explicit execution interfaces.

## Proposal Interface

Energy and transaction operations receive a small immutable proposal value rather than an expanding
list of positional source and destination arguments.

The proposal contains the scientifically relevant local move information, such as source and
destination sites and owners, types, direction identity, phase, and semantic proposal identity where
applicable. It does not own backend arrays or global mutable state.

Proposal construction and fields follow the accepted proposal, time, topology, and RNG contracts.

## Energy Interface

An energy component implements a public operation conceptually named:

```julia
energy_change(component, proposal, state)
```

`energy_change` is pure with respect to simulation state. It returns the component's exact local
energy difference for the proposal under its declared snapshot and does not update trackers, consume
task-local randomness, or commit state.

The readable ASCII name `energy_change` is preferred for the stable API. A documented mathematical
`ΔH` alias MAY be provided. Historical `delta_H` methods receive a migration path where their
semantics are unambiguous.

Every optimized energy component has a simple ordinary CPU/scalar reference implementation wherever
feasible. Fused and backend-specialized implementations are tested against that behavior.

## Mechanical Interface

A stateful non-equilibrium mechanical component implements pure proposal work through
`mechanical_work(component, proposal, state, transaction)` and a separately declared state-update
law. Mechanical work remains a distinct field in proposal diagnostics even though the acceptance
law consumes `delta_h + mechanical_work`. It is not smuggled into a Hamiltonian or drive category.

Stable volume pressure and surface tension use ordinary immutable component values, per-cell
auxiliary property columns, tuple folds specialized by Julia dispatch, and one fused cell-indexed
update kernel for all mechanics. Their CPU scalar transition is the reference for CPU and GPU
kernels. Component instance IDs, state-property keys, access traits, initialization, and lifecycle
requirements are validated before execution.

The first executable consumer of a proposed stable scientific protocol MUST be the sequential
reference engine. A public protocol remains provisional for API-freeze purposes until it has been
used by that engine, tested through a complete MCS, and—when it has a PottsToolkit spelling—reached
through one authoring-to-CorePotts compilation path. This permits breaking refinements before the
paper API freeze when executable use exposes a poor abstraction.

## Trackers and Observables

Authoritative lattice and cell state are distinguished from derived maintained quantities. A
tracker is not the scientific source of truth.

A tracker definition describes a scientific quantity and update law. Mutable tracker arrays live in
compiled state or workspaces, not in the immutable tracker definition.

Tracker update consumes accepted transaction information through an interface conceptually like:

```julia
update!(tracker_state, tracker, accepted_move, state)
```

Initialization, complete reconstruction, incremental update, and validation are separate operations.
Incremental behavior must equal reconstruction under the applicable numerical contract.

The stable compiled derived-observable seam consists of `compile_derived_observable`,
`derived_observable_arrays`, `stage_derived_observable_delta`, and
`apply_derived_observable_delta!`, plus the lifecycle repair operations
`compiled_prepare_derived_division!`, `compiled_accumulate_derived_division!`, and
`compiled_retire_derived!`. A compiled storage value is an adaptable concrete array tree; its
definition remains host-side. These names generalize the current moment-storage slot without making
moment tensors the universal observable representation.

An observable is what a scientist requests. A tracker is one possible maintained implementation.
Some observables are computed on demand. Components request scientific observables; compilation
chooses and deduplicates compatible implementations.

Users ordinarily do not select implementation caches manually. Explicit stable tracker selection
remains possible for advanced use.

## Events and Effects

Scientific events evaluate triggers and produce typed effects. They do not directly mutate arbitrary
state.

Effects include the accepted categories for property transactions, division, death, transition,
field coupling, observation, and termination. The engine validates conflicts and commits effects
according to lifecycle and transaction semantics.

A Level 4 event implementation MAY launch custom kernels. It still declares scientific effects,
workspace requirements, capabilities, ordering, failure behavior, and reference behavior. Kernel
launch code is not itself the scientific event definition.

## Algorithm Interface

Algorithms are ordinary immutable values passed through the SciML-shaped interface:

```julia
solve(problem, CheckerboardSweepCPM(...))
```

They contain scientific algorithm configuration and guarantee selection, not live streams, backend
buffers, or workspaces.

Every stable algorithm returns one immutable `AlgorithmGuaranteeProfile` through
`algorithm_guarantees`. The profile has a fixed schema for proposal process, equilibrium status,
kinetic interpretation, transaction semantics, MCS normalization, reproducibility scope,
compatible component scopes, validation evidence, backend contract, and dimensions. Algorithm
extensions returning an ad hoc symbol, tuple, or mapping fail interface validation. An initialized
scientific integrator delegates `algorithm_guarantees(integrator)` to its selected algorithm, so
execution provenance retains the exact profile without copying mutable state into the algorithm.

Workgroup size, tile size, scratch strategy, and similar performance choices are execution policy
unless an accepted algorithm contract explicitly makes them observable. Scientists do not construct
backend-named algorithm variants for equivalent behavior.

A backend-specific execution specialization preserves the corresponding scientific algorithm
contract and declares its narrower capabilities. If its transition law differs, it is a separately
named scientific algorithm rather than a hidden specialization.

## Topology Interface

A scientific topology describes relations, canonical offsets or adjacency, weights, direction
ordering, periodic behavior, boundary semantics, and dimensional capabilities. It does not return or
own prebuilt device arrays as its public scientific meaning.

Compilation lowers topology descriptions to backend storage and optimized query structures. Custom
topologies conform through documented functions and traits rather than direct knowledge of internal
cache fields.

## Backend Specialization

Backend support is added through Julia package extensions and multiple dispatch. CUDA, AMDGPU, and
Metal are not unconditional CorePotts dependencies.

Scientific component methods normally target portable operations and capabilities. A measured
backend specialization dispatches on a backend or execution operation in the appropriate package
extension. Scientific code does not scatter `isa CuArray` or backend-name conditionals.

The same scientific component value normally runs on CPU and supported GPUs. Types such as
`CUDAVolumeConstraint` and `CPUVolumeConstraint` are not the user-facing representation of one
scientific law.

## Adaptation and Workspaces

Scientific values remain ordinary host-side values until compilation. Individual scientific
interfaces do not require users to call `Adapt.adapt`.

Compilation creates concrete descriptors and centrally adapts compiled state and execution data.
Components declare temporary storage requirements; the compiled execution plan or workspace owns
and reuses mutable arrays.

Scientific definitions do not hide device allocations or synchronization. Extension methods launch
asynchronously by default. Host synchronization occurs only at accepted observation, error,
transfer, and solve boundaries.

## Component Collections and Compilation

Users may naturally provide individual objects, tuples, vectors, or fragments. The public API does
not promise that this input container becomes the execution layout.

Compilation chooses static tuples, descriptor arrays, grouped operations, or another representation
according to component count, inference, compile latency, memory behavior, and measured performance.
It preserves stable scientific identity and order-independent semantics.

Compatible duplicate requirements are deduplicated. Conflicting observable definitions, numerical
policies, schemas, or effect providers require an explicit resolution.

## Validation

CorePotts provides public validation for each scientific category. Validation reports missing
required methods, invalid metadata, unresolved requirements, unsupported capabilities, numerical
conflicts, and backend limitations before simulation execution.

An incomplete extension does not first fail as a GPU `MethodError`. Multiple independent interface
problems are reported together where safe.

Validation is based on declared interfaces and representative calls, not inheritance alone.

## Conformance Helpers

CorePotts provides category-oriented test helpers conceptually equivalent to:

```julia
test_energy_component(component)
test_tracker(tracker)
test_event(event)
test_algorithm(algorithm)
test_topology(topology)
```

They test as applicable:

- Interface completeness
- Reference behavior
- Scientific invariants
- Rebuild-versus-incremental equivalence
- Transaction and effect behavior
- RNG and numerical contracts
- Allocation and synchronization behavior
- CPU and declared GPU capabilities
- Cross-level equivalence fixtures

Passing a helper is required evidence but does not replace component-specific scientific tests.

## Stable Level 4 Boundary

CorePotts exposes a small stable execution-extension protocol for custom operations, kernels,
workspaces, capabilities, and algorithm specializations. Its launch interface accepts portable
operations, logical ranges, workspace data, and execution policy without exposing the full internal
scheduler.

Compiler passes, concrete workspace layouts, internal kernel names, cache field paths, and backend
workarounds remain explicitly internal or experimental unless separately promoted.

Stable Level 4 functions are documented public extension points. Underscored functions are never
required for conformance.

## Display and Inspection

Scientific components, algorithms, topologies, problems, and plans have concise Julia `show`
methods. Displays lead with scientific configuration and identity rather than internal type
parameters, device buffers, or compiler data.

Detailed inspection reports requirements, effects, capabilities, provenance, execution selection,
workspace use, and backend qualification separately.

## Conformance Requirements

- CorePotts is usable without PottsToolkit authoring IR.
- Scientific categories are meaningful and do not collapse into a universal component hierarchy.
- Immutable structs and ordinary public methods form the extension interface.
- Subtyping alone never establishes conformance.
- Scientific accessors isolate extensions from concrete state fields without adding hot-path
  allocation.
- Energy evaluation is pure and agrees with a reference implementation.
- Tracker incremental state agrees with reconstruction.
- Events produce typed effects rather than arbitrary mutation.
- Algorithm values contain scientific configuration rather than execution resources.
- Topology meaning is independent of compiled backend storage.
- Backend specializations use extensions and preserve scientific contracts.
- Workspaces centrally own temporary mutable storage.
- Extension methods do not hide allocation or host synchronization.
- Validation catches incomplete interfaces before GPU execution.
- Public conformance helpers exercise every stable extension category.
- Stable execution protocols are separated from replaceable internals.
- The sequential reference engine can execute a complete normalized MCS through public scientific
  protocols without legacy `PottsState` fields.
- Public protocol freeze follows executable reference and PottsToolkit compilation evidence, not
  interface-shape tests alone.
