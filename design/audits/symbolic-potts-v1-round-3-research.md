# Symbolic Potts V1 Round 3 Research

Date: 2026-07-29; owner interview completed 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: research complete; owner-accepted decisions are normative only through SPV1-014 through
SPV1-033 in `spec/symbolic-potts-v1.md`

## Purpose

Round 3 must freeze the authoring and compiler contracts that were deliberately left open after
the first two owner interviews. This audit studies:

- the current PottsToolkit authoring, lowering, randomness, relationship, and checkerboard code;
- the accepted scientific and execution specifications already in this repository;
- the current public ModelingToolkit, Symbolics, SymbolicIndexingInterface, Catalyst,
  DynamicQuantities, KernelAbstractions, and Atomix contracts; and
- the complete mechanisms required by the Merks 2006 and Wortel 2021 reference models.

The objective is a V1 that is pleasant to author, genuinely native to ModelingToolkit, inspectable
before execution, deterministic where claimed, and capable of lowering to concrete CPU/GPU
execution data without carrying symbolic objects or dynamic registries into kernels.

## Research sources

### Repository evidence

The local audit covered:

- `src/authoring/rule_parts/declarations.jl`;
- `src/authoring/level1_queries.jl`;
- `src/authoring/level1_runtime.jl`;
- `src/authoring/level1_activity.jl`;
- the current model normalization and lowering pipeline;
- dynamic relationship declarations, request generation, request sorting, and portable commit;
- fixed and contact-triggered focal-point-plasticity implementations;
- sequential and checkerboard proposal/commit implementations;
- semantic RNG and deterministic-parallel specifications;
- `src/reference_models/merks_2006.jl`;
- `src/reference_models/wortel_2021.jl`; and
- the Phase 14 semantic-kernel, dynamic-state, coupled-dynamics, and execution specifications.

### Current external contracts

