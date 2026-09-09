# Proposed end-state authoring API

This is the concrete author-facing companion to the
[PR-chain plan](authoring-and-model-ecosystem-plan.md). It describes the experience
we should implement, not an API available on today's package mains. Constructors,
keywords, and signatures below are design proposals unless already present in the
packages. They are not an accepted replacement for the project charter.

The [consolidated dependency map](consolidated-pr-dependency-map.md) assigns the
current delivery bundles and actual planned repository PRs. P01–P16 labels in
this overview identify feature responsibilities, not one GitHub PR each.

The two complete single-file examples are:

- [Cell sorting](examples/cell_sorting.jl): a small model with parameters, initial
  labels, two populations, energies, execution, a success check, and a parameter
  experiment. This is the low-friction entry point.
- [Mechanochemical tissue](examples/mechanochemical_tissue.jl): an explicitly
  two-dimensional active tissue with a conserved ligand field, intracellular
  storage, vector polarity, activity memory, geometry, contact sensing, native
  ODEs, links, division, retirement, observations, experiments, and continuation.
  All declarations and the initialization/execution functions are in one file.

Neither file is currently runnable. Both are Julia-syntax checked without loading
packages, expanding macros, compiling models, or running simulations. Numerical
values are illustrative nondimensional choices, not a validated biological model.
The amount of commentary in the long file is tutorial material, not required
authoring ceremony.

## Ergonomic target: the long file is a semantic walkthrough

The strengthened [ideal spec](../spec/ideal_api_vision.md) and
[research rationale](authoring-design-research.md) distinguish implementation
capability from a good ordinary authoring interface. The full file intentionally
spells out bindings and maintenance to expose the science; it is not the final
syntax to freeze after the PRs.

| Visible mechanical detail in the file | Required ordinary authoring experience | PR owner group |
| --- | --- | --- |
| Repeated cell binding, domain and anchor | Establish scientific scope once; explicit constructor form remains available | P07, P11 |
| Separate state/quantity/process inventory tuples | Collect declarations once, retain imported references, order the same process identities | P11 |
| Handwritten moments for ordinary geometry | Scientific volume/centroid/shape references sharing maintained geometry | P09 |
| General fold for a mean | Familiar reductions with correct typed empty/invalid behavior | P08 |
| Registered helper for ordinary composed arithmetic | Trace supported math; register only a genuinely opaque/contextual operation | P03, P07 |
| Full native binding and lifecycle boilerplate | Bind equations/quantities once; infer only routine, provably valid synchronization | P12, P13 |
| Repeated floating type choices | One default numerical policy with explicit fixed-type overrides | P07, P12 |
| Repeated per-quantity lifecycle plumbing | Concise scientific policies with validated component-level defaults/exceptions | P13 |

These conveniences produce the existing declarations; they do not introduce
another model representation, runtime builder or private PottsModels facade.
The exact scoped syntax is selected with executable P07/P11 consumers. Initial
data, actual equations, material conservation, sampling order, partition and
algorithm choices remain visible. A shorter example achieved by hiding those
choices is not success.

In particular, a ready-made model running successfully, low-level constructors
supporting every operation, and a scientist easily inventing a new mechanism
are separate outcomes. The PRs must deliver all three through ordinary model
examples and tests, not just a final tutorial rewrite.

## The central API promise

An author declares scientific quantities and laws once. The same quantity
reference can appear in an energy, a drive, an ODE input, a process, a lifecycle
predicate, a saved observation, or a plot. The author does not bind tracker arrays,
reconstruct cell indices, write mutation notifications, or manually synchronize
native state.

The smallest useful architecture is:

```text
ordinary Julia functions and model factories
  → PottsSystem: declarations, equations, relationships, scientific ordering
  → PottsProblem: initial conditions, parameter values, span, seed
  → solve/init: CPM algorithm, backend, precision, native solver profiles
  → saved solution: scientific quantities, observations, lineage, failures
```

This extends the existing Potts/SciML direction. It does not introduce a second
model language, registry, simulation executor, or custom experiment framework.
`complete` and inspection remain available, but ordinary users should not need to
call a compiler pipeline to run a model.

### Existing foundations versus proposed extensions

