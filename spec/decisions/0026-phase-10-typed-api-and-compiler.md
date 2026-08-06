# Phase 10 PottsToolkit Typed API and Compiler Contract

Status: Accepted

Current disposition: superseded in part by [Decision 0044](0044-pre-g6-cohesion-and-mtk-hardening.md).
`PottsModel`, the old compiler boundary, and its public-surface choices are not current authority;
compatible extension and scientific intent survives.

Date: 2026-07-20

## Context

Phase 10 replaces the historical PottsToolkit authoring and compilation path with the Julia-native
Level 2 API that will support the Level 1 DSL in Phase 11. The replacement must preserve the
accepted CorePotts, SciML, RNG, lifecycle, numerical, and GPU contracts while removing dictionary-
and closure-first authoring, central concrete-type switches, private CorePotts calls, and the
MLStyle rule prototype.

Breaking changes are allowed before the paper API freeze. The replacement therefore optimizes for
one coherent final architecture rather than compatibility with unreleased interfaces.

## Decision

### Model, problem, and numerical ownership

- `PottsToolkit.PottsModel` is the immutable, reusable biological authoring model.
  `CorePotts.PottsModel` remains the lower-level scientific execution model; module qualification
  distinguishes the two concepts.
- There is exactly one runtime `PottsProblem`: the Phase 9 CorePotts/SciML problem. The friendly
  PottsToolkit constructor validates and lowers the Level 2 model and returns that problem rather
  than wrapping it in another problem type.
- A model contains scientific declarations. A problem adds the domain, initial state, fixed cell
  capacity, time span, and instance configuration. The algorithm is supplied to `init` or `solve`.
- Public models and fragments are persistent immutable values. Add, replace, remove, and `remake`
  operations return new values. A scoped transient builder is permitted only if measurement
  justifies it and it cannot escape as durable mutable model state.
- The model has one explicit real-number policy, with visible `Float32` default behavior. It applies
  to real scientific quantities, not counts, identifiers, Boolean values, or categorical state.
  Decimal literals normalize through that policy; hidden `Float32` casts are forbidden. Wider
  policies are explicit and backend-preflighted. Mixed real policies require an explicitly named
  advanced policy.
- Phase 10 has no authoring-time unit system or Unitful lowering. Model and rule quantities are
  plain numbers whose simulation meaning is documented. Optional units belong to Phase 11
  solution post-processing and cannot alter simulation semantics, fingerprints, RNG, kernels, or
  backend execution.

### Scientific identities, values, and components

- Biological identities such as `CellType(:Tumor)` and `Medium(:Extracellular)` are semantic,
  namespace-capable names, not runtime indices. The model can describe multiple named media even
  when current engine capability rejects their realization.
- Constructors accept homogeneous values and typed heterogeneous bindings. Pair syntax is
  ergonomic input only and normalizes immediately. Pair and dictionary order has no identity or
  precedence meaning; duplicate bindings are errors and missing bindings require an explicit
  default.
- Pairwise interactions use a typed `PairwiseLaw`-style abstraction with explicit symmetry or
  direction, medium participation, value policy, canonical identities, and missing-pair behavior.
  Missing pairs are errors unless a default is explicitly requested. Raw matrices require an
  explicit ordered identity list and remain a lower-level facility.
- A friendly component may expand into several properties, lifecycle policies, trackers, energies,
  rules, and capability requirements. `explain` exposes the expansion. Conflicts never resolve by
  declaration order or by an implicit "explicit beats supplied" rule; they require an explicit
  replacement or a scientifically defined merge.
- Every property declares its value type, ownership scope, initialization, invariant or valid
  range, lifecycle behavior, persistence participation, and optionality. Undefined storage is
  forbidden. Optionality must be explicit and have a GPU-compatible representation.

### Open Julia protocols and the CorePotts boundary

- A conforming public Level 3 CorePotts component may be composed directly into a Level 2 model.
  No adapter, registry entry, or PottsToolkit source edit is required. PottsToolkit may add a
  provenance view without changing the component's identity.
- Scientific conformance is defined by small ordinary Julia methods for semantic identity,
  validation, requirements, effects, reference behavior, lowering, and capabilities. Abstract
  supertypes may describe genuine scientific families but are not mandatory extension gates.
- Components explicitly report provided and required state, reads, writes, effects, RNG use,
  lifecycle participation, dimensional support, and backend capabilities. Unknown effects cannot
  silently claim portable compilation; an explicitly unsafe or backend-specific path may be
  offered when clearly reported.
- PottsToolkit lowers only through public CorePotts APIs. It never constructs private workspaces,
  invokes private kernels, or depends on internal storage fields. CorePotts may batch or fuse
  equivalent operations only when semantics, transactions, RNG, ordering, and provenance are
  preserved.
- Registration is required only for Level 1 spelling, durable semantic serialization, or a
  compatibility alias. Level 2 and Level 3 behavior uses ordinary dispatch. Registration cannot be
  a mutable global table that silently changes an already constructed model.
