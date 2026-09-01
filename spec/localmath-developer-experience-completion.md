# LM-12 — LocalMath developer-experience completion

Status: implemented in the current LocalMath contract.

## Summary

Complete LocalMath's developer experience without changing its mathematical
architecture or adding another authoring, planning, or execution authority.
The ordinary workflow remains:

```text
Space / Field / Relation declarations
        ↓
@localmath
        ↓
@prepare with explicit storage and backend
        ↓
execute! / wait / storage
        ↓
inspect and compilation_report
```

The research audit found that the language and setup model are already sound.
The remaining friction is incomplete Julia help, the absence of a standalone
first-run path, generic authored role names, implementation-shaped diagnostics,
and callable-qualification failures that do not explain their cause.

LM-12 is a direct polish phase. It adds no semantic IR, builder, descriptor
registry, stored report, backend inference, runtime diagnostic path, scheduler,
or executor.

## Audit baseline

- LocalMath exports 29 ordinary names and keeps 90 advanced interfaces public
  but qualified.
- Fifteen exported names and many qualified-public names lack a Julia help
  binding. The relation and boundary vocabulary is the largest gap.
- `@localmath` and `@prepare` have only one-sentence help entries despite
  owning closed syntax vocabularies that cannot be queried as functions.
- The scientific witnesses broadly use `@prepare`; setup syntax is not the
  remaining bottleneck.
- A law display currently reports counts such as `reads=1` and
  `publications=1`, uses `source` for both iteration domain and code origin,
  and does not expose authored roles or publication laws.
- Missing-binding errors aggregate correctly but render raw nested tuples,
  distinguish same-shaped fields mainly by UUID fragments, and include
  automatically derived computed relations among apparent supplied bindings.
- Callable capture and typed-effect qualification are centralized, but a
  failure generally reports only a rejected type or a Boolean qualification
  result rather than the first actionable cause.
- The witness corpus is comprehensive, while the manual's recipe page mostly
  points readers to repository files instead of presenting complete tutorials.

These are presentation, documentation, and cold-diagnostic problems except for
one explicit-constructor safety inconsistency corrected in section 1. That
direct semantic API correction does not change the mathematical language or
the one KernelAbstractions path.

## 1. Align explicit access meaning

Make direct compiler construction agree with mathematical authoring:

```julia
Access(field, relation)                 # required read
Access(field, relation; required=false) # explicit sample-aware read
```

Ordinary `@localmath` indexing is already required, while `samples(...)`
explicitly requests absence-aware access. The explicit constructor currently
defaults in the opposite direction. Change its default to `required=true` and
update every genuinely optional CorePotts, witness, and LocalMath call site
directly.

Total identity, affine, interior, and periodic reads retain their behavior.
Optional indexed, fixed, exterior, masked, and other incomplete reads must make
their absence semantics visible. Add no compatibility constructor or selector.
Inventory every active explicit `Access` construction in LocalMath, CorePotts,
PottsToolkit, tests, witnesses, benchmarks, and current documentation. Classify
each use from its scientific relation and evaluator meaning rather than making
a mechanical keyword replacement. Every intentionally absence-aware use must
spell `required=false`. Strict uses retain the required default even where
endpoint validity is established dynamically, and invalid endpoints fail
transactionally. Every total relation must retain identical observable
behavior, qualification, and physical lowering.

## 2. Complete Julia help and first-run discovery

Give every declared-public LocalMath name a useful help binding. Common
constructors must document:

- canonical signatures;
- mathematical meaning;
- whether physical storage is required;
- validity, boundary, empty, or ordering behavior;
- one compact example; and
- the most common misuse where relevant.

The `@localmath` help entry must document its complete closed vocabulary:

- scalar and Cartesian binders;
- `interior` and `periodic` contracts;
- required reads, `samples`, and `indices`;
- assignment, reduction, resolution, collection, and explicit publication;
- parameters, masks, gates, subsets, and prefixes;
- finite `@stage` composition;
- collection consumption;
- `@ordered` state and `halt_when`; and
- transparent function definitions and rejected dynamic behavior.

The `@prepare` help entry must explain borrowing, `allocate(undef)`, exact fill,
copy, collection allocation, explicit backend selection, accepted block syntax,
and the Pair API used by domain compilers.

Add one standalone ten-minute CPU quickstart beginning with:

```julia
using LocalMath
using KernelAbstractions

backend = KernelAbstractions.CPU()
```

The example must continue through descriptors, a total periodic law,
`@prepare`, `execute!`, `wait`, `storage`, and `inspect`. Explain why an interior
partial publication cannot safely use uninitialized output unless another
stage proves total initialization. Link the quickstart from the documentation
home and LocalMath README.

