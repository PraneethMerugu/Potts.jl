# Symbolic Potts V1

Date: 2026-07-29

Branch: `codex/symbolic-potts-v1`

Status: Implementation-grade consolidation and audit complete; implementation remains prohibited
until explicit owner send-off

## Authority

This document records the owner interviews and governs the clean-break Symbolic Potts V1 work on
`codex/symbolic-potts-v1`. It is the branch-local authority for the PottsToolkit symbolic authoring
model, its ModelingToolkit integration, its compiler boundary, and its execution-facing problem
construction.

When this document conflicts with historical PottsToolkit authoring APIs, migration registries,
compatibility promises, examples, tutorials, or tests, this document governs this branch.

The existing scientific specifications remain authoritative for accepted CPM meaning: proposal
semantics, Hamiltonian terms, lifecycle behavior, relationship behavior, normalized MCS,
reproducible randomness, observation, and backend qualification. Symbolic Potts V1 is a clean
implementation and API break, not permission to silently change accepted scientific meaning.

The words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** have the meanings defined
in [the specification index](README.md).

## Interview and implementation protocol

The owner requires researched interviews and a complete specification before autonomous
implementation.

- Every interview round MUST begin with a fresh audit of the relevant repository code and current
  primary or official external sources.
- Accepted decisions MUST be recorded here before the next round is treated as authoritative.
- Open questions MUST remain visibly open; an implementation agent MUST NOT resolve scientific or
  product questions merely because one implementation is convenient.
- Production implementation MUST NOT begin until the owner gives explicit send-off after the
  interviews and specification are complete.

This document is expected to evolve during the remaining interviews. Accepted decisions may be
changed only by an explicit owner amendment recorded here.

## Clean-break mandate

Symbolic Potts V1 has **no migration or backward-compatibility obligation**.

The implementation MUST NOT add or retain:

- a `PottsModel` compatibility constructor, alias, façade, or deprecated wrapper;
- a `ModelFragment` compatibility wrapper or legacy fragment-composition path;
- forwarding methods for superseded authoring names or call shapes;
- deprecation warnings whose purpose is to preserve the old API temporarily;
- compatibility modes, feature flags, or dual old/new compilation paths;
- readers or converters for historical symbolic-model serializations or model fingerprints;
- readers or converters whose only purpose is restoring old authoring-layer checkpoints;
- migration guides, migration tables, old-to-new cookbooks, or API-transition documentation;
- ports of historical tutorials whose purpose is demonstrating legacy-to-V1 conversion;
- compatibility tests that require superseded public authoring behavior to continue working; or
- legacy implementation retained solely to make an incremental cutover easier.

Old authoring tests MUST be replaced by tests of the accepted V1 contract, not made green through
wrappers. Superseded code SHOULD be deleted once its V1 replacement is qualified. A clean,
inspectable implementation takes priority over reducing the textual diff from the old authoring
layer.

The prohibition on migration documentation does not prohibit:

- this normative specification and its decision records;
- implementation design notes required to make V1 correct;
- API reference, tutorials, or scientific examples that teach only the final V1 interface; or
- provenance that relates a V1 scientific component to a paper or accepted scientific contract.

Whether user-facing V1 documentation is implemented on this branch is a later scope decision. It
MUST NOT be introduced as migration material.

## Accepted architecture

### SPV1-001 — One canonical symbolic model

`PottsSystem <: ModelingToolkitBase.AbstractSystem` MUST be the sole canonical public symbolic
Potts model.

There MUST NOT be a parallel `PottsModel` authoring authority. A compiled execution product MUST
have a distinct name and type from `PottsSystem`.

### SPV1-002 — Public ModelingToolkit contract, not internal coupling

`PottsSystem` MUST implement the documented `AbstractSystem` interfaces needed for composition,
namespacing, variables, parameters, equations, subsystems, completion, and symbolic indexing.

PottsToolkit MUST NOT depend on ModelingToolkit's concrete `System` field layout or undocumented
compiler internals. The V1 public contract is expressed through documented accessor and
transformation functions. The concrete `PottsSystem` field layout is implementation-private.

Research basis:

- <https://docs.sciml.ai/ModelingToolkit/dev/API/System/>
- <https://docs.sciml.ai/ModelingToolkit/dev/basics/Composition/>
- <https://docs.sciml.ai/ModelingToolkit/dev/basics/PrecompileComponents/>

### SPV1-003 — Potts statements and equations are distinct

A `PottsSystem` contains:

1. first-class typed Potts statements; and
2. ordinary symbolic equations.

Potts statements own CPM domain meaning, including cell and medium declarations, lattice and field
resources, Hamiltonian terms, proposal constraints and drives, lifecycle rules, relationship
state, relationship rules, stochastic operations, and Potts-specific observations.

Ordinary equations own continuous or algebraic mathematical relationships. Potts meaning MUST NOT
be hidden in opaque ModelingToolkit metadata or encoded as fake equations.

This follows the proven architectural distinction between Catalyst `Reaction` domain nodes and
ordinary equations while preserving Potts-specific execution semantics:

- <https://github.com/SciML/Catalyst.jl/blob/79144ad28f49b594f84965c58be290be51041f6e/src/reaction.jl>
- <https://github.com/SciML/Catalyst.jl/blob/79144ad28f49b594f84965c58be290be51041f6e/src/reactionsystem.jl>

### SPV1-004 — Symbolic array state remains unscalarized

Lattice ownership, per-cell properties, fields, relationship tables, and other naturally indexed
state MUST be representable by symbolic array handles. Authoring and completion MUST NOT
automatically expand a lattice or fixed-capacity cell table into one scalar symbolic variable per
element.

These symbolic handles MUST remain usable for indexing, observables, parameter replacement,
equation coupling, problem construction, solution inspection, and checkpoint inspection.
Compilation MAY scalarize a bounded expression only when an explicit compiler pass proves that the
transformation is required and safe.

Research basis:

- <https://docs.sciml.ai/Symbolics/stable/manual/arrays/>
- <https://docs.sciml.ai/ModelingToolkit/stable/API/variables/>

### SPV1-005 — Homogeneous symbolic composition

`compose` MUST create a named hierarchical composition of `PottsSystem` values. `extend` MAY merge
Potts statements and equations into one Potts scope where its exact conflict semantics are
specified.

Subsystem identities, variables, parameters, statements, and observations MUST use
ModelingToolkit-compatible namespacing. Completed systems MUST NOT be accepted as mutable or
composable components.

Arbitrary external simulators MUST NOT be smuggled into `PottsSystem` as opaque subsystems.
Heterogeneous simulator composition belongs to an explicit adapter boundary and
ProcessBigraphs.jl.

### SPV1-006 — Completion and compilation are separate

The required lifecycle is:

```text
author -> compose -> complete -> compile -> PottsProblem -> solve
```

`complete(sys)` closes symbolic meaning. It resolves names and scope, discovers symbolic variables
and parameters, validates units and references, validates reads and writes, validates phase and
effect legality, validates required resources, freezes semantic identities and deterministic
ordering, and preserves sufficient source hierarchy for symbolic indexing and diagnostics.

Completion MUST NOT select a runtime engine, backend, numerical precision, device, or random seed.

Compilation consumes a complete system and produces a qualified execution IR and runtime plan. It
owns engine selection, backend capability checks, storage planning, relationship transactions,
RNG draw-site planning, device lowering, and kernel-ready unit-free data.

### SPV1-007 — Stochasticity is native Potts meaning

Symbolic Potts V1 MUST represent stochastic CPM behavior directly. It MUST NOT misrepresent a
discrete proposal-and-acceptance process as an MTK `SDESystem`.

- Probability distributions, stochastic rules, and the identities of semantic random operations
  belong to the symbolic model.
