# [LocalMath API](@id localmath-api)

LocalMath is the typed, bounded, conflict-aware local-computation substrate.
Scientific packages own model meaning and lower eligible spatial mechanics to
`LocalLaw`; LocalMath owns validation, planning, workspace, publication, and
one KernelAbstractions execution path on CPU and GPU.

The ordinary lifecycle reads like a local Julia setup block while retaining
exact descriptor-keyed storage ownership:

```julia
prepared = @prepare (law; backend) begin
    input = host_input
    output = allocate(undef)
    neighbors = host_neighbors
end
receipt = execute!(prepared; parameters=(;), dependencies=())
wait(receipt)
```

`@prepare` is hygienic syntax for the descriptor-to-storage Pair API. It
evaluates each expression once and lowers directly to `prepare`; no setup
object or allocation syntax reaches planning. The Pair API remains the
programmatic interface used by domain compilers. `bind` and `plan` remain
explicit tools when those intermediate values need inspection. Storage-free
computed relations are derived from the law; stored relations remain explicit.

Scientific arrays are caller-owned unless `LocalMath.Allocate` is requested at
the cold binding boundary. Planning, preparation, and warm execution never
guess or allocate omitted scientific storage.

```julia
prepared = @prepare (law; backend) begin
    input = input_array
    output = allocate(undef)
    neighbors = allocate(neighbor_storage)
end
output_array = LocalMath.storage(prepared, output)
```

`allocate(value)` fills a Field when `value` has its exact element type;
`allocate(source)` copies an exact-shape source array, including an ordinary
host array view on the qualified CPU and Metal paths, to independent backend
storage; and `allocate()` creates the exact bounded storage for a produced
Collection. A caller-owned `StructArray` is borrowed unchanged. Allocating one
copies its component arrays recursively and preserves the record layout.

`Collect(...; order=canonical_by(key, identity))` orders participating records
by their keys and identities, including tuple-valued keys. A closed participation
gate publishes an empty logical collection without rewriting backing records.
Duplicate canonical identities fail validation before changing the previously
published count or records. The ordinary CPU and Metal collection-order tests
exercise these behaviors across partial workgroups with bounds checks enabled.

### Sparse keyed update and rebuild

`KeyedReduce` updates one bounded keyed `Collection` without introducing a
second scheduler or storage authority. With `NewKeyIdentity`, prior records are
intrinsic input state and the identity initializes only keys absent at stage
entry. With `RebuildFromIdentity`, stage-entry keys and values are ignored and
every emitted key begins at the identity, so successful execution replaces the
complete logical collection. Both policies use the same failure-atomic
publication path.

```julia
import KernelAbstractions
import LocalMath

struct Contact end
struct ContactDeltas end

@inline function (::ContactDeltas)(contact::Int32, reads, parameters)
    owner = UInt32(isodd(contact) ? 1 : 2)
    delta = isodd(contact) ? Int32(1) : Int32(-1)
    return (; change = LocalMath.KeyedContribution(owner, delta))
end

contacts = LocalMath.Space(Contact, 4)
counts = LocalMath.Collection(LocalMath.KeyedValue{UInt32,Int32}, 8)
stage = LocalMath.Stage(contacts, NamedTuple(), (
        LocalMath.Publication(counts,
            LocalMath.KeyedReduce(UInt32, Int32, +;
                maximum = 1,
                seed = LocalMath.NewKeyIdentity(Int32(0)),
                retention = LocalMath.DropIdentityKeys());
            value = :change),),
    LocalMath.Evaluator(ContactDeltas()), LocalMath.Control(),
    LocalMath.SourceOrigin(:contact_counts, 1))
law = LocalMath.LocalLaw(stage)
prepared = LocalMath.prepare(law, counts => LocalMath.Allocate();
    backend = KernelAbstractions.CPU())
wait(LocalMath.execute!(prepared))
records = LocalMath.storage(prepared, counts)
```

With `NewKeyIdentity`, every exact-key segment folds its stage-entry value first
when one exists, then participating tuple lanes in canonical `(source, lane)`
order. Invalid prior counts, duplicate prior keys, and final capacity overflow
reject the whole publication, leaving its records and logical count unchanged.
`prepare` owns the bounded device workspace; execution performs no device
allocation. Public `execute!` and `wait` still allocate shared host
receipt/launch bookkeeping, which is tracked separately rather than claimed as
zero-allocation execution.

For `RebuildFromIdentity`, only participating contributions form the candidate:
every exact-key segment begins from the declared identity and then folds its
participating tuple lanes in the same canonical order. Stage-entry count, keys,
and values are not read or validated. Capacity, control, evaluator, and
predecessor-stage failure still suppress publication, leaving the complete
stage-entry collection observable until a successful replacement is published.

## Public surface

Ordinary authoring exports only the mathematical and execution vocabulary:

| Purpose | Names |
|:--|:--|
| Domains and values | `Space`, `Field`, `Relation`, `Collection`, `LocalLaw` |
| Relations | `IdentityRelation`, `AffineRelation`, `FixedRelation`, `ProductRelation`, `BoundaryRelation`, `RuntimeRelation`, `MaskedRelation`, `SelectedRelation`, `IndexRelation`, `InverseRelation`, `PackedRelation`, `compose` |
| Boundaries | `StrictBoundary`, `PeriodicBoundary`, `ExteriorBoundary`, `MaskedBoundary`, `GhostBoundary` |
| Author and execute | `@localmath`, `@prepare`, `prepare`, `execute!`, `waitall`, `workspace_requirements` |

The following names are public but intentionally qualified. They form the
storage, inspection, receipt, and domain-compiler SPI rather than the ordinary
equation namespace:

| Purpose | Qualified names |
|:--|:--|
| Lifecycle | `Plan`, `PreparedPlan`, `ExecutionReceipt`, `LocalMathValidationError`, `bind`, `plan`, `Allocate`, `Temporary`, `MutableRelationStorage`, `storage`, `inspect`, `compilation_report`, `execution_contract`, `lowering_identity` |
| Explicit laws | `Stage`, `Publication`, `Access`, `Control`, `SourceOrigin`, `Parameter`, `ParameterSchema`, `Evaluator`, `FieldPublication`, `CollectionPublication`, `FoldPublication`, `PublicationValue`, `sequence` |
| Collections | `CollectionAccess`, `CollectionCount`, `BoundedGroup`, `SourcePositionAccess`, `CompactedStorage`, `BoundedGroupView`, `KeyedValue`, `one_group`, `group_by`, `source_order`, `canonical_by`, `persistent_source_position` |
| Publication laws | `Unique`, `Reduce`, `Resolve`, `Collect`, `KeyedReduce`, `OrderedFold`, `TotalCoverage`, `PartialCoverage`, `UnreachableEmpty`, `PreserveEmpty`, `FillEmpty`, `IdentitySeed`, `ExistingSeed`, `NewKeyIdentity`, `RebuildFromIdentity`, `RetainAllKeys`, `DropIdentityKeys`, `CanonicalLeftFold`, `RelaxedAtomic`, `ArgMin`, `ArgMax`, `CanonicalSourceLaneTie`, `TieMin`, `TieMax`, `RejectOverflow`, `EmptyCollection` |
| Ordered state | `FoldComponent`, `InitializedState`, `initialized_state`, `BoundedWrites`, `FoldStep` |
| Bounded scalar operations | `fold`, `BoundedFold`, `Where`, `RejectInvalid`, `SkipInvalid`, `FillInvalid`, `RejectEmpty`, `RelaxedAssociative`, `BoundedFoldOutcome`, `evaluate_bounded` |
| Evaluator outputs | `UniqueValue`, `ConditionalUniqueValue`, `RoutedUniqueValue`, `ConditionalRoutedUniqueValue`, `Contribution`, `RoutedContribution`, `ResolutionValue`, `RoutedResolutionValue`, `CollectedValue`, `GroupedCollectedValue`, `KeyedContribution`, `FoldValue` |
| Advanced execution | `allocate_workspace`, `submission_capacity`, `ispending`, `success_gate` |

These qualified names are stable interfaces, not permission to access other
underscored LocalMath implementation details.

A Field-derived gate or prefix requires a preceding total publication from a
Stage without a whole-stage gate. Prefix, mask, and subset controls may filter
contributions without weakening successful publication totality. `Unique`
proves publication totality with `TotalCoverage`; `Reduce` proves it with
`IdentitySeed`, which initializes destinations even when no source contributes.
`ExistingSeed` retains previous destination state and does not prove a freshly
produced control value.

`SourcePositionAccess(collection, lane=1)` is a scalar selected-lane access:
for a producer item it returns the compacted position of that exact emitted
lane. It is not an array-valued `SourcePositions` API. The producer must request
`persistent_source_position()`, and `lane` must be within its static emission
width.

`LocalMath.Temporary()` is reserved for domain compilers declaring a Field
that is totally produced before its first read and is not scientifically
observable. It has no public `storage`; planning gives it bounded private
scratch, and a lifetime wholly contained by one pointwise segment is forwarded
without writing that scratch. Ordinary user Fields remain explicitly bound and
observable.

An empty pointwise source domain performs no evaluator calls or accesses to
its source and destination elements, including during backend preparation. Its control declarations
still apply: an open gate rejects an invalid runtime prefix, while a closed
gate suppresses that stage. Zero-length field views leave their backing
storage untouched.

An `OrderedFold` stage with a closed `Control` gate does not evaluate or order
events, run its recurrence, or publish its initializer over the retained
destination. This holds for parameter gates and gates produced by a preceding
total Field publication. Opening the gate restores ordinary ordered-fold
validation, including rejection of duplicate ordering identities.

An ordered transition returns `FoldStep(updates; valid, witness, halt)`. A
computed `valid=false` result rejects before that step changes private
accumulator scratch and reports its `Int32` witness together with the source
item and canonical position. The stage publishes no accumulator component when
any step is invalid. Ordinary scientific denial is not a validation failure:
return a valid step that records the denied disposition and omits the denied
state change.