- Package dependency direction remains `PottsToolkit -> CorePotts`; satellites consume public
  model, solution, or inspection interfaces. CorePotts never imports PottsToolkit or switches on
  PottsToolkit component types.

### Composition and normalization

- A fragment is an ordinary immutable Julia value. Parameterized Julia constructors return
  fragments; a separate template language is not introduced where a function suffices.
- Fragments have hierarchical namespaces, explicit requirements and exports, and reusable
  parameter bindings. Private names remain local. Provenance records supplied and defaulted values
  and the originating fragment.
- Composition is order-independent outside explicit ordered phases. Equal declarations may be
  deduplicated; collisions otherwise require explicit `replace`, `remove`, rename, or a declared
  scientific merge. Import, dictionary, vector, and source order never decide a conflict.
- One typed immutable normalized model, built from ordinary Julia structs, is authoritative for
  validation, inspection, fingerprints, host reference evaluation, and CorePotts lowering. Stable
  accessors and report values are public; internal struct fields need not be compatibility
  promises.
- Normalized types use bounded specialization. Model size and every biological identity are not
  encoded into the top-level type. Hot compiled descriptors may use tuples and static values where
  measured. `Vector{Any}` and unbounded giant-tuple specialization are both rejected designs.
- Provenance retains semantic identity, namespace, fragment, source location when available,
  supplied/defaulted status, explicit replacements or merges, and the path into CorePotts.
  Diagnostic source locations do not affect semantic fingerprints.

### Validation, scheduling, and transactions

- Constructors validate local facts; normalization validates names, dependencies, effects, and
  conflicts; problem construction validates geometry, capacity, and initial state; backend
  preflight validates the selected algorithm, backend, device lowering, and resources.
  Independent diagnostics are accumulated when useful.
- Execution phases are open semantic values with declared order relationships, not a central
  switch. Dependencies derive a deterministic schedule. Missing requirements, ambiguous writers,
  and undeclared dependency cycles are errors.
- State-changing scientific behavior is a typed rule or event. General callbacks are for
  observation, logging, stopping, and explicit host-boundary behavior; they cannot silently become
  GPU stepping logic.
- Rules read the snapshot at their declared boundary and submit typed writes that commit together.
  Conflicting writes are errors unless an explicit combination law, such as addition, minimum, or
  maximum, defines the required algebraic behavior. Source order never resolves writes.
- Stochastic operations follow the accepted semantic RNG address using the seed, MCS, phase,
  operation and entity or proposal identities, and draw index. Unrelated composition changes do not
  perturb a stream. Global or hidden private RNG state is forbidden.
- Components declare 2D, 3D, or dimension-generic support. A 2D law is never silently generalized.
  Applicable first-party components support both 2D and 3D.

### Runtime state and storage

- Stable logical cell identity is distinct from a reusable storage slot. Fixed-capacity GPU storage
  supports creation and deterministic retirement without ordinary step-time host synchronization.
  Slot reuse fully initializes the new cell and cannot leak properties or identity.
- Capacity exhaustion is a clear error at the next safe reporting boundary and never triggers
  silent growth, overwrite, or CPU fallback.
- PottsToolkit specifies property meaning and access, not physical memory layout. CorePotts owns
  structure-of-arrays, `StructArray`, static-value, backend-buffer, and workspace choices.
  Extensions use public access and lowering protocols rather than field assumptions.

### Inspection, persistence, and identity

- Compact and `text/plain` `show` methods follow Julia conventions and never compile or allocate a
  backend. Stable inspection includes `explain`, dependency, provenance, validation, and backend
  reports. Reports are ordinary Julia values and can focus on one declaration.
- Structured diagnostics identify the scientific declaration, namespace and fragment, source when
  known, related declarations, violated contract, and a practical correction. Normal failures do
  not expose private compiler stacks as the primary explanation.
- Semantic manifests, runtime checkpoints, and reconstructable model serialization are distinct.
  Arbitrary Julia closures are never restored through `eval`. Full reconstruction is promised only
  by components that opt into the versioned serialization protocol; other components remain usable
  but are visibly non-portable.
- A semantic fingerprint covers normalized scientific meaning and excludes formatting, source
  paths, declaration order, and object identity. An execution fingerprint additionally includes
  algorithm, backend, real-number policy, RNG contract, relevant package versions, and compilation
  choices. Checkpoint identity also includes state and simulation time. Unstable object-memory
  hashing is forbidden.
- Compilation reuse is keyed by semantic and execution-relevant content. Changing only initial
  conditions normally reuses model lowering and kernels; affected work is invalidated when a
  structural dependency changes.

### Julia, metaprogramming, and GPU execution

- Rich host-side multiple dispatch resolves abstractions during construction and lowering. Hot CPU
  loops and GPU kernels receive concrete, inferred operations and data.
- Phase 10 requires no user macros. Phase 11 macros are thin syntax and source-location capture
  over ordinary builders. Generated functions are reserved for small type-dependent operations
  with measured value; AST rewriting is not an extension protocol.