- [ModelingToolkit system API](https://docs.sciml.ai/ModelingToolkit/dev/API/System/)
- [ModelingToolkit composition](https://docs.sciml.ai/ModelingToolkit/dev/basics/Composition/)
- [ModelingToolkit component precompilation](https://docs.sciml.ai/ModelingToolkit/dev/basics/PrecompileComponents/)
- [ModelingToolkit validation](https://docs.sciml.ai/ModelingToolkit/stable/basics/Validation/)
- [Pinned ModelingToolkit `AbstractSystem` implementation](https://github.com/SciML/ModelingToolkit.jl/blob/d39174937fead779b29fa5baa50ba975adbde8c9/lib/ModelingToolkitBase/src/systems/abstractsystem.jl)
- [Symbolics variables and equations](https://docs.sciml.ai/Symbolics/stable/manual/variables/)
- [Symbolics supported types](https://docs.sciml.ai/Symbolics/stable/manual/types/)
- [Symbolics arrays](https://docs.sciml.ai/Symbolics/stable/manual/arrays/)
- [Symbolics function registration](https://docs.sciml.ai/Symbolics/dev/manual/functions/)
- [SymbolicUtils expression interface](https://docs.sciml.ai/SymbolicUtils/stable/manual/interface/)
- [SymbolicUtils metadata API](https://docs.sciml.ai/SymbolicUtils/stable/api/)
- [SymbolicIndexingInterface](https://docs.sciml.ai/SymbolicIndexingInterface/stable/)
- [Catalyst domain-node implementation](https://github.com/SciML/Catalyst.jl/blob/79144ad28f49b594f84965c58be290be51041f6e/src/reaction.jl)
- [Catalyst system implementation](https://github.com/SciML/Catalyst.jl/blob/79144ad28f49b594f84965c58be290be51041f6e/src/reactionsystem.jl)
- [Catalyst DSL](https://github.com/SciML/Catalyst.jl/blob/79144ad28f49b594f84965c58be290be51041f6e/src/dsl.jl)
- [DynamicQuantities](https://ai.damtp.cam.ac.uk/dynamicquantities/stable/)
- [KernelAbstractions Atomix example](https://juliagpu.github.io/KernelAbstractions.jl/stable/examples/atomix/)
- [Atomix](https://juliaconcurrent.github.io/Atomix.jl/dev/)
- [Julia generated-function constraints](https://docs.julialang.org/en/v1/manual/metaprogramming/)

### Scientific sources

- [Merks et al. 2006, “Cell elongation is key to in silico replication of in vitro
  vasculogenesis and subsequent remodeling”](https://pmc.ncbi.nlm.nih.gov/articles/PMC2562951/)
- [Wortel et al. 2021, “Local actin dynamics couple speed and persistence in a cellular Potts
  model of cell migration”](https://pmc.ncbi.nlm.nih.gov/articles/PMC8390880/)
- [Artistoo Act-CPM explorable](https://artistoo.net/explorables/Explorable-ActModel.html)

## Finding 1 — The current expression layer should be replaced, not generalized

The current authoring layer independently implements:

- literals, owner references, property reads, cell/model parameter reads;
- arithmetic, comparison, Boolean, transcendental, conditional, and clamp operations;
- probability distributions and random draws;
- spatial queries;
- recursive variable, draw, and property discovery;
- expression normalization; and
- a second compiled expression hierarchy.

That is already a small symbolic algebra system. Extending it for fields, relationships,
focal-point plasticity, equation coupling, units, substitution, and MTK namespacing would duplicate
more of Symbolics while remaining less interoperable.

**Candidate:** use Symbolics as the only scalar and array expression tree. Potts-specific meaning
should enter that tree through the stable registered-function API and through metadata on symbolic
variables. Potts statements remain first-class domain objects around those expressions.

The implementation must inspect expressions with `iscall`, `operation`, `arguments`, and public
metadata functions. It must not dispatch on the concrete Symbolics/BasicSymbolic term
representation.

The direct low-level Symbolics registration API is explicitly described as advanced and
experimental. V1 should prefer `@register_symbolic` and `@register_array_symbolic`; it should not
construct private `Term` layouts or depend on the current Moshi representation.

## Finding 2 — Catalyst is the correct architectural precedent, not a syntax template

Catalyst establishes four useful precedents:

1. `Reaction` is a first-class immutable domain node rather than a fake equation.
2. `ReactionSystem <: AbstractSystem` stores domain nodes and ordinary equations together.
3. Catalyst implements domain-specific variable discovery, namespacing, flattening, completion,
   and dependency analysis.
4. Completed systems cannot be composed or mutated.

Catalyst's `CatalystEqType` is a closed `Union{Reaction, Equation}`. Its `ReactionSystem` has
explicit vectors for symbolic unknowns, parameters, subsystems, observations, completion state,
and hierarchy needed for later indexing.

The Catalyst DSL also contains substantial AST parsing and inference machinery. Potts V1 has many
more domain statement forms and should not copy that parser. Pretty syntax should be ordinary Julia
constructors plus small declaration macros that delegate variable creation to Symbolics.

**Candidate:** copy the system/domain-node integration pattern, not the reaction-arrow DSL.

## Finding 3 — Completion must be Potts-specific

Current ModelingToolkit completion:

- marks symbolic construction as closed;
- flattens and namespaces hierarchy;
- discovers scoped variables;
- constructs indexing information where appropriate; and
- disables further namespacing on completed systems.

Catalyst overrides completion because generic equation-system completion cannot understand
reactions. Potts requires a stronger override because completion must additionally understand
proposal context, state ownership, stochastic sites, bounded effects, relationship resources, and
phase legality.

**Candidate completion pipeline:**

1. reject already-completed mutation or composition;
2. namespace and flatten Potts subsystems;
3. namespace every symbolic expression inside every statement using one generic statement
   traversal;
4. discover unknowns and parameters from statements and equations;
5. resolve state ownership, category references, relations, fields, and relationship sets;
6. validate units and select the explicit kernel reference-unit system;
7. infer reads, writes, random operations, effect class, touched identities, and effect bounds;
8. validate phase legality and conflicting writers;
9. resolve registered extension schemas by stable identity and version;
10. canonicalize statement order where order is semantically irrelevant and freeze order where it
    is relevant;
11. create symbolic indexing metadata; and
12. compute the semantic and completed-system fingerprints.

Generic MTK completion should not be invoked as if Potts statements were ordinary equations.
Potts completion may reuse public MTK helpers, but it owns this pipeline.

### Interface and load probe

An isolated Julia 1.12 probe installed and precompiled these current releases on 2026-07-29:

- ModelingToolkitBase 1.58.1;
- ModelingToolkit 11.37.1;
- Symbolics 7.34.1;
- SymbolicIndexingInterface 0.3.51;
- DynamicQuantities 1.13.0; and
- SciMLBase 3.39.1.

The first clean environment precompiled 87 newly required packages in 311 seconds. Individual cold
precompile entries included about 42 seconds for Symbolics, 100 seconds for ModelingToolkitBase,
and 79 seconds for ModelingToolkit. These are machine- and cache-specific measurements, not CI
budgets.

Sequential warm imports in fresh Julia processes measured:

| Import set | Elapsed | Maximum resident size |
|:--|--:|--:|
| Symbolics | 1.40 s | 431 MB |
| ModelingToolkitBase | 4.28 s | 733 MB |
| ModelingToolkit | 4.55 s | 791 MB |
| Symbolics + SciMLBase + SII + DynamicQuantities | 1.79 s | 472 MB |
| ModelingToolkitBase + DynamicQuantities | 6.43 s | 795 MB |

`ModelingToolkitBase` currently has more than fifty direct dependencies, including Symbolics,
SymbolicIndexingInterface, SciMLBase, graph packages, callbacks, jumps, and nonlinear-solve
infrastructure. It is a narrower API boundary than full ModelingToolkit, but it is not a
lightweight load boundary in the tested release. DynamicQuantities activates an MTKBase extension
and makes the actual V1 import set close to full-MTK memory cost.

A minimal six-field `AbstractSystem` prototype (`name`, `unknowns`, `ps`, `systems`, `eqs`, and
`complete`) confirmed that public generic accessors provide:

- recursive namespaced `unknowns` and `parameters`;
- `sys.variable` and `sys.subsystem.variable` access; and
- default SymbolicIndexingInterface variable/parameter symbol discovery.

The prototype also exposed a practical constructor contract: generic system renaming uses
reconstruction with a `checks` keyword. The real `PottsSystem` constructor or construction
interface must support this without exposing fields.

**Dependency candidate:** PottsToolkit should directly depend on ModelingToolkitBase, Symbolics,
SymbolicIndexingInterface, DynamicQuantities, and SciMLBase where their APIs are directly extended.
Full ModelingToolkit should be an integration/test dependency unless implementation proves that a
full-MTK transformation is required in core. The runtime-oriented CorePotts layer should remain
free of MTK/Symbolics. This does not make symbolic Potts lightweight; it keeps the dependency
authority honest and prevents accidental use of full-MTK internals.

## Finding 4 — Expression and statement layers need different extension policies

### Expression layer

The expression grammar should be deliberately small:

- Symbolics variables, parameters, arrays, literals, and indexing;
- standard pure Julia/Symbolics arithmetic, comparison, Boolean, conditional, and mathematical
  operations;
- registered Potts read/query functions; and
- registered stochastic draw operations.

Candidate built-in Potts expression operations include:

- proposal context: source site, target site, source owner, target owner, pre-copy value, and
  proposed value;
- cell/site/medium identity and kind;
- cell measures: area/volume, surface/perimeter, centroid, moment, length, polarity, and property;
- field sample and gradient;
- bounded neighborhood reductions;
- contact and boundary measures;
- relationship membership, degree, incident-edge reduction, endpoint, and edge payload;
- accepted-copy predicates; and
- explicitly named stochastic draws.

Only reads and pure calculations belong in expressions. Mutation, allocation, relationship
insertion, lifecycle changes, and scheduling do not.

### Statement layer

An open `Vector{AbstractPottsStatement}` would make extension easy but would leave arbitrary
unvalidated objects in the canonical system. A giant closed union would make third-party
scientific components impossible without PottsToolkit releases.

**Candidate:** a sealed set of built-in statement types plus one `RegisteredStatement` extension
node. The extension node contains:

- stable schema identity and semantic version;
- symbolic arguments;
- serializable literal options;
- provenance and source location; and
- no executable closure.

At completion, a registered schema must provide:

- accepted argument and result types;
- unit constraints;
- namespace traversal;
- read/write/effect inference;
- RNG and boundedness inference;
- phase and engine capabilities;
- reference semantics;
- canonical serialization; and
- lowering into the qualified built-in IR.

The registry is a host-side construction facility. Completion resolves and freezes it. Kernels
must never perform registry lookup or dynamic dispatch.

This design keeps third-party composition possible without admitting arbitrary CorePotts objects
or host callables into the model.

## Finding 5 — Candidate first-class statement families

The smallest closed family that covers the current scientific corpus is:

1. **Kind declarations** — cell kinds and medium/material kinds.
2. **Domain and relation declarations** — lattice, boundary, spacing, proposal/contact/surface/
   connectivity/query relations.
3. **State declarations** — site, cell, medium, model, field, history, and relationship state with
   storage, initialization, ownership, lifecycle, persistence, and units.
4. **Proposal terms** — energy, drive, hard constraint, and proposal modifier.
5. **Synchronous processes** — bounded assignments from one immutable phase snapshot.
6. **Accepted-copy processes** — bounded effects committed atomically with an accepted copy.
7. **Relationship processes** — bounded create/remove/retune requests.
8. **Lifecycle processes** — transition, division, death, inheritance, cleanup, and capacity
   requests.
9. **Equation processes** — scheduling and solver policy for ordinary symbolic equations owned by
   the system.
10. **Observations** — symbolic or registered reductions with an explicit cadence and transfer
    policy.
11. **Protocol statements** — phase DAG, stage transitions, subcycling, and termination.
12. **Registered extension statements** — the only third-party statement escape hatch.

High-level scientific components such as `Volume`, `Elongation`, `ContactEnergy`, `Chemotaxis`,
`ActEnergy`, and `LocalConnectivity` should construct one or more of these statements. They must
remain inspectable expansions, not hidden runtimes.

## Finding 6 — Effect classes should determine engine capability

The current semantic specifications already distinguish read-only, synchronous, accepted-copy,
ordered, and relationship/lifecycle behavior. V1 should make these compiler-visible.

Candidate effect classes:

| Effect class | Snapshot | Commit | Typical use |
|:--|:--|:--|:--|
| `PureRead` | declared phase snapshot | none | energy, constraint, observation input |
| `SynchronousAssign` | common immutable phase snapshot | simultaneous bounded publish | property/field/rule update |
| `AcceptedCopyEffect` | proposal snapshot plus staged copy | atomic with accepted copy | Act refresh, local copy-coupled state |
| `OrderedBatchEffect` | declared snapshot | canonical request order | relationship and lifecycle requests |

Every effect also needs a statically known or completion-proven bound. “Sequential” is an engine
capability, not a fifth semantic effect class. An unbounded host callback is not a portable V1
statement.

The compiler should derive capabilities from the effect and access summaries. Syntax must not fork
into “sequential model” and “checkerboard model” variants.

## Finding 7 — Deterministic relationship mutation requires an effect language

The repository currently has two relationship mechanisms:

- general dynamic relationship policies emit create/remove/retune requests, sort them by canonical
  priority and identity, and apply them deterministically; and
- contact-triggered focal links use a private accepted-copy transaction around an ordered copy.

The portable GPU relationship commit currently applies a sorted batch in one device lane. This is
deterministic and scientifically clear, but not a parallel graph-mutation algorithm. Atomics alone
cannot make multi-object graph insertion, capacity allocation, duplicate suppression, degree
limits, and conflict policy deterministic.

**Candidate relationship effect language:**

- `Create(set, endpoint_a, endpoint_b; payload, priority)`;
- `Remove(set, edge_or_endpoints; priority)`;
- `Retune(set, edge_or_endpoints; payload, priority)`; and
- statically bounded `foreach` domains over contacts or incident edges.

Arbitrary mutation of adjacency lists is forbidden. A relationship process emits effect records.
The runtime:

1. emits bounded requests in parallel;
2. assigns canonical semantic identities;
3. deterministically sorts or groups requests;
4. rejects duplicate/conflicting requests by the declared policy;
5. reserves capacity and validates degree/lifecycle constraints;
6. applies the canonical transaction; and
7. publishes only a validated state.

The first correct GPU implementation may retain a serialized final apply after parallel
emit/sort/scan. Later parallel commit is an optimization only if it is proven equivalent.

### Checkerboard consequence

Checkerboard can safely read an immutable relationship snapshot. It can perform an
`AcceptedCopyEffect` only when completion proves a bounded touched set and the conflict compiler
includes all affected cells, edges, slots, and state identities. General relationship creation,
breaking, retuning, and lifecycle cleanup should initially be an end-of-MCS `OrderedBatchEffect`.

Contact-triggered focal links are therefore not automatically checkerboard-compatible merely
because their payload is isbits. They require compiler-derived relationship conflicts and bounded
transaction staging. Until that proof exists, the completed model remains valid but checkerboard
preflight rejects that effect.

## Finding 8 — Phase names should describe semantics, not kernel launches

The model should not expose workgroup, tile, color, launch, or backend phases.

Candidate semantic phase vocabulary:

- `Proposal` — pure proposal reads and energy/constraint/drive evaluation;
- `AcceptedCopy` — effects atomic with one accepted copy;
- `AfterSweep` — synchronous work after one declared MCS/sweep;
- `RelationshipCommit` — canonical relationship request commit;
- `Lifecycle` — lifecycle requests and cleanup;
- `EquationStep` — one declared equation-solver/subcycle position;
- `Observe` — read-only observation; and
- named protocol/stage boundaries.

User-defined named phases form a DAG around these anchors. A phase has one immutable input snapshot
and one commit mode. A phase cannot mix synchronous assignments and ordered mutations merely
because they appear next to each other in source.

Checkerboard colors and sequential attempts are compiler schedule details below these semantics.

## Finding 9 — Stochastic draws need semantic identity without becoming state

The Wortel and Merks models are stochastic because CPM proposal selection and Metropolis acceptance
are stochastic even when their biological components contain no explicit `draw`.

V1 must represent:

- model-level random operations such as proposal selection, acceptance, stochastic rule draws, and
  randomized protocol choices;
- a stable user-visible identity for every explicit draw;
- distribution arguments as symbolic expressions;
- a compiler-assigned stream and draw-site address; and
- problem-level seed and replica identity.

**Candidate syntax:** registered draw functions take a mandatory `DrawKey` literal:

```julia
ξ = draw(Normal(0, σ), DrawKey(:polarity_noise))
```

The registered function is a declarative symbolic operation. It is never evaluated during
construction or simplification. Completion rejects duplicate keys within one namespace, validates
distribution parameters and result units, and records the semantic draw. Compilation assigns the
stream/address. The problem supplies the seed.

The built-in CPM proposal and acceptance draws have reserved semantic keys and appear in
`inspect(sys, RandomOperations())` even though the user does not spell them in each model.

An alternative declaration-style `@draw` may be considered only if the registered-function form
cannot preserve literal draw identity through Symbolics using public APIs.

## Finding 10 — Ordinary equations should be native but explicitly scheduled

A `PottsSystem` should accept ordinary symbolic equations directly. Their mathematical meaning
belongs to MTK/Symbolics; their coupling to CPM state and their position in the simulation protocol
belong to Potts statements.

**Candidate:**

- equations live in the ordinary equation vector;
- a state declaration establishes ownership and spatial storage;
- an `EquationProcess` references equations/unknowns, solver family, cadence, and phase;
- completion validates coupling, units, and write ownership;
- compilation lowers a supported equation subset to a native field/cell process or constructs a
  SciML subproblem with a typed exchange boundary; and
- ProcessBigraphs owns genuinely heterogeneous or independently scheduled external simulators.

Potts hierarchy should initially be homogeneous, like Catalyst hierarchy: `PottsSystem` subsystems
inside `PottsSystem`. An external completed MTK system should not be stored as an opaque Potts
subsystem. Its equations may enter through an explicit equation-component adapter whose result is
fully visible to completion.

## Finding 11 — Three fingerprints are justified

One fingerprint cannot simultaneously answer “same science?”, “same closed symbolic program?”, and
“same executable?”

Candidate identities:

1. **Semantic fingerprint** — normalized declarations, statements, equations, units, protocol,
   stochastic operation identities, and scientific provenance; independent of hierarchy spelling,
   backend, precision, engine, seed, and initial values unless an initial value is itself part of
   the model.
2. **Completed-system fingerprint** — semantic fingerprint plus resolved namespaces, selected
   reference units, registered schema versions, inferred access/effect summaries, and completion
   format version.
3. **Executable fingerprint** — completed fingerprint plus compiler/lowering version, engine,
   backend, scalar policy, storage plan, algorithm identity, and qualified capability profile.

Seed, replica, runtime interval, save schedule, and replaceable parameter/initial values belong to a
problem/run identity, not the executable fingerprint.

## Finding 12 — Qualified IR must be a public inspection product

The compiler's output should not be a dump of internal structs. V1 needs a stable inspection model:

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

Every qualified statement should report:

- fully qualified identity and source location;
- normalized expression;
- units and reference-unit conversion;
- reads and writes;
- effect class and bound;
- RNG sites;
- semantic phase and ordering;
- admitted/rejected engines and reasons;
- lowering target; and
- provenance.

Diagnostics should name the model statement and source expression, not an internal component index.

## Merks syntax stress test

The following is a design probe, not accepted API. It intentionally displays the complete model
assembly rather than importing a reference-model constructor.

```julia
using PottsToolkit
using ModelingToolkit
using DynamicQuantities

@independent_variables t
@parameters begin
    A₀ = 100.0
    L₀ = 50.0
    λA = 50.0
    λL = 5.0
    μ  = 1000.0
    D  = 0.1
    α  = 1.8e-4
    ε  = 1.8e-4
    T  = 50.0
end
@celltypes endothelial
@media extracellular border
@variables c(t)[x, y]

domain = Lattice(
    (500, 500);
    spacing = (2.0u"μm", 2.0u"μm"),
    boundary = FrozenBorder(border),
    relations = (
        proposal = Moore(1),
        contact = Moore(1),
        surface = Moore(1),
        connectivity = Moore(1),
        query = Moore(1),
    ),
)

field = FieldState(
    c;
    domain,
    placement = CellCentered(),
    boundary = Periodic(),
    interpolation = Nearest(),
    initial = 0.0,
)

mechanics = [
    Volume(endothelial; target = A₀, strength = λA),
    Elongation(endothelial; target = L₀, strength = λL),
    ContactEnergy([
        endothelial  ↔ endothelial   => 40.0,
        endothelial  ↔ extracellular => 20.0,
        endothelial  ↔ border        => 100.0,
        extracellular ↔ extracellular => 0.0,
        extracellular ↔ border        => 0.0,
        border        ↔ border         => 0.0,
    ]),
    Chemotaxis(
        endothelial,
        c;
        strength = μ,
        mode = ExtensionsOnly(),
        sample = Nearest(),
    ),
    LocalConnectivity(endothelial),
]

field_equations = [
    Dt(c) ~ D * laplacian(c) - ε * c + α * occupies(endothelial),
]

protocol = Protocol(
    EquationStep(
        :chemoattractant,
        field_equations;
        solver = ExplicitDiffusion(),
        substeps = 15,
        phase = Before(Proposal()),
    ),
    Sweep(:cpm; attempts = AttemptsPerSite(1)),
    Observe(:morphometry; every = 1),
)

@named merks = PottsSystem(
    [domain, endothelial, extracellular, border, field, mechanics..., protocol],
    field_equations,
    [c],
    [A₀, L₀, λA, λL, μ, D, α, ε, T],
)

problem = PottsProblem(
    complete(merks),
    MerksInitialLayout(cells = 282, central_extent = 333),
    (0, 10_000);
    engine = Sequential(),
    temperature = T,
    seed = 2006,
)
```

The final API should not retain `MerksInitialLayout`; the tutorial must display its initial-layout
construction too. It is left as a marker here because Round 3 is about the symbolic system, not a
layout DSL. The final acceptance fixture must expand that marker.

This probe covers the paper's area constraint, elongation constraint, contact energies, local
connectivity, autocrine secretion, diffusion/decay, chemotaxis, proposal algorithm, temperature,
and operator splitting.

## Wortel syntax stress test

This probe makes Act state and its transaction order visible instead of hiding them in an imported
`Act` model.

```julia
using PottsToolkit
using ModelingToolkit

@independent_variables t
@parameters begin
    A₀ = 64.0
    λA = 1.0
    M  = 10.0
    λact = 20.0
    T = 20.0
end
@celltypes endothelial
@media extracellular
@variables activity(t)[x, y]

domain = Lattice(
    (128, 128);
    boundary = Periodic(),
    relations = (
        proposal = Moore(1),
        contact = Moore(1),
        surface = Moore(1),
        query = Moore(1),
    ),
)

act = [
    SiteState(
        activity;
        owner = endothelial,
        initial = 0.0,
        lifecycle = ClearOnOwnershipChange(),
    ),
    ActEnergy(
        endothelial,
        activity;
        maximum = M,
        strength = λact,
        reduction = GeometricMean(Moore(1)),
    ),
    AcceptedCopy(
        :activate_protrusion,
        activity[target_site] ~ M;
        when = extension(endothelial),
    ),
    Synchronous(
        :decay_activity,
        activity ~ max(activity - 1, 0);
        phase = AfterSweep(),
    ),
]

@named wortel = PottsSystem(
    [
        domain,
        endothelial,
        extracellular,
        Volume(endothelial; target = A₀, strength = λA),
        ContactEnergy([
            extracellular ↔ endothelial => 6.0,
            endothelial   ↔ endothelial => 2.0,
        ]),
        act...,
        LocalConnectivity(endothelial),
        Protocol(
            Sweep(:cpm; attempts = AttemptsPerSite(1)),
            Observe(:trajectory; every = 1),
        ),
    ],
    [],
    [activity],
    [A₀, λA, M, λact, T],
)

problem = PottsProblem(
    complete(wortel),
    GridLayout(cell_squares = (side = 8, gap = 2)),
    (0, 500);
    engine = Sequential(),
    temperature = T,
    seed = 0x7068617365313401,
)
```

This form exposes:

- site-owned activity state;
- geometric-mean neighborhood semantics;
- the activity energy contribution;
- accepted-protrusion refresh;
- rejected/no-op non-effects;
- after-sweep decay;
- stochastic proposal and Metropolis acceptance; and
- observation cadence.

## Focal-point-plasticity syntax stress test

This probe tests the relationship language directly.

```julia
@relationships focal_links begin
    endpoints = Undirected(endothelial, endothelial)
    capacity = max_links
    maximum_degree = max_degree
    payload = (
        strength = λf,
        target = Lf,
        maximum = Lbreak,
    )
    lifecycle = RemoveWithEndpoint()
end

focal = [
    RelationshipEnergy(
        :focal_spring,
        focal_links,
        edge.strength *
        (distance(unwrapped_center(edge.a), unwrapped_center(edge.b)) -
         edge.target)^2,
    ),
    RelationshipConstraint(
        :fixed_endpoint,
        focal_links,
        FixedFocalEndpoint(),
    ),
    AcceptedCopy(
        :create_contact_link,
        Create(
            focal_links,
            source_cell,
            target_cell;
            payload = (strength = λf, target = Lf, maximum = Lbreak),
        );
        when = new_contact(source_cell, target_cell) &
               !linked(focal_links, source_cell, target_cell),
    ),
    RelationshipProcess(
        :break_long_links,
        Remove(focal_links, edge);
        foreach = edges(focal_links),
        when = distance(unwrapped_center(edge.a), unwrapped_center(edge.b)) >
               edge.maximum,
        phase = RelationshipCommit(),
    ),
]
```

The exact surface spelling is open. The semantic requirements are not: create/remove/retune are
typed bounded effects, edge iteration is declared, distance uses unwrapped centers and the
accepted minimum-image rule, lifecycle is generation-safe, and engine capability is inferred.

## Principal risks

### Symbolics API churn

Risk: dependence on concrete term types or the experimental direct registration API.

Control: only public wrappers, traversal functions, metadata functions, and registration macros;
pin compat; add an integration canary against the supported MTK/Symbolics range.

### Authoring-time type instability

Risk: heterogeneous statement collections increase construction or precompilation cost.

Control: benchmark construction and precompilation before dependency freeze; use a sealed built-in
union plus one extension node if it materially helps; ensure the compiled IR is fully concrete.
Do not move complexity into generated functions merely to make the authoring vector concrete.

### Overloaded component names hide semantics

Risk: attractive constructors recreate opaque “magic components.”

Control: every component must expand through `inspect`; tutorials for reference models show all
stateful effects and protocol positions; one-line convenience forms cannot be the only
specification of paper models.

### Equation/runtime ambiguity

Risk: an equation is mathematically clear but says nothing about discretization, solver, cadence,
or exchange order.

Control: equations remain equations; `EquationProcess` supplies explicit execution semantics.

### Checkerboard overclaim

Risk: accepting a symbolic model is mistaken for qualifying every engine.

Control: completion validates semantic legality; compilation/preflight validates an exact engine
and backend. Rejections contain the effect and unresolved conflict bound.

### Extension-registry nondeterminism

Risk: mutable global registration changes completed meaning.

Control: stable identity/version, duplicate-registration rejection, registry snapshot at
completion, schema digest in the completed fingerprint, and no registry access after lowering.

### DSL scope creep

Risk: a Catalyst-scale parser emerges before the system semantics stabilize.

Control: ordinary constructors first; declaration macros only where they delegate to Symbolics or
remove repetitive binding boilerplate; no macro-owned hidden scheduling.

## Recommended Round 3 decisions

The next owner interview should accept, amend, or reject these decisions in order:

1. Symbolics is the sole scalar/array expression IR; no replacement custom algebra.
2. Potts uses first-class typed statements plus equations, following Catalyst's architecture.
3. The twelve statement families in this audit are the V1 closed built-in surface.
4. Extensions use one versioned registered statement node and must lower to qualified built-in IR.
5. The four effect classes and boundedness rule govern semantic legality.
6. Relationship mutation uses only bounded create/remove/retune effects and canonical batch commit.
7. The semantic phase anchors in this audit replace engine-specific scheduling names.
8. Explicit draws use mandatory stable keys; built-in CPM randomness is inspectable.
9. Equations are native, but `EquationProcess` owns solver/cadence/order.
10. Potts hierarchy is homogeneous; ProcessBigraphs owns heterogeneous runtime composition.
11. The three-fingerprint split is accepted.
12. The qualified inspection API is a V1 public product.
13. The Merks, Wortel, and focal-point-plasticity probes are the syntax acceptance fixtures.
14. The measured dependency candidate is MTKBase + Symbolics + SII + DynamicQuantities + SciMLBase
    in PottsToolkit, full MTK as integration/test dependency, and no symbolic stack in CorePotts.

## Questions that research cannot decide

These require owner product judgment:

- whether the canonical category declaration spelling is `@celltypes`/`@media` or constructors;
- whether `PottsSystem` exposes one compact constructor or a keyword-heavy constructor;
- whether high-level components may be canonical in tutorials when their expansion is printed
  immediately below them;
- whether explicit `AcceptedCopy` and activity decay are preferred over a compact but inspectable
  `Act` component;
- whether `AfterSweep` or `AfterMCS` is the preferred public term;
- whether `↔` is acceptable canonical pair-law syntax or merely display sugar;
- whether equation solver/discretization policy belongs directly in `EquationProcess` or in a
  reusable named solver component;
- whether the first checkerboard release must support accepted-copy relationship effects or may
  reject them while retaining end-of-MCS relationship batches; and
- how much of the complete initial-layout construction must be part of the symbolic system versus
  the `PottsProblem`.
