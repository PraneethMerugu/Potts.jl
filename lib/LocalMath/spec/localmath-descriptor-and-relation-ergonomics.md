# LocalMath descriptor and relation ergonomics

LocalMath presents semantic descriptors as mathematical objects rather than
implementation type graphs. `Space`, `Field`, `Relation`, and `Collection`
display their durable shape, type, bounded topology, storage requirement, and
identity facts. Laws and prepared plans display projections of the existing
semantic, binding, inspection, and physical-lowering authorities.

Presentation is read-only. It may allocate cold host strings and projections,
but it must never plan, allocate scientific or workspace storage, submit a
kernel, synchronize a provider, settle a receipt, or become an execution
input.

Canonical binding reports complete missing-storage requirements in first
scientific encounter order. Relation-shape failures identify the relation,
expected bounded layout, actual physical layout, and a corrective hint. These
facts are derived during ordinary binding and validation; no requirements
report, descriptor label registry, or parallel validator is stored.

LocalMath does not infer spaces, Fields, topology, outputs, initialization, or
backend choice from arrays. Computed relations remain omitted from binding;
stored relations remain explicit. Lexical variable names are presentation
context only and never semantic identities.

No declaration bundle, `@fields` macro, registry, or named lookup is introduced
by this decision. A future syntax-only declaration shorthand requires repeated
evidence from unrelated complete models and must lower immediately to ordinary
descriptor constructors.
