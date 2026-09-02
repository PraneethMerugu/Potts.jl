# LocalWorksets Mechanical-Law Expansion

Date: 2026-08-16

Status: Accepted direct implementation specification; one-time committee accepted with
P0=0, P1=0, and P2=0 after remediation

## Purpose and authority

This document specifies the next bounded expansion of LocalWorksets after the
[execution architecture consolidation](execution-architecture-consolidation.md). It is an
engineering specification for direct edits to the current architecture, not a migration program,
compatibility plan, or permanent review process.

The implementation remains:

```text
localwork / sequence
    -> plan
    -> one _LoweredWork(mechanism, bindings, workspace, phases)
    -> prepare
    -> one _PreparedPipeline
    -> run! -> WorkEvent -> wait / waitall
```

No change in this document may create another lifecycle, execution family, scheduler, task graph,
stream abstraction, public compiler IR, transaction API, or domain-specific lowering authority.
The work should be implemented with ordinary Julian types, multiple dispatch, concrete tuples,
central validation, direct replacement of obsolete code, and the existing test and benchmark
structure.

## Decision

The next LocalWorksets work should deepen the existing vocabulary of bounded local computation in
this order:

1. pre-evaluation active masks and a small centrally qualified combination catalog;
2. heterogeneous-domain `sequence` and proved pointwise read-modify-write;
3. preserve-on-empty resolved publication and same-winner record values; and
4. direct CorePotts adoption where the generic law deletes more mechanism than its adapter adds.

Runtime-keyed routing is included as one bounded stable-grouped address law in this edit. It remains
deliberately small: up to four canonical named independent, combined, or resolved outputs, at most
32 fixed emission lanes in total, runtime `N` and destination counts stored as data, three shared
pre-publication phases followed by one monomorphic publisher per port, and preallocated grouping
and completion storage. Broader adoption still needs unrelated domain witnesses; it does not
authorize public compaction, CSR topology, top-K, or segmented scan. A separate public N-key
arbitration mechanism is rejected.

This ordering is a code dependency order, not a sequence of bureaucratic gates. Each change is
complete when its ordinary semantic, backend, lifetime, inspection, and benchmark tests pass.

## Admission rule

A capability belongs in LocalWorksets only when all of the following are true:

- it is useful outside cellular Potts models;
- its item, destination, emission, record, workspace, and launch bounds are fixed before execution;
- its reads, writes, aliases, coverage, conflict behavior, empty behavior, and publication behavior
  are explicit;
- its canonical order or intentional nondeterminism is stated precisely;
- it lowers through the one package-owned phase pipeline;
- warm execution performs no hidden allocation, topology transfer, host fallback, callback, or
  synchronization;
- backend support is qualified by backend, value type, operation, and address space;
- the package can inspect the same facts used by admission and lowering;
- two unrelated non-CPM witnesses demonstrate the law.

If current ports and ordered phases already express a capability at acceptable bounded cost, improve
composition or representation instead of adding a public mechanism.

Downstream adoption has one additional, separate criterion: replacing a CorePotts path must delete
more production mechanism than its adapter adds. A useful general LocalWorksets law does not need a
CorePotts consumer to justify its existence.

## Ownership boundary

LocalWorksets owns mechanical execution:

- bounded item selection and local evaluation;
- immutable topology and address-law validation;
- output conflict and publication laws;
- binding access and alias proofs;
- exact workspace and typed phase schedules;
- backend qualification, preparation, submission, leases, poison, and waits; and
- truthful inspection of determinism, memory, publication, and completion.

CorePotts continues to own scientific meaning:

- Hamiltonian terms and canonical source-order energy folding;
- proposal views, acceptance, and semantic RNG addresses;
- MCS and lifecycle clocks;
- `ProgramStatus` meaning and scientific failure cuts;
- ownership, tracker, relationship, and lifecycle transaction meaning;
- state-bank choice, checkpoint meaning, rollback, and publication; and
- capability claims and scientific evidence identity.

Executing a Core-owned callable inside LocalWorksets does not transfer any of those meanings.

## The compositional model

The durable abstraction is:

```text
item selection
    × address source
    × conflict law
    × publication-state law
    × result layout
```

The axes are orthogonal:

- **item selection** chooses which planned items may gather, evaluate, or emit;
- **address source** is either a frozen plan-time route or bounded runtime key data;
- **conflict law** is independent, combined, or resolved;
- **publication-state law** says what happens to prior destination state; and
- **result layout** is a scalar or one logical isbits record with qualified physical storage.

This factorization prevents domain-shaped families. For example:

- conditional status selection is resolved conflict plus preserve-on-empty;
- accepted-copy scatter is runtime-keyed resolved conflict plus preserve-on-empty;
- incremental aggregation is combined conflict plus the implemented seed-existing publication law; and
- an arg-selection result is ordinary resolved conflict with a record value containing provenance.

None of these requires a status, tracker, ownership, lifecycle, or transaction API in
LocalWorksets.

## Current substrate and exact gaps

The consolidated implementation already supplies:

- one-based bounded item domains and optional active prefixes;
- immutable fixed-offset and validated finite-incidence bounded reads;
- independent, deterministic/fast combined, resolved, and exact two-key conjunctive behavior;
- static record lanes and canonical item/lane order;
- one typed phase tuple, stage-qualified workspace, and tuple-order execution;
- exact binding, topology, workspace, lease, poison, and cumulative-wait authority; and
- explicit nontransactional publication evidence.

The immediate gaps are narrower than the architecture:

- active selection is effectively prefix-only;
- `sequence` requires one common item domain and one common topology shape;
- the pointwise RMW law named by the V1 contract is not proved through a restricted gathered value;
- combined admission is artificially limited to a few `+ / 0` rows;
- resolved output always writes its declared empty value; and
- resolved record storage does not yet express same-winner provenance as one logical value.

## Immediate law 1: pre-evaluation active masks

### Semantics

`LocalWork.active` should admit a closed active-selection value with four meanings:

- all planned items;
- the existing bounded prefix `1:active_count`;
- an exact-length qualified Boolean mask; or
- the intersection of that mask and a bounded prefix.

For every false item, selection occurs before topology gather, indexed read, destination
calculation, operation invocation, or emission. A false item therefore cannot fault through an
otherwise invalid or unavailable read.

Masking does not compact or renumber items. Semantic identity remains the original item position,
and deterministic record order remains `(item, lane)`. A masked independent output uses partial
coverage unless planning can prove every destination is still covered.

### Julian shape

Use this exact closed grammar:

```julia
active = nothing
active = active_prefix(:active_count)
active = active_mask(:selected)
active = active_mask(:selected; prefix = :active_count)
```

The constructors return concrete isbits values equivalent to `_ActivePrefix{Name}` and
`_ActiveMask{Name,Prefix}`; binding names and prefix presence are type parameters. The old
bare-symbol prefix spelling is replaced directly rather than kept as a compatibility branch.

The mask binding is an exact `(item_count,)` reviewed global `AbstractVector{Bool}` representation.
`BitVector` and packed-bit representations reject. It enters ordinary read-only binding authority,
backend/device validation, alias validation, and lease retention.

Every direct, buffered, singleton-resolved, and conjunctive item kernel must load the selector and
branch before any old-value load, topology read, operation call, route lookup, or destination
calculation. Buffered apply must explicitly write masked record slots invalid, and deterministic
publish must either test the selector or consume those freshly invalidated slots. Stale validity
from a prior submission must never publish.

Apply kernels dispatch on the selector type, so the all-active and prefix paths retain their simple
specialized forms.

No new phase or workspace is required.

### Tests and witnesses

- z-buffer fragments with invalid payload for masked fragments, proving the operation is never
  invoked for them;
- lattice-spring or graph edges whose masked entries cannot safely gather endpoint data;
- independent, combined, resolved, sequence, lease, alias, inspection, and failure tests; and
- CPU and every claimed accelerator backend.

This law is selection, not a performance claim that launch cost scales with the number of true mask
entries.

## Immediate law 2: centrally curated combination profiles

### Semantics

Extend `combined` through a closed package-owned catalog. Each admitted row fixes:

- exact input and result types;
- exact operation and identity;
- deterministic canonical order or explicit fast semantics;
- integer overflow and floating numerical behavior;
- required loads, stores, and atomics; and
- backend and address-space support.

The initial deterministic catalog is exact:

| Type | Binary callable | Identity | Numerical rule |
|---|---|---|---|
| `Int32` | `+` | `Int32(0)` | Julia/device two's-complement wraparound |
| `UInt32` | `+` | `UInt32(0)` | arithmetic modulo `2^32` |
| `Float32` | `+` | `Float32(0)` | canonical sequential IEEE fold in semantic order |
| `Int32` | `min` | `typemax(Int32)` | exact integer order |
| `Int32` | `max` | `typemin(Int32)` | exact integer order |
| `UInt32` | `min` | `typemax(UInt32)` | exact unsigned order |
| `UInt32` | `max` | `typemin(UInt32)` | exact unsigned order |
| `Int32`, `UInt32` | `&` | `typemax(T)` | exact bitwise fold |
| `Int32`, `UInt32` | `|` | `zero(T)` | exact bitwise fold |
| `Int32`, `UInt32` | `xor` | `zero(T)` | exact bitwise fold |

