# LocalMath Direct Cutover

Date: 2026-08-22

Status: authoritative roadmap; implemented through LM-3B

## Decision

The repository now exposes the pre-release compiler-facing authoring and
execution package as `LocalMath.jl`:

> LocalMath expresses local scientific laws over typed spaces, fields, and
> relations, with explicit deterministic semantics for reduction,
> resolution, bounded collection, and ordered state transition on CPUs and
> GPUs.

This was a direct cutover, not a compatibility program. The earlier
execution work is the implementation foundation, but
`LocalWorksets`, `@localwork`, the authored route-symbol topology API, and the
`@port`/`emit`/`candidate` language are not retained as parallel public
surfaces.

The target hourglass is:

```text
Julia domain objects
Space / Field / Relation
          |
          v
@localmath or programmatic law constructors
          |
          v
one LocalLaw semantic IR
          |
          v
one private lowering and validated Plan
          |
          v
one prepared execution architecture
          |
          v
KernelAbstractions
          |
          v
CPU / advertised GPU backends
```

`LocalLaw` is a direct rename and strengthening of the existing `LocalWork`.
It is not a new object layered above `LocalWork`. There MUST NOT be both a
`LocalLaw` and a surviving `LocalWork` semantic authority.

## Authority and supersession

This document is authoritative for the next implementation order. It
supersedes the following portions of
[Typed LocalWork and CorePotts Adoption](localworksets-typed-language-and-core-adoption.md):

- package and module identity;
- the provisional `@localwork` authoring surface and public port vocabulary;
- user-authored route symbols, destination-count tuples, and topology wiring;
- the public names of local-work lifecycle values;
- Tranche 5 as the next immediate implementation step; and
- the Phase 8 final API-freeze order.

The earlier document remains authoritative historical evidence for completed
execution adoption, packed runtime state, validation, deterministic ordering,
KernelAbstractions execution, and Gate 8C.4's compiler-health finding.

This document also supersedes public-authoring and package-identity clauses in
[LocalWorksets Common Mathematical IR](localworksets-common-mathematical-ir.md),
while preserving its central decision: there is one common spatial/publication
IR and one execution architecture. `Space`, `Field`, and `Relation` strengthen
that IR's semantic fields; they MUST NOT create a second persistent
mathematical IR or another lowering pass.

All surviving CorePotts scientific contracts remain authoritative. This
cutover does not transfer Hamiltonian meaning, semantic RNG, Metropolis
acceptance, MCS scheduling, lifecycle transaction meaning, checkpoint
continuation, or domain capability claims into LocalMath.

## Research lineage and product position

LocalMath deliberately synthesizes established simulation-language ideas:

- Simit's typed sets, coordinate-free endpoint access, structure/behavior
  separation, and local-to-global assembly;
- Ebb's embedded relational kernels, domain libraries, functional key
  relations, grouped inverse queries, affine grid access, and phase checking;
- familiar Julia indexed equations and bounded local control; and
- the implemented LocalWorksets laws for deterministic reduction, resolution
  with evidence, stable bounded collection, ordered recurrence, multi-port
  publication, and finite sequence.

LocalMath is not positioned as a new calculus, a graph-analytics framework, a
general tensor compiler, or a universal simulation language. Tullio,
TensorOperations, OMEinsum, LinearAlgebra, and domain packages retain their
natural dense tensor, contraction, solver, and scientific roles.

The package's differentiating responsibility begins when local scalar or
fixed-size tensor evaluation publishes through typed relations and destination
contention affects correctness.

| Precedent | LocalMath adopts | LocalMath deliberately does not copy |
|---|---|---|
| Tullio | familiar indexed scalar/tensor expressions | ownership of general contraction or a second kernel scheduler |
| Simit | typed domains, relations, and local-to-global assembly | a closed standalone language or opaque global solver semantics |
| Ebb | relational locality, grouped queries, and phase checking | application-specific relation libraries in the compiler core |
| KernelAbstractions | portable launch and implicitly ordered backend execution | scientific semantics, publication semantics, selective events, or a scheduler |
| Current LocalWorksets | exact contention laws, packed state, validation, and one planned path | planner vocabulary as the ordinary authoring identity |

## Design-quality and implementation-difficulty policy

Implementation difficulty is a planning cost, not a reason to weaken the
scientific language, preserve obsolete ceremony, or expose compiler machinery
to users. A construct that belongs to the LocalMath mission and materially
improves the complete CPM, LBM, LSM, matrix-free FEM, deposition, graph-local,
or stencil witnesses remains in scope even when its exact analysis, lowering,
diagnostics, or GPU implementation is difficult.

The implementation MUST solve hard cases through principled typed semantics,
exact or conservative analysis, explicit boundedness, and inspectable
planning. It MUST NOT make a heuristic an authority for scientific meaning.
A heuristic MAY choose among already equivalent schedules; it may not infer
uniqueness, associativity, tie order, capacity, overflow, boundary meaning,
alias safety, or device legality. When a proof cannot be established, the
compiler rejects with a source-level explanation or requires an explicit
semantic declaration whose validity LocalMath can mechanically enforce.

The cutover may be revised for semantic incoherence, false scientific claims,
an unavoidable second authority, or an execution design that cannot preserve
the declared law. It is not revised merely because the correct implementation
requires substantial compiler work.

## Review committee disposition

Three independent reviewers audited this plan over three correction passes:

- compiler and Julia/API design;
- scientific semantics and GPU execution; and
- simplification, maintainability, and adoption.

The post-LM-1 roadmap review corrected four additional assumptions: current
KernelAbstractions provides implicit backend ordering rather than a portable
native event system; `ExecutionReceipt` must therefore describe logical
submission and settlement rather than selective provider completion; the
mathematical grammar must be tried privately across domains before the public
rename; and warm host receipt bookkeeping must be bounded and measured rather
than falsely claimed to allocate nothing.

All findings are incorporated into the normative design below. LM-0 and LM-1
are complete. Implementation resumes at LM-2A; later review gates judge live
evidence against this specification and may require either a richer primitive
or a smaller architecture, but never compatibility machinery.

The independent post-LM-1 roadmap re-audit and final three-perspective `PASS`
are recorded in the
[`Post-LM-1 Roadmap Review`](../design/evidence/localmath/post-lm1-roadmap-review.md).

## Baseline and inherited blocker

The current workspace contains the completed LM-1 stage-local compiler and
physical execution spine under `lib/LocalWorksets/src`. The current
`authoring/syntax.jl` is deliberately only a small bridge: `@localwork`
accepts one explicitly constructed typed `Stage`. It does not yet provide the
mathematical grammar described in this document. Earlier `@read`, `@axis`,
`@port`, `emit`, and `candidate` designs are historical input to LM-3A, not a
closed or implemented language.

At the repository level, `LocalWorksets` or `@localwork` appears in at least
89 Julia, TOML, Markdown, and benchmark files and more than 1,600 textual
occurrences. These counts define the rename scope; they are evidence, not a
license for blind replacement without semantic review.

Gate 8C.4 supplied the inherited compiler-health blocker: the former 13-stage
lifecycle initialization did not complete in its original ordinary optimized-
compilation window. LM-1 resolves that blocker with one scientific sequence,
stage-local concrete dispatch, and the explicit flagship authority replacement
below. The exact heterogeneous tuple representation was never frozen.

## Operational definition of locality

A LocalMath law has a finite typed source space, bounded or statically
analyzable reads, bounded publications through typed relations, bounded
planned workspace, and finite stage composition. `Local` means bounded
dependence and effects; it does not require short geometric distance. An
affine stencil, mesh incidence, graph edge, particle deposition key, and
packed runtime relationship may all be local under this definition.

Contention-aware publication is LocalMath's principal differentiator from
ordinary indexed-expression systems, not a minimum admission condition.
Pointwise and contention-free stencil laws remain first-class.

## Final public semantic profile

### Primary nouns

The ordinary public semantic vocabulary is intentionally small:

- `Space`;
- `Field`;
- `Relation`;
- `LocalLaw`;
- `Stage`; and
- `Plan`.

The usable lifecycle additionally includes a prepared execution value and a
logical execution receipt. The design does not enforce an arbitrary count of public
nouns or exports; it minimizes only concepts that users do not need.

Compiler and engine terms such as workset, fiber, inbox, message, port,
emission, lowering, mechanism, phase tuple, and workspace leaf MAY appear in
advanced inspection or implementation documentation. They are not the normal
scientific authoring language.

### Current exported surface

The implemented surface keeps ordinary authoring small:

```julia
export Space, Field, Relation, Collection, LocalLaw
export IdentityRelation, AffineRelation, FixedRelation, ProductRelation
export BoundaryRelation, RuntimeRelation, MaskedRelation, SelectedRelation
export InverseRelation, PackedRelation, compose
export @localmath
export prepare, execute!, waitall, workspace_requirements
```

`bind`, `plan`, `inspect`, `Allocate`, `MutableRelationStorage`, boundary
policies, explicit law constructors, `Plan`, `PreparedPlan`, and
`ExecutionReceipt` are public but qualified. `bounded_collect`, `@stage`, and
`@ordered` are reserved forms consumed by `@localmath`; they are not
independent exports.

The exact names receive a final source-level audit before freeze. Advanced
semantic constructors MAY be public but unexported:

```julia
LocalMath.unique(...)
LocalMath.reduce(...)
LocalMath.resolve(...)
LocalMath.collect_bounded(...)
LocalMath.ordered(...)
LocalMath.sequence(...)
```

Domain compilers such as CorePotts target these constructors directly.
Ordinary scientific authors primarily use `@localmath`.

### Lifecycle and runtime parameters

The ordinary public lifecycle is:

```julia
prepared = prepare(law,
    input => input_storage,
    output => output_storage,
    neighbors => neighbor_storage;
    backend, workspace, lease_capacity)
receipt = execute!(prepared; parameters = (;), dependencies = ())
wait(receipt)
```

This convenience composes the sole `bind`, `plan`, and `prepare` operations.
`bind` remains a structural lifecycle operation, not another semantic IR. It maps
the descriptors already stored by `LocalLaw` to topology and logical storage.
Direct arrays remain caller-owned and are neither copied nor adapted. A
qualified `LocalMath.Allocate` declaration may explicitly request cold
backend storage during binding; it is materialized through
KernelAbstractions before the canonical structural binding is constructed.
Planning, preparation, and execution never infer, initialize, copy, or allocate
scientific arrays. `LocalMath.storage(bound, descriptor)` retrieves the exact
bound Field, physical Relation storage, or `CompactedStorage` by semantic
descriptor identity.
Downstream packages may additionally define `bind(law, domain, state)` as a
concise domain-owned construction convenience; that method must produce the
same structural binding and adds no LocalMath domain adapter.
`Plan` owns validated topology, lowering, workspace requirements, numerical
policy, and specialization evidence. `PreparedPlan` owns concrete storage,
relation device views, workspace, provider state, and submission schema.
Every submission returns exactly one `ExecutionReceipt`. It records its
provider scope, monotonically increasing scope ordinal, exact device-resident
semantic status and publication-receipt references, dependency identities,
lease/generation identity, and source provenance. A provider scope is the
LocalMath-owned logical submission scope for one backend, device, and owner
task. Launches issued through it rely on the backend's KernelAbstractions
implicit ordering; KA exposes no portable queue identity. The receipt is a
bounded host handle and logical settlement record, not a claim that
KernelAbstractions supplies a portable native event.

An unresolved dependency is admitted only when it belongs to the same
provider scope and has an earlier ordinal. Implicit queue ordering establishes
the physical happens-before edge and device status references gate dependent
publication. A settled-success receipt is admissible from any scope. An
unresolved cross-scope receipt is rejected; the caller must explicitly wait
before submitting across that boundary. These rules make cycles impossible
without adding a scheduler or task graph.

A settled-failed dependency rejects before any launch. An unresolved
same-scope dependency that later fails suppresses every dependent publication
and records a dependency failure in the dependent receipt with predecessor
identity and provenance. Semantic failure does not poison the provider scope:
independent later submissions remain admissible, and a corrected retry is a
new submission. Provider failure alone poisons the entire scope.

`Base.wait(receipt::ExecutionReceipt)` is the sole single-receipt explicit
synchronization authority. It may
physically synchronize the cumulative provider tail, then resolves and
releases only the requested logical receipt and caches the scope's settled
ordinal. A later covered wait performs no redundant synchronization. The
exported `waitall(receipts...)` groups scopes by first occurrence,
synchronizes every required scope at most once, resolves and caches every
requested status, and only then reports the earliest failing receipt in the
original argument order. It never aborts merely because a later argument's
scope was settled first. Waits are idempotent. A provider failure poisons its
scope; semantic failures remain exact, cached, receipt-specific failures. No second event, selective
provider-completion claim, copied host-status authority, raw backend event, or
competing scheduler may live in `PreparedPlan`, CorePotts, an executor, or a
provider wrapper.

Runtime captures are classified exactly:

| Capture | Meaning |
|---|---|
| `Space`, `Field`, `Relation` | cold semantic descriptor evaluated once during law construction |
| isbits literal or immutable callable struct | concrete evaluator capture |
| per-execution scalar or small isbits record | explicit prepared submission parameter |
| mutable or non-isbits host object | rejected unless represented by a declared field/relation binding |

