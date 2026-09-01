# LocalWorksets construction-pain audit

Status: CA-0 through CA-4 complete and qualified; focused committee PASS

Date: 2026-08-15

The audit phase was read-only. Its bounded CA-0 through CA-4 remediation then
modified production source without reopening the accepted LocalWorksets
architecture, package name, lifecycle, output-family algebra, central lowering
boundary, or KernelAbstractions ordering contract. This record now includes the
remediation and qualification result.

The lifecycle remains:

```julia
workplan = plan(work, topology; backend)
prepared = prepare(workplan, storage; workspace)
event = run!(prepared, submission)
wait(event)
```

## Committee

Three independent reviewers inspected the candidate before deliberation:

1. a Julia API/usability reviewer;
2. a JuliaGPU/backend, lifetime, and validation reviewer; and
3. an external package adopter who attempted a combined incidence count and an
   independent stencil using only the documented public surface.

The chair separately traced the CorePotts K02 -> K03 proposal sequence, retained
conjunctive claims path, public examples, construction evidence, and normative
contract. The reviewers agreed that the lifecycle and automatic-workspace path
are sound and should remain. They also agreed that broader migration should
pause for bounded remediation. Severity differed for unsupported direct access
to private prepared-state fields; that dissent is retained below.

## Verdict

LocalWorksets does not need another authoring redesign. Common static storage is
already an ordinary named tuple, automatic workspace is allocated once during
`prepare`, and the accepted lifecycle is cohesive. The remaining pain is
concentrated at four seams:

1. a `PreparedWork` does not completely freeze nested runtime/provider
   references;
2. caller-owned workspace cannot be constructed mechanically from the public
   plan evidence as the README claims;
3. topology is explicit but lacks a complete canonical/prepared leaf contract,
   an allocation-free identity-route spelling, and a way for operations to read
   centrally owned connectivity without duplicating it as storage; and
4. CorePotts repeats planning and descriptive evidence that LocalWorksets can
   derive authoritatively.

The correct next action is a construction-hardening amendment, followed by a
focused CPU/real-Metal review. It is not a new execution family and it must not
move physics, clocks, RNG, transactions, or checkpoint meaning into
LocalWorksets.

## Current construction trace

| Stage | Current author obligation | Classification |
|---|---|---|
| `localwork` | one-based items; read-role to logical-binding names; named output declarations; optional active-prefix slot | retain |
| `topology` | exact `UInt64` epoch; route matrices keyed by route name; destination counts keyed by output port; semantic IDs keyed by resolved port | retain the facts; simplify representations and documentation |
| `plan` | explicit backend before concrete storage attachment | retain; required for fail-closed qualification |
| static storage | exact named tuple of read and output arrays | retain; already Julian |
| submission schema | exact scalar bounds and dynamic-array representation/access | retain exactness; permit derived spellings where the plan already proves the same fact |
| automatic workspace | omit `workspace`, optionally provide `lease_capacity` | retain; this is the normal path |
| caller workspace | reproduce lowering-private nesting and append `Vector{Any}` lease slots | remediate |
| execution | exact named submission, `run!`, cumulative `wait`/`waitall` | retain |

The two topology namespaces are intentional but underexplained: `routes` is
keyed by the route symbol stored in an output declaration, while
`destination_counts` and resolved `semantic_ids` are keyed by output port. This
allows several ports or ordered stages to share a route, but diagnostics and
documentation must state the distinction directly.

`active` is not a general mask. The implemented contract is an `Int32`
active-prefix count bounded by the declared item capacity. Public documentation
and inspection should use that exact description consistently.

## Required remediation

### CA-0 -- prepared-state and topology integrity

This slice precedes ergonomic sugar.

- Make `_PreparedDirectIndependent`, `_PreparedBufferedCombined`,
  `_PreparedResolvedWinner`, and `_PreparedConjunctiveResolved` immutable, as
  `_PreparedSingleResolved` already is, or make every kernel/topology/workspace
  reference field `const`.
- Make `_KernelAbstractionsLane.scope` immutable after construction. In the
  shared scope, freeze backend, device, owner, and reviewed environment; retain
  mutation only for poison state and counters.
- Add one private topology-leaf specification parallel to the workspace-leaf
  specification. It must drive canonical-host validation, prepared copy,
  element type/rank/shape/stride checks, backend/device coherence, alias law,
  byte accounting, identity facts, and inspection.
- Require current V1 plan-time route and semantic-ID leaves to be canonical
  host arrays before any host iteration. A future device-native topology
  validator requires separate qualification.
- For the retained CorePotts claim profile, compare the complete canonical
  checkerboard/proposal-offset epoch with both execution banks before accepting
  the identity-order proof.
