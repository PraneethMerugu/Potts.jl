# LocalMath semantic and execution contract

LocalMath is the typed spatial and publication substrate shared by scientific
compilers in this repository. Domain packages retain the meaning of their
models; LocalMath owns bounded local access, routing, conflict laws,
publication, ordered composition, planning, and execution.

## Semantic model

A `Space` identifies a finite index domain. `Field`, `Relation`, and
`Collection` descriptors identify scientific storage and topology without
containing arrays. A `LocalLaw` is an ordered sequence of typed stages. Each
stage declares its source space, accesses, control, evaluator, parameters, and
publications.

Publication laws define observable conflict behavior:

- unique assignment requires one participating value per destination;
- reduction applies its declared operation and ordering law;
- resolution selects a score/payload pair with explicit tie and empty rules;
- collection publishes bounded records with explicit grouping and overflow;
- ordered fold applies a bounded recurrence in its declared canonical order.

In authored `resolve_to` expressions, a noncanonical tie is an explicit
bounded `Field` read. This keeps the tie value inside the declared spatial
access set and makes GPU lowering inspectable. Equal scores select the lowest
tie value. Selection direction is declared by `sense=:min` or `sense=:max`;
`order` is reserved for deterministic ordering policies. `onempty=:preserve` retains the destination; any other exact value
is the result published when no candidate participates.

Conditional participation is distinct from publishing a dummy value. Multiple
ports from one evaluation share the same stage-entry reads. A later stage sees
earlier-stage publications; a stage does not observe its own publications.
Explicit `Access(field, relation)` is a required read: every declared lane must
be present or the stage fails transactionally. Absence-aware scientific
sampling is explicit as `Access(field, relation; required=false)` and as
`samples(...)` in authored notation.

`@localmath` is a syntax translator for these values. Ordinary concrete isbits
Julia callables remain a first-class evaluator representation. No syntax tree,
symbolic interpreter, scheduler, or alternate execution representation reaches
planning or device kernels.

A `BoundedFold` is an immutable scalar operator over a declared bounded gather
or bounded collection group. Its map, combine, seed, finish, value-domain,
invalid-input, empty-input, and ordering policies are explicit. Absent optional
lanes do not participate. Rejected present values and rejected empty inputs
mark the existing evaluator validation sink and fail at the ordinary stage
transaction barrier; they add no validation law or physical launch. The same
sink is carried by external reads used during `OrderedFold` event evaluation
and recurrence, so bounded-input rejection prevents its ordered shadow state
from being committed just like any other recurrence failure.
`CanonicalLeftFold` preserves declared relation or collection order.
`RelaxedAssociative` is permission to reassociate, not a second implementation.

Cartesian authored indexing admits only static offsets from a tuple binder and
requires an explicit `interior(space, halo)` or `periodic(space)` boundary.
It lowers to ordinary affine relation accesses and publications. Interior
relations retain binder-relative offsets plus an explicit embedding origin;
offsets wider than the declared halo reject during construction. Exact read and
reverse-publication footprints remain derivable from those relations; no
Cartesian storage authority, stencil IR, or dimension-specific executor exists.

Authored collection consumers use statically bounded group views and literal
source-position lanes. Collection production distinguishes its global storage
capacity from the per-source `maximum` emission width. These forms lower to
the existing `CollectionAccess`, source-position, `Collect`, and control laws.

Ordered recurrence is authored by declaring a total event order and every
evolving state component with its exact initial Field:

```julia
@ordered (
    by=(priority[event], identity[event]),
    state=(occupancy => occupancy_initial,
           accepted => accepted_initial),
) begin
    admitted = occupancy[first[event]] == 0 &&
        occupancy[second[event]] == 0
    if admitted
        occupancy[(first[event], second[event])] =
            (label[event], label[event])
    end
    accepted[event] = Int32(admitted)
end
```

State reads observe the accumulated successful prefix. Each declared component
produces one statically bounded write bundle per step; a conditional assignment
publishes zero writes when its condition is false. `target => target` requests
in-place initialization, `by=:source` requests source order, and
`halt_when(condition)` halts later events through the existing `FoldStep` law.
The form lowers directly to `InitializedState`, `FoldComponent`, `OrderedFold`,
`FoldStep`, and `BoundedWrites`; no transaction object or runtime syntax tree
survives expansion.
Execution evolves ordered state in package-owned workspace and commits it only
after final validation succeeds, preserving stage-entry destinations on any
late recurrence failure.

