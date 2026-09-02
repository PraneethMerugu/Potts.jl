# LW-1 semantic-portability evidence

Date: 2026-08-10

Status: historical exact evidence for the bounded one-key LW-1 artifact; superseded for current-tree
status by the bounded LW-2 amendment and [LW-3 parity evidence](lw3-localworksets-parity.md)

Authority: [LW-1 Implementation Matrix](lw1-implementation-matrix.md)

This file preserves the evidence snapshot reviewed before any conjunctive lowering or checkerboard
vertical existed. Its 228-assertion counts, hashes and “no checkerboard candidate” statements are
historical facts about that artifact, not claims about the current worktree and may not be inherited
by LW-2, LW-3 or LW-R1.

## Disposition

LW-1 implements one narrow, domain-neutral resolved-selection profile beneath the accepted
`LocalWorksets` lifecycle. Its execution code is backend-portable Julia expressed with
KernelAbstractions, Atomix, and Adapt. CPU and real Metal are the only tested witnesses. CUDA and
ROCm have not been tested or qualified; source portability is not a runtime, determinism, failure,
or performance claim.

There was no checkerboard candidate in this reviewed snapshot. A CorePotts proposal claims both old and new owners and
must win at both destinations. LW-1 admits one destination and one output per item, so that
conjunctive arbitration is not faithfully expressible. Direct CorePotts remains the oracle. No
production checkerboard, clock, RNG, Hamiltonian, acceptance, commit, settlement, checkpoint, or
publication code was changed.

## Frozen lifecycle and ownership

```julia
workplan = plan(work, topology; backend)
prepared = prepare(workplan, storage; workspace)
event = run!(prepared, submission)
wait(event)
```

| Owner | Source | Responsibility |
|---|---|---|
| Generic substrate | `lib/CorePotts/src/localworksets.jl` | lifecycle, schemas, topology evidence, central admission, preparation, leases, poison, receipt truth, inspection |
| Resolved lowering | `lib/CorePotts/src/execution/localworksets_resolved.jl` | declaration, routing, bindings, exact operation requirements, workspace, four KA kernels, determinism facts |
| KA provider | `lib/CorePotts/src/execution/localworksets_kernelabstractions.jl` | concrete KA backend, owner-task rule, implicit-order cumulative tail, one portable synchronize, qualified requirement profile |
| Metal extension | `ext/PottsToolkitMetalExt.jl` | no LocalWorksets code; unrelated existing PottsToolkit/CorePotts Metal support only |
| CorePotts | existing compiler/execution sources | physics, clocks, RNG, Hamiltonian folding/views, dual-owner claims, acceptance, commit, settlement, checkpoints |

The generic substrate contains no resolved scratch name, resolved family, backend implementation,
checkerboard term, or synchronization call. The resolved lowering contains no Metal, CUDA,
AMDGPU/ROCm, synchronization, scalar-fallback, or host-execution branch. The KA provider contains
no vendor name or native queue/event API. The Metal extension contains no `LocalWorksets` reference.

## KernelAbstractions ordering contract

KernelAbstractions 0.9's own documentation records removal of its event system because kernels are
implicitly ordered, and separately documents that launches are asynchronous until
`synchronize(backend)`. LW-1 uses those two contracts directly:

1. `run!` validates and issues clear, rank, identity, and publish kernels in Julia program order.
2. `sequence(a, b)` issues all four kernels for `a`, then all four for `b`; the second stage reads
   the first stage's output without an intermediate host wait.
3. `run!` returns a thin cumulative receipt and performs no synchronization.
4. `wait(event)` snapshots the submitted tail, calls exactly
   `KernelAbstractions.synchronize(backend)` once, then releases the entire completed lease prefix.
5. Waiting an older receipt after later submissions therefore drains the actual cumulative tail;
   waiting any already-covered receipt is idempotent.

LocalWorksets creates no scheduler, native event, stream, queue, command buffer, dependency graph,
or intermediate barrier. Submission and wait are restricted to the preparing task because KA does
not expose a portable cross-task recovery/drain operation. Abandoning that task with outstanding
work is outside the portable contract; no finalizer wait or provider-wide recovery is invented.