- Choose and document the stable-array policy. Either centrally admit exact
  stable concrete array representations, or revalidate complete
  backend/device/type/shape/stride/access/alias facts on every run. Generic
  wrappers must not inherit Array/MtlArray evidence merely because
  `KernelAbstractions.get_backend` is applicable.

The backend reviewer classifies replaceable nested prepared state as P0 because
ordinary Julia field access can reach it and replacement silently bypasses
validated topology. The chair notes that `runtime` and provider fields are
excluded from public `propertynames` and direct mutation is unsupported. This
does not remove the finding: immutability is cheap, matches the advertised
frozen-preparation contract, and is mandatory before admitting more consumers.

### CA-1 -- construction evidence and caller workspace

The README states that an explicit caller workspace can be constructed from
`LocalWorksets.inspect(workplan).workspace`. That is not currently true. The
private `_WorkspaceLeaf` knows each leaf's path, type, size, strides, and role;
plan inspection generally exposes capacities and byte totals, not a complete
round-trippable schema.

Add public, immutable, derived facts for:

- required logical binding names and access modes;
- every algorithmic workspace leaf's semantic name, path, element type, shape,
  required strides, role, backend requirement, and bytes; and
- host lease capacity as lifetime bookkeeping distinct from algorithmic device
  scratch.

The evidence must be derived from the same private specification used by
validation and lowering. It must not create a second evidence graph.

After exposing complete facts, choose one bounded Julia spelling for
caller-owned buffers. The preferred direction is a package-owned constructor
from `WorkPlan` plus named leaf overrides and explicit lease capacity. It may
return the current immutable named-tuple tree; a new scheduler, pool, allocator
hook, or lifecycle noun is unnecessary. Existing explicit workspaces remain a
compatibility path.

Extra undeclared array leaves must either reject or be explicitly reported as
caller decoration excluded from algorithmic byte claims.

### CA-2 -- topology authoring without hidden semantics

- Add a public, typed, allocation-free spelling for the exact one-lane
  `destination == item` route. Planning must prove its item and destination
  counts and retain zero transfer bytes. Do not infer destination capacity from
  a maximum route value.
- Add a declarative topology-backed read spelling so an operation can read a
  centrally copied frozen route/connectivity leaf without binding a second
  storage array. This remains a validated read, not an opaque gather callback.
  The same topology leaf must drive both operation input and publication route
  when so declared.
- Keep epoch, destination counts, non-identity connectivity, resolved semantic
  IDs, and topology ownership explicit.
- A compact `value_slot(range)` spelling may derive the exact scalar type from
  the range. A storage-slot access mode may be inferred only when the WorkPlan
  proves one unambiguous logical access role; otherwise it remains explicit.

The topology-backed read is important for external spring/contact/stencil
authors. Today they must provide connectivity once as canonical topology and
again as execution storage. On GPU that is a host/device duplication, and
LocalWorksets cannot prove the two copies agree.

This does not make changing CPM ownership a frozen topology. Operations whose
destination key is the current cell owner still require separate
representability analysis; they must not be smuggled in by rebuilding a
`WorkPlan` every MCS.

### CA-3 -- CorePotts adapter consolidation

- Split `_prepare_core_localwork` into one reusable planning step and one
  per-storage preparation step. The two proposal-science banks currently repeat
  identical topology validation and planning inside `map(science)` even though
  `WorkPlan` is explicitly reusable.
- Replace the CorePotts `derivation` record's duplicated items, reads, routes,
  outputs, submission, and topology structure with LocalWorksets inspection
  facts. Retain only CorePotts semantic provenance: phase, science/capability
  authority, topology owner, descriptor identity, and checkpoint-relevant
  mechanism identity.
- Preserve CorePotts' package-owned method/world-age boundary, bank ownership,
  queue capacity, settlement, failure translation, RNG, Hamiltonian folding,
  and checkpoint contracts.
- Do not use the retained legacy conjunctive workspace as the model for common
  public authoring.

### CA-4 -- diagnostics, documentation, and evidence

- Populate stable `LocalWorkValidationError` fields on active-prefix, backend,
  workspace structure, device-coherence, item-domain, and semantic-ID failures.
- Pass the actual lifecycle stage into shared count validation; lease-capacity
  errors during `prepare` must not report `stage = :plan`.
- Correct normative examples that currently use non-existent
  `deterministic_sum` and bounds whose integer type does not match
  `value_slot(T)`.
- Document route matrix element type, shape, zero-destination behavior,
  port/route key namespaces, canonical host residency, and topology-backed read
  behavior in one executable example.
- Keep `inspect` non-synchronizing and keep all construction facts derived from
  authoritative validation/lowering state.

