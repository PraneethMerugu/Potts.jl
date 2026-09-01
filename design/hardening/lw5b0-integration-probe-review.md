# LW-5B0 integration-probe evidence and focused hold review

Status: **PASS**; B0 complete; implementation of the decisive proposal pilot
is open under its existing separate hold; production migration remains closed

Date: 2026-08-13

Authority:

- [LW-5A adoption-and-consolidation amendment](lw5a-adoption-consolidation-amendment.md)
- [LW-5A focused review](lw5a-adoption-consolidation-review.md)
- [post-LW-R1 roadmap](../../spec/localworksets-post-lwr1-roadmap.md)

This is the required focused hold on the disposable, non-promoted B0 claim-
workspace clear probe. It reviews the exact source that was compiled on CPU
and real Metal. It does not review the proposal-evaluation pilot, establish
adoption value, authorize a production path, retire a direct oracle, or admit
a new LocalWorksets mechanism.

## Exact candidate

The uncommitted candidate is based on repository `HEAD`
`bc5729f3db636c936ad2dfee46c5d1f1ced56059`. Because the candidate also
contains the already-reviewed LW-5A documents, the execution artifacts are
identified individually:

| Artifact | SHA-256 |
| --- | --- |
| `lib/CorePotts/src/execution/localworksets_adapter.jl` | `237213d054397554324e89d420d7eb5be5ff2a6ba68618a2109e3dd558fc44ea` |
| `lib/CorePotts/src/program/v1.jl` | `a5a9210deee295d3bfb2ae28455d535d44ef46303b2494e4d90315d9e6b96ea8` |
| `lib/CorePotts/test/lw5b0_claim_clear_support.jl` | `e1c344fe40dd3ed3cde5a7166e76712bf496f5df4392927498a926dfc945ecd8` |
| `lib/CorePotts/test/test_program_v1_localworksets_vertical.jl` | `03a431eadbcc4ba1514531d52bd967560a3c0fd46257436aef2c712e85da22b6` |
| `benchmark/backends/metal/lw5b0_probe.jl` | `c6502c0cd0c638aa6b4b8d63b35ab1d2053a26c54fbf2adc24a4df8eaa124298` |
| `benchmark/backends/metal/runtests.jl` | `5f06f21e1bb5777afab5d7acd5d4500708ad1404fd96376342abcc95318fa987` |

`git diff --check` passes. Static scans find no `Metal`, `CUDA`, `AMDGPU`,
vendor array, `@kernel`, `@atomic`, or synchronization reference in the
production adapter and no `LW5B0`/`lw5b0` identifier anywhere under
`lib/CorePotts/src`.

## What B0 implemented

The production change is one private CorePotts derivation/lifecycle boundary:

1. validate a canonical derivation record;
2. invoke the package-owned public LocalWorksets lifecycle
   `localwork -> topology -> plan -> prepare`;
3. retain the declaration, plan, preparation, derivation and trusted adapter
   as one inspectable phase;
4. submit through the existing trusted `run!` boundary; and
5. wait through the existing portable LocalWorksets event boundary.

The adapter is 156 source lines and contains no scientific operation,
scheduler, transaction, settlement, checkpoint, RNG, Hamiltonian, backend
branch, kernel, queue or synchronization implementation.

The entire B0 operation and its CorePotts workspace projection are instead
127 lines of explicitly disposable test support. The probe derives:

- item count and identity routing from the existing checkerboard claim-array
  capacity;
- topology epoch from the compiled checkerboard shape, periodicity, color
  layout and claim capacity;
- backend and destination storage from the existing claim arrays;
- the submission-bound read gate from the current CorePotts execution state;
- two named, partial, independent `UInt32` outputs sharing the logical claims
  route; and
- one prebound LocalWorksets lease with zero algorithmic-workspace bytes.

No production execution entrypoint constructs or runs the probe. The direct
claim-clear kernel remains the unchanged comparison oracle.

## Behavioral evidence

Both backends exercised the same test-support declaration and the same
production adapter. The Metal witness adapts existing CorePotts storage to
`MtlArray`; neither the adapter nor LocalWorksets source contains a Metal
lowering or vendor branch.

| Property | CPU | qualified real Metal |
| --- | ---: | ---: |
| LocalWorksets launches per submission | 1 | 1 |
| explicit evidence waits | 4 | 4 |
| algorithmic workspace | 0 bytes | 0 bytes |
| reported topology transfer | 16 bytes | 288 bytes |
| warm host allocation, submit plus wait | 6,960 bytes | 18,080 bytes |
| open-gate parity with direct clear | pass | pass |
| closed-gate no-emission preservation | pass | pass |
| following KA launch observes the clear without an intermediate wait | pass | pass |
| production promotion | false | false |

The warm allocations are host-side LocalWorksets event/submission/lifetime
bookkeeping. They are reported, not reclassified as algorithmic workspace.
The Metal compiler cache changed from 322 to 330 in the complete suite for
the first exact B0 specialization. These are diagnostics for the decisive
pilot, not claims of steady-state CorePotts performance parity.

The ordering witness submits B0 and then the existing claim-priority kernel on
the same KernelAbstractions backend before the only explicit wait. The later
kernel observes the completed clear. B0 adds no intermediate wait and invents
no queue, stream, command buffer or scheduler.

## Qualification

