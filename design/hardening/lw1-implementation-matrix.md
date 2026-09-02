# LW-1 Implementation Matrix

Date: 2026-08-10

Status: LW-1 through exact-hash LW-R1 passed; owner subsequently selected standalone extraction
under the post-LW-R1 roadmap

Authority:

- [LocalWorksets V1 Normative Contract](../../spec/localworksets-v1.md)
- [LocalWorksets V1 Implementation and Review Gate](../../spec/localworksets-v1-implementation-gate.md)
- [LW-0 Corrected CorePotts Baseline](lw0-corrected-corepotts-baseline.md)
- [LW-1 Implementation Review](lw1-review.md)
- [LW-2 Bounded Conjunctive Amendment](lw2-bounded-conjunctive-amendment.md)
- [Post-LW-R1 Extraction and Adoption Roadmap](../../spec/localworksets-post-lwr1-roadmap.md)

## Purpose and admission boundary

This matrix is the executable traceability contract for LW-1 through LW-R1. It does not reopen the
accepted architecture or public language. LW-1 passed its exact-candidate review. The bounded LW-2
amendment authorized implementation of only the dual-key conjunctive claim block. Its vertical and
LW-3 evidence passed executably, and the fresh exact-hash committee cleared LW-R1. The owner later
selected standalone extraction as the LW-4 disposition; promotion and expansion remain governed by
the successor roadmap and its reviews.

The implementation is an internal-first `CorePotts.LocalWorksets` module. It is not a standalone
package, is not re-exported by PottsToolkit, adds no dependency, and does not establish a second
scientific engine. Its only executable LW-1 profile is a narrow, domain-neutral resolved-selection
lowering. LW-2 may add only the separately specified bounded two-key item-result resolved lowering
and private CorePotts claim-block vertical. The frozen direct implementation remains the LW-0
oracle.

The only admitted lifecycle is:

```julia
workplan = plan(work, topology; backend)
prepared = prepare(workplan, storage; workspace)
event = run!(prepared, submission)
wait(event)
```

`WorkPlan` owns topology identity and epoch. `PreparedWork` may validate and attach the plan to a
concrete device topology representation, storage, workspace, and one provider lane; it may not
accept a second topology or silently re-plan.

## Frozen implementation choices

| Question | LW-1 decision | Enforcement |
|---|---|---|
| Namespace | `CorePotts.LocalWorksets`; its exact V1 names are public within that internal-first namespace, with no PottsToolkit re-export | LW1-T01 |
| Implementation footprint | one generic substrate, one isolated resolved lowering, and one hardware-neutral KernelAbstractions provider; no LocalWorksets backend extension | LW1-T01, LW1-T25 |
| Public lifecycle | `localwork -> plan(work, topology; backend) -> prepare(workplan, storage; workspace) -> run! -> wait` | LW1-T02–T08 |
| Planning result | `WorkPlan` is mandatory because the frozen lifecycle names it | LW1-T04 |
| Ordered composition | `sequence(a, b, ...)` returns a `LocalWork`; private stage/lowering nodes are not public | LW1-T03, LW1-T19 |
| Output support | only `resolved` is executable in LW-1; `independent` and `combined` remain reserved contract vocabulary, not partial implementations | LW1-T18, LW1-T24 |
| Resolution | explicit empty result, total rank, canonical semantic tie break; the central compiler owns backend admission | LW1-T18–T19 |
| Active work | submission-level active count is applied before gather/evaluation/emission | LW1-T16 |
| Output masking | `masked(value, flag)` is eager output-lane suppression; false means no emission | LW1-T17 |
| Storage | exact static binding plus only the bounded storage-slot machinery needed for rejection/lifetime conformance | LW1-T06, LW1-T09–T12 |
| Submission | one exact named schema of concrete value/storage slots; source order is irrelevant | LW1-T08–T10 |
| Execution | one serial host submitter, one prepared provider lane, same-lane ordered reentrancy | LW1-T13–T15 |
| Ordering | KernelAbstractions/provider implicit ordering; no intermediate waits or manufactured dependency events | LW1-T03, LW1-T14, LW2-C04 |
| Event | cumulative KernelAbstractions backend-tail receipt, never a scheduler dependency; submission and wait are same-owner-task | LW1-T14–T15 |
| Workspace | allocated or validated in `prepare`; bounded formula exposed; warm `run!` never grows it | LW1-T07, LW1-T20, LW3-Q05 |
| Leases | queued arguments and resources remain retained in a fixed-capacity table without finalizer waits; exhaustion rejects before launch and reclamation follows provider completion/drain | LW1-T15, LW1-T21 |
| Failure | prelaunch rejection does not poison; an observable host/provider failure after a launch poisons; expected Core scientific status does not; no generic `reset!` | LW1-T22, LW2-C08 |
| Inspection | stable fact-bearing `inspect` result plus concise `show`; no proof/certificate/compiler nouns | LW1-T23 |
| Extension execution | declarations are data; no opaque executor, host callback, self-issued backend capability, or host fallback | LW1-T19, LW1-T25 |
| Selected vertical | none in LW-1; LW-2 is limited to the amended four-launch dual-owner conjunctive claim block | strengthened review and bounded amendment |
| Core ownership | bulk clear, color-order RNG, source/destination bank choice, state copy, lifecycle index, bank publication, settlement, commit boundary, checkpoints, and failure reporting | LW2-C02–C12 |
| Hamiltonians | descriptor evaluation remains beneath the unchanged authoring/compiler boundary; canonical source-order term folding is never a LocalWorksets reduction | LW2-C03, LW3-Q01 |
| Capability identity | scientific and RNG identities remain unchanged; a private runtime-bound execution-lowering identity distinguishes direct from LocalWorksets checkpoints and capability evidence | LW2-C10, LW3-Q02 |
| Default before LW-R1 | frozen direct path; LocalWorksets candidate reachable only through private conformance/benchmark selection | LW2-C01, LW3-Q01 |

