# Composable authoring, developer experience, and the model ecosystem

Status: Proposed design and PR-chain plan; non-normative.

Prepared 2026-09-08 from the independent repositories in `../PottsEcosystem`.
This document is stored in the older Potts workspace because that workspace
contains [Ideal API Vision](../spec/ideal_api_vision.md). It does not imply that
the older checkout is the implementation baseline. No package implementation,
public repository, release, or pull request is created by this proposal.

The [strengthened authoring spec](../spec/ideal_api_vision.md) owns the desired
scientific/ergonomic contracts. The [API overview](authoring-api-overview.md)
maps the explicit single-file walkthrough to the remaining convenience work;
the [research notes](authoring-design-research.md) explain upstream constraints
and unresolved implementation choices. This plan assigns that work to existing
coherent changes rather than adding a final cosmetic authoring layer.

For the current delivery grouping and enumerated PR allocation, use the
[consolidated dependency map](consolidated-pr-dependency-map.md). This document's
P01–P16/B1–B8 labels remain feature-scope references, not extra PRs to open in
addition to that map.

## 1. Objective and limits

The aspiration is that a scientist can define a mechanism once, combine it with
independently developed mechanisms, and understand both the resulting science
and execution without modifying an engine. A contributor should be able to
follow the same mechanism from public authoring through validation, lowering,
execution, diagnostics, and its defending behavioral tests.

There is no finite list of every future scientific feature. This is a concrete
inventory for the major CPM model families, the combinations they require, and
the extension boundaries needed for unfamiliar models. It separates existing
facilities, substantive missing capabilities, and research-dependent expansion.
It does not promise that arbitrary programs become incremental, parallel,
GPU-capable, equilibrium-preserving, or exactly replayable automatically.

Success is measured by complete model-building tasks, useful combinations, clear
failures, and understandable ownership. Lines of model code, file lengths,
abstraction counts, and a single giant passing model are insufficient measures.

### Baseline inspected

| Repository | Local main inspected | Relevant existing foundation |
| --- | --- | --- |
| Potts.jl | `868a22ff` | Symbolic statements, composition, completion, conservative-energy analysis, operation extensions, SciML problem/solution, native components |
| CorePotts.jl | `7183bcec` | CPM proposals, maintained geometry, relationships, lifecycle, transaction settlement, randomness, continuation |
| LocalMath.jl | `b699002a` | Bounded relations, gathers/folds, publication/conflict laws, storage preparation, KernelAbstractions execution |
| MakiePotts.jl | `924ba0a5` | Explicit saved-state frames, typed channels, Makie recipes and recording |

This is a source, documentation, test, and workflow review. Existing test code is
evidence of the intended exercised contract; suites and benchmarks were not
rerun for this planning document. Ordinary package versions and compatibility
ranges remain separate from these review identifiers.

## 2. What should stay, and what needs actual work

Keep the Potts/CorePotts/LocalMath ownership split, native ModelingToolkit systems,
the existing symbolic compiler, public compiler/backend extension interfaces,
ordinary Julia tests, and the shared KernelAbstractions path. Keep sequential
and checkerboard algorithms scientifically distinct. Keep observations explicit.

The following concrete restrictions are more useful planning inputs than public
type names that suggest broader support:

| Area | Observed implementation | Required improvement |
| --- | --- | --- |
| Gathers | Familiar scalar reductions already exist; repeated relation lanes repeat contributions | Structured gathered values, richer relation composition, explicit distinct-owner/weighted semantics where demanded |
| Trackers | Ownership-derived sources; dense scalar or coordinate-moment storage; old/new-owner update bound | Arbitrary declared source dependencies, additional state shapes, compound changes and lifecycle reconstruction |
| Tracker-backed operations | Direct projections require dense scalar storage; a contextual operation admits at most one qualified tracker binding | Compose multiple derived quantities and structured projections without hand-built compiler wrappers |
| Process assignments | Generic staged assignment lowering requires exactly one `Assign`; model assignments read scalar model values/parameters only | Simultaneous multi-output updates, cell-domain work, controlled reductions/publications and meaningful schedule dependencies |
| Native CPU coupling | Preflight requires sequential CPM, CPU, Float64; native CPU/Metal execution modes cannot mix | Deliberately extend supported combinations, starting with checkerboard CPU coupling and selected Float32 profiles |
| Native IO | Inputs use ModelState/CellState declarations; native field output is fixed shape and output-only | Expression inputs, vector/tensor IO, explicit sampling and reciprocal field exchange |
| Relationships | Packed relationship endpoint lowering accepts `Undirected` | Directed/anchored/contained relationships only with corresponding scientific and lifecycle contracts |
| Execution breadth | Public runtime support is 2D CPU and specific Metal profiles; 3D, CUDA, ROCm are not admitted | Dedicated end-to-end additions, rather than merely adding selectors |
| Developer interfaces | Long positional transfer/context constructors; runtime consumes fields named `reports` | Clear construction contracts and operational ownership; derive inspection from them |
| Diagnostics | Existing diagnostic values contain expression/alternatives that ordinary display omits | Show those facts and connect runtime source IDs back to authored mechanisms |
| CI | Different repos test pinned siblings or floating main; a four-revision ecosystem workflow already exists | Coherent candidate dependency sets and cost-aware use of ordinary owner suites |

Evidence: [tracker contracts](../../PottsEcosystem/CorePotts.jl/src/execution/tracker_plan_contracts.jl),
[evaluator lowering](../../PottsEcosystem/Potts.jl/src/compiler/lowering/evaluator_nodes.jl),
[assignment lowering](../../PottsEcosystem/Potts.jl/src/compiler/lowering/accepted_copy_descriptors.jl),
[state layouts](../../PottsEcosystem/Potts.jl/src/compiler/lowering/storage_layouts.jl),
[native preflight](../../PottsEcosystem/Potts.jl/src/native/preflight.jl),
[native ports](../../PottsEcosystem/Potts.jl/src/native/ports.jl),
[capability status](../../PottsEcosystem/Potts.jl/docs/src/concepts/capability-status.md).

## 3. Feature inventory

The identifiers below label planning topics, not new runtime types or modes.
Every implementation item must name its production owner and an actual model
consumer. New constructs should replace repeated work or enable real reuse.

### F1. Scientific component composition

Potts owns composition. PottsModels supplies reusable scientific components.

- Support factories returning ordinary Potts systems with explicit scientific
  inputs, outputs, parameters, and namespace identity. Extend current `compose`
  and `extend`; do not add a second component registry or system representation.
- Bind a component to a cell kind, field, relation, or quantity explicitly.
  Refer to those declarations by identity rather than searching global names.
- Assemble declarations once at an explicit model/component construction
  boundary. Quantities created in that scope should not also require manual
  insertion into a second declaration list. A convenience builder must emit
  the existing statements and release its construction state; it is not a
  second retained model, global registration mechanism, or execution language.
- Make independently instantiated copies safe: separate initial conditions,
  RNG identities, state, namespaces, and parameter overrides.
- Share explicitly supplied quantities between components without duplicating
  their maintenance or allowing a second writer to claim the same state.
- Define override/substitution rules: runtime parameter changes, structural
  changes, removal/replacement of a mechanism, and incomplete required inputs.
  Current Potts duplicate-identity/default rejection must not become implicit
  last-writer-wins behavior by analogy with native MTK systems. Replacement
  removes the replaced component's owned declarations/dependencies, retains
  explicitly shared references, and fails on dangling consumers or unordered
  writers.
- Expose component-local references through normal Julia properties or returned
  bindings. Namespace display names must remain distinct from declaration
  identity. A replacement must explicitly reconnect compatible public inputs
  and outputs; matching a string name is not sufficient to transfer state,
  random streams, or checkpoint identity.
- Expose conflicting writes, duplicate incompatible declarations, unresolved
  inputs, dimensional mistakes, and algebraic/schedule cycles at construction.
- Allow pure Julia factories and optional concise syntax to build the same
  model; macros should capture provenance and remove ceremony, not introduce
  different semantics.
- Keep scientific composition separate from execution selection. A component
  must not hard-code a backend, start a solver, or capture a live integrator.

Defending examples: two polarity components, two species using a shared field,
and replacement of a division law without modifying adhesion or field dynamics.

### F2. Quantities, domains, shapes, and units

Potts owns symbolic meaning and domain checking. CorePotts owns logical state
and storage realization. LocalMath realizes physical access/publication.

- One reference should describe a scientific quantity across energies, drives,
  process expressions, native inputs, initialization, and observations.
- Bind domain and anchor once in a scientific scope, and carry them through
  quantity references. Routine expressions should not repeat `domain`, `anchor`,
  tracker identity, and projection metadata at each use. Cross-domain gathers,
  proposal old/new views, and snapshot changes remain explicit where they change
  meaning. Ambiguous references fail at their authored use, not during storage
  lowering.
- Infer parameter participation only from declared symbolic parameters reached
  through the authored expressions. A misspelled name, free quantity, or numeric
  literal must not silently become a parameter or a newly owned declaration.