## Declaration-to-lowering trace

| Declaration fact | Validation/lowering consequence | Evidence |
|---|---|---|
| items and active count | exact bounded domain; inactive lanes are not read | inactive invalid-tail and bounds tests |
| logical reads | derive topology/storage properties; decorative reads reject | renamed binding and hostile-field tests |
| named output | determines the physical destination binding | renamed-port execution |
| destinations | validated routing copied/frozen during prepare | fingerprint and post-plan mutation tests |
| capacity | bounds candidates and must cover item count | exact/short capacity rejection |
| empty | clear publishes it for destinations with no contribution | empty pixel is `UInt32(0)` |
| rank | closed `Int32` min/max total order | negative/zero/end-point and device-domain tests |
| tie break | unique canonical `UInt32` identity with minimum order | equal ranks choose identity 10 over 50 |
| mask | false lane emits no rank, identity, or value | masked lower-rank fragment does not win |
| access/alias | exact role, backend, shape, stride, and disjointness checks | static/dynamic/workspace rejection tests |

No accepted field is decorative. Unsupported output families and operations reject during central
planning. External capability or lowering methods cannot self-authorize because central admission
accepts methods only from the trusted implementation boundary.

## Capability and determinism

| Witness | Qualified profile | Status |
|---|---|---|
| KernelAbstractions CPU | global `Int32` min/max, global `UInt32` min/store, `Int32` keys and `UInt32` values | compiled and tested |
| Metal 1.10.0, Julia 1.12.6, KA 0.9.42, Atomix 1.1.3, Adapt 4.7.0, Apple M1/Darwin 24/aarch64, active device 1 | same exact profile | compiled and real-device tested |
| CUDA, ROCm/AMDGPU | none | source intended to be portable; untested and unqualified |
| external replacement provider/capability/lowering methods | none | centrally rejected; an unreviewed conforming KA backend rejects during planning even when `functional == true` |

The inspected compiler identity includes Julia, KA, Atomix, Adapt, backend package
UUID/version/module/type, active device token, OS/architecture/machine/CPU, and word size, with
`qualification = :centrally_reviewed_environment`. `functional(backend)` proves only availability.
An exact central evidence row is required before capability validation, so an external backend that
defines only `functional == true` rejects during planning and receives no qualified determinism
facts. Exact-signature `invoke` bypasses more-specific external methods for both environment
construction and evidence membership. Exact invocation continues through the resolved validator and
central capability wrappers; a trusted method-origin wrapper seals compiler identity. The hostile
tests pirate every layer and still reject. Lowering evidence itself is routed through an exact
central trusted-origin wrapper before a `WorkPlan` can be returned.

KA 0.9 exposes an active backend device token but no portable physical-device identity for an
arbitrary array. The lane captures that token and rejects any change. The two reviewed rows are
exact single-device environments, so LW-1 makes no multi-device residency claim. A future
multi-device row is blocked until a hardware-neutral JuliaGPU interface can prove each array's
device; LocalWorksets will not restore a Metal-specific adapter to simulate one.

Reported determinism is similarly qualified: exact integer ordering supports same-run replay,
scheduling invariance, and same-backend bitwise selection for this lowering; workgroup-size and
cross-backend bitwise invariance are not claimed; RNG remains domain-owned. The final store is
race-free under the declaration because semantic identities are unique and only the item matching
both selected rank and identity publishes.

## Workspace, launches, and focused evidence

| Witness | Workspace | Topology transfer | Launches | Visibility waits |
|---|---:|---:|---:|---:|
| one resolved z-buffer stage | 32 bytes | 40 bytes | 4 | one final wait |
| two heterogeneous ordered stages | 64 bytes | 80 bytes | 8 | one final wait, zero intermediate waits |

CPU preparation copies host topology so later host mutation cannot change a prepared route. GPU
topology conversion uses Adapt during preparation. Workspace size, element types, shape, strides,
identity, alias rejection, one-element-short rejection, and warm reuse are tested. Warm `run!`
performs no algorithmic workspace allocation or topology transfer.

