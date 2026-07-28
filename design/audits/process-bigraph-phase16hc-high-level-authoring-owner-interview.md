# ProcessBigraphs Phase 16.HC High-Level Authoring Owner Interview

Status: Complete; all recommended choices accepted

Date: 2026-07-28

## Purpose

This interview resolves the high-level authoring, lowering, problem, extension, execution, and
migration boundary needed before Phase 16.I. It follows an uncommitted first-pass authoring spike
that made raw ProcessBigraph IR slightly easier to spell but did not provide the semantic object
model expected of a polished Julia library.

The owner required:

- no implementation until the architecture and specifications were complete;
- ordinary Julia authoring rather than mandatory raw IR;
- no unnecessary macro language;
- arbitrary solver adapters;
- ProcessBigraphs ownership of when and why computation occurs;
- solver and CPM ownership of heavy numerical implementation;
- runnable bounded Merks and CNV models without full analyses;
- research before every interview; and
- a robust but explicitly non-overengineered Phase 16.HC gate.

The owner accepted A+ for every recommended decision, including the explicit correction that
SciML remain a first-class weak-dependency extension rather than a hard ProcessBigraphs core
dependency.

## Research basis

Primary documentation and papers reviewed across the interviews included:

- Process Bigraphs and Vivarium architecture:
  <https://arxiv.org/abs/2512.23754>,
  <https://vivarium-core.readthedocs.io/en/latest/guides/hierarchy.html>, and
  <https://vivarium-core.readthedocs.io/en/latest/guides/experiments.html>
- ModelingToolkit model building, composition, initialization, events, and IO:
  <https://docs.sciml.ai/ModelingToolkit/stable/API/model_building/>,
  <https://docs.sciml.ai/ModelingToolkit/stable/basics/Composition/>,
  <https://docs.sciml.ai/ModelingToolkit/stable/tutorials/initialization/>, and
  <https://docs.sciml.ai/ModelingToolkit/stable/basics/Events/>
- SciMLBase problems, solve lifecycle, ensembles, and solution conventions:
  <https://docs.sciml.ai/SciMLBase/stable/interfaces/Problems/>,
  <https://docs.sciml.ai/SciMLBase/stable/interfaces/Init_Solve/>, and
  <https://docs.sciml.ai/SciMLBase/stable/interfaces/Ensembles/>
- SymbolicIndexingInterface:
  <https://docs.sciml.ai/SymbolicIndexingInterface/stable/complete_sii/>
- Catalyst programmatic and DSL model construction:
  <https://docs.sciml.ai/Catalyst/stable/api/core_api/>
- JuMP and MathOptInterface authoring and model/solver separation:
  <https://jump.dev/JuMP.jl/stable/manual/variables/> and
  <https://jump.dev/JuMP.jl/stable/moi/manual/models/>
- Catlab wiring diagrams and expressions:
  <https://algebraicjulia.github.io/Catlab.jl/latest/apis/wiring_diagrams/> and
  <https://algebraicjulia.github.io/Catlab.jl/latest/generated/wiring_diagrams/diagrams_and_expressions/>
- Julia weak dependencies, extensions, threading, modules, and compatibility:
  <https://pkgdocs.julialang.org/v1/creating-packages/>,
  <https://docs.julialang.org/en/v1/manual/multi-threading/>,
  <https://docs.julialang.org/en/v1/manual/modules/>, and
  <https://pkgdocs.julialang.org/v1.10/compatibility/>
- FMI 3.0 Co-Simulation:
  <https://fmi-standard.org/docs/3.0.2/>
- preCICE explicit and implicit coupling:
  <https://precice.org/couple-your-code-coupling-flow> and
  <https://precice.org/couple-your-code-implicit-coupling>
- Documenter, Aqua, and BenchmarkTools:
  <https://documenter.juliadocs.org/stable/man/doctests/>,
  <https://juliatesting.github.io/Aqua.jl/stable/>, and
  <https://juliaci.github.io/BenchmarkTools.jl/stable/manual/>

Repository sources remained authoritative. External systems were design inputs, not semantic
authorities or new dependencies.

## Interview 1 — semantic lifecycle

Accepted:

- a transactional builder inside `compose`;
- an immutable inspectable `CompositeModel`;
- derivation through `remake`, composition, or a new transaction;
- explicit nonmutating lowering and compilation; and
- distinct semantic model, canonical IR, execution plan, and runtime.

## Interview 2 — connection semantics

Accepted:

- named shared-store typed junctions as topology truth;
- stores own state and merge semantics;
- logical read, write, and read/write ports;
- explicit exact-name `attach!` with an expansion report;
- typed handles rather than string paths; and
- no silent autowiring.

## Interview 3 — state and schema

Accepted:

- infer unambiguous Julia storage facts;
- require scientific units, meaning, residency, transfer, ownership, and division semantics;
- derive an update law only from one unambiguous compatible writer law;
- separate reusable defaults from run-specific initial conditions;
- preserve typed unit metadata without forcing boxed unitful hot arrays; and
- make conversions explicit.

## Interview 4 — component and solver protocol

Accepted:

- an open functional protocol with optional abstract categories;
- interface, capabilities, initialization, advance, checkpoint, restore, and cleanup;
- private solver sessions and no direct shared-state mutation;
- typed effects committed by ProcessBigraphs;
- scientific algorithm/configuration in the component declaration; and
- stable declaration fingerprints excluding live memory identity.

## Interview 5 — time and orchestration

Accepted:

- exact ProcessBigraphs semantic boundaries;
- solver-owned internal timesteps, events, subcycles, and kernels;
- exact `Advance(from, to, trigger)` requests;
- `Every`, `At`, `On`, `After`, iteration, and adapter wakeups;
- atomic boundary visibility;
- exact logical time and checked adapter conversion; and
- no universal optimistic rollback engine.

## Interview 6 — hierarchy and naming

Accepted:

- lexical hierarchy with private internals and explicit exports;
- reusable repeatedly mounted definitions;
- mount-chain semantic identity and no ordinary `..` traversal;
- preserved hierarchy with flattening origin maps;
- one model category for closed and open composites; and
- deterministic dynamic-template instance identities.

## Interview 7 — validation and diagnostics

Accepted:

- immediate local errors and temporarily incomplete builders;
- accumulated structured finalization diagnostics;
- stable diagnostic codes and author-facing locations;
- phased validation with dependent-error suppression;
- normalize, validate, then freeze;
- explicit requirement profiles; and
- no environment warning in semantic fingerprints.

## Interview 8 — lowering and reproducibility

Accepted:

- the semantic model as author-facing truth;
- pure deterministic backend-independent lowering;
- complete origin maps;
- separate semantic, IR, plan, problem, and checkpoint identities;
- explicit stable identities for portable callables;
- layered format versions and explicit migrations; and
- semantic rather than syntactic serialization round trips.

## Interview 9 — dynamic structure

Accepted:

- typed declarative structural effects;
- semantic-boundary-only topology changes;
- atomic numeric and structural transactions;
- immutable definitions and mutable runtime instances;
- deterministic runtime identity;
- store-owned state transfer;
- explicit solver-session replication lifecycle;
- declared templates;
- fail-closed conflicts and dangling references; and
- no universal graph-rewriting language in the ordinary Phase 16.HC API.

## Interview 10 — models, problems, and experiments

Accepted:

- separate reusable model, simulation problem, and ensemble/run concerns;
- typed parameter handles;
- distinct model constants and run parameters;
- exact override bindings rather than recursive dictionary merge;
- problem-owned initial conditions and interventions;
- semantic observables separated from recording and sinks;
- explicit observation timing;
- problem-owned replayable randomness;
- applicable SciML problem/remake/ensemble conventions; and
- layered problem and run identity.

## Interview 11 — authoring surface

Accepted:

- ordinary Julia `compose` as the primary entry;
- honest builder `!` operations;
- explicit semantic names and typed handles;
- relationship-style connections;
- mount-based hierarchy;
- ordinary Julia control flow and collections;
- optional mechanically transparent macros only;
- no required full `@compose` DSL in Phase 16.HC;
- domain DSL ownership outside ProcessBigraphs;
- strong model display and inspection;
- one small vocabulary; and
- raw IR as an internal/expert boundary.

## Interview 12 — ecosystem and arbitrary solvers

Accepted:

- a small protocol core;
- explicit adapter values and dispatch;
- Julia package extensions;
- declarative narrow capabilities;
- an adapter conformance kit;
- contract views rather than runtime internals;
- explicit representation and transfer negotiation;
- no forced monolithic ODE;
- semantic solution indexing where applicable;
- global registries only for bounded codecs;
- progressive component/adapter tiers;
- contextual failure preservation;
- independently versioned adapter contracts; and
- clean ProcessBigraphs, solver, CPM, and scientific-model ownership.

## Consistency correction — SciML dependency

Repository inspection showed that the provisional recommendation to make SciMLBase a hard
dependency contradicted the already qualified solver-neutral extension boundary. The owner
accepted the correction:

- ProcessBigraphs core retains no hard SciML dependency;
- SciMLBase and CommonSolve remain weak extension triggers;
- real solver integration remains first-class and tested;
- wrappers may satisfy actual SciML subtype requirements where needed; and
- non-SciML adapters remain independent.

## Interview 13 — execution and performance

Accepted:

- deterministic staged dataflow;
- semantic publication boundaries independent of tasks;
- immutable parallel inputs and private effect buffers;
- canonical commit order;
- explicit update laws and deterministic profiles;
- solver-owned internal parallelism;
- asynchronous completion handles;
- typed buffer ownership;
- explicit transfer operations;
- distinct cache scopes;
- conservative initial planning;
- execution policy that preserves semantics;
- semantic profiling;
- atomic stage failure;
- explicit coupling as the Phase 16 default;
- capability-gated implicit regions; and
- communication intervals distinct from numerical timesteps.

## Final interview — Phase 16.HC

Accepted:

- a mandatory specification-first 16.HC gate before 16.I;
- the current uncommitted implementation remains a research spike;
- specification and public API freeze before code;
- staged implementation before scientific migration;
- `compose` as the complete ordinary Julia API;
- a compatibility audit for prior admitted composition surfaces;
- a small public allowlist;
- frozen differential fixtures;
- smallest-to-largest migration;
- restricted rather than abolished raw IR;
- one production authoring authority after each cutover;
- diagnostic and origin-map qualification;
- independent adapter qualification;
- optional SciML extension qualification;
- executable documentation;
- stage-separated performance evidence;
- clean independent package evidence; and
- explicit exclusions preventing macro, solver, analysis, and kernel scope creep.

## Final disposition

Decision 0040 and
[`process-bigraph-high-level-authoring-semantics.md`](../../spec/process-bigraph-high-level-authoring-semantics.md)
are the consolidated authority. The specification pass changes no implementation or prior
qualification claim. The separately authorized implementation and migration are now qualified by
the Phase 16.HC audit, checker, and content-addressed evidence record.