Runtime parameters are never inferred from free variables and are not embedded
into evaluator types merely because they appear lexically in `@localmath`.
They use one explicit declaration:

```julia
law = @localmath (
    i ∈ nodes;
    parameters = (Δt::Float32, threshold::Float32),
) begin
    velocity[i] = velocity[i] + Δt * force[i]
end

execute!(prepared; parameters = (Δt = 0.01f0, threshold = 2f0))
```

Programmatic construction uses `ParameterSchema((:Δt => Float32,
:threshold => Float32))`. `LocalLaw` owns this schema as semantic input names
and exact value types; `Plan` validates use and device legality;
`PreparedPlan` owns the fixed device argument layout; `execute!` accepts the
exact named tuple; inspection reports names, types, and specialization status.
Values are submission arguments, not specialization keys, and warm submission
performs no device transfer, relationship packing, or algorithmic-workspace
allocation. Host receipt/submission bookkeeping remains bounded and measured
under the LM-7 ceilings.

## Structural semantics

### Spaces

A `Space` is a typed finite index domain with a runtime extent and stable
semantic identity. It is not `Base.Set` and does not imply hashing,
deduplication, or unordered container semantics.

```julia
nodes = Space(Node, number_of_nodes)
springs = Space(Spring, number_of_springs)
```

Runtime extents MUST NOT be embedded into types unless they change generated
code. Space type parameters MAY encode semantic kind, dimensionality, and
small static structure.

Space identity is explicit and independent of the Julia variable name. Two
separately constructed spaces are not equal merely because their kind and
extent match. Identity and serialization preserve logical placement; epochs
and runtime extents remain values rather than type parameters.

### Fields

A `Field` declares value placement and exact element type on a space. Storage
binding remains a cold planning/preparation concern. A field descriptor MUST
NOT capture a host array into a device callable or create a runtime symbolic
lookup.

```julia
position = Field(nodes, SVector{3, Float32})
force = Field(nodes, SVector{3, Float32})
stiffness = Field(springs, Float32)
```

Cold `bind` associates logical fields with concrete CPU or GPU storage. The
planner validates shape and backend consistency and lowers device callables to
direct typed storage access.

Field identity is explicit and independent of a macro-local name. Binding
records alias identity and overlapping storage. A stage may read and publish
the same logical field only under the version and initialization semantics
defined below; undeclared overlapping fields reject.

### Relations

A `Relation` connects a domain space to a codomain space and provides
inspectable bounded-access evidence.

```julia
endpoints = FixedRelation(
    springs => nodes;
    degree = 2,
)

bound = bind(law, endpoints => connectivity)
```

The relation constructor above creates a semantic descriptor, not a storage
wrapper. The concrete connectivity participates in structural binding. A
convenience owned by a downstream domain MAY accept both values together, but
it must immediately produce this same descriptor-plus-binding pair; the
relation stored in the law never captures the host array as semantic state.

Every admitted relation provides the minimal semantic protocol:

```julia
domain(relation)
codomain(relation)
degree_bound(relation)
device_view(relation, binding)
```

Planning derives and inspects richer evidence where available:

- forward degree or emission-lane bound;
- inverse multiplicity bound;
- injective, surjective, bijective, or potentially contended status;
- canonical lane identity and order;
- coverage and zero/no-route behavior;
- immutable-schema versus runtime-mutating lifetime;
- exact, upper-bound, or opaque footprint strength;
- source and destination ownership;
- read halo and reverse/publication halo; and
- physical storage and device-view representation.

An extension-provided trait is not trusted admission evidence. Planning
consumes one sealed, package-owned evidence authority:

```text
relation representation + concrete binding
    -> LocalMath-owned structural/device validation
    -> RelationProof{Bound, Multiplicity, Coverage, Freshness, Ownership, ...}
    -> Plan
```

Package-owned static constructors mint proofs only after validating their
storage and representation. Extension relations may provide access/data
through the minimal relation protocol but cannot construct `RelationProof`.
Runtime relations receive device validation whose successful status gates all
dependent publication. Conservative evidence plans validation or a safe
contended algorithm; opaque evidence rejects only the operation that requires
the missing fact and reports that fact. A false degree, uniqueness, ownership,
or freshness claim therefore cannot authorize unsafe execution.

The initial complete relation family includes:

- identity relations;
- fixed-degree incidence relations;
- bounded packed relations;
- affine structured-grid relations;
- grouped inverse relations;
- bounded composed relations;
- runtime-key relations; and
- subset or active-selection relations;
- product/index spaces for lattice channels, element-local nodes, quadrature
  points, and fixed local tensor axes; and
- generic boundary relations for periodic mapping, exterior-value extension,
  masked incidence, strict interior access, and ghost regions.

The semantic interface is common; physical storage remains specialized. A
Cartesian stencil MUST NOT be materialized into generic CSR merely to satisfy
the relation abstraction. Mutable runtime relationship state MUST remain
canonical packed storage on every backend.

`RuntimeRelation` is the storage-free bounded ordinal address law used when an
evaluator supplies an `Int32` or `UInt32` destination key. Its cold schema is
domain, codomain, degree bound, key type, ownership, representation class, and
identity. It has no separate capacity: candidate capacity is derived from the
Stage source extent and law width, while key validity is derived solely from
the codomain extent. Key zero is absence; a participating nonzero key outside
the codomain fails device validation.

Mutable runtime incidence uses `PackedRelation`, not `RuntimeRelation`. Packed
device arrays, counts, active bits, relationship generations, and validation
status may change without rebuilding the plan or round-tripping through the
host, provided the cold bounds and identities remain valid. A `schema_epoch`
covers domain, codomain, degree bound, representation, ownership, and physical
binding identity; changing it invalidates prepared device views.
A `content_generation` covers warm entries, counts, active bits, and
relationship generations; it may advance during execution within planned
bounds. Device validation and admitted execution-receipt dependencies protect content
freshness without host replanning. `RelationProof` records the `schema_epoch`
and binding identity; a mismatch invalidates it. Warm validation receipts pair
the content generation with the exact execution dependency that validated it.

Domain packages SHOULD construct natural spaces and relations for ordinary
users. A mesh, lattice, or Potts author should not repeat low-level relation
construction for each law.

`compose(r₁, r₂, ...)` is the standard relational path operator, not a
dependent-indexing subsystem. Adjacent codomain/domain spaces must agree
exactly, the checked product of factor degree bounds must remain within the
reviewed static bound, and canonical lanes use mixed-radix factor order.
Composition owns no storage or freshness counter: planning seals the ordered
factor proofs, preparation builds an immutable tuple of existing relation
views, and every mutable factor contributes its ordinary generation/status
receipt exactly once. Endpoint traversal is expanded into the existing
bounded read path and therefore creates no executor, precompute kernel, or
unrestricted Field-indexing capability.

This operator is the normative representation for value-dependent scientific
paths whose intermediate values are themselves relations. In particular,
Potts ownership is a mutable degree-one `PackedRelation` from sites to cells,
cell kind may be a degree-one packed relation from cells to kinds, and cell to
relationship incidence is a bounded packed relation. Thus conventional
expressions such as `kind[ownership[x]]`, ownership after a neighbor offset,
and relationship payload after owner incidence lower to composed relations
plus ordinary `Access`. A new `IndexField`, opaque state view, or staging
precompute is forbidden when this algebra suffices.

Every bounded access sample exposes the canonical terminal endpoint ordinal
alongside value, presence, and boundary provenance. The ordinal is zero when
the path is absent. This is provenance already established by relation
traversal, not arbitrary random access; evaluators cannot use it to obtain an
unbound Field view. It lets domain compilers retain discovered site, cell,
edge, and relationship identities without duplicating mapping arrays.

### Sole semantic authority

The final semantic waist is a finite, nonempty tuple of stages. Each stage has
the local mathematical shape, and the law owns the one parameter schema shared
by those stages:

```julia
Stage{
    Source,
    Accesses,
    Publications,
    Evaluator,
    Control,
}

LocalLaw{Stages, Parameters}
```

- `Source` is a `Space` or selected/product subspace;
- each access references a logical `Field` through an admitted `Relation`;
- each publication references a destination `Field`, route relation, and
  complete publication-state law;
- `Evaluator` is an ordinary concrete callable; and
- `Control` owns selection, gate, and source provenance facts; and
- `Stages` is a concrete nonempty tuple whose order is the scientific order.

`Space`, `Field`, and `Relation` descriptors are stored directly in this
semantic declaration. A one-stage law uses a one-element stage tuple rather
than a different semantic type. Heterogeneous composition concatenates stage
tuples; it does not hide a second sequence IR inside the evaluator. Binding
maps descriptors to storage only in the bound, plan, and prepared lifecycle.
Preparation produces concrete relation device views. The syntax AST is
ephemeral frontend input and is erased when `LocalLaw` is constructed.

Authority replacement is exact:

| Current authority | Final owner |
|---|---|
| `items` | source `Space` or selected/product subspace |
| named read binding | `Field` plus access `Relation` |
| route symbol | concrete typed `Relation` |
| destination count | destination `Space` extent |
| output declaration | publication attached to destination `Field` |
| active selector | selected/subspace relation |
| work gate | explicit law or stage gate in `Control` |
| topology payload | validated prepared relation device view |
| semantic ID and order | named publication/order authority |
| submission `@value` | prepared runtime parameter schema |

No private conversion may reconstruct the old symbol-keyed reads, outputs,
routes, and destination-count topology as a semantic planning input. Private
physical arrays and relation views are permitted; the old semantic schema is
not.

## LocalMath authoring language

`@localmath` is a syntax translator only. It constructs the same concrete
`LocalLaw` values as the programmatic API and leaves no expression tree in
planning, preparation, or execution.

Frontend lowering obeys:

1. captured `Space`, `Field`, and `Relation` descriptors are evaluated once
   in a hygienic construction scope;
2. indexed accesses resolve against those descriptors during construction;
3. relation iteration lowers only over admitted bounded relation views;
4. bounded generators lower to fixed or bounded device loops without
   allocating Julia generator objects;
5. ordinary scalar calls remain ordinary Julia calls and must pass the same
   concrete-callable and device-effect admission as programmatic authoring;
6. `reduce_to`, `resolve_to`, `bounded_collect`, `publish`, `@ordered`, and
   publication assignments are recognized only in closed admitted syntactic
   positions;
7. every publication target is a statically identifiable `Field`;
8. every equation receives independent `SourceOrigin`; and
9. evaluator captures are concrete isbits values or explicit runtime
   submission bindings.

Lexical assignment creates a local scalar, tuple, named tuple, or fixed-size
tensor value. Indexed field assignment creates a publication. Mutation inside
an arbitrary scalar callable is forbidden except for computation on private
isbits local values admitted by the device compiler. Nested relation traversal
is semantically admitted whenever every traversal has a finite representable
bound, planned workspace fits its declared capacity, and the target device can
legally execute the resulting operation. Bound products may guide schedule
selection or produce a performance warning; no heuristic execution budget
decides semantic validity. A real backend resource rejection reports the
exact failed capability.

`argmin`, `argmax`, and `foldl` in the examples are reserved DSL forms inside
`@localmath`; LocalMath does not overload or export misleading replacements
for the corresponding Base functions. The final syntax audit MAY select
honest explicit spellings such as `resolve_min` or `orderedfold` if user trials
show that reserved forms remain surprising. There is one spelling at freeze,
not aliases.

Both Unicode and ASCII domain binders are admitted:

```julia
@localmath i ∈ cells begin
    velocity[i] = momentum[i] / density[i]
end

@localmath i in cells begin
    velocity[i] = momentum[i] / density[i]
end
```

### Current grammar and policy attachment

The table below records the public vocabulary implemented through LM-5H. The
grammar still remains pre-release until LM-7, but every listed form lowers to
the sole `LocalLaw`, planner, and KernelAbstractions executor. It is product
syntax rather than a roadmap sketch.