The capability-identity decision deliberately separates scientific equivalence from mechanism
identity. A private `ExecutionLowering{:direct}` or `ExecutionLowering{:localworksets_v1}` value is
fixed when the runtime/workspace is constructed, retained in its checkpoint, and supplied as the
expected lowering to restore. Public construction and restore continue selecting `:direct` before
LW-R1; only private conformance/benchmark plumbing may select `:localworksets_v1`. Both directions
of cross-lowering restore reject. Each lowering must continue its own checkpoint exactly, while
parity tests prove identical accepted trajectories from the same initial scientific state and RNG
address. The direct capability status, maturity, evidence, and fingerprint remain unchanged.

The private candidate uses CorePotts' existing experimental admission rather than bypassing it:

- the LW-1/LW-2 execution candidate is `Experimental/Functional` with a candidate-specific
  conformance evidence identity and is admitted only by the Core-owned private conformance selector
  using `experimental = true`;
- the exact LW-3 replay candidate becomes `Experimental/ReplayQualified` only with its own recorded
  checkpoint/replay evidence identity; its private checkpoint/restore path uses the existing
  experimental replay predicate and the expected `ExecutionLowering{:localworksets_v1}`;
- ordinary public capability checks never pass `experimental = true`, public construction/restore
  select direct execution, and no external declaration can obtain the private selector; and
- neither candidate reuses LW-0 evidence or reports `Supported` before LW-R1.

Thus every candidate operation still passes the normal minimum-maturity, replay-class, environment,
and exact-mechanism checks. There is no test-only bypass of fail-closed admission.

## Required public types

The types below are public only as `CorePotts.LocalWorksets.<name>` during the internal-first gate.
Supporting implementation nodes remain private.

| Type | Minimum responsibility | Prohibited responsibility | Required tests |
|---|---|---|---|
| `LocalWork` | immutable declaration of item domain, reads, local operation, named resolved output, optional active selection, or ordered composition | topology ownership, concrete arrays, backend execution, clock/RNG/physics | LW1-T02, T03, T16–T19, T25; LW2-C01 |
| `WorkPlan` | immutable topology identity/epoch/fingerprint, derived bounds, admitted backend/type/operation/address-space facts, lowering identity, symbolic workspace and launch plan | concrete storage identity, submission values, workspace ownership, lane | LW1-T04–T05, T19–T20, T23; LW2-C01 |
| `PreparedWork` | concrete provider/device/context/lane, device topology, exact static bindings and slot schemas, workspace, lease/serial/poison state | new topology, scientific commit, scheduler, arbitrary dynamic arrays | LW1-T06–T13, T20–T23; LW2-C04–C09 |
| `WorkEvent` | thin receipt retaining the preparation/lease and reporting provider lane-tail wait scope | portable dependency event, readiness promise, cancellation, scheduler | LW1-T14–T15, T21; LW2-C04, C07 |

### Required supporting declaration values

These are small concrete values, not additional lifecycle nouns.

| Value | Responsibility | Required tests |
|---|---|---|
| value-slot declaration | exact name, concrete type, optional inclusive bounds | LW1-T08–T10 |
| storage-slot declaration | element type, rank, shape, layout, address space, active KA backend/device context, access and alias role; KA 0.9 provides no portable per-array physical-device identity | LW1-T09, T11–T12, T21 |
| resolved-output declaration | bounded emissions, key/value/candidate layouts, empty result, total ranking and canonical tie break | LW1-T18–T19; LW2-C03 |
| masked emission | eagerly constructed payload plus fixed bounded Boolean lane mask | LW1-T17 |
| inspection record | immutable facts for declarations, plans, preparations, and events, with every determinism guarantee fully qualified | LW1-T23; LW3-Q04–Q06 |

## Required functions

