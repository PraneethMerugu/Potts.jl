# LW-5B4O-R exact-candidate review

Date: 2026-08-13

Status: **PASS; LW-5B4O FROZEN; BOUNDED LW-5 MAY RESUME**

Authority:

- [LW-5B4O phase](lw5b4o-mandatory-layout-and-execution-optimization.md);
- [exact-candidate evidence](lw5b4o-final-evidence.md); and
- [paired raw performance evidence](lw5b4o-performance-raw.md).

This review freezes the bounded mandatory-layout and execution-optimization
amendment. It does not promote K02 or B3 to production, delete their direct
oracles, authorize another execution family/backend, open LW-R3, or open G6.

## Sealed candidate

| Artifact | SHA-256 |
|---|---|
| `lib/LocalWorksets/src` | `bc2f1a66f6499b90da4503a2e7590e1dc359b1ecd34130df2a5cfc040649c4bf` |
| `lib/CorePotts/src` | `97f1d8b88de73cb865a24590d7921680c349b1db00c18f05d7a83294a80f42b0` |
| `lib/LocalWorksets/test` | `55bc71385481a032b821afce7d969fce624c8d2e5d5f5795243a215553188b72` |
| `lib/CorePotts/test` | `822f23236263c462ae0ed7c611bbc9db53d2864586f57e51b7ae3cae82dc7509` |
| benchmark sources and owned environments | `08e84b163a4bed8ba5696aa1b8a5812155801e494e00930d88e73a32e3a0c893` |

The chair ran the complete evidence matrix before sealing. Reviewers then
performed independent read-only review of the bound source, tests,
specification, final evidence, and raw samples; they did not inherit a prior
ballot or rerun the expensive suites.

## Independent ballots

| Reviewer | P0 | P1 | P2 | Freeze | Resume bounded LW-5 |
|---|---:|---:|---:|---|---|
| Julia API, dispatch, storage and adapter cohesion | 0 | 0 | 5 | **PASS** | **PASS** |
| JuliaGPU, KernelAbstractions and performance | 0 | 0 | 3 | **PASS** | **PASS** |
| Scientific preservation and cross-domain generality | 0 | 0 | 3 | **PASS** | **PASS** |
| Chair synthesis | **0** | **0** | **6 normalized classes** | **PASS** | **PASS** |

The GPU reviewer initially returned an older B3 status summary rather than a
ballot. That response was rejected as nonresponsive. The reviewer then read
the sealed B4O packet and returned the independent GPU/backend/performance
ballot above. No inherited or nonresponsive response counts toward clearance.

## Required decisions

| Question | Committee decision |
|---|---|
| Mandatory dependencies and capability identities | **PASS.** Both packages own ordinary direct imports and exact version-bearing capability identities. |
| Reusable component-record lowering | **PASS, bounded.** It refines independent output, remains centrally validated/lowered, and has an unrelated D2Q9 consumer. |
| CorePotts proposal schema consolidation | **PASS WITH P2.** The seven original arrays remain authoritative and object-identical; K02/K03 share one record authority, but K03 still enumerates five leaves. |
| K02 science, lifetime and performance | **PASS AS NONPRODUCTION WITNESS.** One launch, no intermediate wait, zero algorithmic workspace/identity-route transfer, exact oracle parity, CPU upper95 `1.0319632`, Metal `0.9842337`. |
| Corrected B3 preservation | **PASS.** Canonical Hamiltonian fold, exact RNG, two-bank lifetime, 12 queued MCSs, 24 submissions and one final synchronization remain CorePotts-owned. |
| Resume the existing LW-5 sequence | **PASS.** Only the already-authorized bounded adoption sequence reopens. |

## Contradiction and red-team disposition

The review preserves adverse evidence rather than reducing it to the final
pass:

- the expanded real-Metal topology matrix found host iteration over device
  proposal offsets; canonical epoch hashing now explicitly requires host
  arrays and every altered plan supplies its host proposal offsets;
- a correct recursive warm validator failed Metal performance and was
  replaced by an explicit stable-leaf qualification, not by deleting safety;
- the first post-topology-fix exact Metal gate failed at upper95 `1.1510607`;
  four-layer attribution localized steady-world adapter overhead, and a
  stable-world exact-invoke path reduced it while the changed-world validation
  and draining tests remained intact;
- a Julia 1.10 launch failed before tests against the explicitly Julia 1.12
  Metal environment; only the declared Julia 1.12.6 run is qualification; and
- dependency results remain ordered marginal measurements with no fabricated
  historical O0 comparator.

No reviewer found a P0/P1 contradiction after those corrections. All three
separately confirmed vendor-neutral execution source, KernelAbstractions 0.9
implicit ordering, no intermediate waits, complete prelaunch topology
admission, centrally owned record validation/publication, and fail-closed
CPU/Metal-only qualification.

## Carried P2 ledger

| P2 class | Owner | Required disposition |
|---|---|---|
| Stable-layout/backend scope | LocalWorksets backend qualification | Array/MtlArray are the reviewed stable leaves. Any new array wrapper/backend requires an admitted stable-layout contract or full warm layout/device validation. CUDA/ROCm remain unclaimed. |
| Device-topology provenance | CorePotts compiled-program lifecycle | Retain immutable compiled topology ownership. Reopen freshness evidence before any mutable device-topology adoption. |
| K03 adapter concision | LW-5C decisive proposal pilot | Require measurable bespoke-code deletion and a smaller adapter surface before production promotion. Explicit five-leaf enumeration is not yet proof of downstream concision. |
| Mandatory dependency footprint | Later bounded consolidation/IC review | Preserve the ordered load/method/cache evidence and the absence of a comparable historical O0 measurement. Do not claim an unmeasured improvement. |
| Allocation gap | LW-5 downstream-value qualification | Track CPU +14,016 bytes/+108 allocations and Metal +12,528 bytes/+305 allocations per measured batch; do not call this allocation parity. |
| Internal complexity | LW-5 downstream-value test and later consolidation | LocalWorksets 9,346 and CorePotts 23,465 noncomment lines remain debt. The 1,613-line `checkerboard_program.jl` and 1,279-line `sequential_program.jl` exceed the responsibility-review boundary; the extracted LocalWorksets generic/support units are 932/112. No additional mechanism is justified without concrete adapter reduction and two unrelated consumers. |

These P2s are nonblocking for this bounded freeze. They are explicit inputs to
LW-5C/LW-5D and cannot be silently dropped at LW-R3.

## Final ruling

LW-5B4O-R passes with P0=0 and P1=0. The exact candidate is frozen and the
previously authorized bounded LW-5 sequence may resume at the LW-5C
pre-migration preservation hold. Direct execution remains selected. K02 and
B3 remain private/nonproduction witnesses. LW-R3 and G6 remain closed.