| Meaning | Authoritative authoring form | Canonical lowering |
|---|---|---|
| typed submission parameters | `@localmath (i ∈ S; parameters=(Δt::T, ...))` | `ParameterSchema` stored in `LocalLaw` |
| law gate | `@localmath (i ∈ S; when=enabled, ...)` with a Boolean parameter or singleton Boolean field | law gate in `Control`; false skips the law and preserves stage-entry destinations |
| stage gate | `@stage name(i ∈ S; when=enabled) begin ... end` | stage gate in `Control`; false skips that stage and preserves its destinations |
| total unique publication | `out[i] = value`, where total coverage is proven | `Unique(onempty=Unreachable())` |
| runtime-routed partial unique publication | `publish(out, value; route=r, key=k, law=:unique, when=condition)` | partial `Publication{Unique,...}` with preserve-on-empty behavior |
| default assembly | `out[r(i)] += value` | `Reduce(+, initial=Existing(), order=CanonicalLeftFold())` |
| explicit reduction | `out[r(i)] = reduce_to(value; op, seed, onempty, order, when, maximum)` | `Publication{Reduce,...}` |
| resolution | `out[r(i)] = resolve_to(; score, payload, lower, upper, sense=:min, tie=:canonical, when, maximum)` | `Publication{Resolve,...}` |
| collection production | `records[i] = bounded_collect(value; maximum, group, groups, overflow=:reject, order, projection, when)` | `Publication{Collect,...}` |
| collection consumption | `bounded(records[i]; maximum)`, `source_position(records, i; lane)`, and `prefix=count(records)` | `CollectionAccess`, `SourcePositionAccess`, `CollectionCount`, and `Control` |
| ordered action | `@ordered (by=(key, identity), state=(target=>initial, ...)) begin ... end` | one typed `Publication{OrderedFold,...}` with generated `InitializedState`, `FoldStep`, and `BoundedWrites` |
| source-ordered action | `@ordered (by=:source, state=(target=>initial, ...)) begin ... end` | the same ordered law with canonical source order |
| Cartesian pointwise | `(i, j) ∈ grid` with identity indices only | ordinary identity relations |
| Cartesian offsets | `(i, j) ∈ interior(grid, width)` or `(i, j) ∈ periodic(grid)` | grouped affine reads with an explicit boundary contract |
| runtime routing | `publish(out, value; route, key, law, when, ...)` | the corresponding routed Unique, Reduce, or Resolve carrier |
| multi-output law | several publication statements in one law or stage | one evaluator result record and several publications |
| bounded loop | `for value in field[relation(i)]`, the sample/index facade, a static tuple, or a literal finite integer range | typed bounded device loop |
| bounded generator | the same admitted relation facades, tuples, and literal finite ranges in a Julia comprehension | typed bounded device loop |

`publish`, `reduce_to`, `resolve_to`, `bounded_collect`, `@stage`, and
`@ordered` are reserved forms recognized only within `@localmath`; their ASTs
lower immediately to canonical programmatic constructors. Arbitrary iterators,
`while`, data-dependent unbounded ranges, dynamic collections, and unrecognized
policy keywords reject at construction with source provenance. No lexical
heuristic selects a gate, parameter, active source, or publication policy.

Longer examples below that use direct topology iterators, `argmin` sugar, a
`foldl` spelling, or `@ordered state(from=..., group=...)` remain illustrative
future sketches and are not current syntax. The current ordered form is exactly
the `by`/`state` form in the table above.

### Stage field versions and publication state

Every right-hand-side field read in a stage observes the stage-entry version.
Local lexical bindings execute sequentially and may carry newly calculated
values between equations. Publications settle only at stage exit and become
field-visible to later stages. Reading a same-stage publication through its
field name therefore reads its stage-entry value, never the pending
publication. A later stage is required when a globally settled result
must be visible.

Several publications to one destination field within a stage must share one
compatible admitted publication law. Source statement order never creates
implicit last-writer-wins semantics.

Every publication declares complete initial, coverage, empty, and failure
behavior:

| Law | Initial and coverage | Empty destination | Failure visibility |
|---|---|---|---|
| `Unique` | unconditional syntax means every reached source participates; destination coverage is proven separately | unless total coverage is proven, requires `onempty=Preserve()` or `onempty=Fill(value)` | no publication until uniqueness and any runtime coverage validation succeeds |
| `Reduce` | existing-seeded assembly by default; an explicit identity seed starts from that value | preserves existing on empty input under `Existing()`; an identity seed publishes its identity | guarded publication after reduction validation |
| `Resolve` | replaces the selected destination value | requires `onempty=Preserve()` or `onempty=Fill(value)` | guarded publication after total tie/order validation |
| `Collect` | replaces the logical collection; append requires a separately explicit seed | successful empty input publishes count zero and a valid empty directory | semantic overflow validation is atomic; provider failure follows the global failure model below |
| `Ordered` | requires an explicit initial accumulator source | zero events return the declared initial state | successful-prefix state is visible only according to the ordered-action validation/publication contract |

Work-level gates, stage gates, active selections, runtime parameters, snapshot
timing, and failure-prefix visibility are semantic dimensions of `Control` and
publication declarations. Removing their old `@gate`, `@active`, and `@value`
spellings does not remove the behaviors.

Failure claims distinguish three classes for every law:

1. plan or preparation rejection means execution never starts;
2. a device semantic-validation failure follows the declared law contract:
   buffered Candidate and Collect results remain unpublished, while
   `Ordered` exposes only its validated successful prefix; and
3. a provider or hardware failure after publication begins may leave the
   physical target partially updated; LocalMath claims neither rollback nor
   hardware atomicity.

Transaction-like domain behavior uses private staging and publishes to live
state only behind the successful semantic gate. It does not infer rollback
from a device provider failure.

### Pointwise publication

```julia
@localmath i ∈ cells begin
    velocity[i] = momentum[i] / density[i]
end
```

Ordinary `=` means unique publication. Planning MUST prove uniqueness or
insert a bounded device validation gate and report that distinction in
inspection; otherwise it rejects the equation. A user assertion alone is not
a proof. Source participation and destination coverage are independent:
unconditional source participation does not prove sparse-scatter coverage.
Coverage derives from relation surjectivity, selection, and any exact runtime
validation. Identity pointwise assignment may prove total coverage directly;
otherwise `Unique` requires an explicit `onempty` law. It never means implicit
last-writer-wins.

### Bounded gather

```julia
@localmath v ∈ vertices begin
    du[v] = sum(
        conductivity[e] * (u[other(e, v)] - u[v])
        for e ∈ incident_edges(v)
    )
end
```

### Structured stencil

```julia
@localmath x ∈ interior(grid) begin
    Δu[x] = sum(u[x + δ] - u[x] for δ ∈ stencil) / h²
end
```

Boundary behavior belongs to the domain, field extension, or relation. It is
never inferred from illegal array access.

### Local-to-global assembly

```julia
@localmath e ∈ springs begin
    i, j = endpoints(e)
    f = spring_force(position[j] - position[i], stiffness[e])

    force[i] += f
    force[j] += -f
end
```

`+=`, `*=`, extrema, and admitted named operators denote declared reduction
laws, not arbitrary mutation.

### Resolution with evidence

```julia
@localmath p ∈ proposals begin
    winner[target(p)] = argmin(
        ΔH[p];
        payload = p,
        tie = source_order(p),
        onempty = Preserve(),
    )
end
```

Contested resolution requires a total tie law and explicit empty behavior.
Payload and source provenance survive planning and inspection.

### Bounded collection

```julia
@localmath p ∈ proposals begin
    requests[cell(p)] = bounded_collect(
        request[p];
        maximum = MAX_REQUESTS,
        order = source_order(p),
        overflow = Reject(),
        onempty = Empty(),
    )
end
```

Capacity, canonical order, and overflow behavior are scientific semantics and
remain visible in authoring and inspection.

### Ordered recurrence

```julia
@localmath e ∈ events begin
    @ordered (
        by=(event_order[e], event_identity[e]),
        state=(
            relationships => initial_relationships,
            degree => initial_degree,
        ),
    ) begin
        next = next_relationship(relationships[slot[e]], event[e])
        relationships[slot[e]] = next
        degree[(a[e], b[e])] =
            (next_degree_a(degree[a[e]], event[e]),
             next_degree_b(degree[b[e]], event[e]))
        halt_when(terminal[next])
    end
end
```

`@ordered` is a reserved marker within `@localmath`. Its body lowers to one
typed bounded update record over named heterogeneous accumulator components.
`state` declares every component and its explicit initial Field;
`target => target` explicitly requests in-place initialization. `by` is either
a total `(key, identity)` pair composed from bounded Field reads or `:source`.
During an event, reads from a declared state Field observe the accumulated
successful prefix, while other Field reads retain stage-entry snapshot
semantics. Scalar and tuple assignments become `BoundedWrites`; an ordinary
`if` may reduce a statically bounded assignment to zero writes. Every declared
component produces one bounded bundle per `FoldStep`. `halt_when` marks the
step as terminal. The generated transition is a concrete isbits callable and
receives no writable arrays or mutation escape hatch.

This form is global ordered recurrence. Parallel keyed ordered groups and the
older `foldl`/`@ordered state(from=..., group=...)` sketches are not current
syntax; they require separate scientific and conflict semantics before they
could be admitted. An ordered action is not a scientific transaction.

### Bounded control

The language admits familiar bounded control:

```julia
@localmath e ∈ edges begin
    if energy[e] > threshold[e]
        failed[e] = true
    end
end
```

It also admits bounded loops and generators over static axes or bounded
relations. It rejects unbounded loops, dynamic allocation, host callbacks,
runtime symbolic interpretation, hidden global mutation, arbitrary pointer
access, and unanalyzable routing.

### Stages

```julia
step = @localmath begin
    @stage forces e ∈ springs begin
        i, j = endpoints(e)
        f = spring_force(position[j] - position[i], stiffness[e])
        force[i] += f
        force[j] += -f
    end

    @stage integration i ∈ nodes begin
        vnext = velocity[i] + Δt * force[i] / mass[i]
        velocity[i] = vnext
        position[i] = position[i] + Δt * vnext
    end
end
```

A stage is a semantic visibility boundary, not necessarily a physical kernel
boundary. Fusion MAY change physical launches but MUST preserve publication
visibility and numerical order.

## Publication basis

The common semantic basis is one routed publication descriptor family with
distinct laws:

```text
Unique       -- at most one participating value per destination
Reduce       -- admitted fold operator, explicit seed, and numerical order
Resolve      -- winner score, payload, total tie law, and empty behavior
Collect      -- bounded ordered materialization and overflow behavior
Ordered      -- heterogeneous prior state, bounded update record, transition,
                and canonical event order
```

One conceptual representation MAY be parameterized as:

```julia
Publication{Law, Route, Value, Multiplicity, Policy}
```

The representation centralizes route, value type, destination multiplicity,
order, capacity, numerical policy, provenance, and workspace requirements. It
does not require one physical algorithm. Reduction, resolution, collection,
and ordered recurrence retain the distinct implementation phases their
semantics require.

Keyed versus fixed routing is a relation property, not a second semantic or
executor family. A specialized mechanism is accepted only when it implements
one of the common laws and deletes more duplicated machinery than it adds.

Floating-point `+` is not treated as mathematically associative. Reduction
policies distinguish:

- deterministic canonical left fold with fixed semantic contribution order
  and no reassociation;
- deterministic tree with an explicitly specified tree contract; and
- explicitly relaxed reduction permitting reassociation or atomics under a
  stated comparison and numerical-error contract.

Inspection reports race freedom, seed, contribution order, accumulator type,
reassociation permission, scheduling determinism, same-backend repeatability,
cross-backend repeatability, and numerical comparison rule. `+=` declares
identity-seeded assembly by default. An explicit law-level policy may change
the seed or admit reassociation; planning cannot weaken it invisibly.

The first release requires rigorously defined `Reject()` collection overflow.
`capacity` is total record capacity; an optional `group_capacity` is a separate
per-group bound. Overflow validation completes before caller-visible
publication. On overflow, previous records, count, directory, projections, and
ready receipt remain unchanged; an exact device-resident status closes all
dependent publications. Successful empty input publishes count zero and a
valid empty directory. `Truncate()` is not admitted until canonical global or
per-group prefix semantics and mandatory overflow evidence are specified and
qualified. Status evidence is orthogonal to the overflow response, not a peer
response policy.

## Direct-cutover implementation order

Every cutover is a direct pre-release edit. A superseded API, test, executor,
or adapter is deleted in the same cutover that replaces it. The numbered
boundaries are dependency gates on one development branch, not supported
public migration epochs. Intermediate commits MAY be temporarily uncompilable
inside one boundary, but every boundary restores the complete supported suite
and leaves one production path.

LM-1 through LM-3B form one atomic public cutover with internal review
checkpoints. LM-1, LM-2A, LM-2B, LM-2C, and LM-3A strengthen the sole existing
semantic, plan, prepared, receipt, inspection, and authoring authorities under
their current source names. They do not introduce final-named peers. LM-3B
performs the only mechanical rename and public exposure. After every
checkpoint there is exactly one semantic type, one plan type, one prepared
type, and one receipt type; no old/new pair is ever a supported or production
choice.

Difficulty is not a reason to weaken a primitive that the common mathematical
waist genuinely needs. LocalMath MAY add a richer primitive when it has an
independent mathematical identity, composes orthogonally with the existing
laws, has at least two unrelated domain witnesses, and lowers into the one
planner/executor architecture. It MUST NOT simulate completeness with domain
adapters, opaque callbacks, or several nearly equivalent primitives.

### LM-0 -- Semantic closure and compiler-scaling baseline

Freeze the exact stage, empty-result, overflow, ordering, failure, visibility,
and numerical contracts in this specification before structural editing. Add
ordinary optimized compilation probes for 1, 4, 8, 13, and 32 heterogeneous
stages and record Julia version, command, hardware, cache state, planning time,
host compilation, device compilation, and warm execution separately.

The current executable contract map is maintained in
[`LocalMath LM-0 Semantic Closure Evidence`](localmath-lm0-semantic-closure-evidence.md).
That ledger freezes behavioral witnesses without making the old API or its
implicit cumulative-tail event model authoritative. Missing event, runtime
relation freshness, and syntax-equivalence tests land only with the LM-1,
LM-2, and LM-3 representations they exercise.

