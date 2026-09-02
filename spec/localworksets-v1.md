# LocalWorksets V1 Normative Contract

Date: 2026-08-09

Status: Accepted architecture; bounded internal implementation qualified through the fused,
seed-existing, stable-grouped runtime-keyed, and shared-gate named-port laws;
standalone extraction governed by the post-LW-R1 roadmap

## Authority and closure

This contract is the authoritative pre-implementation definition of LocalWorksets V1. It freezes
the accepted capability-preservation decision as LW-A1 through LW-A14. The package name,
`LocalWork -> WorkPlan -> PreparedWork -> WorkEvent` lifecycle, public nouns, output semantics, and
central-lowering boundary are closed.

LocalWorksets is a small substrate for backend-portable execution of validated local work. It is not
a solver, scheduler, clock, RNG owner, lifecycle engine, checkpoint format, or domain framework.
Domain packages retain physics, time, randomness, scientific transactions, and solver semantics.

The architecture MUST NOT reopen unless implementation produces a concrete contradiction supported
by executable evidence. The owner-authorized LW-4C phase may reconcile constructors, conveniences,
composition, errors, inspection and extension authoring against real extracted-package examples;
it may not create a competing lifecycle or reopen naming by preference alone. Initial
implementation maturity was governed by the
[LocalWorksets Implementation and Review Gate](localworksets-v1-implementation-gate.md); extraction,
bounded completion and adoption are governed by the
[post-LW-R1 roadmap](localworksets-post-lwr1-roadmap.md).

The post-LW-5D construction amendment CA-0 through CA-4 is a bounded normative
clarification under that authority. It does not reopen this charter. It requires:

- immutable prepared kernel/topology/provider references, with mutation limited
  to counters, leases and poison state;
- canonical host-resident plan-time topology leaves and fully validated,
  inspectable prepared topology copies;
- complete public binding/workspace construction evidence derived from the same
  private specifications used by lowering and validation;
- explicit allocation-free identity routes and explicit topology-backed reads;
- reusable WorkPlans across concrete preparations; and
- structured diagnostics and executable documentation for every public
  construction path.

The exact requirements, acceptance matrix and committee dissent are recorded in
the [construction-pain audit](../design/hardening/localworksets-construction-pain-audit.md).

## Public model

The public lifecycle is:

```text
localwork -> plan(work, topology; backend) -> prepare(workplan, storage; workspace)
          -> run! -> WorkEvent -> wait / waitall
```

- `LocalWork` declares items, reads, the local operation, named outputs, and optional active-item
  selection.
- `WorkPlan` is an immutable, shareable result of central validation and topology analysis. It owns
  the topology identity, epoch, bounds, and backend-qualified lowering, but no submission values,
  concrete storage identities, workspace, or execution lane.
- `PreparedWork` fixes the concrete backend device/context and a logical submission/wait adapter
  admitted by the plan, device representation of the planned topology, launch geometry, workspace,
  storage bindings or storage schemas, and a named submission schema. Preparation validates rather
  than redefines topology. A provider MAY share one physical completion/failure scope across
  multiple adapters when its portable synchronization primitive is backend-wide.
- `WorkEvent` is a thin, truthful receipt for the underlying provider completion scope.

Named output ports independently use one of three public meanings:

- `independent`: each selected destination has one validated writer;
- `combined`: contributions to a destination are combined under a declared operation; or
- `resolved`: competing candidates for a key are selected under a declared resolution law.

Execution-family, proof, certificate, settlement, and compiler-node terminology remains private.
Ordered stages use `sequence(a, b, ...)`; internal barrier nodes are not public.

## LW-A1 — Prepared execution lane and storage modes

`plan(work, topology; backend)` MUST fix topology ownership and the backend-qualified lowering.
`prepare(workplan, storage; workspace)` MUST fix the concrete provider device/context, one logical
submission/wait adapter, device topology representation, launch geometry, bindings, and workspace
admitted by that plan. Backend value equality alone is insufficient. Planning and preparation MUST
match the complete reviewed backend/runtime/device fingerprint. Warm validation MAY use a cheaper
exact current-device token only after that complete fingerprint has been frozen.

Static exact-array binding is the default:

```julia
workplan = plan(work, topology; backend)
prepared = prepare(workplan, (; positions, incidence, forces);
    workspace,
    submission = (;
        active_count = value_slot(
            Int32; bounds = Int32(0):Int32(edge_capacity)
        )
    ),
)
```