## Binding and storage ownership

Ordinary preparation accepts one flat sequence of descriptor-to-storage pairs.
Every referenced descriptor that owns physical storage appears exactly once as
caller-owned storage or an explicit cold `LocalMath.Allocate` declaration.
Storage-free computed relations are derived from the law and require no
placeholder pair. Planning, preparation, and execution never infer or allocate
omitted scientific arrays. `LocalMath.storage` returns the storage associated
with a descriptor's stable semantic identity from either the cold bound law or
the prepared plan.

Domain compilers may bind a producer-initialized scratch Field with
`LocalMath.Temporary()`. This qualified declaration does not change the Field's
mathematical identity: it states only that its storage is package-owned and not
scientifically observable. Every Temporary must be totally produced on each
submission before its first read, cannot be retrieved with `storage`, and may
be forwarded or internally materialized according to exact lifetime proofs.
Ordinary authored Fields are never inferred temporary.

Static stored relations are immutable borrowed topology for the lifetime of a
bound or prepared law. Mutable relations use
`LocalMath.MutableRelationStorage` as the cold declaration of their packed
generation, status, validated-generation, and slot protocol. Missing status
arrays may be allocated only at an explicitly backend-qualified cold boundary.
Mutation outside that protocol is invalid input. `ProgramRelationshipState`
is a cold construction or serialization value only; production execution uses
`PackedRelationshipBank` storage.

Algorithmic workspace is separate from scientific storage and is determined by
`workspace_requirements`. Prepared workspace and allocated scientific storage
have explicit ownership and lifetimes.

The exported `@prepare` assignment block is the ordinary lexical spelling of
that same Pair contract:

```julia
prepared = @prepare (law; backend) begin
    input = host_input
    output = allocate(undef)
    relation = host_endpoints
end
```

It accepts only bare descriptor assignments and the existing preparation
keywords, requires an explicit backend, preserves binding order, and evaluates
every expression exactly once. Only top-level `allocate()`,
`allocate(undef)`, and `allocate(value)` are reserved syntax; all other right
sides remain ordinary Julia expressions. Macro expansion constructs the Pair
call directly, so no builder, setup object, allocation syntax, name lookup, or
second binding representation survives.

Record-valued Fields retain ordinary concrete isbits element types. Direct
`StructArray` bindings are borrowed unchanged. Explicit allocation recursively
copies their component arrays to the selected backend while preserving shape,
element type, and component structure.

Semantic descriptors have compact ordinary and `text/plain` displays.
Descriptor presentation exposes scientific shape, element type, relation
family, degree, storage requirement, capacity, optionality, boundary policy,
ownership, schema epoch when nonzero, and an abbreviated identity where
applicable. It must not expose implementation type graphs as the primary user
representation.

`text/plain` display of a law, plan, or prepared plan derives from the law,
canonical inspection, binding ownership, and physical lowering. It stores no
report and performs no planning, allocation, submission, synchronization, or
settlement. Binding coverage diagnostics report every missing Field, stored
Relation, and Collection in scientific encounter order. Storage-shape errors
include the relevant descriptor, expected semantic layout, actual physical
layout, and a correction hint.

Every declared-public name has source-owned Julia help. Authored access and
publication roles are deterministic lexical names used by display,
inspection, and diagnostics; generic ordinal names and macro-generated symbols
are not part of the user representation. Callable qualification reports the
capture path or typed-call cause and a corrective hint while retaining no
diagnostic object in a successful law, plan, preparation, or device kernel.

## Planning and execution

The ordinary public flow is:

```julia
prepared = prepare(law, descriptor_storage_pairs...; backend)
receipt = execute!(prepared; parameters=(;), dependencies=())
wait(receipt)
```

This `prepare` method is a direct cold composition of the sole binding,
planning, and preparation implementations. Explicit `bind` and `plan` remain
available for domain compilers and inspection, accept the same flat pair
sequence, and do not constitute a second path.

