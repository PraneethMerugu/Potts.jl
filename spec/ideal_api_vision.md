# Ideal API Vision

Status: Aspirational, non-normative

This document describes the desired authoring experience for the Potts ecosystem.
Its examples are design sketches, not claims about the current public API. Accepted
contracts, implementation, tests, and current documentation remain authoritative.

This document owns the proposed authoring requirements, not the implementation
schedule or an accepted public spelling. The
[PR-chain plan](../design/authoring-and-model-ecosystem-plan.md) assigns the work;
the [API overview](../design/authoring-api-overview.md) explains the detailed
single-file examples. Those examples expose semantic decisions for review and
are not the final ergonomic syntax. [Research notes](../design/authoring-design-research.md)
record the primary-source considerations behind this refinement.

## Goal

Potts should make novel Cellular Potts models read primarily as scientific
programs. Authors describe quantities, topology, dynamics, terms, and events;
the ecosystem derives proposal-local access, incremental maintenance,
transactional publication, and qualified CPU or GPU execution.

The guiding rule is:

> Anything that is merely compiler plumbing should disappear from ordinary
> authoring. Anything that changes scientific meaning should remain explicit.

An advanced model should normally contain equations, declared topology, derived
quantities, Hamiltonian terms, lifecycle conditions, and parameters. It should
not require authors to construct KernelAbstractions kernels, `ResourceAccess`
records, LocalMath stages, buffers, checkpoint plumbing, proposal overlays, or
host/device branches.

## Authoring requirements, not only engine capabilities

Success has three separate obligations: a feature has a correct implementation;
it works in the required complete model combinations; and its ordinary public
authoring form removes avoidable mechanical work. Passing low-level tests alone
does not establish the latter two. Each relevant PR includes a small executable
public model and its failure cases, rather than postponing authoring to a final
documentation or convenience layer.

The ordinary author should be able to:

1. Use a PottsModels factory, supply data, and solve.
2. Replace or invent a scientific mechanism using quantities, ordinary Julia
   mathematics, native equations, relations, processes, and events.
3. Extract that mechanism into a reusable component without changing its science,
   manually requalifying its inputs, or editing execution code.
4. Use the owning public extension contract only for a genuinely new mathematical
   operation, maintenance law, proposal algorithm, or transaction behavior.

These are levels of responsibility, not runtime modes or separate model
representations. Direct CorePotts programs remain independently supported; they
need not manufacture Potts symbolic declarations to use public Core contracts.

### What stays explicit and what should disappear

| Author chooses | System derives or supplies |
| --- | --- |
| Cell/site/link scope and component inputs | Repeated expression anchors and qualified internal bindings |
| Distinct-neighbor versus contact-weighted sensing | Bounded lanes, access decoding, required maintenance |
| Amount, concentration, geometry, units and reference scales | Consistent propagation and declared scale conversions |
| Independent state versus live or sampled derived quantities | Storage, invalidation and legal accessors |
| Energy versus active drive versus hard constraint | Admitted before/after and affected-contribution evaluation |
| Simultaneous updates versus ordered stages | Read/write analysis and atomic publication machinery |
| Sampling, hold, physical interval, event delivery | Clock bookkeeping and cadence-aware continuation |
| Division, retirement and material allocation policy | Identity-safe state/native/link updates and conservation accounting |
| Algorithm and numerical policy | Concrete realization and routine native component lookup |
| Explicit resource limits and overflow behavior when required | Defaults and estimates where derivable; never neighbor truncation |

Do not replace a scientific choice with an undocumented default to reduce line
count. Conversely, the author should not repeat a mechanical fact in every
consumer merely because the current lowering needs that fact.

## Scoped declarations, identity and composition

### One declaration path

Ordinary Julia factories are the semantic foundation. Concise syntax may capture
names, source locations and lexical scope, but it must immediately produce the
same public statements and PottsSystem composition as ordinary constructor calls.
Extend the existing statement/source-capture path first. Choose concrete syntax
with the small P07/P11 model consumers; do not freeze a new macro family here.

There is no ambient global or task-local model builder, persistent second builder
graph, runtime symbolic evaluator, parallel component registry, or new scheduler.
The macro does not evaluate user functions during expansion, search global
bindings to guess intent, or reinterpret arbitrary Julia control flow as a new
language. Normal construction-time helpers and finite loops remain Julia.