The snapshot's focused CPU suite passed 228 assertions across eleven testsets. Its corrected focused real-Metal
witness reports:

```text
(backend = :metal,
 lowering = :resolved_selection_min_Int32_UInt32_v1,
 launches = 4,
 workspace_bytes = 32,
 topology_transfer_bytes = 40,
 lease_capacity = 12,
 sequence_launches = 8,
 event_scope = :backend_implicit_order_tail,
 asynchronous_error_observation =
   (synchronization = :kernelabstractions_backend_contract,
    asynchronous_failures = :backend_defined))
```

A deliberate production-kernel rank-domain violation surfaces as a real Metal `KernelException`,
causes `wait` to fail, and poisons the preparation. This proves that failure for this witness is
observable at the portable synchronization boundary. It does not claim native command-buffer
inspection, event-selective attribution, or portable error-history semantics.

The corrected final evidence is:

| Evidence | Result |
|---|---|
| focused CPU semantics/source audit | exit 0; 228/228 assertions across eleven testsets |
| complete CorePotts CPU suite | exit 0; all scientific, lifecycle, relationship, capability, exact checkpoint/RNG continuation, rejection, and package-quality tests pass |
| qualified full real-Metal suite | exit 0; extension load orders, 37/37 native components, LW-1 witness/failure, direct checkerboard boundaries, descriptors, lifecycle, relationship, surface, continuation, and external-mechanism rejection pass |
| real-Metal failure witness | production kernel raises `KernelException` at wait; preparation becomes poisoned |

One invalid Julia 1.10 invocation failed in PrecompileTools before candidate loading because the
Metal environment requires Julia 1.12. The first correct Julia 1.12 invocation was sandbox-blocked
from creating a package-cache pidfile. The identical command with normal Julia-cache/GPU access
passed. These are retained as environment failures, not omitted or represented as candidate tests.

For a diagnostic 100-submission batch of the five-item z-buffer, each submission issued exactly
four kernels and the batch used exactly one final wait. Ten warm-measured samples gave:

| Backend | Median batch time | Submissions/s | Median host bytes/batch |
|---|---:|---:|---:|
| CPU | 0.002679166 s | 37,325.05 | 1,850,912 |
| real Metal | 0.0106173125 s | 9,418.58 | 2,816,288 |

These tiny-workload numbers measure validation, receipt, KA launch, and provider overhead; they are
diagnostic baselines, not a noninferiority result or a CPM throughput claim. They include the
exact-concrete-signature origin checks on every lowering/provider callback; those checks materially
increase host cost for this deliberately tiny five-item witness and must be consolidated or cached
before a performance-sensitive vertical can pass parity. The authoritative LW-0
direct checkerboard baseline remains unchanged: `1 + 9C` body launches, queue/settlement semantics
unchanged, and the retained coupled real-Metal fixture remained 65.64 MCS/s with the recorded LW-0
allocation and synchronization boundaries. No LocalWorksets checkerboard candidate existed in this
snapshot to compare without misrepresenting the admitted semantics.

## Checkerboard and future-backend ruling

- No checkerboard stage was selected for migration by this bounded LW-1 artifact.
- Hamiltonian authoring (`HamiltonianTerm`, `Volume`, `ContactEnergy`, `Elongation`, and registered
  external terms), `complete`, `mtkcompile`, proposal views, and canonical source-order folding stay
  unchanged and Core-owned.
- CorePotts RNG, proposal, acceptance, commit, reporting, settlement, and checkpoint semantics are
  not represented by LocalWorksets.
- A checkerboard candidate requires a separately approved bounded multi-emission amendment.
- A future CUDA/ROCm qualification should test this same vendor-neutral source. Backend-specific
  LocalWorksets code requires a demonstrated missing KA abstraction and a new architectural review.

## Committee ballot

The final bounded LW-1 ballots are recorded in [LW-1 implementation review](lw1-review.md). They did
not clear checkerboard migration or LW-R1. The later bounded amendment, actual vertical and
direct-parity evidence are reviewed independently; the old ballot cannot attach to their hashes.