- Preserve distinct contracts for authoritative mutable state, reconstructible
  derived state, continuously evolved state, and sampled results. Shared syntax
  must not make their persistence or timing interchangeable.
- Support scalar, Boolean/integer, fixed vector, fixed tensor, and named product
  values where consumers demonstrate reuse. Logical value shape is separate
  from domain shape and capacity; the author need not manually scalarize a
  polarity vector into unrelated storage declarations.
- Validate domain and shape propagation through indexing, broadcasting, tuple
  construction, dot products, norms, maps, and reductions. Specify empty-cell,
  medium, missing-endpoint, and invalid-value behavior.
- Preserve scientific units through derived expressions, native ports, spatial
  measures, parameters, and output. Separate physical lattice spacing from an
  integer site index; reject incompatible operations before execution.
  Native boundaries need tested conversion to declared reference scales or
  explicit conversion expressions, not dimensional metadata alone. MTK unit
  validation requires equal-valued units, so milliseconds and seconds cannot
  simply be treated as interchangeable annotations.
  [MTK unit validation](https://docs.sciml.ai/ModelingToolkit/stable/basics/Validation/).
- Make storage and accumulator precision explicit when they affect results.
  Support mixed precision only as a declared and tested numerical choice.
- Resolve multiple tracker-backed quantities in one expression or custom
  operation. Do not require a new per-operation projection wrapper for each
  combination of already-declared inputs.

Defending examples: vector polarity and tensor moments in a single energy,
integer receptor counts coupled to a continuous concentration, and typed empty
reductions. Do not generalize to arbitrary heap objects in device state.

### F3. Topology and neighborhood mathematics

LocalMath owns relation traversal. CorePotts owns CPM identity and contact
meaning. Potts owns the scientific declarations and analysis.

- Distinguish lattice sites, interface bonds, distinct neighboring cells,
  contact-area-weighted neighbors, and incident relationship records.
- Specify multiplicity, direction, symmetric-pair counting, canonical order,
  self-neighbors, absent lanes, medium inclusion, and boundary treatment.
- Support useful compositions such as site-to-owner-to-incident-links, filtered
  neighbors, typed payload projections, and bounded zipped/map-reduced inputs.
  Reuse existing LocalMath composition, inverse, packed, and index relations.
- Preserve ordinary `sum`, `mean`, `minimum`, `maximum`, mapped reductions, and
  supported pure Julia functions over gathered values. Authors choose the
  scientific relation and empty-domain behavior, not a separate symbolic fold
  spelling or per-formula compiler registration. Lower supported forms through
  the existing operation/relation contracts and explain unsupported functions.
- Establish the bound for a *cell's* neighbors from actual maintained topology
  and capacity. A finite site stencil does not imply a tiny bound on a whole
  cell's contact graph.
- Maintain changing contact measures from ownership changes using the same
  transaction authority; don't recreate a graph independently for inspection.
- Keep geometry semantics explicit: Cartesian metrics, anisotropic spacing,
  periodic displacement, contact surface measure, and coordinate conventions.
- Introduce new meshes, lattice connectivity, or boundary laws only with matching
  proposal, acceptance, geometry, and execution tests. LocalMath's ability to
  express a graph does not establish CPM support on it.

Defending examples: a cell touching the same neighbor through three bonds,
periodic seam contacts, zero neighbors, heterogeneous incident links, and
filtered traversal during relationship removal.

### F4. Derived state and incremental aggregation

Potts derives legal plans from explicit mathematical structure. CorePotts owns
the maintained value, source changes, proposal projections, and commit.

- Express grouping, mapped contributions, accumulation, identity, finalization,
  removal/replacement law, bounds, and numerical order.
- Begin with integer counts and additive scalar/vector/tensor sufficient
  statistics. Derive mean, centroid, and covariance-like quantities from shared
  statistics instead of independently maintaining each formula.
- Offer scientific geometry references for center, displacement, shape moments,
  axes, and related observables where their convention is defined. An author
  should not rebuild coordinate sums and tensor contractions for every model.
  Requests share owned sufficient statistics; periodic unwrapping, degenerate
  shapes, eigenvector sign/orientation, and units remain documented mathematics.
- Track **all** source mutations: ownership, field updates, cell-state changes,
  relationship changes, creation, division, retirement, restore, and explicit
  parameter changes that affect a cached result.
- Derive initialization, post-change reconstruction, before/after evaluation,
  accepted updates, and invalidation from one declared dependency law.
- Preserve the distinction between reconstructible value and historical state.
  A quantity such as persistent polarity generally needs independent state.
- For non-invertible aggregates, choose explicit additional state or bounded
  recomputation. `minimum` cannot be maintained by subtracting its old minimum.
- Specify drift and rebuilding policy for floating accumulation. Rebuilding is
  not bitwise neutral; persistence and replay must respect that distinction.
- Provide a documented numerical policy at a useful model/quantity boundary for
  accumulator precision, reduction order, and permitted rebuilds. Reuse it
  across consumers, allowing explicit local overrides. Scientific grouping,
  sampling freshness, and whether a value is an amount or concentration are
  separate author decisions and must not be inferred from that policy.
- Detect cycles in derived definitions and avoid duplicate storage for shared
  sufficient statistics. Keep derived expressions lazy when materialization
  would add no demonstrated benefit.
- Allow specialist tracker laws with declared read dependencies and changes,
  without exposing mutable runtime banks or arbitrary hidden captured state.
- Analyze both proposal cost and update fan-out. A constant-size tracker value
  may still require large work when its source field changes.

Defending workflow: evolving signal field -> cell signal mass -> mean signal ->
ODE input and energy -> division -> restore. Tests recompute independent small
cases, including source changes with no ownership changes.

### F5. Energy, driving, and affected contributions

Potts owns conservative-domain analysis. CorePotts owns proposal/acceptance
semantics and concrete evaluation.

- Preserve state energies, direct drives, hard constraints, modifiers, and
  auxiliary mechanical state as scientifically different categories.
- A state energy needs a domain and an anchor. Derive the sum of changed energy
  contributions over the affected anchors, not just an expression evaluated at
  the copied site.
- Extend affected-anchor analysis through derived quantities, inverse relations,
  nested finite gathers, and relationships when a correct bound can be proven.
- Extend parallel read/write conflict closure alongside affected-energy closure.
  Two distant copies changing opposite endpoints of a spring can have disjoint
  old/new-owner claims but coupled energy changes. Include the relevant linked
  dependencies in admission/arbitration, or reject that algorithm/model
  combination; do not silently introduce a synchronous approximation.
- Specify evaluation of both old and new owners, medium transitions, changing
  edges, disappearing cells, shared dependencies, and symmetric terms.
- Treat periodic centers and sufficient statistics as scientific geometry,
  including the convention for unwrapping a cell that spans a boundary.
- Reject proposal-direction expressions as conservative state energy unless a
  corresponding state function is defined. The polarity sketch in the original
  vision needs this correction.
- Preserve separate diagnostic contributions for energy, drives, constraints,
  conflict rejection, and numerical failure. A NaN is not a hard constraint.
- Support custom pure scalar functions through the smallest operation contract;
  contextual operations additionally declare their scientific reads.

Defending tests: independently recompute the entire tiny system's energy before
and after a legal move; include neighbor-tracker dependencies and link mechanics.
Include simultaneous proposals affecting opposite endpoints of one link and
compare admitted settlement with the declared energy/conflict contract.

### F6. Processes, compound effects, and temporal composition

CorePotts owns atomic mutation and boundaries. Potts owns declared dependency
and schedule analysis; LocalMath owns publication mechanics.

- Support cell/site/relationship/model-scoped processes with multiple outputs.
- Define simultaneous assignment separately from sequentially ordered stages.
  For `a <- b; b <- a`, authors must know whether the result is a swap.
- Express bounded scatter/reduction updates, conserved transfers, accepted-copy
  effects, and composed relationship/lifecycle effects without mutable callbacks.
- Resolve conflicting writers using a scientifically chosen combine, arbitration,
  priority, or rejection law. Array iteration order is not an implicit policy.
- Make sampling, freshness, cadence, and ordering explicit at settled boundaries.
  Use the existing MCS clock and native physical-time mapping.
- A result sampled every MCS and a quantity updated after every accepted copy
  are different science. Conversely, caching versus equivalent recomputation
  can be a compiler choice within a declared numerical contract.
- Expose read-after-write dependencies and cycles. Reject implicit fixed-point
  iteration; an actual coupled solve needs an explicit solver contract.
- Allow finite scheduled global work to publish results atomically. Its workspace,
  placement, failure, and resampling behavior must be explicit. Do not silently
  turn an unsupported per-proposal computation into a periodic approximation.
- Check that compound effects roll back together, including all maintained
  quantities, relationship state, native outputs, and failure reporting.

Defending examples: polarity rotation updating two coordinates, conservative
secretion/uptake, shared resource depletion, and two processes targeting one cell.

### F7. Continuous and hybrid coupling

Potts coordinates native SciML systems; CorePotts publishes settled state and
owns CPM mutation. The native integrator owns its internal numerical state.

- Bind derived expressions to native inputs, including gathers, units, and
  structured values. Compile sampling storage internally rather than requiring
  hand-authored intermediate CellState declarations.
- Bind native component and variable references directly, preserving their MTK
  identity. Routine authoring must not require repeated component-path tuples
  or string lookup. Resolve public references once during composition; retain
  any necessary concrete runtime paths only in the existing owned lowering.
- Publish output into declared quantities with one writer and an atomic boundary.
  Distinguish solver state from its published CPM snapshot.
- A native observed output can be reconstructed or eliminated by MTK; it is not
  necessarily a settable unknown. Infer initialization from published state only
  for a proven actual-unknown mapping. Otherwise use explicit initialization
  through public native mechanisms; never guess an inverse from output values.
- Admit checkerboard CPU CPM with native CPU components and useful scalar
  choices after proving staging, settlement, and rollback. Existing CPU support
  is restricted to SequentialCPM/Float64.
- Define multiple components with different cadences and physical intervals.
  Give input hold/interpolation and component ordering explicit meaning.
- Infer routine sample/refresh/publish dependencies from declared input/output
  ownership within the chosen coupling law. Do not make authors manually repeat
  synchronization tokens and refresh stages for ordinary expression coupling.
  Simultaneous sampling versus sequential feedback, physical step size, cadence,
  input hold/interpolation, and an actual coupled solve remain explicit science
  or numerical choices. Inference must not silently choose among them.
- Keep CPU batching distinct from whole-trajectory ensembles. Preserve
  generation-safe per-cell pools, capacity, creation, division, and retirement.
- Preserve user solver choices and expose a small useful preset only when its
  duration, tolerances, adaptivity, and support are visible.
- Add native events in a separate controlled extension: root finding remains
  native; requests to change CPM state wait for a defined boundary. Specify
  whether an event between MCS boundaries is latched, localized, or deferred.
- Treat DAE restart, stochastic solves, adaptive GPU solves, and mixed-device
  islands as separate additions. Do not infer support from native ODE execution.

Defending combinations: receptor feedback + polarity + cell cycle + division;
solver failure after successful CPM staging; removal and slot reuse; restart at a
nontrivial component cadence.

### F8. Fields and reciprocal transport

- Allow multiple interacting fields, cell-dependent secretion and uptake,
  contact-dependent sources, nonlinear reactions, and explicit boundary fluxes.
- Express extensive amount versus concentration and account for cell/lattice
  volume factors. A cell losing mass and a field gaining it should be one
  conservation law, not two unrelated callbacks.
- Define sample/deposit operators and their relation to space, units, and
  interpolation. Reuse them across chemistry, mechanics, and observations.
- Keep the existing fixed-grid Euler scheme and MethodOfLines adapter as
  particular choices; add other native solvers through public interfaces.
- For different field and CPM grids, define both directions of transfer,
  conservation/accuracy, boundaries, update timing, and storage placement.
- Add anisotropy, advection, heterogeneous coefficients, deformable domains,
  or remeshing only when driven by real models and with separate validation.

Defending examples: ligand/receptor conservation, secretion by growing cells,
two-species reaction-diffusion, and a field update followed by aggregate refresh.

### F9. Lifecycle, identity, and capacity

- Preserve generation-safe identity and lineages independently of reused slots.
- Apply scalar, vector, tensor, history, derived-state, native-state, and
  relationship policies consistently to create, divide, transition, and retire.
- Make inherited, reset, transformed, independently drawn, and conservatively
  partitioned daughter values explicit. Reconstruct derived geometry from actual
  daughter ownership instead of copying a parent's derived cache.
- Held samples are historical state even when their source is reconstructible.
  A checkpoint at MCS 7 for cadence 5 must retain the sample taken at MCS 5,
  rather than recompute from MCS 7 sources. Off-tick daughter initialization
  declares its sampling behavior; preserve the global periodic phase by default
  instead of silently restarting the component's cadence.
- Declare concise inheritance/partition/reset policies beside the state or
  reusable component they govern, then resolve them once for the complete
  lifecycle transaction. Common division rules should not repeat storage-slot
  mappings or a policy for each scalarized vector component. Missing or
  conflicting policies identify the quantity and event before execution.
- Permit compound events and deterministic arbitration when several rules
  target the same cell or consume the same capacity.
- Specify same-boundary ordering: growth, differentiation, division, link
  admission, retirement, observation, and native initialization.
- Preserve capacity failures as atomic operational outcomes with useful
  requested/available information. Keep fixed capacity efficient.
- If growth of capacity is added, restrict it to a settled explicit operation
  that validates allocation, native pools, relationships, derived state, and
  checkpoint identity together. Do not silently resize inside kernels.
- Define containment/compartment division and merge/fusion separately where
  required; those are richer identity changes than single-cell division.

Defending examples: competing division rules, partitioned receptor amount,
linked-cell retirement, daughter failure, lineage observations, and stale handles.

### F10. Relationships and multicompartment models

- Extend scalar payloads to useful structured mechanics and kinetic state.
- Specify incident traversal, endpoint-derived values, link age, capacity,
  generations, creation/removal criteria, and retuning independently of storage.
- Add directed relationships, cell-to-fixed-point anchors, and selected
  cell-to-environment relations when models require them.
- Support contact-dependent links, spring plasticity, rest-length evolution,
  bond rupture, and endpoint state coupling through common processes.
- Model containment, nuclei, membranes, clusters, and parent-child identities
  explicitly; external adhesion and internal interface energy may differ.
- Define division/retirement/transition propagation across compartments and
  links, including conservation and capacity arbitration.
- Do not turn LocalMath packed relation generations into the scientific cell or
  link identity authority. CorePotts owns that identity.

Defending examples: two cells sharing a spring, directed signaling, a fixed
anchor, nucleus/cytoplasm mechanics, and division of a linked compartmental cell.
These are established model demands, not a claim to reproduce another simulator:
[CompuCell3D relationship examples](https://pythonscriptingmanual.readthedocs.io/en/4.5.0/focal_point_plasticity.html).

### F11. Randomness, kinetics, and mechanical fluctuations

- Retain addressed CPM randomness and explicit replica/repeat identity.
- Give user processes and component instances stable random-operation identity;
  draws tied to acceptance, lifecycle, or time boundaries have different meaning.
- Support structured distributions and correlated quantities through explicit
  numerical laws; do not capture host RNG objects inside evaluators.
- Specify random draws on rejected/failed transactions and replay after restore.
- Preserve conventional CPM kinetics separately from equilibrium sampling.
  New proposal kernels need probability accounting, null-attempt treatment,
  attempt normalization, and their own acceptance guarantees.
- Honor the charter's equilibrium auxiliary constraints and nonequilibrium
  fluctuating pressure/tension as distinct scientific families. Model components
  can express laws using common state/process machinery, but any new equilibrium
  algorithm belongs in CorePotts with independent statistical checks.
- Treat stochastic intracellular reactions/SDEs and their solver RNG streams as
  an explicit native coupling extension, not as an ODE with an arbitrary random
  callback. Specify units and physical time.

Defending examples: two cells with independent polarity noise, fluctuation-driven
mechanics, restart after a rejected event, and a tiny equilibrium distribution
when an equilibrium claim is actually made.

### F12. Dimension, geometry, and difficult global algorithms

- Support 3D through the entire chain: domain construction, initialization,
  contacts/surfaces, moments, proposals, checkerboard coloring, lifecycle geometry,
  native fields, observations, checkpoints, and actual device tests.
- Reuse dimension-generic mathematics where valid. Document genuinely
  dimension-specific connectivity and curvature rules.
- Distinguish local connectivity checks from exact global connectedness,
  topology preservation, and morphology measurements. Existing LocalConnectivity
  and ActEnergy must not be presented as missing features.
- For a global test, specify whether it is exact on every proposal, incrementally
  maintained, or sampled. A boundary-time scan cannot silently replace a
  per-proposal hard constraint.
- Introduce global workspace and algorithms through existing execution/publication
  boundaries; retain independent tiny scientific oracles, not a second executor.
- Track computational costs openly. Some correct algorithms will have a narrower
  set of efficient execution strategies than local energy terms.

### F13. Observations, experiments, and persistence

- Observe the same declared quantities used by the model, with explicit cadence,
  reduction, units, domain, and retained fields. Keep device-to-host movement
  explicit and amortizable; observation should not force every state to transfer.
- Expose mechanisms and rejected events through opt-in bounded diagnostics.
  Sampling diagnostics must not consume model RNG or change accepted results.
- Provide lineage, relationship, field, vector, and tensor observations and
  useful MakiePotts encodings through public values.
- Support low-memory statistics and explicit recording sinks at settled
  boundaries, with a declared IO failure policy. Keep plotting optional.
- Clarify restart, logical checkpoint portability, and bitwise continuation as
  separate promises. User extension state needs explicit persistence semantics.
- Keep portable experiment parameters, model provenance, seeds, units, and
  resolved environment as scientific reproducibility information. Avoid a new
  development evidence/certification database.
- Use SciML ensembles for replicates and parameter sweeps. Provide conventional
  observable/loss functions for downstream fitting without claiming a
  differentiable discrete stochastic trajectory.
- Offer geometry/mask/data loading as explicit preprocessing with documented
  labels, scale, coordinates, and licensing. Do not mutate package environments
  or fetch large datasets during model construction.

### F14. Diagnostics, inspection, and interactive development

- Capture useful source locations in normal authored code, including macros and
  component factories; preserve the original expression through normalization.
- Display the existing expected/actual/alternatives/expression data coherently.
  Report multiple independent source errors in one cold validation pass.
- Implement scientific `explain` views for dependencies, domain/shape/unit,
  before/after meaning, affected anchors, time sampling, cost, and execution.
  These are projections of the existing authorities, not new model facts.
- Map runtime failures to component path, expression, relevant cell/link
  identity, boundary, and corrective choices where available. Keep raw device
  errors as developer detail.
- Distinguish missing contracts, unsupported combinations, invalid initial
  data, user numerical failures, resource exhaustion, and implementation bugs.
- Make small REPL displays, tab completion, `?` help, keyword constructors,
  and model summaries useful before a full compile or solve.
- Support rapid modification through current `remake` and structural rebuild
  paths with documented invalidation. Do not promise live replacement of an
  already-compiled callable during active execution; rebuild at a safe boundary.

Every new authoring feature ships its own construction errors, short display,
public example, and ordinary behavioral test. P15 integrates those explanations
with richer observations; it is not where basic usability first appears. Error
tests defend useful source/component context and the violated scientific
contract, not a brittle full rendering or incidental internal type name.

### F15. Internal readability and compilation behavior

- Preserve and update the existing [Potts compiler map](../../PottsEcosystem/Potts.jl/src/compiler/README.md)
  and [Core execution map](../../PottsEcosystem/CorePotts.jl/src/execution/README.md).
- Replace long positional author-facing transfer construction with named,
  validated construction of the *same* owned contract. Move builtin and external
  consumers together and remove replaced constructors in the same cutover.
- Make operational manifests visibly operational. Runtime initialization and
  coupling currently consume `execution_plan.reports.states` and related fields;
  don't merely rename that bucket and retain a second copy for inspection.
- Review large concrete proposal-context construction around durable concerns
  such as geometry, gathered scientific values, and outputs. Group fields only
  when it clarifies ownership without duplicating types/state or losing inference.
- The current gathered proposal context has a 30-argument constructor, while
  checkerboard read groups and their numeric decoding offsets are assembled in
  separate places. Derive decoding from the same cold declaration that creates
  the groups. This removes a concrete synchronization burden, rather than adding
  an abstract context hierarchy.
- Share verified pure moment-to-geometry arithmetic across proposal, gathered,
  and lifecycle consumers. Keep each consumer's state selection and hypothetical
  overlay explicit. The eigenvalue helper is already shared; reuse it.
- Keep validation at the appropriate boundary: semantic completion, concrete
  backend admission, runtime data checks. Repeated checks may defend different
  trust boundaries; remove only proven redundant owners, not defenses by count.
- Make transaction flow followable: read settled bank -> compute candidate ->
  validate -> settle/publish; failures discard candidate effects. Native results,
  lifecycle effects, and derived values must join that same story.
- Keep ordinary oracles within their owning package. Downstream packages use
  CompilerSPI/BackendSPI/public authoring instead of internal structs/fields.
- Measure load latency, completion/lowering time, first solve, repeated `remake`,
  warm step allocations, compile growth with model size, and workspace scaling.
  Prefer value-level data for homogeneous repeated instances when it reduces
  demonstrated specialization growth.
- Expand precompile workloads using representative small public workflows;
  avoid importing the whole modeling/rendering ecosystem at package load.
- Fix misleading comments, stale commands, and unreachable examples as part of
  the responsibility change that exposes them. Do not perform cosmetic file
  splitting, wholesale reformatting, or an unrelated architecture rewrite.

### F16. Hardware and operational breadth

- Keep functional support separate from determinism, exact replay, and speed.
- Audit every new quantity/effect for adaptation, lifetimes, failure propagation,
  aliasing, bounded workspace, and actual device execution.
- Grow CPU/Metal combinations deliberately; remove incidental exclusions only
  after the combination's transaction and numerical contracts are tested.
- Add CUDA/ROCm only with available real hardware, supported Julia dependencies,
  optional package extensions, and the same semantic KernelAbstractions path.
- Keep vendor adapters about storage/device integration, not separate physics.
- Add multi-device/domain-decomposed execution only if an actual workload
  justifies halo ownership, cross-partition identities, conflict/commit, and
  numerical semantics. This is a research branch, not a checkbox on GPU support.
- Keep external orchestration and deployment outside the internal scheduler.

## 4. PottsModels.jl

### Responsibility and dependency direction

PottsModels should be a normal independent Julia package containing reusable
scientific components, model factories, and executable modeling tutorials.
It is also a useful downstream integration consumer of the public ecosystem.

```text
PottsModels -> Potts -> CorePotts -> LocalMath -> KernelAbstractions
                 |
                 +-> native MTK/SciML systems through optional integrations

PottsModels tutorials/visualization -> MakiePotts -> explicit Potts observations
```

The arrows represent dependency/use direction, not a second execution path.
PottsModels must not own tracker storage, a solver wrapper framework, an event
scheduler, runtime capability tables, or a private checkpoint system.

Potts and CorePotts must not acquire a package/test dependency on PottsModels.
Their minimal scientific contract fixtures remain with them. A separate
ecosystem CI invocation can use PottsModels as a downstream test without
reversing the package dependency graph.

### Proposed layout

```text
PottsModels.jl/
  Project.toml
  src/
    PottsModels.jl
    components/             reusable mechanisms using public Potts declarations
    models/                 assembled scientific model factories
  test/
    runtests.jl             ordinary package test entrypoint
    components/             laws and parameter/initialization contracts
    models/                 bounded end-to-end model behavior
    compositions/           deliberately chosen interaction cases
    oracles/                independent tiny scientific calculations
  docs/
    Project.toml
    make.jl
    src/                    model-building guide and model explanations
  tutorials/                executable, single-source instructional programs
  dev/
    Project.toml            optional development tools and test dependencies
    setup.jl                small explicit sibling Pkg.develop helper
  integration/              expensive native or cross-model combinations
  test/metal/               model-level real-device witnesses
  benchmark/                reproducible authoring/compiler/runtime studies
  experiments/              longer scientific runs and paper-specific environments
```

Create optional directories only when their first real consumer lands. In
particular, do not scaffold empty plugin hierarchies or a model registry.

Factories should return ordinary models, initialization values, and documented
observations using ordinary Julia functions/NamedTuples when sufficient. They
should not call `solve` automatically. Keep algorithm, scalar, hardware, solver
profiles, and saving policy available to the caller.

The public Potts authoring primitives stay in Potts. More opinionated biological
assemblies belong in PottsModels. Existing essential builtin terms need not be
moved simply because a new library exists. Move complete publication-oriented
examples and their model-specific assertions/tutorials together, keeping small
Potts contract tests independent. Remove the displaced example implementation;
current documentation can link to its new owner without a forwarding executor.

### Dependency and installation experience

- Basic models should not require plotting, a GPU package, every native solver,
  or all fitting libraries just to load PottsModels.
- Use weak dependencies/extensions only where a real optional family needs
  them; scientific factories should preserve upstream native systems.
- Published package compatibility stays broad and tested. Until required
  packages are registered, document explicit Git-tag installation separately
  from sibling development. Do not silently fall back to moving main branches.
- No package installation in tutorials' model definitions and no source-local
  absolute paths or shared committed developer Manifest.
- Tutorials use small local data or explicit artifacts with sources/licenses.
  Research-sized datasets and runs are separate choices.

### Developer environment

The preferred workspace is five sibling checkouts under a plain directory.
`dev/setup.jl` should accept an explicit sibling root, validate paths, activate
an ignored task-specific environment, and `Pkg.develop` all selected packages
together. It should print resolved paths and give the ordinary commands to run.
It must not fetch branches, reset checkouts, install GPU drivers, or change the
user's global environment. Optional Revise/profiling tools belong here.

Use separate task environments for separate PR worktrees. Verify that test
processes load the intended sibling paths; a successful run against an older
installed package proves nothing about the edits. Functional development uses
normal resolution. A deliberately resolved environment can use
`Pkg.test(...; allow_reresolve=false)` when the exact dependency selection is
part of the experiment; that is not required for every developer run.
[Pkg documents both path development and test resolution](https://pkgdocs.julialang.org/v1/api/).

The developer environment may invoke every package's own `Pkg.test` and docs
commands. It must not copy those inventories or create a parallel test executor.
CorePotts/LocalMath development remains possible without loading PottsModels.

The feedback loop should support these concrete tasks using ordinary commands:

| Developer action | Immediate useful feedback and next check |
| --- | --- |
| Change an adhesion parameter in a tutorial | Remake the problem through the supported public path, inspect the changed parameter and bounded result; no environment reset or manual recompilation stages |
| Replace a polarity factory with a differently structured mechanism | Rebuild the affected model explicitly; inspect resolved inputs, quantity ownership, and the changed component before solving |
| Add two polarity instances with one shared signal input | See separate local state and explicit shared input in the model display; a focused composition test checks independent initialization and no duplicate aggregate maintenance |
| Mix concentration and amount in a cell/field transfer | Construction points to the expression and incompatible units; fixing the transfer runs its conservation/positivity example before the full suite |
| Change a tracker law in CorePotts | Run the owning independent-rebuild test, then the public Potts aggregate consumer against that sibling checkout; inspect loaded package paths if behavior appears unchanged |
| Introduce two writers or a coupling cycle | Completion names both components and the conflicting quantity/dependency; a simultaneous or sequential scientific policy must be selected explicitly |
| Request checkerboard execution for a linked-energy model | Admission explains the unresolved parallel dependency or accepts the tested conflict law; a successful sequential run alone is not the answer |

Document which changes permit public `remake` and which require a structural
rebuild, with examples that reflect the implemented contract. Optional Revise
can assist source editing; it does not imply that a running compiled model or
native integrator adopts changed definitions. Useful feedback includes the
scientific model display and focused behavioral result, not just shorter CI.

### Tutorial curriculum

1. Construct, initialize, run, observe, and change a minimal CPM.
2. Express volume/contact energy and distinguish conservative energy from a drive.
3. Write a custom function and inspect a finite gather, including repeated owners.
4. Compose two cell kinds and reusable components with named scientific inputs.
5. Add history/activity and accepted-copy processes.
6. Define a maintained quantity; verify it against an independent recomputation.
7. Couple a field, derived cell input, and native intracellular ODE.
8. Add division/differentiation with explicit daughter policies and lineage.
9. Add relationships and conflicting compound effects.
10. Run combinations on admitted CPU/Metal profiles and explain rejected ones.
11. Observe efficiently, checkpoint, resume, and run ensemble experiments.
12. Extend a scientific operation and trace it through the owning compiler/runtime.
13. Build a new model from a paper: equations, units, missing assumptions,
    parameter mapping, simplifications, independent observables, and limitations.
14. Profile compilation, memory, and execution; diagnose an intentionally broken model.

Each tutorial should have runnable code, a short expected result, an explanation
of scientific choices, a modification exercise, and links to the owning API and
tests. Generate documentation/notebooks from one source when useful; don't
maintain separate handwritten implementations. Literate can produce multiple
formats from Julia source, and Documenter supplies executable checks.
[Literate](https://fredrikekre.github.io/Literate.jl/v2/),
[Documenter](https://documenter.juliadocs.org/stable/man/doctests/).

### Model corpus

Begin with the existing Wortel, Merks, and OpenVT bounded programs as migrated
integration examples, not newly certified paper reproductions. Add mechanism
families in the order their dependencies become available:

| Family | Mechanisms and combinations it should exercise |
| --- | --- |
| Sorting and differential adhesion | Multiple kinds, symmetric contacts, domain/parameter composition |
| Activity and persistent migration | Pixel history, geometric reduction, vector polarity, accepted-copy update |
| Chemotaxis and haptotaxis | Field sampling, gradients, contact response, uptake/deposition |
| Growth and epithelial monolayers | Mechanical target changes, division, free surfaces, contact inhibition |
| Intracellular cell cycle | Native ODE, derived inputs, latching an event, division, continuation |
| Mechanochemical feedback | Shape statistics, receptor state, field evolution, feedback to motion |
| Spring/focal adhesion networks | Incident links, payload dynamics, conflicts, endpoint lifecycle |
| Fluctuating mechanics | Pressure/tension state and explicitly nonequilibrium kinetics |
| Equilibrium auxiliary mechanics | Separate auxiliary sampling law and equilibrium checks |
| Compartmental/nuclear models | Containment, internal/external contact laws, coordinated division |
| Angiogenesis or collective migration | Field feedback, adhesion, polarity, branching/elongation and lifecycle |
| Tumor/immune or infection models | Multiple mechanisms and kinds, birth/death, signaling, stochastic processes |
| Three-dimensional tissue | The same public building blocks across geometry and execution dimensions |

These names describe modeling demands, not evidence that a particular published
result has been reproduced. An executable model, a qualitative recreation, and
a quantitative reproduction require progressively different scientific checks.
The [Artistoo gallery](https://artistoo.net/examples.html) provides additional
concrete breadth examples; it is not a performance or equivalence benchmark.

Each model owns equations/assumptions, a factory, parameter units and defaults,
initialization, suggested observable functions, minimal tests, a tutorial, and
explicit supported execution examples. Add long-run experiments and publication
data only when they have scientific value and appropriate provenance.

## 5. Testing combinations without a Cartesian explosion

Feature support is a conjunction. The matrix must cover domains, value shapes,
topology, timing, mutation kinds, model components, scalar precision, algorithms,
backends, boundary conditions, solver profiles, persistence, and observation.
Running every product of those axes is neither feasible nor scientifically useful.

Use ordinary parameterized behavioral tests with intentional selection:

- Exact enumeration on tiny systems for energy deltas, interface counts,
  lifecycle arbitration, and proposal probabilities where applicable.
- Independent formulas/recomputation for geometry, aggregates, transport, and
  deterministic continuous cases; these oracles must not call the production
  update law they are supposed to check.
- Pairwise coverage for largely independent presentation/shape/parameter options,
  plus targeted three-way and longer interactions at shared state boundaries.
- Metamorphic properties only when warranted: scaling with units, independent
  component instantiation, a neutral component's effect, symmetry where the
  boundary permits it. Do not assume renaming preserves addressed RNG streams.
- Atomicity tests inject failures after progressively later candidate work and
  confirm no partial public state, RNG progression, or retained observation.
- Compare algorithms against their own contracts. Sequential and checkerboard
  need not yield identical trajectories. CPU/GPU comparison uses exact integer
  invariants and justified per-quantity floating expectations.
- Use statistical tests with appropriate sample size and uncertainty for
  stochastic claims; avoid flaky arbitrary fixed-seed image comparisons.
- Keep unsupported combinations as precise preflight tests. Add tests of the
  newly supported conjunction when removing a restriction.

The minimum interaction set should include:

| Interaction | Specific failure it can discover |
| --- | --- |
| Ownership change + evolving field + aggregate | Cache updates triggered only by copies |
| Vector state + shared native input + drive | Manual scalarization or inconsistent snapshot |
| Two simultaneous assignments + shared output | Incidental assignment order |
| Neighbor tracker + Hamiltonian + changed owner | Incomplete affected-anchor set |
| Relationship creation + division + capacity limit | Partial publication or stale endpoint |
| Native solve + lifecycle failure + retry/restore | Solver state committed without CPM state |
| Distinct neighbors + repeated bonds + medium | Wrong average/contact weighting |
| Cadence > 1 + checkpoint + component output | Phase shift or stale sampled input |
| Periodic seam + moments + division | Wrong centroid/geometry convention |
| Structured state + slot reuse + observation | Aliasing a retired cell |
| Two instances + shared quantity + ensemble replica | Duplicated maintenance or correlated randomness |
| Conservation + deposition + field solver | Unit/grid mismatch or double-counted source |
| Two cells + finite shared field resource + simultaneous uptake | Negative concentration despite a superficially correct total balance, or nondeterministic allocation |
| Different native cadences + shared derived input + simultaneous sampling | Accidental change from declared Jacobi/input-hold semantics to sequential feedback |
| Long history + continuation + ownership change | Wrong history reset or rotation |
| 3D + lifecycle + checkerboard | A component only structurally supports 3D |
| Backend adaptation + failure + observation | Async lifetime or implicit transfer bug |

Do not store a duplicate runtime capability registry in PottsModels to generate
this matrix. The tests own their selected cases; support reporting derives from
the production authorities. Small component tests, complete model tests, and
device tests defend different contracts and should not become duplicate suites.

## 6. Dense PR chain

### How to read this chain

Each row is a **coordinated change set**. Its listed repositories need separate
GitHub PRs when they actually change. It is not possible to make one Git PR
atomically modify independent repositories. A repository named as a consumer
does not automatically need an implementation PR if its ordinary downstream
tests suffice.

Dense means one coherent behavioral change containing implementation, removed
representations, consumers, errors, tests, and nearest documentation. It does
not mean putting unrelated scientific algorithms into one enormous diff.
Implementation commits within a PR can remain small and logically ordered.

Every changed package runs its complete ordinary suite before handoff. Public
changes include strict documentation; boundary/native/persistence changes include
relevant integration; device/adaptation/admission/lifetime changes include real
GPU checks. Those checks are implicit in every row below; the last column names
the distinctive scientific validation, not a substitute test gate.

An executable public authoring example belongs in the same change as each new
capability, with its failure cases, basic display and nearest API documentation.
Engine-internal fixtures cannot substitute for constructing, initializing,
running and observing the capability through public Potts references. Keep that
minimal example in its owning package; add a PottsModels companion only when
the reusable scientific component or tutorial there actually changes. P14
organizes and broadens these examples rather than postponing usable authoring.

### Main authoring and developer-experience chain

| Change set | Actual PR owner(s) | Contents that belong together | Dependencies | Distinctive validation |
| --- | --- | --- | --- | --- |
| P01 Model package and development workflow | PottsModels; companion Potts extraction PR | Package, basic scientific factories, dev environment, executable tutorials, model tests; move Wortel/Merks/OpenVT ownership and replace old docs with links while retaining minimal Potts contract fixtures | None; use existing public capabilities | Clean install; same bounded scientific behavior; no upstream dependency on PottsModels; intended sibling paths load |
| P02 Coherent CI and contributor commands | Potts, CorePotts, LocalMath, MakiePotts; Models uses this pattern in P01 | Reviewed sibling revisions, affected owner jobs, reuse/simplification of existing ecosystem workflow, corrected docs, cancellation and ordinary test selectors | Independent of science changes; Models input after P01 | Reproduce a candidate tuple; unrelated docs edit does not launch every GPU suite; required checks cannot silently skip needed work |
| P03 Readable operation authoring and source diagnostics | Potts | Named validated construction of existing operation transfers; direct builtin/fixture/doc cutover; ordinary supported pure functions without repetitive registration; source capture, concise display, and useful existing diagnostics | None; integrate CI pattern as available | Executable custom-function/gather tutorial and external operation example; multi-context/tracker extension, nested source locations, unsupported-function explanation; unchanged results and admission |
| P04 Core scientific context ownership | CorePotts | Single cold read-group/decoder definition, comprehensible concrete proposal construction, removal of verified duplicate pure geometry arithmetic across contexts | None; before extending those contexts | Independent geometry/energy oracles, optional read groups, CPU/Metal inference and allocation behavior |
| P05 Operational manifests and derived inspection | Potts | Replace mixed `reports` runtime bucket across initialization, coupling, saved state, indexing, relationships, and inspection; preserve one canonical mapping to Core handles | Can follow P03; before quantity expansion | Initial state/indexing/observation equivalence; continuation and fingerprints handled explicitly; no second copy retained |
| P06 Structured state and compound publication | CorePotts | Logical scalar/vector/tensor/product values, storage validation/adaptation, simultaneous output groups, atomic commit and structured persistence | P04 | Swaps versus ordered assignments; late failure rolls back all fields; structured state survives lifecycle/restore |
| P07 Structured quantities and process authoring | Potts | Scoped quantity references carrying domain/anchor; declare/assemble once into existing statements; value/shape/unit checking, initialization, compound effects and basic structured observations; concise complete lifecycle policies using P06 | P03, P05, P06 | Runnable vector-polarity/tensor-state example without manual scalarization or repeated declaration lists; swap and saved values; source errors for wrong scope/shape/units/free quantity/multiple writers |
| P08 Scientific relations and gathered values | CorePotts + Potts; LocalMath only for a missing reusable law | Distinct-owner/contact-weighted/incident-link reads; standard gather/map/reduction authoring with structured projections; ordering/multiplicity/medium/empty contracts, maintenance and lowering | P04, P07; evaluate LocalMath reuse first | Runnable contact-weighted versus distinct-neighbor comparison; repeated bonds, empty neighbors, seams, structured folds and relation changes; explain the selected relation and unsupported reductions |
| P09 Mutable-source aggregates and scientific geometry | CorePotts + Potts | Declared source changes, incremental/rebuild laws, shared sufficient statistics with scientific center/shape references, numerical accumulation policy, all mutation invalidation, multiple bindings, before/after and persistence; complete lifecycle for admitted sources | P06–P08 | Executable field amount/mean and shared shape-statistics examples; independent rebuild, two consumers and division; periodic/degenerate geometry; explain drift/rebuild policy separately from freshness |
| P10 Conservative dependency closure | Potts + CorePotts where new evaluation support is needed | Affected-anchor and parallel conflict closure through supported derived/reverse relations; scoped domain energies, separate drives, and explanation of rejected locality or unsafe concurrency | P08–P09 | Runnable neighbor-volume and spring/shape energy examples with full tiny-system energy oracle; medium/edge membership and simultaneous opposite-endpoint proposals; explain why an algorithm is rejected |
| P11 Reusable components and uniform consumers | Potts + PottsModels | Ordinary factories, local references/namespaces and identity; explicit input binding/shared ownership; deliberate replacement/removal and parameter rules; uniform predicates/processes/observations without a second component DSL | P07–P10; scaffold factories earlier in P01 | Runnable replacement of one polarity mechanism and instantiation of two copies sharing an aggregate; independent initialization; fail dangling consumers and conflicting writers; inspect resolved bindings |
| P12 Expression coupling and useful native combinations | Potts; CorePotts companion for missing public settlement/exchange support | Native component/variable references, derived/structured inputs and inferred routine sampling/refresh/publication within an explicit coupling law; cadence/numerical policy, bounded same-grid exchange, checkerboard CPU and selected scalar profiles | P09, P11; use P06 publication | Executable field -> mass -> ODE -> feedback without manual intermediate state/path tuples/refresh stages; positivity/mass balance, simultaneous sampling versus sequential feedback, cadence restart and rollback; reject cycles or unsupported solver/profile choices |
| P13 Lifecycle composition across quantities | CorePotts + Potts + PottsModels | Concise component-local inheritance/partition/reset policies; extend earlier complete individual policies to native/relationship composition, capacity arbitration, lineage and compound events; sampled cell-cycle model | P06, P09, P12 | Executable aggregate+native+division model with conservative daughter amounts and reconstructed geometry; incompatible events, slot reuse, restart; errors identify missing/conflicting policy and capacity |
| P14 Reusable mechanism and tutorial corpus | PottsModels | Assemble earlier executable feature examples into reusable activity/persistence, signal/cycle, shape/links and monolayer components; progressive modification exercises, bounded compositions and model-specific scientific oracles | P11–P13; earlier rows already ship authoring examples | New model assembled through public bindings without engine edits; replacement and shared-state exercises; explicit scientific assumptions and selected pair/triple interactions; tutorials use the tested component factories |
| P15 Scientific failure/observation experience | Potts + MakiePotts; CorePotts only for missing public failure data | Integrate existing feature-local diagnostics into end-to-end explain/source mapping; sampled contribution/failure inspection, richer structured channels/display and efficient explicit observation | P05, P11–P14; basic errors/displays/examples ship in each preceding row | Executable diagnosis/repair and retained-observation examples; source/component mapping, no RNG/result perturbation, stale generation and unsaved-value errors; public rendering contracts where changed |
| P16 Measured authoring/runtime performance | Potts and/or CorePotts; PottsModels scenarios | Address measured compile specialization, excessive allocation or setup costs; representative precompile workloads and public reproducible benchmarks | Representative P14 consumers exist; profile earlier too | Separate load/compile/first solve/warm step/remake/capacity scaling; no machine-specific pass-time threshold |

P07/P12 must test actual scaled values across native unit boundaries, including
different units with the same dimensions. P12/P13 distinguish a settable native
unknown from a reconstructed observed output when initializing or dividing.
Their cadence example restores a held MCS-5 sample at MCS 7 and exercises an
off-tick division without silently shifting the global schedule. These are
behavioral cases in the ordinary owner suites, not additional PRs.

P01 and P02 may proceed together. P03–P05 are independently understandable
preparation, not a global cleanup of unrelated files. P07 intentionally follows
the specific P03/P05 operation-construction and operational-manifest cutovers
because the new quantity path uses both; that ordering avoids expanding the
interfaces slated for replacement. Existing-model work in P01 need not wait.
P06–P13
are the main semantic spine; their companion upstream/downstream PRs should be
developed against one concrete dependency selection. P14 must not be the first
time a feature sees a model: every preceding semantic PR already includes small
public consumers; P14 assembles the broader reusable library and curriculum.

If P06 replaces a Core representation consumed by Potts, P06 and P07 are one
coordinated merge group; P06 must not merge and leave its public consumer waiting
for a later project step. Independently complete additive support may merge
alone. Apply the same rule to P04 or any other row that changes an upstream
consumer contract. Dependency ordering describes implementation order, not
permission to leave a direct cutover incomplete.

The original unconsolidated main-spine estimate was roughly thirty repository
PRs. The [consolidated dependency map](consolidated-pr-dependency-map.md) now
enumerates a base of twenty main-spine and twenty-eight breadth PRs, with
conditional owner companions explicit. Its grouping/dependencies supersede
the implied one-row-at-a-time delivery of this feature table; scientific scope
and required tests remain preservation requirements. Do not open both sets of
PRs or split declarations, implementation and tests to reach a numerical target.

### Breadth branches with explicit scientific decisions

These branches are part of the long-range aspiration. They can start when their
dependencies are available; they do not all have to wait for P16. They must not
be hidden inside the main spine as supposedly small generalizations.
Each breadth row can contain several coherent change sets: directed links and
compartment ownership, hybrid events and stochastic solvers, or new moves and
new meshes should be separate complete PR groups when their contracts differ.
The branch row is not an instruction to combine those into one mega-PR.

| Branch | PR owners and dependency point | Dense scope | Required scientific witness |
| --- | --- | --- | --- |
| B1 Three-dimensional modeling | CorePotts -> Potts -> PottsModels; after structured geometry/lifecycle contracts | 3D contacts/moments/proposals/coloring/division/fields/initialization and observation; LocalMath change only if a real missing relation is found | Same component definitions in 2D/3D where mathematically valid; tiny energy/division oracles and actual 3D CPU/Metal execution |
| B2 Equilibrium auxiliary and fluctuating mechanics | CorePotts -> Potts -> PottsModels; P06/P09/P11 | Separate equilibrium transition law and nonequilibrium mechanical-state components; structured stochastic state, units, lifecycle, checkpoint | Joint/marginal distribution or balance check for the equilibrium claim; independently checked noise/correlation response for fluctuating mechanics |
| B3 Rich links and compartments | CorePotts -> Potts -> PottsModels; P08/P13 | Directed/anchored links, dynamic payloads, containment and coordinated compartment lifecycle where an actual model requires them | Directed exchange, anchored spring, nucleus/cytoplasm cell and its division with link conservation/rollback |
| B4 Hybrid events and stochastic intracellular systems | Potts + CorePotts boundary companion as needed -> PottsModels; P12/P13 | Native event localization/requests, event order and reinitialization; separately specified SDE/jump coupling and RNG semantics | Threshold event near a boundary; failed event+division; stochastic partition/restart; actual admitted solver/backends |
| B5 Reciprocal multiscale fields | Potts + CorePotts if new transactional exchange is needed -> PottsModels; P09/P12 | Extend P12's basic same-grid exchange to multiple species, nonlinear reaction/transport, independently specified sampling/deposition and different grids; new PDE discretizations through native interfaces | Mass conservation and unit checks across changing ownership; reaction-diffusion oracle; multigrid transfer error |
| B6 Global morphology and topology | CorePotts -> Potts -> PottsModels; P09/P10/P12 | Explicit exact global checks or incremental algorithms, scheduled morphology with declared freshness, workspace and failure behavior | Known disconnect/hole cases; independent tiny global scan; avoid equating sampled morphology with a per-proposal constraint |
| B7 Additional hardware | LocalMath/CorePotts device extensions -> Potts -> model witnesses; stable main-spine contracts and available hardware | CUDA or ROCm storage/admission/integration through existing KA semantics, profile-specific support and real-device tests | Same representative combinations on the actual backend; numerical, ownership, failure and lifetime checks; measured performance |
| B8 New move algorithms and non-Cartesian domains | CorePotts -> Potts -> PottsModels; actual scientific demand | Swap/multisite/conserved moves, other proposal distributions, specialized meshes or geometry; each scientifically distinct algorithm separately named | Reverse probability/acceptance or kinetic normalization, independent reference calculation, write conflicts and boundary behavior |

Broader fitting/inference, SBML or other model interchange, dynamic remeshing,
hybrid off-lattice mechanics, and multi-device domain decomposition remain
explicit application/extension projects. Provide clean scientific quantities,
observables, native boundaries, and experiment factories now so those projects
are possible; do not claim to implement them through a generic escape callback.

### Early choices to make concrete during implementation

These are proposed defaults, not permission checkpoints:

1. Start quantity values with fixed-size shapes; dynamic ragged data uses bounded
   relations and separate capacity, not arbitrary resizable objects per cell.
2. Implement additive sufficient statistics before general non-invertible
   aggregates. Admit min/max maintenance only with an explicit state/rebuild law.
3. Keep declaration identity and writer ownership explicit; infer repetitive
   plumbing and legal dependency ordering, not scientific sampling choices.
4. Keep current native simultaneous sampling as an explicit supported split;
   add a different split only when a model and numerical test require it.
5. Start CPU native-combination expansion with checkerboard/Float64, then a
   meaningful Float32 profile. Extend Metal combinations with real-device tests.
6. Use fixed capacity initially, with better requirements/exhaustion diagnostics.
   Capacity growth requires a separate settled transaction and a real workload.
7. Prefer component factories over a new modeling macro until repeated authored
   examples establish what syntax would actually help.
8. Correct the vision's proposal-dependent Hamiltonian and wrapped-centroid
   examples before copying them into new tutorials.
9. Keep exact replay deliberately scoped. A newly extensible feature may first
   have functional support and ordinary restart without a stronger replay claim.
10. Prioritize B1 and B2 highly: 3D broadens tissue models and the charter already
    identifies the auxiliary/fluctuating mechanical families as defining goals.

## 7. CI design for useful density

### Current behavior and opportunities

The current workflows already use Julia setup/cache actions, PR cancellation,
ordinary package runners, and a macOS smoke/full-package distinction. Potts,
CorePotts, and LocalMath already use ParallelTestRunner with focused selectors.
These facilities should be improved, not replaced by a bespoke test platform.

Potts currently launches Ubuntu package tests, macOS smoke, integration, exact
replay, Metal, and a separate strict docs build on PRs. Its weekly sibling-main
check is only a package-suite check. CorePotts/LocalMath also have real Metal
jobs; MakiePotts amortizes many rendering/docs tasks in one Ubuntu job.

Dependency selection differs: Potts CI/docs select CorePotts `3bab07f...`, while
the inspected Core main is `7183bcec`; Core uses LocalMath main, and Makie uses
sibling mains. Testing an older supported dependency is legitimate, but these
green results do not identify the same combined ecosystem.

The existing [ecosystem workflow](../../PottsEcosystem/Potts.jl/.github/workflows/ecosystem-qualification.yml)
already accepts four exact source revisions and runs owner suites, docs,
rendering, Metal and replay. Reuse its useful checkout/execution mechanics and
add PottsModels as a downstream consumer. Generalize it by removing hardcoded
RC2 identity/citation checks and the parallel inline repository-spelling policy
scans. Meaningful import/public-boundary behavior belongs in ordinary owner
quality tests. Keep actual release metadata checks in their normal release task
if needed, rather than imposing them on every feature review.

Correct documentation that currently disagrees with execution: Core/LocalMath
guides describe hosted Metal as unavailable despite their jobs; LocalMath names
an obsolete runner path; Makie describes immutable sibling selections while
using main; Potts describes per-witness fresh Metal processes while its runner
includes witness files in one process. State what the workflow really does.

### Three dependency purposes

| Purpose | Selection | What the result establishes |
| --- | --- | --- |
| Normal package compatibility | Declared version ranges, ordinary resolver, explicit tagged Git dependencies while needed | The package functions with this resolved compatible environment |
| Dependent PR integration | Concrete reviewed sibling revisions in temporary checkouts; develop those paths together | The proposed changes work as this selected ecosystem |
| Exact replay | Explicitly supported source/Julia/dependency/platform/numerical identity | The specific tested continuation guarantee |

Source revision selection for review is ordinary Git practice. It is not an
evidence-hash system, and must not become a runtime field or a reason to pin
every package dependency permanently. Record the tested selection in the normal
workflow inputs/logs and PR description, not a second compatibility database.

### Run policy

| Change or event | Work that adds relevant evidence |
| --- | --- |
| Local editing | Smallest owning test files and the changed public scenario; use existing test selectors |
| PR update | Changed-package complete CPU suite, appropriate boundary tests/docs; relevant expensive jobs selected conservatively from changed responsibilities |
| Final reviewed source changes touching execution/adaptation/admission/lifetime | Required real-device owner and affected downstream checks; full changed-package suites and relevant integration/docs must be complete |
| Only a downstream scientific model changes | PottsModels full package/model tests and docs, plus the model's native/device/rendering checks when applicable; do not automatically rerun all unchanged upstream unit suites |
| Low-level semantics changes | Owner suite plus affected Potts public/model combinations; impacted device and persistence checks |
| Documentation/public examples change | Strict owner docs and runnable affected examples; inherited package workflow requirements remain unless deliberately changed in the CI PR |
| Selected coherent merge/release group | Ordinary affected owner suites and combined downstream integration at the final selected revisions; a complete ecosystem run where the dependency changes warrant it |
| Scheduled compatibility checks | Broader dependency/platform combinations and a representative downstream set; supplement rather than replace required pre-merge validation |
| Expensive scientific reproduction/performance campaign | Explicit runs or schedule, with scientific outputs and benchmark analysis; no brittle per-push wall-time requirement |

Do not use a docs-only heuristic to skip a changed executable tutorial or a
project/dependency file. Ambiguous path changes should choose broader testing.
Changes in shared compiler/setup/serialization/extension code fan out widely.
Select checks from the entire PR diff against its target and from changes in
selected sibling revisions, not only the most recent push. Dependency-only
changes must rerun affected consumers even when consumer source did not change.
Ordinary required check names should remain stable; a final status job must
distinguish intentionally inapplicable work from failures/cancellations or an
unexpectedly skipped dependency. Skipping an entire required workflow through
path filters can leave pending checks; account for GitHub's actual trigger and
job behavior. [GitHub workflow documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

Draft PRs can provide cheap feedback, but draft status does not establish that
a change is merge-ready. Full relevant validation is required on the final
reviewed source, including the dependencies selected for that result. Do not
carry a passing result onto changed source or changed dependencies silently.
If expensive checks are reduced for drafts, configure `ready_for_review` and
dependency-selection changes to start the full relevant runs. A final docs-only
push cannot erase the GPU requirements of execution changes earlier in that PR.

Select downstream work from the changed public responsibility as well as paths:

| Changed responsibility | Owning checks and public consumers that must follow |
| --- | --- |
| LocalMath gather/reduction or publication law | LocalMath ordinary mathematical/scientific tests and applicable device tests; Core execution consumers and the Potts gather/compound-effect examples using that law |
| Core tracker, geometry, identity or transaction contract | Complete Core suite and applicable device tests; Potts public quantity/lifecycle integration and the affected PottsModels composition/restart scenario |
| Potts scope, component binding or operation construction | Complete Potts suite and strict docs; external public construction/example tests and affected PottsModels factories; device checks when lowering/admission changes |
| Native binding, cadence, output settlement or persistence | Potts native integrations including held-sample restart and failure atomicity; the field/aggregate/native/division consumer; applicable native device profiles and the separate replay claim when affected |
| Saved observation or render-channel protocol | Potts public retained-state tests and MakiePotts protocol/rendering tests; model-side observation example, without repeating unrelated field-solver tests |
| CI setup, dependency resolver input or selected sibling commit | Resolve the actual selected environment; rerun checks whose code/dependency selection changed and their affected downstream consumers, even when the consumer PR diff is empty |

These are reviewable examples of test ownership, not a second machine-readable
test registry. Use normal package inventories and ordinary workflow conditions.
A public-consumer check constructs a model from supported declarations, runs a
bounded scenario, and asserts scientific output or a documented failure; it
must not reach into upstream private state merely to report a passing boundary.
Required checks for a dependent PR must identify the tested sibling selection
in their normal logs and PR context. An unrelated successful manual workflow or
an earlier result for a different selection cannot satisfy that review.

When the selection changes, first identify which actual upstream code changed.
A Core geometry change propagates to aggregate/energy/lifecycle consumers; a
PottsModels-only prose edit does not. If the changed responsibility cannot be
bounded confidently, run the broader downstream integration. When existing
results are reused, their source, selected dependencies and relevant execution
profile must still match the reviewed work; this is ordinary result accounting,
not a new approval process or evidence database.

### Reduce costs without weakening claims

- Cancel superseded PR runs; keep useful final logs from failures.
- Resolve/develop siblings once per environment and cap precompile/test worker
  counts to actual runner resources. More workers can increase compilation and
  memory costs.
- Use the existing test runner's units for balanced workers; share expensive
  setup within a compatible job. Keep tests requiring fresh extension load
  orders in fresh processes, and document that distinction accurately.
- Cache dependency downloads/artifacts and compatible compilation products;
  include Julia/OS/architecture/environment in cache identity. A cache hit is
  not test evidence. Don't pass an uncontrolled mutable developer depot as a
  shared cross-platform test environment.
- Group docs/rendering or native cases when setup dominates. Split independent
  families when retries/serialization dominate. Measure both before choosing.
- Prefer owner unit results plus downstream boundary/model checks over repeating
  every unaffected upstream suite in each consumer PR and then again in a giant
  ecosystem job.
- Keep full owner suite validation for every changed package. Integration tests
  cover the combination; they do not replace those owner contracts.
- Reusable workflow calls are justified when they remove duplicated commands;
  do not create a general scheduler or runtime capability system in CI.
- Release publication permissions stay outside ordinary untrusted PR jobs.
  Test candidate branches with read-only permissions; no secret-bearing
  execution of arbitrary PR code through privileged trigger shortcuts.

Measure setup/resolve/precompile time, test worker utilization, suite duration,
peak memory, rerun frequency and runner minutes from ordinary workflow logs.
The review does not establish a numerical speedup or CI-budget target.

## 8. Cross-repository cutovers and release ordering

1. Develop all members of a change set against explicit sibling worktrees or
   branches. Put required dependency selections and linked PRs in ordinary PR
   descriptions. Avoid moving-main dependencies for the review result.
2. Test the set together using owner suites and relevant downstream scenarios.
   Use the existing ecosystem workflow mechanics; no second executor or gate.
3. Merge/release upstream first: LocalMath -> CorePotts -> Potts -> downstream
   MakiePotts/PottsModels, including only affected repositories.
4. Apply normal package version/compat bounds so published packages cannot
   resolve an incompatible mixture. Revise downstream selections after upstream
   squash/rebase/merge and rerun checks affected by the resulting revisions.
5. Remove replaced constructors, representations, examples and duplicate state
   ownership across the coordinated change. Do not preserve old/new runtime
   selectors or compatibility aliases merely to bridge the PR stack.
6. A coordinated merge window can leave arbitrary combinations of repository
   mains incompatible. The coherent reviewed selection and compatible published
   packages remain the supported combinations during that window. Literal
   atomic updates of independent Git mains are impossible; don't describe the
   process as though they occur. If main-at-every-instant atomicity becomes a
   hard requirement, that is a repository-organization decision beyond this plan.

Small upstream public additions can sometimes merge independently when they
have a real consumer and complete tests; direct replacements require the
prepared downstream cutover. Avoid speculative APIs whose consumer exists only
in a future roadmap paragraph.

## 9. Readability as part of each PR

For every changed behavior, the reviewer should be able to follow:

```text
public component or statement
  -> owned scientific declaration
  -> validation, units/shapes/timing and dependency analysis
  -> concrete lowering
  -> Core transaction and LocalMath execution
  -> public observation or useful failure
  -> owning behavior tests and a public model consumer
```

This is a contributor-navigation standard, not a new executable gate. Include a
brief source-map update and comments only at non-obvious scientific, ordering,
transactional, or compiler boundaries. Update nearest docs in the same PR.

Examples worth documenting end-to-end are volume energy, mutable-field aggregate,
compound polarity update, lifecycle division, and native expression coupling.
Those traces are more useful than a second prose catalog of every helper.

The most concrete early cleanup targets are:

- Potts operation declarations and source diagnostic display.
- Potts operational state manifests currently mixed into `reports`.
- Core read-group construction and numeric decoding.
- Core pure geometry formulas reused by proposal and lifecycle contexts.
- Current contributor/test commands that disagree with workflows.

Preserve the deliberate type-erasure of completed source collections where it
limits specialization. Do not infer that more parametric types make a compiler
clearer or faster. Keep concrete typed hot evaluators where execution needs them.

## 10. Deliverable criteria and first implementation target

The authoring spine is successful when an external model author can:

1. Build a model from components, replace one mechanism, and instantiate another
   without changing engine code or duplicating state.
2. Define a quantity once and consume it in a state energy, a process, a native
   input, a lifecycle predicate, and a retained observation where semantically
   allowed.
3. State scientific timing explicitly and have routine storage, source binding,
   dependency maintenance and lowering derived automatically.
4. Receive a useful explanation when a combination is invalid or unsupported.
5. Run the same model declarations on every execution profile actually supported
   for that combination, with the numerical/replay guarantee clearly identified.
6. Reproduce the small scientific checks, follow the owning implementation, and
   add a new component using ordinary Julia development commands.

The first demanding end-to-end implementation target is:

```text
changing extracellular field
  -> per-cell amount and concentration
  -> intracellular receptor/cycle equations
  -> conservative exchange and/or an explicitly nonconservative drive
  -> sampled division with daughter-state policies
  -> retained observations and checkpoint continuation
```

Use a tiny exact/recomputable version for ordinary tests and a larger tutorial
version for scientists. Add a second consumer of the derived quantity and a
competing event so the example tests composition rather than a special-case path.
Compare declared mass balances, energy differences where applicable, event
ordering, failure atomicity, and resumed results. Introduce CPU checkerboard
and qualified Metal versions only when the complete conjunction is exercised.

Build the first complete example on the admitted sequential CPU baseline. It
establishes scientific formulas, held-input timing, daughter policies and
continuation for that execution choice. Its usability example should show one
declaration per quantity, scoped expressions, direct native/component bindings,
automatic routine refresh within the declared coupling law, and ordinary public
observations. It should not require compiler-transfer records, internal paths,
duplicate tracker lists, or handwritten stage wiring in the model.
Here mechanical stage wiring means storage bindings and dependency refresh;
scientific process order, input sampling and native batch boundaries remain
explicit model choices rather than inferred numerical semantics.

Parallel admission is a separate part of the same semantic extension whenever
parallel support is claimed. In addition to tiny sequential energy oracles,
exercise simultaneous opposite-endpoint link changes and competing uptake from
one finite field resource. The admitted execution must respect its conflict,
allocation, positivity and atomicity contracts; otherwise reject that model/
algorithm combination with a scientific explanation. Sequential correctness,
independent owner claims, or a successful isolated GPU kernel does not establish
parallel composability. Compare each algorithm with its declared law rather
than demanding identical sequential/checkerboard trajectories.

Start the ecosystem/dev scaffolding and operation/source clarity work first;
then build structured state, process composition, derived quantities, and native
coupling around that target. Pursue 3D and the charter's mechanical families as
explicit broadening branches. Do not front-load a new IR, component framework,
test platform, or universal callback API in anticipation of every possible model.