- Stable RNG draw-site identity and stream allocation belong to the compiled execution plan.
- Seed, replica identity, runtime interval, runtime parameter values, and run-control configuration
  belong to `PottsProblem`. Engine, backend, scalar policy, and compiled scheduling belong to
  `PottsExecutable`.
- Equal complete system, initial state, execution configuration, engine, and seed MUST satisfy the
  accepted reproducibility contract.

Different admitted engines are not required to produce identical stochastic trajectories unless a
later accepted contract explicitly requires cross-engine trajectory identity.

### SPV1-008 — Two execution engines

V1 targets exactly two engine families:

- sequential reference execution; and
- deterministic checkerboard execution.

The historical tiled engine is not a V1 target and MUST NOT constrain the IR, relationship
language, component API, or compiler.

### SPV1-009 — Unit policy

DynamicQuantities is the canonical symbolic-unit representation. Symbolic variables, parameters,
statements, equations, validation, and completion MUST preserve exact declared scale and
dimensions.

Compiled runtime and device kernels MUST receive unit-stripped numerical data in a validated,
explicit reference unit system.

Unitful MAY remain an optional boundary adapter for user inputs, calibration data, analysis, and
result presentation. Unitful types MUST NOT be part of the normalized compiler IR or device-kernel
ABI.

Research basis:

- <https://docs.sciml.ai/ModelingToolkit/stable/basics/Validation/>
- <https://ai.damtp.cam.ac.uk/dynamicquantities/stable/>

### SPV1-010 — Dependency boundary

The intended symbolic foundation is:

- ModelingToolkitBase for the system interface and common modeling contracts;
- Symbolics for symbolic values, expressions, arrays, and transformations;
- DynamicQuantities for canonical symbolic unit meaning; and
- SciMLBase for problem, remake, solve, integrator, and solution interfaces.

Unitful remains optional. Full ModelingToolkit integration MUST be tested, but PottsToolkit SHOULD
depend on the smallest stable ModelingToolkit layer that satisfies the accepted public contract.
SPV1-034 freezes the exact dependency and extension graph after package-load, interface, and
integration research.

### SPV1-011 — ProcessBigraphs owns heterogeneous orchestration

`PottsSystem` owns symbolic CPM composition. ProcessBigraphs owns heterogeneous, multirate,
Vivarium-style runtime composition between a compiled Potts process and other simulators,
components, solvers, or processes.

This boundary MUST permit an MTK equation subsystem to participate in a Potts model where the
coupling has typed symbolic semantics, while preventing `PottsSystem` from becoming a second
general-purpose orchestration runtime.

### SPV1-012 — Existing code is evidence, not an API migration target

The current `PottsModel`, `ModelFragment`, fragment port contracts, normalization pipeline,
semantic fingerprints, provenance, validation diagnostics, and lowering code MAY inform the V1
design.

Their accepted scientific invariants and useful diagnostics SHOULD be preserved where they remain
correct. Their types, names, call shapes, tuple storage, manual scoping dispatch, and internal
layering have no compatibility authority.

In particular, V1 MUST replace the handwritten declaration-by-declaration namespace rewriting with
a general symbolic and typed-statement traversal.

### SPV1-013 — Visible canonical model construction

The final V1 syntax MUST be sufficiently expressive and readable to state the complete Merks and
Wortel model assemblies using supported public components and symbolic statements.

Canonical examples MUST NOT substitute a hidden reference-model constructor, `include` file, or
opaque imported model for the assembly being demonstrated. This is an authoring-language
acceptance requirement even when user-facing documentation is implemented in a later scope.

### SPV1-014 — Symbolics is the sole expression IR

Symbolics MUST be the sole canonical scalar and array expression tree for Symbolic Potts V1.

Potts-specific reads, proposal-context values, spatial queries, relationship queries, and
stochastic draws MUST enter Symbolics through documented public registration and metadata
interfaces. Implementations MUST traverse expressions through public interfaces such as `iscall`,
`operation`, `arguments`, and public metadata accessors. They MUST NOT dispatch on or construct a
private concrete Symbolics term representation.

The handwritten `AbstractRuleExpression` algebra and its separately compiled mirror have no V1
authority and MUST be replaced rather than generalized.

### SPV1-015 — Catalyst-style domain nodes

`PottsSystem` MUST contain first-class typed Potts statements alongside ordinary symbolic
equations, following the architectural pattern established by Catalyst's `Reaction` and
`ReactionSystem`.

Potts statements own Potts-domain semantics. Ordinary equations own continuous and algebraic
mathematical relationships. Potts meaning MUST NOT be encoded as fake equations or hidden in
opaque variable or system metadata.

### SPV1-016 — Closed built-in statement families

The exact stored V1 semantic-node inventory is:

1. `CellKind`;
2. `MediumKind`;
3. `LatticeDomain`;
4. `SpatialRelation`;
5. `SiteState`;
6. `CellState`;
7. `MediumState`;
8. `ModelState`;
9. `FieldState`;
10. `HistoryState`;
11. `RelationshipState`;
12. `ProposalEnergy`;
13. `ProposalDrive`;
14. `ProposalConstraint`;
15. `ProposalModifier`;
16. `SynchronousProcess`;
17. `AcceptedCopyProcess`;
18. `RelationshipProcess`;
19. `LifecycleProcess`;
20. `EquationProcess`;
21. `Observation`;
22. `Protocol`; and
23. `RegisteredStatement`.

Supporting bindings, ownership policies, phases, effects, lifecycle effects, solver policies,
cadences, domains, layouts, and reference-unit policies are typed arguments or symbolic
operations. They are not additional stored semantic authorities.

High-level scientific components such as volume, elongation, contact energy, chemotaxis, activity,
and connectivity MAY construct one or more built-in statements. Their expansion MUST remain
inspectable and MUST NOT introduce a component-owned runtime, hidden schedule, hidden state, or
unqualified CorePotts object.

### SPV1-017 — One registered extension boundary

Third-party statement extension MUST use one versioned `RegisteredStatement` boundary.

A registered statement contains a stable schema identity and semantic version, symbolic arguments,
serializable literal options, provenance, and source location. It MUST NOT contain an executable
closure, mutable runtime object, or arbitrary CorePotts component.

Before completion can succeed, the registered schema MUST provide argument and result types, unit
constraints, namespace traversal, access and effect inference, RNG and boundedness inference, phase
and engine capabilities, reference semantics, canonical serialization, and lowering into the
qualified built-in IR.

Completion resolves and freezes the registry snapshot and records its identities and versions.
Compiled execution and device kernels MUST NOT perform registry lookup or extension-level dynamic
dispatch.

### SPV1-018 — Thin declarations, ordinary constructors

Symbolic Potts V1 MAY provide thin declaration macros where Symbolics-style binding materially
improves model readability, including the accepted conceptual spellings:

```julia
@celltypes endothelial
@media extracellular border
@variables activity(t)[x, y]
```

These macros MUST delegate symbolic variable construction and metadata to public Symbolics
interfaces. All remaining canonical construction uses ordinary Julia constructors.

V1 MUST NOT introduce a large AST-owned modeling DSL, macro-owned scheduling, hidden statement
inference from arbitrary Julia blocks, or a second expression parser.

### SPV1-019 — Four bounded effect classes

Every completed Potts statement MUST resolve to exactly one of four semantic effect classes:

1. `PureRead` reads a declared immutable snapshot and performs no commit;
2. `SynchronousAssign` reads one common immutable phase snapshot and simultaneously publishes a
   bounded set of assignments;
3. `AcceptedCopyEffect` reads proposal state plus the staged copy and commits a bounded effect
   atomically with one accepted copy; or
4. `OrderedBatchEffect` emits bounded requests from a declared snapshot and commits them in one
   canonical order.