Static bindings fix exact identities and aliases. The only alternative is an explicitly declared
submission-bound storage slot:

```julia
submission = (;
    x = storage_slot(x_template; access = :read),
    y = storage_slot(y_template; access = :write),
)
```

A storage slot fixes the qualified concrete array representation, element type, dimensionality,
shape, layout, address space,
backend/device/context, access role, and alias rules. `run!` supplies the concrete identity and MUST
validate every fixed fact before launch. Slots MUST NOT be inferred from arbitrary array arguments.

`PreparedWork` is ordered-reentrant through its bound logical adapter with one serial host
submitter. Same-adapter submissions MAY queue because provider ordering serializes shared
workspace. Simultaneous calls, task migration, unqualified cross-stream submission, or another
device MUST reject before launch. Independent mutable storage still requires distinct prepared
values and disjoint outputs/workspace, but this does not imply independent backend error scopes.
Validated read-only sharing additionally requires every earlier producer to have completed or been
bridged before ownership transfer.

## LW-A2 — WorkEvent is a truthful receipt

`run!` is asynchronous where supported and returns queued/encoded work. `WorkEvent` MUST report its
provider, lane, wait scope, transfer law, and whether waiting is cumulative.

KernelAbstractions 0.9 implicit ordering does not provide portable dependency events. A generic KA
receipt therefore describes the cumulative submitted prefix of its logical adapter and is not a
scheduler dependency. The accepted KA provider uses exactly one portable
`KernelAbstractions.synchronize(backend)`: adapters prepared on the same backend/device and owner
task share that backend-owner-task completion and failure scope. A wait is same-owner-task,
cumulative, and non-selective; it drains the actual submitted prefix covered by that backend
synchronization. A backend failure poisons every preparation sharing the scope because portable KA
cannot attribute it selectively. A provider-native transferable event MAY be offered only with its
synchronization, batching, allocation, readiness, and error-attribution behavior separately
qualified.

Host visibility is guaranteed after `wait(event)`. `isready` MUST be absent unless the provider has
a qualified nonblocking query.

When several `PreparedWork` values share the exact provider completion scope,
`waitall(event1, event2, ...)` MAY settle their snapshotted cumulative tails
with exactly one provider synchronization. Every event MUST have the same
owner task, backend/device completion scope, and centrally admitted provider;
cross-scope groups reject before synchronization. Successful grouped waiting
releases every participating submitted prefix only after the shared wait
returns. A provider or synchronization failure releases none, poisons every
participating preparation, and preserves the provider's shared poison scope.
Already drained events are idempotent and do not force another synchronization
under ordinary releasing settlement. `waitall(...; release=false)` is the
retaining-fence policy of the same operation: it always synchronizes the
current provider tail, including when supplied receipts are already drained,
and changes no submitted/drained counter or lease. A later releasing `waitall`
performs a fresh synchronization before release. Grouped waiting is explicit
lifetime settlement: it does not create event
dependencies, a scheduler, native queues, transferable receipts, or selective
error attribution.

## LW-A3 — Ordered stages use provider implicit ordering

`sequence(a, b, ...)` MUST lower all stages onto the same qualified lane in program order. It MUST
NOT add an intermediate host fence or manufacture a public event between stages. The final wait
establishes host visibility. Cross-lane or cross-backend sequencing MUST reject unless a future
provider qualifies an explicit bridge.

## LW-A4 — Workspace and allocation

`prepare` MUST allocate or validate all algorithmic workspace. Warm `run!` MUST perform no device or
host workspace growth, topology transfer, hidden pool acquisition, or host fallback.

Total Julia zero-allocation is not portable because provider launches may allocate. Qualification
therefore requires direct parity against identical direct launches with the same lease/event scope,
stable inspected workspace bytes, and separate launch, wait, transfer, and allocation counters.

## LW-A5 — Routing and topology evidence

Each output port MUST declare a concrete device-compilable route containing its source and
destination key spaces, bounded emissions per item, role/sign transform, value or candidate type,
result layout, combination identity or explicit resolved empty result, and empty behavior.

