# Asynchronous Execution and Centralized Settlement Review

Date: 2026-08-03

Branch: `codex/symbolic-potts-v1`

Status: independently reviewed direction implemented in CorePotts for the bounded lifecycle
candidate; quality clearance and broader lifecycle qualification remain pending; no performance
optimization is accepted without measurement

## Implementation checkpoint

The current candidate now has:

- one host-side `submitted_mcs` position and backend-resident committed MCS/active-bank authority;
- host mirrors for drained, committed, and materialized positions updated only by settlement;
- two complete fixed-capacity scientific-state banks for the whole checkerboard MCS;
- sticky device status with exact first scientific failure MCS/stage/source/action identity;
- backend-resident cumulative `UInt64` proposal/lifecycle statistics distinct from resettable
  transaction controls;
- one production `KernelAbstractions.synchronize` call, owned by `settle_program!`;
- no public checkerboard state-copy/materialization bypass;
- one settlement receipt carrying positions, counters, status, typed failure, and an optional coherent
  snapshot; and
- CPU and real Metal witnesses for two queued successful MCS and first-MCS capacity failure with
  later queued work inert.

Focused compiler/lifecycle tests pass, the CPU fast boundary passes 307/307 assertions, real Metal
passes both asynchronous witnesses with scalar device access disabled, and the ordinary Julia
package suite passes 1,846/1,846 assertions on the exact working candidate. The remaining work is
the independent code/architecture/DRYness review, broader effect/policy conformance, and bounded
performance/qualification evidence. Public PottsToolkit boundary scheduling and SciML publication
remain later interface work; this checkpoint does not start them.

## Decision under review

An MCS is a scientific transaction and ordering boundary, but not automatically a host wait. The
candidate architecture separates ordered submission from host settlement:

```text
CorePotts
    enqueue complete scientific transactions on one ordered backend queue

PottsToolkit runtime
    choose the next host-visible boundary
    request the required visibility through one settlement authority

external consumers
    request settlement; never synchronize or materialize storage directly
```

The intended uninterrupted path is:

```text
proposal kernels
→ conflict kernels
→ commit kernels
→ after-MCS stages
→ lifecycle transaction kernels
→ next MCS
→ ...
→ requested projection/materialization
→ one host synchronization
→ status translation and publication
```

This is not a persistent-kernel design, a stream scheduler, or an event graph. Kernel boundaries,
atomics, and workgroup barriers retain their ordinary synchronization meaning. The target is zero
host-blocking barriers inside an uninterrupted execution chunk.

## Independent-review verdict

The independent reviewer accepted centralized settlement and ordered multi-MCS submission as the
right direction, but classified it as a runtime-architecture correction rather than a local barrier
cleanup. The current candidate does not clear because it lacks an end-to-end GPU runtime,
whole-MCS banked atomicity, sticky first-failure/cumulative control storage, complete device
lifecycle publication, distinct runtime positions, and an unbypassable materialization authority.

The review also corrected two overclaims:

- CorePotts, not PottsToolkit, must own the physical backend wait because CorePotts owns the queue,
  backend arrays, status, and coherent state bank. PottsToolkit owns boundary policy and SciML host
  publication.
- Exact failure MCS is mandatory for device-detected scientific failures. A generic backend/driver
  error reported only by terminal synchronization can promise an attribution interval, not a
  fabricated exact MCS.

## Verified constraints and bounded evidence

The repository resolves KernelAbstractions 0.9.42 and AcceleratedKernels 0.4.3. The local
KernelAbstractions 0.9 documentation states that the event/dependency API was removed, launches are
implicitly ordered, and `synchronize(backend)` blocks the host until queued work completes. The
architecture therefore MUST NOT recreate a returned-event DAG or pass obsolete `dependency=`
arguments.

AcceleratedKernels uses KernelAbstractions as its backend boundary. Two local Metal probes with
scalar indexing disabled confirmed the exact mixed sequences needed by the current candidate:

1. KernelAbstractions kernel → AcceleratedKernels stable sort → KernelAbstractions kernel.
2. KernelAbstractions kernel → AcceleratedKernels prefix scan → KernelAbstractions kernel.

Both produced correct results with no intermediate host wait and one final synchronization. This is
a CPU/Metal witness, not CUDA or ROCm qualification. The portable contract and the same
backend-neutral conformance fixture must later be exercised on each claimed vendor backend.

The performance effect of removing barriers is still a hypothesis. Correct queue ordering is a
verified architectural constraint; speedup, launch cost, report cost, and useful chunk length must
be measured after functional equivalence.

## Current implementation audit

### Confirmed blockers

1. PottsToolkit compilation currently rejects every backend except CPU, CorePotts lowering always
   chooses its CPU backend marker, and `ProgramRuntime` stores host `Array`/`Vector` scientific
   state. The manually adapted checkerboard GPU fixtures are valuable kernel witnesses but are not
   an end-to-end `init`/`step!`/`solve!` device runtime.
2. `ProgramRuntime` also stores a host `mcs`, host counters, and a
   single `settled::Bool`. That boolean currently means “no partial host transaction is active.” It
   cannot also mean backend completion or host-mirror freshness.
3. The committed baseline checkerboard loop synchronized approximately eight times per color even
   though most waits separated device-to-device dependencies. The working candidate has removed
   those direct waits, but it does not yet have the settlement representation or end-to-end
   qualification needed to make multi-MCS queuing safe.
4. `step!` calls `CorePotts.advance_mcs!` and then unconditionally calls `_current_saved_state`.
   `_current_saved_state` forms a complete `program_snapshot`; `solve!` is a loop over `step!`.
   Consequently the public wrapper materializes state every MCS even when no save, callback,
   checkpoint, observation, or exchange is due.
5. `_advance_checkerboard!` reads the report buffer after each MCS and updates host counters.
   `copy_checkerboard_state!` defaults to `Array` conversion. Counters and scientific state are not
   yet governed by one explicit settlement boundary.
6. The checkerboard report is reset each MCS, so several queued MCS values would retain only the
   last report. The in-progress backend lifecycle reset now preserves a prior failure and a retired
   total, which is the correct local direction, but there is no complete program-level sticky
   first-failure/cumulative control block yet. Host lifecycle workspace reset also remains a
   separate synchronous path. Program-wide submission therefore still needs sticky cumulative
   counters and one first-failure record distinct from resettable per-MCS scratch.
7. Checkerboard proposal commits mutate the current state in place before lifecycle finishes. A
   later lifecycle or invariant failure would therefore corrupt the last completed state. Exact
   failure and checkpoint semantics require two complete fixed-capacity scientific-state banks:
   copy/build the next MCS in the inactive bank, validate the whole MCS, and publish by a bounded
   bank swap only on success.
8. `program_snapshot`, `program_checkpoint`, parameter mutation, and PottsToolkit checkpointing
   rely on the host `settled` flag. They do not request a declared visibility level from a common
   authority.
9. SymbolicIndexingInterface parameter operations access host buffers directly, and the live state
   getter reads `integrator.u`. There is no fence ensuring that each host read sees precisely the
   requested queued MCS or that a transactional multi-setter settles only once.
10. The ProcessBigraph adapter is currently host-only, accepts exactly one MCS per invocation,
   checkpoints the published integrator, clones from that checkpoint, calls public `step!`, copies
   complete saved outputs, reads host statistics, and checkpoints again. This is scientifically
   conservative but cannot express interval enqueueing, selected-port settlement, or a same-backend
   queued adapter.
11. The in-progress backend lifecycle path now enqueues fixed-capacity indexing, emission,
    compaction, planning, selection, staging, request application, invariant validation,
    publication, and retired-cell accounting without an intervening host read. That is meaningful
    progress and supersedes the earlier finding that it stopped at selection. It is still an
    adapted checkerboard-state path rather than an end-to-end runtime: the status payload lacks
    exact MCS/stage identity, publication is not a whole-MCS bank swap, only the current backend
    fixture is exercised, and the next MCS is not submitted through one program enqueuer.