Every mutating effect MUST have a statically known or completion-proven bound. An arbitrary host
callback, unbounded collection mutation, or closure with undeclared effects is not a portable V1
statement.

Sequential execution is an engine capability, not a semantic effect class. The same completed
effect meaning MUST feed both engine-capability analyses.

### SPV1-020 — Deterministic relationship effect language

Relationship mutation MUST use typed, bounded `Create`, `Remove`, and `Retune` effects over a
declared relationship set. Relationship processes MAY iterate only over a completion-proven bounded
domain such as current contacts or incident edges.

Arbitrary adjacency-list mutation, relationship allocation, or endpoint mutation from symbolic
model code is forbidden.

Portable relationship execution MUST:

1. emit bounded requests;
2. assign canonical semantic request identities;
3. deterministically sort or group them;
4. resolve duplicates and conflicts under the declared policy;
5. validate capacity, maximum degree, endpoint generation, and lifecycle constraints;
6. apply one canonical transaction; and
7. publish only validated relationship state.

An initial GPU implementation MAY serialize the final application of a deterministically prepared
batch. A parallel commit is admissible only when proven semantically equivalent; atomics alone are
not evidence of deterministic multi-object transaction semantics.

### SPV1-021 — Conservative checkerboard relationship boundary

The checkerboard engine MAY read an immutable relationship snapshot.

An `AcceptedCopyEffect` that mutates relationships is checkerboard-admissible only when completion
and compilation prove its complete bounded touched set and incorporate every affected cell, edge,
capacity slot, and state identity into deterministic conflict selection.

Initial V1 is not required to support contact-triggered accepted-copy relationship mutation on
checkerboard. Such a model remains valid and sequentially executable, but checkerboard preflight
MUST reject it with the unresolved effect and conflict bound.

End-of-MCS `OrderedBatchEffect` relationship processing remains an intended capability for both
engines. This boundary MUST NOT be represented through separate sequential and checkerboard model
syntax.

### SPV1-022 — Semantic phase anchors

The public semantic phase anchors are:

- `Proposal`;
- `AcceptedCopy`;
- `AfterMCS`;
- `RelationshipCommit`;
- `Lifecycle`;
- `EquationStep`;
- `Observe`; and
- named protocol-stage boundaries.

`AfterMCS` is the canonical public term because normalized MCS is the accepted scientific clock.

A phase has one declared immutable input snapshot and one commit mode. Named user phases form a
validated DAG around the semantic anchors. A phase MUST NOT mix incompatible commit modes merely
because their statements are adjacent in source.

Checkerboard colors, sequential attempts, kernel launches, workgroups, synchronization details,
and backend-specific staging are compiled schedule details and MUST NOT appear as model phases.

### SPV1-023 — Stable stochastic operation identity

Every explicit symbolic random draw MUST have a stable namespace-local `DrawKey`. The accepted
conceptual spelling is:

```julia
ξ = draw(Normal(0, σ), DrawKey(:polarity_noise))
```

The draw is a declarative symbolic operation and MUST NOT execute during model construction,
completion, simplification, or ordinary expression inspection.

Completion validates key uniqueness, distribution parameters, result type, units, and phase
legality. Compilation assigns the semantic stream and addressed draw site. Seed and replica
identity belong to `PottsProblem`.

Built-in proposal selection, proposal direction, randomized engine decisions, and Metropolis
acceptance MUST have reserved stable semantic identities and MUST appear in random-operation
inspection even when their spelling is implicit in the selected CPM algorithm.

Reproducibility is required for equal completed system, initial state, execution configuration,
engine, and seed under the accepted contract. Sequential and checkerboard engines are not required
to produce identical trajectories.

### SPV1-024 — Native equations with explicit equation processes

Ordinary symbolic equations MUST live directly in `PottsSystem`. Their mathematical meaning remains
ordinary ModelingToolkit/Symbolics meaning.

An `EquationProcess` MUST declare the execution semantics needed to couple an equation set to the
Potts protocol, including its identity, selected equations and written state, solver policy,
cadence or substeps, input snapshot, exchange/commit behavior, and semantic phase. The accepted
conceptual spelling is:

```julia
EquationProcess(
    :chemoattractant,
    field_equations;
    solver = ExplicitDiffusion(),
    substeps = 15,
    phase = EquationStep(),
)
```

`PottsSystem` hierarchy is homogeneous: its symbolic subsystems are `PottsSystem` values. An
external ModelingToolkit system MAY enter only through an explicit equation-component adapter that
exposes and validates its equations, unknowns, parameters, events, and typed coupling. It MUST NOT
remain an opaque simulator or hidden runtime inside `PottsSystem`.

ProcessBigraphs owns composition with independently scheduled heterogeneous simulators and
components.

### SPV1-025 — Strict composition and extension

`compose` preserves named hierarchy and ModelingToolkit-compatible namespaces. `extend` merges
incomplete Potts systems into one namespace.

During `extend`:

- unknowns and parameters unify only by symbolic identity;
- duplicate statement, state, process, observation, protocol, or equation identities are errors,
  including textually or semantically identical duplicates;
- silent override, last-writer-wins behavior, and implicit duplicate elimination are forbidden;
- order-sensitive meaning MUST be represented by explicit identities and dependencies; and
- source insertion order MUST NOT become an accidental semantic identity.

Completed systems MUST NOT be composed or extended. Conflict diagnostics MUST identify both
declarations and their source locations.

### SPV1-026 — Three model and executable fingerprints

V1 MUST distinguish:

1. a **semantic fingerprint** over normalized scientific model meaning, independent of equivalent
   hierarchy packaging, backend, engine, numerical precision, and seed;
2. a **completed-system fingerprint** over the semantic fingerprint plus resolved namespaces,
   validated reference units, registered extension identities and versions, inferred access and
   effect summaries, and completion-format version; and
3. an **executable fingerprint** over the completed-system fingerprint plus compiler/lowering
   version, engine, backend, scalar policy, storage plan, qualified algorithm identity, and
   capability profile.

Seed, replica identity, runtime interval, save schedule, replaceable parameter values, and initial
conditions belong to a separate problem/run identity and MUST NOT be folded into the executable
fingerprint.

### SPV1-027 — Public qualified inspection

The completed system and executable MUST expose a stable public inspection model. The accepted
conceptual query surface includes:

```julia
inspect(sys, Statements())
inspect(sys, Variables())
inspect(sys, Effects())
inspect(sys, RandomOperations())
inspect(sys, Schedule())
inspect(sys, Capabilities())
inspect(sys, Fingerprints())
inspect(executable, StoragePlan())
inspect(executable, Kernels())
```

Every qualified statement inspection MUST be able to report its fully qualified identity and
source location, normalized expression, units and reference-unit conversion, reads and writes,
effect class and bound, RNG sites, semantic phase and ordering, admitted and rejected engines with
reasons, lowering target, and provenance.

Compiler and preflight diagnostics MUST identify the public qualified statement and originating
model expression. An internal component index or kernel type alone is not an acceptable user-facing
diagnostic.

### SPV1-028 — Measured symbolic dependency boundary

PottsToolkit MUST directly depend on ModelingToolkitBase, Symbolics,
SymbolicIndexingInterface, DynamicQuantities, and SciMLBase wherever it directly extends their
public APIs.

Full ModelingToolkit is an integration and test dependency unless a required public transformation
is proven to require it in the production dependency graph. PottsToolkit MUST NOT depend on full
ModelingToolkit merely to reach undocumented compiler internals.

CorePotts MUST remain free of ModelingToolkitBase, ModelingToolkit, Symbolics,
SymbolicIndexingInterface, and DynamicQuantities. Completion and compilation MUST lower symbolic
meaning into concrete, unit-stripped, registry-free CorePotts execution data.