For fixed-route `independent`, planning MUST prove exactly one emitted value for every destination
in the selected output coverage and no competing writer. Runtime-keyed independent instead proves
the corresponding facts in its prepublication validation phase. Missing and duplicate writers
reject before publication. For `combined`, `initial=:identity` publishes the declared identity for
a destination receiving no contribution. The qualified `initial=:existing` law instead defines
each destination as
`foldl(operation, canonical_emissions; init=old(output[d]))`; no emission preserves the old value.
The existing value is a publication-owned read and is invisible to the operation. Seeded output is
therefore an exact read/write binding and must satisfy the ordinary non-aliasing rules against every
operation read, other output, workspace leaf, and prepared topology array. The initial seeded row is
deterministic modular `UInt64 +` with identity `UInt64(0)` on qualified CPU and accelerator
backends. `fast(...), initial=:existing` is not admitted.

`independent(runtime_route(D); coverage=:all|:partial)` uses bounded runtime keys without adding a
scatter family. An enabled nonzero key must be in `1:D`; zero and disabled records participate in
neither uniqueness nor coverage. Before publication, one deterministic validation phase selects a
total diagnostic in class order `invalid_domain < duplicate_key < incomplete_coverage`, using
canonical `(item,lane)` record order and the lexicographically minimum duplicate pair. `:all`
requires exactly one record for every destination; `:partial` preserves unmatched destinations.
No port publishes after normal validation failure. The stable-grouped lowering shares one keyed
record workspace, gate, status transfer, phase tuple, provider lane, leases, and prepared lifecycle
with combined and resolved keyed work. One device item constructs destination counts, exclusive
offsets, and a stable canonical-record permutation in `O(R + D)` work; publishers visit only their
segments. It adds no host cardinality read, callback, or synchronization.

Named runtime-keyed outputs use the same lowering and lifecycle. All keyed outputs in one work must
use runtime routes. The operation is evaluated exactly once per selected item and materializes every
port before one shared device validation opens one shared gate. Cross-port diagnostics are ordered
by `(failure_class, canonical_port_index, primary_record, secondary_record)`, with global class
priority `invalid_domain < duplicate_key < incomplete_coverage`. Mixed signed and unsigned witness
bits decode through the selected port's planned key type, preserving the public diagnostic tuple.
Three launches initialize, apply, and group/validate all ports; one monomorphic segment publisher
then follows per canonical port, for `3 + P` launches. A normal validation failure writes no port.
Publication-phase provider failure has no rollback or cross-port atomicity guarantee.
For `resolved`, the declaration MUST provide a total ranking and canonical semantic tie breaks
independent of launch or arrival order. Every resolved output uses the same generic candidate
contract: an eligible operation emits `candidate(rank, value, condition)`, a false condition emits
nothing, and a destination receiving no candidate publishes the declaration's explicit `empty`
value. Named resolved families and result-layout-specific selection semantics are not part of the
contract.

The only bounded item-selection profile admitted before LW-R1 is the exact two-key conjunctive
profile in the
[LW-2 amendment](../design/hardening/lw2-bounded-conjunctive-amendment.md). That profile does not
imply arbitrary multi-emission, heterogeneous-output, or combined-output support.

Central planning MUST derive item and destination bounds, exact or bounded emissions,
injectivity/conflict facts, required canonical order or coloring, topology identity/epoch/fingerprint,
backend × type × operation × address-space support, and symbolic workspace formulas. External
extensions MUST NOT self-certify these facts or authorize their own backend execution.

Changed shape, boundary map, incidence, DOF mapping, destination domain, or conflict footprint
requires a new topology epoch and plan. Static cell labels or population values on an unchanged
lattice do not.

## LW-A6 — One named submission-binding surface

Submission values MUST NOT enter `WorkPlan`. Each `PreparedWork` declares one exact schema, authored
with named value and storage slots. The execution spelling is:

```julia
event = run!(prepared, (;
    time,
    parameters,
    active_count,
    active_bank,
))
```

The schema MAY include time/MCS, scalar parameters, RNG address components, active bank, active-item
selection, attempt/color ordinal, status epoch, or declared storage slots. LocalWorksets MUST NOT
export CPM-, FEM-, LBM-, or MTK-specific control names; domain packages MAY wrap this interface.

Validation MUST require exact names, concrete types, and bounds. Missing names, extra names, invalid
types/bounds, and invalid storage MUST reject before launch. Internal order is the prepared schema
order, independent of NamedTuple source order. Same-typed value changes MUST NOT replan or recompile.
This plain named binding is sufficient; V1 has no additional public submission noun.