### Important non-findings

- No evidence requires kernel fusion, a persistent kernel, multiple streams, a transaction journal,
  copy-on-write scientific state, Morton ordering, or a general callback language.
- Removing an explicit host wait is not sufficient evidence that a path is correct or faster.
- The 0.9 queue-ordering contract does not qualify a mixed KernelAbstractions/
  AcceleratedKernels sequence on an untested vendor backend by itself.
- A host callback that consumes arbitrary Julia state genuinely requires host visibility. The
  architecture must report that cost instead of obscuring it.

### Measured Metal compiler-pressure finding

The first real Metal lifecycle attempt exposed an unsupported method-error path in generic division
geometry. Making lattice/scalar structure explicit removed that invalid IR. The next attempt
produced valid device IR, but the single all-effects planning kernel emitted approximately 1.6 MiB
of LLVM and caused Apple's Metal compiler service to fail native pipeline construction. Separating
canonical sorting alone did not reduce that planner. Grouping by the closed structural lifecycle
effect classes and enqueuing only compiler-reachable effects removed the unused-effect expansion,
but the reachable division planner still failed to complete compilation within a bounded run; the
Julia process reported roughly 197 million compilation-inclusive allocations before termination.

This is measured qualification evidence, not a timing threshold. It establishes that the current
division planner remains too coarse as one kernel entry point. The next correction is bounded:

- compile/enqueue only structural planning variants reachable from the completed model;
- decompose division planning by the closed partition-geometry and side-policy algebra, or by an
  even smaller semantics-preserving kernel sequence if measurement requires it;
- preserve canonical request-local failure records and reduce them in canonical order after the
  structural kernels, so kernel grouping never changes the scientific offender;
- keep partition workspaces fixed-capacity and request-safe; and
- reject a Metal-only planner, a biological-mechanism grouping, or an alternate host executor.

Generated-code size, first compilation, and synchronized execution are measured separately. A
bounded backend compile is a correctness/portability gate; steady-state speed remains a benchmark
hypothesis.

## Refined runtime positions

Two counters are insufficient once work may be queued beyond a failure. The runtime should track
four value-level positions with names equivalent to:

| Position | Meaning |
| --- | --- |
| `submitted_mcs` | Greatest complete MCS transaction whose full launch sequence was placed on the ordered queue. |
| `drained_mcs` | Greatest submitted MCS whose backend work is known to have finished after a host wait; kernels after a device failure may have completed as no-ops. |
| `committed_mcs` | Greatest MCS whose scientific transaction published successfully. This remains the public scientific time. |
| `materialized_mcs` | Scientific MCS represented by the complete host mirror or immutable host snapshot. |

For a queue submitted through MCS 100 with first failure at MCS 37, settlement may yield:

```text
submitted_mcs  = 100
drained_mcs    = 100
committed_mcs  = 36
failure_mcs    = 37
materialized_mcs ≤ 36
```

`drained_mcs` is deliberately not called “completed scientific MCS.” It records backend completion,
including status-gated no-ops. `committed_mcs` is authoritative for SciML time, checkpoint identity,
replay, and external exchange.

The runtime also needs a separate transaction-submission fact. `enqueue_mcs!` advances
`submitted_mcs` only after the complete kernel sequence for that MCS has been launched. A launch
failure while submission is open is a backend failure; it cannot publish a scientific time.

These positions are ordinary runtime integers. Boundary occurrences, save times, model identities,
and failure MCS values MUST NOT enter types.

## One settlement authority

CorePotts owns the sole physical settlement authority because it owns backend-resident scientific
state, queues, state-bank publication, status payloads, and the low-level copy/projection plans.
PottsToolkit owns the semantic boundary scheduler because it owns SciML time, saving, callbacks,
checkpoints, SII, progress, and external adapters.

This is one physical authority and one policy caller, not two synchronization services:

```text
PottsToolkit request_settlement!(integrator, request)  # chooses why/what/when
    CorePotts.settle_program!(runtime, request)         # sole physical authority
        enqueue requested projection/copies
        KernelAbstractions.synchronize(backend)         # sole production host wait
        inspect sticky status/counters
        optionally materialize the coherent active bank
        return an immutable settlement receipt
    PottsToolkit publishes u/time/retcode/SciML effects from the receipt
```

The precise function names remain implementation details. The ownership rules do not:

- one closed CorePotts settlement API owns synchronization; backend-specific methods are reachable
  only through that API rather than being callable materialization alternatives;
- every device-to-host materialization routes through that authority;
- PottsToolkit checkpoint, SII, callbacks, progress, reporting, ProcessBigraph, and solution code
  submit a request and never wait or call `Array(device_array)` themselves;
- CorePotts execution loops never inspect host-visible device status;
- cached metadata display never requests settlement;
- tests and benchmark harnesses may synchronize directly only at their explicit observation/timing
  boundary and must not be callable from production execution.

## SciML failure-exit decision

SciMLBase 3.39.1 exposes a closed `ReturnCode.T` vocabulary. Its documented generic unsuccessful
solver exit is `ReturnCode.Failure`; `MaxIters`, `Unstable`, and `InitialFailure` have narrower
meanings and MUST NOT be reused for fixed-capacity or lifecycle-status failures. The solution form
remains extensible, so PottsToolkit carries the precise immutable failure report as a problem-
specific field while the standard retcode preserves ecosystem interoperability.

The accepted translation is:

| Settled condition | Public behavior |
| --- | --- |
| fixed cell/relationship capacity, configured inadmissibility/conflict, generation exhaustion, or state-dependent evaluator failure | terminal integrator/partial solution with `ReturnCode.Failure`; exact first failing MCS in the typed report; public `t`/`u` remain at the last committed MCS |
| user-requested termination | `ReturnCode.Terminated` |
| iteration limit | `ReturnCode.MaxIters` |
| invalid construction, admission, or solver option | throw before submission |
| stale generation, footprint-proof violation, internal invariant, unknown device status | throw the translated typed exception after settlement |
| compiler, launch, driver, backend, transfer, or persistence failure | throw with the original cause and honest attribution interval |

`step!` attempts and settles one complete MCS. An expected failed attempt returns the integrator with
`ReturnCode.Failure` and no time advance; `SciMLBase.check_error` reports that retcode. `solve!`
returns the coherent partial failed solution. This distinction preserves asynchronous queuing:
device kernels only write sticky status and self-gate, and public failure is observed at the next
already-required settlement rather than through per-MCS polling.

If a backend or copy API contains an implicit wait, that operation belongs inside CorePotts
authority and is counted as part of the same boundary. It may not be hidden in a getter.

Queue-ordered copies must use a backend operation whose ordering and host-asynchrony are part of
its contract. KernelAbstractions 0.9 provides `KernelAbstractions.copyto!(backend, destination,
source)` for that purpose and documents ordinary `Base.copyto!` as synchronous. The runtime must
keep every host or device buffer participating in an asynchronous copy alive through settlement.
An unqualified `copyto!`, `Array`, `collect`, host scalar read, or backend-specific wait is never
assumed to be asynchronous merely because adjacent kernels use the same backend.

## Closed settlement request

The request is small, immutable, and value-level. It needs no event-query language. Its closed
information is:

```text
current submitted MCS
reason
requested reductions/counters
requested output/projection manifest
whether a full state snapshot is required
whether host mutation follows
```

KernelAbstractions settlement drains the ordered backend queue; it cannot stop at an earlier MCS in
that queue. Therefore every request target equals the runtime's current `submitted_mcs`, and the
boundary scheduler MUST NOT enqueue past the next known host boundary. Work may be submitted past
an unknown device-detected scientific failure because sticky status makes later kernels inert, but
a save, checkpoint, host callback, parameter/input update, or ProcessBigraph exchange cannot be
inserted retroactively after later MCS transactions have already been queued.

The initial reason vocabulary is limited to finalization, public step, save, host callback,
checkpoint, SII read, SII mutation, ProcessBigraph exchange, progress, explicit statistics, and
explicit observation. Coincident consumers form one request at one MCS.