This boundary is architectural rather than a claim that ModelingToolkitBase is lightweight. The
Round 3 dependency probe found current ModelingToolkitBase plus DynamicQuantities close to full
ModelingToolkit in load and memory cost.

### SPV1-029 — Compiler-owned inference

Completion and compilation own semantic analysis.

They MUST derive:

- reads from symbolic variables and registered read/query operations;
- writes from assignment targets and typed effects;
- dimensions and scale through DynamicQuantities propagation;
- random-operation sites from explicit draws and built-in algorithm semantics;
- effect bounds from statement schemas and completion-proven bounded iteration domains; and
- engine and backend capabilities from the resulting access, effect, storage, and algorithm graph.

Users and extensions MUST NOT override failed analysis with unchecked capability, purity,
boundedness, unit, or access annotations.

Users MAY declare facts that cannot be inferred from an expression, including ownership, storage,
capacity, initialization, lifecycle, persistence, and an intended relation. Completion MUST verify
those declarations against all uses.

Registered extension schemas provide analysis rules subject to the same validation. Their declared
rules are not trusted runtime capabilities merely because registration succeeded.

### SPV1-030 — Explicit symbolic focal-point-plasticity bindings

Focal-point plasticity MUST use ordinary relationship state plus explicit symbolic relationship and
proposal bindings. The accepted conceptual relationship declaration is:

```julia
focal_links = RelationshipState(
    :focal_links;
    endpoints = Undirected(endothelial, endothelial),
    payload = (
        strength = λf,
        target = Lf,
        maximum = Lbreak,
    ),
    capacity = max_links,
    maximum_degree = max_degree,
    lifecycle = RemoveWithEndpoint(),
)

edge = RelationshipBinding(:edge, focal_links)
copy = ProposalContext(:copy)
```

`RelationshipBinding` and `ProposalContext` values are symbolic placeholders with stable identity.
They are not runtime iterators, mutable context objects, or stored executable closures.

The focal spring MUST be expressible as a `RelationshipEnergy` over exact unwrapped endpoint
centers and the accepted distance convention. Contact creation MUST be an `AcceptedCopy` containing
a typed `Create` effect over `copy.source_cell` and `copy.target_cell`. Breaking MUST be a
`RelationshipProcess` containing a typed `Remove` effect, a declared `edges(focal_links)` bound
domain, a symbolic break condition, and `RelationshipCommit`.

Fixed endpoint constraints, payload retuning, generation-safe lifecycle cleanup, capacity, maximum
degree, duplicate policy, and endpoint-kind validation remain explicit typed statements or
relationship-state policies. No focal component may bypass the accepted deterministic relationship
effect language.

### SPV1-031 — Canonical visible model syntax

The canonical `PottsSystem` constructor is keyword-oriented. It MUST make statements, equations,
unknowns, parameters, subsystems, initial conditions, observations, events, and name visible where
present without exposing the concrete struct layout.

Symmetric contact-law construction MAY canonically use the `↔` spelling, such as:

```julia
endothelial ↔ extracellular => 20.0
```

The canonical Merks acceptance fixture MUST visibly construct its kinds, lattice and relations,
field state, field equation, equation process, volume, elongation, contact energies, chemotaxis,
connectivity, protocol, full initial layout, stochastic problem, and observations.

The canonical Wortel acceptance fixture MUST visibly construct its kinds, lattice and relations,
site-owned activity state, activity energy and geometric reduction, accepted-copy activation,
`AfterMCS` decay, volume and contact terms, protocol, full initial layout, stochastic problem, and
observations.

Stateful compound mechanisms MUST NOT be hidden behind `Act()` or a reference-model constructor in
the canonical fixture. Convenience components are permitted only when their statement expansion is
publicly inspectable.

Initial layouts belong to `PottsProblem`, not `PottsSystem`, but the acceptance fixture MUST display
their complete construction. A hidden reference-model constructor, model import, or `include` is
not a valid syntax fixture.

### SPV1-032 — One autonomous clean-break implementation phase

After the project owner gives explicit implementation send-off, this branch authorizes one
end-to-end autonomous implementation phase.

The phase includes:

- `PottsSystem` and its public ModelingToolkit interfaces;
- the accepted statements, symbolic operations, bindings, and registration boundary;
- composition, completion, inference, validation, diagnostics, fingerprints, and inspection;
- lowering to qualified concrete execution IR;
- sequential and deterministic-checkerboard compilation;
- deterministic relationship and lifecycle transactions;
- SciML problem, remake, solve, integrator, solution, and indexing behavior;
- complete inline Merks, Wortel, and focal-link fixtures; and
- deletion and replacement of superseded authoring implementation and tests.

The implementation agent MAY restructure in-scope repository code and move work between internal
subtasks when necessary to complete the accepted phase. It MUST preserve accepted scientific
semantics and MUST stop for owner direction only when an unresolved product or scientific choice
would materially change this specification.

The phase MUST NOT add migration wrappers, deprecated aliases, migration documentation, compatibility
modes, or a dual old/new compiler path.

### SPV1-033 — Standard repository acceptance

Completion evidence MUST use ordinary repository tests and checks rather than a custom evidence
freshness or one-time release-qualification system.

The required gate includes:

- package tests on supported Julia versions;
- ModelingToolkit composition, namespacing, completion, indexing, substitution, and remake tests;
- completion inference, extension registration, unit validation, and unit-stripping fixtures;
- deterministic sequential and checkerboard fixtures;
- relationship conflict, capacity, degree, endpoint-generation, and lifecycle fixtures;
- same-seed replay and different-seed divergence;
- complete Merks, Wortel, and focal-link end-to-end executions;
- CPU allocation and performance regression checks;
- available backend tests without freshness ledgers or manually renewed attestations;
- public API, dependency, ambiguity, and stale-authoring-surface audits; and
- a final black-box authoring, completion, inspection, compile, solve, and result-access QA pass.

The branch explicitly excludes user-facing documentation. Browser documentation QA is deferred to
a later documentation phase and MUST NOT be replaced with artificial browser work. The final V1
implementation gate is black-box Julia API QA.

The branch MUST NOT introduce an evidence-freshness system, one-time release-qualification
framework, or custom CI bureaucracy.

### SPV1-034 — Final dependency and extension topology

PottsToolkit MUST strongly depend on:

- CorePotts;
- ModelingToolkitBase;
- Symbolics;
- SymbolicIndexingInterface;
- DynamicQuantities; and
- SciMLBase.

Full ModelingToolkit, ProcessBigraphs, and Unitful MUST be weak dependencies implemented through
`PottsToolkitModelingToolkitExt`, `PottsToolkitProcessBigraphsExt`, and
`PottsToolkitUnitfulExt`, respectively.

The parent package MUST own the public `EquationComponent` and `process_component` entry points.
Extension-owned concrete adapter types are private implementation details. ModelingToolkitStandardLibrary
is an integration-test and example dependency, not a production dependency or package-specific
adapter target.

CorePotts MUST NOT depend on ProcessBigraphs, ModelingToolkitBase, ModelingToolkit, Symbolics,
SymbolicIndexingInterface, DynamicQuantities, Unitful, or a cross-language transport. ProcessBigraphs
MUST remain domain-neutral and independent of PottsToolkit and CorePotts.

This clause resolves the dependency measurement left open by SPV1-010.

### SPV1-035 — Complete public ModelingToolkit system contract

`PottsSystem` MUST implement the documented ModelingToolkitBase system behavior required for:

- `@named`, `nameof`, and namespaced property access to variables and subsystems;
- local and recursive equations, unknowns, parameters, subsystems, defaults, initial conditions,
  observed equations, supported continuous events, and supported discrete events;
- independent variables;
- inputs, outputs, and bound/unbound IO classification;
- hierarchical composition, explicit flattening, strict extension, and substitution;
- completion-state queries and namespacing behavior; and
- SymbolicIndexingInterface problem, parameter, state, integrator, solution, observed-value, and
  `remake_buffer` behavior.