The measured specialization policy, frozen numeric ceilings, final-source CPU
regressions, and real-device execution evidence are maintained in
[`LocalMath LM-0 Compiler and Execution Baseline`](localmath-lm0-compiler-baseline.md).

Before LM-1, the committee selects a numeric non-superlinear scaling bound and
a flagship latency bound from the measured baseline. Every later gate must
meet or improve them. The specialization matrix records which facts may enter
types: scalar and fixed tensor types, dimension, relation representation and
small static degree, publication kind, and evaluator type. Extents, names,
runtime IDs, epochs, origins, and ordinary capacities remain values or cold
metadata unless measured evidence and code-generation need justify otherwise.

The baseline does not excuse current compiler cost. It identifies the next
cold-evidence barrier without boxing executable phases, splitting a scientific
sequence, or creating a second execution route.

LM-0 created the baseline deletion ledger before editing. It is an immutable
record of the pre-LM-1 source rather than a validator for the live tree:

- machine-readable ledger:
  [`design/audits/localmath-cutover-authority-ledger.toml`](../design/audits/localmath-cutover-authority-ledger.toml);
- historical validator: `julia scripts/check_localmath_cutover_authority_ledger.jl`
  against the preserved LM-0 state.

Each later boundary creates or updates its own gate ledger from the immediately
preceding approved source. Gate validators check concrete dispositions and
exact set equality between named package-owned kernels and discovered
`@kernel` definitions; aggregate kernel or line counts never substitute for
row-level evidence. The current live baseline is the approved LM-1 ledger
linked below.

LM-0 closed with four independent `PASS` dispositions on 2026-08-20. The
compiler gate, final-source CPU regressions, real-GPU evidence, corrected
findings, and reviewer decisions are recorded in the
[`LM-0 Final Review`](../design/evidence/localmath/lm0/final-review.md). LM-1
may begin from this baseline; later gates must recheck every LM-0 invariant
their edits affect.

LM-1 explicitly supersedes one structural, but not numerical, LM-0 flagship
invariant. The frozen 13-stage/39-launch/15-fact identity described the
selection prototype that LM-1 directly deletes. Scientific-workload continuity
is instead established by the same public CorePotts program, lifecycle plan,
initial state, request-index execution, stable-priority policy, two physical
banks, selection result, and independent lifecycle oracles. The replacement
structural invariant is exactly one CorePotts-owned transaction kernel followed
by one LocalMath Collect publication Stage, currently nine physical launches
and three qualified publication facts. LM-0's planning-through-first and
fresh-process flagship ceilings remain frozen and must still pass. This is an
authority replacement justified by source deletion, not permission to relabel
a synthetic Stage workload as the CorePotts flagship.

```text
current owner/symbol | semantic fact owned | replacement owner |
deletion boundary | permitted private residue | validation query | status
```

The baseline must expand concrete symbols under at least these rows:

| Current owner/symbol family | Semantic fact | Replacement | Boundary | Permitted residue | Validation query | Initial status |
|---|---|---|---|---|---|---|
| `topology`, `_TopologyLeaf`, route symbols, destination counts | topology, routing, extent | `Space`/`Field`/`Relation` plus `RelationProof` | LM-1/LM-3B | physical relation device views | symbol scan plus plan inspection | enumerate |
| named reads, read roles, `bounded_read`, `pointwise_read` | access placement and bounds | `Field` access through `Relation` | LM-1/LM-3B | typed storage accessor | symbol scan plus witness lowering | enumerate |
| `emit`, `candidate`, output/port declarations | publication meaning | common `Publication` laws | LM-2A/LM-3B | physical law kernels | grammar scan plus inspection | enumerate |
| `active_*`, work gates, authored values | selection, gating, submission values | `Control`, selected spaces, `ParameterSchema` | LM-1/LM-3B | prepared parameter tuple | symbol scan plus syntax witnesses | enumerate |
| keyed/fixed validation and evidence builders | multiplicity, bounds, ordering proof | sealed `RelationProof` and publication evidence | LM-2A | representation-specific validators | method/root count and proof inspection | enumerate |
| result/evidence/workspace builders | output state and resource needs | publication result schema and one workspace planner | LM-2A | law-specific workspace leaf | constructor/root count | enumerate |
| `WorkEvent`, lane-tail methods, provider wrappers | completion, dependency, status | sole logical `ExecutionReceipt` | LM-2B/LM-3B | one KA implicit-order provider-scope state | ownership scan and dependency witness | enumerate |
| `run!` and execution dispatch roots | submission | `execute!` over one prepared architecture | LM-2B/LM-3B | law-specific kernel dispatch | call-graph/root scan | enumerate |
| conjunctive specialization | multi-resource resolution | generalized law or deletion | LM-2A | none unless unrelated witnesses justify it | source and witness scan | enumerate |
| `localworksets_*` kernel families | physical execution | common law kernel families | LM-2A/LM-3B | one implementation per physically distinct law | kernel/launch inventory | enumerate |

LM-7 accepts a row only when every concrete symbol is deleted, retained with
one explicit domain-neutral justification, or replaced by exactly one named
authority. Aggregate counts cannot substitute for the row-level evidence.

### LM-1 -- Strengthen the sole programmatic semantic waist in place

LM-1 is one direct semantic replacement performed under the current package
and lifecycle names. It does not add a LocalMath peer hierarchy. `LocalWork`
is strengthened in place and remains the sole program type until LM-3B;
`WorkPlan` and `PreparedWork` remain the sole plan and prepared types. The
names `LocalLaw`, `Plan`, `PreparedPlan`, and `ExecutionReceipt` in this
specification describe their final LM-3B identities and MUST NOT appear as
parallel source types during LM-1.

#### One stage-tuple program representation

The sole LM-1 program representation is normatively equivalent to:

```julia
struct Stage{S,A,P,E,C,O}
    source::S
    accesses::A
    publications::P
    evaluator::E
    control::C
    origin::O
end

struct LocalWork{Stages,Parameters}
    stages::Stages
    parameters::Parameters
end
```

`stages` is a concrete, nonempty tuple. A one-stage law has a one-element
tuple. `sequence` concatenates stage tuples in exact scientific order.
`_SequenceOperation`, empty sentinel fields, a public scheduler, and a second
sequence IR are forbidden. Each stage owns exactly one source `Space`, typed
access descriptors, typed publication declarations, one ordinary concrete
evaluator, one `Control`, and its source origin.

Stage/evaluator type, relation representation, dimension, and a small static
degree MAY specialize execution. Runtime extents, descriptor identities,
schema epochs, content generations, source labels, ordinary capacities, and
parameter values remain values or cold evidence. A large stage tuple may use
the LM-0 cold-evidence barriers and stage-group execution representation; it
MUST NOT be split into independent scientific programs or executed through a
fallback path.

#### Descriptors and representation payloads

LM-1 adds `Space`, `Field`, `Relation`, `Stage`, `Control`, and
`ParameterSchema` inside the existing package. `Space`, `Field`, and
`Relation` identities are explicit stable values, independent of Julia
variable names, and survive inspection and serialization. Two separately
constructed descriptors are distinct even when their shapes and element types
match. Identity, extent, and schema epoch are not type parameters.

`Relation` is one concrete outer descriptor containing domain, codomain,
identity, schema epoch, and one immutable representation payload. Fixed,
packed, affine, inverse, runtime-key, subset, product/index, and boundary
constructors produce specializations of that representation payload. They do
not create a public abstract-interpreter hierarchy or one lifecycle adapter
per relation family. Physical representation dispatch remains ordinary Julia
multiple dispatch beneath the one descriptor contract.

Relation descriptors do not own bound storage. In particular, a fixed
relation describes degree, domain, codomain, and representation, while its
connectivity is supplied during structural binding. Downstream convenience
constructors may collect a descriptor and binding together for domain UX, but
must lower immediately to the same structural pair and add no LocalWorksets
adapter type.

An access stores a `Field`, an admitted `Relation` from the stage source to
that field's space, and its access/version law. An evaluator-local role label
may remain a compile-time NamedTuple label for readable callable arguments; it
is not field identity, storage identity, or relation lookup authority.
Pointwise access is ordinary access through a proved identity relation.
Bounded gather obtains its bound from the relation proof. Plain exposure of an
entire array without an admitted relation is not a local access and rejects.

An LM-1 publication is one member of a closed Stage-publication vocabulary.
Ordinary spatial publication (`Unique`, `Reduce`, and `Resolve`) has a `Field`
destination and a `Relation` route. Port names are evaluator/publication labels
only. Destination extent comes exclusively from the codomain `Space`.
Canonical lane identity and order are relation-proof/publication evidence;
they are not a `semantic_ids` topology side channel.

Two mathematically distinct terminal forms remain inside the same `Stage`
waist rather than being forced into fictitious spatial destinations:

- `Collect` publishes one bounded finite sequence with exact source/lane
  provenance, capacity, grouping, order, overflow, and empty behavior. It has
  no destination `Field` or routing `Relation`. Its public result is the typed
  bounded sequence storage/view, not an inactive array tail.
- `OrderedFold` publishes the result of one explicitly seeded, left-associated
  recurrence over a declared finite sequence. It owns typed accumulator Field
  components and an exact order. It is terminal and may not feed back into a
  concurrent Stage publication.

These are closed publication laws, not peer program IRs. They use the same
source, accesses, evaluator, control, origin, structural binding, admission,
and receipt lifecycle as every other `Stage`. Their irreducible physical
specializations do not authorize a second planner, public task graph, or
generic output-declaration hierarchy.

A later Stage may consume a preceding `Collect` without materializing a host
result or entering a second sequence pipeline. `CollectionAccess(collection,
BoundedGroup(K))` exposes only the current dense group through a read-only
view whose occupancy is validated against the static bound `K` before any
dependent publication. `SourcePositionAccess(collection, Val(K))` exposes the
fixed `K` producer-lane positions, with zero denoting nonparticipation, and
`CollectionCount(collection)` may provide a device-resident Stage prefix.
Each access requires one exact preceding producer in the same Stage tuple,
retains the producer receipt dependency, and reads the canonical
`CompactedStorage` in place on CPU and GPU. The bounded views expose only
`length`, indexing, and iteration; storage fields and inactive tails are not
part of their semantics. Legacy `CompactedResult`, sequence-demand records,
and public post-hoc `record_count`/`bounded_group_read`/`source_position`
authorities are forbidden.

`RuntimeRelation` is not a fourth publication law. It is a bounded partial
address map from `Int32` or `UInt32` keys to the relation codomain. Typed routed
carriers feed ordinary `Unique`, `Reduce`, or `Resolve`: key zero means
intentional nonrouting, a participating nonzero key outside the codomain is a
deterministic Stage failure, and `Resolve` rank validation precedes key
routing. No runtime-keyed lowerer or separate conflict semantics remain.

`Control` stores typed selection and gate references. Prefix selection names a
parameter slot, mask selection names a Boolean `Field`, and index/subset
selection names a `Relation`. No selector stores a Symbol that is resolved
against a topology record during planning.

#### Structural binding is a lifecycle envelope, not another IR

LM-1 establishes this exact structural lifecycle:

```text
LocalWork{Stage tuple}
    -> bind descriptor identities to concrete storage
    -> validate and mint field/relation proofs in plan
    -> prepare concrete field/relation device views
    -> run through the existing sole receipt path
```

`bind` returns one thin package-owned bound envelope containing the original
`LocalWork` and an exact tuple of descriptor-to-storage bindings. It stores no
derived semantic facts. Missing, duplicate, unreferenced, or wrong-identity
bindings reject. Domain packages MAY define `bind(work, domain, state)`, but
that method must return the same envelope and cannot own validation or create
a domain adapter consumed by planning.

Caller-owned storage is the default and retains object identity. Scientific
storage allocation is never inferred from reads or publications. The sole
explicit cold declaration is:

```julia
prepared = prepare(law,
    input => Allocate(host_input),
    output => Allocate(undef),
    force => Allocate(0f0),
    neighbors => Allocate((
        endpoints = host_endpoints,
        counts = host_counts,
    )),
    records => Allocate();
    backend,
)
```

`Allocate(undef)` requests uninitialized Field storage. `Allocate(value)` is
an exact element fill only when `typeof(value) === eltype(field)`.
`Allocate(source)` accepts only an exact-shape, exact-element-type source array
and produces independent backend storage. Relation declarations recursively
copy array leaves while preserving tuple, named-tuple, and scalar structure.
`Allocate()` is reserved for a produced Collection and derives its exact empty
`CompactedStorage` from the Collect law: record capacity and type, count,
provenance, optional dense group directory, and only a demanded persistent
source-position projection. Composite Collection records use zero-copy
`StructArray` component storage. Multiple producers must require one identical
physical schema.

Every allocation uses `KernelAbstractions.allocate`; package-owned KA kernels
perform exact fills. Generic copying is allowed to synchronize during this
cold operation. There are no provider-specific allocators. Direct arrays are
never copied or adapted. Allocation declarations are consumed before the
ordinary structural envelope is constructed and cannot survive into plans,
prepared values, workspaces, receipts, or kernel arguments.