| Surface | Status relative to inspected package mains |
|---|---|
| `PottsSystem`, statement composition, completion, `PottsProblem`, solve/init | Existing architectural foundations; these files propose additional accepted arguments and consumers |
| State declarations, trackers, native components, relationships, lifecycle | Existing but narrower facilities; the uniform reference model and combinations shown here require the chain |
| Structured state, compound effects, arbitrary admitted quantity consumers | Significant P06–P11 extensions, not just new spelling |
| Mutable-field aggregates and automatic affected-link energy | P09–P10 scientific/compiler work |
| Derived native inputs, conservative `Transfer`, ordered multi-cadence coupling | Proposed P12 interfaces and implementation |
| Cross-component lifecycle and held-value/native restart behavior | Proposed integrated P13 contracts building on earlier state support |
| `PottsModels` factories and tutorial environment | New package work; names such as `Diffusion` and `CueAlignment` are illustrative public designs |
| Uniform `explain`, quantity channels, broader saved observations | Proposed extensions over existing inspection and visualization facilities |

Even where a constructor name already exists, the exact call in an example is
not a compatibility promise for the current release.

## What goes into the full model

| Layer | Author declares | Implementation is responsible for |
|---|---|---|
| Space | Lattice size, spacing, boundary, proposal/contact relations | Valid geometry, neighborhoods, backend lowering |
| Populations | Cell kinds, medium, extinction policy, capacity | Stable cell identity, generations, live-domain iteration |
| Numerical parameters | Energy strengths, rates, thresholds, time intervals | Symbol binding, defaults, validation, problem remaking |
| Owned state | Scalar/vector/site/field values and lifecycle rules | Storage, initialization, publication, adaptation, restore |
| Derived quantities | Expressions, aggregates, gathers, sampling cadence | Dependency closure, incremental maintenance, freshness |
| Conservative energy | State expressions over cells or links | Affected contributions and correct before/after energy |
| Active mechanisms | Proposal biases, accepted effects, boundary processes | Proposal context, snapshots, conflict checks, settlement |
| Native equations | MTK system and explicit input/output bindings | Solver coupling, held inputs, publication, reinitialization |
| Material exchange | Source, destination, rate, capacity, allocation policy | A single feasible conservative transaction |
| Relationships | Endpoint meaning, payload, creation/removal/retuning | Relation identity, degree/capacity checks, adjacency maintenance |
| Lifecycle | Conditions, division geometry, inheritance, retirement | Atomic identity/state/native/link updates and lineage |
| Scientific time | CPM sweep, due stages, order, physical interval | Consistent clocks, restart phase, boundary publication |
| Experiment | Initial data, numerical profile, save policy | Execution, retained results, meaningful failures |

### 1. Quantities are references, not names looked up in buffers

`free_ligand`, `internal_ligand`, `polarity`, and `receptor` are authoritative
state declarations. `volume`, `center`, `covariance`, and
`environment_concentration` are derived references. Both kinds use the same
symbolic indexing and consumer interfaces.

`c = CellBinding(:cell)` declares an expression's bound cell. It is not a concrete
cell slot. Each per-cell expression or native mapping specifies its anchor.
`s` similarly binds sites; relationship/contact bindings expose semantic
endpoints. A concrete saved state is indexed by the quantity reference, not by a
compiler-generated storage symbol.

The proposed `FieldState(...; interpretation=:amount_per_site)` describes an
extensive amount. Dividing by voxel volume produces concentration. Units are
explicitly nondimensional in these examples. The broader quantity work must
validate physical units when supplied; the example does not pretend that plain
floating-point constants demonstrate dimensional checking.

Scalar precision is structural here. The full factory takes `scalar_type` and
uses it for scalar and fixed-vector state. Selecting a Float32 solver may not
silently reinterpret a model that explicitly declares Float64 values.

### 2. Geometry and sensing should look like mathematics

The short `aggregate(source; over, by, groups)` form means an additive reduction
with known identity and retraction semantics. In the example:

```julia
site_count = aggregate(1;
    name=:site_count, over=sites(lattice), by=owner, groups=population)
exposure_amount = aggregate(free_ligand;
    name=:exposure_amount, over=sites(lattice), by=owner, groups=population)
environment_concentration = derived(:environment_concentration;
    domain=population, anchor=c,
    expression=exposure_amount[c] / volume[c])
```

`owner` is the declared grouping map. It is not an instruction to scan the entire
lattice at every proposal. Field changes, ownership changes, lifecycle events,
and restoration must all maintain the same aggregate correctly.

`outer`, `site_position`, `before`, and `after` in the full file are proposed
semantic operations, not arbitrary callbacks into simulation internals.
`before(center[c], copy)` and `after(center[c], copy)` refer to the same logical
copy transaction. They allow actual centroid displacement to be accumulated
without duplicating geometry arithmetic in the model.