Implementation MUST use documented accessors and transformations. It MUST NOT read a concrete
ModelingToolkit `System` field, depend on an internal index cache, tearing state, generated
function cache, private term type, or undocumented compiler pass.

`complete(::PottsSystem)` remains the semantic closure operation and `compile(::PottsSystem)`
remains the Potts compiler entry. `mtkcompile` or structural simplification MUST NOT be invoked
implicitly by Potts construction, composition, completion, or compilation. Full-ModelingToolkit
extension methods MAY provide documented transformations only when they preserve the accepted
Potts lifecycle and diagnostics.

### SPV1-036 — Exact `EquationComponent` assimilation boundary

`EquationComponent` is a public constructor whose result is an incomplete `PottsSystem`, not a
second stored subsystem type and not a runtime wrapper.

The canonical call shape is:

```julia
@named field = EquationComponent(
    external_system,
    EquationProcess(
        :chemoattractant,
        equations(external_system);
        writes = [c],
        solver = ExplicitDiffusion(),
        cadence = EveryMCS(),
        duration_per_mcs = 30us"s",
        substeps = 15,
        phase = Before(Proposal()),
    ),
)
```

The constructor MUST:

1. inspect the supplied `AbstractSystem` exclusively through public accessors;
2. preserve its supported hierarchy, equations, unknowns, parameters, defaults, initial
   conditions, observed equations, events, inputs, outputs, and unit metadata;
3. create a stable mapping from originating symbolic identities to assimilated qualified
   identities;
4. add the explicit `EquationProcess`; and
5. return a homogeneous incomplete Potts component.

It MUST NOT retain an external numerical integrator, solver closure, callback, or independently
scheduled runtime. It MUST NOT silently call `mtkcompile`, `structural_simplify`, or another
symbolic transformation. A caller who wants a transformed external system must transform it
explicitly before assimilation.

V1 admits scalar or symbolic-array algebraic equations, ordinary differential equations with at
most one continuous independent variable, supported nested systems and connections, and symbolic
continuous or discrete events whose conditions, accesses, effects, units, bounds, phase, and
publication behavior can be proven.

V1 rejects functional callback affects, noise or Brownian equations, jump systems, unconverted
reaction semantics, delay equations outside the accepted history language, unresolved PDE domain
or discretization objects, executable initialization callbacks, multiple continuous independent
variables, private compiler caches, and any external semantic object that cannot be lowered into
the accepted equation and effect contracts. Unsupported content MUST be diagnosed with its source
system path and MUST NOT be silently dropped.

### SPV1-037 — ModelingToolkit IO is the external-interface authority

The canonical `PottsSystem` keyword constructor includes `inputs` and `outputs`. These collections
contain symbolic identities and default to empty. They are the sole declarations of intentional
external interface; V1 MUST NOT add a parallel Potts port DSL.

Ordinary equations and hierarchical composition determine which declared IO values are bound
internally. Only unbound inputs and outputs form the external interface of a completed system or
executable.

Completion MUST validate declared IO against compiler-inferred accesses:

- an external input is read-only during one Potts publication interval;
- an external output is a stored value or accepted observation available at a settled publication
  boundary;
- a declared input written by Potts is an error;
- an output with no settled producer is an error;
- one symbolic value cannot be both an unbound input and a mutable Potts-owned output;
- array symbolics preserve their declared shape rather than becoming one port per scalar; and
- internal reads and writes never become external ports merely because the compiler inferred
  them.

Qualified symbolic identity, type, shape, exact declared units, reference-unit conversion,
ownership, persistence, and publication policy MUST survive completion and executable inspection.
This same metadata drives ModelingToolkit IO, SymbolicIndexingInterface, and the optional
ProcessBigraphs bridge.

### SPV1-038 — Exactly two composition levels and one scheduling owner

The ecosystem has two composition levels:

1. `PottsSystem` plus `EquationComponent` performs compile-time symbolic composition under one
   Potts completion, phase schedule, unit system, compiler, and atomic publication protocol.
2. ProcessBigraphs performs runtime composition between independently scheduled engines,
   simulators, services, or language runtimes.

Every component has exactly one scheduling owner. An assimilated `EquationComponent` is scheduled
inside the Potts executable and MUST NOT also be mounted as an independent ProcessBigraphs
component. An independently mounted ProcessBigraphs component MUST NOT also be assimilated into
the Potts executable.

ProcessBigraphs owns global paths, store binding, global or multirate time, invocation,
reconciliation, external failure, checkpoint coordination, and publication. CorePotts owns copy
attempts, kernels, workspaces, stochastic streams, Potts transactions, and numerical execution
inside one MCS.

### SPV1-039 — Derived `process_component` bridge

The public runnable bridge entry is:

```julia
component = process_component(prob::PottsProblem)
```

The ProcessBigraphs extension MUST derive the component interface, schema, capability declaration,
and stable identity from `prob.executable`. The `PottsProblem` supplies initial state, runtime
parameters, seed, replica identity, and permitted horizon. These runtime values MUST NOT enter the
semantic or completed-system fingerprints.

The derived manifest contains:

- qualified symbolic input and output identity;
- a stable external endpoint `Symbol` derived from canonical serialization of the fully qualified
  symbolic identity, independent of source order and object identity;
- direction and inferred access;
- scalar or array element type and shape;
- canonical unit string and reference conversion;
- ownership, persistence, update law, residency, and codec;
- input interval behavior and publication cadence;
- selected engine, backend, precision, and capability envelope;
- replay class and checkpoint schema; and
- stable diagnostic and failure identities.

The returned value MUST participate through ordinary public ProcessBigraphs process and managed
engine interfaces. A private extension-owned `AbstractEngineAdapter` subtype MAY implement the
bridge. Users MUST NOT need to name that type, redescribe the Potts read/write set, or reproduce
the executable schema manually.

The V1 bridge declares the ProcessBigraphs `:interval_advance` engine-operation family. One
authorized interval is exactly one MCS in the admitted logical time scale. Its process schedule
declares partial advance unsupported, and its input ports declare frozen interval behavior.

ProcessBigraphs path placement remains explicit composition work: the bridge exposes endpoints and
schemas, and the surrounding composite binds them to hierarchical stores. Two external identities
that would produce the same endpoint name are a completion error; the bridge MUST NOT append an
order-dependent suffix.

### SPV1-040 — Whole-MCS invocation, publication, and checkpoint contract

One V1 ProcessBigraphs invocation advances exactly one complete MCS.

- The input projection is immutable and frozen for that MCS.
- All admitted output values publish atomically after the MCS commits.
- Partial interval execution and mid-MCS publication are unsupported.
- ProcessBigraphs MAY invoke the component repeatedly to implement multirate orchestration.
- A native `:mcs` logical scale maps exactly one tick to one MCS.
- A physical logical scale is admitted only when `duration_per_mcs` supplies an exact conversion
  and every invocation boundary maps to an integral MCS.
- A nonintegral time request MUST fail before Potts execution. It MUST NOT round, interpolate
  Potts state, or execute a fractional MCS.
- Every input value is type-, shape-, and unit-validated, converted from its declared external
  unit to the executable reference unit, and staged before the MCS begins. A failed input
  projection MUST NOT mutate published Potts state.
- Every output value is read only after commit and converted from the executable reference unit to
  its declared external unit before atomic PB publication.
- An invocation beyond the `PottsProblem` horizon MUST fail before execution.

Checkpoint capture is legal only when the PB and Potts runtimes are settled after a complete-MCS
publication. The Potts checkpoint component contains the logical CorePotts state, RNG
continuation, completed-MCS time, continuation parameters, executable fingerprint, schema
identity, and declared replay class. It MUST NOT serialize an incomplete kernel, scratch
workspace, Symbolics graph, external ModelingToolkit system, or extension registry.