## LW-A7 — Alias and fixed-order combination

General input/output aliasing is illegal. A pointwise stage MAY read old `y[d]` and independently
overwrite `y[d]` only when topology proves identical one-to-one read and write maps.

Fixed-order combination is ordered by semantic item ID and local output slot across every internal
bucket. Bucket order, launch order, and atomic arrival are not semantic. Mixed FEM arities remain one
semantic combined output even when lowering uses several internal buckets.

Floating-point combination MUST choose numerical semantics explicitly. Bare operations such as
`combine = +` reject because they do not say whether order is canonical or deliberately relaxed.
A deterministic declaration supplies an identity and semantic order; a fast declaration explicitly
accepts its qualified backend reduction tree or atomic ordering. Neither declaration may silently
upgrade its reproducibility guarantees.

## LW-A8 — Profiles report guarantees; lowering remains central

Profiles state guarantees, not mandatory kernels. Central lowering MAY choose validated direct
stores, coloring, atomics, fixed reduction, arbitration, or fusion. It MUST NOT call opaque external
execution hooks, branch on domain names, silently relax numerical order, allocate unbounded records,
or fall back to the host.

LocalWorksets reports mechanism capability. CorePotts and other domains compose scientific
capability, RNG identity, checkpoint meaning, and solver claims.

CorePotts Hamiltonian authoring is a preservation boundary. `HamiltonianTerm`, `Volume`,
`ContactEnergy`, `Elongation`, and registered external Hamiltonians retain their public authoring.
`complete` and `mtkcompile` continue proving purity, domains, and bounded affected anchors. Current
before/after proposal views remain CorePotts-owned, and canonical source-order Hamiltonian folding
MUST NOT become an unordered LocalWorksets reduction. LocalWorksets may be inserted only beneath
compiled descriptor evaluation; Hamiltonian authors do not author LocalWorksets declarations.

## LW-A9 — Inspection and rejection are executable contracts

Inspection MUST expose topology evidence, static bindings, submission slots, alias rules,
provider/device/lane, lowering/fusion, launch count, workspace and transfer bytes, record capacity,
reentrancy, event scope, allocation class, poison state, and determinism evidence.

Unsupported type/operation/address space, invalid route, stale topology, insufficient workspace,
invalid alias, cross-device storage, invalid binding, or illegal concurrent use MUST reject before
partial execution.

## LW-A10 — Publication and poison

LocalWorksets does not promise universal transactionality. Direct `independent` output may be
partially modified after an append or backend failure. A `combined` or `resolved` branch is
failure-atomic only when inspection proves private bounded emission plus gated final publication.
Domain-level scientific atomicity may require double buffering, rollback, or reconstruction.

Prelaunch schema, topology, alias, capacity, world-age, method-owner, or dispatch validation failure
does not poison. After central validation has selected an admitted lowering, a synchronous failure
may follow an already appended launch and therefore conservatively poisons `PreparedWork`, as does
a backend/device error or detected lifetime/ownership violation. If the provider exposes only a
shared backend completion boundary, the same failure poisons every preparation in that exact
backend/device/owner-task scope. Poisoned work permits inspection only; the accepted KA provider
does not simulate selective recovery. Generic recovery requires a fresh owner task/provider scope
and re-preparation; V1 MUST NOT promise a universal `reset!`.

## LW-A11 — Submission leases, lifetime, and external mutation

Every queued submission MUST retain a lease over its concrete device arguments, workspace, frozen
topology/operation representations, and provider resources until completion. Dropping
`PreparedWork` or `WorkEvent` does not cancel execution. No finalizer may wait or synchronize.
Abandoned-event completion, reclamation, and error observation occur through a later owner-task
wait while that owner remains available. Owner-task exit is not cancellation. Cross-task recovery,
transfer, reclamation, and simulated provider-wide drain are outside the accepted KA contract and
MUST be reported as unsupported rather than fabricated.

For several prepared values in one provider scope, the owner MAY use
`waitall` to couple the physical backend-wide completion boundary to all
participating lease ledgers. A domain orchestrator chooses which events form
that explicit settlement group; LocalWorksets does not infer scientific
transactions or silently drain omitted preparations. The group snapshots each
participating preparation's complete submitted tail before waiting, retains
all arguments and workspace until success, and then reclaims every covered
tail. Waiting an older receipt remains cumulative for that preparation.

