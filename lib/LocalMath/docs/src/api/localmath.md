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
`allocate(source)` copies an exact-shape source array to independent backend
storage; and `allocate()` creates the exact bounded storage for a produced
Collection. A caller-owned `StructArray` is borrowed unchanged. Allocating one
copies its component arrays recursively and preserves the record layout.

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
| Collections | `CollectionAccess`, `CollectionCount`, `BoundedGroup`, `SourcePositionAccess`, `CompactedStorage`, `BoundedGroupView`, `one_group`, `group_by`, `source_order`, `canonical_by`, `persistent_source_position` |
| Publication laws | `Unique`, `Reduce`, `Resolve`, `Collect`, `OrderedFold`, `TotalCoverage`, `PartialCoverage`, `UnreachableEmpty`, `PreserveEmpty`, `FillEmpty`, `IdentitySeed`, `ExistingSeed`, `CanonicalLeftFold`, `RelaxedAtomic`, `ArgMin`, `ArgMax`, `CanonicalSourceLaneTie`, `TieMin`, `TieMax`, `RejectOverflow`, `EmptyCollection` |
| Ordered state | `FoldComponent`, `InitializedState`, `initialized_state`, `BoundedWrites`, `FoldStep` |
| Bounded scalar operations | `BoundedFold`, `bounded_fold`, `Where`, `RejectInvalid`, `SkipInvalid`, `FillInvalid`, `RejectEmpty`, `RelaxedAssociative`, `BoundedFoldOutcome`, `evaluate_bounded` |
| Evaluator outputs | `UniqueValue`, `ConditionalUniqueValue`, `RoutedUniqueValue`, `ConditionalRoutedUniqueValue`, `Contribution`, `RoutedContribution`, `ResolutionValue`, `RoutedResolutionValue`, `CollectedValue`, `GroupedCollectedValue`, `FoldValue` |
| Advanced execution | `allocate_workspace`, `submission_capacity`, `ispending`, `success_gate` |

These qualified names are stable interfaces, not permission to access other
underscored LocalMath implementation details.

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

## Bounded scalar operators

`LocalMath.bounded_fold` defines a concrete immutable operator over an already
bounded relation gather or collection group. It does not accept arbitrary
arrays or iterators, and it does not create a symbolic runtime:

```julia
geometric_mean = LocalMath.bounded_fold(
    log, +, 0.0, (sum, count) -> exp(sum / count);
    domain=LocalMath.Where(>(0)),
    oninvalid=LocalMath.RejectInvalid(),
    onempty=LocalMath.RejectEmpty(),
    order=LocalMath.CanonicalLeftFold(),
)
```

Optional absent lanes do not participate. Present values outside `domain`
follow `RejectInvalid`, `SkipInvalid`, or `FillInvalid(value)`; empty inputs
follow `RejectEmpty` or `FillEmpty(value)`. `finish(accumulator, count)` receives
an `Int32` count. Rejection uses the containing stage's existing transaction
barrier, so no output from that evaluation is published.

`RelaxedAssociative` grants permission to reassociate a fold. It does not
select a second executor; the canonical implementation remains valid.

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