A scientific cell/site/link scope binds its iteration variable once. Nested
scopes have ordinary lexical capture and shadowing rules; ambiguous mixed-domain
expressions require explicit indexing or reduction. Domain inference never
silently picks the first population or broadcasts a cell value onto lattice sites.
Programmatic constructors expose equivalent explicit scope for advanced use.

### Enrollment, references and ownership

- An authored declaration is enrolled once at its owning component. A lexical
  authoring form collects its declarations without a hand-maintained second
  tuple of state, quantities, processes and outputs.
- A supplied field, relation, parameter or derived quantity remains an imported
  reference. Passing it into two components does not clone its state or tracker.
- A Julia variable alias of one declaration is still that declaration. Two
  distinct owned declarations with a colliding qualified name are not silently
  deduplicated or interpreted as an override.
- Independent component instances receive distinct qualified ownership. Shared
  inputs remain shared; local names and state do not leak between instances.
- Protocol entries order existing declarations. Observations and returned
  references select existing quantities. Neither enrolls another copy.
- Declaration collection and parameter discovery follow explicit typed
  declarations and legal dependencies. An unknown name, undeclared quantity,
  or misspelled keyword is an error, not a newly inferred parameter. Numeric
  literals remain literals unless explicitly declared as parameters.
- Parameter discovery includes defaults, initialization, lifecycle transforms,
  relationship payloads, native equations/ports and scheduled expressions. State
  or parameters declared but not consumed remain inspectable; no silent dropping
  or promotion between structural and numerical roles is allowed.
- Source completion closes the structural model. Structural edits rebuild from
  source declarations; they do not mutate an active integrator or a compiled
  hierarchy in place.

Convenience collection cannot silently omit unreferenced events or declared
state: enrollment is explicit through the authoring scope, not only graph
reachability from the Hamiltonian. The completed public inspection shows exactly
what was enrolled, imported and scheduled, derived from the sole source model.

### Parameters, replacement and reuse

Parameter defaults, initial conditions, shared symbolic parameters, and structural
arguments are different facts. One imported parameter can control an energy and
two native components; a single problem override affects all three. Two local
parameters with equal numeric defaults are not thereby shared.

A value reaching a structural option such as shape, capacity or a structural
cadence must not change through numerical `remake(p=...)`; its classification and
rebuild requirement are diagnosed even if its original spelling was a parameter.

Use ordinary problem remaking for numerical changes. Structural replacement of
a mechanism is explicit at the source-composition boundary. It removes the
replaced component's owned contributions, preserves imported shared quantities,
and revalidates all consumers, initialization and writers. Dangling references or
incompatible output contracts fail; replacement is not hidden last-writer-wins.
Current Potts `extend` rejects duplicate declarations/default conflicts; it must
not be assumed to inherit ModelingToolkit's different override rules.

Composition validates domains, value shapes, units, timing, required inputs,
writer ownership and lifecycle compatibility. It need not invent a new port
hierarchy to do so: use actual quantity/system interfaces. Pure helpers can stay
in the model file, move into another module, or become PottsModels factories
without acquiring private execution dependencies.

Ordinary tests exercise nested scopes, helpers from another module, local
constants, finite factory loops, duplicate local names in independent instances,
one shared field/parameter, misspellings, missing inputs, explicit replacement,
and equivalent scoped/programmatic model behavior. Tests do not freeze AST or
incidental struct layout.

## Package ownership

The authoring experience must preserve the ecosystem's existing semantic
boundaries:

```text
Potts
    symbolic scientific authoring and ModelingToolkit integration

CorePotts
    CPM meaning, proposal semantics, maintained state, scheduling,
    lifecycle, transactions, rollback, and checkpoints

LocalMath
    bounded topology, gathering, folding, conflict laws, publication,
    and KernelAbstractions execution

MakiePotts
    explicit observations and scientific visualization

PottsModels
    scientific model/mechanism factories, initializers, tutorials and model tests
```