Before materializing `Allocate(undef)`, binding performs a conservative
stage-order definite-initialization analysis. Reads, gathers, controls,
OrderedFold state, and publications whose empty behavior preserves prior state
require initialization. Only an unconditional, total, identity-routed Unique
publication over the complete Field establishes it for later stages.
Conditional participation, partial or uncertain coverage, nonidentity routing,
Reduce, Resolve, and preserve-on-empty behavior do not. Unprovable use rejects
at its authored origin with an exact fill/copy suggestion; the proof is not
stored after binding.

`storage(bound, descriptor)` resolves the stable semantic identity, rechecks
the complete descriptor schema, and returns the exact Field array, physical
Relation storage (`nothing` for a computed relation), or `CompactedStorage`.
It is an accessor over the sole structural binding, not a storage registry.

Cold binding assigns each referenced `Field` and `Relation` one positional
slot. `_LoweredWork`, prepared stage projections, and physical phases use
those slots. User Symbols and descriptor UUIDs MUST NOT become warm lookup
keys or arbitrary type parameters. The existing name-parameterized
`_BindingAuthority`, `_BindingProjection{Names}`, and symbol-keyed dynamic
storage submission are deleted. Evaluator role labels and parameter names may
be checked cold, after which execution receives positional tuples.

`ParameterSchema` is the one authority for runtime scalar and small isbits
records. It stores names as cold values and exact value types structurally.
Planning assigns parameter slots; preparation fixes their device argument
layout; warm submission validates the exact named input and exposes a
positional isbits tuple without allocation, packing, or device transfer.
`_ValueSlot`, `_StorageSlot`, inferred free-variable parameters, and dynamic
array submissions are deleted. Field and relation arrays are bound before
planning and remain on their device.

#### Sealed proof and prepared-view ownership

Planning, not a relation extension, mints the sole `RelationProof`. The proof
records the relation and concrete binding identities, schema epoch, degree and
multiplicity bounds, coverage, canonical order, ownership, footprint/halo
strength, and representation evidence. Its constructor requires a
package-owned identity seal checked by planning, and all construction sites
are inventoried. An extension may provide relation data and the minimal
descriptor/device-view protocol; it cannot return a proof or a self-asserted
uniqueness trait that planning trusts.

The plan stores one tuple of validated field and relation proof records.
Law-specific mechanisms reference proof slots and algorithm choices; they do
not retain their own semantic copies of route arrays, destination counts,
semantic identities, or read routes. A physical phase may retain the concrete
device view and scalar extents needed by its kernel, because those are derived
execution values rather than a competing semantic authority.

Preparation creates one concrete device view per referenced relation through
the selected proof and backend. CPU and GPU use the same view protocol and
the same KernelAbstractions execution path. A Cartesian/affine view remains
computed geometry, a packed relation remains canonical packed storage, and no
representation is normalized to a generic matrix merely to enter the waist.
Prepared relation views and field storage are concrete and type-stable. Cold
proof/inspection evidence may be boxed; executable views, stages, evaluators,
parameters, and workspace templates may not.

The current physical binding protocol for arrays, `StructArray` values, and
structured publication storage is retained as a storage-layout mechanism. It
is extended to validate field and relation bindings by positional slot and
physical leaves. It is not allowed to remain a Symbol-keyed semantic binding
authority. `_TopologyLeaf` and the separate topology payload tree are deleted;
relation binding/device-view preparation uses the same physical-leaf,
backend, alias, identity, and layout machinery as field storage. Workspace
leaves remain separate because they describe allocation requirements rather
than bound scientific data.

#### Freshness and runtime relation state

Global topology object identity, topology epoch, and whole-topology
fingerprints are deleted. Each `RelationProof` owns cold schema freshness:
relation identity, `schema_epoch`, physical binding identity, and any content
fingerprint required for an immutable static representation. Changing domain,
codomain, extent/degree bound, representation, ownership, or physical binding
invalidates the proof and every prepared view derived from it.

Warm packed/runtime content uses `content_generation` stored with the bound
device representation. Entry, count, active-bit, and relationship-generation
updates may advance it within the cold proof bounds without rebuilding the
plan or copying through the host. Device validation records the generation it
validated and gates dependent publication. LM-1 installs this schema/content
split using the sole existing receipt/status path; LM-2B gives that receipt
exact dependency and settlement semantics without changing relation meaning
or adding a second validator.

After runtime construction, canonical packed relation state remains packed on
CPU and GPU. Conversion from an unpacked construction/serialization value is
cold and completes before binding. No execution, settlement, lifecycle, or
queued path may convert, store, mutate, or dispatch on unpacked relationship
state.

#### Required direct deletions

The following authorities are deleted in the same LM-1 edit that introduces
their replacement:

- `topology` and its `item_count`, `routes`, `destination_counts`,
  `semantic_ids`, and global epoch record;
- `_TopologyFreshness`, global topology identity/fingerprint checks, and
  family-specific topology fingerprints;
- `_TopologyLeaf`, static topology payload reconstruction/copy/accounting,
  and separate prepared topology-array identity caches;
- `_BindingRead`, `_PointwiseRead`, `_BoundedRead`, `_RuntimeRoute`, active
  route Symbols, and their lookup helpers;
- old identity/fixed route semantic constructors and old route-named physical
  types; relation device views may replace their kernel behavior;
- `_BindingAuthority`, name-derived binding requirements, name-based stage
  projections, `_ValueSlot`, `_StorageSlot`, and dynamic array submission;
- semantic `routes`, `destination_counts`, `semantic_ids`, and `read_routes`
  fields in every law-specific lowering; and
- `_KeyedGroupedLowering`, `_CompactedLowering`, `_OrderedFoldLowering`, their
  old output declarations and plan/prepared phase families, and every old/new
  execution selector; and
- every LocalWorksets/CorePotts/test/benchmark call that constructs the old
  topology schema.

This prohibition is semantic, not lexical. A domain field may legitimately be
called `semantic_ids`, and a physical algorithm may discuss a route. Neither
may reconstruct or own the deleted topology side channel.

The following are permitted LM-1 residues:

- one physical storage-layout protocol and its prepared leaf facts;
- one workspace planner and law-specific workspace leaf requests;
- concrete relation device views and proof-derived scalar kernel arguments;
- distinct package-private physical law kernels beneath the one closed Stage
  publication vocabulary, pending LM-2 consolidation;
- the current package, `LocalWork`, `WorkPlan`, `PreparedWork`, and `WorkEvent`
  names pending their scheduled LM-2A/LM-2B/LM-3B cutovers; and
- the old `@localwork` surface pending LM-3, only if it lowers directly into
  the new stage/descriptor representation and cannot construct old topology.

There is no `plan(work, old_topology)` overload, topology-to-relation adapter,
old/new binding union, compatibility property alias, feature flag, migration
constructor, or fallback executor.

#### Direct-edit order and evidence gate

LM-1 is one atomic source boundary, not a sequence of supported migrations.
Implementation order within the boundary is:

1. define descriptors, `Stage`, parameter schema, structural binding, proof,
   and view protocols;
2. replace the fields of the sole `LocalWork`, `WorkPlan`, `_LoweredWork`, and
   prepared pipeline in place;
3. make every law mechanism consume descriptor/proof slots and prepared views;
4. rewrite LocalWorksets witnesses, compiler harnesses, and existing
   CorePotts compilers directly; and
5. delete all superseded topology/read/binding code, exports, tests, and
   inspection projections before the boundary is reviewed.

#### Gate C1 private stage-model dependency

Before the atomic `LocalWork` replacement, one private dependency checkpoint
defines the exact target stage vocabulary. It is not a second program IR: none
of these values may plan, prepare, execute, convert to the old `LocalWork`, or
enter the public/exported surface while the old topology program remains live.
The checkpoint exists only so the semantic types themselves can be reviewed
before every law and downstream compiler is edited against them.

The cold semantic shape is:

```julia
Access(field::Field, relation::Relation, StageEntry())

Publication(
    (
        PublicationComponent(field, relation, role),
        ...,
    ),
    law,
)

Stage(source, accesses, publications, evaluator, control, origin)
```

An access relation maps the Stage source to the accessed Field space. Access
roles may be the keys of a cold `NamedTuple`, but `Access` itself owns no name,
route, storage, or bound. LM-1 admits one explicit stage-entry Field version;
identity relations express pointwise access and proved bounded-degree relations
express gather. Read kind is not a second semantic hierarchy.

A publication is always one law plus one ordered nonempty tuple of components.
Each component owns one destination `Field`, one publishing `Relation`, and one
closed role. Evaluator-fed roles carry the result-port label as compile-time
callable-shape metadata. Derived count, directory, source-position, and ordered
state roles have closed package types and no evaluator result entry. The law,
not each component, owns status, capacity, order, overflow, workspace, and
publication gating. The first private witness is a route-free Unique law with
typed preserve/fill/unreachable empty behavior. Existing route-bearing output
declarations are neither stored nor adapted into this model; they are deleted
when their production mechanisms are retargeted.

That Unique witness owns its evaluator result carriers as well: a total lane is
`UniqueValue(value)` and a partial lane is `ParticipatingUniqueValue(value,
participates)`. These are not aliases for the legacy `emit` or `candidate`
values and carry neither runtime address nor route semantics. A later
runtime-address publication law may introduce its own explicit value carrier;
it may not smuggle a legacy route token through the Unique result ABI.

`Control` is the orthogonal product of prefix, mask, subset, and gate. Parameter
prefixes and gates refer to the exact declarations in the program's one
`ParameterSchema`; Field prefixes and gates refer to singleton typed Fields; a
mask is a Boolean Field on the Stage source. A subset relation has domain and
codomain equal to the Stage source, degree bound one, and means
identity-or-absent participation. It never remaps or renumbers source items;
ordinary composed relations express those mappings. Provider status is not a
semantic Control value.

The evaluator is one concrete callable specification plus an ordered tuple of
exact parameter declarations. This tuple is the sole owner of the evaluator's
parameter demand. It prevents both free-variable inference and passing the
whole program parameter tuple to every Stage. Planning later resolves the
declarations to positional slots. A scalar one-port adapter is callable-shape
sugar only. Stage construction never probe-executes the evaluator; the planner
validates one inferred exact result type against evaluator-fed publication
labels after access and parameter signatures are known.

The private C1 constructor performs structural callable admission only: it
rejects non-isbits captures, descriptor/metadata/pointer captures, and
unreviewed type parameters. It cannot prove the body effect-safe before the
planner has derived exact gathered-access and positional-parameter argument
types. Therefore C2 planning must, before any preparation, run the existing
closed typed-IR/effect screen on that exact specialization, reject mutable
global/`Ref` reads, host callbacks, foreign calls, mutation, and abstract or
nonconcrete inferred results, then validate the exact publication result ABI.
Preparation additionally proves the accepted callable through the same
KernelAbstractions CPU/GPU compilation route. This is deferred validation, not
an alternate evaluator path or an exception to the GPU contract.

Cold Stage values may contain descriptors, UUIDs, labels, `SourceOrigin`, and
the parameter schema. Prepared phases may contain none of those identity or
lookup authorities. The warm ABI
is stage-local positional tuples of concrete Field arrays, relation views,
workspace/status arrays, a concrete admitted evaluator, typed controls, and
projected scalar parameter values. Slot ordinals are the only accepted
storage-identity-in-type ABI. A bounded `NamedTuple` label set may survive
only at the scalar callable-shape boundary: evaluator result ports and
OrderedFold accumulator components. Those labels select statically known
record fields; they never identify storage, routes, dependencies, or schedule
nodes, and the planner validates them against the cold publication exactly
once. Recursive device-value admission rejects all other semantic
metadata and pointer-like values even when Julia reports them as `isbits`.
Admitted storage values include primitive numeric/Boolean/enumeration values,
bounded static arrays, tuples, and ordinary immutable scientific records whose
fields and type parameters recursively meet the same rule. Symbols, UUIDs,
pointer/reference values, arrays, `Val`, free-standing labels, functions,
semantic descriptors, and arbitrary metadata type parameters are rejected.
Package-owned reviewed type parameters such as the small Unique width are the
only other exception; user callables may not use metadata as a specialization
key. This narrow callable-record exception is necessary mathematical shape,
not a second identity or routing authority.
`FieldGate` and `FieldPrefix` remain device-resident and are validated/guarded
through KernelAbstractions status dependencies without host scalar reads.

Gate C1 moves `ParameterSchema` and its declaration/slot definitions from the
structural-binding file into the stage-model owner; it does not copy them. It
adds no old/new constructor, compatibility property, topology adapter,
execution method, public name, or fallback. Zero-cardinality Spaces remain
valid because empty-source publication behavior is part of the scientific
contract. The full `LocalWork` constructor later owns program-level parameter
coverage, preceding-Field dependencies, total Field controls, and binding-slot
closure; a standalone Stage is deliberately not an executable program.

#### Gate C semantic freeze

The stage-tuple cutover uses the following exact rules. These are semantic
decisions, not temporary implementation conventions.

`ParameterSchema` composition follows first scientific declaration order. A
parameter's cold program-local name is its identity for schema composition;
LM-1 does not add a separate Parameter descriptor. Repeated declarations of
the same name coalesce only when their exact value type and every declared
bound agree; any disagreement rejects. Planning assigns one global positional
parameter slot and each stage receives only its concrete tuple projection.
Parameter names never enter the warm ABI.