The initial visibility request has independent closed fields:

1. status and required counters;
2. a set of named small reductions/observations;
3. a set of declared output ports or state leaves; and
4. a Boolean request for a complete host snapshot and live `integrator.u` publication.

Coincident requests combine by Boolean union and union of their named sets. `reduced` and `selected`
are not treated as a total cost or information ordering. A progress request must not silently
request a full snapshot. `reason` is policy/telemetry metadata, not backend dispatch. A host mutation
always settles the prior queue first and publishes the mutation only at the documented next
scientific boundary.

## Submission contracts

CorePotts needs one internal nonblocking operation equivalent to:

```julia
enqueue_mcs!(runtime, mcs)
```

It enqueues the complete admitted transaction in fixed order:

```text
candidate generation
→ evaluation
→ conflict claims and selection
→ commit
→ ordered after-MCS stages
→ lifecycle emission, compaction, conflict/capacity planning
→ staged lifecycle commit
→ invariant validation
→ atomic publication
→ backend counters/status publication
```

Every kernel first checks the fixed sticky backend status. After the first failure, later kernels
and later submitted MCS transactions are no-ops. No kernel may clear a prior failure. Resettable
per-MCS scratch is separate from the sticky control block. Within one MCS, candidate failures are
reduced by a documented canonical ordering before the payload is published.

The whole MCS executes against the inactive fixed-capacity scientific-state bank. Proposal commit,
after-MCS stages, lifecycle effects, tracker updates, relationship changes, and validation all
target that bank. A final status-gated publication kernel swaps the active-bank identity and
advances the backend committed MCS. Failure leaves the previous active bank byte-for-byte coherent.
This two-bank requirement is the minimal accepted atomicity mechanism; journals and copy-on-write
state remain rejected complexity unless later measurement justifies revisiting it.

Multi-MCS submission cannot require the host to read the active-bank identity between launches.
Every submitted transaction must select its source and destination banks from backend-resident
control state or an equivalent deterministic value-level MCS rule and must receive access to both
complete banks. The host-side submitted position records accepted launch sequences only; it never
chooses scientific publication based on an unobserved device result.

The lifecycle status payload must include at least failure code, exact first failing MCS, execution
stage, qualified source/action identity, required capacity, available capacity, configured maximum,
and the bounded details required for deterministic Julia exception or SciML return-code
translation. Exact MCS attribution is required for device-detected scientific/status failures such
as capacity exhaustion. A generic backend or driver error first reported by the final
`synchronize` cannot always be assigned to one MCS without event tokens; it must report the honest
attribution interval `(previous drained MCS + 1):submitted_mcs` rather than invent a precise time.

The sequential CPU engine remains the semantic reference. It may execute synchronously as an
implementation fact, but it must pass through the same submission/settlement state machine and
produce the same positions and status meaning.

## SciML contract

Public behavior remains synchronous:

- `step!(integrator)` enqueues one MCS, settles it, raises/translates any failure, and publishes a
  complete `integrator.u` before returning.
- `step!(integrator, n)` has the same settled-return contract at its final requested MCS; whether it
  settles intermediate MCS values is determined only by real boundaries.
- `solve(problem)` and `solve!(integrator)` return finalized solutions whose retained data and
  retcode are complete.

The internal solve fast path must not be implemented as repeated public `step!`. It repeatedly
chooses the next required host boundary, enqueues complete MCS transactions through that boundary,
settles once with the combined request, performs boundary actions, and resumes. This is not a second
scientific executor: both paths call the same `enqueue_mcs!` transaction.

For the first implementation:

- `save_start` materializes during initialization when requested;
- `save_end` adds one final boundary;
- each `saveat` boundary settles once;
- `save_everystep` settles every MCS;
- scheduled host callbacks settle at their known boundaries;
- arbitrary host conditions evaluated every MCS settle every MCS;
- admitted device-native conditions/effects add no host boundary;
- device-to-device deferred snapshots are measurement-gated later work.