This table defines semantic rows, not universal backend support. The executable capability table is
keyed by `(mode, exact callable identity, input type, result type, identity, backend, address
space)`. A row exists on CPU or an accelerator only after that exact global-workspace and output-
store profile is qualified.

`Bool` is not covered by the integer rows even though it is an `Integer` subtype. Boolean
`all/any`, spelled as the binary rows `(&, true)` and `(|, false)`, remain absent until Boolean
record and output stores are qualified. Fast rows exist separately only where the exact atomic
operation, type, backend, and address space are qualified; deterministic admission never authorizes
fast execution.

This is not an open monoid registry. External callables do not self-certify associativity,
identity, atomics, or backend safety. Floating min/max should remain absent until NaN and signed-zero
behavior is specified. Wider integer rows remain absent until their exact CPU and accelerator
loads, stores, atomics, and overflow behavior are qualified.

### Lowering

Canonical rows reuse buffered records and the existing apply/canonical-publish phases. Fast rows
reuse identity clear plus a centrally selected qualified atomic phase. No new public family or
phase lifecycle is needed.

### Tests and witnesses

Use at least matrix-free FEM or finite-volume aggregation and graph/lattice-spring aggregation.
Evidence is per catalog row; proving one integer addition profile does not authorize another type or
operation.

## Immediate law 3: heterogeneous-domain ordered sequence

### Semantics

A sequence contains stages `S1 ... Sn`. Each stage retains its own:

- item domain and launch range;
- active selector;
- topology identity, epoch, fingerprint, and prepared payload;
- routes, destination counts, and output laws; and
- workspace leaves and publication evidence.

All phases execute in `(stage, phase)` declaration order on one qualified provider lane. A stage may
read a binding published by an earlier stage, but never a later one. There is no intermediate host
wait. The final event truthfully covers every phase and every leased input in the sequence.

Different domains must not be padded to one maximum domain. The first implementation retains
globally unique output port names and forbids repeated writable ownership across stages. Pointwise
RMW is an intra-stage law in this version; repeated cross-stage output ownership remains deferred.

### Julian shape

Keep `sequence(a, b, ...)`; add no graph, pipeline, or sequence-topology noun. The exact planning
contract is:

```julia
works = sequence(a, b, c)
plan(works, (topology(a; ...), topology(b; ...), topology(c; ...)); backend)
```

The topology argument must be a concrete tuple with exactly one child topology per flattened stage.
There is no `topology(sequence; ...)` convenience constructor. Admission, freshness validation,
fingerprinting, device preparation, transfer accounting, and inspection zip child work and child
topology recursively and retain a concrete tuple throughout. `WorkPlan.topology` is that ordered
tuple. Mutation between planning and preparation rejects per stage. After successful preparation,
the validated prepared copies are authoritative for that `PreparedWork`; host mutation cannot alter
them, while a later preparation revalidates and rejects the changed host topology.

Binding authorities merge structurally across stages and reject incompatible repeated read, mask,
or output requirements. Child phase tuples are flattened directly. Planning rejects more than 32
stages or more than 128 total lowered phases to bound compilation growth; both limits are named,
centrally defined, and reported by inspection. Stage dispatch uses the type parameter of
`_StageRef`, not a runtime `stage.index` strategy branch.

This feature is worth keeping only if it consolidates binding, workspace, lease, inspection, and
downstream adapter machinery. Separate `PreparedWork` submissions already provide basic provider
ordering, so syntax shortening alone is insufficient.

### Tests and witnesses

- matrix-free FEM element-domain work followed by node-domain update;
- LBM cell/population work followed by a distinct boundary/link domain, or rendering fragment work
  followed by pixel work;
- stage-specific active selection, topology mutation rejection, workspace inspection, lease
  retention, partial failure visibility, and one-final-wait behavior.

## Immediate law 4: proved pointwise read-modify-write

### Semantics

The first admitted RMW law is intentionally narrow. It has exactly one scalar output, one emission
lane, an identity route, `destination_count == item_count`, and an unconditional replacement for
every selected item. For each selected item `i`, LocalWorksets:

1. loads exactly one prior scalar value from `output[i]`;
2. passes that scalar to the operation; and
3. stores exactly one replacement to the same destination.

The operation must not receive unrestricted indexing access to the writable array through that
binding. Equal array identity, equal shape, equal binding name, or an identity output route alone is
not a sufficient proof. The route must be identical for the gathered old value and the new value,
and planning must prove writer exclusivity.

Inactive items are untouched. No cross-item order is observable. A launch failure may leave some
items updated, so this law is neither transactional nor failure-atomic.