The contact relation explicitly requests distinct neighboring cells. That is
different from counting lattice contact bonds. `gather` follows that measure;
the fold states empty-neighborhood, invalid-input, and ordering behavior.
Structured vectors and tensors must be legal values, not collections of
unrelated manually synchronized scalar trackers.

Functions composed from supported symbolic mathematics need no extra registration.
Genuinely opaque primitives use LocalMath's public mathematical interface;
contextual operations additionally declare their scientific reads. An arbitrary
function is not assumed to have an
incremental law, derivative, conservative energy interpretation, or GPU method.
For a genuinely new aggregate algebra, an advanced author must supply its actual
identity/combine/retraction or rebuild law and relevant scientific tests. A
missing law should be explained, not hidden behind a generic callback.

### 3. State, memory, and sampling have different meanings

| Quantity | Meaning | When it changes |
|---|---|---|
| `internal_ligand` | Independent intracellular material store | Uptake and lifecycle |
| `exposure_amount` | Sum of existing field values under a cell | Field or ownership changes |
| `volume`, `center`, `covariance` | Live geometric quantities | Ownership and lifecycle |
| `motion` | Accumulated centroid displacement | Accepted copies; boundary reset |
| `activity` | Site memory of successful protrusion | Ownership/activation and decay |
| `sampled_shape` | Deliberately held shape measurement | Every five MCS and lifecycle initialization |
| `receptor`, `cycle`, `damage` | Published native outputs | Native settlement and lifecycle |

A sampled measurement is not a live per-proposal invariant. An observation save
schedule is not a process clock. A future history quantity must similarly state
its sample clock, lag interpretation, initialization, retention, and lifecycle
behavior; saving solution frames does not provide hidden runtime history.

### 4. Energies, drives, and constraints stay distinct

`HamiltonianTerm` declares a state energy. The spring energy uses the positions
of both link endpoints. A candidate copy must include every affected incident
spring, even when the authored expression is compact. This needs conservative
dependency closure, not merely a bounded local read stencil.

Parallel execution additionally needs read/write conflict closure. Two distant
proposals can change opposite endpoints of the same spring while having disjoint
copy-owner claims. Their independently evaluated energy differences generally
do not equal the joint change. The reference tissue example therefore uses
`SequentialCPM`; checkerboard CPU/Metal must prove or reject the complete
dependency/conflict combination. Existing narrow checkerboard admission is not
evidence that every proposed relationship expression is already safe.

`ProposalDrive` declares an active bias such as polarity or chemotaxis. It is not
silently reinterpreted as an equilibrium Hamiltonian. Its guard must run before
the body so a medium proposal cannot perform an invalid cell-state lookup.
`LocalConnectivity` is a separate hard constraint with its own declared scope;
it does not claim all possible global topology guarantees.

The complete tissue model is nonequilibrium: it includes growth, motility,
uptake, damage, and changing links. The separate equilibrium example requires an
actual transition law and balance tests. Naming a CPM energy is insufficient.

### 5. Processes are explicit transactions

An accepted-copy process executes only for a successful ownership change.
Its effects share that transaction. The example updates both affected cells'
centroid-displacement memory and initializes site activity for the new owner.

A `SynchronousProcess` evaluates all right-hand sides from the stage-entry
snapshot. Its multiple outputs publish together. The polarity process therefore
can use `motion[c]` and reset it in one declaration without reading the reset.
Sequential process stages, in contrast, see previous successful publications.

Legitimate multiple updates are explicitly ordered: activation then decay, for
example. Unordered competing writers are an error. Native output ownership and
lifecycle initialization are declared publication authorities, not independent
mutable copies of the same scientific state.

### 6. Reciprocal coupling conserves a named physical amount

The example conserves:

```text
total ligand = sum(free ligand over every lattice site)
             + sum(internal ligand over every live cell)
```

Free ligand permeates all sites, including occupied ones. Occupancy does not
displace it. `exposure_amount` is only a view of free ligand and must not be added
again to the conservation equation.

Diffusion uses zero-flux boundaries. Uptake is one `Transfer`, not an independent
subtract followed by add. Requested transfer is limited by available source
material and remaining destination capacity. Allocation policy is explicit;
negative values must not be repaired by discarding mass. Shrinking an already
over-capacity cell stops new uptake rather than clipping its existing store.