ModelingToolkit owns symbolic continuous equations. It must not become the
runtime owner of CorePotts state or CPM transactions. LocalMath must not acquire
Potts-specific concepts such as cells, proposals, Hamiltonians, trackers, or
lifecycle events.

Generic authoring conveniences belong in Potts; PottsModels must not hide missing
quantity or composition support behind a privileged private facade. Model
factories return ordinary systems and scientific references. Potts/CorePotts
must not depend on PottsModels; optional native, plotting and device families
use genuine optional dependencies/extensions, without install-time or import-time
environment mutation. Reusable numerical laws retain their appropriate owner.

## One mathematical vocabulary

Fields, trackers, relationship properties, continuous variables, and scheduled
quantities should compose through familiar mathematical operations. Their
storage and update origins remain inspectable, but should not fragment ordinary
authoring.

One logical value may be scalar, Boolean/integer, fixed vector, tensor or a
supported named product. Domain shape, value shape and allocation capacity are
distinct. User arrays and initial conditions are validated; the system does not
silently scalarize vector state into unrelated scientific declarations.

The same reference supports initialization, problem remaking where meaningful,
native mapping, saved-state indexing and plotting. Reuse existing public symbolic
indexing machinery; do not maintain a parallel observation-name registry. A
short name is acceptable only when unambiguous. Missing retained data or a
reference incompatible with the model must fail rather than select a similarly
named quantity or reconstruct unsaved history.

Illustrative examples:

```julia
contact_signal =
    mean(gather(signal, :contact; at=proposal.target_site))

neighbor_polarity =
    mean(gather(polarity, :contact_cells; at=proposal.new_owner))

linked_tension =
    sum(gather(tension, :focal_links; at=proposal.new_owner))
```

`gather` names the mathematical or topological operation. Boundedness,
canonical lane order, repeated endpoints, absent lanes, boundary behavior, and
medium participation remain validated properties of the declared relation.

## Familiar bounded reductions

Ordinary reductions over bounded gathers should use familiar Julia vocabulary:

```julia
neighbors = gather(signal, :contact; at=proposal.target_site)

sum(neighbors)
mean(neighbors)
minimum(neighbors)
maximum(neighbors)
geometric_mean(neighbors; invalid=:reject, empty=:reject)
```

The general operation remains available for genuinely custom mathematics:

```julia
LocalMath.fold(neighbors;
    map=log,
    combine=+,
    init=0.0,
    finish=(total, n) -> exp(total / n),
    invalid=:reject,
    empty=:reject,
    order=:canonical,
)
```

Friendly reductions and the general fold must lower to one typed fold contract,
one validation mechanism, and the existing LocalMath execution path. They are
not competing reduction systems.

An empty mean needs a declared result or rejection policy; an empty sum can use
its typed additive identity. Geometric means must distinguish zero from invalid
negative inputs. Element/accumulator precision and reduction order follow the
declared numerical policy; parallel support does not imply bitwise agreement
with a different reduction order. Familiar scalar reductions already exist:
extend their supported values and relations, not a competing wrapper library.

Ordinary functions composed from admitted symbolic operations should work without
registration. Opaque primitives use the existing public operation mechanism when
needed, with shape/domain/unit information and derivatives only where required.
Symbolic registration does not prove purity, incremental maintenance, gradients,
GPU support or an admissible proposal dependency. Contextual reads must remain
visible to dependency analysis; no live-integrator captures or hidden RNG calls.

## Derived scientific quantities

The central future capability is a robust derived-state system. Many quantities
that appear global can be maintained incrementally because they have explicit
algebraic update laws.

Ordinary authors request scientific geometry such as volume, centroid, covariance
and principal axes. Their implementations share the existing authoritative
geometry and sufficient statistics where meanings agree. Authors do not need to
derive first/second moments to use a centroid. Raw aggregates remain available
for new science and for teaching how these quantities work; they must not create
a second independent geometry implementation.

Illustrative declarations:

```julia
volume = aggregate(1; over=sites, by=owner, combine=+)

signal_mass = aggregate(signal; over=sites, by=owner, combine=+)

position_sum = aggregate(position; over=sites, by=owner, combine=+)

centroid = position_sum / volume
mean_signal = signal_mass / volume
```

Geometric sufficient statistics could be expressed similarly:

```julia
first_moment = aggregate(position; by=owner, combine=+)
second_moment = aggregate(position ⊗ position; by=owner, combine=+)

centroid = first_moment / volume
centered_second_moment = second_moment - volume * (centroid ⊗ centroid)
```

These moment expressions illustrate unit-site measures in non-wrapping geometry.
Physical volume, voxel weighting and periodic coordinate conventions must be
explicit where relevant; summing coordinates naively across a periodic seam is
not a valid centroid implementation.
The centered second moment is not generally the mechanical inertia tensor;
with the intended mass/voxel weighting, mechanical inertia is
`tr(centered_second_moment) * I - centered_second_moment`.

For supported aggregation laws, the compiler may derive:

- initial construction and reconstruction;
- contributions added to a new owner and removed from an old owner;
- proposal-before and proposal-after values;
- concrete CPU/GPU storage and update execution;
- lifecycle and checkpoint participation.

Maintenance must also follow every declared source mutation: field updates with
no ownership change, compound effects, native publication, relationship changes,
creation, division and retirement. Multiple consumers share maintenance. An
unsupported dependency or update law produces a scientific error, not silently
stale values or an undisclosed full-lattice scan on every proposal.

This derivation is justified only by explicit mathematical structure. Potts
must not attempt to infer incremental updates from arbitrary Julia programs.

## Explicit tracker laws

Quantities without a derivable aggregation law use an explicit tracker
contract. A robust tracker describes:

- scope, such as cell, lattice site, relationship, or model;
- concrete state and initialization;
- proposal-local hypothetical change;
- accepted update;
- reconstruction;
- creation, division, retirement, and restoration behavior;
- checkpoint and backend qualification.

This is an advanced extension boundary, not the normal way to declare polarity
or memory. Independent polarity is cell state updated by declared processes;
it need not claim a reconstruction law from geometry. A genuine custom
maintained statistic supplies the mathematical source/update/rebuild laws that
are not derivable. Add only contracts demanded by actual consumers, not a generic
callback lifecycle or tracker adapter hierarchy.

Once admitted, its public reference behaves like any other quantity. A polarity
bias depending on proposal direction is a drive, not a conservative Hamiltonian.

Ordinary authors should never manually construct tracker projections,
LocalMath fields, proposal overlays, or checkpoint records.

## Conservative energy and direct proposal contributions

The authoring model should distinguish conservative energy from direct kinetic
or nonconservative proposal contributions.

For conservative terms, authors write energy:

```julia
HamiltonianTerm(:volume_energy;
    domain=cells(epithelial), anchor=c,
    expression=strength * (volume[c] - target_volume)^2)
```

Potts derives the proposal contribution from explicit before and after views:

```julia
delta_h = energy(after(proposal)) - energy(before(proposal))
```

For a drive that is not represented as a global energy, authors write the
proposal contribution directly:

```julia
ProposalDrive(:chemotaxis,
    -strength * (signal[proposal.target_site] - signal[proposal.source_site]);
    when=source_kind(proposal) == epithelial)
```

Hamiltonians, drives, modifiers, and hard constraints may share symbolic
quantities and compilation machinery, but their scientific roles must remain
distinct.

The explicit `domain`/`anchor` above is the constructor-level meaning; the
ordinary scoped form supplies the repeated binding once. A guard must protect
invalid medium/absent-endpoint reads before evaluating its body.

For a global state energy, the before/after difference includes every affected
energy anchor, not only the copy site or the new owner. Follow supported reverse
relations and shared derived dependencies. An incident-link sum can double-count
undirected links; declaring energy over unique link identities avoids ambiguity.

Parallel admission additionally proves read/write conflict closure. Two distant
proposals modifying opposite endpoints of one spring can have disjoint copy-owner
claims but coupled energy changes. Derive adequate conflicts or reject that
model/algorithm combination. Lattice coloring alone is insufficient. The full
linked model has a sequential reference profile; checkerboard/GPU support needs
an ordinary simultaneous-proposal test, not a selector-only claim.

## ModelingToolkit and continuous cell state

Tracker state should interoperate with ModelingToolkit through explicit temporal
semantics. A continuous system may read settled tracker values and evolve
continuous cell state over a declared interval:

```julia
@variables receptor(t) polarity(t)[1:2]
@parameters production decay alignment

equations = [
    D(receptor) ~ production * contact_signal - decay * receptor,
    D(polarity) ~ alignment * migration_signal - decay * polarity,
]
```

Native variables map once to public cell quantities. Those published quantities
may then participate in CPM terms:

```julia
ProposalDrive(:polarized_motion,
    -strength * dot(cell_polarity[proposal.new_owner], proposal.direction);
    when=source_kind(proposal) == epithelial)
```

The default synchronization contract should be conceptually simple:

```text
settled CPM state
    -> evolve continuous systems over an explicit MCS interval
    -> validate continuous results
    -> publish one coupling-state snapshot
    -> begin the next CPM interval
```

Native outputs are held during the CPM interval. Live ownership-derived geometry
still updates on accepted copies; held output does not freeze every quantity.
All proposals observe that declared timing plus admitted before/after views. An ODE solve
must not run inside each copy proposal or mutate live tracker state during an
active checkerboard transaction.

Division and retirement policies remain explicit scientific choices. For
example, a continuous state might be copied, split proportionally, recomputed,
or initialized independently for daughter cells.

### Native binding without manual compiler work

A per-cell native scope binds its cell population and symbolic anchor once.
Inputs can be arbitrary admitted quantity expressions; output bindings use actual
native symbols. Routine sampling, accessors and reinitialization are derived
from those bindings, not manually authored projection arrays. Select native
solver profiles by the public component reference, not a compiler path string.
Qualified paths remain useful diagnostics.

Preserve the genuine native system and use public MTK/SciML interfaces after
structural compilation. Simplification can eliminate or reorder unknowns and
reconstruct observed outputs; never cache a guessed pre-compilation index.
An algebraic observed output is not automatically an independently settable
unknown. Initialization from published values can be inferred for a proven
unknown mapping; otherwise require the native initialization problem or an
explicit supported mapping. Do not invent an inverse or force redundant state.

Bindings can infer routine synchronization, not the split method. The physical
duration per MCS, component cadence, input hold, order, and simultaneous native
batch boundaries remain explicit. Same-time inputs to one declared batch share
one snapshot, independent of declaration order. A coupled algebraic cycle cannot
be fixed by arbitrary topological sorting: require a real coupled native solve,
an explicit lag, or reject the unsupported cycle.

Continuous root events, SDEs and jumps are additional scientific contracts, not
automatic consequences of accepting an MTK system. Native root localization,
delivery at the next CPM boundary, reinitialization and event arbitration are
distinct. A stochastic path requires its own time/RNG/continuation semantics.

### Reciprocal fields and conservative exchange

Start with bounded same-grid exchange. Declare extensive source/destination
pools, rates, physical measures, availability, capacity and allocation policies.
One transfer owns the realized subtraction and addition. An MTK connection
equality is not a finite-resource transaction. Positivity repair cannot silently
discard mass; failed native or transport work cannot partially publish.

Specify whether a field permeates occupied sites or is displaced by cells. A
field aggregated over a cell's footprint is a measurement of that field, not a
second intracellular store. Division and retirement account for every extensive
pool. Different grids, multiple species, nonlinear reactions and new
discretizations require the corresponding breadth work and conservation tests.

## Scheduled global computation

Not every global quantity admits an efficient incremental update. Such
quantities should be represented as scheduled computations at real simulation
boundaries, not disguised as proposal-local Hamiltonian expressions.

Illustrative syntax:

```julia
preferred_axis = derived(:preferred_axis;
    domain=cells(epithelial), anchor=c,
    expression=cell_preferred_axis(shape[c]),
    cadence=EveryMCS(1), initialize=:evaluate, lifecycle=:recompute)
```

The settled result may become a read-only input to subsequent proposals:

```julia
ProposalDrive(:axis_alignment,
    -strength * dot(preferred_axis[proposal.new_owner], proposal.direction)^2;
    when=source_kind(proposal) == epithelial)
```

The author chooses independent state, live derived meaning or explicit sampled
timing. For live derived meaning, the implementation may choose a correct
incremental strategy from known laws; authors need not choose its internal
maintenance representation. It may not silently replace a live quantity with
a periodic approximation.

