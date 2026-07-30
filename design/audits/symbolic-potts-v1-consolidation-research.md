# Symbolic Potts V1 Consolidation Research

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: non-normative research complete; this document informs, but does not authorize, the
implementation-grade consolidation specification

## Purpose

The owner-accepted Symbolic Potts V1 decisions define the product. They do not yet define a safe
repository transformation. This audit determines what an autonomous clean-break implementation
would need to:

- make `PottsSystem` the only symbolic Potts model authority;
- use public ModelingToolkit, Symbolics, SymbolicIndexingInterface, and DynamicQuantities
  contracts;
- retain the scientifically valuable CorePotts execution mechanisms without retaining a second
  modeling language;
- support exactly the sequential and deterministic-checkerboard engines;
- move ProcessBigraphs integration behind the correct optional boundary;
- remove the old authoring surface rather than maintain two systems;
- keep complete Merks, Wortel, and focal-link models as visible test fixtures;
- reduce the public API and dependency surface to an intentional package interface; and
- qualify the result with ordinary, maintainable Julia package checks.

This is a codebase-quality and implementation-risk audit. It does not reopen the scientific or
product decisions accepted as SPV1-001 through SPV1-033.

## Research method and sources

### Repository inspection

The audit traced:

- all root-package source files, imports, exports, precompile workloads, and tests;
- the complete `src/authoring` and `src/reference_models` trees;
- the CorePotts package entry point, public surface, algorithms, coupled runtime, persistence,
  ProcessBigraphs adapters, and tests;
- the ProcessBigraphs dependency direction, extensions, public surface, and tests;
- the living CI, documentation, GPU, and benchmark workflows;
- the accepted symbolic V1 decisions;
- the previously accepted authoring, SciML, consolidation, architecture, metaprogramming, and open
  protocol documents; and
- the current Merks, Wortel, activity, relationship, field, observation, and paper-specific
  implementations.

Searches covered semantic type duplication, include direction, package imports, generated
functions, static branches, underscore-prefixed dependency access, manual namespace dispatch,
registry behavior, and test ownership.

### Upstream implementation comparison

The audit inspected pinned upstream source rather than inferring architecture from tutorials:

- [Catalyst at `79144ad`](https://github.com/SciML/Catalyst.jl/tree/79144ad28f49b594f84965c58be290be51041f6e)
  from 2026-07-29;
- [ModelingToolkit at `d391749`](https://github.com/SciML/ModelingToolkit.jl/tree/d39174937fead779b29fa5baa50ba975adbde8c9)
  from 2026-07-30; and
- the `ModelingToolkitBase` implementation in that ModelingToolkit revision.

The comparison included system storage, public accessors, composition, extension, completion,
conversion, unit validation, serialization guards, package exports, file organization, test
organization, and QA environments.

### Public contracts

- [ModelingToolkit system API](https://docs.sciml.ai/ModelingToolkit/dev/API/System/)
- [ModelingToolkit composition](https://docs.sciml.ai/ModelingToolkit/dev/basics/Composition/)
- [ModelingToolkit validation](https://docs.sciml.ai/ModelingToolkit/stable/basics/Validation/)
- [Symbolics function registration](https://docs.sciml.ai/Symbolics/dev/manual/functions/)
- [Symbolics array variables](https://docs.sciml.ai/Symbolics/stable/manual/arrays/)
- [SymbolicIndexingInterface API](https://docs.sciml.ai/SymbolicIndexingInterface/stable/api/)
- [DynamicQuantities symbolic units](https://ai.damtp.cam.ac.uk/dynamicquantities/stable/)
- [Julia module and `public` semantics](https://docs.julialang.org/en/v1/manual/modules/)
- [Julia package extensions and weak dependencies](https://pkgdocs.julialang.org/dev/toml-files/)
- [Julia performance guidance](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [SciMLStyle](https://docs.sciml.ai/SciMLStyle/)
- [Aqua](https://juliatesting.github.io/Aqua.jl/stable/)
- [JET optimization analysis](https://aviatesk.github.io/JET.jl/stable/optanalysis/)
- [ExplicitImports](https://juliatesting.github.io/ExplicitImports.jl/stable/api/)
- [PrecompileTools](https://julialang.github.io/PrecompileTools.jl/stable/)

## Executive conclusion

The accepted V1 is implementable and can reach Catalyst-class codebase quality, but only if the
consolidation is a replacement of semantic authorities rather than another layer over the current
ones.

The current repository already contains most of the difficult low-level mechanisms: logical Potts
state, proposal and acceptance machinery, semantic RNG, deterministic relationship requests,
capacity and lifecycle validation, portable final transaction application, native fields,
observations, and sequential/checkerboard execution. The main codebase problem is not an absence of
mechanisms. It is that scientific meaning is currently represented in several independent layers:

1. root `AbstractRuleExpression`, Level 1 declarations, components, fragments, `PottsModel`,
   normalization, and lowering;
2. CorePotts `SemanticModel`, `StateSpec`, `ProcessSpec`, schedules, continuous-system declarations,
   and paper-specific assemblies; and
3. CorePotts execution-facing `PottsModel`, concrete components, and runtime protocols.

V1 should replace the first two authorities with:

```text
PottsSystem + typed Potts statements + Symbolics expressions
    -> Potts completion data
    -> qualified concrete IR
    -> PottsExecutable
    -> CorePotts runtime mechanisms
```

The third layer should be narrowed and renamed, not discarded.

The highest implementation risks are specification conflicts, unit-scale correctness, generic
symbolic traversal, strict composition semantics, extension-registry reproducibility, and cleanly
extracting runtime mechanisms from the CorePotts coupled DSL. None requires a new execution engine
or a speculative compiler framework.

## Current repository measurements

Line counts are physical Julia source lines and are used only to size the transformation.

| Package or responsibility | Source lines | Test lines | Test/source ratio |
|:--|--:|--:|--:|
| PottsToolkit root package | 9,759 | 2,279 | 0.23 |
| Root `src/authoring` | 7,701 | — | — |
| Root `src/reference_models` | 1,631 | — | — |
| CorePotts | 32,305 | 10,063 | 0.31 |
| CorePotts `src/coupled` | 16,458 | — | — |
| ProcessBigraphs | 15,105 | 6,075 | 0.40 |
| Catalyst pinned comparison | 13,279 | 22,460 | 1.69 |
| ModelingToolkitBase pinned comparison | 33,095 | 26,224 | 0.79 |

The comparison does not imply that line count or test ratio alone establishes quality. It shows
that the current Potts authoring surface is large relative to its tests and that the V1
consolidation needs substantially more behavioral coverage around the new semantic center.

### Public surface

Runtime inspection in Julia found approximately:

| Package | Public/exported bindings |
|:--|--:|
| PottsToolkit | 248 |
| CorePotts | 777 |
| ProcessBigraphs | 271 |
| Catalyst pinned comparison | 115 explicit exports |

CorePotts currently exports internal storage, transaction, workspace, schedule, compatibility,
paper-model, algorithm-contract, and diagnostic details together. PottsToolkit re-exports a large
part of CorePotts in addition to its own authoring language. This makes ownership unclear and makes
removal appear more disruptive than the intended user-facing product actually requires.

V1 needs an explicit public inventory. Julia 1.12 supports the native `public` keyword, so useful
qualified interfaces need not all be exported.

### Production metaprogramming

CorePotts contains four production `@generated` methods and no production `@static` occurrences in
the audited paths. The generated methods implement bounded native Laplacian, history, and topology
offset specialization. The repository does not have a general generated-function or `@static`
abuse problem.

The consolidation should retain a generated method only when its current local justification
remains valid and a targeted inference/device test covers it. It should not add `@static` merely
because symbolic compilation is involved. The critical function barrier is between dynamic
authoring/completion and concrete runtime plans.

## Finding 1 — There are three modeling authorities

### Root authoring authority

The root package currently owns:

- `AbstractRuleExpression` and a separate compiled-expression hierarchy;
- Level 1 expression constructors and macros;
- Level 2 components;
- `ModelFragment`, bindings, ports, and fragment roles;
- an authoring `PottsModel`;
- normalization, validation, provenance, diagnostics, reports, and fingerprints; and
- lowering into CorePotts objects.

Cross-cutting behavior is repeated across declaration-specific methods:

| Concern | Approximate declaration-specific methods |
|:--|--:|
| Scoping | 30 |
| Canonicalization | 76 |
| Normalization | 42 |
| Validation | 32 |
| Lowering | 39 |
| Reporting | 23 |
| Total | 242 |

This is the mechanism SPV1-012 and SPV1-014 require V1 to replace. Adding Symbolics beneath it
would preserve the duplication.

`NamedCoreComponent` permits an arbitrary CorePotts object to cross the authoring boundary.
`DirectLaw` permits a host closure to represent mathematical meaning. Both defeat inspectable,
serializable, inference-owned symbolic semantics and have no V1 authority.

### CorePotts coupled semantic authority

CorePotts contains another modeling language:

- `StateSpec`;
- `ProcessSpec`;
- `PlanEntrySpec` and `PlanSpec`;
- `LifecycleSpec`;
- `ObservationSpec`;
- `SemanticModel`;
- `ContinuousSystem`;
- `DifferentialEquation`;
- `SynchronousRule`;
- `DirectLaw`;
- multirate schedules, protocol stages, and event declarations; and
- paper-specific Merks and Shirinifard assemblies.

These types mix generic runtime mechanisms with semantic authoring and ProcessBigraphs
orchestration concepts. They cannot remain a parallel input to the V1 compiler.

### Execution-facing CorePotts authority

`CorePotts.PottsModel` is an execution-facing value used by `PottsProblem` and algorithms. It is
conceptually useful but shares the public model name with the old root authoring type.

The compiled product needs a distinct identity, provisionally `PottsExecutable`. It should contain
or reference concrete runtime data, never imply that it is another user-authored symbolic model.

## Finding 2 — Clean break does not mean rewriting the kernels

The current CorePotts implementation contains reusable, already-tested mechanisms that match the
accepted V1:

- logical state, cell identity, generation, capacity, topology, and initialization;
- proposal, energy, hard-constraint, acceptance, and accepted-copy staging;
- semantic addressed RNG;
- sequential reference execution;
- deterministic checkerboard proposal/conflict/commit execution;
- relationship `CreateRelationship`, `RemoveRelationship`, and `RetuneRelationship` values;
- canonical host request sorting, duplicate/conflict handling, capacity/degree/generation checks,
  and atomic publication;
- a portable device path that serializes only the final application after deterministic batch
  preparation;
- lifecycle requests and cleanup;
- native field state and field exchange kernels;
- activity, history, polarity, focal-point, and observation mechanisms; and
- SciML problem/integrator/solution behavior.

The target transformation is:

| Current asset | V1 treatment |
|:--|:--|
| Concrete scientific kernels and mechanisms | Retain, extract, rename, or narrow behind compiler targets |
| Logical state and transaction invariants | Retain as CorePotts authority |
| Semantic RNG implementation | Retain; compiler supplies stable qualified draw identities |
| Sequential and checkerboard engines | Retain and adapt to `PottsExecutable` |
| Relationship request language and transaction | Retain as the concrete lowering target |
| Native fields and observations | Retain as lowerings for V1 statements/equation processes |
| Root expression/fragment/model hierarchy | Delete and replace |
| Core coupled semantic model and continuous DSL | Delete and replace as authoring authorities |
| Paper-specific Core assemblies | Delete; replace with complete V1 fixtures |
| Arbitrary closure/core-component escape hatches | Delete |

This distinction should be normative in the consolidation spec. Without it, an autonomous agent
could either preserve too much legacy structure or unnecessarily rewrite scientifically qualified
kernels.

## Finding 3 — Engine reduction is a real simplification

V1 accepts exactly:

- sequential reference execution; and
- deterministic checkerboard execution.

Current obsolete engine-specific source includes at least:

- `algorithms/tiled_checkerboard.jl`: 463 lines;
- `algorithms/tiled_checkerboard_device.jl`: 812 lines; and
- `algorithms/lottery.jl`: 415 lines.

Additional tiled and lottery definitions occur in shared algorithm contracts, exports, tests,
benchmarks, precompile workloads, specifications, and documentation. Searches found 38 test,
integration, or benchmark files referring to `TiledCheckerboardCPM` or `LotteryCPM`.

The consolidation must remove the implementations, declarations, exports, precompile work, living
tests, and V1-facing capability paths together. Historical records may retain their exact names.

Checkerboard currently builds a realized conflict graph from proposal and component access
relations. It does not provide a general proof for relationship mutation committed with an
accepted copy. This supports the conservative accepted V1 boundary: such a model may compile for
sequential execution and must be rejected for checkerboard until its bounded complete touched set
can be proved. End-of-MCS ordered relationship batches remain viable on both engines.

## Finding 4 — ProcessBigraphs should be optional to Potts execution

CorePotts directly imports ProcessBigraphs, but production usage is confined to:

- activity problem integration;
- coupled Merks and Shirinifard assemblies;
- the direct process-bigraph adapter; and
- a legacy checkpoint conversion path.

That is optional integration, not a foundational dependency of logical Potts state, kernels, or
either V1 engine.

The older repository architecture and semantic-preserving consolidation contract require:

```text
ProcessBigraphs <- CorePotts <- PottsToolkit
```

That direction was reasonable for the former coupled semantic kernel. The accepted V1 instead
states that `PottsSystem` owns symbolic CPM composition and ProcessBigraphs owns heterogeneous
runtime orchestration. Julia package extensions now provide the cleaner boundary.

Recommended V1 dependency direction:

```text
ProcessBigraphs        CorePotts
          ^              ^
          | optional     |
          +-- PottsToolkit
                |
                +-- PottsToolkitProcessBigraphsExt
```

More precisely:

- ProcessBigraphs remains domain-neutral and does not depend on PottsToolkit or CorePotts.
- CorePotts removes its strong ProcessBigraphs dependency.
- PottsToolkit depends strongly on CorePotts.
- ProcessBigraphs becomes a PottsToolkit weak dependency.
- `PottsToolkitProcessBigraphsExt` adds the adapter from a completed/compiled Potts value to a
  ProcessBigraphs engine/process contract.
- A CorePotts-owned extension is warranted only for a truly low-level adapter whose public
  signature does not involve PottsToolkit types.
- Legacy ProcessBigraph checkpoint conversion is deleted under the accepted clean break.

This recommendation requires an explicit accepted supersession of the older strong-dependency
rule. It must not be smuggled into implementation as an incidental project-file cleanup.

## Finding 5 — Catalyst supplies the architecture, not a debt-free template

Catalyst's strongest precedent is coherent domain ownership:

- `Reaction` is a first-class domain node;
- `ReactionSystem <: AbstractSystem` stores reactions and equations;
- composition, extension, completion, flattening, namespacing, and conversion are domain-aware;
- conversions live in explicit conversion files;
- tests are grouped by modeling, simulation, hybrid, spatial, extensions, and QA; and
- field additions are guarded by an explicit system-field inventory used by serialization logic.

Potts V1 should copy those principles.

Catalyst is not spotless. The pinned tree's own QA configuration tracks existing ambiguity,
undefined-export, unbound-parameter, JET, internal-access, and legacy re-export debt. The lesson is
not to imitate every dependency reach-through or compatibility allowlist. A new clean-break V1 has
the opportunity to start without that debt.

The appropriate quality target is:

> Catalyst-style domain-node and system coherence, with public-interface discipline and a clean
> QA baseline stricter than Catalyst's accumulated compatibility surface.

## Finding 6 — Potts must own composition, extension, and completion

Generic ModelingToolkit behavior is insufficient for the accepted semantics:

- generic `extend` may union duplicate content and prefer one system's fields;
- accepted Potts extension treats duplicate statement, state, process, observation, protocol, and
  equation identities as errors;
- generic composition assumes conventional fields and reconstruction behavior; and
- generic completion cannot infer Potts reads, writes, effect bounds, phases, random sites,
  relationship resources, or engine capabilities.

`PottsSystem` therefore needs explicit methods for:

- public system accessors;
- renaming/reconstruction;
- `compose`;
- `extend`;
- namespacing and flattening;
- `complete`;
- variable and parameter discovery;
- observed and initial-condition access;
- SymbolicIndexingInterface integration; and
- conversion/extraction of explicit equation components.

These methods should use documented public interfaces. They must not depend on a concrete
ModelingToolkit `System` layout.

An incomplete and complete system may remain the same immutable outer type with a completion flag
and private completion data, following the practical Catalyst pattern. Its internal vectors can be
mutable values, but constructors and composition must copy them so that a system behaves as an
immutable scientific value.

## Finding 7 — Symbolics is viable as the sole expression IR

The required traversal and registration functions are public through current Symbolics or its
public dependencies:

- `iscall`;
- `operation`;
- `arguments`;
- public metadata access;
- symbolic registration macros; and
- SymbolicIndexingInterface symbolic traits and names.

The implementation should not store or dispatch on private concrete term types. It should also
avoid committing its system field types to an internal alias such as `Symbolics.SymbolicT`.

Recommended host storage:

- `statements::Vector{AbstractPottsStatement}`;
- `equations::Vector{Equation}` or another documented equation element type;
- dynamically typed unknown and parameter vectors validated through public symbolic traits;
- `systems::Vector{PottsSystem}`; and
- private completion data.

Dynamic host storage is acceptable. Catalyst also permits dynamic authoring fields. Type stability
is required after the compiler function barrier, where qualified statements are grouped into
concrete runtime descriptors and storage plans.

### One generic traversal

The old 242-method cross-cutting pipeline should not be recreated with new type names.

Every built-in statement should expose one structural traversal/reconstruction protocol. The
compiler can then apply a generic walk to:

- namespace symbolic values;
- substitute symbolic values;
- collect variables and parameters;
- canonicalize expression children;
- collect source/provenance information; and
- serialize statement structure.

Domain-specific dispatch remains appropriate for:

- unit rules;
- access and effect inference;
- phase validation;
- boundedness;
- reference semantics;
- engine/backend capability inference; and
- lowering.

Expression structure and statement meaning are separate concerns.

## Finding 8 — Unit scale needs a dedicated Potts pass

DynamicQuantities is a suitable canonical unit representation because dimensions are values rather
than type parameters, which reduces overspecialization pressure at authoring boundaries.

The exact syntax matters:

- `us"..."` preserves the declared symbolic unit and scale;
- `u"..."` expands the value into base SI units; and
- `ustrip`/`uexpand` support explicit conversion and stripping.

The Round 3 candidate syntax uses `u"μm"` in places. The canonical V1 fixture should use symbolic
unit spellings such as `us"μm"` wherever declared scale must remain inspectable.

ModelingToolkit's current unit validation checks dimensions/units but does not insert the explicit
reference-unit conversions required by V1. Catalyst maintains a substantial domain-specific unit
helper because generic unit lookup can expand symbolic dimensions into SI and lose the original
declared representation.

V1 therefore needs a bounded Potts unit-analysis pass over the accepted expression grammar. It
must:

1. preserve declared symbolic scale and dimensions;
2. validate statement-specific unit relationships;
3. validate equations and coupling boundaries;
4. select an explicit reference-unit system at completion;
5. record exact conversion factors in qualified inspection;
6. reject ambiguous or inexact conversions before compilation; and
7. strip units only when producing concrete runtime data.

This is one of the few areas where relying solely on generic MTK behavior would be under-specified.

## Finding 9 — Built-ins should be closed; registration should freeze at completion

The accepted single `RegisteredStatement` boundary is compatible with a polished implementation if
registration remains a host-side compiler service.

Recommended behavior:

- built-in statements and Potts symbolic operations use ordinary immutable Julia types/functions
  and multiple dispatch;
- one registry maps stable schema identity and semantic version to immutable compiler services;
- registration is idempotent only for the exact same schema/version definition;
- conflicting registrations are errors;
- extension registration occurs during module/extension loading;
- completion resolves the exact schema implementations;
- completion copies an immutable registry snapshot or resolved schema table into completion data;
- fingerprints include schema identities and versions; and
- compilation and runtime never consult mutable global registry state.

The consolidation spec still needs to freeze whether `complete` accepts an explicit registry
argument in addition to the default package registry. An explicit argument improves isolated tests
and reproducible environments; a default registry improves ordinary extension ergonomics. The two
are compatible if completion always records the resolved immutable snapshot.

## Finding 10 — The compiled product needs a distinct contract

Recommended lifecycle:

```text
incomplete PottsSystem
    -> complete
complete PottsSystem + CompletionData
    -> compile(engine, backend, scalar policy)
PottsExecutable + qualified inspection snapshot
    -> PottsProblem(initial spatial state, time span, parameters, seed, replica)
    -> solve
```

`PottsExecutable` should distinguish:

- host inspection data, which may retain qualified names, source locations, units, and reports;
- concrete runtime plan data, which is unit-stripped and registry-free; and
- device data, which contains no Symbolics, DynamicQuantities, host registry, strings, or
  arbitrary closures.

The current explicit `PottsCompilationCache` is conceptually acceptable because it is caller-owned
rather than hidden global state. Its key and value types will need to move to completed-system and
executable fingerprints.

Initial spatial layouts belong to `PottsProblem`. Symbolic initial conditions in `PottsSystem`
should mean symbolic defaults for declared state, not a hidden large lattice allocation.

Structural bounds such as relationship capacity and maximum degree should be completion-time
declaration literals because they determine storage. Scientific coefficients such as energy
strengths and temperatures can remain replaceable runtime parameters when their replacement does
not alter structure or capability.

## Finding 11 — The package dependency set should follow ownership

### Root PottsToolkit

Recommended strong dependencies:

- CorePotts;
- ModelingToolkitBase;
- Symbolics;
- SymbolicIndexingInterface;
- DynamicQuantities;
- SciMLBase;
- SHA, if fingerprints remain implemented directly in the root package;
- PrecompileTools, if representative workloads materially improve latency; and
- only the small concrete utilities required by compiler data.

Recommended weak dependencies:

- ProcessBigraphs;
- Unitful; and
- optional visualization/backend integrations as applicable.

Recommended removals from the root strong dependency set:

- `OrdinaryDiffEqTsit5`, currently used only by the hidden Merks reference model;
- ProcessBigraphs as a strong dependency; and
- StaticArrays if it remains solely a CorePotts runtime concern after replacement of the old rule
  compiler.

### CorePotts

CorePotts should retain numerical, device, storage, SciML runtime, and fingerprint dependencies it
actually owns. It should remove ProcessBigraphs as a strong dependency unless the implementation
audit proves a general low-level adapter belongs here.

CorePotts must remain free of ModelingToolkitBase, ModelingToolkit, Symbolics,
SymbolicIndexingInterface, and DynamicQuantities.

### Precompile workload

The current root precompile workload constructs a paper reference model and all four historical
algorithm families. V1 should instead compile one tiny deterministic authoring-to-runtime path for:

- completion;
- sequential compilation/problem construction; and
- checkerboard compilation/problem construction.

It should not solve a paper-scale model, load an ODE algorithm solely for precompilation, or retain
deleted engines. Invalidation healing should be added only after measurement identifies a real
external invalidation.

## Finding 12 — QA should be ordinary and strict

The current living CI is already close to the right shape:

- package tests for PottsToolkit, CorePotts, MakiePotts, and ProcessBigraphs;
- cross-package integration tests;
- macOS and Windows load smoke tests;
- a separate documentation build;
- manual GPU validation; and
- manual benchmark/performance comparison workflows.

The obsolete freshness and one-time qualification scripts are already under archive paths and
should not return to the required V1 gate.

Recommended V1 QA:

### Package test organization

Root tests should be grouped by responsibility:

```text
test/
  system/
  statements/
  symbolics/
  compiler/
  runtime/
  integration/
  fixtures/
  qa/
```

The exact directories may vary, but test ownership should mirror the semantic pipeline. One
monolithic sequence of legacy phase tests should not define the V1 architecture.

### QA environment

Use a small separate QA test environment if adding analysis tools would otherwise inflate the
ordinary package test environment.

Required checks:

- Aqua with ambiguities, undefined exports, unbound type parameters, stale dependencies, piracy,
  and persistent tasks enabled unless a documented reproducible upstream limitation applies;
- `Test.detect_ambiguities` for the owned package boundary;
- ExplicitImports checks for implicit imports, stale imports, ownership, and public dependency
  access;
- package-wide JET typo/error analysis at an appropriate target-module boundary; and
- targeted `JET.@test_opt` only for compiler-to-runtime boundaries and hot execution kernels.

Unlike the pinned Catalyst tree, a clean-break V1 should not begin with a broken-test allowlist for
new ambiguities or internal accesses.

### Inference and performance

Do not require every authoring constructor or dynamic symbolic container to infer perfectly.
Require:

- concrete runtime descriptors after the compiler function barrier;
- inference for inner-loop component, proposal, RNG, transaction, and kernel calls;
- zero or explicitly bounded steady-state allocations in hot CPU paths after warmup;
- representative compilation and solve benchmarks; and
- manual/nightly timing regression evidence where shared CI noise makes hard time thresholds
  brittle.

Allocation caps can be reliable PR gates. Fine-grained wall-clock budgets generally should not be.

### Backend scope

GPU tests should run when supported hardware is available or by explicit dispatch. V1 should not
recreate expiring hardware evidence or fail ordinary documentation builds because a device smoke
record aged.

## Finding 13 — Acceptance fixtures replace hidden reference models

The current root reference models account for 1,631 source lines and bring in paper-specific
dependencies. The V1 contract requires model syntax to be visible rather than imported.

Recommended fixtures:

```text
test/fixtures/merks.jl
test/fixtures/wortel.jl
test/fixtures/focal_links.jl
```

Each fixture should:

- construct all kinds, state, relations, statements, equations, protocols, observations, and
  parameters inline;
- construct the complete initial spatial layout inline at the problem boundary;
- call `complete`, inspect, compile, construct a stochastic problem, and run;
- prove same-seed replay and different-seed divergence;
- expose qualified statement, unit, effect, random-operation, schedule, capability, and
  fingerprint information; and
- contain no hidden model constructor, `include` of an assembly, opaque CorePotts object, or
  paper-specific runtime façade.

Small fixture helpers may create repetitive literal arrays or compare results. They must not hide
the scientific assembly being accepted.

These are test fixtures on this branch, not user-facing documentation. The later documentation
phase can display the same public syntax and use native Makie animations without importing a
hidden model.

## Recommended source architecture

The exact split should follow cohesion rather than a one-type-per-file rule:

```text
src/
  PottsToolkit.jl
  system/
    types.jl
    constructors.jl
    accessors.jl
    composition.jl
    completion.jl
  statements/
    types.jl
    constructors.jl
    traversal.jl
    components.jl
  symbolics/
    metadata.jl
    operations.jl
    analysis.jl
    units.jl
  compiler/
    qualified_ir.jl
    inference.jl
    capabilities.jl
    fingerprints.jl
    lowering.jl
    inspection.jl
  runtime/
    executable.jl
    problem.jl
    indexing.jl
    solve.jl
  registry/
    statements.jl
  precompile.jl
```

Directories do not require nested Julia submodules. A submodule is justified only by a real
namespace or dependency boundary.

### Candidate system shape

The concrete fields remain private, but the implementation needs storage equivalent to:

```julia
struct PottsSystem <: ModelingToolkitBase.AbstractSystem
    statements
    equations
    unknowns
    parameters
    systems
    initial_conditions
    observed
    events
    name
    complete
    completion_data
end
```

The final type should use useful container element types where they are part of a documented public
contract, but it should not embed private Symbolics term types. An explicit field inventory should
be tested so new fields force updates to reconstruction, equality, serialization/fingerprinting,
and inspection.

### Candidate qualified statement

The compiler needs an internal immutable product equivalent to:

```text
QualifiedStatement
  qualified identity
  statement kind and schema version
  source location and provenance
  normalized symbolic payload
  inferred result type and units
  reference-unit conversion
  reads and writes
  effect class and bound
  random operations
  phase and ordering dependencies
  required resources and storage
  engine/backend capabilities and rejection reasons
  concrete lowering identity
```

This is not a second expression IR. Symbolics remains the expression representation until lowering;
the qualified record holds resolved semantic facts around it.

### Candidate compilation passes

```text
1. structural validation
2. namespace and flatten
3. symbolic discovery
4. reference and ownership resolution
5. unit and scale analysis
6. access/effect/random/bound inference
7. phase DAG and writer validation
8. extension schema resolution and registry freeze
9. canonical identity/order construction
10. completion fingerprints and public inspection snapshot
11. engine/backend capability selection
12. storage and transaction planning
13. concrete CorePotts lowering
14. executable fingerprint and preflight
```

Passes may be fused when implementation clarity improves, but each output and diagnostic
responsibility must have one owner.

## Deletion, replacement, and extraction map

This is a responsibility map, not an instruction to delete every named file before replacements
exist.

| Current location/responsibility | Disposition | Replacement or retained authority |
|:--|:--|:--|
| `src/authoring/rule_parts` expression algebra | Delete | Symbolics expressions and registered public operations |
| `src/authoring/level1*` old DSL | Delete | Thin declarations plus ordinary V1 constructors |
| `src/authoring/models.jl` fragments and authoring model | Delete | `PottsSystem`, strict `compose`, strict `extend` |
| `src/authoring/normalization*` | Replace | Potts completion and qualified compiler passes |
| `src/authoring/lowering.jl` | Replace | V1 compiler lowering |
| `src/authoring` reports/diagnostics | Reuse concepts, replace types as needed | Public qualified inspection and contextual diagnostics |
| `src/reference_models` hidden assemblies | Delete | Complete visible acceptance fixtures |
| Root paper-specific ODE dependency | Delete | Equation-process fixture/integration dependency only where needed |
| Core `coupled/semantic_kernel.jl` model DSL | Delete as authority | `PottsSystem` and qualified IR |
| Core continuous declaration DSL and `DirectLaw` | Delete as authority | Ordinary equations plus `EquationProcess` |
| Core schedules/protocol declarations | Narrow or delete | V1 semantic phase DAG; ProcessBigraphs owns heterogeneous scheduling |
| Core paper-specific Merks/Shirinifard assemblies | Delete | V1 fixtures; reusable mechanisms remain generic |
| Core ProcessBigraph adapter | Move/narrow | Package extension |
| Core legacy PB checkpoint conversion | Delete | No migration expectation on this branch |
| Core activity/field/history/polarity mechanisms | Extract and retain | Concrete compiler lowering targets |
| Core relationship requests and transactions | Retain and narrow | Concrete `Create`/`Remove`/`Retune` lowering target |
| Core lifecycle machinery | Retain and narrow | Concrete lifecycle lowering target |
| Core observations | Retain and narrow | Concrete observation lowering target |
| Core `PottsModel` | Rename/restructure | `PottsExecutable` or private runtime program |
| Tiled and lottery engines | Delete from living V1 | Exactly sequential and checkerboard |
| Old authoring and obsolete-engine tests | Delete/rewrite | Pipeline tests and V1 fixtures |
| Historical specifications/evidence | Preserve as history | Explicit supersession map; no living authority |

## Required specification supersessions

An autonomous implementation cannot safely operate while contradictory accepted documents remain
apparently current. The consolidation specification must explicitly supersede, at least where they
conflict:

| Existing authority | Conflicting old requirement | V1 replacement |
|:--|:--|:--|
| `pottstoolkit-authoring-composition-and-api-semantics.md` | `PottsModel`, `ModelFragment`, Level 1/2 surface | `PottsSystem`, typed statements, Symbolics, strict composition |
| `pottstoolkit-rule-and-model-semantics.md` | old rule expression/model authority | SPV1 expression and statement contracts |
| `sciml-interface-semantics.md` | authoring `PottsModel`, Lottery as living algorithm | `PottsSystem`, `PottsExecutable`, two engines |
| `semantic-preserving-consolidation-contract.md` | backward-compatible preservation and strong CorePotts → PB dependency | clean break and optional PB extension |
| `repository-architecture-standard.md` | CorePotts strong PB dependency and old Level 2 organization | V1 dependency and source ownership |
| `metaprogramming-and-compiler-architecture.md` | custom typed expression IR and old pipeline names | Symbolics expression IR plus qualified Potts records |
| `open-protocol-and-extensibility-standard.md` | broad Level 2/3 extension expectations and old registries | closed built-ins plus one `RegisteredStatement` boundary |
| living engine specifications | tiled/lottery capability paths | sequential and deterministic checkerboard only |
| Phase 14 semantic-kernel authorities | second coupled modeling language | PottsSystem for CPM; PB for heterogeneous orchestration |

Supersession should be scoped. Accepted scientific invariants for topology, energy, randomness,
lifecycle, persistence, and model reproduction remain authoritative unless V1 explicitly changes
them.

The spec index must clearly separate:

- current V1 authority;
- still-applicable scientific semantics;
- superseded authoring/architecture documents; and
- historical evidence.

Merely saying that newer decisions win in case of conflict is not enough for autonomous work; the
conflicting clauses and their replacements should be listed.

## Autonomous implementation sequence

The owner has requested one end-to-end phase, not a series of supervised project phases. The work
can still have internal dependency-ordered slices:

1. **Authority freeze**
   - accept the consolidation spec;
   - record supersessions and final dependency direction;
   - freeze constructors, operation inventory, registry behavior, diagnostics, and file impact.
2. **System and symbolic center**
   - add dependencies;
   - implement `PottsSystem`, public MTK/SII contracts, statement types, traversal, operations,
     units, composition, and completion.
3. **Qualified compiler**
   - implement inference, phase/effect validation, fingerprints, inspection, capabilities, and
     concrete lowering.
4. **Runtime narrowing**
   - introduce `PottsExecutable`;
   - adapt sequential/checkerboard and SciML runtime;
   - extract reusable mechanisms from the old coupled DSL.
5. **Clean break**
   - remove old authoring, coupled semantic authorities, hidden reference models, obsolete engines,
     exports, tests, dependencies, and precompile paths.
6. **Optional orchestration**
   - move ProcessBigraphs integration behind the accepted extension boundary.
7. **Acceptance fixtures and QA**
   - add full inline Merks, Wortel, and focal fixtures;
   - add package, integration, inference, allocation, public API, and QA checks;
   - run the black-box authoring-to-result gate.

These are implementation slices within one autonomous phase. They are not user review gates.
Temporary dual paths may exist only within local commits while migrating internals; the branch
cannot finish with both authorities.

## Decisions the consolidation specification must freeze

The research supports strong recommendations, but an implementation-grade spec must write exact
answers for:

1. the final public `PottsSystem` constructor call shapes and defaults;
2. the complete built-in statement type and constructor inventory;
3. the complete registered Potts symbolic operation inventory;
4. the generic statement traversal/reconstruction interface;
5. exact identity, source-location, namespace, and duplicate rules;
6. exact unit inference and reference-unit conversion rules;
7. registry creation, registration, snapshot, and explicit-override behavior;
8. completion data fields and completed-system reconstruction behavior;
9. exact `PottsExecutable` name and public/private boundary;
10. which structural values are compile-time declarations versus runtime parameters;
11. the initial-state/problem constructor contract;
12. exact equation-component and `EquationProcess` behavior;
13. exact ProcessBigraphs weak-dependency and extension ownership;
14. the public export/public-qualified inventory;
15. the file-by-file removal/extraction list;
16. the test and QA command matrix; and
17. the scoped supersession table.

Once these are frozen, no unresolved architectural choice identified by this audit requires routine
human oversight during implementation.

## Risk register

| Risk | Severity | Control |
|:--|:--|:--|
| Old accepted documents redirect implementation toward compatibility | Critical | Explicit clause-level supersession map |
| Symbolic unit scale silently expands to SI | High | Potts-owned unit pass and `us"..."` fixtures |
| New statement types recreate manual pass explosion | High | One structural traversal plus semantic dispatch |
| Core coupled DSL survives as a second model input | Critical | Deletion map and stale-authority tests |
| “Clean break” rewrites qualified kernels unnecessarily | High | Extraction map and retained-mechanism conformance tests |
| Mutable registry changes compilation meaning | High | Freeze resolved schema snapshot during completion |
| Generic MTK `extend` silently resolves duplicates | High | Potts-specific strict composition/extension |
| Private Symbolics/MTK types leak into storage | High | ExplicitImports/public-owner QA and public-trait tests |
| Checkerboard overclaims relationship support | High | Capability proof and explicit preflight rejection |
| Public API remains hundreds of unowned exports | Medium | Curated export/public inventory with API tests |
| Symbolic package load cost becomes surprising | Medium | Measured precompile workload and dependency audits |
| Timing thresholds recreate brittle CI | Medium | Hard allocation/inference gates; manual measured timing |
| Optional PB integration remains a core dependency | Medium | Weak dependency and extension-loading tests |
| Full paper fixtures hide assembly behind helpers | High | Source-level fixture audit plus public inspection |

## Readiness judgment

The architecture is ready for an implementation-grade consolidation specification.

It is not yet ready for autonomous implementation because the decisions listed above have not been
expressed as exact constructor, operation, IR, dependency, file-impact, test, and supersession
contracts. The remaining work is specification precision, not fundamental product discovery.

The recommended target is both more ambitious and cleaner than the present code:

- one symbolic model;
- one expression representation;
- one completion authority;
- one qualified compiler path;
- one distinctly named executable;
- two engines;
- one registered statement boundary;
- one optional ProcessBigraphs integration boundary; and
- one ordinary Julia package-quality gate.