## Acceptance matrix

| Concern | Required evidence |
|---|---|
| prepared immutability | every lowering rejects replacement of kernel, topology, workspace-record, lane-scope, backend, device, owner, and environment references; zero submissions, unchanged output, empty leases, no poison |
| stable array qualification | retargetable wrappers, aliased views, changed backing/device/stride, and StructArray component mutations reject prelaunch; exact reviewed Array/MtlArray fast paths remain |
| canonical topology | device-resident plan inputs reject with `stage=:plan`, `contract=:topology_host_residency` before scalar iteration, transfer, or synchronization |
| prepared topology | wrong Adapt/copy type, shape, stride, backend, device, or address space rejects during `prepare`; inspection reports canonical and prepared facts |
| identity route | no host identity matrix allocation, zero topology transfer, same lowering/launch count/results on CPU and real Metal |
| topology-backed read | one authoritative leaf feeds operation reads and routing; stale/mismatched duplicate storage is impossible |
| workspace round trip | construct every admitted caller workspace solely from public plan facts; automatic and caller-owned results, bytes, launches, and determinism match |
| CorePotts planning | one WorkPlan shared by both proposal banks; two PreparedWork values retain exact bank/device identities |
| claim provenance | independent mutations of sites, color offsets, conflict displacements, and proposal offsets reject before submission or synchronization |
| performance | unchanged launch counts, no intermediate wait, one cumulative KA synchronization, no warm workspace growth or topology transfer, no CPU/Metal regression outside frozen bounds |
| documentation | every README/normative construction snippet executes against the current API |

## Rejected shortcuts

- inferring destination counts from route maxima or output storage length;
- inferring topology epoch or backend ownership;
- treating arbitrary device arrays as plan-time host topology;
- exposing private workspace structs or lowering-specific nesting as the public
  API;
- shape-only dynamic storage slots;
- treating `objectid` as a complete backend/device/alias proof for arbitrary
  mutable wrappers;
- hidden per-run allocation, Adapt-based workspace fallback, lease growth,
  transfer, host fallback, or synchronization;
- using a new convenience to reopen the lifecycle or add a scheduler; and
- migrating dynamic owner-keyed CPM statistics by replanning after every copy.

## Committee ballots

| Reviewer | Ballot | Findings |
|---|---|---|
| Julia API/usability | REMEDIATE before broader migration | P0 public caller-workspace round-trip; P1 topology namespaces, active-prefix wording, diagnostics, repeated CorePotts planning; P2 identity-route allocation |
| JuliaGPU/backend/lifetime | BLOCK before broader migration | P0 nested prepared-state substitution; P1 stable-array qualification, prepared topology facts, host topology residency, claim provenance; P2 extra workspace leaves |
| external adopter | HOLD general authoring; narrow automatic-workspace examples are usable | P1 duplicated/unproved topology reads; P2 identity route, workspace construction evidence, route documentation, inference evidence |
| chair | BOUNDED REMEDIATION, then fresh review | no architectural contradiction; preserve qualified candidate as baseline and do not migrate another operation until CA-0 through CA-4 pass |

## Admission decision

The current exact qualified CorePotts path remains the behavioral and
performance baseline. No finding authorizes weakening its tests, evidence,
determinism, fail-closed admission, or KernelAbstractions ordering.

The bounded construction amendment has passed focused standalone, complete
LocalWorksets CPU, complete CorePotts CPU, qualified real-Metal, and fresh
committee review. Broader migration is therefore no longer held by CA-0 through
CA-4. The next adoption test should still be a bounded fixed-topology operation;
dynamic cell-owner statistics remain deferred until their destinations can be
represented without per-MCS replanning.

## Remediation outcome

### CA-0 -- complete

- Prepared execution objects and lane authority retain frozen backend, device,
  owner, environment, topology, workspace, and provider references.
- One topology-leaf authority now drives canonical-host validation, prepared
  copying, exact type/rank/shape/stride/backend/device/address-space checks,
  physical identity, transfer accounting, fingerprinting, and inspection.
- Arbitrary mutable/retargetable nested array representations reject rather
  than inheriting Array or MtlArray evidence. The initially considered generic
  nested `BitArray` exception was rejected as unsafe; CorePotts instead owns an
  immutable `Tuple{Vararg{Bool}}` lifecycle projection.
- Submission-bound writable arrays cannot alias prepared topology, and dynamic
  submission storage can establish the prepared device authority when static
  storage is empty.

### CA-1 -- complete

- `workspace_requirements(workplan)` exposes the complete derived algorithmic
  leaf schema and separate host lease requirement.