## Bounded scalar operators

`LocalMath.fold` names the mathematical action and takes an already bounded
relation gather or collection group first. It does not accept arbitrary arrays
or iterators, and it does not create a symbolic runtime:

```julia
geometric_mean(values) = LocalMath.fold(
    values;
    map=log,
    combine=+,
    init=0.0f0,
    finish=(total, count) -> exp(total / count),
    domain=>(0.0f0),
    invalid=:reject,
    empty=:reject,
    order=:canonical,
)
```

Optional absent lanes do not participate. Present values outside `domain`
use `invalid=:reject`, `invalid=:skip`, or an exact fill value; empty inputs use
`empty=:reject` or an exact result fill. `finish(accumulator, count)` receives an
`Int32` count. Rejection uses the containing stage's existing transaction
barrier, so no output from that evaluation is published. Repeated endpoints
participate repeatedly and canonical relation or collection order is preserved.

Domain compilers construct `LocalMath.BoundedFold(T, map, combine, init,
finish; ...)` with the precise input type and policy values. That constructor
closes the map, accumulator, and result types before planning.

`order=:relaxed` grants permission to reassociate a fold. It does not select a
second executor; the canonical implementation remains valid. Bounded scalar
folding is distinct from the `OrderedFold` publication law for evolving state.

Common reductions use ordinary Julia vocabulary on those same bounded views:

```julia
total = sum(values)
smallest = minimum(values)
largest = maximum(values)
average = Statistics.mean(values)
geometric = LocalMath.geometric_mean(values)
```

Canonical relation or Collection order is retained and repeated endpoints
participate repeatedly. Absent lanes do not participate. `sum` returns the
typed additive identity on empty input; `minimum` and `maximum` reject an empty
transaction; `Statistics.mean` returns the ordinary correctly typed `NaN` for
empty input. Present `NaN`, infinity, and signed zero follow Julia's ordinary
numeric operations. `LocalMath.geometric_mean` accepts concrete floating-point
values and rejects empty input or a nonpositive present value.

## Inspection

`LocalMath.inspect` is qualified because it is tooling rather than ordinary
mathematical notation. It returns immutable named tuples projected from the
authoritative law, relation proofs, workspace authority, lowering, or prepared
runtime. It does not synchronize or mutate execution.

```julia
law_facts = LocalMath.inspect(law)
plan_facts = LocalMath.inspect(planned)
prepared_facts = LocalMath.inspect(prepared)
receipt_facts = LocalMath.inspect(receipt)
```

Focused views select facts from that same projection:

```julia
relations = LocalMath.inspect(prepared; level=:relations)
numerics = LocalMath.inspect(prepared; level=:numerics)
memory = LocalMath.inspect(prepared; level=:memory)
kernels = LocalMath.inspect(prepared; level=:kernels)
```

Relations and numerics are available for laws, plans, and preparations.
Memory and kernel facts require a plan or preparation because a law has no
physical workspace or launch structure. Receipt inspection remains narrow and
accepts no level.

`LocalMath.compilation_report(plan)` reports structural specialization
families, callable signatures, physical phases, relationship validation, and
workspace shape. The prepared form adds prepared launch types, the selected
callback `Method` records, parameter layout, dependency arity, and provider and
device facts. It does not expose `MethodInstance`s or a kernel argument-layout
ABI. It predicts no wall time and does not participate in planning.

The `parameters`, `relations`, `stages`, and `equivalence` fields describe
semantic structure. `planning` and `realized` describe the current compiler and
runtime implementation, including physical phases, specialization signatures,
workspace, callable admission, provider identity, and receipt counters. These
are observations, not a second compiler IR and not dispatch inputs.

## REPL presentation

`Space`, `Field`, `Relation`, and `Collection` values have compact displays
that expose mathematical shape, relation family, degree, storage requirement,
and abbreviated identity without printing implementation type parameters.
Displaying a `LocalLaw`, `Plan`, or `PreparedPlan` with the `text/plain` MIME
shows its descriptors, stages, provenance, workspace, ownership, and physical
segment summary. Presentation derives from the same semantic and inspection
authorities and never plans, allocates, submits, or synchronizes execution.

Binding diagnostics report all missing descriptors in scientific encounter
order. Fixed-relation shape errors report the expected degree/domain layout,
actual storage shape and element type, and a correction hint. See
[LocalMath relations and storage](@ref localmath-relations) for the relation
selection and binding table.

## Diagnostics

Contract failures throw `LocalMath.LocalMathValidationError`. Its fields are
machine-readable; normal display is a compact multiline explanation containing
only applicable facts:

```text
LocalMath validation failed: a required relation endpoint is out of bounds
  lifecycle: :execute
  contract: :relation_endpoint_bounds
  source: model.jl:24 (label: :stream)
  expected: 1:4096
  actual: 4097
  hint: correct the packed relation before resubmitting
```

Authored source provenance is preserved where a failure belongs to a stage or
publication. Provider-wide failures remain provider-wide rather than being
misattributed to the first stage.

## Reference

```@autodocs
Modules = [LocalMath]
Private = false
```