| Function | Exact LW-1 behavior | Required tests |
|---|---|---|
| `localwork` | constructs a declaration only; operation must be a concrete, centrally recognized device-compilable value | LW1-T02, T16, T18–T19, T25 |
| `sequence` | constructs ordered `LocalWork`; validates compatible item/topology/output visibility; lowers stages to one lane in program order | LW1-T03, T19; LW2-C01, C04 |
| `plan` | accepts exactly `(work, topology; backend)`; performs central validation/lowering and captures topology evidence without device allocation, transfer, or concrete storage | LW1-T04–T05, T18–T20, T25 |
| `prepare` | accepts `(workplan, storage; workspace, submission = (;))`; fixes device/context/lane through the centrally admitted provider adapter, device topology, bindings and bounded workspace | LW1-T06–T07, T11–T13, T20–T21 |
| `run!` | validates one exact named submission before launch, serially appends all launches, returns promptly with `WorkEvent`, and never grows workspace | LW1-T08–T15, T20–T22; LW2-C04–C09 |
| `Base.wait` | `Base.wait(::WorkEvent)` delegates to the qualified provider wait/drain scope and guarantees host visibility; introduces no second scheduler or shadow generic | LW1-T14–T15, T21–T22; LW2-C04, C07 |
| `inspect` | reports the normative evidence without synchronizing, mutating, or claiming unavailable guarantees | LW1-T23; LW3-Q04–Q06 |
| `value_slot` | declares a concrete scalar/isbits type and optional bounds; never captures the current value in `WorkPlan` | LW1-T08–T10; LW2-C05 |
| `storage_slot` | declares exact storage facts from a template; a run-time identity is accepted only after full validation | LW1-T09, T11–T12, T21 |
| `resolved` | declares the only executable LW-1 output profile; requires explicit empty result, total rank, canonical tie break and bounded capacity | LW1-T18–T19; LW2-C03 |
| `masked` | suppresses already-safe, eagerly evaluated bounded lanes; false emits nothing | LW1-T17 |
| `Base.show` | type-constrained methods for the four lifecycle types and private inspection-record type give concise non-synchronizing lifecycle/lowering summaries; no method on `Any` is added | LW1-T23 |

No `prepare(work, backend; ...)`, `compile_workset`, `bind`, `enqueue!`, `Policy`, `Seq`,
`Certificate`, reset, cancellation, readiness, or opaque execution hook is admitted.

## Private implementation components

Private components are implementation obligations because the public values may not perform their
own execution or validation.

| Private component | Responsibility | Direct evidence |
|---|---|---|
| declaration normalizer | canonical named-port and schema order independent of NamedTuple source order | LW1-T02, T08 |
| topology witness | stable identity, epoch/fingerprint, item/destination bounds and checkerboard color capacity | LW1-T04–T05; LW2-C01 |
| central resolved lowering | recognizes only the admitted resolved-selection declaration; owns exact routing, bindings, capability, workspace, four kernels and lowering identity | LW1-T18–T20, T25 |
| binding validator | exact name/type/bounds/provider/device/context/shape/layout/access/alias checks before launch | LW1-T08–T13 |
| provider/lane adapter | centrally selected serial append ownership, retained KernelAbstractions backend, qualified preparation/submission accounting, one portable tail synchronization, and backend-defined error-observation facts; external methods cannot authorize operations or execute stages | LW1-T13–T15, T19, T22 |
| bounded lease table | fixed inspected capacity from prepared workspace; retains queued resources, rejects the first over-capacity submission before launch, and reuses slots after cumulative drain without growth | LW1-T15, T20–T21; LW2-C07 |
| poison controller | records whether any launch was appended and rejects unsafe reuse | LW1-T22; LW2-C08 |
| inspection builder | exposes facts from declaration, plan, preparation and receipt without invention | LW1-T23 |
| Core checkerboard wrapper | not present or authorized in LW-1 | strengthened review ruling |

The inspected lease capacity is fixed by prepared workspace. Tests fill the exact declared
capacity, prove that the next submission rejects before launch without poison, perform a cumulative
drain, and reuse the same slots with unchanged identities and bytes. No unbounded queueing is
claimed.

### Hardware-neutral KernelAbstractions provider and Metal evidence

CorePotts owns one generic provider implementation for `KernelAbstractions.Backend`. It retains the
concrete backend and preparing task, issues each centrally lowered kernel in Julia program order,
and uses exactly one `KernelAbstractions.synchronize(backend)` when a cumulative receipt is waited.
KernelAbstractions 0.9 implicit ordering supplies stage visibility; LocalWorksets creates no native
queue, stream, event, dependency edge, command-buffer policy, or asynchronous runtime.

The provider may identify a backend and report the portable synchronization contract. It may not
provide stage execution, select an output algorithm, authorize its own operation profile, call an
opaque host fallback, or inspect backend-native queues. The LocalWorksets source and its algorithm
lowering contain no Metal, CUDA, AMDGPU/ROCm, queue, or native-event branch, and
`ext/PottsToolkitMetalExt.jl` contains no LocalWorksets code.

`KernelAbstractions.functional` is availability, never capability evidence. Central admission
requires an exact reviewed environment row containing Julia, KA, Atomix, Adapt, backend package
UUID/version/module/type, active device token, OS/architecture/machine/CPU, and word size. Only the
current CPU row and real-Metal row exist. A conforming but unreviewed KA backend therefore rejects
during `plan` even if it reports `functional == true`; no qualified determinism facts are built.
Exact-signature `invoke` seals both environment construction and evidence membership against
external specializations of the private helpers. The resolved lowering also invokes the exact
Core-owned validator and central capability wrappers; compiler identity passes through a trusted
method-origin wrapper invoked at its exact signature. Plan construction likewise routes lowering
evidence through an exact central wrapper that rejects untrusted specializations.

The exact qualified environment is Julia 1.12.6, KernelAbstractions 0.9.42, Atomix 1.1.3 and Metal
1.10.0. This gate qualifies only that real-Metal witness and the CPU witness. The source is intended
to compile for other JuliaGPU KernelAbstractions backends, but CUDA and ROCm are untested and no
support, performance, failure-observation, or determinism qualification is claimed for them.
Operation admission records that compilation and backend evidence are required. A real
production-kernel rank-domain violation on Metal must fail the single portable wait and poison the
preparation. KernelAbstractions does not expose a portable cross-task recovery operation, so an owner
task must not be abandoned with outstanding work; LocalWorksets does not invent a provider-wide
drain or native recovery path.