A held sampled value is historical state, not merely a reconstructible cache.
A checkpoint at MCS 7 for a cadence-5 measurement restores the MCS-5 value and
the next due tick; it must not recompute from MCS-7 sources. Runtime histories
likewise declare their sample clock, initialization, lag, retention and lifecycle
policy; solution save times are not a hidden history implementation.

Specify whether a lifecycle refresh resets a per-cell clock or preserves the
global cadence. The full tissue example uses an immediate daughter refresh with
the global cadence unchanged. Off-tick source changes, restart and division are
ordinary tests of this contract.

## Relationship authoring

Cell-cell relationships should be typed scientific objects with explicit:

- endpoint domains;
- payload type;
- degree or capacity bounds;
- creation, removal, and retuning semantics;
- conflict and canonical-order policy;
- generation and checkpoint behavior.

Their values should participate in the same bounded mathematical vocabulary:

```julia
spring_energy(link) =
    0.5 * link.stiffness *
    (distance(link.endpoints) - link.rest_length)^2

HamiltonianTerm(:focal_adhesion;
    domain=edges(focal_links), anchor=link,
    expression=spring_energy(link))
```

Relationship changes remain explicit events:

```julia
Create(focal_links, a, b; payload=(; stiffness, rest_length))
Retune(focal_links, link; payload=(; stiffness))
Remove(focal_links, link)
```

LocalMath owns bounded traversal, ordering, conflict resolution, and
publication. CorePotts owns relationship identity, capacity, generations,
admission, and transactional scientific meaning.

These effects are declarations inside scheduled processes, not imperative
mutation of a running simulation. Contact creation enumerates the declared
measure and, for undirected pairs, the intended unique pair identities. A
scientific degree limit and storage provisioning are not interchangeable:
overflow cannot truncate real neighbors and thereby change an energy.

## Lifecycle conditions and processes

The same symbolic quantities should be available to lifecycle rules without
creating another expression language:

```julia
divide_when(volume > division_volume)
retire_when(intracellular_damage > lethal_damage)

differentiate_when(
    mean(gather(signal, :contact; at=cell)) > threshold,
)
```

Lifecycle evaluation occurs at declared CorePotts boundaries. It is not a
Hamiltonian evaluation and must preserve lifecycle validation, rollback, state
partitioning, and checkpoint semantics.

Concise policies express extensive partition, intensive copying, history reset,
derived reconstruction and relationship disposition. They are inspectable
defaults with explicit exceptions, not a callback repeated for every backend.
Independent component policies are validated together. Multiple effects read
their declared snapshot and publish atomically; incompatible event requests
use an explicit arbitration rule. Initial creation and kind transition are not
assumed identical to division. Per-cell native unknowns are reinitialized only
after the relevant published-state policies have settled.

Failure atomicity names a transaction boundary and the affected state. The full
model's complete-MCS contract includes ownership, native work, transfers,
lifecycle, clocks and semantic random counters. Implement efficient rollback
through the owning executor and test late failure plus continuation; do not
promise it merely because the syntax is declarative. Filtering an inadmissible
event is a declared scientific policy, not the same as a numerical step failure.

## Progressive disclosure

There should be no cliff between a ready-made term and an engine extension.

### Level 1: built-in components

```julia
Volume(epithelial; target=50, strength=2)
ContactEnergy(interaction_matrix)
Chemotaxis(signal, strength=100)
```

### Level 2: mathematical composition

```julia
HamiltonianTerm(:signal_preference;
    domain=cells(epithelial), anchor=c,
    expression=strength * (
        mean(gather(cell_signal, cell_neighbors; at=c); empty=0.0) - target)^2)
```

Here `cell_neighbors` is a declared distinct-cell relation and `cell_signal` a
cell quantity. The surrounding scientific scope supplies `domain`/`anchor` in
the concise form; the explicit constructor above states its meaning.

### Level 3: derivable maintained quantities

```julia
signal_mass = aggregate(signal; over=sites, by=owner, combine=+)
```

### Level 4: explicit tracker and relationship laws

Authors supply update, reconstruction, lifecycle, conflict, and checkpoint
meaning that cannot be derived from a standard aggregation.