Restore MUST verify executable identity, schema, units, capability envelope, and replay class
before reconstructing runtime buffers. PB MUST NOT reach into an incomplete MCS, kernel schedule,
or private CorePotts workspace.

### SPV1-041 — Cross-language peer protocol is deferred, not faked

A future Vivarium or other cross-language component is a ProcessBigraphs peer of the Potts
component. Its language-neutral protocol must eventually define:

- component and protocol identity;
- hierarchical typed ports and canonical unit strings;
- requested logical interval;
- immutable input snapshot and snapshot identity;
- typed output update;
- status, diagnostics, and failure;
- logical checkpoint capture and restore; and
- deterministic publication and replay classification.

The current Julia logical-checkpoint codec MUST NOT be represented as a complete cross-language
transport. Python, Vivarium, JSON-RPC, Arrow, IPC, container, and service dependencies MUST NOT
enter PottsToolkit or CorePotts.

Cross-language transport implementation is deferred from this V1 branch unless the owner
explicitly amends scope. The V1 implementation MUST preserve the derived manifest and orchestration
boundary needed by that future work.

### SPV1-042 — Integration acceptance gate

Ordinary repository and integration tests MUST prove:

- PottsToolkit base authoring loads without ModelingToolkit, ProcessBigraphs, or Unitful;
- extension methods load only when their weak dependency is present;
- the complete public MTK system, IO, namespace, property, substitution, and SII behavior;
- source-to-assimilated identity preservation through problem construction, symbolic `remake`,
  solution indexing, and diagnostics;
- ingestion of a representative supported ModelingToolkit system and
  ModelingToolkitStandardLibrary component;
- contextual rejection of every excluded external-system family;
- absence of private ModelingToolkit access;
- `process_component(prob)` derivation without a CorePotts ProcessBigraphs dependency;
- exact PB schema, direction, unit, time, capability, and failure derivation;
- atomic whole-MCS publication and rejection of nonintegral time requests;
- settled checkpoint/restore under the declared replay contract; and
- rejection of dual scheduling ownership.

These are normal tests, not a compatibility oracle, evidence-freshness ledger, or one-time release
qualification framework.

### SPV1-043 — Compilation fixes the executable contract

The canonical compilation boundary is:

```julia
compile(
    completed::PottsSystem;
    engine::AbstractPottsEngine,
    backend::AbstractPottsBackend,
    scalar_type::Type{<:AbstractFloat},
) -> PottsExecutable
```

All three keyword selections are mandatory. V1 MUST provide `SequentialEngine()`,
`CheckerboardEngine()`, and `CPUBackend()`. Optional backend extensions MAY provide Potts-owned
immutable backend descriptors.

Compilation MUST fix engine semantics, backend and device target, scalar and accumulator policy,
storage and capacities, schedules, RNG sites, relationship and effect transactions, equation
policies, workspaces, observations, capability envelope, and checkpoint schema. Neither
`PottsProblem`, `init`, nor `solve` may override those decisions.

`PottsExecutable` MUST be immutable and privately laid out. Public accessors and `inspect` MUST
expose its fingerprints, selected configuration, qualified manifests, symbolic index map, runtime
parameter and initial-state schemas, external IO, storage/workspace/kernel/schedule reports,
capabilities, replay/checkpoint information, and diagnostics. It privately owns exactly one
`CorePotts.CompiledPottsProgram`.

A compiled executable MUST NOT contain unresolved registry lookup, an external ModelingToolkit
system, DynamicQuantities or Unitful values, Symbolics expressions, source ASTs, or executable host
closures. Compilation MUST aggregate independent validation and capability failures that can be
discovered safely and report them with stable identity and source context.

V1 MUST NOT expose a public compilation cache or maintain a hidden PottsToolkit global or disk
compilation cache. Reuse occurs by constructing multiple problems from one executable.

### SPV1-044 — Parameter role is compiler-proven

The compiler MUST classify every symbolic parameter as structural or runtime-replaceable from its
qualified uses. Author metadata such as `tunable = true` is intent only and MUST NOT override
analysis.

A parameter is structural if it can affect topology, dimensions, element or storage type, shape,
capacity, maximum degree, declarations, RNG-site existence, phase, cadence, substeps, iteration,
accesses, effects, bounds, conflicts, equation algorithm, workspace, generated program structure,
or capability admission.

Every structural value MUST resolve through explicit defaults or substitution before completion.
It enters the completed-system and executable fingerprints. Changing it requires substitution on
an incomplete system followed by new completion and compilation. Capacity is always structural;
problem construction MUST NOT guess, resize, or supply compiled capacity.

A runtime-replaceable parameter changes only a validated numerical leaf. Its replacement MUST NOT
change unit, shape, storage, access, effect, bounds, RNG sites, phase, solver family, or capability.
Runtime values are converted into the executable reference units and scalar type and stored in a
typed executable-owned parameter buffer. They contribute to problem and trajectory provenance but
not the executable fingerprint.

The public `p` input accepts a symbolic pair collection or dictionary. Construction immediately
normalizes it into a typed `PottsParameters` value. Unknown, duplicate, unit-incompatible,
shape-incompatible, structural, or unresolved inputs MUST be contextual errors. Missing runtime
values resolve from executable defaults and, during `remake`, the source problem.

### SPV1-045 — Initial state, problem, and stochastic identity

The canonical host-side state constructor is:

```julia
PottsInitialState(; ownership, values = [])
```

`ownership` MUST be either `LabelledCells(labels; cells, medium)` or an `OwnershipLayout` built
from accepted `CellPlacement`, `MediumPlacement`, and procedural placement declarations. `values`
is a symbolic map to initial state, field, history, or relationship values.

Initialization MUST defensively copy mutable inputs and validate symbolic identity, shape, kind,
capacity, endpoints, generation, and units against the executable manifest. Missing values resolve
from system initial conditions and state defaults; conflicting sources are errors. Procedural
placement randomness uses a dedicated semantic initialization stream and MUST NOT shift simulation
draw sites.

The canonical problem boundary is:

```julia
PottsProblem(
    executable::PottsExecutable,
    initial::PottsInitialState,
    tspan::Tuple{<:Integer,<:Integer};
    p = [],
    seed::Integer,
    replica::Integer = 1,
) -> PottsProblem
```

`PottsProblem` MUST own its executable, normalized immutable initial data, typed runtime
parameters, absolute integer MCS span, `UInt64` master seed, and positive bounded replica identity.
It MUST NOT contain an algorithm, backend, numerical policy, capacity guess, callback, save policy,
compilation cache, or host component-realization function. Every `init` creates independent mutable
runtime state. The span satisfies `0 <= t0 <= t1`, and the first step completes MCS `t0 + 1`.

Every random draw MUST be addressed by master seed, replica, semantic stream, absolute MCS,
operation, entity, invocation, and draw. Worker, thread, device, scheduling order, and completion
order MUST NOT enter the key.

For SciML ensembles, `EnsembleContext.sim_id` supplies replica identity unless a user `prob_func`
returns a different valid replica. Ensemble repeat identity MUST be an additional deterministic
address component rather than a replacement master seed.

### SPV1-046 — Solve executes; it does not compile

The runtime relationship is:

```julia
solve(prob; kwargs...) = solve!(init(prob; kwargs...))
```

There is no positional algorithm argument. `init` validates identity, realizes state, allocates
private storage and workspaces, initializes stochastic and equation state, and optionally restores
a compatible V1 checkpoint; it does not advance an MCS. `step!` advances exactly one complete MCS.
`solve!` loops over that operation.