KA 0.9 exposes the active backend device but no portable physical-device identity for an arbitrary
array. The provider freezes the active device token and rejects a changed token before launch. LW-1
qualification is deliberately restricted to the exact single-device Apple M1 witness and its CPU
row. It does not claim general multi-device array-residency validation. Any future multi-device
qualification is blocked until KA or another reviewed JuliaGPU-wide interface can identify each
array's physical device without a vendor extension.

## Test inventory and exact assertions

### LW-1 substrate tests

Repository location: `lib/CorePotts/test/test_localworksets.jl`, included explicitly by
`lib/CorePotts/test/runtests.jl`.

| ID | Test and pass condition |
|---|---|
| LW1-T01 | Loading CorePotts exposes exactly the module self-binding plus `LocalWork`, `WorkPlan`, `PreparedWork`, `WorkEvent`, `localwork`, `plan`, `prepare`, `run!`, `sequence`, `inspect`, `value_slot`, `storage_slot`, `resolved`, and `masked` as public in `CorePotts.LocalWorksets`; it adds only type-constrained `Base.wait`/`Base.show` methods. `Base.ispublic`, applicability, exact root/module inventories, non-public compiler nodes, and the absence of raw lifecycle constructors are tested. `LocalWorksets.inspect` is distinct from the existing `PottsToolkit.inspect`; PottsToolkit re-exports none of the new names. Dependencies remain unchanged with no MTK/SciMLOperators dependency in CorePotts. |
| LW1-T02 | `localwork` produces an immutable declaration with canonical item/read/output facts, normalizes semantically identical read/output named tuples independent of source order, and contains no backend, topology, array identity, submission value, lane, or domain clock/RNG object. |
| LW1-T03 | `sequence(a,b,...)` is a `LocalWork`; inspection preserves program order and visibility edges; one CPU run records ordered launches and zero intermediate waits. Incompatible output visibility rejects in planning; cross-lane use rejects after preparation. |
| LW1-T04 | `plan(work, topology; backend)` returns an immutable plan recording identity, epoch/fingerprint, bounds, admitted lowering and symbolic workspace. Reusing a plan with same topology and same schema/types/bounds does not re-plan or specialize. |
| LW1-T05 | changed epoch/fingerprint, item/destination bounds, route, or conflict footprint rejects before preparation. Preparation freezes the validated device topology. Later epoch/identity changes reject before run; unversioned external host-route mutation is a caller violation but cannot alter the frozen prepared route and rejects on any later preparation. |
| LW1-T06 | both `prepare(workplan, storage; workspace)` and the explicit `submission=(;)` form prepare an empty schema. Preparation fixes exact static array identities, aliases, concrete provider device/context, a centrally selected retained lane, device topology and workspace; it accepts no topology or lane keyword. |
| LW1-T07 | exact and one-element-short workspace tests match the inspected typed/aligned symbolic formula; preparation performs all required allocation/transfer and warm execution changes neither workspace identity nor bytes. |
| LW1-T08 | named value bindings accept different NamedTuple source order but use canonical schema order; missing, extra, or renamed keys reject before launch. |
| LW1-T09 | wrong value type, out-of-bounds value, and storage-slot element/rank/shape/layout/access mismatch reject before launch without poison. Same-typed in-bounds values do not re-plan or recompile. |
| LW1-T10 | the domain-neutral active-count slot is exactly `Int32` with declared bounds contained by planned item capacity; boundary values pass, wider prepared bounds reject, and no MCS/RNG/bank/color/status slot exists in LW-1. |
| LW1-T11 | illegal static alias, illegal submission alias, and foreign backend storage reject before launch. A changed active KA device context rejects before launch. The exact LW-1 rows are single-device; multi-device qualification is blocked because KA 0.9 cannot portably prove arbitrary array residency. The one allowed pointwise alias requires an explicit proven identical map. |
| LW1-T12 | storage slots carry exact template facts; an undeclared dynamic array rejects. Alternating distinct same-schema storage identities are accepted and leased with unchanged plan and lowering identity. Compiler-cache qualification is deferred to a later performance gate and is not claimed here. |
| LW1-T13 | same host task may queue same-lane submissions; simultaneous calls, task migration, cross-lane calls and changes to the frozen active KA device reject before launch. The append guard is released after encoding, not device completion. |
| LW1-T14 | `run!` returns a receipt whose inspection says provider, lane, cumulative/nonselective tail scope and transfer law. `wait` makes output host-visible. No `isready`, dependency chaining, cancellation, or intermediate sequence wait exists. |
| LW1-T15 | Receipt submission and wait are same-owner-task and retain the prepared backend plus leased resources. Waiting any cumulative receipt snapshots and reclaims the entire submitted prefix completed by its backend-tail synchronization. Wrong-task wait rejects truthfully. Dropping a receipt does not cancel work while its `PreparedWork` remains live; abandoning an owner task with outstanding work is outside the portable contract and no hidden recovery wait is invented. |
| LW1-T16 | active-count selection happens before gather, destination calculation, operation and emission: deliberately invalid inactive entries are never read, while the same entries fail when made active. Capacity overflow rejects before launch. |
| LW1-T17 | `masked(unsafe_payload(), false)` demonstrates Julia eagerness and therefore throws before masking; safe payload with false mask emits no candidate, not identity/empty; true lanes emit in fixed semantic slots. |
| LW1-T18 | resolved output rejects absent empty result, non-total rank, arrival-order tie break, unbounded emission, wrong key/value layout, or capacity. Empty keys publish the declared empty result and canonical semantic ties are launch-order independent. |
| LW1-T19 | a concrete external resolution declaration may describe semantics but cannot authorize backend execution, supply a launch callback, bypass the recognized lowering registry, or compose an unsupported capability; all reject before launch. |
| LW1-T20 | CPU and real-Metal preparation inspect the exact algorithmic workspace formula; after warm-up, repeated `run!` has zero algorithmic workspace/pool growth, topology transfer, or host fallback. Provider launch buffers/pools are counted separately. |
| LW1-T21 | `PreparedWork` retains queued submission-bound resources without finalizer waits. Fill the exact lease capacity, prove the next call rejects prelaunch without poison, wait the oldest cumulative receipt, prove the whole completed prefix is drained, then reuse identical slots/bytes. No claim is made for dropped preparation or owner-task-exit recovery because KernelAbstractions exposes no portable cross-task drain. |
| LW1-T22 | every prelaunch validation failure leaves preparation usable and unpoisoned. A production-reachable provider/device exception after append fails wait and poisons on qualified real Metal. Expected Core scientific status remains Core-owned. Failure observation is explicitly backend-defined; no native command-buffer inspection or broader asynchronous-error-history claim is made. |
| LW1-T23 | immutable `inspect` records and non-synchronizing `Base.show` expose topology, bindings/slots, aliases, provider/device/lane, lowering/fusion, launch count, workspace/transfers, lease/record capacity, reentrancy, event/error-observation scope, allocation class and poison. Every one of the eight determinism dimensions carries backend, element type, operation, address space, compiler and lowering-identity qualifiers. |
| LW1-T24 | `independent` and `combined` are not constructible executable profiles in LW-1. Bare floating `+` cannot enter a lowering through any fallback. The contract vocabulary remains reserved for later bounded expansion. |
| LW1-T25 | source/API audit plus external concrete operation/backend/topology/workspace methods—including `functional=true` and more-specific environment, validator, type-qualified capability, lowering-evidence, topology identity/epoch/fingerprint, workspace validation/preparation/execution, and reviewed-CPU compiler-identity specializations—prove there is no opaque host callback/executor, false topology freshness, runtime domain-name branch, arbitrary launch hook, unbounded record allocation, host fallback, solver/clock/RNG ownership, or external self-authorization path. Every lowering/provider callback is selected against its exact concrete argument signature and must originate in central code. |