`Plan` records validated semantic and workspace requirements. `PreparedPlan`
owns concrete physical storage and compiled KernelAbstractions kernels.
`ExecutionReceipt` is a logical submission receipt over an implicitly ordered
provider scope; it is not a portable native device event. Unresolved
dependencies are accepted only from an earlier submission in the same scope.
Settled successful receipts may be consumed across scopes after an explicit
wait. `waitall` synchronizes each represented provider scope at most once and
reports failures in argument order.

Validation and finalization are transaction barriers. Failed programs do not
publish scientific destinations. Relationship receipts and status storage
remain part of this transaction contract.

Physical lowering may combine at most four consecutive, independently proven
pointwise identity publications into one KernelAbstractions launch. The
segment executes logical members in authored order, retains every intermediate
Field write, and may forward only exact same-item values between members.
Logical stages, producer dependencies, provenance, and stage-entry semantics
remain unchanged. Any off-item access, uncertain alias, routed conflict,
fallible evaluation, mutable relation, collection, recurrence, or global
status boundary splits the segment.

The same physical path removes only barriers proven redundant: the first
unresolved dependency join may clear the new program status, Candidate
publication records already-completed diagnostics, OrderedFold validates order
while initializing private shadow state, and independent Collect ports publish
in bounded chunks. Global scans, sorts, grouping, recurrence, transaction
validation, lifecycle, rollback, and bank publication remain separate launches.

## Backend contract

CPU and GPU execution use the same packed-storage KernelAbstractions path.
Backend admission depends on concrete backend/device consistency, supported
storage and layout, and successful physical compilation. Julia version,
dependency versions, operating system, and reviewed machine identities are
descriptive facts, not execution permissions.

After preparation, execution performs no scientific or algorithmic workspace
allocation, relationship packing or unpacking, runtime symbolic construction,
or Julia compilation. Host receipt bookkeeping is bounded and measured rather
than described as device allocation.

## Inspection

`LocalMath.inspect` is a pure projection over the semantic law, relation proofs,
workspace authority, lowering entries, and prepared runtime. Planning and
execution never consume inspection output. Semantic equivalence excludes source
provenance, backend choice, physical storage, and mutable execution state.

The shared top-level projection for laws and plans is
`(lifecycle, parameters, relations, stages, planning, equivalence)`; prepared
plans append `realized`. Receipt inspection is deliberately narrow and never
recursively embeds a prepared plan. Semantic and equivalence fields express
scientific structure. Relation proofs, workspace requirements, physical phases,
specialization families, callable admission, provider facts, and mutable receipt
counters are descriptive compiler/runtime observations. The `0.2` release
freezes their documented meaning. Later compatible releases may add
descriptive fields but must not turn them into planning or execution authority.

Kernel inspection includes the physical segments actually selected by
lowering: their logical-stage membership, traversal, physical family and launch
count, retained materializations, same-item forwarding, and split reason.
Provider launch counts are derived from those segments rather than from a
logical-stage formula. Prepared reports describe physical launch types.

Inspection is cold tooling. It may allocate host-side projection values, but it
must not submit work, synchronize a provider, mutate receipt state, or become an
input to planning or execution. Errors use `LocalMathValidationError` with
machine-readable contract fields and a compact multiline rendering. When an
authored stage or equation is known, its `SourceOrigin` must survive planning,
preparation, execution, dependency failure, and waiting; a program-wide failure
must not be falsely attributed to the first stage.

## Scientific ownership

LocalMath does not own Hamiltonians, Metropolis acceptance, semantic RNG, Monte
Carlo scheduling, LBM collision models, LSM constitutive laws, FEM weak forms,
or distributed scheduling. Their domain compilers may lower eligible bounded
local mechanics into `LocalLaw` while retaining those scientific authorities.
LocalMath may report relation footprints and communication requirements without
owning partitioning or MPI execution.

## Release contract

LocalMath `0.2` freezes the exported mathematical vocabulary, qualified domain-
compiler SPI, authoring grammar, inspection levels, diagnostics, and receipt
semantics described here. Pre-1.0 development may still make a breaking change
when the repository charter permits it, but such a change is a direct cutover;
it does not retain compatibility aliases, alternate executors, or migration
representations.

Every package-owned launch and synchronization remains expressed through
KernelAbstractions. CPU and Metal execute the release conformance witnesses.
Other conforming KernelAbstractions providers are not blocked by a vendor
branch or dependency, but architectural compatibility is not a scientific
support claim for an untested provider.
