# Symbolic Potts V1 Autonomous Consolidation Contract

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: superseded in part by the
[Architecture Redirection Contract](symbolic-potts-v1-architecture-redirection.md);
implementation prohibited until explicit owner send-off

## Authority and purpose

This document turns the accepted requirements in
[Symbolic Potts V1](symbolic-potts-v1.md), CI-001 through CI-026 in the
[owner interview](../design/audits/symbolic-potts-v1-consolidation-owner-interview.md), and the
surviving scientific specifications into one autonomous implementation phase.

It governs implementation order, package boundaries, public contracts, compiler passes, source
disposition, tests, and completion. It refines but does not replace the scientific meaning in the
parent V1 specification. If this document and a superseded implementation detail conflict, this
document governs. If it exposes a new product or scientific choice not settled here or in the
parent specification, implementation MUST stop and ask the owner.

This specification is not a migration guide. The branch provides no compatibility period.

The Architecture Redirection Contract governs conflicts involving compiler openness, typed
descriptors, CorePotts state and workspace, stage taxonomy, checkerboard concurrency, relationship
admission, the JuliaGPU portability stack, test authority, implementation order, and phase exit.
In particular, the former closed-to-built-ins lowering, mechanism-shaped program boundary,
sequential-only focal fixture, and mechanism-first internal slices are no longer authoritative.

## Phase result

The phase is complete only when one public flow works end to end:

```julia
sys = PottsSystem(...)
completed = complete(sys)
executable = compile(
    completed;
    engine = SequentialEngine(),
    backend = CPUBackend(),
    scalar_type = Float32,
)
prob = PottsProblem(executable, initial, (0, 1_000); seed = 0x1234)
sol = solve(prob)
```

The same system must be inspectable, substitutable before completion, symbolically indexable,
remakeable after problem construction within the permitted runtime fields, executable by the
qualified sequential or checkerboard engine, checkpointable at a settled MCS, and derivable as a
ProcessBigraphs component when the weak dependency is loaded.

The phase produces no old API wrapper, no legacy oracle, no docs rewrite, and no cross-language
transport.

## ACV1-001 — Exact package topology

The final dependency direction is:

```text
ModelingToolkitBase ─┐
Symbolics ───────────┤
SymbolicIndexingInterface ─┤
DynamicQuantities ──┤
SciMLBase ──────────┼──> PottsToolkit ──> CorePotts
                    │          │
ModelingToolkit ────┘ weak     ├── ProcessBigraphs weak
Unitful ───────────────── weak ┘
```

PottsToolkit strong dependencies:

- CorePotts;
- ModelingToolkitBase;
- Symbolics;
- SymbolicIndexingInterface;
- DynamicQuantities; and
- SciMLBase.

PottsToolkit weak dependencies and extensions:

| Weak dependency | Extension | Sole responsibility |
| --- | --- | --- |
| ModelingToolkit | `PottsToolkitModelingToolkitExt` | supported external-system assimilation and documented full-MTK transformations |
| ProcessBigraphs | `PottsToolkitProcessBigraphsExt` | `process_component(prob)` runtime bridge |
| Unitful | `PottsToolkitUnitfulExt` | boundary conversion to and from canonical DynamicQuantities units |

ModelingToolkitStandardLibrary belongs only in integration tests and examples. OrdinaryDiffEq
algorithm packages belong only where a typed equation solver policy actually requires them; they
are not unconditional PottsToolkit dependencies.

CorePotts MUST remove its ProcessBigraphs dependency and MUST remain free of all symbolic and unit
packages. ProcessBigraphs remains unchanged unless its existing public managed-engine protocol
cannot express one proven required operation; any such change must be minimal and domain-neutral.

## ACV1-002 — Source architecture and ownership

PottsToolkit owns:

- symbolic construction and ModelingToolkit system behavior;
- statement and operation meaning;
- completion, qualified IR, diagnostics, fingerprints, and inspection;
- parameter classification and reference-unit conversion;
- compilation and lowering into one concrete CorePotts program;
- public problem, integrator, solution, saved-state, and checkpoint façades; and
- optional ModelingToolkit, ProcessBigraphs, and Unitful adapters.

CorePotts owns:

- concrete logical state and generations;
- spatial/topology execution data;
- semantic addressed randomness;
- proposal and acceptance machinery;
- sequential and checkerboard execution;
- fields, histories, observations, lifecycle, and deterministic relationship transactions;
- concrete workspaces and backend kernels;
- whole-MCS runtime advance; and
- logical checkpoint data and storage codecs.

