# Effortless explicit LocalMath setup

This decision keeps descriptor identity, backend choice, storage ownership,
initialization, and topology explicit while removing repetitive Pair syntax
from ordinary scientific programs.

`@prepare (law; backend, ...) begin ... end` accepts a nonempty ordered block
of bare lexical descriptor assignments. It recognizes only top-level
`allocate()`, `allocate(undef)`, and `allocate(value)` as shorthand for the
cold `LocalMath.Allocate` declaration. It lowers hygienically and directly to
the existing `prepare(law, descriptor => storage...; ...)` method. The Pair API
remains the programmatic compiler interface; the macro creates no builder,
registry, lookup rule, binding representation, or execution path.

Arrays on an ordinary right-hand side are borrowed exactly as supplied.
Allocation is explicit and backend-qualified. A caller-owned `StructArray`
retains identity, while allocating one recursively copies its component arrays
and reconstructs an independent `StructArray` of the same element type and
shape. Record Fields consolidate values only when the record has coherent
scientific identity; independently routed, published, or evolving state stays
in separate Fields.

Setup errors introduced by the syntax translator are source-located.
Descriptor, schema, topology, ownership, and definite-initialization failures
remain the responsibility of canonical binding. No allocation declaration or
syntax object may reach planning or a KernelAbstractions argument.
