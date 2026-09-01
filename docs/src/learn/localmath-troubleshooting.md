# [LocalMath troubleshooting](@id localmath-troubleshooting)

LocalMath failures are contract errors, not backend folklore. Read the
`contract`, `origin`, `expected`, `actual`, and `hint` fields of
`LocalMath.LocalMathValidationError` when automating diagnostics.

## Missing storage

Every Field, stored Relation, and Collection used by a law must appear exactly
once in `@prepare`. Computed identity, affine, boundary, product, composed, and
index relations are supplied automatically and must not be bound. The error
lists each missing authored role and stage.

## Unsafe `allocate(undef)`

Uninitialized output is accepted only when a preceding unconditional total
identity `Unique` publication establishes every element before any read or
preserve-on-empty use. Use `allocate(value)` or `allocate(source)` when the
proof is partial or uncertain.

## Relation direction or storage shape

A relation is `domain → codomain`: stage items live in the domain and endpoints
index the codomain Field. Fixed endpoints use `degree × length(domain)` layout;
optional lanes additionally supply counts. The diagnostic reports both the
expected logical layout and the supplied array shape.

## Required versus sample-aware reads

`field[relation(i)]` and `Access(field, relation)` are required. Missing or
invalid lanes fail atomically. Use `samples(field[relation(i)])` or
`Access(field, relation; required=false)` only when absence is part of the
scientific law.

## Invalid `IndexRelation` keys

Strict indexed keys must be in `1:length(codomain)`. With `optional=true`, an
invalid key becomes an absent lane and must be consumed sample-aware. Keys are
stage-entry values; materialize derived keys in an earlier stage.

## Captured arrays or non-isbits callables

Evaluator closures may capture concrete immutable scalar data, not arrays,
descriptors, references, or mutable objects. Declare arrays as Fields and
gather them through bounded Relations. The structural rejection reports the
first capture path and a durable reason such as `array_capture`.

## Typed-effect rejection

Planning analyzes the selected concrete Julia method. Allocation, mutation,
unsafe globals, foreign calls, dynamic dispatch, recursion, and unsupported
method shapes are rejected. The error reports the callable purpose, analyzed
signature, selected method when available, and a recovery hint.

## Receipt or transaction failure

`execute!` returns a logical `ExecutionReceipt`; call `wait` or `waitall` to
settle it. A failed stage suppresses later publication in the ordered law.
LocalMath is a failure-atomic publication pipeline, not rollback for writes a
domain deliberately committed in an earlier independent submission.

## Canonical versus relaxed numerics

Canonical reductions and folds preserve declared order. Relaxed laws grant
permission to reassociate and may change floating-point bits. Select relaxed
semantics only when that numerical contract is scientifically acceptable.

## CPU and Metal

CPU and Metal use the same packed KernelAbstractions execution path. Backend
qualification is exact to the package versions and Julia version in the active
environment; inspect current capability documentation before claiming another
backend or stronger cross-backend bitwise behavior.