No object may have two scheduling owners. No symbolic object, registry, quantity, external system,
source AST, or host closure may cross into `CorePotts.CompiledPottsProgram`.

## ACV1-003 — Target PottsToolkit modules

The implementation SHOULD converge on the following responsibility layout. Filenames may be split
further when necessary, but ownership MUST remain this clear:

```text
src/
  PottsToolkit.jl
  systems.jl
  statements/
    statements.jl
    resources.jl
    processes.jl
    components.jl
    registry.jl
    traversal.jl
  symbolics/
    bindings.jl
    operations.jl
    distributions.jl
    units.jl
  completion/
    qualified_ir.jl
    namespaces.jl
    inference.jl
    schedule.jl
    fingerprints.jl
    diagnostics.jl
    completion.jl
  compiler/
    executable.jl
    parameters.jl
    storage.jl
    lowering.jl
    compiler.jl
  runtime/
    initial_state.jl
    problem.jl
    integrator.jl
    saved_state.jl
    solution.jl
    checkpoint.jl
    symbolic_indexing.jl
  inspection.jl
  precompile.jl
ext/
  PottsToolkitModelingToolkitExt.jl
  PottsToolkitProcessBigraphsExt.jl
  PottsToolkitUnitfulExt.jl
```

The target is one authority per concern, not exact file-count compliance. A file may be renamed,
but old and new authorities MUST NOT coexist at phase exit.

## ACV1-004 — Public model value

`PottsSystem <: ModelingToolkitBase.AbstractSystem` is one immutable public type with private
storage and a private completion payload. Its constructor is:

```julia
@named sys = PottsSystem(
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

All inputs are defensively copied. Construction performs only cheap shape, name, and collection
checks. `iscomplete(sys)` is public. Incomplete transformations return new values. Completed
systems reject composition, extension, flattening, renaming, and structural reconstruction.

The implementation must cover public ModelingToolkitBase behavior for names, hierarchy, unknowns,
parameters, equations, observed equations, defaults, initial conditions, independent variables,
supported events, inputs, outputs, bound/unbound IO, property namespacing, substitution,
composition, explicit flattening, strict extension, and completion state.

`compose` preserves hierarchy. `flatten` is explicit. `extend` merges incomplete systems in one
scope. Duplicate normalized equations, statements, resources, processes, observations, protocols,
events, or conflicting initial conditions are errors. Variables and parameters unify only by
symbolic identity.

## ACV1-005 — Closed semantic vocabulary

The 23 stored statement kinds are exactly those in SPV1-016. There is no generic public tagged
node. High-level components expand immediately into transparent `StatementSet` values and expose
their complete expansion through `statements(component)`.

Every statement has a stable local `StatementID`; fully qualified identity adds the system path.
Processes and mutable resources require explicit names. Deterministic defaults for simple terms
may use only kind and target, never collection position or source order.

Every built-in statement participates in one internal `map_symbolics(f, statement)`-style
reconstruction operation. All namespacing, substitution, and symbolic discovery use that path.
Behavioral rules remain ordinary Julia methods.

The only extension node is `RegisteredStatement`. Its host-side `StatementRegistry` is snapshotted
during completion. Runtime and compilation never consult it.

The closed Potts symbolic-operation and typed-effect vocabularies are exactly those accepted in
CI-012 and SPV1-014 through SPV1-023. New built-in operations require a release-level source
change; mutation and iteration cannot be hidden in a Symbolics call.

## ACV1-006 — Source capture and diagnostics

`@statements` is optional thin sugar. It evaluates normal Julia constructors and adds:

- file;
- line;
- module; and
- displayed originating expression.

It does not parse scientific meaning. Direct constructors use `UnknownSource()` unless an explicit
source is supplied.

Every construction, completion, compilation, preflight, and runtime diagnostic that can identify a
statement MUST report:

- stable diagnostic kind;
- qualified statement or symbolic identity;
- rendered originating model expression;
- namespace path;
- expected and actual contract;
- admitted alternatives when useful; and
- exact source when captured.

Internal indices, concrete kernel types, and raw stack traces are supplementary, never the only
user-facing diagnosis.

## ACV1-007 — Completion pass order

`complete(sys; reference_units, registry)` is immutable and executes these logically ordered
passes:

1. freeze constructor inputs, completion options, and the registry snapshot;
2. expand `StatementSet` components;
3. qualify hierarchy, statements, symbols, equations, events, and references;
4. normalize equations and reject identity conflicts;
5. discover variables, parameters, state, IO, resources, and references;
6. resolve all structural parameter values;
7. validate result types, shapes, dimensions, declared scales, and reference-unit anchors;
8. assimilate supported equation components and validate equation ownership;
9. infer reads, writes, effects, bounded domains, capacities, and lifecycle implications;
10. discover explicit and reserved random operations and freeze stable identities;
11. build the semantic phase DAG and deterministic order;
12. infer engine/backend capability requirements and contextual rejections;
13. produce immutable qualified records and inspection reports; and
14. produce semantic and completed-system fingerprints from versioned canonical serialization.

A safely discoverable error in one record MUST NOT prevent independent records from being checked.
Completion returns all safely independent failures in deterministic diagnostic order.

`complete(completed; identical options...) === completed`; different options on a completed value
are an error. Completion never chooses engine, backend, scalar type, seed, initial layout, runtime
interval, saving, or a compilation cache.

## ACV1-008 — Qualified record invariant

Every qualified statement record contains:

- qualified identity, kind, schema version, source, and provenance;
- normalized Symbolics payload;
- inferred type, shape, units, and reference conversion;
- reads, writes, ownership, persistence, and resource requirements;
- effect class, bound, transaction identity, and lifecycle implications;
- random operations;
- phase and ordering dependencies;
- admitted and rejected engine/backend families with reasons; and
- lowering identity.

Qualified records and reports are immutable. Their canonical serialization is versioned and
independent of Julia object addresses, randomized hash order, source order, and source path.

## ACV1-009 — Compilation pass order

`compile` accepts only a completed system and three mandatory explicit choices:

```julia
compile(completed; engine, backend, scalar_type)
```

It executes these logical passes:

1. validate selected engine/backend/scalar capabilities;
2. classify and lay out structural and runtime parameter values;
3. erase units through the validated reference conversion plan;
4. select concrete scalar, accumulator, index, identifier, and storage representations;
5. plan topology, ownership, fields, histories, relationships, capacities, and generations;
6. lower phases into deterministic sequential or checkerboard schedules;
7. lower accepted-copy, synchronous, lifecycle, and ordered-batch transactions;
8. assign semantic RNG stream and draw-site addresses;
9. lower equation processes and observation kernels;
10. allocate workspace schemas without allocating live run state;
11. build one immutable `CorePotts.CompiledPottsProgram`;
12. compute capability, storage, workspace, kernel, schedule, replay, and checkpoint reports; and
13. compute the executable fingerprint.

The V1 numerical policy is scalar-matched accumulation, accurate math, deterministic reductions,
and checked model bounds. The backend cannot alter it. Compilation may aggregate safely
independent errors.

`PottsExecutable` is immutable, privately laid out, and reusable. No public, global, or disk cache
exists.

## ACV1-010 — CorePotts program boundary

Before deleting the old coupled authority, implementation must extract the concrete mechanisms
needed by one narrow qualified interface centered on:

- `CompiledPottsProgram`;
- runtime initialization from validated concrete state and parameters;
- exactly one whole-MCS advance;
- settled-state and observation access;
- atomic runtime-parameter update at a boundary;
- logical state and checkpoint export/import;
- capability and execution reports; and
- backend extension hooks.

The narrow interface must not expose PottsToolkit authoring concepts. CorePotts may remain directly
usable by compiler/backend developers through qualified functions, but is no longer a broad
scientific authoring surface.

Existing logical state, generations, topology, semantic RNG, proposal/acceptance, sequential and
checkerboard execution, fields, histories, observations, lifecycle, relationship transactions,
checkpoint integrity, and qualified backend mechanisms are extraction inputs. Existing coupled
declarations, semantic-kernel authoring, paper assemblies, ProcessBigraph adapters, Lottery, tiled
execution, old checkpoint readers, and broad exports are deletion targets.

## ACV1-011 — Parameter and initial-state schemas

Completion requires every structural parameter to resolve. Compilation proves parameter roles and
produces:

- an immutable structural manifest included in the executable fingerprint; and
- a runtime `PottsParameters` schema for numerical leaves that cannot change structure,
  scheduling, effects, bounds, units, solver family, or capability.

`p` accepts symbolic pairs or a dictionary and normalizes immediately. Unknown, duplicate,
unresolved, structural, unit-incompatible, type-incompatible, or shape-incompatible entries fail
before a run is created.

`PottsInitialState(; ownership, values=[])` accepts exactly one ownership authority:
`LabelledCells` or `OwnershipLayout`. Initialization is defensively owned and validates label,
cell-kind, medium, shape, capacity, generation, relationship endpoint, and unit contracts.
Procedural placement uses its own addressed initialization stream.

## ACV1-012 — Problem and stochastic contract

The only public constructor is:

```julia
PottsProblem(
    executable,
    initial,
    (t0, t1);
    p = [],
    seed,
    replica = 1,
)
```

The seed is mandatory and normalized to `UInt64`. The replica is positive and bounded. Time is
absolute integer MCS with `0 <= t0 <= t1`; the first advance completes `t0 + 1`.

The problem has no engine, backend, scalar policy, algorithm, capacity, callback, save policy,
cache, or realization closure. Each `init` creates independent mutable runtime storage.

Every random value is addressed by master seed, replica, semantic stream, absolute MCS, operation,
entity, invocation, and draw. Ensemble repeat identity is an additional address component.
Workers, threads, devices, launch shapes, scheduling, and completion order do not participate.

## ACV1-013 — Runtime and saving contract

The relationship is:

```julia
solve(prob; kwargs...) = solve!(init(prob; kwargs...))
```

There is no solve-time algorithm. `init` allocates and validates without advancing. `step!`
advances exactly one complete MCS. The exact defaults and accepted controls are SPV1-046 and
SPV1-053.

Every saved boundary owns an immutable logical `PottsSavedState`; saved entries never alias live
integrator storage. Requested observations must have been declared before compilation. Exact
integer lookup is supported. Dense, fractional, nearest, or implicit interpolation is not.

`remake` changes only initial state, runtime parameters, integer span, seed, or replica. Problem
mutation through SII `setp` is rejected. Integrator `setp` is atomic, validated, boundary-only, and
effective at the next MCS.

`PottsSolution` is a genuine `SciMLBase.AbstractTimeseriesSolution` with meaningful return codes,
statistics, provenance, collection behavior, exact saved-MCS lookup, and symbolic indexing.

## ACV1-014 — Checkpoint and storage contract

`PottsCheckpoint` is captured and restored only at a settled complete-MCS boundary:

```julia
cp = checkpoint(integrator)
restored = init(prob; checkpoint = cp)
```

The schema includes executable identity, authoritative logical state, parameters and history,
seed, replica, continuation counters, completed MCS, schema, replay class, and integrity checksum.
It excludes live kernels, queues, workspaces, Symbolics, units, external systems, registries, and
Julia serialization.

In-memory is authoritative. Optional HDF5 and Zarr codecs encode the same V1 logical schema through
one narrow reader/writer protocol. No old reader, converter, or migration path remains. Exact
continuation and portable logical restore are separate replay claims.

## ACV1-015 — Relationship and checkerboard contract

Relationship changes use bounded typed `Create`, `Remove`, and `Retune` requests. The transaction
must use canonical request identities, deterministic sorting/grouping, declared duplicate and
conflict policy, capacity and maximum-degree validation, generation-safe endpoint validation,
lifecycle validation, and atomic publication.

Sequential execution supports proven relationship behavior. Checkerboard may read relationship
snapshots and may execute end-of-MCS ordered batches. Accepted-copy relationship mutation is
checkerboard-admitted only when the compiler proves the entire touched set and deterministic
conflict selection. There is no fallback to sequential. The initial focal-point-plasticity fixture
therefore targets sequential execution.

## ACV1-016 — ModelingToolkit and ProcessBigraphs integration

`EquationComponent` returns an incomplete homogeneous `PottsSystem`. It uses public ModelingToolkit
accessors, preserves supported identity and metadata, adds one explicit `EquationProcess`, and
rejects unsupported semantics contextually. It never stores an external integrator or silently
transforms the input.

`process_component(prob)` derives its interface and managed-engine adapter from the executable and
problem. One invocation advances exactly one MCS with frozen inputs and atomic output publication.
Global path binding remains ProcessBigraphs composition work. A component cannot be both
assimilated and independently scheduled.

Cross-language transport remains deferred. The manifest must preserve enough typed, unitful,
timed, checkpoint, and failure information to support it later without putting Python or Vivarium
dependencies in either Potts package.

## ACV1-017 — Curated public surface

Names used in ordinary model source are exported. Extension and inspection contracts that users
must deliberately opt into are qualified `public` names. Internal compiler and runtime machinery
is private.

At minimum, ordinary source must be able to name the accepted:

- system, executable, problem, integrator, solution, saved-state, checkpoint, and initial-state
  types;
- statement constructors and `StatementSet`;
- symbolic bindings, operation constructors, distributions, effects, phases, cadences, solver
  policies, layouts, and reference-unit policies;
- composition, completion, compilation, inspection, and registry entry points;
- sequential/checkerboard engines and CPU backend;
- `EquationComponent`; and
- `process_component`.

The exact source `export` and `public` blocks are the authority. An API ledger or alias registry is
forbidden. Aqua, ExplicitImports, and a stale-name audit enforce the boundary.

## ACV1-018 — Repository disposition

| Area | Required disposition |
| --- | --- |
| root `Project.toml` | replace dependencies, weak dependencies, extensions, compat, and test extras with ACV1-001 |
| `src/PottsToolkit.jl` | replace broad CorePotts re-export surface with the curated V1 module |
| `src/authoring/**` | replace with the target symbolic/completion/compiler/runtime authorities |
| `src/compatibility.jl` | delete |
| `src/reference_models/**` | delete; scientific assemblies move to visible tests |
| `src/public_api_docs.jl` | delete or replace only with V1 docstrings; no tutorial work |
| `src/precompile.jl` | replace with one small public V1 workload |
| `lib/CorePotts/Project.toml` | remove ProcessBigraphs and obsolete authoring/solver dependencies |
| `lib/CorePotts/src/CorePotts.jl` | reduce includes and exports to the qualified runtime boundary |
| CorePotts algorithms | keep sequential/checkerboard; delete Lottery and tiled |
| CorePotts coupled tree | extract required mechanisms, then delete old semantic authority and paper assemblies |
| CorePotts ProcessBigraph files | delete |
| CorePotts persistence | rewrite around V1 checkpoint; keep qualified HDF5/Zarr codecs if conformance is retained |
| MakiePotts | adapt to V1 saved-state/solution/observation access where required for package coherence |
| ProcessBigraphs | leave unchanged except a proven minimal domain-neutral protocol addition |
| docs/examples/paper | do not rewrite on this branch |

Deletion occurs only after its replacement passes the applicable new tests. Old code is never
invoked as an oracle.

## ACV1-019 — Required test layout and assertions

The phase replaces old tests with ordinary public-contract tests grouped by concern:

```text
test/
  test_system_contract.jl
  test_statements_and_traversal.jl
  test_completion_and_diagnostics.jl
  test_units_and_parameters.jl
  test_compilation_and_inspection.jl
  test_initial_problem_remake.jl
  test_runtime_solution_sii.jl
  test_checkpoint.jl
  test_merks_fixture.jl
  test_wortel_fixture.jl
  test_focal_fixture.jl
integration/
  test_modelingtoolkit_assimilation.jl
  test_modelingtoolkit_standard_library.jl
  test_process_bigraph_bridge.jl
  test_unitful_extension.jl
  test_optional_extension_loading.jl
```

CorePotts separately tests the narrow program interface, both engines, transaction laws,
logical-state invariants, checkpoint codecs, and backend hooks.

Required assertions include:

- constructor defensive ownership and immutable transformations;
- `@named`, hierarchy, namespace property access, flattening, extension, substitution, and
  completion idempotence;
- every statement kind, operation family, effect, source-capture path, and registry rule;
- aggregated deterministic diagnostics;
- unit propagation, ambiguous anchors, explicit overrides, and unit erasure;
- structural/runtime parameter proof and rejection paths;
- stable semantic, completed, and executable fingerprints;
- executable inspection and absence of host semantic objects in the Core program;
- exact solve defaults, saving, return codes, remake, SII reads, integrator-only `setp`, and
  independent `init` state;
- same seed and replica replay, different replica divergence, initialization stream isolation, and
  ensemble addressing;
- relationship duplicate, conflict, capacity, degree, generation, cleanup, and rollback;
- checkerboard capability rejection without fallback;
- mandatory in-memory checkpoint continuation, corruption, mismatch, and replay-class behavior;
- HDF5 and Zarr V1 conformance only when the corresponding optional codec is retained in this
  phase;
- ModelingToolkit and MTSL assimilation plus every excluded semantic family;
- ProcessBigraph schema derivation, whole-MCS publication, time conversion, checkpoint, failure,
  and dual-owner rejection;
- Aqua, ExplicitImports, dependency boundaries, stale names, inference, and warmed allocation;
- Linux package tests, macOS/Windows load plus tiny sequential run; and
- one black-box public model-to-solution path.

The Merks, Wortel, and focal fixtures contain their full public model assembly directly in the
test source. Helpers may create literal arrays or compare observations, but may not construct or
import the model. The scientific mechanism, stochastic problem, initial layout, parameters,
observations, and a bounded end-to-end run are visible. Same-seed replay and different-seed or
replica divergence are mandatory. Paper-scale duration and visualization remain later
documentation/reproduction work, not ordinary PR runtime.

## ACV1-020 — CI policy

The normal required CI consists of:

- PottsToolkit, CorePotts, ProcessBigraphs, and MakiePotts package tests on Julia 1.12;
- one cross-package integration job;
- macOS and Windows package load plus a tiny sequential trajectory;
- ordinary static API/dependency checks inside those tests; and
- optional manual or hardware-specific performance and GPU jobs.

The branch must remove V1-obsolete test invocations but MUST NOT add evidence ledgers, freshness
checks, release qualification, parity oracles, expected-output archives, package-wide mandatory
JET, hard wall-clock gates, per-file coverage, or a coverage ratchet.

Documentation is explicitly out of phase. The current PR documentation workflow will become stale
when the old public API is deleted. It must not be weakened or disabled to make this branch green.
Consequently, the implementation branch cannot be merged under the current documentation-required
policy until a later documentation phase is paired with it or the owner explicitly changes the
merge plan.

## ACV1-021 — Autonomous internal slices

For implementation ordering only, this clause is superseded by G0 through G9 in CCV1-022 of the
[Compiler Construction Contract](symbolic-potts-v1-compiler-construction.md). Its package,
integration, proof-model, clean-break, and ordinary-QA requirements survive.

After explicit owner send-off, one autonomous phase proceeds through these internal slices:

1. package boundary, skeleton `PottsSystem`, identity, traversal, and tests;
2. volume/contact vertical slice through completion, compilation, and sequential solve;
3. complete qualified IR, diagnostics, units, parameters, inspection, and SII;
4. checkerboard lowering and capability analysis;
5. Wortel activity, history, accepted-copy activation, and `AfterMCS` decay;
6. Merks field equation assimilation, chemotaxis, connectivity, and protocol;
7. focal relationships, lifecycle, checkpoint, and deterministic batch transactions;
8. ProcessBigraphs, Unitful, ModelingToolkit, MTSL, and MakiePotts integration;
9. extraction of the narrow CorePotts program authority and complete legacy deletion; and
10. full ordinary QA, static audits, platform smoke, and black-box release-candidate pass.

These are not owner gates, separate phases, or partial completion claims. Work may move between
slices to preserve a coherent vertical implementation.

## ACV1-022 — Autonomous stopping rule

The implementation agent continues without human oversight when:

- the choice is an internal representation consistent with this specification;
- a failing test exposes an implementation defect;
- a public upstream interface has a documented equivalent seam;
- files must move or split within the accepted ownership boundary; or
- extraction order must change to avoid dual authority.

The agent stops and requests owner direction only when:

- two scientifically different behaviors are both consistent with surviving specifications;
- a required public upstream interface is absent and satisfying the contract would require private
  API coupling;
- a package dependency must cross an accepted forbidden boundary;
- checkerboard support would require weakening deterministic conflict semantics;
- a required model mechanism cannot fit the closed statement/effect vocabulary;
- the clean break would require adding compatibility or migration behavior; or
- completion would require implementing docs, cross-language transport, Dagger execution, a third
  engine, or another explicitly deferred product.

An ordinary bug, difficult refactor, long test run, or missing optimization is not a product
blocker.

## ACV1-023 — Phase exit

The phase is implementation-complete only when:

1. every SPV1 and ACV1 requirement has a test or a justified static inspection;
2. no old public authoring, Lottery, tiled, CorePotts ProcessBigraph, checkpoint-reader, or broad
   re-export authority remains;
3. all four packages load and pass their ordinary test suites;
4. integration, macOS, and Windows gates pass;
5. Merks, Wortel, and focal fixtures run stochastically through the public V1 flow;
6. no forbidden dependency, private ModelingToolkit access, symbolic device object, hidden
   compiler cache, or legacy alias remains;
7. `git diff --check`, local-link checks for changed specification files, Aqua, and ExplicitImports
   pass; and
8. a final audit records source disposition, public surface, test evidence, known performance and
   GPU qualification limits, and the still-unresolved documentation merge constraint.

Implementation completion does not authorize merging broken living documentation. It prepares the
V1 code for the explicitly separate documentation phase already requested by the owner.