Division partitions internal material conservatively with an explicit rounding
residual rule. Retirement deposits it to the pre-removal footprint before
deleting the identity. The signaling ODE does not consume ligand. A future
binding/consumption mechanism must introduce its bound/product pools and account
for them in the conservation equation.

### 7. Native systems remain native systems

The intracellular equations are a normal ModelingToolkit system. Inputs are
derived quantities, not hidden temporary cell arrays. Native outputs map back
to the declared receptor/cycle/damage quantities. Inputs are held for the stated
physical interval; a due native batch samples a common input snapshot.

`FromPublishedState()` initializes native unknowns from those mapped quantities.
After division, the declared daughter policies are applied first, and each native
daughter system is reinitialized from its published state. Retirement disposes
of its native instance. The implementation owns identity-safe mappings and
invalidation.

Here `r`, `z`, and `d` are actual native unknowns. This policy is not a promise
to initialize an arbitrary algebraic observed output backwards: an output such
as `y = x^2` does not uniquely specify `x`. Other mappings need a supported native
initialization problem or an explicit error. Symbolic indexing and selected IO
must be resolved after native simplification, without guessed numeric indices.

Solver choice is outside the scientific model. The example requests a CPU
sequential/Float64 reference profile with batched Tsit5 solves. P12 expands useful
CPU checkerboard/native combinations, but admission also depends on P10's
whole-model conflict analysis. A separate commented Metal/Float32 example
requests a different native solver profile; its support must be tested, not
inferred from the presence of a backend keyword.

### 8. The complete scientific order is visible

| Position | Stage | Visibility and purpose |
|---|---|---|
| During sweep | CPM proposals and accepted effects | Live geometry; current held native/field values; accumulate motion |
| 1 | Diffusion | Advance free ligand for the physical interval |
| 2 | Uptake | Use diffused field; transfer material; refresh exposure |
| 3 | Sample shape when due | Refresh the existing held quantity every five MCS |
| 4 | Intracellular ODE | Read current field/storage and held shape; publish outputs |
| 5 | Align polarity | Use accumulated displacement and current cue; reset motion |
| 6 | Decay activity | Reduce site memory for the next sweep |
| 7–9 | Relax, rupture, then form links | Each stage sees previous updates; formation is due every ten MCS |
| 10 | Lifecycle batch | Retirement wins competing requests, then admissible division |
| After settlement | Observe/checkpoint | Expose only successfully committed scientific state |

The proposed full-step atomicity contract includes the ownership sweep, native
work, transfers, and lifecycle. A failed step must not leave half-published
results, advanced clocks, or consumed random counters. Efficient rollback is an
implementation obligation requiring tests and profiling, not a free consequence
of declarative syntax.

`StatementSet` enrolls declarations once. A `Protocol` references those same
identities to specify ordering; it does not register second copies. Cadence
decides whether a stage runs, while its position determines what it sees.
Checkpoint continuation must preserve cadence phase and held values.

For example, restoring at MCS 7 preserves the MCS-5 shape sample, even if current
geometry has changed. Daughter refresh recomputes its sampled shape immediately
without shifting the global cadence; the next periodic refresh remains MCS 10.
Live geometry is reconstructible from current ownership; a held sample is not.

### 9. Lifecycle is part of declaring state

Extensive amounts split; intensive values can copy; cell-cycle state resets;
derived quantities rebuild; links follow explicit endpoint policies. These are
different choices, not one generic copying callback. Creation and kind
transitions need equally explicit initialization/transfer rules when a model
uses them; the example only exercises division and retirement.

Link formation enumerates each unordered contact pair once. Capacity, degree,
endpoint validity, and competing requests are settled by the owning engine.
Declared degree bounds are admission/storage contracts, not permission to
silently truncate scientific neighbors. Overflow needs the declared failure or
request-rejection behavior, with a useful diagnostic.
Division removes incident focal links in this model; this is a scientific choice,
not a universal default for every linked or compartmental model.

The default initializer has four separated cells. `event_scenario()` supplies
contact-rich, division-ready, damaged, and initially linked cells to exercise
more mechanisms quickly. This is a proposed test scenario, not evidence that the
future simulation has run or that a particular stochastic event is guaranteed.

### 10. Initial data, analysis, and reuse should be ordinary Julia

The initializer supplies an ownership label array, cell kinds, field values,
and independent cell values. It does not supply volumes, moments, tracker
storage, or a second set of intracellular unknowns.

