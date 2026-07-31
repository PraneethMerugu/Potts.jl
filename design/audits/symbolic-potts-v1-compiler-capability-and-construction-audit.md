# Symbolic Potts V1 Compiler Capability and Construction Audit

Date: 2026-07-30

Status: implementation-blocking technical audit; no production implementation is authorized by
this document

## Purpose

This audit answers two questions:

1. What complete set of compiler capabilities is required by the accepted Symbolic Potts V1
   product?
2. What compiler construction is strong enough to support that product without turning the
   current Wortel, Merks, and focal-point-plasticity implementations into permanent architecture?

The quality target is the standard demonstrated by mature SciML compilers: a rich domain model,
explicit intermediate representations, public and private boundaries, analyzable semantics,
inspectable lowering, controlled specialization, conventional SciML integration, and performance
claims backed by focused evidence.

This audit does not change the accepted product. It tightens the implementation interpretation of:

- [`spec/symbolic-potts-v1.md`](../../spec/symbolic-potts-v1.md);
- [`spec/symbolic-potts-v1-consolidation.md`](../../spec/symbolic-potts-v1-consolidation.md); and
- [`spec/symbolic-potts-v1-architecture-redirection.md`](../../spec/symbolic-potts-v1-architecture-redirection.md).

The architecture-redirection contract remains authoritative where the documents overlap.

## Executive finding

The product architecture is strong enough to implement, but the current compiler construction is
not.

The present branch has already proven valuable authoring, scientific, stochastic, and integration
semantics. It has also produced a useful seed for typed proposal expressions. However, the
implementation still compiles through mechanism symbols, built-in biological plans, a
mechanism-shaped central program, mechanism branches in the proposal loop, and mechanism branches
in end-of-MCS execution. It is therefore a scientifically useful prototype, not the general V1
compiler.

The recommended compiler is:

```text
PottsSystem + Symbolics expressions + typed Potts statements
    │
    ▼
FrozenSourceGraph
    public identities, hierarchy, source, provenance, registry snapshot
    │
    ▼
NormalizedTermGraph
    non-parametric host DAG; canonical operations and explicit references
    │
    ▼
AnalyzedTermIR
    type, shape, units, role, reads/writes, footprint, stage, effects, RNG,
    checkpoint, replay, engine/backend capability, diagnostic provenance
    │
    ▼
DescriptorCandidates
    typed scientific descriptors and static expression evaluator candidates
    │
    ▼
DescriptorGroups + StateLayout + WorkspaceLayout
    repeated instances are data; distinct execution structures are types
    │
    ▼
ExecutionPlan
    closed stages, schedule, checkerboard coloring/conflicts, transactions,
    equation boundaries, observations, backend kernels
    │
    ▼
CompiledPottsProgram
    immutable, unit-free, registry-free, Symbolics-free, backend-adaptable
```

The host graph must be deliberately non-specializing and data-oriented. The device boundary must
be deliberately concrete and typed. This separation is the central compiler invariant.

The current recursive typed expression seed may survive only on the device side after grouping.
It must not remain the host analysis IR, and statement occurrences must not be stored in one
ever-growing heterogeneous tuple.

MetaTheory.jl is not recommended as a V1 dependency or compiler foundation. It may later be useful
as an experimental, host-only equality-saturation optimizer after the baseline compiler and cost
model exist. It must never own semantic analysis, resource inference, scheduling, stochastic
identity, relationship transactions, or device execution.

## Audit basis

### Repository evidence

The audit inspected:

- completion and qualified IR in `src/completion`;
- compilation and lowering in `src/compiler`;
- the current program and runtime in `lib/CorePotts/src/program/v1.jl`;
- the visible Wortel, Merks, and focal fixtures;
- current runtime, checkpoint, inspection, and integration tests;
- the accepted specifications and owner interviews; and
- the previous engine cloned read-only in a temporary directory.

The previous engine was used only to recover portable execution lessons. It was not treated as a
behavioral oracle or a migration target.

### Primary external references

The construction recommendations were compared with:

- [ModelingToolkit internal architecture](https://docs.sciml.ai/ModelingToolkit/v11.10/internals/);
- [ModelingToolkit composition](https://docs.sciml.ai/ModelingToolkit/stable/basics/Composition/);
- [ModelingToolkit code generation](https://docs.sciml.ai/ModelingToolkit/stable/API/codegen/);
- [Symbolics function construction](https://symbolics.juliasymbolics.org/stable/manual/build_function/);
- [RuntimeGeneratedFunctions](https://docs.sciml.ai/RuntimeGeneratedFunctions/stable/);
- [Catalyst core API](https://docs.sciml.ai/Catalyst/stable/api/core_api/);
- [SciMLBase initialization and solve interface](https://docs.sciml.ai/SciMLBase/dev/interfaces/Init_Solve/);
- [Julia performance guidance](https://docs.julialang.org/en/v1/manual/performance-tips/);
- [TermInterface](https://docs.sciml.ai/TermInterface/);
- [KernelAbstractions quick start](https://juliagpu.github.io/KernelAbstractions.jl/stable/quickstart/);
- [AcceleratedKernels performance guidance](https://juliagpu.github.io/AcceleratedKernels.jl/stable/performance/);
- [CUDA kernel programming requirements](https://cuda.juliagpu.org/stable/development/kernel/);
- [Adapt](https://github.com/JuliaGPU/Adapt.jl);
- [Atomix](https://juliaconcurrent.github.io/Atomix.jl/dev/);
- [MetaTheory documentation](https://juliasymbolics.github.io/Metatheory.jl/dev/);
- [MetaTheory e-graphs and equality saturation](https://juliasymbolics.github.io/Metatheory.jl/dev/egraphs/);
- [MetaTheory repository](https://github.com/JuliaSymbolics/Metatheory.jl); and
- [Equality Saturation for Optimizing High-Level Julia IR](https://arxiv.org/abs/2502.17075).

ModelingToolkit explicitly treats its internal transformation structures as unstable. PottsToolkit
should imitate the architectural separation, not depend on ModelingToolkit's private compiler
types. Current ModelingToolkit/Symbolics source also demonstrates two techniques that should be
adopted directly in spirit: non-specializing host compiler boundaries and non-parametric option
containers that avoid recompilation for incidental keyword/type variation.

## Current implementation findings

### What is worth preserving

The branch contains several good seeds:

- `QualifiedStatement` preserves qualified identity, schema version, source, provenance,
  normalized payload, type, shape, units, conversion, accesses, resources, effect, bound,
  lifecycle, random operations, phase, ordering, engine admission, and lowering identity.
- `ProgramLiteral`, `ProgramScalar`, `ProgramCall`, and `ProgramDraw` establish the correct
  principle that the executable contains neither Symbolics values nor host closures.
- Operation identity in `ProgramCall` is statically dispatchable.
- Semantic RNG operations are assigned explicit identities.
- The public compiler/runtime split, parameter manifest, fingerprints, problem/integrator flow,
  checkpoint surface, and inspection selectors are useful foundations.
- Wortel, Merks, and focal fixtures expose the actual scientific demands that the general
  architecture must satisfy.

These pieces should be extracted and generalized, not discarded indiscriminately.

### Wrong abstractions that must not survive

#### The central program is shaped like the proof models

`CompiledPottsProgram` directly contains:

- volume tables;
- contact tables;
- connectivity kinds;
- activity;
- field;
- history;
- elongation;
- relationships; and
- named observation variants.

This violates the accepted rule that CorePotts knows how to execute typed CPM programs but does not
know which biological mechanisms exist.

#### Lowering is mechanism-driven

`_lower_core_program` switches on mechanism symbols including `:volume`, `:contact`, `:activity`,
`:chemotaxis`, `:relationship`, and `:elongation`. Separate functions lower one activity plan, one
field plan, one history plan, one elongation plan, and one relationship plan. This makes each new
mechanism a compiler edit and usually a CorePotts edit.

The registered-statement path is also constrained to return a built-in V1 statement. That is a
normalization hook into a closed biological simulator, not the accepted external descriptor
boundary.

#### Execution is mechanism-driven

The proposal loop directly calls volume, contact, activity, chemotaxis, relationship, and
elongation delta functions. Commit and after-MCS logic directly branch on activity, history, field,
and relationship plans.

These branches make the current implementation fail the decisive extension test:

> A downstream package cannot add a new Hamiltonian term with auxiliary state without changing the
> central program, proposal loop, state/checkpoint code, or engine.

#### The expression representation is only half-general

The recursive typed expression representation has good device-side properties for a small number
of terms. In its current use, however:

- every structurally different expression produces a different recursive Julia type;
- every statement occurrence is placed in a heterogeneous tuple;
- tuple recursion makes specialization depth grow with occurrence count;
- associative calls are folded into left-deep trees;
- operation schemas are a central allowlist;
- a symbolic field reference is lowered to a `Symbol` literal;
- error checks remain in the device-intended evaluator; and
- bounded reductions, general state reads, declared relations, and external operations are not yet
  represented by a complete typed protocol.

This is an acceptable code-generation seed, not an acceptable host IR or finished device IR.

#### Portability is not implemented

The current compiler admits only `CPUBackend`, and the current checkerboard engine is a scalar
host loop. KernelAbstractions, AcceleratedKernels, Adapt, Atomix, portable workspaces, and backend
extensions have not yet been restored as the execution boundary.

#### Hot paths contain known scalability failures

Examples include:

- whole-relationship scans during a local focal energy delta;
- copying complete relationship state during an accepted copy;
- dynamically allocating request vectors;
- allocating field scratch on every MCS;
- dynamic sets and vectors in connectivity checks;
- broad whole-cell scans for geometric quantities; and
- named observation dispatch in the runtime.

These are prototype algorithms and cannot define V1 descriptor semantics.

## Complete compiler capability matrix

The following capabilities are required before the compiler can be considered complete. “Host
artifact” means immutable compiler data, not public runtime state. “Executable artifact” means
unit-free concrete data admitted by CorePotts.

| Area | Required capability | Host artifact | Executable artifact | Decisive gate |
|---|---|---|---|---|
| Identity | Stable qualified identities through hierarchy, flattening, diagnostics, and indexing | source graph and provenance chain | compact stable IDs where execution needs them | composed systems preserve unique inspectable identity |
| Domain model | Typed Potts statements remain distinct from ordinary equations | qualified statement records | term/process/observation descriptor groups | no fake ODE or opaque metadata encoding |
| Symbolics | Public Symbolics tree is canonical through completion | normalized expression DAG | none | no Symbolics value crosses into CorePotts |
| Expression typing | Infer exact result type, scalar/array shape, and context legality | per-node type/shape facts | concrete evaluator result type | invalid mixed shapes fail at source expression |
| Units | Preserve declared units and exact reference conversion | unit constraints and conversion plan | unit-free scalar/buffer data | dimensional errors fail before descriptor construction |
| Parameters | Prove structural versus runtime role | parameter-role manifest | dense runtime parameter buffers and structural constants | runtime update cannot change schedule/layout/code |
| Purity | Reject mutation, hidden effects, exceptions, dynamic calls, and unbounded work | operation schema and purity facts | device-valid operation tags only | external operation cannot bypass schema |
| State | Merge universal and open auxiliary state requirements | state schema with ownership/persistence | typed state blocks/grouped slots | external state adds no central runtime field |
| Workspace | Derive bounded reusable workspace and lifetime | workspace schema and liveness | preallocated adapted workspace blocks | warmed stages allocate zero host heap |
| Resources | Infer reads, writes, snapshots, ownership, and atomic/reduction policy | resource graph | compact resource handles and policies | checkerboard admission derives from facts |
| Locality | Derive bounded spatial and relational footprints | symbolic footprint algebra | offset/incident handles and radii | local term cost is independent of lattice size |
| Spatial relations | Support named, per-role relations and explicit neighborhood semantics | canonical relation definitions | adapted offset tables/stencils | proposal/contact/query/field/conflict relations remain distinct |
| Topology | Support boundary and dimensional semantics without hard-coded 2D assumptions | topology plan | concrete topology descriptor | every claimed dimension/backend compiles |
| Scientific taxonomy | Distinguish Hamiltonian, drive, constraint, modifier, process, and observation | category fact | stage-specific descriptor group | directional terms are never silently energy |
| Hamiltonian | Compute local before/after energy difference over a proven affected region | energy-region plan | local evaluator | delta matches total-energy recomputation |
| Effects | Preserve pure-read, accepted-copy, synchronous, and ordered-batch effects | effect and bound facts | request/effect descriptor | effect count and touched set are bounded |
| Stages | Map public protocol onto one closed stage taxonomy | stage dependency graph | fused/unfused execution schedule | no external stage or second scheduler |
| Ordering | Resolve dependencies and deterministic tie-breaking | partial-order analysis | total stage/group order | reorder is reflected in fingerprint |
| RNG | Assign stable operation, stream, invocation, and draw identities | RNG-site manifest | compact semantic addresses | same-engine replay and stream isolation |
| Proposal protocol | Generate, evaluate, resolve, and commit proposals with explicit snapshots | proposal protocol plan | sequential/checkerboard kernels | engines share descriptors, not authoring paths |
| Checkerboard | Derive coloring and residual conflict resolution from all footprints | conflict graph and coloring plan | colors, priorities, claims, selections | winner independent of device completion order |
| Reductions | Select exact atomic, deterministic grouped, or exclusive-owner strategy | reduction plan | AK/KA/Atomix operation and buffers | promised replay has specified order |
| Relationships | Snapshot reads, incident indexing, bounded requests, validation, rollback, commit | relationship schema and transaction plan | typed edge state/index/request buffers | no whole-graph proposal scan |
| Lifecycle | Retire/create entities through bounded deferred publication | lifecycle transaction plan | requests and commit kernels | generation and endpoint integrity preserved |
| Fields/equations | Partition CPM kernels from host equation integration | equation-process plan | CPM coupling ports/buffers only | external solver is never called in device kernel |
| Observations | Analyze cadence, reads, reductions, saved shape, and indexing | observation plan | descriptor groups and save buffers | new observation adds no central `isa` branch |
| Initialization | Validate and lower symbolic initial state with isolated RNG identity | initialization plan | concrete initial state and initialization kernels | initialization draw changes do not perturb dynamics |
| Checkpoint | Reconstruct logical state recursively at settled boundaries | checkpoint schema | descriptor-declared codecs for logical blocks | no workspace/kernel/registry/Symbolics serialization |
| Replay | State exact, logical-portable, or statistical replay scope honestly | replay report | continuation counters and configuration identity | cross-backend equality is never implied accidentally |
| Backend legality | Prove concrete storage, dispatch, bounds, math, and operation support | backend capability report | adapted isbits/concrete descriptors and buffers | no dynamic dispatch or host fallback in device code |
| Adaptation | Recursively adapt program/state/workspace through public protocols | adaptation plan | backend-native arrays and values | round-trip state meaning survives adaptation |
| Inspection | Preserve source-to-descriptor trace and explain every choice/rejection | qualified reports | compact runtime report IDs | errors identify source statement/expression |
| Serialization | Canonicalize semantic, completed, and executable identities | canonical host encoding | executable fingerprint | dictionary or traversal order cannot alter identity |
| Extensibility | Admit registered host semantics and external concrete descriptors | frozen versioned schema | grouped external descriptor type | independent module passes with zero Core edits |
| Specialization | Bound compiler work by occurrences `N` and execution structures `G` | group keys and specialization report | one evaluator/kernel family per group | fixed-`G` growth does not deepen tuple types |
| Performance | Plan trackers, layouts, workspaces, and kernels explicitly | cost/storage/kernel reports | KA/AK kernels and persistent buffers | hot cost follows declared local footprint |
| Failure model | Aggregate independent host errors; avoid device exceptions | structured diagnostic set | status/request buffers where runtime failure is possible | invalid runtime parameter fails before launch |
| SciML | Respect `compile`, problem, `init`, `step!`, `solve!`, solution, remake | Potts-owned problem/integrator plans | CorePotts executable and state | solve never recompiles |
| ProcessBigraphs | Derive typed whole-MCS component ports and atomic publication | component manifest | settled state exchange only | CorePotts remains free of ProcessBigraphs |

## Recommended IR family

### 1. `FrozenSourceGraph`

This layer freezes the completed public model without compiling it.

It owns:

- qualified identity and namespace;
- source hierarchy and provenance;
- statement/equation/variable/parameter identities;
- canonical registry snapshot;
- declared relations, protocols, state, observations, and external IO; and
- links back to public objects for diagnostics and symbolic indexing.

It must not select engine, backend, scalar type, layout, or RNG seed.

### 2. `NormalizedTermGraph`

This is the first true compiler IR.

It should be a host-only indexed DAG whose node and edge containers do not encode whole model
structure in Julia type parameters. Compiler passes should accept it behind function barriers and
use `@nospecialize` where concrete source payload types would otherwise multiply method instances.
It is lowered private compiler data, not a second public symbolic algebra or an authoring format;
Symbolics remains the sole canonical expression tree at the public and completed-system boundary.

Each expression node requires:

- stable node ID;
- canonical operation ID and schema version;
- ordered operand IDs;
- source expression/provenance ID;
- literal, variable, parameter, proposal-context, state, relation, or draw payload;
- declared versus inferred type/shape/unit slots; and
- canonical serialization key.

The graph may use ordinary host dictionaries during construction. Those dictionaries are never
part of the executable.

Normalization is not unrestricted algebra. It may:

- normalize namespaces and references;
- flatten semantically associative source forms only into an ordered n-ary representation;
- canonicalize literal and parameter representation;
- intern repeated pure subexpressions where identity is irrelevant;
- preserve explicit stochastic operation identity;
- preserve reduction order unless the semantic/replay contract permits reassociation; and
- reject unsupported operations before device lowering.

It must not use mathematical commutativity to reorder floating-point expressions by default.

### 3. `AnalyzedTermIR`

Analysis facts should be attached by node/record ID in explicit tables rather than accumulated in a
single highly-parametric record.

Required fact domains are:

- result type and shape;
- dimension/unit and reference conversion;
- parameter role;
- purity and totality;
- state/resource reads and writes;
- spatial/relationship locality;
- effect class and emission bound;
- semantic category;
- stage and dependency;
- stochastic sites;
- checkpoint participation;
- engine/backend capability with reasons; and
- source diagnostic chain.

Passes must either produce a complete fact or a structured rejection. “Unknown” cannot silently
be interpreted as safe.

Analysis is a monotone fact computation where possible, but it is not equality saturation. A
small explicit fixpoint is appropriate for mutually dependent facts such as resource access,
locality, and capability.

### 4. `DescriptorCandidate`

A descriptor candidate is the boundary between scientific semantics and execution strategy.

It should name:

- the term/process/observation category;
- the evaluator structure;
- instance data schema;
- auxiliary state and workspace blocks;
- resource footprint and access policy;
- stage participation;
- request/effect type and bound;
- supported engines/backends;
- checkpoint/adaptation hooks; and
- source IR identities.

Built-in and registered statements must reach this same boundary.

### 5. `DescriptorGroup`

Descriptors are grouped by concrete evaluator and execution strategy. Repeated instances with
different coefficients, kinds, parameter slots, targets, or relation handles are stored as data in
backend-compatible buffers.

A useful conceptual shape is:

```julia
struct DescriptorGroup{Strategy, InstanceBuffer, StateHandle, WorkspaceHandle}
    strategy::Strategy
    instances::InstanceBuffer
    state::StateHandle
    workspace::WorkspaceHandle
end
```

This is illustrative, not a frozen public name.

The group protocol should dispatch on concrete descriptor/group types. The central executor should
only ask generic questions such as:

- which stage does this group enter?
- what resources and footprint does it use?
- how is proposal contribution evaluated?
- what bounded requests does it emit?
- how is a stage applied?
- how is its state/workspace adapted and checkpointed?

It must never ask whether the group is activity, chemotaxis, elongation, or focal adhesion.

### 6. Static expression evaluator groups

The ordinary expression escape hatch should be a grouped static evaluator, not a runtime bytecode
interpreter.

The safe V1 construction is:

- normalize an expression into the host DAG;
- lower supported operation nodes to concrete operation-tag types;
- separate structural expression shape from instance values;
- construct one concrete evaluator type per distinct lowered structural shape;
- group instances sharing that shape;
- store coefficients, parameter slots, state handles, relation handles, and other varying values
  as group data; and
- evaluate with fully resolved dispatch inside the KA kernel.

Expression structure may therefore contribute to `G`, the number of execution strategies. It must
not contribute once per repeated statement occurrence.

The compiler should balance associative expression trees or use a bounded n-ary typed node so that
one long sum does not produce pathological recursive depth. A specialization report must show the
number of structural evaluator groups and their node counts.

External scalar operations require a versioned host schema and a device-valid operation tag with
methods for:

- type/shape/unit inference;
- purity and resource inference;
- backend capability;
- canonical serialization; and
- concrete evaluation.

An external operation that cannot produce those proofs is rejected.

### 7. `ExecutionPlan`

The execution plan owns:

- the closed stage schedule;
- group ordering and legal fusion;
- state and workspace layouts;
- relation/topology handles;
- incremental tracker plans;
- semantic RNG addressing;
- sequential proposal schedule;
- checkerboard footprint union, coloring, priorities, claims, and commit;
- deterministic reductions;
- bounded relationship and lifecycle transactions;
- equation-process boundaries;
- observation/save schedule;
- checkpoint/replay schema; and
- backend kernel inventory.

This is the only scheduling owner.

### 8. `CompiledPottsProgram`

The final program is one immutable general program. It contains concrete groups, layouts, schedule,
backend policy, compact manifests, and fingerprints.

It contains no:

- Symbolics or DynamicQuantities values;
- source ASTs;
- registry;
- dictionary;
- abstract descriptor collection;
- host closure;
- mechanism field;
- mechanism switch; or
- runtime opcode interpreter.

## Pass construction

Each pass should have a named input contract, output contract, invariants, diagnostics, and
complexity expectation.

### Pass 0 — Freeze and index

Freeze registry snapshot, qualify identities, index hierarchy, and establish deterministic source
order.

Gate: two equivalent construction orders produce the same semantic identity where ordering is not
semantic.

### Pass 1 — Normalize expressions and references

Convert public Symbolics operations and Potts-domain references into the host DAG through public
interfaces. Preserve source links.

Gate: no private ModelingToolkit or Symbolics concrete term type is referenced.

### Pass 2 — Infer type, shape, units, purity, and parameter role

Perform bottom-up inference and validate runtime versus structural roles.

Gate: every node has a proven result and no runtime parameter can alter generated structure.

### Pass 3 — Infer access, locality, effects, RNG, and stages

Compute resource facts and bounded footprints, assign stochastic identities, and map statements
onto the closed stage taxonomy.

Gate: checkerboard safety never depends on a user assertion.

### Pass 4 — Classify scientific semantics

Separate Hamiltonian terms, drives, constraints, modifiers, processes, and observations. For
Hamiltonians, derive the compiler-proven affected region used for before/after evaluation.

Gate: local delta equals total-energy recomputation for every built-in and external Hamiltonian
fixture.

### Pass 5 — Lower descriptor candidates

Invoke built-in lowering methods or frozen registered lowering schemas. Produce typed candidates,
never another biological statement.

Gate: the independent external fixture reaches a descriptor without a central allowlist edit.

### Pass 6 — Group and specialize

Canonicalize structural evaluator keys, group repeated instances, choose layouts, and report `N`,
`G`, instance counts, evaluator node counts, and expected kernel specializations.

Gate: increasing repeated instances at fixed `G` does not create deeper program or tuple types.

### Pass 7 — Plan state, workspace, trackers, and capacities

Merge compatible schemas, assign handles, allocate bounded buffers, and select incremental
trackers.

Gate: proposal and warmed stages have no host allocation and no local calculation scans unrelated
global state.

### Pass 8 — Plan schedule and transactions

Order stage entries, establish snapshots, fuse only proven-compatible stages, and construct
relationship/lifecycle transaction protocols.

Gate: stage/resource verifier accepts the plan; conflicting or cyclic requirements produce source
diagnostics.

### Pass 9 — Plan engine

For sequential, construct the scalar semantic order. For checkerboard, derive the maximum footprint,
coloring, residual resource claims, deterministic priority resolution, reductions, and commit
publication.

Gate: checkerboard conflict winners are invariant to execution order.

### Pass 10 — Prove backend legality and adapt

Select ordinary array, AK primitive, KA kernel, or measured backend-specific implementation in that
order. Validate concrete dispatch, storage, bounds, math, workgroup limits, and adaptation.

Gate: each claimed GPU backend compiles and runs the external descriptor fixture without host
fallback.

### Pass 11 — Construct kernels and host boundaries

Construct stage kernels and equation/observation host boundaries. RuntimeGeneratedFunctions or
Symbolics `build_function` may be used for admitted host equation work, not as an assumed device
strategy.

Gate: generated host callables and device kernels have explicit separate inventories.

### Pass 12 — Verify, fingerprint, and publish reports

Run independent plan verifiers, aggregate safe diagnostics, compute the executable fingerprint,
and construct inspection reports.

Gate: every runtime artifact traces back to qualified source identities and every structural
choice contributes to executable identity.

## Candidate code-generation strategies

| Candidate | Runtime quality | Compilation behavior | Extension quality | GPU portability | Disposition |
|---|---|---|---|---|---|
| Current recursive typed AST in one statement tuple | fast for tiny models | type depth and specialization grow with occurrences and expression shapes | central operation allowlist | plausible only after device cleanup | reject as whole-program architecture |
| Flat runtime opcode/DAG interpreter | bounded compile time | predictable | open operation tables are awkward on device | portable but branch/register/divergence cost | reject as primary runtime |
| One generated/RGF function per model | potentially fast on CPU | model-specific code and latency may be large | difficult world-age/cache ownership | not established for callable use inside GPU kernels | host equations only until proven |
| One fused bespoke kernel per complete model | highest theoretical fusion | invalidation and code-size risk | downstream changes force full recompilation | backend-sensitive | reject for V1 |
| Grouped typed descriptors plus static evaluator groups | fast and dispatch-resolved | proportional to distinct strategies `G` | external concrete types fit generic protocol | compatible with KA when device rules pass | recommended |
| MetaTheory equality-saturated evaluator extraction | potentially excellent optimized expressions | saturation/extraction cost must be bounded | rewrite theories are extensible | extracted result still needs a separate device lowering | optional future optimization only |

## MetaTheory.jl disposition

### What it actually offers

MetaTheory provides classical term rewriting, rewrite combinators, e-graphs, equality saturation,
analyses, and cost-based extraction for expression types that implement TermInterface. This is
genuinely relevant to compiler optimization.

It could eventually help:

- explore multiple algebraically equivalent forms of a pure local Hamiltonian expression;
- extract a form minimizing a device-aware cost model;
- apply domain-specific peephole rewrites without fragile manual rule ordering;
- discover common subexpressions or alternative reduction forms; and
- test whether a curated rewrite theory relates two pure expressions.

### What it does not solve

MetaTheory does not replace:

- type, shape, and unit inference;
- parameter-role proof;
- effect and stochastic analysis;
- state/workspace schemas;
- resource and footprint inference;
- checkerboard conflict construction;
- relationship and lifecycle transactions;
- stage scheduling;
- checkpoint/replay semantics;
- backend adaptation; or
- KA/AK device execution.

An e-graph represents equivalence alternatives. The Potts compiler still needs a typed semantic IR,
legality analysis, a cost model, extraction, descriptor lowering, and backend code generation.

### Why it should not be a V1 dependency

There are four concrete risks.

First, the current stable documentation describes MetaTheory 2.0, while the repository recommends
an in-development 3.0 branch and reports major implementation changes. A load-bearing compiler
dependency should not be adopted while its recommended public surface is moving this materially.

Second, saturation is intentionally nondestructive and may grow many equivalent terms. Its own
documentation requires iteration, time, and e-class limits and notes that termination is not
generally decidable. V1 normalization requires predictable near-linear compiler work.

Third, many tempting algebraic rules are not valid under the exact numerical contract. Floating
point addition and multiplication are not freely associative; changing reduction order can change
same-engine replay. Random draws, state reads across snapshots, relationship queries, and effects
must never be treated as ordinary equational terms.

Fourth, MetaTheory produces a host-side expression choice. It does not establish that the chosen
callable or expression can execute inside all claimed GPU kernels.

### Recommended policy

For V1:

- do not add MetaTheory to `[deps]`, `[weakdeps]`, or CorePotts;
- implement TermInterface-compatible traversal only where it improves interoperability without
  coupling public storage to MetaTheory;
- use explicit deterministic normalization rules for references, literals, identities, and safe
  structural forms;
- rely on Julia's compiler for ordinary scalar optimization after static lowering; and
- establish expression-group and generated-code benchmarks first.

After V1:

1. create a separate research benchmark or test environment;
2. restrict input to pure, total, unit-compatible, RNG-free local expressions;
3. define a small explicitly sound rewrite theory;
4. use a bounded saturation budget;
5. define a backend-aware cost model including operations, registers, branches, loads, and
   numerical-policy penalties;
6. compare compile latency, generated code, registers, and runtime against the baseline;
7. property-test extracted expressions over edge cases; and
8. adopt MetaTheory only if it produces a material measured win.

If adopted later, it should be a host-only optional optimizer. The normalized and analyzed IR
contracts must remain valid without it.

## ModelingToolkit and Symbolics boundary

PottsToolkit should integrate deeply through public system and expression contracts while keeping
compiler ownership explicit.

It should:

- implement the public ModelingToolkitBase system behavior required by the accepted spec;
- use public Symbolics/TermInterface traversal and registration;
- preserve hierarchy, namespacing, equations, IO, metadata, and symbolic indexing;
- use Symbolics code generation for host equation subsystems where appropriate;
- follow SciMLBase problem/integrator/solution conventions; and
- expose qualified inspection comparable to mature SciML systems.

It should not:

- subtype or store private ModelingToolkit IR structures;
- depend on undocumented transformation passes;
- encode CPM proposals as ODE equations;
- send arbitrary Symbolics graphs to GPU kernels; or
- allow ModelingToolkit or ProcessBigraphs to become a second scheduler for CorePotts stages.

Catalyst is the useful product analogy: retain a rich inspectable domain system and compile or
convert it into execution forms. The analogy does not imply copying Catalyst's reaction-specific
IR or numerical conversions.

## KernelAbstractions and AcceleratedKernels construction

KernelAbstractions is the portable kernel boundary, not the scientific IR.

The execution planner should choose:

1. ordinary array operations for cold host work;
2. AcceleratedKernels for portable scan, sort, reduce, accumulate, and index-oriented primitives;
3. KernelAbstractions kernels for CPM-specific proposal, footprint, request, tracker, and commit
   operations; and
4. backend-specific kernels only after measurement.

Adapt recursively moves program, state, and workspace data. Atomix is admitted for exact
commutative integer effects and carefully specified claims; it is not a substitute for ordered
multi-resource transactions. StaticArrays is appropriate for genuinely small fixed coordinates,
moments, tensors, and offset values. StructArrays is conditional on a measured layout win and
backend behavior.

KA kernels should specialize at the descriptor-group boundary. A kernel should not receive one
giant model-shaped type merely to expose every scientific term to inlining.

## Required compiler verification

### IR verifiers

Each layer needs an executable verifier:

- source graph has unique qualified identities;
- normalized graph has only registered operations and valid references;
- analyzed IR has no unknown safety fact;
- descriptor candidates satisfy state/workspace/access/stage contracts;
- groups contain homogeneous execution structure;
- schedule has one owner and no illegal cycle;
- checkerboard coloring and claims cover every exclusive footprint;
- executable contains only admitted concrete backend data; and
- fingerprint inputs cover every structural semantic choice.

Verifier failures are compiler defects and should include internal context. User model failures are
structured diagnostics tied to source.

### Semantic tests

Required exact or property tests include:

- expression normalization and inference;
- local Hamiltonian delta versus total-energy recomputation;
- drive/constraint/modifier acceptance semantics;
- tracker updates versus recomputation;
- relation and boundary behavior;
- semantic RNG address uniqueness and stream isolation;
- checkerboard conflict-order independence;
- deterministic request ordering, validation, rollback, and commit;
- checkpoint reconstruction;
- external state/adaptation/checkpoint recursion; and
- equation/observation boundary behavior.

A small scalar host evaluator for normalized IR is valuable as a test reference. It must remain
test-only or diagnostic-only and must not become the production runtime interpreter.

### Extensibility test

An independent test module must define:

- one new Hamiltonian term;
- one new symbolic operation or declared observation;
- one auxiliary state block;
- one reusable workspace;
- access and footprint rules;
- adaptation and checkpoint behavior; and
- a concrete descriptor/evaluator.

It must execute on sequential CPU and checkerboard CPU, and compile/run on every GPU backend whose
support level covers the used protocol. No CorePotts source, central union, central enum, proposal
loop, engine, checkpoint, or mechanism switch may change.

### Specialization tests

Benchmarks must vary:

- `N` at fixed `G`;
- `G` at fixed small `N`;
- expression node count;
- repeated parameter/data instances;
- number of state/workspace blocks; and
- number of stage groups.

Report:

- completion and compilation latency;
- method instances or equivalent specialization proxy;
- generated LLVM/native/device code size;
- allocations;
- first launch and warm launch;
- registers and local memory where available;
- synchronization and transfers; and
- runtime per proposal/MCS.

These are development reports and regression studies, not a fragile wall-clock CI oracle.

### Backend tests

For each claimed backend support level:

- package extension loads only with the backend;
- representative descriptor groups adapt;
- kernels compile without dynamic dispatch;
- a bounded stochastic run completes;
- no host fallback or per-stage transfer occurs;
- same-configuration replay matches the declared scope; and
- unsupported operations fail at compilation with a source diagnostic.

## Decisions that are now safe to freeze

The following should become implementation constraints before send-off:

1. The host analysis IR is an indexed, non-type-exploding DAG.
2. Symbolics remains canonical only through completion/host normalization.
3. Compiler passes use function barriers and avoid specializing on complete source payload types.
4. Device execution uses grouped concrete descriptors and static evaluator groups.
5. Repeated statement instances are data, not tuple elements or type parameters.
6. Expression shape may create a specialization group; each group is reported and benchmarked.
7. No runtime opcode interpreter is the primary execution path.
8. No RGF or `build_function` callable is assumed device-valid without a cross-backend experiment.
9. The external descriptor fixture lands before Wortel and Merks are rebuilt.
10. KernelAbstractions is the portable CPM-kernel boundary; AcceleratedKernels is used selectively.
11. A test-only scalar IR evaluator and total-energy reference are retained for compiler
    verification.
12. MetaTheory is excluded from V1 dependencies and may be evaluated later as a bounded host-only
    optimizer.

## Remaining design work before autonomous implementation

The phase does not need another broad product interview. It needs one bounded compiler
consolidation round that freezes:

1. the exact host node/fact table schemas;
2. the exact descriptor/group generic protocol;
3. the static expression evaluator representation;
4. state/workspace handle and layout rules;
5. relation semantics, especially `VonNeumann(r)` versus axial rays;
6. checkerboard footprint algebra and coloring/claim algorithm;
7. relationship indices and request buffer schemas;
8. backend support levels for phase exit; and
9. the independent external conformance fixture.

The highest-risk unresolved item is the static expression evaluator representation. It requires a
small disposable experiment comparing:

- recursive typed trees grouped by shape;
- a bounded n-ary typed tree;
- a compile-time unrolled static instruction representation; and
- generated host functions only as a non-device control.

The experiment must measure compilation growth and device compilation. It should not implement a
biological mechanism.

## Readiness conclusion

The branch should not resume mechanism implementation on the current foundation.

It should resume after the bounded compiler construction round and evaluator experiment. At that
point, the work can proceed autonomously architecture-first:

1. host IR and verifier;
2. descriptor/group/state/workspace protocols;
3. static evaluator and external fixture;
4. sequential reference;
5. portable checkerboard;
6. transactions and checkpoint recursion;
7. Wortel and Merks as complete visible integrations; and
8. normal functional, stochastic, specialization, and backend gates.

This is restrained enough for V1 and general enough to support the stated vision. It does not try
to reproduce all CPM literature, invent a general GPU language, or solve arbitrary symbolic
optimization. It builds the narrow compiler substrate that makes those future extensions possible
without turning today's proof models into tomorrow's core architecture.