A compound publication remains one publication-law authority whose
destination payload is an ordered tuple of explicit component `(Field,
Relation, role)` declarations. It owns shared order, capacity, overflow,
status, workspace, and publication gating exactly once. Compacted records,
counts, directories, and source positions therefore use component Fields on
their actual Spaces; no bundle name or storage object becomes a producer,
lookup, extent, or dependency authority. Evaluator-produced value components
have evaluator port labels. Algorithm-derived components such as counts,
directories, and canonical source positions instead have closed typed
component roles and are absent from the evaluator result. Validation status
and publication receipts remain package-owned execution evidence referenced
solely by the receipt/status path; they are not component Fields or evaluator
results. A cold convenience value may lower to this one compound publication
and disappear; the publication law itself remains present through planning
and execution.

Every stage reads its Fields at stage entry. All semantic validation completes
before any caller-visible publication, and the stage's publications become
semantically visible together at the stage-exit boundary. Physical writes
remain subject to the package-wide provider-failure, poisoning, and
non-rollback contract; LM-1 does not claim hardware transactional rollback.
Stage entry means the state after all preceding stages in scientific order,
so repeated earlier publications to the same Field have one unambiguous
value: the latest completed stage. LM-1 does not expose historical field
versions. Same-stage access and publication of one Field still reads the
stage-entry snapshot. When a publication Field aliases any accessed storage,
direct in-place execution is admitted only when a package-derived proof
establishes all of the following: unique assignment, identity-equivalent
source/destination indexing, no cross-index read/write dependence, no
conflicting alias through another Field or Relation, and exact equivalence to
stage-entry snapshot semantics. Otherwise the sole planner selects bounded
staging. Non-aliased destinations follow their publication law's ordinary
direct or buffered admission. Users never select an execution path.

Caller-supplied gates and prefix counts use distinct `ParameterGate(slot)` and
`ParameterPrefix(slot)` controls. A computed prefix uses
`FieldPrefix(count_field_slot)`: the count Field is a singleton integer Field
published by a preceding stage, and the validated value must satisfy
`0 <= count <= length(stage.source)` before launch or publication. A computed
stage gate uses `FieldGate(bool_field_slot)`: the Field must be a singleton
Boolean scalar with proven total publication and empty behavior. A general
Boolean Field is a mask, not an implicit `any`/`all` gate. Mask-Field
selection, subset-Relation selection, parameter controls, Field-derived
controls, and provider failure/status gating use distinct typed `Control`
payloads. Provider status remains package-owned lifecycle state rather than a
user Field or parameter. No category is selected through a shared Symbol
lookup.

Cross-stage dependencies are determined by Field identity and stage order.
An access observes the Field at its current stage entry; the planner records
the nearest preceding publication to that Field when one exists. A
publication in the same or a future stage cannot satisfy that access.
Dependencies on distinct components of a compound result use the explicit
component Field identities. Port labels are diagnostics and evaluator-result
shape only, never producer identity.

An evaluator with multiple evaluator-fed value ports returns a `NamedTuple`
whose keys and order exactly match those value-port labels in publication
order. Algorithm-derived publication components do not appear in this tuple.
A one-value-port scalar evaluator is wrapped during construction into that
same one-field result ABI; the wrapper is callable-shape sugar and owns no
planning or inspection semantics. Duplicate labels, missing ports, extra
ports, wrong order, and inferred result-type disagreement reject before
execution; admission never probe-executes the callable.

Finite stage count has no scientific hard ceiling. In particular, the old
32-stage admission limit is deleted. The LM-0 cold-evidence barriers and
prepared stage grouping control compiler work while preserving one ordered
program, one planner, and one executor; no large-program fallback or second
representation is permitted.

The implemented LM-1 dispositions and forbidden-authority queries are maintained
in
[`design/audits/localmath-lm1-authority-cutover.toml`](../design/audits/localmath-lm1-authority-cutover.toml).
That file and the final LM-1 review evidence are the machine and review
authorities for the direct replacement. The historical LM-0 ledger remains the
baseline record; the explicit flagship amendment above governs the one
structural identity that LM-1 intentionally deletes.

LM-1 review requires all four committees to verify:

- exactly one `LocalWork`/stage-tuple semantic waist and one bound envelope;
- stable Space/Field/Relation identity and exact alias behavior;
- package-sealed proof ownership and rejection of extension self-certification;
- schema-epoch invalidation and allowed content-generation advancement;
- exact identity, fixed-degree, packed, affine, inverse, runtime-key, subset,
  product/index, and boundary relation witnesses;
- positional binding/projection with no Symbol-keyed warm lookup;
- concrete type-stable CPU and real-GPU device views through the same KA path;
- unchanged publication, order, empty, failure, and scientific results;
- the LM-0 compiler envelopes and stage-group constraints still met;
- direct absence of every forbidden authority and no second execution route;
  and
- row-level deletion evidence rather than aggregate line-count claims.

LM-1 closed with approval from the compiler/Julia, GPU/performance,
scientific-modeling, and simplification/maintainability perspectives on
2026-08-22. The retained measurements, corrected findings, and final
dispositions are recorded in
[`LM-1 Final Review`](../design/evidence/localmath/lm1/final-review.md).

#### CorePotts lifecycle-compaction evidence

The LM-1 CorePotts cutover makes the ownership boundary executable. Site
indexing and request indexing are typed `Stage`/`Collect` programs over
`Space`, `Field`, `IdentityRelation`, and `FixedRelation`. Site collection
uses bounded owner grouping, source order, and persistent source position;
request collection uses one group, the exact canonical request key/identity
order, and persistent source position. Both bind directly to canonical
`CompactedStorage` on CPU and GPU. A closed lifecycle gate publishes nothing,
and neither path performs a host count read or warm-path conversion.

Lifecycle trigger evaluation and its first-failure `ProgramStatus` reduction
remain CorePotts-owned because they interpret cadence, domain kind,
generation, source/action identity, evaluator result, MCS, and lifecycle stage.
They execute as typed KernelAbstractions kernels over
`_LifecycleDecisionRuntime` on the same device and queue as the two
LocalWorksets compactions. The status law is a deterministic canonical
first-failure scan with preserve-on-empty and preserve-when-gated semantics.
This is one CPU/GPU execution path, not a fallback: the former opaque science
vector, topology objects, runtime submission slots, singleton route/identity
wrappers, and legacy LocalWorksets emission/status programs are deleted.

Focused evidence records exact grouped site records and segment starts,
canonical active-request order, source-position provenance, gated no-write
behavior, deterministic first-failure selection, package load, and absence of
the deleted authorities and raw backend-specific kernels. Full runtime
construction is credited only when the adjacent lifecycle-selection storage
schema passes its independent boundary gate.

Lifecycle selection now closes that adjacent boundary with one explicit
scientific ownership split. CorePotts performs cross-request conflict over
anchors, planned sites, and packed relationship incidence, then performs the
finite cell-resource transaction (high water, canonical free cells and
demands, capacity, generation overflow, allocation, and exact status
provenance) in one deterministic KernelAbstractions kernel. This meaning is
not a generic publication law and is therefore not hidden inside an
array-capturing Stage evaluator. CPU and GPU use this same device path over
canonical `PackedRelationshipBank` reads with no host count or array
roundtrip.

On success, the kernel exposes typed per-request selection, allocation, key,
and identity fields to one ordinary LocalWorksets `Stage`/`Collect` law. That
law alone owns canonical selected-request publication and persistent
source-position provenance, and runs on the same backend queue. The former
13-stage selection prototype, `CompactedResult` views, topology/route/slot
adapters, and compacted accessor authority are deleted rather than retained
as a migration path. Focused CPU evidence is the independent physical
differential oracle (8/8), the independent decision oracle (15/15), package
load, exact forbidden-symbol absence, and a single KA-kernel/no-Metal source
inventory. Real-GPU and independent committee evidence remain separate LM-1
gate requirements.

#### CorePotts checkerboard proposal and accepted-copy disposition

The checkerboard proposal remains one CorePotts-owned KernelAbstractions
kernel until the LM-6 `ResourceAccess` compiler prerequisite below exists.
Its evaluator interprets canonical Hamiltonian source order, before/after
proposal state, semantic RNG addresses, tracker resources, and packed
relationship incidence. Wrapping that kernel in an opaque LocalMath evaluator
would move no meaning into the common waist and would reintroduce a second
execution authority. The obsolete LocalWorksets proposal wrapper is therefore
deleted; CPU and GPU use the same Core-owned kernel and caller ABI.

Accepted-copy field publication, claim clearing, and claim arbitration follow
the same rule where they implement Core-owned proposal and acceptance meaning.
Accepted relationship publication additionally applies a transaction over an
evolving packed relationship bank: copy live to staged storage, canonicalize
events by `(order_key, order_identity)`, apply the exact ordered recurrence,
and publish the staged bank only through the accepted gate. This remains one
Core-owned KernelAbstractions path. `BoundedWrites` and `FoldStep` remain only
as the domain-neutral typed update vocabulary; no deleted LocalWorksets plan,
event, scheduler, or selector survives around the algorithm. Runtime state is
always `PackedRelationshipBank`; unpacked `ProgramRelationshipState` is never
constructed, stored, or dispatched on in this warm path.

LM-1 storage admission now supports only centrally qualified structured Stage
results. A record is admitted when its complete leaf tree has an exact reviewed
backend load/store capability and its layout satisfies the bounded record
profile. This admits the required `StageEvaluation{Float64}` field reads on
qualified backends without admitting arbitrary records, pointers, references,
or unsupported scalar leaves, and without promoting `Float64` to an
unqualified GPU backend.

The focused boundary evidence is recorded in
[`design/evidence/localmath/lm1/c3-corepotts-checkerboard-boundary.md`](../design/evidence/localmath/lm1/c3-corepotts-checkerboard-boundary.md).

### LM-2A -- Publication and planning consolidation

Consolidate remaining publication, qualification, workspace, and planning
authorities onto the LM-1 stage-local spine. Unify output schemas,
multiplicity, route validation, ordering, capacity, evidence, workspace
requests, and failure closure behind the common publication basis. Preserve
physically distinct algorithms only where their laws require them; they still
share semantic validation, planning, lifecycle, and status authorities.

Generalize or delete conjunctive resolution. A surviving mechanism must be a
domain-neutral multi-resource law with unrelated witnesses. Consolidate keyed
and fixed routing without erasing useful representation evidence. Delete
replaced group types, tuple projections, validators, launch helpers, and
settlement machinery in the same edit. Preserve the LM-1 four-stage inventory
at exactly 21 stage-local physical phases and retain every transaction barrier.
The one program-scope status reset that precedes those phases is a lifecycle
gate, so the CPU submission queues 22 KernelAbstractions launches in total.
Dynamic relationship validation may add its separately reported receipt
launches. Evidence and documentation MUST state which of these counts they
report rather than presenting 21 as the complete provider-launch count.

### LM-2B -- Exact dependencies and execution receipts

Strengthen the sole existing `WorkEvent` implementation in place toward the
final lifecycle:

```julia
receipt = execute!(prepared; parameters = (;), dependencies = ())
wait(receipt)
waitall(receipts...)
```

LM-2B changes semantics and internals only. The public spellings remain
`WorkEvent` and `run!` throughout this gate; LM-3B performs the single atomic
rename to `ExecutionReceipt` and `execute!`. No alias or compatibility path is
introduced at either boundary.

Each provider scope is one LocalMath-owned logical submission scope for a
backend, device, and owner task. Launches issued through it rely on KA backend
implicit ordering; no portable queue object is assumed. The scope owns
monotonically increasing submitted and physically settled ordinals. Each
receipt owns its scope identity, ordinal, plan-local lease/generation, exact
status and publication references, dependencies, and provenance.

An unresolved dependency is admitted only from the same scope with an earlier
ordinal. Settled success is admitted from any scope. Unresolved cross-scope
dependencies reject and require an explicit caller wait. Settled-failed
dependencies reject before launch. An unresolved same-scope dependency adds
one fixed-signature, one-lane KernelAbstractions status join before the
existing gate-only stage phases. The join monotonically closes the consumer
status when its producer failed; it never carries receipt identity,
dependency arity, evaluator type, or scientific data into a stage kernel.
Exact failure identity and argument order remain host-side receipt semantics.
An unresolved failure therefore device-gates all dependent publication and is
recorded in the dependent receipt with predecessor provenance. Semantic failures do not poison the
scope; independent submissions and corrected new submissions remain legal.
Provider failure poisons the scope.

Waiting beyond the settled ordinal synchronizes the current provider tail;
physical settlement may cover later submissions, but only requested logical
receipts are resolved and released. `waitall` orders scope groups by first
occurrence, settles every required group once, caches all observed statuses,
and then selects the earliest failure in original argument order. No native
event API, raw backend event, scheduler, task graph, provider-specific
scientific branch, or second executor is introduced.

Dependency identities, ordinals, generations, and producer-plan identities
remain runtime values. Device dependency status uses one canonical ABI for
every arity. Base provider-launch counts are unchanged when no unresolved
dependency exists; a submission with `U` unresolved dependencies adds exactly
`U` joins, while settled-success dependencies add none. Dependency tuples,
fixed maximum packing, and arity-specialized aggregation kernels are
forbidden. Compatible receipts from different producers and programs reuse
the same join and stage method instances.