## Checkpoint, SII, and statistics contracts

`checkpoint(integrator)` requests `full` settlement at the latest submitted transaction, verifies
that the scientific position is committed, translates device failure, and serializes the settled
state. Checkpoint code does not synchronize directly. Scheduled checkpointing is one boundary
reason and combines with coincident saves or callbacks.

A host SII getter requests the minimum visibility required by that value. A setter first requests
settlement, validates a typed update, enqueues or stages it at the declared scientific boundary,
and invalidates stale mirrors. A transactional multi-getter or multi-setter settles once.

Counters remain backend-resident across chunks. `runtime_statistics`, progress, solution
construction, and checkpointing request only the counters they require. Counter collection must not
copy the lattice. Changing the current one-work-item serial report is a measurement-gated
optimization; exact accounting tests precede any reduction rewrite.

## ProcessBigraph contract

The portable host path becomes:

```text
advance_until(target MCS)
→ settle requested output manifest
→ ProcessBigraph exchange and validation
→ stage declared inputs
→ resume queued execution
```

ProcessBigraph owns the macrostep schedule but does not reach into CorePotts storage or backend
queues. The intended adapter requests exactly the declared ports, counters, and continuation data.
The current protocol requests all outputs and constructs a full host checkpoint continuation for
each candidate, so it does not yet establish selected-only materialization. A selected-port claim
requires either a revised continuation contract or a qualified resident continuation handle.

Three execution cases remain explicit:

1. host component: settle and materialize selected outputs;
2. incompatible/different backend: declared transfer boundary;
3. same backend and compatible storage: a future separately admitted device-native transaction may
   enqueue a qualified adapter/component kernel on the same ordered queue, with no host settlement.

The current one-MCS, host-only, checkpoint-clone adapter is the portable reference behavior but not
the final performance architecture. Its host completion/validation/authorization/publication
protocol makes every current exchange a host boundary. Same-backend queuing is deferred until a
separate device-native ProcessBigraph protocol is accepted and qualified; it is not required for
the current GPU lifecycle boundary. Supporting it later does not authorize a general callback DSL
or allow ProcessBigraph to become a second CorePotts executor.

For the existing two-stage ProcessBigraph engine protocol, `stage_operation!` should validate and
enqueue without forcing host completion; `complete_operation!` should request the required
settlement and construct effects, statistics, checkpoint, and diagnostics. The current implementation
does all synchronous work in `stage_operation!` and merely returns a stored candidate from
`complete_operation!`; that ownership must be reversed before claiming an asynchronous adapter.

## Fresh adversarial question record

The owner-requested reviewer challenged each question against the current source. The bounded
answers, including corrections made after checking the working tree, are:

| # | Disposition |
| ---: | --- |
| 1 | KA same-backend launch ordering is accepted. Exact mixed KA/AcceleratedKernels sort/scan sequences have CPU/Metal evidence only; CUDA/ROCm and other AK algorithms remain unqualified. |
| 2 | Former checkerboard waits between device stages restated queue order. Host protection is required before status, report, state, callback, checkpoint, assertion, or other host consumption. |
| 3 | One wait per color is a valid intermediate checkerboard reference for currently admitted device work, not a final target or lifecycle qualification. |
| 4 | One wait per MCS is also viable after reports become cumulative; it is the frequent-settlement correctness reference before chunking. |
| 5 | Host-only runtime storage/counters, report reset, in-place whole-MCS mutation, incomplete banked publication, and `solve! -> step! -> snapshot` currently prevent safe multi-MCS submission. A scheduler must also stop submission at the next known host boundary. |
| 6 | Reports, snapshots, checkpoints, host observations, statistics, SII state access/mutation, external inputs, and current ProcessBigraph candidate construction force host visibility. Lifecycle science itself must not. |
| 7 | Sticky canonical status can make later kernels inert only if every write path, including resets, bank preparation, reports, lifecycle, and final publication, gates on it. |
| 8 | Public `step!` remains SciML-compatible by settling and publishing coherent `t`/`u` before return. |
| 9 | Internal `solve!` may bypass repeated materialization safely only by sharing the same CorePotts enqueuer and honoring every known intermediate boundary. |
| 10 | Arbitrary host conditions evaluated each MCS force settlement each MCS. Scheduled host callbacks settle only when due; separately admitted device-native callbacks do not. |
| 11 | Selected-output ProcessBigraph effects are possible with projection plans, but the current full checkpoint continuation still forces full materialization. No selected-only claim is established yet. |
| 12 | The current ProcessBigraph completion/validation/publication protocol is host-visible. Entirely queued same-backend components require a separately accepted device-native protocol and are deferred. |
| 13 | Checkpoint ownership is correct in the proposal but not the implementation; every checkpoint front door must use the settlement API or an authority-issued receipt. |
| 14 | SII is not yet correctly fenced: the live parameter buffer and state snapshot paths must become coherent shadows/projections plus settle-once mutation transactions. |
| 15 | The service remains small after requiring `target == submitted`, independent reduction/projection/full-snapshot fields, and one closed API rather than a literal one-file rule. |
| 16 | Banks, sticky status/counters, four positions, and shared enqueue with two visibility policies are correctness work. Fusion, indexes, report redesign, retained snapshots, same-backend ProcessBigraph, and callback machinery remain evidence-gated. |
| 17 | Essential work is the end-to-end backend runtime, banked atomicity, sticky control, complete device lifecycle, sole enqueue/settlement paths, SciML/checkpoint/SII fences, and CPU/Metal equivalence. Vendor expansion and optional device-native integrations wait. |

The reviewer initially repeated the earlier statement that backend lifecycle stopped after
selection. Direct inspection of the current working tree disproved that statement: the enqueuer now
includes staging, application, validation, publication, and retired accounting. The remaining
blocker is integration into whole-MCS banked execution and end-to-end qualification, not absence of
those lifecycle kernels.

## Bounded implementation options

### Option A — Keep public-step loop and one settlement per MCS

Correct and simple, but it cannot satisfy the uninterrupted-solve objective and makes GPU lifecycle
residency pay host latency every MCS. Retain only as a frequent-settlement reference fixture.

### Option B — Central authority plus chunked solve (recommended)

Introduce explicit runtime positions, one settlement request, one CorePotts submission and physical
settlement path, a PottsToolkit boundary scheduler, two fixed scientific-state banks, and sticky
control storage. Preserve kernel boundaries. First qualify one wait per MCS, then multi-MCS chunks.
This is substantial, cross-cutting runtime work but does not change symbolic or scientific
semantics.

The position/control/banking/authority work in this option is required correctness architecture for
the accepted device-resident lifecycle and exact-failure contracts. Its performance effect is still
measured. Optional kernel decomposition, report reductions, indexes, ordering changes, fusion, and
snapshot retention remain optimizations and require an end-to-end workload improvement.

### Option C — Event graph, streams, fusion, or persistent kernel

Rejected for V1. KernelAbstractions 0.9 does not expose the proposed event API, and none of these
complexities is required to test the value of ordered asynchronous submission.

## Essential before GPU lifecycle qualification

1. Freeze the four runtime positions, `settlement target == submitted`, no-submit-past-known-boundary
   rule, and one settlement-owner rule in accepted specifications.
2. Add two complete fixed-capacity scientific-state banks and status-gated whole-MCS publication.
3. Extend device status with exact first-failure MCS, sticky cumulative counters, and deterministic
   first-failure selection.
4. Qualify the complete backend-resident lifecycle transaction now present in the working tree
   through every admitted effect/policy, validation, publication, and the next MCS; no host branch,
   status read, or transfer between its kernels or between queued MCS values.
5. Make all later queued kernels no-op after failure and prove the prior active bank is unchanged.
6. Route checkerboard reports and lifecycle counters into backend-resident accumulators.
7. Establish one nonblocking `enqueue_mcs!` production path used by public step and internal solve.
8. Establish one CorePotts settlement authority and ban direct production waits/materialization
   elsewhere.