| Command/scope | Result |
| --- | --- |
| `julia --project=lib/CorePotts --startup-file=no -e 'using Test; import CorePotts; import LocalWorksets; include("lib/CorePotts/test/test_program_v1_support.jl"); include("lib/CorePotts/test/test_program_v1_localworksets_vertical.jl")'` | pass, 151/151 focused assertions including 37/37 B0 assertions |
| `julia --project=lib/CorePotts --startup-file=no -e 'using Pkg; Pkg.test(; julia_args=["--startup-file=no"])'` | pass, complete CorePotts CPU suite |
| `julia --project=benchmark/backends/metal --startup-file=no benchmark/backends/metal/runtests.jl` | pass, complete qualified real-Metal suite, exit 0 |
| source-boundary scans and `git diff --check` | pass |

The complete CPU suite includes exact checkpoint continuation and rejection of
incompatible LocalWorksets mechanism/RNG identity. B0 creates no production
mechanism identity and cannot affect checkpoint meaning. The complete Metal
suite retains the existing checkerboard, LocalWorksets, failure, lifecycle,
relationship, descriptor and checkpoint qualification in addition to B0.

## Consolidation ledger

| Concern | Before B0 | Exact B0 result | Pilot obligation |
| --- | --- | --- | --- |
| production custom clear | one direct kernel/wrapper | unchanged; oracle only for B0 | no disposition until an authorized production adoption |
| generic lifecycle authority | none for LW-5 adoption | one 156-line private CorePotts adapter | prove a second unrelated operation use or delete/consolidate it |
| B0-specific adapter code | none | 127 disposable test-support lines; zero production lines | do not copy it into the pilot |
| topology construction | implicit array capacity | one derived B0 test projection | pilot derives its topology through shared authority |
| storage binding | positional direct arguments | named static outputs plus one submission read | pilot must remove hand-flattened per-model bindings |
| workspace | existing claim arrays | existing arrays plus LocalWorksets lease; zero algorithmic bytes | distinguish scientific arrays from mechanism workspace |
| execution | one direct clear launch | one non-production LocalWorksets launch | proposal launch must be replaced one-for-one, not wrapped |
| visibility | direct KA ordering | KA implicit ordering; no intermediate wait | preserve the checkerboard queue contract |
| inspection | kernel call site | semantic phase -> declaration -> plan -> preparation | include proposal science/derivation identity without exposing authors |

The original implementation briefly placed the B0 operation/projection beside
the generic adapter. Before qualification it was split out into shared CPU/
Metal test support. This resolves LW-5A finding F3 for B0: disposable machinery
did not become production plumbing. The remaining production adapter is only
provisionally justified; the proposal pilot is its mandatory second-use and
deletion test.

## Hard-veto audit

| Veto | Result |
| --- | --- |
| architecture, lifecycle, naming or execution-family change | absent |
| custom kernel hidden behind a LocalWorksets wrapper | absent; B0 uses the accepted independent lowering |
| new LocalWorksets mechanism or external self-authorization | absent |
| CPM science, RNG, clock, Hamiltonian, settlement or checkpoint ownership moved | absent |
| vendor branch or backend-specific production source | absent |
| host callback, device allocation or hidden wait | absent |
| per-model/manual binding construction in production | absent |
| production entrypoint or default switched | absent |
| direct oracle retired | absent |

## Findings

- **P0: 0.**
- **P1: 0 for B0.** LW-5A F1 remains the proposal pilot's implementation
  hold; B0 neither resolves nor waives nested execution-view and fixed-size
  return derivation.
- **P2 observation: generic-adapter value.** The private adapter has only the
  B0 witness today. The decisive pilot must prove genuine shared use and a
  smaller overall downstream implementation; otherwise it is deleted or
  consolidated rather than preserved as speculative infrastructure.
- **P2 observation: cost diagnostics.** Per-output routing currently reports
  288 transferred topology bytes on the 36-item Metal fixture, and submit plus
  wait allocates 18,080 warm host bytes there. The proposal ledger must explain
  its exact costs and may not hide them behind the B0 result.

## Focused ballot

| Question | Ballot | Reason |
| --- | --- | --- |
| Are topology, storage, submission reads and backend derived rather than hand-authored per model? | **PASS** | They are projected once from the realized checkerboard plan, existing claim workspace and execution state. |
| Does B0 use only accepted LocalWorksets public semantics? | **PASS** | Two named partial independent outputs lower through the existing central compiler in one launch. |
| Is execution backend-portable in source and qualified on CPU/real Metal? | **PASS** | The common source has no vendor code; both exact suites pass. |
| Are KA implicit ordering and asynchronous submission preserved? | **PASS** | The cross-launch witness has no intermediate wait; only the explicit final wait synchronizes. |
| Is B0 disposable and non-promoted? | **PASS** | Operation/projection code is test-only and no production execution method accepts the probe. |
| Did B0 establish proposal derivability or adoption value? | **NO CLAIM** | It intentionally did not exercise the nested scientific execution view or return bridge. |
| May production migration or a later family begin? | **NO** | Those gates remain closed. |

## Ruling

LW-5B0 is complete and passes its focused hold. This opens only implementation
of the decisive proposal-evaluation pilot under the already-recorded F1/F2
holds and hard vetoes. The pilot must replace its custom execution unit rather
than wrap it, use the same derivation authority as a genuine second operation,
prove the bounded type-stable return bridge on CPU and real Metal, preserve
exact science/RNG/checkpoint/launch/wait behavior, and demonstrate material
net consolidation.

No production migration, default switch, direct-oracle retirement, later
operation family, MethodOfLines input-field work, LW-R3 result, or G6 send-off
is authorized by this ruling.