LocalWorksets can enforce aliases and reject mutation/rebinding performed through its own API. It
MUST NOT claim a global mutation registry or interception of arbitrary external kernels/libraries.
External mutation of leased storage is a caller contract violation. Mutable outputs and workspace
of concurrently active prepared values must be disjoint; cross-lane coordination belongs to the
caller or a higher-level orchestrator.

## LW-A12 — Active selection precedes operation evaluation

Active-item selection is a submission-level count, mask, or compacted index set. It MUST be applied
before gather, destination calculation, local-operation evaluation, and emission. It must fit the
capacity proven by `WorkPlan`. Unselected items perform no local operation. `independent` coverage
applies to the selected workset, and storage outside the selected output domain is untouched; this
does not add a general retain-output semantic.

`when = :name` declares a work gate distinct from ordinary reads, outputs, and active selection.
The named binding MUST be a read-only, one-dimensional `Bool` array of length one on the prepared
backend and device, and MUST satisfy the ordinary non-aliasing rules against writable storage,
workspace, and topology. The gate MUST be observed on the device in provider program order. When
the observed value is false, no item operation is evaluated and no live output is published. When
it is true, the operation is evaluated exactly once for each item selected by `active`. External
mutation of a leased gate while a submission is outstanding is a caller contract violation.

Conditional output is expressed by the condition carried by `emit` or `candidate`. Julia evaluates
their payload arguments eagerly, so a false condition suppresses publication but MUST NOT be used to
guard an otherwise invalid gather, destination, or payload calculation. The retired `masked`
wrapper is not part of the API.

A centrally qualified work with exactly one resolved output, `maximum = 1`, minimum- or maximum-rank order, a
`UInt32` tie-break identity, one destination, and one to four read bindings MAY lower to the fused
single-resolved profile. That profile MUST use one device thread in one `resolve_publish` launch,
MUST admit the complete planned item capacity, MUST NOT transfer derived segment topology, and MUST
use neither global algorithmic nor threadgroup workspace. When gated, the phase MUST snapshot the
gate once at phase entry before operation evaluation. Inspection MUST report the invocation rule,
gate-read timing, admitted capacity, destination count, workspace bytes, and segment-transfer fact.

The fused profile MAY accept resolved record values through a wide component-record boundary of at
most 12 primitive, backend-qualified leaves, 48 bytes, and alignment eight. A record outside the
narrow packed boundary of eight fields, 16 bytes, and alignment four MUST use a `StructArray`
structure-of-arrays binding. Inspection MUST expose `record_profile = :wide_component_record`,
`record_layout = :structarray_soa`, and the logical component schema. The fused profile guarantees
one logical winner; it does not promise atomic multi-field publication after provider failure.

A centrally qualified deterministic combined work MAY use `initial=:existing`.
The existing destination participates exactly once before canonically ordered
candidate records; an empty destination preserves its existing value. Fixed
routing uses the ordinary apply and canonical-publish phases. Runtime-keyed
routing snapshots seeds into planner-owned workspace before evaluation. The
qualified catalog is `Int32`/`UInt32` addition, minimum, maximum, bitwise and,
or, and xor; `Float32` addition; and `UInt64` addition. Seed load, final store,
and scalar combination must all be centrally qualified. This law is
deterministic publication, not a transaction guarantee after an asynchronous
provider failure.

## LW-A13 — Determinism is an evidence vector

Inspection and capability evidence MUST report independently:

1. same-run replay on one device;
2. workgroup-size invariance;
3. bucket-order invariance;
4. scheduling invariance;
5. same-backend bitwise reproducibility;
6. cross-backend bitwise reproducibility;
7. a stated numerical bound; and
8. RNG-trajectory reproducibility.

Every guarantee is qualified by backend, element type, operation, address space, compiler, and
lowering identity. A fixed reduction tree does not imply cross-backend bitwise identity. RNG
trajectory remains domain-owned.

## LW-A14 — Optional SciMLOperators boundary

LocalWorksets MUST NOT depend on ModelingToolkit or SciMLOperators. An extension MAY implement a
real `AbstractSciMLOperator` over `PreparedWork` with explicitly declared submission-bound `x` and
`y` slots.