- `allocate_workspace(workplan; ...)` constructs caller-owned workspace from
  that same authoritative private specification. Automatic and explicit paths
  share validation and round-trip tests; no lowering-private struct is public.

### CA-2 -- complete

- `identity_route` is an explicit allocation-free topology declaration and
  reports zero topology transfer bytes.
- `topology_read` gives operations a validated read of centrally owned prepared
  connectivity. Reusing one leaf for operation input and publication preserves
  physical identity rather than copying the connectivity into storage.
- Extra topology reads participate in validation and topology freshness; wrong
  type, rank, shape, residency, and stale mutation reject before execution.

### CA-3 -- complete

- CorePotts plans the proposal sequence once and prepares it against two
  concrete storage banks.
- CorePotts provenance retains only domain authority and identities; structural
  work/topology/binding/workspace evidence comes from LocalWorksets inspection.
- RNG, Hamiltonians, science, clocks, transactions, settlement, checkpoints,
  method-world trust, and queue ownership remain CorePotts-owned.

### CA-4 -- complete

- Active-prefix, topology, backend, item-domain, device, workspace, and
  semantic-ID failures carry stable structured validation fields.
- Normative and README examples use exact scalar types and document topology
  layout, route/port namespaces, host residency, topology-backed reads,
  workspace backend facts, and asynchronous completion.
- Shared inspection/evidence and validation machinery was consolidated where it
  was mechanically identical. Qualified specialization and all safety checks
  were retained; no line-count target drove the change.

## Qualification evidence

| Evidence | Result |
|---|---|
| focused construction/API tests | PASS; all topology, workspace, identity-route, stale-state, alias, and immutability witnesses |
| complete LocalWorksets CPU suite | PASS, including package quality, source-size admission, backend conformance, hostile extension methods, and all execution families |
| complete CorePotts CPU suite | PASS on the exact final source, including package quality, checkpoints, RNG/replay, lifecycle, proposal science, failure boundaries, world-age trust, and LocalWorksets verticals |
| qualified full real-Metal suite | PASS for the substantive candidate, including cross-domain witnesses, native components, queued 12-MCS execution, one final synchronization, and exact settlement/RNG/failure parity |
| exact-final Metal delta witness | PASS for immutable lifecycle constraint storage and forbid-extinction rejection after the final type-bound tightening |

The final Metal delta consisted only of moving unchanged helper methods between
already included source files and tightening immutable Boolean tuple storage.
The backend reviewer accepted the prior complete Metal run plus the exact-final
focused witness; no backend behavior, kernel, launch, wait, allocation, or
lowering changed. Timing observations are intentionally not interpreted because
the laptop power/location conditions changed during the runs.

### Exact candidate fingerprints

The review used SHA-256 fingerprints of the final construction-critical source
and tests:

```text
ea950412  LocalWorksets/src/model.jl
1249a4c0  LocalWorksets/src/execution/topology_support.jl
d6e68527  LocalWorksets/src/preparation.jl
a3755b7e  LocalWorksets/src/execution.jl
513bdf51  LocalWorksets/src/execution/localworksets_generic.jl
a93f6142  LocalWorksets/src/execution/localworksets_combined.jl
81aea477  LocalWorksets/src/execution/localworksets_combined_workspace.jl
f9b6af20  LocalWorksets/src/execution/localworksets_combined_evidence.jl
d0d1ac09  LocalWorksets/src/execution/localworksets_single_resolved.jl
7f01eefe  LocalWorksets/test/test_api.jl
a4055e88  LocalWorksets/test/test_mechanisms.jl
99427ca7  CorePotts/src/execution/localworksets_adapter.jl
d50fcd80  CorePotts/src/execution/localworksets_proposal_stages.jl
6623310d  CorePotts/src/execution/lifecycle_plan.jl
87601206  CorePotts/test/test_program_v1_state.jl
```

The abbreviated values are presentation prefixes; the review log retained the
complete hashes.

KernelAbstractions still owns launch execution and implicit ordering. Sequences
insert no intermediate host wait; `wait` performs one portable backend
synchronization over the cumulative submitted prefix. LocalWorksets gained no
queue, stream, command-buffer, scheduler, host fallback, or vendor branch.

## Final committee freeze ballot

| Reviewer | Final ballot | Open findings |
|---|---|---|
| Julia API/usability | PASS | P0=0, P1=0, P2=0 |
| JuliaGPU/backend/lifetime | PASS | P0=0, P1=0, P2=0 |
| external package adopter | PASS | P0=0, P1=0, P2=0 |
| chair | PASS CA-0 through CA-4 | no architectural contradiction; next migration remains a separate bounded decision |

The construction gate is closed. This ballot does not authorize a new execution
family, dynamic owner-keyed replanning, or an unreviewed operation migration.