V1 solve controls are limited to `saveat`, `save_start`, `save_end`, `save_everystep`,
`observables`, `maxiters`, progress controls, and verbosity. `saveat` accepts integer MCS
boundaries or one positive integer cadence.

Generic `adaptive`, `dt`, `abstol`, `reltol`, `sensealg`, continuous callbacks, and arbitrary host
callbacks MUST be rejected. Equation processes own their numerical policies. Scientific mutation
and scheduling use accepted symbolic events, `Protocol`, runtime-parameter transactions, or
external inputs. `terminate!` remains an admitted interactive operation with a successful
terminated return code.

`remake` accepts only `u0`, runtime `p`, integer `tspan`, seed, and replica. It MUST NOT replace the
executable or any structural choice. Integrator `setp` is admitted only at a settled complete-MCS
boundary for compiler-proven runtime parameters, after complete validation, as one atomic
transaction effective at the next MCS. Every such update enters checkpoint and parameter
timeseries provenance.

### SPV1-047 — Solution and checkpoint contracts

`PottsSolution <: SciMLBase.AbstractTimeseriesSolution` MUST implement the applicable SciML
collection, statistics, return-code, provenance, and SymbolicIndexingInterface contracts. It MUST
support exact symbolic state, observation, and parameter indexing and exact integer saved-MCS
lookup.

The solution MUST NOT provide dense or fractional-MCS interpolation. Accessing a known but unsaved
value MUST NOT silently recompute it or trigger an implicit device transfer. Unknown and
known-but-unsaved identities MUST produce distinguishable structured diagnostics. Solution
metadata reports the executable engine, backend, scalar, and replay configuration rather than a
solve-time algorithm.

The public V1 checkpoint surface is:

```julia
cp = checkpoint(integrator)
integrator = init(prob; checkpoint = cp)
```

`PottsCheckpoint` may be captured only at a settled complete-MCS boundary. It contains executable
identity, logical state, runtime parameters and parameter history, RNG seed, replica and
continuation state, completed MCS, schema identity, replay class, and integrity checksum. It MUST
exclude scratch workspaces, live kernels, Symbolics values, external systems, registries, and
arbitrary Julia serialization.

Restore MUST validate the required executable identity, schema, unit contract, capability
envelope, and replay class before reconstructing private buffers. Portable logical reconstruction
is admitted only where the declared replay class permits it; exact replay requires the exact
continuation envelope.

V1 MUST NOT contain a reader, converter, alias, wrapper, or migration path for a previous
checkpoint schema. Applicable scientific assertions are ported to `PottsCheckpoint`.

### SPV1-048 — Curated public surface and clean-break source disposition

PottsToolkit MUST export the names required in ordinary model source: the canonical system,
executable, initial-state, problem, integrator, solution, checkpoint, lifecycle, composition,
statement, operation, domain, effect, schedule, solver-policy, component, registry, layout,
engine/backend, common inspection, ModelingToolkit-assimilation, and ProcessBigraph bridge entry
points.

Structured diagnostics, qualified IR and manifests, fingerprint and canonical serialization types
needed by extensions, SII support, statement traversal/reconstruction and registration hooks, and
backend or ProcessBigraph adapter hooks MUST be qualified `public` names rather than exports.
Compiler passes and builders, storage and workspaces, kernels, concrete adapters, cache keys,
namespace and generated-function helpers, and transaction internals MUST remain private. Source
`export` and `public` blocks are the authority; V1 MUST NOT introduce an API ledger, migration
registry, or compatibility alias inventory.

CorePotts MUST expose only a narrow qualified compiler/runtime interface centered on
`CompiledPottsProgram`, initialization, complete-MCS advance, logical state and checkpoint
import/export, capability and execution reports, and required backend hooks. PottsToolkit MUST NOT
re-export CorePotts storage, workspace, kernel, tracker, request, transaction, or coupled-schedule
types.

Implementation MUST:

1. replace root `src/authoring/**`, the root public surface, precompile workload, and SciML
   interface around V1;
2. replace hidden reference-model builders with visible Merks, Wortel, and focal-link test
   fixtures;
3. delete compatibility code, Lottery, tiled checkerboard, CorePotts ProcessBigraph adapters and
   conversions, paper-specific CorePotts assemblies, and legacy checkpoint readers;
4. first extract the qualified relationship, field, lifecycle, history, observation, transaction,
   initialization, persistence, sequential, checkerboard, checkpoint-integrity, and capability
   mechanisms required behind `CompiledPottsProgram`; and
5. then delete the old coupled declarations, plans, schedules, semantic-kernel authority, and
   public dispatch.

MakiePotts MAY be adapted to V1 runtime, state, observation, and solution interfaces to keep the
package family coherent. This is runtime integration and MUST NOT introduce tutorials or other
user-facing documentation on this branch. ProcessBigraphs itself remains outside the rewrite
except for a minimal public-protocol change proven necessary for the optional extension.

### SPV1-049 — Strict, ordinary QA and scoped supersession

The required repository gate consists of:

- PottsToolkit and CorePotts Linux package tests;
- the repository's normal ProcessBigraphs and MakiePotts tests;
- ModelingToolkit, ModelingToolkitStandardLibrary, ProcessBigraphs, Unitful, and optional-extension
  integration tests;
- fresh macOS and Windows package load plus a tiny sequential CPU trajectory;
- Aqua and ExplicitImports;
- stale legacy surface and dependency-boundary checks;
- targeted inference and warmed CPU allocation checks at owned barriers;
- same-seed/same-replica replay and different-replica divergence;
- Merks, Wortel, and focal-link end-to-end fixtures; and
- one public black-box authoring-through-solution test.

The gate MUST NOT add evidence freshness, one-time release qualification, a main-branch parity
oracle, expected-output archives, mandatory package-wide JET, hard wall-clock budgets, GPU
availability as a CPU prerequisite, documentation/browser QA, per-file coverage, or a coverage
ratchet. Performance and GPU qualification remain manual, scheduled, or hardware-specific. Any
retained hard coverage threshold MUST be one project threshold no higher than 90%.

An implementation agent MAY clone the exact main branch into a temporary directory for read-only
inspection and spot reference. It MUST NOT use the clone as a parity authority, CI input, expected
output generator, evidence archive, or retained repository artifact.

Historical specifications and evidence remain indexed. The following conflicts are superseded:

- the old PottsToolkit authoring specification for model types, authoring levels, fragments, ports,
  algorithms, problem construction, compatibility, migration, API, serialization, and
  qualification;
- the rule/model specification for its handwritten rule IR, host/expert escapes, old compiler,
  authoring API, and migration;
- the SciML specification for `PottsModel`, solve-time engine/backend selection, compilation
  cache, arbitrary callbacks, old parameter handles, legacy evacuation, and checkpoint migration;
- the CorePotts public-interface export and extension inventory;
- Phase 14 and registry contracts as authoring, coupled-plan, and compiler architecture;
- published-model hidden builders and legacy authoring fixtures, while their scientific
  mechanisms, parameters, stochasticity, and observables survive;
- the semantic-preserving consolidation contract for compatibility aliases, old dependency
  direction, evidence preservation, requalification, and migration;
- ProcessBigraph requirements placing the Potts adapter in CorePotts, while ProcessBigraphs
  semantics otherwise remain authoritative; and
- historical checkpoint migration and authoring-serialization requirements.

Surviving scientific CPM semantics remain authoritative where V1 does not explicitly change them.

In particular, V1 explicitly supersedes:

- the optional `seed = 0` problem-constructor default; V1 requires an explicit `seed`;
- ensemble trajectory-seed derivation that replaces the problem seed; V1 preserves one master seed
  and adds replica and repeat identities to the semantic random address;
- Lottery and tiled-engine time, capability, RNG, SciML, checkpoint, and qualification clauses;
- the historical direct-CorePotts scientific-authoring and broad extension surface; CorePotts
  remains independently executable only through its narrow compiler/runtime interface; and