Source docstrings are the help-mode authority. The API manual must embed them
through Documenter rather than maintaining a second hand-written constructor
contract. Tutorials and troubleshooting may explain complete workflows and
failure recovery, but must link to rather than duplicate normative signatures
and semantics.

## 3. Preserve authored mathematical roles

Replace generic macro-generated access roles (`read_1`, `read_2`) and
publication ports (`port_1`, `port_2`) with deterministic names derived from
the lexical field, relation, access mode, and destination already known during
macro expansion. Repeated uses receive a deterministic suffix.

These existing access-role and publication-port fields are the authority; do
not add a friendly-name field, registry, descriptor alias table, or runtime
metadata. Explicit `Stage` authors and domain compilers retain the roles they
already provide. Source provenance remains excluded from semantic equivalence.
Generated roles must be stable across repeated expansion and collision suffixes
must follow one deterministic first-use rule. Ordinary display and inspection
must never expose `gensym` spellings, `read_N`, `port_N`, or underscored
implementation vocabulary for authored mathematical roles.

Use those roles to present laws as mathematics:

```text
stage 1
  domain: cells
  reads:
    signal via contact_neighbors — required
  writes:
    residual — canonical Reduce(+), preserve when empty
  control: mask=active
  origin: mechanics.jl:41
```

The ordinary `LocalLaw`, `Plan`, and `PreparedPlan` displays must:

- use `domain` for the iteration space and `origin` for source provenance;
- show read roles, access modes, relation families, publication destinations,
  conflict/empty laws, controls, and ordered stage position;
- keep abbreviated identities secondary and full identities in inspection;
- retain the physical segment, provider-launch, workspace, lease, and storage
  ownership summary for plans and preparations; and
- never plan, compile, allocate, submit, synchronize, settle, or mutate state.

Normalize semantic inspection so private implementation type names are not the
ordinary representation of anonymous or product space structure.

## 4. Make binding and publication failures actionable

Derive descriptor use sites transiently from the existing law:

```julia
(
    stage = 3,
    role = :contact_owners,
    use = :required_read,
    origin = ...,
)
```

For fields, distinguish reads, controls, fold state, and publication
destinations. For relations, report read/publication/control direction and
degree. For collections, report producer and consumer roles. For publication
failures, prefer the exact `Publication.origin`; use `Stage.origin` only as a
fallback.

Render missing storage as a concise ordered list containing authored role,
use, expected type/shape or relation layout, stage, origin, and a valid
correction. Show only user-supplied bindings as supplied; computed relation
closure must not appear as user input. Suggest `allocate(undef)` only when the
existing definite-initialization analysis proves it safe.

Evaluator-result errors must identify the mismatched publication port,
expected carrier, inferred result type, and equation origin. Preserve
`LocalMathValidationError` and its machine-readable contract fields; add no
special error hierarchy or stored requirements report.

## 5. Explain callable qualification failures

Keep the existing structural and typed-effect analyses as the sole admission
authority, but retain one cold, best-effort rejection fact while they run.

Structural capture rejection should report:

```julia
(
    path = (:evaluator, :material, :weights),
    type = Vector{Float32},
    reason = :array_capture,
)
```

Cover arrays, references, pointers, descriptors, runtime `Symbol` values,
mutable or non-isbits fields, unsafe type parameters, and non-callable values.
Hints should explain the valid representation, such as declaring arrays as
Fields and gathering them explicitly.

Typed-effect rejection should report the callable purpose, selected method,
analyzed signature, closest offending callee or operation, durable reason, and
recovery hint. Distinguish at least:

- no applicable method or signature mismatch;
- lowering or inference failure;
- unsupported method shape or return type;
- allocation or mutation;
- unsafe global access;
- foreign call;
- unresolved invoke or dynamic dispatch; and
- recursive or excessive-depth call graphs.

The closed analysis traverses the complete finite typed call graph. Method
memoization, active-method cycle detection, and the depth contract bound that
work; no arbitrary node-count ceiling may reject a larger otherwise-admitted
scientific evaluator.

Apply the same explanation to stage evaluators, Reduce operations, ordering
extractors, Collect grouping/order callables, bounded folds, and OrderedFold
transitions. Tests assert durable categories and paths, never raw SSA or
compiler-node text.

The rejection fact may live in the existing ephemeral cold analysis cache
during a planning attempt and while constructing an error. It must be absent
from `LocalLaw`, every successful `Plan`, `PreparedPlan`, inspection,
compilation reports, KernelAbstractions arguments, and runtime state.

## 6. Improve compiler inspection and dogfood the public SPI

Have `compilation_report(plan)` derive callable-admission facts from the
existing lowering authority:

- purpose;
- callable type;
- selected method;
- analyzed signature;
- inferred return type; and
- admission contract.

The prepared report adds only genuinely realized launch/provider facts. Store
no duplicate analysis report.