### Julian shape

Express this as one exact read-source declaration:

```julia
read = (old = pointwise_read(:state), other = :other)
outputs = (
    state = independent(
        :state_route;
        value_type = T,
        maximum = 1,
        coverage = :partial,
    ),
)

topology(...;
    routes = (state_route = identity_route(item_count),),
    destination_counts = (state = item_count,),
)
```

`identity_route(item_count)` is the existing public allocation-free route constructor, not new RMW
surface. It remains topology payload behind the declared route name; planning must prove and
canonicalize its identity/injectivity facts rather than trust the spelling.

The ordinary operation signature remains `(item, reads, values)`, but `reads.old` is the gathered
scalar rather than an array. The load occurs only after active selection. The target array is absent
from every operation-visible array read. Ordinary `Symbol` reads that alias any writable output
reject, as do any other binding aliases to the target.

Binding authority is `:readwrite` only for this proved mode. The existing broad
`allow_readwrite=true` escape is removed; equality of names or arrays cannot grant access. The law
reuses the direct apply phase. Record values, permutations, conditional replacement, multiple
outputs, and cross-stage reuse remain deferred until separately specified.

The proof also covers callable state, not only declared bindings. Pointwise RMW admits only a
centrally certified scalar-callable subset. Qualification recursively rejects callable fields or
captured values containing `Ptr`, `Ref`, `AbstractArray`, provider buffers, device arrays/views,
textures, mutable containers, or opaque memory authorities. The admitted method must use generic
`reads` and `values` arguments so host-array and device-array dispatch cannot select different user
methods. Its lowered source may reference only Base/Core operations and `emit`; external helper
calls, mutable globals, foreign/LLVM/unsafe memory operations, opaque calls, and every known
write/atomic primitive reject. Optimized typed IR is then checked on canonical host-array
surrogates, permitting only primitive Base/Core calls and the unreachable bounds-error edge. This
deliberately small closed subset proves ordinary read-role arrays load-only without trusting a user
trait or pretending host inference is provider compilation. Submission `values` types are
recursively checked and reject pointers, refs, arrays/views, provider buffers, mutable containers,
or any opaque memory authority even when wrapped in an isbits value. The package records this
storage-free/effect qualification in inspection. External code cannot add a trait that
self-certifies the proof.

### Tests and witnesses

- FEM quadrature or element-history update;
- graph edge-damage state or pixel-local transformation;
- hostile operations proving the writable array is unavailable for arbitrary indexing;
- mask interaction, partial coverage, alias rejection, inspection, and failure visibility.

In-place stencil or Gauss-Seidel behavior remains out of scope.

## Immediate law 5: preserve-on-empty resolved publication

### Semantics

For destination `d`, let `C(d)` be the valid candidates under the existing rank and canonical
identity order.

- Current overwrite behavior publishes the winner when `C(d)` is nonempty and the declared empty
  value otherwise.
- Preserve-on-empty publishes the winner when `C(d)` is nonempty and performs no store otherwise.

Prior state does not participate in ranking. Preserve-on-empty is not equivalent to adding one prior
candidate per destination, and it is not a rollback or commit law.

### Lowering

Reuse existing buffered or single-destination resolved apply and publish machinery. The publish
kernel skips its store when no candidate exists. The output can remain write-authorized because the
kernel does not need to load it.

The exact declaration grammar is `on_empty=:overwrite` or `on_empty=:preserve`, encoded as a type
parameter of the resolved declaration. Overwrite requires one exact typed `empty` value. Preserve
forbids an `empty` argument rather than ignoring it. Both generic and singleton publish paths
dispatch on the same policy, and inspection reports `on_empty`, not a private policy object.

Publication remains nontransactional: failure during the publish phase may leave a subset of
destinations modified.

### Tests and witnesses

- prepopulated z-buffer destinations with uncovered pixels left byte-identical;
- graph best-edge or lattice-fracture destinations with no candidate left untouched;
- generic resolved and optimized singleton lowering parity;
- repeated submissions, failure visibility, inspection, and backend parity.

## Immediate law 6: same-winner record values

### Semantics

A resolved candidate may carry one specifically qualified concrete isbits record whose logical
fields include any combination of rank-independent payload and provenance. One rank and one
canonical identity select the entire logical record. Every published field must originate from that
same candidate.

AoS and component/`StructArray` storage are physical layouts of the same logical value. Successful
completion establishes same-winner logical coherence; it does not claim an atomic multi-field or
multi-array store, nor that an observer before completion cannot see torn intermediate fields.