- CorePotts may fuse, batch, and select backend layouts only under the declared transaction,
  numerical, RNG, and provenance contracts, with an unfused reference route for conformance.
- Unsupported GPU behavior fails complete backend preflight. There is no scalar indexing, hidden
  host transfer, partial CPU fallback, or host callback inside an ordinary device-resident step.
  GPU compatibility covers events, rules, reductions, property transactions, and lifecycle work,
  not only the main proposal kernel.

### Conformance and reference workloads

- Every portable component has constructor, validation, reference, lowering, lifecycle,
  fingerprint, provenance, CPU, Metal, and ROCm evidence. Successful kernel compilation alone is
  insufficient.
- Exact semantic state is compared exactly where promised. Floating reductions and stochastic
  trajectories use declared tolerances, invariants, and statistically justified ensemble tests;
  plausibility is not a correctness criterion.
- The five OpenVT reference-model categories are mandatory public-Level-2 conformance workloads:
  single-cell migration, chemotaxis in prescribed gradients, monolayer growth, differential-
  adhesion sorting, and elongation-driven angiogenesis. They are ordinary compositions with no
  runtime special cases. OpenVT schema compatibility is not claimed.
- Benchmarks separate construction, normalization, lowering, compilation, and warm execution and
  report allocations, MCS/s, proposal throughput, device memory, scaling, observations, and
  checkpoint cost on CPU, Metal, and ROCm with machine metadata.
- An external test module must define a miniature component, lower it without editing either
  package, execute it on required backends, and observe it in reports. Public-boundary, ambiguity,
  inference, dependency, and GPU-compilation checks accompany it.

### API shape and legacy removal

- PottsToolkit exports the coherent Level 2 authoring and common inspection surface, not a blanket
  CorePotts re-export. Advanced Level 3 and Level 4 use is explicit through `CorePotts`.
- Public names follow Julia conventions: scientific nouns for values and types, verbs for
  operations, and `!` only for mutation. Constructors infer only unambiguous representational
  facts. Scientific symmetry, identity, lifecycle, timing, and missing behavior remain explicit.
- Before the paper freeze there is one preferred spelling and no migration layer for obsolete
  unreleased APIs. Every public component documents meaning, literature convention, defaults,
  state requirements, timing, lifecycle, RNG, dimensions, backends, validation, and an executable
  example.
- Legacy is frozen when Phase 10 begins. After one replacement vertical slice passes reference,
  CPU, Metal, ROCm, residency, diagnostics, and performance gates, remaining library code and tests
  migrate through a capability ledger. The closure-first compiler, MLStyle path, dictionary/`Any`
  semantic storage, `LegacyPottsProblem`, and private CorePotts calls are then deleted in one
  explicit gate before broad component and reference-model expansion.
- Phase 10 is complete only when Level 2 is the sole PottsToolkit semantic path, required first- and
  third-party protocols work, all five reference workloads are expressible, lowering uses only
  public CorePotts, all required backends pass, legacy is absent, package tests use the replacement,
  and measured execution performance is preserved or improved. Phase 11 then supplies and refines
  the Level 1 DSL and solution-side units without introducing another semantic path.

## Consequences

Phase 10 is a replacement, not a compatibility wrapper. PottsToolkit becomes a Julian declarative
front end while CorePotts retains full independent scientific and execution use. The host interface
may be rich and extensible, but all device work is concrete, bounded, validated, and resident.

The early legacy-deletion gate limits the period in which two implementations coexist. The five
reference models validate breadth only after a smaller end-to-end slice proves the architecture.

## Migration Impact

The historical PottsToolkit authoring/compiler path is intentionally incompatible with this
contract. Required package code and tests migrate manually after the replacement vertical slice;
the old implementation is then removed without aliases or a user migration guide. Documentation
and tutorials migrate after the library and test surface is stable. No released API compatibility
commitment is affected because the paper API has not been frozen.

## Alternatives Considered

- Preserve the historical API and compiler behind adapters until the final release.
- Introduce a second PottsToolkit problem wrapper around the CorePotts/SciML problem.
- Require subtype hierarchies or a global registry for all extensions.
- Encode every declaration and identity into type parameters.
- Permit authoring-time Unitful quantities and device-side conversion.
- Resolve component and writer conflicts by insertion order or implicit precedence.
- Allow unsupported device operations to fall back silently to CPU.

These alternatives create duplicate semantics, invalid specialization, hidden scientific choices,
or nonresident GPU execution.

## Required Conformance Evidence

- The replacement vertical slice exercises model, problem, normalization, validation, reference
  evaluation, public lowering, stochastic rules, transactions, lifecycle, inspection, and all three
  required backends.
- A legacy-containment inventory and capability ledger prove that deletion loses no required
  behavior and that no production caller remains.
- External-component conformance proves dispatch-based extension without a compiler switch or
  mandatory registry.
- The five reference workloads use only public Level 2 and CorePotts interfaces.
- Performance evidence separates compilation from warm MCS execution and finds no material
  regression, hidden host work, scalar indexing, or device allocation.