Qualify dependency arities 0, 1, 2, 4, and a wider fan-in witness; successful and failing chains;
same-scope ordering; cross-scope rejection and post-wait admission; idempotent
waiting; deterministic failure order; receipt lifetime safety; bounded host
bookkeeping; method-instance reuse across changing receipt identities and
producer plans within one schema; zero warm compilation; and a real GPU.

### LM-2C -- Internal inspection substrate

Establish one canonical structural description of the existing semantic and
planned values. It covers reads, writes, routing, publication and conflict
laws, ordered stages, relation/topology footprints, workspace/lifetime needs,
planned physical phases, specialization families, source provenance, and an
equivalence signature. Syntax trials, diagnostics, halo reporting, and
compiler evidence consume this authority.

This substrate describes `LocalLaw` and its plan; it is not another
executable IR, lowering pass, scheduler, or public object hierarchy. Cold
metadata may be type-erased, while executable phases, device views, and scalar
callables remain concrete.

The direct cutover uses one ordinary immutable named-tuple schema:

```julia
(
    lifecycle,
    parameters,
    relations,
    stages,
    planning,
    equivalence,
)
```

Prepared inspection adds exactly one `realized` member. `ExecutionReceipt` remains a
narrow logical-receipt report and never embeds a prepared program. The
`equivalence` member is an exact comparable semantic tuple, not a hash; it is
identical for the work, plan, and prepared views and excludes provenance,
backend, proofs, bindings, storage, workspace, and mutable execution state.

`Plan` stores only the bound law, backend, and lowering. It has no stored
evidence field or evidence type parameter. Relation facts project each sealed
`RelationProof` once in semantic first-use order. Stage records refer to those
relations directionally and derive producer dependencies from the existing
stage projection. Workspace facts come only from `_WorkspaceAuthority`,
including alias scope, lifetime, and lease scaling. Physical phases are
compact ordered `(kind, count)` facts derived beside their launch owners; they
contain no kernel callable or execution behavior.

Launch accounting distinguishes stage-local and complete provider work. The
frozen four-law witness is `1 + 7 + 7 + 6 = 21` stage-local launches. The
unconditional program-status reset makes 22 complete provider launches. A
nonempty relationship guard adds `3V + 1`, where `V` counts dependencies with
concrete content validators; `_NoRelationContentValidator` adds no validation
triple, and an empty guard adds nothing. Benchmark-side phase reconstruction is
forbidden; benchmarks consume these source-owned inspection facts.

LM-2C introduces no report type, cache, registry, trait protocol, scheduler,
task graph, public inspection-level selector, or compilation-report API.

### LM-2D -- Foundation stabilization and qualification

Close the remaining foundation blockers before private grammar work. The root
package's unchanged public construction-through-one-MCS workload executes
inside `PrecompileTools.@compile_workload`, which supplies the latest-world
boundary required by KernelAbstractions CPU tasks during package
precompilation. The workload is not suppressed, caught, moved to `__init__`,
or replaced by artificial `precompile` declarations.

The investigation also found that KA index macros must occur as standalone
kernel expressions before scalar conversion. The lifecycle emission kernel
therefore binds `@index(Global, Linear)` first and converts that binding to
`Int32`; nesting `@index` inside the conversion bypassed KA's CPU rewrite and
reached its GPU intrinsic. This is a source correction on the one KA path, not
a precompile fallback or backend branch.

CorePotts and its tests make no portable claim about the return value of a KA
kernel launch. Checkerboard proposal, acceptance, claim, commit, and report
work remains implicitly ordered on the same backend/provider queue and is
settled only at the existing explicit synchronization or receipt boundary.
Scientific checkerboard oracles compare dispositions and state, not fictional
native events.

Inspection continues to derive producer dependencies cold through the one
`_stage_planning_entry` authority. This recomputation is not stored in
`Plan`, lowering entries, or prepared state. LM-4 may optimize inspection
only if measurement shows material cost; it may not add a second dependency
authority.

LM-2D closes only when root precompilation and cached loading succeed, the
ordinary LocalMath and affected CorePotts/root tests pass, CPU and Metal
inspection agree outside backend/device/storage realization, the real-Metal
Stage and execution-receipt witnesses pass, and the frozen compiler witnesses
retain their existing ceilings and launch counts. LM-2D adds no semantic law,
public API, executor, kernel family, scheduler, report type, or gate script.

Current qualification status (2026-08-23): LM-2D passes. The implementation,
root precompilation, cached load, 832-test LocalMath suite, exact launch
counts, zero warm compilation, and current Metal packets pass. After replacing
tuple-specialized workspace-template discovery with one cold ordered builder
and deleting duplicate per-Stage workspace validation, fresh-process host
compilation is 2.411 s at one Stage and 11.304 s at four Stages. These pass the
frozen 2.851 s and 15.047 s ceilings without changing semantics, workspace
authority, physical launches, or the CPU/GPU execution path.

### LM-3A -- Private grammar and CorePotts feasibility

Implement and exercise the mathematical grammar privately against complete
stencil, D2Q9, LSM, matrix-free FEM, deposition, graph forward/inverse, Potts
proposal-resolution, and bounded PGS/RSA witnesses. Every form lowers to the
same typed laws and execution path as explicit constructors. Concrete isbits
Julia callables remain first-class; symbolic scalar expressions are optional
inputs and never a runtime execution authority.

At the same gate, prove the CorePotts waist with a cold, test-only lowering:

```text
ResourceAccess
-> typed Field, Relation, and parameter requirements
-> bounded gathered context layout
-> programmatic LocalLaw
```

The feasibility witness must preserve canonical descriptor source order,
semantic RNG addressing, affected-footprint evidence, packed relationship
access, and terminal provenance. It creates no production checkerboard path,
opaque proposal packet, array-bearing evaluator, fallback, or retained
parallel runtime.

Current implementation status (2026-08-24): the unexported
`LocalMath.@localmath` macro lowers directly to `Stage`, `Publication`, and
`LocalLaw`. It covers required and sample-aware reads, parameters and gates,
multi-port and multi-stage composition, Unique, Reduce, Resolve, Collect,
OrderedFold, fixed routing, and explicit runtime routing. Routed Collect uses
a typed dense group key distinct from the stored record. Publication equations
carry independent `SourceOrigin` values. Ordinary CPU witnesses cover
dimension-parametric stencil, two-stage D2Q9 collide/pull-stream with nine
scalar streaming ports, lattice-spring fracture and
assembly, matrix-free FEM, CIC/TSC deposition, graph gather/inverse scatter,
runtime-routed z-buffer resolution, an authored ordered-Hamiltonian Potts
proposal/resolution law, and authored bounded PGS/RSA recurrence
against independent references. CorePotts now exposes a pure descriptor-major
typed `ResourceAccess` requirement projection, and a test-only programmatic
LocalLaw witness preserves Hamiltonian evaluation order, consumes a
generation-qualified packed relation, and retains semantic RNG coordinates
without entering the checkerboard runtime. Development evidence lives in
the ordinary Julia testsets and witness sources; LM-3A introduces no hashed
evidence manifest, custom gate script, or alternate executor. Focused Metal
tests execute authored parameterized Unique, deterministic Reduce, routed
Collect, and the authored RSA/PGS ordered recurrences through the same packed
KernelAbstractions executor. A separate focused CorePotts feasibility witness
executes generation-qualified packed reads, ordered Hamiltonian arithmetic,
and deterministic Resolve publication on Metal without entering the production
checkerboard. Routed Collect also removed one stale undefined atomic helper
from the existing GPU path.

Scientific storage authoring is part of the same private grammar gate. The
canonical descriptor-pair `bind` form is now used by every authored scientific
witness. Caller-owned arrays retain identity. `Allocate(undef)`, exact element
fills, exact-shape and exact-element-type source copies, recursive relation
storage copies, and law-derived empty Collection storage are explicit cold
operations on a supplied KernelAbstractions backend. Ambiguous conversion is
rejected. A conservative stage-order analysis admits `undef` only when a prior
unconditional, total, identity-routed Unique publication proves definite
initialization before every read, control use, or preserve-on-empty
publication. Allocation declarations and initialization evidence disappear at
binding; the existing plan, prepared representation, workspaces, receipts, and
physical kernels are unchanged. `storage(bound, descriptor)` validates stable
semantic identity and schema equality and exposes the exact resulting storage.

### LM-3B -- Atomic public identity and authoring cutover

Status: implemented as a repository-wide direct cutover. The UUID and version
remain continuous; the old package and API identities have no aliases or
forwarding methods. `@localmath`, descriptor-keyed `bind`, keyword-only
`execute!`, and the qualified advanced law constructors all use the existing
typed planning and KernelAbstractions execution path.

Perform one direct rename and public exposure:

```text
lib/LocalWorksets        -> lib/LocalMath
module LocalWorksets     -> module LocalMath
LocalWork                -> LocalLaw
WorkPlan                 -> Plan
PreparedWork             -> PreparedPlan
WorkEvent                -> ExecutionReceipt
LocalWorkValidationError -> LocalMathValidationError
run!                     -> execute!
@localwork               -> @localmath
```

Expose only grammar already proven in LM-3A. Macro and constructor forms call
the same canonical constructors and agree in semantic signature, binding,
workspace, planned phases, backend admission, and determinism. Update
package metadata, modules, documentation, tests, benchmarks, and downstream
code together. Delete all old identities in the same edit; add no aliases,
deprecations, forwarding package, old/new selector, or temporary public
`@localmath` over the old representation. The grammar remains pre-release and
revisable until LM-7.

### LM-4 -- Inspection and diagnostics

Status: implemented. The qualified inspection surface remains the one cold
named-tuple projection; semantic fields are separated from revisable planning
and realization observations. Structured `LocalMathValidationError` rendering
and exact `SourceOrigin` propagation cover stage lowering, preparation,
enqueueing, settlement, and dependency failures without assigning provider-wide
failures to an arbitrary stage. The manual documents the classification and the
CPU/Metal inspection and diagnostic witnesses exercise the same production
path. No inspection selector, compilation report, cache, stored evidence, or
execution dependency was added.

Document and harden the existing qualified inspection methods:

```julia
LocalMath.inspect(law)
LocalMath.inspect(plan)
LocalMath.inspect(prepared)
LocalMath.inspect(receipt)
```

Inspection remains one cold immutable named-tuple projection derived from the
semantic law, relation proofs, lowering, workspace authority, prepared runtime,
and receipt state. It is never stored, cached, or consumed by planning or
execution. Documentation distinguishes stable scientific and operational
contracts from current physical observations such as concrete types, methods,
workspace layout, and launch structure.

Diagnostics retain equation-level `SourceOrigin` through construction,
binding, planning, preparation, execution settlement, and dependency failure.
`LocalMathValidationError` presents the relevant contract, authored source,
and recovery hint without introducing a diagnostic object hierarchy.

Ordinary package tests cover projection consistency, provenance, useful error
messages, CPU/GPU semantic agreement, and the absence of syntax or inspection
objects from execution. Focused reproducible benchmarks investigate
compilation and allocation separately. LM-4 adds no inspection-level selector,
compilation-report API, risk score, cache, evidence object, or compiler
authority.

### LM-5 -- Cross-domain validation

LM-5 is carried out as ordinary development slices whose names describe their
scientific scope:

- **LM-5A -- witness consolidation:** one production law and one independent
  numerical oracle per example; delete redundant constructor implementations;
- **LM-5B -- structured transport:** dimension-parametric stencils and D2Q9
  collision/streaming;
- **LM-5C -- mechanics and operators:** lattice-spring mechanics and
  matrix-free FEM application;
- **LM-5D -- routing and topology:** CIC/TSC deposition, graph gather/scatter,
  and deterministic routed resolution;
- **LM-5E -- bounded stateful laws:** collection consumers and ordered
  recurrence witnesses through the sole LocalLaw execution path;
- **LM-5F -- Potts feasibility:** a focused authored proposal calculation and
  deterministic resolution while CorePotts retains its scientific authority;
- **LM-5G -- backend and documentation qualification:** the same law builders
  on CPU and a real GPU, public semantic inspection, and current documentation;
  and
- **LM-5H -- authoring ergonomics:** anonymous spaces, flat descriptor pairs,
  composed preparation, Cartesian boundary-aware notation, authored collection
  pipelines, and declarative ordered state on the sole execution path.

LM-5H implements compact Cartesian-index stencil notation as a front-end
spelling for existing bounded affine relations, for example:

```julia
@localmath (i, j) ∈ interior(grid, 1) begin
    laplacian[i, j] = u[i - 1, j] + u[i + 1, j] +
                      u[i, j - 1] + u[i, j + 1] - 4u[i, j]
end
```

Cartesian indexing is macro syntax only: it lowers directly to the
same `LocalLaw` relation reads, planner, packed storage, and
KernelAbstractions executor. It must not introduce a Cartesian storage
authority, stencil IR, dimension-specific kernel family, alternate executor,
or inferred out-of-bounds behavior. Static offsets such as `i ± 1` should be
recognized without materializing generic adjacency. Dynamic indexing is
admitted only when it can be expressed as an existing bounded relation with an
explicit boundary contract. The `u[i ± 1, j]` shorthand is deliberately
absent; explicit Julia offsets retain unambiguous value shape and ordering.
Interior affine relations carry an explicit embedding origin separately from
their binder-relative offsets. Execution therefore maps the reduced source
domain into its parent while inspection reports conventional directional
halos. Any authored offset wider than the declared interior halo rejects during
construction.

