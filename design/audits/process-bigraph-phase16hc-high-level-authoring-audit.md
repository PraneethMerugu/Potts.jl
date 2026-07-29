# ProcessBigraphs Phase 16.HC high-level authoring audit

Status: qualified implementation; independent Phase 16.C hardware evidence remains open

Date: 2026-07-28

## Outcome

Phase 16.HC replaces direct canonical-IR construction as the ordinary scientific authoring path.
The primary surface is ordinary Julia: `compose` creates a temporary transactional builder,
builder operations return typed handles, and successful finalization returns an immutable
`CompositeModel`. The model lowers deterministically to the existing canonical ProcessBigraph
ACSet and compiles to the existing `ExecutionPlan`.

This is an authoring layer, not another runtime. ProcessBigraphs still owns logical time,
invocation reason, visibility, validation, publication, failure, checkpoint, and replay. Solver
and CPM implementations still own algorithms, internal steps, workspaces, arrays, device buffers,
and kernels within an authorized invocation.

## Consolidated module boundary

The initial implementation grew to 1,950 lines in one `authoring.jl`. Qualification splits that
file into a small include facade and cohesive modules:

- `model.jl` owns immutable semantic records, handles, schedules, diagnostics, and display;
- `builder.jl` owns the temporary transaction and its authoring verbs;
- `validation.jl` owns finalization, diagnostic accumulation, and semantic identity;
- `lowering.jl` owns canonical lowering, complete author-origin mapping, and plan compilation;
- `inspection.jl` owns `describe` and `explain`;
- `serialization.jl` owns the versioned semantic archive protocol;
- `problem.jl` owns run binding, typed interventions, parameter rebinding, and problem identity;
  and
- `structure.jl` owns typed structural request constructors.

The facade is intentionally small. The largest remaining module groups one coherent lifecycle
stage; splitting individual builder verbs or individual semantic record types further would add
navigation overhead without creating a clearer authority boundary.

## Authoring semantics

Qualified behavior includes:

- explicit semantic names and owner-bound typed handles;
- named store junctions through `connect!` and exact-name bulk attachment through `attach!`;
- lexical hierarchy, private mounted internals, repeated definitions, and explicit exports;
- `Every`, exact one-shot `At`, changed-store `On`, dependency `After`, and bounded iteration;
- declared structural templates and typed spawn/divide/remove/move requests;
- typed parameters, observables, initial conditions, state interventions, time span, and seed in
  `SimulationProblem`;
- structured diagnostics with stable codes, author locations, related objects, expected/actual
  contracts, and suggestions;
- layered semantic, IR, plan, problem, and checkpoint identities;
- complete canonical-entity-to-author-origin coverage through the compiled plan; and
- versioned semantic archives with caller-owned component codecs and exact component-contract
  verification.

`At` uses an exact inactive-after-fire clock rather than a fabricated large cadence. Multiple
times expand to deterministic generated occurrences with retained author origins. A state
intervention is lowered to an ordinary one-shot process, so it uses normal reconciliation,
atomic publication, checkpoint, and replay rather than an out-of-band mutation path.

`On(store)` means changed committed input and is qualified. `On(component)` is rejected with a
specific diagnostic because a canonical step dependency is not an event subscription. Models
that require component events expose a typed event store and use `On(store)`. This keeps event
semantics explicit without inventing a second event bus.

## Migration and compatibility

The Merks and CNV assemblies now use `compose`, stores, mounted components, schedules, and typed
connections. Ordinary ProcessBigraphs behavioral fixtures use the same semantic API. Remaining
direct `StaticComposite`, declaration, and binding construction is confined to lowering,
canonical conformance, frozen differential oracles, compatibility tests, and the explicit
authoring performance oracle.

The static raw-IR guard scans ProcessBigraphs, CorePotts, repository tests, integration code, and
benchmarks against a path-and-purpose allowlist. A shipped scientific model that again requires
direct IR is treated as an authoring defect.

Existing Phase 15 composition functions remain available for expert/open-composition compatibility.
The new API does not redefine qualified runtime behavior, solver selection, or kernel ownership.
SciMLBase and CommonSolve remain optional weak-dependency extension triggers, and the core package
does not depend on CorePotts, ModelingToolkit, OrdinaryDiffEq, Metal, AMDGPU, or another concrete
solver.

## Qualification

The clean ProcessBigraphs package suite passes:

- 375 PB0 assertions, including the semantic builder and executable documentation example;
- 440 retained Phase 15.C assertions;
- 392 retained Phase 16 assertions; and
- 9 Aqua assertions.

The clean CorePotts suite passes 3,863 assertions, including the migrated Merks, CNV, native field,
real SciML, custom adapter, restart, rollback, and failure fixtures.

The stage-separated authoring benchmark uses a 128-event paired semantic/direct-IR fixture over
nine repetitions. Both paths have identical model, structural, and execution-plan identities.
The measured semantic/direct warm-runtime ratio is 1.0172 and both paths allocate 18,850,080
bytes. Construction, validation, lowering, compilation, initialization, runtime, and allocation
budgets all pass. These are conservative workload-specific regression limits, not a
fastest-runtime claim.

The executable documentation example defines an open-protocol component, builds and validates a
model, inspects lowering and plan identity, binds a problem, and executes it. CI runs it directly
in addition to package tests.

## Honest limitations

Phase 16.HC does not claim:

- a mandatory or complete macro language;
- inferred scientific connections, schedules, units, or conversions;
- general component-event subscription without an explicit typed event store;
- arbitrary closure or live-solver-session serialization;
- graphical authoring or ModelingToolkit symbolic composition;
- a universal implicit co-simulation engine;
- full Merks or CNV publication analysis;
- GPU qualification for the bounded Merks or CNV assemblies; or
- public 1.x API stability.

The independent Phase 16.C real Metal and ROCm rows remain open. Phase 16.I may reconcile the
internal beta only after exact-head trusted-hardware evidence closes those rows.