Selected Julia methods, typed signatures, and offending callees are
version-dependent observations. They are not serialization identities, stable
equality contracts, semantic equivalence inputs, or checkpoint facts. Tests
assert purpose, admission category, and semantic signature facts rather than
raw `Method` identity, SSA formatting, or compiler-node layout.

Update CorePotts construction only where required by the `Access` default
cutover or where one mechanically equivalent edit directly supports the
domain-compiler tutorial and deletes code. Any such simplification must retain
semantic equivalence, inspection, physical launches, and prepared types.
General SPI cleanup is not an LM-12 completion condition, and no Core-specific
wrapper may be added merely to shorten syntax.

Add one complete domain-compiler tutorial:

```text
domain requirements
→ Fields and bounded Relations
→ derived-key stage
→ gathered evaluator
→ multi-port publication
→ bind / plan / prepare
→ inspect / compilation_report
```

The example is Core-shaped but domain-neutral and uses only the supported
qualified public SPI.

## 7. Turn scientific witnesses into tutorials

Embed five complete, modest examples directly in the manual:

1. Cartesian periodic and interior stencil;
2. matrix-free FEM or graph gather/scatter;
3. deterministic Resolve/z-buffer;
4. bounded grouped Collect with downstream consumption; and
5. ordered RSA or PGS recurrence.

They must use the same public builders as the scientific witnesses and execute
as Documenter examples or doctests. The existing independent witnesses remain
the numerical authorities; documentation must not introduce parallel
production implementations.

Add a troubleshooting page organized by symptoms:

- missing storage;
- unsafe `allocate(undef)`;
- wrong relation direction or fixed-storage shape;
- required versus sample-aware access;
- invalid IndexRelation keys;
- captured arrays or non-isbits callables;
- typed-effect rejection;
- receipt and transaction failure;
- canonical versus relaxed numerical laws; and
- currently qualified CPU and Metal behavior.

## Validation

Use ordinary Julia tests and existing documentation and GPU programs.

- Every declared-public name has a Julia help binding.
- Help coverage is checked through Julia's ordinary
  `Base.Docs.undocumented_names(LocalMath; private=false)` inventory, not a
  milestone script or separate documentation registry.
- Macro help covers every accepted syntax family without creating fake
  callable exports for grammar-only words.
- The quickstart and five embedded recipes execute during the documentation
  build.
- Required access is the explicit-constructor default; intentionally optional
  access remains sample-aware on CPU and Metal.
- The active-source `Access` inventory classifies every use by intended
  required-versus-absence-aware meaning. Strict dynamic endpoints fail
  transactionally, intentional absence spells `required=false`, and total uses
  retain identical behavior.
- Required invalid indexed endpoints fail atomically on CPU and Metal.
- Authored roles are deterministic and macro/explicit laws remain
  structurally equivalent where their declared roles agree.
- Law, plan, and prepared displays show domain, roles, reads, writes, laws,
  controls, and origins without changing inspection or runtime counters.
- Missing bindings distinguish same-shaped descriptors, omit computed
  relations from supplied input, and preserve all authored uses and origins.
  Their `actual` facts contain only caller-supplied pairs, while the structured
  error retains the complete machine-readable missing requirements.
- Publication and evaluator-result failures retain the narrowest equation
  provenance.
- Capture and typed-effect failures identify the first actionable path,
  durable cause, method where available, and recovery hint.
- `compilation_report(plan)` and the prepared report derive consistent
  plan-owned callable facts.
- Simplified and explicit compiler constructions have equal semantics,
  inspection, launches, and numerical results.
- Complete LocalMath, scientific-witness, documentation, CorePotts,
  PottsToolkit, integration, and real-Metal suites pass on the repository Julia
  version.

Compare cold planning and preparation for representative laws because the
diagnostic traversal shares the existing analyzer. Investigate material
regressions on the sole path, but add no timing threshold or benchmark-specific
implementation. Warm execution, launch structure, allocation, synchronization,
and backend behavior must remain unchanged.

## Completion boundary

LM-12 is complete when a new user can discover, run, inspect, and debug an
ordinary law from Julia help and the manual, while a downstream compiler author
can identify the exact access, publication, capture, or typed operation that
failed qualification.

The following explicitness remains intentional:

- Space and Field declarations;
- explicit backend selection;
- explicit stored topology;
- explicit initialization, boundary, conflict, ordering, and capacity laws;
- qualified `storage` result retrieval; and
- the Pair API for dynamically generated bindings.

Do not add `@fields`, name-based binding, inferred outputs, inferred backend,
`prepared[field]`, a callback setup builder, access bundles, relation
expressions, a transaction builder, an adapter hierarchy, a new IR, a stored
diagnostic report, a public GPU trait, an alternate executor, or a compatibility
path.

No live product identifier may contain `LM-12` or another development-phase
name.