This is a resolved value/layout extension, not a new arbitration family or a public `WinnerRecord`
noun. Admission is not granted to all isbits records. It separately qualifies:

- record writes and reads in buffered workspace;
- final output publication;
- exact AoS record ABI, or exact component leaves for a component layout;
- every field type, backend, address space, byte count, and alias fact; and
- reconstruction of one logical winner in registers followed by one same-winner publication helper.

Preparation must allocate the exact field leaves for a component representation and expose them in
workspace and binding inspection.

### Tests and witnesses

- a G-buffer winner carrying color plus material/geometric data;
- a graph/contact winner carrying edge identity and payload;
- AoS/component equivalence, empty and preserve policies, component qualification, inspection, and
  partial publication behavior.

## Implemented bounded law: runtime-keyed buffered routing

Runtime keys are the most important capability that the static route law cannot express. The
stable-grouped lowering is admitted now; unrelated external witnesses remain a requirement
for widening its profile or replacing domain machinery with it.

### Exact semantics

For fixed item capacity `N` and fixed emissions per item `K`, the operation writes one bounded record
per canonical `(item, lane)` slot:

```text
(enabled, key, value[, rank])
```

The record capacity is `R = checked_mul(N, K)`. Destination capacity `D` and the key type are fixed
by planning.

- a disabled record ignores its key entirely;
- an enabled `key == 0` is valid and means no destination;
- `1 <= key <= D` is a valid destination; and
- every other key is mechanical invalidity.

Runtime keys are data inside a planned address law. They do not mutate topology, destination bounds,
aliases, or topology epochs.

The keyed path admits buffered deterministic `combined`, generic `resolved`, and `independent`.
Runtime-keyed independent validates uniqueness before publication. `coverage=:all` additionally
requires a bijection onto `1:D`; `coverage=:partial` preserves unmatched destinations. Disabled
records and key zero participate in neither uniqueness nor coverage.

### Stable-grouped lowering

The production implementation uses one private stable counting-group strategy for every keyed law.
It requires `lease_capacity == 1` and uses preallocated device status plus a preallocated host
mirror:

1. initialize the private publication gate, status, record validity, and seeded snapshot if present;
2. apply into the `R` canonical record slots;
3. run one deterministic device item that validates keys, builds counts, exclusive offsets, and a
   stable canonical-record permutation, selects the total diagnostic, and opens the gate only when
   validation succeeds; and
4. gated-publish with one item per destination, visiting only that destination's stable segment.

These are four concrete package-owned phase descriptors—`InitializeKeyedWorkspace`,
`ApplyKeyedRecords`, `IndexValidateKeyedRecords`, and `PublishKeyedSegments`—inside the existing
typed phase tuple. They are not a second execution lifecycle.

Grouping is bounded by `2R + 3D` for independent and `2R + 2D` for combined or resolved; aggregate
segment publication visits at most `R` records. Common grouping scratch is exactly
`counts::Int32[D]`, `offsets::Int32[D+1]`, and `permutation::Int32[R]`. Seeded combined output alone
adds a value snapshot of length `D`, and resolved output alone retains ranks of length `R`.
Inspection reports these checked linear bounds and exact workspace/status/transfer bytes. No
destination is published when keyed validation fails.

Settlement uses the ordinary provider synchronization first, then reads the preallocated status
through a provider-qualified, reported completion transfer that adds no hidden allocation or
unreported synchronization. A backend unable to provide that profile does not support this law.
An ordinary keyed validation failure releases the successfully synchronized lease, poisons only
that `PreparedWork`, and
throws `LocalWorkValidationError`; it is not provider-scope poison. `waitall` completes every status
transfer before releasing any participating lease. A transfer failure poisons the shared provider
scope and releases none. After all transfers succeed, it releases every eligible synchronized
prefix and reports keyed-validation errors in event-argument order, deduplicated by
`(PreparedWork, serial)`.
`release=false` reads and caches status without releasing the lease, poisons the affected
preparation, and throws; a later releasing wait performs the required retaining-fence
resynchronization, releases the lease, and rethrows the cached validation error. Repeated waits are
idempotent after release: an already released validation-failed event rethrows the same cached
`LocalWorkValidationError` without another transfer or release. Provider or synchronization failure
retains the existing shared-scope poison and no-release behavior.

This is a mechanical pre-publication gate, not a general transaction. The no-publication guarantee
applies only when key validation completes normally and reports invalidity. Provider failure in any
keyed phase retains the existing poison and partial-visibility rules because later phases may
already have been queued.

The serial device index builder is a private implementation seam. A later parallel builder may
replace it only behind the same stable segments, diagnostics, workspace ownership, three shared
phases plus canonical per-port publishers, and publication laws; it does not create a selectable
production fallback.

