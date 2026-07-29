# Decision 0040: ProcessBigraphs High-Level Authoring and Phase 16.HC

Status: Accepted architecture; specification complete, implementation and qualification open

Date: 2026-07-28

## Context

Phase 15 and the implemented portions of Phase 16 established a canonical ProcessBigraph ACSet,
open composition, exact orchestration, dynamic structural transactions, solver-neutral adapters,
real SciML handoff, and runnable bounded Merks and CNV assemblies. Those scientific assemblies and
many behavioral tests still required authors to construct `StaticComposite`,
`ProcessDeclaration`, `StepDeclaration`, `PortBinding`, paths, and other canonical-lowering
records directly.

An initial uncommitted Phase 16.HC spike added `scheduled`, `reactive`, `iteration`, `expose`,
`compose`, and `@compose`, then migrated models and tests. The spike demonstrated that naming and
wrapping the existing port maps did not create the polished semantic API required for a
world-class Julia library. It was useful research, not qualification evidence.

The owner requested a researched second consolidation pass before further implementation. The
result was thirteen architecture interviews, one explicit consistency correction, and one
migration/qualification interview. The owner accepted option A+ for every decision.

## Decision

### Semantic authoring layer

ProcessBigraphs adds an immutable hierarchical `CompositeModel` as its author-facing source of
scientific and compositional meaning. A transactional ordinary-Julia builder creates it.
Deterministic lowering produces the canonical ProcessBigraph ACSet plus an origin map. Backend
compilation then creates an execution plan. Runtime state and solver sessions remain separate.

This refines Decision 0037's typed-authoring rule. The semantic model is not a second canonical
runtime structure: the ACSet remains canonical lowered structure, and the execution plan remains
the sole runtime route.

### Ordinary Julia surface

The primary form is `compose(:Name) do builder ... end`. Explicit names and typed handles replace
raw string paths and port maps. The vocabulary centers on stores, mounts, connections,
attachments, exports, schedules, parameters, observables, and structural templates.

Ordinary Julia functions, loops, collections, and dispatch are the metaprogramming mechanism. A
full `@compose` DSL is not required for Phase 16.HC. Any later macro is optional transparent sugar
over the complete programmatic API.

### Topology and state

Named shared-store junctions are topology truth. Stores own shared state, update-law
reconciliation, persistence, and structural transfer. Logical ports declare read/write access and
contract requirements. Exact-name bulk attachment is explicit and inspectable; silent autowiring
is forbidden.

Schemas infer unambiguous Julia storage facts and require explicit scientific meaning where
needed. Model constants, declared run parameters, model defaults, and problem initial conditions
are distinct.

### Components, time, and execution

Components and adapters use an open functional protocol with typed capabilities and private
sessions. They return typed effects rather than mutating committed stores.

ProcessBigraphs owns communication boundaries, stages, publication, structural transactions, and
resources. Solvers own internal steps, iterations, root finding, workspaces, buffers, and kernels.
An `Advance(t0, t1)` request is not a numerical timestep and cannot impose fixed-step Euler.

Parallel stages read one committed snapshot and commit in deterministic semantic order. Explicit
iterative regions require checkpoint/restore or pure reconstructibility.

### Hierarchy and dynamic structure

Hierarchy is lexical and private by default. Reusable definitions mount repeatedly and expose
only declared boundaries. Lowering may flatten execution while retaining author origin.

Dynamic structure instantiates declared immutable templates through typed spawn, divide, remove,
move, and bounded replacement effects. ProcessBigraphs validates and atomically publishes them.
Runtime identities are replay-stable and independent of task or memory order.

### Diagnostics, lowering, and identity

Finalization accumulates structured diagnostics with stable codes and author-facing handles.
Lowering is pure, deterministic, backend-independent, and provenance-preserving.

Semantic, canonical-IR, execution-plan, problem, run, and checkpoint identities are distinct.
Serialization preserves supported semantics and fingerprints rather than the exact authoring
spelling.

### Problems and ecosystem

Reusable models are bound into immutable simulation problems containing initial state, declared
parameter values, interventions, time span, and seed policy. Observables are semantic; recording
policy and sinks are run concerns. Random streams derive from stable semantic coordinates.

ProcessBigraphs remains solver-neutral without a hard SciML dependency. SciMLBase and CommonSolve
remain weak extension triggers. The extension supplies applicable common interfaces and delegates
numerics to real solver-owned methods. This explicitly corrects the provisional interview
recommendation that SciMLBase become a hard core dependency.

### Migration and qualification

Phase 16.HC, “High-level Composition,” is a mandatory gate after 16.H and before 16.I. It freezes
the specification and public API before implementation, then implements the semantic layer before
migrating scientific models.

Raw IR remains available for lowering, schema conformance, serialization migration, independent
oracles, and explicit expert tooling. It is forbidden in migrated scientific library models,
ordinary behavioral tests, examples, and documentation.

Existing qualified numerical, structural, failure, persistence, and bounded-model evidence is not
rewritten. Merks and CNV receive separate authoring-migration evidence. The unresolved Phase 16.C
Metal and ROCm evidence remains independent and mandatory.

## Supersession and refinement

This decision:

- refines Decision 0037 by defining the previously unspecified ordinary semantic builder and
  staged lowering lifecycle;
- preserves Decision 0036's canonical ACSet and compiled-plan authority;
- preserves Decision 0039's compute-ownership, solver-neutral, model-scope, and evidence boundary;
- supersedes any provisional claim that the uncommitted `scheduled`/`reactive`/`@compose` spike is
  a qualified Phase 16.HC API;
- supersedes any requirement that normal scientific models construct canonical IR directly; and
- corrects any provisional recommendation that ProcessBigraphs core hard-depend on SciMLBase.

## Consequences

- Julia developers receive a small ordinary functional API instead of raw IR or a large macro
  language.
- Canonical ACSet structure and optimized runtime kernels remain intact.
- Authoring, lowering, planning, and execution receive distinct identities and diagnostics.
- Adapter authors can support non-SciML solvers without installing SciML.
- Merks and CNV become high-level composition acceptance models without expanding into their full
  publication analyses.
- Phase 16.I remains open until authoring migration and qualification complete.

## Rejected alternatives

- Treating the current macro spike as sufficient.
- Making raw canonical IR the ordinary public authoring format.
- A mandatory full `@compose` language.
- Silent name-based autowiring.
- One mutable object spanning authoring, IR, plan, and runtime.
- Direct shared-store mutation by solvers.
- A hard SciML dependency in ProcessBigraphs core.
- Replacing the canonical ACSet or qualified numerical kernels during authoring hardening.
- Migrating all models before the semantic API and lowering contract freeze.

## Required evidence

The complete evidence obligations are normative in
[`process-bigraph-high-level-authoring-semantics.md`](../process-bigraph-high-level-authoring-semantics.md)
and the Phase 16 qualification ledger. At minimum they include:

- ordinary Julia expressibility for every stable authoring construct;
- immutable lifecycle, typed handle, hierarchy, connection, schedule, and template tests;
- structured diagnostic and origin-map tests;
- deterministic lowering and layered fingerprint evidence;
- optional SciML extension and independent adapter conformance;
- raw-IR inventory and allowlist enforcement;
- Merks and CNV migration with bounded behavioral equivalence;
- documentation, doctests, Aqua, clean-environment, and performance evidence; and
- preservation of all applicable qualified Phase 15 and Phase 16 contracts.