`PottsProblem` combines declarations and initial data. `remake` changes numerical
parameters. Structural changes such as dimensionality or declared value type
rebuild the factory. `EnsembleProblem` creates independent experiments; per-cell
native batching is a different level of parallelism.

Existing quantities are directly selectable observations. A new named
`Observation` is only needed for a new expression such as total ligand or
lineage. Retained values support analysis and MakiePotts channels without
stepping the simulation or reconstructing unsaved state.

The checkpoint example demonstrates the intended logical restart interface.
Exact continuation additionally requires an admitted numerical/environment
profile and explicit tests. Logical restart, cross-device portability, exact
replay, and scientific/statistical equivalence remain separate claims.

`PottsModels` supplies scientific factories such as persistence, activity, and
signal/cycle components, plus initializers and tutorials. A scientist can replace
the polarity law with a local ordinary Julia factory accepting the same inputs
and producing the same outputs. Larger components return composed Potts systems
with explicit owned state. Shared quantities are passed by reference; library
components must not secretly declare another independent volume or ligand pool.

## How this maps to the PRs

| PRs | Visible result in these examples |
|---|---|
| P01–P02 | PottsModels package, useful starting models, reproducible sibling dev/test environment and ordinary CI |
| P03–P05 | Readable author operation definitions, useful diagnostics, one operational mapping; mostly less work for contributors |
| P06–P07 | Vector/tensor quantities, simultaneous effects, typed state and initialization, direct saved-value access |
| P08 | Distinct-cell contact sensing, structured gather/fold, link endpoint reads |
| P09 | Field-dependent aggregates, shared sufficient statistics, before/after geometry, mutation-aware maintenance |
| P10 | Correct affected energies and parallel read/write conflict closure for shape and incident links |
| P11 | Replaceable scientific factories and uniform quantity consumers |
| P12 | Expression-native coupling, cadence, conservative same-grid exchange, useful CPU/native combinations |
| P13 | Native/aggregate/link-aware division and retirement with compound lifecycle settlement |
| P14 | Reusable mechanisms, progressive executable tutorials, mixed-feature model corpus |
| P15 | End-to-end `explain`, meaningful failures, retained structured observations, plotting adapters |
| P16 | Measured load/compile/run/remake costs and targeted performance improvements |

The main chain does not automatically provide every breadth branch:

| Branch | Additional authoring surface | Why it is separate |
|---|---|---|
| B1 | Dimension-generic geometry, 3D factories and initializers | The full handwritten example intentionally uses 2D vectors and geometry |
| B2 | Fluctuating mechanical state; separate equilibrium auxiliary models | Stochastic laws and equilibrium balance require different scientific contracts |
| B3 | Directed/anchored relationships, nucleus/cytoplasm containment | Endpoint/ownership semantics and coordinated lifecycle change |
| B4 | Localized native events, SDE/jump systems, stochastic partition | Event time, delivery, random paths, and restart must be specified |
| B5 | Multispecies reaction/transport and multiple field grids | Conservative sampling/deposition and discretization are new work |
| B6 | Exact global morphology/topology or declared sampled measurements | Local bounds do not establish global correctness |
| B7 | More backend/solver/precision combinations, including CUDA/ROCm | Actual device extensions and conjunction tests are needed |
| B8 | Swap/multisite/conserved moves, further proposal/kinetic laws, non-Cartesian domains | A backend switch cannot supply a different transition law or geometry |

The long file includes clearly separated sketches for several of these choices.
They are alternatives, not extra declarations to append blindly. Root-triggered
division replaces sampled division; an equilibrium model excludes the active
mechanisms; a 3D factory replaces the explicitly 2D one.

## Developer experience behind the authoring surface

For each declaration, a contributor should be able to trace:

```text
authored quantity/process and source location
  → Potts semantic validation and lowering
  → public CorePotts contracts and LocalMath spatial/publication meaning
  → the common KernelAbstractions execution path
  → derived inspection and scientific diagnostics
  → ordinary owning-package tests and PottsModels integration examples
```

No model author should have to read an internal storage-layout file to connect
an ODE input. Conversely, no pretty constructor should conceal an unsupported
operation: errors should identify the source expression, its consumer, the
missing law or unsupported numerical conjunction, and a meaningful alternative.

The full model is also a useful integration consumer: test conserved total
ligand, independent aggregate rebuilds, link energy deltas, simultaneous writes,
division/retirement policies, native rollback, cadence-aware restart, observation
noninterference, and explicitly supported CPU/GPU parity. A tutorial smoke run
does not replace those tests or prove every feature combination.