- checkerboard support for unwrapped moments or focal links unless the V1 compiler proves the
  complete accepted-copy conflict set. The initial focal fixture is therefore sequential.

User-facing documentation and browser QA are excluded from this branch. A merge that intentionally
breaks living public documentation MUST wait for or be paired with a later V1 documentation phase.
This branch itself MUST NOT add migration documentation, replacement tutorials, or a browser gate.

### SPV1-050 — Statement identity, source, traversal, and registry are exact

Every declaration, state, process, observation, protocol, and registered statement has a
namespace-local `StatementID`. Mutable resources and processes require an explicit name. A simple
scientific term MAY receive a deterministic default derived only from statement family and target;
if that default is not unique, construction requires an explicit name. Identity MUST NOT depend on
source order, collection position, object identity, or randomized hashing.

`@statements begin ... end` is optional collection and source-capture sugar. It evaluates ordinary
constructors, attaches file, line, module, and displayed expression, and performs no semantic
parsing, scheduling, or effect inference. Direct construction is equally valid and records
`UnknownSource()` unless `source` is supplied. Source and AST data never enter compilation.

Each built-in statement implements one internal ordinary-Julia symbolic traversal and
reconstruction operation, conceptually `map_symbolics(f, statement)`. Namespacing, substitution,
symbol discovery, and reconstruction derive from that operation. Other semantic behavior remains
ordinary methods; V1 MUST NOT introduce a universal public statement-schema framework or central
tag switch.

`StatementRegistry` is an explicit host value used only by `RegisteredStatement`.
`default_statement_registry()` supplies the ordinary default. Registration is idempotent only when
schema identity, semantic version, and implementation definition match exactly; otherwise it is an
immediate error. Completion freezes an immutable snapshot, and neither compilation nor execution
performs registry lookup.

### SPV1-051 — Completion is explicit, idempotent, and Potts-owned

The canonical completion call is:

```julia
completed = complete(
    sys;
    reference_units = DeclaredReferenceUnits(),
    registry = default_statement_registry(),
)
```

`DeclaredReferenceUnits()` selects unique explicit semantic anchors: lattice spacing for length,
equation independent-variable metadata for physical time, dimensional Hamiltonian or temperature
declarations for energy, and stored-state declarations for other dimensions. Missing or ambiguous
anchors are contextual errors requiring an explicit `ReferenceUnits` override.

Completion is immutable and idempotent: `complete(completed; the_same_options...) === completed`.
Supplying different completion options for an already completed system is an error. Potts
completion owns semantic closure and MUST NOT silently invoke generic flattening, splitting,
structural simplification, or `mtkcompile`. Compilation rejects an incomplete system.

### SPV1-052 — V1 numerical policy has no hidden backend choice

The mandatory `scalar_type` compilation input fixes primary real storage and, in V1, the default
energy accumulator. V1 uses accurate math, deterministic reductions, and checked model bounds.
Backends MUST NOT silently widen, narrow, enable fast math, or alter reduction laws.

This is the sole V1 compile-time numerical profile. A later explicit wider-accumulation or
performance-policy API requires a separate accepted amendment; it MUST NOT be inferred from the
device.

### SPV1-053 — Exact run, remake, indexing, and save semantics

The solve defaults are:

```julia
save_start = true
save_end = true
save_everystep = false
saveat = ()
observables = ()
maxiters = tspan[2] - tspan[1]
progress = false
progress_steps = 1
verbose = true
```

`observables` selects only executable-declared stored state or observations; it cannot introduce a
new expression, kernel, transfer law, or runtime component. Every saved boundary owns a defensive
logical `PottsSavedState` containing all authoritative declared state selected by the save policy,
without continuation-only machinery. Requested derived observations are attached to that boundary.
Unknown and known-but-unsaved identities have distinct structured errors.

`getp` and applicable SII reads are supported on problem, integrator, and solution values.
Mutating `setp` is supported only on a settled integrator as specified by SPV1-046. `setp` on a
problem is rejected with guidance to use `remake`.

For `remake`, omitted or `missing` `u0` preserves the source initial state. A complete
`PottsInitialState` replaces ownership and values. A symbolic partial map overlays only initial
`values` while preserving ownership. Ownership cannot be partially patched; changing it requires a
complete `PottsInitialState`.

### SPV1-054 — V1 persistence preserves the logical-format contract

The in-memory `PottsCheckpoint` is authoritative. HDF5 and Zarr MAY remain optional CorePotts
storage extensions only when both encode the same new V1 logical schema, integrity metadata, and
transactional publication contract. They MUST use the narrow logical reader/writer protocol and
MUST NOT retain old checkpoint readers, Julia serialization, authoring graphs, or compatibility
conversion.

Portable logical restore and exact continuation remain different replay claims. Backend changes
are admitted only by the checkpoint's declared replay class and never silently preserve an exact
trajectory claim.

### SPV1-055 — Consolidation specification and audit are implementation authority

The implementation-grade phase contract is
[`symbolic-potts-v1-consolidation.md`](symbolic-potts-v1-consolidation.md). Its repository map,
pass order, runtime schemas, test matrix, internal slices, and exit conditions refine this document
without changing the accepted product direction.

The completed readiness audit is
[`design/audits/symbolic-potts-v1-consolidation-audit.md`](../design/audits/symbolic-potts-v1-consolidation-audit.md).
It found no unresolved product or upstream-interface blocker. This finding does not itself authorize
implementation: explicit owner send-off remains mandatory.

## Frozen public system contract

The accepted public constructor surface is:

```julia
@named model = PottsSystem(
    statements = StatementSet(),
    equations = Equation[],
    unknowns = [],
    parameters = [],
    independent_variables = [],
    systems = PottsSystem[],
    inputs = [],
    outputs = [],
    initial_conditions = Dict(),
    observed = Equation[],
    events = [],
)
```

`name` is mandatory and is normally supplied by `@named`. The constructor is keyword-oriented;
there is no public positional constructor with a second meaning. The surface does not expose or
freeze the concrete `PottsSystem` field layout.

## Round 3 closure

The non-normative research basis for this interview is
[`design/audits/symbolic-potts-v1-round-3-research.md`](../design/audits/symbolic-potts-v1-round-3-research.md).
Its accepted recommendations and syntax requirements are incorporated in SPV1-014 through
SPV1-033.

No owner decision remains open from Round 3. The required implementation-grade consolidation and
audit are complete. Production implementation remains prohibited until the project owner gives
explicit implementation send-off.

## MTK and ProcessBigraphs integration closure

The non-normative research basis for SPV1-034 through SPV1-042 is
[`design/audits/symbolic-potts-v1-mtk-processbigraph-integration-research.md`](../design/audits/symbolic-potts-v1-mtk-processbigraph-integration-research.md).

CI-017 through CI-021 are now consolidated into normative dependency, assimilation, IO,
orchestration, timing, checkpoint, transport-deferral, and acceptance contracts. No architectural
decision from the integration amendment remains open.

The consolidation specification and audit are complete. Production implementation remains
prohibited until the project owner gives explicit implementation send-off.

## Round 4 and interview closure

The non-normative research basis for SPV1-043 through SPV1-049 is
[`design/audits/symbolic-potts-v1-round-4-research.md`](../design/audits/symbolic-potts-v1-round-4-research.md).

CI-022 through CI-026 are consolidated into normative executable, problem, runtime, solution,
checkpoint, public-surface, source-disposition, QA, and supersession contracts. Together with
CI-001 through CI-021, they close the owner interview with no product decision left open.

These clauses are assembled into the implementation-grade consolidation specification and audited
against the repository and surviving scientific authorities. Production implementation remains
prohibited until the project owner gives explicit implementation send-off.