### Named keyed ports

The same private lowering admits up to four canonical named runtime-keyed ports with at most 32
total fixed emission lanes. Port metadata, records, grouping scratch, optional ranks, and optional
seed snapshots are concrete nested named tuples. Gate, diagnostic status, status transfer, provider
lane, and lease are shared.

The operation is evaluated once per selected item. One initialization launch snapshots all seeded
ports and clears all validity, one application launch materializes every port, and one device item
groups and validates every port. Diagnostics use global class order before canonical port order.
Only after all ports pass do monomorphic publishers run in canonical port order, giving `3 + P`
launches rather than `4P` sequenced works. Normal validation failure writes no output. Provider
failure after publication begins may expose a nontransactional subset and implies no rollback or
cross-port atomicity.

### Witnesses

- particle/contact contributions routed to bounded runtime bins; and
- fragment-to-pixel/tile or dynamic graph-endpoint contributions.

Core owner IDs or tracker counters may be a later consumer, not either foundational witness.

## Compilation behavior

Host inference is not backend compilation. A provider may preflight every concrete prepared phase,
selector, operation signature, record layout, and combination profile during `prepare` only through
a genuine nonexecuting compiler hook that invokes no work item and cannot touch user or captured
storage. Scratch launches and all-false execution are not compile-only evidence and are forbidden as
preparation preflight.

When the provider lacks a nonexecuting full-call-graph hook, LocalWorksets reports compilation
preflight as unavailable and permits ordinary lazy compilation at first launch. A compilation
failure then follows the existing provider poison, lease retention, and nontransactional partial-
visibility law; in a sequence, earlier stages may already be visible. Inspection records the exact
provider, device, compiler/environment, operation-method, concrete phase identities, and whether
nonexecuting compilation was actually proved. No stronger claim is inferred from host inference.
Lazy compilation does not bypass any mechanism-specific admission proof. In particular, pointwise
RMW first passes the closed source/method/typed-IR subset above; lazy provider compilation proves
only that the selected backend implements the already-admitted primitive vocabulary.

## Deferred laws

| Capability | Disposition | Reason to defer |
|---|---|---|
| Frozen CSR/ragged topology | Deferred representation | Dense padded lanes already express the semantics. Add it only when two witnesses demonstrate material padding, transfer, or compilation cost. |
| Stable compaction/filter-map | Deferred public API | A mask solves sparse pre-evaluation safely without a collective. Internal scan/pack may serve another lowering, but one internal use does not justify public vocabulary. |
| Per-destination top-K | Deferred | It is a genuine fixed-K selection law but has lower current leverage and no demonstrated replacement seam. |
| Segmented scan | Deferred | It is a collective, not a local destination fold. Internal compaction use does not establish an external need for prefix results. |
| Non-prefix index lists | Deferred | They add order, duplicate, and validation laws without evidence that masks are insufficient. |
| Repeated/ping-pong stages | Deferred | They approach iterative execution and need explicit snapshot/visibility semantics. |

Deferred does not mean forbidden. It means the current direct design should not pay their public API
and implementation cost yet.

## Rejected public mechanisms

### Separate N-key conjunctive arbitration

Do not add an `NKeyArbitration` family. Once runtime-keyed resolved routing exists, the general
mechanical composition is:

1. publish the deterministic winner identity for each resource key; and
2. run an ordinary item stage that checks whether the candidate owns every bounded key it claims.

A private fused specialization may later implement the same law if it materially reduces launches
or workspace. It should not change the public semantic model.

This composition does not automatically replace Core lifecycle conflict selection. Core first
canonically deduplicates requests and constructs complete conflict footprints covering anchors,
planned sites, and relationship incident edges. It then supports two distinct scientific policies:

- `RejectLifecycleConflicts` selects every active deduplicated request only when no pair conflicts;
  otherwise it reports the canonical conflicting pair; and
- `StablePriorityLifecycleConflicts` orders priority-descending with canonical-key tie order,
  greedily rejects lower-priority conflicts, and reports the canonical equal-priority conflict among
  otherwise selectable requests.

Core also owns selected-set ordering, canonical error identity, and the capacity preflight performed
after selection. Independent per-key winners can produce a different selected set under either
policy. Any child winner-table mechanism must prove exact equivalence to the selected policy,
deduplication, footprint, error, ordering, and capacity laws. Until then the entire selection remains
Core-owned.

### Domain and orchestration mechanisms

Reject dedicated APIs for:

- state banks, accepted copies, ownership or tracker commit;
- relationships or mutable graph stores;
- Hamiltonian evaluation or acceptance;
- RNG streams, MCS, lifecycle clocks, status, checkpoint, rollback, or settlement;
- task graphs, queues, frontiers, streams, command buffers, or iterative solvers; and
- dynamic topology mutation.