LM-5A through LM-5G are implemented. LM-5H retains descriptor-keyed scientific
storage while replacing categorized binding keywords with a flat pair sequence
and composing binding, planning, and preparation behind the ordinary
`prepare(law, pairs...; backend)` call. Storage-free computed relations require
no placeholder pair. Explicit `bind` and `plan` remain the same cold
boundaries for compilers and inspection, not an alternate path. Collection and
advanced recurrence notation is adopted where the witnesses prove static
bounds, ordering, initialization, and conflict semantics. The authored
collection and ordered-state forms replace the former witness-only constructor
plumbing rather than coexist with it.
Ordered recurrence evolves package-owned shadow state and commits destinations
only from the existing finalization phase after all ordered writes validate, so
late failure preserves the complete stage-entry destination state.

Validate the public authoring and execution model across a
dimension-parametric structured stencil and D2Q9, lattice-spring mechanics,
matrix-free FEM, CIC/TSC deposition, graph gather and scatter, deterministic
routed resolution, bounded ordered recurrence, and a focused Potts proposal
calculation.

Each scientific example has one public-API `LocalLaw` implementation and one
independent host-side numerical oracle. Ordinary equations use `@localmath`;
collection consumers and advanced recurrence use the same public authoring
language. Qualified constructors remain compiler tools and owning-package unit
test fixtures, not scientific witness implementations. The oracle computes the expected scientific result
directly from fixture data; it does not construct a `LocalLaw`, plan work,
invoke KernelAbstractions, or become a second executor. Complete duplicate
production implementations are deleted. Macro and constructor equivalence
remains covered by compact LocalMath unit fixtures for individual language
constructs.

Each example is parameterized by storage constructor and backend so CPU and
GPU execute the same law-building function. Two- and three-dimensional cases
use the same dimension-parametric implementation. Tests compare numerical
results exactly or within the tolerance declared by the scientific law. They
exercise ordering, empty behavior, overflow, or failure atomicity only where
the example depends on that property. Generic receipt, allocation, compiler,
and lifetime contracts remain in LocalMath's owning tests.

Scientific examples may inspect public semantic facts such as source origin,
read and publication relations, conflict law, and declared footprint. They do
not return or assert compiler identities, stage or launch counts, workspace or
execution slogans, backend type names, self-certified evidence booleans,
milestone schemas, or unmeasured synchronization claims. Ordinary package
tests and one applicable real-GPU run exercise the shared examples; focused
benchmarks are used only when performance is under investigation.

Topology claims are representation-specific. Fixed structured offsets report
exact directional read and reverse-publication footprints. Interior and
boundary regions are reported only when current relation extents and ownership
prove them. Graph laws report endpoint and ownership intersections rather than
inventing geometric depth. Runtime and packed relations remain bounded or
opaque until their prepared proofs justify a stronger result. LocalMath does
not construct communication plans, partitioning policy, MPI operations, or a
distributed scheduler. Three-dimensional laws remain dimension-parametric and
create no new executor or dimension-specific kernel family.

### LM-6 -- CorePotts adoption

CorePotts retains `ResourceAccess`, descriptor order, Hamiltonian and proposal
meaning, semantic RNG, Metropolis acceptance, scheduling, lifecycle
transactions, algorithm and backend admission, and checkpoint continuation.
Its compiler lowers eligible local mechanics directly into public LocalMath
descriptors and `LocalLaw` values. No intermediate requirements IR, adapter,
alternate executor, or stored inspection evidence survives lowering.

The first direct cutover replaces checkerboard proposal evaluation and
deterministic resolution. In the same edit:

- lower the Core-owned descriptor analysis directly to one LocalMath law;
- bind and prepare that law through the ordinary LocalMath path;
- preserve canonical Hamiltonian order, semantic RNG addressing, proposal and
  acceptance meaning, transaction atomicity, status propagation, checkpoint
  continuation, and the stated scientific contract on CPU and GPU;
- require exact cross-backend equality only where the ordering and numerical
  contract promises it; and
- delete the replaced CorePotts preparation, operation, kernel, wrapper, and
  any temporary compiler records.

Subsequent operations are converted independently only when the edit removes a
physical implementation, preserves domain ownership, and uses the existing
LocalMath execution path. Selection, bounded gathering, local evaluation,
routing, and publication are natural candidates. Core scheduling,
transactions, lifecycle, Hamiltonian, acceptance, RNG, and checkpoint
mechanisms remain Core-owned. Coverage is determined by semantic ownership and
source deletion, not a target percentage.

Use ordinary CorePotts, LocalMath, integration, checkpoint, and applicable
real-GPU tests, plus focused comparative benchmarks when performance is
affected. Retain no conversion ledger, temporary bridge, percentage target,
or old/new runtime.

### LM-7 -- Release readiness

Declare and document the supported public names, grammar, inspection, and
extension interfaces under ordinary semantic versioning after cross-domain
consumers and CorePotts use them through public APIs. Release claims only the
scientific semantics and hardware backends exercised by ordinary package,
integration, documentation, and real-device tests. Floating-point expectations
are stated per law and backend rather than through a general qualification
label.

Repeated execution of the same `PreparedPlan` and submission schema performs
no LocalMath dynamic code generation, relationship packing or unpacking,
symbolic construction or interpretation, host callback, or package-owned
device or algorithmic-workspace allocation. `execute!` enqueues work without
settling the provider; `wait` and `waitall` are the explicit settlement
boundaries. Receipt and submission state has bounded ownership and lifetime
and retains no unbounded history.

Inspection reports only semantic, topology, workspace, and realization facts
derived from their production authorities. Exact integer, ordering, status,
empty, overflow, and failure behavior is tested directly. Relation footprints
remain explicitly exact, bounded, or opaque according to their current proofs.
Distributed communication and scheduling are outside the release contract.

## Ordinary review and performance development

Technical review considers scientific meaning, Julia API quality, semantic and
execution authority count, GPU portability, performance, and maintainability.
Corrections edit the sole implementation directly; reviews do not create
qualification artifacts or authorize compatibility shims, selectors,
provider-specific scientific paths, or parallel production implementations.
Run the ordinary package, integration, documentation, and applicable
real-device tests for every affected contract.

Use representative one- and multi-stage compiler workloads and complete
scientific programs as reproducible benchmarks for compilation, allocation,
and launch comparisons. Record the Julia version, dependency environment,
backend, device, workload, and measurement method for performance claims.
Machine-dependent wall-clock observations, fitted timing equations, exact
launch layouts, and arbitrary tuning percentages do not become development or
release gates. Physical phase measurements remain useful for finding redundant
work, while tests preserve the semantic visibility and failure barriers those
phases implement.

## GPU and performance contract

LocalMath uses KernelAbstractions as its sole execution boundary.

Production execution obeys:

- one semantic and planning path for CPU and GPU;
- canonical packed runtime relationships on every backend and device;
- after runtime construction, no production execution subsystem owns, stores,
  mutates, or dispatches on unpacked `ProgramRelationshipState`;
- runtime relationship state uses canonical `PackedRelationshipBank` storage
  on CPU and GPU alike;
- `ProgramRelationshipState` exists only as a cold host construction,
  transaction-input, or serialization-boundary value and is packed before it
  enters execution state;
- conversion to or from `ProgramRelationshipState` never occurs during queued
  execution, device settlement, lifecycle processing, or any other warm path;
- no raw CUDA, AMDGPU, Metal, or oneAPI launch in LocalMath;
- no runtime backend-name branch in a law;
- no warm device or algorithmic-workspace allocation after preparation;
- no warm relationship packing/unpacking, symbolic construction or
  interpretation, or host callback;
- host receipt and submission state has bounded ownership and lifetime and
  retains no unbounded execution history;
- fields, relations, workspace, gates, and semantic/publication status state
  remain on the selected device throughout execution; `ExecutionReceipt` is a
  bounded host handle referencing that state;
- `execute!` introduces no explicit synchronization; launches use KA implicit
  ordering and exact logical `ExecutionReceipt` dependencies, while `wait` and
  `waitall` are the explicit settlement boundaries;
- caller-owned or plan-owned bounded workspace prepared before execution;
- no fusion that changes visibility, order, ties, overflow, or numerical
  policy.

Inspection exposes only topology facts established by the current relation and
proof authorities. Structured relations may report exact directional
footprints; graph, packed, and runtime relations remain bounded or opaque when
their proofs do not establish more. LocalMath does not construct a distributed
communication plan, partitioning policy, MPI operation, or task scheduler.

## Scientific ownership

LocalMath may own:

- finite typed spaces;
- fields and storage placement contracts;
- bounded and affine relations;
- local selection and gather;
- scalar or fixed-size tensor evaluation;
- routed assignment and reduction;
- resolution with evidence;
- bounded ordered collection;
- ordered state recurrence;
- multi-output publication;
- finite stage sequence;
- topology, workspace, lifetime, device, and numerical validation; and
- inspection of these meanings.

Domain packages retain scientific interpretation. In particular CorePotts
retains Hamiltonians, canonical Hamiltonian order, before/after proposal
meaning, semantic RNG, Metropolis acceptance, MCS scheduling, lifecycle
transactions, checkpoint continuation, and CPM capability claims. LBM retains
collision and boundary-model meaning; LSM retains constitutive and fracture
meaning; FEM retains weak forms, quadrature policy, and solver meaning.

## Direct-edit and deletion policy

This is pre-release architecture work:

- no compatibility shims;
- no deprecated constructors;
- no old/new authoring selector;
- no old/new executor selector;
- no forwarding package;
- no per-domain adapter hierarchy;
- no public scheduler or task graph;
- no duplicated symbolic and executable authority; and
- no parallel production witness implementation.

Downstream domains MAY define concise `bind` conveniences for their own state,
but LocalMath does not accumulate one adapter type or method family per
scientific feature. New rich primitives are welcome when they are orthogonal
mathematical laws; convenience wrappers are not substitutes for such laws.

Tests and benchmarks are behavioral evidence, not a reason to preserve an
obsolete internal API. Reference interpreters and numerical oracles may remain
when structurally independent of production code.

Ordinary review checks that each addition reduces semantic duplication,
enables demonstrated reuse, or supplies a missing independently meaningful
law. Source added and deleted, compilation behavior, allocations, launches,
and witness readability may inform that review without becoming a parallel
ledger or qualification system.

Target structural metrics are:

| Measure | Final target |
|---|---:|
| Common semantic IRs | 1 |
| Private planning envelopes | 1 |
| Execution architectures | 1 |
| CPU/GPU semantic paths | 1 |
| Public authoring macros | 1 |
| User-authored route symbols in routine examples | 0 |
| User-authored destination-count tuples in routine examples | 0 |
| Compatibility shims | 0 |
| Domain branches in LocalMath | 0 |

## Rejection criteria

A cutover is rejected or revised if it:

1. adds `LocalLaw` above a surviving `LocalWork` rather than renaming and
   strengthening the waist;
2. retains both `@localwork` and `@localmath`;
3. introduces a runtime expression tree or general interpreter;
4. makes fields or relations capture host storage into device callables;
5. normalizes every topology into generic graph adjacency and loses affine or
   fixed-degree evidence;
6. makes assignment, tie, boundary, capacity, overflow, or order semantics
   implicit;
7. adds another CPU/GPU path or backend-specific scientific code;
8. preserves a superseded executor, topology API, or witness as a fallback;
9. hides warm allocation, host transfer, synchronization, or compilation cost;
10. adds domain meaning to LocalMath;
11. makes simple pointwise, stencil, or assembly code materially less readable
    than ordinary Julia and the relevant established DSL precedent; or
12. adds abstraction without deleting authority, duplication, or downstream
    machinery.

## Final acceptance

The LocalMath direct cutover is complete only when:

- the repository contains `LocalMath` and no production `LocalWorksets`
  identity;
- `LocalLaw` is the one strengthened spatial/publication IR;
- spaces, fields, and relations are typed and inspectable without a second IR;
- `@localmath` and programmatic constructors lower identically;
- old authoring and topology ceremony is deleted;
- unique assignment, reduction, resolution, collection, ordered recurrence,
  multi-output publication, bounded control, and stages execute through the
  same path on every advertised GPU backend;
- the stencil, LBM, lattice-spring, matrix-free FEM, deposition, graph,
  Potts-resolution, and bounded-recurrence witnesses use that path and
  independent numerical oracles;
- further CorePotts adoption deletes equivalent machinery;
- compilation behavior is characterized by reproducible representative
  benchmarks and has no unexplained material regression;
- warm execution remains packed, free of device and algorithmic-workspace
  allocation after preparation, KernelAbstractions-only, and without explicit
  synchronization in `execute!`; submission is nonblocking where the backend
  supports it, and host receipt bookkeeping remains bounded and measured; and
- public documentation can explain the package using spaces, fields,
  relations, laws, stages, and plans without requiring compiler vocabulary.