### LW-2 checkerboard vertical tests — authorized only by the bounded amendment

The strengthened review established that one proposal may claim both old and new owners and must
win both. The owner-approved
[bounded conjunctive-resolution amendment](lw2-bounded-conjunctive-amendment.md) now authorizes
implementation of exactly the existing clear/rank/identity/select block. It adds a checked
two-key, item-result resolved profile; it does not authorize approximation through independent
keyed winners or migration of candidate generation, Hamiltonian evaluation, acceptance, commit,
report, RNG, lifecycle, publication, settlement, or checkpoints.

No checkerboard orchestration was authorized by LW-1. The shared domain-neutral one-key
resolved-selection assertions live in
`test/backend_conformance/localworksets_execution.jl`; the real-Metal runner includes that file
directly.

The amendment's LW2-C01 through LW2-C15 rows supersede the historical C01-C12 questions below where
they conflict. Those exact amended rows are normative and must all pass before LW-2 is recorded as
complete. The historical table remains only for traceability.

| ID | Test and pass condition |
|---|---|
| LW2-C01 | Inspection of the candidate plan shows exactly the existing nine per-color stages in order. The one bulk-clear launch remains Core-owned outside the sequence, preserving the baseline `1 + 9C` checkerboard-body formula. No second checkerboard sequence is migrated. |
| LW2-C02 | Same candidate/source/owner/priority/semantic-ID/disposition fixtures prove evaluation and acceptance-status occur before claim arbitration, and claim priority precedes canonical identity selection. |
| LW2-C03 | The resolved declaration has bounded candidate capacity, explicit empty disposition, total priority rank and semantic-ID tie break. Hamiltonian descriptor calls and source-order term folding are byte-for-byte the existing Core path, underneath authoring. |
| LW2-C04 | Each per-color `run!` appends nine launches on the existing provider lane with no intermediate wait/event; the immutable scalar color argument survives preallocated host color-order reuse. CPU and Metal launch traces equal the direct trace. |
| LW2-C05 | Core's wrapper supplies exact named values for `mcs`, `rng_address`, source/destination bank role, active count, attempt/color ordinal and status epoch. Varying values within one schema changes neither plan nor compiled specialization. |
| LW2-C06 | Active and destination bank alternation, same-lane shared-workspace reuse, and failure-atomic double-buffer publication match direct execution; no LocalWorksets code chooses scientific banks or publishes them. |
| LW2-C07 | Queue at least ten complete MCSs before one existing Core settlement. Events may be dropped; one settlement drains the same lane and produces the same submitted/drained/committed/materialized counters and one settlement count. |
| LW2-C08 | A deterministic expected scientific failure with later MCS work already encoded yields the same sticky Core status, logical commit cut, inactive destination state and recovery boundary as direct execution while the substrate remains unpoisoned. A separate observable host/provider failure after append poisons without publishing scientific state. |
| LW2-C09 | Every current Core capability rejection remains: unreviewed external backend/mechanism, invalid attempts, unsupported type/operation/address space, and lifecycle/relationship/surface exclusions. Candidate selection also rejects/falls back to the direct oracle whenever `accepted_count > 0` on CPU or Metal; no host accepted-copy hook enters the LocalWorksets sequence. |
| LW2-C10 | RNG contract, lowering identity, semantic addresses, randomized preallocated color order and immutable per-launch color match direct execution. Private runtime construction and restore bind `ExecutionLowering`; both cross-restore directions reject. Direct capability status/maturity/evidence/fingerprint remain exact. The LW-1/LW-2 candidate is Experimental/Functional and the exact LW-3 candidate is Experimental/ReplayQualified, each with distinct candidate evidence, existing experimental admission, and no LW-0 evidence or public selector. |
| LW2-C11 | Core-owned state copy, lifecycle indexing, accepted-copy host stage on the direct qualified path, bank publication, settlement, tracker publication, lifecycle receipt and public commit behavior remain outside LocalWorksets and pass the full existing suites. Unsupported profiles stay on the frozen direct path until separately migrated. |
| LW2-C12 | The candidate is selectable only through private conformance/benchmark plumbing before LW-R1; public algorithms and Hamiltonian authoring are unchanged. The frozen direct oracle cannot be deleted or weakened before review. |