### Level 5: public scientific and execution extensions

The public compiler interfaces remain available for genuinely new proposal
contexts, global algorithms, persistent workspace, transaction semantics, and
checkpoint state. This path must remain typed, inspectable, GPU-qualifiable,
and independent of private package layout.

## Ordinary model workflow

Model construction should not require compiler vocabulary:

```julia
model = mechanochemical_tissue(; shape=(96, 96))
initial = initial_tissue(model)
problem = PottsProblem(model.system, initial, (0, 10_000); seed=42)
solution = solve(problem, SequentialCPM();
    backend=CPUBackend(), native_profiles)
```

Completion, scientific dependency inference, LocalMath lowering, planning,
preparation, and physical compilation occur internally. Advanced users may
still invoke and inspect the structural steps explicitly.

The factory's definition belongs in the same file when developing a new model.
It contains the scientific declarations, not manual inventory lists, compiled
handles or duplicated initial native values. The detailed example currently
spells some of these out to expose requirements; that is not the ergonomic
acceptance target. Include both a small built-in model and a substantial novel
mechanism example in the executable tutorial suite.

### Numerical policy, units and resources

Select the default floating realization once per numerical configuration;
quantity declarations ordinarily state logical shape and scientific domain.
Explicit fixed types or mixed-precision accumulator choices override defaults
only when admitted and checked. Integer identities, molecule counts and Boolean
state never become floating data just because a GPU profile uses Float32.
Initial data is validated/adapted according to that policy; an explicitly
Float64 field cannot be silently reinterpreted by a Float32 solve keyword.

This is a desired extension, not a claim that present lowering preserves every
declared element type. Parameter/default conversion, native solver tolerances,
literal promotion and reductions must follow one documented numerical policy.
Backend/algorithm selection remains explicit; unsupported combinations fail
without a silent CPU transfer or scientific algorithm change.

Unit checking must cover scaled units and native boundaries, not only dimension
labels. Choose reference scales or explicit conversions before numerical
execution. Current MTK validation has equal-valued-unit restrictions, so merely
forwarding metadata is insufficient. Begin with homogeneous-unit scalar/fixed
shape quantities and tested amount/concentration/time/geometry conversions;
affine units and heterogeneous-unit structures need separately demonstrated
support. Do not introduce a competing symbolic unit algebra.

Routine batching/workspace choices may have documented numerical defaults.
Capacity that affects admissible cell/link events remains observable and requires
a policy. Inferred estimates are not guarantees; unsupported resizing cannot
be promised behind a convenient constructor. Checkpoint compatibility records
the actual chosen scientific/numerical contract, not a friendly preset name.

## Inspection and diagnostics

The compiler should explain scientific meaning rather than exposing internal
compiler failures by default:

```julia
explain(model.system, term)
```

An explanation should connect:

```text
source expression
    -> proposal anchor and before/after meaning
    -> fields, trackers, and relationships
    -> bounded relations and canonical order
    -> reductions and invalid/empty policies
    -> LocalMath publication and conflict laws
    -> qualified physical execution
```

An unsupported expression should identify the missing scientific contract. For
example:

```text
The term `global_shape` cannot be evaluated for every proposal because its
dependency is neither bounded nor incrementally maintained.

Define it as a tracker, compute it at an MCS boundary, or provide a bounded
relation.
```

The diagnostic must say when a remedy changes scientific meaning: computing at
an MCS boundary makes this a sampled model, not an equivalent live constraint.

Raw Symbolics, inference, or device-compiler details remain available for
developers but are not the primary user diagnostic.

Errors should include the source component/expression, conflicting or missing
quantity, scientific consequence, and a supported remedy. Fail before expensive
materialization where the problem is already knowable. Native structural errors
retain their original equation/source context. Explanations derive from source,
dependency and execution authorities, not stored duplicate report facts.

The edit loop should work in an ordinary Julia session: build a small model,
inspect the science, replace a helper, rebuild, remake parameters, and run a
bounded example. Existing problems have a documented snapshot/rebuild boundary;
editing a function does not promise to hot-swap a live compiled GPU kernel.
Test helper redefinition and accessor invalidation through supported ordinary
workflow, without requiring an editor extension or new model server.