Generic admitted laws may execute mechanical pieces beneath these meanings.

## Direct implementation order

The preferred edit sequence is:

1. replace the bare active-symbol interpretation with a closed selector representation and thread
   pre-evaluation masks through every existing apply path;
2. generalize the existing combined capability table rather than creating operation-specific files;
3. remove the same-domain sequence restriction and make topology authority stage-qualified;
4. add a scalar gathered-old-value path to direct independent execution and delete any redundant
   alias exception;
5. add preserve-on-empty and record-valued resolved publication inside the existing resolved
   lowering; and
6. census a concrete Core consumer and replace it directly only when the final adapter deletes more
   production mechanism, preserves its independent reference oracle, and adds no synchronization or
   lifecycle.

Do not create migration constructors, compatibility shims, parallel execution selectors, feature
flags, old checkpoint decoders, or a new migration suite. Specialized kernels may remain where
their physical schedule is valuable, but they must implement the same law under the one pipeline.

## CorePotts adoption map

| Core machinery | Direct disposition | Mechanical part LocalWorksets may own | Meaning retained by Core |
|---|---|---|---|
| After-MCS site/model assignments | Retain; evaluate only a constrained checkerboard adoption | Heterogeneous sequence and buffered/pointwise map for non-iterated site/scalar-model assignments | Target/effect, enabled/preserve law, descriptor order, lifecycle placement, failure translation, and the independent sequential reference implementation |
| K04 status selection | Retain direct in this edit | A future one-launch specialization of preserve-on-empty resolved selection | `ProgramStatus`, failure mapping, sticky gate, semantic identity, exact K03/K04/K05 cut, and settlement identity |
| K06 accepted-copy evaluation | Retain/defer | Future pre-evaluation selection and fixed candidate-indexed record evaluation only after a net-deletion census | Accepted meaning, proposal context, dynamic target publication, relationship transaction, event/capacity/settlement integration |
| K07 ownership/tracker commit | Retain | Future runtime-keyed accumulation may replace scatter mechanics | Ownership mutation order, tracker meaning, transaction |
| K08 reports | Retain | Future qualified seeded integer fold | Disposition mapping and cumulative statistic meaning |
| K09 state-bank clone/copy | Retain; generic copy is optional only when smaller | Representation-qualified leaf copy with the existing lifecycle/open gate | Source/destination bank choice, relationship-specific copying, transaction identity |
| K09 final bank publication | Retain entirely | None in this program | Status/lifecycle gate, active-bank change, committed MCS, K08 counter publication, checkpoint boundary |
| Tracker rebuilds | Retain | Future runtime routing or justified CSR may replace map/scatter | Tracker quantity, affected anchors, source/checkpoint policy |
| Lifecycle request pack/scan | Retain | Future public compaction only after independent demand | Trigger, cadence, capacity, request ordering, failure meaning |
| Lifecycle conflict selection | Retain | Winner tables may be a child mechanism only after exact policy equivalence | Deduplication, both conflict policies, complete footprint, canonical error, selected order, capacity preflight |
| Fixed contacts | Retain current representation | Future immutable CSR traversal if it earns its cost | Periodicity, duplicates, direction and Hamiltonian fold meaning |
| Mutable relationships | Retain | Bounded local child maps only | Generations, degree, incident integrity, transaction |
| Hamiltonian/RNG/acceptance | Never transfer policy | Execute Core-owned pure callables | All scientific meaning and canonical order |

The current after-MCS implementation is shared with the independently executable sequential
reference path; it is not disposable duplicate checkerboard plumbing. That reference implementation
must remain. A checkerboard adoption is eligible only for non-iterated site assignments and scalar
model assignments that can use one compiler-derived adapter and preserve the existing two-
synchronization host schedule exactly:

1. enqueue state copy, K02--K08, and any device-compatible `before_lifecycle` work before the
   retaining `waitall(...; release=false)`;
2. take the existing first synchronization;
3. run the host lifecycle transaction;
4. enqueue device-compatible `after_lifecycle` work followed by final bank publication; and
5. finish through the existing final grouped settlement synchronization.

If a proposed stage needs another fence, cannot preserve the direct sequential oracle, or cannot
retain the exact target/effect, enabled/preserve, descriptor-order, lifecycle-placement, and failure-
translation laws, it stays in Core. No deletion estimate is accepted until a source census excludes
reference/oracle code and includes all new plan, event, lease, capacity, identity, and settlement
adapter machinery.

