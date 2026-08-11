# LocalWorksets V1 Normative Contract

Date: 2026-08-09

Status: Accepted architecture; bounded internal implementation qualified through LW-R1;
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

## Public model

The public lifecycle is:

```text
localwork -> plan(work, topology; backend) -> prepare(workplan, storage; workspace)
          -> run! -> WorkEvent -> wait
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
    submission = (; active_count = value_slot(Int32; bounds = 0:edge_capacity)),
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

For `independent`, planning MUST prove exactly one emitted value for every destination in the
selected output coverage and no competing writer. Missing and duplicate writers reject. For
`combined`, the declared identity is published for every destination receiving no contribution.
For `resolved`, the declaration MUST provide a total ranking and canonical semantic tie breaks
independent of launch or arrival order. Empty publication is result-layout specific and explicit:
a keyed-value result publishes its declared empty for every key receiving no candidate; an
item-selection result publishes its declared empty for each eligible item that loses the declared
resolution relation, leaves ineligible or masked items untouched, and reports the internal
no-winner key state through inspection. A false `masked` lane emits nothing; it is not an identity
or empty candidate.

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

LocalWorksets can enforce aliases and reject mutation/rebinding performed through its own API. It
MUST NOT claim a global mutation registry or interception of arbitrary external kernels/libraries.
External mutation of leased storage is a caller contract violation. Mutable outputs and workspace
of concurrently active prepared values must be disjoint; cross-lane coordination belongs to the
caller or a higher-level orchestrator.

## LW-A12 — Active selection is not output masking

Active-item selection is a submission-level count, mask, or compacted index set. It MUST be applied
before gather, destination calculation, local-operation evaluation, and emission. It must fit the
capacity proven by `WorkPlan`. Unselected items perform no local operation. `independent` coverage
applies to the selected workset, and storage outside the selected output domain is untouched; this
does not add a general retain-output semantic.

`masked(values, mask)` is output-lane masking. Julia evaluates `values` eagerly. It suppresses fixed
bounded emission slots after the local operation, and false lanes mean no emission rather than an
identity value. It is valid only when payload computation is already safe. It MUST NOT guard an
otherwise invalid gather or destination.

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
        combine = deterministic_sum(Float32; identity = 0.0f0, order = :semantic))),
) do edge, local_state
    spring_force(edge, local_state)
end

workplan = plan(work, spring_topology; backend)
prepared = prepare(workplan, (; positions, incidence, forces);
    workspace,
    submission = (;
        active_count = value_slot(Int32; bounds = 0:edge_capacity),
    ),
)

event = run!(prepared, (; active_count = Int32(active_edges)))
wait(event)
```

The arrays are exact static bindings. Reducing the active count does not replan. Changing incidence
does.

`deterministic_sum` is the concise deterministic numerical declaration: the identity is published
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
        mcs = value_slot(Int64; bounds = 1:typemax(Int64)),
        time = value_slot(Float64),
        parameters = value_slot(ParameterBlock),
        rng_address = value_slot(RNGAddress),
        active_bank = value_slot(UInt8; bounds = 1:2),
        active_count = value_slot(Int32; bounds = 0:site_capacity),
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

- `masked(values, mask)` is not active-item selection and cannot make eager payload evaluation safe.
- Same-lane physical order does not legalize undeclared aliases.
- A length check is not sufficient validation for submission-bound storage.
- `PreparedWork` does not accept arbitrary dynamic arrays without declared slots.
- A synchronous SciML adapter does not make lower `run!` synchronous.
- LocalWorksets does not intercept arbitrary external mutation, own scientific transactions, or
  create a cross-task scheduler.