### LW-3 parity qualification

CPU evidence driver: `benchmark/src/lw3_localworksets_parity.jl`.

Real-Metal evidence driver: `benchmark/backends/metal/lw3_localworksets_parity.jl`, invoked from the
qualified Metal environment. Repository evidence is recorded in
`design/hardening/lw3-localworksets-parity.md` with raw command, environment, samples and variance.

| ID | Qualification and pass condition |
|---|---|
| LW3-Q01 | Same compiled system, initial state, seed/replica/repeat, color order and parameters produce exact scientific state, accepted/rejected/null/constraint/energy counters, trackers and lifecycle state for direct and candidate paths. Candidate parity explicitly covers `Volume`, `ContactEnergy`, `Elongation`, registered external Hamiltonians where backend-admitted, current before/after proposal views, and adversarial multi-term canonical source-order folding on CPU and qualified Metal. |
| LW3-Q02 | Accepted trajectory and semantic RNG addresses are identical. Direct and candidate checkpoints each continue exactly; RNG mismatch plus direct-to-candidate and candidate-to-direct restore reject. Tests prove the private experimental path still enforces minimum Functional/ReplayQualified maturity, replay class, environment, evidence and mechanism identity. Exact status/maturity/evidence/fingerprint assertions prove no `Supported` promotion or LW-0 evidence reuse and distinguish scientific equivalence from mechanism identity. |
| LW3-Q03 | Ten-plus queued MCS and deterministic early-failure witnesses have identical sticky failure, logical commit cut, publication, bank, and submitted/drained/committed/materialized counters. |
| LW3-Q04 | Per MCS the candidate preserves the direct `1 + 9C` checkerboard-body launch sequence/count, adds no intermediate wait, preserves queued settlement count, and reports any provider validation/event-only delta separately. |
| LW3-Q05 | Inspected algorithmic workspace/pool formula and bytes are exact; after preparation/warm-up, `run!` causes zero algorithmic growth, topology transfer, or fallback. Shared reuse is proven across queued colors/MCSs. Backend launch machinery is reported separately and never mislabeled as algorithmic workspace. |
| LW3-Q06 | Host allocation is compared as direct launches plus an equivalent lease/event receipt versus LocalWorksets. Algorithmic allocation, provider launch buffers/pools, wait, transfer and receipt/lease counters are separate. Any non-provider delta is identified by type/site and blocks unexplained acceptance. |
| LW3-Q07 | Same declaration schema, concrete types and bounds with changing scalar values and alternating distinct same-schema storage identities produces no additional plan, lowering, KernelAbstractions specialization or Metal compiler-cache entry after warm-up. |
| LW3-Q08 | Predeclared noninferiority test uses at least 10 warm batches and 50 randomized interleaved paired batches, each containing 10 queued MCSs followed by one settlement. The one-sided 95% paired-bootstrap upper confidence bound for candidate/direct median time must be at most `1.05`. Raw paired data, dispersion, synchronization boundaries and bootstrap seed are recorded; otherwise only a causal bounded regression explicitly accepted by the owner may pass. |
| LW3-Q09 | Full CorePotts CPU suite, authoritative root suite and qualified real-Metal suite pass without capability promotion. Every LW1 rejection plus stale topology, active-selection, eager-mask, abandoned event and external-mutation-contract witness is executable. |
| LW3-Q10 | `Adapt` conversion and real device compilation contain only concrete, isbits kernel arguments and recognized lowering nodes. No dynamic dispatch, scalar indexing, opaque closure, host execution, hidden synchronization, or allocation appears in the device path. |

## Contract-to-test closure