K04 likewise remains the current direct one-launch Core kernel. Preserve-on-empty does not by itself
make the existing apply-plus-publish resolved path eligible. A future physical specialization may
replace K04 only if it remains one launch, constructs the exact sticky Core-owned status through a
Core callable, stays exactly between K03 and K05, integrates with the existing event/capacity/
settlement identity, and never translates scientific failure into provider poison. Core status
types, mappings, gates, and sequential failure selection are not deletion targets.

K06 also remains on its current Core path. A future experiment may isolate only accepted-item
filtering and fixed candidate-indexed evaluation records; it must leave dynamic target application,
relationship reset/emission/preparation/publication, K07 ordering, and accepted-copy transaction
meaning in Core. That experiment is not adopted unless its LocalWorksets events join the existing
queue preflight, lease capacity, method identity, retaining fence, and final settlement without a
wrapper lifecycle or net source growth.

## Ordinary test and benchmark design

Development validation should use the repository's normal Julia test design:

- focused unit tests for constructors, admission, binding/access, aliases, topology, workspace,
  inspection, leases, poison, and failure visibility;
- executable non-CPM witnesses with simple independent direct oracles;
- existing CorePotts reference-oracle comparisons for each adopted operation;
- CPU and each actually claimed accelerator backend;
- determinism checks across workgroup sizes and repeated submissions where claimed;
- allocation, launch-count, workspace-byte, and throughput benchmarks proportional to the feature;
  and
- for a proposed CorePotts adoption only, a source/dependency census showing that displaced
  production machinery exceeds the complete new adapter while reference/oracle code remains.

No separate migration suite, proof artifact system, review bureaucracy, or ceremonial phase record is
required. Tests should directly encode the semantic law. Benchmarks should directly compare the
final implementation to the displaced path or an equivalent direct launch.

## API surface discipline

The immediate work should add no lifecycle, scheduler, event, workspace, topology, or transaction
noun. Prefer extending:

- `active_prefix` and `active_mask` as the closed `active` selector constructors;
- `sequence` for heterogeneous stages;
- `independent` plus `pointwise_read` for the narrow scalar RMW law;
- `combined`, `deterministic`, and `fast` for curated operations; and
- `resolved(...; on_empty=...)` for preserve-on-empty and qualified record values.

Runtime routing adds only one address-source spelling and bounded keyed `emit`/`candidate` forms. If
it grows separate public constructors for combined, resolved, histogram, graph, owner, or claim
cases, the design is wrong.

Avoid the following public names and claims:

- generic monoid or arbitrary device operation;
- dynamic topology;
- atomic record or atomic multi-array publication;
- transaction, rollback, or commit;
- task/command graph, scheduler, work queue, or frontier;
- globally conflict-free, matching, maximal, or optimal arbitration; and
- cross-backend bitwise determinism.

## One-time committee audit questions

The requested committee should review this design once and answer:

1. Does each immediate law fit the original bounded local-computation charter?
2. Is any proposed new public concept already expressible through the existing axes?
3. Are active-mask and pointwise-RMW safety actually enforced by the callable interface?
4. Does heterogeneous sequence remain a finite typed tuple on one lane?
5. Are preserve-on-empty and same-winner records free of transactional or atomic claims?
6. Is the runtime-keyed grouped law bounded, deterministic, fail-closed before ordinary
   publication, and honestly inspected as linear grouping plus stable-segment publication?
7. Are Core scientific transactions, greedy conflict semantics, RNG, Hamiltonian folding, and
   checkpoint meaning still entirely Core-owned?
8. Is the direct edit set more Julian and smaller than adding adapters or new mechanism families?

After remediation, the committee's disposition should be recorded in this file. It does not become
an ongoing development process.

## Research and committee disposition

Three research rounds covered: current-law and seam inventory; formal semantics, implementation
feasibility, and adversarial cross-domain scope; and final API, adoption, and rejection convergence.
The independent one-time committee then reviewed Julian/API design, GPU/lifetime correctness, and
CorePotts scientific ownership.

The first committee pass rejected unsupported Core deletion claims and underspecified topology,
RMW, selector, record, compilation, and runtime-key settlement contracts. Those findings were
remediated directly in this document. The final committee disposition is:

| Review | P0 | P1 | P2 | Disposition |
|---|---:|---:|---:|---|
| Julian/API minimality | 0 | 0 | 0 | Accept |
| GPU, determinism, lifetime, and failure | 0 | 0 | 0 | Accept |
| CorePotts science, scheduling, and adoption boundary | 0 | 0 | 0 | Accept |

This closes the requested research audit. Implementation proceeds through direct edits and ordinary
tests and benchmarks, not another review or migration process.