9. Remove the CPU-only compilation/lowering restriction and exercise end-to-end GPU
   `init`/`step!`/`solve!`, not only manually adapted kernel workspaces.
10. Route checkpoint, SII, and the ProcessBigraph host reference through the settlement API; the
    ProcessBigraph path may honestly retain full materialization for its checkpoint continuation.
11. Pass the frequent-settlement reference equivalence tests on CPU and real Metal.
12. Prove that lifecycle kernel generation includes only reachable structural effect/policy classes
    and that the division planner compiles within the explicit backend qualification profile.

## Measurement-only additions

- Count launches, host waits, transfer bytes, visibility class, and boundary reason.
- Compare the existing barriers, one wait per color, one per MCS, and one per solve chunk without
  changing kernel decomposition.
- Separate compilation, first execution, and synchronized steady-state timing.
- Measure no-due lifecycle, emitted-without-selected request, one division as cell size grows,
  independent requests, conflicts, and full publication.
- Measure report serialization, buffer clearing, workgroup size, checkpoint, ProcessBigraph host
  exchange, arbitrary host callbacks, and final materialization.
- Record lifecycle overhead relative to an otherwise identical MCS; do not freeze arbitrary
  absolute timing thresholds.

Timing stays in an explicit benchmark/qualification profile. Every GPU sample synchronizes just
outside the measured operation. Ordinary tests retain exact counts, allocations, inference,
replay, and hidden-fallback guards.

## Deferred pending evidence or a separate protocol

- CUDA and ROCm hardware qualification using the same backend-neutral fixtures.
- Selected-only ProcessBigraph continuation and entirely queued same-backend components.
- Device-resident retained snapshots and a device-native callback implementation.
- Specialized lifecycle indexes, report reductions, or backend tuning beyond portable semantics.

## Explicitly rejected V1 complexity

- KernelAbstractions event/dependency DAGs, persistent kernels, arbitrary streams, or unevidenced
  fusion.
- A second lifecycle/scientific executor, host fallback, or host lifecycle orchestration disguised
  as portability.
- Per-stage or per-MCS status polling inside an uninterrupted chunk.
- Journals or copy-on-write as substitutes for the accepted two-bank correctness contract.
- A general callback DSL or backend-specific scientific semantics.

## Exact acceptance tests

Settlement instrumentation starts after initialization and counts one boundary even when several
reasons coincide.

| Scenario | Expected host settlement |
| --- | ---: |
| 100 MCS, only end state retained | 1 |
| `saveat = (25, 50, 75, 100)` | 4 |
| four public `step!` calls | 4 |
| checkpoint requested at MCS 40 | 1 at 40 |
| host ProcessBigraph exchange every 10 MCS through 100 | 10 |
| arbitrary host callback condition every MCS | 100 |
| separately admitted device-native callback every MCS plus final solution | 1 final; no callback-added boundary |
| capacity failure at 37 after submission through 100 | one observation; exact failure 37; no mutation after 36 |

The same fixtures also require exact replay against the frequent-settlement reference, identical
conflict winners and accounting, public step versus chunked solve equality, save/checkpoint
equality, parameter and external-input ordering, ProcessBigraph host-reference exchange equality,
CPU and real Metal execution, no scalar indexing, no host fallback, and existing warm-allocation
guarantees.

Selected-port ProcessBigraph equality becomes required only when a selected-projection continuation
contract is admitted. The current host reference instead requires exact full candidate,
checkpoint, exchange, and continuation equality at the declared boundary.

CUDA and ROCm use the same backend-neutral fixtures in later qualification; source portability is
not reported as hardware qualification.

## Stop rule

Do not implement fusion, a callback language, device snapshot retention, same-backend
ProcessBigraph execution, multi-stream scheduling, or performance-specialized lifecycle indexes
before the central state machine and frequent-settlement equivalence pass.

Do not claim the current lifecycle execution boundary complete until a fresh independent reviewer
confirms that the single settlement authority is unbypassable, failure time cannot be confused with
observation time, and no production path performs hidden host synchronization or materialization.