| Contract | Executable closure |
|---|---|
| LW-A1 lane/storage | LW1-T06, T09–T13; LW2-C04–C07 |
| LW-A2 event truth | LW1-T14–T15, T21 |
| LW-A3 implicit ordering | LW1-T03, T14; LW2-C04 |
| LW-A4 workspace/allocation | LW1-T07, T20; LW3-Q05–Q06 |
| LW-A5 routing/topology | LW1-T04–T05, T18–T19; LW2-C01–C03 |
| LW-A6 named submission | LW1-T08–T10; LW2-C05 |
| LW-A7 alias/numerics | LW1-T11, T24 |
| LW-A8 central lowering/Core boundary | LW1-T19, T25; LW2-C03, C09–C12 |
| LW-A9 inspection/rejection | LW1-T05, T09–T13, T18–T20, T23; LW3-Q09 |
| LW-A10 publication/poison | LW1-T22; LW2-C06, C08; LW3-Q03 |
| LW-A11 leases/mutation | LW1-T15, T21; LW3-Q09 |
| LW-A12 selection/masking | LW1-T16–T17 |
| LW-A13 determinism vector | LW1-T18, T23; LW3-Q01–Q03, Q08 |
| LW-A14 optional SciML boundary | LW1-T01, T12; no wrapper or dependency implemented in this gate |

## Strengthened semantic-portability review

Owner amendment date: 2026-08-10

Before any checkerboard integration or LW-2 work, the exact LW-1 candidate receives a hostile
source-level review for semantic overfitting. Passing one keyed-winner fixture or presenting generic
names is insufficient.

The generic substrate may own only the four lifecycle values, frozen lifecycle, named declarations
and bindings, topology freshness, backend/device/context validation, workspace, leases, truthful
events, poison, central admission, inspection, and qualified determinism evidence. Concrete
keyed-winner topology witnesses, binding derivation, capability qualification, scratch layout,
kernels, and lowering identity must live in a separately included centrally admitted lowering.
CorePotts clocks, RNG, MCS/color, Hamiltonians, banks, proposals, acceptance, claims, commit,
publication, settlement, and checkpoints do not enter either the generic substrate or its tests.

The reviewer must produce these exact tables and evidence:

1. A declaration-to-lowering trace for items, reads, output-port names, active selection,
   destinations, key/value/rank/identity types, capacity, empty result, total rank, canonical tie
   break, mask, storage access, and alias declarations. Every accepted field must affect validation,
   planning evidence, binding/lowering, execution, or inspection. Otherwise it is P1 unless explicitly
   reserved and rejected as non-executable.
2. A generic-substrate versus concrete-lowering ownership table with exact file/line evidence.
3. Logical-to-physical binding evidence proving declared read names and output-port names determine
   storage. No fixed global `keys/values/priorities/semantic_ids/output/winner_*` storage schema is
   admitted. Scratch arrays are prepared workspace, not scientific storage.
4. One-source-of-truth evidence proving the resolved declaration alone owns empty, capacity,
   key/value layout, total rank, and canonical tie break. Topology may own routing/conflict facts but
   may not duplicate output semantics. Disagreement rejects.
5. Exact workspace evidence mapping every formula byte to used rank/identity scratch, including
   element types and alignment, exact capacity, one element short, identities, warm reuse, no hidden
   growth, and CPU/real-Metal parity.
6. Capability evidence qualified by backend × key type × rank type × identity type × value type ×
   atomic operation × address space. Sentinel validation must cover zero and signed/negative ranks;
   zero may be a max sentinel only when the declared domain proves it is a lower bound.
7. Independent sequence evidence showing distinct admitted stages retain their own operation, reads,
   outputs and order, use one lane with provider implicit ordering, add no intermediate waits, and
   reject incompatible topology/binding/visibility. Repeating one fixed declaration is insufficient.
8. A complete non-CPM deterministic z-buffer witness on CPU and real Metal: fragments map to pixel
   destinations, explicitly ordered depth selects, primitive identity breaks ties canonically,
   winning color is published, masked fragments emit nothing, and empty pixels receive the declared
   empty color. It must exercise a rank/value configuration that falsifies CPM-max assumptions.
9. Hostile source checks for hard-coded logical names/types, decorative fields, magic functions such
   as `identity`, topology-owned output semantics, scratch outside workspace, unused workspace,
   domain branches, opaque callbacks, host fallback, external launch hooks, and unqualified
   determinism claims.
10. An explicit ruling on which checkerboard stages the admitted LW-1 declarations can honestly
    express. If only resolved arbitration is admitted, any later vertical is narrowed to claim
    arbitration; evaluation, Hamiltonians, acceptance, commit, and reporting remain direct CorePotts.

The implementation must be backend-portable Julia/KernelAbstractions, Adapt, and Atomix code. One
generic KernelAbstractions provider owns backend identity and the sole portable wait; LocalWorksets
has no backend-specific extension. GPU qualification in this gate is real Metal only; absence of
CUDA/ROCm tests is not a claim that those backends are qualified. Backend-defined asynchronous
failure behavior is evidence to record, not a native API for LocalWorksets to reproduce.

Review severities are: P0 for incorrect execution, unsafe backend behavior, or false determinism/
visibility; P1 for a decorative generic field, concrete-mechanism leakage, false workspace evidence,
or an advertised but inexpressible sequence; P2 for diagnostics, readability, inspection, or file
organization; and deferred only for genuinely later independent/combined families. Any unresolved
P0/P1 blocks checkerboard integration, LW-2, and LW-R1. Review may not weaken admission, Metal error
observation, performance, or direct-oracle rules to pass.

## Planned repository changes

The implementation candidate may touch only the following categories without a matrix amendment:

- `lib/CorePotts/src/localworksets.jl`: nested module, four public lifecycle types, exact public
  functions, validation,
  binding, lane/event/lease/poison and inspection;
- `lib/CorePotts/src/execution/localworksets_resolved.jl`: private resolved declaration, topology
  witness, capability, workspace, lowering and kernels;
- `lib/CorePotts/src/execution/localworksets_kernelabstractions.jl`: hardware-neutral provider,
  same-owner-task rule, implicit-order tail facts, single portable synchronize, and exact operation
  requirement profile;
- `lib/CorePotts/src/CorePotts.jl`: includes and one internal-first public namespace declaration;
- `lib/CorePotts/test/test_api_boundary.jl`: exact root public-name inventory update;
- `ext/PottsToolkitMetalExt.jl`: no LocalWorksets implementation; its pre-existing unrelated
  PottsToolkit/CorePotts Metal capability code is preserved;
- `lib/CorePotts/test/test_localworksets.jl`, plus explicit runner includes;
- `test/backend_conformance/localworksets_execution.jl`, included by qualified backend runners but
  not added as a stray top-level authoritative root test;
- `benchmark/src/lw3_localworksets_parity.jl` and
  `benchmark/backends/metal/lw3_localworksets_parity.jl`; and
- `design/hardening/lw3-localworksets-parity.md` and the eventual LW-R1 review record.

Any new dependency, standalone package directory, PottsToolkit export, second domain vertical,
accepted public algorithm mode, generalized output family, scheduler/runtime, scientific policy, or
production deletion of the direct path requires stopping and amending the gate before implementation.

## Gate execution order

1. Implement only the LW-1 substrate rows and make LW1-T01 through LW1-T25 pass on CPU and the
   qualified real-Metal rows where named.
2. Review the exact LW-1 diff under the strengthened semantic-portability constraints.
3. Resolve every P0/P1 and re-run the full CorePotts CPU plus qualified real-Metal evidence.
4. Record the exact LW-1 review candidate and stop. Completed: the bounded LW-1 review passed and
   the owner-approved dual-destination amendment now controls the next implementation.
5. Completed: the owner instruction authorized the bounded vertical and LW-3 evidence, and the
   fresh exact-hash committee cleared LW-R1. Do not begin LW-4 until the owner records its
   disposition.

## Committee ballot

Round-one review covered candidate SHA-256
`9fb4136bd97a0f776c6e6790241785b8be8a62a5e1c40915740a021f0f9ac21b`:

| Reviewer | Ballot | Counts | Disposition |
|---|---|---|---|
| Julia API/minimality | PASS WITH BOUNDED AMENDMENTS | P0=0, P1=0, P2=5, P3=2 | exact public surface, lifecycle default, Base generics, storage reuse and qualified inspection amended |
| KernelAbstractions/Metal | FAIL | P0=0, P1=2, P2=3, P3=0 | provider status and recovery blockers made explicit; lease, pool and performance rules amended |
| CorePotts preservation | PASS WITH BOUNDED AMENDMENTS | P0=0, P1=0, P2=4, P3=0 | accepted-copy eligibility, lowering identity, poison split and Hamiltonian coverage amended |

The amended substantive candidate SHA-256
`7f3c414a6732dda650fa424bbb1fff7dda7ea120b50b193996a95a27602ab731` received these independent
final ballots:

| Reviewer | Final ballot | Counts | Substantive dissent |
|---|---|---|---|
| Julia API/minimality | PASS | P0=0, P1=0, P2=0, P3=0 | none |
| KernelAbstractions/Metal | PASS | P0=0, P1=0, P2=0, P3=0 | none |
| CorePotts preservation | PASS | P0=0, P1=0, P2=0, P3=0 | none |

The GPU ballot is a pass for the historical pre-implementation matrix, not for this implementation
or LW-R1. Its backend-extension assumptions are superseded by the hardware-neutral
KernelAbstractions provider and must be re-reviewed on exact source and real-Metal evidence.

That committee signed the pre-amendment matrix for bounded LW-1 implementation. The owner amendment
above superseded its review sufficiency, not its accepted architectural decisions. Those historical
ballots were not inherited by the implementation review.

The fresh exact-hash LW-R1 committee then returned:

| Reviewer | Bounded LW-1 | Future-library obstruction | Counts | Dissent |
|---|---|---|---|---|
| Julia API/package boundary | PASS | NONE | P0=0, P1=0, P2=0 | none |
| CorePotts semantics/determinism | PASS | NONE | P0=0, P1=0, P2=0 | none |
| KernelAbstractions/Metal | PASS | NONE | P0=0, P1=0, P2=0 | none |
| nonvoting contradiction chair | CLEARED | NONE | aggregate P0=0, P1=0, P2=0 | none |

The same committee separately passed the bounded LW-2 conjunctive vertical and LW-3 Q01--Q10 for
qualified CPU and real Metal. Its scope, fresh performance rerun and six separate rulings are
recorded in the [LW-R1 exact-candidate review](lwr1-localworksets-review.md). LW-R1 authorized only
an owner LW-4 disposition; it did not promote the candidate, weaken the direct oracle, authorize
another migration or claim that the general library already exists. The owner subsequently selected
standalone extraction, bounded mechanism completion and API reconciliation through the
[post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md). The completed
[LW-4A extraction matrix](lw4a-extraction-implementation-matrix.md) now governs source
implementation; no LW-4B capability work is authorized before LW-R2A.