Lower `run!` remains asynchronous. Synchronous `mul!(y, A, x, alpha, beta)` MUST wait before return
so `y` is visible to its matrix-like caller. Changed array identities are admitted only through the
prepared slot schema; same schema/types/bounds MUST reuse the plan and compiled lowering. A changed
shape, layout, type, device/context, alias relation, topology bound, or lane owner rejects before
launch.

## Lifecycle examples

### Static LSM storage

```julia
work = localwork(active_items(edges; count = :active_count);
    read = (; positions, incidence),
    outputs = (; forces = combined(vertices;
        combine = deterministic(+, Float32(0)))),
) do edge, local_state
    spring_force(edge, local_state)
end

workplan = plan(work, spring_topology; backend)
prepared = prepare(workplan, (; positions, incidence, forces);
    workspace,
    submission = (;
        active_count = value_slot(
            Int32; bounds = Int32(0):Int32(edge_capacity)
        ),
    ),
)

event = run!(prepared, (; active_count = Int32(active_edges)))
wait(event)
```

The arrays are exact static bindings. Reducing the active count does not replan. Changing incidence
does.

`deterministic(+, Float32(0))` is the explicit deterministic numerical declaration: the identity is published
for vertices with no contribution and contributions follow canonical semantic order. An explicitly
named fast reduction may be offered only with its weaker backend-qualified guarantees visible in
inspection; bare floating-point `+` is never accepted as an implicit choice.

### Illustrative dynamically controlled CorePotts execution

The following remains a future full-sequence illustration, not the bounded LW-2 implementation.
The admitted LW-2 claim-block wrapper binds only the arrays, live gate, and active count used by
that block; Core-owned MCS, RNG, bank, color, status, and checkpoint values must not be added as
decorative LocalWorksets fields.

```julia
workplan = plan(checkerboard_sequence, checkerboard_topology; backend)
prepared = prepare(workplan, core_static_storage;
    workspace = core_workspace,
    submission = (;
        mcs = value_slot(
            Int64; bounds = Int64(1):typemax(Int64)
        ),
        time = value_slot(Float64),
        parameters = value_slot(ParameterBlock),
        rng_address = value_slot(RNGAddress),
        active_bank = value_slot(UInt8; bounds = UInt8(1):UInt8(2)),
        active_count = value_slot(
            Int32; bounds = Int32(0):Int32(site_capacity)
        ),
        attempt_ordinal = value_slot(Int32),
        color_ordinal = value_slot(Int16),
        status_epoch = value_slot(UInt32),
    ),
)

event = run!(prepared, (;
    mcs, time, parameters, rng_address, active_bank, active_count,
    attempt_ordinal, color_ordinal, status_epoch,
))
```

CorePotts owns the meanings of these names, RNG, acceptance, double buffering, sticky status, and
scientific commit. Its wrapper maps them to the generic prepared schema.

### SciMLOperators submission-bound x/y

```julia
workplan = plan(operator_work, operator_topology; backend)
prepared = prepare(workplan, (; coefficients, operator_storage);
    workspace = operator_workspace,
    submission = (;
        coefficient = value_slot(Float32),
        alpha = value_slot(Float32),
        beta = value_slot(Float32),
        x = storage_slot(x_template; access = :read),
        y = storage_slot(y_template; access = :write),
    ),
)

function LinearAlgebra.mul!(y, A::LocalWorkOperator, x, alpha, beta)
    event = run!(A.prepared, (;
        coefficient = A.coefficient,
        alpha = Float32(alpha),
        beta = Float32(beta),
        x,
        y,
    ))
    wait(event)
    return y
end
```

The operator may accept new concrete `x`/`y` identities that satisfy the declared schema. The
submission lease retains those exact arrays through completion; the topology and workspace remain
fixed by the plan and preparation respectively.

## Rejected interpretations

- Conditional emission is not active-item selection and cannot make eager payload evaluation safe.
- Same-lane physical order does not legalize undeclared aliases.
- A length check is not sufficient validation for submission-bound storage.
- `PreparedWork` does not accept arbitrary dynamic arrays without declared slots.
- A synchronous SciML adapter does not make lower `run!` synchronous.
- LocalWorksets does not intercept arbitrary external mutation, own scientific transactions, or
  create a cross-task scheduler.