## Scientific component library

Generality alone does not make a productive modeling environment. The ecosystem
should provide a coherent library of components implemented through the same
public mechanisms available to users, including:

- volume, surface, perimeter, contact, and differential adhesion;
- chemotaxis, haptotaxis, polarity, persistence, and activity;
- connectivity, curvature, elongation, and inertia;
- focal links, springs, compartmental cells, and relationship mechanics;
- secretion, uptake, field coupling, and intracellular dynamics;
- division, retirement, differentiation, and state partitioning.

Built-ins must not use a privileged parallel framework. A substantial corpus of
independently checked paper recreations is part of the authoring design: it
demonstrates that the abstractions express real science rather than isolated
examples.

PottsModels tutorials distinguish a qualitative mechanism example from a
numerical reproduction of a publication. State assumptions, nondimensionalization,
initialization, observable, seed/numerical choices and limitations. Teach use,
modification, extraction into a module, and then a genuine extension. Optional
rendering and hardware are not prerequisites for the CPU modeling curriculum.

## Hard-model qualification set

Before freezing tracker, relationship, or continuous-coupling interfaces, the
design should be exercised against a compact adversarial set:

1. activity-based migration with pixel history and a geometric neighborhood
   reduction;
2. persistent polarity with vector cell state and accepted-copy updates;
3. an ODE-driven cell cycle with division and checkpoint continuation;
4. inertia- or shape-dependent migration with proposal-before/after geometry;
5. focal-point or spring relationships with dynamic payloads and conflicts;
6. a connectivity or global morphology constraint;
7. a chemotaxis model coupling CPM, a field, and continuous cell state.

These models should use public authoring interfaces, independent numerical or
scientific oracles, and the same declarations on CPU and qualified GPU backends.
Their purpose is to discover missing semantics before a larger reproduction
corpus, not to become another execution system.

## Boundaries of automation

The ecosystem should aggressively compile operations with explicit mathematical
structure:

- bounded gathering;
- deterministic and relaxed reductions;
- incremental aggregates;
- proposal-before and proposal-after substitution;
- finite relationship traversal;
- explicit continuous equations;
- scheduled derived quantities;
- declarative lifecycle conditions.

It must not attempt to infer, from arbitrary code, whether a global computation
is incremental, proposal-local, periodically recomputed, approximate, or
continuously evolved. It must not introduce runtime symbolic interpretation,
implicit host/device transfer, mutable proposal callbacks, or a second
execution path to create an illusion of generality.

## Success criteria

The vision is realized when a sophisticated mechanochemical CPM reads as
scientific declarations and ordinary Julia functions, with no redundant
registration, storage plumbing or native bookkeeping, while retaining:

- source-located diagnostics and structural inspection;
- exact proposal, ordering, conflict, and lifecycle semantics;
- failure-atomic transactions and checkpoint continuation;
- one CorePotts state and transaction authority;
- one LocalMath bounded-computation authority;
- one KernelAbstractions semantic path across CPU and qualified GPUs.

A new public abstraction is justified only when it makes complete scientific
workflows clearer, deletes repeated plumbing or semantic authority, or serves
multiple demonstrated models. Attractive syntax alone is insufficient.

Do not use a line-count target, AST snapshot or a single large passing example as
the definition of usability. Ordinary behavioral examples must demonstrate:

- scope without repeated anchors, parameter typo rejection and source locations;
- equivalent scoped and constructor forms, including failures and initialization;
- two independently developed components sharing one quantity/parameter;
- replacement without dangling consumers, hidden owned-state deletion or writers;
- scientific geometry and standard reductions without bespoke projection code;
- a native input expression, an eliminated observed output, and valid initialization;
- simultaneous effects, conservative exchange and compound lifecycle;
- off-cadence sampled/history continuation and quantity-reference saved access;
- a valid source model rejected on an unsupported numerical combination with an
  actionable explanation, including linked-cell parallel conflicts;
- execution and measured authoring/compilation costs on the actual supported
  CPU/GPU profiles, not inferred universal support.

The PR plan assigns these tasks to the same changes that implement their
semantics. There is no final cosmetic authoring phase, duplicate qualification
system, or generic callback that substitutes for a missing scientific contract.
