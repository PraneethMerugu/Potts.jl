# LW-R1 LocalWorksets Exact-Candidate Review

Date: 2026-08-10

Status: passed; P0=0, P1=0, P2=0; no substantive dissent; owner subsequently selected standalone
extraction for LW-4

Authority:

- [LocalWorksets V1 implementation gate](../../spec/localworksets-v1-implementation-gate.md)
- [LW-1 implementation matrix](lw1-implementation-matrix.md)
- [LW-2 bounded conjunctive amendment](lw2-bounded-conjunctive-amendment.md)
- [LW-3 direct-parity evidence](lw3-localworksets-parity.md)

## Decision

The fresh exact-candidate committee unanimously clears LW-R1. This decision answers two separate
questions and does not conflate them:

1. the exact current bounded LW-1 implementation is correct and reviewable; and
2. no present architectural choice materially obstructs an eventual general LocalWorksets library.

The first answer does not claim that independent, combined, heterogeneous-output or general
multi-destination mechanisms already exist. The second does not make the internal module a
standalone package or qualify an untested backend.

LW-R1 also accepts the separately authorized two-key conjunctive claim vertical and LW-3 Q01--Q10
evidence. It permits the owner to choose and record an LW-4 disposition. It does not itself promote
the private `Experimental/ReplayQualified` candidate, add a public selector, re-export
LocalWorksets from PottsToolkit, delete or weaken the direct `Supported` oracle/default, authorize
another checkerboard-stage migration, extract a package, or begin LW-4 implementation.

## Exact review candidate

All three reviewers independently reproduced the sixteen implementation, integration, test and
runner SHA-256 values in the [LW-3 evidence record](lw3-localworksets-parity.md). The record itself
had SHA-256 `0ebf213b51419b2ae649e856618328a31f63a6909fca287cd32c76b31c495214`
when balloted. Other pre-closure document hashes reproduced by the backend reviewer were:

| Document | SHA-256 balloted |
|---|---|
| V1 normative contract | `bcf5004f45a985553f53d78faf2623e76b564596d0a82ad5f6d3d0ee7afbe86d` |
| implementation gate | `c74ff89146bc0d7a912a951b9a53a54fe24861add8d11d8a302fc63cee1c6ac4` |
| LW-1 matrix | `2ff92362e7117753897ddc49572915750923214371f3fdc238d38cb9ae79bd45` |
| LW-2 amendment | `853adbd86cb0818842cc5dec1e81625873632d81ca4f89760c3304eb3c14c53b` |

This review and the status/link edits made after the ballot are documentation-only reconciliation.
They do not change the sixteen balloted source/test/runner artifacts.

## Independent memos

| Role | Ballot | P0 | P1 | P2 | Substantive dissent |
|---|---|---:|---:|---:|---|
| Julia API and package-boundary reviewer | PASS | 0 | 0 | 0 | none |
| CorePotts semantics, determinism and preservation reviewer | PASS | 0 | 0 | 0 | none |
| KernelAbstractions, backend portability and performance reviewer | PASS | 0 | 0 | 0 | none |
| Nonvoting contradiction/red-team chair | CLEARED | 0 | 0 | 0 | none preserved because none was raised |

Each voting reviewer separately returned `PASS` for bounded LW-1 correctness and `NONE` for a
future LocalWorksets obstruction. No historical ballot was inherited.

## Fresh backend qualification

The backend reviewer ran the exact pinned command as the sole benchmark load:

```text
julia --project=benchmark/backends/metal benchmark/backends/metal/runtests.jl
```

It exited zero. The fresh 128x128 protocol used ten warm batches, fifty randomized interleaved
pairs, ten queued MCSs per arm, one settlement, and 10,000 fixed-seed bootstrap samples.

| Measurement | Fresh exact-hash result |
|---|---:|
| direct median | 0.114371021 s |
| candidate median | 0.115211542 s |
| candidate/direct median ratio | 1.0073490732 |
| paired bootstrap one-sided upper 95% | 1.0280494261, passing the 1.05 bound |
| direct median allocation | 17,678,960 bytes |
| candidate median allocation | 17,070,680 bytes |
| candidate allocation delta | -608,280 bytes |

The run recorded 60/60 settlements and synchronizations, 60 LocalWorksets waits, 600 submitted =
600 drained, a stable 32-byte workspace, zero topology transfer, compiler-cache stability
`324 -> 324`, exact final scientific parity and no unexpected failure or poison. Expected
prelaunch, scientific and provider failure witnesses retained their specified classifications.

Qualification remains limited to CPU and the reviewed Apple M1/Metal environment. CUDA, ROCm,
other devices, multi-device execution and cross-backend behavior remain unqualified. The earlier
32x32 CPU upper bound of approximately 1.0612 and one 64x64 Metal upper bound of 1.051075 remain
disclosed diagnostics; the passing 128x128 result is not a universal size-performance claim.

## Contradiction and red-team synthesis

The chair found no unresolved contradiction:

- the historical one-key ballot is exact-hash bounded and not inherited as current evidence;
- one-key winners cannot express the old-owner/new-owner conjunction, so LW-2 implements the exact
  two-key conjunction instead of approximating it;
- only four claim-arbitration launches dispatch through LocalWorksets;
- Hamiltonians, proposal evaluation, acceptance, RNG, banks, commit, lifecycle, publication,
  settlement, failures and checkpoints remain CorePotts-owned;
- canonical source-order Hamiltonian folding remains outside LocalWorksets arbitration;
- scientific equivalence does not erase the direct/candidate capability and checkpoint identities;
- KernelAbstractions implicit ordering supplies visibility without intermediate host waits,
  fabricated transferable events, native queues or a LocalWorksets scheduler;
- hardware-neutral source does not imply unreviewed runtime qualification;
- the allocation comparison includes candidate leases/events without granting the direct path a
  synthetic receipt allowance; and
- no public selector, promotion, new dependency, output-family claim or package extraction occurred.

## Separate rulings

| Question | Ruling | Boundary |
|---|---|---|
| Is the exact current one-key LW-1 implementation correct and honestly bounded? | PASS | one port, one destination per item, fixed qualified integer arbitration profile |
| Does it obstruct an eventual general LocalWorksets library? | NONE | extraction still needs ordinary factoring, a replacement trust/admission root and standalone qualification |
| Is the bounded LW-2 conjunction faithful enough for the selected checkerboard claim block? | PASS | exact two-key claim arbitration and four launches only |
| Do LW-3 Q01--Q10 pass? | PASS | qualified CPU and real Metal evidence only |
| Is eventual extraction feasible? | PASS | not copy-as-is and not current production status |
| Does LW-R1 clear? | YES | owner may now choose an LW-4 disposition |

The bounded LW-2 checkerboard claim work is no longer blocked. Public activation or promotion,
direct-oracle removal, additional stage migration, extraction and automatic LW-4 implementation
remain blocked until the owner records the applicable LW-4 decision.

## Subsequent owner disposition

After this review, the owner selected standalone extraction followed by bounded general mechanism
completion, an implementation-backed Julian/JuliaGPU API reconciliation, and later compiled Potts
operation adoption. The decision and its new review holds are recorded in the
[post-LW-R1 extraction and adoption roadmap](../../spec/localworksets-post-lwr1-roadmap.md). This
subsequent direction does not alter the exact candidate, evidence or committee ballot above.
